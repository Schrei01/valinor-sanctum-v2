import 'dart:convert';
import '../../debtors/domain/debtors_store.dart';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/domain/money.dart';
import '../../../core/infrastructure/database/app_database.dart';
import '../../../core/infrastructure/database/schema.dart';
import '../../collections/data/sqlite_collections_store.dart';
import '../../collections/domain/collections_store.dart';
import '../../inventory/domain/inventory_store.dart';
import '../../sales/data/sqlite_sales_store.dart';
import '../../sales/domain/sales_store.dart';
import '../../workspace/domain/business_profile.dart';
import '../domain/quick_sales_store.dart';

/// A quick sale composes the established FIFO sale and its paid portion inside
/// one transaction. Its durable parent request precedes every business effect.
class SqliteQuickSalesStore implements QuickSalesStore {
  SqliteQuickSalesStore(this._database, {this.synthetic = false});
  final AppDatabase _database;
  final bool synthetic;
  SqliteSalesStore get _sales =>
      SqliteSalesStore(_database, synthetic: synthetic);
  SqliteCollectionsStore get _collections =>
      SqliteCollectionsStore(_database, synthetic: synthetic);

  @override
  Future<void> ensureDefaults() => _database.database.transaction((txn) async {
    await _profile(txn);
    for (final spec in [
      ('cash', 'Caja', 'EFECTIVO', 'Efectivo'),
      ('mobile', 'Nequi', 'NEQUI', 'Nequi'),
    ]) {
      final optionId = 'quick-default:${spec.$3}';
      if ((await txn.query(
        'quick_payment_options',
        where: 'id = ?',
        whereArgs: [optionId],
      )).isNotEmpty) {
        continue;
      }
      final accounts = await txn.rawQuery(
        '''
SELECT c.* FROM cash_accounts c JOIN ledger_accounts l ON l.id=c.ledger_account_id
WHERE c.kind=? AND c.is_active=1 AND c.is_available=1 AND l.is_active=1
AND l.class='asset' AND l.role='cash' ORDER BY c.name COLLATE NOCASE,c.id
''',
        [spec.$1],
      );
      final suitable = accounts
          .where(
            (a) =>
                spec.$1 == 'cash' ||
                (a['name'] as String).trim().toLowerCase() == 'nequi',
          )
          .toList();
      final String accountId;
      if (suitable.isNotEmpty) {
        accountId = suitable.first['id'] as String;
      } else {
        accountId = InventoryIds.next();
        await txn.insert('ledger_accounts', {
          'id': 'money:$accountId',
          'code': 'CASH:$accountId',
          'name': spec.$2,
          'class': 'asset',
          'role': 'cash',
          'is_active': 1,
        });
        await txn.insert('cash_accounts', {
          'id': accountId,
          'ledger_account_id': 'money:$accountId',
          'name': spec.$2,
          'kind': spec.$1,
          'is_available': 1,
          'is_active': 1,
        });
      }
      // An existing code is an immutable identity, including when disabled.
      final methods = await txn.query(
        'payment_methods',
        where: 'UPPER(code) = ?',
        whereArgs: [spec.$3],
        orderBy: 'id',
      );
      final String methodId;
      if (methods.isNotEmpty) {
        methodId = methods.first['id'] as String;
      } else {
        methodId = InventoryIds.next();
        await txn.insert('payment_methods', {
          'id': methodId,
          'code': spec.$3,
          'name': spec.$4,
          'is_active': 1,
        });
      }
      await txn.insert('quick_payment_options', {
        'id': optionId,
        'label': spec.$4,
        'cash_account_id': accountId,
        'payment_method_id': methodId,
        'is_active': 1,
      });
    }
  }, exclusive: true);

  @override
  Future<QuickSalesSnapshot> load() async {
    final commercial = await _sales.load();
    return _database.database.transaction((txn) async {
      await _profile(txn);
      final rows = await txn.query(
        'quick_sales_accounts',
        where: "status IN ('open','prepared')",
        orderBy:
            'created_at_utc IS NOT NULL DESC, ${DatabaseSchema.utcSortKey('created_at_utc')} DESC, rowid DESC',
      );
      final accounts = <QuickSaleAccount>[];
      for (final row in rows) {
        accounts.add(await _account(txn, row));
      }
      final options = await _options(txn);
      final requests = await txn.query(
        'quick_sale_requests',
        where: "status IN ('prepared','rejected')",
        orderBy: 'prepared_at_utc,command_id',
      );
      final history = await txn.query(
        'quick_sale_requests',
        where: "status='confirmed'",
        orderBy: 'occurred_at_utc DESC,command_id',
      );
      final sales = <ConfirmedQuickSale>[];
      for (final row in history) {
        final logged = (await txn.query(
          'command_log',
          where: 'id=?',
          whereArgs: [row['command_id']],
        )).single;
        final cashFacts = await txn.query(
          'quick_sale_line_payments',
          where: 'request_id=?',
          whereArgs: [row['command_id']],
          orderBy: 'sequence',
        );
        final creditFacts = await txn.query(
          'quick_sale_line_tenders',
          where: 'request_id=?',
          whereArgs: [row['command_id']],
          orderBy: 'sequence',
        );
        final splitFacts = await txn.query(
          'quick_sale_split_tenders',
          where: 'request_id=?',
          whereArgs: [row['command_id']],
          orderBy: 'sequence',
        );
        final facts = <Map<String, Object?>>[...cashFacts, ...creditFacts]
          ..sort(
            (a, b) => (a['sequence'] as int).compareTo(b['sequence'] as int),
          );
        final payload =
            jsonDecode(row['canonical_payload'] as String)
                as Map<String, dynamic>;
        if (payload['version'] == 4) {
          for (final line
              in (payload['lines'] as List).cast<Map<String, dynamic>>()) {
            final parts = splitFacts.where(
              (f) => f['source_line_id'] == line['lineId'],
            );
            facts.add({
              'product_name_snapshot': line['productName'],
              'quantity': line['quantity'],
              'unit_price_minor': line['unitPriceMinor'],
              'total_minor': line['totalMinor'],
              'payment_option_label_snapshot': 'Dividido',
              'payment_breakdown': {
                for (final part in parts)
                  part['payment_option_label_snapshot'] as String:
                      part['total_minor'] as int,
              },
              'is_credit': parts.any((p) => p['is_credit'] == 1) ? 1 : 0,
            });
          }
        }
        sales.add(
          ConfirmedQuickSale(
            commandId: row['command_id'] as String,
            label: payload['label'] as String,
            soldAtUtc: DateTime.parse(row['occurred_at_utc'] as String).toUtc(),
            result: _prior(logged, row['canonical_payload'] as String),
            lines: facts
                .map(
                  (f) => ConfirmedQuickSaleLine(
                    productName: f['product_name_snapshot'] as String,
                    quantity: f['quantity'] as int,
                    unitPriceMinor: f['unit_price_minor'] as int,
                    totalMinor: f['total_minor'] as int,
                    paymentLabel: f['payment_option_label_snapshot'] as String,
                    isCredit: f['is_credit'] == 1,
                    paymentBreakdown: Map.unmodifiable(
                      (f['payment_breakdown'] as Map<String, int>?) ?? const {},
                    ),
                  ),
                )
                .toList(),
          ),
        );
      }
      return QuickSalesSnapshot(
        accounts: accounts,
        products: commercial.products,
        stock: commercial.stock,
        paymentOptions: options,
        pendingSales: requests.map(_prepared).toList(),
        sales: sales,
        debtors:
            (await txn.rawQuery(
                  '''SELECT debtor.*,coalesce(sum(balance.remaining_minor),0) balance_minor FROM debtors debtor
LEFT JOIN debtor_receivables link ON link.debtor_id=debtor.id LEFT JOIN customer_receivable_balances balance ON balance.id=link.receivable_id
GROUP BY debtor.id ORDER BY debtor.name COLLATE NOCASE,debtor.id''',
                ))
                .map(
                  (r) => DebtorSummary(
                    id: r['id'] as String,
                    name: r['name'] as String,
                    balanceMinor: r['balance_minor'] as int,
                    isActive: r['is_active'] == 1,
                  ),
                )
                .toList(),
      );
    });
  }

