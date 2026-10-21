import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/domain/money.dart';
import '../../../core/infrastructure/database/app_database.dart';
import '../../../core/infrastructure/database/schema.dart';
import '../../inventory/data/sqlite_inventory_store.dart';
import '../../inventory/domain/inventory_store.dart';
import '../../quick_sales/data/sqlite_quick_sales_store.dart';
import '../../supplier_payments/data/sqlite_supplier_payments_store.dart';
import '../../supplier_payments/domain/supplier_payments_store.dart';
import '../../workspace/domain/business_profile.dart';
import '../domain/stock_intake_store.dart';
import 'sqlite_cash_opening_recorder.dart';

/// A durable parent composes catalog, FIFO receipt and full supplier payment.
/// Preparing reserves identities and snapshots without changing business data.
class SqliteStockIntakeStore implements StockIntakeStore {
  SqliteStockIntakeStore(this._database, {this.synthetic = false});
  final AppDatabase _database;
  final bool synthetic;
  static const _operator = 'system:local-operator';
  SqliteInventoryStore get _inventory =>
      SqliteInventoryStore(_database, synthetic: synthetic);
  SqliteSupplierPaymentsStore get _payments =>
      SqliteSupplierPaymentsStore(_database, synthetic: synthetic);

  @override
  Future<void> ensureDefaults() async {
    await SqliteQuickSalesStore(
      _database,
      synthetic: synthetic,
    ).ensureDefaults();
    await _database.database.transaction((txn) async {
      await _profile(txn);
      for (final name in ['Comestible', 'Artículo', 'Evento']) {
        final rows = await txn.query('categories', where: 'is_active=1');
        if (!rows.any(
          (r) =>
              (r['name'] as String).trim().toLowerCase() == name.toLowerCase(),
        )) {
          await txn.insert('categories', {
            'id': InventoryIds.next(),
            'name': name,
            'is_active': 1,
          });
        }
      }
    }, exclusive: true);
  }

  @override
  Future<StockIntakeSnapshot> load() async {
    final inventory = await _inventory.load();
    return _database.database.transaction((txn) async {
      await _profile(txn);
      final options = await txn.rawQuery('''
SELECT o.*, c.is_active account_active,c.is_available,c.kind,c.ledger_account_id,
 l.is_active ledger_active,l.class ledger_class,l.role ledger_role,m.is_active method_active
FROM quick_payment_options o JOIN cash_accounts c ON c.id=o.cash_account_id
JOIN ledger_accounts l ON l.id=c.ledger_account_id
JOIN payment_methods m ON m.id=o.payment_method_id
ORDER BY CASE o.label WHEN 'Efectivo' THEN 0 WHEN 'Nequi' THEN 1 ELSE 2 END,o.label,o.id
''');
      final balances = await _balances(txn);
      final paymentOptions = <IntakePaymentOption>[];
      for (final row in options) {
        final opening = await txn.query(
          'cash_openings',
          where: 'cash_account_id=?',
          whereArgs: [row['cash_account_id']],
        );
        final importedOpening = await txn.rawQuery(
          '''
SELECT document_id FROM treasury_openings
WHERE cash_account_id=? OR nequi_account_id=? OR reserve_account_id=? LIMIT 1
''',
          [
            row['cash_account_id'],
            row['cash_account_id'],
            row['cash_account_id'],
          ],
        );
        final openingRecorded =
            opening.isNotEmpty || importedOpening.isNotEmpty;
        final movements = await txn.rawQuery(
          '''
SELECT l.id FROM journal_lines l
JOIN journal_entries e ON e.id=l.entry_id AND e.status='posted'
JOIN business_documents d ON d.id=e.document_id AND d.status='posted'
WHERE l.account_id=? LIMIT 1
''',
          [row['ledger_account_id']],
        );
        final active =
            row['is_active'] == 1 &&
            row['account_active'] == 1 &&
            row['is_available'] == 1 &&
            row['ledger_active'] == 1 &&
            row['method_active'] == 1 &&
            row['ledger_class'] == 'asset' &&
            row['ledger_role'] == 'cash';
        paymentOptions.add(
          IntakePaymentOption(
            id: row['id'] as String,
            label: row['label'] as String,
            cashAccountId: row['cash_account_id'] as String,
            paymentMethodId: row['payment_method_id'] as String,
            balanceMinor: _signed(
              balances[row['ledger_account_id']] ?? BigInt.zero,
              'Saldo',
            ),
            openingRecorded: openingRecorded,
            canRecordOpening: active && !openingRecorded && movements.isEmpty,
            isActive: active,
          ),
        );
      }
      final pending = await txn.query(
        'paid_purchase_requests',
        where: "status IN ('prepared','rejected')",
        orderBy: 'prepared_at_utc,command_id',
      );
      final entries = await txn.rawQuery('''
SELECT e.*,r.occurred_at_utc FROM paid_purchase_entries e
JOIN paid_purchase_requests r ON r.command_id=e.request_id AND r.status='confirmed'
ORDER BY r.occurred_at_utc DESC,e.request_id
''');
      return StockIntakeSnapshot(
        categories: inventory.categories
            .where((c) => _allowedCategory(c.name))
            .toList(),
        suppliers: inventory.suppliers,
        products: inventory.products.where((p) => !p.isEvent).toList(),
        stock: inventory.stock,
        productDefaults: await _productDefaults(txn),
        paymentOptions: paymentOptions,
        pendingIntakes: pending.map(_prepared).toList(),
        entries: entries
            .map(
              (r) => StockIntakeEntry(
                commandId: r['request_id'] as String,
                productId: r['product_id'] as String,
                productName: r['product_name_snapshot'] as String,
                sku: r['sku_snapshot'] as String?,
                categoryName: r['category_name_snapshot'] as String,
                supplierName: r['supplier_name_snapshot'] as String,
                quantity: r['quantity'] as int,
                unitPurchasePriceMinor: r['unit_purchase_price_minor'] as int,
                listPriceMinor: r['list_price_minor'] as int,
                totalCostMinor: r['total_cost_minor'] as int,
                paymentLabel: r['payment_option_label_snapshot'] as String,
                occurredAtUtc: DateTime.parse(
                  r['occurred_at_utc'] as String,
                ).toUtc(),
              ),
            )
            .toList(),
      );
    });
  }

