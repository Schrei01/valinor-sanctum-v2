import '../../../core/domain/money.dart';
import 'quick_sales_store.dart';

/// Current payment totals, including full-line selections and saved splits.
Map<String, BigInt> accountPaymentTotals(QuickSaleAccount account) {
  final totals = <String, BigInt>{};
  for (final line in account.lines) {
    if (line.isSplit) {
      for (final part in line.paymentParts) {
        final amount = BigInt.from(part.amountMinor);
        totals.update(
          part.paymentOptionId,
          (v) => v + amount,
          ifAbsent: () => amount,
        );
      }
    } else if (line.paymentOptionId != null) {
      final amount =
          BigInt.from(line.unitPriceMinor ?? 0) *
          (BigInt.tryParse(line.quantityText.trim()) ?? BigInt.zero);
      totals.update(
        line.paymentOptionId!,
        (v) => v + amount,
        ifAbsent: () => amount,
      );
    }
  }
  return totals;
}

/// Allocate a whole-account payment to the existing durable line format.
/// Each column is apportioned against remaining row capacity using largest
/// remainders; ties follow line order. Both row and payment totals stay exact.
List<QuickSaleLine> allocateAccountPayments(
  QuickSaleAccount account,
  List<QuickLinePaymentPart> parts,
) {
  final ids = <String>{};
  if (parts.isEmpty ||
      parts.length > 3 ||
      parts.any((p) => !ids.add(p.paymentOptionId) || p.amountMinor <= 0)) {
    throw const QuickSalesValidationException(
      'Revisa los importes del reparto de la cuenta.',
    );
  }
  final remaining = <BigInt>[];
  for (final line in account.lines) {
    final quantity = BigInt.tryParse(line.quantityText.trim());
    if (line.productId == null ||
        line.unitPriceMinor == null ||
        line.unitPriceMinor! < 0 ||
        quantity == null ||
        quantity <= BigInt.zero ||
        !RegExp(r'^[0-9]+$').hasMatch(line.quantityText.trim())) {
      throw const QuickSalesValidationException(
        'Completa producto, cantidad y precio de todas las líneas antes de dividir la cuenta.',
      );
    }
    remaining.add(quantity * BigInt.from(line.unitPriceMinor!));
  }
  var capacity = remaining.fold(BigInt.zero, (s, v) => s + v);
  if (capacity <= BigInt.zero ||
      capacity > Money.maxMinorUnits ||
      parts.fold(BigInt.zero, (s, p) => s + BigInt.from(p.amountMinor)) !=
          capacity) {
    throw const QuickSalesValidationException(
      'La suma del reparto debe coincidir con el total de la cuenta.',
    );
  }
  final allocated = [for (final _ in remaining) <QuickLinePaymentPart>[]];
  for (final part in parts) {
    final amount = BigInt.from(part.amountMinor);
    final floors = [for (final row in remaining) row * amount ~/ capacity];
    final residues = [for (final row in remaining) row * amount % capacity];
    final order = List.generate(remaining.length, (i) => i)
      ..sort((a, b) {
        final byRemainder = residues[b].compareTo(residues[a]);
        return byRemainder != 0 ? byRemainder : a.compareTo(b);
      });
    var extra = amount - floors.fold(BigInt.zero, (s, v) => s + v);
    for (final i in order) {
      if (extra == BigInt.zero) break;
      if (floors[i] < remaining[i]) {
        floors[i] += BigInt.one;
        extra -= BigInt.one;
      }
    }
    if (extra != BigInt.zero) throw StateError('Payment allocation remainder');
    for (var i = 0; i < remaining.length; i++) {
      if (floors[i] > BigInt.zero) {
        allocated[i].add(
          QuickLinePaymentPart(part.paymentOptionId, floors[i].toInt()),
        );
      }
      remaining[i] -= floors[i];
    }
    capacity -= amount;
  }
  return List.unmodifiable([
    for (var i = 0; i < account.lines.length; i++)
      QuickSaleLine(
        id: account.lines[i].id,
        productId: account.lines[i].productId,
        quantityText: account.lines[i].quantityText,
        unitPriceMinor: account.lines[i].unitPriceMinor,
        paymentOptionId: allocated[i].isEmpty
            ? parts.first.paymentOptionId
            : null,
        paymentParts: List.unmodifiable(allocated[i]),
      ),
  ]);
}