  @override
  Future<QuickSaleAccount> saveAccount(SaveQuickSaleAccount input) async {
    _id(input.id);
    if (input.createdAtUtc != null &&
        (!input.createdAtUtc!.isUtc ||
            input.createdAtUtc!.year < 1 ||
            input.createdAtUtc!.year > 9998)) {
      throw const QuickSalesValidationException(
        'La fecha de creación no es válida.',
      );
    }
    if (!['legacy', 'single', 'split'].contains(input.paymentMode) ||
        (input.paymentMode != 'single' &&
            input.accountPaymentOptionId != null)) {
      throw const QuickSalesValidationException(
        'Revisa la forma de pago de la cuenta.',
      );
    }
    if (input.paymentMode == 'single' &&
        input.lines.any(
          (l) => l.isSplit || l.paymentOptionId != input.accountPaymentOptionId,
        )) {
      throw const QuickSalesValidationException(
        'El pago único debe aplicarse a toda la cuenta.',
      );
    }
    var customer = input.customerName.trim();
    if (input.expectedRevision < 0 ||
        input.label.length > 120 ||
        input.lines.length > 100 ||
        customer.length > 120 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(customer)) {
      throw const QuickSalesValidationException(
        'La cuenta admite hasta 100 líneas y un nombre de 120 caracteres.',
      );
    }
    final seen = <String>{};
    for (final line in input.lines) {
      _id(line.id);
      if (!seen.add(line.id) ||
          line.quantityText.length > 32 ||
          (line.unitPriceMinor != null && line.unitPriceMinor! < 0)) {
        throw const QuickSalesValidationException(
          'Revisa las líneas de la cuenta.',
        );
      }
      if (line.productId != null) _id(line.productId!);
      if (line.paymentOptionId != null) _id(line.paymentOptionId!);
      final splitIds = <String>{};
      if (line.paymentParts.length > 3 ||
          (line.isSplit && line.paymentOptionId != null)) {
        throw const QuickSalesValidationException(
          'Revisa el reparto de pagos.',
        );
      }
      for (final part in line.paymentParts) {
        if (!splitIds.add(part.paymentOptionId) ||
            part.amountMinor <= 0 ||
            ![
              'quick-default:EFECTIVO',
              'quick-default:NEQUI',
              QuickPaymentOption.creditId,
            ].contains(part.paymentOptionId)) {
          throw const QuickSalesValidationException(
            'El reparto requiere importes positivos y medios diferentes.',
          );
        }
      }
    }
    return _database.database.transaction((txn) async {
      await _profile(txn);
      if (input.debtorId != null) {
        _id(input.debtorId!);
        final person = await txn.query(
          'debtors',
          where: 'id=?',
          whereArgs: [input.debtorId],
        );
        if (person.length != 1) {
          throw const QuickSalesValidationException(
            'Selecciona una persona registrada en Deudores.',
          );
        }
        customer = person.single['name'] as String;
      }
      final rows = await txn.query(
        'quick_sales_accounts',
        where: 'id=?',
        whereArgs: [input.id],
      );
      if (rows.isEmpty && input.expectedRevision != 0) {
        throw const QuickSalesValidationException(
          'La cuenta ya no existe. Actualiza la vista.',
        );
      }
      if (rows.isNotEmpty) {
        final old = await _account(txn, rows.single);
        if (input.createdAtUtc != null &&
            old.createdAtUtc != input.createdAtUtc) {
          throw const QuickSalesValidationException(
            'La fecha de creación de la cuenta no puede cambiar.',
          );
        }
        if (old.status == 'open' &&
            old.revision == input.expectedRevision + 1 &&
            old.label == input.label &&
            old.customerName == customer &&
            old.debtorId == input.debtorId &&
            old.paymentMode == input.paymentMode &&
            old.accountPaymentOptionId == input.accountPaymentOptionId &&
            old.paymentSplitBasis == input.paymentSplitBasis &&
            _sameLines(old.lines, input.lines)) {
          return old;
        }
        if (old.status != 'open' || old.revision != input.expectedRevision) {
          throw const QuickSalesValidationException(
            'La cuenta cambió o tiene una venta pendiente. Actualiza la vista.',
          );
        }
      }
      final revision = _int(
        BigInt.from(input.expectedRevision) + BigInt.one,
        'Revisión',
      );
      final now = DateTime.now().toUtc();
      final createdAt = rows.isEmpty
          ? input.createdAtUtc ?? now
          : rows.single['created_at_utc'] == null
          ? null
          : DateTime.parse(rows.single['created_at_utc'] as String);
      if (rows.isEmpty) {
        await txn.insert('quick_sales_accounts', {
          'id': input.id,
          'label': input.label,
          'customer_name': customer,
          'debtor_id': input.debtorId,
          'payment_mode': input.paymentMode,
          'account_payment_option_id': input.accountPaymentOptionId,
          'payment_split_basis': input.paymentSplitBasis,
          'revision': revision,
          'status': 'open',
          'updated_at_utc': now.toIso8601String(),
          'created_at_utc': createdAt!.toIso8601String(),
        });
      } else {
        await txn.update(
          'quick_sales_accounts',
          {
            'label': input.label,
            'customer_name': customer,
            'debtor_id': input.debtorId,
            'payment_mode': input.paymentMode,
            'account_payment_option_id': input.accountPaymentOptionId,
            'payment_split_basis': input.paymentSplitBasis,
            'revision': revision,
            'updated_at_utc': now.toIso8601String(),
          },
          where: 'id=?',
          whereArgs: [input.id],
        );
        await txn.delete(
          'quick_sales_lines',
          where: 'account_id=?',
          whereArgs: [input.id],
        );
      }
      for (var i = 0; i < input.lines.length; i++) {
        final line = input.lines[i];
        await txn.insert('quick_sales_lines', {
          'id': line.id,
          'account_id': input.id,
          'sequence': i,
          'product_id': line.productId,
          'quantity_text': line.quantityText,
          'unit_price_minor': line.unitPriceMinor,
          'payment_split_json': jsonEncode(
            line.paymentParts.map((p) => p.toJson()).toList(),
          ),
          'payment_option_id':
              line.paymentOptionId == QuickPaymentOption.creditId
              ? null
              : line.paymentOptionId,
          'is_credit': line.paymentOptionId == QuickPaymentOption.creditId
              ? 1
              : 0,
        });
      }
      return QuickSaleAccount(
        id: input.id,
        label: input.label,
        customerName: customer,
        debtorId: input.debtorId,
        paymentMode: input.paymentMode,
        accountPaymentOptionId: input.accountPaymentOptionId,
        paymentSplitBasis: input.paymentSplitBasis,
        revision: revision,
        status: 'open',
        updatedAtUtc: now,
        createdAtUtc: createdAt,
        lines: input.lines,
      );
    }, exclusive: true);
  }

