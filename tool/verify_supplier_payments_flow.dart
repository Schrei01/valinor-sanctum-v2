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
import 'package:valinor_sanctum_2/features/supplier_payments/data/sqlite_supplier_payments_store.dart';
import 'package:valinor_sanctum_2/features/supplier_payments/domain/supplier_payments_store.dart';
import 'package:valinor_sanctum_2/features/workspace/data/sqlite_workspace_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';

/// Generates a fresh synthetic profile; never accepts existing database paths.
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
      'supplier-payments-${InventoryIds.next()}',
    );
    const profileId = 'supplier-payments-smoke';
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
        businessName: 'Pagos sintéticos 0.5.0',
        currencyCode: 'COP',
        moneyScale: 2,
        timezone: 'America/Bogota',
        createdAtUtc: now,
      ),
    );
    var inventory = SqliteInventoryStore(app, synthetic: true);
    var sales = SqliteSalesStore(app, synthetic: true);
    var collections = SqliteCollectionsStore(app, synthetic: true);
    var payments = SqliteSupplierPaymentsStore(app, synthetic: true);
    await inventory.saveSupplier(
      const InventorySupplier(id: 'supplier', name: 'Proveedor sintético'),
    );
    await inventory.saveProduct(
      const CatalogProduct(
        id: 'product',
        name: 'Producto sintético',
        listPriceMinor: 7500,
      ),
    );
    await inventory.receivePurchase(
      ReceiptCommand(
        commandId: 'purchase',
        supplierId: 'supplier',
        reference: 'Compra sintética 100',
        dueDate: due,
        occurredAtUtc: now,
        lines: const [
          ReceiptLineInput(
            productId: 'product',
            quantity: 3,
            totalCostMinor: 10000,
          ),
        ],
      ),
    );
    check(
      'initialSupplierDebt100',
      (await payments.load()).payables.single.remainingMinor == 10000,
    );
    final draft = await sales.saveDraft(
      SaveSaleDraft(
        id: 'tab',
        label: 'Venta sintética para fondos',
        customerName: 'Cliente sintético',
        expectedRevision: 0,
        lines: const [
          SaleDraftLine(
            productId: 'product',
            quantity: 2,
            unitPriceMinor: 7500,
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
    check(
      'noOpeningBalanceInvented',
      (await payments.load()).accounts.every((a) => a.balanceMinor == 0),
    );
    final receivable = (await collections.load()).receivables.single;
    await collections.prepareCollection(
      CollectionCommand(
        commandId: 'funds',
        receivableId: receivable.receivableId,
        occurredAtUtc: DateTime.now().toUtc(),
        parts: const [
          CollectionPartInput(
            cashAccountId: 'cash',
            paymentMethodId: 'cash-method',
            amountMinor: 9000,
          ),
          CollectionPartInput(
            cashAccountId: 'mobile',
            paymentMethodId: 'mobile-method',
            amountMinor: 6000,
          ),
        ],
      ),
    );
    await collections.confirmPrepared('funds');
    var snapshot = await payments.load();
    check(
      'fundedFromActualCollection',
      snapshot.accounts.fold(0, (sum, a) => sum + a.balanceMinor) == 15000,
    );
    final payable = snapshot.payables.single;
    Future<String> facts() async {
      final rows = <String, Object?>{};
      for (final table in [
        'purchases',
        'purchase_lines',
        'inventory_movements',
        'cost_layers',
        'sales',
        'sale_lines',
        'sale_outflows',
        'sale_cost_allocations',
        'collections',
        'receivable_settlements',
      ]) {
        rows[table] = await app!.database.query(table, orderBy: 'rowid');
      }
      return jsonEncode(rows);
    }

    final commercialBefore = await facts();
    final first = SupplierPaymentCommand(
      commandId: 'partial-40',
      payableId: payable.payableId,
      occurredAtUtc: DateTime.now().toUtc(),
      parts: const [
        SupplierPaymentPartInput(
          cashAccountId: 'cash',
          paymentMethodId: 'cash-method',
          amountMinor: 4000,
        ),
      ],
    );
    await payments.preparePayment(first);
    check(
      'prepareDoesNotSpend',
      (await payments.load()).accounts
              .firstWhere((a) => a.id == 'cash')
              .balanceMinor ==
          9000,
    );
    check(
      'prepareDoesNotSettleDebt',
      (await payments.load()).payables.single.remainingMinor == 10000,
    );
    await app.close();
    app = await AppDatabase.open(path: paths.databasePath);
    inventory = SqliteInventoryStore(app, synthetic: true);
    sales = SqliteSalesStore(app, synthetic: true);
    collections = SqliteCollectionsStore(app, synthetic: true);
    payments = SqliteSupplierPaymentsStore(app, synthetic: true);
    check(
      'preparedSurvivesReopen',
      (await payments.load()).pendingPayments.single.commandId ==
          first.commandId,
    );
    final partial = await payments.confirmPrepared(first.commandId);
    check(
      'partialHasExactResponse',
      partial.totalMinor == 4000 && partial.remainingMinor == 6000,
    );
    snapshot = await payments.load();
    check(
      'partialDebt60',
      snapshot.payables.single.paidMinor == 4000 &&
          snapshot.payables.single.remainingMinor == 6000,
    );
    check(
      'partialCash50',
      snapshot.accounts.firstWhere((a) => a.id == 'cash').balanceMinor == 5000,
    );
    final purchasePartial = (await inventory.load()).receipts.single;
    check(
      'purchaseViewReflectsPartial',
      purchasePartial.paidMinor == 4000 &&
          purchasePartial.remainingMinor == 6000,
    );
    check('partialChangesNoCommercialFacts', await facts() == commercialBefore);
    await app.close();
    app = await AppDatabase.open(path: paths.databasePath);
    inventory = SqliteInventoryStore(app, synthetic: true);
    sales = SqliteSalesStore(app, synthetic: true);
    collections = SqliteCollectionsStore(app, synthetic: true);
    payments = SqliteSupplierPaymentsStore(app, synthetic: true);
    check(
      'partialPersistsAfterReopen',
      (await payments.load()).payables.single.remainingMinor == 6000,
    );
    Future<bool> rejected(SupplierPaymentCommand command) async {
      try {
        await payments.preparePayment(command);
        return false;
      } on SupplierPaymentsValidationException {
        return true;
      }
    }

    check(
      'overpaymentRejected',
      await rejected(
        SupplierPaymentCommand(
          commandId: 'too-much',
          payableId: payable.payableId,
          occurredAtUtc: DateTime.now().toUtc(),
          parts: const [
            SupplierPaymentPartInput(
              cashAccountId: 'mobile',
              paymentMethodId: 'mobile-method',
              amountMinor: 6001,
            ),
          ],
        ),
      ),
    );
    check(
      'insufficientCashRejected',
      await rejected(
        SupplierPaymentCommand(
          commandId: 'no-funds',
          payableId: payable.payableId,
          occurredAtUtc: DateTime.now().toUtc(),
          parts: const [
            SupplierPaymentPartInput(
              cashAccountId: 'cash',
              paymentMethodId: 'cash-method',
              amountMinor: 6000,
            ),
          ],
        ),
      ),
    );
    check(
      'invalidInputsNoDurableRequest',
      (await app.database.query('supplier_payment_requests')).length == 1,
    );
    final last = SupplierPaymentCommand(
      commandId: 'final-60',
      payableId: payable.payableId,
      occurredAtUtc: DateTime.now().toUtc(),
      parts: const [
        SupplierPaymentPartInput(
          cashAccountId: 'cash',
          paymentMethodId: 'cash-method',
          amountMinor: 2000,
        ),
        SupplierPaymentPartInput(
          cashAccountId: 'mobile',
          paymentMethodId: 'mobile-method',
          amountMinor: 4000,
        ),
      ],
    );
    await payments.preparePayment(last);
    await app.close();
    app = await AppDatabase.open(path: paths.databasePath);
    inventory = SqliteInventoryStore(app, synthetic: true);
    sales = SqliteSalesStore(app, synthetic: true);
    collections = SqliteCollectionsStore(app, synthetic: true);
    payments = SqliteSupplierPaymentsStore(app, synthetic: true);
    check(
      'splitPreparedSurvivesReopen',
      (await payments.load()).pendingPayments.single.parts.length == 2,
    );
    final paid = await payments.confirmPrepared(last.commandId);
    snapshot = await payments.load();
    check(
      'finalDebtZero',
      paid.remainingMinor == 0 && snapshot.payables.single.remainingMinor == 0,
    );
    check(
      'cashRemaining30',
      snapshot.accounts.firstWhere((a) => a.id == 'cash').balanceMinor == 3000,
    );
    check(
      'mobileRemaining20',
      snapshot.accounts.firstWhere((a) => a.id == 'mobile').balanceMinor ==
          2000,
    );
    check('noPendingRequests', snapshot.pendingPayments.isEmpty);
    check('twoPaymentDocuments', snapshot.payments.length == 2);
    check(
      'purchaseViewFullyPaid',
      (await inventory.load()).receipts.single.paidMinor == 10000,
    );
    final replay = await payments.confirmPrepared(first.commandId);
    check(
      'partialReplayPreservesOriginalRemainder',
      replay.documentId == partial.documentId && replay.remainingMinor == 6000,
    );
    check(
      'finalReplayReturnsSameDocument',
      (await payments.confirmPrepared(last.commandId)).documentId ==
          paid.documentId,
    );
    check(
      'replaysDoNotDuplicate',
      (await payments.load()).payments.length == 2 &&
          (await app.database.query('payable_settlements')).length == 2,
    );
    check('noCommercialFactsChanged', await facts() == commercialBefore);
    final stock = (await inventory.load()).stock.single;
    check(
      'remainingStockAndCostExact',
      stock.quantity == 1 && stock.totalCostMinor == 3333,
    );
    final sale = (await sales.load()).sales.single;
    check(
      'saleRevenueCostCollectionUnchanged',
      sale.totalMinor == 15000 &&
          sale.totalCostMinor == 6667 &&
          sale.paidMinor == 15000,
    );
    final journal = await app.database.rawQuery('''
SELECT a.role, l.debit_minor, l.credit_minor FROM journal_lines l
JOIN ledger_accounts a ON a.id = l.account_id
JOIN journal_entries e ON e.id = l.entry_id AND e.status = 'posted'
JOIN business_documents d ON d.id = e.document_id AND d.status = 'posted'
WHERE d.type = 'supplier_payment'
''');
    check(
      'onlyLiabilityAndMoneyAffected',
      journal.every(
        (r) => r['role'] == 'cash' || r['role'] == 'supplier_payable',
      ),
    );
    final debit = journal.fold(
      BigInt.zero,
      (s, r) => s + BigInt.from(r['debit_minor'] as int),
    );
    final credit = journal.fold(
      BigInt.zero,
      (s, r) => s + BigInt.from(r['credit_minor'] as int),
    );
    check(
      'paymentJournalBalanced100',
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
    final history = (await payments.load()).payments;
    check(
      'historicalAccountNamesPreserved',
      history.every(
        (h) => h.parts
            .where((p) => p.cashAccountId == 'cash')
            .every((p) => p.cashAccountName == 'Caja sintética'),
      ),
    );
    check(
      'historicalMethodNamesPreserved',
      history.every(
        (h) => h.parts
            .where((p) => p.paymentMethodId == 'cash-method')
            .every((p) => p.paymentMethodName == 'Efectivo'),
      ),
    );
    check(
      'sharedBalancesVisibleInCollections',
      (await collections.load()).accounts.fold(
            0,
            (s, a) => s + a.balanceMinor,
          ) ==
          5000,
    );
    await app.close();
    app = await AppDatabase.open(path: paths.databasePath);
    payments = SqliteSupplierPaymentsStore(app, synthetic: true);
    check(
      'finalPersistsAfterReopen',
      (await payments.load()).payables.single.remainingMinor == 0,
    );
    check(
      'replayAfterFinalReopen',
      (await payments.confirmPrepared(first.commandId)).remainingMinor == 6000,
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
          'purchaseMinor': 10000,
          'partialMinor': 4000,
          'partialRemainingMinor': 6000,
          'finalMinor': 6000,
          'remainingMinor': 0,
          'cashBalanceMinor': 3000,
          'mobileBalanceMinor': 2000,
          'stockQuantity': 1,
          'stockCostMinor': 3333,
          'saleMinor': 15000,
          'saleCostMinor': 6667,
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
