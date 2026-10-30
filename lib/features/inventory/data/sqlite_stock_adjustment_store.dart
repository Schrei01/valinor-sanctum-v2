import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../../core/domain/fifo_cost.dart';
import '../../../core/domain/money.dart';
import '../../../core/infrastructure/database/app_database.dart';
import '../../../core/infrastructure/database/schema.dart';
import '../../workspace/domain/business_profile.dart';
import '../domain/inventory_store.dart';
import '../domain/stock_adjustment_store.dart';

class SqliteStockAdjustmentStore implements StockAdjustmentStore {
  SqliteStockAdjustmentStore(this.database, {this.synthetic = false});
  final AppDatabase database;
  final bool synthetic;
  static const _actor = 'system:local-operator';

  @override
  Future<List<StockAdjustmentCommand>> pendingAdjustments() async =>
      (await database.database.query(
            'stock_adjustment_requests',
            where: "status='prepared'",
            orderBy: 'prepared_at_utc,command_id',
          ))
          .map(
            (r) => _decode(
              jsonDecode(r['canonical_payload'] as String)
                  as Map<String, dynamic>,
            ),
          )
          .toList();

  @override
  Future<void> prepareAdjustment(StockAdjustmentCommand command) async {
    _validate(command);
    await database.database.transaction((txn) async {
      final prior = await txn.query(
        'stock_adjustment_requests',
        where: 'command_id=?',
        whereArgs: [command.commandId],
      );
      if (prior.isNotEmpty) {
        final old =
            jsonDecode(prior.single['canonical_payload'] as String)
                as Map<String, dynamic>;
        if (jsonEncode(_input(_decode(old))) != jsonEncode(_input(command)) ||
            prior.single['status'] == 'discarded') {
          throw const StockAdjustmentValidationException(
            'Este identificador pertenece a otro ajuste.',
          );
        }
        return;
      }
      final profile = await _profile(txn), plan = await _plan(txn, command);
      final payload = jsonEncode({
        ..._input(command),
        'profileId': profile.profileId,
        'currency': profile.currencyCode,
        'scale': profile.moneyScale,
        'costMinor': plan.cost,
        'productName': plan.name,
        if (command.isAddition) ...{
          'referenceId': plan.referenceId,
          'referenceSource': plan.referenceSource,
        },
      });
      await txn.insert('stock_adjustment_requests', {
        'command_id': command.commandId,
        'canonical_payload': payload,
        'prepared_at_utc': DateTime.now().toUtc().toIso8601String(),
        'status': 'prepared',
      });
    }, exclusive: true);
  }

