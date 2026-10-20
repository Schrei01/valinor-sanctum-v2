/// A local reference, never an operational stock position or saleable product.
class ReferenceInventoryProduct {
  const ReferenceInventoryProduct({
    required this.id,
    required this.name,
    required this.quantity,
    required this.priceMinor,
    required this.purchasePriceMinor,
    this.lot = '',
  });

  final String id;
  final String name;
  final int quantity;
  final int priceMinor;
  final int purchasePriceMinor;
  final String lot;
}

class ReferenceInventory {
  ReferenceInventory({
    required this.sourceName,
    required this.sourceSha256,
    required this.capturedAtUtc,
    required List<ReferenceInventoryProduct> products,
  }) : products = List.unmodifiable(products) {
    if (sourceName.trim().isEmpty ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sourceSha256) ||
        !capturedAtUtc.isUtc) {
      throw const ReferenceInventoryFormatException(
        'Los metadatos de la copia de inventario no son válidos.',
      );
    }
    final ids = <String>{};
    var units = BigInt.zero;
    for (final product in this.products) {
      if (product.id.trim().isEmpty ||
          product.name.trim().isEmpty ||
          !ids.add(product.id)) {
        throw const ReferenceInventoryFormatException(
          'Cada producto de la copia debe tener nombre e identificador único.',
        );
      }
      for (final value in [
        product.quantity,
        product.priceMinor,
        product.purchasePriceMinor,
      ]) {
        if (value < 0 || BigInt.from(value) > maxInteger) {
          throw const ReferenceInventoryFormatException(
            'La copia contiene cantidades o precios fuera del rango permitido.',
          );
        }
      }
      units += BigInt.from(product.quantity);
      if (units > maxInteger) {
        throw const ReferenceInventoryFormatException(
          'El total de unidades de la copia excede el rango permitido.',
        );
      }
    }
    totalUnits = units.toInt();
  }

  static final BigInt maxInteger = (BigInt.one << 63) - BigInt.one;

  final String sourceName;
  final String sourceSha256;
  final DateTime capturedAtUtc;
  final List<ReferenceInventoryProduct> products;
  late final int totalUnits;
  String get currencyCode => 'COP';
  int get moneyScale => 2;
}

abstract interface class ReferenceInventoryStore {
  /// Missing local data returns null. Invalid data must never look like emptiness.
  Future<ReferenceInventory?> load();
}

class ReferenceInventoryFormatException implements Exception {
  const ReferenceInventoryFormatException(this.message);
  final String message;

  @override
  String toString() => message;
}
