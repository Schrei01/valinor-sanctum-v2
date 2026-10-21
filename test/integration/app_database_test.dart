import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/schema.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory fixtureDirectory;

  setUp(() async {
    final root = Directory(
      p.join(Directory.current.path, 'tmp', 'database_tests'),
    );
    await root.create(recursive: true);
    fixtureDirectory = await root.createTemp('fixture_');
  });

  tearDown(() async {
    if (await fixtureDirectory.exists()) {
      final allowedRoot = await Directory(
        p.join(Directory.current.path, 'tmp', 'database_tests'),
      ).resolveSymbolicLinks();
      final target = await fixtureDirectory.resolveSymbolicLinks();
      if (!p.isWithin(allowedRoot, target)) {
        throw StateError(
          'Refusing to delete a fixture outside the test directory',
        );
      }
      await Directory(target).delete(recursive: true);
    }
  });

  test(
    'fresh schema has integrity and no invented configuration or balances',
    () async {
      final app = await AppDatabase.open(path: inMemoryDatabasePath);
      addTearDown(app.close);

      final health = await app.readHealth();
      expect(health['schemaVersion'], DatabaseSchema.version);
      expect(health['applicationId'], DatabaseSchema.applicationId);
      expect(health['foreignKeysEnabled'], isTrue);
      expect(health['integrityOk'], isTrue);
      expect(health['foreignKeyViolations'], 0);
      expect(health['migrationChecksumVerified'], isTrue);
      expect(health['schemaChecksumVerified'], isTrue);
      expect(health['configured'], isFalse);
      expect(health['migrationBackupsSupported'], isTrue);

      for (final table in <String>[
        'actors',
        'app_profile',
        'command_log',
        'business_documents',
        'ledger_accounts',
        'journal_entries',
        'journal_lines',
        'cash_accounts',
        'payment_methods',
        'categories',
        'counterparties',
        'catalog_items',
        'purchases',
        'purchase_lines',
        'inventory_movements',
        'cost_layers',
        'obligations',
        'sales_drafts',
        'sales_draft_lines',
        'sale_confirmations',
        'sales',
        'sale_lines',
        'sale_outflows',
        'sale_cost_allocations',
        'customer_receivables',
        'collection_requests',
        'collections',
        'collection_parts',
        'receivable_settlements',
        'supplier_payment_requests',
        'supplier_payments',
        'supplier_payment_parts',
        'payable_settlements',
        'quick_payment_options',
        'quick_sales_accounts',
        'quick_sales_lines',
        'quick_sale_requests',
        'quick_sale_line_payments',
      ]) {
        expect(await app.database.query(table), isEmpty, reason: table);
      }
      expect(
        await app.database.query('schema_migrations'),
        hasLength(DatabaseSchema.version),
      );
    },
  );

  test(
    'direct DB access rejects external, original and legacy-named paths',
    () async {
      for (final path in <String>[
        'relative.sqlite',
        p.normalize(
          p.join(AppConfig.repositoryRootPath, '..', 'outside.sqlite'),
        ),
        p.normalize('C:/proyectos/valinor_ludoteca/never_open.sqlite'),
        p.join(fixtureDirectory.path, 'valinor.db'),
      ]) {
        await expectLater(
          AppDatabase.open(path: path),
          throwsArgumentError,
          reason: path,
        );
      }
      expect(await fixtureDirectory.list().toList(), isEmpty);
    },
  );

  test(
    'reopening an independent file preserves data and migration history',
    () async {
      final filePath = p.join(fixtureDirectory.path, 'independent.sqlite');
      final first = await AppDatabase.open(path: filePath);
      await _insertActor(first.database);
      final originalMigration = await first.database.query('schema_migrations');
      await first.close();

      final second = await AppDatabase.open(path: filePath);
      addTearDown(second.close);
      expect(await second.database.query('actors'), hasLength(1));
      expect(
        await second.database.query('schema_migrations'),
        originalMigration,
      );
      expect((await second.readHealth())['foreignKeysEnabled'], isTrue);
    },
  );

  test('foreign keys reject references to missing actors', () async {
    final app = await AppDatabase.open(path: inMemoryDatabasePath);
    addTearDown(app.close);

    await expectLater(
      app.database.insert('command_log', _command(actorId: 'missing')),
      throwsA(isA<DatabaseException>()),
    );
    expect(await app.database.query('command_log'), isEmpty);
  });

  test(
    'fractional REAL money and invalid two-sided lines are rejected',
    () async {
      final app = await AppDatabase.open(path: inMemoryDatabasePath);
      addTearDown(app.close);
      await _insertDraftEntry(app.database);

      await expectLater(
        app.database.insert('journal_lines', _line(debit: 100.25, credit: 0)),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        app.database.insert('journal_lines', _line(debit: 100, credit: 100)),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        app.database.insert('journal_lines', _line(debit: -100, credit: 0)),
        throwsA(isA<DatabaseException>()),
      );
      expect(await app.database.query('journal_lines'), isEmpty);
    },
  );

  test(
    'posting requires balance and then freezes the entry and its lines',
    () async {
      final app = await AppDatabase.open(path: inMemoryDatabasePath);
      addTearDown(app.close);
      await _insertDraftEntry(app.database);
      await app.database.insert('journal_lines', _line(debit: 100, credit: 0));

      await expectLater(
        _postEntry(app.database),
        throwsA(isA<DatabaseException>()),
      );
      await app.database.insert('journal_lines', <String, Object?>{
        ..._line(debit: 0, credit: 99),
        'id': 'line-credit',
        'sequence': 1,
      });
      await expectLater(
        _postEntry(app.database),
        throwsA(isA<DatabaseException>()),
      );
      await app.database.update(
        'journal_lines',
        <String, Object?>{'credit_minor': 100},
        where: 'id = ?',
        whereArgs: <Object?>['line-credit'],
      );
      await _postEntry(app.database);

      await expectLater(
        app.database.update('journal_lines', <String, Object?>{
          'debit_minor': 200,
        }),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        app.database.delete('journal_entries'),
        throwsA(isA<DatabaseException>()),
      );
      expect(await app.database.query('journal_lines'), hasLength(2));
    },
  );

  test('failure rolls back the entire command and its result', () async {
    final app = await AppDatabase.open(path: inMemoryDatabasePath);
    addTearDown(app.close);
    await _insertActor(app.database);

    await expectLater(
      app.database.transaction<void>((transaction) async {
        await transaction.insert('command_log', _command());
        await transaction.insert('payment_methods', <String, Object?>{
          'id': 'synthetic-method',
          'code': 'SYNTHETIC',
          'name': 'Synthetic test method',
          'is_active': 1,
        });
        throw StateError('Synthetic failure after writes');
      }),
      throwsStateError,
    );
    expect(await app.database.query('command_log'), isEmpty);
    expect(await app.database.query('payment_methods'), isEmpty);
    expect(await app.database.query('actors'), hasLength(1));
  });

  test(
    'a command key is unique and its stored response is immutable',
    () async {
      final app = await AppDatabase.open(path: inMemoryDatabasePath);
      addTearDown(app.close);
      await _insertActor(app.database);
      await app.database.insert('command_log', _command());

      await expectLater(
        app.database.insert('command_log', _command()),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        app.database.update('command_log', <String, Object?>{
          'response_json': '{"id":"different"}',
        }),
        throwsA(isA<DatabaseException>()),
      );
      final command = (await app.database.query('command_log')).single;
      expect(command['response_version'], 1);
      expect(command['response_json'], '{"id":"synthetic-document"}');
    },
  );

  test(
    'a future schema is refused without downgrade, reset or data loss',
    () async {
      final filePath = p.join(fixtureDirectory.path, 'future.sqlite');
      final app = await AppDatabase.open(path: filePath);
      await _insertActor(app.database);
      await app.database.execute('PRAGMA user_version = 99');
      await app.close();

      await expectLater(
        AppDatabase.open(path: filePath),
        throwsA(isA<UnsupportedSchemaVersionException>()),
      );
      final inspection = await databaseFactoryFfi.openDatabase(
        filePath,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      addTearDown(inspection.close);
      expect(await inspection.getVersion(), 99);
      expect(await inspection.query('actors'), hasLength(1));
    },
  );

  test('a foreign version-zero file is never initialized or reset', () async {
    final filePath = p.join(fixtureDirectory.path, 'foreign.sqlite');
    sqfliteFfiInit();
    final foreign = await databaseFactoryFfi.openDatabase(
      filePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await foreign.execute('CREATE TABLE unrelated (value TEXT NOT NULL)');
    await foreign.insert('unrelated', <String, Object?>{
      'value': 'preserve me',
    });
    await foreign.close();

    await expectLater(
      AppDatabase.open(path: filePath),
      throwsA(isA<DatabaseValidationException>()),
    );
    final inspection = await databaseFactoryFfi.openDatabase(
      filePath,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    addTearDown(inspection.close);
    expect(await inspection.getVersion(), 0);
    expect(
      (await inspection.query('unrelated')).single['value'],
      'preserve me',
    );
  });

  test(
    'migration checksum mismatch is refused and preserved for review',
    () async {
      final filePath = p.join(fixtureDirectory.path, 'metadata.sqlite');
      final app = await AppDatabase.open(path: filePath);
      await app.database.update('schema_migrations', <String, Object?>{
        'migration_checksum': 'synthetic-corruption',
      });
      await app.close();

      await expectLater(
        AppDatabase.open(path: filePath),
        throwsA(isA<DatabaseValidationException>()),
      );
    },
  );

  test(
    'schema drift is detected even when migration metadata is unchanged',
    () async {
      final filePath = p.join(fixtureDirectory.path, 'drift.sqlite');
      final app = await AppDatabase.open(path: filePath);
      await app.database.execute(
        'ALTER TABLE actors ADD COLUMN unexpected TEXT',
      );
      await app.close();

      await expectLater(
        AppDatabase.open(path: filePath),
        throwsA(isA<DatabaseValidationException>()),
      );
    },
  );

  test('v1 DDL remains byte-for-byte compatible with released checksums', () {
    expect(DatabaseSchema.migrationChecksum, 'fnv1a64:2b8aa24f7fdff6d1');
    expect(DatabaseSchema.migration2Checksum, 'fnv1a64:7c3f94396eb01ba3');
    expect(DatabaseSchema.migration3Checksum, 'fnv1a64:c719534b847edc09');
    expect(DatabaseSchema.migration4Checksum, 'fnv1a64:b669041fbf59266d');
    expect(DatabaseSchema.migration5Checksum, 'fnv1a64:aaf6156fd67b9099');
    expect(DatabaseSchema.migration6Checksum, 'fnv1a64:4ccd48022ac15ecc');
  });

  test(
    'v1 migrates with a verified backup and preserves all history',
    () async {
      final path = p.join(fixtureDirectory.path, 'upgrade.sqlite3');
      final old = await _createVersion1(path);
      await _insertDraftEntry(old);
      await old.insert('journal_lines', _line(debit: 100, credit: 0));
      await old.insert('journal_lines', <String, Object?>{
        ..._line(debit: 0, credit: 100),
        'id': 'line-credit',
        'sequence': 1,
      });
      await _postEntry(old);
      final originalRows = await _foundationRows(old);
      final originalMigration = await old.query('schema_migrations');
      await old.close();

      final app = await AppDatabase.open(path: path);
      final health = await app.readHealth();
      expect(health['schemaVersion'], DatabaseSchema.version);
      expect(health['migrationChecksumVerified'], isTrue);
      expect(health['schemaChecksumVerified'], isTrue);
      final migratedRows = await _foundationRows(app.database);
      for (final table in originalRows.keys) {
        if (table == 'command_log') continue;
        expect(migratedRows[table], originalRows[table], reason: table);
      }
      expect(migratedRows['command_log']!.single, <String, Object?>{
        ...originalRows['command_log']!.single,
        'authorization_policy_version': 'foundation-v1',
      });
      final history = await app.database.query(
        'schema_migrations',
        orderBy: 'version',
      );
      expect(history, hasLength(DatabaseSchema.version));
      expect(history.first, originalMigration.single);
      await app.close();

      final backups = await Directory(
        p.join(fixtureDirectory.path, 'backups'),
      ).list().where((entry) => entry is File).toList();
      expect(backups, hasLength(1));
      final backup = await databaseFactoryFfi.openDatabase(
        backups.single.path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      expect(await backup.getVersion(), 1);
      expect(await _foundationRows(backup), originalRows);
      expect(await backup.query('schema_migrations'), originalMigration);
      expect(
        (await backup.rawQuery('PRAGMA quick_check')).single.values.single,
        'ok',
      );
      expect(await backup.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await backup.close();

      final reopened = await AppDatabase.open(path: path);
      await reopened.close();
      expect(
        await Directory(p.join(fixtureDirectory.path, 'backups')).list().length,
        1,
      );
    },
  );

  test('migration snapshot includes committed WAL data', () async {
    final path = p.join(fixtureDirectory.path, 'wal.sqlite3');
    final old = await _createVersion1(path);
    addTearDown(old.close);
    await old.rawQuery('PRAGMA journal_mode = WAL');
    await _insertActor(old);
    expect(await File('$path-wal').exists(), isTrue);
    final app = await AppDatabase.open(path: path);
    addTearDown(app.close);
    expect(await app.database.query('actors'), hasLength(1));
    final backups = await Directory(
      p.join(fixtureDirectory.path, 'backups'),
    ).list().toList();
    expect(backups, hasLength(1));
    final backup = await databaseFactoryFfi.openDatabase(
      backups.single.path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    expect((await backup.query('actors')).single['id'], 'synthetic-actor');
    await backup.close();
  });

  test('a backup path failure leaves v1 intact and does not migrate', () async {
    final path = p.join(fixtureDirectory.path, 'no_backup.sqlite3');
    final old = await _createVersion1(path);
    await _insertActor(old);
    await old.close();
    await File(p.join(fixtureDirectory.path, 'backups')).writeAsString('keep');
    final before = await File(path).readAsBytes();
    await expectLater(
      AppDatabase.open(path: path),
      throwsA(isA<FileSystemException>()),
    );
    expect(await File(path).readAsBytes(), before);
    final check = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    expect(await check.getVersion(), 1);
    expect(await check.query('schema_migrations'), hasLength(1));
    expect(await check.query('actors'), hasLength(1));
    await check.close();
  });

  test(
    'drifted v1 is refused before backup even with rewritten metadata',
    () async {
      final path = p.join(fixtureDirectory.path, 'tampered_v1.sqlite3');
      final old = await _createVersion1(path);
      await old.execute('ALTER TABLE actors ADD COLUMN unapproved TEXT');
      await old.update('schema_migrations', <String, Object?>{
        'schema_checksum': await _testSchemaChecksum(old),
      });
      await old.close();
      await expectLater(
        AppDatabase.open(path: path),
        throwsA(isA<DatabaseValidationException>()),
      );
      expect(
        await Directory(p.join(fixtureDirectory.path, 'backups')).exists(),
        isFalse,
      );
      final check = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      expect(await check.getVersion(), 1);
      await check.close();
    },
  );

  test(
    'current schema validates historical v1 checksum as well as current schema',
    () async {
      final path = p.join(fixtureDirectory.path, 'history.sqlite3');
      final app = await AppDatabase.open(path: path);
      await app.database.update('schema_migrations', <String, Object?>{
        'schema_checksum': 'fnv1a64:historical-drift',
      }, where: 'version = 1');
      await app.close();
      await expectLater(
        AppDatabase.open(path: path),
        throwsA(isA<DatabaseValidationException>()),
      );
    },
  );

  test(
    'v2 purchase history survives current migration with a verified v2 backup',
    () async {
      final path = p.join(fixtureDirectory.path, 'upgrade_v2.sqlite3');
      final old = await _createVersion2(path);
      await _insertPurchaseDraft(old);
      await _postPurchaseDocument(old);
      await old.update('journal_entries', {
        'status': 'posted',
        'posted_at_utc': _timestamp,
      });
      final before = await _allRows(old);
      await old.close();

      final app = await AppDatabase.open(path: path);
      final health = await app.readHealth();
      expect(health['schemaVersion'], DatabaseSchema.version);
      expect(health['schemaChecksumVerified'], isTrue);
      expect(health['migrationChecksumVerified'], isTrue);
      for (final table in before.keys) {
        final after = await app.database.query(table);
        if (table == 'schema_migrations') {
          expect(after.take(2).toList(), before[table]);
        } else {
          expect(after, before[table], reason: table);
        }
      }
      await app.close();
      final backups = await Directory(
        p.join(fixtureDirectory.path, 'backups'),
      ).list().where((entry) => entry is File).toList();
      expect(backups, hasLength(1));
      expect(p.basename(backups.single.path), contains('.v2.'));
      final backup = await databaseFactoryFfi.openDatabase(
        backups.single.path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      expect(await backup.getVersion(), 2);
      expect(await _allRows(backup), before);
      expect(await backup.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await backup.close();
      final reopened = await AppDatabase.open(path: path);
      await reopened.close();
      expect(
        await Directory(p.join(fixtureDirectory.path, 'backups')).list().length,
        1,
      );
    },
  );

  test(
    'v2 migration snapshots committed WAL and rejects historical drift',
    () async {
      final path = p.join(fixtureDirectory.path, 'wal_v2.sqlite3');
      final old = await _createVersion2(path);
      addTearDown(old.close);
      await old.rawQuery('PRAGMA journal_mode = WAL');
      await _insertActor(old);
      final app = await AppDatabase.open(path: path);
      expect(
        (await app.database.query('actors')).single['id'],
        'synthetic-actor',
      );
      await app.database.update('schema_migrations', {
        'migration_checksum': 'historical-v2-drift',
      }, where: 'version = 2');
      await app.close();
      await expectLater(
        AppDatabase.open(path: path),
        throwsA(isA<DatabaseValidationException>()),
      );
    },
  );

  test(
    'v2 backup failure preserves the old file and migration history',
    () async {
      final path = p.join(fixtureDirectory.path, 'no_backup_v2.sqlite3');
      final old = await _createVersion2(path);
      await _insertActor(old);
      await old.close();
      await File(
        p.join(fixtureDirectory.path, 'backups'),
      ).writeAsString('keep');
      final before = await File(path).readAsBytes();
      await expectLater(
        AppDatabase.open(path: path),
        throwsA(isA<FileSystemException>()),
      );
      expect(await File(path).readAsBytes(), before);
      final check = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      expect(await check.getVersion(), 2);
      expect(await check.query('schema_migrations'), hasLength(2));
      await check.close();
    },
  );

  test('purchase posting requires matching stock, debt and journal', () async {
    final app = await AppDatabase.open(path: inMemoryDatabasePath);
    addTearDown(app.close);
    await _insertPurchaseDraft(app.database);
    await app.database.update('cost_layers', <String, Object?>{
      'total_cost_minor': 99,
    });
    await expectLater(
      _postPurchaseDocument(app.database),
      throwsA(isA<DatabaseException>()),
    );
    await app.database.update('cost_layers', <String, Object?>{
      'total_cost_minor': 100,
    });
    await app.database.update('obligations', <String, Object?>{
      'initial_minor': 99,
    });
    await expectLater(
      _postPurchaseDocument(app.database),
      throwsA(isA<DatabaseException>()),
    );
    await app.database.update('obligations', <String, Object?>{
      'initial_minor': 100,
    });
    await app.database.update(
      'journal_lines',
      <String, Object?>{'debit_minor': 99},
      where: 'id = ?',
      whereArgs: ['purchase-debit'],
    );
    await expectLater(
      _postPurchaseDocument(app.database),
      throwsA(isA<DatabaseException>()),
    );
    await app.database.update(
      'journal_lines',
      <String, Object?>{'debit_minor': 100},
      where: 'id = ?',
      whereArgs: ['purchase-debit'],
    );
    await _postPurchaseDocument(app.database);
    await app.database.update('journal_entries', <String, Object?>{
      'status': 'posted',
      'posted_at_utc': _timestamp,
    });
    expect(
      (await app.database.query('business_documents')).single['status'],
      'posted',
    );
  });

  test(
    'v3 sale, FIFO and prepared history survive migration with a complete WAL backup',
    () async {
      final path = p.join(fixtureDirectory.path, 'upgrade_v3.sqlite3');
      final old = await _createVersion3(path);
      await old.rawQuery('PRAGMA journal_mode = WAL');
      await _insertVersion3Sale(old);
      final before = await _allRows(old);
      expect(await File('$path-wal').exists(), isTrue);
      final app = await AppDatabase.open(path: path);
      await old.close();
      expect((await app.readHealth())['schemaVersion'], DatabaseSchema.version);
      expect((await app.readHealth())['schemaChecksumVerified'], isTrue);
      for (final table in before.keys) {
        final after = await app.database.query(table);
        expect(
          table == 'schema_migrations' ? after.take(3).toList() : after,
          before[table],
          reason: table,
        );
      }
      await app.close();
      final backups = await Directory(
        p.join(fixtureDirectory.path, 'backups'),
      ).list().toList();
      expect(backups, hasLength(1));
      expect(p.basename(backups.single.path), contains('.v3.'));
      final backup = await databaseFactoryFfi.openDatabase(
        backups.single.path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      expect(await backup.getVersion(), 3);
      expect(await _allRows(backup), before);
      expect(await backup.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await backup.close();
    },
  );

  test(
    'v3 backup failure preserves the file and all released migration rows',
    () async {
      final path = p.join(fixtureDirectory.path, 'backup_failure_v3.sqlite3');
      final old = await _createVersion3(path);
      await _insertActor(old);
      await old.close();
      await File(
        p.join(fixtureDirectory.path, 'backups'),
      ).writeAsString('keep');
      final before = await File(path).readAsBytes();
      await expectLater(
        AppDatabase.open(path: path),
        throwsA(isA<FileSystemException>()),
      );
      expect(await File(path).readAsBytes(), before);
    },
  );

  test('historical v3 drift is refused before migration or backup', () async {
    final path = p.join(fixtureDirectory.path, 'history_failure_v3.sqlite3');
    final old = await _createVersion3(path);
    await old.update('schema_migrations', {
      'migration_checksum': 'changed-v3',
    }, where: 'version = 3');
    await old.close();
    await expectLater(
      AppDatabase.open(path: path),
      throwsA(isA<DatabaseValidationException>()),
    );
    expect(
      await Directory(p.join(fixtureDirectory.path, 'backups')).exists(),
      isFalse,
    );
  });

  test(
    'v4 collections and money survive current schema with a complete WAL backup',
    () async {
      final path = p.join(fixtureDirectory.path, 'upgrade_v4.sqlite3');
      final old = await _createVersion4(path);
      await old.rawQuery('PRAGMA journal_mode = WAL');
      await _insertVersion4Collection(old);
      final before = await _allRows(old);
      expect(await File('$path-wal').exists(), isTrue);
      final app = await AppDatabase.open(path: path);
      await old.close();
      final health = await app.readHealth();
      expect(health['schemaVersion'], DatabaseSchema.version);
      expect(health['schemaChecksumVerified'], isTrue);
      expect(health['migrationChecksumVerified'], isTrue);
      for (final table in before.keys) {
        final after = await app.database.query(table);
        expect(
          table == 'schema_migrations' ? after.take(4).toList() : after,
          before[table],
          reason: table,
        );
      }
      for (final table in [
        'supplier_payment_requests',
        'supplier_payments',
        'supplier_payment_parts',
        'payable_settlements',
      ]) {
        expect(await app.database.query(table), isEmpty);
      }
      expect(
        (await app.database.query('collections')).single['total_minor'],
        40,
      );
      expect(
        (await app.database.query('collections')).single['remaining_minor'],
        110,
      );
      await app.close();
      final backups = await Directory(
        p.join(fixtureDirectory.path, 'backups'),
      ).list().toList();
      expect(backups, hasLength(1));
      expect(p.basename(backups.single.path), contains('.v4.'));
      final backup = await databaseFactoryFfi.openDatabase(
        backups.single.path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      expect(await backup.getVersion(), 4);
      expect(await _allRows(backup), before);
      expect(await backup.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      expect(
        (await backup.rawQuery('PRAGMA quick_check')).single.values.single,
        'ok',
      );
      await backup.close();
      final reopened = await AppDatabase.open(path: path);
      await reopened.close();
      expect(
        await Directory(p.join(fixtureDirectory.path, 'backups')).list().length,
        1,
      );
    },
  );

  test(
    'v4 backup failure preserves the old file and collection history',
    () async {
      final path = p.join(fixtureDirectory.path, 'backup_failure_v4.sqlite3');
      final old = await _createVersion4(path);
      await _insertVersion4Collection(old);
      await old.close();
      await File(
        p.join(fixtureDirectory.path, 'backups'),
      ).writeAsString('keep');
      final before = await File(path).readAsBytes();
      await expectLater(
        AppDatabase.open(path: path),
        throwsA(isA<FileSystemException>()),
      );
      expect(await File(path).readAsBytes(), before);
    },
  );

  test('historical v4 drift is refused before migration or backup', () async {
    final path = p.join(fixtureDirectory.path, 'history_failure_v4.sqlite3');
    final old = await _createVersion4(path);
    await old.update('schema_migrations', {
      'migration_checksum': 'changed-v4',
    }, where: 'version = 4');
    await old.close();
    await expectLater(
      AppDatabase.open(path: path),
      throwsA(isA<DatabaseValidationException>()),
    );
    expect(
      await Directory(p.join(fixtureDirectory.path, 'backups')).exists(),
      isFalse,
    );
  });

  test(
    'v5 supplier payment and money survive current schema with a complete WAL backup',
    () async {
      final path = p.join(fixtureDirectory.path, 'upgrade_v5.sqlite3');
      final old = await _createVersion5(path);
      await old.rawQuery('PRAGMA journal_mode = WAL');
      await _insertVersion5Payment(old);
      final before = await _allRows(old);
      expect(await File('$path-wal').exists(), isTrue);
      final app = await AppDatabase.open(path: path);
      await old.close();
      final health = await app.readHealth();
      expect(health['schemaVersion'], DatabaseSchema.version);
      expect(health['schemaChecksumVerified'], isTrue);
      expect(health['migrationChecksumVerified'], isTrue);
      for (final table in before.keys) {
        final after = await app.database.query(table);
        expect(
          table == 'schema_migrations' ? after.take(5).toList() : after,
          before[table],
          reason: table,
        );
      }
      for (final table in [
        'quick_payment_options',
        'quick_sales_accounts',
        'quick_sales_lines',
        'quick_sale_requests',
        'quick_sale_line_payments',
      ]) {
        expect(await app.database.query(table), isEmpty);
      }
      expect(
        (await app.database.query('supplier_payments')).single['total_minor'],
        20,
      );
      expect(
        (await app.database.query(
          'supplier_payments',
        )).single['remaining_minor'],
        80,
      );
      await app.close();
      final backups = await Directory(
        p.join(fixtureDirectory.path, 'backups'),
      ).list().toList();
      expect(backups, hasLength(1));
      expect(p.basename(backups.single.path), contains('.v5.'));
      final backup = await databaseFactoryFfi.openDatabase(
        backups.single.path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      expect(await backup.getVersion(), 5);
      expect(await _allRows(backup), before);
      expect(await backup.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      expect(
        (await backup.rawQuery('PRAGMA quick_check')).single.values.single,
        'ok',
      );
      await backup.close();
      final reopened = await AppDatabase.open(path: path);
      await reopened.close();
      expect(
        await Directory(p.join(fixtureDirectory.path, 'backups')).list().length,
        1,
      );
    },
  );

  test('v5 backup failure preserves posted payments and old file', () async {
    final path = p.join(fixtureDirectory.path, 'backup_failure_v5.sqlite3');
    final old = await _createVersion5(path);
    await _insertVersion5Payment(old);
    await old.close();
    await File(p.join(fixtureDirectory.path, 'backups')).writeAsString('keep');
    final before = await File(path).readAsBytes();
    await expectLater(
      AppDatabase.open(path: path),
      throwsA(isA<FileSystemException>()),
    );
    expect(await File(path).readAsBytes(), before);
  });

  test('historical v5 drift is refused before migration or backup', () async {
    final path = p.join(fixtureDirectory.path, 'history_failure_v5.sqlite3');
    final old = await _createVersion5(path);
    await old.update('schema_migrations', {
      'migration_checksum': 'changed-v5',
    }, where: 'version = 5');
    await old.close();
    await expectLater(
      AppDatabase.open(path: path),
      throwsA(isA<DatabaseValidationException>()),
    );
    expect(
      await Directory(p.join(fixtureDirectory.path, 'backups')).exists(),
      isFalse,
    );
  });

  test(
    'v6 prepared quick account and confirmed history survive the current schema with a complete WAL backup',
    () async {
      final path = p.join(fixtureDirectory.path, 'upgrade_v6.sqlite3');
      final old = await _createVersion6(path);
      await old.rawQuery('PRAGMA journal_mode = WAL');
      await _insertVersion6History(old);
      final before = await _allRows(old);
      expect(await File('$path-wal').exists(), isTrue);
      final app = await AppDatabase.open(path: path);
      await old.close();
      final health = await app.readHealth();
      expect(health['schemaVersion'], DatabaseSchema.version);
      expect(health['schemaChecksumVerified'], isTrue);
      expect(health['migrationChecksumVerified'], isTrue);
      for (final table in before.keys) {
        final after = await app.database.query(table);
        expect(
          table == 'schema_migrations'
              ? after.take(6).toList()
              : _priorColumns(after, before[table]!),
          before[table],
          reason: table,
        );
      }
      for (final table in [
        'paid_purchase_requests',
        'paid_purchase_entries',
        'cash_openings',
      ]) {
        expect(await app.database.query(table), isEmpty);
      }
      expect(
        (await app.database.query('quick_sale_requests')).single['status'],
        'prepared',
      );
      expect(
        (await app.database.query('supplier_payments')).single['total_minor'],
        20,
      );
      expect(
        (await app.database.query('catalog_items')).single['name'],
        'Synthetic product',
      );
      await app.close();
      final backups = await Directory(
        p.join(fixtureDirectory.path, 'backups'),
      ).list().toList();
      expect(backups, hasLength(1));
      expect(p.basename(backups.single.path), contains('.v6.'));
      final backup = await databaseFactoryFfi.openDatabase(
        backups.single.path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      expect(await backup.getVersion(), 6);
      expect(await _allRows(backup), before);
      expect(await backup.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      expect(
        (await backup.rawQuery('PRAGMA quick_check')).single.values.single,
        'ok',
      );
      await backup.close();
      final reopened = await AppDatabase.open(path: path);
      await reopened.close();
      expect(
        await Directory(p.join(fixtureDirectory.path, 'backups')).list().length,
        1,
      );
    },
  );

  test(
    'v6 backup failure preserves all prior history and the old file',
    () async {
      final path = p.join(fixtureDirectory.path, 'backup_failure_v6.sqlite3');
      final old = await _createVersion6(path);
      await _insertVersion6History(old);
      await old.close();
      await File(
        p.join(fixtureDirectory.path, 'backups'),
      ).writeAsString('keep');
      final before = await File(path).readAsBytes();
      await expectLater(
        AppDatabase.open(path: path),
        throwsA(isA<FileSystemException>()),
      );
      expect(await File(path).readAsBytes(), before);
    },
  );

  test(
    'v7 history migrates to current schema with a verified unchanged v7 backup',
    () async {
      final path = p.join(fixtureDirectory.path, 'upgrade_v7.sqlite3');
      final old = await _createVersion6(path);
      await _insertVersion6History(old);
      for (final statement in DatabaseSchema.migration7Statements) {
        await old.execute(statement);
      }
      await old.execute('PRAGMA user_version = 7');
      await old.insert('schema_migrations', {
        'version': 7,
        'name': DatabaseSchema.migration7Name,
        'migration_checksum': DatabaseSchema.migration7Checksum,
        'schema_checksum': await _testSchemaChecksum(old),
        'applied_at_utc': _timestamp,
      });
      final before = await _allRows(old);
      await old.close();
      final app = await AppDatabase.open(path: path);
      try {
        expect(
          (await app.readHealth())['schemaVersion'],
          DatabaseSchema.version,
        );
        for (final table in before.keys) {
          final after = await app.database.query(table);
          expect(
            table == 'schema_migrations'
                ? after.take(7).toList()
                : _priorColumns(after, before[table]!),
            before[table],
            reason: table,
          );
        }
        for (final table in [
          'inventory_openings',
          'inventory_opening_items',
          'inventory_opening_allocations',
        ]) {
          expect(await app.database.query(table), isEmpty);
        }
      } finally {
        await app.close();
      }
      final backups = await Directory(
        p.join(fixtureDirectory.path, 'backups'),
      ).list().toList();
      expect(backups, hasLength(1));
      expect(p.basename(backups.single.path), contains('.v7.'));
      final backup = await databaseFactoryFfi.openDatabase(
        backups.single.path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      try {
        expect(await backup.getVersion(), 7);
        expect(await _allRows(backup), before);
        expect(await backup.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        await backup.close();
      }
    },
  );

  for (final startingVersion in [9, 10, 11]) {
    test(
      'v$startingVersion migrates with prior records preserved and an unchanged verified backup',
      () async {
        final path = p.join(
          fixtureDirectory.path,
          'upgrade_v$startingVersion.sqlite3',
        );
        final old = await _createVersion6(path);
        await _insertVersion6History(old);
        for (final migration in [
          (7, DatabaseSchema.migration7Statements),
          (8, DatabaseSchema.migration8Statements),
          (9, DatabaseSchema.migration9Statements),
          (10, DatabaseSchema.migration10Statements),
          (11, DatabaseSchema.migration11Statements),
        ].where((migration) => migration.$1 <= startingVersion)) {
          for (final statement in migration.$2) {
            await old.execute(statement);
          }
          await old.execute('PRAGMA user_version = ${migration.$1}');
          await old.insert('schema_migrations', {
            'version': migration.$1,
            'name': DatabaseSchema.nameForVersion(migration.$1),
            'migration_checksum': DatabaseSchema.checksumForVersion(
              migration.$1,
            ),
            'schema_checksum': await _testSchemaChecksum(old),
            'applied_at_utc': _timestamp,
          });
        }
        final before = await _allRows(old);
        await old.close();
        final app = await AppDatabase.open(path: path);
        try {
          expect(
            (await app.readHealth())['schemaVersion'],
            DatabaseSchema.version,
          );
          for (final table in before.keys) {
            final after = await app.database.query(table);
            expect(
              table == 'schema_migrations'
                  ? after.take(startingVersion).toList()
                  : _priorColumns(after, before[table]!),
              before[table],
              reason: table,
            );
          }
          expect(
            (await app.database.query(
              'quick_sales_accounts',
            )).every((row) => row['customer_name'] == ''),
            isTrue,
          );
          expect(
            (await app.database.query(
              'quick_sales_lines',
            )).every((row) => row['is_credit'] == 0),
            isTrue,
          );
          for (final table in [
            'quick_sale_line_tenders',
            'treasury_operation_requests',
            'treasury_operations',
          ]) {
            expect(await app.database.query(table), isEmpty);
          }
        } finally {
          await app.close();
        }
        final backups = await Directory(
          p.join(fixtureDirectory.path, 'backups'),
        ).list().toList();
        expect(backups, hasLength(1));
        expect(
          p.basename(backups.single.path),
          contains('.v$startingVersion.'),
        );
        final backup = await databaseFactoryFfi.openDatabase(
          backups.single.path,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
        );
        try {
          expect(await backup.getVersion(), startingVersion);
          expect(await _allRows(backup), before);
          expect(await backup.rawQuery('PRAGMA foreign_key_check'), isEmpty);
          expect(
            (await backup.rawQuery('PRAGMA quick_check')).single.values.single,
            'ok',
          );
        } finally {
          await backup.close();
        }
        final reopened = await AppDatabase.open(path: path);
        await reopened.close();
        expect(
          await Directory(
            p.join(fixtureDirectory.path, 'backups'),
          ).list().length,
          1,
        );
      },
    );
  }

  test('historical v6 drift is refused before migration or backup', () async {
    final path = p.join(fixtureDirectory.path, 'history_failure_v6.sqlite3');
    final old = await _createVersion6(path);
    await old.update('schema_migrations', {
      'migration_checksum': 'changed-v6',
    }, where: 'version = 6');
    await old.close();
    await expectLater(
      AppDatabase.open(path: path),
      throwsA(isA<DatabaseValidationException>()),
    );
    expect(
      await Directory(p.join(fixtureDirectory.path, 'backups')).exists(),
      isFalse,
    );
  });

  test(
    'confirmed purchase lines, movements, layers and debt are immutable',
    () async {
      final app = await AppDatabase.open(path: inMemoryDatabasePath);
      addTearDown(app.close);
      await _insertPurchaseDraft(app.database);
      await _postPurchaseDocument(app.database);
      for (final table in [
        'purchases',
        'purchase_lines',
        'inventory_movements',
        'cost_layers',
        'obligations',
      ]) {
        final original = (await app.database.query(table)).single;
        await expectLater(
          app.database.update(table, original),
          throwsA(isA<DatabaseException>()),
          reason: table,
        );
        await expectLater(
          app.database.delete(table),
          throwsA(isA<DatabaseException>()),
          reason: table,
        );
        // REPLACE must not bypass the confirmed-history INSERT guard.
        await expectLater(
          app.database.insert(
            table,
            original,
            conflictAlgorithm: ConflictAlgorithm.replace,
          ),
          throwsA(isA<DatabaseException>()),
          reason: table,
        );
      }
      await expectLater(
        app.database.update(
          'journal_lines',
          <String, Object?>{'debit_minor': 200},
          where: 'id = ?',
          whereArgs: ['purchase-debit'],
        ),
        throwsA(isA<DatabaseException>()),
      );
    },
  );

  test(
    'catalog money quantities and SKU uniqueness are enforced by SQLite',
    () async {
      final app = await AppDatabase.open(path: inMemoryDatabasePath);
      addTearDown(app.close);
      await _insertPurchaseDraft(app.database);
      await expectLater(
        app.database.update('catalog_items', <String, Object?>{
          'list_price_minor': 1.5,
        }),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        app.database.update('purchase_lines', <String, Object?>{
          'quantity': 1.5,
        }),
        throwsA(isA<DatabaseException>()),
      );
      final duplicate = <String, Object?>{
        ...(await app.database.query('catalog_items')).single,
        'id': 'another-product',
        'sku': 'sku-one',
      };
      await expectLater(
        app.database.insert('catalog_items', duplicate),
        throwsA(isA<DatabaseException>()),
      );
    },
  );

  test(
    'REPLACE cannot rewrite confirmed command, document or draft journal',
    () async {
      final app = await AppDatabase.open(path: inMemoryDatabasePath);
      addTearDown(app.close);
      await _insertPurchaseDraft(app.database);
      await _postPurchaseDocument(app.database);
      final command = (await app.database.query('command_log')).single;
      await expectLater(
        app.database.insert('command_log', {
          ...command,
          'response_json': '{"changed":true}',
        }, conflictAlgorithm: ConflictAlgorithm.replace),
        throwsA(isA<DatabaseException>()),
      );
      final document = (await app.database.query('business_documents')).single;
      await expectLater(
        app.database.insert('business_documents', {
          ...document,
          'type': 'generic_test',
          'status': 'draft',
        }, conflictAlgorithm: ConflictAlgorithm.replace),
        throwsA(isA<DatabaseException>()),
      );
      final entry = (await app.database.query('journal_entries')).single;
      await expectLater(
        app.database.insert(
          'journal_entries',
          entry,
          conflictAlgorithm: ConflictAlgorithm.replace,
        ),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        app.database.delete('journal_entries'),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        app.database.update('journal_entries', {
          'cost_completeness': 'unknown',
        }),
        throwsA(isA<DatabaseException>()),
      );
    },
  );

  test(
    'purchase posting checks active category and actual Bogotá dates',
    () async {
      final app = await AppDatabase.open(path: inMemoryDatabasePath);
      addTearDown(app.close);
      await _insertPurchaseDraft(app.database);
      await app.database.update('categories', {'is_active': 0});
      await expectLater(
        _postPurchaseDocument(app.database),
        throwsA(isA<DatabaseException>()),
      );
      await app.database.update('categories', {'is_active': 1});
      await app.database.update('business_documents', {
        'business_date': '2025-12-31',
      });
      await expectLater(
        _postPurchaseDocument(app.database),
        throwsA(isA<DatabaseException>()),
      );
      await app.database.update('business_documents', {
        'business_date': '2026-01-01',
      });
      await app.database.update('purchases', {'due_date': '2026-02-30'});
      await app.database.update('obligations', {'due_date': '2026-02-30'});
      await expectLater(
        _postPurchaseDocument(app.database),
        throwsA(isA<DatabaseException>()),
      );
    },
  );

  for (final replacement
      in <
        ({
          String description,
          String table,
          String draftId,
          Map<String, Object?> changes,
        })
      >[
        (
          description: 'cost layer ID',
          table: 'cost_layers',
          draftId: 'second-layer',
          changes: {'id': 'layer'},
        ),
        (
          description: 'cost layer FIFO sequence',
          table: 'cost_layers',
          draftId: 'second-layer',
          changes: {'fifo_sequence': 1},
        ),
        (
          description: 'supplier obligation ID',
          table: 'obligations',
          draftId: 'second-obligation',
          changes: {'id': 'obligation'},
        ),
        (
          description: 'journal line ID',
          table: 'journal_lines',
          draftId: 'second-debit',
          changes: {'id': 'purchase-debit'},
        ),
        (
          description: 'movement stock sequence',
          table: 'inventory_movements',
          draftId: 'second-movement',
          changes: {'stock_sequence': 1},
        ),
        (
          description: 'journal entry ID',
          table: 'journal_entries',
          draftId: 'second-entry',
          changes: {'id': 'purchase-entry'},
        ),
        (
          description: 'document ID',
          table: 'business_documents',
          draftId: 'second-document',
          changes: {'id': 'purchase-document'},
        ),
        (
          description: 'document command sequence',
          table: 'business_documents',
          draftId: 'second-document',
          changes: {'command_id': 'synthetic-command', 'command_sequence': 0},
        ),
      ]) {
    test(
      'UPDATE OR REPLACE cannot consume a confirmed ${replacement.description}',
      () async {
        final app = await AppDatabase.open(path: inMemoryDatabasePath);
        addTearDown(app.close);
        await _insertPurchaseDraft(app.database);
        await _insertSecondPurchaseDraft(app.database);
        await _postPurchaseDocument(app.database);
        await app.database.update(
          'journal_entries',
          {'status': 'posted', 'posted_at_utc': _timestamp},
          where: 'id = ?',
          whereArgs: ['purchase-entry'],
        );
        // REPLACE's implicit delete does not run DELETE triggers in this mode.
        // Protection must therefore inspect the conflicting confirmed row.
        await app.database.execute('PRAGMA recursive_triggers = OFF');
        final before = await app.database.query(
          replacement.table,
          orderBy: 'id',
        );
        await expectLater(
          app.database.update(
            replacement.table,
            replacement.changes,
            where: 'id = ?',
            whereArgs: [replacement.draftId],
            conflictAlgorithm: ConflictAlgorithm.replace,
          ),
          throwsA(isA<DatabaseException>()),
        );
        expect(
          await app.database.query(replacement.table, orderBy: 'id'),
          before,
        );
        expect(
          await app.database.rawQuery('PRAGMA foreign_key_check'),
          isEmpty,
        );
      },
    );
  }
}

Future<Database> _createVersion1(String path) async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  await db.execute('PRAGMA foreign_keys = ON');
  for (final statement in DatabaseSchema.statements) {
    await db.execute(statement);
  }
  final schemaChecksum = await _testSchemaChecksum(db);
  expect(schemaChecksum, 'fnv1a64:897fbe6bf2401dc4');
  await db.execute('PRAGMA application_id = ${DatabaseSchema.applicationId}');
  await db.execute('PRAGMA user_version = 1');
  await db.insert('schema_migrations', <String, Object?>{
    'version': 1,
    'name': DatabaseSchema.migrationName,
    'migration_checksum': DatabaseSchema.migrationChecksum,
    'schema_checksum': schemaChecksum,
    'applied_at_utc': _timestamp,
  });
  return db;
}

Future<String> _testSchemaChecksum(DatabaseExecutor executor) async {
  final objects = await executor.rawQuery('''
SELECT type, name, tbl_name, sql FROM sqlite_master
WHERE substr(name, 1, 7) <> 'sqlite_' ORDER BY type, name
''');
  return DatabaseSchema.checksum(
    jsonEncode(
      objects
          .map(
            (object) => <Object?>[
              object['type'],
              object['name'],
              object['tbl_name'],
              object['sql'],
            ],
          )
          .toList(),
    ),
  );
}

Future<Database> _createVersion2(String path) async {
  final db = await _createVersion1(path);
  for (final statement in DatabaseSchema.migration2Statements) {
    await db.execute(statement);
  }
  await db.execute('PRAGMA user_version = 2');
  await db.insert('schema_migrations', {
    'version': 2,
    'name': DatabaseSchema.migration2Name,
    'migration_checksum': DatabaseSchema.migration2Checksum,
    'schema_checksum': await _testSchemaChecksum(db),
    'applied_at_utc': _timestamp,
  });
  return db;
}

Future<Database> _createVersion3(String path) async {
  final db = await _createVersion2(path);
  for (final statement in DatabaseSchema.migration3Statements) {
    await db.execute(statement);
  }
  await db.execute('PRAGMA user_version = 3');
  await db.insert('schema_migrations', {
    'version': 3,
    'name': DatabaseSchema.migration3Name,
    'migration_checksum': DatabaseSchema.migration3Checksum,
    'schema_checksum': await _testSchemaChecksum(db),
    'applied_at_utc': _timestamp,
  });
  return db;
}

Future<Database> _createVersion4(String path) async {
  final db = await _createVersion3(path);
  for (final statement in DatabaseSchema.migration4Statements) {
    await db.execute(statement);
  }
  await db.execute('PRAGMA user_version = 4');
  await db.insert('schema_migrations', {
    'version': 4,
    'name': DatabaseSchema.migration4Name,
    'migration_checksum': DatabaseSchema.migration4Checksum,
    'schema_checksum': await _testSchemaChecksum(db),
    'applied_at_utc': _timestamp,
  });
  return db;
}

Future<Database> _createVersion5(String path) async {
  final db = await _createVersion4(path);
  for (final statement in DatabaseSchema.migration5Statements) {
    await db.execute(statement);
  }
  await db.execute('PRAGMA user_version = 5');
  await db.insert('schema_migrations', {
    'version': 5,
    'name': DatabaseSchema.migration5Name,
    'migration_checksum': DatabaseSchema.migration5Checksum,
    'schema_checksum': await _testSchemaChecksum(db),
    'applied_at_utc': _timestamp,
  });
  return db;
}

Future<Database> _createVersion6(String path) async {
  final db = await _createVersion5(path);
  for (final statement in DatabaseSchema.migration6Statements) {
    await db.execute(statement);
  }
  await db.execute('PRAGMA user_version = 6');
  await db.insert('schema_migrations', {
    'version': 6,
    'name': DatabaseSchema.migration6Name,
    'migration_checksum': DatabaseSchema.migration6Checksum,
    'schema_checksum': await _testSchemaChecksum(db),
    'applied_at_utc': _timestamp,
  });
  return db;
}

/// Released-v6 prepared quick account plus immutable prior sale/payment facts.
/// Built with only the released statements; no current adapters or downgrade.
Future<void> _insertVersion6History(DatabaseExecutor db) async {
  await _insertVersion5Payment(db);
  const occurred = '2026-01-01T18:00:00.000Z';
  await db.insert('quick_payment_options', {
    'id': 'old-quick-option',
    'label': 'Efectivo sintético',
    'cash_account_id': 'old-cash',
    'payment_method_id': 'old-method',
    'is_active': 1,
  });
  await db.insert('quick_sales_accounts', {
    'id': 'old-quick-account',
    'label': 'Cuenta sintética preparada',
    'revision': 1,
    'status': 'open',
    'updated_at_utc': occurred,
  });
  await db.insert('quick_sales_lines', {
    'id': 'old-quick-line',
    'account_id': 'old-quick-account',
    'sequence': 0,
    'product_id': 'product',
    'quantity_text': '1',
    'unit_price_minor': 150,
    'payment_option_id': 'old-quick-option',
  });
  await db.insert('quick_sale_requests', {
    'command_id': 'old-prepared-quick-command',
    'account_id': 'old-quick-account',
    'account_revision': 1,
    'canonical_payload': '{"fixture":"prepared-v6"}',
    'occurred_at_utc': occurred,
    'prepared_at_utc': occurred,
    'status': 'prepared',
    'sale_command_id': 'old-quick-sale-command',
    'collection_command_id': 'old-quick-collection-command',
    'legacy_draft_id': 'old-quick-internal-draft',
  });
  await db.update(
    'quick_sales_accounts',
    {'status': 'prepared'},
    where: 'id = ?',
    whereArgs: ['old-quick-account'],
  );
}

/// Actual released-v5 facts, assembled without current adapters or downgrades.
Future<void> _insertVersion5Payment(DatabaseExecutor db) async {
  await _insertVersion4Collection(db);
  const occurred = '2026-01-01T17:00:00.000Z';
  await db.insert('supplier_payment_requests', {
    'command_id': 'old-payment-command',
    'canonical_payload': '{"fixture":"released-v5"}',
    'payable_id': 'obligation',
    'occurred_at_utc': occurred,
    'prepared_at_utc': occurred,
    'status': 'prepared',
  });
  await db.insert('command_log', {
    'id': 'old-payment-command',
    'command_type': 'pay_supplier',
    'payload_hash': 'synthetic-payment',
    'actor_id': 'synthetic-actor',
    'response_json': '{"synthetic":true}',
    'response_version': 1,
    'committed_at_utc': occurred,
    'authorization_policy_version': 'development-single-user-v1',
  });
  await db.insert('business_documents', {
    'id': 'old-payment',
    'command_id': 'old-payment-command',
    'command_sequence': 0,
    'profile_id': 'synthetic-profile',
    'actor_id': 'synthetic-actor',
    'type': 'supplier_payment',
    'status': 'draft',
    'occurred_at_utc': occurred,
    'business_date': '2026-01-01',
    'recorded_at_utc': occurred,
    'source_kind': 'synthetic',
    'date_quality': 'documented',
  });
  await db.insert('supplier_payments', {
    'document_id': 'old-payment',
    'payable_id': 'obligation',
    'purchase_label_snapshot': 'purchase-document',
    'supplier_name_snapshot': 'Synthetic supplier',
    'paid_at_utc': occurred,
    'total_minor': 20,
    'remaining_minor': 80,
  });
  await db.insert('supplier_payment_parts', {
    'id': 'old-payment-part',
    'supplier_payment_id': 'old-payment',
    'sequence': 0,
    'cash_account_id': 'old-cash',
    'payment_method_id': 'old-method',
    'cash_account_name_snapshot': 'Caja sintética',
    'cash_account_kind_snapshot': 'cash',
    'payment_method_code_snapshot': 'CASH',
    'payment_method_name_snapshot': 'Efectivo',
    'amount_minor': 20,
  });
  await db.insert('payable_settlements', {
    'id': 'old-payable-settlement',
    'payable_id': 'obligation',
    'supplier_payment_id': 'old-payment',
    'amount_minor': 20,
  });
  await db.insert('journal_entries', {
    'id': 'old-payment-entry',
    'document_id': 'old-payment',
    'status': 'draft',
    'cost_completeness': 'not_applicable',
  });
  for (final (sequence, account, debit, credit) in [
    (0, 'payable-account', 20, 0),
    (1, 'old-money-ledger', 0, 20),
  ]) {
    await db.insert('journal_lines', {
      'id': 'old-payment-line-$sequence',
      'entry_id': 'old-payment-entry',
      'sequence': sequence,
      'account_id': account,
      'debit_minor': debit,
      'credit_minor': credit,
    });
  }
  await db.update(
    'business_documents',
    {'status': 'posted'},
    where: 'id = ?',
    whereArgs: ['old-payment'],
  );
  await db.update(
    'journal_entries',
    {'status': 'posted', 'posted_at_utc': occurred},
    where: 'id = ?',
    whereArgs: ['old-payment-entry'],
  );
  await db.update(
    'supplier_payment_requests',
    {'status': 'confirmed'},
    where: 'command_id = ?',
    whereArgs: ['old-payment-command'],
  );
  await db.insert('supplier_payment_requests', {
    'command_id': 'old-prepared-payment',
    'canonical_payload': '{"fixture":"prepared-v5"}',
    'payable_id': 'obligation',
    'occurred_at_utc': occurred,
    'prepared_at_utc': occurred,
    'status': 'prepared',
  });
}

/// True released-v4 collection: no current adapter, downgrade, or reset.
Future<void> _insertVersion4Collection(DatabaseExecutor db) async {
  await _insertVersion3Sale(db);
  const occurred = '2026-01-01T16:00:00.000Z';
  await db.insert('ledger_accounts', {
    'id': 'old-money-ledger',
    'code': 'OLD-MONEY',
    'name': 'Caja sintética',
    'class': 'asset',
    'role': 'cash',
    'is_active': 1,
  });
  await db.insert('cash_accounts', {
    'id': 'old-cash',
    'ledger_account_id': 'old-money-ledger',
    'name': 'Caja sintética',
    'kind': 'cash',
    'is_available': 1,
    'is_active': 1,
  });
  await db.insert('payment_methods', {
    'id': 'old-method',
    'code': 'CASH',
    'name': 'Efectivo',
    'is_active': 1,
  });
  await db.insert('collection_requests', {
    'command_id': 'old-collection-command',
    'canonical_payload': '{"fixture":"released-v4"}',
    'receivable_id': 'old-receivable',
    'occurred_at_utc': occurred,
    'prepared_at_utc': occurred,
    'status': 'prepared',
  });
  await db.insert('command_log', {
    'id': 'old-collection-command',
    'command_type': 'collect_receivable',
    'payload_hash': 'synthetic-collection',
    'actor_id': 'synthetic-actor',
    'response_json': '{"synthetic":true}',
    'response_version': 1,
    'committed_at_utc': occurred,
    'authorization_policy_version': 'development-single-user-v1',
  });
  await db.insert('business_documents', {
    'id': 'old-collection',
    'command_id': 'old-collection-command',
    'command_sequence': 0,
    'profile_id': 'synthetic-profile',
    'actor_id': 'synthetic-actor',
    'type': 'customer_collection',
    'status': 'draft',
    'occurred_at_utc': occurred,
    'business_date': '2026-01-01',
    'recorded_at_utc': occurred,
    'source_kind': 'synthetic',
    'date_quality': 'documented',
  });
  await db.insert('collections', {
    'document_id': 'old-collection',
    'receivable_id': 'old-receivable',
    'sale_label_snapshot': 'Mesa sintética',
    'customer_name_snapshot': 'Cliente sintético',
    'collected_at_utc': occurred,
    'total_minor': 40,
    'remaining_minor': 110,
  });
  await db.insert('collection_parts', {
    'id': 'old-collection-part',
    'collection_id': 'old-collection',
    'sequence': 0,
    'cash_account_id': 'old-cash',
    'payment_method_id': 'old-method',
    'cash_account_name_snapshot': 'Caja sintética',
    'cash_account_kind_snapshot': 'cash',
    'payment_method_code_snapshot': 'CASH',
    'payment_method_name_snapshot': 'Efectivo',
    'amount_minor': 40,
  });
  await db.insert('receivable_settlements', {
    'id': 'old-settlement',
    'receivable_id': 'old-receivable',
    'collection_id': 'old-collection',
    'amount_minor': 40,
  });
  await db.insert('journal_entries', {
    'id': 'old-collection-entry',
    'document_id': 'old-collection',
    'status': 'draft',
    'cost_completeness': 'not_applicable',
  });
  for (final (sequence, account, debit, credit) in [
    (0, 'old-money-ledger', 40, 0),
    (1, 'receivable-account', 0, 40),
  ]) {
    await db.insert('journal_lines', {
      'id': 'old-collection-line-$sequence',
      'entry_id': 'old-collection-entry',
      'sequence': sequence,
      'account_id': account,
      'debit_minor': debit,
      'credit_minor': credit,
    });
  }
  await db.update(
    'business_documents',
    {'status': 'posted'},
    where: 'id = ?',
    whereArgs: ['old-collection'],
  );
  await db.update(
    'journal_entries',
    {'status': 'posted', 'posted_at_utc': occurred},
    where: 'id = ?',
    whereArgs: ['old-collection-entry'],
  );
  await db.update(
    'collection_requests',
    {'status': 'confirmed'},
    where: 'command_id = ?',
    whereArgs: ['old-collection-command'],
  );
  await db.insert('collection_requests', {
    'command_id': 'old-prepared-collection',
    'canonical_payload': '{"fixture":"prepared-v4"}',
    'receivable_id': 'old-receivable',
    'occurred_at_utc': occurred,
    'prepared_at_utc': occurred,
    'status': 'prepared',
  });
}

/// Constructs an actual released-v3 sale without opening it through the newer
/// adapter. This tests migration of stock/cost/debt, not only empty DDL.
Future<void> _insertVersion3Sale(DatabaseExecutor db) async {
  await _insertPurchaseDraft(db);
  await _postPurchaseDocument(db);
  await db.update('journal_entries', {
    'status': 'posted',
    'posted_at_utc': _timestamp,
  });
  const occurred = '2026-01-01T15:00:01.000Z';
  for (final (id, accountClass, role) in [
    ('receivable-account', 'asset', 'customer_receivable'),
    ('revenue-account', 'revenue', 'sales_revenue'),
    ('cost-account', 'cost', 'cost_of_sales'),
  ]) {
    await db.insert('ledger_accounts', {
      'id': id,
      'code': id,
      'name': id,
      'class': accountClass,
      'role': role,
      'is_active': 1,
    });
  }
  await db.insert('sales_drafts', {
    'id': 'old-tab',
    'label': 'Mesa sintética',
    'customer_name': 'Cliente sintético',
    'revision': 1,
    'status': 'open',
    'updated_at_utc': occurred,
  });
  await db.insert('sales_draft_lines', {
    'draft_id': 'old-tab',
    'sequence': 0,
    'product_id': 'product',
    'quantity': 1,
    'unit_price_minor': 150,
  });
  final canonical = jsonEncode({
    'version': 1,
    'profileId': 'synthetic-profile',
    'currency': 'COP',
    'scale': 2,
    'draftId': 'old-tab',
    'draftRevision': 1,
    'label': 'Mesa sintética',
    'customerName': 'Cliente sintético',
    'occurredAtUtc': occurred,
    'dueDate': '2026-01-10',
    'costPolicy': 'fifo-front-remainder-v1',
    'lines': [
      {'productId': 'product', 'quantity': 1, 'unitPriceMinor': 150},
    ],
  });
  await db.insert('sale_confirmations', {
    'command_id': 'old-sale-command',
    'draft_id': 'old-tab',
    'draft_revision': 1,
    'canonical_payload': canonical,
    'occurred_at_utc': occurred,
    'due_date': '2026-01-10',
    'prepared_at_utc': occurred,
    'status': 'prepared',
  });
  await db.update(
    'sales_drafts',
    {'status': 'prepared'},
    where: 'id = ?',
    whereArgs: ['old-tab'],
  );
  await db.insert('command_log', {
    'id': 'old-sale-command',
    'command_type': 'confirm_sale',
    'payload_hash': DatabaseSchema.checksum(canonical),
    'actor_id': 'synthetic-actor',
    'response_json': jsonEncode({
      'canonicalPayload': canonical,
      'result': {
        'documentId': 'old-sale',
        'commandId': 'old-sale-command',
        'totalMinor': 150,
        'totalCostMinor': 50,
      },
    }),
    'response_version': 1,
    'committed_at_utc': occurred,
    'authorization_policy_version': 'development-single-user-v1',
  });
  await db.insert('business_documents', {
    'id': 'old-sale',
    'command_id': 'old-sale-command',
    'command_sequence': 0,
    'profile_id': 'synthetic-profile',
    'actor_id': 'synthetic-actor',
    'type': 'credit_sale',
    'status': 'draft',
    'occurred_at_utc': occurred,
    'business_date': '2026-01-01',
    'recorded_at_utc': occurred,
    'source_kind': 'synthetic',
    'date_quality': 'documented',
  });
  await db.insert('sales', {
    'document_id': 'old-sale',
    'draft_id': 'old-tab',
    'label_snapshot': 'Mesa sintética',
    'customer_name_snapshot': 'Cliente sintético',
    'sold_at_utc': occurred,
    'due_date': '2026-01-10',
    'receivable_minor': 150,
    'total_cost_minor': 50,
    'terms': 'credit',
    'cost_policy': 'fifo-front-remainder-v1',
  });
  await db.insert('sale_lines', {
    'id': 'old-sale-line',
    'sale_id': 'old-sale',
    'sequence': 0,
    'product_id': 'product',
    'name_snapshot': 'Synthetic product',
    'quantity': 1,
    'unit_price_minor': 150,
    'total_minor': 150,
    'total_cost_minor': 50,
  });
  await db.insert('sale_outflows', {
    'id': 'old-outflow',
    'document_id': 'old-sale',
    'sequence': 0,
    'product_id': 'product',
    'sale_line_id': 'old-sale-line',
    'quantity': 1,
    'cost_minor': 50,
  });
  await db.insert('sale_cost_allocations', {
    'id': 'old-allocation',
    'sale_line_id': 'old-sale-line',
    'cost_layer_id': 'layer',
    'sequence': 0,
    'quantity': 1,
    'cost_minor': 50,
  });
  await db.insert('customer_receivables', {
    'id': 'old-receivable',
    'origin_document_id': 'old-sale',
    'customer_name_snapshot': 'Cliente sintético',
    'control_account_id': 'receivable-account',
    'initial_minor': 150,
    'issued_at_utc': occurred,
    'due_date': '2026-01-10',
  });
  await db.insert('journal_entries', {
    'id': 'old-sale-entry',
    'document_id': 'old-sale',
    'status': 'draft',
    'cost_completeness': 'complete',
  });
  var sequence = 0;
  for (final (account, debit, credit) in [
    ('receivable-account', 150, 0),
    ('revenue-account', 0, 150),
    ('cost-account', 50, 0),
    ('inventory-account', 0, 50),
  ]) {
    await db.insert('journal_lines', {
      'id': 'old-journal-$sequence',
      'entry_id': 'old-sale-entry',
      'sequence': sequence++,
      'account_id': account,
      'debit_minor': debit,
      'credit_minor': credit,
    });
  }
  await db.update(
    'business_documents',
    {'status': 'posted'},
    where: 'id = ?',
    whereArgs: ['old-sale'],
  );
  await db.update(
    'journal_entries',
    {'status': 'posted', 'posted_at_utc': occurred},
    where: 'id = ?',
    whereArgs: ['old-sale-entry'],
  );
  await db.update(
    'sale_confirmations',
    {'status': 'confirmed'},
    where: 'command_id = ?',
    whereArgs: ['old-sale-command'],
  );
  await db.update(
    'sales_drafts',
    {'status': 'confirmed', 'confirmed_document_id': 'old-sale'},
    where: 'id = ?',
    whereArgs: ['old-tab'],
  );
}

// ALTER migrations may add columns; every prior value must remain identical.
List<Map<String, Object?>> _priorColumns(
  List<Map<String, Object?>> after,
  List<Map<String, Object?>> before,
) {
  if (before.isEmpty) return after;
  final keys = before.first.keys;
  return after.map((row) => {for (final key in keys) key: row[key]}).toList();
}

Future<Map<String, List<Map<String, Object?>>>> _allRows(
  DatabaseExecutor db,
) async {
  final tables = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND substr(name, 1, 7) <> 'sqlite_' ORDER BY name",
  );
  return {
    for (final table in tables)
      table['name']! as String: await db.query(table['name']! as String),
  };
}

Future<Map<String, List<Map<String, Object?>>>> _foundationRows(
  DatabaseExecutor executor,
) async {
  return <String, List<Map<String, Object?>>>{
    for (final table in [
      'actors',
      'app_profile',
      'command_log',
      'business_documents',
      'ledger_accounts',
      'journal_entries',
      'journal_lines',
      'cash_accounts',
      'payment_methods',
    ])
      table: await executor.query(table),
  };
}

Future<void> _insertPurchaseDraft(DatabaseExecutor db) async {
  await _insertActor(db);
  await db.insert('app_profile', <String, Object?>{
    'id': 1,
    'profile_id': 'synthetic-profile',
    'business_name': 'Synthetic business',
    'currency_code': 'COP',
    'money_scale': 2,
    'business_timezone': 'America/Bogota',
    'created_at_utc': _timestamp,
  });
  await db.insert('command_log', <String, Object?>{
    ..._command(),
    'command_type': 'receive_purchase',
    'authorization_policy_version': 'development-single-user-v1',
  });
  await db.insert('business_documents', <String, Object?>{
    'id': 'purchase-document',
    'command_id': 'synthetic-command',
    'command_sequence': 0,
    'profile_id': 'synthetic-profile',
    'actor_id': 'synthetic-actor',
    'type': 'purchase_receipt',
    'status': 'draft',
    'occurred_at_utc': _timestamp,
    'business_date': '2026-01-01',
    'recorded_at_utc': _timestamp,
    'source_kind': 'synthetic',
    'date_quality': 'documented',
  });
  await db.insert('categories', {
    'id': 'category',
    'name': 'Synthetic category',
    'is_active': 1,
  });
  await db.insert('counterparties', {
    'id': 'supplier',
    'name': 'Synthetic supplier',
    'is_customer': 0,
    'is_supplier': 1,
    'is_active': 1,
  });
  await db.insert('catalog_items', {
    'id': 'product',
    'sku': 'SKU-ONE',
    'name': 'Synthetic product',
    'kind': 'product',
    'category_id': 'category',
    'unit_code': 'unit',
    'quantity_scale': 0,
    'list_price_minor': 150,
    'is_active': 1,
  });
  await db.insert('purchases', {
    'document_id': 'purchase-document',
    'supplier_id': 'supplier',
    'supplier_name_snapshot': 'Synthetic supplier',
    'received_at_utc': _timestamp,
    'due_date': '2026-01-10',
    'payable_minor': 100,
    'terms': 'credit',
  });
  await db.insert('purchase_lines', {
    'id': 'purchase-line',
    'purchase_id': 'purchase-document',
    'sequence': 0,
    'product_id': 'product',
    'name_snapshot': 'Synthetic product',
    'quantity': 2,
    'acquisition_total_minor': 100,
    'cost_quality': 'documented',
  });
  await db.insert('inventory_movements', {
    'id': 'movement',
    'document_id': 'purchase-document',
    'sequence': 0,
    'stock_sequence': 1,
    'product_id': 'product',
    'kind': 'purchase',
    'quantity_delta': 2,
    'value_delta_minor': 100,
    'purchase_line_id': 'purchase-line',
  });
  await db.insert('cost_layers', {
    'id': 'layer',
    'inbound_movement_id': 'movement',
    'product_id': 'product',
    'initial_quantity': 2,
    'total_cost_minor': 100,
    'cost_quality': 'documented',
    'fifo_sequence': 1,
    'acquired_at_utc': _timestamp,
  });
  await db.insert('ledger_accounts', {
    'id': 'inventory-account',
    'code': 'INVENTORY',
    'name': 'Inventory',
    'class': 'asset',
    'role': 'inventory',
    'is_active': 1,
  });
  await db.insert('ledger_accounts', {
    'id': 'payable-account',
    'code': 'PAYABLE',
    'name': 'Supplier payable',
    'class': 'liability',
    'role': 'supplier_payable',
    'is_active': 1,
  });
  await db.insert('obligations', {
    'id': 'obligation',
    'origin_document_id': 'purchase-document',
    'sequence': 0,
    'counterparty_id': 'supplier',
    'kind': 'supplier_payable',
    'control_account_id': 'payable-account',
    'initial_minor': 100,
    'issued_at_utc': _timestamp,
    'due_date': '2026-01-10',
  });
  await db.insert('journal_entries', {
    'id': 'purchase-entry',
    'document_id': 'purchase-document',
    'status': 'draft',
    'cost_completeness': 'complete',
  });
  await db.insert('journal_lines', {
    'id': 'purchase-debit',
    'entry_id': 'purchase-entry',
    'sequence': 0,
    'account_id': 'inventory-account',
    'debit_minor': 100,
    'credit_minor': 0,
  });
  await db.insert('journal_lines', {
    'id': 'purchase-credit',
    'entry_id': 'purchase-entry',
    'sequence': 1,
    'account_id': 'payable-account',
    'debit_minor': 0,
    'credit_minor': 100,
  });
}

Future<int> _postPurchaseDocument(DatabaseExecutor db) => db.update(
  'business_documents',
  {'status': 'posted'},
  where: 'id = ?',
  whereArgs: ['purchase-document'],
);

Future<void> _insertSecondPurchaseDraft(DatabaseExecutor db) async {
  Future<void> clone(
    String table,
    String key,
    String original,
    String target,
    Map<String, Object?> changes,
  ) async {
    final row = (await db.query(
      table,
      where: '$key = ?',
      whereArgs: [original],
    )).single;
    await db.insert(table, {...row, key: target, ...changes});
  }

  await clone('command_log', 'id', 'synthetic-command', 'second-command', {});
  await clone(
    'business_documents',
    'id',
    'purchase-document',
    'second-document',
    {'command_id': 'second-command'},
  );
  await clone(
    'purchases',
    'document_id',
    'purchase-document',
    'second-document',
    {},
  );
  await clone('purchase_lines', 'id', 'purchase-line', 'second-line', {
    'purchase_id': 'second-document',
  });
  await clone('inventory_movements', 'id', 'movement', 'second-movement', {
    'document_id': 'second-document',
    'stock_sequence': 2,
    'purchase_line_id': 'second-line',
  });
  await clone('cost_layers', 'id', 'layer', 'second-layer', {
    'inbound_movement_id': 'second-movement',
    'fifo_sequence': 2,
  });
  await clone('obligations', 'id', 'obligation', 'second-obligation', {
    'origin_document_id': 'second-document',
  });
  await clone('journal_entries', 'id', 'purchase-entry', 'second-entry', {
    'document_id': 'second-document',
  });
  await clone('journal_lines', 'id', 'purchase-debit', 'second-debit', {
    'entry_id': 'second-entry',
  });
  await clone('journal_lines', 'id', 'purchase-credit', 'second-credit', {
    'entry_id': 'second-entry',
  });
}

const _timestamp = '2026-01-01T12:00:00.000Z';

Future<void> _insertActor(DatabaseExecutor executor) async {
  await executor.insert('actors', <String, Object?>{
    'id': 'synthetic-actor',
    'display_name': 'Synthetic actor',
    'kind': 'system',
    'is_active': 1,
    'created_at_utc': _timestamp,
  });
}

Map<String, Object?> _command({String actorId = 'synthetic-actor'}) {
  return <String, Object?>{
    'id': 'synthetic-command',
    'command_type': 'synthetic_test',
    'payload_hash': 'synthetic-payload-hash',
    'actor_id': actorId,
    'response_json': '{"id":"synthetic-document"}',
    'response_version': 1,
    'committed_at_utc': _timestamp,
  };
}

Future<void> _insertDraftEntry(DatabaseExecutor executor) async {
  await _insertActor(executor);
  await executor.insert('app_profile', <String, Object?>{
    'id': 1,
    'profile_id': 'synthetic-profile',
    'business_name': 'Synthetic test business',
    'currency_code': 'COP',
    'money_scale': 2,
    'business_timezone': 'America/Bogota',
    'created_at_utc': _timestamp,
  });
  await executor.insert('command_log', _command());
  await executor.insert('business_documents', <String, Object?>{
    'id': 'synthetic-document',
    'command_id': 'synthetic-command',
    'command_sequence': 0,
    'profile_id': 'synthetic-profile',
    'actor_id': 'synthetic-actor',
    'type': 'synthetic_test',
    'status': 'posted',
    'occurred_at_utc': _timestamp,
    'business_date': '2026-01-01',
    'recorded_at_utc': _timestamp,
    'source_kind': 'synthetic',
    'date_quality': 'documented',
  });
  await executor.insert('ledger_accounts', <String, Object?>{
    'id': 'synthetic-account',
    'code': 'SYNTHETIC',
    'name': 'Synthetic test account',
    'class': 'asset',
    'role': 'test',
    'is_active': 1,
  });
  await executor.insert('journal_entries', <String, Object?>{
    'id': 'synthetic-entry',
    'document_id': 'synthetic-document',
    'status': 'draft',
    'cost_completeness': 'not_applicable',
  });
}

Map<String, Object?> _line({required num debit, required num credit}) {
  return <String, Object?>{
    'id': 'line-debit',
    'entry_id': 'synthetic-entry',
    'sequence': 0,
    'account_id': 'synthetic-account',
    'debit_minor': debit,
    'credit_minor': credit,
  };
}

Future<int> _postEntry(DatabaseExecutor executor) {
  return executor.update(
    'journal_entries',
    <String, Object?>{'status': 'posted', 'posted_at_utc': _timestamp},
    where: 'id = ?',
    whereArgs: <Object?>['synthetic-entry'],
  );
}
