import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/domain/money.dart';
import '../../../core/infrastructure/database/app_database.dart';
import '../../../core/infrastructure/database/schema.dart';
import '../../workspace/domain/business_profile.dart';
import '../domain/inventory_store.dart';

/// Catalog edits never rewrite the snapshots or immutable receipt facts.
class SqliteInventoryStore implements InventoryStore {
  SqliteInventoryStore(this._database, {this.synthetic = false});
  final AppDatabase _database;
  final bool synthetic;

  static const _operatorId = 'system:local-operator';
  static const _inventoryAccountId = 'system:inventory';
  static const _payableAccountId = 'system:supplier-payable';

  @override
  Future<InventorySnapshot> load() =>
      _database.database.transaction((txn) async {
        await _profile(txn);
        final categories = await txn.query(
          'categories',
          orderBy: 'name COLLATE NOCASE, id',
        );
        final suppliers = await txn.query(
          'counterparties',
          where: 'is_supplier = 1',
          orderBy: 'name COLLATE NOCASE, id',
        );
        final products = await txn.query(
          'catalog_items',
          orderBy: 'name COLLATE NOCASE, id',
        );
        final stock = await _stock(txn);
        final supplierLinks = await txn.rawQuery('''
SELECT DISTINCT line.product_id, purchase.supplier_id
FROM purchase_lines line
JOIN purchases purchase ON purchase.document_id = line.purchase_id
JOIN business_documents document ON document.id = purchase.document_id AND document.status = 'posted'
JOIN journal_entries entry ON entry.document_id = document.id AND entry.status = 'posted'
ORDER BY line.product_id, purchase.supplier_id
''');
        final productSupplierIds = <String, List<String>>{};
        for (final row in supplierLinks) {
          productSupplierIds
              .putIfAbsent(row['product_id'] as String, () => [])
              .add(row['supplier_id'] as String);
        }
        final receipts = await txn.rawQuery('''
SELECT p.* FROM purchases p
JOIN business_documents d ON d.id = p.document_id AND d.status = 'posted'
JOIN journal_entries j ON j.document_id = d.id AND j.status = 'posted'
ORDER BY p.received_at_utc DESC, p.document_id
''');
        final receiptLines = await txn.rawQuery('''
SELECT l.* FROM purchase_lines l
JOIN business_documents d ON d.id = l.purchase_id AND d.status = 'posted'
JOIN journal_entries j ON j.document_id = d.id AND j.status = 'posted'
ORDER BY l.purchase_id, l.sequence
''');
        final linesByReceipt = <String, List<PurchaseReceiptLine>>{};
        final paymentRows = await txn.rawQuery('''
SELECT o.origin_document_id, s.amount_minor FROM payable_settlements s
JOIN obligations o ON o.id = s.payable_id
JOIN business_documents d ON d.id = s.supplier_payment_id AND d.status = 'posted'
JOIN journal_entries j ON j.document_id = d.id AND j.status = 'posted'
''');
        final paidByReceipt = <String, BigInt>{};
        for (final row in paymentRows) {
          final id = row['origin_document_id'] as String;
          paidByReceipt[id] =
              (paidByReceipt[id] ?? BigInt.zero) +
              BigInt.from(row['amount_minor'] as int);
        }
        for (final line in receiptLines) {
          linesByReceipt
              .putIfAbsent(line['purchase_id'] as String, () => [])
              .add(
                PurchaseReceiptLine(
                  productName: line['name_snapshot'] as String,
                  quantity: line['quantity'] as int,
                  totalCostMinor: line['acquisition_total_minor'] as int,
                ),
              );
        }
        return InventorySnapshot(
          productSupplierIds: productSupplierIds,
          categories: categories
              .map(
                (r) => InventoryCategory(
                  id: r['id'] as String,
                  name: r['name'] as String,
                  isActive: r['is_active'] == 1,
                ),
              )
              .toList(),
          suppliers: suppliers
              .map(
                (r) => InventorySupplier(
                  id: r['id'] as String,
                  name: r['name'] as String,
                  isActive: r['is_active'] == 1,
                ),
              )
              .toList(),
          products: products
              .map(
                (r) => CatalogProduct(
                  id: r['id'] as String,
                  name: r['name'] as String,
                  sku: r['sku'] as String?,
                  categoryId: r['category_id'] as String?,
                  listPriceMinor: r['list_price_minor'] as int,
                  isActive: r['is_active'] == 1,
                ),
              )
              .toList(),
          stock: stock.entries
              .map(
                (e) => StockPosition(
                  productId: e.key,
                  quantity: _int64(e.value.quantity, 'Existencias'),
                  totalCostMinor: _int64(e.value.cost, 'Valor de existencias'),
                ),
              )
              .toList(),
          receipts: receipts
              .map(
                (r) => PurchaseReceiptSummary(
                  documentId: r['document_id'] as String,
                  supplierName: r['supplier_name_snapshot'] as String,
                  reference: r['supplier_reference'] as String?,
                  totalMinor: r['payable_minor'] as int,
                  paidMinor: _int64(
                    paidByReceipt[r['document_id']] ?? BigInt.zero,
                    'Total pagado',
                  ),
                  receivedAtUtc: DateTime.parse(
                    r['received_at_utc'] as String,
                  ).toUtc(),
                  dueDate: r['due_date'] as String,
                  lines: linesByReceipt[r['document_id']] ?? const [],
                ),
              )
              .toList(),
        );
      });

