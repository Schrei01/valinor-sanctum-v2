import 'business_profile.dart';
import '../../inventory/domain/inventory_store.dart';

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
  });
  final WorkspaceStore store;
  final String databasePath;
  final String profileId;
  final InventoryStore? inventoryStore;
}
