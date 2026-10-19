import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/schema.dart';

/// Inspects only an explicitly selected synthetic desktop profile, read-only.
///
/// Run twice with distinct output files and compare `reopenFingerprint` to
/// confirm that a desktop restart preserved configuration and empty ledgers.
Future<void> main(List<String> arguments) async {
  try {
    final options = _parseArguments(arguments);
    final databasePath = p.normalize(options['--database']!);
    final outputPath = p.normalize(options['--output']!);
    final expectedProfile = options['--profile']!;
    final expectedName = options['--name']!;

    await _guardPath(databasePath, mustExist: true, extension: '.sqlite3');
    await _guardPath(outputPath, mustExist: false, extension: '.json');
    if (await File(outputPath).exists()) {
      throw FileSystemException('The report already exists; choose a new output.', outputPath);
    }

    Map<String, Object?> report;
    try {
      report = await _verify(
        databasePath,
        expectedProfile: expectedProfile,
        expectedName: expectedName,
      );
    } catch (error) {
      report = <String, Object?>{
        'reportVersion': 1,
        'passed': false,
        'quality': 'verification_failed',
        'verifiedAtUtc': DateTime.now().toUtc().toIso8601String(),
        'databasePath': databasePath,
        'expectedProfileId': expectedProfile,
        'errorType': error.runtimeType.toString(),
        'error': error.toString(),
      };
    }

    // Recheck immediately before writing; never create a database or its parent.
    await _guardPath(outputPath, mustExist: false, extension: '.json');
    await Directory(p.dirname(outputPath)).create(recursive: true);
    await _guardPath(outputPath, mustExist: false, extension: '.json');
    await File(outputPath).writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      flush: true,
    );
    if (report['passed'] == true) {
      stdout.writeln('Desktop profile verification passed: $outputPath');
    } else {
      stderr.writeln('Desktop profile verification failed: $outputPath');
      exitCode = 1;
    }
  } catch (error) {
    stderr.writeln('Verification refused: $error');
    stderr.writeln(
      'Usage: dart run tool/verify_desktop_profile.dart '
      '--database <absolute-existing.sqlite3> --profile <id> '
      '--name <expectedName> --output <absolute-report.json>',
    );
    exitCode = 64;
  }
}

Map<String, String> _parseArguments(List<String> arguments) {
  const requiredOptions = <String>{
    '--database',
    '--profile',
    '--name',
    '--output',
  };
  if (arguments.length != requiredOptions.length * 2) {
    throw const FormatException('Exactly four named arguments are required');
  }
  final parsed = <String, String>{};
  for (var index = 0; index < arguments.length; index += 2) {
    final key = arguments[index];
    final value = arguments[index + 1];
    if (!requiredOptions.contains(key) ||
        parsed.containsKey(key) ||
        value.trim().isEmpty) {
      throw const FormatException('Unknown, repeated or empty argument');
    }
    parsed[key] = value;
  }
  if (!RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$',
  ).hasMatch(parsed['--profile']!)) {
    throw const FormatException(
      'A simple synthetic profile identifier is required',
    );
  }
  return parsed;
}

Future<void> _guardPath(
  String path, {
  required bool mustExist,
  required String extension,
}) async {
  final repository = p.normalize(AppConfig.repositoryRootPath);
  final boundary = p.join(repository, 'tmp');
  final original = p.normalize('C:/proyectos/valinor_ludoteca');
  bool inside(String root, String candidate) =>
      p.equals(root, candidate) || p.isWithin(root, candidate);
  if (!p.isAbsolute(path) ||
      !p.isAbsolute(repository) ||
      inside(original, repository) ||
      inside(original, path) ||
      !p.isWithin(boundary, path) ||
      p.extension(path).toLowerCase() != extension ||
      p.split(path).any((part) => part.toLowerCase() == 'valinor.db')) {
    throw ArgumentError(
      'Verification paths must be regular files under $boundary',
    );
  }

  final components = p.split(path);
  var current = components.first;
  for (var index = 0; index < components.length; index++) {
    if (index > 0) current = p.join(current, components[index]);
    final isFile = index == components.length - 1;
    final type = await FileSystemEntity.type(current, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      if (mustExist) {
        throw FileSystemException(
          'The selected database must already exist',
          current,
        );
      }
      continue;
    }
    final expected = isFile
        ? FileSystemEntityType.file
        : FileSystemEntityType.directory;
    if (type != expected) {
      throw FileSystemException(
        'Links, junctions and invalid components are refused',
        current,
      );
    }
    final canonical = isFile
        ? await File(current).resolveSymbolicLinks()
        : await Directory(current).resolveSymbolicLinks();
    if (!p.equals(p.normalize(canonical), p.normalize(current))) {
      throw FileSystemException('Aliased paths are refused', current);
    }
  }

  if (mustExist) {
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
          'Aliased SQLite sidecars are refused',
          sidecar,
        );
      }
    }
  }
}

