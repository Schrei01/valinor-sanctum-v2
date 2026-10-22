import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../../core/domain/money.dart';
import '../../../core/infrastructure/database/app_database.dart';
import '../../../core/infrastructure/database/schema.dart';
import '../../collections/data/sqlite_collections_store.dart';
import '../../inventory/domain/inventory_store.dart';
import '../../quick_sales/data/sqlite_quick_sales_store.dart';
import '../../workspace/domain/business_profile.dart';
import '../domain/debtors_store.dart';

class SqliteDebtorsStore implements DebtorsStore {
  SqliteDebtorsStore(this.database, {this.synthetic = false});
  final AppDatabase database;
  final bool synthetic;
  static const _operator = 'system:local-operator',
      _control = 'system:customer-receivable',
      _legacy = 'system:legacy-customer-receivables';
  @override
  Future<DebtorsSnapshot> load() async {
    await SqliteQuickSalesStore(
      database,
      synthetic: synthetic,
    ).ensureDefaults();
    final oldCollections = await SqliteCollectionsStore(
      database,
      synthetic: synthetic,
    ).load();
    return database.database.transaction((txn) async {
      final people = await txn.rawQuery(
        'SELECT debtor.*,EXISTS(SELECT 1 FROM debtor_openings WHERE debtor_id=debtor.id) has_opening FROM debtors debtor ORDER BY name COLLATE NOCASE,id',
      );
      final rows = await _receivables(txn);
      final balances = <String, BigInt>{};
      final charges = <DebtorCharge>[];
      for (final r in rows) {
        final person = r['debtor_id'] as String?;
        if (person != null) {
          balances[person] =
              (balances[person] ?? BigInt.zero) +
              BigInt.from(r['remaining_minor'] as int);
        }
        charges.add(
          DebtorCharge(
            receivableId: r['id'] as String,
            label: r['label'] as String,
            nameSnapshot: r['customer_name_snapshot'] as String,
            occurredAtUtc: DateTime.parse(r['issued_at_utc'] as String),
            originalCreditMinor: r['credit_minor'] as int,
            remainingMinor: r['remaining_minor'] as int,
            isOpening: r['is_opening'] == 1,
            debtorId: person,
          ),
        );
      }
      final payments = <DebtorPayment>[];
      final newPayments = await txn.rawQuery(
        '''SELECT payment.*,document.occurred_at_utc FROM debtor_payments payment
JOIN business_documents document ON document.id=payment.document_id AND document.status='posted'
JOIN journal_entries entry ON entry.document_id=document.id AND entry.status='posted' ORDER BY document.occurred_at_utc DESC,document.id''',
      );
      for (final r in newPayments) {
        payments.add(
          DebtorPayment(
            id: r['document_id'] as String,
            debtorId: r['debtor_id'] as String,
            nameSnapshot: r['name_snapshot'] as String,
            amountMinor: r['amount_minor'] as int,
            occurredAtUtc: DateTime.parse(r['occurred_at_utc'] as String),
            paymentLabel: r['payment_label_snapshot'] as String,
          ),
        );
      }
      final links = {
        for (final r in rows) r['id'] as String: r['debtor_id'] as String?,
      };
      final immediate = await txn.query(
        'quick_sale_requests',
        columns: ['collection_command_id'],
      );
      final immediateIds = immediate
          .map((r) => r['collection_command_id'])
          .toSet();
      for (final c in oldCollections.collections) {
        final person = links[c.receivableId];
        if (person == null || immediateIds.contains(c.commandId)) continue;
        payments.add(
          DebtorPayment(
            id: c.documentId,
            debtorId: person,
            nameSnapshot: c.customerName,
            amountMinor: c.totalMinor,
            occurredAtUtc: c.collectedAtUtc,
            paymentLabel: c.parts
                .map((p) => p.paymentMethodName)
                .toSet()
                .join(' + '),
          ),
        );
      }
      payments.sort((a, b) => b.occurredAtUtc.compareTo(a.occurredAtUtc));
      final requests = await txn.query(
        'debtor_requests',
        where: "status='prepared'",
        orderBy: 'prepared_at_utc,command_id',
      );
      return DebtorsSnapshot(
        debtors: people
            .map(
              (p) => DebtorSummary(
                id: p['id'] as String,
                name: p['name'] as String,
                balanceMinor: _minor(balances[p['id']] ?? BigInt.zero),
                isActive: p['is_active'] == 1,
                hasOpening: p['has_opening'] == 1,
              ),
            )
            .toList(),
        charges: charges,
        payments: payments,
        paymentOptions: (await _options(txn))
            .map(
              (r) =>
                  DebtorPaymentOption(r['id'] as String, r['label'] as String),
            )
            .toList(),
        pending: requests.map(_prepared).toList(),
        unassignedLegacyMinor: _minor(await _legacyBalance(txn)),
        legacyPending: oldCollections.pendingCollections,
        confirmedCommands: (await txn.query(
          'debtor_requests',
          columns: ['command_id'],
          where: "status='confirmed'",
        )).map((r) => r['command_id'] as String).toSet(),
      );
    });
  }

