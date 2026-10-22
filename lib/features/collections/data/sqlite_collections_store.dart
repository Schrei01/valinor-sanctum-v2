import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/domain/money.dart';
import '../../../core/infrastructure/database/app_database.dart';
import '../../../core/infrastructure/database/schema.dart';
import '../../inventory/domain/inventory_store.dart';
import '../../workspace/domain/business_profile.dart';
import '../domain/collections_store.dart';

/// Receipts settle an existing sale obligation. They never create revenue,
/// inventory movements, cost allocations, or an opening money balance.
class SqliteCollectionsStore implements CollectionsStore {
  SqliteCollectionsStore(this._database, {this.synthetic = false});
  final AppDatabase _database;
  final bool synthetic;
  static const _operator = 'system:local-operator';

  @override
  Future<CollectionsSnapshot> load() =>
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
        final receivables = await _receivables(txn);
        final requests = await txn.query(
          'collection_requests',
          where: "status IN ('prepared', 'rejected')",
          orderBy: 'prepared_at_utc, command_id',
        );
        final rows = await txn.rawQuery('''
SELECT c.*, d.command_id FROM collections c
JOIN business_documents d ON d.id = c.document_id AND d.status = 'posted'
JOIN journal_entries e ON e.document_id = d.id AND e.status = 'posted'
ORDER BY c.collected_at_utc DESC, c.document_id
''');
        final collections = <ConfirmedCollection>[];
        for (final row in rows) {
          final parts = await txn.query(
            'collection_parts',
            where: 'collection_id = ?',
            whereArgs: [row['document_id']],
            orderBy: 'sequence',
          );
          collections.add(
            ConfirmedCollection(
              documentId: row['document_id'] as String,
              commandId: row['command_id'] as String,
              receivableId: row['receivable_id'] as String,
              label: row['sale_label_snapshot'] as String,
              customerName: row['customer_name_snapshot'] as String,
              collectedAtUtc: DateTime.parse(
                row['collected_at_utc'] as String,
              ).toUtc(),
              totalMinor: row['total_minor'] as int,
              remainingMinor: row['remaining_minor'] as int,
              parts: parts.map(_storedPart).toList(),
            ),
          );
        }
        return CollectionsSnapshot(
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
          receivables: receivables,
          pendingCollections: requests.map(_prepared).toList(),
          collections: collections,
        );
      });

  @override
  Future<void> saveAccount(CollectionAccount account) async {
    _id(account.id);
    final name = _text(account.name, 'Nombre de cuenta', 120);
    if (!const ['cash', 'bank', 'mobile', 'clearing'].contains(account.kind)) {
      throw const CollectionsValidationException(
        'El tipo de cuenta no es válido.',
      );
    }
    await _database.database.transaction((txn) async {
      await _profile(txn);
      final rows = await txn.query(
        'cash_accounts',
        where: 'id = ?',
        whereArgs: [account.id],
      );
      final ledger = 'money:${account.id}';
      final ledgerRows = await txn.query(
        'ledger_accounts',
        where: 'id = ?',
        whereArgs: [ledger],
      );
      if (rows.isEmpty) {
        if (ledgerRows.isNotEmpty ||
            (await txn.query(
              'ledger_accounts',
              where: 'code = ?',
              whereArgs: ['CASH:${account.id}'],
            )).isNotEmpty) {
          throw const CollectionsValidationException(
            'El identificador ya corresponde a otra cuenta.',
          );
        }
        await txn.insert('ledger_accounts', {
          'id': ledger,
          'code': 'CASH:${account.id}',
          'name': name,
          'class': 'asset',
          'role': 'cash',
          'is_active': account.isActive ? 1 : 0,
        });
        await txn.insert('cash_accounts', {
          'id': account.id,
          'ledger_account_id': ledger,
          'name': name,
          'kind': account.kind,
          'is_available': account.isAvailable ? 1 : 0,
          'is_active': account.isActive ? 1 : 0,
        });
      } else {
        if (rows.single['kind'] != account.kind ||
            rows.single['ledger_account_id'] != ledger ||
            ledgerRows.length != 1 ||
            ledgerRows.single['class'] != 'asset' ||
            ledgerRows.single['role'] != 'cash') {
          throw const CollectionsValidationException(
            'No se puede cambiar la identidad o tipo de una cuenta.',
          );
        }
        await txn.update(
          'ledger_accounts',
          {'name': name, 'is_active': account.isActive ? 1 : 0},
          where: 'id = ?',
          whereArgs: [ledger],
        );
        await txn.update(
          'cash_accounts',
          {
            'name': name,
            'is_available': account.isAvailable ? 1 : 0,
            'is_active': account.isActive ? 1 : 0,
          },
          where: 'id = ?',
          whereArgs: [account.id],
        );
      }
    }, exclusive: true);
  }

  @override
  Future<void> saveMethod(CollectionMethod method) async {
    _id(method.id);
    final code = _text(method.code, 'Código de medio', 32);
    final name = _text(method.name, 'Nombre de medio', 120);
    await _database.database.transaction((txn) async {
      await _profile(txn);
      final rows = await txn.query(
        'payment_methods',
        where: 'id = ?',
        whereArgs: [method.id],
      );
      final existingCode = await txn.query(
        'payment_methods',
        where: 'code = ? AND id <> ?',
        whereArgs: [code, method.id],
      );
      if (existingCode.isNotEmpty) {
        throw const CollectionsValidationException(
          'Otro medio ya usa ese código.',
        );
      }
      if (rows.isEmpty) {
        await txn.insert('payment_methods', {
          'id': method.id,
          'code': code,
          'name': name,
          'is_active': method.isActive ? 1 : 0,
        });
      } else {
        if (rows.single['code'] != code) {
          throw const CollectionsValidationException(
            'El código de un medio existente no se modifica.',
          );
        }
        await txn.update(
          'payment_methods',
          {'name': name, 'is_active': method.isActive ? 1 : 0},
          where: 'id = ?',
          whereArgs: [method.id],
        );
      }
    }, exclusive: true);
  }

  @override
  Future<PreparedCollection> prepareCollection(CollectionCommand command) =>
      _database.database.transaction((txn) async {
        await _rejectQuickCommand(txn, command.commandId);
        return prepareCollectionInTransaction(txn, command);
      }, exclusive: true);

  /// Composition seam for one atomic sale and receipt.
  Future<PreparedCollection> prepareCollectionInTransaction(
    Transaction txn,
    CollectionCommand command, {
    List<CollectionPart>? snapshots,
  }) async {
    _id(command.commandId);
    _id(command.receivableId);
    _businessDate(command.occurredAtUtc);
    final inputs = _inputs(command.parts);
    final profile = await _profile(txn);
    final prior = await txn.query(
      'collection_requests',
      where: 'command_id = ?',
      whereArgs: [command.commandId],
    );
    if (prior.isNotEmpty) {
      final old = _prepared(prior.single);
      if (old.receivableId != command.receivableId ||
          old.occurredAtUtc.microsecondsSinceEpoch !=
              command.occurredAtUtc.microsecondsSinceEpoch ||
          !_sameInputs(old.parts, inputs)) {
        throw const CollectionsValidationException(
          'El identificador ya corresponde a otro cobro.',
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
          'supplier_payment_requests',
          where: 'command_id = ?',
          whereArgs: [command.commandId],
        )).isNotEmpty) {
      throw const CollectionsValidationException(
        'El identificador ya corresponde a otro comando.',
      );
    }
    final receivable = await _receivable(txn, command.receivableId);
    final parts = <CollectionPart>[];
    for (final input in inputs) {
      final account = await _activeAccount(txn, input.cashAccountId);
      final method = await _activeMethod(txn, input.paymentMethodId);
      parts.add(
        CollectionPart(
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
    final total = _total(parts);
    if (snapshots != null) {
      final captured = snapshots.toList()
        ..sort((a, b) {
          final account = a.cashAccountId.compareTo(b.cashAccountId);
          return account == 0
              ? a.paymentMethodId.compareTo(b.paymentMethodId)
              : account;
        });
      if (captured.length != parts.length ||
          !List.generate(
            parts.length,
            (i) =>
                parts[i].cashAccountId == captured[i].cashAccountId &&
                parts[i].paymentMethodId == captured[i].paymentMethodId &&
                parts[i].cashAccountKind == captured[i].cashAccountKind &&
                parts[i].paymentMethodCode == captured[i].paymentMethodCode &&
                parts[i].amountMinor == captured[i].amountMinor,
          ).every((v) => v)) {
        throw const CollectionsValidationException(
          'La identidad del cobro preparado cambió.',
        );
      }
      parts
        ..clear()
        ..addAll(captured);
    }
    await _validateTimingAndAmount(
      txn,
      receivable,
      command.occurredAtUtc,
      total,
    );
    final canonical = jsonEncode({
      'version': 1,
      'profileId': profile.profileId,
      'currency': profile.currencyCode,
      'scale': profile.moneyScale,
      'receivableId': receivable.receivableId,
      'saleDocumentId': receivable.saleDocumentId,
      'label': receivable.label,
      'customerName': receivable.customerName,
      'occurredAtUtc': command.occurredAtUtc.toIso8601String(),
      'totalMinor': total,
      'parts': parts.map(_partPayload).toList(),
    });
    final preparedAt = DateTime.now().toUtc();
    final row = <String, Object?>{
      'command_id': command.commandId,
      'canonical_payload': canonical,
      'receivable_id': command.receivableId,
      'occurred_at_utc': command.occurredAtUtc.toIso8601String(),
      'prepared_at_utc': preparedAt.toIso8601String(),
      'status': 'prepared',
    };
    await txn.insert('collection_requests', row);
    return _prepared(row);
  }

  Future<CollectionResult> confirmInTransaction(
    Transaction txn,
    String commandId,
  ) => _confirm(txn, commandId);

  @override
  Future<CollectionResult> confirmPrepared(String commandId) async {
    _id(commandId);
    await _rejectQuickCommand(_database.database, commandId);
    try {
      return await _database.database.transaction(
        (txn) => _confirm(txn, commandId),
        exclusive: true,
      );
    } on CollectionsValidationException {
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
            'collection_requests',
            {
              'status': 'rejected',
              'rejection_reason':
                  'El cobro fue rechazado sin registrar dinero.',
            },
            where: "command_id = ? AND status = 'prepared'",
            whereArgs: [commandId],
          );
        }
      }, exclusive: true);
      rethrow;
    }
  }

  static Future<void> _rejectQuickCommand(
    DatabaseExecutor txn,
    String id,
  ) async {
    if ((await txn.query(
      'paid_purchase_requests',
      where: 'command_id=? OR purchase_command_id=? OR payment_command_id=?',
      whereArgs: [id, id, id],
    )).isNotEmpty) {
      throw const CollectionsValidationException(
        'Este identificador pertenece a un ingreso de productos.',
      );
    }
    if ((await txn.query(
      'quick_sale_requests',
      where: 'command_id=? OR sale_command_id=? OR collection_command_id=?',
      whereArgs: [id, id, id],
    )).isNotEmpty) {
      throw const CollectionsValidationException(
        'Este identificador pertenece a una venta rápida; recupérala desde Ventas.',
      );
    }
  }

  Future<CollectionResult> _confirm(Transaction txn, String commandId) async {
    final rows = await txn.query(
      'collection_requests',
      where: 'command_id = ?',
      whereArgs: [commandId],
    );
    if (rows.isEmpty) {
      throw const CollectionsValidationException(
        'No existe el cobro pendiente.',
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
      throw const CollectionsValidationException(
        'El cobro fue rechazado o descartado. Prepara uno nuevo.',
      );
    }
    final prepared = _prepared(row);
    final payload = jsonDecode(canonical) as Map<String, dynamic>;
    final profile = await _profile(txn);
    final receivable = await _receivable(txn, prepared.receivableId);
    if (payload['version'] != 1 ||
        payload['profileId'] != profile.profileId ||
        payload['currency'] != profile.currencyCode ||
        payload['scale'] != profile.moneyScale ||
        payload['receivableId'] != row['receivable_id'] ||
        payload['occurredAtUtc'] != row['occurred_at_utc'] ||
        payload['saleDocumentId'] != receivable.saleDocumentId ||
        prepared.label != receivable.label ||
        prepared.customerName != receivable.customerName ||
        prepared.totalMinor != _total(prepared.parts)) {
      throw const CollectionsValidationException(
        'El cobro no coincide con la solicitud guardada.',
      );
    }
    _businessDate(prepared.occurredAtUtc);
    _inputs(
      prepared.parts
          .map(
            (part) => CollectionPartInput(
              cashAccountId: part.cashAccountId,
              paymentMethodId: part.paymentMethodId,
              amountMinor: part.amountMinor,
            ),
          )
          .toList(),
    );
    await _validateTimingAndAmount(
      txn,
      receivable,
      prepared.occurredAtUtc,
      prepared.totalMinor,
    );
    final debits = <String, BigInt>{};
    for (final part in prepared.parts) {
      final account = await _activeAccount(txn, part.cashAccountId);
      final method = await _activeMethod(txn, part.paymentMethodId);
      if (account['kind'] != part.cashAccountKind ||
          method['code'] != part.paymentMethodCode) {
        throw const CollectionsValidationException(
          'La identidad de una cuenta o medio cambió.',
        );
      }
      final ledger = account['ledger_account_id'] as String;
      debits[ledger] =
          (debits[ledger] ?? BigInt.zero) + BigInt.from(part.amountMinor);
    }
    final balances = await _balances(txn);
    for (final debit in debits.entries) {
      _signedInt64(
        (balances[debit.key] ?? BigInt.zero) + debit.value,
        'Saldo registrado de la cuenta',
      );
      _positiveInt64(debit.value, 'Ingreso de la cuenta');
    }
    final obligation = (await txn.query(
      'customer_receivables',
      where: 'id = ?',
      whereArgs: [receivable.receivableId],
    )).single;
    final control = obligation['control_account_id'] as String;
    final controlRows = await txn.query(
      'ledger_accounts',
      where: 'id = ?',
      whereArgs: [control],
    );
    if (controlRows.length != 1 ||
        controlRows.single['role'] != 'customer_receivable' ||
        controlRows.single['class'] != 'asset' ||
        controlRows.single['is_active'] != 1) {
      throw const CollectionsValidationException(
        'La cuenta de clientes no está disponible.',
      );
    }
    final now = DateTime.now().toUtc().toIso8601String();
    await _operatorRow(txn, now);
    final document = InventoryIds.next();
    final entry = InventoryIds.next();
    final result = CollectionResult(
      documentId: document,
      commandId: commandId,
      receivableId: receivable.receivableId,
      totalMinor: prepared.totalMinor,
      remainingMinor: receivable.remainingMinor - prepared.totalMinor,
    );
    await txn.insert('command_log', {
      'id': commandId,
      'command_type': 'collect_receivable',
      'payload_hash': DatabaseSchema.checksum(canonical),
      'actor_id': _operator,
      'response_json': jsonEncode({
        'canonicalPayload': canonical,
        'result': {
          'documentId': document,
          'commandId': commandId,
          'receivableId': result.receivableId,
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
      'type': 'customer_collection',
      'status': 'draft',
      'occurred_at_utc': prepared.occurredAtUtc.toIso8601String(),
      'business_date': _businessDate(prepared.occurredAtUtc),
      'recorded_at_utc': now,
      'source_kind': synthetic ? 'synthetic' : 'native',
      'date_quality': 'documented',
    });
    await txn.insert('collections', {
      'document_id': document,
      'receivable_id': receivable.receivableId,
      'sale_label_snapshot': prepared.label,
      'customer_name_snapshot': prepared.customerName,
      'collected_at_utc': prepared.occurredAtUtc.toIso8601String(),
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
      await txn.insert('collection_parts', {
        'id': InventoryIds.next(),
        'collection_id': document,
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
    await txn.insert('receivable_settlements', {
      'id': InventoryIds.next(),
      'receivable_id': receivable.receivableId,
      'collection_id': document,
      'amount_minor': prepared.totalMinor,
    });
    var sequence = 0;
    for (final debit in debits.entries) {
      await txn.insert('journal_lines', {
        'id': InventoryIds.next(),
        'entry_id': entry,
        'sequence': sequence++,
        'account_id': debit.key,
        'debit_minor': _positiveInt64(debit.value, 'Ingreso de cuenta'),
        'credit_minor': 0,
      });
    }
    await txn.insert('journal_lines', {
      'id': InventoryIds.next(),
      'entry_id': entry,
      'sequence': sequence,
      'account_id': control,
      'debit_minor': 0,
      'credit_minor': prepared.totalMinor,
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
      'collection_requests',
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
        'collection_requests',
        where: 'command_id = ?',
        whereArgs: [commandId],
      );
      if (rows.isEmpty) {
        throw const CollectionsValidationException('El cobro no existe.');
      }
      if (rows.single['status'] == 'cancelled') return;
      if (rows.single['status'] != 'rejected' ||
          (await txn.query(
            'command_log',
            where: 'id = ?',
            whereArgs: [commandId],
          )).isNotEmpty) {
        throw const CollectionsValidationException(
          'Primero resuelve el cobro pendiente. Un cobro registrado no se descarta.',
        );
      }
      await txn.update(
        'collection_requests',
        {'status': 'cancelled'},
        where: 'command_id = ?',
        whereArgs: [commandId],
      );
    }, exclusive: true);
  }

  static Future<List<ReceivableSummary>> _receivables(
    DatabaseExecutor txn,
  ) async {
    final rows = await txn.rawQuery('''
SELECT r.*, s.label_snapshot FROM customer_receivables r
JOIN sales s ON s.document_id = r.origin_document_id
JOIN business_documents d ON d.id = r.origin_document_id AND d.status = 'posted'
JOIN journal_entries e ON e.document_id = d.id AND e.status = 'posted'
ORDER BY r.issued_at_utc DESC, r.id
''');
    final settlements = await txn.rawQuery('''
SELECT r.receivable_id, r.amount_minor FROM all_receivable_settlements r
JOIN business_documents d ON d.id = r.collection_id AND d.status = 'posted'
JOIN journal_entries e ON e.document_id = d.id AND e.status = 'posted'
''');
    final totals = <String, BigInt>{};
    for (final row in settlements) {
      final id = row['receivable_id'] as String;
      totals[id] =
          (totals[id] ?? BigInt.zero) + BigInt.from(row['amount_minor'] as int);
    }
    return rows.map((row) {
      final collected = totals[row['id']] ?? BigInt.zero;
      final initial = row['initial_minor'] as int;
      return ReceivableSummary(
        receivableId: row['id'] as String,
        saleDocumentId: row['origin_document_id'] as String,
        label: row['label_snapshot'] as String,
        customerName: row['customer_name_snapshot'] as String,
        issuedAtUtc: DateTime.parse(row['issued_at_utc'] as String).toUtc(),
        dueDate: row['due_date'] as String,
        initialMinor: initial,
        collectedMinor: _nonnegativeInt64(collected, 'Total cobrado'),
        remainingMinor: _nonnegativeInt64(
          BigInt.from(initial) - collected,
          'Saldo por cobrar',
        ),
      );
    }).toList();
  }

  static Future<ReceivableSummary> _receivable(
    DatabaseExecutor txn,
    String id,
  ) async {
    final rows = (await _receivables(
      txn,
    )).where((row) => row.receivableId == id);
    if (rows.length != 1) {
      throw const CollectionsValidationException(
        'La cuenta por cobrar no existe o no está confirmada.',
      );
    }
    return rows.single;
  }

  static Future<void> _validateTimingAndAmount(
    DatabaseExecutor txn,
    ReceivableSummary receivable,
    DateTime occurredAt,
    int total,
  ) async {
    if (total > receivable.remainingMinor) {
      throw const CollectionsValidationException(
        'El cobro excede el saldo pendiente. Actualiza la vista.',
      );
    }
    final instant = occurredAt.microsecondsSinceEpoch;
    if (instant < receivable.issuedAtUtc.microsecondsSinceEpoch) {
      throw const CollectionsValidationException(
        'El cobro no puede ser anterior a la venta.',
      );
    }
    final prior = await txn.rawQuery(
      '''
SELECT d.occurred_at_utc collected_at_utc FROM all_receivable_settlements c
JOIN business_documents d ON d.id = c.collection_id AND d.status = 'posted'
JOIN journal_entries e ON e.document_id = d.id AND e.status = 'posted'
WHERE c.receivable_id = ?
''',
      [receivable.receivableId],
    );
    if (prior.any(
      (row) =>
          DateTime.parse(
            row['collected_at_utc'] as String,
          ).microsecondsSinceEpoch >
          instant,
    )) {
      throw const CollectionsValidationException(
        'El cobro no puede ser anterior a otro cobro de esta venta.',
      );
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
        rows.single['ledger_active'] != 1 ||
        rows.single['ledger_class'] != 'asset' ||
        rows.single['ledger_role'] != 'cash') {
      throw const CollectionsValidationException(
        'La cuenta de destino debe estar activa y ser monetaria.',
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
      throw const CollectionsValidationException(
        'El medio de pago debe estar activo.',
      );
    }
    return rows.single;
  }

  static Future<BusinessProfile> _profile(DatabaseExecutor txn) async {
    final rows = await txn.query('app_profile', where: 'id = 1');
    if (rows.length != 1) {
      throw const CollectionsValidationException(
        'Configura el espacio de trabajo primero.',
      );
    }
    final profile = BusinessProfile.fromRow(rows.single);
    if (profile.timezone != 'America/Bogota') {
      throw const CollectionsValidationException(
        'Los cobros requieren la zona horaria America/Bogota.',
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
      throw const CollectionsValidationException(
        'El operador local no está disponible.',
      );
    }
  }

  static List<CollectionPartInput> _inputs(List<CollectionPartInput> input) {
    if (input.isEmpty || input.length > 100) {
      throw const CollectionsValidationException(
        'El cobro requiere entre 1 y 100 partes.',
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
        throw const CollectionsValidationException(
          'Combina los importes que usan la misma cuenta y medio.',
        );
      }
    }
    _positiveInt64(total, 'Total de cobro');
    return parts;
  }

  static int _total(List<CollectionPart> parts) => _positiveInt64(
    parts.fold(BigInt.zero, (sum, part) => sum + BigInt.from(part.amountMinor)),
    'Total de cobro',
  );
  static bool _sameInputs(
    List<CollectionPart> a,
    List<CollectionPartInput> b,
  ) =>
      a.length == b.length &&
      List.generate(
        a.length,
        (i) =>
            a[i].cashAccountId == b[i].cashAccountId &&
            a[i].paymentMethodId == b[i].paymentMethodId &&
            a[i].amountMinor == b[i].amountMinor,
      ).every((same) => same);
  static Map<String, Object> _partPayload(CollectionPart part) => {
    'cashAccountId': part.cashAccountId,
    'paymentMethodId': part.paymentMethodId,
    'cashAccountName': part.cashAccountName,
    'cashAccountKind': part.cashAccountKind,
    'paymentMethodCode': part.paymentMethodCode,
    'paymentMethodName': part.paymentMethodName,
    'amountMinor': part.amountMinor,
  };
  static CollectionPart _payloadPart(dynamic input) {
    final row = input as Map<String, dynamic>;
    return CollectionPart(
      cashAccountId: row['cashAccountId'] as String,
      paymentMethodId: row['paymentMethodId'] as String,
      cashAccountName: row['cashAccountName'] as String,
      cashAccountKind: row['cashAccountKind'] as String,
      paymentMethodCode: row['paymentMethodCode'] as String,
      paymentMethodName: row['paymentMethodName'] as String,
      amountMinor: row['amountMinor'] as int,
    );
  }

  static CollectionPart _storedPart(Map<String, Object?> row) => CollectionPart(
    cashAccountId: row['cash_account_id'] as String,
    paymentMethodId: row['payment_method_id'] as String,
    cashAccountName: row['cash_account_name_snapshot'] as String,
    cashAccountKind: row['cash_account_kind_snapshot'] as String,
    paymentMethodCode: row['payment_method_code_snapshot'] as String,
    paymentMethodName: row['payment_method_name_snapshot'] as String,
    amountMinor: row['amount_minor'] as int,
  );
  static PreparedCollection _prepared(Map<String, Object?> row) {
    final payload =
        jsonDecode(row['canonical_payload'] as String) as Map<String, dynamic>;
    return PreparedCollection(
      commandId: row['command_id'] as String,
      receivableId: row['receivable_id'] as String,
      label: payload['label'] as String,
      customerName: payload['customerName'] as String,
      occurredAtUtc: DateTime.parse(row['occurred_at_utc'] as String).toUtc(),
      preparedAtUtc: DateTime.parse(row['prepared_at_utc'] as String).toUtc(),
      status: row['status'] as String,
      totalMinor: payload['totalMinor'] as int,
      parts: (payload['parts'] as List).map(_payloadPart).toList(),
    );
  }

  static CollectionResult _priorResult(
    Map<String, Object?> row,
    String canonical,
  ) {
    if (row['command_type'] != 'collect_receivable' ||
        row['response_version'] != 1 ||
        row['payload_hash'] != DatabaseSchema.checksum(canonical)) {
      throw const CollectionsValidationException(
        'El identificador ya corresponde a otro comando.',
      );
    }
    final stored =
        jsonDecode(row['response_json'] as String) as Map<String, dynamic>;
    if (stored['canonicalPayload'] != canonical) {
      throw const CollectionsValidationException(
        'El identificador ya corresponde a otro comando.',
      );
    }
    final result = stored['result'] as Map<String, dynamic>;
    return CollectionResult(
      documentId: result['documentId'] as String,
      commandId: result['commandId'] as String,
      receivableId: result['receivableId'] as String,
      totalMinor: result['totalMinor'] as int,
      remainingMinor: result['remainingMinor'] as int,
    );
  }

  static void _id(String value) {
    if (!RegExp(r'^[A-Za-z0-9:_-]{1,128}$').hasMatch(value)) {
      throw const CollectionsValidationException(
        'El identificador no es válido.',
      );
    }
  }

  static String _text(String value, String label, int maximum) {
    final text = value.trim();
    if (text.isEmpty ||
        text.length > maximum ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(text)) {
      throw CollectionsValidationException(
        '$label debe tener entre 1 y $maximum caracteres y no contener controles.',
      );
    }
    return text;
  }

  static int _positiveInt64(BigInt value, String label) {
    if (value <= BigInt.zero || value > Money.maxMinorUnits) {
      throw CollectionsValidationException(
        '$label debe ser positivo y estar dentro de 64 bits.',
      );
    }
    return value.toInt();
  }

  static int _nonnegativeInt64(BigInt value, String label) {
    if (value < BigInt.zero || value > Money.maxMinorUnits) {
      throw CollectionsValidationException(
        '$label excede el rango entero positivo de 64 bits.',
      );
    }
    return value.toInt();
  }

  static int _signedInt64(BigInt value, String label) {
    if (value < Money.minMinorUnits || value > Money.maxMinorUnits) {
      throw CollectionsValidationException(
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
      throw const CollectionsValidationException(
        'La fecha del cobro debe ser UTC y estar dentro del rango permitido.',
      );
    }
    return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }
}
