import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/features/collections/data/sqlite_collections_store.dart';
import 'package:valinor_sanctum_2/features/collections/domain/collections_store.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_inventory_opening_store.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_opening.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/reference_inventory.dart';
import 'package:valinor_sanctum_2/features/stock_intake/data/sqlite_stock_intake_store.dart';
import 'package:valinor_sanctum_2/features/stock_intake/domain/stock_intake_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/data/sqlite_quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/reports/data/sqlite_reports_store.dart';
import 'package:valinor_sanctum_2/features/reports/domain/reports_store.dart';
import 'package:valinor_sanctum_2/features/supplier_payments/data/sqlite_supplier_payments_store.dart';
import 'package:valinor_sanctum_2/features/supplier_payments/domain/supplier_payments_store.dart';
import 'package:valinor_sanctum_2/features/workspace/data/sqlite_workspace_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase app;
  late SqliteStockIntakeStore store;
  late String category;
  setUp(() async {
    app = await AppDatabase.open(path: inMemoryDatabasePath);
    store = SqliteStockIntakeStore(app, synthetic: true);
    await profile(app);
    await store.ensureDefaults();
    category = (await store.load()).categories
        .singleWhere((c) => c.name == 'Comestible')
        .id;
  });
  tearDown(() => app.close());

  Future<void> opening({String option = 'EFECTIVO', int amount = 100000}) =>
      store.recordOpeningBalance(
        CashOpeningCommand(
          commandId: 'opening-$option',
          paymentOptionId: 'quick-default:$option',
          amountMinor: amount,
          occurredAtUtc: DateTime.utc(2026, 10, 19, 8),
        ),
      );
  StockIntakeCommand input(
    String id, {
    String productId = 'product',
    CatalogProduct? expected,
    String name = 'Producto sintético',
    String? sku,
    String? supplierId,
    String supplier = 'Proveedor sintético',
    int quantity = 5,
    int cost = 1000,
    int? totalCost,
    int pvp = 1500,
    String option = 'EFECTIVO',
    DateTime? occurredAt,
  }) => StockIntakeCommand(
    commandId: id,
    productId: productId,
    expectedProduct: expected,
    productName: name,
    sku: sku,
    categoryId: category,
    supplierId: supplierId,
    supplierName: supplier,
    unitPurchasePriceMinor: totalCost == null ? cost : null,
    totalPurchasePriceMinor: totalCost,
    listPriceMinor: pvp,
    quantity: quantity,
    paymentOptionId: 'quick-default:$option',
    occurredAtUtc: occurredAt ?? DateTime.utc(2026, 10, 19, 10),
  );
  Future<int> count(String table) async =>
      (await app.database.query(table)).length;

  test(
    'owner-paid intake adds inventory and owner debt with no cash movement and no duplicate supplier debt',
    () async {
      final command = StockIntakeCommand(
        commandId: 'owner-intake',
        productId: 'owner-product',
        productName: 'Producto con inversión',
        categoryId: category,
        supplierName: 'Proveedor sintético',
        totalPurchasePriceMinor: 25001,
        listPriceMinor: 4000,
        quantity: 10,
        paymentOptionId: 'investment',
        occurredAtUtc: DateTime.utc(2026, 10, 29, 20),
      );
      await store.prepare(command);
      final result = await store.confirmPrepared(command.commandId);
      expect(
        (await store.confirmPrepared(command.commandId)).paymentDocumentId,
        result.paymentDocumentId,
      );
      final data = await store.load();
      expect(data.stock.single.quantity, 10);
      expect(data.stock.single.totalCostMinor, 25001);
      expect(data.entries.single.paymentLabel, 'Inversión');
      expect(
        data.paymentOptions.singleWhere((o) => o.isInvestment).balanceMinor,
        25001,
      );
      expect(
        data.paymentOptions
            .where((o) => !o.isInvestment)
            .every((o) => o.balanceMinor == 0),
        isTrue,
      );
      expect(
        (await SqliteSupplierPaymentsStore(
          app,
        ).load()).payables.single.remainingMinor,
        0,
      );
      expect(await count('supplier_payments'), 0);
      expect(await count('investment_operations'), 1);
      expect(await app.database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );

  test(
    'total cost remains exact while the new PVP applies to all old and new stock with immutable price history',
    () async {
      await opening();
      await store.prepare(input('old'));
      await store.confirmPrepared('old');
      final old = (await store.load()).products.single;
      await store.prepare(
        input(
          'total',
          expected: old,
          totalCost: 25001,
          quantity: 10,
          pvp: 3500,
          occurredAt: DateTime.utc(2026, 10, 19, 11),
        ),
      );
      await store.confirmPrepared('total');
      await store.confirmPrepared('total');
      final current = await store.load();
      expect(current.products.single.listPriceMinor, 3500);
      expect(current.stock.single.quantity, 15);
      expect(current.stock.single.totalCostMinor, 30001);
      expect(
        current.paymentOptions
            .singleWhere((o) => o.label == 'Efectivo')
            .balanceMinor,
        69999,
      );
      final entry = current.entries.singleWhere((e) => e.commandId == 'total');
      expect(entry.totalCostMinor, 25001);
      expect(entry.unitPurchasePriceMinor, isNull);
      final history = await app.database.query(
        'product_price_history',
        orderBy: 'id',
      );
      expect(history.map((h) => h['price_minor']), [1500, 3500]);
      expect(history.last['previous_price_minor'], 1500);
      expect(history.last['request_id'], 'total');
      expect(
        history.last['operation_at_utc'],
        DateTime.utc(2026, 10, 19, 11).toIso8601String(),
      );
      await expectLater(
        app.database.update('product_price_history', {'price_minor': 1}),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        app.database.delete('product_price_history'),
        throwsA(isA<DatabaseException>()),
      );
    },
  );

  test(
    'a fractional minor-unit average conserves the whole purchase cost through FIFO sale',
    () async {
      await opening(amount: 100);
      await store.prepare(input('fraction', totalCost: 1, quantity: 3, pvp: 1));
      await store.confirmPrepared('fraction');
      final quick = SqliteQuickSalesStore(app, synthetic: true);
      await quick.saveAccount(
        SaveQuickSaleAccount(
          id: 'sell',
          label: 'Cuenta',
          expectedRevision: 0,
          lines: const [
            QuickSaleLine(
              id: 'line',
              productId: 'product',
              quantityText: '3',
              unitPriceMinor: 1,
              paymentOptionId: 'quick-default:EFECTIVO',
            ),
          ],
        ),
      );
      await quick.prepareSale(
        commandId: 'sale',
        accountId: 'sell',
        expectedRevision: 1,
        occurredAtUtc: DateTime.utc(2026, 10, 19, 12),
      );
      await quick.confirmPrepared('sale');
      expect(
        (await app.database.query('sale_lines')).single['total_cost_minor'],
        1,
      );
      expect((await store.load()).stock.single.quantity, 0);
      expect((await store.load()).entries.single.totalCostMinor, 1);
    },
  );

  test(
    'total purchase from Nequi permits PVP zero and is reported as the exact outflow',
    () async {
      await opening(option: 'NEQUI', amount: 50000);
      await store.prepare(
        input('bank', option: 'NEQUI', totalCost: 25000, quantity: 10, pvp: 0),
      );
      await store.confirmPrepared('bank');
      final state = await store.load();
      expect(
        state.paymentOptions
            .singleWhere((o) => o.label == 'Nequi')
            .balanceMinor,
        25000,
      );
      expect(state.products.single.listPriceMinor, 0);
      final report = await SqliteReportsStore(app).load(
        ReportPeriod(
          start: DateTime.utc(2026, 10, 19),
          end: DateTime.utc(2026, 10, 19),
        ),
      );
      expect(report.outflowTotals.cashMinor, 0);
      expect(report.outflowTotals.transferMinor, 25000);
      expect(report.saleTotals.totalMinor, 0);
    },
  );

  Future<InventoryOpeningResult> initialInventory() =>
      SqliteInventoryOpeningStore(app, synthetic: true).open(
        InventoryOpeningCommand(
          commandId: 'initial-inventory',
          reference: ReferenceInventory(
            sourceName: 'synthetic.db',
            sourceSha256: List.filled(64, 'a').join(),
            capturedAtUtc: DateTime.utc(2026, 10, 19, 7),
            products: const [
              ReferenceInventoryProduct(
                id: 'opening-regular',
                name: 'Producto inicial',
                quantity: 2,
                priceMinor: 1000,
                purchasePriceMinor: 400,
                category: 'Comestible',
                supplier: 'Proveedor inicial',
              ),
              ReferenceInventoryProduct(
                id: 'opening-zero',
                name: 'Agotado de costo cero',
                quantity: 0,
                priceMinor: 1000,
                purchasePriceMinor: 0,
                category: 'Comestible',
                supplier: 'Proveedor cero',
              ),
              ReferenceInventoryProduct(
                id: 'opening-no-supplier',
                name: 'Agotado sin proveedor',
                quantity: 0,
                priceMinor: 1000,
                purchasePriceMinor: 700,
                category: 'Comestible',
              ),
            ],
          ),
          snapshotSha256: List.filled(64, 'b').join(),
          occurredAtUtc: DateTime.utc(2026, 10, 19, 8),
          zeroCostsConfirmed: true,
        ),
      );

  test(
    'intake defaults include opening zero cost and exhausted products',
    () async {
      final imported = await initialInventory();
      final snapshot = await store.load();
      final regular = snapshot
          .productDefaults[imported.productIdsBySourceId['opening-regular']!]!;
      expect(regular.unitPurchasePriceMinor, 400);
      expect(regular.supplierName, 'Proveedor inicial');
      expect(regular.supplierId, isNotNull);
      final zero = snapshot
          .productDefaults[imported.productIdsBySourceId['opening-zero']!]!;
      expect(zero.unitPurchasePriceMinor, 0);
      expect(zero.supplierName, 'Proveedor cero');
      final noSupplier =
          snapshot.productDefaults[imported
              .productIdsBySourceId['opening-no-supplier']!]!;
      expect(noSupplier.unitPurchasePriceMinor, 700);
      expect(noSupplier.supplierId, isNull);
      expect(noSupplier.supplierName, isNull);
      expect(snapshot.productDefaults, hasLength(3));
      expect(snapshot.entries, isEmpty);
      expect(() => snapshot.productDefaults.clear(), throwsUnsupportedError);
    },
  );

  test(
    'latest posted legacy receipt replaces opening defaults as a pair',
    () async {
      final imported = await initialInventory();
      final productId = imported.productIdsBySourceId['opening-regular']!;
      final inventory = SqliteInventoryStore(app, synthetic: true);
      await inventory.saveSupplier(
        const InventorySupplier(id: 'latest-supplier', name: 'Proveedor nuevo'),
      );
      await inventory.receivePurchase(
        ReceiptCommand(
          commandId: 'later-receipt',
          supplierId: 'latest-supplier',
          dueDate: '2026-10-19',
          occurredAtUtc: DateTime.utc(2026, 10, 19, 10),
          lines: [
            ReceiptLineInput(
              productId: productId,
              quantity: 2,
              totalCostMinor: 900,
            ),
          ],
        ),
      );
      await inventory.saveSupplier(
        const InventorySupplier(
          id: 'latest-supplier',
          name: 'Proveedor renombrado',
        ),
      );
      final snapshot = await store.load();
      final defaults = snapshot.productDefaults[productId]!;
      expect(defaults.supplierId, 'latest-supplier');
      expect(defaults.supplierName, 'Proveedor renombrado');
      expect(defaults.unitPurchasePriceMinor, 450);
      expect(snapshot.entries, isEmpty);
    },
  );

  test(
    'nonintegral latest unit cost stays unknown with its own supplier',
    () async {
      final inventory = SqliteInventoryStore(app, synthetic: true);
      await inventory.saveProduct(
        CatalogProduct(
          id: 'legacy-product',
          name: 'Producto',
          categoryId: category,
          listPriceMinor: 2000,
        ),
      );
      for (final supplier in ['old-supplier', 'new-supplier']) {
        await inventory.saveSupplier(
          InventorySupplier(id: supplier, name: supplier),
        );
      }
      await inventory.receivePurchase(
        ReceiptCommand(
          commandId: 'exact-cost',
          supplierId: 'old-supplier',
          dueDate: '2026-10-19',
          occurredAtUtc: DateTime.utc(2026, 10, 19, 10),
          lines: const [
            ReceiptLineInput(
              productId: 'legacy-product',
              quantity: 2,
              totalCostMinor: 1000,
            ),
          ],
        ),
      );
      expect(
        (await store.load())
            .productDefaults['legacy-product']!
            .unitPurchasePriceMinor,
        500,
      );
      await inventory.receivePurchase(
        ReceiptCommand(
          commandId: 'nonintegral-cost',
          supplierId: 'new-supplier',
          dueDate: '2026-10-19',
          occurredAtUtc: DateTime.utc(2026, 10, 19, 11),
          lines: const [
            ReceiptLineInput(
              productId: 'legacy-product',
              quantity: 3,
              totalCostMinor: 1000,
            ),
          ],
        ),
      );
      final defaults = (await store.load()).productDefaults['legacy-product']!;
      expect(defaults.supplierId, 'new-supplier');
      expect(defaults.supplierName, 'new-supplier');
      expect(defaults.unitPurchasePriceMinor, isNull);
    },
  );

  test(
    'inactive latest supplier is not selected or replaced by an older one',
    () async {
      await opening();
      await store.prepare(
        input('old-intake', supplier: 'Proveedor anterior', cost: 900),
      );
      await store.confirmPrepared('old-intake');
      final old = (await store.load()).products.single;
      await store.prepare(
        input(
          'new-intake',
          expected: old,
          supplier: 'Proveedor reciente',
          cost: 1200,
          occurredAt: DateTime.utc(2026, 10, 19, 11),
        ),
      );
      await store.confirmPrepared('new-intake');
      final snapshot = await store.load();
      final recent = snapshot.suppliers.singleWhere(
        (s) => s.name == 'Proveedor reciente',
      );
      await SqliteInventoryStore(app).saveSupplier(
        InventorySupplier(id: recent.id, name: recent.name, isActive: false),
      );
      final defaults = (await store.load()).productDefaults['product']!;
      expect(defaults.supplierId, isNull);
      expect(defaults.supplierName, isNull);
      expect(defaults.unitPurchasePriceMinor, 1200);
    },
  );

  test(
    'defaults are idempotent and reuse active category without inventing money',
    () async {
      await store.ensureDefaults();
      final snapshot = await store.load();
      expect(snapshot.categories.map((c) => c.name).toSet(), {
        'Comestible',
        'Artículo',
        'Evento',
      });
      expect(snapshot.categories, hasLength(3));
      expect(snapshot.paymentOptions, hasLength(3));
      expect(
        snapshot.paymentOptions
            .where((p) => !p.isInvestment)
            .every(
              (p) =>
                  p.balanceMinor == 0 &&
                  p.canRecordOpening &&
                  !p.openingRecorded,
            ),
        isTrue,
      );
      final investment = snapshot.paymentOptions.singleWhere(
        (p) => p.isInvestment,
      );
      expect(investment.balanceMinor, 0);
      expect(investment.canRecordOpening, isFalse);
      expect(investment.openingRecorded, isTrue);
      expect(await count('command_log'), 0);
      expect(await count('journal_entries'), 0);
      final other = await AppDatabase.open(path: inMemoryDatabasePath);
      try {
        await profile(other);
        await SqliteInventoryStore(other).saveCategory(
          const InventoryCategory(id: 'existing', name: 'Comestible'),
        );
        final s = SqliteStockIntakeStore(other);
        await s.ensureDefaults();
        expect(
          (await s.load()).categories
              .singleWhere((c) => c.name == 'Comestible')
              .id,
          'existing',
        );
        expect(await other.database.query('categories'), hasLength(3));
      } finally {
        await other.close();
      }
    },
  );

  test(
    'one intake creates catalog supplier FIFO stock and fully paid purchase',
    () async {
      await opening();
      await store.prepare(input('first', sku: 'SKU-1'));
      final result = await store.confirmPrepared('first');
      expect(result.totalCostMinor, 5000);
      final snapshot = await store.load();
      expect(snapshot.pendingIntakes, isEmpty);
      expect(snapshot.products.single.name, 'Producto sintético');
      expect(snapshot.products.single.sku, 'SKU-1');
      expect(snapshot.products.single.listPriceMinor, 1500);
      expect(snapshot.stock.single.quantity, 5);
      expect(snapshot.stock.single.totalCostMinor, 5000);
      expect(snapshot.entries.single.quantity, 5);
      expect(snapshot.entries.single.unitPurchasePriceMinor, 1000);
      expect(snapshot.entries.single.paymentLabel, 'Efectivo');
      expect(
        snapshot.paymentOptions
            .singleWhere((p) => p.label == 'Efectivo')
            .balanceMinor,
        95000,
      );
      expect(
        snapshot.paymentOptions
            .singleWhere((p) => p.label == 'Efectivo')
            .canRecordOpening,
        isFalse,
      );
      final payable = (await SqliteSupplierPaymentsStore(
        app,
      ).load()).payables.single;
      expect(payable.initialMinor, 5000);
      expect(payable.paidMinor, 5000);
      expect(payable.remainingMinor, 0);
      expect(await count('purchases'), 1);
      expect(await count('supplier_payments'), 1);
      expect(await count('cost_layers'), 1);
      expect(await count('paid_purchase_entries'), 1);
    },
  );

  test(
    'preparation has no catalog inventory money or supplier effects and stable replay',
    () async {
      await opening();
      final facts = await app.database.query('journal_lines');
      final first = await store.prepare(input('first'));
      final replay = await store.prepare(input('first'));
      expect(replay.preparedAtUtc, first.preparedAtUtc);
      expect(await count('catalog_items'), 0);
      expect(await count('counterparties'), 0);
      expect(await count('purchases'), 0);
      expect(await app.database.query('journal_lines'), facts);
      await expectLater(
        store.prepare(input('first', quantity: 6)),
        throwsA(isA<StockIntakeValidationException>()),
      );
      final result = await store.confirmPrepared('first');
      final after = await app.database.query('journal_lines');
      final resultAgain = await store.confirmPrepared('first');
      expect(resultAgain.purchaseDocumentId, result.purchaseDocumentId);
      expect(resultAgain.paymentDocumentId, result.paymentDocumentId);
      expect(await app.database.query('journal_lines'), after);
      expect(await count('purchases'), 1);
      expect(await count('supplier_payments'), 1);
    },
  );

  test(
    'replenishment updates current catalog while preserving historical cost and snapshots',
    () async {
      await opening();
      await store.prepare(input('first', sku: 'SKU-1'));
      await store.confirmPrepared('first');
      final old = (await store.load()).products.single;
      await store.prepare(
        input(
          'second',
          expected: old,
          name: 'Nombre actualizado',
          sku: 'SKU-2',
          quantity: 2,
          cost: 1200,
          pvp: 1800,
          occurredAt: DateTime.utc(2026, 10, 19, 11),
        ),
      );
      await store.confirmPrepared('second');
      final snapshot = await store.load();
      expect(snapshot.products.single.name, 'Nombre actualizado');
      expect(snapshot.products.single.listPriceMinor, 1800);
      expect(snapshot.stock.single.quantity, 7);
      expect(snapshot.stock.single.totalCostMinor, 7400);
      expect(snapshot.suppliers, hasLength(1));
      final first = snapshot.entries.singleWhere((e) => e.commandId == 'first');
      expect(first.productName, 'Producto sintético');
      expect(first.sku, 'SKU-1');
      expect(first.unitPurchasePriceMinor, 1000);
      expect(first.listPriceMinor, 1500);
      expect(
        (await SqliteSupplierPaymentsStore(
          app,
        ).load()).payables.every((p) => p.remainingMinor == 0),
        isTrue,
      );
    },
  );

  test(
    'failure after both child documents rolls back catalog supplier inventory money and retry recovers',
    () async {
      await opening();
      await store.prepare(input('first', totalCost: 501));
      final before = await app.database.query('journal_lines');
      await app.database.execute(
        "CREATE TEMP TRIGGER fail_intake_fact BEFORE INSERT ON paid_purchase_entries BEGIN SELECT RAISE(ABORT,'Synthetic storage failure'); END",
      );
      await expectLater(
        store.confirmPrepared('first'),
        throwsA(isA<DatabaseException>()),
      );
      expect(await count('catalog_items'), 0);
      expect(await count('counterparties'), 0);
      expect(await count('purchases'), 0);
      expect(await count('product_price_history'), 0);
      expect(await count('supplier_payment_requests'), 0);
      expect(await count('supplier_payments'), 0);
      expect(await app.database.query('journal_lines'), before);
      expect((await store.load()).pendingIntakes.single.status, 'prepared');
      await app.database.execute('DROP TRIGGER fail_intake_fact');
      await store.confirmPrepared('first');
      expect(await count('purchases'), 1);
      expect(await count('product_price_history'), 1);
      expect(await count('supplier_payments'), 1);
    },
  );

  test(
    'insufficient funds reject before preparation without inventing an opening',
    () async {
      await expectLater(
        store.prepare(input('first')),
        throwsA(isA<StockIntakeValidationException>()),
      );
      expect(await count('paid_purchase_requests'), 0);
      expect(await count('catalog_items'), 0);
      expect(await count('cash_openings'), 0);
    },
  );

  test(
    'competing requests cannot spend the same funds and known rejection is discardable',
    () async {
      await opening(amount: 6000);
      await store.prepare(input('first'));
      await store.prepare(
        input('second', productId: 'product-2', supplier: 'Otro proveedor'),
      );
      await store.confirmPrepared('first');
      await expectLater(
        store.confirmPrepared('second'),
        throwsA(isA<StockIntakeValidationException>()),
      );
      expect((await store.load()).pendingIntakes.single.status, 'rejected');
      expect(await count('catalog_items'), 1);
      expect(await count('counterparties'), 1);
      expect(await count('purchases'), 1);
      expect(
        (await store.load()).paymentOptions
            .singleWhere((p) => p.label == 'Efectivo')
            .balanceMinor,
        1000,
      );
      await store.discardRejected('second');
      await store.discardRejected('second');
      expect((await store.load()).pendingIntakes, isEmpty);
      await expectLater(
        store.discardRejected('first'),
        throwsA(isA<StockIntakeValidationException>()),
      );
    },
  );

  test(
    'full catalog CAS prevents stale overwrite during prepare and after preparation',
    () async {
      await opening();
      final inventory = SqliteInventoryStore(app);
      const old = CatalogProduct(
        id: 'product',
        name: 'Original',
        listPriceMinor: 1000,
      );
      await inventory.saveProduct(old);
      await store.prepare(input('first', expected: old));
      await inventory.saveProduct(
        const CatalogProduct(
          id: 'product',
          name: 'Concurrente',
          listPriceMinor: 1300,
        ),
      );
      await expectLater(
        store.confirmPrepared('first'),
        throwsA(isA<StockIntakeValidationException>()),
      );
      await expectLater(
        store.prepare(input('stale', expected: old)),
        throwsA(isA<StockIntakeValidationException>()),
      );
      expect((await store.load()).products.single.name, 'Concurrente');
      expect(await count('purchases'), 0);
      expect(await count('counterparties'), 0);
      expect(
        (await store.load()).paymentOptions
            .singleWhere((p) => p.label == 'Efectivo')
            .balanceMinor,
        100000,
      );
    },
  );

  test(
    'a new product ID appearing after preparation cannot be overwritten',
    () async {
      await opening();
      await store.prepare(input('first'));
      await SqliteInventoryStore(app).saveProduct(
        const CatalogProduct(
          id: 'product',
          name: 'Concurrente',
          listPriceMinor: 1300,
        ),
      );
      await expectLater(
        store.confirmPrepared('first'),
        throwsA(isA<StockIntakeValidationException>()),
      );
      expect((await store.load()).products.single.name, 'Concurrente');
      expect(await count('purchases'), 0);
    },
  );

  test(
    'existing supplier is reused case insensitively and rename rejects a prepared intake',
    () async {
      await opening();
      final inventory = SqliteInventoryStore(app);
      await inventory.saveSupplier(
        const InventorySupplier(id: 'supplier', name: 'Proveedor Sintético'),
      );
      await store.prepare(input('first', supplier: 'proveedor sintético'));
      await inventory.saveSupplier(
        const InventorySupplier(id: 'supplier', name: 'Proveedor nuevo'),
      );
      await expectLater(
        store.confirmPrepared('first'),
        throwsA(isA<StockIntakeValidationException>()),
      );
      expect(await count('counterparties'), 1);
      expect(await count('catalog_items'), 0);
      expect(await count('purchases'), 0);
    },
  );

  test(
    'money snapshots survive harmless renaming without changing the captured identity',
    () async {
      await opening();
      await store.prepare(input('first'));
      final catalogs = SqliteCollectionsStore(app);
      final money = await catalogs.load();
      final account = money.accounts.singleWhere((a) => a.kind == 'cash');
      final method = money.methods.singleWhere((m) => m.code == 'EFECTIVO');
      await catalogs.saveAccount(
        CollectionAccount(
          id: account.id,
          name: 'Caja renombrada',
          kind: account.kind,
        ),
      );
      await catalogs.saveMethod(
        CollectionMethod(
          id: method.id,
          code: method.code,
          name: 'Medio renombrado',
        ),
      );
      await store.confirmPrepared('first');
      final entry = (await app.database.query('paid_purchase_entries')).single;
      expect(entry['cash_account_name_snapshot'], 'Caja');
      expect(entry['payment_method_name_snapshot'], 'Efectivo');
      final payment = (await SqliteSupplierPaymentsStore(
        app,
      ).load()).payments.single;
      expect(payment.parts.single.cashAccountName, 'Caja');
      expect(payment.parts.single.paymentMethodName, 'Efectivo');
    },
  );

  test(
    'disabled payment method rejects without creating catalog or money effects',
    () async {
      await opening();
      await store.prepare(input('first'));
      final catalogs = SqliteCollectionsStore(app);
      final method = (await catalogs.load()).methods.singleWhere(
        (m) => m.code == 'EFECTIVO',
      );
      await catalogs.saveMethod(
        CollectionMethod(
          id: method.id,
          code: method.code,
          name: method.name,
          isActive: false,
        ),
      );
      await expectLater(
        store.confirmPrepared('first'),
        throwsA(isA<StockIntakeValidationException>()),
      );
      expect(await count('catalog_items'), 0);
      expect(await count('purchases'), 0);
      expect(await count('supplier_payments'), 0);
    },
  );

  test(
    'unit prices quantities and both multiplied totals are validated exactly',
    () async {
      await opening();
      for (final command in [
        input('zero-cost', cost: 0),
        input('negative-cost', cost: -1),
        input('zero-quantity', quantity: 0),
        input('negative-pvp', pvp: -1),
        input('overflow-cost', cost: 9223372036854775807, quantity: 2),
        input('overflow-pvp', pvp: 9223372036854775807, quantity: 2),
        input('invalid-time', occurredAt: DateTime(2026, 10, 19, 10)),
      ]) {
        await expectLater(
          store.prepare(command),
          throwsA(isA<StockIntakeValidationException>()),
        );
      }
      expect(await count('paid_purchase_requests'), 0);
      expect(await count('catalog_items'), 0);
      await store.prepare(input('free-public', pvp: 0));
      await store.confirmPrepared('free-public');
      expect((await store.load()).products.single.listPriceMinor, 0);
    },
  );

  test(
    'SKU is optional and duplicate SKU cannot silently identify another product',
    () async {
      await opening();
      await store.prepare(input('first', sku: ' SKU-1 '));
      await store.confirmPrepared('first');
      await expectLater(
        store.prepare(input('duplicate', productId: 'different', sku: 'sku-1')),
        throwsA(isA<StockIntakeValidationException>()),
      );
      await store.prepare(
        input(
          'optional',
          productId: 'without-sku',
          sku: '  ',
          occurredAt: DateTime.utc(2026, 10, 19, 11),
        ),
      );
      await store.confirmPrepared('optional');
      expect(
        (await store.load()).products
            .singleWhere((p) => p.id == 'without-sku')
            .sku,
        isNull,
      );
    },
  );

  test(
    'public legacy receipt and payment APIs cannot use any reserved parent or child',
    () async {
      await opening();
      await store.prepare(input('first'));
      final request = (await app.database.query(
        'paid_purchase_requests',
      )).single;
      final inventory = SqliteInventoryStore(app);
      final payments = SqliteSupplierPaymentsStore(app);
      for (final id in [
        'first',
        request['purchase_command_id'] as String,
        request['payment_command_id'] as String,
      ]) {
        await expectLater(
          inventory.receivePurchase(
            ReceiptCommand(
              commandId: id,
              supplierId: 'none',
              dueDate: '2026-10-19',
              occurredAtUtc: DateTime.utc(2026, 10, 19, 10),
              lines: const [
                ReceiptLineInput(
                  productId: 'product',
                  quantity: 1,
                  totalCostMinor: 1,
                ),
              ],
            ),
          ),
          throwsA(isA<InventoryValidationException>()),
        );
        await expectLater(
          payments.preparePayment(
            SupplierPaymentCommand(
              commandId: id,
              payableId: 'none',
              occurredAtUtc: DateTime.utc(2026, 10, 19, 10),
              parts: const [
                SupplierPaymentPartInput(
                  cashAccountId: 'none',
                  paymentMethodId: 'none',
                  amountMinor: 1,
                ),
              ],
            ),
          ),
          throwsA(isA<SupplierPaymentsValidationException>()),
        );
        await expectLater(
          payments.confirmPrepared(id),
          throwsA(isA<SupplierPaymentsValidationException>()),
        );
        if (id != 'first') {
          await expectLater(
            store.prepare(input(id, productId: 'other')),
            throwsA(isA<StockIntakeValidationException>()),
          );
        }
      }
      final result = await store.confirmPrepared('first');
      await expectLater(
        payments.confirmPrepared(request['payment_command_id'] as String),
        throwsA(isA<SupplierPaymentsValidationException>()),
      );
      expect(
        (await store.confirmPrepared('first')).purchaseDocumentId,
        result.purchaseDocumentId,
      );
    },
  );

  test(
    'prepared operation and its original result survive file reopen',
    () async {
      final root = Directory(
        p.join(
          Directory.current.path,
          'tmp',
          'tests',
          'intake-${InventoryIds.next()}',
        ),
      )..createSync(recursive: true);
      final path = p.join(root.path, 'intake.sqlite3');
      var disk = await AppDatabase.open(path: path);
      try {
        await profile(disk);
        var s = SqliteStockIntakeStore(disk, synthetic: true);
        await s.ensureDefaults();
        final categoryId = (await s.load()).categories
            .singleWhere((c) => c.name == 'Evento')
            .id;
        await s.recordOpeningBalance(
          CashOpeningCommand(
            commandId: 'opening',
            paymentOptionId: 'quick-default:NEQUI',
            amountMinor: 10000,
            occurredAtUtc: DateTime.utc(2026, 10, 19, 8),
          ),
        );
        await s.prepare(
          StockIntakeCommand(
            commandId: 'restart',
            productId: 'event',
            productName: 'Evento sintético',
            categoryId: categoryId,
            supplierName: 'Proveedor',
            unitPurchasePriceMinor: 1000,
            listPriceMinor: 2000,
            quantity: 2,
            paymentOptionId: 'quick-default:NEQUI',
            occurredAtUtc: DateTime.utc(2026, 10, 19, 10),
          ),
        );
        await disk.close();
        disk = await AppDatabase.open(path: path);
        s = SqliteStockIntakeStore(disk, synthetic: true);
        expect(
          (await s.load()).pendingIntakes.single.command.commandId,
          'restart',
        );
        final first = await s.confirmPrepared('restart');
        await disk.close();
        disk = await AppDatabase.open(path: path);
        s = SqliteStockIntakeStore(disk, synthetic: true);
        final replay = await s.confirmPrepared('restart');
        expect(replay.purchaseDocumentId, first.purchaseDocumentId);
        expect(replay.paymentDocumentId, first.paymentDocumentId);
        final current = await s.load();
        expect(current.entries.single.categoryName, 'Evento');
        expect(current.stock.single.quantity, 2);
        expect(
          current.paymentOptions
              .singleWhere((p) => p.label == 'Nequi')
              .balanceMinor,
          8000,
        );
        expect(
          (await SqliteSupplierPaymentsStore(
            disk,
          ).load()).payables.single.remainingMinor,
          0,
        );
        expect(await disk.database.query('purchases'), hasLength(1));
      } finally {
        await disk.close();
      }
    },
  );
}

Future<void> profile(AppDatabase app) =>
    SqliteWorkspaceStore(app).createProfile(
      BusinessProfile(
        profileId: 'intake-test',
        businessName: 'Ludoteca sintética',
        currencyCode: 'COP',
        moneyScale: 2,
        timezone: 'America/Bogota',
        createdAtUtc: DateTime.utc(2026, 10, 19),
      ),
    );
