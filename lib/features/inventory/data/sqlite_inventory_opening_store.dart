import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/infrastructure/database/app_database.dart';
import '../../../core/infrastructure/database/schema.dart';
import '../../workspace/domain/business_profile.dart';
import '../domain/inventory_opening.dart';
import '../domain/reference_inventory.dart';

/// One declared opening establishes stock and equity without a purchase, debt,
/// payment or cash movement. Source IDs remain separate from operational IDs.
class SqliteInventoryOpeningStore {
  SqliteInventoryOpeningStore(this._database, {this.synthetic = false});
  final AppDatabase _database;
  final bool synthetic;
  static const _operator = 'system:local-operator';
  static const _inventory = 'system:inventory';
  static const _equity = 'system:opening-equity';

  Future<InventoryOpeningResult> open(
    InventoryOpeningCommand command, {
    BusinessProfile? initialProfile,
  }) async {
    _validateCommand(command);
    return _database.database.transaction((txn) async {
      final profile = await _profile(txn, initialProfile);
      final rows = command.reference.products.toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      final prepared = <_OpeningProduct>[];
      var total = BigInt.zero;
      for (final row in rows) {
        _text(row.name, 'Nombre de producto');
        if (row.supplier.trim().isNotEmpty) {
          _text(row.supplier, 'Nombre de proveedor');
        }
        final category = _category(row.category);
        final price = _scale(row.priceMinor, profile.moneyScale);
        final cost = _scale(row.purchasePriceMinor, profile.moneyScale);
        if (cost == 0 && !command.zeroCostsConfirmed) {
          throw const InventoryOpeningValidationException(
            'Confirma expresamente los productos cuyo costo de compra es cero.',
          );
        }
        final lineTotal = BigInt.from(row.quantity) * BigInt.from(cost);
        _integer(lineTotal, 'Costo total del producto');
        total += lineTotal;
        _integer(total, 'Costo total de la apertura');
        prepared.add(
          _OpeningProduct(row, category, price, cost, lineTotal.toInt()),
        );
      }
      final canonical = _canonical(command, profile, rows);
      final prior = await txn.query(
        'command_log',
        where: 'id=?',
        whereArgs: [command.commandId],
      );
      if (prior.isNotEmpty) {
        final stored = prior.single;
        if (stored['command_type'] != 'inventory_opening' ||
            stored['response_version'] != 1 ||
            stored['payload_hash'] != DatabaseSchema.checksum(canonical)) {
          throw const InventoryOpeningValidationException(
            'El identificador ya corresponde a otra operación o contenido.',
          );
        }
        final response = jsonDecode(stored['response_json'] as String);
        if (response is! Map || response['canonicalPayload'] != canonical) {
          throw const InventoryOpeningValidationException(
            'El identificador ya corresponde a otra operación o contenido.',
          );
        }
        return _result(response['result']);
      }
      await _unusedCommand(txn, command.commandId);
      if ((await txn.query(
        'inventory_openings',
        columns: ['document_id'],
      )).isNotEmpty) {
        throw const InventoryOpeningValidationException(
          'Este perfil ya tiene una apertura de inventario.',
        );
      }
      for (final table in [
        'catalog_items',
        'business_documents',
        'inventory_movements',
        'sales',
        'purchases',
        'obligations',
        'quick_sales_accounts',
        'cost_layers',
        'command_log',
        'sale_confirmations',
        'collection_requests',
        'supplier_payment_requests',
        'quick_sale_requests',
        'paid_purchase_requests',
      ]) {
        if ((await txn.query(table, limit: 1)).isNotEmpty) {
          throw const InventoryOpeningValidationException(
            'La apertura requiere un perfil limpio, sin catálogo ni operaciones previas.',
          );
        }
      }
      final now = DateTime.now().toUtc().toIso8601String();
      await _systemRows(txn, now);
      final documentId =
          'inventory-opening:${command.snapshotSha256.toLowerCase()}';
      final entryId = 'opening-entry:${command.snapshotSha256.toLowerCase()}';
      final productIds = <String, String>{
        for (final row in prepared.indexed)
          row.$2.source.id:
              'opening-product:${command.snapshotSha256.toLowerCase()}:${row.$1}',
      };
      final result = InventoryOpeningResult(
        documentId: documentId,
        commandId: command.commandId,
        productCount: prepared.length,
        totalUnits: command.reference.totalUnits,
        totalCostMinor: total.toInt(),
        productIdsBySourceId: productIds,
      );
      await txn.insert('command_log', {
        'id': command.commandId,
        'command_type': 'inventory_opening',
        'payload_hash': DatabaseSchema.checksum(canonical),
        'actor_id': _operator,
        'response_json': jsonEncode({
          'canonicalPayload': canonical,
          'result': _resultJson(result),
        }),
        'response_version': 1,
        'committed_at_utc': now,
        'authorization_policy_version': 'development-single-user-v1',
      });
      final occurred = command.occurredAtUtc.toIso8601String();
      final date = command.occurredAtUtc.subtract(const Duration(hours: 5));
      await txn.insert('business_documents', {
        'id': documentId,
        'command_id': command.commandId,
        'command_sequence': 0,
        'profile_id': profile.profileId,
        'actor_id': _operator,
        'type': 'inventory_opening',
        'status': 'draft',
        'occurred_at_utc': occurred,
        'business_date':
            '${date.year.toString().padLeft(4, '0')}-'
            '${date.month.toString().padLeft(2, '0')}-'
            '${date.day.toString().padLeft(2, '0')}',
        'recorded_at_utc': now,
        'reason': 'Inventario inicial desde copia verificada',
        'source_kind': synthetic ? 'synthetic' : 'legacy',
        'date_quality': 'reconstructed',
      });
      await txn.insert('inventory_openings', {
        'document_id': documentId,
        'command_id': command.commandId,
        'profile_id': profile.profileId,
        'source_name': command.reference.sourceName,
        'source_sha256': command.reference.sourceSha256.toLowerCase(),
        'snapshot_sha256': command.snapshotSha256.toLowerCase(),
        'occurred_at_utc': occurred,
        'total_cost_minor': total.toInt(),
      });
      final categories = <String, String>{};
      final suppliers = <String, String>{};
      for (final row in prepared.indexed) {
        final item = row.$2;
        final source = item.source;
        final categoryId =
            categories[item.category] ?? await _categoryId(txn, item.category);
        categories[item.category] = categoryId;
        final supplierName = source.supplier.trim();
        String? supplierId;
        if (supplierName.isNotEmpty) {
          supplierId = suppliers[supplierName];
          if (supplierId == null) {
            supplierId =
                'opening-supplier:${command.snapshotSha256.toLowerCase()}:${suppliers.length}';
            await txn.insert('counterparties', {
              'id': supplierId,
              'name': supplierName,
              'is_customer': 0,
              'is_supplier': 1,
              'is_active': 1,
            });
            suppliers[supplierName] = supplierId;
          }
        }
        final productId = productIds[source.id]!;
        await txn.insert('catalog_items', {
          'id': productId,
          'sku': null,
          'name': source.name.trim(),
          'kind': 'product',
          'category_id': categoryId,
          'unit_code': 'unit',
          'quantity_scale': 0,
          'list_price_minor': item.price,
          'is_active': 1,
        });
        await txn.insert('inventory_opening_items', {
          'id':
              'opening-item:${command.snapshotSha256.toLowerCase()}:${row.$1}',
          'opening_id': documentId,
          'sequence': row.$1,
          'source_product_id': source.id,
          'product_id': productId,
          'name_snapshot': source.name.trim(),
          'category_id': categoryId,
          'supplier_id': supplierId,
          'unit_price_minor': item.price,
          'unit_cost_minor': item.cost,
          'quantity': source.quantity,
          'total_cost_minor': item.total,
          'zero_cost_confirmed': item.cost == 0 && command.zeroCostsConfirmed
              ? 1
              : 0,
        });
      }
      await txn.insert('journal_entries', {
        'id': entryId,
        'document_id': documentId,
        'status': 'draft',
        'cost_completeness': 'complete',
      });
      if (total > BigInt.zero) {
        for (final line in [
          (_inventory, total.toInt(), 0),
          (_equity, 0, total.toInt()),
        ].indexed) {
          await txn.insert('journal_lines', {
            'id': '$entryId:${line.$1}',
            'entry_id': entryId,
            'sequence': line.$1,
            'account_id': line.$2.$1,
            'debit_minor': line.$2.$2,
            'credit_minor': line.$2.$3,
          });
        }
      }
      await txn.update(
        'business_documents',
        {'status': 'posted'},
        where: 'id=?',
        whereArgs: [documentId],
      );
      await txn.update(
        'journal_entries',
        {'status': 'posted', 'posted_at_utc': now},
        where: 'id=?',
        whereArgs: [entryId],
      );
      return result;
    }, exclusive: true);
  }

