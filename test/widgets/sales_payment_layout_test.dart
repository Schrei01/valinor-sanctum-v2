import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/features/inventory/presentation/inventory_widgets.dart';
import 'package:valinor_sanctum_2/features/quick_sales/application/quick_sales_controller.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/presentation/quick_sales_page.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';
import '../support/fake_quick_sales_store.dart';

void main() {
  for (final width in [1280.0, 900.0, 400.0]) {
    testWidgets(
      'register stays in place while debt and split summaries remain visible at $width',
      (t) async {
        await t.binding.setSurfaceSize(Size(width, 1800));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final store = FakeQuickSalesStore();
        final c = QuickSalesController(
          store: store,
          autosaveDelay: const Duration(days: 1),
        );
        await c.load();
        addTearDown(c.dispose);
        final id = c.addAccount()!, line = c.accounts.single.lines.single;
        c.editLine(
          id,
          QuickSaleLine(
            id: line.id,
            productId: 'water',
            quantityText: '1',
            unitPriceMinor: 10000,
            paymentOptionId: 'cash',
          ),
        );
        final total = c.totalFor(c.accounts.single).toInt();
        final profile = BusinessProfile(
          profileId: 'test',
          businessName: 'Sintética',
          currencyCode: 'COP',
          moneyScale: 0,
          timezone: 'America/Bogota',
          createdAtUtc: DateTime.utc(2026, 10, 30),
        );
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: QuickSalesPage(controller: c, profile: profile),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        final register = find.byKey(ValueKey('quick-register-$id'));
        final initial = t.getRect(register);
        c.selectAccountPayment(id, QuickPaymentOption.creditId);
        await t.pumpAndSettle();
        expect(t.getRect(register), initial);
        expect(
          find.byKey(ValueKey('quick-credit-summary-$id')),
          findsOneWidget,
        );
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is InventoryNotice &&
                w.kind == InventoryNoticeKind.error &&
                w.text.contains('persona'),
          ),
          findsOneWidget,
        );
        c.selectDebtor(id, store.debtors.first.id);
        await t.pumpAndSettle();
        expect(t.getRect(register), initial);
        expect(
          c.divideAccount(id, [
            QuickLinePaymentPart('cash', total ~/ 2),
            QuickLinePaymentPart(
              QuickPaymentOption.creditId,
              total - total ~/ 2,
            ),
          ]),
          isTrue,
        );
        await t.pumpAndSettle();
        expect(t.getRect(register), initial);
        expect(find.text('Volver a pago único'), findsOneWidget);
        expect(
          t.getTopLeft(find.byKey(ValueKey('quick-payment-details-$id'))).dy,
          greaterThan(initial.bottom),
        );
        expect(
          t
              .widget<InventoryNotice>(
                find.byKey(ValueKey('quick-payment-details-$id')),
              )
              .kind,
          InventoryNoticeKind.information,
        );
        expect(
          c.divideAccount(id, [
            QuickLinePaymentPart('cash', total ~/ 4),
            QuickLinePaymentPart('nequi', total ~/ 4),
            QuickLinePaymentPart(
              QuickPaymentOption.creditId,
              total - total ~/ 2,
            ),
          ]),
          isTrue,
        );
        await t.pumpAndSettle();
        expect(t.getRect(register), initial);
        c.returnToSinglePayment(id);
        c.selectAccountPayment(id, 'cash');
        await t.pumpAndSettle();
        expect(t.getRect(register), initial);
        expect(t.takeException(), isNull);
        expect(await c.flushAll(), isTrue);
        await t.pumpAndSettle();
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}
