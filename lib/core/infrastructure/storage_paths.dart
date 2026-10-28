import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_config.dart';

/// Resolved directories for the new application. Resolution never opens a DB.
class StoragePaths {
  const StoragePaths._({
    required this.rootDirectory,
    required this.profileDirectory,
    required this.databasePath,
  });

  final Directory rootDirectory;
  final Directory profileDirectory;
  final String databasePath;

  static final _profilePattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$');
  static final _reservedWindowsName = RegExp(
    r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$',
    caseSensitive: false,
  );

  static Future<StoragePaths> resolve(AppConfig config) async {
    _validateProfile(config.profileId);
    if (config.dataRoot.isEmpty || !p.isAbsolute(config.dataRoot)) {
      throw ArgumentError.value(
        config.dataRoot,
        'dataRoot',
        'An explicit absolute data root is required.',
      );
    }

    final repositoryRoot = p.normalize(AppConfig.repositoryRootPath);
    final root = p.normalize(config.dataRoot);
    final protectedOriginal = p.normalize('C:/proyectos/valinor_ludoteca');
    if (!p.isAbsolute(repositoryRoot) ||
        _isInside(protectedOriginal, repositoryRoot) ||
        _isInside(protectedOriginal, root)) {
      throw ArgumentError.value(
        AppConfig.repositoryRootPath,
        'SANCTUM_WORKSPACE_ROOT',
        'The checkout boundary must be absolute and separate from the original project.',
      );
    }
    final installed = config.environment == AppEnvironment.installed;
    final approvedDocuments = AppConfig.installedDocumentsDirectory;
    if (!_isInside(repositoryRoot, root) &&
        !(installed &&
            approvedDocuments != null &&
            p.equals(root, approvedDocuments))) {
      throw ArgumentError.value(
        config.dataRoot,
        'dataRoot',
        'Use the new repository or the installed app Documents directory.',
      );
    }
    if (p.split(root).any((part) => part.toLowerCase() == 'valinor.db')) {
      throw ArgumentError.value(
        config.dataRoot,
        'dataRoot',
        'The legacy database namespace cannot be used for application data.',
      );
    }

    if (installed && config.profileId != 'valinor') {
      throw ArgumentError('La edición instalada usa el perfil Valinor.');
    }
    final profile = installed ? root : p.join(root, config.profileId);
    final database = p.join(profile, 'sanctum2.sqlite3');

    // Preflight every existing component before creating any directory.
    await _verifyDirectoryChain(repositoryRoot, profile);
    await _verifyDatabasePath(database);

    await Directory(root).create(recursive: true);
    await _verifyDirectoryChain(repositoryRoot, root);
    await Directory(profile).create(recursive: true);
    await _verifyDirectoryChain(repositoryRoot, profile);
    await _verifyDatabasePath(database);

    return StoragePaths._(
      rootDirectory: Directory(root),
      profileDirectory: Directory(profile),
      databasePath: database,
    );
  }

  static void _validateProfile(String profileId) {
    final lower = profileId.toLowerCase();
    if (!_profilePattern.hasMatch(profileId) ||
        _reservedWindowsName.hasMatch(profileId) ||
        lower == 'production' ||
        lower == 'prod') {
      throw ArgumentError.value(
        profileId,
        'profileId',
        'Use a simple development/test profile identifier; production is disabled.',
      );
    }
  }

  static bool _isInside(String boundary, String candidate) =>
      p.equals(boundary, candidate) || p.isWithin(boundary, candidate);

  static Future<void> _verifyDirectoryChain(
    String repositoryRoot,
    String destination,
  ) async {
    // Inspect ancestors as well: a junction at the repository boundary is unsafe.
    final components = p.split(destination);
    var current = components.first;
    for (var index = 0; index < components.length; index++) {
      if (index > 0) current = p.join(current, components[index]);
      final type = await FileSystemEntity.type(current, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw FileSystemException(
          'Links and junctions are not allowed.',
          current,
        );
      }
      if (type == FileSystemEntityType.notFound) continue;
      if (type != FileSystemEntityType.directory) {
        throw FileSystemException(
          'A data path component is not a directory.',
          current,
        );
      }
      final canonical = p.normalize(
        await Directory(current).resolveSymbolicLinks(),
      );
      if (!p.equals(canonical, p.normalize(current))) {
        throw FileSystemException(
          'Aliased data directories are not allowed.',
          current,
        );
      }
      if (_isInside(repositoryRoot, current) &&
          !_isInside(repositoryRoot, canonical)) {
        throw FileSystemException(
          'Data escaped the repository boundary.',
          current,
        );
      }
    }
  }

  static Future<void> _verifyDatabasePath(String database) async {
    final type = await FileSystemEntity.type(database, followLinks: false);
    if (type == FileSystemEntityType.notFound) return;
    if (type != FileSystemEntityType.file) {
      throw FileSystemException(
        'The database must be a regular file, not a link.',
        database,
      );
    }
    final canonical = p.normalize(await File(database).resolveSymbolicLinks());
    if (!p.equals(canonical, p.normalize(database))) {
      throw FileSystemException(
        'An aliased database file is not allowed.',
        database,
      );
    }
  }
}
