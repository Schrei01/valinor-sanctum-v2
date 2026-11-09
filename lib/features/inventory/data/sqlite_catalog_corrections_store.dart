import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../../core/domain/money.dart';
import '../../../core/infrastructure/database/app_database.dart';
import '../../../core/infrastructure/database/schema.dart';
import '../../../core/infrastructure/database/investment_ledger.dart';
import '../../events/domain/events_store.dart';
import '../../treasury/data/sqlite_treasury_store.dart';
import '../../treasury/domain/treasury_store.dart';
import '../domain/catalog_corrections_store.dart';
import '../domain/stock_adjustment_store.dart';
import 'sqlite_stock_adjustment_store.dart';

class SqliteCatalogCorrectionsStore implements CatalogCorrectionsStore {
  const SqliteCatalogCorrectionsStore(this.app, {this.synthetic = false});
  final AppDatabase app;
  final bool synthetic;
  static const actor = 'system:local-operator';
  Never _invalid(String message) =>
      throw CatalogCorrectionValidationException(message);
  int _money(BigInt value) {
    if (value < BigInt.zero || value > Money.maxMinorUnits) {
      _invalid('El importe supera el rango permitido.');
    }
    return value.toInt();
  }

  String _text(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty ||
        text.length > 120 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(text)) {
      _invalid('Escribe un nombre de hasta 120 caracteres.');
    }
    return text;
  }

  Future<List<EventAccount>> _accounts(DatabaseExecutor t) async {
    final result = <EventAccount>[];
    for (final row in await t.rawQuery(
      "SELECT o.cash_account_id id,o.id option_id,c.ledger_account_id FROM quick_payment_options o JOIN cash_accounts c ON c.id=o.cash_account_id JOIN ledger_accounts l ON l.id=c.ledger_account_id WHERE o.id IN('quick-default:EFECTIVO','quick-default:NEQUI') AND c.is_active=1 AND c.is_available=1 AND l.is_active=1",
    )) {
      result.add(
        EventAccount(
          row['id'] as String,
          row['option_id'] == 'quick-default:EFECTIVO' ? 'Caja' : 'Nequi',
          InvestmentLedger.checked(
            await InvestmentLedger.signedBalance(
              t,
              row['ledger_account_id'] as String,
            ),
          ),
        ),
      );
    }
    result.add(
      EventAccount(
        'investment',
        'Inversión',
        await InvestmentLedger.balance(t),
      ),
    );
    return result;
  }

  @override
  Future<CatalogEventState> loadEvent(String id) =>
      app.database.transaction((t) async {
        final rows = await t.query(
          'event_current_settings',
          where: 'product_id=?',
          whereArgs: [id],
        );
        if (rows.length != 1) {
          _invalid('Selecciona un evento registrado en esta app.');
        }
        return CatalogEventState(
          rows.single,
          await t.query(
            'event_current_components',
            where: 'event_product_id=?',
            whereArgs: [id],
            orderBy: 'product_id',
          ),
          await _accounts(t),
        );
      });
  PreparedCatalogCorrection _decode(Map<String, Object?> row) {
    final p =
        jsonDecode(row['canonical_payload'] as String) as Map<String, dynamic>;
    return PreparedCatalogCorrection(
      CatalogCorrectionCommand.fromJson(p['input']),
      p,
    );
  }

  @override
  Future<List<PreparedCatalogCorrection>> pendingCorrections() async =>
      (await app.database.query(
        'catalog_correction_requests',
        where: "status='prepared'",
        orderBy: 'prepared_at_utc,command_id',
      )).map(_decode).toList();
  @override
  Future<PreparedCatalogCorrection> prepareCorrection(
    CatalogCorrectionCommand c,
  ) => app.database.transaction((t) async {
    final prior = await t.query(
      'catalog_correction_requests',
      where: 'command_id=?',
      whereArgs: [c.commandId],
    );
    if (prior.isNotEmpty) {
      final old = _decode(prior.single);
      if (jsonEncode(old.command.toJson()) != jsonEncode(c.toJson()) ||
          prior.single['status'] == 'discarded') {
        _invalid('El identificador pertenece a otra corrección.');
      }
      return old;
    }
    final plan = await _plan(t, c);
    await t.insert('catalog_correction_requests', {
      'command_id': c.commandId,
      'canonical_payload': jsonEncode(plan),
      'prepared_at_utc': DateTime.now().toUtc().toIso8601String(),
      'status': 'prepared',
    });
    return PreparedCatalogCorrection(c, plan);
  }, exclusive: true);

  Future<Map<String, dynamic>> _plan(
    Transaction t,
    CatalogCorrectionCommand c,
  ) async {
    if (c.commandId.isEmpty ||
        c.commandId.length > 80 ||
        !c.occurredAtUtc.isUtc ||
        c.occurredAtUtc.year < 1 ||
        c.occurredAtUtc.year > 9998) {
      _invalid('La solicitud de corrección no es válida.');
    }
    final rows = await t.query(
      'catalog_items',
      where: 'id=?',
      whereArgs: [c.productId],
    );
    if (rows.length != 1) _invalid('El ítem ya no está disponible.');
    final p = rows.single;
    if (p['name'] != c.expectedName ||
        p['list_price_minor'] != c.expectedPriceMinor) {
      _invalid(
        'El ítem cambió. Descarta la solicitud y revisa los valores actuales.',
      );
    }
    final service = await t.query(
      'catalog_services',
      where: 'product_id=?',
      whereArgs: [c.productId],
    );
    if (service.isNotEmpty) {
      _invalid('Pasadía, Bulk y Alquiler conservan sus reglas especiales.');
    }
    final original = await t.query(
      'events',
      where: 'product_id=?',
      whereArgs: [c.productId],
    );
    final before = <String, dynamic>{
      'name': p['name'],
      'priceMinor': p['list_price_minor'],
    };
    final after = Map<String, dynamic>.from(before);
    final changes = <Map<String, dynamic>>[];
    if (c.kind != CatalogCorrectionKind.event) {
      if (original.isNotEmpty) _invalid('Para un evento usa Corregir evento.');
      final cats = await t.query(
        'categories',
        where: 'id=?',
        whereArgs: [p['category_id']],
      );
      final category = cats.isEmpty
          ? ''
          : (cats.single['name'] as String).trim().toLowerCase().replaceAll(
              'í',
              'i',
            );
      if (![
        'comestible',
        'comestibles',
        'articulo',
        'articulos',
      ].contains(category)) {
        _invalid('Esta corrección es para Comestibles y Artículos.');
      }
      if (c.kind == CatalogCorrectionKind.name) {
        after['name'] = _text(c.name);
      } else {
        if (c.priceMinor == null || c.priceMinor! <= 0) {
          _invalid('El PVP debe ser mayor que cero.');
        }
        after['priceMinor'] = _money(BigInt.from(c.priceMinor!));
      }
      if (jsonEncode(before) == jsonEncode(after)) {
        _invalid('No hay cambios para guardar.');
      }
    } else {
      if (original.length != 1) _invalid('Selecciona un evento.');
      final current = (await t.query(
        'event_current_settings',
        where: 'product_id=?',
        whereArgs: [c.productId],
      )).single;
      if (c.expectedRevision != current['revision']) {
        _invalid('El evento cambió. Descarta la solicitud y vuelve a abrirlo.');
      }
      final priorParts = await t.query(
        'event_current_components',
        where: 'event_product_id=?',
        whereArgs: [c.productId],
        orderBy: 'product_id',
      );
      before.addAll({
        'revision': current['revision'],
        'minimumPeople': current['minimum_people'],
        'fixedCostMinor': current['fixed_cost_minor'],
        'productsCostMinor': current['products_cost_minor'],
        'paidFixedCostMinor': current['paid_fixed_cost_minor'],
        'components': priorParts,
      });
      final minimum = c.minimumPeople,
          fixed = c.fixedCostMinor,
          price = c.priceMinor;
      if (minimum == null ||
          minimum < 0 ||
          BigInt.from(minimum) > Money.maxMinorUnits ||
          fixed == null ||
          fixed < 0 ||
          price == null ||
          price <= 0) {
        _invalid('Revisa mínimo de personas, costo fijo y PVP.');
      }
      _money(BigInt.from(fixed));
      _money(BigInt.from(price));
      if ((fixed > 0 || c.products.isNotEmpty) && minimum == 0) {
        _invalid(
          'Si hay costos o artículos, el mínimo de personas debe ser mayor que cero.',
        );
      }
      if (c.products.length > 100) {
        _invalid('El evento admite hasta 100 artículos distintos.');
      }
      final selected = <String, int>{};
      for (final part in c.products) {
        if (part.quantity <= 0 ||
            BigInt.from(part.quantity) > Money.maxMinorUnits ||
            selected.containsKey(part.productId)) {
          _invalid('Usa cantidades positivas y no repitas artículos.');
        }
        selected[part.productId] = part.quantity;
      }
      final parts = <Map<String, dynamic>>[];
      final oldParts = {
        for (final part in priorParts) part['product_id'] as String: part,
      };
      final ids = {...oldParts.keys, ...selected.keys}.toList()..sort();
      final stock = SqliteStockAdjustmentStore(
        app,
        synthetic: synthetic,
        transaction: t,
      );
      var sequence = 0;
      for (final id in ids) {
        final old = oldParts[id],
            oldQty = old?['quantity'] as int? ?? 0,
            oldCost = old?['cost_minor'] as int? ?? 0;
        final qty = selected[id] ?? 0, delta = qty - oldQty;
        final item = (await t.query(
          'catalog_items',
          where: 'id=?',
          whereArgs: [id],
        )).single;
        if ((await t.query(
              'events',
              where: 'product_id=?',
              whereArgs: [id],
            )).isNotEmpty ||
            (await t.query(
              'catalog_services',
              where: 'product_id=?',
              whereArgs: [id],
            )).isNotEmpty) {
          _invalid('El evento solo puede consumir artículos físicos.');
        }
        var cost = oldCost;
        if (delta > 0) {
          if (item['is_active'] != 1) {
            _invalid('No puedes agregar un artículo desactivado.');
          }
          final command = StockAdjustmentCommand(
            commandId: '${c.commandId}:stock:${sequence++}',
            productId: id,
            quantity: delta,
            reason: 'Corrección de evento: ${c.productId}',
            occurredAtUtc: c.occurredAtUtc,
          );
          int extra;
          try {
            extra = await stock.quoteCost(command);
          } on StockAdjustmentValidationException catch (e) {
            _invalid(e.message);
          }
          cost = _money(BigInt.from(cost) + BigInt.from(extra));
          changes.add({
            'commandId': command.commandId,
            'productId': id,
            'name': item['name'],
            'quantity': delta,
            'isAddition': false,
            'costMinor': extra,
          });
        } else if (delta < 0) {
          final returning = -delta,
              base = oldCost ~/ oldQty,
              remainder = oldCost % oldQty;
          final high = returning < remainder ? returning : remainder;
          for (final batch in [(high, base + 1), (returning - high, base)]) {
            if (batch.$1 == 0) continue;
            final returnedCost = _money(
              BigInt.from(batch.$1) * BigInt.from(batch.$2),
            );
            cost -= returnedCost;
            changes.add({
              'commandId': '${c.commandId}:stock:${sequence++}',
              'productId': id,
              'name': item['name'],
              'quantity': batch.$1,
              'isAddition': true,
              'unitCost': batch.$2,
              'costMinor': returnedCost,
            });
          }
        }
        if (qty > 0) {
          parts.add({
            'productId': id,
            'name': item['name'],
            'quantity': qty,
            'costMinor': cost,
          });
        }
      }
      final productsCost = _money(
        parts.fold(
          BigInt.zero,
          (s, p) => s + BigInt.from(p['costMinor'] as int),
        ),
      );
      final total = _money(BigInt.from(productsCost) + BigInt.from(fixed));
      final min = BigInt.from(minimum), amount = BigInt.from(total);
      final unit = minimum == 0
          ? 0
          : _money(
              amount ~/ min +
                  ((amount % min) * BigInt.two >= min
                      ? BigInt.one
                      : BigInt.zero),
            );
      final oldFixed = current['fixed_cost_minor'] as int;
      final additional = fixed > oldFixed ? fixed - oldFixed : 0;
      final accounts = await _accounts(t);
      final source = accounts
          .where((a) => a.id == c.sourceAccountId)
          .firstOrNull;
      if (fixed > 0 && source == null) {
        _invalid('Selecciona Caja, Nequi o Inversión para el costo fijo.');
      }
      if (additional > 0) {
        if (source!.isInvestment) {
          await InvestmentLedger.initialize(t);
        }
        final ledger = source.isInvestment
            ? InvestmentLedger.accountId
            : (await t.query(
                    'cash_accounts',
                    where: 'id=?',
                    whereArgs: [source.id],
                  )).single['ledger_account_id']
                  as String;
        try {
          await InvestmentLedger.checkChronology(t, [ledger], c.occurredAtUtc);
        } on InvestmentValidationException catch (e) {
          _invalid(e.message);
        }
        if (!source.isInvestment && source.balanceMinor < additional) {
          _invalid('Saldo insuficiente para el costo fijo adicional.');
        }
        if (source.isInvestment) {
          _money(BigInt.from(source.balanceMinor) + BigInt.from(additional));
        }
      }
      final paid = _money(
        BigInt.from(current['paid_fixed_cost_minor'] as int) +
            BigInt.from(additional),
      );
      _money(BigInt.from(paid) + BigInt.from(productsCost));
      after.addAll({
        'name': _text(c.name),
        'priceMinor': price,
        'minimumPeople': minimum,
        'fixedCostMinor': fixed,
        'productsCostMinor': productsCost,
        'totalCostMinor': total,
        'unitCostMinor': unit,
        'sourceAccountId': fixed == 0 ? null : source!.id,
        'sourceAccountName': fixed == 0 ? null : source!.label,
        'additionalFixedCost': additional,
        'paidFixedCostMinor': paid,
        'components': parts,
        'stockCostDelta':
            productsCost - (current['products_cost_minor'] as int),
      });
    }
    final profile = (await t.query('app_profile')).single;
    return {
      'input': c.toJson(),
      'profileId': profile['profile_id'],
      'currency': profile['currency_code'],
      'scale': profile['money_scale'],
      'before': before,
      'after': after,
      'stockChanges': changes,
    };
  }

  @override
  Future<void> confirmCorrection(String id) => app.database.transaction((
    t,
  ) async {
    final rows = await t.query(
      'catalog_correction_requests',
      where: 'command_id=?',
      whereArgs: [id],
    );
    if (rows.length != 1) _invalid('No se encontró la corrección guardada.');
    final request = rows.single,
        canonical = request['canonical_payload'] as String;
    final prior = await t.query('command_log', where: 'id=?', whereArgs: [id]);
    if (prior.isNotEmpty) {
      if (prior.single['command_type'] != 'catalog_correction' ||
          jsonDecode(
                prior.single['response_json'] as String,
              )['canonicalPayload'] !=
              canonical) {
        _invalid('El identificador ya pertenece a otra operación.');
      }
      return;
    }
    if (request['status'] != 'prepared') {
      _invalid('La corrección fue descartada.');
    }
    final prepared = _decode(request), c = prepared.command;
    final plan = await _plan(t, c);
    if (jsonEncode(plan) != canonical) {
      _invalid(
        'Cambió el inventario, el costo o la cuenta. Descarta y prepara de nuevo la corrección.',
      );
    }
    final now = DateTime.now().toUtc().toIso8601String(),
        after = plan['after'] as Map<String, dynamic>;
    await t.rawInsert(
      "INSERT OR IGNORE INTO actors(id,display_name,kind,is_active,created_at_utc) VALUES(?,'Operador local','system',1,?)",
      [actor, now],
    );
    final operator = (await t.query(
      'actors',
      where: 'id=?',
      whereArgs: [actor],
    )).single;
    if (operator['kind'] != 'system' || operator['is_active'] != 1) {
      _invalid('El operador local no está disponible.');
    }
    await t.insert('command_log', {
      'id': id,
      'command_type': 'catalog_correction',
      'payload_hash': DatabaseSchema.checksum(canonical),
      'actor_id': actor,
      'response_json': jsonEncode({
        'canonicalPayload': canonical,
        'result': {'productId': c.productId},
      }),
      'response_version': 1,
      'committed_at_utc': now,
      'authorization_policy_version': 'development-single-user-v1',
    });
    final stock = SqliteStockAdjustmentStore(
      app,
      synthetic: synthetic,
      transaction: t,
    );
    for (final raw in plan['stockChanges'] as List) {
      final change = raw as Map<String, dynamic>;
      if (change['isAddition'] == true) {
        await t.insert('event_return_values', {
          'stock_command_id': change['commandId'],
          'correction_command_id': id,
          'product_id': change['productId'],
          'quantity': change['quantity'],
          'unit_cost_minor': change['unitCost'],
          'cost_minor': change['costMinor'],
        });
      }
      final command = StockAdjustmentCommand(
        commandId: change['commandId'],
        productId: change['productId'],
        quantity: change['quantity'],
        isAddition: change['isAddition'],
        reason: 'Corrección de evento: ${c.productId}',
        occurredAtUtc: c.occurredAtUtc,
      );
      await stock.prepareAdjustment(command);
      await stock.confirmAdjustment(command.commandId);
    }
    if ((after['additionalFixedCost'] as int? ?? 0) > 0) {
      await _pay(t, c, after, now);
    }
    await t.insert('catalog_corrections', {
      'command_id': id,
      'product_id': c.productId,
      'kind': c.kind.name,
      'previous_revision': c.expectedRevision,
      'before_json': jsonEncode(plan['before']),
      'after_json': jsonEncode(after),
      'occurred_at_utc': c.occurredAtUtc.toIso8601String(),
    });
    await t.update(
      'catalog_items',
      {'name': after['name'], 'list_price_minor': after['priceMinor']},
      where: 'id=?',
      whereArgs: [c.productId],
    );
    await t.update(
      'catalog_correction_requests',
      {'status': 'confirmed'},
      where: 'command_id=?',
      whereArgs: [id],
    );
    if ((after['additionalFixedCost'] as int? ?? 0) > 0) {
      try {
        final balances = await SqliteTreasuryStore(app).loadInTransaction(t);
        balances.totalAvailableMinor;
        balances.totalPotentialMinor;
        balances.totalMinor;
      } on TreasuryValidationException catch (e) {
        _invalid(e.message);
      }
    }
  }, exclusive: true);

  Future<void> _pay(
    Transaction t,
    CatalogCorrectionCommand c,
    Map<String, dynamic> after,
    String now,
  ) async {
    final amount = after['additionalFixedCost'] as int;
    final source = after['sourceAccountId'] as String;
    final ledger = source == 'investment'
        ? InvestmentLedger.accountId
        : (await t.query(
                'cash_accounts',
                where: 'id=?',
                whereArgs: [source],
              )).single['ledger_account_id']
              as String;
    if ((await t.query(
      'ledger_accounts',
      where: "id='events:costs'",
    )).isEmpty) {
      await t.insert('ledger_accounts', {
        'id': 'events:costs',
        'code': 'EVENT:COST',
        'name': 'Costos de eventos',
        'class': 'expense',
        'role': 'event_cost',
        'is_active': 1,
      });
    }
    final document = '${c.commandId}:payment', entry = '${c.commandId}:journal';
    await t.insert('business_documents', {
      'id': document,
      'command_id': c.commandId,
      'command_sequence': 0,
      'profile_id': (await t.query('app_profile')).single['profile_id'],
      'actor_id': actor,
      'type': 'event_correction_payment',
      'status': 'draft',
      'occurred_at_utc': c.occurredAtUtc.toIso8601String(),
      'business_date': c.occurredAtUtc
          .subtract(const Duration(hours: 5))
          .toIso8601String()
          .substring(0, 10),
      'recorded_at_utc': now,
      'reason': 'Costo fijo adicional de evento: ${after['name']}',
      'source_kind': synthetic ? 'synthetic' : 'native',
      'date_quality': 'documented',
    });
    await t.insert('event_correction_payments', {
      'document_id': document,
      'correction_command_id': c.commandId,
      'product_id': c.productId,
      'source_option_id': source,
      'source_ledger_id': ledger,
      'amount_minor': amount,
      'name_snapshot': after['name'],
    });
    await t.insert('journal_entries', {
      'id': entry,
      'document_id': document,
      'status': 'draft',
      'cost_completeness': 'complete',
    });
    for (final line in [('events:costs', amount, 0), (ledger, 0, amount)]) {
      await t.insert('journal_lines', {
        'id': '$entry:${line.$1}',
        'entry_id': entry,
        'sequence': line.$2 == 0 ? 1 : 0,
        'account_id': line.$1,
        'debit_minor': line.$2,
        'credit_minor': line.$3,
      });
    }
    await t.update(
      'business_documents',
      {'status': 'posted'},
      where: 'id=?',
      whereArgs: [document],
    );
    await t.update(
      'journal_entries',
      {'status': 'posted', 'posted_at_utc': now},
      where: 'id=?',
      whereArgs: [entry],
    );
  }

  @override
  Future<void> discardCorrection(String id) => app.database.transaction((
    t,
  ) async {
    if ((await t.query(
      'command_log',
      where: 'id=?',
      whereArgs: [id],
    )).isNotEmpty) {
      _invalid(
        'La corrección ya se confirmó. Reintenta para recuperar el resultado.',
      );
    }
    await t.update(
      'catalog_correction_requests',
      {'status': 'discarded'},
      where: "command_id=? AND status='prepared'",
      whereArgs: [id],
    );
  }, exclusive: true);
}
