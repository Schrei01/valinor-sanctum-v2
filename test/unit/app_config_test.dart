import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';

void main() {
  final repository = p.normalize(AppConfig.repositoryRootPath);

  test('workspace boundary is selected only by the compile-time define', () {
    const expected = String.fromEnvironment(
      'SANCTUM_WORKSPACE_ROOT',
      defaultValue: r'C:\proyectos\valinor_sanctum_2',
    );
    expect(AppConfig.repositoryRootPath, expected);
  });

  test('explicit configuration preserves environment, root, and profile', () {
    final config = AppConfig(
      environment: AppEnvironment.test,
      dataRoot: p.join(repository, 'tmp', 'config'),
      profileId: 'unit_test',
    );
    expect(config.environment, AppEnvironment.test);
    expect(config.profileId, 'unit_test');
    expect(p.isAbsolute(config.dataRoot), isTrue);
  });

  test(
    'default does not depend on working directory or external tool location',
    () {
      final config = AppConfig.fromDefines(
        executablePath: p.join(p.dirname(repository), 'toolchain', 'dart.exe'),
      );
      expect(config.environment, AppEnvironment.development);
      expect(config.profileId, 'development');
      expect(config.dataRoot, p.join(repository, 'data', 'development'));
    },
  );

  test(
    'packaged development executable stores data beside its build output',
    () {
      final executable = p.join(
        repository,
        'build',
        'windows',
        'runner',
        'Debug',
        'app.exe',
      );
      final config = AppConfig.fromDefines(executablePath: executable);
      expect(
        config.dataRoot,
        p.join(p.dirname(executable), 'data', 'development'),
      );
    },
  );

  test(
    'tool executables inside the repo do not choose a tool data directory',
    () {
      final config = AppConfig.fromDefines(
        executablePath: p.join(repository, '.tools', 'dart', 'bin', 'dart.exe'),
      );
      expect(config.dataRoot, p.join(repository, 'data', 'development'));
    },
  );

  test('test environment gets a distinct default root', () {
    final config = AppConfig.fromDefines(
      environment: 'test',
      executablePath: p.join(p.dirname(repository), 'tools', 'dart.exe'),
    );
    expect(config.environment, AppEnvironment.test);
    expect(config.dataRoot, p.join(repository, 'data', 'test'));
  });

  test('explicit root and profile are passed to the validating resolver', () {
    final root = p.join(repository, 'tmp', 'custom');
    final config = AppConfig.fromDefines(
      environment: 'test',
      dataRoot: root,
      profileId: 'counter_2',
    );
    expect(config.dataRoot, root);
    expect(config.profileId, 'counter_2');
  });

  test('unknown and production environments are rejected', () {
    for (final environment in ['production', 'prod', '', 'staging']) {
      expect(
        () => AppConfig.fromDefines(environment: environment),
        throwsArgumentError,
      );
    }
  });

  test(
    'installed release uses the current user Documents and fixed Valinor profile',
    () {
      final home = p.join(repository, 'tmp', 'synthetic-user');
      final config = AppConfig.fromDefines(
        environment: 'installed',
        userProfileDirectory: home,
        executablePath: p.join(repository, 'unrelated', 'app.exe'),
      );
      expect(config.environment, AppEnvironment.installed);
      expect(config.dataRoot, p.join(home, 'Documents'));
      expect(config.profileId, 'valinor');
    },
  );

  test(
    'installed release cannot silently redirect storage using development defines',
    () {
      for (final override in [
        () => AppConfig.fromDefines(
          environment: 'installed',
          userProfileDirectory: repository,
          dataRoot: repository,
        ),
        () => AppConfig.fromDefines(
          environment: 'installed',
          userProfileDirectory: repository,
          profileId: 'other',
        ),
      ]) {
        expect(override, throwsArgumentError);
      }
      expect(
        () => AppConfig.fromDefines(
          environment: 'installed',
          userProfileDirectory: 'relative',
        ),
        throwsStateError,
      );
    },
  );

  test(
    'only the installed database and named migration backups are allowed in Documents',
    () {
      final docs = p.join(repository, 'tmp', 'Documents');
      bool allowed(String name) => AppConfig.isInstalledDatabasePath(
        p.join(docs, name),
        documentsDirectory: docs,
      );
      expect(allowed('sanctum2.sqlite3'), isTrue);
      expect(
        allowed(
          p.join('ValinorSanctum2-backups', 'sanctum2.v15.123456-abc.sqlite3'),
        ),
        isTrue,
      );
      for (final name in [
        'valinor.db',
        'other.sqlite3',
        p.join('subdir', 'sanctum2.sqlite3'),
        p.join('ValinorSanctum2-backups', 'other.sqlite3'),
        p.join('..', 'sanctum2.sqlite3'),
      ]) {
        expect(allowed(name), isFalse, reason: name);
      }
    },
  );

  test(
    'compile-time configuration uses only the supported environment factory',
    () {
      const environment = String.fromEnvironment(
        'SANCTUM_ENV',
        defaultValue: 'development',
      );
      if (environment != 'development' && environment != 'test') {
        expect(AppConfig.fromEnvironment, throwsArgumentError);
        return;
      }
      final config = AppConfig.fromEnvironment();
      expect(config.environment.name, environment);
      expect(p.isAbsolute(config.dataRoot), isTrue);
      expect(p.isWithin(repository, p.normalize(config.dataRoot)), isTrue);
    },
  );
}
