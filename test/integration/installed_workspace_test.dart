import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/core/infrastructure/storage_paths.dart';
import 'package:valinor_sanctum_2/core/infrastructure/local_workspace_selection.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/features/workspace/application/workspace_controller.dart';
import 'package:valinor_sanctum_2/features/workspace/data/sqlite_workspace_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/workspace_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory sandbox;
  setUp(() async {
    final parent = Directory(
      p.join(AppConfig.repositoryRootPath, 'tmp', 'installed-tests'),
    );
    await parent.create(recursive: true);
    sandbox = await parent.createTemp('documents-');
  });
  tearDown(() async {
    final resolved = await sandbox.resolveSymbolicLinks();
    if (!p.isWithin(p.join(AppConfig.repositoryRootPath, 'tmp'), resolved)) {
      throw StateError('Unsafe test cleanup');
    }
    await sandbox.delete(recursive: true);
  });
  AppConfig config() => AppConfig(
    environment: AppEnvironment.installed,
    dataRoot: p.join(sandbox.path, 'Documents'),
    profileId: 'valinor',
  );

  test(
    'installed storage uses Documents directly and ignores development selector',
    () async {
      final c = config();
      final paths = await StoragePaths.resolve(c);
      expect(paths.databasePath, p.join(c.dataRoot, 'sanctum2.sqlite3'));
      expect(paths.profileDirectory.path, c.dataRoot);
      await File(
        p.join(c.dataRoot, 'active-workspace.json'),
      ).writeAsString('broken development selector');
      expect(await resolveLocalWorkspace(c), same(c));
      expect(await File(paths.databasePath).exists(), isFalse);
      expect(await Directory(p.join(c.dataRoot, 'valinor')).exists(), isFalse);
    },
  );

  test(
    'fresh installed database configures Valinor once and reopens without business facts',
    () async {
      final c = config();
      final paths = await StoragePaths.resolve(c);
      Future<WorkspaceSession> session() async => WorkspaceSession(
        store: SqliteWorkspaceStore(
          await AppDatabase.open(path: paths.databasePath),
        ),
        databasePath: paths.databasePath,
        profileId: c.profileId,
      );
      final first = WorkspaceController(openSession: session);
      await first.initialize();
      expect(first.state, WorkspaceState.ready);
      expect(first.profile!.businessName, 'Valinor');
      expect(first.profile!.currencyCode, 'COP');
      expect(first.profile!.moneyScale, 0);
      final original = first.profile!.createdAtUtc;
      first.dispose();
      final second = WorkspaceController(openSession: session);
      await second.initialize();
      expect(second.state, WorkspaceState.ready);
      expect(second.profile!.createdAtUtc, original);
      final db = await AppDatabase.open(path: paths.databasePath);
      try {
        for (final table in [
          'business_documents',
          'sales',
          'purchase_lines',
          'journal_entries',
        ]) {
          expect(await db.database.query(table), isEmpty, reason: table);
        }
        expect((await db.readHealth())['integrityOk'], isTrue);
      } finally {
        second.dispose();
        await db.close();
      }
    },
  );

  test('invalid existing database fails without replacing its bytes', () async {
    final paths = await StoragePaths.resolve(config());
    final f = File(paths.databasePath);
    const sentinel = 'not a database; never replace this file';
    await f.writeAsString(sentinel);
    await expectLater(
      AppDatabase.open(path: paths.databasePath),
      throwsA(anything),
    );
    expect(await f.readAsString(), sentinel);
  });

  test(
    'installed storage rejects other profile IDs and unrelated external roots',
    () async {
      await expectLater(
        StoragePaths.resolve(
          AppConfig(
            environment: AppEnvironment.installed,
            dataRoot: config().dataRoot,
            profileId: 'other',
          ),
        ),
        throwsArgumentError,
      );
      await expectLater(
        StoragePaths.resolve(
          AppConfig(
            environment: AppEnvironment.installed,
            dataRoot: p.join(
              p.dirname(AppConfig.repositoryRootPath),
              'unapproved',
            ),
            profileId: 'valinor',
          ),
        ),
        throwsArgumentError,
      );
    },
  );
}
