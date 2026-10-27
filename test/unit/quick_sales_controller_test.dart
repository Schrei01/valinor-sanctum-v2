import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/features/quick_sales/application/quick_sales_controller.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/quick_sales_store.dart';

import '../support/fake_quick_sales_store.dart';

void main() {
  late FakeQuickSalesStore store;
  late QuickSalesController controller;
  setUp(() async {
    store = FakeQuickSalesStore();
    controller = QuickSalesController(
      store: store,
      autosaveDelay: const Duration(days: 1),
    );
    await controller.load();
  });
  tearDown(() => controller.dispose());

  String account() => controller.addAccount()!;
  void fill(String id, {String product = 'water', String payment = 'cash'}) {
    final line = controller.accounts
        .firstWhere((item) => item.id == id)
        .lines
        .first;
    controller.editLine(
      id,
      QuickSaleLine(
        id: line.id,
        productId: product,
        unitPriceMinor: product == 'water' ? 300000 : 200000,
        paymentOptionId: payment,
      ),
    );
  }

  test(
    'choosing a person names the account and persists the same debtor before any credit line',
    () async {
      final id = account();
      controller.selectDebtor(id, 'Cliente válido');
      expect(controller.accounts.single.label, 'Cliente válido');
      expect(controller.accounts.single.debtorId, 'Cliente válido');
      expect(controller.hasCreditFor(controller.accounts.single), isFalse);
      expect(await controller.flushAll(), isTrue);
      await controller.load();
      expect(controller.accounts.single.debtorId, 'Cliente válido');
      expect(controller.accounts.single.customerName, 'Cliente válido');
      final second = account();
      controller.selectDebtor(second, 'Cliente mixto');
      expect(
        controller.accounts.firstWhere((a) => a.id == id).debtorId,
        'Cliente válido',
      );
      expect(
        controller.accounts.firstWhere((a) => a.id == second).label,
        'Cliente mixto',
      );
    },
  );

  test(
    'editing a named account clears its old debtor and cannot charge the prior person',
    () async {
      final id = account();
      controller.selectDebtor(id, 'Cliente válido');
      controller.rename(id, 'Mesa libre');
      expect(controller.accounts.single.debtorId, isNull);
      expect(controller.accounts.single.customerName, isEmpty);
      fill(id, payment: QuickPaymentOption.creditId);
      expect(await controller.register(id), isFalse);
      expect(store.customerDebts, isEmpty);
      expect(store.preparedIds, isEmpty);
      controller.selectDebtor(id, 'Cliente mixto');
      expect(await controller.register(id), isTrue);
      expect(store.customerDebts, {'Cliente mixto': 300000});
    },
  );

  test(
    'independent cards autosave incomplete lines and preserve them across reload errors',
    () async {
      final first = account();
      final second = account();
      controller.rename(second, 'Mesa dos');
      controller.addLine(first);
      expect(await controller.flushAll(), isTrue);
      expect(store.accounts, hasLength(2));
      expect(
        store.accounts.firstWhere((item) => item.id == first).lines,
        hasLength(2),
      );
      expect(
        store.accounts
            .firstWhere((item) => item.id == first)
            .lines
            .first
            .productId,
        isNull,
      );
      controller.rename(second, 'Mesa con cambios');
      store.loadFailure = StateError('offline');
      await controller.load();
      expect(
        controller.accounts.firstWhere((item) => item.id == second).label,
        'Mesa con cambios',
      );
      expect(controller.isDirty(second), isTrue);
      expect(controller.loadError, isNotNull);
      expect(store.defaultsCalls, 1);
    },
  );

  test(
    'serial save queue coalesces newer edits without overlapping a card write',
    () async {
      final id = account();
      store.saveGate = Completer<void>();
      final saving = controller.flush(id);
      controller.rename(id, 'Última versión');
      controller.addLine(id);
      store.saveGate!.complete();
      expect(await saving, isTrue);
      expect(store.maximumActiveSaves, 1);
      expect(store.savedInputs, hasLength(2));
      expect(store.accounts.single.label, 'Última versión');
      expect(store.accounts.single.lines, hasLength(2));
      expect(controller.isDirty(id), isFalse);
    },
  );

  test(
    'lost save response replays exact input before saving later edits',
    () async {
      final id = account();
      store.saveFailure = StateError('response lost');
      store.saveBeforeFailure = true;
      expect(await controller.flush(id), isFalse);
      final firstInput = store.savedInputs.single;
      controller.rename(id, 'Cambio posterior');
      store.saveFailure = null;
      expect(await controller.flush(id), isTrue);
      expect(identical(store.savedInputs[1], firstInput), isTrue);
      expect(store.accounts.single.revision, 2);
      expect(store.accounts.single.label, 'Cambio posterior');
    },
  );

  test(
    'register flushes current values and closes only its own card',
    () async {
      final first = account();
      final second = account();
      fill(first);
      fill(second, product: 'snack', payment: 'nequi');
      expect(await controller.register(first), isTrue);
      expect(store.sales.single.result.totalMinor, 300000);
      expect(controller.accounts.single.id, second);
      expect(controller.accounts.single.lines.single.paymentOptionId, 'nequi');
      expect(await controller.flush(second), isTrue);
    },
  );

  test(
    'unknown preparation locks only that card and retries the exact command',
    () async {
      final first = account();
      final second = account();
      fill(first);
      store.preparationFailure = StateError('lost preparation');
      store.prepareBeforeFailure = true;
      expect(await controller.register(first), isFalse);
      final pendingId = controller.pendingFor(first)!.commandId;
      controller.rename(first, 'Blocked edit');
      controller.rename(second, 'Otra cuenta editable');
      expect(
        controller.accounts.firstWhere((item) => item.id == first).label,
        'Cuenta 1',
      );
      expect(
        controller.accounts.firstWhere((item) => item.id == second).label,
        'Otra cuenta editable',
      );
      store.preparationFailure = null;
      expect(await controller.retry(first), isTrue);
      expect(store.preparedIds.toSet(), {pendingId});
      expect(store.sales, hasLength(1));
    },
  );

  test(
    'prepared operation survives controller restart and confirms once',
    () async {
      final id = account();
      fill(id);
      store.confirmationFailure = StateError('unavailable');
      expect(await controller.register(id), isFalse);
      final command = controller.pendingFor(id)!.commandId;
      controller.dispose();
      controller = QuickSalesController(store: store);
      await controller.load();
      expect(controller.isLocked(id), isTrue);
      store.confirmationFailure = null;
      expect(await controller.retry(id), isTrue);
      expect(store.confirmedIds.toSet(), {command});
      expect(store.sales, hasLength(1));
    },
  );

  test(
    'load recovers committed result after response loss without repeating sale',
    () async {
      final id = account();
      fill(id);
      store.confirmationFailure = StateError('response lost');
      store.commitBeforeFailure = true;
      expect(await controller.register(id), isFalse);
      expect(controller.isLocked(id), isTrue);
      await controller.load();
      expect(controller.accounts, isEmpty);
      expect(controller.notice, contains('recuperada'));
      expect(store.sales, hasLength(1));
    },
  );

  test(
    'deterministic rejection unlocks current durable revision for correction',
    () async {
      final id = account();
      fill(id);
      store.confirmationFailure = const QuickSalesValidationException(
        'Stock insuficiente.',
      );
      expect(await controller.register(id), isFalse);
      expect(controller.pendingFor(id)!.status, 'rejected');
      expect(await controller.unlockRejected(id), isTrue);
      final previous = controller.accounts.single.revision;
      controller.rename(id, 'Cuenta corregida');
      store.confirmationFailure = null;
      expect(await controller.register(id), isTrue);
      expect(store.savedInputs.last.expectedRevision, previous);
      expect(store.sales.single.label, 'Cuenta corregida');
    },
  );

  test(
    'positive partial total still validates unselected lines before confirming',
    () async {
      final id = account();
      fill(id);
      controller.addLine(id);
      expect(await controller.register(id), isFalse);
      expect(controller.pendingFor(id), isNull);
      expect(controller.isLocked(id), isFalse);
      expect(controller.errorFor(id), contains('cada línea'));
      expect(store.sales, isEmpty);
    },
  );

  test(
    'refresh recovers a rejected card unlocked before its read failed',
    () async {
      final id = account();
      fill(id);
      store.confirmationFailure = const QuickSalesValidationException(
        'Stock insuficiente.',
      );
      await controller.register(id);
      store.loadFailure = StateError('read failed after unlock');
      expect(await controller.unlockRejected(id), isFalse);
      expect(controller.isLocked(id), isTrue);
      store.loadFailure = null;
      await controller.load();
      expect(controller.pendingFor(id), isNull);
      expect(controller.isLocked(id), isFalse);
      controller.rename(id, 'Cuenta recuperada');
      expect(await controller.flush(id), isTrue);
      expect(store.accounts.single.label, 'Cuenta recuperada');
    },
  );

  test(
    'known revision conflict preserves edits until explicit recovery of saved account',
    () async {
      final id = account();
      await controller.flush(id);
      final original = store.accounts.single;
      store.accounts[0] = QuickSaleAccount(
        id: id,
        label: 'Guardada externamente',
        revision: original.revision + 1,
        status: 'open',
        updatedAtUtc: original.updatedAtUtc,
        lines: original.lines,
      );
      controller.rename(id, 'Edición local');
      expect(await controller.flush(id), isFalse);
      expect(controller.canRecoverSaved(id), isTrue);
      await controller.load();
      expect(controller.accounts.single.label, 'Edición local');
      expect(await controller.recoverSavedAccount(id), isTrue);
      expect(controller.accounts.single.label, 'Guardada externamente');
      controller.rename(id, 'Cambio sobre revisión actual');
      expect(await controller.flush(id), isTrue);
      expect(store.accounts.single.revision, 3);
    },
  );

  test(
    'authoritative refresh removes closed clean cards but preserves dirty cards',
    () async {
      final clean = account();
      final dirty = account();
      await controller.flushAll();
      controller.rename(dirty, 'Edición por recuperar');
      store.accounts.clear();
      await controller.load();
      expect(controller.accounts.map((item) => item.id), [dirty]);
      expect(controller.accounts.any((item) => item.id == clean), isFalse);
      expect(controller.canRecoverSaved(dirty), isTrue);
      expect(await controller.recoverSavedAccount(dirty), isTrue);
      expect(controller.accounts, isEmpty);
    },
  );

  test(
    'an older concurrent refresh cannot resurrect a just registered account',
    () async {
      final id = account();
      fill(id);
      await controller.flush(id);
      final gate = Completer<void>();
      store.loadGate = gate;
      final staleRefresh = controller.load();
      store.loadGate = null;
      expect(await controller.register(id), isTrue);
      gate.complete();
      await staleRefresh;
      expect(controller.accounts, isEmpty);
      expect(controller.snapshot!.sales, hasLength(1));
      expect(store.sales, hasLength(1));
    },
  );

  test(
    'customer edits replay an uncertain save before newer changes',
    () async {
      final id = account();
      fill(id, payment: QuickPaymentOption.creditId);
      controller.updateCustomerName(id, 'Cliente inicial');
      store.saveFailure = StateError('response lost');
      store.saveBeforeFailure = true;
      expect(await controller.flush(id), isFalse);
      final originalInput = store.savedInputs.single;
      controller.updateCustomerName(id, 'Cliente posterior');
      store.saveFailure = null;
      expect(await controller.flush(id), isTrue);
      expect(store.savedInputs[1], same(originalInput));
      expect(store.savedInputs.last.customerName, 'Cliente posterior');
      expect(store.accounts.single.customerName, 'Cliente posterior');
      expect(store.maximumActiveSaves, 1);
    },
  );

  test('credit requires an explicit valid customer before preparing', () async {
    final id = account();
    fill(id, payment: QuickPaymentOption.creditId);
    for (final name in ['', ' ', 'x' * 121, 'Cliente\ninválido']) {
      controller.updateCustomerName(id, name);
      expect(await controller.register(id), isFalse);
      expect(controller.errorFor(id), contains('persona registrada'));
    }
    expect(store.preparedIds, isEmpty);
    expect(store.customerDebts, isEmpty);
    controller.selectDebtor(id, 'Cliente válido');
    expect(await controller.register(id), isTrue);
    expect(store.sales.single.result.customerName, 'Cliente válido');
    expect(store.customerDebts['Cliente válido'], 300000);
  });

  test(
    'unknown credit result locks the named debtor and reconciles once',
    () async {
      final id = account();
      fill(id, payment: QuickPaymentOption.creditId);
      controller.selectDebtor(id, 'Cliente fijo');
      store.confirmationFailure = StateError('lost result');
      store.commitBeforeFailure = true;
      expect(await controller.register(id), isFalse);
      final commandId = controller.pendingFor(id)!.commandId;
      controller.updateCustomerName(id, 'No debe cambiar');
      expect(controller.accounts.single.customerName, 'Cliente fijo');
      expect(controller.pendingFor(id)!.customerName, 'Cliente fijo');
      expect(controller.pendingFor(id)!.creditMinor, 300000);
      await controller.load();
      expect(controller.accounts, isEmpty);
      expect(store.customerDebts, {'Cliente fijo': 300000});
      expect(store.stock.first.quantity, 19);
      expect(store.confirmedIds, [commandId]);
    },
  );

  test(
    'cash selection preserves customer draft without creating a debt',
    () async {
      final id = account();
      fill(id, payment: QuickPaymentOption.creditId);
      controller.selectDebtor(id, 'Cliente conservado');
      controller.addLine(id);
      expect(controller.accounts.single.customerName, 'Cliente conservado');
      controller.removeLine(id, controller.accounts.single.lines.last.id);
      fill(id, payment: 'cash');
      expect(controller.accounts.single.customerName, 'Cliente conservado');
      expect(await controller.register(id), isTrue);
      expect(store.sales.single.result.creditMinor, 0);
      expect(store.sales.single.result.customerName, isEmpty);
      expect(store.customerDebts, isEmpty);
      expect(store.balances['cash-account'], 300000);
    },
  );

  test(
    'reopening recovers the exact prepared debtor and retry identity',
    () async {
      final id = account();
      fill(id, payment: QuickPaymentOption.creditId);
      controller.selectDebtor(id, 'Cliente preparado');
      store.preparationFailure = StateError('preparation response lost');
      store.prepareBeforeFailure = true;
      expect(await controller.register(id), isFalse);
      final commandId = store.preparedIds.single;
      controller.dispose();
      controller = QuickSalesController(
        store: store,
        autosaveDelay: const Duration(days: 1),
      );
      await controller.load();
      expect(controller.isLocked(id), isTrue);
      expect(controller.pendingFor(id)!.commandId, commandId);
      expect(controller.pendingFor(id)!.customerName, 'Cliente preparado');
      expect(controller.pendingFor(id)!.creditMinor, 300000);
      controller.updateCustomerName(id, 'No debe reemplazarlo');
      expect(controller.accounts.single.customerName, 'Cliente preparado');
      store.preparationFailure = null;
      expect(await controller.retry(id), isTrue);
      expect(store.preparedIds, [commandId]);
      expect(store.confirmedIds, [commandId]);
      expect(store.customerDebts, {'Cliente preparado': 300000});
      expect(store.stock.first.quantity, 19);
      expect(store.balances.values.every((amount) => amount == 0), isTrue);
    },
  );
}
