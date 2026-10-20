import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../domain/reference_inventory.dart';

/// Reads only the extracted inventory JSON. It never opens the source database.
class JsonReferenceInventoryStore implements ReferenceInventoryStore {
  const JsonReferenceInventoryStore(this.path);
  final String path;

  @override
  Future<ReferenceInventory?> load() => _load();

  /// Verifies and parses the same byte buffer before an opening can write data.
  Future<ReferenceInventory?> loadVerified(String expectedSha256) =>
      _load(expectedSha256);

  Future<ReferenceInventory?> _load([String? expectedSha256]) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return null;
    if (type != FileSystemEntityType.file) {
      throw const ReferenceInventoryFormatException(
        'La copia local de inventario debe ser un archivo regular.',
      );
    }
    try {
      final bytes = await File(path).readAsBytes();
      if (expectedSha256 != null &&
          (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(expectedSha256) ||
              sha256.convert(bytes).toString() !=
                  expectedSha256.toLowerCase())) {
        throw const ReferenceInventoryFormatException(
          'La huella del snapshot no coincide con el archivo; no se importó.',
        );
      }
      final json = jsonDecode(utf8.decode(bytes));
      if (json is! Map<String, dynamic> ||
          json['formatVersion'] is! int ||
          (json['formatVersion'] != 1 && json['formatVersion'] != 2) ||
          json['currencyCode'] != 'COP' ||
          json['moneyScale'] is! int ||
          json['moneyScale'] != 2 ||
          json['products'] is! List) {
        throw const ReferenceInventoryFormatException(
          'El formato de la copia local de inventario no es compatible.',
        );
      }
      final captured = DateTime.tryParse(_string(json, 'capturedAtUtc'));
      if (captured == null || !captured.isUtc) {
        throw const ReferenceInventoryFormatException(
          'La fecha de captura de la copia de inventario no es válida.',
        );
      }
      return ReferenceInventory(
        sourceName: _string(json, 'sourceName'),
        sourceSha256: _string(json, 'sourceSha256'),
        capturedAtUtc: captured,
        products: [
          for (final row in json['products'] as List)
            _product(row, json['formatVersion'] as int),
        ],
      );
    } on ReferenceInventoryFormatException {
      rethrow;
    } on FormatException {
      throw const ReferenceInventoryFormatException(
        'La copia local de inventario está dañada; vuelve a extraerla.',
      );
    } on FileSystemException {
      throw const ReferenceInventoryFormatException(
        'No se pudo leer la copia local de inventario. Revisa el archivo.',
      );
    }
  }

  static ReferenceInventoryProduct _product(Object? row, int formatVersion) {
    if (row is! Map<String, dynamic>) {
      throw const ReferenceInventoryFormatException(
        'La copia de inventario contiene un producto inválido.',
      );
    }
    return ReferenceInventoryProduct(
      id: _string(row, 'id'),
      name: _string(row, 'name'),
      quantity: _integer(row, 'quantity'),
      priceMinor: _integer(row, 'priceMinor'),
      purchasePriceMinor: _integer(row, 'purchasePriceMinor'),
      lot: _string(row, 'lot'),
      category: formatVersion == 1 ? '' : _string(row, 'category'),
      supplier: formatVersion == 1 ? '' : _string(row, 'supplier'),
    );
  }

  static String _string(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is! String) {
      throw ReferenceInventoryFormatException(
        'El campo $key de la copia de inventario debe ser texto.',
      );
    }
    return value;
  }

  static int _integer(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is! int) {
      throw ReferenceInventoryFormatException(
        'El campo $key de la copia de inventario debe ser un entero exacto.',
      );
    }
    return value;
  }
}
