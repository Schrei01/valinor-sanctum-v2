import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/infrastructure/database/app_database.dart';
import '../../../core/infrastructure/database/legacy_conversion_schema.dart';
import '../../treasury/domain/legacy_treasury_snapshot.dart';
import '../domain/legacy_time.dart';

const legacyBalanceRoles = {
  'cash': 'cash',
  'nequi': 'nequi',
  'caja_mayor': 'reserve',
  'deudas': 'receivables',
};

class LegacyConversionResult {
  const LegacyConversionResult(
    this.counts,
    this.orphanSales,
    this.undatedBalances,
    this.replayed,
  );
  final Map<String, int> counts;
  final int orphanSales, undatedBalances;
  final bool replayed;
  Map<String, Object?> toJson() => {
    'counts': counts,
    'orphanSalesPreserved': orphanSales,
    'undatedBalancesPreserved': undatedBalances,
    'replayed': replayed,
  };
}

Future<String> legacyFileHash(String path) async =>
    (await sha256.bind(File(path).openRead()).first).toString();

Future<void> verifyLegacyFilePath(String path) async {
  if (!p.isAbsolute(path)) {
    throw const FormatException('La ruta debe ser absoluta.');
  }
  final parts = p.split(p.normalize(path));
  var current = parts.first;
  for (var i = 0; i < parts.length; i++) {
    if (i > 0) current = p.join(current, parts[i]);
    final expected = i == parts.length - 1
        ? FileSystemEntityType.file
        : FileSystemEntityType.directory;
    if (await FileSystemEntity.type(current, followLinks: false) != expected) {
      throw const FormatException('Ruta inexistente o con enlaces.');
    }
  }
  if (!p.equals(
    p.normalize(await File(path).resolveSymbolicLinks()),
    p.normalize(path),
  )) {
    throw const FormatException('Ruta de archivo no canónica.');
  }
}

