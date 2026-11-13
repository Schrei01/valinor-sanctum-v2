import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/schema.dart';
import 'package:valinor_sanctum_2/features/quick_sales/data/bulk_catalog_defaults.dart';
import 'package:valinor_sanctum_2/features/quick_sales/data/sqlite_quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/quick_sales_store.dart';
import 'quick_sales_store_test.dart' show fixture;
import '../support/released_v15_fixture.dart' show restoreReleasedV26ForFixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'v25 upgrade preserves history, prepared bulk and creates rental once',
    () async {
      final root = p.join(AppConfig.repositoryRootPath, 'tmp');
      final folder = await Directory(root).createTemp('rental-v25-');
      final path = p.join(folder.path, 'sanctum2.sqlite3');
      AppDatabase? app;
      String rows(List<Map<String, Object?>> values) =>
          jsonEncode(values.map(jsonEncode).toList()..sort());
      try {
        app = await AppDatabase.open(path: path);
        await fixture(app, moneyScale: 0);
        final db = app.database;
        await restoreReleasedV26ForFixture(db);
        // Reconstruct released v25 only inside this disposable fixture.
        await db.execute('DROP TRIGGER services_validate_insert');
        await db.execute(
          DatabaseSchema.migration25Statements.singleWhere(
            (s) => s.startsWith('CREATE TRIGGER services_validate_insert '),
          ),
        );
        await db.delete('schema_migrations', where: 'version=26');
        await db.execute('PRAGMA user_version=25');
        await db.insert('categories', {
          'id': 'articles',
          'name': 'Artículo',
          'is_active': 1,
        });
        for (final item in BulkCatalogDefaults.products.entries.where(
          (e) => e.key != BulkCatalogDefaults.rentalId,
        )) {
          await db.insert('catalog_items', {
            'id': item.key,
            'name': item.value,
            'category_id': 'articles',
            'kind': 'product',
            'unit_code': 'unit',
            'quantity_scale': 0,
            'list_price_minor': 0,
            'is_active': 1,
          });
          await db.insert('catalog_services', {
            'product_id': item.key,
            'kind': 'bulk',
          });
        }
        var quick = SqliteQuickSalesStore(app, synthetic: true);
        await quick.ensureDefaults();
        final saved = await quick.saveAccount(
          SaveQuickSaleAccount(
            id: 'prior',
            label: 'Cuenta anterior',
            expectedRevision: 0,
            lines: [
              const QuickSaleLine(
                id: 'prior-line',
                productId: 'bulk:sales:magic',
                quantityText: '1',
                unitPriceMinor: 5000,
                paymentOptionId: 'quick-default:EFECTIVO',
              ),
            ],
          ),
        );
        await quick.prepareSale(
          commandId: 'prior-request',
          accountId: saved.id,
          expectedRevision: saved.revision,
          occurredAtUtc: DateTime.utc(2026, 11, 8, 15),
        );
        final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
        );
        final before = <String, String>{
          for (final table in tables)
            table['name'] as String: rows(
              await db.query(table['name'] as String),
            ),
        };
        await app.close();
        app = null;
        app = await AppDatabase.open(path: path);
        expect(await app.database.getVersion(), DatabaseSchema.version);
        for (final table in before.entries) {
          final after = await app.database.query(
            table.key,
            where: table.key == 'schema_migrations' ? 'version<=25' : null,
          );
          final priorColumns = after.map((row) {
            final copy = Map<String, Object?>.from(row);
            if (table.key == 'quick_sales_lines') {
              expect(copy.remove('membership_discount'), 0);
              expect(copy.remove('voucher_selected'), 0);
              expect(copy.remove('voucher_minor'), 0);
              expect(copy.remove('voucher_period_id'), isNull);
            }
            return copy;
          }).toList();
          expect(rows(priorColumns), table.value, reason: table.key);
        }
        final backups = await Directory(p.join(folder.path, 'backups'))
            .list()
            .where((f) => f is File && f.path.endsWith('.sqlite3'))
            .toList();
        expect(backups, hasLength(1));
        final backup = await databaseFactoryFfi.openDatabase(
          backups.single.path,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
        );
        try {
          expect(await backup.getVersion(), 25);
          for (final table in before.entries) {
            expect(
              rows(await backup.query(table.key)),
              table.value,
              reason: 'backup ${table.key}',
            );
          }
        } finally {
          await backup.close();
        }
        quick = SqliteQuickSalesStore(app, synthetic: true);
        await quick.ensureBulkProducts();
        await quick.ensureBulkProducts();
        final snapshot = await quick.load();
        final rental = snapshot.availableProducts.singleWhere(
          (p) => p.id == BulkCatalogDefaults.rentalId,
        );
        expect(rental.name, 'Alquiler');
        expect(rental.isVariablePrice, isTrue);
        expect(rental.isUnlimited, isTrue);
        expect(rental.listPriceMinor, 0);
        expect(
          await app.database.query(
            'product_price_history',
            where: 'product_id=?',
            whereArgs: [rental.id],
          ),
          hasLength(1),
        );
        await quick.confirmPrepared('prior-request');
        await quick.confirmPrepared('prior-request');
        expect(await app.database.query('sales'), hasLength(1));
        expect(
          (await app.database.query('sale_lines')).single['total_minor'],
          5000,
        );
        expect(
          await app.database.rawQuery('PRAGMA foreign_key_check'),
          isEmpty,
        );
        expect(
          (await app.database.rawQuery(
            'PRAGMA integrity_check',
          )).single.values.single,
          'ok',
        );
      } finally {
        await app?.close();
        if (!p.isWithin(root, await folder.resolveSymbolicLinks())) {
          throw StateError('Unsafe cleanup');
        }
        await folder.delete(recursive: true);
      }
    },
  );
}