  @override
  Future<void> confirmAdjustment(
    String commandId,
  ) => database.database.transaction((txn) async {
    final requests = await txn.query(
      'stock_adjustment_requests',
      where: 'command_id=?',
      whereArgs: [commandId],
    );
    if (requests.length != 1) {
      throw const StockAdjustmentValidationException(
        'No se encontró la solicitud guardada.',
      );
    }
    final request = requests.single,
        canonical = request['canonical_payload'] as String;
    final prior = await txn.query(
      'command_log',
      where: 'id=?',
      whereArgs: [commandId],
    );
    if (prior.isNotEmpty) {
      final response =
          jsonDecode(prior.single['response_json'] as String)
              as Map<String, dynamic>;
      if (prior.single['command_type'] == 'stock_adjustment' &&
          response['canonicalPayload'] == canonical &&
          request['status'] == 'confirmed') {
        return;
      }
      throw const StockAdjustmentValidationException(
        'El identificador ya fue utilizado.',
      );
    }
    if (request['status'] != 'prepared') {
      throw const StockAdjustmentValidationException(
        'La solicitud ya no está pendiente.',
      );
    }
    final payload = jsonDecode(canonical) as Map<String, dynamic>,
        command = _decode(payload);
    final profile = await _profile(txn), plan = await _plan(txn, command);
    if (payload['profileId'] != profile.profileId ||
        payload['currency'] != profile.currencyCode ||
        payload['scale'] != profile.moneyScale ||
        payload['costMinor'] != plan.cost ||
        payload['productName'] != plan.name ||
        (command.isAddition &&
            (payload['referenceId'] != plan.referenceId ||
                payload['referenceSource'] != plan.referenceSource))) {
      throw const StockAdjustmentValidationException(
        'Cambió el producto o su costo. Descarta esta solicitud y revisa el ajuste.',
      );
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final actor = await txn.query('actors', where: 'id=?', whereArgs: [_actor]);
    if (actor.isEmpty) {
      await txn.insert('actors', {
        'id': _actor,
        'display_name': 'Operador local',
        'kind': 'system',
        'is_active': 1,
        'created_at_utc': now,
      });
    } else if (actor.single['is_active'] != 1 ||
        actor.single['kind'] != 'system') {
      throw const StockAdjustmentValidationException(
        'El operador local no está disponible.',
      );
    }
    for (final account in [
      ('system:inventory', 'INV', 'Inventario', 'asset', 'inventory'),
      (
        'inventory:adjustment-expense',
        'INV:ADJUST',
        'Ajustes de inventario',
        'expense',
        'inventory_adjustment',
      ),
    ]) {
      final rows = await txn.query(
        'ledger_accounts',
        where: 'id=? OR code=?',
        whereArgs: [account.$1, account.$2],
      );
      if (rows.isEmpty) {
        await txn.insert('ledger_accounts', {
          'id': account.$1,
          'code': account.$2,
          'name': account.$3,
          'class': account.$4,
          'role': account.$5,
          'is_active': 1,
        });
      } else if (rows.length != 1 ||
          rows.single['id'] != account.$1 ||
          rows.single['class'] != account.$4 ||
          rows.single['role'] != account.$5 ||
          rows.single['is_active'] != 1) {
        throw const StockAdjustmentValidationException(
          'Las cuentas internas de inventario no están disponibles.',
        );
      }
    }
    final document = InventoryIds.next(),
        adjustment = InventoryIds.next(),
        entry = InventoryIds.next();
    await txn.insert('command_log', {
      'id': commandId,
      'command_type': 'stock_adjustment',
      'payload_hash': DatabaseSchema.checksum(canonical),
      'actor_id': _actor,
      'response_json': jsonEncode({
        'canonicalPayload': canonical,
        'documentId': document,
      }),
      'response_version': 1,
      'committed_at_utc': now,
      'authorization_policy_version': 'development-single-user-v1',
    });
    await txn.insert('business_documents', {
      'id': document,
      'command_id': commandId,
      'command_sequence': 0,
      'profile_id': profile.profileId,
      'actor_id': _actor,
      'type': 'stock_adjustment',
      'status': 'draft',
      'occurred_at_utc': command.occurredAtUtc.toIso8601String(),
      'business_date': command.occurredAtUtc
          .subtract(const Duration(hours: 5))
          .toIso8601String()
          .substring(0, 10),
      'recorded_at_utc': now,
      'reason': command.reason,
      'source_kind': synthetic ? 'synthetic' : 'native',
      'date_quality': 'documented',
    });
    if (command.isAddition) {
      await txn.insert('stock_additions', {
        'id': adjustment,
        'document_id': document,
        'product_id': command.productId,
        'name_snapshot': plan.name,
        'quantity': command.quantity,
        'unit_cost_minor': plan.unitCost,
        'cost_minor': plan.cost,
        'reason': command.reason,
        plan.referenceSource == 'purchase'
                ? 'reference_cost_layer_id'
                : 'reference_opening_item_id':
            plan.referenceId,
      });
      final sequence =
          BigInt.from(
            (await txn.rawQuery(
                  'SELECT coalesce(max(stock_sequence),0) n FROM inventory_movements',
                )).single['n']
                as int,
          ) +
          BigInt.one;
      if (sequence > Money.maxMinorUnits) {
        throw const StockAdjustmentValidationException(
          'No se puede asignar otra secuencia de inventario.',
        );
      }
      final movement = InventoryIds.next();
      await txn.insert('inventory_movements', {
        'id': movement,
        'document_id': document,
        'sequence': 0,
        'stock_sequence': sequence.toInt(),
        'product_id': command.productId,
        'kind': 'adjustment',
        'quantity_delta': command.quantity,
        'value_delta_minor': plan.cost,
        'purchase_line_id': null,
        'stock_addition_id': adjustment,
      });
      await txn.insert('cost_layers', {
        'id': InventoryIds.next(),
        'inbound_movement_id': movement,
        'product_id': command.productId,
        'initial_quantity': command.quantity,
        'total_cost_minor': plan.cost,
        'cost_quality': 'documented',
        'fifo_sequence': sequence.toInt(),
        'acquired_at_utc': command.occurredAtUtc.toIso8601String(),
      });
    } else {
      await txn.insert('stock_adjustments', {
        'id': adjustment,
        'document_id': document,
        'product_id': command.productId,
        'name_snapshot': plan.name,
        'quantity': command.quantity,
        'cost_minor': plan.cost,
        'reason': command.reason,
      });
      for (var i = 0; i < plan.allocations.length; i++) {
        final a = plan.allocations[i];
        await txn.insert('stock_adjustment_allocations', {
          'id': InventoryIds.next(),
          'adjustment_id': adjustment,
          'sequence': i,
          a.source == 'purchase' ? 'cost_layer_id' : 'opening_item_id': a.id,
          'quantity': a.quantity,
          'cost_minor': a.cost,
        });
      }
    }
    await txn.insert('journal_entries', {
      'id': entry,
      'document_id': document,
      'status': 'draft',
      'cost_completeness': 'complete',
    });
    final expected = await txn.query(
      'stock_adjustment_expected_journal',
      where: 'document_id=?',
      whereArgs: [document],
    );
    for (var i = 0; i < expected.length; i++) {
      await txn.insert('journal_lines', {
        'id': InventoryIds.next(),
        'entry_id': entry,
        'sequence': i,
        'account_id': expected[i]['account_id'],
        'debit_minor': expected[i]['debit_minor'],
        'credit_minor': expected[i]['credit_minor'],
      });
    }
    await txn.update(
      'business_documents',
      {'status': 'posted'},
      where: 'id=?',
      whereArgs: [document],
    );
    await txn.update(
      'journal_entries',
      {'status': 'posted', 'posted_at_utc': now},
      where: 'id=?',
      whereArgs: [entry],
    );
    await txn.update(
      'stock_adjustment_requests',
      {'status': 'confirmed'},
      where: 'command_id=?',
      whereArgs: [commandId],
    );
  }, exclusive: true);

  @override
  Future<void> discardAdjustment(String commandId) =>
      database.database.transaction((txn) async {
        if ((await txn.query(
          'command_log',
          where: 'id=?',
          whereArgs: [commandId],
        )).isNotEmpty) {
          throw const StockAdjustmentValidationException(
            'El ajuste ya se registró y no se puede descartar.',
          );
        }
        await txn.update(
          'stock_adjustment_requests',
          {'status': 'discarded'},
          where: "command_id=? AND status='prepared'",
          whereArgs: [commandId],
        );
      }, exclusive: true);

  static Future<BusinessProfile> _profile(DatabaseExecutor txn) async {
    final rows = await txn.query('app_profile');
    if (rows.length != 1) {
      throw const StockAdjustmentValidationException(
        'Configura el espacio de trabajo.',
      );
    }
    final p = BusinessProfile.fromRow(rows.single);
    if (p.timezone != 'America/Bogota') {
      throw const StockAdjustmentValidationException(
        'El ajuste requiere horario de Bogotá.',
      );
    }
    return p;
  }

  static Future<_Plan> _plan(
    DatabaseExecutor txn,
    StockAdjustmentCommand c,
  ) async {
    _validate(c);
    final rows = await txn.rawQuery(
      '''SELECT p.name FROM catalog_items p LEFT JOIN categories k ON k.id=p.category_id
 WHERE p.id=?
 AND NOT EXISTS(SELECT 1 FROM events WHERE product_id=p.id) AND NOT EXISTS(SELECT 1 FROM catalog_services WHERE product_id=p.id)''',
      [c.productId],
    );
    if (rows.length != 1) {
      throw const StockAdjustmentValidationException(
        'Selecciona un producto físico con existencias.',
      );
    }
    final later = await txn.rawQuery(
      '''SELECT d.occurred_at_utc FROM business_documents d WHERE d.status='posted' AND d.id IN(
 SELECT purchase_id FROM purchase_lines WHERE product_id=? UNION SELECT sale_id FROM sale_lines WHERE product_id=?
 UNION SELECT event_id FROM event_products WHERE product_id=? UNION SELECT document_id FROM inventory_adjustment_facts WHERE product_id=?)''',
      List.filled(4, c.productId),
    );
    if (later.any(
      (r) => DateTime.parse(
        r['occurred_at_utc'] as String,
      ).isAfter(c.occurredAtUtc),
    )) {
      throw const StockAdjustmentValidationException(
        'El ajuste no puede ser anterior a otro movimiento de este producto.',
      );
    }
    if (c.isAddition) {
      return _additionPlan(txn, c, rows.single['name'] as String);
    }
    final layers = await txn.query(
      'inventory_effective_layers',
      where: 'product_id=?',
      whereArgs: [c.productId],
      orderBy: 'fifo_sequence,id',
    );
    var remaining = c.quantity, cost = BigInt.zero;
    final allocations = <_Allocation>[];
    for (final layer in layers) {
      if (DateTime.parse(
        layer['acquired_at_utc'] as String,
      ).isAfter(c.occurredAtUtc)) {
        continue;
      }
      final source = layer['source_kind'] as String, id = layer['id'] as String;
      final used = (await txn.query(
        'inventory_cost_usage',
        where:
            '${source == 'purchase' ? 'cost_layer_id' : 'opening_item_id'}=?',
        whereArgs: [id],
      )).fold(BigInt.zero, (s, r) => s + BigInt.from(r['quantity'] as int)).toInt();
      final available = (layer['initial_quantity'] as int) - used;
      if (available <= 0) continue;
      final quantity = remaining < available ? remaining : available;
      final amount = fifoFrontRemainderCostForRange(
        totalCostMinor: layer['total_cost_minor'] as int,
        totalQuantity: layer['initial_quantity'] as int,
        startInclusive: used,
        endExclusive: used + quantity,
      );
      allocations.add(_Allocation(id, source, quantity, amount));
      cost += BigInt.from(amount);
      remaining -= quantity;
      if (remaining == 0) break;
    }
    if (remaining != 0) {
      throw const StockAdjustmentValidationException(
        'No hay suficientes unidades. Actualiza el catálogo y revisa la cantidad.',
      );
    }
    if (cost > Money.maxMinorUnits) {
      throw const StockAdjustmentValidationException(
        'El costo del ajuste supera el límite monetario.',
      );
    }
    return _Plan(rows.single['name'] as String, cost.toInt(), allocations);
  }

  static void _validate(StockAdjustmentCommand c) {
    if (c.commandId.trim().isEmpty ||
        c.commandId.length > 128 ||
        c.productId.isEmpty ||
        c.quantity <= 0 ||
        BigInt.from(c.quantity) > Money.maxMinorUnits ||
        c.reason.trim().isEmpty ||
        c.reason.length > 300 ||
        RegExp(r'[\x00-\x1f]').hasMatch(c.reason) ||
        !c.occurredAtUtc.isUtc) {
      throw const StockAdjustmentValidationException(
        'Indica un producto y una cantidad entera positiva para el ajuste.',
      );
    }
  }

  static Map<String, Object?> _input(StockAdjustmentCommand c) => {
    'commandId': c.commandId,
    'productId': c.productId,
    'quantity': c.quantity,
    if (c.isAddition) 'isAddition': true,
    'reason': c.reason,
    'occurredAtUtc': c.occurredAtUtc.toIso8601String(),
  };
  static StockAdjustmentCommand _decode(Map<String, dynamic> j) =>
      StockAdjustmentCommand(
        commandId: j['commandId'] as String,
        productId: j['productId'] as String,
        quantity: j['quantity'] as int,
        isAddition: j['isAddition'] == true,
        reason: j['reason'] as String,
        occurredAtUtc: DateTime.parse(j['occurredAtUtc'] as String),
      );

  static Future<_Plan> _additionPlan(
    DatabaseExecutor txn,
    StockAdjustmentCommand c,
    String name,
  ) async {
    final references = await txn.query(
      'inventory_reference_costs',
      where: 'product_id=?',
      whereArgs: [c.productId],
      orderBy:
          '${DatabaseSchema.utcSortKey('acquired_at_utc')} DESC,fifo_sequence DESC,id DESC',
      limit: 1,
    );
    if (references.isEmpty) {
      throw const StockAdjustmentValidationException(
        'Este producto no tiene un costo registrado. Registra su primer ingreso desde Compras.',
      );
    }
    final reference = references.single;
    if (DateTime.parse(
      reference['acquired_at_utc'] as String,
    ).isAfter(c.occurredAtUtc)) {
      throw const StockAdjustmentValidationException(
        'El ajuste no puede ser anterior al ingreso del producto.',
      );
    }
    final available = await txn.rawQuery(
      '''SELECT layer.initial_quantity,layer.total_cost_minor,
    coalesce((SELECT sum(cost_minor) FROM inventory_cost_usage usage WHERE
    (layer.source_kind='purchase' AND usage.cost_layer_id=layer.id) OR
    (layer.source_kind='opening' AND usage.opening_item_id=layer.id)),0) used_cost,
    coalesce((SELECT sum(quantity) FROM inventory_cost_usage usage WHERE
    (layer.source_kind='purchase' AND usage.cost_layer_id=layer.id) OR
    (layer.source_kind='opening' AND usage.opening_item_id=layer.id)),0) used
    FROM inventory_effective_layers layer WHERE layer.product_id=?''',
      [c.productId],
    );
    final current = available.fold(
      BigInt.zero,
      (n, r) =>
          n +
          BigInt.from(r['initial_quantity'] as int) -
          BigInt.from(r['used'] as int),
    );
    final unitCost = reference['unit_cost_minor'] as int;
    final currentCost = available.fold(
      BigInt.zero,
      (n, r) =>
          n +
          BigInt.from(r['total_cost_minor'] as int) -
          BigInt.from(r['used_cost'] as int),
    );
    final total = BigInt.from(unitCost) * BigInt.from(c.quantity);
    if (current + BigInt.from(c.quantity) > Money.maxMinorUnits ||
        currentCost + total > Money.maxMinorUnits) {
      throw const StockAdjustmentValidationException(
        'La cantidad o su costo superan el límite permitido.',
      );
    }
    return _Plan(
      name,
      total.toInt(),
      const [],
      referenceId: reference['id'] as String,
      referenceSource: reference['source_kind'] as String,
      unitCost: unitCost,
    );
  }
}

class _Plan {
  _Plan(
    this.name,
    this.cost,
    this.allocations, {
    this.referenceId,
    this.referenceSource,
    this.unitCost = 0,
  });
  final String name;
  final int cost;
  final List<_Allocation> allocations;
  final String? referenceId, referenceSource;
  final int unitCost;
}

class _Allocation {
  _Allocation(this.id, this.source, this.quantity, this.cost);
  final String id, source;
  final int quantity, cost;
}
