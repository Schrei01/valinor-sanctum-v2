import '../../../core/infrastructure/database/app_database.dart';
import '../domain/business_profile.dart';
import '../domain/workspace_store.dart';

class SqliteWorkspaceStore implements WorkspaceStore {
  SqliteWorkspaceStore(this._database);
  final AppDatabase _database;

  @override
  Future<BusinessProfile?> readProfile() async {
    final rows = await _database.database.query(
      'app_profile',
      where: 'id = ?',
      whereArgs: [1],
    );
    return rows.isEmpty ? null : BusinessProfile.fromRow(rows.single);
  }

  @override
  Future<void> createProfile(BusinessProfile profile) =>
      _database.database.transaction((txn) async {
        final existing = await txn.query('app_profile', columns: ['id']);
        if (existing.isNotEmpty) {
          throw StateError('Este espacio ya está configurado.');
        }
        await txn.insert('app_profile', profile.toRow());
      });

  @override
  Future<Map<String, Object?>> readHealth() => _database.readHealth();

  @override
  Future<void> close() => _database.close();
}