  static void _validateCommand(InventoryOpeningCommand command) {
    if (!RegExp(r'^[A-Za-z0-9:_-]{1,128}$').hasMatch(command.commandId) ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(command.snapshotSha256)) {
      throw const InventoryOpeningValidationException(
        'Identificador o huella de snapshot no válido.',
      );
    }
    final date = command.occurredAtUtc;
    final bogota = date.subtract(const Duration(hours: 5));
    if (!date.isUtc ||
        date.year < 1 ||
        date.year > 9999 ||
        bogota.year < 1 ||
        bogota.year > 9999) {
      throw const InventoryOpeningValidationException(
        'La fecha de apertura debe ser UTC y estar dentro del rango permitido.',
      );
    }
    if (command.reference.products.isEmpty) {
      throw const InventoryOpeningValidationException(
        'La copia no contiene productos para abrir el inventario.',
      );
    }
  }

  static Future<BusinessProfile> _profile(
    DatabaseExecutor txn,
    BusinessProfile? initial,
  ) async {
    var rows = await txn.query('app_profile', where: 'id=1');
    if (rows.isEmpty && initial != null) {
      await txn.insert('app_profile', initial.toRow());
      rows = await txn.query('app_profile', where: 'id=1');
    }
    if (rows.length != 1) {
      throw const InventoryOpeningValidationException(
        'Configura el perfil antes de abrir el inventario.',
      );
    }
    final profile = BusinessProfile.fromRow(rows.single);
    if (profile.currencyCode != 'COP' ||
        profile.timezone != 'America/Bogota' ||
        (initial != null &&
            (profile.profileId != initial.profileId ||
                profile.businessName != initial.businessName ||
                profile.moneyScale != initial.moneyScale ||
                profile.currencyCode != initial.currencyCode ||
                profile.timezone != initial.timezone))) {
      throw const InventoryOpeningValidationException(
        'La configuración del perfil no coincide con la apertura solicitada.',
      );
    }
    return profile;
  }