  @override
  Future<PreparedDebtorCommand> prepare(DebtorCommand command) async {
    final input = _input(command);
    return database.database.transaction((txn) async {
      final prior = await txn.query(
        'debtor_requests',
        where: 'command_id=?',
        whereArgs: [command.commandId],
      );
      if (prior.isNotEmpty) {
        final payload =
            jsonDecode(prior.single['canonical_payload'] as String)
                as Map<String, dynamic>;
        if (jsonEncode(payload['input']) != jsonEncode(input) ||
            prior.single['status'] == 'discarded') {
          throw const DebtorsValidationException(
            'El identificador corresponde a otra solicitud o fue descartado.',
          );
        }
        return _prepared(prior.single);
      }
      final profile = await _profile(txn);
      final plan = await _plan(txn, command);
      final payload = jsonEncode({
        'version': 1,
        'profileId': profile.profileId,
        'currency': profile.currencyCode,
        'scale': profile.moneyScale,
        ...input,
        'debtorId': command.kind == 'create'
            ? InventoryIds.next()
            : command.debtorId,
        'input': input,
        'nameSnapshot': plan.name,
        'allocations': plan.allocations,
        'paymentOptionLabel': plan.option?['label'],
        'cashAccountId': plan.option?['cash_account_id'],
        'cashLedgerAccountId': plan.option?['ledger_account_id'],
        'paymentMethodId': plan.option?['payment_method_id'],
        'cashAccountName': plan.option?['cash_account_name'],
        'paymentMethodCode': plan.option?['payment_method_code'],
      });
      final row = {
        'command_id': command.commandId,
        'kind': command.kind,
        'canonical_payload': payload,
        'prepared_at_utc': DateTime.now().toUtc().toIso8601String(),
        'status': 'prepared',
      };
      await txn.insert('debtor_requests', row);
      return _prepared(row);
    }, exclusive: true);
  }

