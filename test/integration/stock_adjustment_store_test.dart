import 'package:valinor_sanctum_2/features/workspace/data/sqlite_workspace_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/stock_adjustment_store.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_inventory_opening_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_opening.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/reference_inventory.dart';
import 'package:valinor_sanctum_2/features/quick_sales/data/sqlite_quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/reports/data/sqlite_reports_store.dart';
import 'package:valinor_sanctum_2/features/reports/domain/reports_store.dart';
import 'package:valinor_sanctum_2/features/stock_intake/data/sqlite_stock_intake_store.dart';
import 'package:valinor_sanctum_2/features/events/data/sqlite_events_store.dart';
import 'package:valinor_sanctum_2/features/events/domain/events_store.dart';
import 'quick_sales_store_test.dart' show fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase app;
  late SqliteInventoryStore inventory;
  final at = DateTime.utc(2026, 10, 20, 14);
  setUp(() async {
    app = await AppDatabase.open(path: inMemoryDatabasePath);
    await fixture(app);
    inventory = SqliteInventoryStore(app, synthetic: true);
  });
  tearDown(() => app.close());
  StockAdjustmentCommand command(
    String id,
    int quantity, {
    String product = 'product',
    DateTime? time,
  }) => StockAdjustmentCommand(
    commandId: id,
    productId: product,
    quantity: quantity,
    reason: 'Consumo interno',
    occurredAtUtc: time ?? at,
  );
  Future<StockPosition> stock([String id = 'product']) async =>
      (await inventory.load()).stock.singleWhere((s) => s.productId == id);
  Future<Map<String, String>> rows() async => {
    for (final t in await app.database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    ))
      t['name'] as String: jsonEncode(
        await app.database.query(t['name'] as String),
      ),
  };
  Future<void> sell(
    String id,
    String product,
    int qty, {
    DateTime? time,
  }) async {
    final q = SqliteQuickSalesStore(app, synthetic: true);
    await q.ensureDefaults();
    await q.saveAccount(
      SaveQuickSaleAccount(
        id: id,
        label: id,
        expectedRevision: 0,
        lines: [
          QuickSaleLine(
            id: '$id-line',
            productId: product,
            quantityText: '$qty',
            unitPriceMinor: 5000,
            paymentOptionId: 'quick-default:EFECTIVO',
          ),
        ],
      ),
    );
    await q.prepareSale(
      commandId: 'sell-$id',
      accountId: id,
      expectedRevision: 1,
      occurredAtUtc: time ?? at.add(const Duration(hours: 1)),
    );
    await q.confirmPrepared('sell-$id');
  }

  Future<ReportsSnapshot> report() => SqliteReportsStore(app).load(
    ReportPeriod(
      start: DateTime.utc(2026, 10, 20),
      end: DateTime.utc(2026, 10, 20),
    ),
  );
  test(
    'two units remove exact FIFO cost once without cash, sale, debt or revenue',
    () async {
      final beforeSales = await app.database.query('sales'),
          beforeCollections = await app.database.query('collections');
      final c = command('adjust', 2);
      await inventory.prepareAdjustment(c);
      await inventory.prepareAdjustment(c);
      expect(await inventory.pendingAdjustments(), hasLength(1));
      await inventory.confirmAdjustment(c.commandId);
      await inventory.confirmAdjustment(c.commandId);
      expect((await stock()).quantity, 8);
      expect((await stock()).totalCostMinor, 8000);
      expect(await app.database.query('sales'), beforeSales);
      expect(await app.database.query('collections'), beforeCollections);
      expect(await app.database.query('stock_adjustments'), hasLength(1));
      final r = await report();
      expect(r.saleTotals.knownTotalMinor, 0);
      expect(r.outflowTotals.knownTotalMinor, 0);
      expect(r.operatingExpensesMinor, 2001);
      expect((await app.readHealth())['integrityOk'], isTrue);
      expect(await inventory.pendingAdjustments(), isEmpty);
    },
  );
  test(
    'decrement can exhaust all inventory and records immutable noncash expense',
    () async {
      await inventory.prepareAdjustment(command('all', 10));
      await inventory.confirmAdjustment('all');
      expect((await stock()).quantity, 0);
      expect((await stock()).totalCostMinor, 0);
      for (final table in [
        'stock_adjustments',
        'stock_adjustment_allocations',
      ]) {
        expect(app.database.delete(table), throwsA(isA<DatabaseException>()));
        expect(
          app.database.update(table, {'quantity': 1}),
          throwsA(isA<DatabaseException>()),
        );
      }
      expect((await report()).sales, isEmpty);
    },
  );
  test('future sale consumes only remaining layers after adjustment', () async {
    await inventory.prepareAdjustment(command('a', 2));
    await inventory.confirmAdjustment('a');
    await sell('remaining', 'product', 8);
    expect((await stock()).quantity, 0);
    expect((await stock()).totalCostMinor, 0);
    final r = await report();
    expect(r.sales.single.quantity, 8);
    expect(r.sales.single.costMinor, 8000);
    expect(r.items.single.quantity, 8);
  });
  test(
    'events and later adjustments share FIFO with sales and reject overconsumption',
    () async {
      await inventory.prepareAdjustment(command('a', 2));
      await inventory.confirmAdjustment('a');
      final events = SqliteEventsStore(app, synthetic: true);
      final c = CreateEvent(
        commandId: 'event',
        name: 'Premios',
        minimumPeople: 1,
        fixedCostMinor: 0,
        pvpMinor: 100,
        occurredAtUtc: at.add(const Duration(minutes: 1)),
        products: const [EventProductInput('product', 8)],
      );
      await events.prepare(c);
      await events.confirm('event');
      expect((await stock()).quantity, 0);
      expect(
        inventory.prepareAdjustment(
          command('b', 1, time: at.add(const Duration(hours: 2))),
        ),
        throwsA(isA<StockAdjustmentValidationException>()),
      );
    },
  );
  test(
    'opening layers and zero cost adjustment keep exact quantities and allow empty journal',
    () async {
      await app.close();
      app = await AppDatabase.open(path: inMemoryDatabasePath);
      inventory = SqliteInventoryStore(app, synthetic: true);
      await SqliteWorkspaceStore(app).createProfile(
        BusinessProfile(
          profileId: 'opening-test',
          businessName: 'Sintética',
          currencyCode: 'COP',
          moneyScale: 2,
          timezone: 'America/Bogota',
          createdAtUtc: at,
        ),
      );
      final opened = await SqliteInventoryOpeningStore(app, synthetic: true)
          .open(
            InventoryOpeningCommand(
              commandId: 'open-zero',
              reference: ReferenceInventory(
                sourceName: 'synthetic',
                sourceSha256: 'a' * 64,
                capturedAtUtc: at.subtract(const Duration(hours: 1)),
                products: const [
                  ReferenceInventoryProduct(
                    id: 'free',
                    name: 'Producto gratuito',
                    category: 'Artículo',
                    quantity: 4,
                    priceMinor: 100,
                    purchasePriceMinor: 0,
                  ),
                  ReferenceInventoryProduct(
                    id: 'cost',
                    name: 'Producto apertura',
                    category: 'Artículo',
                    quantity: 3,
                    priceMinor: 200,
                    purchasePriceMinor: 101,
                  ),
                ],
              ),
              snapshotSha256: 'b' * 64,
              occurredAtUtc: at.subtract(const Duration(minutes: 30)),
              zeroCostsConfirmed: true,
            ),
          );
      final free = opened.productIdsBySourceId['free']!,
          cost = opened.productIdsBySourceId['cost']!;
      await inventory.prepareAdjustment(command('free', 4, product: free));
      await inventory.confirmAdjustment('free');
      expect((await stock(free)).quantity, 0);
      final doc = (await app.database.query(
        'stock_adjustments',
        where: 'product_id=?',
        whereArgs: [free],
      )).single;
      expect(doc['cost_minor'], 0);
      await inventory.prepareAdjustment(command('cost', 2, product: cost));
      await inventory.confirmAdjustment('cost');
      expect((await stock(cost)).quantity, 1);
      expect((await stock(cost)).totalCostMinor, 101);
    },
  );
  test(
    'prepared stale cost, oversell and nonpositive quantities leave inventory intact',
    () async {
      for (final n in [0, -1, 11]) {
        expect(
          inventory.prepareAdjustment(command('invalid$n', n)),
          throwsA(isA<StockAdjustmentValidationException>()),
        );
      }
      await inventory.prepareAdjustment(command('first', 2));
      await inventory.prepareAdjustment(command('second', 1));
      await inventory.confirmAdjustment('second');
      expect(
        inventory.confirmAdjustment('first'),
        throwsA(isA<StockAdjustmentValidationException>()),
      );
      expect((await stock()).quantity, 9);
      await inventory.discardAdjustment('first');
      expect(await inventory.pendingAdjustments(), isEmpty);
    },
  );
  test(
    'two prepared writeoffs cannot make stock negative and identifiers cannot change payload',
    () async {
      await inventory.prepareAdjustment(command('one', 6));
      await inventory.prepareAdjustment(command('two', 6));
      expect(
        inventory.prepareAdjustment(command('one', 1)),
        throwsA(isA<StockAdjustmentValidationException>()),
      );
      await inventory.confirmAdjustment('one');
      expect(
        inventory.confirmAdjustment('two'),
        throwsA(isA<StockAdjustmentValidationException>()),
      );
      expect((await stock()).quantity, 4);
    },
  );
  test(
    'late failure rolls back journal allocations and command; exact retry succeeds',
    () async {
      await inventory.prepareAdjustment(command('fail', 2));
      final before = await rows();
      await app.database.execute(
        "CREATE TRIGGER force_adjustment_fail BEFORE UPDATE OF status ON journal_entries WHEN NEW.status='posted' AND EXISTS(SELECT 1 FROM stock_adjustments WHERE document_id=NEW.document_id) BEGIN SELECT RAISE(ABORT,'synthetic failure'); END",
      );
      expect(
        inventory.confirmAdjustment('fail'),
        throwsA(isA<DatabaseException>()),
      );
      expect(await rows(), before);
      await app.database.execute('DROP TRIGGER force_adjustment_fail');
      await inventory.confirmAdjustment('fail');
      expect((await stock()).quantity, 8);
    },
  );
  test(
    'operations before a confirmed adjustment are rejected atomically',
    () async {
      await inventory.prepareAdjustment(command('now', 2));
      await inventory.confirmAdjustment('now');
      expect(
        sell(
          'backdated',
          'product',
          1,
          time: at.subtract(const Duration(minutes: 1)),
        ),
        throwsA(anything),
      );
      expect((await stock()).quantity, 8);
      expect(await app.database.query('sales'), isEmpty);
    },
  );
  test(
    'only exact Pasadia becomes unlimited, excluded from purchases, with real quantities in sales reports',
    () async {
      await inventory.saveProduct(
        const CatalogProduct(id: 'pass', name: 'Pasadía', listPriceMinor: 5000),
      );
      await inventory.saveProduct(
        const CatalogProduct(
          id: 'pass2',
          name: 'Pasadía 2',
          listPriceMinor: 6000,
        ),
      );
      final snapshot = await inventory.load();
      expect(
        snapshot.products.singleWhere((p) => p.id == 'pass').isService,
        isTrue,
      );
      expect(
        snapshot.products.singleWhere((p) => p.id == 'pass2').isUnlimited,
        isFalse,
      );
      expect(
        (await SqliteStockIntakeStore(
          app,
          synthetic: true,
        ).load()).products.any((p) => p.id == 'pass'),
        isFalse,
      );
      final original = await rows();
      expect(
        inventory.receivePurchase(
          ReceiptCommand(
            commandId: 'badpass',
            supplierId: 'supplier',
            dueDate: '2026-10-21',
            occurredAtUtc: at,
            lines: const [
              ReceiptLineInput(
                productId: 'pass',
                quantity: 1,
                totalCostMinor: 100,
              ),
            ],
          ),
        ),
        throwsA(anything),
      );
      expect(await rows(), original);
      await sell('pass', 'pass', 1000);
      await sell(
        'pass-again',
        'pass',
        2000,
        time: at.add(const Duration(hours: 2)),
      );
      final r = await report();
      expect(r.items.map((i) => i.quantity).reduce((a, b) => a! + b!), 3000);
      expect(r.sales.every((l) => l.costMinor == 0), isTrue);
      expect(await app.database.query('sale_outflows'), isEmpty);
      expect(r.saleTotals.knownCashMinor, 15000000);
      expect(
        inventory.prepareAdjustment(command('service', 1, product: 'pass')),
        throwsA(isA<StockAdjustmentValidationException>()),
      );
    },
  );
}
