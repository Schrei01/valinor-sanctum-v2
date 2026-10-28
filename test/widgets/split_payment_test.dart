import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/features/quick_sales/application/quick_sales_controller.dart';
import 'package:valinor_sanctum_2/features/quick_sales/data/sqlite_quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/presentation/quick_sales_page.dart';
import 'package:valinor_sanctum_2/features/workspace/data/sqlite_workspace_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_store.dart';
import '../integration/quick_sales_store_test.dart' show fixture;
import '../support/register_debtor.dart';

void main() {
  testWidgets(
    'whole account split inherits header person, locks its selector and recovers exact payments',
    (t) async {
      await t.runAsync(() async {
        await t.binding.setSurfaceSize(const Size(1300, 1000));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final app = await AppDatabase.open(path: inMemoryDatabasePath);
        QuickSalesController? c;
        try {
          await fixture(app, moneyScale: 0);
          final person = await registerDebtor(app, 'Persona de prueba');
          final profile = (await SqliteWorkspaceStore(app).readProfile())!;
          final store = SqliteQuickSalesStore(app, synthetic: true);
          c = QuickSalesController(store: store);
          await c.load();
          final account = c.addAccount()!;
          final line = c.accounts.single.lines.single.id;
          c.editLine(
            account,
            QuickSaleLine(
              id: line,
              productId: 'product',
              quantityText: '2',
              unitPriceMinor: 10000,
            ),
          );
          c.addLine(account);
          final second = c.accounts.single.lines.last.id;
          c.editLine(
            account,
            QuickSaleLine(
              id: second,
              productId: 'product',
              unitPriceMinor: 10000,
            ),
          );
          await c.flushAll();
          Future<void> settle() async {
            await Future<void>.delayed(const Duration(milliseconds: 250));
            await t.pumpAndSettle();
          }

          Future<void> mount() async {
            await t.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: QuickSalesPage(controller: c!, profile: profile),
                  ),
                ),
              ),
            );
            await settle();
          }

          await mount();
          final split = find.byKey(ValueKey('quick-split-account-$account'));
          await t.ensureVisible(split);
          await t.tap(split);
          await settle();
          await t.enterText(
            find.byKey(const ValueKey('split-amount-quick-default:EFECTIVO')),
            '10000',
          );
          await t.enterText(
            find.byKey(const ValueKey('split-amount-quick-default:NEQUI')),
            '5000',
          );
          await t.tap(find.text('Enviar restante a Deudas'));
          await settle();
          expect(
            t
                .widget<TextField>(
                  find.byKey(const ValueKey('split-amount-quick-debt')),
                )
                .controller!
                .text,
            '15.000',
          );
          await t.tap(find.byKey(const Key('split-save')));
          await settle();
          expect(
            find.text(
              'Asocia la cuenta a una persona en el encabezado de Ventas para registrar deuda.',
            ),
            findsOneWidget,
          );
          expect(find.byKey(const Key('split-debtor')), findsNothing);
          await t.tap(find.text('Cancelar'));
          await settle();
          await t.tap(find.byKey(ValueKey('quick-person-picker-$account')));
          await settle();
          await t.tap(find.text('Persona de prueba').last);
          await settle();
          await t.tap(split);
          await settle();
          expect(
            find.text('La deuda se asignará a Persona de prueba.'),
            findsOneWidget,
          );
          await t.enterText(
            find.byKey(const ValueKey('split-amount-quick-default:EFECTIVO')),
            '10000',
          );
          await t.enterText(
            find.byKey(const ValueKey('split-amount-quick-default:NEQUI')),
            '5000',
          );
          await t.tap(find.text('Enviar restante a Deudas'));
          await settle();
          await t.tap(find.byKey(const Key('split-save')));
          await settle();
          expect(find.byKey(const Key('split-payment-dialog')), findsNothing);
          await c.flushAll();
          expect(c.accounts.single.debtorId, person);
          expect(c.creditTotalFor(c.accounts.single), BigInt.from(15000));
          await t.pumpWidget(const SizedBox());
          await settle();
          c.dispose();
          c = QuickSalesController(store: store);
          await c.load();
          await mount();
          expect(c.accounts.single.lines.first.paymentParts.length, 3);
          expect(c.accounts.single.lines.last.paymentParts.length, 3);
          expect(find.byKey(ValueKey('quick-payment-$line')), findsNothing);
          expect(find.byKey(ValueKey('quick-payment-$second')), findsNothing);
          expect(
            t
                .widget<DropdownButtonFormField<String>>(
                  find.byKey(ValueKey('quick-account-payment-$account')),
                )
                .onChanged,
            isNull,
          );
          expect(find.byKey(ValueKey('quick-split-$line')), findsNothing);
          await t.tap(find.byKey(ValueKey('quick-split-account-$account')));
          await settle();
          await t.enterText(
            find.byKey(const ValueKey('split-amount-quick-default:EFECTIVO')),
            '11000',
          );
          await t.tap(find.byKey(const Key('split-save')));
          await settle();
          expect(
            find.text(
              'La suma debe coincidir exactamente con el total de la cuenta.',
            ),
            findsOneWidget,
          );
          await t.tap(find.text('Cancelar'));
          await settle();
          final register = find.byKey(ValueKey('quick-register-$account'));
          await t.enterText(
            find.byKey(ValueKey('quick-product-$line')),
            'Producto',
          );
          await settle();
          expect(c.accounts.single.needsPaymentReview, isTrue);
          expect(t.widget<FilledButton>(register).onPressed, isNull);
          await t.tap(
            find.descendant(
              of: find.byKey(ValueKey('quick-options-$line')),
              matching: find.text('Producto sintético'),
            ),
          );
          await settle();
          expect(c.accounts.single.needsPaymentReview, isFalse);
          expect(c.accounts.single.lines.first.paymentParts.length, 3);
          await t.enterText(find.byKey(ValueKey('quick-quantity-$line')), '3');
          await settle();
          expect(c.accounts.single.needsPaymentReview, isTrue);
          expect(
            find.byKey(ValueKey('quick-credit-summary-$account')),
            findsNothing,
          );
          expect(
            find.text(
              'El consumo cambió. Revisa y guarda de nuevo la división antes de registrar.',
            ),
            findsOneWidget,
          );
          expect(t.widget<FilledButton>(register).onPressed, isNull);
          await t.ensureVisible(
            find.byKey(ValueKey('quick-single-payment-$account')),
          );
          await t.tap(find.byKey(ValueKey('quick-single-payment-$account')));
          await settle();
          final method = find.byKey(ValueKey('quick-account-payment-$account'));
          expect(
            t.widget<DropdownButtonFormField<String>>(method).onChanged,
            isNotNull,
          );
          expect(c.accounts.single.singlePaymentOptionId, isNull);
          expect(t.widget<FilledButton>(register).onPressed, isNull);
          expect(
            c.accounts.single.lines.every((l) => l.paymentParts.isEmpty),
            isTrue,
          );
          expect(c.accounts.single.debtorId, person);
          await t.tap(method);
          await settle();
          await t.tap(find.text('Transferencia').last);
          await settle();
          expect(
            c.accounts.single.lines.every(
              (l) => l.paymentOptionId == 'quick-default:NEQUI',
            ),
            isTrue,
          );
          expect(t.widget<FilledButton>(register).onPressed, isNotNull);
          await t.enterText(find.byKey(ValueKey('quick-quantity-$line')), '2');
          await settle();
          await t.tap(split);
          await settle();
          await t.enterText(
            find.byKey(const ValueKey('split-amount-quick-default:EFECTIVO')),
            '10000',
          );
          await t.enterText(
            find.byKey(const ValueKey('split-amount-quick-default:NEQUI')),
            '5000',
          );
          await t.tap(find.text('Enviar restante a Deudas'));
          await settle();
          await t.tap(find.byKey(const Key('split-save')));
          await settle();
          expect(c.accounts.single.needsPaymentReview, isFalse);
          await t.ensureVisible(register);
          await t.tap(register);
          await settle();
          expect(
            (await store.load()).sales.single.lines.fold(
              0,
              (sum, l) => sum + l.quantity,
            ),
            3,
          );
          final money = await SqliteTreasuryStore(app).load();
          expect(money.cashMinor, 10000);
          expect(money.nequiMinor, 5000);
          expect(money.receivablesMinor, 15000);
          expect((await store.load()).stock.single.quantity, 7);
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox());
          c?.dispose();
          await app.close();
        }
      });
    },
  );
}
