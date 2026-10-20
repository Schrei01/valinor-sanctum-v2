import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/schema.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_store.dart';
import 'package:valinor_sanctum_2/features/workspace/data/sqlite_workspace_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';

const _time = '2026-10-20T15:00:00.000Z';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase app;
  late Database db;
  late String cashId;
  late String nequiId;
  setUp(() async {
    app = await AppDatabase.open(path: inMemoryDatabasePath);
    db = app.database;
    await SqliteWorkspaceStore(app).createProfile(
      BusinessProfile(
        profileId: 'treasury-schema',
        businessName: 'Tienda sintética',
        currencyCode: 'COP',
        moneyScale: 2,
        timezone: 'America/Bogota',
        createdAtUtc: DateTime.utc(2026, 10, 20),
      ),
    );
    await SqliteTreasuryStore(app).ensureDefaults();
    final options = await db.query('quick_payment_options');
    cashId =
        options.singleWhere(
              (row) => row['id'] == 'quick-default:EFECTIVO',
            )['cash_account_id']
            as String;
    nequiId =
        options.singleWhere(
              (row) => row['id'] == 'quick-default:NEQUI',
            )['cash_account_id']
            as String;
    await db.insert('actors', {
      'id': 'schema-actor',
      'display_name': 'Operador sintético',
      'kind': 'synthetic',
      'is_active': 1,
      'created_at_utc': _time,
    });
    for (final spec in [
      ('system:opening-equity', 'EQ', 'equity', 'opening_balance'),
      (
        'system:legacy-customer-receivables',
        'LEGACY-AR',
        'asset',
        'receivable',
      ),
    ]) {
      await db.insert('ledger_accounts', {
        'id': spec.$1,
        'code': spec.$2,
        'name': spec.$1,
        'class': spec.$3,
        'role': spec.$4,
        'is_active': 1,
      });
    }
  });
  tearDown(() => app.close());

  Future<Map<String, Object?>> draft({
    int cash = 100,
    int nequi = 200,
    int reserve = -50,
    int receivables = 75,
    bool insertHeader = true,
  }) async {
    final source = List.filled(64, 'a').join();
    final snapshot = List.filled(64, 'b').join();
    final metadata = {'note': 'synthetic'};
    final canonical = jsonEncode({
      'version': 1,
      'profileId': 'treasury-schema',
      'currency': 'COP',
      'scale': 2,
      'sourceSha256': source,
      'snapshotSha256': snapshot,
      'occurredAtUtc': _time,
      'cashAccountId': cashId,
      'nequiAccountId': nequiId,
      'reserveAccountId': 'treasury:main-cash',
      'cashMinor': cash,
      'nequiMinor': nequi,
      'reserveMinor': reserve,
      'receivablesMinor': receivables,
      'sourceMetadata': metadata,
    });
    await db.insert('command_log', {
      'id': 'opening-command',
      'command_type': 'treasury_opening',
      'payload_hash': DatabaseSchema.checksum(canonical),
      'actor_id': 'schema-actor',
      'response_json': jsonEncode({
        'canonicalPayload': canonical,
        'documentId': 'opening-document',
      }),
      'response_version': 1,
      'committed_at_utc': _time,
      'authorization_policy_version': 'development-single-user-v1',
    });
    await db.insert('business_documents', {
      'id': 'opening-document',
      'command_id': 'opening-command',
      'command_sequence': 0,
      'profile_id': 'treasury-schema',
      'actor_id': 'schema-actor',
      'type': 'treasury_opening',
      'status': 'draft',
      'occurred_at_utc': _time,
      'business_date': '2026-10-20',
      'recorded_at_utc': _time,
      'source_kind': 'synthetic',
      'date_quality': 'reconstructed',
    });
    final header = <String, Object?>{
      'document_id': 'opening-document',
      'command_id': 'opening-command',
      'profile_id': 'treasury-schema',
      'cash_account_id': cashId,
      'nequi_account_id': nequiId,
      'reserve_account_id': 'treasury:main-cash',
      'cash_minor': cash,
      'nequi_minor': nequi,
      'reserve_minor': reserve,
      'receivables_minor': receivables,
      'source_sha256': source,
      'snapshot_sha256': snapshot,
      'source_metadata_json': jsonEncode(metadata),
      'occurred_at_utc': _time,
    };
    if (insertHeader) {
      await db.insert('treasury_openings', header);
    }
    return header;
  }

  Future<void> journal() async {
    await db.insert('journal_entries', {
      'id': 'opening-entry',
      'document_id': 'opening-document',
      'status': 'draft',
      'cost_completeness': 'not_applicable',
    });
    final expected = await db.query(
      'treasury_opening_expected_lines',
      where: 'document_id=?',
      whereArgs: ['opening-document'],
    );
    for (final pair in expected.indexed) {
      await db.insert('journal_lines', {
        'id': 'opening-line-${pair.$1}',
        'entry_id': 'opening-entry',
        'sequence': pair.$1,
        'account_id': pair.$2['account_id'],
        'debit_minor': pair.$2['debit_minor'],
        'credit_minor': pair.$2['credit_minor'],
      });
    }
  }

  Future<int> postDocument() => db.update(
    'business_documents',
    {'status': 'posted'},
    where: 'id=?',
    whereArgs: ['opening-document'],
  );
  Future<int> postEntry() => db.update(
    'journal_entries',
    {'status': 'posted', 'posted_at_utc': _time},
    where: 'id=?',
    whereArgs: ['opening-entry'],
  );

  test(
    'v9 appends to the immutable released migrations without seeding financial facts',
    () async {
      expect(DatabaseSchema.version, 9);
      expect(DatabaseSchema.migrationChecksum, 'fnv1a64:2b8aa24f7fdff6d1');
      expect(DatabaseSchema.migration2Checksum, 'fnv1a64:7c3f94396eb01ba3');
      expect(DatabaseSchema.migration3Checksum, 'fnv1a64:c719534b847edc09');
      expect(DatabaseSchema.migration4Checksum, 'fnv1a64:b669041fbf59266d');
      expect(DatabaseSchema.migration5Checksum, 'fnv1a64:aaf6156fd67b9099');
      expect(DatabaseSchema.migration6Checksum, 'fnv1a64:4ccd48022ac15ecc');
      for (final table in [
        'treasury_openings',
        'business_documents',
        'journal_entries',
        'journal_lines',
      ]) {
        expect(await db.query(table), isEmpty);
      }
    },
  );

  test(
    'header cannot claim amounts or provenance absent from its canonical command',
    () async {
      final header = await draft(insertHeader: false);
      for (final changes in [
        <String, Object?>{'cash_minor': 101},
        <String, Object?>{'source_metadata_json': '{}'},
        <String, Object?>{'snapshot_sha256': List.filled(64, 'c').join()},
      ]) {
        await expectLater(
          db.insert('treasury_openings', {...header, ...changes}),
          throwsA(isA<DatabaseException>()),
        );
      }
      expect(await db.query('treasury_openings'), isEmpty);
      await db.insert('treasury_openings', header);
    },
  );

  test(
    'floating money and an overflowing aggregate cannot enter the opening table',
    () async {
      final header = await draft(insertHeader: false);
      for (final changes in [
        <String, Object?>{'cash_minor': 1.5},
        <String, Object?>{'receivables_minor': -1},
        <String, Object?>{'cash_minor': 9223372036854775807, 'nequi_minor': 1},
      ]) {
        await expectLater(
          db.insert('treasury_openings', {...header, ...changes}),
          throwsA(isA<DatabaseException>()),
        );
      }
    },
  );

  test(
    'posting rejects an equity counterparty with the same amount but wrong identity',
    () async {
      await draft();
      await journal();
      await db.insert('ledger_accounts', {
        'id': 'wrong-equity',
        'code': 'WRONG-EQ',
        'name': 'Equity sintético',
        'class': 'equity',
        'role': 'opening_balance',
        'is_active': 1,
      });
      await db.update(
        'journal_lines',
        {'account_id': 'wrong-equity'},
        where: 'account_id=?',
        whereArgs: ['system:opening-equity'],
      );
      await expectLater(postDocument(), throwsA(isA<DatabaseException>()));
    },
  );

  test(
    'posting requires each configured cash role and all expected lines exactly once',
    () async {
      await draft();
      await journal();
      final line = (await db.query(
        'journal_lines',
        where: 'account_id=?',
        whereArgs: ['system:legacy-customer-receivables'],
      )).single;
      await db.delete('journal_lines', where: 'id=?', whereArgs: [line['id']]);
      await expectLater(postDocument(), throwsA(isA<DatabaseException>()));
      await db.insert('journal_lines', line);
      await db.update(
        'cash_accounts',
        {'is_available': 0},
        where: 'id=?',
        whereArgs: ['treasury:main-cash'],
      );
      await expectLater(postDocument(), throwsA(isA<DatabaseException>()));
      await db.update(
        'cash_accounts',
        {'is_available': 1},
        where: 'id=?',
        whereArgs: ['treasury:main-cash'],
      );
      await postDocument();
      await postEntry();
    },
  );

  test(
    'document posting freezes its journal before the journal is posted',
    () async {
      await draft();
      await journal();
      await postDocument();
      await db.execute('PRAGMA recursive_triggers=OFF');
      final entry = (await db.query('journal_entries')).single;
      final lines = await db.query('journal_lines', orderBy: 'sequence');
      for (final operation in <Future<void> Function()>[
        () async {
          await db.delete('journal_entries');
        },
        () async {
          await db.insert(
            'journal_entries',
            entry,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        },
        () async {
          await db.insert(
            'journal_lines',
            lines.first,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        },
        () async {
          await db.update(
            'journal_lines',
            {'debit_minor': 1},
            where: 'id=?',
            whereArgs: [lines.first['id']],
          );
        },
        () async {
          await db.delete(
            'journal_lines',
            where: 'id=?',
            whereArgs: [lines.first['id']],
          );
        },
      ]) {
        await expectLater(operation(), throwsA(isA<DatabaseException>()));
        expect(await db.query('journal_lines', orderBy: 'sequence'), lines);
      }
      await postEntry();
    },
  );

  test(
    'zero opening cannot acquire a fake journal line or grant the exception to an ordinary document',
    () async {
      await draft(cash: 0, nequi: 0, reserve: 0, receivables: 0);
      await journal();
      await postDocument();
      await postEntry();
      expect(await db.query('journal_lines'), isEmpty);
      await db.insert('business_documents', {
        'id': 'ordinary-document',
        'command_id': 'opening-command',
        'command_sequence': 1,
        'profile_id': 'treasury-schema',
        'actor_id': 'schema-actor',
        'type': 'ordinary',
        'status': 'posted',
        'occurred_at_utc': _time,
        'business_date': '2026-10-20',
        'recorded_at_utc': _time,
        'source_kind': 'synthetic',
        'date_quality': 'documented',
      });
      await db.insert('journal_entries', {
        'id': 'ordinary-entry',
        'document_id': 'ordinary-document',
        'status': 'draft',
        'cost_completeness': 'not_applicable',
      });
      await expectLater(
        db.update(
          'journal_entries',
          {'status': 'posted', 'posted_at_utc': _time},
          where: 'id=?',
          whereArgs: ['ordinary-entry'],
        ),
        throwsA(isA<DatabaseException>()),
      );
    },
  );

  test(
    'own cash cannot be backdated before an imported zero opening',
    () async {
      await draft(cash: 0, nequi: 0, reserve: 0, receivables: 0);
      await journal();
      await postDocument();
      await postEntry();
      await db.insert('business_documents', {
        'id': 'backdated-document',
        'command_id': 'opening-command',
        'command_sequence': 1,
        'profile_id': 'treasury-schema',
        'actor_id': 'schema-actor',
        'type': 'ordinary',
        'status': 'draft',
        'occurred_at_utc': '2026-10-19T15:00:00.000Z',
        'business_date': '2026-10-19',
        'recorded_at_utc': _time,
        'source_kind': 'synthetic',
        'date_quality': 'documented',
      });
      await db.insert('journal_entries', {
        'id': 'backdated-entry',
        'document_id': 'backdated-document',
        'status': 'draft',
        'cost_completeness': 'not_applicable',
      });
      final ledger = (await db.query(
        'cash_accounts',
        where: 'id=?',
        whereArgs: [cashId],
      )).single['ledger_account_id'];
      for (final pair in [
        (ledger, 100, 0),
        ('system:opening-equity', 0, 100),
      ].indexed) {
        await db.insert('journal_lines', {
          'id': 'backdated-line-${pair.$1}',
          'entry_id': 'backdated-entry',
          'sequence': pair.$1,
          'account_id': pair.$2.$1,
          'debit_minor': pair.$2.$2,
          'credit_minor': pair.$2.$3,
        });
      }
      await expectLater(
        db.update(
          'business_documents',
          {'status': 'posted'},
          where: 'id=?',
          whereArgs: ['backdated-document'],
        ),
        throwsA(isA<DatabaseException>()),
      );
    },
  );

  test(
    'journal posting rejects an older generic document posted before its money lines existed',
    () async {
      await draft(cash: 0, nequi: 0, reserve: 0, receivables: 0);
      await journal();
      await postDocument();
      await postEntry();
      // Generic documents may already be posted when their draft journal is
      // assembled. Posting the entry must enforce the same opening cutoff.
      await db.insert('business_documents', {
        'id': 'early-posted-document',
        'command_id': 'opening-command',
        'command_sequence': 1,
        'profile_id': 'treasury-schema',
        'actor_id': 'schema-actor',
        'type': 'ordinary',
        'status': 'posted',
        'occurred_at_utc': '2026-10-19T15:00:00.000Z',
        'business_date': '2026-10-19',
        'recorded_at_utc': _time,
        'source_kind': 'synthetic',
        'date_quality': 'documented',
      });
      await db.insert('journal_entries', {
        'id': 'late-money-entry',
        'document_id': 'early-posted-document',
        'status': 'draft',
        'cost_completeness': 'not_applicable',
      });
      final ledger = (await db.query(
        'cash_accounts',
        where: 'id=?',
        whereArgs: [cashId],
      )).single['ledger_account_id'];
      for (final pair in [
        (ledger, 100, 0),
        ('system:opening-equity', 0, 100),
      ].indexed) {
        await db.insert('journal_lines', {
          'id': 'late-money-line-${pair.$1}',
          'entry_id': 'late-money-entry',
          'sequence': pair.$1,
          'account_id': pair.$2.$1,
          'debit_minor': pair.$2.$2,
          'credit_minor': pair.$2.$3,
        });
      }
      await expectLater(
        db.update(
          'journal_entries',
          {'status': 'posted', 'posted_at_utc': _time},
          where: 'id=?',
          whereArgs: ['late-money-entry'],
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        (await db.query(
          'journal_entries',
          where: 'id=?',
          whereArgs: ['late-money-entry'],
        )).single['status'],
        'draft',
      );
      final snapshot = await SqliteTreasuryStore(app).load();
      expect(snapshot.cashMinor, 0);
      expect(snapshot.nequiMinor, 0);
      expect(snapshot.reserveMinor, 0);
    },
  );
}
