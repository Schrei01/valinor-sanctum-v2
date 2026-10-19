import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/features/collections/application/collections_controller.dart';
import 'package:valinor_sanctum_2/features/collections/domain/collections_store.dart';

import '../support/fake_collections_store.dart';

void main() {
  FakeCollectionsStore store() => FakeCollectionsStore()
    ..accounts.add(
      const CollectionAccount(id: 'cash', name: 'Caja sintética', kind: 'cash'),
    )
    ..methods.add(
      const CollectionMethod(id: 'method', code: 'EFECTIVO', name: 'Efectivo'),
    )
    ..receivables.add(
      ReceivableSummary(
        receivableId: 'receivable',
        saleDocumentId: 'sale',
        label: 'Mesa sintética',
        customerName: 'Cliente sintético',
        issuedAtUtc: DateTime.utc(2026, 10, 19),
        dueDate: '2099-12-31',
        initialMinor: 10000,
        collectedMinor: 0,
        remainingMinor: 10000,
      ),
    );
  const parts = [
    CollectionPartInput(
      cashAccountId: 'cash',
      paymentMethodId: 'method',
      amountMinor: 4000,
    ),
  ];
  Future<CollectionsController> open(FakeCollectionsStore fake) async {
    final controller = CollectionsController(store: fake);
    addTearDown(controller.dispose);
    await controller.load();
    return controller;
  }

  test(
    'a partial payment records money and reduces the remaining receivable',
    () async {
      final fake = store();
      final controller = await open(fake);
      expect(
        await controller.collect(receivableId: 'receivable', parts: parts),
        isTrue,
      );
      expect(fake.receivables.single.remainingMinor, 6000);
      expect(fake.accounts.single.balanceMinor, 4000);
      expect(controller.pendingCollections, isEmpty);
      expect(controller.operationNotice, contains('Cobro confirmado'));
    },
  );

  test(
    'unknown preparation before persistence retains exact immutable identity and blocks another payment',
    () async {
      final fake = store()
        ..preparationFailure = StateError('storage unavailable');
      final controller = await open(fake);
      final at = DateTime.utc(2026, 10, 19, 18);
      expect(
        await controller.collect(
          receivableId: 'receivable',
          parts: parts,
          occurredAtUtc: at,
        ),
        isFalse,
      );
      final command = fake.preparedInputs.single;
      expect(controller.preparationUncertain, isTrue);
      expect(fake.pending, isEmpty);
      expect(
        await controller.collect(receivableId: 'receivable', parts: parts),
        isFalse,
      );
      expect(fake.preparedInputs, hasLength(1));
      fake.preparationFailure = null;
      expect(await controller.retry(command.commandId), isTrue);
      expect(fake.preparedInputs.map((item) => item.commandId), [
        command.commandId,
        command.commandId,
      ]);
      expect(fake.collections.single.collectedAtUtc, at);
      expect(fake.receivables.single.remainingMinor, 6000);
    },
  );

  test(
    'lost preparation response recovers durable input after reopening',
    () async {
      final fake = store()
        ..preparationFailure = StateError('lost reply')
        ..persistBeforePreparationFailure = true;
      final controller = await open(fake);
      expect(
        await controller.collect(receivableId: 'receivable', parts: parts),
        isFalse,
      );
      final id = fake.pending.single.commandId;
      final reopened = await open(fake);
      fake.preparationFailure = null;
      expect(await reopened.retry(id), isTrue);
      expect(fake.confirmedIds, [id]);
      expect(fake.collections, hasLength(1));
    },
  );

  test('lost commit reply retries without collecting a second time', () async {
    final fake = store()
      ..confirmationFailure = StateError('lost commit reply')
      ..commitBeforeConfirmationFailure = true;
    final controller = await open(fake);
    expect(
      await controller.collect(receivableId: 'receivable', parts: parts),
      isFalse,
    );
    final id = controller.pendingCollections.single.commandId;
    expect(await controller.retry(id), isTrue);
    expect(fake.confirmedIds, [id, id]);
    expect(fake.collections, hasLength(1));
    expect(fake.accounts.single.balanceMinor, 4000);
  });

  test(
    'refresh discovers an already committed collection after an unknown response',
    () async {
      final fake = store()
        ..confirmationFailure = StateError('lost commit reply')
        ..commitBeforeConfirmationFailure = true;
      final controller = await open(fake);
      await controller.collect(receivableId: 'receivable', parts: parts);
      await controller.load();
      expect(controller.pendingCollections, isEmpty);
      expect(
        controller.operationNotice,
        contains('recuperado como confirmado'),
      );
      expect(controller.operationError, isNull);
      expect(fake.collections, hasLength(1));
    },
  );

  test(
    'postcommit read failure preserves success and blocks another payment until refresh',
    () async {
      final fake = store();
      final controller = await open(fake);
      fake.loadFailure = StateError('read unavailable');
      expect(
        await controller.collect(receivableId: 'receivable', parts: parts),
        isTrue,
      );
      expect(controller.pendingCollections, isEmpty);
      expect(controller.loadError, isNotNull);
      expect(
        await controller.collect(receivableId: 'receivable', parts: parts),
        isFalse,
      );
      fake.loadFailure = null;
      await controller.load();
      expect(controller.snapshot!.receivables.single.remainingMinor, 6000);
    },
  );

  test(
    'deterministic prepare rejection keeps editor correctable and never dispatches',
    () async {
      final fake = store()
        ..preparationFailure = const CollectionsValidationException(
          'Importe inválido.',
        );
      final controller = await open(fake);
      expect(
        await controller.collect(receivableId: 'receivable', parts: parts),
        isFalse,
      );
      expect(controller.pendingCollections, isEmpty);
      expect(controller.operationError, 'Importe inválido.');
      expect(fake.confirmedIds, isEmpty);
    },
  );

  test(
    'rejected payment unlocks but failed refresh still blocks correction until current balances load',
    () async {
      final fake = store()
        ..confirmationFailure = const CollectionsValidationException(
          'Saldo insuficiente.',
        );
      final controller = await open(fake);
      await controller.collect(receivableId: 'receivable', parts: parts);
      final id = controller.pendingCollections.single.commandId;
      expect(controller.pendingCollections.single.status, 'rejected');
      fake.loadFailure = StateError('read unavailable');
      expect(await controller.unlockRejected(id), isTrue);
      expect(controller.pendingCollections, isEmpty);
      expect(controller.loadError, isNotNull);
      expect(
        await controller.collect(receivableId: 'receivable', parts: parts),
        isFalse,
      );
      fake.loadFailure = null;
      fake.confirmationFailure = null;
      await controller.load();
      expect(
        await controller.collect(receivableId: 'receivable', parts: parts),
        isTrue,
      );
      expect(fake.collections, hasLength(1));
    },
  );
}
