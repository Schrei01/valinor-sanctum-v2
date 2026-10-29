import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/domain/money.dart';
import '../../../core/infrastructure/database/app_database.dart';
import '../../../core/infrastructure/database/schema.dart';
import '../../../core/infrastructure/database/investment_ledger.dart';
import 'sqlite_investment_refund_store.dart';
import '../../inventory/domain/inventory_store.dart';
import '../../workspace/domain/business_profile.dart';
import '../domain/treasury_operation_store.dart';
import '../domain/treasury_store.dart';
import 'sqlite_treasury_store.dart';

/// Durable, atomic expenses and transfers. No stock or commercial facts are
/// created: every operation posts exactly one balanced monetary journal.
class SqliteTreasuryOperationStore implements TreasuryOperationStore {
  SqliteTreasuryOperationStore(this._database, {this.synthetic = false});
  final AppDatabase _database;
  final bool synthetic;
  static const _operator = 'system:local-operator';
  static const expenseAccountId = 'treasury:operating-expenses';
  static const _expenseCode = 'TREASURY:EXPENSE';
  SqliteInvestmentRefundStore get _refunds =>
      SqliteInvestmentRefundStore(_database, synthetic: synthetic);

  @override
  Future<void> ensureDefaults() async {
    await SqliteTreasuryStore(_database).ensureDefaults();
    await _database.database.transaction((txn) async {
      await _profile(txn);
      final rows = await txn.query(
        'ledger_accounts',
        where: 'id=? OR code=?',
        whereArgs: [expenseAccountId, _expenseCode],
      );
      if (rows.isEmpty) {
        await txn.insert('ledger_accounts', {
          'id': expenseAccountId,
          'code': _expenseCode,
          'name': 'Gastos de funcionamiento',
          'class': 'expense',
          'role': 'operating_expense',
          'is_active': 1,
        });
      } else {
        await _expenseAccount(txn);
      }
    }, exclusive: true);
  }

  @override
  Future<TreasuryOperationSnapshot> load() =>
      _database.database.transaction((txn) async {
        await _profile(txn);
        final accounts = await _accounts(txn);
        final balances = await _balances(txn);
        final pending = await txn.query(
          'treasury_operation_requests',
          where: "status IN ('prepared','rejected')",
          orderBy: 'prepared_at_utc,command_id',
        );
        final refunds = await txn.query('investment_refund_requests');
        final confirmed = await txn.rawQuery('''
SELECT r.command_id FROM treasury_operation_requests r
JOIN treasury_operations o ON o.request_id=r.command_id
JOIN business_documents d ON d.id=o.document_id AND d.status='posted'
JOIN journal_entries e ON e.document_id=d.id AND e.status='posted'
WHERE r.status='confirmed'
''');
        return TreasuryOperationSnapshot(
          investmentMinor: await InvestmentLedger.balance(txn),
          accounts: accounts
              .map(
                (row) => TreasuryAccount(
                  id: row['id'] as String,
                  name: row['name'] as String,
                  role: row['treasury_role'] as TreasuryAccountRole,
                  balanceMinor: treasuryCheckedMinor(
                    balances[row['ledger_account_id']] ?? BigInt.zero,
                    'Saldo de ${row['name']}',
                  ),
                ),
              )
              .toList(),
          pendingOperations: [
            ...pending.map(_prepared),
            ...refunds
                .where(
                  (r) => r['status'] == 'prepared' || r['status'] == 'rejected',
                )
                .map(SqliteInvestmentRefundStore.prepared),
          ],
          confirmedCommandIds:
              confirmed.map((r) => r['command_id'] as String).toSet()..addAll(
                refunds
                    .where((r) => r['status'] == 'confirmed')
                    .map((r) => r['command_id'] as String),
              ),
        );
      });

