import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/schema.dart';

/// Test-only reconstruction; never an application downgrade path.
Future<void> restoreReleasedV15ForFixture(DatabaseExecutor db) async {
  await restoreReleasedV16ForFixture(db);
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

/// Rebuilds only an empty v17 addition in a synthetic fixture.
Future<void> restoreReleasedV16ForFixture(DatabaseExecutor db) async {
  await restoreReleasedV17ForFixture(db);
  for (final sql in DatabaseSchema.migration17Statements) {
    final name = RegExp(r'^CREATE TRIGGER (\w+)').firstMatch(sql)?.group(1);
    if (name != null) await db.execute('DROP TRIGGER $name');
  }
  await db.execute('DROP TABLE quick_sale_split_tenders');
  await db.execute(
    'ALTER TABLE quick_sales_lines DROP COLUMN payment_split_json',
  );
  for (final name in [
    'quick_credit_requests_validate_insert',
    'quick_sale_requests_validate_update',
    'debtor_receivable_validate',
  ]) {
    await db.execute(
      DatabaseSchema.migration13Statements.singleWhere(
        (s) => RegExp('CREATE TRIGGER $name\\b').hasMatch(s),
      ),
    );
  }
  await db.delete('schema_migrations', where: 'version=17');
  await db.execute('PRAGMA user_version=16');
}

Future<void> restoreReleasedV17ForFixture(DatabaseExecutor db) async {
  for (final sql in DatabaseSchema.migration18Statements) {
    final name = RegExp(r'^CREATE TRIGGER (\w+)').firstMatch(sql)?.group(1);
    if (name != null) await db.execute('DROP TRIGGER $name');
  }
  for (final column in [
    'payment_split_basis',
    'account_payment_option_id',
    'payment_mode',
  ]) {
    await db.execute('ALTER TABLE quick_sales_accounts DROP COLUMN $column');
  }
  await db.delete('schema_migrations', where: 'version=18');
  await db.execute('PRAGMA user_version=17');
}
