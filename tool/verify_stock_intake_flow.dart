import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/core/infrastructure/storage_paths.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/data/sqlite_quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/stock_intake/data/sqlite_stock_intake_store.dart';
import 'package:valinor_sanctum_2/features/stock_intake/domain/stock_intake_store.dart';
import 'package:valinor_sanctum_2/features/supplier_payments/data/sqlite_supplier_payments_store.dart';
import 'package:valinor_sanctum_2/features/workspace/data/sqlite_workspace_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';

/// Always creates a new synthetic profile inside this repository. No existing
/// database or caller-supplied path is accepted.
Future<void> main(List<String> args) async {
  if (args.isNotEmpty) {
    stderr.writeln('This verifier takes no file arguments.');
    exitCode = 64;
    return;
  }
  AppDatabase? app;
  try {
    final root = p.join(
      AppConfig.repositoryRootPath,
      'tmp',
      'stock-intake-${InventoryIds.next()}',
    );
    final paths = await StoragePaths.resolve(
      AppConfig(
        environment: AppEnvironment.test,
        dataRoot: root,
        profileId: 'stock-intake-smoke',
      ),
    );
    if (await File(paths.databasePath).exists()) {
      throw StateError('Synthetic path already exists.');
    }
    app = await AppDatabase.open(path: paths.databasePath);
    await SqliteWorkspaceStore(app).createProfile(
      BusinessProfile(
        profileId: 'stock-intake-smoke',
        businessName: 'Ingresos sintéticos 0.7.0',
        currencyCode: 'COP',
        moneyScale: 2,
        timezone: 'America/Bogota',
        createdAtUtc: DateTime.utc(2026, 10, 19),
      ),
    );
    var store = SqliteStockIntakeStore(app, synthetic: true);
    final checks = <String, bool>{};
    void check(String label, bool value) {
      checks[label] = value;
      if (!value) throw StateError('Check failed: $label');
    }

    await store.ensureDefaults();
    await store.ensureDefaults();
    var snapshot = await store.load();
    check(
      'threeCategoriesConfiguredOnce',
      snapshot.categories.length == 3 &&
          snapshot.categories.map((c) => c.name).toSet().containsAll([
            'Comestible',
            'Artículo',
            'Evento',
          ]),
    );
    check(
      'cashAndNequiWithoutInventedMoney',
      snapshot.paymentOptions.length == 2 &&
          snapshot.paymentOptions.every(
            (o) => o.balanceMinor == 0 && o.canRecordOpening,
          ),
    );
    final category = snapshot.categories
        .singleWhere((c) => c.name == 'Comestible')
        .id;
    StockIntakeCommand input(
      String id, {
      CatalogProduct? existing,
      int qty = 5,
      int cost = 1001,
      int pvp = 3000,
      String option = 'EFECTIVO',
      int hour = 14,
    }) => StockIntakeCommand(
      commandId: id,
      productId: existing?.id ?? 'product-synthetic',
      expectedProduct: existing,
      productName: 'Producto sintético',
      sku: 'STOCK-SYNTHETIC',
      categoryId: category,
      supplierName: 'Proveedor sintético',
      unitPurchasePriceMinor: cost,
      listPriceMinor: pvp,
      quantity: qty,
      paymentOptionId: 'quick-default:$option',
      occurredAtUtc: DateTime.utc(2026, 10, 19, hour),
    );
    var insufficient = false;
    try {
      await store.prepare(input('insufficient'));
    } on StockIntakeValidationException {
      insufficient = true;
    }
    snapshot = await store.load();
    check(
      'insufficientMoneyRejectsBeforeCreatingProduct',
      insufficient &&
          snapshot.products.isEmpty &&
          snapshot.entries.isEmpty &&
          snapshot.suppliers.isEmpty,
    );
    final cashOpening = CashOpeningCommand(
      commandId: 'cash-opening',
      paymentOptionId: 'quick-default:EFECTIVO',
      amountMinor: 100000,
      occurredAtUtc: DateTime.utc(2026, 10, 19, 12),
    );
    await store.recordOpeningBalance(cashOpening);
    await store.recordOpeningBalance(cashOpening);
    await store.recordOpeningBalance(
      CashOpeningCommand(
        commandId: 'mobile-opening',
        paymentOptionId: 'quick-default:NEQUI',
        amountMinor: 50000,
        occurredAtUtc: DateTime.utc(2026, 10, 19, 12),
      ),
    );
    snapshot = await store.load();
    check(
      'declaredOpeningsUseRealInputsOnce',
      snapshot.paymentOptions
                  .singleWhere((o) => o.label == 'Efectivo')
                  .balanceMinor ==
              100000 &&
          snapshot.paymentOptions
                  .singleWhere((o) => o.label == 'Nequi')
                  .balanceMinor ==
              50000,
    );
    final firstInput = input('new-product');
    await store.prepare(firstInput);
    snapshot = await store.load();
    check(
      'preparedIntakeHasNoCatalogOrStockSideEffects',
      snapshot.products.isEmpty &&
          snapshot.stock.isEmpty &&
          snapshot.suppliers.isEmpty &&
          snapshot.pendingIntakes.length == 1,
    );
    await app.close();
    app = await AppDatabase.open(path: paths.databasePath);
    store = SqliteStockIntakeStore(app, synthetic: true);
    snapshot = await store.load();
    check(
      'preparedIntakeRecoversAfterReopen',
      snapshot.pendingIntakes.single.command.commandId == firstInput.commandId,
    );
    final first = await store.confirmPrepared(firstInput.commandId);
    snapshot = await store.load();
    check(
      'productCreatedDirectlyWithPvpSkuAndCategory',
      snapshot.products.single.listPriceMinor == 3000 &&
          snapshot.products.single.sku == 'STOCK-SYNTHETIC' &&
          snapshot.products.single.categoryId == category,
    );
    check(
      'supplierCreatedInSameOperation',
      snapshot.suppliers.single.name == 'Proveedor sintético',
    );
    check(
      'fiveUnitsWithExactCost',
      snapshot.stock.single.quantity == 5 &&
          snapshot.stock.single.totalCostMinor == 5005,
    );
    check(
      'cashPurchaseDeductsItsFullCost',
      snapshot.paymentOptions
              .singleWhere((o) => o.label == 'Efectivo')
              .balanceMinor ==
          94995,
    );
    check(
      'purchaseHasNoOutstandingDebt',
      (await SqliteSupplierPaymentsStore(
        app,
      ).load()).payables.every((d) => d.remainingMinor == 0),
    );
    check(
      'historyPreservesUnitCostPvpQuantityAndPayment',
      snapshot.entries.single.unitPurchasePriceMinor == 1001 &&
          snapshot.entries.single.listPriceMinor == 3000 &&
          snapshot.entries.single.quantity == 5 &&
          snapshot.entries.single.paymentLabel == 'Efectivo',
    );
    final replay = await store.confirmPrepared(firstInput.commandId);
    check(
      'replayReturnsOriginalPurchaseAndPayment',
      replay.purchaseDocumentId == first.purchaseDocumentId &&
          replay.paymentDocumentId == first.paymentDocumentId,
    );
    check(
      'replayDoesNotDuplicateMoneyOrStock',
      (await store.load()).stock.single.quantity == 5 &&
          (await app.database.query('supplier_payments')).length == 1,
    );
    final secondInput = input(
      'replenishment',
      existing: snapshot.products.single,
      qty: 2,
      cost: 1200,
      pvp: 3500,
      option: 'NEQUI',
      hour: 15,
    );
    await store.prepare(secondInput);
    await store.confirmPrepared(secondInput.commandId);
    snapshot = await store.load();
    check(
      'replenishmentReusesOneProductAndSupplier',
      snapshot.products.length == 1 && snapshot.suppliers.length == 1,
    );
    check(
      'replenishmentAddsExactStockAndCost',
      snapshot.stock.single.quantity == 7 &&
          snapshot.stock.single.totalCostMinor == 7405,
    );
    check(
      'newPvpIsVisibleInCatalog',
      snapshot.products.single.listPriceMinor == 3500,
    );
    check(
      'nequiPurchaseDeductsItsCost',
      snapshot.paymentOptions
              .singleWhere((o) => o.label == 'Nequi')
              .balanceMinor ==
          47600,
    );
    check(
      'firstEntryKeepsItsHistoricalPvpAndCost',
      snapshot.entries.last.listPriceMinor == 3000 &&
          snapshot.entries.last.unitPurchasePriceMinor == 1001,
    );
    final quick = SqliteQuickSalesStore(app, synthetic: true);
    await quick.saveAccount(
      SaveQuickSaleAccount(
        id: 'counter-account',
        label: 'Cuenta sintética',
        expectedRevision: 0,
        lines: const [
          QuickSaleLine(
            id: 'counter-line',
            productId: 'product-synthetic',
            quantityText: '2',
            unitPriceMinor: 3500,
            paymentOptionId: 'quick-default:EFECTIVO',
          ),
        ],
      ),
    );
    await quick.prepareSale(
      commandId: 'counter-sale',
      accountId: 'counter-account',
      expectedRevision: 1,
      occurredAtUtc: DateTime.utc(2026, 10, 19, 16),
    );
    final sale = await quick.confirmPrepared('counter-sale');
    snapshot = await store.load();
    check(
      'newStockIsImmediatelySellable',
      sale.totalMinor == 7000 && snapshot.stock.single.quantity == 5,
    );
    check(
      'saleUsesHistoricalAcquisitionCost',
      sale.totalCostMinor == 2002 &&
          snapshot.stock.single.totalCostMinor == 5403,
    );
    check(
      'saleAndPurchaseMoneyReconcile',
      snapshot.paymentOptions
                  .singleWhere((o) => o.label == 'Efectivo')
                  .balanceMinor ==
              101995 &&
          snapshot.paymentOptions
                  .singleWhere((o) => o.label == 'Nequi')
                  .balanceMinor ==
              47600,
    );
    check(
      'allPurchasesRemainFullyPaid',
      (await SqliteSupplierPaymentsStore(
        app,
      ).load()).payables.every((d) => d.remainingMinor == 0),
    );
    await app.close();
    app = await AppDatabase.open(path: paths.databasePath);
    store = SqliteStockIntakeStore(app, synthetic: true);
    snapshot = await store.load();
    check(
      'historyAndBalancesSurviveFinalReopen',
      snapshot.entries.length == 2 &&
          snapshot.stock.single.quantity == 5 &&
          snapshot.paymentOptions
                  .singleWhere((o) => o.label == 'Nequi')
                  .balanceMinor ==
              47600,
    );
    check(
      'noPendingRequestAfterConfirmedOperations',
      snapshot.pendingIntakes.isEmpty,
    );
    final health = await app.readHealth();
    check(
      'databaseIntegrityVerified',
      health['integrityOk'] == true &&
          health['schemaChecksumVerified'] == true &&
          health['migrationChecksumVerified'] == true &&
          health['foreignKeyViolations'] == 0,
    );
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'verifiedAtUtc': DateTime.now().toUtc().toIso8601String(),
        'syntheticOnly': true,
        'dataRoot': root,
        'profileId': 'stock-intake-smoke',
        'databasePath': paths.databasePath,
        'checks': checks,
        'passed': checks.length,
        'health': health,
      }),
    );
  } catch (failure, stack) {
    stderr.writeln(failure);
    stderr.writeln(stack);
    exitCode = 1;
  } finally {
    await app?.close();
  }
}
