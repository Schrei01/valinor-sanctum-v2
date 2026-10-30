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
  await restoreReleasedV18ForFixture(db);
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

/// Synthetic reconstruction of an empty investment addition, never a runtime downgrade.
Future<void> restoreReleasedV18ForFixture(DatabaseExecutor db) async {
  await restoreReleasedV19ForFixture(db);
  expect(await db.query('investment_operations'), isEmpty);
  expect(await db.query('investment_refund_requests'), isEmpty);
  final names = <String>{};
  for (final sql in DatabaseSchema.migration19Statements) {
    final name = RegExp(r'^CREATE TRIGGER (\w+)').firstMatch(sql)?.group(1);
    if (name != null) names.add(name);
  }
  for (final name in names) {
    await db.execute('DROP TRIGGER $name');
  }
  for (final name in [
    'investment_initialization',
    'investment_operations',
    'investment_refund_requests',
  ]) {
    await db.execute('DROP TABLE $name');
  }
  final table = DatabaseSchema.migration15Statements.singleWhere(
    (s) => s.contains('CREATE TABLE paid_purchase_entries_upgrade ('),
  );
  await db.execute(table);
  await db.execute(
    'INSERT INTO paid_purchase_entries_upgrade SELECT * FROM paid_purchase_entries',
  );
  await db.execute('DROP TABLE paid_purchase_entries');
  await db.execute(
    'ALTER TABLE paid_purchase_entries_upgrade RENAME TO paid_purchase_entries',
  );
  await db.execute(
    'CREATE INDEX idx_paid_purchase_entries_product ON paid_purchase_entries(product_id)',
  );
  for (final sql in DatabaseSchema.migration15Statements.where(
    (s) => s.contains('CREATE TRIGGER paid_purchase_'),
  )) {
    await db.execute(sql);
  }
  for (final sql in DatabaseSchema.migration7Statements.where(
    (s) => s.contains(
      'CREATE TRIGGER paid_purchase_requests_reserve_command_ids\n',
    ),
  )) {
    await db.execute(sql);
  }
  await db.delete('schema_migrations', where: 'version=19');
  await db.execute('PRAGMA user_version=18');
  final schema = await db.rawQuery(
    "SELECT type,name,tbl_name,sql FROM sqlite_master WHERE substr(name,1,7)<>'sqlite_' ORDER BY type,name",
  );
  expect(
    DatabaseSchema.checksum(
      jsonEncode([
        for (final s in schema) [s['type'], s['name'], s['tbl_name'], s['sql']],
      ]),
    ),
    (await db.query(
      'schema_migrations',
      where: 'version=18',
    )).single['schema_checksum'],
  );
}

/// Synthetic cash-event graph only, for testing the forward v19 -> v20 upgrade.
Future<void> restoreReleasedV19ForFixture(DatabaseExecutor db) async {
  await restoreReleasedV20ForFixture(db);
  expect(await db.query('events', where: "funding_mode<>'cash'"), isEmpty);
  const order = ['events', 'event_products', 'event_cost_allocations'];
  final definitions = {
    for (final name in order)
      name: DatabaseSchema.migration12Statements.singleWhere(
        (s) => s.startsWith('CREATE TABLE $name ('),
      ),
  };
  String staged(String sql) {
    for (final name in order) {
      sql = sql
          .replaceAll(
            'CREATE TABLE $name (',
            'CREATE TABLE ${name}_v19_fixture (',
          )
          .replaceAll('REFERENCES $name(', 'REFERENCES ${name}_v19_fixture(');
    }
    return sql;
  }

  for (final name in order) {
    await db.execute(staged(definitions[name]!));
  }
  final columns = (await db.rawQuery('PRAGMA table_info(events)'))
      .map((r) => r['name'] as String)
      .where((c) => c != 'funding_mode')
      .join(',');
  await db.execute(
    'INSERT INTO events_v19_fixture SELECT $columns FROM events',
  );
  for (final name in order.skip(1)) {
    await db.execute('INSERT INTO ${name}_v19_fixture SELECT * FROM $name');
  }
  final triggers = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='trigger' AND (tbl_name IN('events','event_products','event_cost_allocations') OR name IN('events_posting','event_investment_posting'))",
  );
  for (final trigger in triggers) {
    await db.execute('DROP TRIGGER ${trigger['name']}');
  }
  for (final name in order.reversed) {
    await db.execute('DROP TABLE $name');
  }
  for (final name in order) {
    await db.execute(definitions[name]!);
    await db.execute('INSERT INTO $name SELECT * FROM ${name}_v19_fixture');
  }
  for (final name in order.reversed) {
    await db.execute('DROP TABLE ${name}_v19_fixture');
  }
  for (final sql in DatabaseSchema.migration12Statements.where(
    (s) =>
        s.startsWith('CREATE INDEX idx_event_') ||
        s.startsWith('CREATE TRIGGER events_posting ') ||
        RegExp(
          r'^CREATE TRIGGER \w+ .*\bON (events|event_products|event_cost_allocations)\b',
          dotAll: true,
        ).hasMatch(s),
  )) {
    await db.execute(sql);
  }
  await db.execute(
    DatabaseSchema.migration16Statements.singleWhere(
      (s) => s.startsWith('CREATE TRIGGER service_no_event_material '),
    ),
  );
  await db.execute('DROP VIEW event_expected_journal');
  await db.execute(
    DatabaseSchema.migration12Statements.singleWhere(
      (s) => s.startsWith('CREATE VIEW event_expected_journal AS'),
    ),
  );
  await db.delete('schema_migrations', where: 'version=20');
  await db.execute('PRAGMA user_version=19');
  final schema = await db.rawQuery(
    "SELECT type,name,tbl_name,sql FROM sqlite_master WHERE substr(name,1,7)<>'sqlite_' ORDER BY type,name",
  );
  expect(
    DatabaseSchema.checksum(
      jsonEncode([
        for (final s in schema) [s['type'], s['name'], s['tbl_name'], s['sql']],
      ]),
    ),
    (await db.query(
      'schema_migrations',
      where: 'version=19',
    )).single['schema_checksum'],
  );
}

