import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/schema.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_opening_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_operation_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_store.dart';
import 'package:valinor_sanctum_2/features/treasury/domain/treasury_opening.dart';
import 'package:valinor_sanctum_2/features/workspace/data/sqlite_workspace_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';

const _time = '2026-10-20T10:00:00.000Z';
const _actor = 'schema-operator';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase app;
  late Database db;
  late String cash;
  late String nequi;
  const reserve = SqliteTreasuryStore.reserveAccountId;

  setUp(() async {
    app = await AppDatabase.open(path: inMemoryDatabasePath);
    db = app.database;
    await SqliteWorkspaceStore(app).createProfile(
      BusinessProfile(
        profileId: 'treasury-operation-schema',
        businessName: 'Tienda sintética',
        currencyCode: 'COP',
        moneyScale: 2,
        timezone: 'America/Bogota',
        createdAtUtc: DateTime.utc(2026, 10, 20),
      ),
    );
    await SqliteTreasuryOperationStore(app, synthetic: true).ensureDefaults();
    final options = await db.query('quick_payment_options');
    cash =
        options.singleWhere(
              (r) => r['id'] == 'quick-default:EFECTIVO',
            )['cash_account_id']
            as String;
    nequi =
        options.singleWhere(
              (r) => r['id'] == 'quick-default:NEQUI',
            )['cash_account_id']
            as String;
    await SqliteTreasuryOpeningStore(app, synthetic: true).importOpening(
      TreasuryOpeningCommand(
        commandId: 'opening',
        sourceSha256: 'a' * 64,
        snapshotSha256: 'b' * 64,
        occurredAtUtc: DateTime.utc(2026, 10, 20, 8),
        cashMinor: 10000,
        nequiMinor: 5000,
        reserveMinor: -2000,
        receivablesMinor: 0,
        sourceMetadata: const {'source': 'synthetic'},
      ),
    );
    await db.insert('actors', {
      'id': _actor,
      'display_name': 'Operador sintético',
      'kind': 'synthetic',
      'is_active': 1,
      'created_at_utc': _time,
    });
  });
  tearDown(() => app.close());

  Future<Map<String, Object?>> request(
    String id, {
    String kind = 'expense',
    String? source,
    String? destination,
    int amount = 1000,
    String? reason,
    String? note,
    String time = _time,
  }) async {
    final origin = (await db.query(
      'cash_accounts',
      where: 'id=?',
      whereArgs: [source ?? cash],
    )).single;
    final targetId = kind == 'transfer' ? destination ?? nequi : destination;
    final target = targetId == null
        ? null
        : (await db.query(
            'cash_accounts',
            where: 'id=?',
            whereArgs: [targetId],
          )).single;
    return {
      'command_id': id,
      'canonical_payload': jsonEncode({
        'version': 1,
        'profileId': 'treasury-operation-schema',
        'currency': 'COP',
        'scale': 2,
        'commandId': id,
        'kind': kind,
        'sourceAccountId': origin['id'],
        'destinationAccountId': target?['id'],
        'amountMinor': amount,
        'reason': reason ?? (kind == 'expense' ? 'Aseo' : 'Transferencia'),
        'note': note,
        'occurredAtUtc': time,
        'sourceLedgerAccountId': origin['ledger_account_id'],
        'destinationLedgerAccountId': target?['ledger_account_id'],
        'sourceAccountName': origin['name'],
        'destinationAccountName': target?['name'],
      }),
      'occurred_at_utc': time,
      'prepared_at_utc': _time,
      'status': 'prepared',
    };
  }

  Map<String, Object?> logged(
    String id,
    String canonical, {
    Map<String, Object?> resultChanges = const {},
  }) {
    final payload = jsonDecode(canonical) as Map<String, dynamic>;
    return {
      'id': id,
      'command_type': 'treasury_operation',
      'payload_hash': DatabaseSchema.checksum(canonical),
      'actor_id': _actor,
      'response_json': jsonEncode({
        'canonicalPayload': canonical,
        'result': {
          'commandId': id,
          'documentId': '$id-document',
          'kind': payload['kind'],
          'amountMinor': payload['amountMinor'],
          ...resultChanges,
        },
      }),
      'response_version': 1,
      'committed_at_utc': _time,
      'authorization_policy_version': 'development-single-user-v1',
    };
  }

  Future<Map<String, Object?>> draft(
    String id, {
    String kind = 'expense',
    String? source,
    String? destination,
    int amount = 1000,
    String? reason,
    String? note,
    String time = _time,
    bool insertOperation = true,
    bool withJournal = true,
  }) async {
    final row = await request(
      id,
      kind: kind,
      source: source,
      destination: destination,
      amount: amount,
      reason: reason,
      note: note,
      time: time,
    );
    final canonical = row['canonical_payload'] as String;
    final payload = jsonDecode(canonical) as Map<String, dynamic>;
    await db.insert('treasury_operation_requests', row);
    await db.update(
      'treasury_operation_requests',
      {'status': 'executing'},
      where: 'command_id=?',
      whereArgs: [id],
    );
    await db.insert('command_log', logged(id, canonical));
    await db.insert('business_documents', {
      'id': '$id-document',
      'command_id': id,
      'command_sequence': 0,
      'profile_id': 'treasury-operation-schema',
      'actor_id': _actor,
      'type': kind == 'expense' ? 'cash_expense' : 'cash_transfer',
      'status': 'draft',
      'occurred_at_utc': time,
      'business_date': DateTime.parse(
        time,
      ).subtract(const Duration(hours: 5)).toIso8601String().substring(0, 10),
      'recorded_at_utc': _time,
      'reason': payload['reason'],
      'source_kind': 'synthetic',
      'date_quality': 'documented',
    });
    final header = <String, Object?>{
      'document_id': '$id-document',
      'request_id': id,
      'kind': kind,
      'source_account_id': payload['sourceAccountId'],
      'destination_account_id': payload['destinationAccountId'],
      'source_account_name_snapshot': payload['sourceAccountName'],
      'destination_account_name_snapshot': payload['destinationAccountName'],
      'amount_minor': amount,
      'reason': payload['reason'],
      'note': note,
      'expense_account_id': kind == 'expense'
          ? SqliteTreasuryOperationStore.expenseAccountId
          : null,
    };
    if (insertOperation) await db.insert('treasury_operations', header);
    if (withJournal) {
      await db.insert('journal_entries', {
        'id': '$id-entry',
        'document_id': '$id-document',
        'status': 'draft',
        'cost_completeness': 'not_applicable',
      });
      final expected = await db.query(
        'treasury_operation_expected_lines',
        where: 'document_id=?',
        whereArgs: ['$id-document'],
      );
      for (final pair in expected.indexed) {
        await db.insert('journal_lines', {
          'id': '$id-line-${pair.$1}',
          'entry_id': '$id-entry',
          'sequence': pair.$1,
          'account_id': pair.$2['account_id'],
          'debit_minor': pair.$2['debit_minor'],
          'credit_minor': pair.$2['credit_minor'],
        });
      }
    }
    return header;
  }

  Future<int> postDocument(String id) => db.update(
    'business_documents',
    {'status': 'posted'},
    where: 'id=?',
    whereArgs: ['$id-document'],
  );
  Future<int> postEntry(String id) => db.update(
    'journal_entries',
    {'status': 'posted', 'posted_at_utc': _time},
    where: 'id=?',
    whereArgs: ['$id-entry'],
  );
  Future<void> confirm(String id) async {
    await postDocument(id);
    await postEntry(id);
    await db.update(
      'treasury_operation_requests',
      {'status': 'confirmed'},
      where: 'command_id=?',
      whereArgs: [id],
    );
  }

  final rejected = throwsA(isA<DatabaseException>());

  test(
    'prepared input and terminal request history cannot be rewritten or replaced',
    () async {
      final row = await request('prepared');
      await db.insert('treasury_operation_requests', row);
      await expectLater(
        db.insert(
          'treasury_operation_requests',
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        ),
        rejected,
      );
      for (final change in [
        {'canonical_payload': '{}'},
        {'command_id': 'changed'},
        {'occurred_at_utc': '2026-10-20T11:00:00.000Z'},
        {'prepared_at_utc': '2026-10-20T11:00:00.000Z'},
        {'status': 'confirmed'},
        {'status': 'discarded'},
      ]) {
        await expectLater(
          db.update(
            'treasury_operation_requests',
            change,
            where: 'command_id=?',
            whereArgs: ['prepared'],
          ),
          rejected,
        );
      }
      await expectLater(
        db.delete(
          'treasury_operation_requests',
          where: 'command_id=?',
          whereArgs: ['prepared'],
        ),
        rejected,
      );
      await db.update(
        'treasury_operation_requests',
        {'status': 'rejected', 'rejection_reason': 'Saldo cambió.'},
        where: 'command_id=?',
        whereArgs: ['prepared'],
      );
      await expectLater(
        db.update(
          'treasury_operation_requests',
          {'status': 'discarded', 'rejection_reason': 'Otra razón'},
          where: 'command_id=?',
          whereArgs: ['prepared'],
        ),
        rejected,
      );
      await db.update(
        'treasury_operation_requests',
        {'status': 'discarded'},
        where: 'command_id=?',
        whereArgs: ['prepared'],
      );
      await expectLater(
        db.update(
          'treasury_operation_requests',
          {'status': 'prepared', 'rejection_reason': null},
          where: 'command_id=?',
          whereArgs: ['prepared'],
        ),
        rejected,
      );
    },
  );

  test(
    'raw requests enforce expense source reason and distinct transfer accounts',
    () async {
      for (final row in [
        await request('reserve-expense', source: reserve),
        await request('reason', reason: 'Inventado'),
        await request('self', kind: 'transfer', destination: cash),
        await request('transfer-reason', kind: 'transfer', reason: 'Aseo'),
        await request('zero', amount: 0),
      ]) {
        await expectLater(
          db.insert('treasury_operation_requests', row),
          rejected,
          reason: row['command_id'] as String,
        );
      }
      expect(await db.query('treasury_operation_requests'), isEmpty);
      await db.insert(
        'treasury_operation_requests',
        await request('other', reason: 'Otro'),
      );
    },
  );

  test(
    'a reserved request cannot log another command type or misleading response',
    () async {
      final row = await request('reserved');
      await db.insert('treasury_operation_requests', row);
      await db.update(
        'treasury_operation_requests',
        {'status': 'executing'},
        where: 'command_id=?',
        whereArgs: ['reserved'],
      );
      final canonical = row['canonical_payload'] as String;
      for (final changed in [
        {
          ...logged('reserved', canonical),
          'command_type': 'customer_collection',
        },
        logged('reserved', canonical, resultChanges: {'commandId': 'other'}),
        logged('reserved', canonical, resultChanges: {'kind': 'transfer'}),
        logged('reserved', canonical, resultChanges: {'amountMinor': 1}),
      ]) {
        await expectLater(db.insert('command_log', changed), rejected);
      }
      await db.insert('command_log', logged('reserved', canonical));
    },
  );

  test(
    'operation header must match its prepared amount and account snapshots',
    () async {
      final header = await draft(
        'header',
        insertOperation: false,
        withJournal: false,
      );
      for (final change in [
        {'amount_minor': 1},
        {'source_account_name_snapshot': 'Otra cuenta'},
        {'source_account_id': nequi},
        {'reason': 'Arriendo'},
        {'note': 'Otro detalle'},
        {'expense_account_id': 'system:opening-equity'},
      ]) {
        await expectLater(
          db.insert('treasury_operations', {...header, ...change}),
          rejected,
        );
      }
      await db.insert('treasury_operations', header);
      await expectLater(
        db.insert(
          'treasury_operations',
          header,
          conflictAlgorithm: ConflictAlgorithm.replace,
        ),
        rejected,
      );
    },
  );

  test(
    'expense document requires both exact balanced lines and no extras',
    () async {
      await draft('lines');
      await db.update(
        'journal_lines',
        {'debit_minor': 999},
        where: 'id=?',
        whereArgs: ['lines-line-1'],
      );
      await expectLater(postDocument('lines'), rejected);
      await db.update(
        'journal_lines',
        {'debit_minor': 1000},
        where: 'id=?',
        whereArgs: ['lines-line-1'],
      );
      await db.insert('journal_lines', {
        'id': 'extra',
        'entry_id': 'lines-entry',
        'sequence': 2,
        'account_id': SqliteTreasuryOperationStore.expenseAccountId,
        'debit_minor': 1,
        'credit_minor': 0,
      });
      await expectLater(postDocument('lines'), rejected);
      await db.delete('journal_lines', where: 'id=?', whereArgs: ['extra']);
      await confirm('lines');
    },
  );

  test(
    'transfer posts exactly source credit and destination debit without expense',
    () async {
      await draft('transfer', kind: 'transfer');
      await db.update(
        'journal_lines',
        {'account_id': SqliteTreasuryOperationStore.expenseAccountId},
        where: 'id=?',
        whereArgs: ['transfer-line-1'],
      );
      await expectLater(postDocument('transfer'), rejected);
      final destination = (await db.query(
        'cash_accounts',
        where: 'id=?',
        whereArgs: [nequi],
      )).single;
      await db.update(
        'journal_lines',
        {'account_id': destination['ledger_account_id']},
        where: 'id=?',
        whereArgs: ['transfer-line-1'],
      );
      await confirm('transfer');
      expect(
        (await db.query('treasury_operations')).single['expense_account_id'],
        isNull,
      );
    },
  );

  test(
    'posting cannot rewrite source facts or reverse document-entry order',
    () async {
      await draft('posting');
      await expectLater(
        db.update(
          'business_documents',
          {'status': 'posted', 'reason': 'Arriendo'},
          where: 'id=?',
          whereArgs: ['posting-document'],
        ),
        rejected,
      );
      await expectLater(
        db.update(
          'business_documents',
          {'status': 'posted', 'recorded_at_utc': '2026-10-20T11:00:00.000Z'},
          where: 'id=?',
          whereArgs: ['posting-document'],
        ),
        rejected,
      );
      await expectLater(postEntry('posting'), rejected);
      await confirm('posting');
    },
  );

  test(
    'posting requires sufficient source funds and active accounts',
    () async {
      await draft('too-large', amount: 10001);
      await expectLater(postDocument('too-large'), rejected);
      await draft('inactive', kind: 'transfer');
      await db.update(
        'cash_accounts',
        {'is_active': 0},
        where: 'id=?',
        whereArgs: [nequi],
      );
      await expectLater(postDocument('inactive'), rejected);
    },
  );

  test(
    'draft metadata changes are revalidated against immutable source facts',
    () async {
      await draft('metadata');
      await db.update(
        'business_documents',
        {'reason': 'Arriendo'},
        where: 'id=?',
        whereArgs: ['metadata-document'],
      );
      await expectLater(postDocument('metadata'), rejected);
      await db.update(
        'business_documents',
        {'reason': 'Aseo', 'recorded_at_utc': '2026-10-20T11:00:00.000Z'},
        where: 'id=?',
        whereArgs: ['metadata-document'],
      );
      await expectLater(postDocument('metadata'), rejected);
      await db.update(
        'business_documents',
        {'recorded_at_utc': _time},
        where: 'id=?',
        whereArgs: ['metadata-document'],
      );
      await confirm('metadata');
    },
  );

  test(
    'document posting reserves money before its journal is posted',
    () async {
      await draft('first', amount: 7000);
      await draft('second', amount: 7000);
      await postDocument('first');
      await expectLater(postDocument('second'), rejected);
      await postEntry('first');
    },
  );

  test(
    'destination chronology is checked at document and entry posting',
    () async {
      await draft(
        'earlier',
        kind: 'transfer',
        source: cash,
        destination: nequi,
      );
      await draft('later', source: nequi, time: '2026-10-20T11:00:00.000Z');
      await confirm('later');
      await expectLater(postDocument('earlier'), rejected);
    },
  );

  test(
    'entry posting rechecks chronology after the document was already posted',
    () async {
      await draft('earlier', kind: 'transfer');
      await postDocument('earlier');
      await draft('later', source: nequi, time: '2026-10-20T11:00:00.000Z');
      await confirm('later');
      await expectLater(postEntry('earlier'), rejected);
    },
  );

  test(
    'confirmed treasury facts and journal cannot be edited deleted or replaced',
    () async {
      final header = await draft('fixed');
      await confirm('fixed');
      await expectLater(
        db.update(
          'treasury_operations',
          {'note': 'changed'},
          where: 'document_id=?',
          whereArgs: ['fixed-document'],
        ),
        rejected,
      );
      await expectLater(
        db.delete(
          'treasury_operations',
          where: 'document_id=?',
          whereArgs: ['fixed-document'],
        ),
        rejected,
      );
      await expectLater(
        db.insert(
          'treasury_operations',
          header,
          conflictAlgorithm: ConflictAlgorithm.replace,
        ),
        rejected,
      );
      await expectLater(
        db.update(
          'journal_lines',
          {'debit_minor': 1},
          where: 'id=?',
          whereArgs: ['fixed-line-1'],
        ),
        rejected,
      );
      await expectLater(
        db.delete('journal_lines', where: 'id=?', whereArgs: ['fixed-line-1']),
        rejected,
      );
      final line = (await db.query(
        'journal_lines',
        where: 'id=?',
        whereArgs: ['fixed-line-1'],
      )).single;
      await expectLater(
        db.insert(
          'journal_lines',
          line,
          conflictAlgorithm: ConflictAlgorithm.replace,
        ),
        rejected,
      );
      final entry = (await db.query(
        'journal_entries',
        where: 'id=?',
        whereArgs: ['fixed-entry'],
      )).single;
      await expectLater(
        db.insert(
          'journal_entries',
          entry,
          conflictAlgorithm: ConflictAlgorithm.replace,
        ),
        rejected,
      );
      await expectLater(
        db.update(
          'treasury_operation_requests',
          {'status': 'rejected', 'rejection_reason': 'changed'},
          where: 'command_id=?',
          whereArgs: ['fixed'],
        ),
        rejected,
      );
    },
  );
}
