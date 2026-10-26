import 'business_profile.dart';
import '../../events/domain/events_store.dart';
import '../../debtors/domain/debtors_store.dart';
import '../../reports/domain/reports_store.dart';
import '../../inventory/domain/inventory_store.dart';
import '../../inventory/domain/reference_inventory.dart';
import '../../sales/domain/sales_store.dart';
import '../../collections/domain/collections_store.dart';
import '../../supplier_payments/domain/supplier_payments_store.dart';
import '../../quick_sales/domain/quick_sales_store.dart';
import '../../stock_intake/domain/stock_intake_store.dart';
import '../../treasury/domain/treasury_store.dart';
import '../../treasury/domain/treasury_operation_store.dart';
import '../../treasury/domain/legacy_treasury_snapshot.dart';

abstract interface class WorkspaceStore {
  Future<BusinessProfile?> readProfile();
  Future<void> createProfile(BusinessProfile profile);
  Future<Map<String, Object?>> readHealth();
  Future<void> close();
}

class WorkspaceSession {
  const WorkspaceSession({
    required this.store,
    required this.databasePath,
    required this.profileId,
    this.inventoryStore,
    this.referenceInventoryStore,
    this.salesStore,
    this.collectionsStore,
    this.supplierPaymentsStore,
    this.quickSalesStore,
    this.stockIntakeStore,
    this.treasuryStore,
    this.treasuryOperationStore,
    this.legacyTreasuryStore,
    this.eventsStore,
    this.debtorsStore,
    this.reportsStore,
  });
  final WorkspaceStore store;
  final String databasePath;
  final String profileId;
  final InventoryStore? inventoryStore;
  final ReferenceInventoryStore? referenceInventoryStore;
  final SalesStore? salesStore;
  final CollectionsStore? collectionsStore;
  final SupplierPaymentsStore? supplierPaymentsStore;
  final QuickSalesStore? quickSalesStore;
  final StockIntakeStore? stockIntakeStore;
  final TreasuryStore? treasuryStore;
  final TreasuryOperationStore? treasuryOperationStore;
  final LegacyTreasuryStore? legacyTreasuryStore;
  final EventsStore? eventsStore;
  final DebtorsStore? debtorsStore;
  final ReportsStore? reportsStore;
}