  @override
  Future<void> cancelAccount({
    required String accountId,
    required int expectedRevision,
  }) => _database.database.transaction((txn) async {
    _id(accountId);
    final rows = await txn.query(
      'quick_sales_accounts',
      where: 'id=?',
      whereArgs: [accountId],
    );
    if (rows.isEmpty) {
      throw const QuickSalesValidationException('La cuenta no existe.');
    }
    final row = rows.single;
    if (row['status'] == 'cancelled' && row['revision'] == expectedRevision) {
      return;
    }
    if (row['status'] != 'open' || row['revision'] != expectedRevision) {
      throw const QuickSalesValidationException(
        'Solo se puede quitar una cuenta abierta sin venta pendiente.',
      );
    }
    await txn.update(
      'quick_sales_accounts',
      {
        'status': 'cancelled',
        'updated_at_utc': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id=?',
      whereArgs: [accountId],
    );
  }, exclusive: true);

  @override
  Future<PreparedQuickSale> prepareSale({
    required String commandId,
    required String accountId,
    required int expectedRevision,
    required DateTime occurredAtUtc,
  }) async {
    _id(commandId);
    _id(accountId);
    _date(occurredAtUtc);
    return _database.database.transaction((txn) async {
      final profile = await _profile(txn);
      final prior = await txn.query(
        'quick_sale_requests',
        where: 'command_id=?',
        whereArgs: [commandId],
      );
      if (prior.isNotEmpty) {
        final row = prior.single;
        if (row['account_id'] != accountId ||
            row['account_revision'] != expectedRevision ||
            DateTime.parse(
                  row['occurred_at_utc'] as String,
                ).microsecondsSinceEpoch !=
                occurredAtUtc.microsecondsSinceEpoch) {
          throw const QuickSalesValidationException(
            'El identificador ya pertenece a otra venta.',
          );
        }
        return _prepared(row);
      }
      await _unusedCommand(txn, commandId);
      final rows = await txn.query(
        'quick_sales_accounts',
        where: 'id=?',
        whereArgs: [accountId],
      );
      if (rows.isEmpty) {
        throw const QuickSalesValidationException('La cuenta no existe.');
      }
      final account = await _account(txn, rows.single);
      if (account.needsPaymentReview) {
        throw const QuickSalesValidationException(
          'El consumo cambió. Revisa y guarda de nuevo la división antes de registrar.',
        );
      }
      if (account.paymentMode == 'single' &&
          account.accountPaymentOptionId == null) {
        throw const QuickSalesValidationException(
          'Selecciona la forma de pago de la cuenta.',
        );
      }
      if (account.status != 'open' || account.revision != expectedRevision) {
        throw const QuickSalesValidationException(
          'La cuenta cambió o tiene una venta pendiente. Actualiza la vista.',
        );
      }
      if (account.label.trim().isEmpty || account.lines.isEmpty) {
        throw const QuickSalesValidationException(
          'Escribe un nombre y agrega productos a la cuenta.',
        );
      }
      if (account.lines.any((l) => l.isSplit)) {
        return _prepareSplit(txn, account, profile, commandId, occurredAtUtc);
      }
      final lines = <Map<String, Object?>>[];
      final prices = <String, int>{};
      var total = BigInt.zero;
      var creditTotal = BigInt.zero;
      final hasCredit = account.lines.any(
        (line) => line.paymentOptionId == QuickPaymentOption.creditId,
      );
      final customer = account.customerName.trim();
      if (hasCredit && (customer.isEmpty || account.debtorId == null)) {
        throw const QuickSalesValidationException(
          'Asigna la cuenta a una persona registrada en Deudores.',
        );
      }
      if (hasCredit) {
        final person = await txn.query(
          'debtors',
          where: 'id=? AND is_active=1',
          whereArgs: [account.debtorId],
        );
        if (person.length != 1 || person.single['name'] != customer) {
          throw const QuickSalesValidationException(
            'La persona no está habilitada para nuevas deudas.',
          );
        }
      }
      for (final line in account.lines) {
        if (line.productId == null ||
            line.unitPriceMinor == null ||
            line.paymentOptionId == null ||
            !RegExp(r'^[0-9]+$').hasMatch(line.quantityText.trim())) {
          throw const QuickSalesValidationException(
            'Completa producto, cantidad, precio y forma de pago de cada línea.',
          );
        }
        final quantity = _int(
          BigInt.parse(line.quantityText.trim()),
          'Cantidad',
        );
        if (quantity <= 0) {
          throw const QuickSalesValidationException(
            'La cantidad debe ser un entero positivo.',
          );
        }
        final price = line.unitPriceMinor!;
        Money.fromMinorUnits(
          price,
          currency: profile.currencyCode,
          scale: profile.moneyScale,
        );
        if (prices.containsKey(line.productId) &&
            prices[line.productId] != price) {
          throw const QuickSalesValidationException(
            'El mismo producto debe tener el mismo precio en esta cuenta. Usa otra cuenta para otro precio.',
          );
        }
        prices[line.productId!] = price;
        final products = await txn.rawQuery(
          'SELECT p.* FROM catalog_items p LEFT JOIN categories c ON c.id=p.category_id WHERE p.id=? AND p.is_active=1 AND (p.category_id IS NULL OR c.is_active=1)',
          [line.productId],
        );
        if (products.length != 1) {
          throw const QuickSalesValidationException(
            'Uno de los productos ya no está activo.',
          );
        }
        final isCredit = line.paymentOptionId == QuickPaymentOption.creditId;
        final option = isCredit
            ? _creditFact()
            : await _optionFact(txn, line.paymentOptionId!);
        final amount = _int(
          BigInt.from(quantity) * BigInt.from(price),
          'Total de línea',
        );
        total += BigInt.from(amount);
        if (isCredit) creditTotal += BigInt.from(amount);
        lines.add({
          'lineId': line.id,
          'productId': line.productId,
          'productName': products.single['name'],
          'quantity': quantity,
          'unitPriceMinor': price,
          'totalMinor': amount,
          if (hasCredit) 'isCredit': isCredit,
          ...option,
        });
      }
      final totalMinor = _int(total, 'Total de venta');
      if (totalMinor <= 0) {
        throw const QuickSalesValidationException(
          'El total de venta debe ser positivo.',
        );
      }
      if (hasCredit) {
        await _checkCreditCapacity(txn, creditTotal);
      }
      final now = DateTime.now().toUtc();
      final row = <String, Object?>{
        'command_id': commandId,
        'account_id': accountId,
        'account_revision': expectedRevision,
        'canonical_payload': jsonEncode({
          'version': hasCredit ? 3 : 1,
          'profileId': profile.profileId,
          'currency': profile.currencyCode,
          'scale': profile.moneyScale,
          'label': account.label,
          'occurredAtUtc': occurredAtUtc.toIso8601String(),
          'totalMinor': totalMinor,
          if (hasCredit) ...{
            'customerName': customer,
            'debtorId': account.debtorId,
            'creditMinor': _int(creditTotal, 'Total de deuda'),
            'paidMinor': _int(total - creditTotal, 'Total pagado'),
          },
          'lines': lines,
        }),
        'occurred_at_utc': occurredAtUtc.toIso8601String(),
        'prepared_at_utc': now.toIso8601String(),
        'status': 'prepared',
        'sale_command_id': InventoryIds.next(),
        'collection_command_id': InventoryIds.next(),
        'legacy_draft_id': InventoryIds.next(),
      };
      await txn.insert('quick_sale_requests', row);
      await txn.update(
        'quick_sales_accounts',
        {'status': 'prepared', 'updated_at_utc': now.toIso8601String()},
        where: 'id=?',
        whereArgs: [accountId],
      );
      return _prepared(row);
    }, exclusive: true);
  }

  @override
  Future<QuickSaleResult> confirmPrepared(String commandId) async {
    _id(commandId);
    try {
      return await _database.database.transaction(
        (txn) => _confirm(txn, commandId),
        exclusive: true,
      );
    } on SalesValidationException catch (e) {
      await _reject(commandId, e.message);
      throw QuickSalesValidationException(e.message);
    } on CollectionsValidationException catch (e) {
      await _reject(commandId, e.message);
      throw QuickSalesValidationException(e.message);
    } on QuickSalesValidationException catch (e) {
      await _reject(commandId, e.message);
      rethrow;
    }
  }

  Future<QuickSaleResult> _confirm(Transaction txn, String commandId) async {
    final rows = await txn.query(
      'quick_sale_requests',
      where: 'command_id=?',
      whereArgs: [commandId],
    );
    if (rows.isEmpty) {
      throw const QuickSalesValidationException(
        'No existe la venta pendiente.',
      );
    }
    final request = rows.single;
    final canonical = request['canonical_payload'] as String;
    final logged = await txn.query(
      'command_log',
      where: 'id=?',
      whereArgs: [commandId],
    );
    if (logged.isNotEmpty) return _prior(logged.single, canonical);
    if (request['status'] != 'prepared') {
      throw const QuickSalesValidationException(
        'Esta venta fue rechazada o descartada. Libera la cuenta para corregirla.',
      );
    }
    final payload = jsonDecode(canonical) as Map<String, dynamic>;
    final splitCheckout = payload['version'] == 4;
    final creditCheckout =
        payload['version'] == 2 || payload['version'] == 3 || splitCheckout;
    final registeredCheckout =
        payload['version'] == 3 ||
        (splitCheckout && (payload['creditMinor'] as int) > 0);
    final profile = await _profile(txn);
    final accounts = await txn.query(
      'quick_sales_accounts',
      where: 'id=?',
      whereArgs: [request['account_id']],
    );
    if (accounts.length != 1 ||
        accounts.single['status'] != 'prepared' ||
        accounts.single['revision'] != request['account_revision'] ||
        payload['profileId'] != profile.profileId ||
        payload['currency'] != profile.currencyCode ||
        payload['scale'] != profile.moneyScale ||
        (payload['version'] != 1 && !creditCheckout) ||
        ((registeredCheckout || (creditCheckout && !splitCheckout)) &&
            (accounts.single['customer_name'] != payload['customerName'] ||
                (payload['customerName'] as String).trim().isEmpty)) ||
        payload['occurredAtUtc'] != request['occurred_at_utc']) {
      throw const QuickSalesValidationException(
        'La cuenta no coincide con la solicitud guardada.',
      );
    }
    final lines = (payload[splitCheckout ? 'tenders' : 'lines'] as List)
        .cast<Map<String, dynamic>>();
    if (registeredCheckout) {
      final person = await txn.query(
        'debtors',
        where: 'id=? AND is_active=1',
        whereArgs: [payload['debtorId']],
      );
      if (person.length != 1 ||
          person.single['name'] != payload['customerName'] ||
          accounts.single['debtor_id'] != payload['debtorId']) {
        throw const QuickSalesValidationException(
          'La persona de esta cuenta cambió o no está habilitada para fiado.',
        );
      }
    }
    if (creditCheckout) {
      await _checkCreditCapacity(
        txn,
        BigInt.from(payload['creditMinor'] as int),
      );
    }
    for (final line in lines) {
      final current = creditCheckout && line['isCredit'] == true
          ? _creditFact()
          : await _optionFact(txn, line['paymentOptionId'] as String);
      if (current['cashAccountId'] != line['cashAccountId'] ||
          current['paymentMethodId'] != line['paymentMethodId'] ||
          current['cashAccountKind'] != line['cashAccountKind'] ||
          current['paymentMethodCode'] != line['paymentMethodCode']) {
        throw const QuickSalesValidationException(
          'La identidad de la forma de pago cambió.',
        );
      }
      final product = await txn.query(
        'catalog_items',
        where: 'id=?',
        whereArgs: [line['productId']],
      );
      // The prepared snapshot is the customer-facing name. Requiring the same
      // name keeps the composed legacy sale and line-payment history identical.
      if (product.length != 1 ||
          product.single['name'] != line['productName']) {
        throw const QuickSalesValidationException(
          'Un producto cambió después de preparar la venta. Libera y revisa la cuenta.',
        );
      }
    }
    await txn.update(
      'quick_sale_requests',
      {'status': 'executing'},
      where: 'command_id=?',
      whereArgs: [commandId],
    );
    final grouped = <String, ({int price, BigInt quantity})>{};
    for (final line in lines) {
      final id = line['productId'] as String;
      final old = grouped[id];
      grouped[id] = (
        price: line['unitPriceMinor'] as int,
        quantity:
            (old?.quantity ?? BigInt.zero) +
            BigInt.from(line['quantity'] as int),
      );
    }
    final draft = await _sales.saveDraftInTransaction(
      txn,
      SaveSaleDraft(
        id: request['legacy_draft_id'] as String,
        label: payload['label'] as String,
        customerName: creditCheckout
            ? payload['customerName'] as String
            : 'Consumidor final',
        expectedRevision: 0,
        lines: grouped.entries
            .map(
              (g) => SaleDraftLine(
                productId: g.key,
                quantity: _int(g.value.quantity, 'Cantidad acumulada'),
                unitPriceMinor: g.value.price,
              ),
            )
            .toList(),
      ),
    );
    final occurred = DateTime.parse(
      request['occurred_at_utc'] as String,
    ).toUtc();
    final saleCommand = request['sale_command_id'] as String;
    await _sales.prepareConfirmationInTransaction(
      txn,
      commandId: saleCommand,
      draftId: draft.id,
      expectedRevision: draft.revision,
      occurredAtUtc: occurred,
      dueDate: _date(occurred),
    );
    final sale = await _sales.confirmInTransaction(txn, saleCommand);
    if (sale.totalMinor != payload['totalMinor']) {
      throw const QuickSalesValidationException(
        'El total no coincide con la venta preparada.',
      );
    }
    final receivable = (await txn.query(
      'customer_receivables',
      where: 'origin_document_id=?',
      whereArgs: [sale.documentId],
    )).single;
    if (registeredCheckout) {
      await txn.insert('debtor_receivables', {
        'receivable_id': receivable['id'],
        'sales_receivable_id': receivable['id'],
        'debtor_id': payload['debtorId'],
        'source': 'sale',
        'command_id': commandId,
        'assigned_at_utc': DateTime.now().toUtc().toIso8601String(),
      });
    }
    final payments =
        <String, ({String account, String method, BigInt amount})>{};
    for (final line in lines) {
      if (creditCheckout && line['isCredit'] == true) continue;
      final amount = line['totalMinor'] as int;
      if (amount == 0) continue;
      final key = '${line['cashAccountId']}\u0000${line['paymentMethodId']}';
      final old = payments[key];
      payments[key] = (
        account: line['cashAccountId'] as String,
        method: line['paymentMethodId'] as String,
        amount: (old?.amount ?? BigInt.zero) + BigInt.from(amount),
      );
    }
    final collectionCommand = request['collection_command_id'] as String;
    CollectionResult? collection;
    if (payments.isNotEmpty) {
      await _collections.prepareCollectionInTransaction(
        txn,
        CollectionCommand(
          commandId: collectionCommand,
          receivableId: receivable['id'] as String,
          occurredAtUtc: occurred,
          parts: payments.values
              .map(
                (p) => CollectionPartInput(
                  cashAccountId: p.account,
                  paymentMethodId: p.method,
                  amountMinor: _int(p.amount, 'Cobro por forma de pago'),
                ),
              )
              .toList(),
        ),
        snapshots: payments.values.map((p) {
          final line = lines.firstWhere(
            (l) =>
                l['cashAccountId'] == p.account &&
                l['paymentMethodId'] == p.method,
          );
          return CollectionPart(
            cashAccountId: p.account,
            paymentMethodId: p.method,
            cashAccountName: line['cashAccountName'] as String,
            cashAccountKind: line['cashAccountKind'] as String,
            paymentMethodCode: line['paymentMethodCode'] as String,
            paymentMethodName: line['paymentMethodName'] as String,
            amountMinor: _int(p.amount, 'Cobro por forma de pago'),
          );
        }).toList(),
      );
      collection = await _collections.confirmInTransaction(
        txn,
        collectionCommand,
      );
    }
    final creditMinor = creditCheckout ? payload['creditMinor'] as int : 0;
    final paidMinor = creditCheckout
        ? payload['paidMinor'] as int
        : sale.totalMinor;
    if ((collection?.remainingMinor ?? sale.totalMinor) != creditMinor ||
        (collection?.totalMinor ?? 0) != paidMinor) {
      throw const QuickSalesValidationException(
        'El cobro y la deuda no coinciden con la venta preparada.',
      );
    }
    final legacyLines = await txn.query(
      'sale_lines',
      where: 'sale_id=?',
      whereArgs: [sale.documentId],
    );
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final saleLine = legacyLines.singleWhere(
        (l) => l['product_id'] == line['productId'],
      );
      await txn.insert(
        splitCheckout
            ? 'quick_sale_split_tenders'
            : creditCheckout
            ? 'quick_sale_line_tenders'
            : 'quick_sale_line_payments',
        {
          'id': InventoryIds.next(),
          'request_id': commandId,
          'sequence': i,
          'source_line_id': line['lineId'],
          'sale_document_id': sale.documentId,
          'sale_line_id': saleLine['id'],
          'collection_document_id': line['isCredit'] == true
              ? null
              : collection?.documentId,
          'product_id': line['productId'],
          'product_name_snapshot': line['productName'],
          'quantity': line['quantity'],
          'unit_price_minor': line['unitPriceMinor'],
          'total_minor': line['totalMinor'],
          'payment_option_id': line['isCredit'] == true
              ? null
              : line['paymentOptionId'],
          'payment_option_label_snapshot': line['paymentOptionLabel'],
          'cash_account_id': line['cashAccountId'],
          'payment_method_id': line['paymentMethodId'],
          'cash_account_name_snapshot': line['cashAccountName'],
          'cash_account_kind_snapshot': line['cashAccountKind'],
          'payment_method_code_snapshot': line['paymentMethodCode'],
          'payment_method_name_snapshot': line['paymentMethodName'],
          if (creditCheckout) ...{
            'is_credit': line['isCredit'] == true ? 1 : 0,
            'customer_name_snapshot': payload['customerName'],
          },
        },
      );
    }
    final result = QuickSaleResult(
      commandId: commandId,
      saleDocumentId: sale.documentId,
      collectionDocumentId: collection?.documentId,
      totalMinor: sale.totalMinor,
      totalCostMinor: sale.totalCostMinor,
      creditMinor: creditMinor,
      customerName: creditCheckout ? payload['customerName'] as String : '',
      debtorId: registeredCheckout ? payload['debtorId'] as String : null,
    );
    final now = DateTime.now().toUtc().toIso8601String();
    await txn.insert('command_log', {
      'id': commandId,
      'command_type': 'quick_sale',
      'payload_hash': DatabaseSchema.checksum(canonical),
      'actor_id': 'system:local-operator',
      'response_json': jsonEncode({
        'canonicalPayload': canonical,
        'result': {
          'commandId': commandId,
          'saleDocumentId': sale.documentId,
          'collectionDocumentId': collection?.documentId,
          'totalMinor': result.totalMinor,
          'totalCostMinor': result.totalCostMinor,
          if (creditCheckout) ...{
            'creditMinor': result.creditMinor,
            'customerName': result.customerName,
            if (registeredCheckout) 'debtorId': result.debtorId,
          },
        },
      }),
      'response_version': 1,
      'committed_at_utc': now,
      'authorization_policy_version': 'development-single-user-v1',
    });
    await txn.update(
      'quick_sale_requests',
      {'status': 'confirmed'},
      where: 'command_id=?',
      whereArgs: [commandId],
    );
    await txn.update(
      'quick_sales_accounts',
      {
        'status': 'confirmed',
        'confirmed_document_id': sale.documentId,
        'updated_at_utc': now,
      },
      where: 'id=?',
      whereArgs: [request['account_id']],
    );
    return result;
  }

