import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../app_config.dart';
import 'schema.dart';
import 'investment_ledger.dart';

/// Owns one explicit FFI connection, without changing the global DB factory.
///
/// Upgrades validate the old format and preserve a verified SQLite snapshot.
class AppDatabase {
  AppDatabase._(this._database, this._path);

  static const int schemaVersion = DatabaseSchema.version;
  final Database _database;
  final String _path;
  static Future<Map<int, String>>? _expectedChecksums;

  Database get database => _database;

  static Future<AppDatabase> open({required String path}) async {
    if (path.trim().isEmpty) {
      throw ArgumentError.value(
        path,
        'path',
        'An explicit database path is required',
      );
    }
    if (path != inMemoryDatabasePath && !p.isAbsolute(path)) {
      throw ArgumentError.value(
        path,
        'path',
        'The database path must be absolute',
      );
    }
    if (path != inMemoryDatabasePath) {
      await _validateDatabasePath(p.normalize(path));
    }

    sqfliteFfiInit();
    final database = await databaseFactoryFfi.openDatabase(
      path == inMemoryDatabasePath ? path : p.normalize(path),
      options: OpenDatabaseOptions(
        singleInstance: false,
        onConfigure: (connection) async {
          await connection.execute('PRAGMA foreign_keys = ON');
          if (await _pragmaInt(connection, 'foreign_keys') != 1) {
            throw const DatabaseValidationException(
              'Foreign keys could not be enabled',
            );
          }
          await connection.execute('PRAGMA busy_timeout = 5000');
        },
      ),
    );
    final instance = AppDatabase._(database, path);
    try {
      await instance._initialize();
      return instance;
    } catch (_) {
      await database.close();
      rethrow;
    }
  }

  Future<void> close() => _database.close();

  static Future<void> _validateDatabasePath(String path) async {
    final boundary = p.normalize(AppConfig.repositoryRootPath);
    final original = p.normalize('C:/proyectos/valinor_ludoteca');
    bool inside(String root, String candidate) =>
        p.equals(root, candidate) || p.isWithin(root, candidate);
    if (!p.isAbsolute(boundary) ||
        inside(original, boundary) ||
        inside(original, path) ||
        (!inside(boundary, path) && !AppConfig.isInstalledDatabasePath(path)) ||
        p.split(path).any((part) => part.toLowerCase() == 'valinor.db')) {
      throw ArgumentError.value(
        path,
        'path',
        'Use an independent checkout database or sanctum2.sqlite3 in Documents',
      );
    }

    // Inspect before opening: FFI must never follow a file link or a junction.
    final components = p.split(path);
    var current = components.first;
    for (var index = 0; index < components.length; index++) {
      if (index > 0) current = p.join(current, components[index]);
      final type = await FileSystemEntity.type(current, followLinks: false);
      if (type == FileSystemEntityType.notFound) continue;
      final isFile = index == components.length - 1;
      final expected = isFile
          ? FileSystemEntityType.file
          : FileSystemEntityType.directory;
      if (type != expected) {
        throw FileSystemException(
          'Database paths cannot contain links or invalid components',
          current,
        );
      }
      final canonical = isFile
          ? await File(current).resolveSymbolicLinks()
          : await Directory(current).resolveSymbolicLinks();
      if (!p.equals(p.normalize(canonical), p.normalize(current))) {
        throw FileSystemException(
          'Aliased database paths are not allowed',
          current,
        );
      }
    }
    // SQLite can also write sidecar files. Existing aliases are unsafe too.
    for (final suffix in <String>['-journal', '-wal', '-shm']) {
      final sidecar = '$path$suffix';
      final type = await FileSystemEntity.type(sidecar, followLinks: false);
      if (type == FileSystemEntityType.notFound) continue;
      if (type != FileSystemEntityType.file ||
          !p.equals(
            p.normalize(await File(sidecar).resolveSymbolicLinks()),
            sidecar,
          )) {
        throw FileSystemException(
          'Aliased SQLite sidecars are not allowed',
          sidecar,
        );
      }
    }
  }