  @override
  Future<PreparedTreasuryOperation> prepare(
    TreasuryOperationCommand command,
  ) async {
    if (command.kind == TreasuryOperationKind.investmentRefund) {
      return _refunds.prepare(command);
    }
    final input = _input(command);
    return _database.database.transaction((txn) async {
      final profile = await _profile(txn);
      final requests = await txn.query(
        'treasury_operation_requests',
        where: 'command_id=?',
        whereArgs: [command.commandId],
      );
      if (requests.isNotEmpty) {
        final old = _prepared(requests.single);
        if (jsonEncode(_input(old.command)) != jsonEncode(input)) {
          throw const TreasuryValidationException(
            'El identificador ya corresponde a otra operación.',
          );
        }
        if (old.status == 'discarded') {
          throw const TreasuryValidationException(
            'La operación fue descartada.',
          );
        }
        return old;
      }
      await _unused(txn, command.commandId);
      final accounts = await _accounts(txn);
      final source = _account(accounts, command.sourceAccountId);
      final destination = command.destinationAccountId == null
          ? null
          : _account(accounts, command.destinationAccountId!);
      _allowedSource(command.kind, source);
      if (command.kind == TreasuryOperationKind.expense) {
        await _expenseAccount(txn);
      }
      await _fundsAndChronology(txn, source, destination, command);
      final canonical = jsonEncode({
        'version': 1,
        'profileId': profile.profileId,
        'currency': profile.currencyCode,
        'scale': profile.moneyScale,
        ...input,
        'sourceLedgerAccountId': source['ledger_account_id'],
        'destinationLedgerAccountId': destination?['ledger_account_id'],
        'sourceAccountName': source['name'],
        'destinationAccountName': destination?['name'],
      });
      final row = <String, Object?>{
        'command_id': command.commandId,
        'canonical_payload': canonical,
        'occurred_at_utc': command.occurredAtUtc.toIso8601String(),
        'prepared_at_utc': DateTime.now().toUtc().toIso8601String(),
        'status': 'prepared',
        'rejection_reason': null,
      };
      await txn.insert('treasury_operation_requests', row);
      return _prepared(row);
    }, exclusive: true);
  }

  @override
  Future<TreasuryOperationResult> confirmPrepared(String commandId) async {
    if ((await _database.database.query(
      'investment_refund_requests',
      where: 'command_id=?',
      whereArgs: [commandId],
    )).isNotEmpty) {
      return _refunds.confirm(commandId);
    }
    _id(commandId);
    try {
      return await _database.database.transaction(
        (txn) => _confirm(txn, commandId),
        exclusive: true,
      );
    } on TreasuryValidationException catch (error) {
      await _reject(commandId, error.message);
      rethrow;
    }
  }