Future<Map<String, Object?>> _verify(
  String databasePath, {
  required String expectedProfile,
  required String expectedName,
}) async {
  final before = await File(databasePath).stat();
  sqfliteFfiInit();
  final database = await databaseFactoryFfi.openDatabase(
    databasePath,
    options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
  );
  final checks = <String, Object?>{};
  void check(String name, Object? actual, Object? expected) {
    checks[name] = <String, Object?>{
      'passed': actual == expected,
      'actual': actual,
      'expected': expected,
    };
  }

  late Map<String, Object?> profileSnapshot;
  late Map<String, Object?> migrationSnapshot;
  final tableCounts = <String, int>{};
  late Map<String, Object?> sums;
  try {
    await database.execute('PRAGMA query_only = ON');
    await database.execute('PRAGMA foreign_keys = ON');
    check('queryOnly', await _pragmaInt(database, 'query_only'), 1);
    check('foreignKeys', await _pragmaInt(database, 'foreign_keys'), 1);
    check('userVersion', await _pragmaInt(database, 'user_version'), 1);
    check(
      'applicationId',
      await _pragmaInt(database, 'application_id'),
      DatabaseSchema.applicationId,
    );

    final quickCheck = await database.rawQuery('PRAGMA quick_check');
    check(
      'quickCheck',
      quickCheck.length == 1
          ? quickCheck.single.values.single
          : 'multiple_results',
      'ok',
    );
    final violations = await database.rawQuery('PRAGMA foreign_key_check');
    check('foreignKeyViolationCount', violations.length, 0);

    final migrations = await database.query(
      'schema_migrations',
      columns: <String>[
        'version',
        'name',
        'migration_checksum',
        'schema_checksum',
        'applied_at_utc',
      ],
    );
    check('migrationCount', migrations.length, 1);
    migrationSnapshot = migrations.length == 1
        ? Map<String, Object?>.from(migrations.single)
        : <String, Object?>{};
    check('migrationVersion', migrationSnapshot['version'], 1);
    check(
      'migrationName',
      migrationSnapshot['name'],
      DatabaseSchema.migrationName,
    );
    check(
      'migrationChecksum',
      migrationSnapshot['migration_checksum'],
      DatabaseSchema.migrationChecksum,
    );
    final objects = await database.rawQuery('''
SELECT type, name, tbl_name, sql FROM sqlite_master
WHERE substr(name, 1, 7) <> 'sqlite_'
ORDER BY type, name
''');
    final schemaFingerprint = DatabaseSchema.checksum(
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
            .toList(growable: false),
      ),
    );
    check(
      'schemaChecksum',
      migrationSnapshot['schema_checksum'],
      schemaFingerprint,
    );

    final profiles = await database.query(
      'app_profile',
      columns: <String>[
        'id',
        'profile_id',
        'business_name',
        'currency_code',
        'money_scale',
        'business_timezone',
        'created_at_utc',
      ],
    );
    check('profileCount', profiles.length, 1);
    profileSnapshot = profiles.length == 1
        ? Map<String, Object?>.from(profiles.single)
        : <String, Object?>{};
    check('profilePrimaryKey', profileSnapshot['id'], 1);
    check('profileId', profileSnapshot['profile_id'], expectedProfile);
    check('businessName', profileSnapshot['business_name'], expectedName);
    check('currency', profileSnapshot['currency_code'], 'COP');
    check('moneyScale', profileSnapshot['money_scale'], 2);
    check('timezone', profileSnapshot['business_timezone'], 'America/Bogota');

    for (final table in <String>[
      'command_log',
      'business_documents',
      'journal_entries',
      'journal_lines',
      'cash_accounts',
      'payment_methods',
    ]) {
      final rows = await database.rawQuery(
        'SELECT count(*) AS count FROM $table',
      );
      final count = rows.single['count']! as int;
      tableCounts[table] = count;
      check('${table}Count', count, 0);
    }
    final sumRows = await database.rawQuery('''
SELECT COALESCE(sum(debit_minor), 0) AS debit_minor,
       COALESCE(sum(credit_minor), 0) AS credit_minor
FROM journal_lines
''');
    sums = Map<String, Object?>.from(sumRows.single);
    check('journalDebitSum', sums['debit_minor'], 0);
    check('journalCreditSum', sums['credit_minor'], 0);
  } finally {
    await database.close();
  }

  final after = await File(databasePath).stat();
  check('databaseSizeUnchanged', after.size, before.size);
  check('databaseModifiedAtUnchanged', after.modified, before.modified);
  final passed = checks.values.every(
    (value) => (value! as Map<String, Object?>)['passed'] == true,
  );
  final reopenFingerprint = DatabaseSchema.checksum(
    jsonEncode(<Object?>[
      migrationSnapshot,
      profileSnapshot,
      tableCounts,
      sums,
    ]),
  );
  // Convert DateTime values in check results explicitly before JSON encoding.
  final serializableChecks = <String, Object?>{
    for (final entry in checks.entries)
      entry.key: <String, Object?>{
        for (final field in (entry.value! as Map<String, Object?>).entries)
          field.key: field.value is DateTime
              ? (field.value! as DateTime).toUtc().toIso8601String()
              : field.value,
      },
  };
  return <String, Object?>{
    'reportVersion': 1,
    'passed': passed,
    'quality': passed ? 'verified_synthetic_profile' : 'check_failed',
    'verifiedAtUtc': DateTime.now().toUtc().toIso8601String(),
    'databasePath': databasePath,
    'readOnlyConnection': true,
    'closedConnection': true,
    'checks': serializableChecks,
    'profile': profileSnapshot,
    'migration': migrationSnapshot,
    'emptyTableCounts': tableCounts,
    'journalSums': sums,
    'reopenFingerprint': reopenFingerprint,
    'fingerprintAlgorithm':
        'fnv1a64; accidental-change detection, not a security signature',
    'databaseFile': <String, Object?>{
      'sizeBytes': after.size,
      'modifiedAtUtc': after.modified.toUtc().toIso8601String(),
    },
  };
}

Future<int> _pragmaInt(DatabaseExecutor executor, String name) async {
  final rows = await executor.rawQuery('PRAGMA $name');
  return rows.single.values.single as int;
}
