import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'app/sanctum_app.dart';
import 'core/infrastructure/app_config.dart';
import 'core/infrastructure/database/app_database.dart';
import 'core/infrastructure/storage_paths.dart';
import 'core/infrastructure/local_workspace_selection.dart';
import 'features/workspace/application/workspace_controller.dart';
import 'features/workspace/data/sqlite_workspace_store.dart';
import 'features/workspace/domain/workspace_store.dart';
import 'features/inventory/data/sqlite_inventory_store.dart';
import 'features/inventory/data/json_reference_inventory_store.dart';
import 'features/sales/data/sqlite_sales_store.dart';
import 'features/collections/data/sqlite_collections_store.dart';
import 'features/supplier_payments/data/sqlite_supplier_payments_store.dart';
import 'features/quick_sales/data/sqlite_quick_sales_store.dart';
import 'features/stock_intake/data/sqlite_stock_intake_store.dart';
import 'features/treasury/data/sqlite_treasury_store.dart';
import 'features/treasury/data/json_legacy_treasury_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = WorkspaceController(
    openSession: () async {
      final config = await resolveLocalWorkspace(
        AppConfig.fromEnvironment(),
        enabled:
            !const bool.hasEnvironment('SANCTUM_PROFILE') &&
            !const bool.hasEnvironment('SANCTUM_DATA_ROOT') &&
            !const bool.hasEnvironment('SANCTUM_ENV') &&
            !const bool.hasEnvironment('SANCTUM_WORKSPACE_ROOT'),
      );
      final paths = await StoragePaths.resolve(config);
      final database = await AppDatabase.open(path: paths.databasePath);
      final treasuryOrigins = await database.database.rawQuery('''
SELECT opening.snapshot_sha256 FROM treasury_openings opening
JOIN business_documents document ON document.id=opening.document_id AND document.status='posted'
JOIN journal_entries entry ON entry.document_id=document.id AND entry.status='posted'
''');
      return WorkspaceSession(
        store: SqliteWorkspaceStore(database),
        databasePath: paths.databasePath,
        profileId: config.profileId,
        referenceInventoryStore: JsonReferenceInventoryStore(
          p.join(paths.profileDirectory.path, 'reference-inventory.json'),
        ),
        inventoryStore: SqliteInventoryStore(
          database,
          synthetic: config.environment == AppEnvironment.test,
        ),
        salesStore: SqliteSalesStore(
          database,
          synthetic: config.environment == AppEnvironment.test,
        ),
        collectionsStore: SqliteCollectionsStore(
          database,
          synthetic: config.environment == AppEnvironment.test,
        ),
        supplierPaymentsStore: SqliteSupplierPaymentsStore(
          database,
          synthetic: config.environment == AppEnvironment.test,
        ),
        quickSalesStore: SqliteQuickSalesStore(
          database,
          synthetic: config.environment == AppEnvironment.test,
        ),
        stockIntakeStore: SqliteStockIntakeStore(
          database,
          synthetic: config.environment == AppEnvironment.test,
        ),
        treasuryStore: SqliteTreasuryStore(database),
        legacyTreasuryStore: treasuryOrigins.isEmpty
            ? null
            : JsonLegacyTreasuryStore(
                p.join(paths.profileDirectory.path, 'legacy-treasury.json'),
                expectedSha256:
                    treasuryOrigins.single['snapshot_sha256'] as String,
              ),
      );
    },
  );
  runApp(SanctumApp(controller: controller));
  unawaited(controller.initialize());
}
