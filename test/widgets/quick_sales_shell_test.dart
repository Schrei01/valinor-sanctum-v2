import 'dart:ui' show AppExitResponse;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/app/sanctum_app.dart';
import 'package:valinor_sanctum_2/features/sales/domain/sales_store.dart';
import 'package:valinor_sanctum_2/features/workspace/application/workspace_controller.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/workspace_store.dart';
import '../support/fake_quick_sales_store.dart';
import '../support/fake_sales_store.dart';
import '../support/fake_workspace_store.dart';

void main() {
  Future<WorkspaceController> open(
    WidgetTester tester,
    FakeQuickSalesStore? quick, {
    FakeSalesStore? sales,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1120, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final workspace = FakeWorkspaceStore()
      ..profile = BusinessProfile(
        profileId: 'test',
        businessName: 'Mostrador sintético',
        currencyCode: 'COP',
        moneyScale: 2,
        timezone: 'America/Bogota',
        createdAtUtc: DateTime.utc(2026, 10, 19),
      );
    final controller = WorkspaceController(
      openSession: () async => WorkspaceSession(
        store: workspace,
        databasePath: 'perfil-sintetico/sanctum2.sqlite3',
        profileId: 'test',
        quickSalesStore: quick,
        salesStore: sales,
      ),
    );
    await controller.initialize();
    await tester.pumpWidget(SanctumApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ventas'));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
    return controller;
  }

  testWidgets(
    'Ventas only exposes the current checkout and keeps historical data untouched',
    (tester) async {
      final quick = FakeQuickSalesStore();
      final old = FakeSalesStore()
        ..drafts.add(
          SaleDraft(
            id: 'old',
            label: 'Cuenta previa',
            customerName: 'Cliente previo',
            revision: 1,
            status: 'open',
            updatedAtUtc: DateTime.utc(2026, 10, 19),
            lines: const [],
          ),
        );
      await open(tester, quick, sales: old);
      expect(find.text('Ventas'), findsNWidgets(2));
      expect(find.text('Venta rápida'), findsNothing);
      expect(find.byKey(const Key('sale-customer')), findsNothing);
      expect(find.byKey(const Key('toggle-previous-accounts')), findsNothing);
      expect(find.text('Cuentas anteriores'), findsNothing);
      expect(find.text('Volver al mostrador'), findsNothing);
      expect(find.text('Ventas y cuentas abiertas'), findsNothing);
      expect(find.text('Cuenta previa'), findsNothing);
      await tester.tap(find.text('Sistema'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ventas'));
      await tester.pumpAndSettle();
      expect(find.text('Ventas'), findsNWidgets(2));
      expect(find.byKey(const Key('toggle-previous-accounts')), findsNothing);
      expect(old.drafts.single.label, 'Cuenta previa');
    },
  );

  testWidgets(
    'a missing checkout store never falls back to the legacy screen',
    (tester) async {
      final old = FakeSalesStore();
      await open(tester, null, sales: old);
      expect(
        find.text('El módulo no está disponible en esta sesión.'),
        findsOneWidget,
      );
      expect(find.text('Ventas y cuentas abiertas'), findsNothing);
      expect(find.byKey(const Key('sale-customer')), findsNothing);
      expect(find.byKey(const Key('toggle-previous-accounts')), findsNothing);
    },
  );

  testWidgets(
    'cancelable app exit flushes the latest draft before allowing close',
    (tester) async {
      final quick = FakeQuickSalesStore();
      await open(tester, quick);
      await tester.tap(find.byKey(const Key('quick-new-account')));
      await tester.pump();
      final label = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith('quick-label-'),
      );
      await tester.enterText(label, 'Última edición antes de cerrar');
      final response = await tester.binding.handleRequestAppExit();
      expect(response, AppExitResponse.exit);
      expect(quick.accounts.single.label, 'Última edición antes de cerrar');
      await tester.pumpAndSettle();
    },
  );

  testWidgets('failed draft flush cancels close and keeps the latest edit', (
    tester,
  ) async {
    final quick = FakeQuickSalesStore();
    await open(tester, quick);
    await tester.tap(find.byKey(const Key('quick-new-account')));
    await tester.pumpAndSettle();
    quick.saveFailure = StateError('synthetic storage unavailable');
    final label = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith('quick-label-'),
    );
    await tester.enterText(label, 'Edición protegida');
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.cancel);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(label).controller!.text,
      'Edición protegida',
    );
    quick.saveFailure = null;
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);
    expect(quick.accounts.single.label, 'Edición protegida');
    await tester.pumpAndSettle();
  });
}
