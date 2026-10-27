import '../../../core/domain/money.dart';

int reportSum(Iterable<int> values) => reportMinor(
  values.fold(BigInt.zero, (sum, value) => sum + BigInt.from(value)),
);
int reportMinor(BigInt value) {
  if (value < Money.minMinorUnits || value > Money.maxMinorUnits) {
    throw const ReportsValidationException(
      'El reporte supera el rango monetario permitido. Reduce el rango de fechas.',
    );
  }
  return value.toInt();
}

class ReportPeriod {
  ReportPeriod({required DateTime start, required DateTime end})
    : startDate = DateTime.utc(start.year, start.month, start.day),
      endDate = DateTime.utc(end.year, end.month, end.day),
      endExclusiveUtc = DateTime.utc(
        end.year,
        end.month,
        end.day,
      ).add(const Duration(days: 1, hours: 5)) {
    _validate();
  }

  /// Wall-clock minutes in Bogotá, including the entire selected final minute.
  ReportPeriod.timed({required DateTime start, required DateTime end})
    : startDate = DateTime.utc(
        start.year,
        start.month,
        start.day,
        start.hour,
        start.minute,
      ),
      endDate = DateTime.utc(
        end.year,
        end.month,
        end.day,
        end.hour,
        end.minute,
      ),
      endExclusiveUtc = DateTime.utc(
        end.year,
        end.month,
        end.day,
        end.hour,
        end.minute,
      ).add(const Duration(hours: 5, minutes: 1)) {
    _validate();
  }

  void _validate() {
    if (startDate.isAfter(endDate) ||
        startDate.year < 1 ||
        endDate.year > 9998) {
      throw const ReportsValidationException(
        'Elige un rango de fechas válido.',
      );
    }
  }

  final DateTime startDate, endDate;
  DateTime get startUtc => startDate.add(const Duration(hours: 5));
  final DateTime endExclusiveUtc;
  DateTime get startLocal => startDate;
  DateTime get endLocal =>
      endExclusiveUtc.subtract(const Duration(hours: 5, minutes: 1));
  bool contains(DateTime utc) =>
      !utc.isBefore(startUtc) && utc.isBefore(endExclusiveUtc);
}

enum ReportMovementKind {
  saleReceipt,
  debtorPayment,
  purchasePayment,
  expense,
  eventPayment,
  transfer,
  opening,
  other,
}

enum ReportAccountRole { cash, transfer, reserve, other }

class ReportAccount {
  const ReportAccount({
    required this.id,
    required this.name,
    required this.role,
    required this.openingMinor,
    required this.closingMinor,
  });
  final String id, name;
  final ReportAccountRole role;
  final int? openingMinor, closingMinor;
}

class ReportMovement {
  const ReportMovement({
    required this.id,
    required this.documentId,
    required this.occurredAtUtc,
    required this.accountId,
    required this.accountName,
    required this.kind,
    required this.concept,
    required this.amountMinor,
    this.reason = '',
  });
  final String id, documentId, accountId, accountName, concept, reason;
  final DateTime occurredAtUtc;
  final ReportMovementKind kind;

  /// Signed account amount. A transfer has one outgoing and one incoming leg.
  final int amountMinor;
}

class ReportSaleLine {
  const ReportSaleLine({
    required this.id,
    required this.documentId,
    required this.saleLabel,
    required this.occurredAtUtc,
    required this.productId,
    required this.productName,
    required this.categoryId,
    required this.categoryName,
    required this.quantity,
    required this.salesMinor,
    required this.costMinor,
    required this.cashMinor,
    required this.transferMinor,
    required this.creditMinor,
    required this.isEvent,
  });
  final String id,
      documentId,
      saleLabel,
      productId,
      productName,
      categoryId,
      categoryName;
  final DateTime occurredAtUtc;
  final int quantity,
      salesMinor,
      costMinor,
      cashMinor,
      transferMinor,
      creditMinor;
  final bool isEvent;
  int get marginMinor =>
      reportMinor(BigInt.from(salesMinor) - BigInt.from(costMinor));
}

