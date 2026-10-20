import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/stock_intake/application/stock_intake_controller.dart';
import 'package:valinor_sanctum_2/features/stock_intake/domain/stock_intake_store.dart';

import '../support/fake_stock_intake_store.dart';

void main() {
  late FakeStockIntakeStore store;
  late StockIntakeController controller;
  setUp(() {
    store = FakeStockIntakeStore();
    controller = StockIntakeController(store: store);
  });
  tearDown(() => controller.dispose());
  Future<bool> receive({
    int cost = 1234,
    int price = 2500,
    int quantity = 3,
    CatalogProduct? existing,
  }) => controller.receive(
    expectedProduct: existing,
    productName: 'Agua sintética',
    categoryId: 'food',
    supplierName: 'Proveedor sintético',
    unitPurchasePriceMinor: cost,
    listPriceMinor: price,
    quantity: quantity,
    paymentOptionId: 'cash',
  );

  test(
    'one action creates product stock and paid history using unit cost',
    () async {
      await controller.load();
      expect(await receive(), isTrue);
      expect(store.entries.single.totalCostMinor, 3702);
      expect(store.stock.single.quantity, 3);
      expect(store.products.single.listPriceMinor, 2500);
      expect(controller.pendingIntakes, isEmpty);
      expect(controller.confirmedVersion, 1);
    },
  );

  test(
    'uncertain preparation preserves the exact request and new product identity',
    () async {
      await controller.load();
      store.prepareFailure = StateError('lost response');
      expect(await receive(), isFalse);
      final first = store.preparedCommands.single;
      expect(controller.formLocked, isTrue);
      expect(await receive(), isFalse);
      store.prepareFailure = null;
      expect(await controller.retry(first.commandId), isTrue);
      expect(identical(store.preparedCommands.last, first), isTrue);
      expect(store.entries.single.productId, first.productId);
      expect(store.entries, hasLength(1));
    },
  );

  test(
    'prepared request survives reopening and can be confirmed once',
    () async {
      await controller.load();
      store.confirmFailure = StateError('interrupted');
      expect(await receive(), isFalse);
      final pending = controller.pendingIntakes.single;
      final reopened = StockIntakeController(store: store);
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(
        reopened.pendingIntakes.single.command.commandId,
        pending.command.commandId,
      );
      store.confirmFailure = null;
      expect(await reopened.retry(pending.command.commandId), isTrue);
      expect(store.entries, hasLength(1));
      expect(reopened.pendingIntakes, isEmpty);
    },
  );

  test(
    'refresh recovers confirmed unknown result without another stock or payment write',
    () async {
      await controller.load();
      store.confirmFailure = StateError('lost response');
      store.commitBeforeConfirmFailure = true;
      expect(await receive(), isFalse);
      expect(controller.pendingIntakes, hasLength(1));
      await controller.load();
      expect(controller.pendingIntakes, isEmpty);
      expect(controller.confirmedVersion, 1);
      expect(store.entries, hasLength(1));
      expect(store.confirmedIds, hasLength(1));
      expect(controller.operationNotice, contains('recuperado'));
    },
  );

  test(
    'known rejection requires explicit correction before a new command',
    () async {
      await controller.load();
      store.confirmFailure = const StockIntakeValidationException(
        'Saldo cambió.',
      );
      expect(await receive(), isFalse);
      final rejected = controller.pendingIntakes.single;
      expect(rejected.status, 'rejected');
      expect(await controller.retry(rejected.command.commandId), isFalse);
      expect(await receive(), isFalse);
      expect(
        await controller.discardRejected(rejected.command.commandId),
        isTrue,
      );
      store.confirmFailure = null;
      expect(await receive(), isTrue);
      expect(
        store.preparedCommands.last.commandId,
        isNot(rejected.command.commandId),
      );
    },
  );

  test(
    'preparation validation leaves form editable and does not confirm',
    () async {
      await controller.load();
      store.prepareFailure = const StockIntakeValidationException(
        'SKU duplicado.',
      );
      expect(await receive(), isFalse);
      expect(controller.pendingIntakes, isEmpty);
      expect(controller.formLocked, isFalse);
      expect(controller.operationError, 'SKU duplicado.');
      expect(store.confirmedIds, isEmpty);
    },
  );

  test(
    'rejects missing costs fractional equivalent quantities overflow and insufficient funds',
    () async {
      await controller.load();
      expect(await receive(cost: 0), isFalse);
      expect(await receive(quantity: 0), isFalse);
      expect(await receive(cost: 9223372036854775807, quantity: 2), isFalse);
      expect(await receive(price: 9223372036854775807, quantity: 2), isFalse);
      expect(await receive(cost: 1000001, quantity: 1), isFalse);
      expect(store.preparedCommands, isEmpty);
    },
  );

  test(
    'replenishment carries exact edited catalog snapshot for conflict detection',
    () async {
      const existing = CatalogProduct(
        id: 'old-product',
        name: 'Agua sintética',
        listPriceMinor: 2000,
        categoryId: 'food',
      );
      store.products.add(existing);
      await controller.load();
      expect(await receive(existing: existing), isTrue);
      expect(
        identical(store.preparedCommands.single.expectedProduct, existing),
        isTrue,
      );
      expect(store.preparedCommands.single.productId, 'old-product');
    },
  );

  test(
    'uncertain opening retries the exact identity and never adds the amount twice',
    () async {
      await controller.load();
      store.openingFailure = StateError('lost opening response');
      store.commitBeforeOpeningFailure = true;
      expect(
        await controller.recordOpening(
          paymentOptionId: 'cash',
          amountMinor: 12500,
        ),
        isFalse,
      );
      final first = store.openingCommands.single;
      expect(controller.pendingOpening, same(first));
      expect(controller.formLocked, isTrue);
      await controller.load();
      expect(controller.pendingOpening, same(first));
      expect(await controller.retryOpening(), isTrue);
      expect(identical(store.openingCommands.last, first), isTrue);
      expect(controller.snapshot!.paymentOptions.first.balanceMinor, 1012500);
      expect(controller.pendingOpening, isNull);
      expect(
        await controller.recordOpening(
          paymentOptionId: 'cash',
          amountMinor: 12500,
        ),
        isFalse,
      );
    },
  );

  test(
    'read failure after authoritative confirmation preserves successful result and blocks a new intake',
    () async {
      await controller.load();
      final gate = store.confirmGate = Completer<void>();
      final result = receive();
      await Future<void>.delayed(Duration.zero);
      store.loadFailure = StateError('read failed');
      gate.complete();
      expect(await result, isTrue);
      expect(controller.pendingIntakes, isEmpty);
      expect(controller.loadError, isNotNull);
      expect(await receive(), isFalse);
      store.loadFailure = null;
      await controller.load();
      expect(controller.loadError, isNull);
    },
  );
}
