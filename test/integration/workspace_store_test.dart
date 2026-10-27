import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/features/workspace/data/sqlite_workspace_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';
import 'package:valinor_sanctum_2/features/workspace/application/workspace_controller.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/workspace_store.dart';

void main() {
  test(
    'new database initializes Valinor once without adding money inventory or business facts',
    () async {
      final root = p.normalize(AppConfig.repositoryRootPath);
      final parent = Directory(
        p.join(root, 'tmp', 'tests', 'automatic-valinor'),
      );
      await parent.create(recursive: true);
      final directory = await parent.createTemp('workspace-');
      final path = p.join(directory.path, 'sanctum2.sqlite3');
      AppDatabase? app;
      WorkspaceController? controller;
      try {
        app = await AppDatabase.open(path: path);
        Future<Map<String, Object?>> businessRows(AppDatabase database) async {
          final tables = await database.database.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name<>'app_profile' ORDER BY name",
          );
          return {
            for (final table in tables)
              table['name'] as String: await database.database.query(
                table['name'] as String,
              ),
          };
        }

        final before = await businessRows(app);
        WorkspaceController bind(AppDatabase database) => WorkspaceController(
          openSession: () async => WorkspaceSession(
            store: SqliteWorkspaceStore(database),
            databasePath: path,
            profileId: 'test',
          ),
        );
        controller = bind(app);
        await controller.initialize();
        expect(controller.state, WorkspaceState.ready);
        expect(controller.profile!.businessName, 'Valinor');
        expect(controller.profile!.currencyCode, 'COP');
        expect(controller.profile!.moneyScale, 0);
        expect(controller.profile!.timezone, 'America/Bogota');
        final originalProfile = (await app.database.query(
          'app_profile',
        )).single;
        expect(await businessRows(app), before);
        await app.close();
        controller.dispose();
        controller = null;
        app = await AppDatabase.open(path: path);
        controller = bind(app);
        await controller.initialize();
        expect(controller.state, WorkspaceState.ready);
        expect(
          (await app.database.query('app_profile')).single,
          originalProfile,
        );
        expect(await businessRows(app), before);
      } finally {
        await app?.close();
        controller?.dispose();
        final canonical = await directory.resolveSymbolicLinks();
        if (!p.isWithin(root, canonical)) {
          throw StateError('Unsafe test cleanup');
        }
        await directory.delete(recursive: true);
      }
    },
  );
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
