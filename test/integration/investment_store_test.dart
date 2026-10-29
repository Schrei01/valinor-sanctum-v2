import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/investment_ledger.dart';
import 'package:valinor_sanctum_2/core/domain/money.dart';
import 'package:valinor_sanctum_2/features/workspace/data/sqlite_workspace_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';
import 'package:valinor_sanctum_2/features/stock_intake/data/sqlite_stock_intake_store.dart';
import 'package:valinor_sanctum_2/features/stock_intake/domain/stock_intake_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_operation_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_opening_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_store.dart';
import 'package:valinor_sanctum_2/features/treasury/domain/treasury_operation_store.dart';
import 'package:valinor_sanctum_2/features/treasury/domain/treasury_opening.dart';
import 'package:valinor_sanctum_2/features/reports/data/sqlite_reports_store.dart';
import 'package:valinor_sanctum_2/features/reports/domain/reports_store.dart';
import '../support/released_v15_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase app;
  late SqliteStockIntakeStore intake;
  late SqliteTreasuryOperationStore operations;
  Future<void> configure(AppDatabase db) async {
    await SqliteWorkspaceStore(db).createProfile(
      BusinessProfile(
        profileId: 'test',
        businessName: 'Tienda sintética',
        currencyCode: 'COP',
        moneyScale: 0,
        timezone: 'America/Bogota',
        createdAtUtc: DateTime.utc(2026, 10, 20),
      ),
    );
    await SqliteTreasuryStore(db).ensureDefaults();
  }

  setUp(() async {
    app = await AppDatabase.open(path: inMemoryDatabasePath);
    await configure(app);
    intake = SqliteStockIntakeStore(app, synthetic: true);
    operations = SqliteTreasuryOperationStore(app, synthetic: true);
    await intake.ensureDefaults();
    await operations.ensureDefaults();
  });
  tearDown(() => app.close());
  Future<void> cash({int amount = 100000}) => intake.recordOpeningBalance(
    CashOpeningCommand(
      commandId: 'cash-opening',
      paymentOptionId: 'quick-default:EFECTIVO',
      amountMinor: amount,
      occurredAtUtc: DateTime.utc(2026, 10, 20),
    ),
  );
  Future<void> purchase({String id = 'invest', int amount = 25000}) async {
    final category = (await intake.load()).categories.first.id;
    await intake.prepare(
      StockIntakeCommand(
        commandId: id,
        productId: 'product-$id',
        productName: 'Producto $id',
        categoryId: category,
        supplierName: 'Proveedor',
        totalPurchasePriceMinor: amount,
        listPriceMinor: 4000,
        quantity: 10,
        paymentOptionId: 'investment',
        occurredAtUtc: DateTime.utc(2026, 10, 29, 20),
      ),
    );
    await intake.confirmPrepared(id);
  }

  Future<TreasuryOperationCommand> refund(
    String id,
    int amount, {
    String option = 'quick-default:EFECTIVO',
  }) async => TreasuryOperationCommand(
    commandId: id,
    kind: TreasuryOperationKind.investmentRefund,
    sourceAccountId:
        (await app.database.query(
              'quick_payment_options',
              where: 'id=?',
              whereArgs: [option],
            )).single['cash_account_id']
            as String,
    amountMinor: amount,
    reason: 'Devolución de inversión',
    occurredAtUtc: DateTime.utc(2026, 10, 29, 21),
  );

  test(
    'refund is partial, atomic and idempotent, and reports keep it separate from operating expenses',
    () async {
      await cash();
      await purchase();
      final c = await refund('refund', 10000);
      await operations.prepare(c);
      final result = await operations.confirmPrepared(c.commandId);
      expect(
        (await operations.confirmPrepared(c.commandId)).documentId,
        result.documentId,
      );
      final data = await SqliteTreasuryStore(app).load();
      expect(data.cashMinor, 90000);
      expect(data.nequiMinor, 0);
      expect(data.investmentMinor, 15000);
      expect(data.totalAvailableMinor, 90000);
      final report = await SqliteReportsStore(app).load(
        ReportPeriod(
          start: DateTime.utc(2026, 10, 29),
          end: DateTime.utc(2026, 10, 29),
        ),
      );
      expect(report.investmentRefundsMinor, 10000);
      expect(report.outflowTotals.totalMinor, 0);
      expect(report.operatingExpensesMinor, 0);
      expect(report.salesMinor, 0);
      expect(report.investmentRefundsFor(ReportAccountRole.cash), 10000);
      expect(
        report.accounts
            .singleWhere((a) => a.role == ReportAccountRole.cash)
            .closingMinor,
        90000,
      );
      expect(await app.database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );
  test(
    'refund from Nequi and full return reduce the owner balance to zero',
    () async {
      await intake.recordOpeningBalance(
        CashOpeningCommand(
          commandId: 'nequi-opening',
          paymentOptionId: 'quick-default:NEQUI',
          amountMinor: 50000,
          occurredAtUtc: DateTime.utc(2026, 10, 20),
        ),
      );
      await purchase();
      final c = await refund(
        'nequi-refund',
        25000,
        option: 'quick-default:NEQUI',
      );
      await operations.prepare(c);
      await operations.confirmPrepared(c.commandId);
      final data = await SqliteTreasuryStore(app).load();
      expect(data.nequiMinor, 25000);
      expect(data.investmentMinor, 0);
    },
  );
  test(
    'overpayment, insufficient cash and reserve source are rejected without financial writes',
    () async {
      await cash(amount: 10000);
      await purchase();
      final before = await app.database.query('journal_lines');
      await expectLater(
        operations.prepare(await refund('over-owner', 30000)),
        throwsA(isA<TreasuryValidationException>()),
      );
      await expectLater(
        operations.prepare(await refund('over-cash', 11000)),
        throwsA(isA<TreasuryValidationException>()),
      );
      await expectLater(
        operations.prepare(
          TreasuryOperationCommand(
            commandId: 'reserve-refund',
            kind: TreasuryOperationKind.investmentRefund,
            sourceAccountId: SqliteTreasuryStore.reserveAccountId,
            amountMinor: 1,
            reason: 'Devolución de inversión',
            occurredAtUtc: DateTime.utc(2026, 10, 29, 21),
          ),
        ),
        throwsA(isA<TreasuryValidationException>()),
      );
      expect(await app.database.query('journal_lines'), before);
      expect(await app.database.query('investment_refund_requests'), isEmpty);
    },
  );
  test(
    'funds and debt are revalidated after preparation; rollback keeps stock and cash unchanged',
    () async {
      await cash(amount: 10000);
      await purchase();
      final a = await refund('first', 9000), b = await refund('second', 9000);
      await operations.prepare(a);
      await operations.prepare(b);
      await operations.confirmPrepared(a.commandId);
      await expectLater(
        operations.confirmPrepared(b.commandId),
        throwsA(isA<TreasuryValidationException>()),
      );
      expect(
        (await app.database.query(
          'investment_refund_requests',
          where: 'command_id=?',
          whereArgs: [b.commandId],
        )).single['status'],
        'rejected',
      );
      expect((await SqliteTreasuryStore(app).load()).cashMinor, 1000);
      expect((await intake.load()).stock.single.quantity, 10);
      await operations.discardRejected(b.commandId);
    },
  );
  test(
    'failed posting rolls the entire owner purchase back and allows the same prepared retry',
    () async {
      final category = (await intake.load()).categories.first.id;
      final c = StockIntakeCommand(
        commandId: 'rollback',
        productId: 'rollback-product',
        productName: 'Producto rollback',
        categoryId: category,
        supplierName: 'Proveedor',
        totalPurchasePriceMinor: 123,
        listPriceMinor: 100,
        quantity: 3,
        paymentOptionId: 'investment',
        occurredAtUtc: DateTime.utc(2026, 10, 29, 20),
      );
      await intake.prepare(c);
      await app.database.execute(
        "CREATE TRIGGER injected_investment_failure BEFORE INSERT ON investment_operations BEGIN SELECT RAISE(ABORT,'synthetic failure'); END",
      );
      await expectLater(
        intake.confirmPrepared(c.commandId),
        throwsA(isA<DatabaseException>()),
      );
      expect((await intake.load()).stock, isEmpty);
      expect(await InvestmentLedger.balance(app.database), 0);
      expect(await app.database.query('purchases'), isEmpty);
      await app.database.execute('DROP TRIGGER injected_investment_failure');
      await intake.confirmPrepared(c.commandId);
      expect((await intake.load()).stock.single.quantity, 3);
    },
  );

  for (final shortage in ['cash', 'owner']) {
    test(
      'SQL posting guard rejects $shortage shortage even if a caller skips the application check',
      () async {
        await cash(amount: shortage == 'cash' ? 10000 : 100000);
        await purchase();
        final first = await refund(
          'sql-first',
          shortage == 'cash' ? 5000 : 20000,
        );
        final second = await refund(
          'sql-second',
          shortage == 'cash' ? 9000 : 20000,
        );
        await operations.prepare(first);
        await operations.prepare(second);
        await operations.confirmPrepared(second.commandId);
        final before = await app.database.query('journal_lines');
        await expectLater(
          app.database.transaction((txn) async {
            final row = (await txn.query(
              'investment_refund_requests',
              where: 'command_id=?',
              whereArgs: [first.commandId],
            )).single;
            final source = (await txn.query(
              'cash_accounts',
              where: 'id=?',
              whereArgs: [first.sourceAccountId],
            )).single;
            await txn.update(
              'investment_refund_requests',
              {'status': 'executing'},
              where: 'command_id=?',
              whereArgs: [first.commandId],
            );
            await InvestmentLedger.post(
              txn,
              commandId: first.commandId,
              kind: 'refund',
              amount: first.amountMinor,
              counterLedger: source['ledger_account_id'] as String,
              sourceCashId: first.sourceAccountId,
              occurredAt: first.occurredAtUtc,
              reason: first.reason,
              canonical: row['canonical_payload'] as String,
              synthetic: true,
            );
          }),
          throwsA(isA<DatabaseException>()),
        );
        expect(await app.database.query('journal_lines'), before);
      },
    );
  }
  test(
    'multiple max-int funding and refund cycles stay exact when gross flows exceed int64',
    () async {
      final maximum = Money.maxMinorUnits.toInt();
      await cash(amount: maximum);
      await intake.recordOpeningBalance(
        CashOpeningCommand(
          commandId: 'max-nequi',
          paymentOptionId: 'quick-default:NEQUI',
          amountMinor: maximum,
          occurredAtUtc: DateTime.utc(2026, 10, 20),
        ),
      );
      await purchase(id: 'max-first', amount: maximum);
      final first = await refund('max-refund-first', maximum);
      await operations.prepare(first);
      await operations.confirmPrepared(first.commandId);
      final category = (await intake.load()).categories.first.id;
      await intake.prepare(
        StockIntakeCommand(
          commandId: 'max-second',
          productId: 'product-max-second',
          productName: 'Producto máximo',
          categoryId: category,
          supplierName: 'Proveedor',
          totalPurchasePriceMinor: maximum,
          listPriceMinor: 0,
          quantity: 1,
          paymentOptionId: 'investment',
          occurredAtUtc: DateTime.utc(2026, 10, 29, 21),
        ),
      );
      await intake.confirmPrepared('max-second');
      final second = await refund(
        'max-refund-second',
        maximum,
        option: 'quick-default:NEQUI',
      );
      await operations.prepare(second);
      await operations.confirmPrepared(second.commandId);
      final state = await SqliteTreasuryStore(app).load();
      expect(state.investmentMinor, 0);
      expect(state.cashMinor, 0);
      expect(state.nequiMinor, 0);
    },
  );

  test(
    'owner purchases and prepared refund survive closing and reopening the database',
    () async {
      final root = Directory(
        p.join(
          AppConfig.repositoryRootPath,
          'tmp',
          'investment-reopen-${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
      await root.create();
      final path = p.join(root.path, 'synthetic.sqlite3');
      var disk = await AppDatabase.open(path: path);
      await configure(disk);
      final store = SqliteStockIntakeStore(disk, synthetic: true);
      await store.ensureDefaults();
      await store.recordOpeningBalance(
        CashOpeningCommand(
          commandId: 'open-cash',
          paymentOptionId: 'quick-default:EFECTIVO',
          amountMinor: 10000,
          occurredAtUtc: DateTime.utc(2026, 10, 20),
        ),
      );
      final category = (await store.load()).categories.first.id;
      await store.prepare(
        StockIntakeCommand(
          commandId: 'persistent-investment',
          productId: 'persistent-product',
          productName: 'Producto persistente',
          categoryId: category,
          supplierName: 'Proveedor',
          totalPurchasePriceMinor: 5000,
          listPriceMinor: 1000,
          quantity: 10,
          paymentOptionId: 'investment',
          occurredAtUtc: DateTime.utc(2026, 10, 29, 20),
        ),
      );
      await disk.close();
      disk = await AppDatabase.open(path: path);
      final reopened = SqliteStockIntakeStore(disk, synthetic: true);
      await reopened.confirmPrepared('persistent-investment');
      final cashId =
          (await disk.database.query(
                'quick_payment_options',
                where: "id='quick-default:EFECTIVO'",
              )).single['cash_account_id']
              as String;
      final refunds = SqliteTreasuryOperationStore(disk, synthetic: true);
      await refunds.ensureDefaults();
      await refunds.prepare(
        TreasuryOperationCommand(
          commandId: 'persistent-refund',
          kind: TreasuryOperationKind.investmentRefund,
          sourceAccountId: cashId,
          amountMinor: 3000,
          reason: 'Devolución de inversión',
          occurredAtUtc: DateTime.utc(2026, 10, 29, 21),
        ),
      );
      await disk.close();
      disk = await AppDatabase.open(path: path);
      final restored = SqliteTreasuryOperationStore(disk, synthetic: true);
      expect(
        (await restored.load()).pendingOperations.single.command.commandId,
        'persistent-refund',
      );
      await restored.confirmPrepared('persistent-refund');
      await restored.confirmPrepared('persistent-refund');
      final state = await SqliteTreasuryStore(disk).load();
      expect(state.investmentMinor, 2000);
      expect(state.cashMinor, 7000);
      await disk.close();
    },
  );

  for (final reserve in [-35000, 0, 7000]) {
    test(
      'v18 migration preserves old facts and reclassifies reserve $reserve once with a verified backup',
      () async {
        final root = Directory(
          p.join(
            AppConfig.repositoryRootPath,
            'tmp',
            'investment-migration-${DateTime.now().microsecondsSinceEpoch}',
          ),
        );
        await root.create();
        final path = p.join(root.path, 'synthetic.sqlite3');
        var disk = await AppDatabase.open(path: path);
        await configure(disk);
        await SqliteTreasuryOpeningStore(disk, synthetic: true).importOpening(
          TreasuryOpeningCommand(
            commandId: 'opening',
            sourceSha256: 'a' * 64,
            snapshotSha256: 'b' * 64,
            occurredAtUtc: DateTime.utc(2026, 10, 20),
            cashMinor: 10000,
            nequiMinor: 5000,
            reserveMinor: reserve,
            receivablesMinor: 2000,
            sourceMetadata: const {'sourceName': 'synthetic.db'},
          ),
        );
        await disk.database.transaction(
          (txn) => restoreReleasedV18ForFixture(txn),
        );
        final oldTables = await disk.database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
        );
        final before = {
          for (final t in oldTables)
            t['name'] as String: await disk.database.query(t['name'] as String),
        };
        await disk.close();
        disk = await AppDatabase.open(path: path);
        final data = await SqliteTreasuryStore(disk).load();
        expect(data.reserveMinor, reserve < 0 ? 0 : reserve);
        expect(data.investmentMinor, reserve < 0 ? -reserve : 0);
        expect(data.cashMinor, 10000);
        expect(data.nequiMinor, 5000);
        expect(data.receivablesMinor, 2000);
        for (final table in before.keys) {
          final after = await disk.database.query(table);
          for (final prior in before[table]!) {
            expect(after, contains(equals(prior)), reason: table);
          }
        }
        expect(
          await disk.database.query('investment_operations'),
          hasLength(reserve < 0 ? 1 : 0),
        );
        final migratedLines = await disk.database.query('journal_lines');
        await disk.close();
        disk = await AppDatabase.open(path: path);
        await SqliteTreasuryStore(disk).ensureDefaults();
        expect(await disk.database.query('journal_lines'), migratedLines);
        expect(
          (await Directory(p.join(root.path, 'backups')).list().toList()),
          hasLength(1),
        );
        expect(
          await disk.database.rawQuery('PRAGMA foreign_key_check'),
          isEmpty,
        );
        await disk.close();
      },
    );
  }
}
