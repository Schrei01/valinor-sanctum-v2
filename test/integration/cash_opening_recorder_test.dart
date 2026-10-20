import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/features/collections/data/sqlite_collections_store.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/data/sqlite_quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/stock_intake/data/sqlite_cash_opening_recorder.dart';
import 'package:valinor_sanctum_2/features/stock_intake/domain/stock_intake_store.dart';
import 'package:valinor_sanctum_2/features/workspace/data/sqlite_workspace_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase app;
  late SqliteCashOpeningRecorder recorder;
  setUp(() async {
    app = await AppDatabase.open(path: inMemoryDatabasePath);
    await SqliteWorkspaceStore(app).createProfile(
      BusinessProfile(
        profileId: 'opening-test',
        businessName: 'Saldo sintético',
        currencyCode: 'COP',
        moneyScale: 2,
        timezone: 'America/Bogota',
        createdAtUtc: DateTime.utc(2026, 10, 19),
      ),
    );
    await SqliteQuickSalesStore(app, synthetic: true).ensureDefaults();
    recorder = SqliteCashOpeningRecorder(app, synthetic: true);
  });
  tearDown(() => app.close());

  CashOpeningCommand command({
    String id = 'opening',
    int amount = 100000,
    String option = 'EFECTIVO',
  }) => CashOpeningCommand(
    commandId: id,
    paymentOptionId: 'quick-default:$option',
    amountMinor: amount,
    occurredAtUtc: DateTime.utc(2026, 10, 19, 12),
  );
  Future<int> balance(String option) async {
    final account = (await app.database.query(
      'quick_payment_options',
      where: 'id=?',
      whereArgs: ['quick-default:$option'],
    )).single['cash_account_id'];
    return (await SqliteCollectionsStore(
      app,
    ).load()).accounts.singleWhere((a) => a.id == account).balanceMinor;
  }

  test(
    'a declared opening creates equity and money once, never revenue or debt',
    () async {
      expect(await balance('EFECTIVO'), 0);
      await recorder.record(command());
      await SqliteCashOpeningRecorder(app, synthetic: true).record(command());
      expect(await balance('EFECTIVO'), 100000);
      expect(await balance('NEQUI'), 0);
      expect((await app.database.query('cash_openings')).length, 1);
      expect((await app.database.query('journal_entries')).length, 1);
      expect(await app.database.query('obligations'), isEmpty);
      expect(await app.database.query('sales'), isEmpty);
      expect(await app.database.query('purchases'), isEmpty);
      final equity = (await app.database.rawQuery(
        "SELECT l.* FROM journal_lines l JOIN ledger_accounts a ON a.id=l.account_id WHERE a.class='equity'",
      )).single;
      expect(equity['credit_minor'], 100000);
      expect(equity['debit_minor'], 0);
      expect((await app.readHealth())['integrityOk'], isTrue);
    },
  );

  test(
    'each money account accepts its own opening, but a second ID cannot duplicate it',
    () async {
      await recorder.record(command());
      await recorder.record(
        command(id: 'mobile-opening', option: 'NEQUI', amount: 70000),
      );
      await expectLater(
        recorder.record(command(id: 'another-opening')),
        throwsA(isA<StockIntakeValidationException>()),
      );
      expect(await balance('EFECTIVO'), 100000);
      expect(await balance('NEQUI'), 70000);
      expect((await app.database.query('command_log')).length, 2);
    },
  );

  test(
    'a reused command cannot silently change its amount or destination',
    () async {
      await recorder.record(command());
      await expectLater(
        recorder.record(command(amount: 200000)),
        throwsA(isA<StockIntakeValidationException>()),
      );
      await expectLater(
        recorder.record(command(option: 'NEQUI')),
        throwsA(isA<StockIntakeValidationException>()),
      );
      expect(await balance('EFECTIVO'), 100000);
      expect(await balance('NEQUI'), 0);
    },
  );

  test('zero, negative and inactive-account openings leave no money', () async {
    for (final amount in [0, -1]) {
      await expectLater(
        recorder.record(command(amount: amount)),
        throwsA(isA<StockIntakeValidationException>()),
      );
    }
    await app.database.update(
      'cash_accounts',
      {'is_active': 0},
      where: 'kind=?',
      whereArgs: ['cash'],
    );
    await expectLater(
      recorder.record(command()),
      throwsA(isA<StockIntakeValidationException>()),
    );
    expect(await app.database.query('cash_openings'), isEmpty);
    expect(await app.database.query('command_log'), isEmpty);
  });

  test(
    'failure while posting an opening rolls back both money and its command',
    () async {
      await app.database.execute(
        "CREATE TRIGGER synthetic_opening_failure BEFORE UPDATE OF status ON journal_entries WHEN NEW.status='posted' BEGIN SELECT RAISE(ABORT,'synthetic failure'); END",
      );
      await expectLater(
        recorder.record(command()),
        throwsA(isA<DatabaseException>()),
      );
      expect(await app.database.query('cash_openings'), isEmpty);
      expect(await app.database.query('command_log'), isEmpty);
      expect(await app.database.query('business_documents'), isEmpty);
      expect(await balance('EFECTIVO'), 0);
      await app.database.execute('DROP TRIGGER synthetic_opening_failure');
      await recorder.record(command());
      expect(await balance('EFECTIVO'), 100000);
    },
  );

  test(
    'an account with recorded sales cannot add its current money again as an opening',
    () async {
      final inventory = SqliteInventoryStore(app, synthetic: true);
      await inventory.saveSupplier(
        const InventorySupplier(id: 'supplier', name: 'Proveedor sintético'),
      );
      await inventory.saveProduct(
        const CatalogProduct(
          id: 'product',
          name: 'Producto sintético',
          listPriceMinor: 500,
        ),
      );
      await inventory.receivePurchase(
        ReceiptCommand(
          commandId: 'historical-receipt',
          supplierId: 'supplier',
          lines: const [
            ReceiptLineInput(
              productId: 'product',
              quantity: 1,
              totalCostMinor: 100,
            ),
          ],
          dueDate: '2026-10-19',
          occurredAtUtc: DateTime.utc(2026, 10, 19, 14),
        ),
      );
      final quick = SqliteQuickSalesStore(app, synthetic: true);
      await quick.saveAccount(
        SaveQuickSaleAccount(
          id: 'tab',
          label: 'Cuenta sintética',
          expectedRevision: 0,
          lines: const [
            QuickSaleLine(
              id: 'line',
              productId: 'product',
              unitPriceMinor: 500,
              paymentOptionId: 'quick-default:EFECTIVO',
            ),
          ],
        ),
      );
      await quick.prepareSale(
        commandId: 'sale',
        accountId: 'tab',
        expectedRevision: 1,
        occurredAtUtc: DateTime.utc(2026, 10, 19, 16),
      );
      await quick.confirmPrepared('sale');
      await expectLater(
        recorder.record(command()),
        throwsA(isA<StockIntakeValidationException>()),
      );
      expect(await balance('EFECTIVO'), 500);
      expect(await app.database.query('cash_openings'), isEmpty);
    },
  );
}