  Future<Map<String, ProductIntakeDefaults>> _productDefaults(
    Transaction txn,
  ) async {
    final history = await txn.rawQuery('''
SELECT history.*, supplier.id active_supplier_id, supplier.name supplier_name
FROM (
  SELECT line.product_id, purchase.supplier_id,
    CASE WHEN line.acquisition_total_minor % line.quantity = 0
      THEN line.acquisition_total_minor / line.quantity END unit_cost_minor,
    purchase.received_at_utc occurred_at_utc, 1 source_priority,
    purchase.document_id source_id, line.id item_id
  FROM purchase_lines line
  JOIN purchases purchase ON purchase.document_id = line.purchase_id
  JOIN business_documents document ON document.id = purchase.document_id AND document.status = 'posted'
  JOIN journal_entries entry ON entry.document_id = document.id AND entry.status = 'posted'
  UNION ALL
  SELECT item.product_id, item.supplier_id, item.unit_cost_minor,
    opening.occurred_at_utc, 0 source_priority, opening.document_id, item.id
  FROM inventory_opening_items item
  JOIN inventory_openings opening ON opening.document_id = item.opening_id
  JOIN business_documents document ON document.id = opening.document_id AND document.status = 'posted'
  JOIN journal_entries entry ON entry.document_id = document.id AND entry.status = 'posted'
) history
LEFT JOIN counterparties supplier ON supplier.id = history.supplier_id
  AND supplier.is_supplier = 1 AND supplier.is_active = 1
''');
    // Parse instants instead of sorting UTC strings with optional fractions.
    final ordered = history.toList()
      ..sort((a, b) {
        final time = DateTime.parse(
          b['occurred_at_utc'] as String,
        ).compareTo(DateTime.parse(a['occurred_at_utc'] as String));
        if (time != 0) return time;
        final source = (b['source_priority'] as int).compareTo(
          a['source_priority'] as int,
        );
        if (source != 0) return source;
        final document = (b['source_id'] as String).compareTo(
          a['source_id'] as String,
        );
        if (document != 0) return document;
        return (b['item_id'] as String).compareTo(a['item_id'] as String);
      });
    final defaults = <String, ProductIntakeDefaults>{};
    for (final row in ordered) {
      defaults.putIfAbsent(
        row['product_id'] as String,
        () => ProductIntakeDefaults(
          supplierId: row['active_supplier_id'] as String?,
          supplierName: row['supplier_name'] as String?,
          unitPurchasePriceMinor: row['unit_cost_minor'] as int?,
        ),
      );
    }
    return defaults;
  }

