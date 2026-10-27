import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/features/reports/domain/reports_store.dart';

void main() {
  test(
    'native and estimated amounts combine without treating missing records as zero',
    () {
      const totals = ReportSalesTotals(
        cashMinor: 100,
        transferMinor: 200,
        creditMinor: 300,
        estimatedCashMinor: 50,
        estimatedTransferMinor: 75,
        estimatedSales: 2,
        unpricedTransferSales: 1,
      );
      totals.validate();
      expect(totals.cashTotalMinor, 150);
      expect(totals.knownTransferMinor, 275);
      expect(totals.transferTotalMinor, isNull);
      expect(totals.totalMinor, isNull);
      expect(totals.knownTotalMinor, 725);
      expect(totals.estimatedTotalMinor, 125);
      expect(totals.cashMinor, 100);
      expect(totals.estimatedSales, 2);
    },
  );
  test(
    'incomplete historical groups retain the exact subtotal and do not invalidate other channels',
    () {
      const totals = ReportSalesTotals(
        cashMinor: 60,
        transferMinor: 200,
        creditMinor: 40,
        unpricedCashSales: 2,
      );
      totals.validate();
      expect(totals.cashTotalMinor, isNull);
      expect(totals.transferTotalMinor, 200);
      expect(totals.creditTotalMinor, 40);
      expect(totals.totalMinor, isNull);
      expect(totals.knownTotalMinor, 300);
      expect(totals.unpricedSales, 2);
    },
  );
  test(
    'other payment channels reconcile the total; integer overflow remains an error',
    () {
      const totals = ReportSalesTotals(
        cashMinor: 100,
        transferMinor: 200,
        creditMinor: 300,
        otherMinor: 50,
      );
      totals.validate();
      expect(totals.totalMinor, 650);
      expect(
        () => const ReportSalesTotals(
          cashMinor: 0x7fffffffffffffff,
          transferMinor: 1,
          creditMinor: 0,
        ).validate(),
        throwsA(isA<ReportsValidationException>()),
      );
      expect(
        () => const ReportSalesTotals(
          cashMinor: -1,
          transferMinor: 0,
          creditMinor: 0,
        ).validate(),
        throwsA(isA<ReportsValidationException>()),
      );
      expect(
        () => const ReportSalesTotals(
          cashMinor: 0x7fffffffffffffff,
          transferMinor: 0,
          creditMinor: 0,
          estimatedCashMinor: 1,
        ).validate(),
        throwsA(isA<ReportsValidationException>()),
      );
    },
  );
}