  String _canonical(
    InventoryOpeningCommand command,
    BusinessProfile profile,
    List<ReferenceInventoryProduct> rows,
  ) => jsonEncode({
    'version': 1,
    'commandId': command.commandId,
    'profile': profile.toRow(),
    'synthetic': synthetic,
    'snapshotSha256': command.snapshotSha256.toLowerCase(),
    'occurredAtUtc': command.occurredAtUtc.toIso8601String(),
    'zeroCostsConfirmed': command.zeroCostsConfirmed,
    'reference': {
      'sourceName': command.reference.sourceName,
      'sourceSha256': command.reference.sourceSha256.toLowerCase(),
      'capturedAtUtc': command.reference.capturedAtUtc.toIso8601String(),
      'currencyCode': command.reference.currencyCode,
      'moneyScale': command.reference.moneyScale,
      'products': [
        for (final row in rows)
          {
            'id': row.id,
            'name': row.name,
            'quantity': row.quantity,
            'priceMinor': row.priceMinor,
            'purchasePriceMinor': row.purchasePriceMinor,
            'lot': row.lot,
            'category': row.category,
            'supplier': row.supplier,
          },
      ],
    },
  });

  static int _scale(int minor, int targetScale) {
    var value = BigInt.from(minor);
    if (targetScale >= 2) {
      value *= BigInt.from(10).pow(targetScale - 2);
    } else {
      final divisor = BigInt.from(10).pow(2 - targetScale);
      if (value % divisor != BigInt.zero) {
        throw const InventoryOpeningValidationException(
          'Un precio o costo tiene decimales que el perfil no admite; no se redondeó.',
        );
      }
      value ~/= divisor;
    }
    return _integer(value, 'Precio o costo');
  }

  static int _integer(BigInt value, String field) {
    if (value < BigInt.zero || value > ReferenceInventory.maxInteger) {
      throw InventoryOpeningValidationException(
        '$field excede el rango entero permitido.',
      );
    }
    return value.toInt();
  }

  static void _text(String value, String label) {
    if (value.trim().isEmpty ||
        value.trim().length > 120 ||
        RegExp(r'[\x00-\x1f]').hasMatch(value)) {
      throw InventoryOpeningValidationException(
        '$label admite entre 1 y 120 caracteres sin controles.',
      );
    }
  }

  static String _category(String value) => switch (value.trim().toLowerCase()) {
    'producto' ||
    'artículo' ||
    'articulo' ||
    'artículos' ||
    'articulos' => 'Artículo',
    'comestible' || 'comestibles' => 'Comestible',
    'evento' || 'eventos' => 'Evento',
    'pasadía' || 'pasadia' || 'pasadías' || 'pasadias' => 'Pasadía',
    _ => throw const InventoryOpeningValidationException(
      'La copia contiene una categoría desconocida; corrígela antes de abrir inventario.',
    ),
  };