  @override
  Future<PreparedStockIntake> prepare(StockIntakeCommand command) async {
    final input = _input(command);
    return _database.database.transaction((txn) async {
      final profile = await _profile(txn);
      final prior = await txn.query(
        'paid_purchase_requests',
        where: 'command_id=?',
        whereArgs: [command.commandId],
      );
      if (prior.isNotEmpty) {
        final payload =
            jsonDecode(prior.single['canonical_payload'] as String)
                as Map<String, dynamic>;
        if (jsonEncode(payload['input']) != jsonEncode(input)) {
          throw const StockIntakeValidationException(
            'El identificador ya corresponde a otro ingreso.',
          );
        }
        return _prepared(prior.single);
      }
      await _unused(txn, command.commandId);
      await _checkProduct(
        txn,
        command.productId,
        input['expectedProduct'] as Map<String, Object?>?,
      );
      final category = await _category(txn, command.categoryId);
      await _checkSku(txn, input['sku'] as String?, command.productId);
      final supplierName = input['supplierName'] as String;
      final supplier = command.supplierId == null
          ? (await txn.query(
                  'counterparties',
                  where: 'is_supplier=1 AND is_active=1',
                  orderBy: 'id',
                ))
                .where(
                  (r) =>
                      (r['name'] as String).trim().toLowerCase() ==
                      supplierName.toLowerCase(),
                )
                .toList()
          : await txn.query(
              'counterparties',
              where: 'id=? AND is_supplier=1 AND is_active=1',
              whereArgs: [command.supplierId],
            );
      if (command.supplierId != null &&
          (supplier.length != 1 || supplier.single['name'] != supplierName)) {
        throw const StockIntakeValidationException(
          'El proveedor cambió. Selecciónalo nuevamente.',
        );
      }
      final supplierId = supplier.isEmpty
          ? InventoryIds.next()
          : supplier.first['id'] as String;
      final option = await _option(txn, command.paymentOptionId);
      final total = _nonnegative(
        BigInt.from(command.unitPurchasePriceMinor) *
            BigInt.from(command.quantity),
        'Costo total',
      );
      await _funds(txn, option, total, command.occurredAtUtc);
      final now = DateTime.now().toUtc();
      final row = <String, Object?>{
        'command_id': command.commandId,
        'canonical_payload': jsonEncode({
          'version': 1,
          'profileId': profile.profileId,
          'currency': profile.currencyCode,
          'scale': profile.moneyScale,
          'input': input,
          'productId': command.productId,
          'expectedProduct': input['expectedProduct'],
          'productName': input['productName'],
          'sku': input['sku'],
          'categoryId': command.categoryId,
          'categoryName': category['name'],
          'supplierId': supplierId,
          'supplierName': supplier.isEmpty
              ? supplierName
              : supplier.first['name'],
          'existingSupplier': supplier.isNotEmpty,
          'unitPurchasePriceMinor': command.unitPurchasePriceMinor,
          'listPriceMinor': command.listPriceMinor,
          'quantity': command.quantity,
          'totalCostMinor': total,
          'occurredAtUtc': command.occurredAtUtc.toIso8601String(),
          ...option,
        }),
        'occurred_at_utc': command.occurredAtUtc.toIso8601String(),
        'prepared_at_utc': now.toIso8601String(),
        'status': 'prepared',
        'purchase_command_id': InventoryIds.next(),
        'payment_command_id': InventoryIds.next(),
      };
      await txn.insert('paid_purchase_requests', row);
      return _prepared(row);
    }, exclusive: true);
  }

  @override
  Future<StockIntakeResult> confirmPrepared(String commandId) async {
    _id(commandId);
    try {
      return await _database.database.transaction(
        (txn) => _confirm(txn, commandId),
        exclusive: true,
      );
    } on InventoryValidationException catch (e) {
      await _reject(commandId, e.message);
      throw StockIntakeValidationException(e.message);
    } on SupplierPaymentsValidationException catch (e) {
      await _reject(commandId, e.message);
      throw StockIntakeValidationException(e.message);
    } on StockIntakeValidationException catch (e) {
      await _reject(commandId, e.message);
      rethrow;
    }
  }

