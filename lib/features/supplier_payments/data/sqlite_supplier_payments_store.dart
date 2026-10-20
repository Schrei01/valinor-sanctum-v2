import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/domain/money.dart';
import '../../../core/infrastructure/database/app_database.dart';
import '../../../core/infrastructure/database/schema.dart';
import '../../inventory/domain/inventory_store.dart';
import '../../workspace/domain/business_profile.dart';
import '../../collections/domain/collections_store.dart';
import '../domain/supplier_payments_store.dart';

/// Payments settle an existing supplier obligation. They never create revenue,
/// inventory movements, cost allocations, or an opening money balance.
class SqliteSupplierPaymentsStore implements SupplierPaymentsStore {
  SqliteSupplierPaymentsStore(this._database, {this.synthetic = false});
  final AppDatabase _database;
  final bool synthetic;
  static const _operator = 'system:local-operator';

  @override
  Future<SupplierPaymentsSnapshot> load() =>
      _database.database.transaction((txn) async {
        await _profile(txn);
        final balances = await _balances(txn);
        final accounts = await txn.query(
          'cash_accounts',
          orderBy: 'name COLLATE NOCASE, id',
        );
        final methods = await txn.query(
          'payment_methods',
          orderBy: 'name COLLATE NOCASE, id',
        );
        final payables = await _payables(txn);
        final requests = await txn.query(
          'supplier_payment_requests',
          where: "status IN ('prepared', 'rejected')",
          orderBy: 'prepared_at_utc, command_id',
        );
        final rows = await txn.rawQuery('''
SELECT c.*, d.command_id FROM supplier_payments c
JOIN business_documents d ON d.id = c.document_id AND d.status = 'posted'
JOIN journal_entries e ON e.document_id = d.id AND e.status = 'posted'
ORDER BY c.paid_at_utc DESC, c.document_id
''');
        final payments = <ConfirmedSupplierPayment>[];
        for (final row in rows) {
          final parts = await txn.query(
            'supplier_payment_parts',
            where: 'supplier_payment_id = ?',
            whereArgs: [row['document_id']],
            orderBy: 'sequence',
          );
          payments.add(
            ConfirmedSupplierPayment(
              documentId: row['document_id'] as String,
              commandId: row['command_id'] as String,
              payableId: row['payable_id'] as String,
              label: row['purchase_label_snapshot'] as String,
              supplierName: row['supplier_name_snapshot'] as String,
              paidAtUtc: DateTime.parse(row['paid_at_utc'] as String).toUtc(),
              totalMinor: row['total_minor'] as int,
              remainingMinor: row['remaining_minor'] as int,
              parts: parts.map(_storedPart).toList(),
            ),
          );
        }
        return SupplierPaymentsSnapshot(
          accounts: accounts
              .map(
                (row) => CollectionAccount(
                  id: row['id'] as String,
                  name: row['name'] as String,
                  kind: row['kind'] as String,
                  isAvailable: row['is_available'] == 1,
                  isActive: row['is_active'] == 1,
                  balanceMinor: _signedInt64(
                    balances[row['ledger_account_id']] ?? BigInt.zero,
                    'Saldo registrado',
                  ),
                ),
              )
              .toList(),
          methods: methods
              .map(
                (row) => CollectionMethod(
                  id: row['id'] as String,
                  code: row['code'] as String,
                  name: row['name'] as String,
                  isActive: row['is_active'] == 1,
                ),
              )
              .toList(),
          payables: payables,
          pendingPayments: requests.map(_prepared).toList(),
          payments: payments,
        );
      });

