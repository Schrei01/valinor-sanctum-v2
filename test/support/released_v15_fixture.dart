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
  await restoreReleasedV21ForFixture(db);
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

/// Synthetic reconstruction only: remove the empty v22 addition for old fixtures.
Future<void> restoreReleasedV21ForFixture(DatabaseExecutor db) async {
  await restoreReleasedV22ForFixture(db);
  expect(await db.query('debtor_loans'), isEmpty);
  await db.execute('PRAGMA defer_foreign_keys=ON');
  final created = <String>{};
  for (final sql in DatabaseSchema.migration22Statements) {
    final name = RegExp(r'^CREATE TRIGGER (\w+)').firstMatch(sql)?.group(1);
    if (name != null) created.add(name);
  }
  for (final name in created) {
    await db.execute('DROP TRIGGER $name');
  }
  await db.execute('DROP VIEW all_customer_receivables');
  await db.execute('DROP VIEW debtor_expected_journal');
  for (final name in ['debtor_requests', 'debtor_receivables']) {
    final definition = DatabaseSchema.migration13Statements.singleWhere(
      (s) => s.startsWith('CREATE TABLE $name('),
    );
    final columns = (await db.rawQuery('PRAGMA table_info($name)'))
        .map((r) => r['name'] as String)
        .where((c) => c != 'loan_document_id')
        .join(',');
    await db.execute(
      'CREATE TABLE ${name}_fixture AS SELECT $columns FROM $name',
    );
    await db.execute('DROP TABLE $name');
    await db.execute(definition);
    await db.execute('INSERT INTO $name SELECT * FROM ${name}_fixture');
    await db.execute('DROP TABLE ${name}_fixture');
  }
  await db.execute('DROP TABLE debtor_loans');
  final released = [
    ...DatabaseSchema.migration13Statements,
    ...DatabaseSchema.migration16Statements,
    ...DatabaseSchema.migration17Statements,
    ...DatabaseSchema.migration19Statements,
  ];
  final triggers = <String, String>{};
  for (final sql in released) {
    final name = RegExp(r'^CREATE TRIGGER (\w+)').firstMatch(sql)?.group(1);
    if (name != null && created.contains(name)) triggers[name] = sql;
  }
  for (final sql in triggers.values) {
    await db.execute(sql);
  }
  await db.execute(
    'CREATE INDEX idx_debtor_receivables_person ON debtor_receivables(debtor_id)',
  );
  for (final name in ['all_customer_receivables', 'debtor_expected_journal']) {
    await db.execute(
      DatabaseSchema.migration13Statements.singleWhere(
        (s) => s.startsWith('CREATE VIEW $name '),
      ),
    );
  }
  await db.delete('schema_migrations', where: 'version=22');
  await db.execute('PRAGMA user_version=21');
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
      where: 'version=21',
    )).single['schema_checksum'],
  );
}

/// Test-only reconstruction of v22; keep the original financial facts intact.
Future<void> restoreReleasedV22ForFixture(DatabaseExecutor db) async {
  await restoreReleasedV23ForFixture(db);
  await db.execute('DROP TRIGGER supplier_payments_validate_document_posting');
  await db.execute(
    DatabaseSchema.migration5Statements.singleWhere(
      (s) => s.startsWith(
        'CREATE TRIGGER supplier_payments_validate_document_posting\n',
      ),
    ),
  );
  await db.delete('schema_migrations', where: 'version=23');
  await db.execute('PRAGMA user_version=22');
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
      where: 'version=22',
    )).single['schema_checksum'],
  );
}

/// Synthetic fixture only. No runtime downgrade path.
Future<void> restoreReleasedV23ForFixture(DatabaseExecutor db) async {
  await restoreReleasedV24ForFixture(db);
  expect(await db.query('purchase_batch_requests'), isEmpty);
  for (final sql in DatabaseSchema.migration24Statements) {
    final name = RegExp(r'^CREATE TRIGGER (\w+)').firstMatch(sql)?.group(1);
    if (name != null) await db.execute('DROP TRIGGER $name');
  }
  await db.execute('DROP VIEW purchase_item_costs');
  await db.execute('DROP VIEW purchase_spending');
  await db.execute('DROP TABLE purchase_batch_items');
  await db.execute('DROP TABLE purchase_batch_requests');
  await db.delete('schema_migrations', where: 'version=24');
  await db.execute('PRAGMA user_version=23');
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
      where: 'version=23',
    )).single['schema_checksum'],
  );
}

