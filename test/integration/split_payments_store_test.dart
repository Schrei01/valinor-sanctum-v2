import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/features/quick_sales/data/sqlite_quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_store.dart';
import 'package:valinor_sanctum_2/features/reports/data/sqlite_reports_store.dart';
import 'package:valinor_sanctum_2/features/reports/domain/reports_store.dart';
import 'quick_sales_store_test.dart' show fixture;
import '../support/register_debtor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final credit in [0, 15000, 30000]) {
    test(
      'split amount $credit credit posts one unit, exact money and report; retry unchanged',
      () async {
        final app = await AppDatabase.open(path: inMemoryDatabasePath);
        addTearDown(app.close);
        await fixture(app, moneyScale: 0);
        final store = SqliteQuickSalesStore(app, synthetic: true);
        await store.ensureDefaults();
        final person = credit > 0
            ? await registerDebtor(app, 'Persona sintética')
            : null;
        final cash = credit == 30000 ? 0 : 10000,
            transfer = 30000 - credit - (credit == 30000 ? 0 : 10000);
        final parts = [
          if (cash > 0) QuickLinePaymentPart('quick-default:EFECTIVO', cash),
          if (transfer > 0)
            QuickLinePaymentPart('quick-default:NEQUI', transfer),
          if (credit > 0)
            QuickLinePaymentPart(QuickPaymentOption.creditId, credit),
        ];
        final saved = await store.saveAccount(
          SaveQuickSaleAccount(
            id: 'split',
            label: 'Cuenta',
            expectedRevision: 0,
            debtorId: person,
            customerName: person == null ? '' : 'Persona sintética',
            lines: [
              QuickSaleLine(
                id: 'line',
                productId: 'product',
                unitPriceMinor: 30000,
                paymentParts: parts,
              ),
            ],
          ),
        );
        expect(
          (await store.load()).accounts.single.lines.single.paymentParts.length,
          parts.length,
        );
        await store.prepareSale(
          commandId: 'confirm',
          accountId: saved.id,
          expectedRevision: saved.revision,
          occurredAtUtc: DateTime.utc(2026, 10, 28, 15),
        );
        final result = await store.confirmPrepared('confirm');
        expect(result.totalMinor, 30000);
        expect(result.creditMinor, credit);
        final before = await app.database.query('journal_lines');
        await store.confirmPrepared('confirm');
        expect(await app.database.query('journal_lines'), before);
        final money = await SqliteTreasuryStore(app).load();
        expect(money.cashMinor, cash);
        expect(money.nequiMinor, transfer);
        expect(money.receivablesMinor, credit);
        expect((await store.load()).stock.single.quantity, 9);
        expect((await store.load()).sales.single.lines.length, 1);
        expect((await store.load()).sales.single.lines.single.quantity, 1);
        final report = await SqliteReportsStore(app).load(
          ReportPeriod(
            start: DateTime.utc(2026, 10, 28),
            end: DateTime.utc(2026, 10, 28),
          ),
        );
        expect(report.salesMinor, 30000);
        expect(report.creditSalesMinor, credit);
        expect(await app.database.query('sale_lines'), hasLength(1));
      },
    );
  }
}
