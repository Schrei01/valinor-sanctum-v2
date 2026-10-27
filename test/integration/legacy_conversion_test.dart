import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_inventory_opening_store.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_opening.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/reference_inventory.dart';
import 'package:valinor_sanctum_2/features/legacy_conversion/data/sqlite_legacy_conversion.dart';
import 'package:valinor_sanctum_2/features/reports/data/sqlite_reports_store.dart';
import 'package:valinor_sanctum_2/features/reports/domain/reports_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/data/sqlite_quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_opening_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_operation_store.dart';
import 'package:valinor_sanctum_2/features/treasury/domain/treasury_opening.dart';
import 'package:valinor_sanctum_2/features/treasury/domain/treasury_operation_store.dart';
import 'package:valinor_sanctum_2/features/workspace/data/sqlite_workspace_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory fixture;
  late String source, sourceHash;
  late AppDatabase app;
  setUp(() async {
    sqfliteFfiInit();
    final parent = Directory(
      p.join(AppConfig.repositoryRootPath, 'tmp', 'conversion-tests'),
    );
    await parent.create(recursive: true);
    fixture = await parent.createTemp('case-');
    source = p.join(fixture.path, 'legacy.sqlite3');
    final old = await databaseFactoryFfi.openDatabase(source);
    try {
      for (final t in ['cash', 'nequi', 'caja_mayor', 'deudas']) {
        await old.execute(
          'CREATE TABLE $t(id INTEGER PRIMARY KEY,total REAL NOT NULL,fecha TEXT)',
        );
      }
      await old.execute(
        'CREATE TABLE products(id INTEGER PRIMARY KEY,name TEXT,quantity INTEGER,price REAL,purchasePrice REAL,proveedor TEXT,categoria TEXT)',
      );
      await old.execute(
        'CREATE TABLE sales(id INTEGER PRIMARY KEY,productId INTEGER,quantity INTEGER,date TEXT,paymentMethod TEXT)',
      );
      await old.execute(
        'CREATE TABLE movimientos(id INTEGER PRIMARY KEY,tipo TEXT,cuenta TEXT,monto REAL,motivo TEXT,fecha TEXT)',
      );
      await old.execute(
        'CREATE TABLE transfermovements(id INTEGER PRIMARY KEY,tipo TEXT,cuenta_origen TEXT,cuenta_destino TEXT,monto REAL,motivo TEXT,fecha TEXT)',
      );
      await old.insert('products', {
        'id': 1,
        'name': 'Producto sintético',
        'quantity': 3,
        'price': 100.0,
        'purchasePrice': 40.0,
        'proveedor': 'Proveedor',
        'categoria': 'producto',
      });
      for (final i in [1, 2]) {
        await old.insert('sales', {
          'id': i,
          'productId': i == 1 ? 1 : 999,
          'quantity': i == 1 ? 3 : 1,
          'date': '2026-10-18T11:00:00.000',
          'paymentMethod': i == 1 ? 'Caja' : 'Transferencia',
        });
      }
      for (final row in [
        [100, 'egreso', 'Caja', 7, '2026-10-18T11:00:00'],
        [101, 'egreso', 'Nequi', 11, '2026-10-18T11:00:00'],
        [102, 'ingreso', 'Caja', 99, '2026-10-18T11:00:00'],
        [103, 'transferencia', 'Caja', 99, '2026-10-18T11:00:00'],
        [104, 'egreso', 'Caja mayor', 13, '2026-10-18T11:00:00'],
        [105, 'egreso', 'Deudas', 17, '2026-10-18T11:00:00'],
        [106, 'egreso', 'Caja', 5, '2026-10-18T10:59:59.999999'],
        [107, 'egreso', 'Nequi', 3, '2026-10-18T11:01:00'],
        [108, 'egreso', 'Caja', 'invalid', '2026-10-18T11:00:00'],
      ]) {
        await old.insert('movimientos', {
          'id': row[0],
          'tipo': row[1],
          'cuenta': row[2],
          'monto': row[3],
          'fecha': row[4],
          'motivo': 'Movimiento sintético',
        });
      }
      for (final r in [
        // Balance history remains independent of the archived transfer log.
        {'id': 1, 'total': 0.0, 'fecha': null},
        {'id': 2, 'total': 100.0, 'fecha': '2026-10-18T10:00:00.000000'},
        {'id': 3, 'total': 110.0, 'fecha': '2026-10-18T10:00:00.000000'},
        {'id': 4, 'total': 120.0, 'fecha': '2026-10-18T10:00:00.000001'},
      ]) {
        await old.insert('cash', r);
      }
      await old.insert('nequi', {'id': 1, 'total': 0.0, 'fecha': null});
      await old.insert('nequi', {
        'id': 2,
        'total': 200.0,
        'fecha': '2026-10-18T10:00:00.000000',
      });
      await old.insert('caja_mayor', {
        'id': 1,
        'total': -50.0,
        'fecha': '2026-10-18T09:00:00.000',
      });
      await old.insert('deudas', {
        'id': 1,
        'total': 30.0,
        'fecha': '2026-10-18T09:00:00.000',
      });
      for (final row in [
        [1, 'Caja', 'Nequi', 7, '2026-10-18T11:00:00'],
        [2, 'Nequi', 'Caja', 2, '2026-10-18T11:00:00'],
        [3, 'Caja Mayor', 'Deudas', 3, '2026-10-18T11:00:00'],
        [4, 'Caja', 'Nequi', 5, '2026-10-18T10:59:59.999999'],
        [5, 'Caja', 'Nequi', 11, '2026-10-18T11:01:00'],
        [6, 'Caja', 'Nequi', 'invalid', '2026-10-18T11:00:00'],
      ]) {
        await old.insert('transfermovements', {
          'id': row[0],
          'tipo': 'transferencia',
          'cuenta_origen': row[1],
          'cuenta_destino': row[2],
          'monto': row[3],
          'fecha': row[4],
          'motivo': 'Transferencia sintética',
        });
      }
    } finally {
      await old.close();
    }
    sourceHash = await legacyFileHash(source);
    app = await AppDatabase.open(path: inMemoryDatabasePath);
    await SqliteWorkspaceStore(app).createProfile(
      BusinessProfile(
        profileId: 'conversion',
        businessName: 'Tienda sintética',
        currencyCode: 'COP',
        moneyScale: 0,
        timezone: 'America/Bogota',
        createdAtUtc: DateTime.utc(2026, 10, 20),
      ),
    );
    await SqliteInventoryOpeningStore(app, synthetic: true).open(
      InventoryOpeningCommand(
        commandId: 'inventory',
        snapshotSha256: 'b' * 64,
        occurredAtUtc: DateTime.utc(2026, 10, 20, 14),
        zeroCostsConfirmed: true,
        reference: ReferenceInventory(
          sourceName: 'legacy.sqlite3',
          sourceSha256: sourceHash,
          capturedAtUtc: DateTime.utc(2026, 10, 20, 12),
          products: const [
            ReferenceInventoryProduct(
              id: '1',
              name: 'Producto sintético',
              quantity: 3,
              priceMinor: 10000,
              purchasePriceMinor: 4000,
              category: 'producto',
              supplier: 'Proveedor',
            ),
          ],
        ),
      ),
    );
    await SqliteTreasuryStore(app).ensureDefaults();
    await SqliteTreasuryOpeningStore(app, synthetic: true).importOpening(
      TreasuryOpeningCommand(
        commandId: 'money',
        sourceSha256: sourceHash,
        snapshotSha256: 'c' * 64,
        occurredAtUtc: DateTime.utc(2026, 10, 20, 15),
        cashMinor: 120,
        nequiMinor: 200,
        reserveMinor: -50,
        receivablesMinor: 30,
        sourceMetadata: const {'sourceName': 'legacy.sqlite3'},
      ),
    );
    final operations = SqliteTreasuryOperationStore(app, synthetic: true);
    final options = await app.database.query('quick_payment_options');
    String account(String id) =>
        options.singleWhere((r) => r['id'] == id)['cash_account_id'] as String;
    await operations.prepare(
      TreasuryOperationCommand(
        commandId: 'transfer',
        kind: TreasuryOperationKind.transfer,
        sourceAccountId: account('quick-default:EFECTIVO'),
        destinationAccountId: account('quick-default:NEQUI'),
        amountMinor: 20,
        reason: 'Transferencia',
        occurredAtUtc: DateTime.utc(2026, 10, 21, 15),
      ),
    );
    await operations.confirmPrepared('transfer');
  });
  tearDown(() async {
    await app.close();
    await fixture.delete(recursive: true);
  });

  Future<String> nativeRows() async {
    final tables = await app.database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'legacy_%' ORDER BY name",
    );
    return jsonEncode({
      for (final t in tables)
        t['name'] as String: await app.database.query(t['name'] as String),
    });
  }

  Future<ReportsSnapshot> day(int day) => SqliteReportsStore(app).load(
    ReportPeriod(
      start: DateTime.utc(2026, 10, day),
      end: DateTime.utc(2026, 10, day),
    ),
  );
  ReportAccount cash(ReportsSnapshot s) =>
      s.accounts.singleWhere((a) => a.role == ReportAccountRole.cash);
  ReportAccount nequi(ReportsSnapshot s) =>
      s.accounts.singleWhere((a) => a.role == ReportAccountRole.transfer);

  test(
    'complete archive preserves orphan sales, undated rows and all native facts; replay is idempotent',
    () async {
      final before = await nativeRows();
      final result = await importLegacyHistory(target: app, sourcePath: source);
      expect(result.orphanSales, 1);
      expect(result.undatedBalances, 2);
      expect(result.replayed, isFalse);
      expect(result.counts.keys, hasLength(8));
      expect(await nativeRows(), before);
      expect(await legacyFileHash(source), sourceHash);
      final replay = await importLegacyHistory(target: app, sourcePath: source);
      expect(replay.replayed, isTrue);
      expect(
        (await app.database.query('legacy_source_rows')).length,
        result.counts.values.fold<int>(0, (a, b) => a + b),
      );
      for (final table in [
        'legacy_source_rows',
        'legacy_balance_history',
        'legacy_conversions',
      ]) {
        await expectLater(
          app.database.delete(table),
          throwsA(isA<DatabaseException>()),
        );
      }
      await expectLater(
        app.database.update('legacy_balance_history', {'amount_minor': 0}),
        throwsA(isA<DatabaseException>()),
      );
      expect((await app.readHealth())['foreignKeyViolations'], 0);
    },
  );
  test(
    'historical cutoffs preserve duplicate-date ordering and fractional seconds; no money is doubled at the opening',
    () async {
      await importLegacyHistory(target: app, sourcePath: source);
      final old = await day(19);
      expect(cash(old).openingMinor, 120);
      expect(cash(old).closingMinor, 120);
      expect(nequi(old).openingMinor, 200);
      expect(nequi(old).closingMinor, 200);
      expect(old.usesHistoricalBalances, isTrue);
      final row = await app.database.rawQuery(
        "SELECT amount_minor FROM legacy_balance_history WHERE role='cash' AND occurred_at_utc < '2026-10-18T15:00:00.000001Z' ORDER BY occurred_at_utc DESC,source_id DESC LIMIT 1",
      );
      expect(row.single['amount_minor'], 110);
      final live = await day(21);
      expect(cash(live).openingMinor, 120);
      expect(cash(live).closingMinor, 100);
      expect(nequi(live).openingMinor, 200);
      expect(nequi(live).closingMinor, 220);
      expect(live.usesHistoricalBalances, isFalse);
      final prior = await day(17);
      expect(cash(prior).openingMinor, isNull);
      expect(nequi(prior).closingMinor, isNull);
      final overlap = await day(20);
      expect(cash(overlap).openingMinor, 120);
      expect(cash(overlap).closingMinor, 120);
      expect(overlap.sales, isEmpty);
    },
  );
  test(
    'converted database can continue selling without replaying old inventory or history',
    () async {
      await importLegacyHistory(target: app, sourcePath: source);
      await File(
        source,
      ).rename(p.join(fixture.path, 'source-kept-aside.sqlite3'));
      final product =
          (await app.database.query(
                'inventory_opening_items',
              )).single['product_id']
              as String;
      final quick = SqliteQuickSalesStore(app, synthetic: true);
      await quick.saveAccount(
        SaveQuickSaleAccount(
          id: 'counter',
          label: 'Venta sintética',
          expectedRevision: 0,
          lines: [
            QuickSaleLine(
              id: 'line',
              productId: product,
              quantityText: '1',
              unitPriceMinor: 100,
              paymentOptionId: 'quick-default:EFECTIVO',
            ),
          ],
        ),
      );
      await quick.prepareSale(
        commandId: 'new-sale',
        accountId: 'counter',
        expectedRevision: 1,
        occurredAtUtc: DateTime.utc(2026, 10, 22, 15),
      );
      await quick.confirmPrepared('new-sale');
      expect((await SqliteInventoryStore(app).load()).stock.single.quantity, 2);
      expect((await SqliteTreasuryStore(app).load()).cashMinor, 200);
      expect(cash(await day(19)).closingMinor, 120);
      expect((await app.database.query('sales')).length, 1);
      final combined = await SqliteReportsStore(app).load(
        ReportPeriod(
          start: DateTime.utc(2026, 10, 18),
          end: DateTime.utc(2026, 10, 22),
        ),
      );
      expect(combined.saleTotals.cashTotalMinor, 400);
      expect(combined.saleTotals.transferTotalMinor, isNull);
      expect(combined.saleTotals.knownTotalMinor, 400);
      expect(combined.saleTotals.cashMinor, 100);
      expect(combined.saleTotals.estimatedCashMinor, 300);
      expect(combined.saleTotals.estimatedSales, 1);
      expect(combined.saleTotals.totalMinor, isNull);
      expect(combined.saleTotals.unpricedSales, 1);
    },
  );
  test(
    'archived sales use immutable copied PVP in range, orphan amounts remain unknown',
    () async {
      await importLegacyHistory(target: app, sourcePath: source);
      final old = await day(18);
      expect(old.saleTotals.cashTotalMinor, 300);
      expect(old.saleTotals.transferTotalMinor, isNull);
      expect(old.saleTotals.creditTotalMinor, 0);
      expect(old.saleTotals.totalMinor, isNull);
      expect(old.saleTotals.unpricedCashSales, 0);
      expect(old.saleTotals.unpricedTransferSales, 1);
      expect(old.saleTotals.unpricedSales, 1);
      expect(old.saleTotals.knownTotalMinor, 300);
      expect(old.saleTotals.estimatedCashMinor, 300);
      expect(old.saleTotals.estimatedSales, 1);
      final inventory = SqliteInventoryStore(app, synthetic: true);
      final product = (await inventory.load()).products.single;
      await inventory.saveProduct(
        CatalogProduct(
          id: product.id,
          name: 'PVP actual diferente',
          listPriceMinor: 999,
        ),
      );
      final beforeReads = await nativeRows();
      expect((await day(18)).saleTotals.estimatedCashMinor, 300);
      final noSales = await day(19);
      expect(noSales.saleTotals.totalMinor, 0);
      expect(noSales.saleTotals.unpricedSales, 0);
      final afterTransfer = await day(21);
      expect(afterTransfer.saleTotals.cashTotalMinor, 0);
      expect(afterTransfer.saleTotals.transferTotalMinor, 0);
      final beforeMinute = await SqliteReportsStore(app).load(
        ReportPeriod.timed(
          start: DateTime.utc(2026, 10, 18, 10, 59),
          end: DateTime.utc(2026, 10, 18, 10, 59),
        ),
      );
      expect(beforeMinute.saleTotals.totalMinor, 0);
      final minute = await SqliteReportsStore(app).load(
        ReportPeriod.timed(
          start: DateTime.utc(2026, 10, 18, 11),
          end: DateTime.utc(2026, 10, 18, 11),
        ),
      );
      expect(minute.saleTotals.unpricedSales, 1);
      expect(minute.saleTotals.estimatedCashMinor, 300);
      expect(await nativeRows(), beforeReads);
    },
  );
  test(
    'historical outflows use Caja and Nequi within the exact minute; missing amount stays partial',
    () async {
      await importLegacyHistory(target: app, sourcePath: source);
      final before = await nativeRows();
      final data = await day(18);
      expect(data.outflowTotals.cashMinor, 12);
      expect(data.outflowTotals.transferMinor, 14);
      expect(data.outflowTotals.knownTotalMinor, 26);
      expect(data.outflowTotals.totalMinor, isNull);
      expect(data.outflowTotals.unpricedCashRecords, 1);
      final minute = await SqliteReportsStore(app).load(
        ReportPeriod.timed(
          start: DateTime.utc(2026, 10, 18, 11),
          end: DateTime.utc(2026, 10, 18, 11),
        ),
      );
      expect(minute.outflowTotals.cashMinor, 7);
      expect(minute.outflowTotals.transferMinor, 11);
      expect((await day(21)).outflowTotals.totalMinor, 0);
      expect(await nativeRows(), before);
    },
  );
  test(
    'archived transfers respect minute edges, route direction and missing amounts without replaying balances',
    () async {
      await importLegacyHistory(target: app, sourcePath: source);
      final before = await nativeRows();
      final old = await day(18);
      expect(old.transfers.length, 5);
      expect(old.transfers.every((t) => t.isHistorical), isTrue);
      expect(old.knownTransferTotalMinor, 28);
      expect(old.transferTotalMinor, isNull);
      expect(old.unpricedTransferRecords, 1);
      final cashToNequi = old.transferRoutes.singleWhere(
        (r) => r.sourceName == 'Caja' && r.destinationName == 'Nequi',
      );
      expect(cashToNequi.count, 3);
      expect(cashToNequi.amountMinor, 23);
      expect(
        old.transferRoutes.any(
          (r) => r.sourceName == 'Caja mayor' && r.destinationName == 'Deudas',
        ),
        isTrue,
      );
      final minute = await SqliteReportsStore(app).load(
        ReportPeriod.timed(
          start: DateTime.utc(2026, 10, 18, 11),
          end: DateTime.utc(2026, 10, 18, 11),
        ),
      );
      expect(minute.transfers.length, 3);
      expect(minute.knownTransferTotalMinor, 12);
      expect(minute.unpricedTransferRecords, 1);
      final mixed = await SqliteReportsStore(app).load(
        ReportPeriod(
          start: DateTime.utc(2026, 10, 18),
          end: DateTime.utc(2026, 10, 21),
        ),
      );
      expect(mixed.transfers.length, 6);
      expect(mixed.knownTransferTotalMinor, 48);
      expect(mixed.transfers.where((t) => !t.isHistorical).length, 1);
      expect(await nativeRows(), before);
    },
  );
  test(
    'changed source is rejected atomically rather than replacing or duplicating existing origins',
    () async {
      final before = await nativeRows();
      final changed = await databaseFactoryFfi.openDatabase(
        source,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await changed.insert('movimientos', {
        'id': 1,
        'tipo': 'ingreso',
        'cuenta': 'caja',
        'monto': 1,
        'motivo': 'Cambio sintético',
        'fecha': '2026-10-18T12:00:00',
      });
      await changed.close();
      await expectLater(
        importLegacyHistory(target: app, sourcePath: source),
        throwsA(isA<FormatException>()),
      );
      expect(await app.database.query('legacy_conversions'), isEmpty);
      expect(await nativeRows(), before);
    },
  );
  test(
    'an archive insertion failure rolls back header, rows and balances together',
    () async {
      final before = await nativeRows();
      await app.database.execute(
        "CREATE TRIGGER synthetic_archive_failure BEFORE INSERT ON legacy_source_rows WHEN NEW.source_table='cash' AND NEW.source_id=3 BEGIN SELECT RAISE(ABORT, 'Synthetic failure'); END",
      );
      await expectLater(
        importLegacyHistory(target: app, sourcePath: source),
        throwsA(isA<DatabaseException>()),
      );
      for (final table in [
        'legacy_conversions',
        'legacy_source_rows',
        'legacy_balance_history',
      ]) {
        expect(await app.database.query(table), isEmpty);
      }
      expect(await nativeRows(), before);
      await app.database.execute('DROP TRIGGER synthetic_archive_failure');
      expect((await app.readHealth())['integrityOk'], isTrue);
    },
  );
  test(
    'invalid historical date aborts before any archive is committed',
    () async {
      final changed = await databaseFactoryFfi.openDatabase(
        source,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await changed.update('cash', {
        'fecha': '2026-02-30T12:00:00',
      }, where: 'id=4');
      await changed.close();
      await expectLater(
        importLegacyHistory(target: app, sourcePath: source),
        throwsA(isA<FormatException>()),
      );
      expect(await app.database.query('legacy_balance_history'), isEmpty);
      expect(await app.database.query('legacy_conversions'), isEmpty);
    },
  );
}
