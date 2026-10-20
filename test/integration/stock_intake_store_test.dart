import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/features/collections/data/sqlite_collections_store.dart';
import 'package:valinor_sanctum_2/features/collections/domain/collections_store.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/stock_intake/data/sqlite_stock_intake_store.dart';
import 'package:valinor_sanctum_2/features/stock_intake/domain/stock_intake_store.dart';
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
    unitPurchasePriceMinor: cost,
    listPriceMinor: pvp,
    quantity: quantity,
    paymentOptionId: 'quick-default:$option',
    occurredAtUtc: occurredAt ?? DateTime.utc(2026, 10, 19, 10),
  );
  Future<int> count(String table) async =>
      (await app.database.query(table)).length;

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
      expect(snapshot.paymentOptions, hasLength(2));
      expect(
        snapshot.paymentOptions.every(
          (p) =>
              p.balanceMinor == 0 && p.canRecordOpening && !p.openingRecorded,
        ),
        isTrue,
      );
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
      await store.prepare(input('first'));
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
      expect(await count('supplier_payment_requests'), 0);
      expect(await count('supplier_payments'), 0);
      expect(await app.database.query('journal_lines'), before);
      expect((await store.load()).pendingIntakes.single.status, 'prepared');
      await app.database.execute('DROP TRIGGER fail_intake_fact');
      await store.confirmPrepared('first');
      expect(await count('purchases'), 1);
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