  Future<TreasuryOperationResult> _confirm(Transaction txn, String id) async {
    final requests = await txn.query(
      'treasury_operation_requests',
      where: 'command_id=?',
      whereArgs: [id],
    );
    if (requests.length != 1) {
      throw const TreasuryValidationException(
        'La operación preparada no existe.',
      );
    }
    final row = requests.single;
    final canonical = row['canonical_payload'] as String;
    final logs = await txn.query('command_log', where: 'id=?', whereArgs: [id]);
    if (logs.isNotEmpty) return _prior(logs.single, canonical);
    if (row['status'] != 'prepared') {
      throw const TreasuryValidationException(
        'La operación ya no está pendiente de confirmación.',
      );
    }
    final prepared = _prepared(row);
    final command = prepared.command;
    final payload = jsonDecode(canonical) as Map<String, dynamic>;
    final profile = await _profile(txn);
    if (payload['profileId'] != profile.profileId ||
        payload['currency'] != profile.currencyCode ||
        payload['scale'] != profile.moneyScale) {
      throw const TreasuryValidationException(
        'La configuración monetaria cambió.',
      );
    }
    final accounts = await _accounts(txn);
    final source = _account(accounts, command.sourceAccountId);
    final destination = command.destinationAccountId == null
        ? null
        : _account(accounts, command.destinationAccountId!);
    _allowedSource(command.kind, source);
    if (source['ledger_account_id'] != payload['sourceLedgerAccountId'] ||
        destination?['ledger_account_id'] !=
            payload['destinationLedgerAccountId']) {
      throw const TreasuryValidationException(
        'La identidad de una cuenta cambió.',
      );
    }
    if (command.kind == TreasuryOperationKind.expense) {
      await _expenseAccount(txn);
    }
    await _fundsAndChronology(txn, source, destination, command);
    final now = DateTime.now().toUtc().toIso8601String();
    await _operatorRow(txn, now);
    final documentId = InventoryIds.next();
    final entryId = InventoryIds.next();
    final result = TreasuryOperationResult(
      commandId: id,
      documentId: documentId,
      kind: command.kind,
      amountMinor: command.amountMinor,
    );
    await txn.update(
      'treasury_operation_requests',
      {'status': 'executing'},
      where: 'command_id=?',
      whereArgs: [id],
    );
    await txn.insert('command_log', {
      'id': id,
      'command_type': 'treasury_operation',
      'payload_hash': DatabaseSchema.checksum(canonical),
      'actor_id': _operator,
      'response_json': jsonEncode({
        'canonicalPayload': canonical,
        'result': {
          'commandId': id,
          'documentId': documentId,
          'kind': command.kind.name,
          'amountMinor': command.amountMinor,
        },
      }),
      'response_version': 1,
      'committed_at_utc': now,
      'authorization_policy_version': 'development-single-user-v1',
    });
    await txn.insert('business_documents', {
      'id': documentId,
      'command_id': id,
      'command_sequence': 0,
      'profile_id': profile.profileId,
      'actor_id': _operator,
      'type': command.kind == TreasuryOperationKind.expense
          ? 'cash_expense'
          : 'cash_transfer',
      'status': 'draft',
      'occurred_at_utc': command.occurredAtUtc.toIso8601String(),
      'business_date': _businessDate(command.occurredAtUtc),
      'recorded_at_utc': now,
      'reason': command.reason,
      'source_kind': synthetic ? 'synthetic' : 'native',
      'date_quality': 'documented',
    });
    await txn.insert('treasury_operations', {
      'document_id': documentId,
      'request_id': id,
      'kind': command.kind.name,
      'source_account_id': command.sourceAccountId,
      'destination_account_id': command.destinationAccountId,
      'source_account_name_snapshot': prepared.sourceAccountName,
      'destination_account_name_snapshot': prepared.destinationAccountName,
      'amount_minor': command.amountMinor,
      'reason': command.reason,
      'note': command.note,
      'expense_account_id': command.kind == TreasuryOperationKind.expense
          ? expenseAccountId
          : null,
    });
    await txn.insert('journal_entries', {
      'id': entryId,
      'document_id': documentId,
      'status': 'draft',
      'cost_completeness': 'not_applicable',
    });
    for (final line in [
      (
        destination?['ledger_account_id'] ?? expenseAccountId,
        command.amountMinor,
        0,
      ),
      (source['ledger_account_id'], 0, command.amountMinor),
    ].indexed) {
      await txn.insert('journal_lines', {
        'id': InventoryIds.next(),
        'entry_id': entryId,
        'sequence': line.$1,
        'account_id': line.$2.$1,
        'debit_minor': line.$2.$2,
        'credit_minor': line.$2.$3,
      });
    }
    await txn.update(
      'business_documents',
      {'status': 'posted'},
      where: 'id=?',
      whereArgs: [documentId],
    );
    await txn.update(
      'journal_entries',
      {'status': 'posted', 'posted_at_utc': now},
      where: 'id=?',
      whereArgs: [entryId],
    );
    await txn.update(
      'treasury_operation_requests',
      {'status': 'confirmed'},
      where: 'command_id=?',
      whereArgs: [id],
    );
    return result;
  }

  @override
  Future<void> discardRejected(String commandId) async {
    if ((await _database.database.query(
      'investment_refund_requests',
      where: 'command_id=?',
      whereArgs: [commandId],
    )).isNotEmpty) {
      return _refunds.discard(commandId);
    }
    _id(commandId);
    await _database.database.transaction((txn) async {
      final rows = await txn.query(
        'treasury_operation_requests',
        where: 'command_id=?',
        whereArgs: [commandId],
      );
      if (rows.length != 1) {
        throw const TreasuryValidationException('La operación no existe.');
      }
      if (rows.single['status'] == 'discarded') return;
      if (rows.single['status'] != 'rejected' ||
          (await txn.query(
            'command_log',
            where: 'id=?',
            whereArgs: [commandId],
          )).isNotEmpty) {
        throw const TreasuryValidationException(
          'Solo se puede descartar una operación rechazada sin registrar.',
        );
      }
      await txn.update(
        'treasury_operation_requests',
        {'status': 'discarded'},
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
            'treasury_operation_requests',
            {'status': 'rejected', 'rejection_reason': message},
            where: "command_id=? AND status='prepared'",
            whereArgs: [id],
          );
        }
      }, exclusive: true);