  Future<StockIntakeResult> _confirm(Transaction txn, String id) async {
    final rows = await txn.query(
      'paid_purchase_requests',
      where: 'command_id=?',
      whereArgs: [id],
    );
    if (rows.length != 1) {
      throw const StockIntakeValidationException(
        'No existe el ingreso pendiente.',
      );
    }
    final row = rows.single;
    final canonical = row['canonical_payload'] as String;
    final logged = await txn.query(
      'command_log',
      where: 'id=?',
      whereArgs: [id],
    );
    if (logged.isNotEmpty) return _prior(logged.single, canonical);
    if (row['status'] != 'prepared') {
      throw const StockIntakeValidationException(
        'El ingreso fue rechazado o descartado. Corrige y prepara uno nuevo.',
      );
    }
    final payload = jsonDecode(canonical) as Map<String, dynamic>;
    final prepared = _prepared(row);
    final command = prepared.command;
    final profile = await _profile(txn);
    if (payload['version'] != 1 ||
        payload['profileId'] != profile.profileId ||
        payload['currency'] != profile.currencyCode ||
        payload['scale'] != profile.moneyScale ||
        payload['occurredAtUtc'] != row['occurred_at_utc'] ||
        jsonEncode(payload['input']) != jsonEncode(_input(command))) {
      throw const StockIntakeValidationException(
        'El ingreso no coincide con la solicitud guardada.',
      );
    }
    final expected = (payload['expectedProduct'] as Map?)
        ?.cast<String, Object?>();
    await _checkProduct(txn, command.productId, expected);
    await _checkSku(txn, command.sku, command.productId);
    final category = await _category(txn, command.categoryId);
    if (category['name'] != payload['categoryName']) {
      throw const StockIntakeValidationException(
        'La categoría cambió. Revisa el ingreso.',
      );
    }
    final currentOption = await _option(txn, command.paymentOptionId);
    for (final key in [
      'paymentOptionId',
      'cashAccountId',
      'paymentMethodId',
      'cashAccountKind',
      'paymentMethodCode',
    ]) {
      if (currentOption[key] != payload[key]) {
        throw const StockIntakeValidationException(
          'La identidad de la forma de pago cambió.',
        );
      }
    }
    final total = _nonnegative(
      BigInt.from(command.quantity) *
          BigInt.from(command.unitPurchasePriceMinor),
      'Costo total',
    );
    if (total != payload['totalCostMinor']) {
      throw const StockIntakeValidationException(
        'El costo del ingreso no coincide.',
      );
    }
    await _funds(txn, currentOption, total, command.occurredAtUtc);
    final suppliers = await txn.query(
      'counterparties',
      where: 'id=?',
      whereArgs: [payload['supplierId']],
    );
    if (payload['existingSupplier'] == true) {
      if (suppliers.length != 1 ||
          suppliers.single['name'] != payload['supplierName'] ||
          suppliers.single['is_supplier'] != 1 ||
          suppliers.single['is_active'] != 1) {
        throw const StockIntakeValidationException(
          'El proveedor cambió. Revisa el ingreso.',
        );
      }
    } else {
      final matching =
          (await txn.query(
            'counterparties',
            where: 'is_supplier=1 AND is_active=1',
          )).where(
            (r) =>
                (r['name'] as String).trim().toLowerCase() ==
                (payload['supplierName'] as String).toLowerCase(),
          );
      if (suppliers.isNotEmpty || matching.isNotEmpty) {
        throw const StockIntakeValidationException(
          'El proveedor fue creado mientras se preparaba el ingreso. Selecciónalo nuevamente.',
        );
      }
    }
    await txn.update(
      'paid_purchase_requests',
      {'status': 'executing'},
      where: 'command_id=?',
      whereArgs: [id],
    );
    if (payload['existingSupplier'] != true) {
      await txn.insert('counterparties', {
        'id': payload['supplierId'],
        'name': payload['supplierName'],
        'is_supplier': 1,
        'is_customer': 0,
        'is_active': 1,
      });
    }
    final product = <String, Object?>{
      'name': command.productName,
      'sku': command.sku,
      'category_id': command.categoryId,
      'kind': 'product',
      'unit_code': 'unit',
      'quantity_scale': 0,
      'list_price_minor': command.listPriceMinor,
      'is_active': 1,
    };
    if (expected == null) {
      await txn.insert('catalog_items', {'id': command.productId, ...product});
    } else {
      await txn.update(
        'catalog_items',
        product,
        where: 'id=?',
        whereArgs: [command.productId],
      );
    }
    final purchase = await _inventory.receivePurchaseInTransaction(
      txn,
      ReceiptCommand(
        commandId: row['purchase_command_id'] as String,
        supplierId: payload['supplierId'] as String,
        occurredAtUtc: command.occurredAtUtc,
        dueDate: _businessDate(command.occurredAtUtc),
        lines: [
          ReceiptLineInput(
            productId: command.productId,
            quantity: command.quantity,
            totalCostMinor: total,
          ),
        ],
      ),
    );
    final obligation = (await txn.query(
      'obligations',
      where: 'origin_document_id=?',
      whereArgs: [purchase.documentId],
    )).single;
    await _payments.preparePaymentInTransaction(
      txn,
      SupplierPaymentCommand(
        commandId: row['payment_command_id'] as String,
        payableId: obligation['id'] as String,
        occurredAtUtc: command.occurredAtUtc,
        parts: [
          SupplierPaymentPartInput(
            cashAccountId: payload['cashAccountId'] as String,
            paymentMethodId: payload['paymentMethodId'] as String,
            amountMinor: total,
          ),
        ],
      ),
      snapshots: [
        SupplierPaymentPart(
          cashAccountId: payload['cashAccountId'] as String,
          paymentMethodId: payload['paymentMethodId'] as String,
          cashAccountName: payload['cashAccountName'] as String,
          cashAccountKind: payload['cashAccountKind'] as String,
          paymentMethodCode: payload['paymentMethodCode'] as String,
          paymentMethodName: payload['paymentMethodName'] as String,
          amountMinor: total,
        ),
      ],
    );
    final payment = await _payments.confirmInTransaction(
      txn,
      row['payment_command_id'] as String,
    );
    final result = StockIntakeResult(
      commandId: id,
      productId: command.productId,
      purchaseDocumentId: purchase.documentId,
      paymentDocumentId: payment.documentId,
      totalCostMinor: total,
    );
    await txn.insert('command_log', {
      'id': id,
      'command_type': 'paid_purchase',
      'payload_hash': DatabaseSchema.checksum(canonical),
      'actor_id': _operator,
      'response_json': jsonEncode({
        'canonicalPayload': canonical,
        'result': {
          'commandId': id,
          'productId': command.productId,
          'purchaseDocumentId': purchase.documentId,
          'paymentDocumentId': payment.documentId,
          'totalCostMinor': total,
        },
      }),
      'response_version': 1,
      'committed_at_utc': DateTime.now().toUtc().toIso8601String(),
      'authorization_policy_version': 'development-single-user-v1',
    });
    await txn.insert('paid_purchase_entries', {
      'request_id': id,
      'purchase_document_id': purchase.documentId,
      'payment_document_id': payment.documentId,
      'product_id': command.productId,
      'product_name_snapshot': command.productName,
      'sku_snapshot': command.sku,
      'category_id': command.categoryId,
      'category_name_snapshot': payload['categoryName'],
      'supplier_id': payload['supplierId'],
      'supplier_name_snapshot': payload['supplierName'],
      'quantity': command.quantity,
      'unit_purchase_price_minor': command.unitPurchasePriceMinor,
      'list_price_minor': command.listPriceMinor,
      'total_cost_minor': total,
      'payment_option_id': command.paymentOptionId,
      'payment_option_label_snapshot': payload['paymentOptionLabel'],
      'cash_account_id': payload['cashAccountId'],
      'payment_method_id': payload['paymentMethodId'],
      'cash_account_name_snapshot': payload['cashAccountName'],
      'cash_account_kind_snapshot': payload['cashAccountKind'],
      'payment_method_code_snapshot': payload['paymentMethodCode'],
      'payment_method_name_snapshot': payload['paymentMethodName'],
    });
    await txn.update(
      'paid_purchase_requests',
      {'status': 'confirmed'},
      where: 'command_id=?',
      whereArgs: [id],
    );
    return result;
  }

