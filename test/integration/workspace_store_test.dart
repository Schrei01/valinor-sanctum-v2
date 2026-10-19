import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/features/workspace/data/sqlite_workspace_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';

void main() {
  test(
    'configuration survives reopen without introducing financial records',
    () async {
      final root = p.normalize(AppConfig.repositoryRootPath);
      final parent = Directory(p.join(root, 'tmp', 'tests', 'workspace'));
      await parent.create(recursive: true);
      final directory = await parent.createTemp('profile_');
      final path = p.join(directory.path, 'sanctum2.sqlite3');
      AppDatabase? openDatabase;
      try {
        openDatabase = await AppDatabase.open(path: path);
        var store = SqliteWorkspaceStore(openDatabase);
        expect(await store.readProfile(), isNull);
        await store.createProfile(
          BusinessProfile(
            profileId: 'test',
            businessName: 'Ludoteca sintética',
            currencyCode: 'COP',
            moneyScale: 2,
            timezone: 'America/Bogota',
            createdAtUtc: DateTime.utc(2026, 1, 1),
          ),
        );
        await expectLater(
          store.createProfile(
            BusinessProfile(
              profileId: 'other',
              businessName: 'Duplicado',
              currencyCode: 'COP',
              moneyScale: 0,
              timezone: 'America/Bogota',
              createdAtUtc: DateTime.utc(2026, 1, 1),
            ),
          ),
          throwsStateError,
        );
        await store.close();
        openDatabase = await AppDatabase.open(path: path);
        store = SqliteWorkspaceStore(openDatabase);
        final profile = await store.readProfile();
        expect(profile!.businessName, 'Ludoteca sintética');
        expect(profile.moneyScale, 2);
        expect((await store.readHealth())['configured'], isTrue);
        for (final table in [
          'actors',
          'business_documents',
          'journal_entries',
          'journal_lines',
          'cash_accounts',
        ]) {
          expect(await openDatabase.database.query(table), isEmpty);
        }
      } finally {
        await openDatabase?.close();
        final canonical = await directory.resolveSymbolicLinks();
        if (!p.isWithin(root, canonical)) {
          throw StateError('Unsafe test cleanup.');
        }
        await directory.delete(recursive: true);
      }
    },
  );
}
