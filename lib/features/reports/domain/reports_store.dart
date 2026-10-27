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
  });
  final String documentId,
      sourceAccountId,
      sourceName,
      destinationAccountId,
      destinationName,
      note;
  final DateTime occurredAtUtc;
  final int amountMinor;
}

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

class ReportsSnapshot {
  ReportsSnapshot({
    required this.period,
    required List<ReportAccount> accounts,
    required List<ReportMovement> movements,
    required List<ReportSaleLine> sales,
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
    required List<String> warnings,
  }) : accounts = List.unmodifiable(accounts),
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

abstract interface class ReportsStore {
  Future<ReportsSnapshot> load(ReportPeriod period);
}

class ReportsValidationException implements Exception {
  const ReportsValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}