  @override
  Future<void> discardRejected(String commandId) async {
    _id(commandId);
    await _database.database.transaction((txn) async {
      final rows = await txn.query(
        'paid_purchase_requests',
        where: 'command_id=?',
        whereArgs: [commandId],
      );
      if (rows.length != 1) {
        throw const StockIntakeValidationException('El ingreso no existe.');
      }
      if (rows.single['status'] == 'cancelled') return;
      if (rows.single['status'] != 'rejected' ||
          (await txn.query(
            'command_log',
            where: 'id=?',
            whereArgs: [commandId],
          )).isNotEmpty) {
        throw const StockIntakeValidationException(
          'Resuelve primero el ingreso pendiente. Un ingreso registrado no se descarta.',
        );
      }
      await txn.update(
        'paid_purchase_requests',
        {'status': 'cancelled'},
        where: 'command_id=?',
        whereArgs: [commandId],
      );
    }, exclusive: true);
  }

  Future<void> _reject(String id, String message) =>
      _database.database.transaction((txn) async {
        if ((await txn.query(
          'command_log',
          where: 'id=?',
          whereArgs: [id],
        )).isEmpty) {
          await txn.update(
            'paid_purchase_requests',
            {'status': 'rejected', 'rejection_reason': message},
            where: "command_id=? AND status='prepared'",
            whereArgs: [id],
          );
        }
      }, exclusive: true);