  @override
  Future<PreparedSupplierPayment> preparePayment(
    SupplierPaymentCommand command,
  ) async {
    _id(command.commandId);
    _id(command.payableId);
    _businessDate(command.occurredAtUtc);
    final inputs = _inputs(command.parts);
    return _database.database.transaction((txn) async {
      final profile = await _profile(txn);
      final prior = await txn.query(
        'supplier_payment_requests',
        where: 'command_id = ?',
        whereArgs: [command.commandId],
      );
      if (prior.isNotEmpty) {
        final old = _prepared(prior.single);
        if (old.payableId != command.payableId ||
            old.occurredAtUtc.microsecondsSinceEpoch !=
                command.occurredAtUtc.microsecondsSinceEpoch ||
            !_sameInputs(old.parts, inputs)) {
          throw const SupplierPaymentsValidationException(
            'El identificador ya corresponde a otro pago.',
          );
        }
        return old;
      }
      if ((await txn.query(
            'command_log',
            where: 'id = ?',
            whereArgs: [command.commandId],
          )).isNotEmpty ||
          (await txn.query(
            'sale_confirmations',
            where: 'command_id = ?',
            whereArgs: [command.commandId],
          )).isNotEmpty ||
          (await txn.query(
            'collection_requests',
            where: 'command_id = ?',
            whereArgs: [command.commandId],
          )).isNotEmpty) {
        throw const SupplierPaymentsValidationException(
          'El identificador ya corresponde a otro comando.',
        );
      }
      if ((await txn.rawQuery(
        'SELECT command_id FROM quick_sale_requests WHERE command_id = ? OR sale_command_id = ? OR collection_command_id = ?',
        [command.commandId, command.commandId, command.commandId],
      )).isNotEmpty) {
        throw const SupplierPaymentsValidationException(
          'El identificador ya corresponde a una venta de mostrador.',
        );
      }
      final payable = await _payable(txn, command.payableId);
      final parts = <SupplierPaymentPart>[];
      for (final input in inputs) {
        final account = await _activeAccount(txn, input.cashAccountId);
        final method = await _activeMethod(txn, input.paymentMethodId);
        parts.add(
          SupplierPaymentPart(
            cashAccountId: input.cashAccountId,
            paymentMethodId: input.paymentMethodId,
            cashAccountName: account['name'] as String,
            cashAccountKind: account['kind'] as String,
            paymentMethodCode: method['code'] as String,
            paymentMethodName: method['name'] as String,
            amountMinor: input.amountMinor,
          ),
        );
      }
      await _validateFundsAndTiming(txn, parts, command.occurredAtUtc);
      final total = _total(parts);
      await _validateTimingAndAmount(
        txn,
        payable,
        command.occurredAtUtc,
        total,
      );
      final canonical = jsonEncode({
        'version': 1,
        'profileId': profile.profileId,
        'currency': profile.currencyCode,
        'scale': profile.moneyScale,
        'payableId': payable.payableId,
        'purchaseDocumentId': payable.purchaseDocumentId,
        'label': payable.label,
        'supplierName': payable.supplierName,
        'occurredAtUtc': command.occurredAtUtc.toIso8601String(),
        'totalMinor': total,
        'parts': parts.map(_partPayload).toList(),
      });
      final preparedAt = DateTime.now().toUtc();
      final row = <String, Object?>{
        'command_id': command.commandId,
        'canonical_payload': canonical,
        'payable_id': command.payableId,
        'occurred_at_utc': command.occurredAtUtc.toIso8601String(),
        'prepared_at_utc': preparedAt.toIso8601String(),
        'status': 'prepared',
      };
      await txn.insert('supplier_payment_requests', row);
      return _prepared(row);
    }, exclusive: true);
  }

  @override
  Future<SupplierPaymentResult> confirmPrepared(String commandId) async {
    _id(commandId);
    try {
      return await _database.database.transaction(
        (txn) => _confirm(txn, commandId),
        exclusive: true,
      );
    } on SupplierPaymentsValidationException {
      // Only a known precommit rejection becomes discardable. An I/O failure
      // leaves the durable request prepared, including after an uncertain reply.
      await _database.database.transaction((txn) async {
        final logged = await txn.query(
          'command_log',
          where: 'id = ?',
          whereArgs: [commandId],
        );
        if (logged.isEmpty) {
          await txn.update(
            'supplier_payment_requests',
            {
              'status': 'rejected',
              'rejection_reason': 'El pago fue rechazado sin registrar dinero.',
            },
            where: "command_id = ? AND status = 'prepared'",
            whereArgs: [commandId],
          );
        }
      }, exclusive: true);
      rethrow;
    }
  }

