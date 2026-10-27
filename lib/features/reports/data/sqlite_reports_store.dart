import 'dart:convert';
import '../../../core/infrastructure/database/app_database.dart';
import '../../legacy_conversion/domain/legacy_time.dart';
import '../../treasury/domain/legacy_treasury_snapshot.dart';
import '../domain/reports_store.dart';

/// Pure read model. A single SQLite transaction supplies every report section.
class SqliteReportsStore implements ReportsStore {
  SqliteReportsStore(this.database);
  final AppDatabase database;

  @override
  Future<ReportsSnapshot> load(
    ReportPeriod period,
  ) => database.database.transaction((txn) async {
    final profile = await txn.query('app_profile');
    if (profile.length != 1 ||
        profile.single['business_timezone'] != 'America/Bogota') {
      throw const ReportsValidationException(
        'Configura un espacio de trabajo con zona horaria Bogotá.',
      );
    }
    final accounts = await txn.rawQuery('''SELECT cash.* FROM cash_accounts cash
JOIN ledger_accounts ledger ON ledger.id=cash.ledger_account_id AND ledger.class='asset' AND ledger.role='cash'
ORDER BY cash.name COLLATE NOCASE,cash.id''');
    final options = await txn.query('quick_payment_options');
    final roles = <String, ReportAccountRole>{
      'treasury:main-cash': ReportAccountRole.reserve,
    };
    for (final spec in [
      ('quick-default:EFECTIVO', ReportAccountRole.cash),
      ('quick-default:NEQUI', ReportAccountRole.transfer),
    ]) {
      final option = options.where((r) => r['id'] == spec.$1).firstOrNull;
      if (option != null) {
        roles[option['cash_account_id'] as String] = spec.$2;
      }
    }
    final journal = await txn.rawQuery(
      '''SELECT line.debit_minor,line.credit_minor,line.account_id,
ledger.role ledger_role,ledger.class ledger_class,document.id document_id,document.command_id,
document.occurred_at_utc,document.type,cash.id cash_id,cash.name cash_name
FROM journal_lines line JOIN journal_entries entry ON entry.id=line.entry_id AND entry.status='posted'
JOIN business_documents document ON document.id=entry.document_id AND document.status='posted'
JOIN ledger_accounts ledger ON ledger.id=line.account_id
LEFT JOIN cash_accounts cash ON cash.ledger_account_id=ledger.id
ORDER BY document.id,line.sequence,line.id''',
    );
    final imports = await txn.rawQuery(
      '''SELECT document.occurred_at_utc FROM treasury_openings opening
JOIN business_documents document ON document.id=opening.document_id AND document.status='posted'
JOIN journal_entries entry ON entry.document_id=document.id AND entry.status='posted' ''',
    );
    final importedDates =
        imports.map((r) => _date(r['occurred_at_utc'])).toList()..sort();
    final coverage = importedDates.firstOrNull;
    // The opening balance is strictly before the start instant. An imported
    // snapshot at that same instant supplies no preceding balance.
    var openingKnown = coverage == null || period.startUtc.isAfter(coverage);
    var closingKnown =
        coverage == null || period.endExclusiveUtc.isAfter(coverage);
    final nativeOpeningKnown = openingKnown, nativeClosingKnown = closingKnown;
    final warnings = <String>[
      'Categorías según clasificación actual. Precios, nombres y costos de venta conservan el valor registrado en cada operación.',
    ];

    final requests = await txn.query(
      'quick_sale_requests',
      where: "status='confirmed'",
    );
    final bySaleCommand = <String, Map<String, Object?>>{
      for (final r in requests) r['sale_command_id'] as String: r,
    };
    final immediateCollections = requests
        .map((r) => r['collection_command_id'])
        .toSet();
    final treasury = await txn.rawQuery(
      '''SELECT operation.*,document.occurred_at_utc FROM treasury_operations operation
JOIN business_documents document ON document.id=operation.document_id AND document.status='posted'
JOIN journal_entries entry ON entry.document_id=document.id AND entry.status='posted' ''',
    );
    final treasuryByDoc = {
      for (final r in treasury) r['document_id'] as String: r,
    };
    final eventRows = await txn.rawQuery(
      '''SELECT event.*,document.occurred_at_utc FROM events event
JOIN business_documents document ON document.id=event.document_id AND document.status='posted'
JOIN journal_entries entry ON entry.document_id=document.id AND entry.status='posted' ''',
    );
    final eventByDoc = {
      for (final r in eventRows) r['document_id'] as String: r,
    };
    final debtPayments = await txn.query('debtor_payments');
    final debtorByDoc = {
      for (final r in debtPayments)
        r['document_id'] as String: r['name_snapshot'] as String,
    };
    final collectionRows = await txn.query('collections');
    final collectionByDoc = {
      for (final r in collectionRows) r['document_id'] as String: r,
    };
    final supplierRows = await txn.query('supplier_payments');
    final supplierByDoc = {
      for (final r in supplierRows) r['document_id'] as String: r,
    };

    final opening = <String, BigInt>{}, closing = <String, BigInt>{};
    var debtOpening = BigInt.zero, debtClosing = BigInt.zero;
    final grouped = <(String, String), _CashMovement>{};
    final expenseGroups = <String, _Expense>{};
    for (final row in journal) {
      final date = _date(row['occurred_at_utc']),
          amount =
              BigInt.from(row['debit_minor'] as int) -
              BigInt.from(row['credit_minor'] as int);
      if (!date.isBefore(period.endExclusiveUtc)) continue;
      final isDebt =
          row['ledger_role'] == 'customer_receivable' ||
          row['account_id'] == 'system:legacy-customer-receivables';
      if (isDebt) {
        debtClosing += amount;
        if (date.isBefore(period.startUtc)) debtOpening += amount;
      }
      final cashId = row['cash_id'] as String?;
      if (cashId != null) {
        closing[cashId] = (closing[cashId] ?? BigInt.zero) + amount;
        if (date.isBefore(period.startUtc)) {
          opening[cashId] = (opening[cashId] ?? BigInt.zero) + amount;
        } else {
          final key = (row['document_id'] as String, cashId);
          grouped.putIfAbsent(key, () => _CashMovement(row)).amount += amount;
        }
      }
      if (period.contains(date) &&
          row['ledger_class'] == 'expense' &&
          !eventByDoc.containsKey(row['document_id'])) {
        expenseGroups
                .putIfAbsent(row['document_id'] as String, () => _Expense(row))
                .amount +=
            amount;
      }
    }
    final accountNames = {
      for (final a in accounts) a['id'] as String: a['name'] as String,
    };
    final movements = <ReportMovement>[];
    for (final movement in grouped.values) {
      final row = movement.row,
          doc = row['document_id'] as String,
          type = row['type'] as String;
      final op = treasuryByDoc[doc],
          event = eventByDoc[doc],
          collection = collectionByDoc[doc],
          supplier = supplierByDoc[doc];
      final kind = switch (type) {
        'cash_opening' || 'treasury_opening' => ReportMovementKind.opening,
        'cash_transfer' => ReportMovementKind.transfer,
        'cash_expense' => ReportMovementKind.expense,
        'event_creation' => ReportMovementKind.eventPayment,
        'debtor_collection' => ReportMovementKind.debtorPayment,
        'customer_collection'
            when immediateCollections.contains(row['command_id']) =>
          ReportMovementKind.saleReceipt,
        'customer_collection' => ReportMovementKind.debtorPayment,
        'supplier_payment' => ReportMovementKind.purchasePayment,
        _ => ReportMovementKind.other,
      };
      final concept = switch (kind) {
        ReportMovementKind.opening => 'Saldo inicial registrado',
        ReportMovementKind.saleReceipt =>
          'Venta: ${collection?['sale_label_snapshot'] ?? doc}',
        ReportMovementKind.debtorPayment =>
          'Abono: ${debtorByDoc[doc] ?? collection?['customer_name_snapshot'] ?? 'Cliente'}',
        ReportMovementKind.purchasePayment =>
          'Pago de compra: ${supplier?['supplier_name_snapshot'] ?? 'Proveedor'}',
        ReportMovementKind.expense => 'Gasto: ${op?['reason'] ?? 'Otro'}',
        ReportMovementKind.eventPayment =>
          'Costo fijo de evento: ${event?['name_snapshot'] ?? 'Evento'}',
        ReportMovementKind.transfer =>
          'Transferencia: ${op?['source_account_name_snapshot'] ?? 'Origen'} → ${op?['destination_account_name_snapshot'] ?? 'Destino'}',
        ReportMovementKind.other => 'Movimiento: $type',
      };
      movements.add(
        ReportMovement(
          id: '$doc:${row['cash_id']}',
          documentId: doc,
          occurredAtUtc: _date(row['occurred_at_utc']),
          accountId: row['cash_id'] as String,
          accountName: row['cash_name'] as String,
          kind: kind,
          concept: concept,
          amountMinor: reportMinor(movement.amount),
          reason: op?['reason'] as String? ?? '',
        ),
      );
    }
    movements.sort((a, b) => b.occurredAtUtc.compareTo(a.occurredAtUtc));

    final saleRows = await txn.rawQuery(
      '''SELECT line.*,sale.label_snapshot,document.command_id,document.occurred_at_utc,
catalog.category_id,category.name category_name,event.product_id event_product_id
FROM sale_lines line JOIN sales sale ON sale.document_id=line.sale_id
JOIN business_documents document ON document.id=sale.document_id AND document.status='posted'
JOIN journal_entries entry ON entry.document_id=document.id AND entry.status='posted'
JOIN catalog_items catalog ON catalog.id=line.product_id LEFT JOIN categories category ON category.id=catalog.category_id
LEFT JOIN events event ON event.product_id=line.product_id
ORDER BY document.occurred_at_utc,document.id,line.sequence''',
    );
    final tenders = <(String, String), _Tender>{};
    for (final table in [
      'quick_sale_line_payments',
      'quick_sale_line_tenders',
    ]) {
      for (final row in await txn.query(table)) {
        final key = (
          row['sale_document_id'] as String,
          row['product_id'] as String,
        );
        final tender = tenders.putIfAbsent(key, _Tender.new),
            amount = BigInt.from(row['total_minor'] as int);
        if (row['is_credit'] == 1) {
          tender.credit += amount;
        } else {
          final role = roles[row['cash_account_id']];
          if (role == ReportAccountRole.cash) {
            tender.cash += amount;
          } else if (role == ReportAccountRole.transfer) {
            tender.transfer += amount;
          } else {
            tender.other += amount;
          }
        }
      }
    }
    final sales = <ReportSaleLine>[];
    var hasOtherSelectedTender = false;
    for (final row in saleRows) {
      final date = _date(row['occurred_at_utc']);
      if (!period.contains(date)) continue;
      final quick = bySaleCommand[row['command_id']],
          gross = BigInt.from(row['total_minor'] as int);
      final tender =
          tenders[(row['sale_id'] as String, row['product_id'] as String)] ??
          _Tender();
      hasOtherSelectedTender =
          hasOtherSelectedTender || tender.other != BigInt.zero;
      final credit = quick == null ? gross : tender.credit;
      if (quick != null &&
          gross !=
              tender.cash + tender.transfer + tender.other + tender.credit) {
        throw const ReportsValidationException(
          'Una venta no coincide con sus formas de pago registradas.',
        );
      }
      sales.add(
        ReportSaleLine(
          id: row['id'] as String,
          documentId: row['sale_id'] as String,
          saleLabel: row['label_snapshot'] as String,
          occurredAtUtc: date,
          productId: row['product_id'] as String,
          productName: row['name_snapshot'] as String,
          categoryId: row['category_id'] as String? ?? '',
          categoryName: row['category_name'] as String? ?? 'Sin categoría',
          quantity: row['quantity'] as int,
          salesMinor: row['total_minor'] as int,
          costMinor: row['total_cost_minor'] as int,
          cashMinor: reportMinor(tender.cash),
          transferMinor: reportMinor(tender.transfer),
          creditMinor: reportMinor(credit),
          isEvent: row['event_product_id'] != null,
        ),
      );
    }
    if (hasOtherSelectedTender) {
      warnings.add(
        'Hay ventas cobradas en otras cuentas locales. El total de ventas las incluye; consulta sus movimientos por cuenta.',
      );
    }
    final transfers = <ReportTransfer>[
      for (final op in treasury.where(
        (op) =>
            op['kind'] == 'transfer' &&
            period.contains(_date(op['occurred_at_utc'])),
      ))
        ReportTransfer(
          documentId: op['document_id'] as String,
          occurredAtUtc: _date(op['occurred_at_utc']),
          sourceAccountId: op['source_account_id'] as String,
          sourceName: op['source_account_name_snapshot'] as String,
          destinationAccountId: op['destination_account_id'] as String,
          destinationName: op['destination_account_name_snapshot'] as String,
          amountMinor: op['amount_minor'] as int,
          note: op['note'] as String? ?? '',
        ),
    ];
    final expenses = <ReportExpense>[
      for (final expense in expenseGroups.values)
        ReportExpense(
          documentId: expense.row['document_id'] as String,
          occurredAtUtc: _date(expense.row['occurred_at_utc']),
          reason:
              treasuryByDoc[expense.row['document_id']]?['reason'] as String? ??
              'Otro',
          concept:
              treasuryByDoc[expense.row['document_id']]?['note'] as String? ??
              'Gasto registrado',
          amountMinor: reportMinor(expense.amount),
          isEvent: false,
        ),
      for (final event in eventRows.where(
        (e) => period.contains(_date(e['occurred_at_utc'])),
      ))
        ReportExpense(
          documentId: event['document_id'] as String,
          occurredAtUtc: _date(event['occurred_at_utc']),
          reason: 'Evento',
          concept: event['name_snapshot'] as String,
          amountMinor: event['total_cost_minor'] as int,
          isEvent: true,
        ),
    ];
    final openingRows = await txn.rawQuery(
      '''SELECT opening.*,document.occurred_at_utc FROM debtor_openings opening
JOIN business_documents document ON document.id=opening.document_id AND document.status='posted'
JOIN journal_entries entry ON entry.document_id=document.id AND entry.status='posted' ''',
    );
    final debtChanges = <ReportDebtChange>[
      for (final opening in openingRows.where(
        (o) => period.contains(_date(o['occurred_at_utc'])),
      ))
        ReportDebtChange(
          documentId: opening['document_id'] as String,
          occurredAtUtc: _date(opening['occurred_at_utc']),
          concept: 'Saldo anterior: ${opening['name_snapshot']}',
          amountMinor: opening['amount_minor'] as int,
          isLegacyAssignment: opening['source'] == 'legacy',
        ),
    ];
    final eventResults = <ReportEventResult>[];
    for (final event in eventRows.where(
      (e) => _date(e['occurred_at_utc']).isBefore(period.endExclusiveUtc),
    )) {
      final lines = saleRows.where(
        (l) =>
            l['product_id'] == event['product_id'] &&
            _date(l['occurred_at_utc']).isBefore(period.endExclusiveUtc),
      );
      eventResults.add(
        ReportEventResult(
          productId: event['product_id'] as String,
          name: event['name_snapshot'] as String,
          createdAtUtc: _date(event['occurred_at_utc']),
          quantity: reportSum(lines.map((l) => l['quantity'] as int)),
          salesMinor: reportSum(lines.map((l) => l['total_minor'] as int)),
          costMinor: event['total_cost_minor'] as int,
        ),
      );
    }
    final converted = await txn.query(
      'legacy_conversions',
      where: "status='complete'",
    );
    final nativeSaleTotals = ReportSalesTotals.fromNative(sales);
    final unpriced = [0, 0, 0, 0];
    final estimated = [BigInt.zero, BigInt.zero, BigInt.zero, BigInt.zero];
    var estimatedSales = 0;
    if (converted.isNotEmpty) {
      final legacySales = await txn.rawQuery('''
SELECT sale.row_json, product.row_json product_json
FROM legacy_source_rows sale
LEFT JOIN legacy_source_rows product ON product.source_table='products'
  AND product.source_id=json_extract(sale.row_json, '\$.productId')
  AND product.conversion_id=sale.conversion_id
WHERE sale.source_table='sales' ''');
      for (final row in legacySales) {
        final archived =
            jsonDecode(row['row_json'] as String) as Map<String, dynamic>;
        DateTime? date;
        try {
          date = parseLegacyDate(archived['date']);
        } on FormatException {
          throw const ReportsValidationException(
            'Una venta antigua no tiene una fecha válida para ubicarla en el reporte.',
          );
        }
        if (date == null) {
          throw const ReportsValidationException(
            'Una venta antigua no tiene fecha para ubicarla en el reporte.',
          );
        }
        if (!period.contains(date)) continue;
        final method = (archived['paymentMethod'] as String? ?? '')
            .trim()
            .toLowerCase();
        final group = switch (method) {
          'efectivo' || 'caja' || 'cash' => 0,
          'nequi' || 'transferencia' || 'transfer' => 1,
          'deudas' || 'deuda' || 'crédito' || 'credito' => 2,
          _ => 3,
        };
        // Join only the immutable archived product, never today's catalog.
        final productJson = row['product_json'] as String?;
        final quantity = archived['quantity'];
        int? price;
        if (productJson != null && quantity is int && quantity >= 0) {
          final product = jsonDecode(productJson) as Map<String, dynamic>;
          try {
            price = legacyTreasuryAmountToMinor(
              '${product['price']}',
              moneyScale: profile.single['money_scale'] as int,
            );
          } on LegacyTreasuryFormatException {
            // Missing, invalid or unrepresentable prices remain unknown.
          }
        }
        if (price == null || price < 0) {
          unpriced[group]++;
        } else {
          estimated[group] += BigInt.from(price) * BigInt.from(quantity as int);
          estimatedSales++;
        }
      }
    }
    final saleTotals = ReportSalesTotals(
      cashMinor: nativeSaleTotals.cashMinor,
      transferMinor: nativeSaleTotals.transferMinor,
      creditMinor: nativeSaleTotals.creditMinor,
      otherMinor: nativeSaleTotals.otherMinor,
      estimatedCashMinor: reportMinor(estimated[0]),
      estimatedTransferMinor: reportMinor(estimated[1]),
      estimatedCreditMinor: reportMinor(estimated[2]),
      estimatedOtherMinor: reportMinor(estimated[3]),
      estimatedSales: estimatedSales,
      unpricedCashSales: unpriced[0],
      unpricedTransferSales: unpriced[1],
      unpricedCreditSales: unpriced[2],
      unpricedOtherSales: unpriced[3],
    );
    var historyUsed = false;
    Future<int?> historical(String role, DateTime before) async {
      if (converted.isEmpty) return null;
      final rows = await txn.query(
        'legacy_balance_history',
        columns: ['amount_minor'],
        where: 'role=? AND occurred_at_utc < ?',
        whereArgs: [role, legacyUtcKey(before)],
        orderBy: 'occurred_at_utc DESC, source_id DESC',
        limit: 1,
      );
      if (rows.isEmpty) return null;
      historyUsed = true;
      return rows.single['amount_minor'] as int;
    }

    final resolvedAccounts = <ReportAccount>[];
    for (final account in accounts) {
      final role = roles[account['id']] ?? ReportAccountRole.other;
      final legacyRole = switch (role) {
        ReportAccountRole.cash => 'cash',
        ReportAccountRole.transfer => 'nequi',
        ReportAccountRole.reserve => 'reserve',
        _ => '',
      };
      resolvedAccounts.add(
        ReportAccount(
          id: account['id'] as String,
          name: accountNames[account['id']]!,
          role: role,
          openingMinor: nativeOpeningKnown
              ? reportMinor(opening[account['id']] ?? BigInt.zero)
              : await historical(legacyRole, period.startUtc),
          closingMinor: nativeClosingKnown
              ? reportMinor(closing[account['id']] ?? BigInt.zero)
              : await historical(legacyRole, period.endExclusiveUtc),
        ),
      );
    }
    if (converted.isNotEmpty) {
      final visible = resolvedAccounts
          .where(
            (a) =>
                a.role == ReportAccountRole.cash ||
                a.role == ReportAccountRole.transfer,
          )
          .toList();
      openingKnown =
          visible.length == 2 && visible.every((a) => a.openingMinor != null);
      closingKnown =
          visible.length == 2 && visible.every((a) => a.closingMinor != null);
    }
    final resolvedDebtOpening = nativeOpeningKnown
        ? reportMinor(debtOpening)
        : await historical('receivables', period.startUtc);
    final resolvedDebtClosing = nativeClosingKnown
        ? reportMinor(debtClosing)
        : await historical('receivables', period.endExclusiveUtc);
    if (!openingKnown) {
      warnings.add(
        'No hay información suficiente para todos los saldos iniciales.',
      );
    }
    if (!closingKnown) {
      warnings.add(
        'No hay información suficiente para todos los saldos finales.',
      );
    }
    if (historyUsed) {
      warnings.add(
        'Los saldos anteriores a la apertura usan el historial convertido, en hora de Bogotá.',
      );
    }
    final result = ReportsSnapshot(
      period: period,
      accounts: resolvedAccounts,
      movements: movements,
      sales: sales,
      transfers: transfers,
      expenses: expenses,
      debtChanges: debtChanges,
      events: eventResults,
      debtOpeningMinor: resolvedDebtOpening,
      debtClosingMinor: resolvedDebtClosing,
      coverageStartUtc: coverage,
      openingBalancesKnown: openingKnown,
      closingBalancesKnown: closingKnown,
      usesHistoricalBalances: historyUsed,
      saleTotals: saleTotals,
      warnings: warnings,
    );
    result.validate();
    return result;
  });

  static DateTime _date(Object? value) =>
      DateTime.parse(value as String).toUtc();
}

class _CashMovement {
  _CashMovement(this.row);
  final Map<String, Object?> row;
  BigInt amount = BigInt.zero;
}

class _Expense {
  _Expense(this.row);
  final Map<String, Object?> row;
  BigInt amount = BigInt.zero;
}

class _Tender {
  BigInt cash = BigInt.zero,
      transfer = BigInt.zero,
      credit = BigInt.zero,
      other = BigInt.zero;
}
