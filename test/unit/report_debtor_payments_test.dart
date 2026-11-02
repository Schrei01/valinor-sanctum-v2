import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/features/reports/domain/reports_store.dart';
import '../support/fake_reports_store.dart';

void main() {
  final period = ReportPeriod.timed(
    start: DateTime.utc(2026, 11, 2, 9, 15),
    end: DateTime.utc(2026, 11, 2, 9, 16),
  );
  ReportMovement payment(
    String id,
    DateTime at,
    String account,
    int amount, {
    ReportMovementKind kind = ReportMovementKind.debtorPayment,
  }) => ReportMovement(
    id: id,
    documentId: 'collection-$id',
    occurredAtUtc: at,
    accountId: account,
    accountName: account,
    kind: kind,
    concept: 'Abono',
    amountMinor: amount,
    debtorName: 'Persona $id',
  );
  test(
    'payments respect Bogota minute bounds, exclude sales and retain all account legs',
    () {
      final rows = [
        payment('before', DateTime.utc(2026, 11, 2, 14, 14, 59), 'cash', 400),
        payment('first', DateTime.utc(2026, 11, 2, 14, 15), 'cash', 100),
        payment(
          'last',
          DateTime.utc(2026, 11, 2, 14, 16, 59, 999),
          'nequi',
          200,
        ),
        payment('other', DateTime.utc(2026, 11, 2, 14, 16), 'unknown', 50),
        payment('after', DateTime.utc(2026, 11, 2, 14, 17), 'cash', 800),
        payment(
          'sale',
          DateTime.utc(2026, 11, 2, 14, 15),
          'cash',
          10000,
          kind: ReportMovementKind.saleReceipt,
        ),
        payment(
          'transfer',
          DateTime.utc(2026, 11, 2, 14, 15),
          'cash',
          2000,
          kind: ReportMovementKind.transfer,
        ),
      ];
      final report = reportFixture(period, movementRows: rows);
      report.validate();
      expect(report.debtorPayments.map((m) => m.id), [
        'last',
        'other',
        'first',
      ]);
      expect(report.debtorPaymentsMinor, 350);
      expect(report.debtorPaymentsFor(ReportAccountRole.cash), 100);
      expect(report.debtorPaymentsFor(ReportAccountRole.transfer), 200);
      expect(report.saleTotals.totalMinor, 30000);
      expect(() => report.debtorPayments.clear(), throwsUnsupportedError);
    },
  );
  test('payment sums are checked before rendering', () {
    final report = reportFixture(
      period,
      movementRows: [
        payment('large', period.startUtc, 'cash', 0x7fffffffffffffff),
        payment('extra', period.startUtc, 'cash', 1),
      ],
    );
    expect(report.validate, throwsA(isA<ReportsValidationException>()));
  });
}
