import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/features/stock_intake/domain/purchase_pricing.dart';

void main() {
  test('25000 for ten suggests 3846 at scale0; scale2 retains cents', () {
    expect(
      suggestedRetailPriceMinor(totalCostMinor: 25000, quantity: 10),
      3846,
    );
    expect(
      suggestedRetailPriceMinor(totalCostMinor: 2500000, quantity: 10),
      384615,
    );
    expect(suggestedRetailPriceMinor(totalCostMinor: 10, quantity: 3), 5);
  });
  test(
    'rounding is nearest, division never uses floating point, invalid inputs reject',
    () {
      expect(suggestedRetailPriceMinor(totalCostMinor: 1, quantity: 1), 2);
      expect(suggestedRetailPriceMinor(totalCostMinor: 1, quantity: 10), 0);
      expect(
        () => suggestedRetailPriceMinor(totalCostMinor: 1, quantity: 0),
        throwsArgumentError,
      );
      expect(
        () => suggestedRetailPriceMinor(totalCostMinor: 0, quantity: 1),
        throwsArgumentError,
      );
      expect(
        () => suggestedRetailPriceMinor(
          totalCostMinor: 0x7fffffffffffffff,
          quantity: 1,
        ),
        throwsRangeError,
      );
    },
  );
}
