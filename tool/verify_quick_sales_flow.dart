import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/core/infrastructure/storage_paths.dart';
import 'package:valinor_sanctum_2/features/collections/data/sqlite_collections_store.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/data/sqlite_quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/sales/data/sqlite_sales_store.dart';
import 'package:valinor_sanctum_2/features/workspace/data/sqlite_workspace_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';

/// A new synthetic profile only: never accepts an existing database path.
Future<void> main(List<String> args) async {
  if (args.isNotEmpty) {
    stderr.writeln('This verifier takes no file arguments.');
    exitCode = 64;
    return;
  }
  AppDatabase? app;
  try {
    final dataRoot = p.join(
      AppConfig.repositoryRootPath,
      'tmp',
      'quick-sales-${InventoryIds.next()}',
    );
    const profileId = 'quick-sales-smoke';
    final paths = await StoragePaths.resolve(
      AppConfig(
        environment: AppEnvironment.test,
        dataRoot: dataRoot,
        profileId: profileId,
      ),
    );
    if (await File(paths.databasePath).exists()) {
      throw StateError('Refusing to overwrite fixture.');
    }
    final checks = <String, bool>{};
    void check(String name, bool passed) {
      checks[name] = passed;
      if (!passed) throw StateError('Failed: $name');
    }

    app = await AppDatabase.open(path: paths.databasePath);
    final now = DateTime.now().toUtc();
    final due = now
        .add(const Duration(days: 7))
        .toIso8601String()
        .substring(0, 10);
    await SqliteWorkspaceStore(app).createProfile(
      BusinessProfile(
        profileId: profileId,
        businessName: 'Mostrador sintético 0.6.0',
        currencyCode: 'COP',
        moneyScale: 2,
        timezone: 'America/Bogota',
        createdAtUtc: now,
      ),
    );
    var inventory = SqliteInventoryStore(app, synthetic: true);
    var quick = SqliteQuickSalesStore(app, synthetic: true);
    await inventory.saveSupplier(
      const InventorySupplier(id: 'supplier', name: 'Proveedor sintético'),
    );
    await inventory.saveProduct(
      const CatalogProduct(
        id: 'product',
        name: 'Producto sintético',
        listPriceMinor: 5000,
      ),
    );
    await inventory.receivePurchase(
      ReceiptCommand(
        commandId: 'purchase',
        supplierId: 'supplier',
        dueDate: due,
        occurredAtUtc: now,
        lines: const [
          ReceiptLineInput(
            productId: 'product',
            quantity: 5,
            totalCostMinor: 10001,
          ),
        ],
      ),
    );
    await quick.ensureDefaults();
    var snapshot = await quick.load();
    final cash = snapshot.paymentOptions.firstWhere(
      (o) => o.label == 'Efectivo',
    );
    final mobile = snapshot.paymentOptions.firstWhere(
      (o) => o.label == 'Nequi',
    );
    check(
      'twoQuickPaymentOptions',
      cash.id != mobile.id && snapshot.paymentOptions.length == 2,
    );
    check(
      'defaultsCreateNoMoney',
      (await SqliteCollectionsStore(
        app,
      ).load()).accounts.every((a) => a.balanceMinor == 0),
    );
    await quick.ensureDefaults();
    check(
      'defaultSetupIdempotent',
      (await quick.load()).paymentOptions.length == 2,
    );
    final first = await quick.saveAccount(
      SaveQuickSaleAccount(
        id: 'account-a',
        label: 'Cuenta A sintética',
        expectedRevision: 0,
        lines: [
          QuickSaleLine(
            id: 'line-a1',
            productId: 'product',
            quantityText: '1',
            unitPriceMinor: 5000,
            paymentOptionId: cash.id,
          ),
          QuickSaleLine(
            id: 'line-a2',
            productId: 'product',
            quantityText: '2',
            unitPriceMinor: 5000,
            paymentOptionId: mobile.id,
          ),
        ],
      ),
    );
    final other = await quick.saveAccount(
      SaveQuickSaleAccount(
        id: 'account-b',
        label: 'Cuenta B sintética',
        expectedRevision: 0,
        lines: [
          QuickSaleLine(
            id: 'line-b1',
            productId: 'product',
            quantityText: '1',
            unitPriceMinor: 5000,
            paymentOptionId: cash.id,
          ),
        ],
      ),
    );
    check(
      'twoSavedAccountsIndependent',
      (await quick.load()).accounts.length == 2 &&
          first.lines.length == 2 &&
          other.lines.length == 1,
    );
    check(
      'draftsDoNotConsumeStock',
      (await inventory.load()).stock.single.quantity == 5,
    );
    check(
      'draftsCreateNoSaleOrCollection',
      (await app.database.query('sales')).isEmpty &&
          (await app.database.query('collections')).isEmpty,
    );
    await app.close();
    app = await AppDatabase.open(path: paths.databasePath);
    quick = SqliteQuickSalesStore(app, synthetic: true);
    inventory = SqliteInventoryStore(app, synthetic: true);
    snapshot = await quick.load();
    check('multipleAccountsSurviveReopen', snapshot.accounts.length == 2);
    check(
      'perLinePaymentSurvivesReopen',
      snapshot.accounts
              .firstWhere((a) => a.id == first.id)
              .lines[1]
              .paymentOptionId ==
          mobile.id,
    );
    final prepared = await quick.prepareSale(
      commandId: 'register-a',
      accountId: first.id,
      expectedRevision: first.revision,
      occurredAtUtc: DateTime.now().toUtc(),
    );
    check('preparedTotalExact', prepared.totalMinor == 15000);
    check(
      'prepareDoesNotDeliverOrCollect',
      (await app.database.query('sales')).isEmpty &&
          (await app.database.query('collections')).isEmpty,
    );
    check(
      'preparedCardLocksOnlyItself',
      (await quick.load()).accounts
                  .firstWhere((a) => a.id == first.id)
                  .status ==
              'prepared' &&
          (await quick.load()).accounts
                  .firstWhere((a) => a.id == other.id)
                  .status ==
              'open',
    );
    await app.close();
    app = await AppDatabase.open(path: paths.databasePath);
    quick = SqliteQuickSalesStore(app, synthetic: true);
    inventory = SqliteInventoryStore(app, synthetic: true);
    check(
      'durableRequestSurvivesReopen',
      (await quick.load()).pendingSales.single.commandId == prepared.commandId,
    );
    final result = await quick.confirmPrepared(prepared.commandId);
    check(
      'immediateSaleHasExactTotalAndCost',
      result.totalMinor == 15000 && result.totalCostMinor == 6001,
    );
    snapshot = await quick.load();
    check(
      'onlyRegisteredAccountCloses',
      snapshot.accounts.length == 1 && snapshot.accounts.single.id == other.id,
    );
    check(
      'otherAccountContentPreserved',
      snapshot.accounts.single.label == other.label &&
          snapshot.accounts.single.revision == other.revision &&
          snapshot.accounts.single.lines.single.quantityText == '1',
    );
    check('noUnresolvedRequestAfterSuccess', snapshot.pendingSales.isEmpty);
    check(
      'perLineHistoryPreserved',
      snapshot.sales.single.lines.length == 2 &&
          snapshot.sales.single.lines.any(
            (l) => l.paymentLabel == 'Efectivo',
          ) &&
          snapshot.sales.single.lines.any((l) => l.paymentLabel == 'Nequi'),
    );
    final stock = (await inventory.load()).stock.single;
    check(
      'repeatedProductAggregatedStock',
      stock.quantity == 2 && stock.totalCostMinor == 4000,
    );
    check(
      'oneSaleOneFullCollection',
      (await app.database.query('sales')).length == 1 &&
          (await app.database.query('collections')).length == 1,
    );
    final collection = await SqliteCollectionsStore(app).load();
    check(
      'noPendingCustomerDebt',
      collection.receivables.single.remainingMinor == 0,
    );
    check(
      'cashReceived50',
      collection.accounts
              .firstWhere((a) => a.id == cash.cashAccountId)
              .balanceMinor ==
          5000,
    );
    check(
      'mobileReceived100',
      collection.accounts
              .firstWhere((a) => a.id == mobile.cashAccountId)
              .balanceMinor ==
          10000,
    );
    check(
      'legacySaleShowsFullyPaid',
      (await SqliteSalesStore(app).load()).sales.single.remainingMinor == 0,
    );
    final replay = await quick.confirmPrepared(prepared.commandId);
    check(
      'replayReturnsOriginalDocuments',
      replay.saleDocumentId == result.saleDocumentId &&
          replay.collectionDocumentId == result.collectionDocumentId,
    );
    check(
      'replayNeverDuplicates',
      (await app.database.query('sales')).length == 1 &&
          (await app.database.query('collections')).length == 1 &&
          (await inventory.load()).stock.single.quantity == 2,
    );
    final lines = await app.database.rawQuery(
      '''
SELECT l.debit_minor,l.credit_minor FROM journal_lines l
JOIN journal_entries e ON e.id = l.entry_id AND e.status = 'posted'
JOIN business_documents d ON d.id = e.document_id AND d.status = 'posted'
WHERE d.id IN (?, ?)
''',
      [result.saleDocumentId, result.collectionDocumentId],
    );
    final debit = lines.fold(
      BigInt.zero,
      (s, l) => s + BigInt.from(l['debit_minor'] as int),
    );
    final credit = lines.fold(
      BigInt.zero,
      (s, l) => s + BigInt.from(l['credit_minor'] as int),
    );
    check(
      'saleAndMoneyJournalBalanced',
      debit == credit && debit == BigInt.from(36001),
    );
    await quick.saveAccount(
      SaveQuickSaleAccount(
        id: 'account-c',
        label: 'Cuenta C en preparación',
        expectedRevision: 0,
        lines: const [QuickSaleLine(id: 'line-c1', quantityText: '')],
      ),
    );
    await app.close();
    app = await AppDatabase.open(path: paths.databasePath);
    quick = SqliteQuickSalesStore(app, synthetic: true);
    snapshot = await quick.load();
    check(
      'partialDraftSurvivesReopen',
      snapshot.accounts
          .firstWhere((a) => a.id == 'account-c')
          .lines
          .single
          .quantityText
          .isEmpty,
    );
    check(
      'twoOpenCardsAndPaidHistory',
      snapshot.accounts.length == 2 && snapshot.sales.length == 1,
    );
    check(
      'replayAfterFinalReopen',
      (await quick.confirmPrepared(prepared.commandId)).saleDocumentId ==
          result.saleDocumentId,
    );
    final health = await app.readHealth();
    check(
      'currentSchemaHealthy',
      health['schemaVersion'] == AppDatabase.schemaVersion &&
          health['integrityOk'] == true &&
          health['foreignKeyViolations'] == 0 &&
          health['schemaChecksumVerified'] == true &&
          health['migrationChecksumVerified'] == true,
    );
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'verifiedAtUtc': DateTime.now().toUtc().toIso8601String(),
        'syntheticOnly': true,
        'dataRoot': dataRoot,
        'profileId': profileId,
        'databasePath': paths.databasePath,
        'checks': checks,
        'checkCount': checks.length,
        'health': health,
        'result': {
          'totalMinor': 15000,
          'totalCostMinor': 6001,
          'remainingStock': 2,
          'remainingStockCostMinor': 4000,
          'cashBalanceMinor': 5000,
          'mobileBalanceMinor': 10000,
          'pendingCustomerDebtMinor': 0,
          'openAccounts': 2,
          'paidAccounts': 1,
          'paymentLines': 2,
        },
      }),
    );
  } catch (error, stack) {
    stderr.writeln(error);
    stderr.writeln(stack);
    exitCode = 1;
  } finally {
    await app?.close();
  }
}