class ReportItem {
  const ReportItem({
    required this.id,
    required this.productName,
    required this.occurredAtUtc,
    required this.quantity,
    required this.amountMinor,
    required this.paymentMethod,
    this.isEstimated = false,
  });
  factory ReportItem.fromSale(ReportSaleLine sale) => ReportItem(
    id: sale.id,
    productName: sale.productName,
    occurredAtUtc: sale.occurredAtUtc,
    quantity: sale.quantity,
    amountMinor: sale.salesMinor,
    paymentMethod: [
      if (sale.cashMinor > 0) 'Efectivo',
      if (sale.transferMinor > 0) 'Transferencia',
      if (sale.creditMinor > 0) 'Deudas',
      if (BigInt.from(sale.salesMinor) >
          BigInt.from(sale.cashMinor) +
              BigInt.from(sale.transferMinor) +
              BigInt.from(sale.creditMinor))
        'Otro',
      if (sale.salesMinor == 0) 'Sin cobro',
    ].join(' / '),
  );
  final String id, productName, paymentMethod;
  final DateTime occurredAtUtc;
  final int? quantity, amountMinor;
  final bool isEstimated;
}

class ReportProduct {
  const ReportProduct({
    required this.productId,
    required this.name,
    required this.categoryId,
    required this.categoryName,
    required this.quantity,
    required this.salesMinor,
    required this.costMinor,
    required this.isEvent,
  });
  final String productId, name, categoryId, categoryName;
  final int quantity, salesMinor, costMinor;
  final bool isEvent;
  int get marginMinor =>
      reportMinor(BigInt.from(salesMinor) - BigInt.from(costMinor));
}

class ReportTransfer {
  const ReportTransfer({
    required this.documentId,
    required this.occurredAtUtc,
    required this.sourceAccountId,
    required this.sourceName,
    required this.destinationAccountId,
    required this.destinationName,
    required this.amountMinor,
    required this.note,
    this.isHistorical = false,
  });
  final String documentId,
      sourceAccountId,
      sourceName,
      destinationAccountId,
      destinationName,
      note;
  final DateTime occurredAtUtc;
  final int amountMinor;
  final bool isHistorical;
}

class ReportTransferRoute {
  const ReportTransferRoute({
    required this.sourceName,
    required this.destinationName,
    required this.count,
    required this.amountMinor,
  });
  final String sourceName, destinationName;
  final int count, amountMinor;
}

String _transferAccountName(String name) => switch (name.trim().toLowerCase()) {
  'caja' || 'efectivo' || 'cash' => 'Caja',
  'nequi' || 'transferencia' || 'transfer' => 'Nequi',
  'caja mayor' => 'Caja mayor',
  'deudas' => 'Deudas',
  _ => name.trim().isEmpty ? 'Cuenta sin información' : name.trim(),
};

class ReportExpense {
  const ReportExpense({
    required this.documentId,
    required this.occurredAtUtc,
    required this.reason,
    required this.concept,
    required this.amountMinor,
    required this.isEvent,
  });
  final String documentId, reason, concept;
  final DateTime occurredAtUtc;
  final int amountMinor;
  final bool isEvent;
}

class ReportDebtChange {
  const ReportDebtChange({
    required this.documentId,
    required this.occurredAtUtc,
    required this.concept,
    required this.amountMinor,
    required this.isLegacyAssignment,
  });
  final String documentId, concept;
  final DateTime occurredAtUtc;
  final int amountMinor;
  final bool isLegacyAssignment;
}

class ReportEventResult {
  const ReportEventResult({
    required this.productId,
    required this.name,
    required this.createdAtUtc,
    required this.quantity,
    required this.salesMinor,
    required this.costMinor,
  });
  final String productId, name;
  final DateTime createdAtUtc;

  /// Lifetime inscriptions through the report's final day, including credit.
  final int quantity, salesMinor, costMinor;
  int get resultMinor =>
      reportMinor(BigInt.from(salesMinor) - BigInt.from(costMinor));
}

class ReportDebtorBalance {
  const ReportDebtorBalance({
    required this.id,
    required this.name,
    required this.amountMinor,
  });
  final String id, name;
  final int amountMinor;
}