  Future<SupplierPaymentResult> _confirm(
    Transaction txn,
    String commandId,
  ) async {
    final rows = await txn.query(
      'supplier_payment_requests',
      where: 'command_id = ?',
      whereArgs: [commandId],
    );
    if (rows.isEmpty) {
      throw const SupplierPaymentsValidationException(
        'No existe el pago pendiente.',
      );
    }
    final row = rows.single;
    final canonical = row['canonical_payload'] as String;
    final logged = await txn.query(
      'command_log',
      where: 'id = ?',
      whereArgs: [commandId],
    );
    if (logged.isNotEmpty) return _priorResult(logged.single, canonical);
    if (row['status'] != 'prepared') {
      throw const SupplierPaymentsValidationException(
        'El pago fue rechazado o descartado. Prepara uno nuevo.',
      );
    }
    final prepared = _prepared(row);
    final payload = jsonDecode(canonical) as Map<String, dynamic>;
    final profile = await _profile(txn);
    final payable = await _payable(txn, prepared.payableId);
    if (payload['version'] != 1 ||
        payload['profileId'] != profile.profileId ||
        payload['currency'] != profile.currencyCode ||
        payload['scale'] != profile.moneyScale ||
        payload['payableId'] != row['payable_id'] ||
        payload['occurredAtUtc'] != row['occurred_at_utc'] ||
        payload['purchaseDocumentId'] != payable.purchaseDocumentId ||
        prepared.label != payable.label ||
        prepared.supplierName != payable.supplierName ||
        prepared.totalMinor != _total(prepared.parts)) {
      throw const SupplierPaymentsValidationException(
        'El pago no coincide con la solicitud guardada.',
      );
    }
    _businessDate(prepared.occurredAtUtc);
    _inputs(
      prepared.parts
          .map(
            (part) => SupplierPaymentPartInput(
              cashAccountId: part.cashAccountId,
              paymentMethodId: part.paymentMethodId,
              amountMinor: part.amountMinor,
            ),
          )
          .toList(),
    );
    await _validateTimingAndAmount(
      txn,
      payable,
      prepared.occurredAtUtc,
      prepared.totalMinor,
    );
    await _validateFundsAndTiming(txn, prepared.parts, prepared.occurredAtUtc);
    final credits = <String, BigInt>{};
    for (final part in prepared.parts) {
      final account = await _activeAccount(txn, part.cashAccountId);
      final method = await _activeMethod(txn, part.paymentMethodId);
      if (account['kind'] != part.cashAccountKind ||
          method['code'] != part.paymentMethodCode) {
        throw const SupplierPaymentsValidationException(
          'La identidad de una cuenta o medio cambió.',
        );
      }
      final ledger = account['ledger_account_id'] as String;
      credits[ledger] =
          (credits[ledger] ?? BigInt.zero) + BigInt.from(part.amountMinor);
    }
    final balances = await _balances(txn);
    for (final credit in credits.entries) {
      _nonnegativeInt64(
        (balances[credit.key] ?? BigInt.zero) - credit.value,
        'Saldo disponible de la cuenta',
      );
      _positiveInt64(credit.value, 'Salida de la cuenta');
    }
    final obligation = (await txn.query(
      'obligations',
      where: 'id = ?',
      whereArgs: [payable.payableId],
    )).single;
    final control = obligation['control_account_id'] as String;
    final controlRows = await txn.query(
      'ledger_accounts',
      where: 'id = ?',
      whereArgs: [control],
    );
    if (controlRows.length != 1 ||
        controlRows.single['role'] != 'supplier_payable' ||
        controlRows.single['class'] != 'liability' ||
        controlRows.single['is_active'] != 1) {
      throw const SupplierPaymentsValidationException(
        'La cuenta de proveedores no está disponible.',
      );
    }
    final now = DateTime.now().toUtc().toIso8601String();
    await _operatorRow(txn, now);
    final document = InventoryIds.next();
    final entry = InventoryIds.next();
    final result = SupplierPaymentResult(
      documentId: document,
      commandId: commandId,
      payableId: payable.payableId,
      totalMinor: prepared.totalMinor,
      remainingMinor: payable.remainingMinor - prepared.totalMinor,
    );
    await txn.insert('command_log', {
      'id': commandId,
      'command_type': 'pay_supplier',
      'payload_hash': DatabaseSchema.checksum(canonical),
      'actor_id': _operator,
      'response_json': jsonEncode({
        'canonicalPayload': canonical,
        'result': {
          'documentId': document,
          'commandId': commandId,
          'payableId': result.payableId,
          'totalMinor': result.totalMinor,
          'remainingMinor': result.remainingMinor,
        },
      }),
      'response_version': 1,
      'committed_at_utc': now,
      'authorization_policy_version': 'development-single-user-v1',
    });
    await txn.insert('business_documents', {
      'id': document,
      'command_id': commandId,
      'command_sequence': 0,
      'profile_id': profile.profileId,
      'actor_id': _operator,
      'type': 'supplier_payment',
      'status': 'draft',
      'occurred_at_utc': prepared.occurredAtUtc.toIso8601String(),
      'business_date': _businessDate(prepared.occurredAtUtc),
      'recorded_at_utc': now,
      'source_kind': synthetic ? 'synthetic' : 'native',
      'date_quality': 'documented',
    });
    await txn.insert('supplier_payments', {
      'document_id': document,
      'payable_id': payable.payableId,
      'purchase_label_snapshot': prepared.label,
      'supplier_name_snapshot': prepared.supplierName,
      'paid_at_utc': prepared.occurredAtUtc.toIso8601String(),
      'total_minor': prepared.totalMinor,
      'remaining_minor': result.remainingMinor,
    });
    await txn.insert('journal_entries', {
      'id': entry,
      'document_id': document,
      'status': 'draft',
      'cost_completeness': 'not_applicable',
    });
    for (var index = 0; index < prepared.parts.length; index++) {
      final part = prepared.parts[index];
      await txn.insert('supplier_payment_parts', {
        'id': InventoryIds.next(),
        'supplier_payment_id': document,
        'sequence': index,
        'cash_account_id': part.cashAccountId,
        'payment_method_id': part.paymentMethodId,
        'cash_account_name_snapshot': part.cashAccountName,
        'cash_account_kind_snapshot': part.cashAccountKind,
        'payment_method_code_snapshot': part.paymentMethodCode,
        'payment_method_name_snapshot': part.paymentMethodName,
        'amount_minor': part.amountMinor,
      });
    }
    await txn.insert('payable_settlements', {
      'id': InventoryIds.next(),
      'payable_id': payable.payableId,
      'supplier_payment_id': document,
      'amount_minor': prepared.totalMinor,
    });
    var sequence = 0;
    for (final credit in credits.entries) {
      await txn.insert('journal_lines', {
        'id': InventoryIds.next(),
        'entry_id': entry,
        'sequence': sequence++,
        'account_id': credit.key,
        'debit_minor': 0,
        'credit_minor': _positiveInt64(credit.value, 'Salida de cuenta'),
      });
    }
    await txn.insert('journal_lines', {
      'id': InventoryIds.next(),
      'entry_id': entry,
      'sequence': sequence,
      'account_id': control,
      'debit_minor': prepared.totalMinor,
      'credit_minor': 0,
    });
    await txn.update(
      'business_documents',
      {'status': 'posted'},
      where: 'id = ?',
      whereArgs: [document],
    );
    await txn.update(
      'journal_entries',
      {'status': 'posted', 'posted_at_utc': now},
      where: 'id = ?',
      whereArgs: [entry],
    );
    await txn.update(
      'supplier_payment_requests',
      {'status': 'confirmed'},
      where: 'command_id = ?',
      whereArgs: [commandId],
    );
    return result;
  }

