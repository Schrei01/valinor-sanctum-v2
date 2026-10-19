import 'dart:async';
import 'package:valinor_sanctum_2/core/infrastructure/database/schema.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/workspace_store.dart';

class FakeWorkspaceStore implements WorkspaceStore {
  FakeWorkspaceStore({
    this.identityVerified = true,
    this.foreignKeyViolations = 0,
  });

  BusinessProfile? profile;
  Object? saveFailure;
  Object? healthFailureAfterSave;
  Completer<void>? saveGate;
  int saves = 0;
  int closes = 0;
  bool healthy = true;
  bool identityVerified;
  int foreignKeyViolations;

  @override
  Future<BusinessProfile?> readProfile() async => profile;
  @override
  Future<void> createProfile(BusinessProfile value) async {
    saves++;
    if (saveGate != null) await saveGate!.future;
    if (saveFailure != null) throw saveFailure!;
    profile = value;
  }

  @override
  Future<Map<String, Object?>> readHealth() async {
    if (profile != null && healthFailureAfterSave != null) {
      throw healthFailureAfterSave!;
    }
    return {
      'schemaVersion': DatabaseSchema.version,
      'identityVerified': identityVerified,
      'integrityOk': healthy,
      'foreignKeysEnabled': true,
      'foreignKeyViolations': foreignKeyViolations,
      'schemaChecksumVerified': true,
      'migrationChecksumVerified': true,
      'configured': profile != null,
    };
  }

  @override
  Future<void> close() async {
    closes++;
  }
}

WorkspaceSession fakeSession(FakeWorkspaceStore store) => WorkspaceSession(
  store: store,
  databasePath: 'perfil-sintetico/sanctum2.sqlite3',
  profileId: 'test',
);