  @override
  Future<void> saveCategory(InventoryCategory category) async {
    _id(category.id);
    final name = _text(category.name, 'Nombre de categoría', 120);
    await _database.database.transaction((txn) async {
      await _profile(txn);
      await _save(txn, 'categories', category.id, {
        'name': name,
        'is_active': category.isActive ? 1 : 0,
      });
    });
  }

  @override
  Future<void> saveSupplier(InventorySupplier supplier) async {
    _id(supplier.id);
    final name = _text(supplier.name, 'Nombre de proveedor', 120);
    await _database.database.transaction((txn) async {
      await _profile(txn);
      await _save(txn, 'counterparties', supplier.id, {
        'name': name,
        'is_customer': 0,
        'is_supplier': 1,
        'is_active': supplier.isActive ? 1 : 0,
      });
    });
  }

  @override
  Future<void> saveProduct(CatalogProduct product) async {
    _id(product.id);
    if (product.categoryId != null) _id(product.categoryId!);
    final name = _text(product.name, 'Nombre de producto', 120);
    final sku = _optionalText(product.sku, 'SKU', 64);
    await _database.database.transaction((txn) async {
      final profile = await _profile(txn);
      _amount(product.listPriceMinor, profile, 'Precio de lista');
      if (product.categoryId != null) {
        final category = await txn.query(
          'categories',
          where: 'id = ?',
          whereArgs: [product.categoryId],
        );
        if (category.isEmpty ||
            (product.isActive && category.single['is_active'] != 1)) {
          throw const InventoryValidationException(
            'Selecciona una categoría activa.',
          );
        }
      }
      if (sku != null) {
        final duplicate = await txn.query(
          'catalog_items',
          columns: ['id'],
          where: 'sku = ? COLLATE NOCASE AND id <> ?',
          whereArgs: [sku, product.id],
        );
        if (duplicate.isNotEmpty) {
          throw const InventoryValidationException(
            'El SKU ya pertenece a otro producto.',
          );
        }
      }
      await _save(txn, 'catalog_items', product.id, {
        'name': name,
        'sku': sku,
        'category_id': product.categoryId,
        'kind': 'product',
        'unit_code': 'unit',
        'quantity_scale': 0,
        'list_price_minor': product.listPriceMinor,
        'is_active': product.isActive ? 1 : 0,
      });
    });
  }

  @override
  Future<ReceiptResult> receivePurchase(ReceiptCommand command) =>
      _database.database.transaction((txn) async {
        await _guardPaidCommand(txn, command.commandId, internal: false);
        return receivePurchaseInTransaction(txn, command);
      }, exclusive: true);

