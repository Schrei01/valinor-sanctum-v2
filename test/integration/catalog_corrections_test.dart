import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_catalog_corrections_store.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/stock_adjustment_store.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_stock_adjustment_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/catalog_corrections_store.dart';
import 'package:valinor_sanctum_2/features/events/data/sqlite_events_store.dart';
import 'package:valinor_sanctum_2/features/events/domain/events_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/data/sqlite_quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_opening_store.dart';
import 'package:valinor_sanctum_2/features/treasury/domain/treasury_opening.dart';
import 'package:valinor_sanctum_2/features/treasury/domain/treasury_store.dart';
import 'package:valinor_sanctum_2/features/reports/data/sqlite_reports_store.dart';
import 'package:valinor_sanctum_2/features/reports/domain/reports_store.dart';
import 'quick_sales_store_test.dart' show fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase app;
  late SqliteCatalogCorrectionsStore edits;
  late SqliteInventoryStore inventory;
  final at = DateTime.utc(2026, 11, 9, 10);
  setUp(() async {
    app = await AppDatabase.open(path: inMemoryDatabasePath);
    await fixture(app, moneyScale: 0);
    inventory = SqliteInventoryStore(app, synthetic: true);
    edits = SqliteCatalogCorrectionsStore(app, synthetic: true);
    await inventory.saveCategory(
      const InventoryCategory(id: 'food', name: 'Comestible'),
    );
    await app.database.update('catalog_items', {
      'category_id': 'food',
    }, where: "id='product'");
    final quick = SqliteQuickSalesStore(app, synthetic: true);
    await quick.ensureDefaults();
  });
  tearDown(() async {
    await app.close();
  });
  test(
    'correction identities are reserved against other commands and pending stock requests',
    () async {
      CatalogCorrectionCommand command(String id) => CatalogCorrectionCommand(
        commandId: id,
        productId: 'product',
        kind: CatalogCorrectionKind.name,
        expectedName: 'Producto sintético',
        expectedPriceMinor: 10000,
        name: 'Corregido',
        occurredAtUtc: at,
      );
      await edits.prepareCorrection(command('reserved'));
      await expectLater(
        app.database.insert('command_log', {
          'id': 'reserved',
          'command_type': 'other',
          'payload_hash': 'x',
          'actor_id': (await app.database.query('actors')).first['id'],
          'response_json': '{}',
          'response_version': 1,
          'committed_at_utc': at.toIso8601String(),
          'authorization_policy_version': 'development-single-user-v1',
        }),
        throwsA(isA<DatabaseException>()),
      );
      await SqliteStockAdjustmentStore(app, synthetic: true).prepareAdjustment(
        StockAdjustmentCommand(
          commandId: 'stock-reserved',
          productId: 'product',
          quantity: 1,
          reason: 'Sintético',
          occurredAtUtc: at,
        ),
      );
      await expectLater(
        edits.prepareCorrection(command('stock-reserved')),
        throwsA(isA<DatabaseException>()),
      );
      expect(await app.database.query('catalog_corrections'), isEmpty);
      expect((await inventory.load()).stock.single.quantity, 10);
    },
  );
  test(
    'metadata changes preserve stock, receipts and price history with exact retries',
    () async {
      final old = jsonEncode(await app.database.query('purchase_lines'));
      final cmd = CatalogCorrectionCommand(
        commandId: 'rename',
        productId: 'product',
        kind: CatalogCorrectionKind.name,
        expectedName: 'Producto sintético',
        expectedPriceMinor: 10000,
        name: 'Nombre corregido',
        occurredAtUtc: at,
      );
      await edits.prepareCorrection(cmd);
      await edits.confirmCorrection('rename');
      await edits.confirmCorrection('rename');
      final price = CatalogCorrectionCommand(
        commandId: 'price',
        productId: 'product',
        kind: CatalogCorrectionKind.price,
        expectedName: 'Nombre corregido',
        expectedPriceMinor: 10000,
        priceMinor: 12000,
        occurredAtUtc: at,
      );
      await edits.prepareCorrection(price);
      await edits.confirmCorrection('price');
      await edits.confirmCorrection('price');
      final product = (await app.database.query(
        'catalog_items',
        where: "id='product'",
      )).single;
      expect(product['name'], 'Nombre corregido');
      expect(product['list_price_minor'], 12000);
      expect(jsonEncode(await app.database.query('purchase_lines')), old);
      expect((await inventory.load()).stock.single.quantity, 10);
      expect(await app.database.query('catalog_corrections'), hasLength(2));
      expect(
        (await app.database.query(
          'product_price_history',
          where: "product_id='product'",
          orderBy: 'id',
        )).last['previous_price_minor'],
        10000,
      );
    },
  );
  Future<String> event() async {
    final events = SqliteEventsStore(app, synthetic: true);
    final cmd = CreateEvent(
      commandId: 'event',
      name: 'Liga',
      minimumPeople: 2,
      fixedCostMinor: 100,
      pvpMinor: 5000,
      sourceAccountId: 'investment',
      occurredAtUtc: at,
      products: const [EventProductInput('product', 3)],
    );
    await events.prepare(cmd);
    return events.confirm('event');
  }

  Future<void> revise(
    String product,
    String id,
    int quantity,
    int fixed,
  ) async {
    final state = await edits.loadEvent(product);
    final cmd = CatalogCorrectionCommand(
      commandId: id,
      productId: product,
      kind: CatalogCorrectionKind.event,
      expectedName: state.name,
      expectedPriceMinor: state.pvpMinor,
      expectedRevision: state.revision,
      name: 'Liga corregida',
      priceMinor: 6000,
      minimumPeople: 2,
      fixedCostMinor: fixed,
      sourceAccountId: 'investment',
      products: quantity == 0
          ? const []
          : [EventProductInput('product', quantity)],
      occurredAtUtc: at.add(const Duration(hours: 1)),
    );
    await edits.prepareCorrection(cmd);
    await edits.confirmCorrection(id);
    await edits.confirmCorrection(id);
  }

  test(
    'event returns exact FIFO cost, refunds only goods and keeps initial facts',
    () async {
      final id = await event();
      final original = jsonEncode(await app.database.query('events'));
      final invested = (await SqliteTreasuryStore(app).load()).investmentMinor;
      await revise(id, 'return', 1, 50);
      expect((await inventory.load()).stock.single.quantity, 9);
      expect((await edits.loadEvent(id)).fixedCostMinor, 50);
      expect((await SqliteTreasuryStore(app).load()).investmentMinor, invested);
      expect(jsonEncode(await app.database.query('events')), original);
      await revise(id, 'remove', 0, 0);
      expect((await inventory.load()).stock.single.quantity, 10);
      expect((await inventory.load()).stock.single.totalCostMinor, 10001);
      expect((await SqliteTreasuryStore(app).load()).investmentMinor, invested);
      expect((await edits.loadEvent(id)).components, isEmpty);
      expect(await app.database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );
  test(
    'additional goods consume once and only fixed cost increases add investment',
    () async {
      final id = await event();
      final invested = (await SqliteTreasuryStore(app).load()).investmentMinor;
      await revise(id, 'add', 5, 150);
      expect((await inventory.load()).stock.single.quantity, 5);
      expect(
        (await SqliteTreasuryStore(app).load()).investmentMinor,
        invested + 50,
      );
      expect(
        await app.database.query('event_correction_payments'),
        hasLength(1),
      );
      expect(
        (await SqliteEventsStore(
          app,
          synthetic: true,
        ).load()).events.single.pvpMinor,
        6000,
      );
    },
  );
  test(
    'event sales keep their original name and PVP after corrections',
    () async {
      final id = await event();
      final quick = SqliteQuickSalesStore(app, synthetic: true);
      Future<void> sell(String command, int price, DateTime time) async {
        final saved = await quick.saveAccount(
          SaveQuickSaleAccount(
            id: command,
            label: 'Cuenta',
            expectedRevision: 0,
            lines: [
              QuickSaleLine(
                id: '$command:line',
                productId: id,
                quantityText: '1',
                unitPriceMinor: price,
                paymentOptionId: 'quick-default:EFECTIVO',
              ),
            ],
          ),
        );
        await quick.prepareSale(
          commandId: '$command:request',
          accountId: command,
          expectedRevision: saved.revision,
          occurredAtUtc: time,
        );
        await quick.confirmPrepared('$command:request');
      }

      await sell('before', 5000, at.add(const Duration(minutes: 30)));
      final old = jsonEncode(await app.database.query('sale_lines'));
      await revise(id, 'edit-after-sale', 2, 50);
      expect(jsonEncode(await app.database.query('sale_lines')), old);
      await sell('after', 6000, at.add(const Duration(hours: 2)));
      final lines = await app.database.query(
        'sale_lines',
        orderBy: 'unit_price_minor',
      );
      expect(lines.map((l) => l['name_snapshot']), ['Liga', 'Liga corregida']);
      expect(lines.map((l) => l['total_minor']), [5000, 6000]);
    },
  );
  for (final role in [TreasuryAccountRole.cash, TreasuryAccountRole.nequi]) {
    test(
      'fixed cost addition spends only $role; reduction retains actual report cost',
      () async {
        await SqliteTreasuryStore(app).ensureDefaults();
        await SqliteTreasuryOpeningStore(app, synthetic: true).importOpening(
          TreasuryOpeningCommand(
            commandId: 'funds',
            sourceSha256: 'a' * 64,
            snapshotSha256: 'b' * 64,
            occurredAtUtc: DateTime.utc(2026, 10, 20),
            cashMinor: 1000,
            nequiMinor: 1000,
            reserveMinor: 0,
            receivablesMinor: 0,
            sourceMetadata: const {'source': 'synthetic'},
          ),
        );
        final id = await event();
        var state = await edits.loadEvent(id);
        final treasury = await SqliteTreasuryStore(app).load();
        final source = treasury.accounts.singleWhere((a) => a.role == role).id;
        CatalogCorrectionCommand command(String key, int fixed) =>
            CatalogCorrectionCommand(
              commandId: key,
              productId: id,
              kind: CatalogCorrectionKind.event,
              expectedName: state.name,
              expectedPriceMinor: state.pvpMinor,
              expectedRevision: state.revision,
              name: state.name,
              priceMinor: state.pvpMinor,
              minimumPeople: 2,
              fixedCostMinor: fixed,
              sourceAccountId: source,
              products: const [EventProductInput('product', 3)],
              occurredAtUtc: at.add(const Duration(hours: 1)),
            );
        await edits.prepareCorrection(command('increase', 150));
        await edits.confirmCorrection('increase');
        state = await edits.loadEvent(id);
        await edits.prepareCorrection(command('reduce', 50));
        await edits.confirmCorrection('reduce');
        final after = await SqliteTreasuryStore(app).load();
        expect(
          after.accounts.singleWhere((a) => a.id == source).balanceMinor,
          950,
        );
        final report = await SqliteReportsStore(app).load(
          ReportPeriod(
            start: DateTime.utc(2026, 11, 9),
            end: DateTime.utc(2026, 11, 9, 23, 59),
          ),
        );
        expect(report.events.single.costMinor, 3151);
        expect(report.outflowTotals.knownTotalMinor, 50);
      },
    );
  }
  test('stale revision cannot consume or return inventory twice', () async {
    final id = await event();
    final state = await edits.loadEvent(id);
    final command = CatalogCorrectionCommand(
      commandId: 'stale',
      productId: id,
      kind: CatalogCorrectionKind.event,
      expectedName: state.name,
      expectedPriceMinor: state.pvpMinor,
      expectedRevision: state.revision,
      name: 'Viejo',
      priceMinor: 5000,
      minimumPeople: 2,
      fixedCostMinor: 100,
      sourceAccountId: 'investment',
      products: const [EventProductInput('product', 1)],
      occurredAtUtc: at.add(const Duration(hours: 2)),
    );
    await edits.prepareCorrection(command);
    await revise(id, 'first', 2, 100);
    final before = jsonEncode(
      await inventory.load().then(
        (s) => s.stock.map((s) => [s.quantity, s.totalCostMinor]).toList(),
      ),
    );
    await expectLater(
      edits.confirmCorrection('stale'),
      throwsA(isA<CatalogCorrectionValidationException>()),
    );
    expect(
      jsonEncode(
        await inventory.load().then(
          (s) => s.stock.map((s) => [s.quantity, s.totalCostMinor]).toList(),
        ),
      ),
      before,
    );
  });
  test(
    'posting failure rolls back goods, money, metadata and revision together',
    () async {
      final id = await event(),
          state = await edits.loadEvent(
            (await app.database.query('events')).single['product_id'] as String,
          );
      final command = CatalogCorrectionCommand(
        commandId: 'atomic',
        productId: id,
        kind: CatalogCorrectionKind.event,
        expectedName: state.name,
        expectedPriceMinor: state.pvpMinor,
        expectedRevision: state.revision,
        name: 'Corrección atómica',
        priceMinor: 6000,
        minimumPeople: 2,
        fixedCostMinor: 150,
        sourceAccountId: 'investment',
        products: const [EventProductInput('product', 1)],
        occurredAtUtc: at.add(const Duration(hours: 1)),
      );
      await edits.prepareCorrection(command);
      final oldStock = (await inventory.load()).stock.single;
      final oldInvestment = (await SqliteTreasuryStore(
        app,
      ).load()).investmentMinor;
      await app.database.execute(
        "CREATE TRIGGER fail_correction BEFORE UPDATE OF status ON journal_entries WHEN NEW.status='posted' AND EXISTS(SELECT 1 FROM event_correction_payments WHERE document_id=NEW.document_id) BEGIN SELECT RAISE(ABORT,'synthetic failure'); END",
      );
      await expectLater(edits.confirmCorrection('atomic'), throwsA(anything));
      expect((await inventory.load()).stock.single.quantity, oldStock.quantity);
      expect(
        (await inventory.load()).stock.single.totalCostMinor,
        oldStock.totalCostMinor,
      );
      expect(
        (await SqliteTreasuryStore(app).load()).investmentMinor,
        oldInvestment,
      );
      expect(await app.database.query('catalog_corrections'), isEmpty);
      expect(await app.database.query('event_return_values'), isEmpty);
      expect((await edits.loadEvent(id)).name, 'Liga');
      await app.database.execute('DROP TRIGGER fail_correction');
      await edits.confirmCorrection('atomic');
      await edits.confirmCorrection('atomic');
      expect((await inventory.load()).stock.single.quantity, 9);
      expect(
        (await SqliteTreasuryStore(app).load()).investmentMinor,
        oldInvestment + 50,
      );
    },
  );
  test(
    'prepared event correction recovers after database reopen without duplicate effects',
    () async {
      final id = await event();
      final state = await edits.loadEvent(id);
      final command = CatalogCorrectionCommand(
        commandId: 'durable',
        productId: id,
        kind: CatalogCorrectionKind.event,
        expectedName: state.name,
        expectedPriceMinor: state.pvpMinor,
        expectedRevision: state.revision,
        name: 'Liga',
        priceMinor: 5000,
        minimumPeople: 2,
        fixedCostMinor: 100,
        sourceAccountId: 'investment',
        products: const [EventProductInput('product', 1)],
        occurredAtUtc: at.add(const Duration(hours: 1)),
      );
      await edits.prepareCorrection(command);
      final root = p.join(AppConfig.repositoryRootPath, 'tmp'),
          folder = await Directory(
            p.join(AppConfig.repositoryRootPath, 'tmp'),
          ).createTemp('correction-reopen-');
      AppDatabase? copy;
      try {
        final path = p.join(folder.path, 'sanctum2.sqlite3');
        await app.database.execute('VACUUM INTO ?', [path]);
        copy = await AppDatabase.open(path: path);
        final reopened = SqliteCatalogCorrectionsStore(copy, synthetic: true);
        expect(
          (await reopened.pendingCorrections()).single.command.commandId,
          'durable',
        );
        await reopened.confirmCorrection('durable');
        await copy.close();
        copy = null;
        copy = await AppDatabase.open(path: path);
        await SqliteCatalogCorrectionsStore(
          copy,
          synthetic: true,
        ).confirmCorrection('durable');
        expect(
          (await SqliteInventoryStore(
            copy,
            synthetic: true,
          ).load()).stock.single.quantity,
          9,
        );
        expect(await copy.database.query('catalog_corrections'), hasLength(1));
      } finally {
        await copy?.close();
        if (!p.isWithin(root, await folder.resolveSymbolicLinks())) {
          throw StateError('Unsafe cleanup');
        }
        await folder.delete(recursive: true);
      }
    },
  );
}