  static Future<List<Map<String, Object?>>> _accounts(
    DatabaseExecutor txn,
  ) async {
    final rows = await txn.rawQuery('''
SELECT c.* FROM cash_accounts c
JOIN ledger_accounts l ON l.id=c.ledger_account_id
WHERE c.is_active=1 AND c.is_available=1 AND l.is_active=1
AND l.class='asset' AND l.role='cash'
ORDER BY c.name COLLATE NOCASE,c.id
''');
    final options = await txn.query(
      'quick_payment_options',
      where: 'id IN (?,?)',
      whereArgs: ['quick-default:EFECTIVO', 'quick-default:NEQUI'],
    );
    final roles = <String, TreasuryAccountRole>{
      SqliteTreasuryStore.reserveAccountId: TreasuryAccountRole.reserve,
    };
    for (final spec in [
      ('quick-default:EFECTIVO', TreasuryAccountRole.cash),
      ('quick-default:NEQUI', TreasuryAccountRole.nequi),
    ]) {
      final matches = options.where((o) => o['id'] == spec.$1);
      if (matches.length != 1) {
        throw const TreasuryValidationException(
          'Configura Caja y Nequi primero.',
        );
      }
      final id = matches.single['cash_account_id'] as String;
      if (roles.containsKey(id)) {
        throw const TreasuryValidationException(
          'Las cuentas monetarias deben ser distintas.',
        );
      }
      roles[id] = spec.$2;
    }
    final result = rows
        .map(
          (r) => <String, Object?>{
            ...r,
            'treasury_role': roles[r['id']] ?? TreasuryAccountRole.other,
          },
        )
        .toList();
    result.sort((a, b) {
      final role = (a['treasury_role'] as TreasuryAccountRole).index.compareTo(
        (b['treasury_role'] as TreasuryAccountRole).index,
      );
      return role == 0
          ? (a['name'] as String).compareTo(b['name'] as String)
          : role;
    });
    return result;
  }

  static Map<String, Object?> _account(
    List<Map<String, Object?>> accounts,
    String id,
  ) {
    final matches = accounts.where((a) => a['id'] == id);
    if (matches.length != 1) {
      throw const TreasuryValidationException(
        'La cuenta no está activa o disponible.',
      );
    }
    return matches.single;
  }

  static void _allowedSource(
    TreasuryOperationKind kind,
    Map<String, Object?> source,
  ) {
    if (kind == TreasuryOperationKind.expense &&
        ![
          TreasuryAccountRole.cash,
          TreasuryAccountRole.nequi,
        ].contains(source['treasury_role'])) {
      throw const TreasuryValidationException(
        'Los gastos se pagan desde Caja o Nequi.',
      );
    }
  }

