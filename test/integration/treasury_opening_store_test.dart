import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/domain/money.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/schema.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_inventory_opening_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_opening.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/reference_inventory.dart';
import 'package:valinor_sanctum_2/features/stock_intake/data/sqlite_cash_opening_recorder.dart';
import 'package:valinor_sanctum_2/features/stock_intake/domain/stock_intake_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_opening_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_store.dart';
import 'package:valinor_sanctum_2/features/treasury/domain/treasury_opening.dart';
import 'package:valinor_sanctum_2/features/workspace/data/sqlite_workspace_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase app;
  late SqliteTreasuryOpeningStore store;
  final sourceSha = List.filled(64, 'a').join();
  final snapshotSha = List.filled(64, 'b').join();
  final occurred = DateTime.utc(2026, 10, 20, 15);

  Future<void> configure(AppDatabase db) async {
    await SqliteWorkspaceStore(db).createProfile(
      BusinessProfile(
        profileId: 'treasury-opening-test',
        businessName: 'Tienda sintética',
        currencyCode: 'COP',
        moneyScale: 2,
        timezone: 'America/Bogota',
        createdAtUtc: DateTime.utc(2026, 10, 20),
      ),
    );
    await SqliteTreasuryStore(db).ensureDefaults();
  }

  setUp(() async {
    app = await AppDatabase.open(path: inMemoryDatabasePath);
    await configure(app);
    store = SqliteTreasuryOpeningStore(app, synthetic: true);
  });
  tearDown(() => app.close());

  TreasuryOpeningCommand command({
    String id = 'treasury-opening-command',
    int cash = 10000,
    int nequi = 25000,
    int reserve = -2000,
    int receivables = 5000,
    String? hash,
    DateTime? time,
    Map<String, Object?>? metadata,
  }) => TreasuryOpeningCommand(
    commandId: id,
    sourceSha256: sourceSha,
    snapshotSha256: hash ?? snapshotSha,
    occurredAtUtc: time ?? occurred,
    cashMinor: cash,
    nequiMinor: nequi,
    reserveMinor: reserve,
    receivablesMinor: receivables,
    sourceMetadata:
        metadata ??
        {
          'sourceName': 'synthetic.db',
          'rows': {'cash': 2, 'nequi': 4, 'reserve': 7, 'receivables': 3},
        },
  );

  Future<Map<String, List<Map<String, Object?>>>> allRows(
    DatabaseExecutor db,
  ) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND substr(name,1,7)<>'sqlite_' ORDER BY name",
    );
    return {
      for (final table in tables)
        table['name'] as String: await db.query(table['name'] as String),
    };
  }

  test(
    'opening preserves a negative reserve and posts only exact opening equity',
    () async {
      final result = await store.importOpening(command());
      expect(result.replayed, isFalse);
      final opening = (await app.database.query('treasury_openings')).single;
      expect(opening['cash_minor'], 10000);
      expect(opening['reserve_minor'], -2000);
      expect(opening['receivables_minor'], 5000);
      expect(opening['source_sha256'], sourceSha);
      expect(
        jsonDecode(opening['source_metadata_json'] as String),
        command().sourceMetadata,
      );
      final document = (await app.database.query('business_documents')).single;
      expect(document['type'], 'treasury_opening');
      expect(document['status'], 'posted');
      expect(document['date_quality'], 'reconstructed');
      expect(document['business_date'], '2026-10-20');
      final lines = await app.database.query(
        'journal_lines',
        orderBy: 'sequence',
      );
      expect(lines.map((line) => [line['debit_minor'], line['credit_minor']]), [
        [10000, 0],
        [25000, 0],
        [0, 2000],
        [5000, 0],
        [0, 38000],
      ]);
      expect(lines.last['account_id'], 'system:opening-equity');
      final money = await SqliteTreasuryStore(app).load();
      expect(money.cashMinor, 10000);
      expect(money.nequiMinor, 25000);
      expect(money.reserveMinor, -2000);
      expect(money.totalAvailableMinor, 35000);
      for (final table in [
        'cash_openings',
        'sales',
        'customer_receivables',
        'collections',
        'purchases',
        'supplier_payments',
        'obligations',
        'inventory_movements',
      ]) {
        expect(await app.database.query(table), isEmpty, reason: table);
      }
      expect((await app.readHealth())['foreignKeyViolations'], 0);
    },
  );

  test(
    'canonical replay is exact and independent of metadata key ordering',
    () async {
      final first = await store.importOpening(
        command(
          metadata: {
            'b': {'y': 2, 'x': 1},
            'a': 0,
          },
        ),
      );
      final before = await allRows(app.database);
      final second = await store.importOpening(
        command(
          metadata: {
            'a': 0,
            'b': {'x': 1, 'y': 2},
          },
        ),
      );
      expect(second.documentId, first.documentId);
      expect(second.replayed, isTrue);
      expect(await allRows(app.database), before);
      await expectLater(
        store.importOpening(command(cash: 10001)),
        throwsA(isA<TreasuryOpeningValidationException>()),
      );
      await expectLater(
        store.importOpening(command(id: 'other-command')),
        throwsA(isA<TreasuryOpeningValidationException>()),
      );
      expect(await allRows(app.database), before);
    },
  );

  test(
    'all zero is recorded without invented journal lines and blocks a later manual opening',
    () async {
      await store.importOpening(
        command(cash: 0, nequi: 0, reserve: 0, receivables: 0),
      );
      expect(await app.database.query('treasury_openings'), hasLength(1));
      expect(await app.database.query('journal_lines'), isEmpty);
      expect(
        (await app.database.query('journal_entries')).single['status'],
        'posted',
      );
      final before = await allRows(app.database);
      await expectLater(
        SqliteCashOpeningRecorder(app, synthetic: true).record(
          CashOpeningCommand(
            commandId: 'manual-after-import',
            paymentOptionId: 'quick-default:EFECTIVO',
            amountMinor: 100,
            occurredAtUtc: occurred.add(const Duration(minutes: 1)),
          ),
        ),
        throwsA(anything),
      );
      expect(await allRows(app.database), before);
    },
  );

  test(
    'an identical replay remains available after a money account is archived',
    () async {
      final first = await store.importOpening(command());
      await app.database.update(
        'cash_accounts',
        {'is_active': 0},
        where: 'id=?',
        whereArgs: ['treasury:main-cash'],
      );
      final before = await allRows(app.database);
      final replay = await store.importOpening(command());
      expect(replay.replayed, isTrue);
      expect(replay.documentId, first.documentId);
      expect(await allRows(app.database), before);
    },
  );

  test(
    'negative net equity posts as a debit and cancelling assets do not invent equity',
    () async {
      await store.importOpening(
        command(cash: -400, nequi: 100, reserve: 0, receivables: 0),
      );
      final equity = (await app.database.query(
        'journal_lines',
        where: 'account_id=?',
        whereArgs: ['system:opening-equity'],
      )).single;
      expect(equity['debit_minor'], 300);
      expect(equity['credit_minor'], 0);
    },
  );

  test('equal positive and negative balances need no equity line', () async {
    await store.importOpening(
      command(cash: 100, nequi: 0, reserve: -100, receivables: 0),
    );
    expect(await app.database.query('journal_lines'), hasLength(2));
    expect(
      await app.database.query(
        'journal_lines',
        where: 'account_id=?',
        whereArgs: ['system:opening-equity'],
      ),
      isEmpty,
    );
  });

  test(
    'one missing account and negative debt reject without partial writes',
    () async {
      final before = await allRows(app.database);
      await expectLater(
        store.importOpening(command(receivables: -1)),
        throwsA(isA<TreasuryOpeningValidationException>()),
      );
      expect(await allRows(app.database), before);
      await app.database.update(
        'cash_accounts',
        {'is_available': 0},
        where: 'id=?',
        whereArgs: ['treasury:main-cash'],
      );
      final unavailable = await allRows(app.database);
      await expectLater(
        store.importOpening(command()),
        throwsA(isA<TreasuryOpeningValidationException>()),
      );
      expect(await allRows(app.database), unavailable);
    },
  );

  test(
    'overflowing debit totals and minimum signed integer reject even when net would cancel',
    () async {
      final max = Money.maxMinorUnits.toInt();
      final before = await allRows(app.database);
      for (final bad in [
        command(cash: max, nequi: 1, reserve: -max, receivables: 0),
        command(
          cash: Money.minMinorUnits.toInt(),
          nequi: 0,
          reserve: 0,
          receivables: 0,
        ),
      ]) {
        await expectLater(
          store.importOpening(bad),
          throwsA(isA<TreasuryOpeningValidationException>()),
        );
      }
      expect(await allRows(app.database), before);
      await store.importOpening(
        command(cash: max, nequi: 0, reserve: -max, receivables: 0),
      );
      expect(await app.database.query('journal_lines'), hasLength(2));
    },
  );

  test(
    'a late SQL failure rolls back command, provenance, ledgers and journal together',
    () async {
      final before = await allRows(app.database);
      await app.database.execute('''
CREATE TRIGGER synthetic_treasury_late_failure BEFORE UPDATE OF status ON journal_entries
WHEN NEW.status='posted' AND EXISTS (SELECT 1 FROM treasury_openings WHERE document_id=NEW.document_id)
BEGIN SELECT RAISE(ABORT,'synthetic late failure'); END
''');
      await expectLater(
        store.importOpening(command()),
        throwsA(isA<DatabaseException>()),
      );
      expect(await allRows(app.database), before);
    },
  );

  test(
    'document posting rejects a journal mutated after line creation',
    () async {
      final before = await allRows(app.database);
      await app.database.execute('''
CREATE TRIGGER synthetic_corrupt_treasury AFTER INSERT ON journal_lines
WHEN NEW.account_id='system:opening-equity'
BEGIN UPDATE journal_lines SET credit_minor=credit_minor+1 WHERE id=NEW.id; END
''');
      await expectLater(
        store.importOpening(command()),
        throwsA(isA<DatabaseException>()),
      );
      expect(await allRows(app.database), before);
    },
  );

  test(
    'an existing manual opening blocks legacy balances without touching it',
    () async {
      await SqliteCashOpeningRecorder(app, synthetic: true).record(
        CashOpeningCommand(
          commandId: 'manual-before-import',
          paymentOptionId: 'quick-default:NEQUI',
          amountMinor: 500,
          occurredAtUtc: occurred.subtract(const Duration(minutes: 1)),
        ),
      );
      final before = await allRows(app.database);
      await expectLater(
        store.importOpening(command()),
        throwsA(isA<TreasuryOpeningValidationException>()),
      );
      expect(await allRows(app.database), before);
    },
  );

  test(
    'a posted own cash movement blocks the import even without a cash opening',
    () async {
      await app.database.insert('actors', {
        'id': 'synthetic-actor',
        'display_name': 'Operador',
        'kind': 'synthetic',
        'is_active': 1,
        'created_at_utc': occurred.toIso8601String(),
      });
      await app.database.insert('ledger_accounts', {
        'id': 'synthetic-equity',
        'code': 'SYNTHETIC-EQ',
        'name': 'Aporte sintético',
        'class': 'equity',
        'role': 'equity',
        'is_active': 1,
      });
      await app.database.insert('command_log', {
        'id': 'own-command',
        'command_type': 'synthetic_contribution',
        'payload_hash': 'synthetic',
        'actor_id': 'synthetic-actor',
        'response_json': '{}',
        'response_version': 1,
        'committed_at_utc': occurred.toIso8601String(),
        'authorization_policy_version': 'development-single-user-v1',
      });
      await app.database.insert('business_documents', {
        'id': 'own-document',
        'command_id': 'own-command',
        'command_sequence': 0,
        'profile_id': 'treasury-opening-test',
        'actor_id': 'synthetic-actor',
        'type': 'synthetic_contribution',
        'status': 'posted',
        'occurred_at_utc': occurred.toIso8601String(),
        'business_date': '2026-10-20',
        'recorded_at_utc': occurred.toIso8601String(),
        'source_kind': 'synthetic',
        'date_quality': 'documented',
      });
      await app.database.insert('journal_entries', {
        'id': 'own-entry',
        'document_id': 'own-document',
        'status': 'draft',
        'cost_completeness': 'not_applicable',
      });
      final cash = (await app.database.rawQuery(
        "SELECT cash.ledger_account_id FROM cash_accounts cash JOIN quick_payment_options option ON option.cash_account_id=cash.id WHERE option.id='quick-default:EFECTIVO'",
      )).single['ledger_account_id'];
      for (final pair in [
        (cash, 100, 0),
        ('synthetic-equity', 0, 100),
      ].indexed) {
        await app.database.insert('journal_lines', {
          'id': 'own-line-${pair.$1}',
          'entry_id': 'own-entry',
          'sequence': pair.$1,
          'account_id': pair.$2.$1,
          'debit_minor': pair.$2.$2,
          'credit_minor': pair.$2.$3,
        });
      }
      await app.database.update(
        'journal_entries',
        {'status': 'posted', 'posted_at_utc': occurred.toIso8601String()},
        where: 'id=?',
        whereArgs: ['own-entry'],
      );
      final before = await allRows(app.database);
      await expectLater(
        store.importOpening(command()),
        throwsA(isA<TreasuryOpeningValidationException>()),
      );
      expect(await allRows(app.database), before);
    },
  );

  test(
    'existing initial inventory is preserved by the separate treasury opening',
    () async {
      await app.close();
      app = await AppDatabase.open(path: inMemoryDatabasePath);
      await SqliteInventoryOpeningStore(app, synthetic: true).open(
        InventoryOpeningCommand(
          commandId: 'synthetic-stock-opening',
          reference: ReferenceInventory(
            sourceName: 'synthetic.db',
            sourceSha256: sourceSha,
            capturedAtUtc: occurred,
            products: [
              const ReferenceInventoryProduct(
                id: '1',
                name: 'Producto sintético',
                quantity: 2,
                priceMinor: 1000,
                purchasePriceMinor: 500,
                category: 'producto',
              ),
            ],
          ),
          snapshotSha256: List.filled(64, 'c').join(),
          occurredAtUtc: occurred,
          zeroCostsConfirmed: false,
        ),
        initialProfile: BusinessProfile(
          profileId: 'treasury-opening-test',
          businessName: 'Tienda sintética',
          currencyCode: 'COP',
          moneyScale: 2,
          timezone: 'America/Bogota',
          createdAtUtc: occurred,
        ),
      );
      await SqliteTreasuryStore(app).ensureDefaults();
      final before = {
        for (final table in [
          'catalog_items',
          'inventory_openings',
          'inventory_opening_items',
        ])
          table: await app.database.query(table),
      };
      await SqliteTreasuryOpeningStore(
        app,
        synthetic: true,
      ).importOpening(command());
      for (final table in before.keys) {
        expect(await app.database.query(table), before[table]);
      }
      expect(await app.database.query('journal_entries'), hasLength(2));
    },
  );

  test(
    'confirmed opening facts and lines cannot be replaced or edited',
    () async {
      await store.importOpening(command());
      await app.database.execute('PRAGMA recursive_triggers=OFF');
      final opening = (await app.database.query('treasury_openings')).single;
      final entry = (await app.database.query('journal_entries')).single;
      final line = (await app.database.query('journal_lines')).first;
      final before = await allRows(app.database);
      for (final operation in <Future<void> Function()>[
        () async {
          await app.database.update('treasury_openings', {'reserve_minor': 0});
        },
        () async {
          await app.database.delete('treasury_openings');
        },
        () async {
          await app.database.insert(
            'treasury_openings',
            opening,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        },
        () async {
          await app.database.insert(
            'journal_entries',
            entry,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        },
        () async {
          await app.database.insert(
            'journal_lines',
            line,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        },
        () async {
          await app.database.update(
            'journal_lines',
            {'debit_minor': 1},
            where: 'id=?',
            whereArgs: [line['id']],
          );
        },
        () async {
          await app.database.delete(
            'journal_lines',
            where: 'id=?',
            whereArgs: [line['id']],
          );
        },
      ]) {
        await expectLater(operation(), throwsA(isA<DatabaseException>()));
        expect(await allRows(app.database), before);
      }
    },
  );

  test(
    'disk replay survives reopening and v8 migrates with an exact v8 backup',
    () async {
      final fixtureRoot = Directory(
        p.join(Directory.current.path, 'tmp', 'treasury_opening_tests'),
      );
      await fixtureRoot.create(recursive: true);
      final fixture = await fixtureRoot.createTemp('v8_');
      final path = p.join(fixture.path, 'synthetic.sqlite3');
      try {
        final old = await databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(singleInstance: false),
        );
        await old.execute('PRAGMA foreign_keys=ON');
        final migrations = [
          DatabaseSchema.statements,
          DatabaseSchema.migration2Statements,
          DatabaseSchema.migration3Statements,
          DatabaseSchema.migration4Statements,
          DatabaseSchema.migration5Statements,
          DatabaseSchema.migration6Statements,
          DatabaseSchema.migration7Statements,
          DatabaseSchema.migration8Statements,
        ];
        for (final pair in migrations.indexed) {
          for (final statement in pair.$2) {
            await old.execute(statement);
          }
          await old.insert('schema_migrations', {
            'version': pair.$1 + 1,
            'name': DatabaseSchema.nameForVersion(pair.$1 + 1),
            'migration_checksum': DatabaseSchema.checksumForVersion(
              pair.$1 + 1,
            ),
            'schema_checksum': await _schemaChecksum(old),
            'applied_at_utc': occurred.toIso8601String(),
          });
        }
        await old.execute(
          'PRAGMA application_id=${DatabaseSchema.applicationId}',
        );
        await old.execute('PRAGMA user_version=8');
        await old.insert('actors', {
          'id': 'preserved-v8-actor',
          'display_name': 'Actor sintético',
          'kind': 'synthetic',
          'is_active': 1,
          'created_at_utc': occurred.toIso8601String(),
        });
        final before = await allRows(old);
        await old.close();
        var migrated = await AppDatabase.open(path: path);
        for (final table in before.keys) {
          final after = await migrated.database.query(table);
          expect(
            table == 'schema_migrations' ? after.take(8).toList() : after,
            before[table],
            reason: table,
          );
        }
        expect(
          (await migrated.readHealth())['schemaVersion'],
          DatabaseSchema.version,
        );
        await configure(migrated);
        final first = await SqliteTreasuryOpeningStore(
          migrated,
          synthetic: true,
        ).importOpening(command());
        await migrated.close();
        migrated = await AppDatabase.open(path: path);
        final replay = await SqliteTreasuryOpeningStore(
          migrated,
          synthetic: true,
        ).importOpening(command());
        expect(replay.replayed, isTrue);
        expect(replay.documentId, first.documentId);
        expect(
          await migrated.database.query('treasury_openings'),
          hasLength(1),
        );
        await migrated.close();
        final backups = await Directory(
          p.join(fixture.path, 'backups'),
        ).list().toList();
        expect(backups, hasLength(1));
        expect(p.basename(backups.single.path), contains('.v8.'));
        final backup = await databaseFactoryFfi.openDatabase(
          backups.single.path,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
        );
        try {
          await backup.execute('PRAGMA query_only=ON');
          expect(await backup.getVersion(), 8);
          expect(await allRows(backup), before);
          expect(await backup.rawQuery('PRAGMA foreign_key_check'), isEmpty);
        } finally {
          await backup.close();
        }
      } finally {
        final target = await fixture.resolveSymbolicLinks();
        if (!p.isWithin(await fixtureRoot.resolveSymbolicLinks(), target)) {
          throw StateError('Unsafe fixture cleanup');
        }
        await Directory(target).delete(recursive: true);
      }
    },
  );
}

Future<String> _schemaChecksum(DatabaseExecutor db) async {
  final rows = await db.rawQuery(
    "SELECT type,name,tbl_name,sql FROM sqlite_master WHERE substr(name,1,7)<>'sqlite_' ORDER BY type,name",
  );
  return DatabaseSchema.checksum(
    jsonEncode(
      rows
          .map((row) => [row['type'], row['name'], row['tbl_name'], row['sql']])
          .toList(),
    ),
  );
}
