import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../../core/domain/fifo_cost.dart';
import '../../../core/domain/money.dart';
import '../../../core/infrastructure/database/app_database.dart';
import '../../../core/infrastructure/database/schema.dart';
import '../../../core/infrastructure/database/investment_ledger.dart';
import '../../inventory/data/sqlite_inventory_store.dart';
import '../../inventory/domain/inventory_store.dart';
import '../../quick_sales/data/sqlite_quick_sales_store.dart';
import '../../workspace/domain/business_profile.dart';
import '../domain/events_store.dart';

class SqliteEventsStore implements EventsStore {
  SqliteEventsStore(this.database, {this.synthetic = false});
  final AppDatabase database;
  final bool synthetic;
  static const _operator = 'system:local-operator';

  @override
  Future<EventsSnapshot> load() async {
    await SqliteQuickSalesStore(
      database,
      synthetic: synthetic,
    ).ensureDefaults();
    final inventory = await SqliteInventoryStore(
      database,
      synthetic: synthetic,
    ).load();
    return database.database.transaction((txn) async {
      await InvestmentLedger.initialize(txn);
      final rows = await txn.rawQuery(
        '''SELECT event.*, product.is_active,document.occurred_at_utc FROM events event
JOIN catalog_items product ON product.id=event.product_id
JOIN business_documents document ON document.id=event.document_id AND document.status='posted'
JOIN journal_entries entry ON entry.document_id=document.id AND entry.status='posted'
ORDER BY document.occurred_at_utc DESC,document.id''',
      );
      final records = <EventRecord>[];
      for (final r in rows) {
        final parts = await txn.query(
          'event_products',
          where: 'event_id=?',
          whereArgs: [r['document_id']],
          orderBy: 'sequence',
        );
        records.add(
          EventRecord(
            productId: r['product_id'] as String,
            name: r['name_snapshot'] as String,
            minimumPeople: r['minimum_people'] as int,
            fixedCostMinor: r['fixed_cost_minor'] as int,
            productsCostMinor: r['products_cost_minor'] as int,
            totalCostMinor: r['total_cost_minor'] as int,
            unitCostMinor: r['unit_cost_minor'] as int,
            pvpMinor: r['pvp_minor'] as int,
            isActive: r['is_active'] == 1,
            createdAtUtc: DateTime.parse(r['occurred_at_utc'] as String),
            sourceAccountName: r['source_account_name_snapshot'] as String?,
            products: List.unmodifiable(
              parts.map((p) => '${p['quantity']} × ${p['name_snapshot']}'),
            ),
          ),
        );
      }
      final accounts = <EventAccount>[];
      for (final row in await _accounts(txn)) {
        accounts.add(
          EventAccount(
            row['id'] as String,
            row['label'] as String,
            _signed(await _balance(txn, row['ledger_account_id'] as String)),
          ),
        );
      }
      final pending = await txn.query(
        'event_requests',
        where: "status='prepared'",
        orderBy: 'prepared_at_utc,command_id',
      );
      accounts.add(
        EventAccount(
          InvestmentLedger.optionId,
          'Inversión',
          await InvestmentLedger.balance(txn),
        ),
      );
      return EventsSnapshot(
        inventory: inventory,
        events: records,
        accounts: accounts,
        pending: pending.map(_prepared).toList(),
        confirmedCommandIds: (await txn.query(
          'event_requests',
          columns: ['command_id'],
          where: "status='confirmed'",
        )).map((r) => r['command_id'] as String).toSet(),
      );
    });
  }

  @override
  Future<EventQuote> quote(CreateEvent command) => database.database
      .transaction((txn) async => (await _plan(txn, command)).quote);