/// Test-only reconstruction of the released v20, without positive corrections.
Future<void> restoreReleasedV20ForFixture(DatabaseExecutor db) async {
  expect(await db.query('stock_additions'), isEmpty);
  for (final sql in DatabaseSchema.migration21Statements) {
    final name = RegExp(r'^CREATE TRIGGER (\w+)').firstMatch(sql)?.group(1);
    if (name != null) {
      await db.execute('DROP TRIGGER $name');
    }
  }
  await db.execute('DROP VIEW stock_adjustment_expected_journal');
  await db.execute(
    DatabaseSchema.migration16Statements.singleWhere(
      (s) => s.startsWith('CREATE VIEW stock_adjustment_expected_journal '),
    ),
  );
  await db.execute('DROP VIEW inventory_adjustment_facts');
  await db.execute('DROP VIEW inventory_reference_costs');
  await db.execute(
    'ALTER TABLE quick_sales_accounts DROP COLUMN created_at_utc',
  );
  await db.execute('PRAGMA defer_foreign_keys=ON');
  final columns = (await db.rawQuery('PRAGMA table_info(inventory_movements)'))
      .map((r) => r['name'] as String)
      .where((name) => name != 'stock_addition_id')
      .join(',');
  await db.execute(
    'CREATE TABLE movements_v20_fixture AS SELECT $columns FROM inventory_movements',
  );
  await db.execute('DROP TABLE inventory_movements');
  await db.execute(
    DatabaseSchema.migration2Statements.singleWhere(
      (s) => s.contains('CREATE TABLE inventory_movements ('),
    ),
  );
  await db.execute(
    'INSERT INTO inventory_movements SELECT * FROM movements_v20_fixture',
  );
  await db.execute('DROP TABLE movements_v20_fixture');
  await db.execute('DROP TABLE stock_additions');
  for (final sql in DatabaseSchema.migration2Statements.where(
    (s) =>
        s.startsWith('CREATE INDEX idx_movements_') ||
        RegExp(
          r'^\s*CREATE TRIGGER \w+\s+.*\bON inventory_movements\b',
          dotAll: true,
        ).hasMatch(s),
  )) {
    await db.execute(sql);
  }
  for (final sql in DatabaseSchema.migration21Statements) {
    final name = RegExp(r'^CREATE TRIGGER (\w+)').firstMatch(sql)?.group(1);
    if (name == null) continue;
    final original = DatabaseSchema.migration16Statements.where(
      (s) => RegExp('^CREATE TRIGGER $name\\b').hasMatch(s),
    );
    if (original.isNotEmpty) {
      await db.execute(original.single);
    }
  }
  await db.delete('schema_migrations', where: 'version=21');
  await db.execute('PRAGMA user_version=20');
  final schema = await db.rawQuery(
    "SELECT type,name,tbl_name,sql FROM sqlite_master WHERE substr(name,1,7)<>'sqlite_' ORDER BY type,name",
  );
  expect(
    DatabaseSchema.checksum(
      jsonEncode([
        for (final s in schema) [s['type'], s['name'], s['tbl_name'], s['sql']],
      ]),
    ),
    (await db.query(
      'schema_migrations',
      where: 'version=20',
    )).single['schema_checksum'],
  );
}
