import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/domain/fifo_cost.dart';
import '../../../core/domain/money.dart';
import '../../../core/infrastructure/database/app_database.dart';
import '../../../core/infrastructure/database/schema.dart';
import '../../inventory/domain/inventory_store.dart';
import '../../workspace/domain/business_profile.dart';
import '../domain/sales_store.dart';

/// Own development storage. Drafts are editable, never reservations. Prepared
/// commands persist their exact input before the atomic commercial transaction.
class SqliteSalesStore implements SalesStore {
  SqliteSalesStore(this._database, {this.synthetic = false});
  final AppDatabase _database;
  final bool synthetic;
  static const _operator = 'system:local-operator';
  static const _inventory = 'system:inventory';
  static const _receivable = 'system:customer-receivable';
  static const _revenue = 'system:sales-revenue';
  static const _cost = 'system:cost-of-sales';

  @override
  Future<SalesSnapshot> load() => _database.database.transaction((txn) async {
    await _profile(txn);
    final draftRows = await txn.query(
      'sales_drafts',
      where: "status <> 'confirmed'",
      orderBy: 'updated_at_utc DESC, id',
    );
    final drafts = <SaleDraft>[];
    for (final row in draftRows) {
      drafts.add(await _draft(txn, row));
    }
    final confirmations = await txn.query(
      'sale_confirmations',
      where: "status IN ('prepared', 'rejected')",
      orderBy: 'prepared_at_utc, command_id',
    );
    final products = await txn.rawQuery('''
SELECT c.* FROM catalog_items c
LEFT JOIN categories k ON k.id = c.category_id
WHERE c.is_active = 1 AND (c.category_id IS NULL OR k.is_active = 1)
ORDER BY c.name COLLATE NOCASE, c.id
''');
    final layers = await _availableLayers(txn);
    final totals = <String, _Totals>{};
    for (final layer in layers) {
      final total = totals.putIfAbsent(layer.productId, _Totals.new);
      total.quantity += BigInt.from(layer.quantity - layer.used);
      total.cost += BigInt.from(layer.cost - layer.usedCost);
    }
    final salesRows = await txn.rawQuery('''
SELECT s.* FROM sales s
JOIN business_documents d ON d.id = s.document_id AND d.status = 'posted'
JOIN journal_entries e ON e.document_id = d.id AND e.status = 'posted'
ORDER BY s.sold_at_utc DESC, s.document_id
''');
    final sales = <ConfirmedSale>[];
    final settlementRows = await txn.rawQuery('''
SELECT r.origin_document_id, a.amount_minor FROM receivable_settlements a
JOIN customer_receivables r ON r.id = a.receivable_id
JOIN business_documents d ON d.id = a.collection_id AND d.status = 'posted'
JOIN journal_entries j ON j.document_id = d.id AND j.status = 'posted'
''');
    final collectedBySale = <String, BigInt>{};
    for (final row in settlementRows) {
      final saleId = row['origin_document_id'] as String;
      collectedBySale[saleId] =
          (collectedBySale[saleId] ?? BigInt.zero) +
          BigInt.from(row['amount_minor'] as int);
    }
    for (final row in salesRows) {
      final lines = await txn.query(
        'sale_lines',
        where: 'sale_id = ?',
        whereArgs: [row['document_id']],
        orderBy: 'sequence',
      );
      sales.add(
        ConfirmedSale(
          documentId: row['document_id'] as String,
          draftId: row['draft_id'] as String,
          label: row['label_snapshot'] as String,
          customerName: row['customer_name_snapshot'] as String,
          soldAtUtc: DateTime.parse(row['sold_at_utc'] as String).toUtc(),
          dueDate: row['due_date'] as String,
          totalMinor: row['receivable_minor'] as int,
          totalCostMinor: row['total_cost_minor'] as int,
          paidMinor: _int64(
            collectedBySale[row['document_id']] ?? BigInt.zero,
            'Cobros de venta',
          ),
          lines: lines
              .map(
                (line) => ConfirmedSaleLine(
                  productName: line['name_snapshot'] as String,
                  quantity: line['quantity'] as int,
                  unitPriceMinor: line['unit_price_minor'] as int,
                  totalMinor: line['total_minor'] as int,
                  totalCostMinor: line['total_cost_minor'] as int,
                ),
              )
              .toList(),
        ),
      );
    }
    return SalesSnapshot(
      drafts: drafts,
      pendingConfirmations: confirmations.map(_confirmation).toList(),
      sales: sales,
      products: products
          .map(
            (row) => CatalogProduct(
              id: row['id'] as String,
              name: row['name'] as String,
              sku: row['sku'] as String?,
              categoryId: row['category_id'] as String?,
              listPriceMinor: row['list_price_minor'] as int,
            ),
          )
          .toList(),
      stock: totals.entries
          .map(
            (e) => StockPosition(
              productId: e.key,
              quantity: _int64(e.value.quantity, 'Existencias'),
              totalCostMinor: _int64(e.value.cost, 'Costo de existencias'),
            ),
          )
          .toList(),
    );
  });

