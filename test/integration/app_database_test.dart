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
      expect(health['schemaVersion'], 1);
      expect(health['applicationId'], DatabaseSchema.applicationId);
      expect(health['foreignKeysEnabled'], isTrue);
      expect(health['integrityOk'], isTrue);
      expect(health['foreignKeyViolations'], 0);
      expect(health['migrationChecksumVerified'], isTrue);
      expect(health['schemaChecksumVerified'], isTrue);
      expect(health['configured'], isFalse);
      expect(health['migrationBackupsSupported'], isFalse);

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
      ]) {
        expect(await app.database.query(table), isEmpty, reason: table);
      }
      expect(await app.database.query('schema_migrations'), hasLength(1));
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