  @override
  Future<void> discardRejected(String commandId) async {
    _id(commandId);
    await _database.database.transaction((txn) async {
      final rows = await txn.query(
        'supplier_payment_requests',
        where: 'command_id = ?',
        whereArgs: [commandId],
      );
      if (rows.isEmpty) {
        throw const SupplierPaymentsValidationException('El pago no existe.');
      }
      if (rows.single['status'] == 'cancelled') return;
      if (rows.single['status'] != 'rejected' ||
          (await txn.query(
            'command_log',
            where: 'id = ?',
            whereArgs: [commandId],
          )).isNotEmpty) {
        throw const SupplierPaymentsValidationException(
          'Primero resuelve el pago pendiente. Un pago registrado no se descarta.',
        );
      }
      await txn.update(
        'supplier_payment_requests',
        {'status': 'cancelled'},
        where: 'command_id = ?',
        whereArgs: [commandId],
      );
    }, exclusive: true);
  }

  static Future<List<PayableSummary>> _payables(DatabaseExecutor txn) async {
    final rows = await txn.rawQuery('''
SELECT r.*, COALESCE(s.supplier_reference, s.document_id) label_snapshot, s.supplier_name_snapshot FROM obligations r
JOIN purchases s ON s.document_id = r.origin_document_id
JOIN business_documents d ON d.id = s.document_id AND d.status = 'posted'
JOIN journal_entries e ON e.document_id = d.id AND e.status = 'posted'
ORDER BY r.issued_at_utc DESC, r.id
''');
    final settlements = await txn.rawQuery('''
SELECT r.payable_id, r.amount_minor FROM payable_settlements r
JOIN business_documents d ON d.id = r.supplier_payment_id AND d.status = 'posted'
JOIN journal_entries e ON e.document_id = d.id AND e.status = 'posted'
''');
    final totals = <String, BigInt>{};
    for (final row in settlements) {
      final id = row['payable_id'] as String;
      totals[id] =
          (totals[id] ?? BigInt.zero) + BigInt.from(row['amount_minor'] as int);
    }
    return rows.map((row) {
      final paid = totals[row['id']] ?? BigInt.zero;
      final initial = row['initial_minor'] as int;
      return PayableSummary(
        payableId: row['id'] as String,
        purchaseDocumentId: row['origin_document_id'] as String,
        label: row['label_snapshot'] as String,
        supplierName: row['supplier_name_snapshot'] as String,
        issuedAtUtc: DateTime.parse(row['issued_at_utc'] as String).toUtc(),
        dueDate: row['due_date'] as String,
        initialMinor: initial,
        paidMinor: _nonnegativeInt64(paid, 'Total pagado'),
        remainingMinor: _nonnegativeInt64(
          BigInt.from(initial) - paid,
          'Saldo por pagar',
        ),
      );
    }).toList();
  }

