import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/core/infrastructure/storage_paths.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/sales/data/sqlite_sales_store.dart';
import 'package:valinor_sanctum_2/features/sales/domain/sales_store.dart';
import 'package:valinor_sanctum_2/features/workspace/data/sqlite_workspace_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';

/// Synthetic end-to-end business fixture; never accepts an existing file.
Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty) {
    stderr.writeln('This verifier takes no path arguments.');
    exitCode = 64;
    return;
  }
  AppDatabase? app;
  try {
    final dataRoot = p.join(
      AppConfig.repositoryRootPath,
      'tmp',
      'sales-${InventoryIds.next()}',
    );
    const profileId = 'sales-smoke';
    final paths = await StoragePaths.resolve(
      AppConfig(
        environment: AppEnvironment.test,
        dataRoot: dataRoot,
        profileId: profileId,
      ),
    );
    if (await File(paths.databasePath).exists()) {
      throw StateError('Refusing to overwrite a fixture.');
    }
    final checks = <String, bool>{};
    void check(String label, bool passed) {
      checks[label] = passed;
      if (!passed) throw StateError('Failed synthetic check: $label');
    }

    final now = DateTime.now().toUtc();
    final dueDate = now
        .add(const Duration(days: 7))
        .toIso8601String()
        .substring(0, 10);
    app = await AppDatabase.open(path: paths.databasePath);
    await SqliteWorkspaceStore(app).createProfile(
      BusinessProfile(
        profileId: profileId,
        businessName: 'Ventas sintéticas 0.3.0',
        currencyCode: 'COP',
        moneyScale: 2,
        timezone: 'America/Bogota',
        createdAtUtc: now,
      ),
    );
    var inventory = SqliteInventoryStore(app, synthetic: true);
    var sales = SqliteSalesStore(app, synthetic: true);
    await inventory.saveSupplier(
      const InventorySupplier(id: 'supplier-test', name: 'Proveedor sintético'),
    );
    await inventory.saveProduct(
      const CatalogProduct(
        id: 'product-test',
        name: 'Producto sintético',
        listPriceMinor: 5000,
      ),
    );
    await inventory.receivePurchase(
      ReceiptCommand(
        commandId: 'receipt-test',
        supplierId: 'supplier-test',
        lines: const [
          ReceiptLineInput(
            productId: 'product-test',
            quantity: 3,
            totalCostMinor: 10001,
          ),
        ],
        dueDate: dueDate,
        occurredAtUtc: now,
      ),
    );
    final draft = await sales.saveDraft(
      SaveSaleDraft(
        id: 'tab-test',
        label: 'Mesa sintética',
        customerName: 'Cliente sintético',
        expectedRevision: 0,
        lines: const [
          SaleDraftLine(
            productId: 'product-test',
            quantity: 2,
            unitPriceMinor: 5000,
          ),
        ],
      ),
    );
    check(
      'draftDoesNotReduceStock',
      (await inventory.load()).stock.single.quantity == 3,
    );
    check('draftCreatesNoSale', (await sales.load()).sales.isEmpty);
    await app.close();
    app = await AppDatabase.open(path: paths.databasePath);
    sales = SqliteSalesStore(app, synthetic: true);
    inventory = SqliteInventoryStore(app, synthetic: true);
    final recoveredDraft = (await sales.load()).drafts.single;
    check(
      'draftSurvivesReopen',
      recoveredDraft.id == draft.id &&
          recoveredDraft.revision == draft.revision &&
          recoveredDraft.lines.single.quantity == 2,
    );
    check(
      'stockStillThreeAfterReopen',
      (await inventory.load()).stock.single.quantity == 3,
    );
    final prepared = await sales.prepareConfirmation(
      commandId: 'sale-test',
      draftId: draft.id,
      expectedRevision: draft.revision,
      occurredAtUtc: DateTime.now().toUtc(),
      dueDate: dueDate,
    );
    check(
      'prepareDoesNotReduceStock',
      (await inventory.load()).stock.single.quantity == 3,
    );
    await app.close();
    app = await AppDatabase.open(path: paths.databasePath);
    sales = SqliteSalesStore(app, synthetic: true);
    inventory = SqliteInventoryStore(app, synthetic: true);
    final pending = (await sales.load()).pendingConfirmations.single;
    check(
      'preparedIdentitySurvivesReopen',
      pending.commandId == prepared.commandId &&
          pending.draftRevision == prepared.draftRevision &&
          pending.occurredAtUtc == prepared.occurredAtUtc,
    );
    final result = await sales.confirmPrepared(pending.commandId);
    check('saleExactTotal', result.totalMinor == 10000);
    check('saleExactHistoricalCost', result.totalCostMinor == 6668);
    final replay = await sales.confirmPrepared(pending.commandId);
    check(
      'replayReturnsSameResult',
      result.documentId == replay.documentId &&
          result.commandId == replay.commandId &&
          result.totalMinor == replay.totalMinor &&
          result.totalCostMinor == replay.totalCostMinor,
    );
    final stock = (await inventory.load()).stock.single;
    check('remainingStockOne', stock.quantity == 1);
    check('remainingCostExact', stock.totalCostMinor == 3333);
    check(
      'customerReceivableExact',
      (await app.database.query(
            'customer_receivables',
          )).single['initial_minor'] ==
          10000,
    );
    check(
      'oneOutflowAfterReplay',
      (await app.database.query('sale_outflows')).length == 1,
    );
    final confirmed = (await sales.load()).sales.single;
    check(
      'customerAndLabelSnapshot',
      confirmed.customerName == 'Cliente sintético' &&
          confirmed.label == 'Mesa sintética',
    );
    check(
      'confirmedPendingRemoved',
      (await sales.load()).pendingConfirmations.isEmpty,
    );
    await inventory.saveProduct(
      const CatalogProduct(
        id: 'product-test',
        name: 'Producto cambiado después',
        listPriceMinor: 9000,
      ),
    );
    final history = (await sales.load()).sales.single;
    check(
      'historicalProductNameImmutable',
      history.lines.single.productName == 'Producto sintético',
    );
    check(
      'historicalPriceImmutable',
      history.lines.single.unitPriceMinor == 5000,
    );
    check(
      'historicalCostImmutable',
      history.lines.single.totalCostMinor == 6668,
    );
    final journal = await app.database.query('journal_lines');
    var debit = BigInt.zero;
    var credit = BigInt.zero;
    for (final line in journal) {
      debit += BigInt.from(line['debit_minor']! as int);
      credit += BigInt.from(line['credit_minor']! as int);
    }
    check('journalBalanced', debit == credit);
    check(
      'noCashAccountsInvented',
      (await app.database.query('cash_accounts')).isEmpty,
    );
    check(
      'noPaymentMethodsInvented',
      (await app.database.query('payment_methods')).isEmpty,
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
    await app.close();
    app = await AppDatabase.open(path: paths.databasePath);
    sales = SqliteSalesStore(app, synthetic: true);
    inventory = SqliteInventoryStore(app, synthetic: true);
    check(
      'saleSurvivesReopen',
      (await sales.load()).sales.single.documentId == result.documentId,
    );
    check(
      'stockSurvivesReopen',
      (await inventory.load()).stock.single.quantity == 1,
    );
    final afterReopen = await sales.confirmPrepared(prepared.commandId);
    check('replayAfterReopen', afterReopen.documentId == result.documentId);
    // Leave one clearly synthetic prepared account for native recovery inspection.
    final nativeDraft = await sales.saveDraft(
      SaveSaleDraft(
        id: 'tab-native-pending',
        label: 'Cuenta pendiente sintética',
        customerName: 'Cliente sintético pendiente',
        expectedRevision: 0,
        lines: const [
          SaleDraftLine(
            productId: 'product-test',
            quantity: 1,
            unitPriceMinor: 9000,
          ),
        ],
      ),
    );
    await sales.prepareConfirmation(
      commandId: 'sale-native-pending',
      draftId: nativeDraft.id,
      expectedRevision: nativeDraft.revision,
      occurredAtUtc: DateTime.now().toUtc(),
      dueDate: dueDate,
    );
    check(
      'nativePendingPrepared',
      (await sales.load()).pendingConfirmations.single.commandId ==
          'sale-native-pending',
    );
    check(
      'nativePendingStillNoStockEffect',
      (await inventory.load()).stock.single.quantity == 1,
    );
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'verifiedAtUtc': DateTime.now().toUtc().toIso8601String(),
        'dataRoot': dataRoot,
        'profileId': profileId,
        'databasePath': paths.databasePath,
        'syntheticOnly': true,
        'checks': checks,
        'checkCount': checks.length,
        'health': health,
        'result': {
          'totalMinor': result.totalMinor,
          'costMinor': result.totalCostMinor,
          'remainingQuantity': 1,
          'remainingCostMinor': 3333,
        },
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
