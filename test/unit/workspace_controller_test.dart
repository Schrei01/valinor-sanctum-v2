import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/features/workspace/application/workspace_controller.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/workspace_store.dart';
import '../support/fake_workspace_store.dart';

void main() {
  test(
    'reinitializing a ready workspace does not replace its connection',
    () async {
      final store = FakeWorkspaceStore();
      var opens = 0;
      final controller = WorkspaceController(
        openSession: () async {
          opens++;
          return fakeSession(store);
        },
      );
      await controller.initialize();
      await controller.initialize();
      expect(opens, 1);
      expect(store.closes, 0);
      controller.dispose();
    },
  );

  test(
    'verification failure after commit is recoverable without duplicate setup',
    () async {
      final store = FakeWorkspaceStore()
        ..healthFailureAfterSave = StateError('Fallo posterior al commit');
      final controller = WorkspaceController(
        openSession: () async => fakeSession(store),
      );
      await controller.initialize();
      expect(
        await controller.createProfile(businessName: 'Ludoteca sintética'),
        isFalse,
      );
      expect(store.profile, isNotNull);
      expect(controller.profile, isNull);
      expect(controller.state, WorkspaceState.failed);
      expect(store.closes, 1);
      store.healthFailureAfterSave = null;
      await controller.initialize();
      expect(controller.state, WorkspaceState.ready);
      expect(controller.profile!.businessName, 'Ludoteca sintética');
      expect(controller.profile!.moneyScale, 0);
      expect(store.saves, 1);
      controller.dispose();
    },
  );

  test(
    'save is confirmed before publishing and a second submit is ignored',
    () async {
      final store = FakeWorkspaceStore()..saveGate = Completer<void>();
      final controller = WorkspaceController(
        openSession: () async => fakeSession(store),
      );
      await controller.initialize();
      final saving = controller.createProfile(
        businessName: 'Ludoteca sintética',
      );
      expect(controller.busy, isTrue);
      expect(controller.profile, isNull);
      expect(
        await controller.createProfile(businessName: 'Duplicado'),
        isFalse,
      );
      store.saveGate!.complete();
      expect(await saving, isTrue);
      expect(store.saves, 1);
      expect(controller.profile!.businessName, 'Ludoteca sintética');
      controller.dispose();
    },
  );

  test('failed save keeps configuration pending and supports retry', () async {
    final store = FakeWorkspaceStore()
      ..saveFailure = StateError('Fallo sintético');
    final controller = WorkspaceController(
      openSession: () async => fakeSession(store),
    );
    await controller.initialize();
    expect(await controller.createProfile(businessName: 'Prueba'), isFalse);
    expect(controller.profile, isNull);
    expect(controller.error, contains('Fallo sintético'));
    expect(controller.busy, isFalse);
    store.saveFailure = null;
    expect(await controller.createProfile(businessName: 'Prueba'), isTrue);
    expect(controller.error, isNull);
    controller.dispose();
  });

  test('unhealthy storage fails startup and closes the session', () async {
    final store = FakeWorkspaceStore()..healthy = false;
    final controller = WorkspaceController(
      openSession: () async => fakeSession(store),
    );
    await controller.initialize();
    expect(controller.state, WorkspaceState.failed);
    expect(store.closes, 1);
    controller.dispose();
  });

  for (final violation in ['identity', 'foreign keys']) {
    test(
      'startup rejects invalid $violation despite other healthy checks',
      () async {
        final store = FakeWorkspaceStore(
          identityVerified: violation != 'identity',
          foreignKeyViolations: violation == 'foreign keys' ? 1 : 0,
        );
        final controller = WorkspaceController(
          openSession: () async => fakeSession(store),
        );

        await controller.initialize();

        expect(controller.state, WorkspaceState.failed);
        expect(controller.error, contains('no fue satisfactoria'));
        expect(controller.busy, isFalse);
        expect(store.closes, 1);
        expect(
          await controller.createProfile(businessName: 'Ludoteca sintética'),
          isFalse,
        );
        expect(store.saves, 0);
        controller.dispose();
      },
    );

    test(
      'recheck rejects invalid $violation and allows validated recovery',
      () async {
        final store = FakeWorkspaceStore();
        var opens = 0;
        final controller = WorkspaceController(
          openSession: () async {
            opens++;
            return fakeSession(store);
          },
        );
        await controller.initialize();
        expect(controller.state, WorkspaceState.ready);

        if (violation == 'identity') {
          store.identityVerified = false;
        } else {
          store.foreignKeyViolations = 2;
        }
        await controller.verifyStorage();

        expect(controller.state, WorkspaceState.failed);
        expect(controller.error, contains('no fue satisfactoria'));
        expect(controller.busy, isFalse);
        expect(store.closes, 1);
        expect(controller.databasePath, isEmpty);

        store.identityVerified = true;
        store.foreignKeyViolations = 0;
        await controller.initialize();

        expect(opens, 2);
        expect(controller.state, WorkspaceState.ready);
        expect(controller.error, isNull);
        controller.dispose();
      },
    );
  }

  test(
    'disposing during startup closes a session that arrives later',
    () async {
      final store = FakeWorkspaceStore();
      final gate = Completer<WorkspaceSession>();
      final controller = WorkspaceController(openSession: () => gate.future);
      final opening = controller.initialize();
      controller.dispose();
      gate.complete(fakeSession(store));
      await opening;
      expect(store.closes, 1);
    },
  );
}
