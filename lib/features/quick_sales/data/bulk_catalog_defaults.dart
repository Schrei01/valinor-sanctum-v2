import 'package:sqflite_common_ffi/sqflite_ffi.dart';

abstract final class BulkCatalogDefaults {
  static const rentalId = 'rental:sales:games';
  static const products = {
    'bulk:sales:magic': 'Bulk Magic',
    'bulk:sales:pokemon': 'Bulk Pokémon',
    'bulk:sales:yugioh': 'Bulk Yu-Gi-Oh!',
    rentalId: 'Alquiler',
  };
  static Future<void> ensure(Transaction txn) async {
    final categories = await txn.query(
      'categories',
      where: 'is_active=1',
      orderBy: 'id',
    );
    final existing = categories
        .where(
          (row) => [
            'artículo',
            'artículos',
            'articulo',
            'articulos',
          ].contains((row['name'] as String).trim().toLowerCase()),
        )
        .firstOrNull;
    final category = existing?['id'] as String? ?? 'bulk:category:articles';
    if (existing == null) {
      await txn.insert('categories', {
        'id': category,
        'name': 'Artículo',
        'is_active': 1,
      });
    }
    for (final item in products.entries) {
      final prior = await txn.query(
        'catalog_items',
        where: 'id=?',
        whereArgs: [item.key],
      );
      if (prior.isEmpty) {
        await txn.insert('catalog_items', {
          'id': item.key,
          'name': item.value,
          'sku': null,
          'category_id': category,
          'kind': 'product',
          'unit_code': 'unit',
          'quantity_scale': 0,
          'list_price_minor': 0,
          'is_active': 1,
        });
        await txn.insert('catalog_services', {
          'product_id': item.key,
          'kind': 'bulk',
        });
      } else {
        final classification = await txn.query(
          'catalog_services',
          where: "product_id=? AND kind='bulk'",
          whereArgs: [item.key],
        );
        if (classification.length != 1) {
          throw StateError(
            'Identidad de venta variable ocupada por otro producto.',
          );
        }
      }
    }
  }
}
