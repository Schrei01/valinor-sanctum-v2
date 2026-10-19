import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/sales/application/sales_controller.dart';
import 'package:valinor_sanctum_2/features/sales/domain/sales_store.dart';

import '../support/fake_sales_store.dart';

void main() {
  Future<SalesController> open(FakeSalesStore store) async {
    final controller = SalesController(store: store);
    addTearDown(controller.dispose);
    await controller.load();
    return controller;
  }

  FakeSalesStore store() => FakeSalesStore()
    ..products.add(
      const CatalogProduct(
        id: 'product',
        name: 'Juego sintético',
        listPriceMinor: 1000,
      ),
    )
    ..stock.add(
      const StockPosition(
        productId: 'product',
        quantity: 3,
        totalCostMinor: 1000,
      ),
    )
    ..drafts.add(
      SaleDraft(
        id: 'draft',
        label: 'Mesa sintética',
        customerName: 'Cliente sintético',
        revision: 1,
        status: 'open',
        updatedAtUtc: DateTime.utc(2026, 10, 19),
        lines: const [
          SaleDraftLine(
            productId: 'product',
            quantity: 2,
            unitPriceMinor: 1000,
          ),
        ],
      ),
    );

  test(
    'uncertain preparation retries its original identity before dispatching and survives a reopening',
    () async {
      final fake = store()
        ..preparationFailure = StateError('lost preparation acknowledgement')
        ..persistBeforePreparationFailure = true;
      final first = await open(fake);
      expect(
        await first.confirm(
          draftId: 'draft',
          expectedRevision: 1,
          dueDate: '2099-12-31',
        ),
        isFalse,
      );
      final commandId = fake.preparedIds.single;
      expect(fake.confirmedIds, isEmpty);
      expect(first.pendingFor('draft')?.commandId, commandId);
      final second = await open(fake);
      expect(second.pendingFor('draft')?.commandId, commandId);
      fake.preparationFailure = null;
      expect(await second.retry('draft'), isTrue);
      expect(fake.confirmedIds, [commandId]);
      expect(fake.sales, hasLength(1));
      expect(fake.stock.single.quantity, 1);
    },
  );

  test(
    'uncertain preparation before persistence retains input and retries the same request',
    () async {
      final fake = store()
        ..preparationFailure = StateError('storage unavailable');
      final controller = await open(fake);
      final occurred = DateTime.utc(2026, 10, 19, 18);
      expect(
        await controller.confirm(
          draftId: 'draft',
          expectedRevision: 1,
          dueDate: '2099-12-31',
          occurredAtUtc: occurred,
        ),
        isFalse,
      );
      final commandId = fake.preparedIds.single;
      expect(fake.pending, isEmpty);
      expect(
        await controller.confirm(
          draftId: 'another',
          expectedRevision: 1,
          dueDate: '2099-12-31',
        ),
        isFalse,
      );
      expect(fake.preparedIds, hasLength(1));
      fake.preparationFailure = null;
      expect(await controller.retry('draft'), isTrue);
      expect(fake.preparedIds, [commandId, commandId]);
      expect(fake.confirmedIds, [commandId]);
      expect(fake.sales.single.soldAtUtc, occurred);
    },
  );

  test(
    'confirmed sale remains a success when the following refresh fails',
    () async {
      final fake = store();
      final controller = await open(fake);
      fake.loadFailure = StateError('read unavailable');
      expect(
        await controller.confirm(
          draftId: 'draft',
          expectedRevision: 1,
          dueDate: '2099-12-31',
        ),
        isTrue,
      );
      expect(controller.pendingFor('draft'), isNull);
      expect(controller.loadError, isNotNull);
      expect(
        controller.operationNotice,
        contains('Venta a crédito confirmada'),
      );
      expect(fake.sales, hasLength(1));
    },
  );

  test(
    'deterministic preparation failure leaves the draft editable without dispatch',
    () async {
      final fake = store()
        ..preparationFailure = const SalesValidationException(
          'La fecha no es válida.',
        );
      final controller = await open(fake);
      expect(
        await controller.confirm(
          draftId: 'draft',
          expectedRevision: 1,
          dueDate: 'invalid',
        ),
        isFalse,
      );
      expect(controller.pendingFor('draft'), isNull);
      expect(controller.operationError, 'La fecha no es válida.');
      expect(fake.confirmedIds, isEmpty);
      expect(fake.sales, isEmpty);
    },
  );
}
