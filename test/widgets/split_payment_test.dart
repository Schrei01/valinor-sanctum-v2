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
    'split dialog validates, assigns a person, formats money, saves and recovers one physical sale',
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
              unitPriceMinor: 30000,
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
          final split = find.byKey(ValueKey('quick-split-$line'));
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
            find.text('Selecciona una persona para asignar la deuda.'),
            findsOneWidget,
          );
          await t.tap(find.byKey(const Key('split-debtor')));
          await settle();
          await t.tap(find.text('Persona de prueba').last);
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
          expect(c.accounts.single.lines.single.paymentParts.length, 3);
          await t.tap(find.byKey(ValueKey('quick-split-$line')));
          await settle();
          await t.enterText(
            find.byKey(const ValueKey('split-amount-quick-default:EFECTIVO')),
            '11000',
          );
          await t.tap(find.byKey(const Key('split-save')));
          await settle();
          expect(
            find.text(
              'La suma debe coincidir exactamente con el total de la línea.',
            ),
            findsOneWidget,
          );
          await t.tap(find.text('Cancelar'));
          await settle();
          final register = find.byKey(ValueKey('quick-register-$account'));
          await t.ensureVisible(register);
          await t.tap(register);
          await settle();
          expect((await store.load()).sales.single.lines.single.quantity, 1);
          final money = await SqliteTreasuryStore(app).load();
          expect(money.cashMinor, 10000);
          expect(money.nequiMinor, 5000);
          expect(money.receivablesMinor, 15000);
          expect((await store.load()).stock.single.quantity, 9);
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
