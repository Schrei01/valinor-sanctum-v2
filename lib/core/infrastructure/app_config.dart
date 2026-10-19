import 'dart:io';

import 'package:path/path.dart' as p;

enum AppEnvironment { development, test }

/// Configuration for the isolated bootstrap. Production is deliberately absent.
class AppConfig {
  const AppConfig({
    required this.environment,
    required this.dataRoot,
    required this.profileId,
  });

  /// The approved checkout boundary, overrideable only at compile time for CI.
  static const repositoryRootPath = String.fromEnvironment(
    'SANCTUM_WORKSPACE_ROOT',
    defaultValue: r'C:\proyectos\valinor_sanctum_2',
  );

  final AppEnvironment environment;
  final String dataRoot;
  final String profileId;

  factory AppConfig.fromEnvironment() => AppConfig.fromDefines(
    environment: const String.fromEnvironment(
      'SANCTUM_ENV',
      defaultValue: 'development',
    ),
    dataRoot: const String.fromEnvironment(
      'SANCTUM_DATA_ROOT',
      defaultValue: '',
    ),
    profileId: const String.fromEnvironment(
      'SANCTUM_PROFILE',
      defaultValue: 'development',
    ),
  );

  /// A deterministic counterpart to compile-time defines, also used by tests.
  /// It neither reads the working directory nor accesses the filesystem.
  factory AppConfig.fromDefines({
    String environment = 'development',
    String dataRoot = '',
    String profileId = 'development',
    String? executablePath,
  }) {
    final parsedEnvironment = switch (environment) {
      'development' => AppEnvironment.development,
      'test' => AppEnvironment.test,
      _ => throw ArgumentError.value(
        environment,
        'SANCTUM_ENV',
        'Only development and test are enabled.',
      ),
    };

    if (dataRoot.isNotEmpty) {
      return AppConfig(
        environment: parsedEnvironment,
        dataRoot: dataRoot,
        profileId: profileId,
      );
    }

    final repositoryRoot = p.normalize(repositoryRootPath);
    final executable = executablePath ?? Platform.resolvedExecutable;
    final executableDirectory = p.dirname(p.normalize(executable));
    final buildDirectory = p.join(repositoryRoot, 'build');
    final useExecutableDirectory =
        p.isAbsolute(executable) &&
        (p.equals(buildDirectory, executableDirectory) ||
            p.isWithin(buildDirectory, executableDirectory));
    final baseDirectory = useExecutableDirectory
        ? executableDirectory
        : repositoryRoot;

    return AppConfig(
      environment: parsedEnvironment,
      dataRoot: p.join(baseDirectory, 'data', parsedEnvironment.name),
      profileId: profileId,
    );
  }
}