  @override
  Future<String> confirm(String commandId) => database.database.transaction((
    txn,
  ) async {
    final requests = await txn.query(
      'debtor_requests',
      where: 'command_id=?',
      whereArgs: [commandId],
    );
    if (requests.length != 1) {
      throw const DebtorsValidationException(
        'No existe la solicitud guardada.',
      );
    }
    final row = requests.single, canonical = row['canonical_payload'] as String;
    final old = await txn.query(
      'command_log',
      where: 'id=?',
      whereArgs: [commandId],
    );
    if (old.isNotEmpty) {
      final p =
          jsonDecode(old.single['response_json'] as String)
              as Map<String, dynamic>;
      if (old.single['command_type'] != 'debtor_operation' ||
          old.single['payload_hash'] != DatabaseSchema.checksum(canonical) ||
          p['canonicalPayload'] != canonical) {
        throw const DebtorsValidationException(
          'La respuesta no coincide con la solicitud original.',
        );
      }
      return (p['result'] as Map<String, dynamic>)['debtorId'] as String;
    }
    if (row['status'] != 'prepared') {
      throw const DebtorsValidationException(
        'La solicitud ya no está pendiente.',
      );
    }
    final payload = jsonDecode(canonical) as Map<String, dynamic>,
        prepared = _prepared(row),
        command = prepared.command;
    final profile = await _profile(txn);
    if (payload['profileId'] != profile.profileId ||
        payload['currency'] != profile.currencyCode ||
        payload['scale'] != profile.moneyScale) {
      throw const DebtorsValidationException(
        'El perfil cambió desde la preparación.',
      );
    }
    final plan = await _plan(
      txn,
      command,
      allocations: (payload['allocations'] as List)
          .cast<Map<String, dynamic>>(),
    );
    if (plan.name != payload['nameSnapshot'] ||
        plan.option?['cash_account_id'] != payload['cashAccountId'] ||
        plan.option?['payment_method_id'] != payload['paymentMethodId'] ||
        plan.option?['cash_account_name'] != payload['cashAccountName'] ||
        plan.option?['ledger_account_id'] != payload['cashLedgerAccountId'] ||
        plan.option?['payment_method_code'] != payload['paymentMethodCode'] ||
        plan.option?['label'] != payload['paymentOptionLabel']) {
      throw const DebtorsValidationException(
        'Cambió la persona o el medio de pago. Descarta la solicitud y revisa los datos.',
      );
    }
    final now = DateTime.now().toUtc().toIso8601String(),
        personId = payload['debtorId'] as String;
    final document =
        (command.kind == 'payment' ||
            command.kind == 'opening' ||
            (command.kind == 'create' && command.amountMinor > 0))
        ? InventoryIds.next()
        : null;
    await _operatorRow(txn, now);
    await txn.update(
      'debtor_requests',
      {'status': 'executing'},
      where: 'command_id=?',
      whereArgs: [commandId],
    );
    await txn.insert('command_log', {
      'id': commandId,
      'command_type': 'debtor_operation',
      'payload_hash': DatabaseSchema.checksum(canonical),
      'actor_id': _operator,
      'response_json': jsonEncode({
        'canonicalPayload': canonical,
        'result': {
          'debtorId': personId,
          'documentId': document,
          'amountMinor': command.amountMinor,
          'remainingMinor': command.kind == 'payment'
              ? _minor(plan.balance - BigInt.from(command.amountMinor))
              : command.kind == 'create'
              ? command.amountMinor
              : command.kind == 'opening'
              ? _minor(plan.balance + BigInt.from(command.amountMinor))
              : _minor(plan.balance),
        },
      }),
      'response_version': 1,
      'committed_at_utc': now,
      'authorization_policy_version': 'development-single-user-v1',
    });
    if (command.kind == 'create') {
      await txn.insert('debtors', {
        'id': personId,
        'name': plan.name,
        'name_key': _nameKey(plan.name),
        'is_active': 1,
        'created_command_id': commandId,
        'created_at_utc': now,
      });
    }
    if (document != null) {
      final entry = InventoryIds.next();
      await txn.insert('business_documents', {
        'id': document,
        'command_id': commandId,
        'command_sequence': 0,
        'profile_id': profile.profileId,
        'actor_id': _operator,
        'type': command.kind == 'payment'
            ? 'debtor_collection'
            : 'debtor_opening',
        'status': 'draft',
        'occurred_at_utc': command.occurredAtUtc.toIso8601String(),
        'business_date': _date(command.occurredAtUtc),
        'recorded_at_utc': now,
        'source_kind': synthetic ? 'synthetic' : 'native',
        'date_quality': command.kind == 'payment'
            ? 'documented'
            : 'reconstructed',
      });
      if (command.kind == 'create' || command.kind == 'opening') {
        await _account(
          txn,
          _control,
          'CXC',
          'Clientes por cobrar',
          'asset',
          'customer_receivable',
        );
        final offset =
            command.previousSource == PreviousDebtSource.includedInLegacy
            ? _legacy
            : 'debtors:opening-equity';
        if (command.previousSource == PreviousDebtSource.additional) {
          await _account(
            txn,
            offset,
            'DEBTOR:OPEN',
            'Patrimonio por saldos anteriores declarados',
            'equity',
            'opening_balance',
          );
        }
        await txn.insert('debtor_openings', {
          'document_id': document,
          'debtor_id': personId,
          'name_snapshot': plan.name,
          'source':
              command.previousSource == PreviousDebtSource.includedInLegacy
              ? 'legacy'
              : 'additional',
          'amount_minor': command.amountMinor,
          'offset_account_id': offset,
          'control_account_id': _control,
        });
        final receivable = InventoryIds.next();
        await txn.insert('debtor_receivables', {
          'receivable_id': receivable,
          'opening_document_id': document,
          'debtor_id': personId,
          'source': 'opening',
          'command_id': commandId,
          'assigned_at_utc': now,
        });
      } else {
        await txn.insert('debtor_payments', {
          'document_id': document,
          'debtor_id': personId,
          'name_snapshot': plan.name,
          'payment_option_id': command.paymentOptionId,
          'cash_account_id': payload['cashAccountId'],
          'payment_method_id': payload['paymentMethodId'],
          'payment_label_snapshot': payload['paymentOptionLabel'],
          'cash_account_name_snapshot': payload['cashAccountName'],
          'payment_method_code_snapshot': payload['paymentMethodCode'],
          'amount_minor': command.amountMinor,
        });
        for (var i = 0; i < plan.allocations.length; i++) {
          final a = plan.allocations[i];
          await txn.insert('debtor_payment_allocations', {
            'id': InventoryIds.next(),
            'collection_id': document,
            'receivable_id': a['receivableId'],
            'sequence': i,
            'amount_minor': a['amountMinor'],
          });
        }
      }
      await txn.insert('journal_entries', {
        'id': entry,
        'document_id': document,
        'status': 'draft',
        'cost_completeness': 'not_applicable',
      });
      final lines = await txn.query(
        'debtor_expected_journal',
        where: 'document_id=?',
        whereArgs: [document],
      );
      for (var i = 0; i < lines.length; i++) {
        await txn.insert('journal_lines', {
          'id': InventoryIds.next(),
          'entry_id': entry,
          'sequence': i,
          'account_id': lines[i]['account_id'],
          'debit_minor': lines[i]['debit_minor'],
          'credit_minor': lines[i]['credit_minor'],
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
    }
    if (command.kind == 'assign') {
      await txn.insert('debtor_receivables', {
        'receivable_id': command.receivableId,
        'sales_receivable_id': command.receivableId,
        'debtor_id': personId,
        'source': 'historical',
        'command_id': commandId,
        'assigned_at_utc': now,
      });
    }
    await txn.update(
      'debtor_requests',
      {'status': 'confirmed'},
      where: 'command_id=?',
      whereArgs: [commandId],
    );
    return personId;
  }, exclusive: true);

  Future<_Plan> _plan(
    DatabaseExecutor txn,
    DebtorCommand command, {
    List<Map<String, dynamic>>? allocations,
  }) async {
    _input(command);
    final legacy = await _legacyBalance(txn), rows = await _receivables(txn);
    if (command.kind == 'create') {
      final name = command.name!.trim();
      if ((await txn.query(
        'debtors',
        where: 'name_key=?',
        whereArgs: [_nameKey(name)],
      )).isNotEmpty) {
        throw const DebtorsValidationException(
          'Ya existe una persona con ese nombre. Selecciónala o añade un apellido para distinguirla.',
        );
      }
      if (command.amountMinor > 0) {
        if (command.previousSource == PreviousDebtSource.includedInLegacy &&
            legacy < BigInt.from(command.amountMinor)) {
          throw const DebtorsValidationException(
            'El importe supera la cartera anterior pendiente de asignar. Si no estaba registrado, elige Deuda adicional.',
          );
        }
        final total = rows.fold<BigInt>(
          legacy,
          (s, r) => s + BigInt.from(r['remaining_minor'] as int),
        );
        _minor(
          total +
              (command.previousSource == PreviousDebtSource.additional
                  ? BigInt.from(command.amountMinor)
                  : BigInt.zero),
        );
      }
      return _Plan(name, BigInt.from(command.amountMinor), [], null);
    }
    final people = await txn.query(
      'debtors',
      where: 'id=?',
      whereArgs: [command.debtorId],
    );
    if (people.length != 1) {
      throw const DebtorsValidationException(
        'Selecciona una persona registrada.',
      );
    }
    final person = people.single, name = person['name'] as String;
    final own = rows.where((r) => r['debtor_id'] == command.debtorId).toList();
    final balance = own.fold<BigInt>(
      BigInt.zero,
      (s, r) => s + BigInt.from(r['remaining_minor'] as int),
    );
    _minor(balance);
    if (command.kind == 'opening') {
      if ((await txn.query(
        'debtor_openings',
        where: 'debtor_id=?',
        whereArgs: [command.debtorId],
      )).isNotEmpty) {
        throw const DebtorsValidationException(
          'Esta persona ya tiene un saldo anterior registrado.',
        );
      }
      if (command.previousSource == PreviousDebtSource.includedInLegacy &&
          legacy < BigInt.from(command.amountMinor)) {
        throw const DebtorsValidationException(
          'El importe supera la cartera anterior pendiente de asignar.',
        );
      }
      final total = rows.fold<BigInt>(
        legacy,
        (s, r) => s + BigInt.from(r['remaining_minor'] as int),
      );
      _minor(
        total +
            (command.previousSource == PreviousDebtSource.additional
                ? BigInt.from(command.amountMinor)
                : BigInt.zero),
      );
      return _Plan(name, balance, [], null);
    }
    if (command.kind == 'assign') {
      final matches = rows.where((r) => r['id'] == command.receivableId);
      if (matches.length != 1 ||
          matches.single['debtor_id'] != null ||
          matches.single['remaining_minor'] == 0) {
        throw const DebtorsValidationException(
          'La deuda ya está asignada, saldada o no está disponible.',
        );
      }
      return _Plan(
        name,
        balance + BigInt.from(matches.single['remaining_minor'] as int),
        [],
        null,
      );
    }
    if (BigInt.from(command.amountMinor) > balance) {
      throw const DebtorsValidationException(
        'El abono no puede superar la deuda pendiente de esta persona.',
      );
    }
    final options = await _options(txn),
        option = options.where((r) => r['id'] == command.paymentOptionId);
    if (option.length != 1) {
      throw const DebtorsValidationException(
        'Selecciona Efectivo o Transferencia disponible.',
      );
    }
    final selected = option.single;
    final money = await _balances(txn);
    _signed(
      (money[selected['ledger_account_id']] ?? BigInt.zero) +
          BigInt.from(command.amountMinor),
    );
    final available = options
        .map((r) => r['ledger_account_id'])
        .toSet()
        .fold<BigInt>(BigInt.zero, (s, id) => s + (money[id] ?? BigInt.zero));
    _signed(available + BigInt.from(command.amountMinor));
    final later = await txn.rawQuery(
      '''SELECT document.occurred_at_utc FROM business_documents document JOIN journal_entries entry ON entry.document_id=document.id AND entry.status='posted'
JOIN journal_lines line ON line.entry_id=entry.id WHERE document.status='posted' AND line.account_id=?''',
      [selected['ledger_account_id']],
    );
    if (later.any(
      (r) => DateTime.parse(
        r['occurred_at_utc'] as String,
      ).isAfter(command.occurredAtUtc),
    )) {
      throw const DebtorsValidationException(
        'Hay un movimiento posterior en esa cuenta. Descarta la solicitud y prepara el abono de nuevo.',
      );
    }
    final planned = <Map<String, Object?>>[];
    if (allocations == null) {
      var remaining = command.amountMinor;
      for (final r in own.where((r) => (r['remaining_minor'] as int) > 0)) {
        final due = r['remaining_minor'] as int,
            amount = remaining < due ? remaining : due;
        planned.add({'receivableId': r['id'], 'amountMinor': amount});
        remaining -= amount;
        if (remaining == 0) break;
      }
    } else {
      var total = BigInt.zero;
      final seen = <String>{};
      for (final a in allocations) {
        final id = a['receivableId'] as String,
            amount = a['amountMinor'] as int;
        _minor(BigInt.from(amount));
        final matches = own.where((r) => r['id'] == id);
        if (!seen.add(id) ||
            amount <= 0 ||
            matches.length != 1 ||
            amount > (matches.single['remaining_minor'] as int)) {
          throw const DebtorsValidationException(
            'Cambió una deuda desde la preparación. Descarta la solicitud y revisa el abono.',
          );
        }
        total += BigInt.from(amount);
        planned.add({'receivableId': id, 'amountMinor': amount});
      }
      if (total != BigInt.from(command.amountMinor)) {
        throw const DebtorsValidationException(
          'El abono no coincide con sus aplicaciones guardadas.',
        );
      }
    }
    for (final a in planned) {
      final r = own.singleWhere((r) => r['id'] == a['receivableId']);
      if (DateTime.parse(
        r['issued_at_utc'] as String,
      ).isAfter(command.occurredAtUtc)) {
        throw const DebtorsValidationException(
          'El abono no puede ser anterior a la deuda.',
        );
      }
      final settlements = await txn.rawQuery(
        '''SELECT document.occurred_at_utc FROM all_receivable_settlements settlement JOIN business_documents document ON document.id=settlement.collection_id AND document.status='posted' WHERE settlement.receivable_id=?''',
        [a['receivableId']],
      );
      if (settlements.any(
        (s) => DateTime.parse(
          s['occurred_at_utc'] as String,
        ).isAfter(command.occurredAtUtc),
      )) {
        throw const DebtorsValidationException(
          'El abono no puede ser anterior a un pago ya registrado.',
        );
      }
    }
    return _Plan(name, balance, planned, selected);
  }

  @override
  Future<void> discard(String commandId) =>
      database.database.transaction((txn) async {
        await txn.update(
          'debtor_requests',
          {'status': 'discarded'},
          where: "command_id=? AND status='prepared'",
          whereArgs: [commandId],
        );
      }, exclusive: true);
  @override
  Future<void> setActive(String debtorId, bool active) =>
      database.database.transaction((txn) async {
        if ((await txn.query(
              'debtors',
              where: 'id=?',
              whereArgs: [debtorId],
            )).length !=
            1) {
          throw const DebtorsValidationException('La persona no existe.');
        }
        await txn.update(
          'debtors',
          {'is_active': active ? 1 : 0},
          where: 'id=?',
          whereArgs: [debtorId],
        );
      }, exclusive: true);
  @override
  Future<void> retryLegacyCollection(String id) async {
    await SqliteCollectionsStore(
      database,
      synthetic: synthetic,
    ).confirmPrepared(id);
  }

  @override
  Future<void> discardLegacyCollection(String id) => SqliteCollectionsStore(
    database,
    synthetic: synthetic,
  ).discardRejected(id);

  static Future<List<Map<String, Object?>>> _receivables(
    DatabaseExecutor txn,
  ) => txn.rawQuery(
    '''SELECT balance.*,link.debtor_id,
 coalesce(sale.label_snapshot,'Saldo anterior') label,CASE WHEN opening.document_id IS NULL THEN 0 ELSE 1 END is_opening,
 CASE WHEN request.command_id IS NOT NULL AND json_valid(request.canonical_payload) AND json_extract(request.canonical_payload,'\$.version') IN(2,3)
 THEN json_extract(request.canonical_payload,'\$.creditMinor') ELSE balance.initial_minor END credit_minor
 FROM customer_receivable_balances balance LEFT JOIN debtor_receivables link ON link.receivable_id=balance.id
 LEFT JOIN sales sale ON sale.document_id=balance.origin_document_id LEFT JOIN debtor_openings opening ON opening.document_id=balance.origin_document_id
 LEFT JOIN business_documents document ON document.id=balance.origin_document_id LEFT JOIN quick_sale_requests request ON request.sale_command_id=document.command_id
 WHERE sale.document_id IS NOT NULL OR opening.document_id IS NOT NULL ORDER BY balance.issued_at_utc,balance.id''',
  );
  static Future<List<Map<String, Object?>>> _options(
    DatabaseExecutor txn,
  ) => txn.rawQuery(
    '''SELECT option.*,cash.ledger_account_id,cash.name cash_account_name,method.code payment_method_code FROM quick_payment_options option
JOIN cash_accounts cash ON cash.id=option.cash_account_id JOIN ledger_accounts ledger ON ledger.id=cash.ledger_account_id JOIN payment_methods method ON method.id=option.payment_method_id
WHERE option.id IN('quick-default:EFECTIVO','quick-default:NEQUI') AND option.is_active=1 AND cash.is_active=1 AND cash.is_available=1 AND ledger.is_active=1
AND ledger.class='asset' AND ledger.role='cash' AND method.is_active=1 ORDER BY option.id''',
  );
  static Future<Map<String, BigInt>> _balances(DatabaseExecutor txn) async {
    final rows = await txn.rawQuery(
      '''SELECT line.account_id,line.debit_minor,line.credit_minor FROM journal_lines line JOIN journal_entries entry ON entry.id=line.entry_id AND entry.status='posted'
JOIN business_documents document ON document.id=entry.document_id AND document.status='posted' ''',
    );
    final result = <String, BigInt>{};
    for (final r in rows) {
      final id = r['account_id'] as String;
      result[id] =
          (result[id] ?? BigInt.zero) +
          BigInt.from(r['debit_minor'] as int) -
          BigInt.from(r['credit_minor'] as int);
    }
    return result;
  }

  static Future<BigInt> _legacyBalance(DatabaseExecutor txn) async =>
      (await _balances(txn))[_legacy] ?? BigInt.zero;
  static Future<BusinessProfile> _profile(DatabaseExecutor txn) async {
    final rows = await txn.query('app_profile', where: 'id=1');
    if (rows.length != 1) {
      throw const DebtorsValidationException(
        'Configura el espacio de trabajo primero.',
      );
    }
    final p = BusinessProfile.fromRow(rows.single);
    if (p.timezone != 'America/Bogota') {
      throw const DebtorsValidationException(
        'Deudores requiere la zona horaria America/Bogota.',
      );
    }
    return p;
  }

  static Future<void> _operatorRow(DatabaseExecutor txn, String now) async {
    final rows = await txn.query(
      'actors',
      where: 'id=?',
      whereArgs: [_operator],
    );
    if (rows.isEmpty) {
      await txn.insert('actors', {
        'id': _operator,
        'display_name': 'Operador local',
        'kind': 'system',
        'is_active': 1,
        'created_at_utc': now,
      });
    } else if (rows.single['kind'] != 'system' ||
        rows.single['is_active'] != 1) {
      throw const DebtorsValidationException('El operador no está disponible.');
    }
  }

  static Future<void> _account(
    DatabaseExecutor txn,
    String id,
    String code,
    String name,
    String type,
    String role,
  ) async {
    final rows = await txn.query(
      'ledger_accounts',
      where: 'id=? OR code=?',
      whereArgs: [id, code],
    );
    if (rows.isEmpty) {
      await txn.insert('ledger_accounts', {
        'id': id,
        'code': code,
        'name': name,
        'class': type,
        'role': role,
        'is_active': 1,
      });
    } else if (rows.length != 1 ||
        rows.single['id'] != id ||
        rows.single['class'] != type ||
        rows.single['role'] != role ||
        rows.single['is_active'] != 1) {
      throw const DebtorsValidationException(
        'La cuenta interna de deudas no está disponible.',
      );
    }
  }

  static Map<String, Object?> _input(DebtorCommand c) {
    for (final id in [
      c.commandId,
      ?c.debtorId,
      ?c.receivableId,
      ?c.paymentOptionId,
    ]) {
      if (!RegExp(r'^[A-Za-z0-9:_-]{1,128}$').hasMatch(id)) {
        throw const DebtorsValidationException('Identificador inválido.');
      }
    }
    if (c.kind == 'assign' && c.amountMinor != 0) {
      throw const DebtorsValidationException(
        'La asignación no modifica importes.',
      );
    }
    _minor(BigInt.from(c.amountMinor));
    _date(c.occurredAtUtc);
    if (!['create', 'opening', 'payment', 'assign'].contains(c.kind)) {
      throw const DebtorsValidationException('Operación desconocida.');
    }
    if (c.kind == 'opening' &&
        (c.amountMinor <= 0 || c.previousSource == null)) {
      throw const DebtorsValidationException(
        'Indica el importe positivo y la procedencia de la deuda anterior.',
      );
    }
    if (c.kind == 'create') {
      final name = c.name?.trim() ?? '';
      if (name.isEmpty ||
          name.length > 120 ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(name)) {
        throw const DebtorsValidationException(
          'Escribe un nombre de hasta 120 caracteres.',
        );
      }
      if (c.amountMinor > 0 && c.previousSource == null) {
        throw const DebtorsValidationException(
          'Indica si la deuda anterior ya estaba incluida en la cartera importada.',
        );
      }
    } else if (c.debtorId == null ||
        (c.kind == 'payment' &&
            (c.amountMinor <= 0 || c.paymentOptionId == null)) ||
        (c.kind == 'assign' && c.receivableId == null)) {
      throw const DebtorsValidationException(
        'Selecciona persona, importe y medio de pago cuando corresponda.',
      );
    }
    return {
      'kind': c.kind,
      'name': c.kind == 'create' ? c.name!.trim() : null,
      'debtorId': c.kind == 'create' ? null : c.debtorId,
      'amountMinor': c.amountMinor,
      'previousSource':
          (c.kind == 'create' || c.kind == 'opening') && c.amountMinor > 0
          ? (c.previousSource == PreviousDebtSource.includedInLegacy
                ? 'legacy'
                : 'additional')
          : null,
      'paymentOptionId': c.kind == 'payment' ? c.paymentOptionId : null,
      'receivableId': c.kind == 'assign' ? c.receivableId : null,
      'occurredAtUtc': c.occurredAtUtc.toIso8601String(),
    };
  }

  static PreparedDebtorCommand _prepared(Map<String, Object?> row) {
    final p =
            jsonDecode(row['canonical_payload'] as String)
                as Map<String, dynamic>,
        i = p['input'] as Map<String, dynamic>;
    return PreparedDebtorCommand(
      DebtorCommand(
        commandId: row['command_id'] as String,
        kind: i['kind'] as String,
        name: i['name'] as String?,
        debtorId: i['debtorId'] as String?,
        amountMinor: i['amountMinor'] as int,
        previousSource: i['previousSource'] == null
            ? null
            : i['previousSource'] == 'legacy'
            ? PreviousDebtSource.includedInLegacy
            : PreviousDebtSource.additional,
        paymentOptionId: i['paymentOptionId'] as String?,
        receivableId: i['receivableId'] as String?,
        occurredAtUtc: DateTime.parse(i['occurredAtUtc'] as String),
      ),
      p['nameSnapshot'] as String,
      row['status'] as String,
    );
  }

  static String _nameKey(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  static int _minor(BigInt n) {
    if (n < BigInt.zero || n > Money.maxMinorUnits) {
      throw const DebtorsValidationException(
        'La deuda o el importe supera el rango permitido.',
      );
    }
    return n.toInt();
  }

  static int _signed(BigInt n) {
    if (n < -Money.maxMinorUnits || n > Money.maxMinorUnits) {
      throw const DebtorsValidationException(
        'El saldo supera el rango permitido.',
      );
    }
    return n.toInt();
  }

  static String _date(DateTime n) {
    final local = n.subtract(const Duration(hours: 5));
    if (!n.isUtc || local.year < 1 || n.year > 9999) {
      throw const DebtorsValidationException('Fecha inválida.');
    }
    return local.toIso8601String().substring(0, 10);
  }
}

class _Plan {
  _Plan(this.name, this.balance, this.allocations, this.option);
  final String name;
  final BigInt balance;
  final List<Map<String, Object?>> allocations;
  final Map<String, Object?>? option;
}
