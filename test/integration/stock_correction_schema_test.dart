import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/stock_adjustment_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/data/sqlite_quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/quick_sales_store.dart';
import '../support/released_v15_fixture.dart';
import 'quick_sales_store_test.dart' show fixture;

Future<Map<String, List<Map<String, Object?>>>> all(
  DatabaseExecutor db,
) async => {
  for (final t in await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
  ))
    t['name'] as String: await db.query(t['name'] as String),
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'v20 migration keeps posted movements, accounts and pending negative corrections with verified backup',
    () async {
      final parent = Directory(
        p.join(Directory.current.path, 'tmp', 'correction-migration-tests'),
      );
      await parent.create(recursive: true);
      final directory = await parent.createTemp('fixture_');
      final path = p.join(directory.path, 'inventory.sqlite3');
      var app = await AppDatabase.open(path: path);
      try {
        await fixture(app);
        var inventory = SqliteInventoryStore(app, synthetic: true);
        StockAdjustmentCommand correction(
          String id,
          int qty, {
          bool add = false,
        }) => StockAdjustmentCommand(
          commandId: id,
          productId: 'product',
          quantity: qty,
          isAddition: add,
          reason: 'Corrección sintética',
          occurredAtUtc: DateTime.utc(2026, 10, 30),
        );
        final quick = SqliteQuickSalesStore(app, synthetic: true);
        await quick.ensureDefaults();
        await quick.saveAccount(
          SaveQuickSaleAccount(
            id: 'legacy',
            label: 'Anterior',
            expectedRevision: 0,
            lines: const [],
          ),
        );
        await inventory.prepareAdjustment(correction('posted', 1));
        await inventory.confirmAdjustment('posted');
        await inventory.prepareAdjustment(correction('pending', 2));
        await app.database.transaction(restoreReleasedV20ForFixture);
        final before = await all(app.database);
        await app.close();
        app = await AppDatabase.open(path: path);
        for (final table in before.keys) {
          if (table == 'schema_migrations') {
            expect(
              (await app.database.query(table)).take(20).toList(),
              before[table],
            );
            continue;
          }
          final columns = before[table]!.isEmpty
              ? null
              : before[table]!.first.keys.toList();
          expect(
            await app.database.query(table, columns: columns),
            before[table],
            reason: table,
          );
        }
        expect(await app.database.query('stock_additions'), isEmpty);
        final backups =
            (await Directory(p.join(directory.path, 'backups')).list().toList())
                .whereType<File>()
                .where((f) => p.basename(f.path).startsWith('inventory.v20.'));
        final backup = await databaseFactoryFfi.openDatabase(
          backups.single.path,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
        );
        expect(jsonEncode(await all(backup)), jsonEncode(before));
        await backup.close();
        inventory = SqliteInventoryStore(app, synthetic: true);
        await inventory.confirmAdjustment('pending');
        await inventory.prepareAdjustment(correction('positive', 4, add: true));
        await app.close();
        app = await AppDatabase.open(path: path);
        inventory = SqliteInventoryStore(app, synthetic: true);
        await inventory.confirmAdjustment('positive');
        final after = await all(app.database);
        await inventory.confirmAdjustment('positive');
        expect(await all(app.database), after);
        expect(
          (await inventory.load()).stock
              .singleWhere((s) => s.productId == 'product')
              .quantity,
          11,
        );
        expect(
          await app.database.rawQuery('PRAGMA foreign_key_check'),
          isEmpty,
        );
        expect((await app.readHealth())['integrityOk'], isTrue);
      } finally {
        await app.close();
      }
    },
  );
}
