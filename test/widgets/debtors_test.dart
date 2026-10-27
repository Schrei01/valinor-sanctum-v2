import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/features/debtors/application/debtors_controller.dart';
import 'package:valinor_sanctum_2/features/debtors/domain/debtors_store.dart';
import 'package:valinor_sanctum_2/features/debtors/presentation/debtors_page.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';
import '../support/fake_debtors_store.dart';
import '../support/fake_workspace_store.dart';
import 'package:valinor_sanctum_2/app/sanctum_app.dart';
import 'package:valinor_sanctum_2/features/workspace/application/workspace_controller.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/workspace_store.dart';

void main() {
  testWidgets(
    'Deudores replaces Cobros in workspace and loads registered people',
    (t) async {
      await t.binding.setSurfaceSize(const Size(1120, 1000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final store = FakeDebtorsStore()
        ..people.add(
          const DebtorSummary(
            id: 'person',
            name: 'Persona del módulo',
            balanceMinor: 0,
          ),
        );
      final workspace = FakeWorkspaceStore()
        ..profile = BusinessProfile(
          profileId: 'test',
          businessName: 'Sintética',
          currencyCode: 'COP',
          moneyScale: 2,
          timezone: 'America/Bogota',
          createdAtUtc: DateTime.utc(2026, 10, 21),
        );
      final c = WorkspaceController(
        openSession: () async => WorkspaceSession(
          store: workspace,
          databasePath: 'synthetic',
          profileId: 'test',
          debtorsStore: store,
        ),
      );
      await c.initialize();
      await t.pumpWidget(SanctumApp(controller: c));
      await t.pumpAndSettle();
      expect(find.text('Cobros'), findsNothing);
      await t.tap(find.text('Deudores'));
      await t.pumpAndSettle();
      expect(find.text('Persona del módulo'), findsOneWidget);
      expect(find.text('Registrar persona'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  late FakeDebtorsStore store;
  late DebtorsController controller;
  setUp(() {
    store = FakeDebtorsStore();
    controller = DebtorsController(store: store);
  });
  tearDown(() => controller.dispose());
  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(1120, 1000),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: DebtorsPage(
              controller: controller,
              profile: BusinessProfile(
                profileId: 'ui',
                businessName: 'Sintética',
                currencyCode: 'COP',
                moneyScale: 2,
                timezone: 'America/Bogota',
                createdAtUtc: DateTime.utc(2026, 10, 21),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async => tester.pumpWidget(const SizedBox()));
  }

  Future<void> tap(WidgetTester t, Finder f) async {
    await t.ensureVisible(f);
    await t.tap(f);
    await t.pumpAndSettle();
  }

  Future<void> enter(WidgetTester t, String key, String value) async {
    final f = find.byKey(Key(key));
    await t.ensureVisible(f);
    await t.enterText(f, value);
    await t.pumpAndSettle();
  }

  Finder option() => find.byWidgetPredicate(
    (w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('debtor-payment-option-'),
  );

  testWidgets(
    'register person with zero debt and keep history after blocking fiado',
    (t) async {
      await open(t);
      await tap(t, find.text('Registrar persona').first);
      await enter(t, 'debtor-name', 'Ana sintética');
      await tap(t, find.byKey(const Key('debtor-create-confirm')));
      expect(store.people.single.name, 'Ana sintética');
      expect(store.inputs.single.amountMinor, 0);
      expect(find.byKey(const Key('debtor-balance')), findsOneWidget);
      await tap(t, find.text('Bloquear fiado'));
      await tap(t, find.text('Confirmar'));
      expect(store.people.single.isActive, isFalse);
      expect(find.text('Habilitar fiado'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('previous debt requires explicit source before saving', (
    t,
  ) async {
    await open(t);
    await tap(t, find.text('Registrar persona').first);
    await enter(t, 'debtor-name', 'Luis sintético');
    await enter(t, 'debtor-initial-amount', '100');
    await tap(t, find.byKey(const Key('debtor-create-confirm')));
    expect(store.inputs, isEmpty);
    expect(find.text('Indica si ya estaba incluida.'), findsOneWidget);
    await tap(t, find.byKey(const Key('debtor-initial-source')));
    await tap(t, find.text('Ya incluida en la cartera anterior').last);
    await tap(t, find.byKey(const Key('debtor-create-confirm')));
    expect(
      store.inputs.single.previousSource,
      PreviousDebtSource.includedInLegacy,
    );
    expect(store.people.single.balanceMinor, 10000);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'partial transfer abono and full cash payment update person and history',
    (t) async {
      store.people.add(
        const DebtorSummary(
          id: 'ana',
          name: 'Ana sintética',
          balanceMinor: 20000,
          hasOpening: true,
        ),
      );
      await open(t);
      await tap(t, find.byKey(const Key('debtor-person-ana')));
      await enter(t, 'debtor-payment-amount', '201');
      await tap(t, find.byKey(const Key('debtor-confirm-payment')));
      expect(find.text('Supera la deuda pendiente.'), findsOneWidget);
      expect(store.inputs, isEmpty);
      await enter(t, 'debtor-payment-amount', '50');
      await tap(t, option());
      await tap(t, find.text('Transferencia').last);
      await tap(t, find.byKey(const Key('debtor-confirm-payment')));
      expect(store.people.single.balanceMinor, 15000);
      expect(store.payments.single.paymentLabel, 'Nequi');
      await tap(t, find.text('Pagar todo'));
      await tap(t, option());
      await tap(t, find.text('Efectivo').last);
      await tap(t, find.byKey(const Key('debtor-confirm-payment')));
      expect(store.people.single.balanceMinor, 0);
      expect(store.confirmed, hasLength(2));
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('narrow view allows selected blocked person to pay', (t) async {
    store.people.add(
      const DebtorSummary(
        id: 'ana',
        name: 'Persona sintética con nombre extenso de prueba',
        balanceMinor: 10000,
        isActive: false,
        hasOpening: true,
      ),
    );
    await open(t, size: const Size(620, 1000));
    await tap(t, find.byKey(const Key('debtor-person-ana')));
    expect(
      t.getTopLeft(find.byKey(const Key('debtor-confirm-payment'))).dy -
          t.getBottomRight(find.byKey(const Key('debtor-payment-amount'))).dy,
      greaterThanOrEqualTo(16),
    );
    await tap(t, find.text('Pagar todo'));
    await tap(t, option());
    await tap(t, find.text('Efectivo').last);
    await tap(t, find.byKey(const Key('debtor-confirm-payment')));
    expect(store.people.single.balanceMinor, 0);
    expect(t.takeException(), isNull);
  });
}
