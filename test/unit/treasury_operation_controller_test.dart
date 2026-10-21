import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/features/treasury/application/treasury_operation_controller.dart';
import 'package:valinor_sanctum_2/features/treasury/domain/treasury_operation_store.dart';
import 'package:valinor_sanctum_2/features/treasury/domain/treasury_store.dart';

import '../support/fake_treasury_operation_store.dart';

void main() {
  late FakeTreasuryOperationStore store;
  late TreasuryOperationController controller;
  setUp(() {
    store = FakeTreasuryOperationStore();
    controller = TreasuryOperationController(store: store);
  });
  tearDown(() => controller.dispose());

  Future<bool> expense({
    int amount = 1234,
    String source = 'cash',
    String reason = 'Aseo',
    String? note,
  }) => controller.record(
    kind: TreasuryOperationKind.expense,
    sourceAccountId: source,
    amountMinor: amount,
    reason: reason,
    note: note,
  );

  Future<bool> transfer({
    String source = 'cash',
    String? destination = 'reserve',
    int amount = 20000,
  }) => controller.record(
    kind: TreasuryOperationKind.transfer,
    sourceAccountId: source,
    destinationAccountId: destination,
    amountMinor: amount,
    reason: 'Transferencia',
  );

  test(
    'expense reduces only selected cash account and confirms once',
    () async {
      await controller.load();
      expect(await expense(source: 'nequi'), isTrue);
      expect(store.accounts[0].balanceMinor, 100000);
      expect(store.accounts[1].balanceMinor, 48766);
      expect(store.accounts[2].balanceMinor, -20000);
      expect(controller.confirmedVersion, 1);
      expect(controller.operationNotice, contains('Gasto registrado'));
      expect(controller.pendingOperations, isEmpty);
    },
  );

  test(
    'transfer preserves total money and can repay negative reserve',
    () async {
      await controller.load();
      expect(await transfer(), isTrue);
      expect(store.accounts[0].balanceMinor, 80000);
      expect(store.accounts[1].balanceMinor, 50000);
      expect(store.accounts[2].balanceMinor, 0);
      expect(
        store.accounts.fold(0, (sum, item) => sum + item.balanceMinor),
        130000,
      );
      expect(controller.operationNotice, contains('Transferencia registrada'));
    },
  );

  test(
    'validates amount source balance distinct destination and motives',
    () async {
      await controller.load();
      expect(await expense(amount: 0), isFalse);
      expect(await expense(amount: -1), isFalse);
      expect(await expense(amount: 100001), isFalse);
      expect(await expense(source: 'reserve'), isFalse);
      expect(await expense(source: 'missing'), isFalse);
      expect(await expense(reason: 'Unknown'), isFalse);
      expect(await expense(note: 'bad\nline'), isFalse);
      expect(await expense(note: 'x' * 501), isFalse);
      expect(await transfer(destination: 'cash'), isFalse);
      expect(await transfer(destination: null), isFalse);
      expect(await transfer(source: 'reserve', amount: 1), isFalse);
      expect(store.preparedCommands, isEmpty);
      expect(await expense(reason: 'Otro', note: ' Transporte '), isTrue);
      expect(store.preparedCommands.single.note, 'Transporte');
    },
  );

  test('Otro expense may omit the optional observation', () async {
    await controller.load();
    expect(await expense(reason: 'Otro', note: '  '), isTrue);
    expect(store.preparedCommands.single.reason, 'Otro');
    expect(store.preparedCommands.single.note, isNull);
  });

  test('destination overflow is rejected before preparation', () async {
    store.accounts[2] = const TreasuryAccount(
      id: 'reserve',
      name: 'Caja mayor',
      role: TreasuryAccountRole.reserve,
      balanceMinor: 9223372036854775807,
    );
    await controller.load();
    expect(await transfer(amount: 1), isFalse);
    expect(store.preparedCommands, isEmpty);
  });

  test(
    'uncertain preparation retries the identical command without duplicate',
    () async {
      await controller.load();
      store.prepareFailure = StateError('lost response');
      store.persistBeforePrepareFailure = true;
      expect(await expense(), isFalse);
      final first = store.preparedCommands.single;
      expect(controller.formLocked, isTrue);
      expect(await expense(), isFalse);
      store.prepareFailure = null;
      expect(await controller.retry(first.commandId), isTrue);
      expect(store.preparedCommands.last, same(first));
      expect(store.results, hasLength(1));
      expect(store.accounts[0].balanceMinor, 98766);
    },
  );

  test(
    'reload replaces unknown preparation with canonical persisted request',
    () async {
      await controller.load();
      store.prepareFailure = StateError('lost response');
      store.persistBeforePrepareFailure = true;
      expect(await transfer(), isFalse);
      final first = store.preparedCommands.single;
      await controller.load();
      store.prepareFailure = null;
      expect(await controller.retry(first.commandId), isTrue);
      expect(store.preparedCommands, hasLength(1));
    },
  );

  test(
    'durable request recovers after reopen and cannot be recreated',
    () async {
      await controller.load();
      store.confirmFailure = StateError('interrupted');
      expect(await expense(), isFalse);
      final pending = controller.pendingOperations.single;
      final reopened = TreasuryOperationController(store: store);
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.formLocked, isTrue);
      store.confirmFailure = null;
      expect(await reopened.retry(pending.command.commandId), isTrue);
      expect(store.results, hasLength(1));
      expect(reopened.pendingOperations, isEmpty);
    },
  );

  test(
    'lost confirmation response reconciles on refresh without second write',
    () async {
      await controller.load();
      store.confirmFailure = StateError('lost response');
      store.commitBeforeConfirmFailure = true;
      expect(await expense(), isFalse);
      expect(controller.formLocked, isTrue);
      await controller.load();
      expect(controller.pendingOperations, isEmpty);
      expect(controller.confirmedVersion, 1);
      expect(controller.operationNotice, contains('recuperada'));
      expect(store.confirmedCalls, hasLength(1));
      expect(store.results, hasLength(1));
    },
  );

  test(
    'known rejection requires explicit correction and new identity',
    () async {
      await controller.load();
      store.confirmFailure = const TreasuryValidationException('Saldo cambió.');
      expect(await transfer(), isFalse);
      final rejected = controller.pendingOperations.single;
      expect(rejected.status, 'rejected');
      expect(await controller.retry(rejected.command.commandId), isFalse);
      expect(await expense(), isFalse);
      expect(
        await controller.discardRejected(rejected.command.commandId),
        isTrue,
      );
      store.confirmFailure = null;
      expect(await expense(), isTrue);
      expect(
        store.preparedCommands.last.commandId,
        isNot(rejected.command.commandId),
      );
    },
  );

  test(
    'known preparation validation leaves editable form with no confirmation',
    () async {
      await controller.load();
      store.prepareFailure = const TreasuryValidationException(
        'Cuenta inactiva.',
      );
      expect(await expense(), isFalse);
      expect(controller.formLocked, isFalse);
      expect(controller.pendingOperations, isEmpty);
      expect(store.confirmedCalls, isEmpty);
    },
  );

  test(
    'confirmed write remains successful if subsequent reload fails',
    () async {
      await controller.load();
      final gate = store.confirmGate = Completer<void>();
      final result = expense();
      await Future<void>.delayed(Duration.zero);
      expect(controller.busy, isTrue);
      expect(await transfer(), isFalse);
      store.loadFailure = StateError('read failed');
      gate.complete();
      expect(await result, isTrue);
      expect(controller.pendingOperations, isEmpty);
      expect(controller.confirmedVersion, 1);
      expect(controller.loadError, isNotNull);
      expect(await expense(), isFalse);
      store.loadFailure = null;
      await controller.load();
      expect(controller.loadError, isNull);
    },
  );

  test(
    'failed discard keeps rejected request blocked and recoverable',
    () async {
      await controller.load();
      store.confirmFailure = const TreasuryValidationException('Saldo cambió.');
      await expense();
      final id = controller.pendingOperations.single.command.commandId;
      store.discardFailure = StateError('write failed');
      expect(await controller.discardRejected(id), isFalse);
      expect(controller.formLocked, isTrue);
      expect(controller.pendingOperations.single.command.commandId, id);
    },
  );

  test(
    'defaults load failure leaves controls blocked until successful refresh',
    () async {
      store.defaultsFailure = StateError('not ready');
      await controller.load();
      expect(controller.loadError, isNotNull);
      expect(await expense(), isFalse);
      store.defaultsFailure = null;
      await controller.load();
      expect(await expense(), isTrue);
    },
  );
}
