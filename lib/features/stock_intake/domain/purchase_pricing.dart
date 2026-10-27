import '../../../core/domain/money.dart';

/// Total / quantity / 0.65, rounded to the nearest stored minor unit.
/// The recommendation never constrains the PVP chosen by the operator.
int suggestedRetailPriceMinor({
  required int totalCostMinor,
  required int quantity,
}) {
  if (totalCostMinor <= 0 || quantity <= 0) {
    throw ArgumentError('Costo y cantidad deben ser positivos.');
  }
  final numerator = BigInt.from(totalCostMinor) * BigInt.from(100);
  final denominator = BigInt.from(quantity) * BigInt.from(65);
  final result =
      numerator ~/ denominator +
      ((numerator % denominator) * BigInt.two >= denominator
          ? BigInt.one
          : BigInt.zero);
  if (result > Money.maxMinorUnits) {
    throw RangeError('El PVP sugerido supera el límite.');
  }
  return result.toInt();
}
