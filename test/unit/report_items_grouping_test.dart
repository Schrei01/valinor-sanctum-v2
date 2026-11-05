import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/core/domain/money.dart';
import 'package:valinor_sanctum_2/features/reports/domain/reports_store.dart';
import '../support/fake_reports_store.dart';

void main() {
  var sequence = 0;
  ReportItem item(
    String name,
    String method, {
    int? quantity = 1,
    int? amount = 100,
    bool estimated = false,
  }) => ReportItem(
    id: 'source-${sequence++}',
    productName: name,
    paymentMethod: method,
    occurredAtUtc: DateTime.utc(2026, 11, 5),
    quantity: quantity,
    amountMinor: amount,
    isEstimated: estimated,
  );

  test(
    'same name and payment combine quantities and actual prices without changing source totals',
    () {
      final input = [
        item('Agua', 'Efectivo', quantity: 2, amount: 200),
        item(' agua ', 'efectivo', quantity: 3, amount: 450, estimated: true),
        item('Agua', 'Transferencia', quantity: 4, amount: 800),
      ];
      final period = ReportPeriod(
        start: DateTime.utc(2026, 11, 5),
        end: DateTime.utc(2026, 11, 5),
      );
      final snapshot = reportFixture(period, itemRows: input);
      final original = reportFixture(period);
      expect(snapshot.items, hasLength(3));
      expect(snapshot.groupedItems, hasLength(2));
      final cash = snapshot.groupedItems.first;
      expect(cash.paymentMethod, 'Efectivo');
      expect(cash.quantity, 5);
      expect(cash.amountMinor, 650);
      expect(cash.isEstimated, isTrue);
      expect(snapshot.groupedItems.last.quantity, 4);
      expect(snapshot.saleTotals.totalMinor, original.saleTotals.totalMinor);
      expect(input.first.quantity, 2);
      expect(() => snapshot.groupedItems.clear(), throwsUnsupportedError);
    },
  );

  test(
    'alphabetical Spanish order ignores case and vowel accents, with ene before enye',
    () {
      final groups = ReportItemGroup.fromItems([
        for (final name in ['Zumo', 'Ñame', 'Óleo', 'Nuez', 'Água', 'Café'])
          item(name, 'Efectivo'),
      ]);
      expect(groups.map((g) => g.productName), [
        'Água',
        'Café',
        'Nuez',
        'Ñame',
        'Óleo',
        'Zumo',
      ]);
      expect(
        ReportItemGroup.fromItems([
          item('Cafe', 'Efectivo'),
          item('Café', 'Efectivo'),
        ]),
        hasLength(2),
      );
    },
  );

  test(
    'unknown fields remain unknown instead of presenting partial sums as complete',
    () {
      final grouped = ReportItemGroup.fromItems([
        item('Agua', 'Efectivo', quantity: null, amount: 100),
        item('Agua', 'Efectivo', quantity: 2, amount: null, estimated: true),
      ]).single;
      expect(grouped.quantity, isNull);
      expect(grouped.amountMinor, isNull);
      expect(grouped.isEstimated, isTrue);
    },
  );

  test(
    'split payments remain one method combination and keys cannot collide',
    () {
      final groups = ReportItemGroup.fromItems([
        item('Agua', 'Efectivo / Deudas', quantity: 2),
        item('Agua', 'Efectivo / Deudas', quantity: 3),
        item('Agua', 'Efectivo'),
        item('a|b', 'c'),
        item('a', 'b|c'),
      ]);
      expect(groups, hasLength(4));
      expect(
        groups
            .singleWhere((g) => g.paymentMethod == 'Efectivo / Deudas')
            .quantity,
        5,
      );
      expect(groups.map((g) => g.id).toSet(), hasLength(4));
    },
  );

  test(
    'sums validate final BigInt values and reject overflow without wrapping',
    () {
      final max = Money.maxMinorUnits.toInt();
      final exact = ReportItemGroup.fromItems([
        item('Agua', 'Efectivo', amount: max),
        item('Agua', 'Efectivo', amount: 1),
        item('Agua', 'Efectivo', amount: -1),
      ]).single;
      expect(exact.amountMinor, max);
      expect(
        () => ReportItemGroup.fromItems([
          item('Agua', 'Efectivo', amount: max),
          item('Agua', 'Efectivo', amount: 1),
        ]),
        throwsA(isA<ReportsValidationException>()),
      );
    },
  );
}