/// Test-only reconstruction of v24; never an application downgrade.
Future<void> restoreReleasedV24ForFixture(DatabaseExecutor db) async {
  if (((await db.rawQuery('PRAGMA user_version')).single.values.single
          as int) >=
      27) {
    await restoreReleasedV26ForFixture(db);
  }
  for (final name in [
    'services_validate_insert',
    'services_no_update',
    'services_no_delete',
    'services_no_replace',
    'bulk_sale_posting',
  ]) {
    await db.execute('DROP TRIGGER $name');
  }
  final bulk = await db.query('catalog_services', where: "kind='bulk'");
  for (final row in bulk) {
    expect(
      await db.query(
        'sale_lines',
        where: 'product_id=?',
        whereArgs: [row['product_id']],
      ),
      isEmpty,
    );
    await db.delete(
      'catalog_services',
      where: 'product_id=?',
      whereArgs: [row['product_id']],
    );
  }
  if (bulk.isNotEmpty) {
    await db.execute('DROP TRIGGER product_price_history_no_delete');
    for (final row in bulk) {
      await db.delete(
        'product_price_history',
        where: 'product_id=?',
        whereArgs: [row['product_id']],
      );
      await db.delete(
        'catalog_items',
        where: 'id=?',
        whereArgs: [row['product_id']],
      );
    }
    await db.execute(
      DatabaseSchema.migration15Statements.singleWhere(
        (s) => s.startsWith('CREATE TRIGGER product_price_history_no_delete '),
      ),
    );
    await db.delete(
      'categories',
      where:
          "id='bulk:category:articles' AND NOT EXISTS(SELECT 1 FROM catalog_items WHERE category_id=categories.id)",
    );
  }
  await db.execute(
    'CREATE TABLE catalog_services_fixture AS SELECT * FROM catalog_services',
  );
  await db.execute('DROP TABLE catalog_services');
  await db.execute(
    DatabaseSchema.migration16Statements.singleWhere(
      (s) => s.startsWith('CREATE TABLE catalog_services ('),
    ),
  );
  await db.execute(
    'INSERT INTO catalog_services SELECT * FROM catalog_services_fixture',
  );
  await db.execute('DROP TABLE catalog_services_fixture');
  for (final sql in DatabaseSchema.migration16Statements.where(
    (s) => s.startsWith('CREATE TRIGGER services_'),
  )) {
    await db.execute(sql);
  }
  await db.delete('schema_migrations', where: 'version>=25');
  await db.execute('PRAGMA user_version=24');
}

/// Test-only reconstruction of v26 before any new correction is recorded.
Future<void> restoreReleasedV26ForFixture(DatabaseExecutor db) async {
  await restoreReleasedV27ForFixture(db);
  final replacements = <String>{};
  for (final sql in DatabaseSchema.migration27Statements) {
    final trigger = RegExp(r'CREATE TRIGGER (\w+)').firstMatch(sql)?.group(1);
    if (trigger != null) await db.execute('DROP TRIGGER $trigger');
    if (sql.startsWith('DROP TRIGGER ')) {
      replacements.add(sql.substring('DROP TRIGGER '.length));
    }
  }
  await db.execute('DROP VIEW event_current_components');
  await db.execute('DROP VIEW event_current_settings');
  for (final name in [
    'event_correction_payments',
    'event_return_values',
    'catalog_corrections',
    'catalog_correction_requests',
  ]) {
    expect(await db.query(name), isEmpty);
    await db.execute('DROP TABLE $name');
  }
  for (final sql in [
    ...DatabaseSchema.migration10Statements,
    ...DatabaseSchema.migration21Statements,
  ]) {
    final name = RegExp(r'CREATE TRIGGER (\w+)').firstMatch(sql)?.group(1);
    if (replacements.contains(name)) await db.execute(sql);
  }
  await db.delete('schema_migrations', where: 'version>=27');
  await db.execute('PRAGMA user_version=26');
}

/// Test-only reconstruction; operational databases never downgrade.
Future<void> restoreReleasedV27ForFixture(DatabaseExecutor db) async {
  await restoreReleasedV28ForFixture(db);
  for (final sql in DatabaseSchema.migration28Statements) {
    final name = RegExp(r'^CREATE TRIGGER (\w+)').firstMatch(sql)?.group(1);
    if (name != null) await db.execute('DROP TRIGGER $name');
  }
  for (final name in [
    'membership_benefits',
    'membership_periods',
    'membership_profiles',
    'membership_sale_plans',
  ]) {
    expect(await db.query(name), isEmpty);
    await db.execute('DROP TABLE $name');
  }
  await db.execute(
    'ALTER TABLE quick_sales_lines DROP COLUMN membership_discount',
  );
  await db.execute(
    DatabaseSchema.migration26Statements.singleWhere(
      (s) => s.startsWith('CREATE TRIGGER services_validate_insert '),
    ),
  );
  await db.delete('schema_migrations', where: 'version>=28');
  await db.execute('PRAGMA user_version=27');
}

/// Synthetic reconstruction only; never part of the runtime migration path.
Future<void> restoreReleasedV28ForFixture(DatabaseExecutor db) async {
  for (final sql in DatabaseSchema.migration29Statements) {
    final name = RegExp(r'^CREATE TRIGGER (\w+)').firstMatch(sql)?.group(1);
    if (name != null) await db.execute('DROP TRIGGER $name');
  }
  await db.execute('DROP VIEW all_receivable_settlements');
  await db.execute(
    DatabaseSchema.migration13Statements.singleWhere(
      (s) => s.startsWith('CREATE VIEW all_receivable_settlements '),
    ),
  );
  for (final table in [
    'membership_voucher_collections',
    'membership_voucher_plans',
    'membership_voucher_grants',
  ]) {
    expect(await db.query(table), isEmpty);
    await db.execute('DROP TABLE $table');
  }
  for (final column in [
    'voucher_period_id',
    'voucher_minor',
    'voucher_selected',
  ]) {
    await db.execute('ALTER TABLE quick_sales_lines DROP COLUMN $column');
  }
  await db.execute(
    DatabaseSchema.migration13Statements.singleWhere(
      (s) => s.startsWith(
        'CREATE TRIGGER collections_validate_document_posting\n',
      ),
    ),
  );
  await db.execute(
    DatabaseSchema.migration18Statements.singleWhere(
      (s) => s.startsWith('CREATE TRIGGER account_payment_prepare_guard '),
    ),
  );
  await db.delete('schema_migrations', where: 'version>=29');
  await db.execute('PRAGMA user_version=28');
}
