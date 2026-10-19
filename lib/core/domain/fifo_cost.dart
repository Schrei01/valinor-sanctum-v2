import 'money.dart';

/// Immutable cost evidence for one received layer, independent of catalog data.
///
/// Unknown cost is intentionally not representable as zero: the caller must
/// handle an unknown layer separately instead of constructing this value.
final class FifoCostLayer {
  final Money totalCost;
  final int totalQuantity;

  FifoCostLayer({required this.totalCost, required this.totalQuantity}) {
    _validateLayer(totalCost.minorUnits, totalQuantity);
  }

  Money costForRange({
    required int startInclusive,
    required int endExclusive,
  }) => Money.fromMinorUnits(
    fifoCostForRange(
      totalCostMinor: totalCost.minorUnits,
      totalQuantity: totalQuantity,
      startInclusive: startInclusive,
      endExclusive: endExclusive,
    ),
    currency: totalCost.currency,
    scale: totalCost.scale,
  );
}

/// Exact cost of the half-open unit interval [startInclusive, endExclusive).
///
/// floor(end * total / quantity) - floor(start * total / quantity) preserves
/// the layer's total across all consecutive partitions, including remainders.
/// Tracking consumption, FIFO ordering and preventing overlapping allocations
/// are transaction-level responsibilities; this function never mutates a layer.
int fifoCostForRange({
  required int totalCostMinor,
  required int totalQuantity,
  required int startInclusive,
  required int endExclusive,
}) {
  _validateLayer(totalCostMinor, totalQuantity);
  if (startInclusive < 0 || startInclusive >= totalQuantity) {
    throw RangeError.value(
      startInclusive,
      'startInclusive',
      'Fuera de la capa.',
    );
  }
  if (endExclusive <= startInclusive || endExclusive > totalQuantity) {
    throw RangeError.value(endExclusive, 'endExclusive', 'Tramo inválido.');
  }

  final total = BigInt.from(totalCostMinor);
  final quantity = BigInt.from(totalQuantity);
  final before = BigInt.from(startInclusive) * total ~/ quantity;
  final throughEnd = BigInt.from(endExclusive) * total ~/ quantity;
  final result = throughEnd - before;
  // Both endpoints lie in [0, totalCostMinor], already checked for int64.
  return result.toInt();
}

void _validateLayer(int totalCostMinor, int totalQuantity) {
  if (totalCostMinor < 0 || BigInt.from(totalCostMinor) > Money.maxMinorUnits) {
    throw RangeError.value(totalCostMinor, 'totalCostMinor', 'Costo inválido.');
  }
  if (totalQuantity <= 0 || BigInt.from(totalQuantity) > Money.maxMinorUnits) {
    throw RangeError.value(
      totalQuantity,
      'totalQuantity',
      'Cantidad inválida.',
    );
  }
}

/// Versioned sale policy `fifo-front-remainder-v1`: each unit receives the
/// integer base cost and the first `totalCostMinor % totalQuantity` units receive
/// one additional minor unit. Consecutive partitions exactly exhaust the layer.
/// Unlike the proportional policy above, SQL can validate this calculation
/// without multiplying the full layer value by an endpoint.
int fifoFrontRemainderCostForRange({
  required int totalCostMinor,
  required int totalQuantity,
  required int startInclusive,
  required int endExclusive,
}) {
  _validateLayer(totalCostMinor, totalQuantity);
  if (startInclusive < 0 || startInclusive >= totalQuantity) {
    throw RangeError.value(
      startInclusive,
      'startInclusive',
      'Fuera de la capa.',
    );
  }
  if (endExclusive <= startInclusive || endExclusive > totalQuantity) {
    throw RangeError.value(endExclusive, 'endExclusive', 'Tramo inválido.');
  }
  final total = BigInt.from(totalCostMinor);
  final quantity = BigInt.from(totalQuantity);
  final start = BigInt.from(startInclusive);
  final length = BigInt.from(endExclusive) - start;
  final remainingExtra = (total % quantity) - start;
  final extra = remainingExtra <= BigInt.zero
      ? BigInt.zero
      : (remainingExtra < length ? remainingExtra : length);
  return (length * (total ~/ quantity) + extra).toInt();
}