  static Future<PayableSummary> _payable(
    DatabaseExecutor txn,
    String id,
  ) async {
    final rows = (await _payables(txn)).where((row) => row.payableId == id);
    if (rows.length != 1) {
      throw const SupplierPaymentsValidationException(
        'La cuenta por pagar no existe o no está confirmada.',
      );
    }
    return rows.single;
  }

  static Future<void> _validateTimingAndAmount(
    DatabaseExecutor txn,
    PayableSummary payable,
    DateTime occurredAt,
    int total,
  ) async {
    if (total > payable.remainingMinor) {
      throw const SupplierPaymentsValidationException(
        'El pago excede el saldo pendiente. Actualiza la vista.',
      );
    }
    final instant = occurredAt.microsecondsSinceEpoch;
    if (instant < payable.issuedAtUtc.microsecondsSinceEpoch) {
      throw const SupplierPaymentsValidationException(
        'El pago no puede ser anterior a la compra.',
      );
    }
    final prior = await txn.rawQuery(
      '''
SELECT c.paid_at_utc FROM supplier_payments c
JOIN business_documents d ON d.id = c.document_id AND d.status = 'posted'
JOIN journal_entries e ON e.document_id = d.id AND e.status = 'posted'
WHERE c.payable_id = ?
''',
      [payable.payableId],
    );
    if (prior.any(
      (row) =>
          DateTime.parse(row['paid_at_utc'] as String).microsecondsSinceEpoch >
          instant,
    )) {
      throw const SupplierPaymentsValidationException(
        'El pago no puede ser anterior a otro pago de esta compra.',
      );
    }
  }