class ReportsSnapshot {
  ReportsSnapshot({
    required this.period,
    required List<ReportAccount> accounts,
    required List<ReportMovement> movements,
    required List<ReportSaleLine> sales,
    List<ReportItem>? items,
    List<ReportDebtorBalance> debtorBalances = const [],
    required List<ReportTransfer> transfers,
    required List<ReportExpense> expenses,
    required List<ReportDebtChange> debtChanges,
    required List<ReportEventResult> events,
    required this.debtOpeningMinor,
    required this.debtClosingMinor,
    required this.coverageStartUtc,
    required this.openingBalancesKnown,
    this.closingBalancesKnown = true,
    this.usesHistoricalBalances = false,
    ReportSalesTotals? saleTotals,
    ReportOutflowTotals? outflowTotals,
    this.unpricedTransferRecords = 0,
    required List<String> warnings,
  }) : saleTotals = saleTotals ?? ReportSalesTotals.fromNative(sales),
       outflowTotals =
           outflowTotals ?? ReportOutflowTotals.fromNative(movements, accounts),
       items = List.unmodifiable(
         (items ?? sales.map(ReportItem.fromSale).toList()).toList()
           ..sort((a, b) {
             final date = b.occurredAtUtc.compareTo(a.occurredAtUtc);
             return date == 0 ? a.id.compareTo(b.id) : date;
           }),
       ),
       debtorBalances = List.unmodifiable(debtorBalances),
       accounts = List.unmodifiable(accounts),
       movements = List.unmodifiable(movements),
       sales = List.unmodifiable(sales),
       transfers = List.unmodifiable(transfers),
       expenses = List.unmodifiable(expenses),
       debtChanges = List.unmodifiable(debtChanges),
       events = List.unmodifiable(events),
       warnings = List.unmodifiable(warnings);
  final ReportPeriod period;
  final List<ReportAccount> accounts;
  final List<ReportMovement> movements;
  final List<ReportSaleLine> sales;
  final List<ReportItem> items;

  /// Outstanding ownership at the final cutoff, including unassigned debt.
  final List<ReportDebtorBalance> debtorBalances;
  final List<ReportTransfer> transfers;
  final List<ReportExpense> expenses;
  final List<ReportDebtChange> debtChanges;
  final List<ReportEventResult> events;
  final int? debtOpeningMinor, debtClosingMinor;
  final DateTime? coverageStartUtc;
  final bool openingBalancesKnown;
  final bool closingBalancesKnown;
  final bool usesHistoricalBalances;
  final List<String> warnings;
  final ReportSalesTotals saleTotals;
  final ReportOutflowTotals outflowTotals;
  final int unpricedTransferRecords;
  int get knownTransferTotalMinor =>
      reportSum(transfers.map((t) => t.amountMinor));
  int? get transferTotalMinor =>
      unpricedTransferRecords == 0 ? knownTransferTotalMinor : null;
  List<ReportTransferRoute> get transferRoutes {
    final grouped = <(String, String), List<ReportTransfer>>{};
    for (final transfer in transfers) {
      grouped
          .putIfAbsent((
            _transferAccountName(transfer.sourceName),
            _transferAccountName(transfer.destinationName),
          ), () => [])
          .add(transfer);
    }
    return List.unmodifiable(
      grouped.entries
          .map(
            (e) => ReportTransferRoute(
              sourceName: e.key.$1,
              destinationName: e.key.$2,
              count: e.value.length,
              amountMinor: reportSum(e.value.map((t) => t.amountMinor)),
            ),
          )
          .toList()
        ..sort((a, b) {
          final source = a.sourceName.compareTo(b.sourceName);
          return source == 0
              ? a.destinationName.compareTo(b.destinationName)
              : source;
        }),
    );
  }

  int get salesMinor => reportSum(sales.map((s) => s.salesMinor));
  int get creditSalesMinor => reportSum(sales.map((s) => s.creditMinor));
  int get costOfGoodsMinor =>
      reportSum(sales.where((s) => !s.isEvent).map((s) => s.costMinor));
  int get physicalMarginMinor =>
      reportSum(sales.where((s) => !s.isEvent).map((s) => s.marginMinor));
  int get eventCostsMinor =>
      reportSum(expenses.where((s) => s.isEvent).map((s) => s.amountMinor));
  int get operatingExpensesMinor =>
      reportSum(expenses.where((s) => !s.isEvent).map((s) => s.amountMinor));
  int get operatingResultMinor => reportMinor(
    BigInt.from(salesMinor) -
        BigInt.from(costOfGoodsMinor) -
        BigInt.from(eventCostsMinor) -
        BigInt.from(operatingExpensesMinor),
  );
  int get saleReceiptsMinor => reportSum(
    movements
        .where((m) => m.kind == ReportMovementKind.saleReceipt)
        .map((m) => m.amountMinor),
  );
  int get debtorPaymentsMinor => reportSum(
    movements
        .where((m) => m.kind == ReportMovementKind.debtorPayment)
        .map((m) => m.amountMinor),
  );
  int get outflowsMinor => reportMinor(
    movements
        .where(
          (m) =>
              m.amountMinor < 0 &&
              m.kind != ReportMovementKind.transfer &&
              m.kind != ReportMovementKind.opening,
        )
        .fold(BigInt.zero, (sum, m) => sum - BigInt.from(m.amountMinor)),
  );
  int get additionalDebtMinor => reportSum(
    debtChanges.where((d) => !d.isLegacyAssignment).map((d) => d.amountMinor),
  );

