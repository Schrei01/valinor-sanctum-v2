import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/schema.dart';

/// Test-only reconstruction; never an application downgrade path.
Future<void> restoreReleasedV15ForFixture(DatabaseExecutor db) async {
  for (final sql in DatabaseSchema.migration16Statements) {
    final name = RegExp(r'^CREATE TRIGGER (\w+)').firstMatch(sql)?.group(1);
    if (name != null) await db.execute('DROP TRIGGER $name');
  }
  await db.execute('DROP VIEW stock_adjustment_expected_journal');
  await db.execute('DROP VIEW inventory_cost_usage');
  for (final table in [
    'stock_adjustment_allocations',
    'stock_adjustments',
    'stock_adjustment_requests',
    'catalog_services',
  ]) {
    await db.execute('DROP TABLE $table');
  }
  for (final sql in DatabaseSchema.migration12Statements.where(
    (s) =>
        s.startsWith('CREATE VIEW inventory_cost_usage AS') ||
        s.startsWith('CREATE TRIGGER sales_validate_document_posting\n') ||
        s.startsWith('CREATE TRIGGER entries_validate_posting\n'),
  )) {
    await db.execute(sql);
  }
  await db.delete('schema_migrations', where: 'version=16');
  await db.execute('PRAGMA user_version=15');
  final schema = await db.rawQuery(
    "SELECT type,name,tbl_name,sql FROM sqlite_master WHERE substr(name,1,7)<>'sqlite_' ORDER BY type,name",
  );
  final checksum = DatabaseSchema.checksum(
    jsonEncode([
      for (final o in schema) [o['type'], o['name'], o['tbl_name'], o['sql']],
    ]),
  );
  expect(
    checksum,
    (await db.query(
      'schema_migrations',
      where: 'version=15',
    )).single['schema_checksum'],
  );
}
