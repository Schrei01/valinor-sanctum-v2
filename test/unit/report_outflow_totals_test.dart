import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/features/reports/domain/reports_store.dart';

void main() {
  test(
    'outflows count negative Caja/Nequi entries, exclude transfers, openings, reserve and positive receipts',
    () {
      ReportMovement movement(
        String id,
        int amount,
        ReportMovementKind kind,
        String account,
      ) => ReportMovement(
        id: id,
        documentId: id,
        occurredAtUtc: DateTime.utc(2026, 10, 27),
        accountId: account,
        accountName: account,
        kind: kind,
        concept: id,
        amountMinor: amount,
      );
      final totals = ReportOutflowTotals.fromNative(
        [
          movement('expense', -10, ReportMovementKind.expense, 'cash'),
          movement(
            'purchase',
            -20,
            ReportMovementKind.purchasePayment,
            'nequi',
          ),
          movement('event', -5, ReportMovementKind.eventPayment, 'cash'),
          movement('transfer', -100, ReportMovementKind.transfer, 'cash'),
          movement('opening', -200, ReportMovementKind.opening, 'nequi'),
          movement('reserve', -300, ReportMovementKind.expense, 'reserve'),
          movement('receipt', 400, ReportMovementKind.debtorPayment, 'cash'),
        ],
        [
          for (final role in [
            ReportAccountRole.cash,
            ReportAccountRole.transfer,
            ReportAccountRole.reserve,
          ])
            ReportAccount(
              id: role == ReportAccountRole.transfer ? 'nequi' : role.name,
              name: role.name,
              role: role,
              openingMinor: 0,
              closingMinor: 0,
            ),
        ],
      );
      expect(totals.cashMinor, 15);
      expect(totals.transferMinor, 20);
      expect(totals.totalMinor, 35);
    },
  );
  test('missing outflow amount is not zero; combined overflow is rejected', () {
    const totals = ReportOutflowTotals(
      cashMinor: 10,
      transferMinor: 20,
      unpricedCashRecords: 1,
    );
    totals.validate();
    expect(totals.cashTotalMinor, isNull);
    expect(totals.transferTotalMinor, 20);
    expect(totals.totalMinor, isNull);
    expect(totals.knownTotalMinor, 30);
    expect(
      () => const ReportOutflowTotals(
        cashMinor: 0x7fffffffffffffff,
        transferMinor: 1,
      ).validate(),
      throwsA(isA<ReportsValidationException>()),
    );
  });
}