  static Future<Map<String, BigInt>> _balances(DatabaseExecutor txn) async {
    final rows = await txn.rawQuery('''
SELECT l.account_id,l.debit_minor,l.credit_minor FROM journal_lines l
JOIN journal_entries e ON e.id=l.entry_id AND e.status='posted'
JOIN business_documents d ON d.id=e.document_id AND d.status='posted'
JOIN ledger_accounts a ON a.id=l.account_id AND a.class='asset' AND a.role='cash'
''');
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

  static Future<void> _fundsAndChronology(
    DatabaseExecutor txn,
    Map<String, Object?> source,
    Map<String, Object?>? destination,
    TreasuryOperationCommand command,
  ) async {
    final balances = await _balances(txn);
    final amount = BigInt.from(command.amountMinor);
    final balance = balances[source['ledger_account_id']] ?? BigInt.zero;
    treasuryCheckedMinor(balance, 'Saldo de origen');
    if (balance < amount) {
      throw const TreasuryValidationException(
        'Saldo insuficiente en la cuenta de origen.',
      );
    }
    treasuryCheckedMinor(balance - amount, 'Saldo de origen');
    if (destination != null) {
      final targetBalance =
          balances[destination['ledger_account_id']] ?? BigInt.zero;
      treasuryCheckedMinor(targetBalance, 'Saldo de destino');
      treasuryCheckedMinor(targetBalance + amount, 'Saldo de destino');
    }
    final available = await txn.rawQuery('''
SELECT c.ledger_account_id FROM quick_payment_options q
JOIN cash_accounts c ON c.id=q.cash_account_id
WHERE q.id IN ('quick-default:EFECTIVO','quick-default:NEQUI')
''');
    final availableLedgers = available
        .map((r) => r['ledger_account_id'])
        .toSet();
    var totalAvailable = availableLedgers.fold(
      BigInt.zero,
      (sum, id) => sum + (balances[id] ?? BigInt.zero),
    );
    if (availableLedgers.contains(source['ledger_account_id'])) {
      totalAvailable -= amount;
    }
    if (destination != null &&
        availableLedgers.contains(destination['ledger_account_id'])) {
      totalAvailable += amount;
    }
    treasuryCheckedMinor(totalAvailable, 'Total disponible');
    for (final account in [source, ?destination]) {
      final rows = await txn.rawQuery(
        '''
SELECT d.occurred_at_utc FROM journal_lines l
JOIN journal_entries e ON e.id=l.entry_id AND e.status='posted'
JOIN business_documents d ON d.id=e.document_id AND d.status='posted'
WHERE l.account_id=?
''',
        [account['ledger_account_id']],
      );
      if (rows.any(
        (r) => DateTime.parse(
          r['occurred_at_utc'] as String,
        ).isAfter(command.occurredAtUtc),
      )) {
        throw const TreasuryValidationException(
          'La operación no puede ser anterior al último movimiento de sus cuentas.',
        );
      }
    }
  }

  static Future<void> _expenseAccount(DatabaseExecutor txn) async {
    final rows = await txn.query(
      'ledger_accounts',
      where: 'id=? OR code=?',
      whereArgs: [expenseAccountId, _expenseCode],
    );
    if (rows.length != 1 ||
        rows.single['id'] != expenseAccountId ||
        rows.single['code'] != _expenseCode ||
        rows.single['class'] != 'expense' ||
        rows.single['role'] != 'operating_expense' ||
        rows.single['is_active'] != 1) {
      throw const TreasuryValidationException(
        'La cuenta interna de gastos no está disponible.',
      );
    }
  }

  static Future<void> _operatorRow(DatabaseExecutor txn, String now) async {
    final rows = await txn.query(
      'actors',
      where: 'id=?',
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
      throw const TreasuryValidationException(
        'El operador no está disponible.',
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
        throw const TreasuryValidationException(
          'El identificador ya corresponde a otra operación.',
        );
      }
    }
    for (final spec in [
      ('quick_sale_requests', 'sale_command_id', 'collection_command_id'),
      ('paid_purchase_requests', 'purchase_command_id', 'payment_command_id'),
    ]) {
      if ((await txn.rawQuery(
        'SELECT command_id FROM ${spec.$1} WHERE command_id=? OR ${spec.$2}=? OR ${spec.$3}=?',
        [id, id, id],
      )).isNotEmpty) {
        throw const TreasuryValidationException(
          'El identificador está reservado por otra operación.',
        );
      }
    }
  }

  static Map<String, Object?> _input(TreasuryOperationCommand c) {
    _id(c.commandId);
    _id(c.sourceAccountId);
    if (c.destinationAccountId != null) _id(c.destinationAccountId!);
    _businessDate(c.occurredAtUtc);
    if (c.amountMinor <= 0 ||
        BigInt.from(c.amountMinor) > Money.maxMinorUnits) {
      throw const TreasuryValidationException(
        'El valor debe ser positivo y estar dentro del rango permitido.',
      );
    }
    final reason = _text(c.reason, 'Motivo', 80);
    final note = c.note == null || c.note!.trim().isEmpty
        ? null
        : _text(c.note!, 'Observación', 500);
    if (c.kind == TreasuryOperationKind.expense) {
      if (c.destinationAccountId != null ||
          !['Arriendo', 'Aseo', 'Servicios', 'Otro'].contains(reason)) {
        throw const TreasuryValidationException(
          'Selecciona un motivo de gasto válido.',
        );
      }
    } else if (c.destinationAccountId == null ||
        c.destinationAccountId == c.sourceAccountId ||
        reason != 'Transferencia') {
      throw const TreasuryValidationException(
        'Selecciona dos cuentas distintas para transferir.',
      );
    }
    return {
      'commandId': c.commandId,
      'kind': c.kind.name,
      'sourceAccountId': c.sourceAccountId,
      'destinationAccountId': c.destinationAccountId,
      'amountMinor': c.amountMinor,
      'reason': reason,
      'note': note,
      'occurredAtUtc': c.occurredAtUtc.toIso8601String(),
    };
  }

  static PreparedTreasuryOperation _prepared(Map<String, Object?> row) {
    final p =
        jsonDecode(row['canonical_payload'] as String) as Map<String, dynamic>;
    return PreparedTreasuryOperation(
      command: TreasuryOperationCommand(
        commandId: p['commandId'] as String,
        kind: TreasuryOperationKind.values.byName(p['kind'] as String),
        sourceAccountId: p['sourceAccountId'] as String,
        destinationAccountId: p['destinationAccountId'] as String?,
        amountMinor: p['amountMinor'] as int,
        reason: p['reason'] as String,
        note: p['note'] as String?,
        occurredAtUtc: DateTime.parse(p['occurredAtUtc'] as String).toUtc(),
      ),
      status: row['status'] as String,
      preparedAtUtc: DateTime.parse(row['prepared_at_utc'] as String).toUtc(),
      rejectionReason: row['rejection_reason'] as String?,
      sourceAccountName: p['sourceAccountName'] as String,
      destinationAccountName: p['destinationAccountName'] as String?,
    );
  }

  static TreasuryOperationResult _prior(
    Map<String, Object?> row,
    String canonical,
  ) {
    if (row['command_type'] != 'treasury_operation' ||
        row['response_version'] != 1 ||
        row['payload_hash'] != DatabaseSchema.checksum(canonical)) {
      throw const TreasuryValidationException(
        'El identificador ya corresponde a otra operación.',
      );
    }
    final p =
        jsonDecode(row['response_json'] as String) as Map<String, dynamic>;
    if (p['canonicalPayload'] != canonical) {
      throw const TreasuryValidationException(
        'El identificador ya corresponde a otra operación.',
      );
    }
    final r = p['result'] as Map<String, dynamic>;
    return TreasuryOperationResult(
      commandId: r['commandId'] as String,
      documentId: r['documentId'] as String,
      kind: TreasuryOperationKind.values.byName(r['kind'] as String),
      amountMinor: r['amountMinor'] as int,
    );
  }

  static Future<BusinessProfile> _profile(DatabaseExecutor txn) async {
    final rows = await txn.query('app_profile', where: 'id=1');
    if (rows.length != 1) {
      throw const TreasuryValidationException(
        'Configura el espacio de trabajo primero.',
      );
    }
    final p = BusinessProfile.fromRow(rows.single);
    if (p.timezone != 'America/Bogota') {
      throw const TreasuryValidationException(
        'La operación requiere la zona horaria America/Bogota.',
      );
    }
    return p;
  }

  static void _id(String value) {
    if (!RegExp(r'^[A-Za-z0-9:_-]{1,128}$').hasMatch(value)) {
      throw const TreasuryValidationException('El identificador no es válido.');
    }
  }

  static String _text(String value, String label, int max) {
    final trimmed = value.trim();
    if (trimmed.isEmpty ||
        trimmed.length > max ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(trimmed)) {
      throw TreasuryValidationException(
        '$label debe tener entre 1 y $max caracteres y no contener controles.',
      );
    }
    return trimmed;
  }

  static String _businessDate(DateTime time) {
    final local = time.subtract(const Duration(hours: 5));
    if (!time.isUtc ||
        time.year < 1 ||
        time.year > 9999 ||
        local.year < 1 ||
        local.year > 9999) {
      throw const TreasuryValidationException(
        'La fecha debe ser UTC y estar dentro del rango permitido.',
      );
    }
    return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }
}
