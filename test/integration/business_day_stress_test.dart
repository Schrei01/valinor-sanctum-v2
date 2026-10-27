import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/features/debtors/data/sqlite_debtors_store.dart';
import 'package:valinor_sanctum_2/features/debtors/domain/debtors_store.dart';
import 'package:valinor_sanctum_2/features/events/data/sqlite_events_store.dart';
import 'package:valinor_sanctum_2/features/events/domain/events_store.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/data/sqlite_quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_operation_store.dart';
import 'package:valinor_sanctum_2/features/treasury/domain/treasury_operation_store.dart';
import 'package:valinor_sanctum_2/features/reports/data/sqlite_reports_store.dart';
import 'package:valinor_sanctum_2/features/reports/domain/reports_store.dart';
import 'quick_sales_store_test.dart' show fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final seed in [17, 83, 2026]) {
    test(
      '20-person business day, out-of-order accounts, real reopen, events and money reconciliation seed $seed',
      () async {
        final root = p.normalize(AppConfig.repositoryRootPath);
        final parent = Directory(
          p.join(root, 'tmp', 'tests', 'business-stress'),
        );
        await parent.create(recursive: true);
        final directory = await parent.createTemp('day-$seed-');
        final path = p.join(directory.path, 'sanctum2.sqlite3');
        var app = await AppDatabase.open(path: path);
        try {
          await fixture(app, moneyScale: 0);
          await SqliteInventoryStore(app, synthetic: true).receivePurchase(
            ReceiptCommand(
              commandId: 'replenish',
              supplierId: 'supplier',
              occurredAtUtc: DateTime.utc(2026, 10, 19, 11),
              dueDate: '2026-10-20',
              lines: const [
                ReceiptLineInput(
                  productId: 'product',
                  quantity: 300,
                  totalCostMinor: 300000,
                ),
              ],
            ),
          );
          var quick = SqliteQuickSalesStore(app, synthetic: true);
          await quick.ensureDefaults();
          var debtors = SqliteDebtorsStore(app, synthetic: true);
          final people = <String>[];
          final debt = <String, int>{};
          for (var i = 0; i < 5; i++) {
            await debtors.prepare(
              DebtorCommand(
                commandId: 'person-$i',
                kind: 'create',
                name: 'Persona sintética $i',
                amountMinor: 2000,
                previousSource: PreviousDebtSource.additional,
                occurredAtUtc: DateTime.utc(2026, 10, 19, 12),
              ),
            );
            final id = await debtors.confirm('person-$i');
            people.add(id);
            debt[id] = 2000;
          }
          final options = await app.database.query('quick_payment_options');
          String cashId(String id) =>
              options.singleWhere((r) => r['id'] == id)['cash_account_id']
                  as String;
          final cash = cashId('quick-default:EFECTIVO'),
              nequi = cashId('quick-default:NEQUI');
          var cashExpected = 0,
              nequiExpected = 0,
              stockExpected = 310,
              paid = 0,
              totalSales = 0,
              creditSales = 0;
          var tick = 0;
          DateTime now() =>
              DateTime.utc(2026, 10, 27, 14).add(Duration(seconds: tick++));
          String? event;
          final open = <int>{}, done = <int>{};
          List<QuickSaleLine> lines(int i) => [
            for (var j = 0; j < 3; j++)
              QuickSaleLine(
                id: 'l-$i-$j',
                productId: 'product',
                quantityText: '1',
                unitPriceMinor: 1000,
                paymentOptionId: switch (i % 4) {
                  0 => 'quick-default:EFECTIVO',
                  1 => 'quick-default:NEQUI',
                  2 => QuickPaymentOption.creditId,
                  _ => [
                    'quick-default:EFECTIVO',
                    'quick-default:NEQUI',
                    QuickPaymentOption.creditId,
                  ][j],
                },
              ),
            if (event != null && i >= 5 && i % 5 == 0)
              QuickSaleLine(
                id: 'event-$i',
                productId: event,
                quantityText: '1',
                unitPriceMinor: 5000,
                paymentOptionId: 'quick-default:EFECTIVO',
              ),
          ];
          Future<void> add(int i) async {
            await quick.saveAccount(
              SaveQuickSaleAccount(
                id: 'a-$i',
                label: 'Cuenta ${i + 1}',
                expectedRevision: 0,
                debtorId: people[i % 5],
                customerName: 'Persona sintética ${i % 5}',
                lines: lines(i),
              ),
            );
            open.add(i);
          }

          Future<void> reconcile() async {
            final money = await SqliteTreasuryStore(app).load();
            expect(money.cashMinor, cashExpected);
            expect(money.nequiMinor, nequiExpected);
            expect(
              money.receivablesMinor,
              debt.values.fold(0, (a, b) => a + b),
            );
            final ds = await debtors.load();
            for (final id in people) {
              expect(
                ds.debtors.singleWhere((d) => d.id == id).balanceMinor,
                debt[id],
              );
            }
            final inventory = await SqliteInventoryStore(app).load();
            final stock = inventory.stock.singleWhere(
              (s) => s.productId == 'product',
            );
            expect(stock.quantity, stockExpected);
            final state = await quick.load();
            expect(
              state.accounts.map((a) => a.id).toSet(),
              open.map((i) => 'a-$i').toSet(),
            );
            expect(state.sales.length, paid);
            expect(
              await app.database.rawQuery(
                'SELECT entry_id FROM journal_lines GROUP BY entry_id HAVING SUM(debit_minor)<>SUM(credit_minor)',
              ),
              isEmpty,
            );
          }

          Future<void> pay(int i, {bool reopenPrepared = false}) async {
            final row = (await quick.load()).accounts.singleWhere(
              (a) => a.id == 'a-$i',
            );
            await quick.prepareSale(
              commandId: 'sale-$i',
              accountId: row.id,
              expectedRevision: row.revision,
              occurredAtUtc: now(),
            );
            if (reopenPrepared) {
              await app.close();
              app = await AppDatabase.open(path: path);
              quick = SqliteQuickSalesStore(app, synthetic: true);
              debtors = SqliteDebtorsStore(app, synthetic: true);
              expect(
                (await quick.load()).pendingSales.any(
                  (s) => s.commandId == 'sale-$i',
                ),
                isTrue,
              );
            }
            final result = await quick.confirmPrepared('sale-$i');
            for (final l in lines(i)) {
              final n = l.unitPriceMinor!;
              totalSales += n;
              if (l.paymentOptionId == 'quick-default:EFECTIVO') {
                cashExpected += n;
              } else if (l.paymentOptionId == 'quick-default:NEQUI') {
                nequiExpected += n;
              } else {
                debt[people[i % 5]] = debt[people[i % 5]]! + n;
                creditSales += n;
              }
            }
            stockExpected -= 3;
            paid++;
            open.remove(i);
            done.add(i);
            final rows = await app.database.query('journal_lines');
            expect(
              (await quick.confirmPrepared('sale-$i')).saleDocumentId,
              result.saleDocumentId,
            );
            expect(await app.database.query('journal_lines'), rows);
            await reconcile();
          }

          for (var i = 0; i < 5; i++) {
            await add(i);
          }
          await reconcile();
          await pay(1);
          await pay(3); // Account 2 is paid first; account 4 second.
          final events = SqliteEventsStore(app, synthetic: true);
          await events.prepare(
            CreateEvent(
              commandId: 'league',
              name: 'Liga de jornada sintética',
              minimumPeople: 5,
              fixedCostMinor: 500,
              pvpMinor: 5000,
              sourceAccountId: cash,
              products: const [EventProductInput('product', 2)],
              occurredAtUtc: now(),
            ),
          );
          event = await events.confirm('league');
          cashExpected -= 500;
          stockExpected -= 2;
          expect(
            (await SqliteInventoryStore(
              app,
            ).load()).products.any((p) => p.id == event && p.isEvent),
            isTrue,
          );
          expect(
            (await quick.load()).availableProducts.any(
              (p) => p.id == event && p.isUnlimited,
            ),
            isTrue,
          );
          final operations = SqliteTreasuryOperationStore(app, synthetic: true);
          await operations.ensureDefaults();
          await operations.prepare(
            TreasuryOperationCommand(
              commandId: 'transfer',
              kind: TreasuryOperationKind.transfer,
              sourceAccountId: cash,
              destinationAccountId: nequi,
              amountMinor: 200,
              reason: 'Transferencia',
              occurredAtUtc: now(),
            ),
          );
          await operations.confirmPrepared('transfer');
          await operations.confirmPrepared('transfer');
          cashExpected -= 200;
          nequiExpected += 200;
          await operations.prepare(
            TreasuryOperationCommand(
              commandId: 'cleaning',
              kind: TreasuryOperationKind.expense,
              sourceAccountId: nequi,
              amountMinor: 100,
              reason: 'Aseo',
              occurredAtUtc: now(),
            ),
          );
          await operations.confirmPrepared('cleaning');
          nequiExpected -= 100;
          await debtors.prepare(
            DebtorCommand(
              commandId: 'payment',
              kind: 'payment',
              debtorId: people[3],
              amountMinor: 400,
              paymentOptionId: 'quick-default:EFECTIVO',
              occurredAtUtc: now(),
            ),
          );
          await debtors.confirm('payment');
          await debtors.confirm('payment');
          debt[people[3]] = debt[people[3]]! - 400;
          cashExpected += 400;
          await add(5);
          expect((await quick.load()).accounts.length, 4);
          await app.close();
          app = await AppDatabase.open(path: path);
          quick = SqliteQuickSalesStore(app, synthetic: true);
          debtors = SqliteDebtorsStore(app, synthetic: true);
          await reconcile();
          await pay(5, reopenPrepared: true);
          await pay(0);
          for (var i = 6; i < 20; i++) {
            await add(i);
          }
          await reconcile();
          final remainder = open.toList()..shuffle(Random(seed));
          for (final i in remainder) {
            await pay(i);
          }
          expect(done.length, 20);
          expect(cashExpected, 34700);
          expect(nequiExpected, 20100);
          expect(debt.values.fold(0, (a, b) => a + b), 29600);
          expect(stockExpected, 248);
          expect(
            (await SqliteInventoryStore(app).load()).stock
                .singleWhere((s) => s.productId == 'product')
                .totalCostMinor,
            248000,
          );
          final report = await SqliteReportsStore(app).load(
            ReportPeriod(
              start: DateTime.utc(2026, 10, 27),
              end: DateTime.utc(2026, 10, 27),
            ),
          );
          expect(report.salesMinor, totalSales);
          expect(totalSales, 75000);
          expect(report.creditSalesMinor, creditSales);
          expect(creditSales, 20000);
          expect(report.debtorPaymentsMinor, 400);
          expect(report.knownTransferTotalMinor, 200);
          expect(report.outflowTotals.totalMinor, 600);
          expect(report.debtClosingMinor, 29600);
          expect(
            report.debtorBalances.fold(0, (a, b) => a + b.amountMinor),
            29600,
          );
          final health = await app.readHealth();
          expect(health['integrityOk'], isTrue);
          expect(health['foreignKeyViolations'], 0);
        } finally {
          await app.close();
          final resolved = await directory.resolveSymbolicLinks();
          if (!p.isWithin(root, resolved)) {
            throw StateError('Unsafe test cleanup');
          }
          await directory.delete(recursive: true);
        }
      },
      timeout: const Timeout(Duration(minutes: 8)),
    );
  }
}
