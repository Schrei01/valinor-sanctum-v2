import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/features/treasury/domain/legacy_treasury_snapshot.dart';

Future<void> main(List<String> arguments) async {
  try {
    final options = <String, String>{};
    for (var index = 0; index < arguments.length; index++) {
      final key = arguments[index];
      if (!const ['--source', '--output', '--money-scale'].contains(key) ||
          options.containsKey(key) ||
          index + 1 >= arguments.length ||
          arguments[index + 1].startsWith('--')) {
        throw const FormatException(
          'Uso: --source RUTA --output RUTA --money-scale ENTERO (sin sobrescritura)',
        );
      }
      options[key] = arguments[++index];
    }
    final scale = int.tryParse(options['--money-scale'] ?? '');
    if (options.length != 3 || scale == null) {
      throw const FormatException(
        'Se requieren fuente, salida y escala explícitas.',
      );
    }
    final snapshot = await exportLegacyTreasury(
      sourcePath: options['--source']!,
      outputPath: options['--output']!,
      moneyScale: scale,
    );
    stdout.writeln(
      jsonEncode({
        'output': p.normalize(options['--output']!),
        'balances': snapshot.balances.length,
        'historicalMovements': snapshot.movements.length,
        'sourceReadOnly': true,
      }),
    );
  } catch (failure) {
    stderr.writeln('No se extrajo la tesorería: $failure');
    exitCode = 1;
  }
}