  @override
  Future<void> recordOpeningBalance(CashOpeningCommand command) =>
      SqliteCashOpeningRecorder(
        _database,
        synthetic: synthetic,
      ).record(command);

  static Future<Map<String, Object?>> _category(
    DatabaseExecutor txn,
    String id,
  ) async {
    final rows = await txn.query(
      'categories',
      where: 'id=? AND is_active=1',
      whereArgs: [id],
    );
    if (rows.length != 1 || !_allowedCategory(rows.single['name'] as String)) {
      throw const StockIntakeValidationException(
        'Selecciona Comestible, Artículo o Evento.',
      );
    }
    return rows.single;
  }

  static bool _allowedCategory(String name) => const [
    'comestible',
    'artículo',
    'evento',
  ].contains(name.trim().toLowerCase());

  static Future<void> _checkProduct(
    DatabaseExecutor txn,
    String id,
    Map<String, Object?>? expected,
  ) async {
    final rows = await txn.query(
      'catalog_items',
      where: 'id=?',
      whereArgs: [id],
    );
    if (expected == null) {
      if (rows.isNotEmpty) {
        throw const StockIntakeValidationException(
          'El producto ya existe. Selecciónalo para reponerlo.',
        );
      }
      return;
    }
    if (rows.length != 1 ||
        rows.single['is_active'] != 1 ||
        rows.single['kind'] != 'product' ||
        rows.single['unit_code'] != 'unit' ||
        rows.single['quantity_scale'] != 0 ||
        jsonEncode(_productRow(rows.single)) != jsonEncode(expected)) {
      throw const StockIntakeValidationException(
        'El producto cambió. Actualiza y vuelve a seleccionarlo antes de reponer.',
      );
    }
  }

  static Future<void> _checkSku(
    DatabaseExecutor txn,
    String? sku,
    String productId,
  ) async {
    if (sku != null &&
        (await txn.rawQuery(
          'SELECT id FROM catalog_items WHERE sku=? COLLATE NOCASE AND id<>?',
          [sku, productId],
        )).isNotEmpty) {
      throw const StockIntakeValidationException(
        'El SKU ya pertenece a otro producto.',
      );
    }
  }

  static Map<String, Object?> _product(CatalogProduct p) => {
    'id': p.id,
    'name': p.name,
    'sku': p.sku,
    'categoryId': p.categoryId,
    'listPriceMinor': p.listPriceMinor,
    'isActive': p.isActive,
  };
  static Map<String, Object?> _productRow(Map<String, Object?> p) => {
    'id': p['id'],
    'name': p['name'],
    'sku': p['sku'],
    'categoryId': p['category_id'],
    'listPriceMinor': p['list_price_minor'],
    'isActive': p['is_active'] == 1,
  };
  static Map<String, Object?> _input(StockIntakeCommand c) {
    for (final id in [
      c.commandId,
      c.productId,
      c.categoryId,
      c.paymentOptionId,
      if (c.supplierId != null) c.supplierId!,
    ]) {
      _id(id);
    }
    _businessDate(c.occurredAtUtc);
    if (c.quantity <= 0 ||
        c.unitPurchasePriceMinor <= 0 ||
        c.listPriceMinor < 0) {
      throw const StockIntakeValidationException(
        'Cantidad y precio de compra deben ser positivos; el PVP no puede ser negativo.',
      );
    }
    _nonnegative(BigInt.from(c.quantity), 'Cantidad');
    _nonnegative(BigInt.from(c.unitPurchasePriceMinor), 'Precio de compra');
    _nonnegative(BigInt.from(c.listPriceMinor), 'PVP');
    _nonnegative(
      BigInt.from(c.quantity) * BigInt.from(c.unitPurchasePriceMinor),
      'Costo total',
    );
    _nonnegative(
      BigInt.from(c.quantity) * BigInt.from(c.listPriceMinor),
      'Valor al público total',
    );
    if (c.expectedProduct != null &&
        (c.expectedProduct!.id != c.productId ||
            !c.expectedProduct!.isActive)) {
      throw const StockIntakeValidationException(
        'Selecciona un producto activo para reponer.',
      );
    }
    return {
      'commandId': c.commandId,
      'productId': c.productId,
      'expectedProduct': c.expectedProduct == null
          ? null
          : _product(c.expectedProduct!),
      'productName': _text(c.productName, 'Nombre de producto', 160),
      'sku': c.sku == null || c.sku!.trim().isEmpty
          ? null
          : _text(c.sku!, 'SKU', 80),
      'categoryId': c.categoryId,
      'supplierId': c.supplierId,
      'supplierName': _text(c.supplierName, 'Proveedor', 160),
      'unitPurchasePriceMinor': c.unitPurchasePriceMinor,
      'listPriceMinor': c.listPriceMinor,
      'quantity': c.quantity,
      'paymentOptionId': c.paymentOptionId,
      'occurredAtUtc': c.occurredAtUtc.toIso8601String(),
    };
  }

