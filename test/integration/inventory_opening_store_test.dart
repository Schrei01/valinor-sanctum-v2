import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/schema.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_inventory_opening_store.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_opening.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/reference_inventory.dart';
import 'package:valinor_sanctum_2/features/quick_sales/data/sqlite_quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/stock_intake/data/sqlite_stock_intake_store.dart';
import 'package:valinor_sanctum_2/features/workspace/data/sqlite_workspace_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase app;
  late SqliteInventoryOpeningStore store;
  final sourceSha = List.filled(64, 'a').join();
  final snapshotSha = List.filled(64, 'b').join();
  final occurred = DateTime.utc(2026, 10, 20, 15);

  setUp(() async {
    app = await AppDatabase.open(path: inMemoryDatabasePath);
    store = SqliteInventoryOpeningStore(app, synthetic: true);
  });
  tearDown(() => app.close());

  BusinessProfile profile({
    int scale = 0,
    String name = 'Ludoteca sintética',
  }) => BusinessProfile(
    profileId: 'opening-test',
    businessName: name,
    currencyCode: 'COP',
    moneyScale: scale,
    timezone: 'America/Bogota',
    createdAtUtc: DateTime.utc(2026, 10, 20, 12),
  );

  ReferenceInventoryProduct product({
    String id = '1',
    String name = 'Nombre repetido',
    int quantity = 3,
    int price = 100000,
    int cost = 60000,
    String category = 'producto',
    String supplier = 'Proveedor A',
    String lot = 'Lote antiguo',
  }) => ReferenceInventoryProduct(
    id: id,
    name: name,
    quantity: quantity,
    priceMinor: price,
    purchasePriceMinor: cost,
    category: category,
    supplier: supplier,
    lot: lot,
  );

  ReferenceInventory reference({List<ReferenceInventoryProduct>? products}) =>
      ReferenceInventory(
        sourceName: 'synthetic.db',
        sourceSha256: sourceSha,
        capturedAtUtc: DateTime.utc(2026, 10, 20, 14),
        products:
            products ??
            [
              product(),
              product(
                id: '2',
                quantity: 2,
                cost: 0,
                category: 'comestibles',
                supplier: 'Proveedor B',
              ),
              product(
                id: '3',
                name: 'Agotado',
                quantity: 0,
                cost: 10000,
                category: 'Evento',
              ),
            ],
      );

  InventoryOpeningCommand command({
    String id = 'opening-command',
    ReferenceInventory? data,
    String? hash,
    DateTime? time,
    bool zeroConfirmed = true,
  }) => InventoryOpeningCommand(
    commandId: id,
    reference: data ?? reference(),
    snapshotSha256: hash ?? snapshotSha,
    occurredAtUtc: time ?? occurred,
    zeroCostsConfirmed: zeroConfirmed,
  );

  Future<Map<String, int>> counts() async => {
    for (final table in [
      'app_profile',
      'actors',
      'command_log',
      'business_documents',
      'catalog_items',
      'categories',
      'counterparties',
      'inventory_openings',
      'inventory_opening_items',
      'journal_entries',
      'journal_lines',
      'ledger_accounts',
      'inventory_movements',
      'purchases',
      'purchase_lines',
      'obligations',
      'cash_openings',
    ])
      table: (await app.database.query(table)).length,
  };

  test(
    'opening creates all catalog rows and equity without cash, debt or purchases',
    () async {
      final result = await store.open(command(), initialProfile: profile());
      expect(result.productCount, 3);
      expect(result.totalUnits, 5);
      expect(result.totalCostMinor, 1800);
      expect(result.productIdsBySourceId.keys.toSet(), {'1', '2', '3'});
      expect(result.productIdsBySourceId.values.toSet(), hasLength(3));
      expect(
        result.productIdsBySourceId.values.any(
          (id) => ['1', '2', '3'].contains(id),
        ),
        isFalse,
      );
      expect(() => result.productIdsBySourceId.clear(), throwsUnsupportedError);
      final catalog = await app.database.query('catalog_items', orderBy: 'id');
      expect(catalog, hasLength(3));
      expect(
        catalog.where((row) => row['name'] == 'Nombre repetido'),
        hasLength(2),
      );
      expect(catalog.every((row) => row['list_price_minor'] == 1000), isTrue);
      expect(
        catalog.every((row) => row['sku'] == null && row['is_active'] == 1),
        isTrue,
      );
      final items = await app.database.query(
        'inventory_opening_items',
        orderBy: 'sequence',
      );
      expect(items.map((row) => row['quantity']), [3, 2, 0]);
      expect(items.map((row) => row['unit_cost_minor']), [600, 0, 100]);
      expect(items.map((row) => row['zero_cost_confirmed']), [0, 1, 0]);
      expect(
        (await app.database.query(
          'categories',
        )).map((row) => row['name']).toSet(),
        {'Artículo', 'Comestible', 'Evento'},
      );
      expect(
        (await app.database.query(
          'counterparties',
        )).map((row) => row['name']).toSet(),
        {'Proveedor A', 'Proveedor B'},
      );
      final lines = await app.database.query(
        'journal_lines',
        orderBy: 'sequence',
      );
      expect(
        lines.map(
          (row) => [row['account_id'], row['debit_minor'], row['credit_minor']],
        ),
        [
          ['system:inventory', 1800, 0],
          ['system:opening-equity', 0, 1800],
        ],
      );
      final header = (await app.database.query('inventory_openings')).single;
      expect(header['source_sha256'], sourceSha);
      expect(header['snapshot_sha256'], snapshotSha);
      final document = (await app.database.query('business_documents')).single;
      expect(document['status'], 'posted');
      expect(document['type'], 'inventory_opening');
      expect(document['source_kind'], 'synthetic');
      expect(document['date_quality'], 'reconstructed');
      expect(document['business_date'], '2026-10-20');
      expect(
        (await app.database.query('journal_entries')).single['status'],
        'posted',
      );
      for (final table in [
        'purchases',
        'purchase_lines',
        'obligations',
        'supplier_payments',
        'collections',
        'cash_openings',
        'inventory_movements',
        'cost_layers',
      ]) {
        expect(await app.database.query(table), isEmpty, reason: table);
      }
      await SqliteQuickSalesStore(app).ensureDefaults();
      final balances = await SqliteStockIntakeStore(app).load();
      expect(
        balances.paymentOptions.every((option) => option.balanceMinor == 0),
        isTrue,
      );
    },
  );

  test(
    'same full payload replays original result without duplicating rows',
    () async {
      final input = command();
      final first = await store.open(input, initialProfile: profile());
      final before = await counts();
      final replay = await store.open(input, initialProfile: profile());
      expect(await counts(), before);
      expect(replay.documentId, first.documentId);
      expect(replay.productIdsBySourceId, first.productIdsBySourceId);
      expect(replay.totalCostMinor, first.totalCostMinor);
      final reversed = reference(
        products: reference().products.reversed.toList(),
      );
      expect(
        (await store.open(command(data: reversed))).documentId,
        first.documentId,
      );
      final log = (await app.database.query('command_log')).single;
      final payload = jsonDecode(log['response_json'] as String) as Map;
      final canonical =
          jsonDecode(payload['canonicalPayload'] as String) as Map;
      expect(canonical['zeroCostsConfirmed'], true);
      expect(
        ((canonical['reference'] as Map)['products'] as List).first['lot'],
        'Lote antiguo',
      );
    },
  );

  test(
    'reused command rejects changed payload, hash, date and confirmation',
    () async {
      await store.open(command(), initialProfile: profile());
      final before = await counts();
      final changedLot = reference(
        products: [
          product(lot: 'Distinto'),
          ...reference().products.skip(1),
        ],
      );
      for (final input in [
        command(data: changedLot),
        command(hash: List.filled(64, 'c').join()),
        command(time: occurred.add(const Duration(seconds: 1))),
        command(zeroConfirmed: false),
      ]) {
        await expectLater(
          store.open(input),
          throwsA(isA<InventoryOpeningValidationException>()),
        );
        expect(await counts(), before);
      }
      await expectLater(
        store.open(command(), initialProfile: profile(name: 'Otro nombre')),
        throwsA(isA<InventoryOpeningValidationException>()),
      );
      expect(await counts(), before);
    },
  );

  test(
    'second opening is rejected even under another command and snapshot',
    () async {
      await store.open(command(), initialProfile: profile());
      final before = await counts();
      await expectLater(
        store.open(command(id: 'second', hash: List.filled(64, 'c').join())),
        throwsA(isA<InventoryOpeningValidationException>()),
      );
      expect(await counts(), before);
    },
  );

  test(
    'existing catalog is preserved and never merged by matching names',
    () async {
      await SqliteWorkspaceStore(app).createProfile(profile());
      await SqliteInventoryStore(app).saveProduct(
        const CatalogProduct(
          id: 'already-existing',
          name: 'Nombre repetido',
          listPriceMinor: 1000,
        ),
      );
      final before = await counts();
      await expectLater(
        store.open(command()),
        throwsA(isA<InventoryOpeningValidationException>()),
      );
      expect(await counts(), before);
      expect(
        (await app.database.query('catalog_items')).single['id'],
        'already-existing',
      );
    },
  );

  test(
    'late posting failure rolls back profile, catalog, identities and all facts',
    () async {
      await app.database.execute('''
      CREATE TRIGGER test_reject_opening_entry BEFORE UPDATE OF status ON journal_entries
      WHEN NEW.status='posted'
      BEGIN SELECT RAISE(ABORT, 'synthetic late opening failure'); END
    ''');
      final before = await counts();
      await expectLater(
        store.open(command(), initialProfile: profile()),
        throwsA(isA<DatabaseException>()),
      );
      expect(await counts(), before);
      await app.database.execute('DROP TRIGGER test_reject_opening_entry');
      expect(
        (await store.open(command(), initialProfile: profile())).productCount,
        3,
      );
    },
  );

  test(
    'zero costs require confirmation and zero-total opening has no fake journal lines',
    () async {
      final data = reference(products: [product(cost: 0, quantity: 4)]);
      await expectLater(
        store.open(
          command(data: data, zeroConfirmed: false),
          initialProfile: profile(),
        ),
        throwsA(isA<InventoryOpeningValidationException>()),
      );
      expect(await app.database.query('app_profile'), isEmpty);
      final result = await store.open(
        command(data: data),
        initialProfile: profile(),
      );
      expect(result.totalCostMinor, 0);
      expect(result.totalUnits, 4);
      expect(await app.database.query('journal_lines'), isEmpty);
      expect(
        (await app.database.query('journal_entries')).single['status'],
        'posted',
      );
      expect(
        (await app.database.query(
          'inventory_opening_items',
        )).single['zero_cost_confirmed'],
        1,
      );
    },
  );

  test(
    'exact scale conversion rejects cents in whole-peso profile and preserves them at scale 2',
    () async {
      final data = reference(products: [product(price: 100001, cost: 60001)]);
      await expectLater(
        store.open(command(data: data), initialProfile: profile()),
        throwsA(isA<InventoryOpeningValidationException>()),
      );
      expect(await app.database.query('app_profile'), isEmpty);
      final result = await store.open(
        command(data: data),
        initialProfile: profile(scale: 2),
      );
      expect(result.totalCostMinor, 180003);
      final item = (await app.database.query('inventory_opening_items')).single;
      expect(item['unit_price_minor'], 100001);
      expect(item['unit_cost_minor'], 60001);
    },
  );

  test(
    'unknown category and total overflow fail before creating the profile',
    () async {
      final badCategory = reference(
        products: [product(category: 'Desconocida')],
      );
      await expectLater(
        store.open(command(data: badCategory), initialProfile: profile()),
        throwsA(isA<InventoryOpeningValidationException>()),
      );
      expect(await app.database.query('app_profile'), isEmpty);
      final overflow = reference(
        products: [product(quantity: 9223372036854775807)],
      );
      await expectLater(
        store.open(command(data: overflow), initialProfile: profile()),
        throwsA(isA<InventoryOpeningValidationException>()),
      );
      expect(await app.database.query('app_profile'), isEmpty);
    },
  );

  test(
    'committed opening replays with its original product IDs after reopening',
    () async {
      final root = Directory(p.join(AppConfig.repositoryRootPath, 'tmp'));
      await root.create(recursive: true);
      final sandbox = await root.createTemp('inventory_opening_reopen_');
      final path = p.join(sandbox.path, 'opening.sqlite3');
      InventoryOpeningResult? first;
      AppDatabase? disk;
      try {
        disk = await AppDatabase.open(path: path);
        first = await SqliteInventoryOpeningStore(
          disk,
          synthetic: true,
        ).open(command(), initialProfile: profile());
        await disk.close();
        disk = await AppDatabase.open(path: path);
        final replay = await SqliteInventoryOpeningStore(
          disk,
          synthetic: true,
        ).open(command(), initialProfile: profile());
        expect(replay.documentId, first.documentId);
        expect(replay.productIdsBySourceId, first.productIdsBySourceId);
        expect(await disk.database.query('inventory_openings'), hasLength(1));
        expect(
          (await disk.readHealth())['schemaVersion'],
          DatabaseSchema.version,
        );
      } finally {
        await disk?.close();
        final canonical = p.normalize(await sandbox.resolveSymbolicLinks());
        if (!p.isWithin(
          p.join(AppConfig.repositoryRootPath, 'tmp'),
          canonical,
        )) {
          throw StateError('Refusing cleanup outside the test sandbox.');
        }
        await sandbox.delete(recursive: true);
      }
    },
  );
}
