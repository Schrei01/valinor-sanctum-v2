import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_config.dart';
import 'storage_paths.dart';

/// Selects a local development workspace without moving or merging its data.
/// Explicit test and compile-time profile configurations stay isolated.
Future<AppConfig> resolveLocalWorkspace(
  AppConfig base, {
  bool enabled = true,
}) async {
  if (!enabled ||
      base.environment != AppEnvironment.development ||
      base.profileId != 'development') {
    return base;
  }
  final paths = await StoragePaths.resolve(base);
  final path = p.join(paths.rootDirectory.path, 'active-workspace.json');
  final type = await FileSystemEntity.type(path, followLinks: false);
  if (type == FileSystemEntityType.notFound) return base;
  if (type != FileSystemEntityType.file ||
      !p.equals(p.normalize(await File(path).resolveSymbolicLinks()), path)) {
    throw const FormatException('La selección de espacio local no es válida.');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(await File(path).readAsString());
  } on FormatException {
    throw const FormatException('La selección de espacio local está dañada.');
  }
  if (decoded is! Map<String, dynamic> ||
      decoded['formatVersion'] is! int ||
      decoded['formatVersion'] != 1 ||
      decoded['profileId'] is! String) {
    throw const FormatException(
      'La selección de espacio local no es compatible.',
    );
  }
  final selected = AppConfig(
    environment: base.environment,
    dataRoot: base.dataRoot,
    profileId: decoded['profileId'] as String,
  );
  // The same boundary, reserved-name and alias checks apply to the selected ID.
  await StoragePaths.resolve(selected);
  return selected;
}
