import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/schema.dart';
import 'package:valinor_sanctum_2/features/stock_intake/data/sqlite_stock_intake_store.dart';
import 'package:valinor_sanctum_2/features/stock_intake/domain/stock_intake_store.dart';
import 'package:valinor_sanctum_2/features/workspace/data/sqlite_workspace_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';
import '../support/released_v15_fixture.dart';

Future<Map<String, List<Map<String, Object?>>>> rows(
  DatabaseExecutor db,
) async => {
  for (final table in await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
  ))
    table['name'] as String: await db.query(table['name'] as String),
};

/// Synthetic fixture only: use valid legacy unit-mode facts, then restore the
/// exact released v14 definitions before exercising the forward migration.
/// No reverse migration or production downgrade API is introduced.
Future<Database> releasedV14Fixture(String path) async {
  final app = await AppDatabase.open(path: path);
  await SqliteWorkspaceStore(app).createProfile(
    BusinessProfile(
      profileId: 'synthetic',
      businessName: 'Tienda sintética',
      currencyCode: 'COP',
      moneyScale: 0,
      timezone: 'America/Bogota',
      createdAtUtc: DateTime.utc(2026, 10, 27),
    ),
  );
  final store = SqliteStockIntakeStore(app, synthetic: true);
  await store.ensureDefaults();
  final category = (await store.load()).categories.first.id;
  await store.recordOpeningBalance(
    CashOpeningCommand(
      commandId: 'fund',
      paymentOptionId: 'quick-default:EFECTIVO',
      amountMinor: 10000,
      occurredAtUtc: DateTime.utc(2026, 10, 27, 8),
    ),
  );
  StockIntakeCommand old(String id, int hour) => StockIntakeCommand(
    commandId: id,
    productId: 'product-$id',
    productName: 'Producto $id',
    categoryId: category,
    supplierName: 'Proveedor',
    unitPurchasePriceMinor: 100,
    listPriceMinor: 200,
    quantity: 2,
    paymentOptionId: 'quick-default:EFECTIVO',
    occurredAtUtc: DateTime.utc(2026, 10, 27, hour),
  );
  await store.prepare(old('posted', 9));
  await store.confirmPrepared('posted');
  await store.prepare(old('pending', 10));
  await app.close();
  final db = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  await db.execute('PRAGMA foreign_keys=ON');
  await db.transaction((txn) async {
    await restoreReleasedV15ForFixture(txn);
    await txn.execute('DROP TRIGGER catalog_price_history_created');
    await txn.execute('DROP TRIGGER catalog_price_history_changed');
    await txn.execute('DROP TABLE product_price_history');
    final entries = await txn.query('paid_purchase_entries');
    await txn.execute('DROP TRIGGER paid_purchase_requests_validate_update');
    await txn.execute('DROP TABLE paid_purchase_entries');
    await txn.execute(
      DatabaseSchema.migration7Statements.singleWhere(
        (s) => s.contains('CREATE TABLE paid_purchase_entries ('),
      ),
    );
    for (final entry in entries) {
      await txn.insert('paid_purchase_entries', entry);
    }
    for (final sql in DatabaseSchema.migration7Statements.where(
      (s) =>
          s.contains('CREATE TRIGGER paid_purchase_entries_') ||
          s.contains(
            'CREATE TRIGGER paid_purchase_requests_validate_update\n',
          ) ||
          s.startsWith('CREATE INDEX idx_paid_purchase_entries_product'),
    )) {
      await txn.execute(sql);
    }
    await txn.delete('schema_migrations', where: 'version=15');
    await txn.execute('PRAGMA user_version=14');
  });
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
      where: 'version=14',
    )).single['schema_checksum'],
  );
  return db;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory fixture;
  setUp(() async {
    final parent = Directory(
      p.join(
        AppConfig.repositoryRootPath,
        'tmp',
        'total-purchase-schema-tests',
      ),
    );
    await parent.create(recursive: true);
    fixture = await parent.createTemp('case-');
  });
  tearDown(() async {
    expect(
      p.isWithin(
        p.join(
          AppConfig.repositoryRootPath,
          'tmp',
          'total-purchase-schema-tests',
        ),
        fixture.path,
      ),
      isTrue,
    );
    await fixture.delete(recursive: true);
  });
  test(
    'v14 posted history and pending unit request survive with verified backup; new total cost is exact',
    () async {
      final path = p.join(fixture.path, 'old.sqlite3');
      final old = await releasedV14Fixture(path);
      final before = await rows(old);
      await old.close();
      var app = await AppDatabase.open(path: path);
      try {
        expect(
          (await app.readHealth())['schemaVersion'],
          AppDatabase.schemaVersion,
        );
        final after = await rows(app.database);
        for (final table in before.keys) {
          expect(
            table == 'schema_migrations'
                ? after[table]!.take(14).toList()
                : after[table],
            before[table],
            reason: table,
          );
        }
        final baseline = (await app.database.query(
          'product_price_history',
        )).single;
        expect(baseline['source'], 'baseline');
        expect(baseline['price_minor'], 200);
        expect(baseline['operation_at_utc'], isNull);
        final backups = await Directory(
          p.join(fixture.path, 'backups'),
        ).list().toList();
        expect(backups, hasLength(1));
        final backup = await databaseFactoryFfi.openDatabase(
          backups.single.path,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
        );
        expect(await backup.getVersion(), 14);
        expect(await rows(backup), before);
        await backup.close();
        final store = SqliteStockIntakeStore(app, synthetic: true);
        final pending = (await store.load()).pendingIntakes.single.command;
        expect(pending.totalPurchasePriceMinor, isNull);
        expect(pending.totalCostMinor, 200);
        await store.prepare(pending);
        final first = await store.confirmPrepared('pending');
        expect(
          (await store.confirmPrepared('pending')).purchaseDocumentId,
          first.purchaseDocumentId,
        );
        final product = (await store.load()).products.singleWhere(
          (p) => p.id == 'product-posted',
        );
        await store.prepare(
          StockIntakeCommand(
            commandId: 'total',
            productId: product.id,
            expectedProduct: product,
            productName: product.name,
            categoryId: product.categoryId!,
            supplierName: 'Proveedor',
            totalPurchasePriceMinor: 251,
            listPriceMinor: 180,
            quantity: 2,
            paymentOptionId: 'quick-default:EFECTIVO',
            occurredAtUtc: DateTime.utc(2026, 10, 27, 11),
          ),
        );
        await store.confirmPrepared('total');
        final state = await store.load();
        expect(
          state.entries
              .singleWhere((e) => e.commandId == 'total')
              .totalCostMinor,
          251,
        );
        expect(
          state.entries
              .singleWhere((e) => e.commandId == 'total')
              .unitPurchasePriceMinor,
          isNull,
        );
        expect(
          state.paymentOptions
              .singleWhere((o) => o.label == 'Efectivo')
              .balanceMinor,
          9349,
        );
        final history = await app.database.query(
          'product_price_history',
          where: 'product_id=?',
          whereArgs: [product.id],
          orderBy: 'id',
        );
        expect(history.map((h) => h['price_minor']), [200, 180]);
        await app.close();
        app = await AppDatabase.open(path: path);
        expect(
          await app.database.query(
            'product_price_history',
            where: 'product_id=?',
            whereArgs: [product.id],
            orderBy: 'id',
          ),
          history,
        );
        expect((await app.readHealth())['integrityOk'], isTrue);
      } finally {
        await app.close();
      }
    },
  );
  test(
    'failure to create the v14 backup leaves the legacy file unchanged',
    () async {
      final path = p.join(fixture.path, 'old.sqlite3');
      final old = await releasedV14Fixture(path);
      await old.close();
      await File(p.join(fixture.path, 'backups')).writeAsString('block backup');
      final before = await File(path).readAsBytes();
      await expectLater(
        AppDatabase.open(path: path),
        throwsA(isA<FileSystemException>()),
      );
      expect(await File(path).readAsBytes(), before);
    },
  );
}
