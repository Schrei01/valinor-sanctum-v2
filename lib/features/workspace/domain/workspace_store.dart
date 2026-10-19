import 'business_profile.dart';

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
  });
  final WorkspaceStore store;
  final String databasePath;
  final String profileId;
}