  static PreparedStockIntake _prepared(Map<String, Object?> row) {
    final payload =
        jsonDecode(row['canonical_payload'] as String) as Map<String, dynamic>;
    final p = payload['input'] as Map<String, dynamic>;
    final e = p['expectedProduct'] as Map<String, dynamic>?;
    return PreparedStockIntake(
      command: StockIntakeCommand(
        commandId: row['command_id'] as String,
        productId: p['productId'] as String,
        expectedProduct: e == null
            ? null
            : CatalogProduct(
                id: e['id'] as String,
                name: e['name'] as String,
                sku: e['sku'] as String?,
                categoryId: e['categoryId'] as String?,
                listPriceMinor: e['listPriceMinor'] as int,
                isActive: e['isActive'] as bool,
              ),
        productName: p['productName'] as String,
        sku: p['sku'] as String?,
        categoryId: p['categoryId'] as String,
        supplierId: p['supplierId'] as String?,
        supplierName: p['supplierName'] as String,
        unitPurchasePriceMinor: p['unitPurchasePriceMinor'] as int,
        listPriceMinor: p['listPriceMinor'] as int,
        quantity: p['quantity'] as int,
        paymentOptionId: p['paymentOptionId'] as String,
        occurredAtUtc: DateTime.parse(row['occurred_at_utc'] as String).toUtc(),
      ),
      status: row['status'] as String,
      preparedAtUtc: DateTime.parse(row['prepared_at_utc'] as String).toUtc(),
      rejectionReason: row['rejection_reason'] as String?,
    );
  }

  static StockIntakeResult _prior(Map<String, Object?> row, String canonical) {
    if (row['command_type'] != 'paid_purchase' ||
        row['response_version'] != 1 ||
        row['payload_hash'] != DatabaseSchema.checksum(canonical)) {
      throw const StockIntakeValidationException(
        'El identificador ya corresponde a otro comando.',
      );
    }
    final stored =
        jsonDecode(row['response_json'] as String) as Map<String, dynamic>;
    if (stored['canonicalPayload'] != canonical) {
      throw const StockIntakeValidationException(
        'El identificador ya corresponde a otro comando.',
      );
    }
    final r = stored['result'] as Map<String, dynamic>;
    return StockIntakeResult(
      commandId: r['commandId'] as String,
      productId: r['productId'] as String,
      purchaseDocumentId: r['purchaseDocumentId'] as String,
      paymentDocumentId: r['paymentDocumentId'] as String,
      totalCostMinor: r['totalCostMinor'] as int,
    );
  }

  static Future<Map<String, Object?>> _option(
    DatabaseExecutor txn,
    String id,
  ) async {
    final rows = await txn.rawQuery(
      '''SELECT o.*,c.name account_name,c.kind account_kind,c.ledger_account_id,m.code method_code,m.name method_name FROM quick_payment_options o JOIN cash_accounts c ON c.id=o.cash_account_id JOIN ledger_accounts l ON l.id=c.ledger_account_id JOIN payment_methods m ON m.id=o.payment_method_id WHERE o.id=? AND o.is_active=1 AND c.is_active=1 AND c.is_available=1 AND l.is_active=1 AND l.class='asset' AND l.role='cash' AND m.is_active=1''',
      [id],
    );
    if (rows.length != 1) {
      throw const StockIntakeValidationException(
        'La forma de pago no está disponible.',
      );
    }
    final r = rows.single;
    return {
      'paymentOptionId': r['id'],
      'paymentOptionLabel': r['label'],
      'cashAccountId': r['cash_account_id'],
      'cashAccountName': r['account_name'],
      'cashAccountKind': r['account_kind'],
      'paymentMethodId': r['payment_method_id'],
      'paymentMethodCode': r['method_code'],
      'paymentMethodName': r['method_name'],
    };
  }

  static Future<Map<String, BigInt>> _balances(DatabaseExecutor txn) async {
    final rows = await txn.rawQuery(
      "SELECT l.account_id,l.debit_minor,l.credit_minor FROM journal_lines l JOIN ledger_accounts a ON a.id=l.account_id AND a.role='cash' JOIN journal_entries e ON e.id=l.entry_id AND e.status='posted' JOIN business_documents d ON d.id=e.document_id AND d.status='posted'",
    );
    final result = <String, BigInt>{};
    for (final r in rows) {
      final id = r['account_id'] as String;
      result[id] =
          (result[id] ?? BigInt.zero) +
          BigInt.from(r['debit_minor'] as int) -
          BigInt.from(r['credit_minor'] as int);
    }
    return result;
  }