  @override
  Future<PreparedEvent> prepare(CreateEvent command) async {
    _input(command);
    return database.database.transaction((txn) async {
      final prior = await txn.query(
        'event_requests',
        where: 'command_id=?',
        whereArgs: [command.commandId],
      );
      if (prior.isNotEmpty) {
        final p = _prepared(prior.single);
        if (jsonEncode(_input(p.command)) != jsonEncode(_input(command)) ||
            prior.single['status'] == 'discarded') {
          throw const EventsValidationException(
            'El identificador corresponde a otra solicitud.',
          );
        }
        return p;
      }
      final profile = await _profile(txn);
      final plan = await _plan(txn, command);
      final payload = jsonEncode({
        'version': 1,
        'profileId': profile.profileId,
        'currency': profile.currencyCode,
        'scale': profile.moneyScale,
        ..._input(command),
        'productsCostMinor': plan.quote.productsCostMinor,
        'totalCostMinor': plan.quote.totalCostMinor,
        'unitCostMinor': plan.quote.unitCostMinor,
        'sourceLedgerAccountId': plan.account?['ledger_account_id'],
        'sourceAccountName': plan.account?['name'],
      });
      final row = {
        'command_id': command.commandId,
        'canonical_payload': payload,
        'prepared_at_utc': DateTime.now().toUtc().toIso8601String(),
        'status': 'prepared',
      };
      await txn.insert('event_requests', row);
      return _prepared(row);
    }, exclusive: true);
  }