  /// Validate totals before a report is exposed to presentation code. Although
  /// final balances can fit in SQLite's range, gross movement totals may not.
  void validate() {
    saleTotals.validate();
    outflowTotals.validate();
    if (unpricedTransferRecords < 0 ||
        transfers.any((t) => t.amountMinor < 0)) {
      throw const ReportsValidationException(
        'El reporte de transferencias contiene valores inválidos.',
      );
    }
    salesMinor;
    creditSalesMinor;
    costOfGoodsMinor;
    physicalMarginMinor;
    eventCostsMinor;
    operatingExpensesMinor;
    operatingResultMinor;
    saleReceiptsMinor;
    debtorPaymentsMinor;
    outflowsMinor;
    additionalDebtMinor;
    reportSum(sales.map((s) => s.quantity));
    reportSum(transfers.map((t) => t.amountMinor));
    reportSum(debtChanges.map((d) => d.amountMinor));
    // Every table/filter/chart subgroup is a subset of one of these bounded
    // sign-specific totals, so it cannot overflow while being rendered.
    reportSum(
      movements.where((m) => m.amountMinor > 0).map((m) => m.amountMinor),
    );
    reportMinor(
      movements
          .where((m) => m.amountMinor < 0)
          .fold(BigInt.zero, (sum, m) => sum - BigInt.from(m.amountMinor)),
    );
    reportSum(
      sales
          .where((s) => !s.isEvent && s.marginMinor > 0)
          .map((s) => s.marginMinor),
    );
    reportSum(
      sales
          .where((s) => !s.isEvent && s.marginMinor < 0)
          .map((s) => s.marginMinor),
    );
    for (final product in products()) {
      product.marginMinor;
    }
    for (final event in events) {
      event.resultMinor;
    }
  }

  List<ReportSaleLine> filteredSales({String? categoryId, String? productId}) =>
      sales
          .where(
            (s) =>
                (categoryId == null || s.categoryId == categoryId) &&
                (productId == null || s.productId == productId),
          )
          .toList(growable: false);
  List<ReportProduct> products({String? categoryId, String? productId}) {
    final grouped = <String, List<ReportSaleLine>>{};
    for (final line in filteredSales(
      categoryId: categoryId,
      productId: productId,
    )) {
      grouped.putIfAbsent(line.productId, () => []).add(line);
    }
    return grouped.values.map((lines) {
      final first = lines.first;
      return ReportProduct(
        productId: first.productId,
        name: first.productName,
        categoryId: first.categoryId,
        categoryName: first.categoryName,
        quantity: reportSum(lines.map((s) => s.quantity)),
        salesMinor: reportSum(lines.map((s) => s.salesMinor)),
        costMinor: reportSum(lines.map((s) => s.costMinor)),
        isEvent: first.isEvent,
      );
    }).toList()..sort((a, b) => a.name.compareTo(b.name));
  }
}

/// Sale revenue by the tender chosen when confirming the sale. Collections of
/// old debt, openings and transfers between accounts never enter these totals.
class ReportSalesTotals {
  const ReportSalesTotals({
    required this.cashMinor,
    required this.transferMinor,
    required this.creditMinor,
    this.otherMinor = 0,
    this.estimatedCashMinor = 0,
    this.estimatedTransferMinor = 0,
    this.estimatedCreditMinor = 0,
    this.estimatedOtherMinor = 0,
    this.estimatedSales = 0,
    this.unpricedCashSales = 0,
    this.unpricedTransferSales = 0,
    this.unpricedCreditSales = 0,
    this.unpricedOtherSales = 0,
  });
  factory ReportSalesTotals.fromNative(Iterable<ReportSaleLine> sales) {
    final cash = reportSum(sales.map((s) => s.cashMinor));
    final transfer = reportSum(sales.map((s) => s.transferMinor));
    final credit = reportSum(sales.map((s) => s.creditMinor));
    final other = reportMinor(
      BigInt.from(reportSum(sales.map((s) => s.salesMinor))) -
          BigInt.from(cash) -
          BigInt.from(transfer) -
          BigInt.from(credit),
    );
    return ReportSalesTotals(
      cashMinor: cash,
      transferMinor: transfer,
      creditMinor: credit,
      otherMinor: other,
    );
  }