  static Future<String> _categoryId(DatabaseExecutor txn, String name) async {
    final rows = await txn.query(
      'categories',
      where: 'name=? AND is_active=1',
      whereArgs: [name],
      orderBy: 'id',
    );
    if (rows.isNotEmpty) return rows.first['id'] as String;
    final id =
        'opening-category:${name == 'Artículo'
            ? 'article'
            : name == 'Comestible'
            ? 'food'
            : name == 'Pasadía'
            ? 'day-pass'
            : 'event'}';
    await txn.insert('categories', {'id': id, 'name': name, 'is_active': 1});
    return id;
  }

  static Future<void> _unusedCommand(
    DatabaseExecutor txn,
    String commandId,
  ) async {
    for (final table in [
      'sale_confirmations',
      'collection_requests',
      'supplier_payment_requests',
    ]) {
      if ((await txn.query(
        table,
        where: 'command_id=?',
        whereArgs: [commandId],
        limit: 1,
      )).isNotEmpty) {
        throw const InventoryOpeningValidationException(
          'El identificador está reservado para otra operación.',
        );
      }
    }
    for (final spec in [
      ('quick_sale_requests', 'sale_command_id', 'collection_command_id'),
      ('paid_purchase_requests', 'purchase_command_id', 'payment_command_id'),
    ]) {
      if ((await txn.rawQuery(
        'SELECT command_id FROM ${spec.$1} WHERE command_id=? OR ${spec.$2}=? OR ${spec.$3}=?',
        [commandId, commandId, commandId],
      )).isNotEmpty) {
        throw const InventoryOpeningValidationException(
          'El identificador está reservado para otra operación.',
        );
      }
    }
  }

  static Future<void> _systemRows(DatabaseExecutor txn, String now) async {
    final actors = await txn.query(
      'actors',
      where: 'id=?',
      whereArgs: [_operator],
    );
    if (actors.isEmpty) {
      await txn.insert('actors', {
        'id': _operator,
        'display_name': 'Operador local',
        'kind': 'system',
        'is_active': 1,
        'created_at_utc': now,
      });
    } else if (actors.single['kind'] != 'system' ||
        actors.single['is_active'] != 1) {
      throw const InventoryOpeningValidationException(
        'El operador local no está disponible.',
      );
    }
    for (final account in [
      (_inventory, 'INV', 'Inventario', 'asset', 'inventory'),
      (
        _equity,
        'OPENING-EQUITY',
        'Saldos iniciales declarados',
        'equity',
        'opening_balance',
      ),
    ]) {
      final existing = await txn.query(
        'ledger_accounts',
        where: 'id=?',
        whereArgs: [account.$1],
      );
      if (existing.isEmpty) {
        await txn.insert('ledger_accounts', {
          'id': account.$1,
          'code': account.$2,
          'name': account.$3,
          'class': account.$4,
          'role': account.$5,
          'is_active': 1,
        });
      } else if (existing.single['class'] != account.$4 ||
          existing.single['role'] != account.$5 ||
          existing.single['is_active'] != 1) {
        throw const InventoryOpeningValidationException(
          'Una cuenta interna de la apertura no está disponible.',
        );
      }
    }
  }

  static Map<String, Object?> _resultJson(InventoryOpeningResult result) => {
    'documentId': result.documentId,
    'commandId': result.commandId,
    'productCount': result.productCount,
    'totalUnits': result.totalUnits,
    'totalCostMinor': result.totalCostMinor,
    'productIdsBySourceId': result.productIdsBySourceId,
  };

  static InventoryOpeningResult _result(Object? value) {
    if (value is! Map) {
      throw const InventoryOpeningValidationException(
        'La respuesta guardada de apertura no es válida.',
      );
    }
    return InventoryOpeningResult(
      documentId: value['documentId'] as String,
      commandId: value['commandId'] as String,
      productCount: value['productCount'] as int,
      totalUnits: value['totalUnits'] as int,
      totalCostMinor: value['totalCostMinor'] as int,
      productIdsBySourceId: Map<String, String>.from(
        value['productIdsBySourceId'] as Map,
      ),
    );
  }
}

class _OpeningProduct {
  const _OpeningProduct(
    this.source,
    this.category,
    this.price,
    this.cost,
    this.total,
  );
  final ReferenceInventoryProduct source;
  final String category;
  final int price;
  final int cost;
  final int total;
}