  Future<void> _initialize() async {
    final version = await _pragmaInt(_database, 'user_version');
    if (version > schemaVersion) {
      throw UnsupportedSchemaVersionException(version, schemaVersion);
    }
    if (version > 0 && version < schemaVersion) {
      // VACUUM INTO cannot run inside a transaction. Validate before snapshot,
      // then compare its complete content under the exclusive migration lock.
      await _database.transaction<void>(
        (transaction) => _assertHealthy(transaction, version),
        exclusive: true,
      );
      final backupFingerprint = await _createVerifiedBackup(version);
      await _database.transaction<void>((transaction) async {
        await _assertHealthy(transaction, version);
        if (await _contentChecksum(transaction) != backupFingerprint) {
          throw const DatabaseValidationException(
            'The database changed after its backup; reopen to retry safely',
          );
        }
        for (var next = version + 1; next <= schemaVersion; next++) {
          await _applyMigration(transaction, next);
        }
        await _assertHealthy(transaction, schemaVersion);
      }, exclusive: true);
      return;
    }

    // Schema, identity, complete history and user_version commit together.
    await _database.transaction<void>((transaction) async {
      final lockedVersion = await _pragmaInt(transaction, 'user_version');
      final applicationId = await _pragmaInt(transaction, 'application_id');
      if (lockedVersion == 0) {
        final objects = await _schemaObjects(transaction);
        if (applicationId != 0 || objects.isNotEmpty) {
          throw const DatabaseValidationException(
            'Refusing to initialize a nonempty or foreign database',
          );
        }
        for (final statement in DatabaseSchema.statements) {
          await transaction.execute(statement);
        }
        await transaction.execute(
          'PRAGMA application_id = ${DatabaseSchema.applicationId}',
        );
        await transaction.execute('PRAGMA user_version = 1');
        await _recordMigration(transaction, 1);
        for (var next = 2; next <= schemaVersion; next++) {
          await _applyMigration(transaction, next);
        }
      } else if (lockedVersion != schemaVersion ||
          applicationId != DatabaseSchema.applicationId) {
        throw const DatabaseValidationException(
          'Database identity or schema version is not supported',
        );
      }

      await _assertHealthy(transaction, schemaVersion);
    }, exclusive: true);
  }

  static List<String> _migrationStatements(int version) => switch (version) {
    1 => DatabaseSchema.statements,
    2 => DatabaseSchema.migration2Statements,
    3 => DatabaseSchema.migration3Statements,
    4 => DatabaseSchema.migration4Statements,
    5 => DatabaseSchema.migration5Statements,
    6 => DatabaseSchema.migration6Statements,
    7 => DatabaseSchema.migration7Statements,
    8 => DatabaseSchema.migration8Statements,
    9 => DatabaseSchema.migration9Statements,
    10 => DatabaseSchema.migration10Statements,
    11 => DatabaseSchema.migration11Statements,
    12 => DatabaseSchema.migration12Statements,
    13 => DatabaseSchema.migration13Statements,
    14 => DatabaseSchema.migration14Statements,
    15 => DatabaseSchema.migration15Statements,
    16 => DatabaseSchema.migration16Statements,
    17 => DatabaseSchema.migration17Statements,
    18 => DatabaseSchema.migration18Statements,
    19 => DatabaseSchema.migration19Statements,
    20 => DatabaseSchema.migration20Statements,
    21 => DatabaseSchema.migration21Statements,
    _ => throw ArgumentError.value(version, 'version'),
  };

  static Future<void> _applyMigration(
    DatabaseExecutor executor,
    int version,
  ) async {
    for (final statement in _migrationStatements(version)) {
      await executor.execute(statement);
    }
    if (version == 19) {
      await InvestmentLedger.initialize(executor, reclassificationOnly: true);
    }
    await executor.execute('PRAGMA user_version = $version');
    await _recordMigration(executor, version);
  }