  /// Exact native revenue. Archived estimates remain separate below.
  final int cashMinor, transferMinor, creditMinor, otherMinor;
  final int estimatedCashMinor,
      estimatedTransferMinor,
      estimatedCreditMinor,
      estimatedOtherMinor,
      estimatedSales;
  int get knownCashMinor => reportSum([cashMinor, estimatedCashMinor]);
  int get knownTransferMinor =>
      reportSum([transferMinor, estimatedTransferMinor]);
  int get knownCreditMinor => reportSum([creditMinor, estimatedCreditMinor]);
  int get knownOtherMinor => reportSum([otherMinor, estimatedOtherMinor]);
  int get estimatedTotalMinor => reportSum([
    estimatedCashMinor,
    estimatedTransferMinor,
    estimatedCreditMinor,
    estimatedOtherMinor,
  ]);
  final int unpricedCashSales,
      unpricedTransferSales,
      unpricedCreditSales,
      unpricedOtherSales;
  int get unpricedSales =>
      unpricedCashSales +
      unpricedTransferSales +
      unpricedCreditSales +
      unpricedOtherSales;
  int get knownTotalMinor => reportSum([
    knownCashMinor,
    knownTransferMinor,
    knownCreditMinor,
    knownOtherMinor,
  ]);
  int? get cashTotalMinor => unpricedCashSales == 0 ? knownCashMinor : null;
  int? get transferTotalMinor =>
      unpricedTransferSales == 0 ? knownTransferMinor : null;
  int? get creditTotalMinor =>
      unpricedCreditSales == 0 ? knownCreditMinor : null;
  int? get otherTotalMinor => unpricedOtherSales == 0 ? knownOtherMinor : null;
  int? get totalMinor => unpricedSales == 0 ? knownTotalMinor : null;
  void validate() {
    for (final value in [
      cashMinor,
      transferMinor,
      creditMinor,
      otherMinor,
      estimatedCashMinor,
      estimatedTransferMinor,
      estimatedCreditMinor,
      estimatedOtherMinor,
      estimatedSales,
      unpricedCashSales,
      unpricedTransferSales,
      unpricedCreditSales,
      unpricedOtherSales,
    ]) {
      if (value < 0) {
        throw const ReportsValidationException(
          'El desglose de ventas contiene valores negativos.',
        );
      }
    }
    knownTotalMinor;
  }
}

/// Registered money leaving Caja/Nequi; transfers and openings are excluded.
class ReportOutflowTotals {
  const ReportOutflowTotals({
    required this.cashMinor,
    required this.transferMinor,
    this.unpricedCashRecords = 0,
    this.unpricedTransferRecords = 0,
  });
  factory ReportOutflowTotals.fromNative(
    Iterable<ReportMovement> movements,
    Iterable<ReportAccount> accounts,
  ) {
    final roles = {for (final account in accounts) account.id: account.role};
    var cash = BigInt.zero, transfer = BigInt.zero;
    for (final m in movements) {
      if (m.amountMinor >= 0 ||
          m.kind == ReportMovementKind.transfer ||
          m.kind == ReportMovementKind.opening) {
        continue;
      }
      final amount = BigInt.from(m.amountMinor).abs();
      if (roles[m.accountId] == ReportAccountRole.cash) cash += amount;
      if (roles[m.accountId] == ReportAccountRole.transfer) transfer += amount;
    }
    return ReportOutflowTotals(
      cashMinor: reportMinor(cash),
      transferMinor: reportMinor(transfer),
    );
  }
  final int cashMinor,
      transferMinor,
      unpricedCashRecords,
      unpricedTransferRecords;
  int get unpricedRecords => unpricedCashRecords + unpricedTransferRecords;
  int get knownTotalMinor => reportSum([cashMinor, transferMinor]);
  int? get cashTotalMinor => unpricedCashRecords == 0 ? cashMinor : null;
  int? get transferTotalMinor =>
      unpricedTransferRecords == 0 ? transferMinor : null;
  int? get totalMinor => unpricedRecords == 0 ? knownTotalMinor : null;
  void validate() {
    if ([
      cashMinor,
      transferMinor,
      unpricedCashRecords,
      unpricedTransferRecords,
    ].any((v) => v < 0)) {
      throw const ReportsValidationException(
        'El desglose de egresos contiene valores negativos.',
      );
    }
    knownTotalMinor;
  }
}

abstract interface class ReportsStore {
  Future<ReportsSnapshot> load(ReportPeriod period);
}

class ReportsValidationException implements Exception {
  const ReportsValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}
