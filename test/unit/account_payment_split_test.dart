import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/core/domain/money.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/account_payment_split.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/application/quick_sales_controller.dart';
import '../support/fake_quick_sales_store.dart';

QuickSaleAccount account(List<QuickSaleLine> lines) => QuickSaleAccount(
  id: 'account',
  label: 'Cuenta',
  revision: 1,
  status: 'open',
  updatedAtUtc: DateTime.utc(2026, 10, 28),
  lines: lines,
);

void main() {
  test(
    'account allocation preserves both margins with deterministic rounding across 40 orders',
    () {
      for (var seed = 0; seed < 40; seed++) {
        final random = Random(seed);
        final input = account([
          for (var i = 0; i < 20; i++)
            QuickSaleLine(
              id: 'line-$i',
              productId: 'product-$i',
              unitPriceMinor: random.nextInt(10000),
              paymentOptionId: 'old',
            ),
        ]);
        final total = input.lines.fold(0, (s, l) => s + l.unitPriceMinor!);
        final cash = random.nextInt(total + 1),
            transfer = random.nextInt(total - cash + 1),
            debt = total - cash - transfer;
        final parts = [
          if (cash > 0) QuickLinePaymentPart('cash', cash),
          if (transfer > 0) QuickLinePaymentPart('transfer', transfer),
          if (debt > 0) QuickLinePaymentPart(QuickPaymentOption.creditId, debt),
        ];
        final result = allocateAccountPayments(input, parts);
        final totals = accountPaymentTotals(account(result));
        for (final p in parts) {
          expect(totals[p.paymentOptionId], BigInt.from(p.amountMinor));
        }
        for (var i = 0; i < result.length; i++) {
          expect(result[i].id, input.lines[i].id);
          expect(result[i].unitPriceMinor, input.lines[i].unitPriceMinor);
          expect(
            result[i].paymentParts.fold(0, (s, p) => s + p.amountMinor),
            input.lines[i].unitPriceMinor,
          );
          expect(input.lines[i].paymentOptionId, 'old');
        }
        final repeated = allocateAccountPayments(input, parts);
        expect(
          [
            for (final l in result)
              l.paymentParts.map((p) => p.toJson()).toList(),
          ],
          [
            for (final l in repeated)
              l.paymentParts.map((p) => p.toJson()).toList(),
          ],
        );
      }
    },
  );

  test(
    'zero-value rows and the largest monetary value retain exact integer totals',
    () {
      final max = Money.maxMinorUnits.toInt();
      final input = account([
        QuickSaleLine(id: 'a', productId: 'p', unitPriceMinor: max - 2),
        const QuickSaleLine(id: 'b', productId: 'q', unitPriceMinor: 1),
        const QuickSaleLine(id: 'c', productId: 'r', unitPriceMinor: 1),
        const QuickSaleLine(id: 'free', productId: 'free', unitPriceMinor: 0),
      ]);
      final result = allocateAccountPayments(input, [
        QuickLinePaymentPart('cash', max - 2),
        const QuickLinePaymentPart('transfer', 1),
        const QuickLinePaymentPart(QuickPaymentOption.creditId, 1),
      ]);
      final totals = accountPaymentTotals(account(result));
      expect(totals['cash'], BigInt.from(max - 2));
      expect(totals['transfer'], BigInt.one);
      expect(totals[QuickPaymentOption.creditId], BigInt.one);
      expect(result.last.paymentOptionId, 'cash');
      expect(result.last.paymentParts, isEmpty);
      expect(() => result.add(result.first), throwsUnsupportedError);
      expect(() => result.first.paymentParts.clear(), throwsUnsupportedError);
    },
  );

  test(
    'invalid sums, repeated methods, incomplete rows and excessive totals are rejected',
    () {
      final valid = account(const [
        QuickSaleLine(id: 'a', productId: 'p', unitPriceMinor: 10),
      ]);
      for (final parts in <List<QuickLinePaymentPart>>[
        [],
        [const QuickLinePaymentPart('cash', 9)],
        [const QuickLinePaymentPart('cash', 11)],
        [
          const QuickLinePaymentPart('cash', 5),
          const QuickLinePaymentPart('cash', 5),
        ],
        [
          const QuickLinePaymentPart('cash', -1),
          const QuickLinePaymentPart('transfer', 11),
        ],
      ]) {
        expect(
          () => allocateAccountPayments(valid, parts),
          throwsA(isA<QuickSalesValidationException>()),
        );
      }
      for (final bad in [
        const QuickSaleLine(id: 'a', unitPriceMinor: 10),
        const QuickSaleLine(
          id: 'a',
          productId: 'p',
          quantityText: '0',
          unitPriceMinor: 10,
        ),
        const QuickSaleLine(
          id: 'a',
          productId: 'p',
          quantityText: '1.5',
          unitPriceMinor: 10,
        ),
        QuickSaleLine(
          id: 'a',
          productId: 'p',
          quantityText: '2',
          unitPriceMinor: Money.maxMinorUnits.toInt(),
        ),
      ]) {
        expect(
          () => allocateAccountPayments(account([bad]), const [
            QuickLinePaymentPart('cash', 10),
          ]),
          throwsA(isA<QuickSalesValidationException>()),
        );
      }
    },
  );

  test(
    'account totals combine full-line selections with previously saved parts',
    () {
      final input = account(const [
        QuickSaleLine(
          id: 'a',
          productId: 'p',
          quantityText: '2',
          unitPriceMinor: 10,
          paymentOptionId: 'cash',
        ),
        QuickSaleLine(
          id: 'b',
          productId: 'q',
          unitPriceMinor: 15,
          paymentParts: [
            QuickLinePaymentPart('cash', 10),
            QuickLinePaymentPart(QuickPaymentOption.creditId, 5),
          ],
        ),
      ]);
      expect(accountPaymentTotals(input), {
        'cash': BigInt.from(30),
        QuickPaymentOption.creditId: BigInt.from(5),
      });
    },
  );

  test(
    'controller inherits the header person and a later line selection changes only that line',
    () async {
      final store = FakeQuickSalesStore();
      final c = QuickSalesController(
        store: store,
        autosaveDelay: const Duration(days: 1),
      );
      addTearDown(c.dispose);
      await c.load();
      final id = c.addAccount()!;
      final first = c.accounts.single.lines.first.id;
      c.editLine(
        id,
        QuickSaleLine(id: first, productId: 'water', unitPriceMinor: 20000),
      );
      c.addLine(id);
      final second = c.accounts.single.lines.last.id;
      c.editLine(
        id,
        QuickSaleLine(id: second, productId: 'snack', unitPriceMinor: 10000),
      );
      const parts = [
        QuickLinePaymentPart('cash', 10000),
        QuickLinePaymentPart('nequi', 5000),
        QuickLinePaymentPart(QuickPaymentOption.creditId, 15000),
      ];
      expect(c.divideAccount(id, parts), isFalse);
      expect(c.accounts.single.lines.every((l) => !l.isSplit), isTrue);
      final person = store.debtors.first.id;
      c.selectDebtor(id, person);
      expect(c.divideAccount(id, parts), isTrue);
      expect(c.accounts.single.debtorId, person);
      expect(c.creditTotalFor(c.accounts.single), BigInt.from(15000));
      final oldSecond = c.accounts.single.lines.last;
      c.editLine(
        id,
        QuickSaleLine(
          id: first,
          productId: 'water',
          unitPriceMinor: 20000,
          paymentOptionId: 'nequi',
        ),
      );
      expect(c.accounts.single.lines.last, same(oldSecond));
      expect(accountPaymentTotals(c.accounts.single), {
        'nequi': BigInt.from(21667),
        'cash': BigInt.from(3333),
        QuickPaymentOption.creditId: BigInt.from(5000),
      });
      expect(c.accounts.single.debtorId, person);
    },
  );
}
