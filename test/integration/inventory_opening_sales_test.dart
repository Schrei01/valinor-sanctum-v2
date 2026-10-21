import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/features/events/data/sqlite_events_store.dart';
import 'package:valinor_sanctum_2/features/events/domain/events_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/features/collections/data/sqlite_collections_store.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_inventory_opening_store.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_opening.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/reference_inventory.dart';
import 'package:valinor_sanctum_2/features/quick_sales/data/sqlite_quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/sales/data/sqlite_sales_store.dart';
import 'package:valinor_sanctum_2/features/workspace/data/sqlite_workspace_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase app;
  late SqliteInventoryStore inventory;
  late SqliteQuickSalesStore quick;
  final openingAt = DateTime.utc(2026, 10, 20, 12);
  setUp(() async {
    app = await AppDatabase.open(path: inMemoryDatabasePath);
    inventory = SqliteInventoryStore(app, synthetic: true);
    quick = SqliteQuickSalesStore(app, synthetic: true);
    await SqliteWorkspaceStore(app).createProfile(
      BusinessProfile(
        profileId: 'opening-sales-synthetic',
        businessName: 'Ludoteca sintética',
        currencyCode: 'COP',
        moneyScale: 2,
        timezone: 'America/Bogota',
        createdAtUtc: DateTime.utc(2026, 10, 20, 11),
      ),
    );
  });
  tearDown(() => app.close());

  Future<InventoryOpeningResult> opening({
    List<ReferenceInventoryProduct>? products,
  }) => SqliteInventoryOpeningStore(app, synthetic: true).open(
    InventoryOpeningCommand(
      commandId: 'inventory-opening-synthetic',
      reference: ReferenceInventory(
        sourceName: 'inventario-sintetico.sqlite3',
        sourceSha256: List.filled(64, 'a').join(),
        capturedAtUtc: DateTime.utc(2026, 10, 20, 11, 30),
        products:
            products ??
            const [
              ReferenceInventoryProduct(
                id: 'normal',
                name: 'Producto con costo',
                quantity: 3,
                priceMinor: 500,
                purchasePriceMinor: 101,
                category: 'Comestible',
                supplier: 'Proveedor apertura',
              ),
              ReferenceInventoryProduct(
                id: 'zero-cost',
                name: 'Producto con costo cero confirmado',
                quantity: 4,
                priceMinor: 200,
                purchasePriceMinor: 0,
                category: 'Artículo',
                supplier: 'Proveedor apertura',
              ),
              ReferenceInventoryProduct(
                id: 'exhausted',
                name: 'Producto agotado conservado',
                quantity: 0,
                priceMinor: 700,
                purchasePriceMinor: 350,
                category: 'Evento',
                supplier: 'Proveedor agotado',
              ),
            ],
      ),
      snapshotSha256: List.filled(64, 'b').join(),
      occurredAtUtc: openingAt,
      zeroCostsConfirmed: true,
    ),
  );

  QuickSaleLine line(String id, String product, int quantity, int price) =>
      QuickSaleLine(
        id: id,
        productId: product,
        quantityText: '$quantity',
        unitPriceMinor: price,
        paymentOptionId: 'quick-default:EFECTIVO',
      );

  Future<void> prepare(
    String id,
    List<QuickSaleLine> lines, {
    DateTime? at,
  }) async {
    await quick.ensureDefaults();
    final account = await quick.saveAccount(
      SaveQuickSaleAccount(
        id: 'account-$id',
        label: 'Cuenta sintética $id',
        expectedRevision: 0,
        lines: lines,
      ),
    );
    await quick.prepareSale(
      commandId: id,
      accountId: account.id,
      expectedRevision: account.revision,
      occurredAtUtc: at ?? openingAt.add(const Duration(hours: 2)),
    );
  }

  Future<StockPosition> stock(String product) async => (await inventory.load())
      .stock
      .singleWhere((position) => position.productId == product);

  test(
    'only zero-cost prizes still require minimum and consume quantities without a monetary journal',
    () async {
      final imported = await opening();
      final zero = imported.productIdsBySourceId['zero-cost']!;
      final events = SqliteEventsStore(app, synthetic: true);
      await events.prepare(
        CreateEvent(
          commandId: 'zero-prizes',
          name: 'Evento de prueba',
          minimumPeople: 3,
          fixedCostMinor: 0,
          pvpMinor: 1000,
          occurredAtUtc: openingAt.add(const Duration(minutes: 10)),
          products: [EventProductInput(zero, 2)],
        ),
      );
      await events.confirm('zero-prizes');
      final record = (await events.load()).events.single;
      expect(record.unitCostMinor, 0);
      expect(record.totalCostMinor, 0);
      expect((await stock(zero)).quantity, 2);
      final document = (await app.database.query(
        'events',
      )).single['document_id'];
      final journal = await app.database.rawQuery(
        'SELECT line.* FROM journal_lines line JOIN journal_entries entry ON entry.id=line.entry_id WHERE entry.document_id=?',
        [document],
      );
      expect(journal, isEmpty);
      expect(await app.database.query('sales'), isEmpty);
      expect(await app.database.query('purchases'), isEmpty);
    },
  );

  test(
    'event prizes consume opening stock including confirmed zero cost, then sale consumes only remaining units',
    () async {
      final imported = await opening();
      final normal = imported.productIdsBySourceId['normal']!,
          zero = imported.productIdsBySourceId['zero-cost']!;
      final events = SqliteEventsStore(app, synthetic: true);
      await expectLater(
        events.prepare(
          CreateEvent(
            commandId: 'invalid-min',
            name: 'Evento sintético',
            minimumPeople: 0,
            fixedCostMinor: 0,
            pvpMinor: 1000,
            occurredAtUtc: openingAt.add(const Duration(minutes: 10)),
            products: [EventProductInput(zero, 1)],
          ),
        ),
        throwsA(isA<EventsValidationException>()),
      );
      await events.prepare(
        CreateEvent(
          commandId: 'opening-prizes',
          name: 'Evento sintético',
          minimumPeople: 2,
          fixedCostMinor: 0,
          pvpMinor: 1000,
          occurredAtUtc: openingAt.add(const Duration(minutes: 10)),
          products: [EventProductInput(normal, 2), EventProductInput(zero, 1)],
        ),
      );
      final event = await events.confirm('opening-prizes');
      expect((await stock(normal)).quantity, 1);
      expect((await stock(normal)).totalCostMinor, 101);
      expect((await stock(zero)).quantity, 3);
      final record = (await events.load()).events.single;
      expect(record.productsCostMinor, 202);
      expect(record.unitCostMinor, 101);
      await prepare('after-prizes', [
        line('l1', normal, 1, 500),
        line('l2', event, 10, 1000),
      ]);
      await quick.confirmPrepared('after-prizes');
      expect((await stock(normal)).quantity, 0);
      final sale = (await app.database.query('sales')).single;
      expect(sale['total_cost_minor'], 101);
      await prepare('oversell-prizes', [line('l3', normal, 1, 500)]);
      await expectLater(
        quick.confirmPrepared('oversell-prizes'),
        throwsA(anything),
      );
      expect((await app.readHealth())['foreignKeyViolations'], 0);
    },
  );

  test(
    'posted opening supplies saleable stock and supplier filters without inventing purchases or debt',
    () async {
      final result = await opening();
      final snapshot = await inventory.load();
      final normal = result.productIdsBySourceId['normal']!;
      final free = result.productIdsBySourceId['zero-cost']!;
      final empty = result.productIdsBySourceId['exhausted']!;
      expect(snapshot.products, hasLength(3));
      expect((await stock(normal)).quantity, 3);
      expect((await stock(normal)).totalCostMinor, 303);
      expect((await stock(free)).quantity, 4);
      expect((await stock(free)).totalCostMinor, 0);
      expect(
        snapshot.stock.any((position) => position.productId == empty),
        isFalse,
      );
      expect(
        snapshot.products.singleWhere((product) => product.id == empty).name,
        'Producto agotado conservado',
      );
      for (final product in snapshot.products) {
        final supplierId = snapshot.productSupplierIds[product.id]!.single;
        expect(
          snapshot.suppliers.any((supplier) => supplier.id == supplierId),
          isTrue,
        );
      }
      final sales = await SqliteSalesStore(app).load();
      expect(
        sales.stock
            .singleWhere((position) => position.productId == normal)
            .quantity,
        3,
      );
      expect(
        sales.stock
            .singleWhere((position) => position.productId == free)
            .totalCostMinor,
        0,
      );
      expect(
        sales.stock.any((position) => position.productId == empty),
        isFalse,
      );
      expect(snapshot.receipts, isEmpty);
      for (final table in [
        'purchases',
        'obligations',
        'collections',
        'supplier_payments',
        'cash_accounts',
      ]) {
        expect(await app.database.query(table), isEmpty, reason: table);
      }
      expect(
        await app.database.query('inventory_opening_layers'),
        hasLength(2),
      );
    },
  );

  test(
    'a quick cash sale consumes opening stock and confirmed zero cost once with full settlement',
    () async {
      final imported = await opening();
      final normal = imported.productIdsBySourceId['normal']!;
      final free = imported.productIdsBySourceId['zero-cost']!;
      await prepare('sale', [
        line('normal-line', normal, 2, 500),
        line('free-line', free, 1, 200),
      ]);
      final first = await quick.confirmPrepared('sale');
      expect(first.totalMinor, 1200);
      expect(first.totalCostMinor, 202);
      expect((await stock(normal)).quantity, 1);
      expect((await stock(normal)).totalCostMinor, 101);
      expect((await stock(free)).quantity, 3);
      expect((await stock(free)).totalCostMinor, 0);
      final allocations = await app.database.query(
        'inventory_opening_allocations',
      );
      expect(allocations, hasLength(2));
      expect(allocations.map((row) => row['cost_minor']).toSet(), {0, 202});
      expect(await app.database.query('sale_cost_allocations'), isEmpty);
      final money = await SqliteCollectionsStore(app).load();
      expect(
        money.accounts
            .singleWhere((account) => account.kind == 'cash')
            .balanceMinor,
        1200,
      );
      expect(
        money.accounts
            .singleWhere((account) => account.kind == 'mobile')
            .balanceMinor,
        0,
      );
      expect(
        money.receivables.every((receivable) => receivable.remainingMinor == 0),
        isTrue,
      );
      expect(money.collections.single.totalMinor, 1200);
      final entry = (await app.database.query(
        'journal_entries',
        where: 'document_id=?',
        whereArgs: [first.saleDocumentId],
      )).single;
      expect(entry['status'], 'posted');
      expect(entry['cost_completeness'], 'complete');
      final journal = await app.database.query(
        'journal_lines',
        where: 'entry_id=?',
        whereArgs: [entry['id']],
      );
      expect(journal, hasLength(4));
      expect(
        journal.fold<int>(0, (sum, row) => sum + (row['debit_minor'] as int)),
        1402,
      );
      expect(
        journal.fold<int>(0, (sum, row) => sum + (row['credit_minor'] as int)),
        1402,
      );
      final before = {
        for (final table in [
          'sales',
          'collections',
          'sale_outflows',
          'inventory_opening_allocations',
          'journal_lines',
        ])
          table: await app.database.query(table),
      };
      final replay = await SqliteQuickSalesStore(app).confirmPrepared('sale');
      expect(replay.saleDocumentId, first.saleDocumentId);
      expect(replay.collectionDocumentId, first.collectionDocumentId);
      expect(replay.totalCostMinor, 202);
      for (final table in before.keys) {
        expect(await app.database.query(table), before[table], reason: table);
      }
      expect((await stock(normal)).quantity, 1);
      expect((await stock(free)).quantity, 3);
    },
  );

  test(
    'an entirely zero cost opening can be sold without fictitious cost journal lines',
    () async {
      final imported = await opening(
        products: const [
          ReferenceInventoryProduct(
            id: 'free',
            name: 'Artículo costo cero confirmado',
            quantity: 4,
            priceMinor: 200,
            purchasePriceMinor: 0,
            category: 'Artículo',
            supplier: 'Proveedor sintético',
          ),
        ],
      );
      final product = imported.productIdsBySourceId['free']!;
      expect(imported.totalCostMinor, 0);
      expect(
        (await app.database.query('journal_entries')).single['status'],
        'posted',
      );
      expect(await app.database.query('journal_lines'), isEmpty);
      await prepare('zero-sale', [line('zero-line', product, 2, 200)]);
      final result = await quick.confirmPrepared('zero-sale');
      expect(result.totalMinor, 400);
      expect(result.totalCostMinor, 0);
      final entry = (await app.database.query(
        'journal_entries',
        where: 'document_id=?',
        whereArgs: [result.saleDocumentId],
      )).single;
      final journal = await app.database.query(
        'journal_lines',
        where: 'entry_id=?',
        whereArgs: [entry['id']],
      );
      expect(journal, hasLength(2));
      expect(
        journal.any(
          (row) =>
              row['account_id'] == 'system:inventory' ||
              row['account_id'] == 'system:cost-of-sales',
        ),
        isFalse,
      );
      expect(entry['cost_completeness'], 'complete');
      expect((await stock(product)).quantity, 2);
      expect((await stock(product)).totalCostMinor, 0);
      expect(
        (await SqliteCollectionsStore(app).load()).accounts
            .singleWhere((account) => account.kind == 'cash')
            .balanceMinor,
        400,
      );
    },
  );

  test(
    'mixed FIFO exhausts opening before replenishment and preserves its front remainder cost',
    () async {
      final imported = await opening();
      final product = imported.productIdsBySourceId['normal']!;
      final supplier =
          (await inventory.load()).productSupplierIds[product]!.single;
      // Exercise the established receipt seam to create a second, independent
      // cost layer; this fixture does not use the commercial purchase screen.
      await inventory.receivePurchase(
        ReceiptCommand(
          commandId: 'replenishment',
          supplierId: supplier,
          lines: [
            ReceiptLineInput(
              productId: product,
              quantity: 2,
              totalCostMinor: 301,
            ),
          ],
          dueDate: '2026-10-21',
          occurredAtUtc: openingAt.add(const Duration(hours: 1)),
        ),
      );
      expect((await stock(product)).quantity, 5);
      expect((await stock(product)).totalCostMinor, 604);
      await prepare('mixed-sale', [line('mixed-line', product, 4, 500)]);
      final first = await quick.confirmPrepared('mixed-sale');
      expect(first.totalCostMinor, 454); // 3 × 101 + first purchase unit 151.
      final allocations = await app.database.query(
        'all_sale_cost_allocations',
        orderBy: 'sequence',
      );
      expect(allocations, hasLength(2));
      expect(allocations.map((row) => row['source_kind']), [
        'opening',
        'purchase',
      ]);
      expect(allocations.map((row) => row['sequence']), [0, 1]);
      expect(allocations.map((row) => row['quantity']), [3, 1]);
      expect(allocations.map((row) => row['cost_minor']), [303, 151]);
      expect((await stock(product)).quantity, 1);
      expect((await stock(product)).totalCostMinor, 150);
      final saleStock = (await SqliteSalesStore(
        app,
      ).load()).stock.singleWhere((position) => position.productId == product);
      expect(saleStock.quantity, 1);
      expect(saleStock.totalCostMinor, 150);
      await prepare('last-sale', [
        line('last-line', product, 1, 500),
      ], at: openingAt.add(const Duration(hours: 3)));
      final last = await quick.confirmPrepared('last-sale');
      expect(last.totalCostMinor, 150);
      expect((await stock(product)).quantity, 0);
      expect((await stock(product)).totalCostMinor, 0);
      expect(
        (await app.database.query(
          'all_sale_cost_allocations',
        )).fold<int>(0, (sum, row) => sum + (row['cost_minor'] as int)),
        604,
      );
    },
  );

  test(
    'insufficient opening stock rejects the complete sale without consuming money or inventory',
    () async {
      final imported = await opening();
      final product = imported.productIdsBySourceId['normal']!;
      final journalBefore = await app.database.query('journal_lines');
      await prepare('insufficient', [line('too-many', product, 4, 500)]);
      await expectLater(
        quick.confirmPrepared('insufficient'),
        throwsA(isA<QuickSalesValidationException>()),
      );
      expect((await stock(product)).quantity, 3);
      expect((await stock(product)).totalCostMinor, 303);
      for (final table in [
        'sales',
        'collections',
        'sale_outflows',
        'inventory_opening_allocations',
        'sale_cost_allocations',
      ]) {
        expect(await app.database.query(table), isEmpty, reason: table);
      }
      expect(await app.database.query('journal_lines'), journalBefore);
      expect(
        (await SqliteCollectionsStore(
          app,
        ).load()).accounts.every((account) => account.balanceMinor == 0),
        isTrue,
      );
      expect(
        (await app.database.query('quick_sale_requests')).single['status'],
        'rejected',
      );
    },
  );

  test(
    'sales and receipts cannot predate the opening, including catalog items with zero units',
    () async {
      final imported = await opening();
      final snapshot = await inventory.load();
      final before = openingAt.subtract(const Duration(seconds: 1));
      for (final source in ['normal', 'exhausted']) {
        final product = imported.productIdsBySourceId[source]!;
        await expectLater(
          inventory.receivePurchase(
            ReceiptCommand(
              commandId: 'backdated-$source',
              supplierId: snapshot.productSupplierIds[product]!.single,
              lines: [
                ReceiptLineInput(
                  productId: product,
                  quantity: 1,
                  totalCostMinor: 100,
                ),
              ],
              dueDate: '2026-10-21',
              occurredAtUtc: before,
            ),
          ),
          throwsA(isA<InventoryValidationException>()),
        );
      }
      final product = imported.productIdsBySourceId['normal']!;
      await prepare('backdated-sale', [
        line('early', product, 1, 500),
      ], at: before);
      await expectLater(
        quick.confirmPrepared('backdated-sale'),
        throwsA(isA<QuickSalesValidationException>()),
      );
      expect((await stock(product)).quantity, 3);
      expect((await stock(product)).totalCostMinor, 303);
      for (final table in [
        'purchases',
        'sales',
        'collections',
        'inventory_opening_allocations',
      ]) {
        expect(await app.database.query(table), isEmpty, reason: table);
      }
    },
  );
}
