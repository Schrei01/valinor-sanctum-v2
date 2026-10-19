import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/core/domain/fifo_cost.dart';
import 'package:valinor_sanctum_2/core/domain/money.dart';

void main() {
  test(
    'front remainder policy places minor units first and exhausts each partition',
    () {
      for (var quantity = 1; quantity <= 20; quantity++) {
        for (var cost = 0; cost <= 100; cost++) {
          var sum = 0;
          for (var start = 0; start < quantity; start++) {
            final amount = fifoFrontRemainderCostForRange(
              totalCostMinor: cost,
              totalQuantity: quantity,
              startInclusive: start,
              endExclusive: start + 1,
            );
            expect(
              amount,
              cost ~/ quantity + (start < cost % quantity ? 1 : 0),
            );
            sum += amount;
          }
          expect(sum, cost);
          for (var split = 1; split < quantity; split++) {
            expect(
              fifoFrontRemainderCostForRange(
                    totalCostMinor: cost,
                    totalQuantity: quantity,
                    startInclusive: 0,
                    endExclusive: split,
                  ) +
                  fifoFrontRemainderCostForRange(
                    totalCostMinor: cost,
                    totalQuantity: quantity,
                    startInclusive: split,
                    endExclusive: quantity,
                  ),
              cost,
            );
          }
        }
      }
    },
  );

  test(
    'front remainder policy handles maximum int64 without intermediate overflow',
    () {
      final maximum = Money.maxMinorUnits.toInt();
      expect(
        fifoFrontRemainderCostForRange(
          totalCostMinor: maximum,
          totalQuantity: maximum,
          startInclusive: 0,
          endExclusive: maximum,
        ),
        maximum,
      );
      expect(
        fifoFrontRemainderCostForRange(
          totalCostMinor: maximum,
          totalQuantity: 3,
          startInclusive: 0,
          endExclusive: 3,
        ),
        maximum,
      );
      expect(
        () => fifoFrontRemainderCostForRange(
          totalCostMinor: maximum,
          totalQuantity: 3,
          startInclusive: 2,
          endExclusive: 4,
        ),
        throwsRangeError,
      );
    },
  );
}
