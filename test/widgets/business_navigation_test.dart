import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/app/sanctum_app.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/features/workspace/application/workspace_controller.dart';
import 'package:valinor_sanctum_2/features/workspace/data/sqlite_workspace_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/workspace_store.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_inventory_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/data/sqlite_quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/presentation/quick_sales_page.dart';
import 'package:valinor_sanctum_2/features/debtors/data/sqlite_debtors_store.dart';
import 'package:valinor_sanctum_2/features/events/data/sqlite_events_store.dart';
import 'package:valinor_sanctum_2/features/events/domain/events_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_operation_store.dart';
import 'package:valinor_sanctum_2/features/reports/data/sqlite_reports_store.dart';
import '../integration/quick_sales_store_test.dart' show fixture;
import '../support/register_debtor.dart';
import 'package:valinor_sanctum_2/features/stock_intake/data/sqlite_stock_intake_store.dart';

void main() {
  testWidgets(
    'real SQLite accounts survive every tab, unordered GUI payments, new arrivals and widget reopen',
    (t) async {
      await t.runAsync(() async {
        await t.binding.setSurfaceSize(const Size(1366, 1000));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final app = await AppDatabase.open(path: inMemoryDatabasePath);
        WorkspaceController? workspace;
        try {
          await fixture(app, moneyScale: 0);
          final person = await registerDebtor(app, 'Titular de navegación');
          final events = SqliteEventsStore(app, synthetic: true);
          await events.prepare(
            CreateEvent(
              commandId: 'nav-event',
              name: 'Liga de navegación',
              minimumPeople: 2,
              fixedCostMinor: 0,
              pvpMinor: 5000,
              products: const [EventProductInput('product', 1)],
              occurredAtUtc: DateTime.utc(2026, 10, 19, 13),
            ),
          );
          final event = await events.confirm('nav-event');
          final store = SqliteQuickSalesStore(app, synthetic: true);
          workspace = WorkspaceController(
            openSession: () async => WorkspaceSession(
              store: SqliteWorkspaceStore(app),
              databasePath: 'synthetic',
              profileId: 'quick-test',
              quickSalesStore: store,
              stockIntakeStore: SqliteStockIntakeStore(app, synthetic: true),
              inventoryStore: SqliteInventoryStore(app, synthetic: true),
              debtorsStore: SqliteDebtorsStore(app, synthetic: true),
              eventsStore: events,
              treasuryStore: SqliteTreasuryStore(app),
              treasuryOperationStore: SqliteTreasuryOperationStore(
                app,
                synthetic: true,
              ),
              reportsStore: SqliteReportsStore(app),
            ),
          );
          await workspace.initialize();
          await t.pumpWidget(SanctumApp(controller: workspace));
          await Future<void>.delayed(const Duration(milliseconds: 250));
          await t.pumpAndSettle();
          final c = t
              .widget<QuickSalesPage>(find.byType(QuickSalesPage))
              .controller;
          final ids = <String>[];
          for (var i = 0; i < 5; i++) {
            final id = c.addAccount()!;
            ids.add(id);
            if (i == 2 || i == 3) c.selectDebtor(id, person);
            final row = c.accounts.singleWhere((a) => a.id == id).lines.first;
            c.editLine(
              id,
              QuickSaleLine(
                id: row.id,
                productId: 'product',
                quantityText: '1',
                unitPriceMinor: 1000,
                paymentOptionId: i == 1
                    ? 'quick-default:NEQUI'
                    : i == 2 || i == 3
                    ? QuickPaymentOption.creditId
                    : 'quick-default:EFECTIVO',
              ),
            );
          }
          await c.flushAll();
          await Future<void>.delayed(const Duration(milliseconds: 250));
          await t.pumpAndSettle();
          Future<void> tab(String name) async {
            final f = find.text(name).first;
            await t.ensureVisible(f);
            await t.tap(f);
            await Future<void>.delayed(const Duration(milliseconds: 250));
            await t.pumpAndSettle();
          }

          Future<void> pay(String id) async {
            final f = find.byKey(ValueKey('quick-register-$id'));
            await t.ensureVisible(f);
            await t.tap(f);
            await Future<void>.delayed(const Duration(milliseconds: 250));
            await t.pumpAndSettle();
          }

          await pay(ids[1]);
          await pay(ids[3]);
          final sixth = c.addAccount()!;
          final row = c.accounts.singleWhere((a) => a.id == sixth).lines.first;
          c.editLine(
            sixth,
            QuickSaleLine(
              id: row.id,
              productId: event,
              quantityText: '2',
              unitPriceMinor: 5000,
              paymentOptionId: 'quick-default:EFECTIVO',
            ),
          );
          await c.flushAll();
          await Future<void>.delayed(const Duration(milliseconds: 250));
          await t.pumpAndSettle();
          final expected = {ids[0], ids[2], ids[4], sixth};
          for (var cycle = 0; cycle < 3; cycle++) {
            for (final name in [
              'Catálogo',
              'Compras',
              'Deudores',
              'Tesorería',
              'Eventos',
              'Reportes',
            ]) {
              await tab(name);
              if (name == 'Catálogo') {
                expect(find.text('Liga de navegación'), findsOneWidget);
              }
            }
            await tab('Ventas');
            expect(c.accounts.map((a) => a.id).toSet(), expected);
            expect(
              (await store.load()).accounts.map((a) => a.id).toSet(),
              expected,
            );
            expect(
              c.accounts.singleWhere((a) => a.id == ids[2]).debtorId,
              person,
            );
            expect(
              c.accounts
                  .singleWhere((a) => a.id == sixth)
                  .lines
                  .single
                  .quantityText,
              '2',
            );
          }
          expect((await store.load()).sales.length, 2);
          expect(
            (await SqliteDebtorsStore(app).load()).debtors.single.balanceMinor,
            1000,
          );
          final bank = await SqliteTreasuryStore(app).load();
          expect(bank.nequiMinor, 1000);
          expect(bank.cashMinor, 0);
          expect(
            (await SqliteInventoryStore(app).load()).stock.single.quantity,
            7,
          );
          await t.pumpWidget(const SizedBox());
          await Future<void>.delayed(const Duration(milliseconds: 250));
          await t.pumpAndSettle();
          await t.pumpWidget(SanctumApp(controller: workspace));
          await Future<void>.delayed(const Duration(milliseconds: 250));
          await t.pumpAndSettle();
          final reopened = t
              .widget<QuickSalesPage>(find.byType(QuickSalesPage))
              .controller;
          expect(reopened.accounts.map((a) => a.id).toSet(), expected);
          expect(
            reopened.snapshot!.availableProducts.any((p) => p.id == event),
            isTrue,
          );
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox());
          workspace?.dispose();
          await app.close();
        }
      });
    },
  );
}