/// Copies every source row to an immutable archive. Never replays source sales,
/// stock, money or debts into the operational ledger; openings already include them.
Future<LegacyConversionResult> importLegacyHistory({
  required AppDatabase target,
  required String sourcePath,
}) async {
  await verifyLegacyFilePath(sourcePath);
  for (final suffix in ['-wal', '-shm', '-journal']) {
    if (await File('$sourcePath$suffix').exists()) {
      throw const FormatException(
        'La copia de origen tiene auxiliares SQLite activos.',
      );
    }
  }
  final sourceHash = await legacyFileHash(sourcePath);
  final profile = (await target.database.query('app_profile')).single;
  final scale = profile['money_scale'] as int;
  if (profile['business_timezone'] != 'America/Bogota') {
    throw const FormatException('La conversión requiere el perfil Bogotá.');
  }
  sqfliteFfiInit();
  final source = await databaseFactoryFfi.openDatabase(
    sourcePath,
    options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
  );
  final rows = <String, List<Map<String, Object?>>>{};
  final history = <Map<String, Object?>>[];
  late List<Map<String, Object?>> schema;
  try {
    await source.execute('PRAGMA query_only=ON');
    await source.transaction((txn) async {
      schema = await txn.rawQuery(
        "SELECT type,name,sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type,name",
      );
      final tables = schema
          .where((r) => r['type'] == 'table')
          .map((r) => r['name'])
          .toSet();
      if (tables.length != LegacyConversionSchema.tables.length ||
          !tables.containsAll(LegacyConversionSchema.tables)) {
        throw const FormatException(
          'La fuente tiene tablas no reconocidas; no se omitió ninguna.',
        );
      }
      for (final table in LegacyConversionSchema.tables) {
        rows[table] = await txn.query(table, orderBy: 'id');
        for (final row in rows[table]!) {
          if (row['id'] is! int || (row['id'] as int) <= 0) {
            throw const FormatException('Identificador de origen inválido.');
          }
          jsonEncode(row); // Reject unsupported binary or non-JSON values.
        }
        if (!legacyBalanceRoles.containsKey(table)) continue;
        final amounts = await txn.rawQuery(
          'SELECT id,fecha,CAST(total AS TEXT) amount_text FROM $table ORDER BY id',
        );
        if (amounts.isEmpty) {
          throw const FormatException('Falta el historial de una cuenta.');
        }
        for (final row in amounts) {
          final date = parseLegacyDate(row['fecha']);
          history.add({
            'source_table': table,
            'source_id': row['id'],
            'role': legacyBalanceRoles[table],
            'source_date_raw': row['fecha'],
            'occurred_at_utc': date == null ? null : legacyUtcKey(date),
            'amount_minor': legacyTreasuryAmountToMinor(
              row['amount_text'],
              moneyScale: scale,
            ),
          });
        }
      }
    });
  } finally {
    await source.close();
  }
  if (sourceHash != await legacyFileHash(sourcePath)) {
    throw const FormatException('La fuente cambió durante la lectura.');
  }
  final contentHash = sha256
      .convert(utf8.encode(jsonEncode({'schema': schema, 'rows': rows})))
      .toString();
  final counts = {for (final table in rows.keys) table: rows[table]!.length};
  final productIds = rows['products']!.map((r) => r['id']).toSet();
  final orphans = rows['sales']!
      .where((r) => !productIds.contains(r['productId']))
      .length;
  final undated = history.where((r) => r['occurred_at_utc'] == null).length;
  return target.database.transaction((txn) async {
    final existing = await txn.query('legacy_conversions');
    if (existing.isNotEmpty) {
      if (existing.single['status'] != 'complete' ||
          existing.single['source_sha256'] != sourceHash ||
          existing.single['content_sha256'] != contentHash) {
        throw const FormatException(
          'Ya existe otra conversión o está incompleta.',
        );
      }
      return LegacyConversionResult(counts, orphans, undated, true);
    }
    final inventory = await txn.query('inventory_openings');
    final treasury = await txn.query('treasury_openings');
    if (inventory.length != 1 ||
        treasury.length != 1 ||
        inventory.single['source_sha256'] != sourceHash ||
        treasury.single['source_sha256'] != sourceHash) {
      throw const FormatException(
        'La fuente no coincide con las aperturas operativas.',
      );
    }
    final opening = treasury.single;
    final cutoff = DateTime.parse(opening['occurred_at_utc'] as String);
    for (final role in legacyBalanceRoles.values) {
      final balances = history.where((r) => r['role'] == role).toList();
      final last = balances.last;
      final dated = balances.where((r) => r['occurred_at_utc'] != null).toList()
        ..sort((a, b) {
          final order = (a['occurred_at_utc'] as String).compareTo(
            b['occurred_at_utc'] as String,
          );
          return order == 0
              ? (a['source_id'] as int).compareTo(b['source_id'] as int)
              : order;
        });
      if (dated.isEmpty ||
          dated.last['source_id'] != last['source_id'] ||
          balances.any(
            (r) =>
                r['occurred_at_utc'] != null &&
                DateTime.parse(r['occurred_at_utc'] as String).isAfter(cutoff),
          )) {
        throw const FormatException(
          'El historial no concilia por fecha con su último saldo.',
        );
      }
      final field = switch (role) {
        'cash' => 'cash_minor',
        'nequi' => 'nequi_minor',
        'reserve' => 'reserve_minor',
        _ => 'receivables_minor',
      };
      if (last['amount_minor'] != opening[field]) {
        throw const FormatException(
          'El último saldo histórico no coincide con la apertura.',
        );
      }
    }
    final items = await txn.query('inventory_opening_items');
    if (items.length != rows['products']!.length) {
      throw const FormatException('No coincide el inventario de apertura.');
    }
    for (final product in rows['products']!) {
      final item = items
          .where((i) => i['source_product_id'] == '${product['id']}')
          .single;
      if (item['name_snapshot'] != product['name'] ||
          item['quantity'] != product['quantity'] ||
          item['unit_price_minor'] !=
              legacyTreasuryAmountToMinor(
                '${product['price']}',
                moneyScale: scale,
              ) ||
          item['unit_cost_minor'] !=
              legacyTreasuryAmountToMinor(
                '${product['purchasePrice']}',
                moneyScale: scale,
              )) {
        throw const FormatException(
          'Un producto de apertura no coincide con la copia.',
        );
      }
    }
    await txn.insert('legacy_conversions', {
      'id': 1,
      'source_name': p.basename(sourcePath),
      'source_sha256': sourceHash,
      'content_sha256': contentHash,
      'source_schema_json': jsonEncode(schema),
      'counts_json': jsonEncode(counts),
      'timezone': 'America/Bogota',
      'money_scale': scale,
      'treasury_opening_id': opening['document_id'],
      'converted_at_utc': DateTime.now().toUtc().toIso8601String(),
      'status': 'draft',
    });
    final batch = txn.batch();
    for (final table in rows.keys) {
      for (final row in rows[table]!) {
        batch.insert('legacy_source_rows', {
          'conversion_id': 1,
          'source_table': table,
          'source_id': row['id'],
          'row_json': jsonEncode(row),
        });
      }
    }
    for (final row in history) {
      batch.insert('legacy_balance_history', row);
    }
    await batch.commit(noResult: true);
    await txn.update('legacy_conversions', {
      'status': 'complete',
    }, where: 'id=1');
    return LegacyConversionResult(counts, orphans, undated, false);
  });
}