  static Future<void> _validateFundsAndTiming(
    DatabaseExecutor txn,
    List<SupplierPaymentPart> parts,
    DateTime occurredAt,
  ) async {
    final amounts = <String, BigInt>{};
    for (final part in parts) {
      final account = await _activeAccount(txn, part.cashAccountId);
      final ledger = account['ledger_account_id'] as String;
      amounts[ledger] =
          (amounts[ledger] ?? BigInt.zero) + BigInt.from(part.amountMinor);
    }
    final balances = await _balances(txn);
    for (final amount in amounts.entries) {
      if ((balances[amount.key] ?? BigInt.zero) < amount.value) {
        throw const SupplierPaymentsValidationException(
          'Saldo registrado insuficiente en una cuenta de origen. Actualiza la vista.',
        );
      }
      _positiveInt64(amount.value, 'Salida de la cuenta');
      final movements = await txn.rawQuery(
        """
SELECT d.occurred_at_utc FROM journal_lines l
JOIN journal_entries e ON e.id = l.entry_id AND e.status = 'posted'
JOIN business_documents d ON d.id = e.document_id AND d.status = 'posted'
WHERE l.account_id = ?
""",
        [amount.key],
      );
      if (movements.any(
        (row) =>
            DateTime.parse(
              row['occurred_at_utc'] as String,
            ).microsecondsSinceEpoch >
            occurredAt.microsecondsSinceEpoch,
      )) {
        throw const SupplierPaymentsValidationException(
          'El pago no puede ser anterior al último movimiento de su cuenta de origen.',
        );
      }
    }
  }

  static Future<Map<String, BigInt>> _balances(DatabaseExecutor txn) async {
    final rows = await txn.rawQuery('''
SELECT l.account_id, l.debit_minor, l.credit_minor FROM journal_lines l
JOIN ledger_accounts a ON a.id = l.account_id AND a.role = 'cash'
JOIN journal_entries e ON e.id = l.entry_id AND e.status = 'posted'
JOIN business_documents d ON d.id = e.document_id AND d.status = 'posted'
''');
    final result = <String, BigInt>{};
    for (final row in rows) {
      final account = row['account_id'] as String;
      result[account] =
          (result[account] ?? BigInt.zero) +
          BigInt.from(row['debit_minor'] as int) -
          BigInt.from(row['credit_minor'] as int);
    }
    return result;
  }

  static Future<Map<String, Object?>> _activeAccount(
    DatabaseExecutor txn,
    String id,
  ) async {
    final rows = await txn.rawQuery(
      '''
SELECT c.*, l.class ledger_class, l.role ledger_role, l.is_active ledger_active
FROM cash_accounts c JOIN ledger_accounts l ON l.id = c.ledger_account_id WHERE c.id = ?
''',
      [id],
    );
    if (rows.length != 1 ||
        rows.single['is_active'] != 1 ||
        rows.single['is_available'] != 1 ||
        rows.single['ledger_active'] != 1 ||
        rows.single['ledger_class'] != 'asset' ||
        rows.single['ledger_role'] != 'cash') {
      throw const SupplierPaymentsValidationException(
        'La cuenta de origen debe estar activa, disponible y ser monetaria.',
      );
    }
    return rows.single;
  }

