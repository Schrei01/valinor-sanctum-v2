import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/features/debtors/data/sqlite_debtors_store.dart';
import 'package:valinor_sanctum_2/features/debtors/domain/debtors_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/application/quick_sales_controller.dart';
import 'package:valinor_sanctum_2/features/quick_sales/data/sqlite_quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_store.dart';
import 'quick_sales_store_test.dart' show fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'named mixed account adds only credit to its owner and paid lines to their cash accounts',
    () async {
      final app = await AppDatabase.open(path: inMemoryDatabasePath);
      QuickSalesController? controller;
      try {
        await fixture(app);
        final debtors = SqliteDebtorsStore(app, synthetic: true);
        Future<String> person(String name, int initial) async {
          await debtors.prepare(
            DebtorCommand(
              commandId: 'create-$initial',
              kind: 'create',
              name: name,
              amountMinor: initial,
              previousSource: PreviousDebtSource.additional,
              occurredAtUtc: DateTime.utc(2026, 10, 19, 12),
            ),
          );
          return debtors.confirm('create-$initial');
        }

        final owner = await person('Persona primera', 5000);
        final other = await person('Persona segunda', 7000);
        final store = SqliteQuickSalesStore(app, synthetic: true);
        controller = QuickSalesController(
          store: store,
          autosaveDelay: const Duration(days: 1),
        );
        await controller.load();
        final account = controller.addAccount()!;
        controller.selectDebtor(account, owner);
        expect(controller.accounts.single.label, 'Persona primera');
        expect(controller.accounts.single.debtorId, owner);
        for (final payment in [
          'quick-default:EFECTIVO',
          'quick-default:NEQUI',
          QuickPaymentOption.creditId,
        ].indexed) {
          if (payment.$1 > 0) controller.addLine(account);
          final line = controller.accounts.single.lines[payment.$1];
          controller.editLine(
            account,
            QuickSaleLine(
              id: line.id,
              productId: 'product',
              quantityText: '1',
              unitPriceMinor: 10000,
              paymentOptionId: payment.$2,
            ),
          );
        }
        expect(await controller.flushAll(), isTrue);
        await controller.load();
        expect(controller.accounts.single.debtorId, owner);
        expect(await controller.register(account), isTrue);
        final people = (await debtors.load()).debtors;
        expect(people.singleWhere((p) => p.id == owner).balanceMinor, 15000);
        expect(people.singleWhere((p) => p.id == other).balanceMinor, 7000);
        final treasury = await SqliteTreasuryStore(app).load();
        expect(treasury.cashMinor, 10000);
        expect(treasury.nequiMinor, 10000);
        expect(treasury.receivablesMinor, 22000);
        final history = (await store.load()).sales.single;
        expect(history.label, 'Persona primera');
        expect(history.result.debtorId, owner);
        expect(history.result.totalMinor, 30000);
        expect(history.result.creditMinor, 10000);
        expect(history.lines.map((l) => l.paymentLabel), [
          'Efectivo',
          'Nequi',
          'Deudas',
        ]);
        final before = await app.database.query('journal_lines');
        await store.confirmPrepared(history.commandId);
        expect(await app.database.query('journal_lines'), before);
        expect((await app.database.query('sales')).length, 1);
      } finally {
        controller?.dispose();
        await app.close();
      }
    },
  );
}
