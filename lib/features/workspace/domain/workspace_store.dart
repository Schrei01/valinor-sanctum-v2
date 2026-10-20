import 'business_profile.dart';
import '../../inventory/domain/inventory_store.dart';
import '../../sales/domain/sales_store.dart';
import '../../collections/domain/collections_store.dart';
import '../../supplier_payments/domain/supplier_payments_store.dart';
import '../../quick_sales/domain/quick_sales_store.dart';
import '../../stock_intake/domain/stock_intake_store.dart';

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
    this.salesStore,
    this.collectionsStore,
    this.supplierPaymentsStore,
    this.quickSalesStore,
    this.stockIntakeStore,
  });
  final WorkspaceStore store;
  final String databasePath;
  final String profileId;
  final InventoryStore? inventoryStore;
  final SalesStore? salesStore;
  final CollectionsStore? collectionsStore;
  final SupplierPaymentsStore? supplierPaymentsStore;
  final QuickSalesStore? quickSalesStore;
  final StockIntakeStore? stockIntakeStore;
}
