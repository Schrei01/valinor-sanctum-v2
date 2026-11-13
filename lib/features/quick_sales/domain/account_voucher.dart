import '../../../core/domain/money.dart';
import 'quick_sales_store.dart';

BigInt lineGross(QuickSaleLine line) =>
    BigInt.from(line.unitPriceMinor ?? 0) *
    (BigInt.tryParse(line.quantityText.trim()) ?? BigInt.zero);
BigInt linePayable(QuickSaleLine line) =>
    lineGross(line) - BigInt.from(line.voucherMinor);
BigInt accountVoucher(QuickSaleAccount account) =>
    account.lines.fold(BigInt.zero, (s, l) => s + BigInt.from(l.voucherMinor));
BigInt accountPayable(QuickSaleAccount account) =>
    account.lines.fold(BigInt.zero, (s, l) => s + linePayable(l));

/// Predictable allocation in displayed line order. Never reserves a grant.
List<QuickSaleLine> allocateVoucher(
  List<QuickSaleLine> lines,
  int available,
  String? periodId,
) {
  var remaining = BigInt.from(available);
  return [
    for (final line in lines)
      (() {
        final gross = lineGross(line);
        final used =
            line.useVoucher &&
                line.productId != 'membership:elven' &&
                periodId != null &&
                gross > BigInt.zero &&
                gross <= Money.maxMinorUnits
            ? (gross < remaining ? gross : remaining).toInt()
            : 0;
        remaining -= BigInt.from(used);
        final nextPeriodId = used > 0 ? periodId : null;
        if (used == line.voucherMinor && nextPeriodId == line.voucherPeriodId) {
          return line;
        }
        return QuickSaleLine(
          id: line.id,
          productId: line.productId,
          quantityText: line.quantityText,
          unitPriceMinor: line.unitPriceMinor,
          paymentOptionId: line.paymentOptionId,
          paymentParts: line.paymentParts,
          membershipDiscount: line.membershipDiscount,
          useVoucher: line.useVoucher,
          voucherMinor: used,
          voucherPeriodId: nextPeriodId,
        );
      })(),
  ];
}
