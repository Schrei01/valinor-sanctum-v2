import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../app_config.dart';
import 'schema.dart';

/// Owns one explicit FFI connection, without changing the global DB factory.
///
/// V1 only creates an empty foundation. Upgrades and their required backups are
/// deliberately unsupported until a separately tested migration is supplied.
class AppDatabase {
  AppDatabase._(this._database);

  static const int schemaVersion = DatabaseSchema.version;
  final Database _database;

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
    final instance = AppDatabase._(database);
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
        !inside(boundary, path) ||
        p.split(path).any((part) => part.toLowerCase() == 'valinor.db')) {
      throw ArgumentError.value(
        path,
        'path',
        'Only independent databases inside the approved new repository are allowed',
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
    // Schema, identity, migration metadata and user_version commit together.
    await _database.transaction<void>((transaction) async {
      final version = await _pragmaInt(transaction, 'user_version');
      if (version > schemaVersion) {
        throw UnsupportedSchemaVersionException(version, schemaVersion);
      }
      final applicationId = await _pragmaInt(transaction, 'application_id');
      if (version == 0) {
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
        await transaction.execute('PRAGMA user_version = $schemaVersion');
        await transaction.insert('schema_migrations', <String, Object?>{
          'version': schemaVersion,
          'name': DatabaseSchema.migrationName,
          'migration_checksum': DatabaseSchema.migrationChecksum,
          'schema_checksum': await _schemaChecksum(transaction),
          'applied_at_utc': DateTime.now().toUtc().toIso8601String(),
        });
      } else if (version != schemaVersion ||
          applicationId != DatabaseSchema.applicationId) {
        throw const DatabaseValidationException(
          'Database identity or schema version is not supported',
        );
      }

      final health = await _readHealth(transaction);
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
    }, exclusive: true);
  }

  /// Reads a consistent health snapshot. No financial rows are seeded.
  Future<Map<String, Object?>> readHealth() {
    return _database.transaction<Map<String, Object?>>(_readHealth);
  }

  static Future<Map<String, Object?>> _readHealth(
    DatabaseExecutor executor,
  ) async {
    final version = await _pragmaInt(executor, 'user_version');
    final applicationId = await _pragmaInt(executor, 'application_id');
    final foreignKeys = await _pragmaInt(executor, 'foreign_keys');
    final check = await executor.rawQuery('PRAGMA quick_check');
    final violations = await executor.rawQuery('PRAGMA foreign_key_check');
    final migrations = await executor.query('schema_migrations');
    final migration = migrations.length == 1 ? migrations.single : null;
    final migrationVerified =
        migration != null &&
        migration['version'] == schemaVersion &&
        migration['name'] == DatabaseSchema.migrationName &&
        migration['migration_checksum'] == DatabaseSchema.migrationChecksum;
    final schemaVerified =
        migration != null &&
        migration['schema_checksum'] == await _schemaChecksum(executor);
    final profiles = await executor.rawQuery(
      'SELECT count(*) AS profile_count FROM app_profile',
    );
    return <String, Object?>{
      'schemaVersion': version,
      'applicationId': applicationId,
      'identityVerified':
          version == schemaVersion &&
          applicationId == DatabaseSchema.applicationId,
      'foreignKeysEnabled': foreignKeys == 1,
      'integrityOk': check.length == 1 && check.single.values.single == 'ok',
      'foreignKeyViolations': violations.length,
      'migrationChecksumVerified': migrationVerified,
      'schemaChecksumVerified': schemaVerified,
      'configured': profiles.single['profile_count'] == 1,
      'migrationBackupsSupported': false,
    };
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
