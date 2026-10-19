import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/core/infrastructure/storage_paths.dart';
import 'package:valinor_sanctum_2/features/collections/data/sqlite_collections_store.dart';
import 'package:valinor_sanctum_2/features/collections/domain/collections_store.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/sales/data/sqlite_sales_store.dart';
import 'package:valinor_sanctum_2/features/sales/domain/sales_store.dart';
import 'package:valinor_sanctum_2/features/workspace/data/sqlite_workspace_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';

/// Creates only a fresh synthetic profile inside the new repository.
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
      'collections-${InventoryIds.next()}',
    );
    const profileId = 'collections-smoke';
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
        businessName: 'Cobros sintéticos 0.4.0',
        currencyCode: 'COP',
        moneyScale: 2,
        timezone: 'America/Bogota',
        createdAtUtc: now,
      ),
    );
    var inventory = SqliteInventoryStore(app, synthetic: true);
    var sales = SqliteSalesStore(app, synthetic: true);
    var collections = SqliteCollectionsStore(app, synthetic: true);
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
        commandId: 'receipt',
        supplierId: 'supplier',
        occurredAtUtc: now,
        dueDate: due,
        lines: const [
          ReceiptLineInput(
            productId: 'product',
            quantity: 3,
            totalCostMinor: 10001,
          ),
        ],
      ),
    );
    final draft = await sales.saveDraft(
      SaveSaleDraft(
        id: 'tab',
        label: 'Mesa sintética',
        customerName: 'Cliente sintético',
        expectedRevision: 0,
        lines: const [
          SaleDraftLine(
            productId: 'product',
            quantity: 2,
            unitPriceMinor: 5000,
          ),
        ],
      ),
    );
    await sales.prepareConfirmation(
      commandId: 'sale',
      draftId: draft.id,
      expectedRevision: draft.revision,
      occurredAtUtc: DateTime.now().toUtc(),
      dueDate: due,
    );
    await sales.confirmPrepared('sale');
    final moneyRowsBefore = await app.database.query('journal_lines');
    await collections.saveAccount(
      const CollectionAccount(id: 'cash', name: 'Caja sintética', kind: 'cash'),
    );
    await collections.saveAccount(
      const CollectionAccount(
        id: 'mobile',
        name: 'Cuenta móvil sintética',
        kind: 'mobile',
      ),
    );
    await collections.saveMethod(
      const CollectionMethod(
        id: 'cash-method',
        code: 'EFECTIVO',
        name: 'Efectivo',
      ),
    );
    await collections.saveMethod(
      const CollectionMethod(
        id: 'mobile-method',
        code: 'MOVIL',
        name: 'Pago móvil',
      ),
    );
    var snapshot = await collections.load();
    check(
      'noOpeningBalanceInvented',
      snapshot.accounts.every((a) => a.balanceMinor == 0),
    );
    check(
      'configurationDoesNotPostMoney',
      (await app.database.query('journal_lines')).length ==
          moneyRowsBefore.length,
    );
    final receivable = snapshot.receivables.single;
    final firstCommand = CollectionCommand(
      commandId: 'partial-40',
      receivableId: receivable.receivableId,
      occurredAtUtc: DateTime.now().toUtc(),
      parts: const [
        CollectionPartInput(
          cashAccountId: 'cash',
          paymentMethodId: 'cash-method',
          amountMinor: 4000,
        ),
      ],
    );
    final prepared = await collections.prepareCollection(firstCommand);
    check(
      'preparedDoesNotMoveMoney',
      (await collections.load()).accounts.every((a) => a.balanceMinor == 0),
    );
    await app.close();
    app = await AppDatabase.open(path: paths.databasePath);
    collections = SqliteCollectionsStore(app, synthetic: true);
    inventory = SqliteInventoryStore(app, synthetic: true);
    sales = SqliteSalesStore(app, synthetic: true);
    check(
      'preparedIdentityRecovered',
      (await collections.load()).pendingCollections.single.commandId ==
          prepared.commandId,
    );
    final partial = await collections.confirmPrepared(prepared.commandId);
    snapshot = await collections.load();
    check(
      'partialExact',
      partial.totalMinor == 4000 && partial.remainingMinor == 6000,
    );
    check(
      'pendingSixty',
      snapshot.receivables.single.remainingMinor == 6000 &&
          snapshot.receivables.single.collectedMinor == 4000,
    );
    check(
      'cashForty',
      snapshot.accounts.firstWhere((a) => a.id == 'cash').balanceMinor == 4000,
    );
    final salePartial = (await sales.load()).sales.single;
    check(
      'salesViewUpdated',
      salePartial.paidMinor == 4000 && salePartial.remainingMinor == 6000,
    );
    check(
      'saleRevenueAndCostUnchanged',
      salePartial.totalMinor == 10000 && salePartial.totalCostMinor == 6668,
    );
    var stock = (await inventory.load()).stock.single;
    check(
      'partialDoesNotChangeStock',
      stock.quantity == 1 && stock.totalCostMinor == 3333,
    );
    await app.close();
    app = await AppDatabase.open(path: paths.databasePath);
    collections = SqliteCollectionsStore(app, synthetic: true);
    inventory = SqliteInventoryStore(app, synthetic: true);
    sales = SqliteSalesStore(app, synthetic: true);
    check(
      'partialSurvivesReopen',
      (await collections.load()).receivables.single.remainingMinor == 6000,
    );
    final finalCommand = CollectionCommand(
      commandId: 'final-60',
      receivableId: receivable.receivableId,
      occurredAtUtc: DateTime.now().toUtc(),
      parts: const [
        CollectionPartInput(
          cashAccountId: 'cash',
          paymentMethodId: 'cash-method',
          amountMinor: 2500,
        ),
        CollectionPartInput(
          cashAccountId: 'mobile',
          paymentMethodId: 'mobile-method',
          amountMinor: 3500,
        ),
      ],
    );
    await collections.prepareCollection(finalCommand);
    final paid = await collections.confirmPrepared(finalCommand.commandId);
    check('finalExact', paid.totalMinor == 6000 && paid.remainingMinor == 0);
    snapshot = await collections.load();
    check(
      'settledExact',
      snapshot.receivables.single.remainingMinor == 0 &&
          snapshot.receivables.single.collectedMinor == 10000,
    );
    check(
      'cashSixtyFive',
      snapshot.accounts.firstWhere((a) => a.id == 'cash').balanceMinor == 6500,
    );
    check(
      'mobileThirtyFive',
      snapshot.accounts.firstWhere((a) => a.id == 'mobile').balanceMinor ==
          3500,
    );
    final replay = await collections.confirmPrepared(firstCommand.commandId);
    check(
      'earlierResultNotReplacedByLiveBalance',
      replay.documentId == partial.documentId &&
          replay.remainingMinor == 6000 &&
          replay.totalMinor == 4000,
    );
    check(
      'replayDoesNotDuplicate',
      snapshot.collections.length == 2 &&
          (await app.database.query('receivable_settlements')).length == 2,
    );
    check(
      'salesViewSettled',
      (await sales.load()).sales.single.remainingMinor == 0,
    );
    stock = (await inventory.load()).stock.single;
    check(
      'fullDoesNotChangeStock',
      stock.quantity == 1 && stock.totalCostMinor == 3333,
    );
    check('noExtraSales', (await app.database.query('sales')).length == 1);
    final collectionJournal = await app.database.rawQuery(
      "SELECT l.*, a.role FROM journal_lines l JOIN journal_entries e ON e.id=l.entry_id JOIN business_documents d ON d.id=e.document_id JOIN ledger_accounts a ON a.id=l.account_id WHERE d.type='customer_collection' AND d.status='posted' AND e.status='posted'",
    );
    check(
      'collectionOnlyMoneyAndReceivable',
      collectionJournal.every(
        (row) => row['role'] == 'cash' || row['role'] == 'customer_receivable',
      ),
    );
    var debit = BigInt.zero;
    var credit = BigInt.zero;
    for (final row in collectionJournal) {
      debit += BigInt.from(row['debit_minor'] as int);
      credit += BigInt.from(row['credit_minor'] as int);
    }
    check(
      'collectionJournalBalanced',
      debit == credit && debit == BigInt.from(10000),
    );
    await collections.saveAccount(
      const CollectionAccount(
        id: 'cash',
        name: 'Caja renombrada después',
        kind: 'cash',
      ),
    );
    await collections.saveMethod(
      const CollectionMethod(
        id: 'cash-method',
        code: 'EFECTIVO',
        name: 'Medio renombrado después',
      ),
    );
    final history = (await collections.load()).collections;
    check(
      'historicalAccountSnapshot',
      history.every(
        (c) => c.parts
            .where((p) => p.cashAccountId == 'cash')
            .every((p) => p.cashAccountName == 'Caja sintética'),
      ),
    );
    check(
      'historicalMethodSnapshot',
      history.every(
        (c) => c.parts
            .where((p) => p.paymentMethodId == 'cash-method')
            .every((p) => p.paymentMethodName == 'Efectivo'),
      ),
    );
    await app.close();
    app = await AppDatabase.open(path: paths.databasePath);
    collections = SqliteCollectionsStore(app, synthetic: true);
    check(
      'fullSurvivesReopen',
      (await collections.load()).receivables.single.remainingMinor == 0,
    );
    check(
      'finalReplayAfterReopen',
      (await collections.confirmPrepared(finalCommand.commandId)).documentId ==
          paid.documentId,
    );
    final health = await app.readHealth();
    check(
      'currentSchemaHealthy',
      health['schemaVersion'] == 4 &&
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
          'saleMinor': 10000,
          'partialMinor': 4000,
          'partialRemainingMinor': 6000,
          'finalMinor': 6000,
          'remainingMinor': 0,
          'cashBalanceMinor': 6500,
          'mobileBalanceMinor': 3500,
          'stockQuantity': 1,
          'stockCostMinor': 3333,
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