/// Extracts latest source balances and bounded read-only historical context.
/// Nothing in this tool creates, updates or replays a ledger entry.
Future<LegacyTreasurySnapshot> exportLegacyTreasury({
  required String sourcePath,
  required String outputPath,
  required int moneyScale,
  DateTime? extractedAtUtc,
}) async {
  if (moneyScale < 0 || moneyScale > 6) {
    throw const LegacyTreasuryFormatException(
      'La escala debe estar entre 0 y 6.',
    );
  }
  final source = p.normalize(sourcePath);
  final destination = p.normalize(outputPath);
  if (!p.isAbsolute(source) ||
      !p.isAbsolute(destination) ||
      p.equals(source, destination)) {
    throw ArgumentError('Las rutas deben ser absolutas y distintas.');
  }
  await _verifyRegularPath(source);
  if (await FileSystemEntity.type(source, followLinks: false) !=
      FileSystemEntityType.file) {
    throw ArgumentError(
      'La fuente debe ser un archivo de base de datos existente.',
    );
  }
  await _verifyOutput(destination);
  await _verifyNoSourceSidecars(source);
  final before = await _hash(source);
  sqfliteFfiInit();
  final database = await databaseFactoryFfi.openDatabase(
    source,
    options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
  );
  late final LegacyTreasurySnapshot snapshot;
  try {
    await database.execute('PRAGMA query_only=ON');
    final balances = <LegacyTreasuryBalance>[];
    for (final entry in LegacyTreasurySnapshot.sourceTables.entries) {
      await _requireColumns(database, entry.value, const {
        'id',
        'total',
        'fecha',
      });
      // Identifiers are fixed in sourceTables, never supplied by database values.
      final rows = await database.rawQuery('''
        SELECT id, CAST(total AS TEXT) AS amount_text, fecha
        FROM ${entry.value} ORDER BY id DESC LIMIT 1
      ''');
      if (rows.isEmpty) {
        throw LegacyTreasuryFormatException(
          'La tabla ${entry.value} no tiene saldo.',
        );
      }
      final row = rows.single;
      balances.add(
        LegacyTreasuryBalance(
          role: entry.key,
          sourceTable: entry.value,
          sourceRowId: _integer(row['id'], 'id'),
          sourceDateRaw: _text(row['fecha'], 'fecha'),
          amountMinor: legacyTreasuryAmountToMinor(
            row['amount_text'],
            moneyScale: moneyScale,
          ),
        ),
      );
    }
    final candidates = <String, LegacyTreasuryMovement>{};
    final tableNames = {
      for (final row in await database.rawQuery(
        "SELECT name FROM sqlite_schema WHERE type='table'",
      ))
        row['name'],
    };
    for (final account in const ['caja', 'nequi', 'caja mayor', 'deudas']) {
      if (tableNames.contains('movimientos')) {
        await _requireColumns(database, 'movimientos', const {
          'id',
          'tipo',
          'cuenta',
          'monto',
          'motivo',
          'fecha',
        });
        final rows = await database.rawQuery(
          '''
          SELECT id,tipo,cuenta,CAST(monto AS TEXT) AS amount_text,motivo,fecha
          FROM movimientos WHERE LOWER(TRIM(cuenta))=?
          ORDER BY fecha DESC,id DESC LIMIT 50
        ''',
          [account],
        );
        for (final row in rows) {
          final type = _text(row['tipo'], 'tipo');
          final role = _role(row['cuenta']);
          final item = LegacyTreasuryMovement(
            sourceTable: 'movimientos',
            sourceRowId: _integer(row['id'], 'id'),
            type: type,
            fromRole: type == 'egreso' ? role : null,
            toRole: type == 'ingreso' ? role : null,
            amountMinor: legacyTreasuryAmountToMinor(
              row['amount_text'],
              moneyScale: moneyScale,
            ),
            reason: _text(row['motivo'], 'motivo'),
            sourceDateRaw: _text(row['fecha'], 'fecha'),
          );
          candidates['${item.sourceTable}:${item.sourceRowId}'] = item;
        }
      }
      if (tableNames.contains('transfermovements')) {
        await _requireColumns(database, 'transfermovements', const {
          'id',
          'tipo',
          'cuenta_origen',
          'cuenta_destino',
          'monto',
          'motivo',
          'fecha',
        });
        final rows = await database.rawQuery(
          '''
          SELECT id,tipo,cuenta_origen,cuenta_destino,
                 CAST(monto AS TEXT) AS amount_text,motivo,fecha
          FROM transfermovements
          WHERE LOWER(TRIM(cuenta_origen))=? OR LOWER(TRIM(cuenta_destino))=?
          ORDER BY fecha DESC,id DESC LIMIT 50
        ''',
          [account, account],
        );
        for (final row in rows) {
          final item = LegacyTreasuryMovement(
            sourceTable: 'transfermovements',
            sourceRowId: _integer(row['id'], 'id'),
            type: _text(row['tipo'], 'tipo'),
            fromRole: _role(row['cuenta_origen']),
            toRole: _role(row['cuenta_destino']),
            amountMinor: legacyTreasuryAmountToMinor(
              row['amount_text'],
              moneyScale: moneyScale,
            ),
            reason: _text(row['motivo'], 'motivo'),
            sourceDateRaw: _text(row['fecha'], 'fecha'),
          );
          candidates['${item.sourceTable}:${item.sourceRowId}'] = item;
        }
      }
    }
    final sorted = candidates.values.toList()
      ..sort((a, b) {
        final date = b.sourceDateRaw.compareTo(a.sourceDateRaw);
        if (date != 0) return date;
        final table = a.sourceTable.compareTo(b.sourceTable);
        return table != 0 ? table : b.sourceRowId.compareTo(a.sourceRowId);
      });
    final selected = <String>{};
    for (final role in LegacyTreasurySnapshot.sourceTables.keys) {
      for (final item
          in sorted
              .where((row) => row.fromRole == role || row.toRole == role)
              .take(50)) {
        selected.add('${item.sourceTable}:${item.sourceRowId}');
      }
    }
    snapshot = LegacyTreasurySnapshot(
      sourceName: p.basename(source),
      sourceSha256: before,
      extractedAtUtc: extractedAtUtc ?? DateTime.now().toUtc(),
      moneyScale: moneyScale,
      balances: balances,
      movements: sorted
          .where(
            (row) => selected.contains('${row.sourceTable}:${row.sourceRowId}'),
          )
          .toList(),
    );
  } finally {
    await database.close();
    await _verifyNoSourceSidecars(source);
    if (await _hash(source) != before) {
      throw const LegacyTreasuryFormatException(
        'La fuente cambió durante la lectura; no se guardó ningún snapshot.',
      );
    }
  }
  await _verifyOutput(destination);
  await Directory(p.dirname(destination)).create(recursive: true);
  await _verifyOutput(destination);
  final staging = await Directory(
    p.dirname(destination),
  ).createTemp('.legacy-treasury-');
  try {
    final temporary = File(p.join(staging.path, 'snapshot.json'));
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(snapshot.toJson()),
      flush: true,
    );
    await _verifyOutput(destination);
    // Reserve a new destination without overwriting an existing snapshot.
    final bytes = await temporary.readAsBytes();
    final created = await File(destination).create(exclusive: true);
    await _verifyRegularPath(created.path);
    final handle = await created.open(mode: FileMode.writeOnly);
    try {
      await handle.writeFrom(bytes);
      await handle.flush();
    } finally {
      await handle.close();
    }
  } finally {
    await _verifyRegularPath(staging.path);
    if (!p.isWithin(_dataBoundary, p.normalize(staging.path))) {
      throw StateError('El temporal salió de data del proyecto nuevo.');
    }
    await staging.delete(recursive: true);
  }
  return snapshot;
}