  static Future<void> _funds(
    DatabaseExecutor txn,
    Map<String, Object?> option,
    int total,
    DateTime occurredAt,
  ) async {
    final cash = (await txn.query(
      'cash_accounts',
      where: 'id=?',
      whereArgs: [option['cashAccountId']],
    )).single;
    final ledger = cash['ledger_account_id'];
    final balances = await _balances(txn);
    if ((balances[ledger] ?? BigInt.zero) < BigInt.from(total)) {
      throw const StockIntakeValidationException(
        'Saldo registrado insuficiente. Declara el saldo inicial real de esta cuenta si aún no tiene movimientos.',
      );
    }
    final movements = await txn.rawQuery(
      "SELECT d.occurred_at_utc FROM journal_lines l JOIN journal_entries e ON e.id=l.entry_id AND e.status='posted' JOIN business_documents d ON d.id=e.document_id AND d.status='posted' WHERE l.account_id=?",
      [ledger],
    );
    if (movements.any(
      (r) => DateTime.parse(r['occurred_at_utc'] as String).isAfter(occurredAt),
    )) {
      throw const StockIntakeValidationException(
        'El ingreso no puede ser anterior al último movimiento de la cuenta de pago.',
      );
    }
  }

  static Future<void> _unused(DatabaseExecutor txn, String id) async {
    for (final table in [
      'command_log',
      'sale_confirmations',
      'collection_requests',
      'supplier_payment_requests',
    ]) {
      if ((await txn.query(
        table,
        where: '${table == 'command_log' ? 'id' : 'command_id'}=?',
        whereArgs: [id],
      )).isNotEmpty) {
        throw const StockIntakeValidationException(
          'El identificador ya corresponde a otra operación.',
        );
      }
    }
    if ((await txn.rawQuery(
          'SELECT command_id FROM quick_sale_requests WHERE command_id=? OR sale_command_id=? OR collection_command_id=?',
          [id, id, id],
        )).isNotEmpty ||
        (await txn.rawQuery(
          'SELECT command_id FROM paid_purchase_requests WHERE command_id=? OR purchase_command_id=? OR payment_command_id=?',
          [id, id, id],
        )).isNotEmpty) {
      throw const StockIntakeValidationException(
        'El identificador está reservado por otra operación.',
      );
    }
  }

  static Future<BusinessProfile> _profile(DatabaseExecutor txn) async {
    final rows = await txn.query('app_profile', where: 'id=1');
    if (rows.length != 1) {
      throw const StockIntakeValidationException(
        'Configura el espacio de trabajo primero.',
      );
    }
    final p = BusinessProfile.fromRow(rows.single);
    if (p.timezone != 'America/Bogota') {
      throw const StockIntakeValidationException(
        'El ingreso requiere la zona horaria America/Bogota.',
      );
    }
    return p;
  }

  static void _id(String id) {
    if (!RegExp(r'^[A-Za-z0-9:_-]{1,128}$').hasMatch(id)) {
      throw const StockIntakeValidationException(
        'El identificador no es válido.',
      );
    }
  }

  static String _text(String value, String label, int max) {
    final r = value.trim();
    if (r.isEmpty || r.length > max || RegExp(r'[\x00-\x1f\x7f]').hasMatch(r)) {
      throw StockIntakeValidationException(
        '$label debe tener entre 1 y $max caracteres y no contener controles.',
      );
    }
    return r;
  }

  static int _nonnegative(BigInt value, String label) {
    if (value < BigInt.zero || value > Money.maxMinorUnits) {
      throw StockIntakeValidationException(
        '$label excede el rango entero positivo de 64 bits.',
      );
    }
    return value.toInt();
  }

  static int _signed(BigInt value, String label) {
    if (value < Money.minMinorUnits || value > Money.maxMinorUnits) {
      throw StockIntakeValidationException(
        '$label excede el rango entero de 64 bits.',
      );
    }
    return value.toInt();
  }

  static String _businessDate(DateTime value) {
    final local = value.subtract(const Duration(hours: 5));
    if (!value.isUtc ||
        value.year < 1 ||
        value.year > 9999 ||
        local.year < 1 ||
        local.year > 9999) {
      throw const StockIntakeValidationException(
        'La fecha del ingreso debe ser UTC y estar dentro del rango permitido.',
      );
    }
    return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }
}
