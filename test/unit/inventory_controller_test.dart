import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/features/inventory/application/inventory_controller.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';

import '../support/fake_inventory_store.dart';

void main() {
  late FakeInventoryStore store;
  late InventoryController controller;
  final occurred = DateTime.utc(2026, 10, 19, 14);
  const lines = [
    ReceiptLineInput(productId: 'product', quantity: 3, totalCostMinor: 10001),
  ];

  setUp(() async {
    store = FakeInventoryStore()
      ..products.add(
        const CatalogProduct(
          id: 'product',
          name: 'Producto sintético',
          listPriceMinor: 1200,
        ),
      )
      ..suppliers.add(
        const InventorySupplier(id: 'supplier', name: 'Proveedor sintético'),
      );
    controller = InventoryController(store: store);
    await controller.load();
  });
  tearDown(() => controller.dispose());

  Future<bool> receive({
    List<ReceiptLineInput> input = lines,
    String due = '2026-10-20',
  }) => controller.receivePurchase(
    supplierId: 'supplier',
    lines: input,
    dueDate: due,
    occurredAtUtc: occurred,
  );

  test(
    'uncertain receipt blocks new payload and retries exactly one original command',
    () async {
      store.receiveFailure = StateError('Lost confirmation after commit');
      store.commitBeforeReceiveFailure = true;
      final input = [...lines];
      expect(await receive(input: input), isFalse);
      final original = controller.pendingReceipt!;
      input.clear();
      expect(original.lines, hasLength(1));
      expect(
        await receive(
          input: const [
            ReceiptLineInput(
              productId: 'product',
              quantity: 500,
              totalCostMinor: 50000,
            ),
          ],
        ),
        isFalse,
      );
      expect(store.receivedCommands, hasLength(1));
      expect(await controller.retryReceipt(), isTrue);
      expect(
        identical(store.receivedCommands.first, store.receivedCommands.last),
        isTrue,
      );
      expect(controller.pendingReceipt, isNull);
      expect(store.receipts, hasLength(1));
      expect(controller.snapshot!.stock.single.quantity, 3);
      expect(controller.snapshot!.stock.single.totalCostMinor, 10001);
    },
  );

  test('double submission while waiting is blocked', () async {
    store.receiveGate = Completer<void>();
    final first = receive();
    expect(controller.receiving, isTrue);
    expect(await receive(), isFalse);
    expect(await controller.retryReceipt(), isFalse);
    expect(store.receivedCommands, hasLength(1));
    store.receiveGate!.complete();
    expect(await first, isTrue);
  });

  test(
    'confirmed rejection permits correcting form with a new command',
    () async {
      store.receiveFailure = const InventoryValidationException(
        'El proveedor está archivado.',
      );
      expect(await receive(), isFalse);
      final firstId = store.receivedCommands.single.commandId;
      expect(controller.pendingReceipt, isNull);
      expect(controller.receiptError, 'El proveedor está archivado.');
      store.receiveFailure = null;
      expect(await receive(), isTrue);
      expect(store.receivedCommands.last.commandId, isNot(firstId));
    },
  );

  test(
    'client rejects duplicated products, impossible dates and zero totals',
    () async {
      expect(await receive(input: [...lines, ...lines]), isFalse);
      expect(await receive(due: '2026-02-31'), isFalse);
      expect(await receive(due: '2026-10-18'), isFalse);
      expect(
        await receive(
          input: const [
            ReceiptLineInput(
              productId: 'product',
              quantity: 1,
              totalCostMinor: 0,
            ),
          ],
        ),
        isFalse,
      );
      expect(store.receivedCommands, isEmpty);
      expect(controller.pendingReceipt, isNull);
    },
  );

  test(
    'an active product in an archived category cannot be received',
    () async {
      store.categories.add(
        const InventoryCategory(
          id: 'archived',
          name: 'Archivada',
          isActive: false,
        ),
      );
      store.products[0] = const CatalogProduct(
        id: 'product',
        name: 'Producto sintético',
        categoryId: 'archived',
        listPriceMinor: 1200,
      );
      await controller.load();
      expect(controller.isProductAvailable(store.products.single), isFalse);
      expect(await receive(), isFalse);
      expect(store.receivedCommands, isEmpty);
    },
  );

  test('confirmed receipt remains successful when refresh fails', () async {
    store.loadFailure = StateError('read failed');
    expect(await receive(), isTrue);
    expect(controller.pendingReceipt, isNull);
    expect(controller.loadError, isNotNull);
    expect(store.receipts, hasLength(1));
    store.loadFailure = null;
    await controller.load();
    expect(controller.loadError, isNull);
    expect(controller.snapshot!.receipts, hasLength(1));
  });

  test(
    'catalog double save blocked and failed save does not mutate snapshot',
    () async {
      store.saveGate = Completer<void>();
      store.saveFailure = const InventoryValidationException('SKU repetido.');
      const product = CatalogProduct(
        id: 'other',
        name: 'Otro producto',
        listPriceMinor: 12000,
      );
      final first = controller.saveProduct(product);
      expect(await controller.saveProduct(product), isFalse);
      expect(store.saves, 1);
      store.saveGate!.complete();
      expect(await first, isFalse);
      expect(controller.catalogError, 'SKU repetido.');
      expect(controller.snapshot!.products, hasLength(1));
    },
  );
}