  @override
  Future<SaleDraft> saveDraft(SaveSaleDraft input) async {
    _id(input.id);
    final label = _text(input.label, 'Nombre de cuenta', 120);
    final customer = _text(input.customerName, 'Cliente', 120);
    if (input.expectedRevision < 0) {
      throw const SalesValidationException('La revisión no es válida.');
    }
    final lines = _lines(input.lines);
    return _database.database.transaction((txn) async {
      final profile = await _profile(txn);
      for (final line in lines) {
        _amount(line.unitPriceMinor, profile, 'Precio');
        _int64(
          BigInt.from(line.quantity) * BigInt.from(line.unitPriceMinor),
          'Total de línea',
        );
      }
      final rows = await txn.query(
        'sales_drafts',
        where: 'id = ?',
        whereArgs: [input.id],
      );
      if (rows.isEmpty && input.expectedRevision != 0) {
        throw const SalesValidationException(
          'La cuenta ya no existe. Actualiza la vista.',
        );
      }
      if (rows.isNotEmpty) {
        final old = await _draft(txn, rows.single);
        // A response may have been lost after save. Replaying the same intended
        // revision and complete value is safe even after reopening the app.
        if (old.status == 'open' &&
            old.revision == input.expectedRevision + 1 &&
            old.label == label &&
            old.customerName == customer &&
            _sameLines(old.lines, lines)) {
          return old;
        }
        if (old.status != 'open' || old.revision != input.expectedRevision) {
          throw const SalesValidationException(
            'La cuenta cambió o tiene una confirmación pendiente. Actualiza la vista.',
          );
        }
      }
      for (final line in lines) {
        await _activeProduct(txn, line.productId);
      }
      final revision = _int64(
        BigInt.from(input.expectedRevision) + BigInt.one,
        'Revisión',
      );
      final now = DateTime.now().toUtc();
      if (rows.isEmpty) {
        await txn.insert('sales_drafts', {
          'id': input.id,
          'label': label,
          'customer_name': customer,
          'revision': revision,
          'status': 'open',
          'updated_at_utc': now.toIso8601String(),
        });
      } else {
        await txn.update(
          'sales_drafts',
          {
            'label': label,
            'customer_name': customer,
            'revision': revision,
            'updated_at_utc': now.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [input.id],
        );
        await txn.delete(
          'sales_draft_lines',
          where: 'draft_id = ?',
          whereArgs: [input.id],
        );
      }
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];
        await txn.insert('sales_draft_lines', {
          'draft_id': input.id,
          'sequence': index,
          'product_id': line.productId,
          'quantity': line.quantity,
          'unit_price_minor': line.unitPriceMinor,
        });
      }
      return SaleDraft(
        id: input.id,
        label: label,
        customerName: customer,
        revision: revision,
        status: 'open',
        updatedAtUtc: now,
        lines: lines,
      );
    }, exclusive: true);
  }

  @override
  Future<SaleConfirmation> prepareConfirmation({
    required String commandId,
    required String draftId,
    required int expectedRevision,
    required DateTime occurredAtUtc,
    required String dueDate,
  }) async {
    _id(commandId);
    _id(draftId);
    final businessDate = _businessDate(occurredAtUtc);
    _dueDate(dueDate, businessDate);
    return _database.database.transaction((txn) async {
      final profile = await _profile(txn);
      final prior = await txn.query(
        'sale_confirmations',
        where: 'command_id = ?',
        whereArgs: [commandId],
      );
      if (prior.isNotEmpty) {
        final old = prior.single;
        if (old['draft_id'] != draftId ||
            old['draft_revision'] != expectedRevision ||
            old['occurred_at_utc'] != occurredAtUtc.toIso8601String() ||
            old['due_date'] != dueDate) {
          throw const SalesValidationException(
            'El identificador ya corresponde a otra confirmación.',
          );
        }
        return _confirmation(old);
      }
      if ((await txn.query(
        'command_log',
        where: 'id = ?',
        whereArgs: [commandId],
      )).isNotEmpty) {
        throw const SalesValidationException(
          'El identificador ya corresponde a otro comando.',
        );
      }
      if ((await txn.query(
        'collection_requests',
        columns: ['command_id'],
        where: 'command_id = ?',
        whereArgs: [commandId],
      )).isNotEmpty) {
        throw const SalesValidationException(
          'El identificador ya corresponde a una solicitud de cobro.',
        );
      }
      final rows = await txn.query(
        'sales_drafts',
        where: 'id = ?',
        whereArgs: [draftId],
      );
      if (rows.isEmpty) {
        throw const SalesValidationException('La cuenta no existe.');
      }
      final draft = await _draft(txn, rows.single);
      if (draft.status != 'open' || draft.revision != expectedRevision) {
        throw const SalesValidationException(
          'La cuenta cambió o tiene una confirmación pendiente. Actualiza la vista.',
        );
      }
      _saleTotal(draft.lines, profile);
      final now = DateTime.now().toUtc();
      final canonical = _payload(profile, draft, occurredAtUtc, dueDate);
      await txn.insert('sale_confirmations', {
        'command_id': commandId,
        'draft_id': draftId,
        'draft_revision': expectedRevision,
        'canonical_payload': canonical,
        'occurred_at_utc': occurredAtUtc.toIso8601String(),
        'due_date': dueDate,
        'prepared_at_utc': now.toIso8601String(),
        'status': 'prepared',
      });
      await txn.update(
        'sales_drafts',
        {'status': 'prepared', 'updated_at_utc': now.toIso8601String()},
        where: 'id = ?',
        whereArgs: [draftId],
      );
      return SaleConfirmation(
        commandId: commandId,
        draftId: draftId,
        draftRevision: expectedRevision,
        occurredAtUtc: occurredAtUtc,
        dueDate: dueDate,
        preparedAtUtc: now,
        status: 'prepared',
      );
    }, exclusive: true);
  }

  @override
  Future<SaleResult> confirmPrepared(String commandId) async {
    _id(commandId);
    try {
      return await _database.database.transaction(
        (txn) => _confirm(txn, commandId),
        exclusive: true,
      );
    } on SalesValidationException {
      // This exception is only raised before committing. Record a recoverable
      // deterministic rejection after rollback; unknown exceptions keep locks.
      await _database.database.transaction((txn) async {
        final committed = await txn.query(
          'command_log',
          where: 'id = ?',
          whereArgs: [commandId],
        );
        if (committed.isEmpty) {
          await txn.update(
            'sale_confirmations',
            {
              'status': 'rejected',
              'rejection_reason':
                  'La confirmación fue rechazada sin registrar una venta.',
            },
            where: "command_id = ? AND status = 'prepared'",
            whereArgs: [commandId],
          );
        }
      }, exclusive: true);
      rethrow;
    }
  }

  Future<SaleResult> _confirm(Transaction txn, String commandId) async {
    final rows = await txn.query(
      'sale_confirmations',
      where: 'command_id = ?',
      whereArgs: [commandId],
    );
    if (rows.isEmpty) {
      throw const SalesValidationException(
        'No existe la confirmación pendiente.',
      );
    }
    final confirmation = rows.single;
    final canonical = confirmation['canonical_payload'] as String;
    final prior = await txn.query(
      'command_log',
      where: 'id = ?',
      whereArgs: [commandId],
    );
    if (prior.isNotEmpty) return _priorResult(prior.single, canonical);
    if (confirmation['status'] != 'prepared') {
      throw const SalesValidationException(
        'Esta confirmación fue rechazada o descartada. Libera la cuenta antes de editarla.',
      );
    }
    final profile = await _profile(txn);
    final draftRows = await txn.query(
      'sales_drafts',
      where: 'id = ?',
      whereArgs: [confirmation['draft_id']],
    );
    if (draftRows.isEmpty) {
      throw const SalesValidationException('La cuenta no existe.');
    }
    final draft = await _draft(txn, draftRows.single);
    final occurredAt = DateTime.parse(
      confirmation['occurred_at_utc'] as String,
    ).toUtc();
    final dueDate = confirmation['due_date'] as String;
    if (draft.status != 'prepared' ||
        draft.revision != confirmation['draft_revision'] ||
        _payload(profile, draft, occurredAt, dueDate) != canonical) {
      throw const SalesValidationException(
        'La cuenta no coincide con la confirmación guardada.',
      );
    }
    final total = _saleTotal(draft.lines, profile);
    final layers = await _availableLayers(txn);
    final planned = <_PlannedLine>[];
    var totalCost = BigInt.zero;
    for (final line in draft.lines) {
      final product = await _activeProduct(txn, line.productId);
      final laterSales = await txn.rawQuery(
        '''
SELECT s.sold_at_utc FROM sales s
JOIN sale_lines l ON l.sale_id = s.document_id
JOIN business_documents d ON d.id = s.document_id AND d.status = 'posted'
JOIN journal_entries e ON e.document_id = d.id AND e.status = 'posted'
WHERE l.product_id = ?
''',
        [line.productId],
      );
      if (laterSales.any(
        (row) =>
            DateTime.parse(row['sold_at_utc'] as String).isAfter(occurredAt),
      )) {
        throw const SalesValidationException(
          'La fecha de venta es anterior a otra venta confirmada del mismo producto. Prepara una nueva confirmación.',
        );
      }
      var remaining = line.quantity;
      final allocations = <_Allocation>[];
      var cost = BigInt.zero;
      for (final layer in layers.where(
        (layer) =>
            layer.productId == line.productId &&
            !layer.acquiredAt.isAfter(occurredAt),
      )) {
        final available = layer.quantity - layer.used;
        if (available == 0) continue;
        final quantity = remaining < available ? remaining : available;
        final amount = fifoFrontRemainderCostForRange(
          totalCostMinor: layer.cost,
          totalQuantity: layer.quantity,
          startInclusive: layer.used,
          endExclusive: layer.used + quantity,
        );
        allocations.add(_Allocation(layer.id, quantity, amount));
        cost += BigInt.from(amount);
        remaining -= quantity;
        if (remaining == 0) break;
      }
      if (remaining != 0) {
        throw SalesValidationException(
          'Existencias insuficientes de ${product['name']}. La cuenta sigue guardada.',
        );
      }
      totalCost += cost;
      planned.add(
        _PlannedLine(
          line,
          product['name'] as String,
          _int64(cost, 'Costo de línea'),
          allocations,
        ),
      );
    }
    final costMinor = _int64(totalCost, 'Costo de venta');
    _int64(BigInt.from(total) + totalCost, 'Total del asiento');
    final now = DateTime.now().toUtc().toIso8601String();
    await _systemRows(txn, now);
    final document = InventoryIds.next();
    final entry = InventoryIds.next();
    final result = SaleResult(
      documentId: document,
      commandId: commandId,
      totalMinor: total,
      totalCostMinor: costMinor,
    );
    await txn.insert('command_log', {
      'id': commandId,
      'command_type': 'confirm_sale',
      'payload_hash': DatabaseSchema.checksum(canonical),
      'actor_id': _operator,
      'response_json': jsonEncode({
        'canonicalPayload': canonical,
        'result': {
          'documentId': document,
          'commandId': commandId,
          'totalMinor': total,
          'totalCostMinor': costMinor,
        },
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
      'actor_id': _operator,
      'type': 'credit_sale',
      'status': 'draft',
      'occurred_at_utc': occurredAt.toIso8601String(),
      'business_date': _businessDate(occurredAt),
      'recorded_at_utc': now,
      'source_kind': synthetic ? 'synthetic' : 'native',
      'date_quality': 'documented',
    });
    await txn.insert('sales', {
      'document_id': document,
      'draft_id': draft.id,
      'label_snapshot': draft.label,
      'customer_name_snapshot': draft.customerName,
      'sold_at_utc': occurredAt.toIso8601String(),
      'due_date': dueDate,
      'receivable_minor': total,
      'total_cost_minor': costMinor,
      'terms': 'credit',
      'cost_policy': 'fifo-front-remainder-v1',
    });
    await txn.insert('journal_entries', {
      'id': entry,
      'document_id': document,
      'status': 'draft',
      'cost_completeness': 'complete',
    });
    for (var sequence = 0; sequence < planned.length; sequence++) {
      final plan = planned[sequence];
      final line = InventoryIds.next();
      await txn.insert('sale_lines', {
        'id': line,
        'sale_id': document,
        'sequence': sequence,
        'product_id': plan.input.productId,
        'name_snapshot': plan.name,
        'quantity': plan.input.quantity,
        'unit_price_minor': plan.input.unitPriceMinor,
        'total_minor': _int64(
          BigInt.from(plan.input.quantity) *
              BigInt.from(plan.input.unitPriceMinor),
          'Total de línea',
        ),
        'total_cost_minor': plan.cost,
      });
      await txn.insert('sale_outflows', {
        'id': InventoryIds.next(),
        'document_id': document,
        'sequence': sequence,
        'product_id': plan.input.productId,
        'sale_line_id': line,
        'quantity': plan.input.quantity,
        'cost_minor': plan.cost,
      });
      for (
        var allocationSequence = 0;
        allocationSequence < plan.allocations.length;
        allocationSequence++
      ) {
        final allocation = plan.allocations[allocationSequence];
        await txn.insert('sale_cost_allocations', {
          'id': InventoryIds.next(),
          'sale_line_id': line,
          'cost_layer_id': allocation.layerId,
          'sequence': allocationSequence,
          'quantity': allocation.quantity,
          'cost_minor': allocation.cost,
        });
      }
    }
    await txn.insert('customer_receivables', {
      'id': InventoryIds.next(),
      'origin_document_id': document,
      'customer_name_snapshot': draft.customerName,
      'control_account_id': _receivable,
      'initial_minor': total,
      'issued_at_utc': occurredAt.toIso8601String(),
      'due_date': dueDate,
    });
    final journal = [
      (_receivable, total, 0),
      (_revenue, 0, total),
      if (costMinor > 0) ...[(_cost, costMinor, 0), (_inventory, 0, costMinor)],
    ];
    for (var sequence = 0; sequence < journal.length; sequence++) {
      final (account, debit, credit) = journal[sequence];
      await txn.insert('journal_lines', {
        'id': InventoryIds.next(),
        'entry_id': entry,
        'sequence': sequence,
        'account_id': account,
        'debit_minor': debit,
        'credit_minor': credit,
      });
    }
    await txn.update(
      'business_documents',
      {'status': 'posted'},
      where: 'id = ?',
      whereArgs: [document],
    );
    await txn.update(
      'journal_entries',
      {'status': 'posted', 'posted_at_utc': now},
      where: 'id = ?',
      whereArgs: [entry],
    );
    await txn.update(
      'sale_confirmations',
      {'status': 'confirmed'},
      where: 'command_id = ?',
      whereArgs: [commandId],
    );
    await txn.update(
      'sales_drafts',
      {
        'status': 'confirmed',
        'confirmed_document_id': document,
        'updated_at_utc': now,
      },
      where: 'id = ?',
      whereArgs: [draft.id],
    );
    return result;
  }

  @override
  Future<void> discardRejected(String commandId) async {
    _id(commandId);
    await _database.database.transaction((txn) async {
      final rows = await txn.query(
        'sale_confirmations',
        where: 'command_id = ?',
        whereArgs: [commandId],
      );
      if (rows.isEmpty) {
        throw const SalesValidationException('La confirmación no existe.');
      }
      final row = rows.single;
      if (row['status'] == 'cancelled') return;
      final logged = await txn.query(
        'command_log',
        where: 'id = ?',
        whereArgs: [commandId],
      );
      if (row['status'] != 'rejected' || logged.isNotEmpty) {
        throw const SalesValidationException(
          'Primero resuelve la confirmación pendiente. Una venta registrada no se descarta.',
        );
      }
      await txn.update(
        'sale_confirmations',
        {'status': 'cancelled'},
        where: 'command_id = ?',
        whereArgs: [commandId],
      );
      await txn.update(
        'sales_drafts',
        {
          'status': 'open',
          'revision': _int64(
            BigInt.from(row['draft_revision'] as int) + BigInt.one,
            'Revisión',
          ),
          'updated_at_utc': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [row['draft_id']],
      );
    }, exclusive: true);
  }

  static Future<SaleDraft> _draft(
    DatabaseExecutor txn,
    Map<String, Object?> row,
  ) async {
    final lines = await txn.query(
      'sales_draft_lines',
      where: 'draft_id = ?',
      whereArgs: [row['id']],
      orderBy: 'sequence',
    );
    return SaleDraft(
      id: row['id'] as String,
      label: row['label'] as String,
      customerName: row['customer_name'] as String,
      revision: row['revision'] as int,
      status: row['status'] as String,
      updatedAtUtc: DateTime.parse(row['updated_at_utc'] as String).toUtc(),
      confirmedDocumentId: row['confirmed_document_id'] as String?,
      lines: lines
          .map(
            (line) => SaleDraftLine(
              productId: line['product_id'] as String,
              quantity: line['quantity'] as int,
              unitPriceMinor: line['unit_price_minor'] as int,
            ),
          )
          .toList(),
    );
  }

  static SaleConfirmation _confirmation(Map<String, Object?> row) =>
      SaleConfirmation(
        commandId: row['command_id'] as String,
        draftId: row['draft_id'] as String,
        draftRevision: row['draft_revision'] as int,
        occurredAtUtc: DateTime.parse(row['occurred_at_utc'] as String).toUtc(),
        dueDate: row['due_date'] as String,
        preparedAtUtc: DateTime.parse(row['prepared_at_utc'] as String).toUtc(),
        status: row['status'] as String,
      );

  static String _payload(
    BusinessProfile profile,
    SaleDraft draft,
    DateTime occurredAt,
    String dueDate,
  ) => jsonEncode({
    'version': 1,
    'profileId': profile.profileId,
    'currency': profile.currencyCode,
    'scale': profile.moneyScale,
    'draftId': draft.id,
    'draftRevision': draft.revision,
    'label': draft.label,
    'customerName': draft.customerName,
    'occurredAtUtc': occurredAt.toIso8601String(),
    'dueDate': dueDate,
    'costPolicy': 'fifo-front-remainder-v1',
    'lines': draft.lines
        .map(
          (line) => {
            'productId': line.productId,
            'quantity': line.quantity,
            'unitPriceMinor': line.unitPriceMinor,
          },
        )
        .toList(),
  });

  static SaleResult _priorResult(Map<String, Object?> row, String canonical) {
    if (row['command_type'] != 'confirm_sale' ||
        row['response_version'] != 1 ||
        row['payload_hash'] != DatabaseSchema.checksum(canonical)) {
      throw const SalesValidationException(
        'El identificador ya corresponde a otro comando.',
      );
    }
    final stored =
        jsonDecode(row['response_json'] as String) as Map<String, dynamic>;
    if (stored['canonicalPayload'] != canonical) {
      throw const SalesValidationException(
        'El identificador ya corresponde a otro comando.',
      );
    }
    final result = stored['result'] as Map<String, dynamic>;
    return SaleResult(
      documentId: result['documentId'] as String,
      commandId: result['commandId'] as String,
      totalMinor: result['totalMinor'] as int,
      totalCostMinor: result['totalCostMinor'] as int,
    );
  }

  static Future<List<_Layer>> _availableLayers(DatabaseExecutor txn) async {
    final rows = await txn.rawQuery('''
SELECT l.* FROM cost_layers l
JOIN inventory_movements m ON m.id = l.inbound_movement_id
JOIN business_documents d ON d.id = m.document_id AND d.status = 'posted'
JOIN journal_entries e ON e.document_id = d.id AND e.status = 'posted'
ORDER BY l.fifo_sequence
''');
    final allocations = await txn.rawQuery('''
SELECT a.* FROM sale_cost_allocations a
JOIN sale_lines sl ON sl.id = a.sale_line_id
JOIN business_documents d ON d.id = sl.sale_id AND d.status = 'posted'
JOIN journal_entries e ON e.document_id = d.id AND e.status = 'posted'
''');
    final consumed = <String, _Totals>{};
    for (final row in allocations) {
      final total = consumed.putIfAbsent(
        row['cost_layer_id'] as String,
        _Totals.new,
      );
      total.quantity += BigInt.from(row['quantity'] as int);
      total.cost += BigInt.from(row['cost_minor'] as int);
    }
    return rows.map((row) {
      final used = consumed[row['id']] ?? _Totals();
      return _Layer(
        row['id'] as String,
        row['product_id'] as String,
        row['initial_quantity'] as int,
        row['total_cost_minor'] as int,
        _int64(used.quantity, 'Cantidad consumida'),
        _int64(used.cost, 'Costo consumido'),
        DateTime.parse(row['acquired_at_utc'] as String).toUtc(),
      );
    }).toList();
  }

  static Future<Map<String, Object?>> _activeProduct(
    DatabaseExecutor txn,
    String id,
  ) async {
    final rows = await txn.rawQuery(
      '''
SELECT c.*, k.is_active category_active FROM catalog_items c
LEFT JOIN categories k ON k.id = c.category_id WHERE c.id = ?
''',
      [id],
    );
    if (rows.isEmpty ||
        rows.single['is_active'] != 1 ||
        (rows.single['category_id'] != null &&
            rows.single['category_active'] != 1)) {
      throw const SalesValidationException(
        'Todos los productos y sus categorías deben estar activos.',
      );
    }
    return rows.single;
  }

  static Future<BusinessProfile> _profile(DatabaseExecutor txn) async {
    final rows = await txn.query('app_profile', where: 'id = 1');
    if (rows.length != 1) {
      throw const SalesValidationException(
        'Configura el espacio de trabajo primero.',
      );
    }
    final profile = BusinessProfile.fromRow(rows.single);
    if (profile.timezone != 'America/Bogota') {
      throw const SalesValidationException(
        'Las ventas requieren la zona horaria America/Bogota.',
      );
    }
    return profile;
  }

  static List<SaleDraftLine> _lines(List<SaleDraftLine> input) {
    if (input.length > 1000) {
      throw const SalesValidationException(
        'La cuenta permite hasta 1000 productos.',
      );
    }
    final lines = input.toList()
      ..sort((a, b) => a.productId.compareTo(b.productId));
    final seen = <String>{};
    for (final line in lines) {
      _id(line.productId);
      if (!seen.add(line.productId)) {
        throw const SalesValidationException(
          'No repitas productos en la cuenta.',
        );
      }
      if (line.quantity <= 0) {
        throw const SalesValidationException(
          'La cantidad debe ser un entero positivo.',
        );
      }
      _int64(BigInt.from(line.quantity), 'Cantidad');
      _int64(BigInt.from(line.unitPriceMinor), 'Precio');
    }
    return lines;
  }

  static bool _sameLines(List<SaleDraftLine> a, List<SaleDraftLine> b) =>
      a.length == b.length &&
      List.generate(
        a.length,
        (i) =>
            a[i].productId == b[i].productId &&
            a[i].quantity == b[i].quantity &&
            a[i].unitPriceMinor == b[i].unitPriceMinor,
      ).every((same) => same);

  static int _saleTotal(List<SaleDraftLine> input, BusinessProfile profile) {
    final lines = _lines(input);
    if (lines.isEmpty) {
      throw const SalesValidationException(
        'Agrega al menos un producto antes de confirmar.',
      );
    }
    var total = BigInt.zero;
    for (final line in lines) {
      _amount(line.unitPriceMinor, profile, 'Precio');
      total += BigInt.from(line.quantity) * BigInt.from(line.unitPriceMinor);
    }
    final result = _int64(total, 'Total de venta');
    if (result <= 0) {
      throw const SalesValidationException(
        'El total de venta debe ser positivo.',
      );
    }
    return result;
  }

  static Future<void> _systemRows(DatabaseExecutor txn, String now) async {
    final actors = await txn.query(
      'actors',
      where: 'id = ?',
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
      throw const SalesValidationException(
        'El operador local no está disponible.',
      );
    }
    for (final (id, code, name, accountClass, role) in [
      (_inventory, 'INV', 'Inventario', 'asset', 'inventory'),
      (
        _receivable,
        'CXC',
        'Clientes por cobrar',
        'asset',
        'customer_receivable',
      ),
      (_revenue, 'VENTAS', 'Ingresos por ventas', 'revenue', 'sales_revenue'),
      (_cost, 'COSTO', 'Costo de ventas', 'cost', 'cost_of_sales'),
    ]) {
      final rows = await txn.query(
        'ledger_accounts',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isEmpty) {
        await txn.insert('ledger_accounts', {
          'id': id,
          'code': code,
          'name': name,
          'class': accountClass,
          'role': role,
          'is_active': 1,
        });
      } else if (rows.single['role'] != role ||
          rows.single['class'] != accountClass ||
          rows.single['is_active'] != 1) {
        throw const SalesValidationException(
          'Las cuentas internas no están disponibles.',
        );
      }
    }
  }

  static void _id(String value) {
    if (!RegExp(r'^[A-Za-z0-9:_-]{1,128}$').hasMatch(value)) {
      throw const SalesValidationException('El identificador no es válido.');
    }
  }

  static String _text(String value, String label, int maximum) {
    final text = value.trim();
    if (text.isEmpty ||
        text.length > maximum ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(text)) {
      throw SalesValidationException(
        '$label debe tener entre 1 y $maximum caracteres y no contener controles.',
      );
    }
    return text;
  }

  static void _amount(int value, BusinessProfile profile, String label) {
    _int64(BigInt.from(value), label);
    Money.fromMinorUnits(
      value,
      currency: profile.currencyCode,
      scale: profile.moneyScale,
    );
  }

  static int _int64(BigInt value, String label) {
    if (value < BigInt.zero || value > Money.maxMinorUnits) {
      throw SalesValidationException(
        '$label excede el rango entero positivo de 64 bits.',
      );
    }
    return value.toInt();
  }

  static String _date(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static String _businessDate(DateTime value) {
    final local = value.subtract(const Duration(hours: 5));
    if (!value.isUtc ||
        value.year < 1 ||
        value.year > 9999 ||
        local.year < 1 ||
        local.year > 9999) {
      throw const SalesValidationException(
        'La fecha de venta debe ser UTC y estar dentro del rango permitido.',
      );
    }
    return _date(local);
  }

  static void _dueDate(String value, String businessDate) {
    final parsed = RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$').hasMatch(value)
        ? DateTime.tryParse('${value}T00:00:00Z')
        : null;
    if (parsed == null ||
        parsed.year < 1 ||
        _date(parsed) != value ||
        value.compareTo(businessDate) < 0) {
      throw const SalesValidationException(
        'El vencimiento debe ser una fecha real igual o posterior a la venta en Bogotá (AAAA-MM-DD).',
      );
    }
  }
}

class _Totals {
  BigInt quantity = BigInt.zero;
  BigInt cost = BigInt.zero;
}

class _Layer {
  const _Layer(
    this.id,
    this.productId,
    this.quantity,
    this.cost,
    this.used,
    this.usedCost,
    this.acquiredAt,
  );
  final String id;
  final String productId;
  final int quantity;
  final int cost;
  final int used;
  final int usedCost;
  final DateTime acquiredAt;
}

class _Allocation {
  const _Allocation(this.layerId, this.quantity, this.cost);
  final String layerId;
  final int quantity;
  final int cost;
}

class _PlannedLine {
  const _PlannedLine(this.input, this.name, this.cost, this.allocations);
  final SaleDraftLine input;
  final String name;
  final int cost;
  final List<_Allocation> allocations;
}