  /// Composes a fully paid intake without nesting SQLite transactions.
  Future<ReceiptResult> receivePurchaseInTransaction(
    Transaction txn,
    ReceiptCommand command,
  ) async {
    await _guardPaidCommand(txn, command.commandId, internal: true);
    _id(command.commandId);
    _id(command.supplierId);
    if (!command.occurredAtUtc.isUtc ||
        command.occurredAtUtc.year < 1 ||
        command.occurredAtUtc.year > 9999) {
      throw const InventoryValidationException(
        'La fecha de recepción debe estar en UTC.',
      );
    }
    final businessDate = command.occurredAtUtc.subtract(
      const Duration(hours: 5),
    );
    if (businessDate.year < 1 || businessDate.year > 9999) {
      throw const InventoryValidationException(
        'La fecha de recepción en Bogotá está fuera de rango.',
      );
    }
    final businessDateIso = _dateIso(businessDate);
    _dueDate(command.dueDate, businessDateIso);
    final reference = _optionalText(
      command.reference,
      'Referencia del proveedor',
      120,
    );
    if (command.lines.isEmpty || command.lines.length > 1000) {
      throw const InventoryValidationException(
        'La compra debe tener entre 1 y 1000 productos.',
      );
    }
    final lines = command.lines.toList()
      ..sort((a, b) => a.productId.compareTo(b.productId));
    final seen = <String>{};
    for (final line in lines) {
      _id(line.productId);
      if (!seen.add(line.productId)) {
        throw const InventoryValidationException(
          'No repitas un producto en la misma compra.',
        );
      }
      if (line.quantity <= 0) {
        throw const InventoryValidationException(
          'La cantidad debe ser un entero positivo.',
        );
      }
      _int64(BigInt.from(line.quantity), 'Cantidad');
    }
    final profile = await _profile(txn);
    var total = BigInt.zero;
    for (final line in lines) {
      _amount(line.totalCostMinor, profile, 'Costo total de línea');
      total += BigInt.from(line.totalCostMinor);
    }
    final totalMinor = _int64(total, 'Total de compra');
    if (totalMinor <= 0) {
      throw const InventoryValidationException(
        'El total de la compra debe ser positivo.',
      );
    }
    final canonicalPayload = jsonEncode({
      'version': 1,
      'profileId': profile.profileId,
      'currency': profile.currencyCode,
      'scale': profile.moneyScale,
      'supplierId': command.supplierId,
      'reference': reference,
      'dueDate': command.dueDate,
      'occurredAtUtc': command.occurredAtUtc.toIso8601String(),
      'lines': lines
          .map(
            (line) => {
              'productId': line.productId,
              'quantity': line.quantity,
              'totalCostMinor': line.totalCostMinor,
            },
          )
          .toList(),
    });
    final payloadHash = DatabaseSchema.checksum(canonicalPayload);
    final prior = await txn.query(
      'command_log',
      where: 'id = ?',
      whereArgs: [command.commandId],
    );
    if (prior.isNotEmpty) {
      final row = prior.single;
      if (row['command_type'] != 'receive_purchase' ||
          row['response_version'] != 1 ||
          row['payload_hash'] != payloadHash) {
        throw const InventoryValidationException(
          'Este identificador ya corresponde a otro comando.',
        );
      }
      final stored =
          jsonDecode(row['response_json'] as String) as Map<String, dynamic>;
      if (stored['canonicalPayload'] != canonicalPayload) {
        throw const InventoryValidationException(
          'Este identificador ya corresponde a otro comando.',
        );
      }
      final response = stored['result'] as Map<String, dynamic>;
      return ReceiptResult(
        documentId: response['documentId'] as String,
        commandId: response['commandId'] as String,
        totalMinor: response['totalMinor'] as int,
      );
    }

    final reservedSaleCommands = await txn.query(
      'sale_confirmations',
      columns: ['command_id'],
      where: 'command_id = ?',
      whereArgs: [command.commandId],
    );
    if (reservedSaleCommands.isNotEmpty) {
      throw const InventoryValidationException(
        'Este identificador ya corresponde a una confirmación de venta.',
      );
    }
    if ((await txn.query(
      'collection_requests',
      columns: ['command_id'],
      where: 'command_id = ?',
      whereArgs: [command.commandId],
    )).isNotEmpty) {
      throw const InventoryValidationException(
        'Este identificador ya corresponde a una solicitud de cobro.',
      );
    }

    if ((await txn.query(
      'supplier_payment_requests',
      columns: ['command_id'],
      where: 'command_id = ?',
      whereArgs: [command.commandId],
    )).isNotEmpty) {
      throw const InventoryValidationException(
        'Este identificador ya corresponde a una solicitud de pago.',
      );
    }
    if ((await txn.rawQuery(
      'SELECT command_id FROM quick_sale_requests WHERE command_id = ? OR sale_command_id = ? OR collection_command_id = ?',
      [command.commandId, command.commandId, command.commandId],
    )).isNotEmpty) {
      throw const InventoryValidationException(
        'Este identificador ya corresponde a una venta de mostrador.',
      );
    }
    final suppliers = await txn.query(
      'counterparties',
      where: 'id = ? AND is_supplier = 1 AND is_active = 1',
      whereArgs: [command.supplierId],
    );
    if (suppliers.isEmpty) {
      throw const InventoryValidationException(
        'Selecciona un proveedor activo.',
      );
    }
    final productRows = <String, Map<String, Object?>>{};
    final stock = await _stock(txn);
    for (final line in lines) {
      final rows = await txn.rawQuery(
        '''
SELECT c.*, g.is_active AS category_is_active FROM catalog_items c
LEFT JOIN categories g ON g.id = c.category_id WHERE c.id = ?
''',
        [line.productId],
      );
      if (rows.isEmpty ||
          rows.single['is_active'] != 1 ||
          (rows.single['category_id'] != null &&
              rows.single['category_is_active'] != 1)) {
        throw const InventoryValidationException(
          'Todos los productos y sus categorías deben estar activos.',
        );
      }
      productRows[line.productId] = rows.single;
      final laterSales = await txn.rawQuery(
        '''
SELECT s.sold_at_utc FROM sales s
JOIN sale_lines l ON l.sale_id = s.document_id
JOIN business_documents d ON d.id = s.document_id AND d.status = 'posted'
JOIN journal_entries e ON e.document_id = d.id AND e.status = 'posted'
WHERE l.product_id = ?
''',
        [line.productId],
      );
      if (laterSales.any(
        (row) => DateTime.parse(
          row['sold_at_utc'] as String,
        ).isAfter(command.occurredAtUtc),
      )) {
        throw const InventoryValidationException(
          'La recepción no puede ser anterior a una venta confirmada del mismo producto.',
        );
      }
      final current = stock[line.productId] ?? _StockTotals();
      _int64(
        current.quantity + BigInt.from(line.quantity),
        'Existencias resultantes',
      );
      _int64(
        current.cost + BigInt.from(line.totalCostMinor),
        'Valor de existencias resultante',
      );
    }
    final lastSequences = await txn.query(
      'inventory_movements',
      columns: ['stock_sequence'],
      orderBy: 'stock_sequence DESC',
      limit: 1,
    );
    var stockSequence = lastSequences.isEmpty
        ? BigInt.one
        : BigInt.from(lastSequences.single['stock_sequence'] as int) +
              BigInt.one;
    _int64(
      stockSequence + BigInt.from(lines.length - 1),
      'Secuencia de existencias',
    );
    final now = DateTime.now().toUtc().toIso8601String();
    final occurredAt = command.occurredAtUtc.toIso8601String();
    await _ensureSystemRows(txn, now);
    final documentId = InventoryIds.next();
    final entryId = InventoryIds.next();
    final result = ReceiptResult(
      documentId: documentId,
      commandId: command.commandId,
      totalMinor: totalMinor,
    );
    await txn.insert('command_log', {
      'id': command.commandId,
      'command_type': 'receive_purchase',
      'payload_hash': payloadHash,
      'actor_id': _operatorId,
      'response_json': jsonEncode({
        'canonicalPayload': canonicalPayload,
        'result': {
          'documentId': documentId,
          'commandId': command.commandId,
          'totalMinor': totalMinor,
        },
      }),
      'response_version': 1,
      'committed_at_utc': now,
      'authorization_policy_version': 'development-single-user-v1',
    });
    await txn.insert('business_documents', {
      'id': documentId,
      'command_id': command.commandId,
      'command_sequence': 0,
      'profile_id': profile.profileId,
      'actor_id': _operatorId,
      'type': 'purchase_receipt',
      'status': 'draft',
      'occurred_at_utc': occurredAt,
      'business_date': businessDateIso,
      'recorded_at_utc': now,
      'source_kind': synthetic ? 'synthetic' : 'native',
      'date_quality': 'documented',
    });
    await txn.insert('purchases', {
      'document_id': documentId,
      'supplier_id': command.supplierId,
      'supplier_name_snapshot': suppliers.single['name'],
      'supplier_reference': reference,
      'received_at_utc': occurredAt,
      'due_date': command.dueDate,
      'payable_minor': totalMinor,
      'terms': 'credit',
    });
    await txn.insert('journal_entries', {
      'id': entryId,
      'document_id': documentId,
      'status': 'draft',
      'cost_completeness': 'complete',
    });
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineId = InventoryIds.next();
      final movementId = InventoryIds.next();
      final sequence = _int64(stockSequence, 'Secuencia de existencias');
      stockSequence += BigInt.one;
      await txn.insert('purchase_lines', {
        'id': lineId,
        'purchase_id': documentId,
        'sequence': i,
        'product_id': line.productId,
        'name_snapshot': productRows[line.productId]!['name'],
        'quantity': line.quantity,
        'acquisition_total_minor': line.totalCostMinor,
        'cost_quality': 'documented',
      });
      await txn.insert('inventory_movements', {
        'id': movementId,
        'document_id': documentId,
        'sequence': i,
        'stock_sequence': sequence,
        'product_id': line.productId,
        'kind': 'purchase',
        'quantity_delta': line.quantity,
        'value_delta_minor': line.totalCostMinor,
        'purchase_line_id': lineId,
      });
      await txn.insert('cost_layers', {
        'id': InventoryIds.next(),
        'inbound_movement_id': movementId,
        'product_id': line.productId,
        'initial_quantity': line.quantity,
        'total_cost_minor': line.totalCostMinor,
        'cost_quality': 'documented',
        'fifo_sequence': sequence,
        'acquired_at_utc': occurredAt,
      });
    }
    await txn.insert('obligations', {
      'id': InventoryIds.next(),
      'origin_document_id': documentId,
      'sequence': 0,
      'counterparty_id': command.supplierId,
      'kind': 'supplier_payable',
      'control_account_id': _payableAccountId,
      'initial_minor': totalMinor,
      'issued_at_utc': occurredAt,
      'due_date': command.dueDate,
    });
    await txn.insert('journal_lines', {
      'id': InventoryIds.next(),
      'entry_id': entryId,
      'sequence': 0,
      'account_id': _inventoryAccountId,
      'debit_minor': totalMinor,
      'credit_minor': 0,
    });
    await txn.insert('journal_lines', {
      'id': InventoryIds.next(),
      'entry_id': entryId,
      'sequence': 1,
      'account_id': _payableAccountId,
      'debit_minor': 0,
      'credit_minor': totalMinor,
    });
    await txn.update(
      'business_documents',
      {'status': 'posted'},
      where: 'id = ?',
      whereArgs: [documentId],
    );
    await txn.update(
      'journal_entries',
      {'status': 'posted', 'posted_at_utc': now},
      where: 'id = ?',
      whereArgs: [entryId],
    );
    return result;
  }

  static Future<void> _guardPaidCommand(
    DatabaseExecutor txn,
    String id, {
    required bool internal,
  }) async {
    final rows = await txn.rawQuery(
      'SELECT * FROM paid_purchase_requests WHERE command_id=? OR purchase_command_id=? OR payment_command_id=?',
      [id, id, id],
    );
    if (rows.isNotEmpty &&
        !(internal &&
            rows.length == 1 &&
            rows.single['purchase_command_id'] == id &&
            rows.single['status'] == 'executing')) {
      throw const InventoryValidationException(
        'El identificador pertenece a un ingreso de mercancía.',
      );
    }
  }

  static Future<BusinessProfile> _profile(DatabaseExecutor txn) async {
    final rows = await txn.query('app_profile', where: 'id = 1');
    if (rows.length != 1) {
      throw const InventoryValidationException(
        'Configura el espacio de trabajo primero.',
      );
    }
    final profile = BusinessProfile.fromRow(rows.single);
    if (profile.timezone != 'America/Bogota') {
      throw const InventoryValidationException(
        'La recepción requiere la zona horaria America/Bogota.',
      );
    }
    return profile;
  }

  static Future<void> _save(
    DatabaseExecutor txn,
    String table,
    String id,
    Map<String, Object?> values,
  ) async {
    final count = await txn.update(
      table,
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (count == 0) await txn.insert(table, {'id': id, ...values});
  }

  static Future<Map<String, _StockTotals>> _stock(DatabaseExecutor txn) async {
    final rows = await txn.rawQuery('''
SELECT m.product_id, m.quantity_delta, l.total_cost_minor FROM inventory_movements m
JOIN cost_layers l ON l.inbound_movement_id = m.id
JOIN business_documents d ON d.id = m.document_id AND d.status = 'posted'
JOIN journal_entries j ON j.document_id = d.id AND j.status = 'posted'
ORDER BY m.stock_sequence
''');
    final result = <String, _StockTotals>{};
    for (final row in rows) {
      final value = result.putIfAbsent(
        row['product_id'] as String,
        _StockTotals.new,
      );
      value.quantity += BigInt.from(row['quantity_delta'] as int);
      value.cost += BigInt.from(row['total_cost_minor'] as int);
    }
    final outflows = await txn.rawQuery('''
SELECT o.product_id, o.quantity, o.cost_minor FROM sale_outflows o
JOIN business_documents d ON d.id = o.document_id AND d.status = 'posted'
JOIN journal_entries j ON j.document_id = d.id AND j.status = 'posted'
''');
    for (final row in outflows) {
      final value = result.putIfAbsent(
        row['product_id'] as String,
        _StockTotals.new,
      );
      value.quantity -= BigInt.from(row['quantity'] as int);
      value.cost -= BigInt.from(row['cost_minor'] as int);
    }
    return result;
  }

  static Future<void> _ensureSystemRows(
    DatabaseExecutor txn,
    String now,
  ) async {
    final operatorRows = await txn.query(
      'actors',
      where: 'id = ?',
      whereArgs: [_operatorId],
    );
    if (operatorRows.isEmpty) {
      await txn.insert('actors', {
        'id': _operatorId,
        'display_name': 'Operador local',
        'kind': 'system',
        'is_active': 1,
        'created_at_utc': now,
      });
    } else if (operatorRows.single['kind'] != 'system' ||
        operatorRows.single['is_active'] != 1) {
      throw const InventoryValidationException(
        'El operador local del sistema no está disponible.',
      );
    }
    for (final account in [
      {
        'id': _inventoryAccountId,
        'code': 'INV',
        'name': 'Inventario',
        'class': 'asset',
        'role': 'inventory',
        'is_active': 1,
      },
      {
        'id': _payableAccountId,
        'code': 'PROV',
        'name': 'Proveedores por pagar',
        'class': 'liability',
        'role': 'supplier_payable',
        'is_active': 1,
      },
    ]) {
      final rows = await txn.query(
        'ledger_accounts',
        where: 'id = ?',
        whereArgs: [account['id']],
      );
      if (rows.isEmpty) {
        await txn.insert('ledger_accounts', account);
      } else if (rows.single['role'] != account['role'] ||
          rows.single['class'] != account['class'] ||
          rows.single['is_active'] != 1) {
        throw const InventoryValidationException(
          'Las cuentas internas no están disponibles.',
        );
      }
    }
  }

  static void _id(String id) {
    if (!RegExp(r'^[A-Za-z0-9:_-]{1,128}$').hasMatch(id)) {
      throw const InventoryValidationException(
        'El identificador no es válido.',
      );
    }
  }

  static String _text(String value, String label, int maximum) {
    final result = value.trim();
    if (result.isEmpty ||
        result.length > maximum ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(result)) {
      throw InventoryValidationException(
        '$label debe tener entre 1 y $maximum caracteres y no contener controles.',
      );
    }
    return result;
  }

  static String? _optionalText(String? value, String label, int maximum) =>
      value == null || value.trim().isEmpty
      ? null
      : _text(value, label, maximum);

  static void _amount(int value, BusinessProfile profile, String label) {
    if (value < 0) {
      throw InventoryValidationException('$label no puede ser negativo.');
    }
    try {
      Money.fromMinorUnits(
        value,
        currency: profile.currencyCode,
        scale: profile.moneyScale,
      );
    } on RangeError {
      throw InventoryValidationException(
        '$label excede el rango entero de 64 bits.',
      );
    }
  }

  static int _int64(BigInt value, String label) {
    if (value < BigInt.zero || value > Money.maxMinorUnits) {
      throw InventoryValidationException(
        '$label excede el rango entero positivo de 64 bits.',
      );
    }
    return value.toInt();
  }

  static String _dateIso(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  static void _dueDate(String value, String businessDate) {
    if (!RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$').hasMatch(value)) {
      throw const InventoryValidationException(
        'El vencimiento debe usar AAAA-MM-DD.',
      );
    }
    final parsed = DateTime.tryParse('${value}T00:00:00Z');
    if (parsed == null ||
        parsed.year < 1 ||
        _dateIso(parsed) != value ||
        value.compareTo(businessDate) < 0) {
      throw const InventoryValidationException(
        'El vencimiento debe ser una fecha real igual o posterior a la recepción en Bogotá.',
      );
    }
  }
}

class _StockTotals {
  BigInt quantity = BigInt.zero;
  BigInt cost = BigInt.zero;
}
