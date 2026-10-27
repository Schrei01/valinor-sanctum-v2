import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/features/reports/domain/reports_store.dart';
import '../support/fake_reports_store.dart';

ReportTransfer transfer(
  String id,
  String source,
  String destination,
  int amount, {
  bool historical = false,
}) => ReportTransfer(
  documentId: id,
  occurredAtUtc: DateTime.utc(2026, 10, 27),
  sourceAccountId: source,
  sourceName: source,
  destinationAccountId: destination,
  destinationName: destination,
  amountMinor: amount,
  note: '',
  isHistorical: historical,
);

void main() {
  final period = ReportPeriod(
    start: DateTime.utc(2026, 10, 27),
    end: DateTime.utc(2026, 10, 27),
  );
  test(
    'routes combine historical aliases with current names but retain direction and count once',
    () {
      final report = reportFixture(
        period,
        transferRows: [
          transfer('current', 'Caja', 'Nequi', 100),
          transfer('old', ' Efectivo ', 'Transferencia', 50, historical: true),
          transfer('reverse', 'Nequi', 'Caja', 70),
        ],
        unpricedTransferRecords: 1,
      );
      report.validate();
      expect(report.knownTransferTotalMinor, 220);
      expect(report.transferTotalMinor, isNull);
      expect(report.transferRoutes.length, 2);
      final forward = report.transferRoutes.singleWhere(
        (r) => r.sourceName == 'Caja',
      );
      expect(forward.count, 2);
      expect(forward.amountMinor, 150);
      expect(
        report.transferRoutes
            .singleWhere((r) => r.sourceName == 'Nequi')
            .amountMinor,
        70,
      );
      expect(() => report.transferRoutes.clear(), throwsUnsupportedError);
      expect(report.saleTotals.totalMinor, 30000);
      expect(report.outflowTotals.totalMinor, 7000);
    },
  );
  test('transfer aggregate overflow is rejected before rendering', () {
    final report = reportFixture(
      period,
      transferRows: [
        transfer('large', 'Caja', 'Nequi', 0x7fffffffffffffff),
        transfer('one-more', 'Caja', 'Nequi', 1),
      ],
    );
    expect(report.validate, throwsA(isA<ReportsValidationException>()));
  });
}
