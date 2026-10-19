import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/core/infrastructure/storage_paths.dart';

void main() {
  final repository = p.normalize(AppConfig.repositoryRootPath);
  late Directory sandbox;
  var hasSandbox = false;

  setUp(() async {
    hasSandbox = false;
    final protectedOriginal = p.normalize('C:/proyectos/valinor_ludoteca');
    if (!p.isAbsolute(repository) ||
        p.equals(repository, protectedOriginal) ||
        p.isWithin(protectedOriginal, repository)) {
      throw StateError('Refusing filesystem test setup in an unsafe checkout.');
    }
    final temporaryRoot = Directory(p.join(repository, 'tmp'));
    await temporaryRoot.create(recursive: true);
    sandbox = await temporaryRoot.createTemp('storage_paths_test_');
    hasSandbox = true;
  });

  tearDown(() async {
    if (!hasSandbox) return;
    final canonical = p.normalize(await sandbox.resolveSymbolicLinks());
    if (!p.isWithin(p.join(repository, 'tmp'), canonical)) {
      throw StateError('Refusing cleanup outside this test sandbox.');
    }
    await sandbox.delete(recursive: true);
  });

  AppConfig configFor(String root, {String profile = 'unit_test'}) => AppConfig(
    environment: AppEnvironment.test,
    dataRoot: root,
    profileId: profile,
  );

  test(
    'creates only root and profile and returns the exclusive database name',
    () async {
      final root = p.join(sandbox.path, 'nested', 'data');
      final paths = await StoragePaths.resolve(configFor(root));
      expect(paths.rootDirectory.path, root);
      expect(paths.profileDirectory.path, p.join(root, 'unit_test'));
      expect(paths.databasePath, p.join(root, 'unit_test', 'sanctum2.sqlite3'));
      expect(await paths.rootDirectory.exists(), isTrue);
      expect(await paths.profileDirectory.exists(), isTrue);
      expect(await File(paths.databasePath).exists(), isFalse);
    },
  );

  test(
    'existing paths are reusable without modifying a database file',
    () async {
      final root = p.join(sandbox.path, 'data');
      final first = await StoragePaths.resolve(configFor(root));
      final database = File(first.databasePath);
      await database.writeAsString('synthetic sentinel, not a SQLite database');
      final again = await StoragePaths.resolve(configFor(root));
      expect(again.databasePath, first.databasePath);
      expect(
        await database.readAsString(),
        'synthetic sentinel, not a SQLite database',
      );
    },
  );

  test('profile directories are distinct', () async {
    final root = p.join(sandbox.path, 'data');
    final first = await StoragePaths.resolve(
      configFor(root, profile: 'counter_1'),
    );
    final second = await StoragePaths.resolve(
      configFor(root, profile: 'counter_2'),
    );
    expect(first.databasePath, isNot(second.databasePath));
  });

  test('rejects empty, relative, and escaping roots before creation', () async {
    final roots = [
      '',
      'relative/data',
      p.dirname(repository),
      p.join(repository, '..', 'unapproved_project', 'data'),
    ];
    for (final root in roots) {
      await expectLater(
        StoragePaths.resolve(configFor(root)),
        throwsArgumentError,
      );
    }
  });

  test(
    'rejects unsafe, reserved, and production profiles before creating root',
    () async {
      final root = p.join(sandbox.path, 'must_not_be_created');
      for (final profile in [
        '',
        '.',
        '..',
        '../other',
        r'..\other',
        'two words',
        'CON',
        'lpt1',
        'production',
        'PROD',
        List.filled(65, 'a').join(),
      ]) {
        await expectLater(
          StoragePaths.resolve(configFor(root, profile: profile)),
          throwsArgumentError,
        );
      }
      expect(await Directory(root).exists(), isFalse);
    },
  );

  test('rejects the legacy database namespace without opening it', () async {
    final root = p.join(sandbox.path, 'Documents', 'valinor.db');
    await expectLater(
      StoragePaths.resolve(configFor(root)),
      throwsArgumentError,
    );
    expect(await Directory(root).exists(), isFalse);
  });

  test('rejects a file in place of a directory', () async {
    final blocker = File(p.join(sandbox.path, 'blocker'));
    await blocker.writeAsString('synthetic');
    await expectLater(
      StoragePaths.resolve(configFor(p.join(blocker.path, 'data'))),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('rejects a directory in place of the database', () async {
    final root = p.join(sandbox.path, 'data');
    await Directory(
      p.join(root, 'unit_test', 'sanctum2.sqlite3'),
    ).create(recursive: true);
    await expectLater(
      StoragePaths.resolve(configFor(root)),
      throwsA(isA<FileSystemException>()),
    );
  });

  Future<bool> makeTestLink(String alias, String target) async {
    try {
      await Link(alias).create(target);
      return true;
    } on FileSystemException {
      markTestSkipped('This host cannot create the link needed for this test.');
      return false;
    }
  }

  test(
    'rejects a linked data root even when target stays in the sandbox',
    () async {
      final target = await Directory(p.join(sandbox.path, 'target')).create();
      final alias = p.join(sandbox.path, 'alias');
      if (!await makeTestLink(alias, target.path)) return;
      await expectLater(
        StoragePaths.resolve(configFor(alias)),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        await Directory(p.join(target.path, 'unit_test')).exists(),
        isFalse,
      );
    },
  );

  test(
    'rejects a linked profile before creating any data beneath its target',
    () async {
      final root = await Directory(p.join(sandbox.path, 'data')).create();
      final target = await Directory(p.join(sandbox.path, 'target')).create();
      if (!await makeTestLink(p.join(root.path, 'unit_test'), target.path)) {
        return;
      }
      await expectLater(
        StoragePaths.resolve(configFor(root.path)),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        await File(p.join(target.path, 'sanctum2.sqlite3')).exists(),
        isFalse,
      );
    },
  );

  test(
    'rejects a linked database without reading or changing its target',
    () async {
      final root = await Directory(p.join(sandbox.path, 'data')).create();
      await Directory(p.join(root.path, 'unit_test')).create();
      final target = File(p.join(sandbox.path, 'synthetic_target'));
      await target.writeAsString('unchanged');
      final databasePath = p.join(root.path, 'unit_test', 'sanctum2.sqlite3');
      if (!await makeTestLink(databasePath, target.path)) return;
      await expectLater(
        StoragePaths.resolve(configFor(root.path)),
        throwsA(isA<FileSystemException>()),
      );
      expect(await target.readAsString(), 'unchanged');
    },
  );
}
