import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/core/domain/fifo_cost.dart';
import 'package:valinor_sanctum_2/core/domain/money.dart';

FifoCostLayer layer(int total, int quantity) => FifoCostLayer(
  totalCost: Money.fromMinorUnits(total, currency: 'COP', scale: 2),
  totalQuantity: quantity,
);

void main() {
  group('Exact layer cost intervals', () {
    test(
      'distributes the full historical cost without losing the remainder',
      () {
        final costLayer = layer(1001, 3);
        expect(
          costLayer.costForRange(startInclusive: 0, endExclusive: 1).minorUnits,
          333,
        );
        expect(
          costLayer.costForRange(startInclusive: 1, endExclusive: 2).minorUnits,
          334,
        );
        expect(
          costLayer.costForRange(startInclusive: 2, endExclusive: 3).minorUnits,
          334,
        );
        expect(
          costLayer.costForRange(startInclusive: 0, endExclusive: 3),
          costLayer.totalCost,
        );
      },
    );

    test('different consecutive partitions preserve the same total', () {
      for (final total in [0, 1, 2, 7, 1001, 7003]) {
        for (final quantity in [2, 3, 7, 19]) {
          final costLayer = layer(total, quantity);
          for (var split = 1; split < quantity; split++) {
            final first = costLayer.costForRange(
              startInclusive: 0,
              endExclusive: split,
            );
            final second = costLayer.costForRange(
              startInclusive: split,
              endExclusive: quantity,
            );
            expect(first + second, costLayer.totalCost);
          }
        }
      }
    });

    test('partial returns can reuse the original interval cost exactly', () {
      final original = layer(1001, 3);
      final sold = original.costForRange(startInclusive: 1, endExclusive: 3);
      final firstReturn = original.costForRange(
        startInclusive: 1,
        endExclusive: 2,
      );
      final secondReturn = original.costForRange(
        startInclusive: 2,
        endExclusive: 3,
      );
      expect(firstReturn + secondReturn, sold);
      // The cost evidence is immutable; unrelated current layers cannot alter it.
      final currentPurchase = layer(2000, 3);
      expect(currentPurchase.totalCost, isNot(original.totalCost));
      expect(original.costForRange(startInclusive: 1, endExclusive: 3), sold);
    });

    test(
      'documented zero cost and sub-unit remainder are represented exactly',
      () {
        expect(
          layer(0, 5).costForRange(startInclusive: 0, endExclusive: 5).isZero,
          isTrue,
        );
        final smallCost = layer(1, 3);
        expect(
          smallCost.costForRange(startInclusive: 0, endExclusive: 2).minorUnits,
          0,
        );
        expect(
          smallCost.costForRange(startInclusive: 2, endExclusive: 3).minorUnits,
          1,
        );
      },
    );

    test('supports int64 endpoints with much larger intermediate products', () {
      final maximum = Money.maxMinorUnits.toInt();
      final costLayer = layer(maximum, maximum);
      expect(
        costLayer.costForRange(startInclusive: 0, endExclusive: maximum),
        costLayer.totalCost,
      );
      final first = costLayer.costForRange(startInclusive: 0, endExclusive: 3);
      final rest = costLayer.costForRange(
        startInclusive: 3,
        endExclusive: maximum,
      );
      expect(first.minorUnits, 3);
      expect(first + rest, costLayer.totalCost);
      expect(rest.currency, 'COP');
      expect(rest.scale, 2);
    });

    test('keeps currency and scale of historical layer evidence', () {
      final costLayer = FifoCostLayer(
        totalCost: Money.fromMinorUnits(9, currency: 'USD', scale: 0),
        totalQuantity: 2,
      );
      expect(
        costLayer.costForRange(startInclusive: 0, endExclusive: 1),
        Money.fromMinorUnits(4, currency: 'USD', scale: 0),
      );
    });
  });

  group('Layer and interval validation', () {
    test('rejects negative cost and empty or negative layer quantities', () {
      expect(() => layer(-1, 3), throwsRangeError);
      expect(() => layer(100, 0), throwsRangeError);
      expect(() => layer(100, -1), throwsRangeError);
    });

    test('rejects empty, reversed and out-of-layer intervals', () {
      final costLayer = layer(1001, 3);
      for (final (start, end) in [(-1, 1), (0, 0), (2, 1), (0, 4), (3, 3)]) {
        expect(
          () =>
              costLayer.costForRange(startInclusive: start, endExclusive: end),
          throwsRangeError,
          reason: '[$start, $end)',
        );
      }
    });
  });
}
