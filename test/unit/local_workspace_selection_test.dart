import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/core/infrastructure/local_workspace_selection.dart';

void main() {
  late Directory sandbox;
  late AppConfig base;
  late File selection;

  setUp(() async {
    final root = Directory(p.join(AppConfig.repositoryRootPath, 'tmp'));
    await root.create(recursive: true);
    sandbox = await root.createTemp('local_workspace_');
    base = AppConfig(
      environment: AppEnvironment.development,
      dataRoot: sandbox.path,
      profileId: 'development',
    );
    selection = File(p.join(sandbox.path, 'active-workspace.json'));
  });

  tearDown(() async {
    final resolved = p.normalize(await sandbox.resolveSymbolicLinks());
    if (!p.isWithin(p.join(AppConfig.repositoryRootPath, 'tmp'), resolved)) {
      throw StateError('Cleanup escaped the test workspace.');
    }
    await sandbox.delete(recursive: true);
  });

  test('absent selection keeps the existing workspace', () async {
    expect(await resolveLocalWorkspace(base), same(base));
  });

  test(
    'explicit startup configuration never follows a local selector',
    () async {
      await selection.writeAsString('{broken');
      expect(await resolveLocalWorkspace(base, enabled: false), same(base));
    },
  );

  test(
    'selection opens a separate workspace and preserves prior files',
    () async {
      final old = File(p.join(sandbox.path, 'development', 'sentinel.txt'));
      await old.parent.create(recursive: true);
      await old.writeAsString('previous workspace');
      await selection.writeAsString(
        jsonEncode({'formatVersion': 1, 'profileId': 'inventory_start'}),
      );
      final selected = await resolveLocalWorkspace(base);
      expect(selected.profileId, 'inventory_start');
      expect(selected.dataRoot, base.dataRoot);
      expect(selected.environment, AppEnvironment.development);
      expect(await old.readAsString(), 'previous workspace');
    },
  );

  test(
    'invalid IDs and unsupported formats never fall back silently',
    () async {
      for (final id in ['../outside', 'production', 'prod', 'CON', '']) {
        await selection.writeAsString(
          jsonEncode({'formatVersion': 1, 'profileId': id}),
        );
        await expectLater(resolveLocalWorkspace(base), throwsArgumentError);
      }
      await selection.writeAsString('{broken');
      await expectLater(resolveLocalWorkspace(base), throwsFormatException);
      await selection.writeAsString('{"formatVersion":2,"profileId":"other"}');
      await expectLater(resolveLocalWorkspace(base), throwsFormatException);
    },
  );

  test(
    'test and explicit profile configurations ignore local selection',
    () async {
      await selection.writeAsString('{broken');
      for (final config in [
        AppConfig(
          environment: AppEnvironment.test,
          dataRoot: base.dataRoot,
          profileId: 'development',
        ),
        AppConfig(
          environment: AppEnvironment.development,
          dataRoot: base.dataRoot,
          profileId: 'explicit_profile',
        ),
      ]) {
        expect(await resolveLocalWorkspace(config), same(config));
      }
    },
  );
}
