import 'package:valinor_sanctum_2/features/inventory/domain/stock_adjustment_store.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import '../support/released_v15_fixture.dart';
import 'quick_sales_store_test.dart' show fixture;

Future<Map<String, String>> allRows(DatabaseExecutor db) async => {
  for (final row in await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
  ))
    row['name'] as String: jsonEncode([
      for (final record in await db.query(row['name'] as String))
        {
          for (final e in record.entries)
            if (!((row['name'] == 'inventory_movements' &&
                    e.key == 'stock_addition_id') ||
                (row['name'] == 'quick_sales_accounts' &&
                    e.key == 'created_at_utc')))
              e.key: e.value,
        },
    ]),
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUp(() async {
    dir = await Directory(
      p.join(AppConfig.repositoryRootPath, 'tmp'),
    ).createTemp('catalog-schema-');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  Future<Database> old({bool nonzero = false}) async {
    final path = p.join(dir.path, 'v15.sqlite3');
    final app = await AppDatabase.open(path: path);
    await fixture(app);
    final store = SqliteInventoryStore(app, synthetic: true);
    await store.saveProduct(
      CatalogProduct(
        id: 'pass',
        name: nonzero ? 'Pendiente' : 'Pasadía',
        listPriceMinor: 5000,
      ),
    );
    await store.saveProduct(
      const CatalogProduct(
        id: 'pass2',
        name: 'Pasadía 2',
        listPriceMinor: 6000,
      ),
    );
    if (nonzero) {
      await store.receivePurchase(
        ReceiptCommand(
          commandId: 'physical',
          supplierId: 'supplier',
          dueDate: '2026-10-21',
          occurredAtUtc: DateTime.utc(2026, 10, 20),
          lines: const [
            ReceiptLineInput(
              productId: 'pass',
              quantity: 2,
              totalCostMinor: 100,
            ),
          ],
        ),
      );
      await store.saveProduct(
        const CatalogProduct(id: 'pass', name: 'Pasadía', listPriceMinor: 5000),
      );
    }
    await app.close();
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await db.execute('PRAGMA foreign_keys=ON');
    await db.transaction(restoreReleasedV15ForFixture);
    return db;
  }

  test(
    'v15 forward migration preserves all released rows/checksums, creates only exact Pasadia classification and verified backup',
    () async {
      final beforeDb = await old(), before = await allRows(beforeDb);
      final migrations = await beforeDb.query('schema_migrations');
      await beforeDb.close();
      final app = await AppDatabase.open(path: p.join(dir.path, 'v15.sqlite3'));
      final after = await allRows(app.database);
      for (final table in before.keys) {
        expect(
          table == 'schema_migrations'
              ? jsonEncode((await app.database.query(table)).take(15).toList())
              : after[table],
          before[table],
          reason: table,
        );
      }
      expect(await app.database.query('catalog_services'), [
        {'product_id': 'pass', 'kind': 'day_pass'},
      ]);
      expect(await app.database.query('stock_adjustments'), isEmpty);
      expect(
        (await app.readHealth())['schemaVersion'],
        AppDatabase.schemaVersion,
      );
      final backup = (await Directory(
        p.join(dir.path, 'backups'),
      ).list().toList()).whereType<File>().single;
      final b = await databaseFactoryFfi.openDatabase(
        backup.path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      expect(await allRows(b), before);
      expect(await b.query('schema_migrations'), migrations);
      await b.close();
      await app.close();
      final reopened = await AppDatabase.open(
        path: p.join(dir.path, 'v15.sqlite3'),
      );
      expect(await reopened.database.query('catalog_services'), hasLength(1));
      final store = SqliteInventoryStore(reopened, synthetic: true);
      await store.prepareAdjustment(
        StockAdjustmentCommand(
          commandId: 'durable',
          productId: 'product',
          quantity: 2,
          reason: 'Prueba',
          occurredAtUtc: DateTime.utc(2026, 10, 20, 14),
        ),
      );
      await reopened.close();
      final retry = await AppDatabase.open(
        path: p.join(dir.path, 'v15.sqlite3'),
      );
      final restored = SqliteInventoryStore(retry, synthetic: true);
      expect(await restored.pendingAdjustments(), hasLength(1));
      await restored.confirmAdjustment('durable');
      await restored.confirmAdjustment('durable');
      expect(
        (await restored.load()).stock
            .singleWhere((s) => s.productId == 'product')
            .quantity,
        8,
      );
      await retry.close();
    },
  );
  test(
    'nonzero physical Pasadia cost rejects conversion without altering v15 data or schema',
    () async {
      final db = await old(nonzero: true), before = await allRows(db);
      final schema = await db.rawQuery(
        "SELECT type,name,sql FROM sqlite_master ORDER BY type,name",
      );
      await db.close();
      await expectLater(
        AppDatabase.open(path: p.join(dir.path, 'v15.sqlite3')),
        throwsA(anything),
      );
      final after = await databaseFactoryFfi.openDatabase(
        p.join(dir.path, 'v15.sqlite3'),
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      expect(await allRows(after), before);
      expect(
        await after.rawQuery(
          "SELECT type,name,sql FROM sqlite_master ORDER BY type,name",
        ),
        schema,
      );
      expect(
        (await after.rawQuery('PRAGMA user_version')).single.values.single,
        15,
      );
      await after.close();
    },
  );
}