  static Future<Map<String, Object?>> _activeMethod(
    DatabaseExecutor txn,
    String id,
  ) async {
    final rows = await txn.query(
      'payment_methods',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.length != 1 || rows.single['is_active'] != 1) {
      throw const SupplierPaymentsValidationException(
        'El medio de pago debe estar activo.',
      );
    }
    return rows.single;
  }

  static Future<BusinessProfile> _profile(DatabaseExecutor txn) async {
    final rows = await txn.query('app_profile', where: 'id = 1');
    if (rows.length != 1) {
      throw const SupplierPaymentsValidationException(
        'Configura el espacio de trabajo primero.',
      );
    }
    final profile = BusinessProfile.fromRow(rows.single);
    if (profile.timezone != 'America/Bogota') {
      throw const SupplierPaymentsValidationException(
        'Los pagos requieren la zona horaria America/Bogota.',
      );
    }
    return profile;
  }

  static Future<void> _operatorRow(DatabaseExecutor txn, String now) async {
    final rows = await txn.query(
      'actors',
      where: 'id = ?',
      whereArgs: [_operator],
    );
    if (rows.isEmpty) {
      await txn.insert('actors', {
        'id': _operator,
        'display_name': 'Operador local',
        'kind': 'system',
        'is_active': 1,
        'created_at_utc': now,
      });
    } else if (rows.single['kind'] != 'system' ||
        rows.single['is_active'] != 1) {
      throw const SupplierPaymentsValidationException(
        'El operador local no está disponible.',
      );
    }
  }

  static List<SupplierPaymentPartInput> _inputs(
    List<SupplierPaymentPartInput> input,
  ) {
    if (input.isEmpty || input.length > 100) {
      throw const SupplierPaymentsValidationException(
        'El pago requiere entre 1 y 100 partes.',
      );
    }
    final parts = input.toList()
      ..sort((a, b) {
        final account = a.cashAccountId.compareTo(b.cashAccountId);
        return account == 0
            ? a.paymentMethodId.compareTo(b.paymentMethodId)
            : account;
      });
    final seen = <String>{};
    var total = BigInt.zero;
    for (final part in parts) {
      _id(part.cashAccountId);
      _id(part.paymentMethodId);
      _positiveInt64(BigInt.from(part.amountMinor), 'Importe');
      total += BigInt.from(part.amountMinor);
      if (!seen.add('${part.cashAccountId}\u0000${part.paymentMethodId}')) {
        throw const SupplierPaymentsValidationException(
          'Combina los importes que usan la misma cuenta y medio.',
        );
      }
    }
    _positiveInt64(total, 'Total de pago');
    return parts;
  }

  static int _total(List<SupplierPaymentPart> parts) => _positiveInt64(
    parts.fold(BigInt.zero, (sum, part) => sum + BigInt.from(part.amountMinor)),
    'Total de pago',
  );
  static bool _sameInputs(
    List<SupplierPaymentPart> a,
    List<SupplierPaymentPartInput> b,
  ) =>
      a.length == b.length &&
      List.generate(
        a.length,
        (i) =>
            a[i].cashAccountId == b[i].cashAccountId &&
            a[i].paymentMethodId == b[i].paymentMethodId &&
            a[i].amountMinor == b[i].amountMinor,
      ).every((same) => same);
  static Map<String, Object> _partPayload(SupplierPaymentPart part) => {
    'cashAccountId': part.cashAccountId,
    'paymentMethodId': part.paymentMethodId,
    'cashAccountName': part.cashAccountName,
    'cashAccountKind': part.cashAccountKind,
    'paymentMethodCode': part.paymentMethodCode,
    'paymentMethodName': part.paymentMethodName,
    'amountMinor': part.amountMinor,
  };
  static SupplierPaymentPart _payloadPart(dynamic input) {
    final row = input as Map<String, dynamic>;
    return SupplierPaymentPart(
      cashAccountId: row['cashAccountId'] as String,
      paymentMethodId: row['paymentMethodId'] as String,
      cashAccountName: row['cashAccountName'] as String,
      cashAccountKind: row['cashAccountKind'] as String,
      paymentMethodCode: row['paymentMethodCode'] as String,
      paymentMethodName: row['paymentMethodName'] as String,
      amountMinor: row['amountMinor'] as int,
    );
  }

