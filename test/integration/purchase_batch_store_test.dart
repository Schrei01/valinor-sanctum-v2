import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import '../support/released_v15_fixture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/investment_ledger.dart';
import 'package:valinor_sanctum_2/features/stock_intake/data/sqlite_stock_intake_store.dart';
import 'package:valinor_sanctum_2/features/stock_intake/domain/stock_intake_store.dart';
import 'package:valinor_sanctum_2/features/supplier_payments/data/sqlite_supplier_payments_store.dart';
import 'package:valinor_sanctum_2/features/reports/data/sqlite_reports_store.dart';
import 'package:valinor_sanctum_2/features/reports/domain/reports_store.dart';
import 'package:valinor_sanctum_2/features/workspace/data/sqlite_workspace_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase app;
  late SqliteStockIntakeStore store;
  late String category;
  final at = DateTime.utc(2026, 11, 6, 15);
  setUp(() async {
    app = await AppDatabase.open(path: inMemoryDatabasePath);
    await SqliteWorkspaceStore(app).createProfile(
      BusinessProfile(
        profileId: 'batch-test',
        businessName: 'Tienda sintética',
        currencyCode: 'COP',
        moneyScale: 2,
        timezone: 'America/Bogota',
        createdAtUtc: DateTime.utc(2026, 11, 1),
      ),
    );
    store = SqliteStockIntakeStore(app, synthetic: true);
    await store.ensureDefaults();
    category = (await store.load()).categories
        .singleWhere((c) => c.name == 'Comestible')
        .id;
    await store.recordOpeningBalance(
      CashOpeningCommand(
        commandId: 'cash-opening',
        paymentOptionId: 'quick-default:EFECTIVO',
        amountMinor: 1200,
        occurredAtUtc: DateTime.utc(2026, 11, 6, 14),
      ),
    );
    await store.recordOpeningBalance(
      CashOpeningCommand(
        commandId: 'nequi-opening',
        paymentOptionId: 'quick-default:NEQUI',
        amountMinor: 1200,
        occurredAtUtc: DateTime.utc(2026, 11, 6, 14),
      ),
    );
  });
  tearDown(() => app.close());
  PurchaseBatchCommand command({
    int paid = 1200,
    String option = 'quick-default:EFECTIVO',
    int secondCost = 60,
  }) => PurchaseBatchCommand(
    commandId: 'batch',
    categoryId: category,
    paymentOptionId: option,
    totalPaidMinor: paid,
    occurredAtUtc: at,
    items: [
      StockIntakeCommand(
        commandId: 'child-cola',
        productId: 'cola',
        productName: 'Cocacola sintética',
        categoryId: category,
        supplierName: 'PTO sintético',
        totalPurchasePriceMinor: 1134,
        listPriceMinor: 150,
        quantity: 12,
        paymentOptionId: option,
        occurredAtUtc: at,
      ),
      StockIntakeCommand(
        commandId: 'child-water',
        productId: 'water',
        productName: 'Agua sintética',
        categoryId: category,
        supplierName: 'PTO sintético',
        totalPurchasePriceMinor: secondCost,
        listPriceMinor: 100,
        quantity: 10,
        paymentOptionId: option,
        occurredAtUtc: at,
      ),
    ],
  );

  for (final option in [
    'quick-default:EFECTIVO',
    'quick-default:NEQUI',
    'investment',
  ]) {
    test(
      'batch preserves declared costs but posts exactly total paid for $option',
      () async {
        final input = command(option: option);
        await store.prepareBatch(input);
        await store.prepareBatch(input);
        expect(
          (await store.load()).pendingBatches.single.command.itemsTotalMinor,
          1194,
        );
        await store.confirmBatch('batch');
        await store.confirmBatch('batch');
        final snapshot = await store.load();
        expect(snapshot.pendingBatches, isEmpty);
        expect(snapshot.entries, isEmpty);
        expect(snapshot.batches, hasLength(1));
        expect(
          snapshot.batches.single.command.items.map((i) => i.totalCostMinor),
          [1134, 60],
        );
        expect(snapshot.batches.single.command.differenceMinor, 6);
        expect(
          (await app.database.rawQuery(
            'SELECT sum(amount_paid_minor) total FROM purchase_spending WHERE category_id=?',
            [category],
          )).single['total'],
          1200,
        );
        expect(
          (await app.database.rawQuery(
            "SELECT sum(cost_minor) total FROM purchase_item_costs WHERE product_id='cola'",
          )).single['total'],
          1134,
        );
        expect(await app.database.query('purchase_item_costs'), hasLength(2));
        expect(
          snapshot.stock.singleWhere((s) => s.productId == 'cola').quantity,
          12,
        );
        expect(
          snapshot.stock.singleWhere((s) => s.productId == 'water').quantity,
          10,
        );
        expect(
          snapshot.paymentOptions
              .singleWhere((o) => o.id == option)
              .balanceMinor,
          option == 'investment' ? 1200 : 0,
        );
        expect(
          (await SqliteSupplierPaymentsStore(
            app,
          ).load()).payables.every((p) => p.remainingMinor == 0),
          isTrue,
        );
        expect(await app.database.query('purchases'), hasLength(2));
        expect(
          await app.database.query(
            'product_price_history',
            where: "source='created'",
          ),
          hasLength(2),
        );
        final period = ReportPeriod(
          start: DateTime.utc(2026, 11, 6),
          end: DateTime.utc(2026, 11, 6, 23, 59),
        );
        final report = await SqliteReportsStore(app).load(period);
        expect(
          report.movements
              .where((m) => m.kind == ReportMovementKind.purchasePayment)
              .fold(0, (sum, m) => sum - m.amountMinor),
          option == 'investment' ? 0 : 1200,
        );
        expect(
          (await app.database.rawQuery('PRAGMA foreign_key_check')),
          isEmpty,
        );
      },
    );
  }
  test(
    'discounted total is independent of product costs and checked against actual funds',
    () async {
      final input = command(paid: 1100, secondCost: 1000);
      await store.prepareBatch(input);
      await store.confirmBatch('batch');
      final data = await store.load();
      expect(data.batches.single.command.itemsTotalMinor, 2134);
      expect(data.batches.single.command.differenceMinor, -1034);
      expect(
        data.paymentOptions
            .singleWhere((o) => o.id == 'quick-default:EFECTIVO')
            .balanceMinor,
        100,
      );
    },
  );
  test(
    'failure on later product rolls back earlier stock, catalog, prices and payments',
    () async {
      await store.prepareBatch(command());
      await app.database.execute(
        "CREATE TRIGGER fail_water BEFORE INSERT ON catalog_items WHEN NEW.id='water' BEGIN SELECT RAISE(ABORT,'synthetic failure');END",
      );
      await expectLater(store.confirmBatch('batch'), throwsA(anything));
      expect(await app.database.query('catalog_items'), isEmpty);
      expect(await app.database.query('purchases'), isEmpty);
      expect(await app.database.query('paid_purchase_entries'), isEmpty);
      expect(await app.database.query('product_price_history'), isEmpty);
      expect(
        (await store.load()).paymentOptions
            .singleWhere((o) => o.id == 'quick-default:EFECTIVO')
            .balanceMinor,
        1200,
      );
      await app.database.execute('DROP TRIGGER fail_water');
      await store.confirmBatch('batch');
      expect((await store.load()).batches, hasLength(1));
    },
  );
  test(
    'prepared and confirmed batch facts resist modification and identity reuse',
    () async {
      await store.prepareBatch(command(paid: 1201, option: 'investment'));
      await app.database.update(
        'counterparties',
        {'is_active': 0},
        where: 'id=?',
        whereArgs: ['not-present'],
      );
      // A prepared request is immutable even through direct SQL.
      await expectLater(
        app.database.update('purchase_batch_requests', {
          'total_paid_minor': 1,
        }, where: "command_id='batch'"),
        throwsA(anything),
      );
      await store.confirmBatch('batch');
      await expectLater(
        app.database.delete('purchase_batch_items'),
        throwsA(anything),
      );
      await expectLater(
        store.prepareBatch(command(paid: 1300, option: 'investment')),
        throwsA(isA<StockIntakeValidationException>()),
      );
      expect(await InvestmentLedger.balance(app.database), 1201);
    },
  );
  test('mixed categories and duplicate names fail before preparing', () async {
    final source = command();
    final other = (await store.load()).categories
        .singleWhere((c) => c.name == 'Artículo')
        .id;
    final bad = StockIntakeCommand(
      commandId: 'different',
      productId: 'another',
      productName: 'Artículo sintético',
      categoryId: other,
      supplierName: 'Otro',
      totalPurchasePriceMinor: 50,
      listPriceMinor: 100,
      quantity: 1,
      paymentOptionId: source.paymentOptionId,
      occurredAtUtc: at,
    );
    await expectLater(
      store.prepareBatch(
        PurchaseBatchCommand(
          commandId: 'bad',
          categoryId: category,
          paymentOptionId: source.paymentOptionId,
          totalPaidMinor: 1200,
          occurredAtUtc: at,
          items: [source.items.first, bad],
        ),
      ),
      throwsA(isA<StockIntakeValidationException>()),
    );
    expect(await app.database.query('purchase_batch_requests'), isEmpty);
  });
  test(
    'prepared whole purchase survives SQLite reopen and confirmation is idempotent after another reopen',
    () async {
      await store.prepareBatch(command());
      final folder = await Directory(
        p.join(AppConfig.repositoryRootPath, 'tmp'),
      ).createTemp('batch-reopen-');
      final path = p.join(folder.path, 'sanctum2.sqlite3');
      await app.database.execute('VACUUM INTO ?', [path]);
      AppDatabase? disk;
      try {
        disk = await AppDatabase.open(path: path);
        var intake = SqliteStockIntakeStore(disk, synthetic: true);
        final pending = (await intake.load()).pendingBatches.single.command;
        expect(pending.items.map((i) => i.totalCostMinor), [1134, 60]);
        expect(pending.totalPaidMinor, 1200);
        await intake.prepareBatch(pending);
        await intake.confirmBatch(pending.commandId);
        await disk.close();
        disk = null;
        disk = await AppDatabase.open(path: path);
        intake = SqliteStockIntakeStore(disk, synthetic: true);
        await intake.confirmBatch('batch');
        expect((await intake.load()).batches, hasLength(1));
        expect(await disk.database.query('purchases'), hasLength(2));
      } finally {
        await disk?.close();
        await folder.delete(recursive: true);
      }
    },
  );
  test(
    'v23 migration preserves every historical row and pending single-product purchase with verified backup',
    () async {
      final item = command().items.first;
      await store.prepare(
        item,
      ); // Preserves the released durable request format.
      final folder = await Directory(
        p.join(AppConfig.repositoryRootPath, 'tmp'),
      ).createTemp('batch-migration-');
      final path = p.join(folder.path, 'sanctum2.sqlite3');
      await app.database.execute('VACUUM INTO ?', [path]);
      AppDatabase? disk;
      try {
        final raw = await databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(singleInstance: false),
        );
        await raw.transaction(restoreReleasedV23ForFixture);
        final prior = <String, String>{
          for (final table in await raw.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name<>'schema_migrations' ORDER BY name",
          ))
            table['name'] as String: jsonEncode(
              (await raw.query(
                table['name'] as String,
              )).map(jsonEncode).toList()..sort(),
            ),
        };
        await raw.close();
        disk = await AppDatabase.open(path: path);
        expect(await disk.database.getVersion(), AppDatabase.schemaVersion);
        for (final entry in prior.entries) {
          expect(
            jsonEncode(
              (await disk.database.query(entry.key)).map(jsonEncode).toList()
                ..sort(),
            ),
            entry.value,
            reason: entry.key,
          );
        }
        final intake = SqliteStockIntakeStore(disk, synthetic: true);
        expect(
          (await intake.load()).pendingIntakes.single.command.commandId,
          item.commandId,
        );
        await intake.confirmPrepared(item.commandId);
        expect((await intake.load()).entries, hasLength(1));
        expect(await disk.database.rawQuery('PRAGMA integrity_check'), [
          {'integrity_check': 'ok'},
        ]);
        expect(
          await disk.database.rawQuery('PRAGMA foreign_key_check'),
          isEmpty,
        );
        final backups = await folder
            .list(recursive: true)
            .where(
              (file) =>
                  file is File &&
                  file.path != path &&
                  file.path.endsWith('.sqlite3'),
            )
            .toList();
        expect(backups, isNotEmpty);
      } finally {
        await disk?.close();
        await folder.delete(recursive: true);
      }
    },
  );
  test(
    'balance consumed after prepare rejects whole purchase and allows explicit correction',
    () async {
      await store.prepareBatch(command());
      final other = StockIntakeCommand(
        commandId: 'other',
        productId: 'other-product',
        productName: 'Otro producto',
        categoryId: category,
        supplierName: 'PTO sintético',
        totalPurchasePriceMinor: 1,
        listPriceMinor: 1,
        quantity: 1,
        paymentOptionId: 'quick-default:EFECTIVO',
        occurredAtUtc: at,
      );
      await store.prepare(other);
      await store.confirmPrepared(other.commandId);
      await expectLater(
        store.confirmBatch('batch'),
        throwsA(isA<StockIntakeValidationException>()),
      );
      final data = await store.load();
      expect(data.pendingBatches.single.status, 'rejected');
      expect(data.products.map((item) => item.id), ['other-product']);
      expect(
        await app.database.query(
          'paid_purchase_requests',
          where: "command_id IN('child-cola','child-water')",
        ),
        isEmpty,
      );
      await store.discardBatch('batch');
      expect((await store.load()).pendingBatches, isEmpty);
    },
  );
  test(
    'supplier typed with different accented case resolves existing identity without changing recorded costs',
    () async {
      await app.database.insert('counterparties', {
        'id': 'supplier-accent',
        'name': 'Proveedor Ágil',
        'is_supplier': 1,
        'is_customer': 0,
        'is_active': 1,
      });
      final original = command();
      final input = PurchaseBatchCommand(
        commandId: 'batch',
        categoryId: category,
        paymentOptionId: original.paymentOptionId,
        totalPaidMinor: 1200,
        occurredAtUtc: at,
        items: [
          for (final item in original.items)
            StockIntakeCommand(
              commandId: item.commandId,
              productId: item.productId,
              productName: item.productName,
              categoryId: category,
              supplierName: 'PROVEEDOR ÁGIL',
              totalPurchasePriceMinor: item.totalCostMinor,
              listPriceMinor: item.listPriceMinor,
              quantity: item.quantity,
              paymentOptionId: item.paymentOptionId,
              occurredAtUtc: at,
            ),
        ],
      );
      await store.prepareBatch(input);
      await expectLater(
        store.prepare(input.items.first),
        throwsA(isA<StockIntakeValidationException>()),
      );
      await store.confirmBatch('batch');
      expect(
        (await store.load()).batches.single.command.items.map(
          (item) => item.totalCostMinor,
        ),
        [1134, 60],
      );
      expect(
        (await app.database.query(
          'purchases',
        )).map((row) => row['supplier_id']).toSet(),
        {'supplier-accent'},
      );
    },
  );
}