  @override
  Future<String> confirm(String commandId) => database.database.transaction((
    txn,
  ) async {
    final rows = await txn.query(
      'event_requests',
      where: 'command_id=?',
      whereArgs: [commandId],
    );
    if (rows.length != 1) {
      throw const EventsValidationException(
        'No existe la solicitud de evento.',
      );
    }
    final row = rows.single;
    final canonical = row['canonical_payload'] as String;
    final prior = await txn.query(
      'command_log',
      where: 'id=?',
      whereArgs: [commandId],
    );
    if (prior.isNotEmpty) {
      final stored =
          jsonDecode(prior.single['response_json'] as String)
              as Map<String, dynamic>;
      if (prior.single['command_type'] != 'create_event' ||
          stored['canonicalPayload'] != canonical ||
          prior.single['payload_hash'] != DatabaseSchema.checksum(canonical)) {
        throw const EventsValidationException(
          'La solicitud no coincide con el evento guardado.',
        );
      }
      return (stored['result'] as Map<String, dynamic>)['productId'] as String;
    }
    if (row['status'] != 'prepared') {
      throw const EventsValidationException(
        'Esta solicitud ya fue descartada.',
      );
    }
    final prepared = _prepared(row);
    final command = prepared.command;
    final profile = await _profile(txn);
    final json = jsonDecode(canonical) as Map<String, dynamic>;
    if (json['profileId'] != profile.profileId ||
        json['currency'] != profile.currencyCode ||
        json['scale'] != profile.moneyScale) {
      throw const EventsValidationException(
        'El perfil cambió desde la preparación.',
      );
    }
    final plan = await _plan(txn, command);
    if (plan.quote.productsCostMinor != prepared.quote.productsCostMinor ||
        plan.account?['ledger_account_id'] != json['sourceLedgerAccountId'] ||
        plan.account?['name'] != json['sourceAccountName']) {
      throw const EventsValidationException(
        'Cambió el costo o la cuenta. Descarta esta solicitud y revisa el evento antes de crearlo.',
      );
    }
    final now = DateTime.now().toUtc().toIso8601String();
    if (plan.quote.totalCostMinor > 0) {
      final accounts = await txn.query(
        'ledger_accounts',
        where: 'id=? OR code=?',
        whereArgs: ['events:costs', 'EVENT:COST'],
      );
      if (accounts.isEmpty) {
        await txn.insert('ledger_accounts', {
          'id': 'events:costs',
          'code': 'EVENT:COST',
          'name': 'Costos de eventos',
          'class': 'expense',
          'role': 'event_cost',
          'is_active': 1,
        });
      } else if (accounts.length != 1 ||
          accounts.single['id'] != 'events:costs' ||
          accounts.single['class'] != 'expense' ||
          accounts.single['role'] != 'event_cost' ||
          accounts.single['is_active'] != 1) {
        throw const EventsValidationException(
          'La cuenta interna de costos de eventos no está disponible.',
        );
      }
    }
    await txn.rawInsert(
      '''INSERT OR IGNORE INTO actors(id,display_name,kind,is_active,created_at_utc) VALUES(?,'Operador local','system',1,?)''',
      [_operator, now],
    );
    final actor = (await txn.query(
      'actors',
      where: 'id=?',
      whereArgs: [_operator],
    )).single;
    if (actor['kind'] != 'system' || actor['is_active'] != 1) {
      throw const EventsValidationException('El operador no está disponible.');
    }
    final categories = await txn.rawQuery(
      "SELECT * FROM categories WHERE lower(trim(name))='evento' ORDER BY id",
    );
    String category;
    if (categories.isEmpty) {
      category = InventoryIds.next();
      await txn.insert('categories', {
        'id': category,
        'name': 'Evento',
        'is_active': 1,
      });
    } else {
      final active = categories.where((c) => c['is_active'] == 1);
      if (active.isEmpty) {
        throw const EventsValidationException(
          'La categoría Evento está desactivada.',
        );
      }
      category = active.first['id'] as String;
    }
    final product = InventoryIds.next(),
        document = InventoryIds.next(),
        entry = InventoryIds.next();
    await txn.insert('catalog_items', {
      'id': product,
      'name': command.name.trim(),
      'kind': 'product',
      'unit_code': 'unit',
      'quantity_scale': 0,
      'category_id': category,
      'list_price_minor': command.pvpMinor,
      'is_active': 1,
    });
    await txn.insert('command_log', {
      'id': commandId,
      'command_type': 'create_event',
      'payload_hash': DatabaseSchema.checksum(canonical),
      'actor_id': _operator,
      'response_json': jsonEncode({
        'canonicalPayload': canonical,
        'result': {'documentId': document, 'productId': product},
      }),
      'response_version': 1,
      'committed_at_utc': now,
      'authorization_policy_version': 'development-single-user-v1',
    });
    final occurred = command.occurredAtUtc.toIso8601String();
    final date = command.occurredAtUtc
        .subtract(const Duration(hours: 5))
        .toIso8601String()
        .substring(0, 10);
    await txn.insert('business_documents', {
      'id': document,
      'command_id': commandId,
      'command_sequence': 0,
      'profile_id': profile.profileId,
      'actor_id': _operator,
      'type': 'event_creation',
      'status': 'draft',
      'occurred_at_utc': occurred,
      'business_date': date,
      'recorded_at_utc': now,
      'source_kind': synthetic ? 'synthetic' : 'native',
      'date_quality': 'documented',
    });
    await txn.insert('events', {
      'document_id': document,
      'product_id': product,
      'name_snapshot': command.name.trim(),
      'minimum_people': command.minimumPeople,
      'fixed_cost_minor': command.fixedCostMinor,
      'source_account_id':
          command.fixedCostMinor > 0 &&
              command.sourceAccountId != InvestmentLedger.optionId
          ? command.sourceAccountId
          : null,
      'funding_mode':
          command.fixedCostMinor > 0 &&
              command.sourceAccountId == InvestmentLedger.optionId
          ? 'investment'
          : 'cash',
      'source_account_name_snapshot': plan.account?['name'],
      'products_cost_minor': plan.quote.productsCostMinor,
      'total_cost_minor': plan.quote.totalCostMinor,
      'unit_cost_minor': plan.quote.unitCostMinor,
      'pvp_minor': command.pvpMinor,
    });
    for (var i = 0; i < plan.parts.length; i++) {
      final part = plan.parts[i], id = InventoryIds.next();
      await txn.insert('event_products', {
        'id': id,
        'event_id': document,
        'sequence': i,
        'product_id': part.input.productId,
        'name_snapshot': part.name,
        'quantity': part.input.quantity,
        'cost_minor': part.cost,
      });
      for (var j = 0; j < part.allocations.length; j++) {
        final allocation = part.allocations[j];
        await txn.insert('event_cost_allocations', {
          'id': InventoryIds.next(),
          'event_product_id': id,
          'sequence': j,
          allocation.source == 'purchase' ? 'cost_layer_id' : 'opening_item_id':
              allocation.id,
          'quantity': allocation.quantity,
          'cost_minor': allocation.cost,
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
      'event_expected_journal',
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
      'event_requests',
      {'status': 'confirmed'},
      where: 'command_id=?',
      whereArgs: [commandId],
    );
    return product;
  }, exclusive: true);

  @override
  Future<void> discard(String commandId) =>
      database.database.transaction((txn) async {
        await txn.update(
          'event_requests',
          {'status': 'discarded'},
          where: "command_id=? AND status='prepared'",
          whereArgs: [commandId],
        );
      }, exclusive: true);

  @override
  Future<void> deactivate(String productId) =>
      database.database.transaction((txn) async {
        if ((await txn.query(
              'events',
              where: 'product_id=?',
              whereArgs: [productId],
            )).length !=
            1) {
          throw const EventsValidationException('El artículo no es un evento.');
        }
        await txn.update(
          'catalog_items',
          {'is_active': 0},
          where: 'id=?',
          whereArgs: [productId],
        );
      }, exclusive: true);

  Future<_Plan> _plan(DatabaseExecutor txn, CreateEvent command) async {
    _input(command);
    final parts = <_Part>[];
    final layers = await txn.query(
      'inventory_effective_layers',
      orderBy: 'fifo_sequence,id',
    );
    var productsCost = BigInt.zero;
    for (final input in command.products) {
      final products = await txn.rawQuery(
        '''SELECT product.* FROM catalog_items product LEFT JOIN categories category ON category.id=product.category_id
WHERE product.id=? AND product.is_active=1 AND (product.category_id IS NULL OR category.is_active=1)
AND NOT EXISTS(SELECT 1 FROM events WHERE product_id=product.id) AND NOT EXISTS(SELECT 1 FROM catalog_services WHERE product_id=product.id)''',
        [input.productId],
      );
      if (products.length != 1) {
        throw const EventsValidationException(
          'Selecciona únicamente productos físicos activos.',
        );
      }
      await _chronology(txn, command.occurredAtUtc, productId: input.productId);
      var remaining = input.quantity, cost = BigInt.zero;
      final allocations = <_Allocation>[];
      for (final layer in layers.where(
        (l) => l['product_id'] == input.productId,
      )) {
        if (DateTime.parse(
          layer['acquired_at_utc'] as String,
        ).isAfter(command.occurredAtUtc)) {
          throw const EventsValidationException(
            'El evento no puede ser anterior a los ingresos de sus productos.',
          );
        }
        final source = layer['source_kind'] as String,
            id = layer['id'] as String;
        final usage = await txn.query(
          'inventory_cost_usage',
          where:
              '${source == 'purchase' ? 'cost_layer_id' : 'opening_item_id'}=?',
          whereArgs: [id],
        );
        final used = _checked(
          usage.fold(
            BigInt.zero,
            (s, r) => s + BigInt.from(r['quantity'] as int),
          ),
        );
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
        throw EventsValidationException(
          'Existencias insuficientes de ${products.single['name']}.',
        );
      }
      parts.add(
        _Part(
          input,
          products.single['name'] as String,
          _checked(cost),
          allocations,
        ),
      );
      productsCost += cost;
    }
    final total = productsCost + BigInt.from(command.fixedCostMinor);
    Map<String, Object?>? account;
    if (command.fixedCostMinor > 0 &&
        command.sourceAccountId == InvestmentLedger.optionId) {
      await InvestmentLedger.initialize(txn);
      try {
        await InvestmentLedger.checkPurchase(
          txn,
          command.fixedCostMinor,
          command.occurredAtUtc,
        );
      } on InvestmentValidationException catch (e) {
        throw EventsValidationException(e.message);
      }
      account = {
        'id': InvestmentLedger.optionId,
        'name': 'Inversión',
        'ledger_account_id': InvestmentLedger.accountId,
      };
    } else if (command.fixedCostMinor > 0) {
      final accounts = await _accounts(txn);
      final selected = accounts.where(
        (a) => a['id'] == command.sourceAccountId,
      );
      if (selected.length != 1) {
        throw const EventsValidationException(
          'Selecciona Caja, Nequi o Inversión para el costo fijo.',
        );
      }
      account = selected.single;
      final ledger = account['ledger_account_id'] as String;
      final balance = await _balance(txn, ledger);
      _signed(balance);
      if (balance < BigInt.from(command.fixedCostMinor)) {
        throw const EventsValidationException(
          'Saldo insuficiente para pagar el costo fijo.',
        );
      }
      await _chronology(txn, command.occurredAtUtc, ledger: ledger);
      final balances = <BigInt>[];
      for (final a in accounts) {
        balances.add(await _balance(txn, a['ledger_account_id'] as String));
      }
      _signed(
        balances.fold(BigInt.zero, (a, b) => a + b) -
            BigInt.from(command.fixedCostMinor),
      );
    }
    final minimum = BigInt.from(command.minimumPeople);
    final unit = command.minimumPeople == 0
        ? BigInt.zero
        : total ~/ minimum +
              ((total % minimum) * BigInt.two >= minimum
                  ? BigInt.one
                  : BigInt.zero);
    return _Plan(
      EventQuote(_checked(productsCost), _checked(total), _checked(unit)),
      parts,
      account,
    );
  }

  static Future<void> _chronology(
    DatabaseExecutor txn,
    DateTime occurred, {
    String? productId,
    String? ledger,
  }) async {
    final rows = ledger != null
        ? await txn.rawQuery(
            '''SELECT document.occurred_at_utc FROM business_documents document JOIN journal_entries entry ON entry.document_id=document.id
JOIN journal_lines line ON line.entry_id=entry.id WHERE document.status='posted' AND entry.status='posted' AND line.account_id=?''',
            [ledger],
          )
        : await txn.rawQuery(
            '''
SELECT document.occurred_at_utc FROM business_documents document WHERE document.status='posted' AND document.id IN(
SELECT sale_id FROM sale_lines WHERE product_id=? UNION ALL SELECT event_id FROM event_products WHERE product_id=?)''',
            [productId, productId],
          );
    if (rows.any(
      (r) => DateTime.parse(r['occurred_at_utc'] as String).isAfter(occurred),
    )) {
      throw const EventsValidationException(
        'La fecha del evento es anterior al último movimiento. Descarta la solicitud y vuelve a crearla.',
      );
    }
  }

  static Future<List<Map<String, Object?>>> _accounts(
    DatabaseExecutor txn,
  ) => txn.rawQuery(
    '''SELECT cash.*,CASE option.id WHEN 'quick-default:EFECTIVO' THEN 'Caja' ELSE 'Nequi' END label
FROM cash_accounts cash JOIN quick_payment_options option ON option.cash_account_id=cash.id JOIN ledger_accounts ledger ON ledger.id=cash.ledger_account_id
WHERE option.id IN('quick-default:EFECTIVO','quick-default:NEQUI') AND cash.is_active=1 AND cash.is_available=1 AND ledger.is_active=1 AND ledger.class='asset' AND ledger.role='cash' ORDER BY option.id''',
  );
  static Future<BigInt> _balance(DatabaseExecutor txn, String ledger) async {
    final rows = await txn.rawQuery(
      '''SELECT line.debit_minor,line.credit_minor FROM journal_lines line JOIN journal_entries entry ON entry.id=line.entry_id AND entry.status='posted'
JOIN business_documents document ON document.id=entry.document_id AND document.status='posted' WHERE line.account_id=?''',
      [ledger],
    );
    return rows.fold<BigInt>(
      BigInt.zero,
      (s, r) =>
          s +
          BigInt.from(r['debit_minor'] as int) -
          BigInt.from(r['credit_minor'] as int),
    );
  }

  static Future<BusinessProfile> _profile(DatabaseExecutor txn) async {
    final rows = await txn.query('app_profile', where: 'id=1');
    if (rows.length != 1) {
      throw const EventsValidationException('Configura el espacio primero.');
    }
    final p = BusinessProfile.fromRow(rows.single);
    if (p.timezone != 'America/Bogota') {
      throw const EventsValidationException(
        'Eventos requiere la zona horaria America/Bogota.',
      );
    }
    return p;
  }

  static Map<String, Object?> _input(CreateEvent c) {
    for (final id in [
      c.commandId,
      ?c.sourceAccountId,
      ...c.products.map((p) => p.productId),
    ]) {
      if (!RegExp(r'^[A-Za-z0-9:_-]{1,128}$').hasMatch(id)) {
        throw const EventsValidationException('Identificador inválido.');
      }
    }
    final name = c.name.trim();
    if (name.isEmpty ||
        name.length > 160 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(name)) {
      throw const EventsValidationException(
        'Escribe un nombre de hasta 160 caracteres.',
      );
    }
    for (final amount in [c.minimumPeople, c.fixedCostMinor, c.pvpMinor]) {
      _checked(BigInt.from(amount));
    }
    if (c.pvpMinor <= 0) {
      throw const EventsValidationException(
        'El PVP de inscripción debe ser mayor que cero.',
      );
    }
    if ((c.fixedCostMinor > 0 || c.products.isNotEmpty) &&
        c.minimumPeople == 0) {
      throw const EventsValidationException(
        'Indica un mínimo de personas mayor que cero cuando hay costos o productos.',
      );
    }
    if (c.fixedCostMinor > 0 && c.sourceAccountId == null) {
      throw const EventsValidationException('Selecciona Caja o Nequi.');
    }
    if (c.products.length > 100) {
      throw const EventsValidationException(
        'Agrega como máximo 100 productos.',
      );
    }
    final seen = <String>{};
    for (final p in c.products) {
      if (!seen.add(p.productId) || p.quantity <= 0) {
        throw const EventsValidationException(
          'No repitas productos y usa cantidades positivas.',
        );
      }
      _checked(BigInt.from(p.quantity));
    }
    if (!c.occurredAtUtc.isUtc ||
        c.occurredAtUtc.year < 1 ||
        c.occurredAtUtc.year > 9999) {
      throw const EventsValidationException('Fecha inválida.');
    }
    final sorted = c.products.toList()
      ..sort((a, b) => a.productId.compareTo(b.productId));
    return {
      'name': name,
      'minimumPeople': c.minimumPeople,
      'fixedCostMinor': c.fixedCostMinor,
      'sourceAccountId': c.fixedCostMinor > 0 ? c.sourceAccountId : null,
      'pvpMinor': c.pvpMinor,
      'occurredAtUtc': c.occurredAtUtc.toIso8601String(),
      'products': sorted.map((p) => p.toJson()).toList(),
    };
  }

  static PreparedEvent _prepared(Map<String, Object?> row) {
    final p =
        jsonDecode(row['canonical_payload'] as String) as Map<String, dynamic>;
    return PreparedEvent(
      CreateEvent(
        commandId: row['command_id'] as String,
        name: p['name'] as String,
        minimumPeople: p['minimumPeople'] as int,
        fixedCostMinor: p['fixedCostMinor'] as int,
        pvpMinor: p['pvpMinor'] as int,
        sourceAccountId: p['sourceAccountId'] as String?,
        occurredAtUtc: DateTime.parse(p['occurredAtUtc'] as String),
        products: (p['products'] as List)
            .map(
              (v) => EventProductInput(
                v['productId'] as String,
                v['quantity'] as int,
              ),
            )
            .toList(),
      ),
      EventQuote(
        p['productsCostMinor'] as int,
        p['totalCostMinor'] as int,
        p['unitCostMinor'] as int,
      ),
    );
  }

  static int _checked(BigInt n) {
    if (n < BigInt.zero || n > Money.maxMinorUnits) {
      throw const EventsValidationException(
        'El importe o la cantidad excede el rango permitido.',
      );
    }
    return n.toInt();
  }

  static int _signed(BigInt n) {
    if (n < -Money.maxMinorUnits || n > Money.maxMinorUnits) {
      throw const EventsValidationException(
        'El saldo excede el rango permitido.',
      );
    }
    return n.toInt();
  }
}

class _Plan {
  _Plan(this.quote, this.parts, this.account);
  final EventQuote quote;
  final List<_Part> parts;
  final Map<String, Object?>? account;
}

class _Part {
  _Part(this.input, this.name, this.cost, this.allocations);
  final EventProductInput input;
  final String name;
  final int cost;
  final List<_Allocation> allocations;
}

class _Allocation {
  _Allocation(this.id, this.source, this.quantity, this.cost);
  final String id, source;
  final int quantity, cost;
}
