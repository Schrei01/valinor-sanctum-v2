import 'dart:async';
import 'package:valinor_sanctum_2/features/reports/domain/reports_store.dart';

class FakeReportsStore implements ReportsStore {
  final queries = <ReportPeriod>[];
  Object? failure;
  Completer<void>? gate;
  bool unknownBalances = false, uncategorized = false;
  bool convertedHistory = false;
  bool noTransfers = false;
  List<ReportTransfer>? transferRows;
  List<ReportItem>? itemRows;
  List<ReportDebtorBalance>? debtorRows;
  int unpricedTransferRecords = 0;
  int unpricedCashSales = 0;
  int estimatedCashMinor = 0, estimatedSales = 0;
  ReportsSnapshot Function(ReportPeriod)? build;
  @override
  Future<ReportsSnapshot> load(ReportPeriod period) async {
    queries.add(period);
    await gate?.future;
    if (failure != null) throw failure!;
    return build?.call(period) ??
        reportFixture(
          period,
          unknownBalances: unknownBalances,
          uncategorized: uncategorized,
          convertedHistory: convertedHistory,
          noTransfers: noTransfers,
          transferRows: transferRows,
          itemRows: itemRows,
          debtorRows: debtorRows,
          unpricedTransferRecords: unpricedTransferRecords,
          unpricedCashSales: unpricedCashSales,
          estimatedCashMinor: estimatedCashMinor,
          estimatedSales: estimatedSales,
        );
  }
}

ReportsSnapshot reportFixture(
  ReportPeriod period, {
  bool unknownBalances = false,
  bool uncategorized = false,
  bool convertedHistory = false,
  bool noTransfers = false,
  List<ReportTransfer>? transferRows,
  List<ReportItem>? itemRows,
  List<ReportDebtorBalance>? debtorRows,
  int unpricedTransferRecords = 0,
  int unpricedCashSales = 0,
  int estimatedCashMinor = 0,
  int estimatedSales = 0,
}) {
  final at = period.startUtc.add(const Duration(hours: 10));
  ReportMovement movement(
    String id,
    String account,
    ReportMovementKind kind,
    int amount,
    String concept, {
    String reason = '',
  }) => ReportMovement(
    id: id,
    documentId: id,
    occurredAtUtc: at,
    accountId: account,
    accountName: account == 'cash' ? 'Caja' : 'Nequi',
    kind: kind,
    concept: concept,
    amountMinor: amount,
    reason: reason,
  );
  return ReportsSnapshot(
    period: period,
    items: itemRows,
    unpricedTransferRecords: unpricedTransferRecords,
    saleTotals: ReportSalesTotals(
      cashMinor: 6000,
      transferMinor: 20000,
      creditMinor: 4000,
      unpricedCashSales: unpricedCashSales,
      estimatedCashMinor: estimatedCashMinor,
      estimatedSales: estimatedSales,
    ),
    accounts: [
      ReportAccount(
        id: 'cash',
        name: 'Caja',
        role: ReportAccountRole.cash,
        openingMinor: unknownBalances ? null : 100000,
        closingMinor: unknownBalances ? null : 94000,
      ),
      ReportAccount(
        id: 'nequi',
        name: 'Nequi',
        role: ReportAccountRole.transfer,
        openingMinor: unknownBalances ? null : 50000,
        closingMinor: unknownBalances ? null : 80000,
      ),
    ],
    movements: [
      movement(
        'cash-sale',
        'cash',
        ReportMovementKind.saleReceipt,
        6000,
        'Venta física',
      ),
      movement(
        'event-sale',
        'nequi',
        ReportMovementKind.saleReceipt,
        20000,
        'Inscripciones',
      ),
      movement(
        'abono',
        'cash',
        ReportMovementKind.debtorPayment,
        5000,
        'Abono anterior',
      ),
      movement(
        'expense',
        'cash',
        ReportMovementKind.expense,
        -7000,
        'Aseo',
        reason: 'Aseo',
      ),
      movement(
        'transfer-out',
        'cash',
        ReportMovementKind.transfer,
        -10000,
        'Caja → Nequi',
      ),
      movement(
        'transfer-in',
        'nequi',
        ReportMovementKind.transfer,
        10000,
        'Caja → Nequi',
      ),
    ],
    sales: [
      ReportSaleLine(
        id: 'physical',
        documentId: 'physical-sale',
        saleLabel: 'Cuenta sintética',
        occurredAtUtc: at,
        productId: 'p1',
        productName: 'Producto con pérdida',
        categoryId: uncategorized ? '' : 'food',
        categoryName: uncategorized ? 'Sin categoría' : 'Comestible',
        quantity: 2,
        salesMinor: 10000,
        costMinor: 12000,
        cashMinor: 6000,
        transferMinor: 0,
        creditMinor: 4000,
        isEvent: false,
      ),
      ReportSaleLine(
        id: 'entry',
        documentId: 'event-sale',
        saleLabel: 'Liga sintética',
        occurredAtUtc: at,
        productId: 'e1',
        productName: 'Liga sintética',
        categoryId: 'event',
        categoryName: 'Evento',
        quantity: 2,
        salesMinor: 20000,
        costMinor: 0,
        cashMinor: 0,
        transferMinor: 20000,
        creditMinor: 0,
        isEvent: true,
      ),
    ],
    transfers:
        transferRows ??
        [
          if (!noTransfers)
            ReportTransfer(
              documentId: 'transfer',
              occurredAtUtc: at,
              sourceAccountId: 'cash',
              sourceName: 'Caja',
              destinationAccountId: 'nequi',
              destinationName: 'Nequi',
              amountMinor: 10000,
              note: 'Movimiento sintético',
            ),
        ],
    expenses: [
      ReportExpense(
        documentId: 'expense',
        occurredAtUtc: at,
        reason: 'Aseo',
        concept: 'Gasto sintético',
        amountMinor: 7000,
        isEvent: false,
      ),
      ReportExpense(
        documentId: 'event-created',
        occurredAtUtc: at.subtract(const Duration(hours: 1)),
        reason: 'Evento',
        concept: 'Liga sintética',
        amountMinor: 2000,
        isEvent: true,
      ),
    ],
    debtChanges: const [],
    events: [
      ReportEventResult(
        productId: 'e1',
        name: 'Liga sintética',
        createdAtUtc: at.subtract(const Duration(hours: 1)),
        quantity: 2,
        salesMinor: 20000,
        costMinor: 2000,
      ),
    ],
    debtOpeningMinor: unknownBalances ? null : 30000,
    debtClosingMinor: unknownBalances ? null : 29000,
    debtorBalances: unknownBalances
        ? const []
        : debtorRows ??
              const [
                ReportDebtorBalance(
                  id: 'one',
                  name: 'Persona uno',
                  amountMinor: 18000,
                ),
                ReportDebtorBalance(
                  id: 'two',
                  name: 'Persona dos',
                  amountMinor: 11000,
                ),
              ],
    coverageStartUtc: unknownBalances ? at.add(const Duration(days: 1)) : null,
    openingBalancesKnown: !unknownBalances,
    usesHistoricalBalances: convertedHistory,
    closingBalancesKnown: !unknownBalances,
    warnings: const ['Categorías según clasificación actual.'],
  );
}
