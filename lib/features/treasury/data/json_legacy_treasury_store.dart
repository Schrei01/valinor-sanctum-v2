import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../domain/legacy_treasury_snapshot.dart';

/// Only opens the private JSON snapshot, never the source SQLite database.
class JsonLegacyTreasuryStore implements LegacyTreasuryStore {
  const JsonLegacyTreasuryStore(this.path, {this.expectedSha256});
  final String path;
  final String? expectedSha256;

  @override
  Future<LegacyTreasurySnapshot?> load() => _load(expectedSha256);

  /// Verification and parsing always use the same bytes.
  Future<LegacyTreasurySnapshot?> loadVerified(String expectedSha256) =>
      _load(expectedSha256);

  Future<LegacyTreasurySnapshot?> _load([String? expectedSha256]) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return null;
    if (type != FileSystemEntityType.file) {
      throw const LegacyTreasuryFormatException(
        'La copia local de tesorería debe ser un archivo regular.',
      );
    }
    try {
      final file = File(path);
      if (await file.length() > 8 * 1024 * 1024) {
        throw const LegacyTreasuryFormatException(
          'La copia de tesorería es demasiado grande.',
        );
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > 8 * 1024 * 1024) {
        throw const LegacyTreasuryFormatException(
          'La copia de tesorería es demasiado grande.',
        );
      }
      if (expectedSha256 != null &&
          (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(expectedSha256) ||
              sha256.convert(bytes).toString() !=
                  expectedSha256.toLowerCase())) {
        throw const LegacyTreasuryFormatException(
          'La huella del snapshot de tesorería no coincide; no se importó.',
        );
      }
      return LegacyTreasurySnapshot.fromJson(jsonDecode(utf8.decode(bytes)));
    } on LegacyTreasuryFormatException {
      rethrow;
    } on FormatException {
      throw const LegacyTreasuryFormatException(
        'La copia local de tesorería está dañada.',
      );
    } on FileSystemException {
      throw const LegacyTreasuryFormatException(
        'No se pudo leer la copia local de tesorería.',
      );
    }
  }
}