  static SupplierPaymentPart _storedPart(Map<String, Object?> row) =>
      SupplierPaymentPart(
        cashAccountId: row['cash_account_id'] as String,
        paymentMethodId: row['payment_method_id'] as String,
        cashAccountName: row['cash_account_name_snapshot'] as String,
        cashAccountKind: row['cash_account_kind_snapshot'] as String,
        paymentMethodCode: row['payment_method_code_snapshot'] as String,
        paymentMethodName: row['payment_method_name_snapshot'] as String,
        amountMinor: row['amount_minor'] as int,
      );
  static PreparedSupplierPayment _prepared(Map<String, Object?> row) {
    final payload =
        jsonDecode(row['canonical_payload'] as String) as Map<String, dynamic>;
    return PreparedSupplierPayment(
      commandId: row['command_id'] as String,
      payableId: row['payable_id'] as String,
      label: payload['label'] as String,
      supplierName: payload['supplierName'] as String,
      occurredAtUtc: DateTime.parse(row['occurred_at_utc'] as String).toUtc(),
      preparedAtUtc: DateTime.parse(row['prepared_at_utc'] as String).toUtc(),
      status: row['status'] as String,
      totalMinor: payload['totalMinor'] as int,
      parts: (payload['parts'] as List).map(_payloadPart).toList(),
    );
  }

  static SupplierPaymentResult _priorResult(
    Map<String, Object?> row,
    String canonical,
  ) {
    if (row['command_type'] != 'pay_supplier' ||
        row['response_version'] != 1 ||
        row['payload_hash'] != DatabaseSchema.checksum(canonical)) {
      throw const SupplierPaymentsValidationException(
        'El identificador ya corresponde a otro comando.',
      );
    }
    final stored =
        jsonDecode(row['response_json'] as String) as Map<String, dynamic>;
    if (stored['canonicalPayload'] != canonical) {
      throw const SupplierPaymentsValidationException(
        'El identificador ya corresponde a otro comando.',
      );
    }
    final result = stored['result'] as Map<String, dynamic>;
    return SupplierPaymentResult(
      documentId: result['documentId'] as String,
      commandId: result['commandId'] as String,
      payableId: result['payableId'] as String,
      totalMinor: result['totalMinor'] as int,
      remainingMinor: result['remainingMinor'] as int,
    );
  }

  static void _id(String value) {
    if (!RegExp(r'^[A-Za-z0-9:_-]{1,128}$').hasMatch(value)) {
      throw const SupplierPaymentsValidationException(
        'El identificador no es válido.',
      );
    }
  }

  static int _positiveInt64(BigInt value, String label) {
    if (value <= BigInt.zero || value > Money.maxMinorUnits) {
      throw SupplierPaymentsValidationException(
        '$label debe ser positivo y estar dentro de 64 bits.',
      );
    }
    return value.toInt();
  }

  static int _nonnegativeInt64(BigInt value, String label) {
    if (value < BigInt.zero || value > Money.maxMinorUnits) {
      throw SupplierPaymentsValidationException(
        '$label excede el rango entero positivo de 64 bits.',
      );
    }
    return value.toInt();
  }

  static int _signedInt64(BigInt value, String label) {
    if (value < Money.minMinorUnits || value > Money.maxMinorUnits) {
      throw SupplierPaymentsValidationException(
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
      throw const SupplierPaymentsValidationException(
        'La fecha del pago debe ser UTC y estar dentro del rango permitido.',
      );
    }
    return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }
}