  Future<PreparedQuickSale> _prepareSplit(
    DatabaseExecutor txn,
    QuickSaleAccount account,
    BusinessProfile profile,
    String commandId,
    DateTime occurred,
  ) async {
    final lines = <Map<String, Object?>>[], tenders = <Map<String, Object?>>[];
    final prices = <String, int>{};
    var total = BigInt.zero, credit = BigInt.zero;
    for (var sequence = 0; sequence < account.lines.length; sequence++) {
      final line = account.lines[sequence];
      if (line.productId == null ||
          line.unitPriceMinor == null ||
          !RegExp(r'^[0-9]+$').hasMatch(line.quantityText.trim())) {
        throw const QuickSalesValidationException(
          'Completa producto, cantidad y precio de cada línea.',
        );
      }
      final quantity = _int(BigInt.parse(line.quantityText.trim()), 'Cantidad');
      final price = line.unitPriceMinor!;
      if (quantity <= 0 || price < 0) {
        throw const QuickSalesValidationException('Revisa cantidad y precio.');
      }
      Money.fromMinorUnits(
        price,
        currency: profile.currencyCode,
        scale: profile.moneyScale,
      );
      if (prices.containsKey(line.productId) &&
          prices[line.productId] != price) {
        throw const QuickSalesValidationException(
          'El mismo producto debe tener el mismo precio en esta cuenta.',
        );
      }
      prices[line.productId!] = price;
      final products = await txn.rawQuery(
        'SELECT p.* FROM catalog_items p LEFT JOIN categories c ON c.id=p.category_id WHERE p.id=? AND p.is_active=1 AND (p.category_id IS NULL OR c.is_active=1)',
        [line.productId],
      );
      if (products.length != 1) {
        throw const QuickSalesValidationException(
          'Uno de los productos ya no está activo.',
        );
      }
      final amount = _int(
        BigInt.from(quantity) * BigInt.from(price),
        'Total de línea',
      );
      final parts = line.isSplit
          ? line.paymentParts
          : [QuickLinePaymentPart(line.paymentOptionId ?? '', amount)];
      if (parts.fold(
            BigInt.zero,
            (sum, p) => sum + BigInt.from(p.amountMinor),
          ) !=
          BigInt.from(amount)) {
        throw const QuickSalesValidationException(
          'La suma del reparto debe coincidir con el total de la línea.',
        );
      }
      final physical = <String, Object?>{
        'lineId': line.id,
        'productId': line.productId,
        'productName': products.single['name'],
        'quantity': quantity,
        'unitPriceMinor': price,
        'totalMinor': amount,
      };
      lines.add(physical);
      total += BigInt.from(amount);
      for (var partIndex = 0; partIndex < parts.length; partIndex++) {
        final part = parts[partIndex];
        _int(BigInt.from(part.amountMinor), 'Importe de pago');
        final isCredit = part.paymentOptionId == QuickPaymentOption.creditId;
        final option = isCredit
            ? _creditFact()
            : await _optionFact(txn, part.paymentOptionId);
        if (isCredit) credit += BigInt.from(part.amountMinor);
        tenders.add({
          ...physical,
          'quantity': partIndex == 0 ? quantity : 0,
          'totalMinor': part.amountMinor,
          'lineSequence': sequence,
          'partIndex': partIndex,
          'isCredit': isCredit,
          ...option,
        });
      }
    }
    final totalMinor = _int(total, 'Total de venta'),
        creditMinor = _int(credit, 'Total de deuda');
    if (totalMinor <= 0) {
      throw const QuickSalesValidationException(
        'El total de venta debe ser positivo.',
      );
    }
    final customer = creditMinor > 0
        ? account.customerName.trim()
        : 'Consumidor final';
    if (creditMinor > 0) {
      if (account.debtorId == null || customer.isEmpty) {
        throw const QuickSalesValidationException(
          'Asigna la cuenta a una persona registrada en Deudores.',
        );
      }
      final person = await txn.query(
        'debtors',
        where: 'id=? AND is_active=1',
        whereArgs: [account.debtorId],
      );
      if (customer.isEmpty ||
          person.length != 1 ||
          person.single['name'] != customer) {
        throw const QuickSalesValidationException(
          'Asigna la cuenta a una persona registrada en Deudores.',
        );
      }
      await _checkCreditCapacity(txn, credit);
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final row = <String, Object?>{
      'command_id': commandId,
      'account_id': account.id,
      'account_revision': account.revision,
      'canonical_payload': jsonEncode({
        'version': 4,
        'profileId': profile.profileId,
        'currency': profile.currencyCode,
        'scale': profile.moneyScale,
        'label': account.label,
        'occurredAtUtc': occurred.toIso8601String(),
        'totalMinor': totalMinor,
        'creditMinor': creditMinor,
        'paidMinor': _int(total - credit, 'Total pagado'),
        'customerName': customer,
        'debtorId': creditMinor > 0 ? account.debtorId : null,
        'lines': lines,
        'tenders': tenders,
      }),
      'occurred_at_utc': occurred.toIso8601String(),
      'prepared_at_utc': now,
      'status': 'prepared',
      'sale_command_id': InventoryIds.next(),
      'collection_command_id': InventoryIds.next(),
      'legacy_draft_id': InventoryIds.next(),
    };
    await txn.insert('quick_sale_requests', row);
    await txn.update(
      'quick_sales_accounts',
      {'status': 'prepared', 'updated_at_utc': now},
      where: 'id=?',
      whereArgs: [account.id],
    );
    return _prepared(row);
  }

  Future<void> _reject(String id, String reason) =>
      _database.database.transaction((txn) async {
        if ((await txn.query(
          'command_log',
          where: 'id=?',
          whereArgs: [id],
        )).isNotEmpty) {
          return;
        }
        await txn.update(
          'quick_sale_requests',
          {'status': 'rejected', 'rejection_reason': reason},
          where: "command_id=? AND status='prepared'",
          whereArgs: [id],
        );
      }, exclusive: true);

  @override
  Future<void> discardRejected(String commandId) =>
      _database.database.transaction((txn) async {
        _id(commandId);
        final rows = await txn.query(
          'quick_sale_requests',
          where: 'command_id=?',
          whereArgs: [commandId],
        );
        if (rows.isEmpty) {
          throw const QuickSalesValidationException(
            'La venta pendiente no existe.',
          );
        }
        final row = rows.single;
        if (row['status'] == 'cancelled') return;
        if (row['status'] != 'rejected' ||
            (await txn.query(
              'command_log',
              where: 'id=?',
              whereArgs: [commandId],
            )).isNotEmpty) {
          throw const QuickSalesValidationException(
            'Solo se libera una venta rechazada sin operación registrada.',
          );
        }
        await txn.update(
          'quick_sale_requests',
          {'status': 'cancelled'},
          where: 'command_id=?',
          whereArgs: [commandId],
        );
        await txn.update(
          'quick_sales_accounts',
          {
            'status': 'open',
            'revision': _int(
              BigInt.from(row['account_revision'] as int) + BigInt.one,
              'Revisión',
            ),
            'updated_at_utc': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'id=?',
          whereArgs: [row['account_id']],
        );
      }, exclusive: true);

  static Future<List<QuickPaymentOption>> _options(DatabaseExecutor txn) async {
    final rows = await txn.rawQuery(
      '''SELECT o.*, (o.is_active=1 AND c.is_active=1 AND l.is_active=1 AND l.class='asset' AND l.role='cash' AND m.is_active=1) available FROM quick_payment_options o JOIN cash_accounts c ON c.id=o.cash_account_id JOIN ledger_accounts l ON l.id=c.ledger_account_id JOIN payment_methods m ON m.id=o.payment_method_id ORDER BY o.label COLLATE NOCASE,o.id''',
    );
    return rows
        .map(
          (r) => QuickPaymentOption(
            id: r['id'] as String,
            label: r['label'] as String,
            cashAccountId: r['cash_account_id'] as String,
            paymentMethodId: r['payment_method_id'] as String,
            isActive: r['available'] == 1,
          ),
        )
        .toList()
      ..add(
        const QuickPaymentOption(
          id: QuickPaymentOption.creditId,
          label: 'Deudas',
          cashAccountId: '',
          paymentMethodId: '',
          isCredit: true,
        ),
      );
  }

  static Map<String, Object?> _creditFact() => {
    'paymentOptionId': QuickPaymentOption.creditId,
    'paymentOptionLabel': 'Deudas',
    'cashAccountId': null,
    'paymentMethodId': null,
    'cashAccountName': null,
    'cashAccountKind': null,
    'paymentMethodCode': null,
    'paymentMethodName': null,
  };

  static Future<Map<String, Object?>> _optionFact(
    DatabaseExecutor txn,
    String id,
  ) async {
    final rows = await txn.rawQuery(
      '''SELECT o.*,c.name account_name,c.kind account_kind,m.code method_code,m.name method_name FROM quick_payment_options o JOIN cash_accounts c ON c.id=o.cash_account_id JOIN ledger_accounts l ON l.id=c.ledger_account_id JOIN payment_methods m ON m.id=o.payment_method_id WHERE o.id=? AND o.is_active=1 AND c.is_active=1 AND l.is_active=1 AND l.class='asset' AND l.role='cash' AND m.is_active=1''',
      [id],
    );
    if (rows.length != 1) {
      throw const QuickSalesValidationException(
        'La forma de pago no está disponible.',
      );
    }
    final row = rows.single;
    return {
      'paymentOptionId': row['id'],
      'paymentOptionLabel': row['label'],
      'cashAccountId': row['cash_account_id'],
      'paymentMethodId': row['payment_method_id'],
      'cashAccountName': row['account_name'],
      'cashAccountKind': row['account_kind'],
      'paymentMethodCode': row['method_code'],
      'paymentMethodName': row['method_name'],
    };
  }

  /// The dashboard includes ordinary receivables and the aggregate legacy
  /// opening. Check the final residual, rather than gross temporary balances
  /// between the atomic sale and collection child documents.
  static Future<void> _checkCreditCapacity(
    DatabaseExecutor txn,
    BigInt additionalCredit,
  ) async {
    final receivables = await txn.rawQuery('''
SELECT r.id,r.initial_minor FROM all_customer_receivables r
JOIN business_documents d ON d.id=r.origin_document_id AND d.status='posted'
JOIN journal_entries e ON e.document_id=d.id AND e.status='posted'
''');
    final settlements = await txn.rawQuery('''
SELECT s.receivable_id,s.amount_minor FROM all_receivable_settlements s
JOIN business_documents d ON d.id=s.collection_id AND d.status='posted'
JOIN journal_entries e ON e.document_id=d.id AND e.status='posted'
''');
    final legacy = await txn.rawQuery('''
SELECT line.debit_minor-line.credit_minor receivables_minor FROM journal_lines line
JOIN journal_entries entry ON entry.id=line.entry_id
JOIN business_documents d ON d.id=entry.document_id AND d.status='posted'
JOIN journal_entries e ON e.document_id=d.id AND e.status='posted'
WHERE line.account_id='system:legacy-customer-receivables'
''');
    final collected = <String, BigInt>{};
    for (final row in settlements) {
      final id = row['receivable_id'] as String;
      collected[id] =
          (collected[id] ?? BigInt.zero) +
          BigInt.from(row['amount_minor'] as int);
    }
    var total = additionalCredit;
    for (final row in receivables) {
      final remaining =
          BigInt.from(row['initial_minor'] as int) -
          (collected[row['id']] ?? BigInt.zero);
      _int(remaining, 'Saldo por cobrar');
      total += remaining;
    }
    for (final row in legacy) {
      total += BigInt.from(row['receivables_minor'] as int);
    }
    _int(total, 'Deudas de clientes');
  }

  static Future<void> _unusedCommand(DatabaseExecutor txn, String id) async {
    if ((await txn.query(
      'paid_purchase_requests',
      where: 'command_id=? OR purchase_command_id=? OR payment_command_id=?',
      whereArgs: [id, id, id],
    )).isNotEmpty) {
      throw const QuickSalesValidationException(
        'El identificador está reservado por un ingreso de productos.',
      );
    }
    for (final table in [
      'command_log',
      'sale_confirmations',
      'collection_requests',
      'supplier_payment_requests',
      'treasury_operation_requests',
    ]) {
      if ((await txn.query(
        table,
        where: '${table == 'command_log' ? 'id' : 'command_id'}=?',
        whereArgs: [id],
      )).isNotEmpty) {
        throw const QuickSalesValidationException(
          'El identificador ya corresponde a otra operación.',
        );
      }
    }
    if ((await txn.query(
      'quick_sale_requests',
      where: 'command_id=? OR sale_command_id=? OR collection_command_id=?',
      whereArgs: [id, id, id],
    )).isNotEmpty) {
      throw const QuickSalesValidationException(
        'El identificador está reservado por otra venta rápida.',
      );
    }
  }

  static Future<BusinessProfile> _profile(DatabaseExecutor txn) async {
    final rows = await txn.query('app_profile');
    if (rows.length != 1) {
      throw const QuickSalesValidationException(
        'Configura el espacio de trabajo primero.',
      );
    }
    final profile = BusinessProfile.fromRow(rows.single);
    if (profile.timezone != 'America/Bogota') {
      throw const QuickSalesValidationException(
        'Las ventas requieren la zona horaria America/Bogota.',
      );
    }
    return profile;
  }

  static Future<QuickSaleAccount> _account(
    DatabaseExecutor txn,
    Map<String, Object?> row,
  ) async {
    final lines = await txn.query(
      'quick_sales_lines',
      where: 'account_id=?',
      whereArgs: [row['id']],
      orderBy: 'sequence',
    );
    return QuickSaleAccount(
      id: row['id'] as String,
      label: row['label'] as String,
      customerName: row['customer_name'] as String? ?? '',
      debtorId: row['debtor_id'] as String?,
      paymentMode: row['payment_mode'] as String,
      accountPaymentOptionId: row['account_payment_option_id'] as String?,
      paymentSplitBasis: row['payment_split_basis'] as String,
      revision: row['revision'] as int,
      status: row['status'] as String,
      updatedAtUtc: DateTime.parse(row['updated_at_utc'] as String).toUtc(),
      createdAtUtc: row['created_at_utc'] == null
          ? null
          : DateTime.parse(row['created_at_utc'] as String).toUtc(),
      confirmedDocumentId: row['confirmed_document_id'] as String?,
      lines: lines
          .map(
            (l) => QuickSaleLine(
              id: l['id'] as String,
              productId: l['product_id'] as String?,
              quantityText: l['quantity_text'] as String,
              unitPriceMinor: l['unit_price_minor'] as int?,
              paymentParts: List.unmodifiable(
                (jsonDecode(l['payment_split_json'] as String) as List).map(
                  (p) => QuickLinePaymentPart(
                    p['paymentOptionId'] as String,
                    p['amountMinor'] as int,
                  ),
                ),
              ),
              paymentOptionId: l['is_credit'] == 1
                  ? QuickPaymentOption.creditId
                  : l['payment_option_id'] as String?,
            ),
          )
          .toList(),
    );
  }

  static PreparedQuickSale _prepared(Map<String, Object?> row) {
    final p =
        jsonDecode(row['canonical_payload'] as String) as Map<String, dynamic>;
    return PreparedQuickSale(
      commandId: row['command_id'] as String,
      accountId: row['account_id'] as String,
      accountRevision: row['account_revision'] as int,
      label: p['label'] as String,
      totalMinor: p['totalMinor'] as int,
      occurredAtUtc: DateTime.parse(row['occurred_at_utc'] as String).toUtc(),
      preparedAtUtc: DateTime.parse(row['prepared_at_utc'] as String).toUtc(),
      status: row['status'] as String,
      rejectionReason: row['rejection_reason'] as String?,
      creditMinor: p['creditMinor'] as int? ?? 0,
      customerName: p['customerName'] as String? ?? '',
      debtorId: p['debtorId'] as String?,
    );
  }

  static QuickSaleResult _prior(Map<String, Object?> row, String canonical) {
    final response =
        jsonDecode(row['response_json'] as String) as Map<String, dynamic>;
    if (row['command_type'] != 'quick_sale' ||
        row['payload_hash'] != DatabaseSchema.checksum(canonical) ||
        response['canonicalPayload'] != canonical ||
        row['response_version'] != 1) {
      throw const QuickSalesValidationException(
        'La respuesta guardada pertenece a otra operación.',
      );
    }
    final r = response['result'] as Map<String, dynamic>;
    return QuickSaleResult(
      commandId: r['commandId'] as String,
      saleDocumentId: r['saleDocumentId'] as String,
      collectionDocumentId: r['collectionDocumentId'] as String?,
      totalMinor: r['totalMinor'] as int,
      totalCostMinor: r['totalCostMinor'] as int,
      creditMinor: r['creditMinor'] as int? ?? 0,
      customerName: r['customerName'] as String? ?? '',
      debtorId: r['debtorId'] as String?,
    );
  }

  static bool _sameLines(List<QuickSaleLine> a, List<QuickSaleLine> b) =>
      a.length == b.length &&
      List.generate(
        a.length,
        (i) =>
            a[i].id == b[i].id &&
            a[i].productId == b[i].productId &&
            a[i].quantityText == b[i].quantityText &&
            a[i].unitPriceMinor == b[i].unitPriceMinor &&
            a[i].paymentOptionId == b[i].paymentOptionId &&
            jsonEncode(a[i].paymentParts.map((p) => p.toJson()).toList()) ==
                jsonEncode(b[i].paymentParts.map((p) => p.toJson()).toList()),
      ).every((v) => v);
  static int _int(BigInt value, String label) {
    if (value < BigInt.zero || value > Money.maxMinorUnits) {
      throw QuickSalesValidationException('$label fuera del rango permitido.');
    }
    return value.toInt();
  }

  static void _id(String id) {
    if (id.trim().isEmpty || id.length > 160) {
      throw const QuickSalesValidationException(
        'El identificador no es válido.',
      );
    }
  }

  static String _date(DateTime at) {
    if (!at.isUtc || at.year < 2000 || at.year > 9999) {
      throw const QuickSalesValidationException(
        'La fecha de venta no es válida.',
      );
    }
    final local = at.subtract(const Duration(hours: 5));
    return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }
}
