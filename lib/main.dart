import 'dart:async';
import 'package:flutter/material.dart';
import 'app/sanctum_app.dart';
import 'core/infrastructure/app_config.dart';
import 'core/infrastructure/database/app_database.dart';
import 'core/infrastructure/storage_paths.dart';
import 'features/workspace/application/workspace_controller.dart';
import 'features/workspace/data/sqlite_workspace_store.dart';
import 'features/workspace/domain/workspace_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = WorkspaceController(
    openSession: () async {
      final config = AppConfig.fromEnvironment();
      final paths = await StoragePaths.resolve(config);
      final database = await AppDatabase.open(path: paths.databasePath);
      return WorkspaceSession(
        store: SqliteWorkspaceStore(database),
        databasePath: paths.databasePath,
        profileId: config.profileId,
      );
    },
  );
  runApp(SanctumApp(controller: controller));
  unawaited(controller.initialize());
}