Future<String> _hash(String path) async =>
    (await sha256.bind(File(path).openRead()).first).toString();

Future<void> _verifyNoSourceSidecars(String source) async {
  for (final suffix in ['-wal', '-journal', '-shm']) {
    final path = '$source$suffix';
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) continue;
    if (type != FileSystemEntityType.file || await File(path).length() > 0) {
      throw const LegacyTreasuryFormatException(
        'La fuente tiene archivos auxiliares activos o incompletos; usa una copia SQLite cerrada.',
      );
    }
  }
}

Future<void> _requireColumns(
  Database database,
  String table,
  Set<String> required,
) async {
  final columns = {
    for (final row in await database.rawQuery('PRAGMA table_info($table)'))
      row['name'],
  };
  if (!columns.containsAll(required)) {
    throw LegacyTreasuryFormatException(
      'La tabla $table no contiene las columnas requeridas.',
    );
  }
}

String _role(Object? source) =>
    switch (_text(source, 'cuenta').trim().toLowerCase()) {
      'caja' => 'cash',
      'nequi' => 'nequi',
      'caja mayor' => 'reserve',
      'deudas' => 'receivables',
      _ => throw const LegacyTreasuryFormatException(
        'El historial contiene una cuenta desconocida.',
      ),
    };

String _text(Object? input, String field) {
  if (input is! String) {
    throw LegacyTreasuryFormatException('El campo $field debe ser texto.');
  }
  return input;
}

int _integer(Object? input, String field) {
  if (input is! int) {
    throw LegacyTreasuryFormatException(
      'El campo $field debe ser un entero exacto.',
    );
  }
  return input;
}

String get _dataBoundary =>
    p.normalize(p.join(AppConfig.repositoryRootPath, 'data'));

Future<void> _verifyOutput(String path) async {
  if (!p.isWithin(_dataBoundary, path) ||
      p.extension(path).toLowerCase() != '.json') {
    throw ArgumentError(
      'La salida JSON debe permanecer en data del proyecto nuevo.',
    );
  }
  await _verifyRegularPath(path);
  if (await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw StateError('La salida ya existe; no se permite sobrescribirla.');
  }
}

Future<void> _verifyRegularPath(String path) async {
  final parts = p.split(path);
  var current = parts.first;
  for (var index = 0; index < parts.length; index++) {
    if (index > 0) current = p.join(current, parts[index]);
    final type = await FileSystemEntity.type(current, followLinks: false);
    if (type == FileSystemEntityType.notFound) continue;
    if (type == FileSystemEntityType.link ||
        (index < parts.length - 1 && type != FileSystemEntityType.directory)) {
      throw FileSystemException(
        'No se admiten enlaces, junctions ni padres no directorio.',
        current,
      );
    }
    final resolved = type == FileSystemEntityType.directory
        ? await Directory(current).resolveSymbolicLinks()
        : await File(current).resolveSymbolicLinks();
    if (!p.equals(p.normalize(resolved), p.normalize(current))) {
      throw FileSystemException('No se admiten rutas con alias.', current);
    }
  }
}
