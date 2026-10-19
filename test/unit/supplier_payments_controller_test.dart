import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/features/supplier_payments/application/supplier_payments_controller.dart';
import 'package:valinor_sanctum_2/features/collections/domain/collections_store.dart';
import 'package:valinor_sanctum_2/features/supplier_payments/domain/supplier_payments_store.dart';

import '../support/fake_supplier_payments_store.dart';

void main() {
  FakeSupplierPaymentsStore store() => FakeSupplierPaymentsStore()
    ..accounts.add(
      const CollectionAccount(
        id: 'cash',
        name: 'Caja sintética',
        kind: 'cash',
        balanceMinor: 10000,
      ),
    )
    ..methods.add(
      const CollectionMethod(id: 'method', code: 'EFECTIVO', name: 'Efectivo'),
    )
    ..payables.add(
      PayableSummary(
        payableId: 'payable',
        purchaseDocumentId: 'purchase',
        label: 'Compra sintética',
        supplierName: 'Proveedor sintético',
        issuedAtUtc: DateTime.utc(2026, 10, 19),
        dueDate: '2099-12-31',
        initialMinor: 10000,
        paidMinor: 0,
        remainingMinor: 10000,
      ),
    );
  const parts = [
    SupplierPaymentPartInput(
      cashAccountId: 'cash',
      paymentMethodId: 'method',
      amountMinor: 4000,
    ),
  ];
  Future<SupplierPaymentsController> open(
    FakeSupplierPaymentsStore fake,
  ) async {
    final controller = SupplierPaymentsController(store: fake);
    addTearDown(controller.dispose);
    await controller.load();
    return controller;
  }

  test(
    'a partial payment spends registered money and reduces the remaining payable',
    () async {
      final fake = store();
      final controller = await open(fake);
      expect(await controller.pay(payableId: 'payable', parts: parts), isTrue);
      expect(fake.payables.single.remainingMinor, 6000);
      expect(fake.accounts.single.balanceMinor, 6000);
      expect(controller.pendingPayments, isEmpty);
      expect(controller.operationNotice, contains('Pago confirmado'));
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
        await controller.pay(
          payableId: 'payable',
          parts: parts,
          occurredAtUtc: at,
        ),
        isFalse,
      );
      final command = fake.preparedInputs.single;
      expect(controller.preparationUncertain, isTrue);
      expect(fake.pending, isEmpty);
      expect(await controller.pay(payableId: 'payable', parts: parts), isFalse);
      expect(fake.preparedInputs, hasLength(1));
      fake.preparationFailure = null;
      expect(await controller.retry(command.commandId), isTrue);
      expect(fake.preparedInputs.map((item) => item.commandId), [
        command.commandId,
        command.commandId,
      ]);
      expect(fake.payments.single.paidAtUtc, at);
      expect(fake.payables.single.remainingMinor, 6000);
    },
  );

  test(
    'lost preparation response recovers durable input after reopening',
    () async {
      final fake = store()
        ..preparationFailure = StateError('lost reply')
        ..persistBeforePreparationFailure = true;
      final controller = await open(fake);
      expect(await controller.pay(payableId: 'payable', parts: parts), isFalse);
      final id = fake.pending.single.commandId;
      final reopened = await open(fake);
      fake.preparationFailure = null;
      expect(await reopened.retry(id), isTrue);
      expect(fake.confirmedIds, [id]);
      expect(fake.payments, hasLength(1));
    },
  );

  test('lost commit reply retries without spending a second time', () async {
    final fake = store()
      ..confirmationFailure = StateError('lost commit reply')
      ..commitBeforeConfirmationFailure = true;
    final controller = await open(fake);
    expect(await controller.pay(payableId: 'payable', parts: parts), isFalse);
    final id = controller.pendingPayments.single.commandId;
    expect(await controller.retry(id), isTrue);
    expect(fake.confirmedIds, [id, id]);
    expect(fake.payments, hasLength(1));
    expect(fake.accounts.single.balanceMinor, 6000);
  });

  test(
    'refresh discovers an already committed payment after an unknown response',
    () async {
      final fake = store()
        ..confirmationFailure = StateError('lost commit reply')
        ..commitBeforeConfirmationFailure = true;
      final controller = await open(fake);
      await controller.pay(payableId: 'payable', parts: parts);
      await controller.load();
      expect(controller.pendingPayments, isEmpty);
      expect(
        controller.operationNotice,
        contains('recuperado como confirmado'),
      );
      expect(controller.operationError, isNull);
      expect(fake.payments, hasLength(1));
    },
  );

  test(
    'postcommit read failure preserves success and blocks another payment until refresh',
    () async {
      final fake = store();
      final controller = await open(fake);
      fake.loadFailure = StateError('read unavailable');
      expect(await controller.pay(payableId: 'payable', parts: parts), isTrue);
      expect(controller.pendingPayments, isEmpty);
      expect(controller.loadError, isNotNull);
      expect(await controller.pay(payableId: 'payable', parts: parts), isFalse);
      fake.loadFailure = null;
      await controller.load();
      expect(controller.snapshot!.payables.single.remainingMinor, 6000);
    },
  );

  test(
    'deterministic prepare rejection keeps editor correctable and never dispatches',
    () async {
      final fake = store()
        ..preparationFailure = const SupplierPaymentsValidationException(
          'Importe inválido.',
        );
      final controller = await open(fake);
      expect(await controller.pay(payableId: 'payable', parts: parts), isFalse);
      expect(controller.pendingPayments, isEmpty);
      expect(controller.operationError, 'Importe inválido.');
      expect(fake.confirmedIds, isEmpty);
    },
  );

  test(
    'rejected payment unlocks but failed refresh still blocks correction until current balances load',
    () async {
      final fake = store()
        ..confirmationFailure = const SupplierPaymentsValidationException(
          'Saldo insuficiente.',
        );
      final controller = await open(fake);
      await controller.pay(payableId: 'payable', parts: parts);
      final id = controller.pendingPayments.single.commandId;
      expect(controller.pendingPayments.single.status, 'rejected');
      fake.loadFailure = StateError('read unavailable');
      expect(await controller.unlockRejected(id), isTrue);
      expect(controller.pendingPayments, isEmpty);
      expect(controller.loadError, isNotNull);
      expect(await controller.pay(payableId: 'payable', parts: parts), isFalse);
      fake.loadFailure = null;
      fake.confirmationFailure = null;
      await controller.load();
      expect(await controller.pay(payableId: 'payable', parts: parts), isTrue);
      expect(fake.payments, hasLength(1));
    },
  );

  test(
    'overflowing split total never creates a pending client request',
    () async {
      final fake = store();
      final controller = await open(fake);
      expect(
        await controller.pay(
          payableId: 'payable',
          parts: const [
            SupplierPaymentPartInput(
              cashAccountId: 'cash',
              paymentMethodId: 'method',
              amountMinor: 9223372036854775807,
            ),
            SupplierPaymentPartInput(
              cashAccountId: 'cash',
              paymentMethodId: 'method',
              amountMinor: 1,
            ),
          ],
        ),
        isFalse,
      );
      expect(fake.preparedInputs, isEmpty);
      expect(controller.pendingPayments, isEmpty);
      expect(controller.operationError, isNotNull);
    },
  );

  test(
    'stale selection is rejected before constructing a pending snapshot',
    () async {
      final fake = store();
      final controller = await open(fake);
      fake.payables.clear();
      await controller.load();
      expect(await controller.pay(payableId: 'payable', parts: parts), isFalse);
      expect(fake.preparedInputs, isEmpty);
      expect(controller.pendingPayments, isEmpty);
      expect(fake.accounts.single.balanceMinor, 10000);
    },
  );
}
