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
            balanceMinor: 100,
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
    'total includes every person and unassigned debt, survives filtering and updates after a payment',
    (t) async {
      store.legacy = 500;
      store.people.addAll([
        const DebtorSummary(id: 'ana', name: 'Ana', balanceMinor: 20000),
        const DebtorSummary(
          id: 'luis',
          name: 'Luis',
          balanceMinor: 10000,
          isActive: false,
        ),
      ]);
      store.charges.addAll([
        DebtorCharge(
          receivableId: 'assigned',
          label: 'Venta',
          nameSnapshot: 'Ana',
          occurredAtUtc: DateTime.utc(2026, 10, 29),
          originalCreditMinor: 20000,
          remainingMinor: 20000,
          debtorId: 'ana',
        ),
        DebtorCharge(
          receivableId: 'unassigned',
          label: 'Venta',
          nameSnapshot: 'Sin asignar',
          occurredAtUtc: DateTime.utc(2026, 10, 29),
          originalCreditMinor: 3000,
          remainingMinor: 1500,
        ),
      ]);
      await open(t);
      String total() =>
          t.widget<Text>(find.byKey(const Key('debtors-total'))).data!;
      expect(total(), 'COP 320,00');
      await enter(t, 'debtor-search', 'Ana');
      expect(total(), 'COP 320,00');
      await tap(t, find.byKey(const Key('debtor-person-ana')));
      await enter(t, 'debtor-payment-amount', '50');
      await tap(t, option());
      await tap(t, find.text('Efectivo').last);
      await tap(t, find.byKey(const Key('debtor-confirm-payment')));
      expect(total(), 'COP 270,00');
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('empty debt portfolio displays zero', (t) async {
    store.legacy = 0;
    await open(t, size: const Size(400, 900));
    expect(
      t.widget<Text>(find.byKey(const Key('debtors-total'))).data,
      'COP 0,00',
    );
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'zero balances stay saved but are absent from the list and search',
    (t) async {
      store.legacy = 0;
      store.people.addAll(const [
        DebtorSummary(id: 'paid', name: 'Persona pagada', balanceMinor: 0),
        DebtorSummary(
          id: 'due',
          name: 'Persona pendiente',
          balanceMinor: 10000,
        ),
        DebtorSummary(
          id: 'blocked',
          name: 'Persona bloqueada',
          balanceMinor: 5000,
          isActive: false,
        ),
      ]);
      await open(t);
      expect(find.byKey(const Key('debtor-person-paid')), findsNothing);
      expect(find.byKey(const Key('debtor-person-due')), findsOneWidget);
      expect(find.byKey(const Key('debtor-person-blocked')), findsOneWidget);
      expect(
        t.widget<Text>(find.byKey(const Key('debtors-total'))).data,
        'COP 150,00',
      );
      await enter(t, 'debtor-search', 'pagada');
      expect(find.byKey(const Key('debtor-person-paid')), findsNothing);
      expect(store.people, hasLength(3));
      expect(store.inputs, isEmpty);
    },
  );

  for (final width in [1120.0, 400.0]) {
    testWidgets(
      'register suggests paid and blocked people and opens the original account at $width',
      (t) async {
        store.legacy = 0;
        store.people.add(
          const DebtorSummary(
            id: 'paid',
            name: 'Ana anterior',
            balanceMinor: 0,
            isActive: false,
          ),
        );
        store.payments.add(
          DebtorPayment(
            id: 'old-payment',
            debtorId: 'paid',
            nameSnapshot: 'Ana anterior',
            amountMinor: 10000,
            occurredAtUtc: DateTime.utc(2026, 10, 20),
            paymentLabel: 'Efectivo',
          ),
        );
        await open(t, size: Size(width, 1100));
        expect(find.byKey(const Key('debtor-person-paid')), findsNothing);
        await tap(t, find.byKey(const Key('debtor-add')));
        await enter(t, 'debtor-name', 'Ana');
        expect(find.text('Ana anterior'), findsOneWidget);
        await tap(t, find.text('Ana anterior'));
        expect(find.byKey(const Key('debtor-existing-person')), findsOneWidget);
        expect(find.byKey(const Key('debtor-initial-amount')), findsNothing);
        expect(find.text('Ver cuenta'), findsOneWidget);
        await tap(t, find.byKey(const Key('debtor-create-confirm')));
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('Ana anterior'), findsOneWidget);
        expect(find.text('Habilitar fiado'), findsOneWidget);
        expect(find.textContaining('COP 100,00 · Efectivo'), findsOneWidget);
        expect(store.people.single.id, 'paid');
        expect(store.people.single.isActive, isFalse);
        expect(store.inputs, isEmpty);
        expect(store.confirmed, isEmpty);
        expect(t.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'exact normalized name reuses the account; editing it to a new name still allows registration',
    (t) async {
      store.people.add(
        const DebtorSummary(
          id: 'existing',
          name: 'Ana anterior',
          balanceMinor: 10000,
        ),
      );
      await open(t);
      await tap(t, find.byKey(const Key('debtor-add')));
      await enter(t, 'debtor-name', '  ANA   ANTERIOR  ');
      expect(find.text('Ver cuenta'), findsOneWidget);
      expect(find.byKey(const Key('debtor-initial-amount')), findsNothing);
      await tap(t, find.byKey(const Key('debtor-create-confirm')));
      expect(store.inputs, isEmpty);
      expect(
        t.widget<Text>(find.byKey(const Key('debtor-balance'))).data,
        'COP 100,00',
      );
      await tap(t, find.byKey(const Key('debtor-add')));
      await enter(t, 'debtor-name', 'Ana');
      await tap(t, find.text('Ana anterior').last);
      await enter(t, 'debtor-name', 'Persona nueva');
      expect(find.text('Ver cuenta'), findsNothing);
      expect(find.byKey(const Key('debtor-initial-amount')), findsOneWidget);
      await tap(t, find.byKey(const Key('debtor-create-confirm')));
      expect(store.people, hasLength(2));
      expect(store.inputs.single.kind, 'create');
      expect(store.inputs.single.name, 'Persona nueva');
      expect(store.inputs.single.amountMinor, 0);
      expect(t.takeException(), isNull);
    },
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
      expect(find.byKey(const Key('debtor-person-ana')), findsNothing);
      await tap(t, find.byKey(const Key('debtor-add')));
      await enter(t, 'debtor-name', 'Ana');
      await tap(t, find.text('Ana sintética').last);
      await tap(t, find.byKey(const Key('debtor-create-confirm')));
      expect(store.confirmed, hasLength(2));
      expect(store.payments, hasLength(2));
      expect(store.people.single.balanceMinor, 0);
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
