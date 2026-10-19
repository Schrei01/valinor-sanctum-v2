import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/core/infrastructure/storage_paths.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/workspace/data/sqlite_workspace_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';

/// Creates a fresh, isolated synthetic fixture for native desktop observation.
/// Never accepts an existing database or a production path.
Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty) {
    stderr.writeln('This synthetic verifier takes no path arguments.');
    exitCode = 64;
    return;
  }
  AppDatabase? app;
  try {
    final runId = 'inventory-${InventoryIds.next()}';
    final dataRoot = p.join(AppConfig.repositoryRootPath, 'tmp', runId);
    const profileId = 'inventory-smoke';
    final paths = await StoragePaths.resolve(
      AppConfig(
        environment: AppEnvironment.test,
        dataRoot: dataRoot,
        profileId: profileId,
      ),
    );
    if (await File(paths.databasePath).exists()) {
      throw StateError('Refusing to overwrite an existing fixture.');
    }
    final checks = <String, bool>{};
    void check(String name, bool passed) {
      checks[name] = passed;
      if (!passed) throw StateError('Failed synthetic check: $name');
    }

    final now = DateTime.now().toUtc();
    app = await AppDatabase.open(path: paths.databasePath);
    await SqliteWorkspaceStore(app).createProfile(
      BusinessProfile(
        profileId: profileId,
        businessName: 'Inventario sintético 0.2.0',
        currencyCode: 'COP',
        moneyScale: 2,
        timezone: 'America/Bogota',
        createdAtUtc: now,
      ),
    );
    var store = SqliteInventoryStore(app, synthetic: true);
    await store.saveCategory(
      const InventoryCategory(id: 'category-a', name: 'Categoría sintética'),
    );
    await store.saveSupplier(
      const InventorySupplier(id: 'supplier-a', name: 'Proveedor sintético'),
    );
    await store.saveProduct(
      const CatalogProduct(
        id: 'product-a',
        name: 'Producto sintético A',
        sku: 'TEST-A',
        categoryId: 'category-a',
        listPriceMinor: 5000,
      ),
    );
    await store.saveProduct(
      const CatalogProduct(
        id: 'product-b',
        name: 'Producto sintético B',
        sku: 'TEST-B',
        listPriceMinor: 3000,
      ),
    );
    final command = ReceiptCommand(
      commandId: 'receipt-synthetic-a',
      supplierId: 'supplier-a',
      lines: const [
        ReceiptLineInput(
          productId: 'product-a',
          quantity: 3,
          totalCostMinor: 10001,
        ),
        ReceiptLineInput(
          productId: 'product-b',
          quantity: 2,
          totalCostMinor: 4000,
        ),
      ],
      reference: 'SINTETICA-001',
      dueDate: _date(now.add(const Duration(days: 7))),
      occurredAtUtc: now,
    );
    final posted = await store.receivePurchase(command);
    final replayed = await store.receivePurchase(command);
    check(
      'idempotentResult',
      posted.documentId == replayed.documentId &&
          posted.totalMinor == replayed.totalMinor &&
          posted.commandId == replayed.commandId,
    );
    check('exactReceiptTotal', posted.totalMinor == 14001);

    await store.saveProduct(
      const CatalogProduct(
        id: 'product-a',
        name: 'Producto sintético A actualizado',
        sku: 'TEST-A',
        categoryId: 'category-a',
        listPriceMinor: 5500,
      ),
    );
    await store.saveSupplier(
      const InventorySupplier(
        id: 'supplier-a',
        name: 'Proveedor sintético actualizado',
      ),
    );
    final historicalLine = (await app.database.query(
      'purchase_lines',
      where: 'product_id = ?',
      whereArgs: ['product-a'],
    )).single;
    check(
      'historicalProductName',
      historicalLine['name_snapshot'] == 'Producto sintético A',
    );
    check('historicalCost', historicalLine['acquisition_total_minor'] == 10001);
    final history = await store.load();
    check(
      'historicalSupplierName',
      history.receipts.single.supplierName == 'Proveedor sintético',
    );
    check('oneReceiptAfterRetry', history.receipts.length == 1);

    await app.close();
    app = null;
    app = await AppDatabase.open(path: paths.databasePath);
    store = SqliteInventoryStore(app, synthetic: true);
    final reopened = await store.load();
    final stockA = reopened.stock.singleWhere(
      (item) => item.productId == 'product-a',
    );
    final stockB = reopened.stock.singleWhere(
      (item) => item.productId == 'product-b',
    );
    check(
      'reopenedStockA',
      stockA.quantity == 3 && stockA.totalCostMinor == 10001,
    );
    check(
      'reopenedStockB',
      stockB.quantity == 2 && stockB.totalCostMinor == 4000,
    );
    final obligations = await app.database.query('obligations');
    check(
      'supplierDebt',
      obligations.length == 1 &&
          obligations.single['initial_minor'] == 14001 &&
          obligations.single['kind'] == 'supplier_payable',
    );
    final totals = (await app.database.rawQuery(
      'SELECT sum(debit_minor) AS debit, sum(credit_minor) AS credit FROM journal_lines',
    )).single;
    check(
      'balancedJournal',
      totals['debit'] == 14001 && totals['credit'] == 14001,
    );
    check(
      'noCashMovement',
      (await app.database.query('cash_accounts')).isEmpty,
    );
    check(
      'noExpenseAccount',
      (await app.database.query(
        'ledger_accounts',
        where: 'class = ?',
        whereArgs: ['expense'],
      )).isEmpty,
    );
    check(
      'syntheticProvenance',
      (await app.database.query('business_documents')).single['source_kind'] ==
          'synthetic',
    );
    final health = await app.readHealth();
    for (final key in [
      'identityVerified',
      'foreignKeysEnabled',
      'integrityOk',
      'migrationChecksumVerified',
      'schemaChecksumVerified',
    ]) {
      check(key, health[key] == true);
    }
    check('foreignKeyViolations', health['foreignKeyViolations'] == 0);
    await app.close();
    app = null;
    final reportPath = p.join(paths.profileDirectory.path, 'verification.json');
    final report = <String, Object?>{
      'verifiedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'passed': true,
      'syntheticOnly': true,
      'dataRoot': dataRoot,
      'profileId': profileId,
      'databasePath': paths.databasePath,
      'reportPath': reportPath,
      'documentId': posted.documentId,
      'receiptTotalMinor': posted.totalMinor,
      'checks': checks,
      'databaseSha256Note':
          'No whole-file hash computed; checks inspect committed synthetic facts.',
    };
    await File(
      reportPath,
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(report)}\n');
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
  } catch (error, stack) {
    stderr.writeln('Synthetic inventory verification failed: $error\n$stack');
    exitCode = 1;
  } finally {
    await app?.close();
  }
}

String _date(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
