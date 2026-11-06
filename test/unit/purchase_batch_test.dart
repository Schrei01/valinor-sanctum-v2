import 'dart:async';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/core/domain/money.dart';
import 'package:valinor_sanctum_2/features/stock_intake/domain/stock_intake_store.dart';
import 'package:valinor_sanctum_2/features/stock_intake/application/stock_intake_controller.dart';
import '../support/fake_stock_intake_store.dart';

PurchaseBatchCommand batch({
  List<int> costs = const [1134, 60],
  int paid = 1200,
}) {
  final at = DateTime.utc(2026, 11, 6, 15);
  return PurchaseBatchCommand(
    commandId: 'batch',
    categoryId: 'food',
    paymentOptionId: 'cash',
    totalPaidMinor: paid,
    occurredAtUtc: at,
    items: [
      for (var index = 0; index < costs.length; index++)
        StockIntakeCommand(
          commandId: 'child-$index',
          productId: 'product-$index',
          productName: 'Producto $index',
          categoryId: 'food',
          supplierName: 'PTO',
          totalPurchasePriceMinor: costs[index],
          listPriceMinor: 2000,
          quantity: index + 1,
          paymentOptionId: 'cash',
          occurredAtUtc: at,
        ),
    ],
  );
}

void main() {
  test(
    'recorded costs remain immutable while actual costs exactly reconcile positive and negative differences',
    () {
      final b = batch();
      expect(b.itemsTotalMinor, 1194);
      expect(b.differenceMinor, 6);
      expect(b.settlementCosts, [1140, 60]);
      expect(b.items.map((i) => i.totalCostMinor), [1134, 60]);
      expect(
        batch(paid: 1100).settlementCosts.fold<int>(0, (a, b) => a + b),
        1100,
      );
      expect(batch(paid: 1194).settlementCosts, [1134, 60]);
      expect(() => b.items.clear(), throwsUnsupportedError);
    },
  );
  test(
    'allocation exactness for uneven whole minor units, minimal totals and large values',
    () {
      final random = Random(43);
      for (var sample = 0; sample < 300; sample++) {
        final costs = List.generate(
          1 + random.nextInt(20),
          (_) => 1 + random.nextInt(100000),
        );
        final paid = costs.length + random.nextInt(100000);
        final allocation = batch(costs: costs, paid: paid).settlementCosts;
        expect(allocation.fold<int>(0, (a, b) => a + b), paid);
        expect(allocation.every((value) => value > 0), isTrue);
      }
      final max = Money.maxMinorUnits.toInt();
      expect(batch(costs: [max - 1, 1], paid: max).settlementCosts, [
        max - 1,
        1,
      ]);
      expect(
        () => batch(costs: [max, 1]).settlementCosts,
        throwsA(isA<StockIntakeValidationException>()),
      );
      expect(
        () => batch(paid: 1).settlementCosts,
        throwsA(isA<StockIntakeValidationException>()),
      );
    },
  );
  test(
    'uncertain prepare keeps exact batch and child identities; retry pays once',
    () async {
      final store = FakeStockIntakeStore()
        ..prepareFailure = StateError('lost response')
        ..persistBeforePrepareFailure = true;
      final c = StockIntakeController(store: store);
      addTearDown(c.dispose);
      await c.load();
      final input = batch();
      expect(await c.receiveBatch(input), isFalse);
      expect(c.formLocked, isTrue);
      expect(c.pendingBatches.single.command, same(input));
      expect(await c.receiveBatch(batch()), isFalse);
      store.prepareFailure = null;
      expect(await c.retryBatch('batch'), isTrue);
      expect(store.batchCommands, hasLength(2));
      expect(store.batchCommands[0], same(store.batchCommands[1]));
      expect(store.batchEntries, hasLength(1));
      expect(c.pendingBatches, isEmpty);
      expect(c.confirmedVersion, 1);
    },
  );
  test(
    'uncertain committed batch is recovered by refresh without another payment',
    () async {
      final store = FakeStockIntakeStore()
        ..confirmFailure = StateError('lost response')
        ..commitBeforeConfirmFailure = true;
      final c = StockIntakeController(store: store);
      addTearDown(c.dispose);
      await c.load();
      expect(await c.receiveBatch(batch()), isFalse);
      expect(c.formLocked, isTrue);
      await c.load();
      expect(c.pendingBatches, isEmpty);
      expect(c.confirmedVersion, 1);
      expect(store.batchEntries, hasLength(1));
      expect(store.paymentOptions.first.balanceMinor, 1000000 - 1200);
      await c.load();
      expect(c.confirmedVersion, 1);
    },
  );
  test(
    'double submit and edits cannot create another batch while confirmation waits',
    () async {
      final store = FakeStockIntakeStore()..confirmGate = Completer<void>();
      final c = StockIntakeController(store: store);
      addTearDown(c.dispose);
      await c.load();
      final first = c.receiveBatch(batch());
      await Future<void>.delayed(Duration.zero);
      expect(c.formLocked, isTrue);
      expect(await c.receiveBatch(batch()), isFalse);
      store.confirmGate!.complete();
      expect(await first, isTrue);
      expect(store.batchEntries, hasLength(1));
      expect(c.confirmedVersion, 1);
    },
  );
}