  static Future<void> _recordMigration(
    DatabaseExecutor executor,
    int version,
  ) async {
    await executor.insert('schema_migrations', <String, Object?>{
      'version': version,
      'name': DatabaseSchema.nameForVersion(version),
      'migration_checksum': DatabaseSchema.checksumForVersion(version),
      'schema_checksum': await _schemaChecksum(executor),
      'applied_at_utc': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<String> _createVerifiedBackup(int version) async {
    if (_path == inMemoryDatabasePath) {
      throw const DatabaseValidationException(
        'An existing schema needs a file-backed backup before migration',
      );
    }
    final backupDirectory = Directory(
      p.join(
        p.dirname(_path),
        AppConfig.isInstalledDatabasePath(_path)
            ? 'ValinorSanctum2-backups'
            : 'backups',
      ),
    );
    final suffix = Random.secure().nextInt(0x7fffffff).toRadixString(16);
    final backupPath = p.join(
      backupDirectory.path,
      '${p.basenameWithoutExtension(_path)}.v$version.'
      '${DateTime.now().toUtc().microsecondsSinceEpoch}-$suffix.sqlite3',
    );
    await _validateDatabasePath(backupPath);
    await backupDirectory.create(recursive: true);
    await _validateDatabasePath(backupPath);
    // SQLite itself creates a transactionally consistent, standalone snapshot,
    // including committed WAL pages; no live database file is copied directly.
    await _database.execute('VACUUM main INTO ?', <Object?>[backupPath]);
    await _validateDatabasePath(backupPath);
    final backup = await databaseFactoryFfi.openDatabase(
      backupPath,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    try {
      await backup.execute('PRAGMA foreign_keys = ON');
      await backup.execute('PRAGMA query_only = ON');
      await _assertHealthy(backup, version);
      return await _contentChecksum(backup);
    } finally {
      await backup.close();
    }
  }

  static Future<void> _assertHealthy(
    DatabaseExecutor executor,
    int version,
  ) async {
    if (await _pragmaInt(executor, 'user_version') != version ||
        await _pragmaInt(executor, 'application_id') !=
            DatabaseSchema.applicationId) {
      throw const DatabaseValidationException(
        'Database identity or schema version is not supported',
      );
    }
    final health = await _readHealth(executor, expectedVersion: version);
    if (health['identityVerified'] != true ||
        health['foreignKeysEnabled'] != true ||
        health['integrityOk'] != true ||
        health['foreignKeyViolations'] != 0 ||
        health['migrationChecksumVerified'] != true ||
        health['schemaChecksumVerified'] != true) {
      throw const DatabaseValidationException(
        'Schema metadata, structure or integrity validation failed',
      );
    }
  }

  /// Reads a consistent health snapshot. No financial rows are seeded.
  Future<Map<String, Object?>> readHealth() {
    return _database.transaction<Map<String, Object?>>(
      (transaction) => _readHealth(transaction),
    );
  }

  static Future<Map<String, Object?>> _readHealth(
    DatabaseExecutor executor, {
    int expectedVersion = schemaVersion,
  }) async {
    final version = await _pragmaInt(executor, 'user_version');
    final applicationId = await _pragmaInt(executor, 'application_id');
    final foreignKeys = await _pragmaInt(executor, 'foreign_keys');
    final check = await executor.rawQuery('PRAGMA quick_check');
    final violations = await executor.rawQuery('PRAGMA foreign_key_check');
    final migrations = await executor.query(
      'schema_migrations',
      orderBy: 'version',
    );
    final expectedSchemas = await (_expectedChecksums ??=
        _deriveExpectedSchemaChecksums());
    var migrationVerified = migrations.length == expectedVersion;
    var historicalSchemasVerified = migrationVerified;
    for (var index = 0; index < migrations.length; index++) {
      final migrationVersion = index + 1;
      if (migrationVersion > schemaVersion) {
        migrationVerified = false;
        historicalSchemasVerified = false;
        continue;
      }
      final migration = migrations[index];
      migrationVerified =
          migrationVerified &&
          migration['version'] == migrationVersion &&
          migration['name'] ==
              DatabaseSchema.nameForVersion(migrationVersion) &&
          migration['migration_checksum'] ==
              DatabaseSchema.checksumForVersion(migrationVersion);
      historicalSchemasVerified =
          historicalSchemasVerified &&
          migration['schema_checksum'] == expectedSchemas[migrationVersion];
    }
    final schemaVerified =
        historicalSchemasVerified &&
        expectedSchemas[expectedVersion] == await _schemaChecksum(executor);
    final profiles = await executor.rawQuery(
      'SELECT count(*) AS profile_count FROM app_profile',
    );
    return <String, Object?>{
      'schemaVersion': version,
      'applicationId': applicationId,
      'identityVerified':
          version == expectedVersion &&
          applicationId == DatabaseSchema.applicationId,
      'foreignKeysEnabled': foreignKeys == 1,
      'integrityOk': check.length == 1 && check.single.values.single == 'ok',
      'foreignKeyViolations': violations.length,
      'migrationChecksumVerified': migrationVerified,
      'schemaChecksumVerified': schemaVerified,
      'configured': profiles.single['profile_count'] == 1,
      'migrationBackupsSupported': true,
    };
  }

  static Future<Map<int, String>> _deriveExpectedSchemaChecksums() async {
    final reference = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      final checksums = <int, String>{};
      for (var version = 1; version <= schemaVersion; version++) {
        for (final statement in _migrationStatements(version)) {
          await reference.execute(statement);
        }
        checksums[version] = await _schemaChecksum(reference);
      }
      return checksums;
    } finally {
      await reference.close();
    }
  }

  static Future<String> _contentChecksum(DatabaseExecutor executor) async {
    final tables = await executor.rawQuery('''
SELECT name FROM sqlite_master WHERE type = 'table'
AND substr(name, 1, 7) <> 'sqlite_' ORDER BY name
''');
    final content = <Object?>[];
    for (final table in tables) {
      final name = table['name']! as String;
      final rows = await executor.query(name);
      final canonicalRows = rows.map(jsonEncode).toList()..sort();
      content.add(<Object?>[name, canonicalRows]);
    }
    return DatabaseSchema.checksum(jsonEncode(content));
  }

  static Future<int> _pragmaInt(DatabaseExecutor executor, String name) async {
    final result = await executor.rawQuery('PRAGMA $name');
    return result.single.values.single as int;
  }

  static Future<List<Map<String, Object?>>> _schemaObjects(
    DatabaseExecutor executor,
  ) {
    return executor.rawQuery('''
SELECT type, name, tbl_name, sql FROM sqlite_master
WHERE substr(name, 1, 7) <> 'sqlite_'
ORDER BY type, name
''');
  }

  static Future<String> _schemaChecksum(DatabaseExecutor executor) async {
    final objects = await _schemaObjects(executor);
    final canonical = objects
        .map(
          (object) => <Object?>[
            object['type'],
            object['name'],
            object['tbl_name'],
            object['sql'],
          ],
        )
        .toList(growable: false);
    return DatabaseSchema.checksum(jsonEncode(canonical));
  }
}

class DatabaseValidationException implements Exception {
  const DatabaseValidationException(this.message);

  final String message;

  @override
  String toString() => 'DatabaseValidationException: $message';
}

class UnsupportedSchemaVersionException implements Exception {
  const UnsupportedSchemaVersionException(this.actual, this.supported);

  final int actual;
  final int supported;

  @override
  String toString() =>
      'UnsupportedSchemaVersionException: database v$actual is newer than '
      'supported v$supported; no downgrade or reset was performed';
}
