import 'dart:io';

import 'package:path/path.dart' as p;

enum AppEnvironment { development, test, installed }

/// Development/test remain isolated; installed releases use the user's Documents.
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

  static String? get installedDocumentsDirectory {
    final home = Platform.environment['USERPROFILE'];
    if (home == null || !p.isAbsolute(home)) return null;
    return p.normalize(p.join(home, 'Documents'));
  }

  /// Only this app's database and its migration backups may leave the checkout.
  static bool isInstalledDatabasePath(
    String path, {
    String? documentsDirectory,
  }) {
    final documents = documentsDirectory ?? installedDocumentsDirectory;
    if (documents == null || !p.isAbsolute(documents)) return false;
    final normalized = p.normalize(path);
    return p.equals(normalized, p.join(documents, 'sanctum2.sqlite3')) ||
        (p.equals(
              p.dirname(normalized),
              p.join(documents, 'ValinorSanctum2-backups'),
            ) &&
            RegExp(
              r'^sanctum2\.v\d+\.\d+-[a-f0-9]+\.sqlite3$',
            ).hasMatch(p.basename(normalized)));
  }

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
    String? userProfileDirectory,
  }) {
    final parsedEnvironment = switch (environment) {
      'development' => AppEnvironment.development,
      'test' => AppEnvironment.test,
      'installed' => AppEnvironment.installed,
      _ => throw ArgumentError.value(
        environment,
        'SANCTUM_ENV',
        'Use development, test or installed.',
      ),
    };

    if (parsedEnvironment == AppEnvironment.installed) {
      final home = userProfileDirectory ?? Platform.environment['USERPROFILE'];
      if (home == null || !p.isAbsolute(home)) {
        throw StateError(
          'No se pudo localizar la carpeta Documentos del usuario.',
        );
      }
      if (dataRoot.isNotEmpty || profileId != 'development') {
        throw ArgumentError(
          'La edición instalada usa Documentos y el perfil Valinor.',
        );
      }
      return AppConfig(
        environment: parsedEnvironment,
        dataRoot: p.normalize(p.join(home, 'Documents')),
        profileId: 'valinor',
      );
    }

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
