import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../support/released_v15_fixture.dart';
import '../support/register_debtor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/features/events/data/sqlite_events_store.dart';
import 'package:valinor_sanctum_2/features/events/domain/events_store.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/data/sqlite_quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_opening_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_store.dart';
import 'package:valinor_sanctum_2/features/treasury/domain/treasury_opening.dart';
import 'package:valinor_sanctum_2/features/workspace/data/sqlite_workspace_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_operation_store.dart';
import 'package:valinor_sanctum_2/features/treasury/domain/treasury_operation_store.dart';
import 'package:valinor_sanctum_2/features/reports/data/sqlite_reports_store.dart';
import 'package:valinor_sanctum_2/features/reports/domain/reports_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase app;
  late SqliteEventsStore events;
  late SqliteInventoryStore inventory;
  late SqliteQuickSalesStore quick;
  final at = DateTime.utc(2026, 10, 21, 16);
  setUp(() async {
    app = await AppDatabase.open(path: inMemoryDatabasePath);
    await SqliteWorkspaceStore(app).createProfile(
      BusinessProfile(
        profileId: 'event-test',
        businessName: 'Tienda sintética',
        currencyCode: 'COP',
        moneyScale: 2,
        timezone: 'America/Bogota',
        createdAtUtc: at,
      ),
    );
    events = SqliteEventsStore(app, synthetic: true);
    inventory = SqliteInventoryStore(app, synthetic: true);
    quick = SqliteQuickSalesStore(app, synthetic: true);
    await SqliteTreasuryStore(app).ensureDefaults();
    await SqliteTreasuryOpeningStore(app, synthetic: true).importOpening(
      TreasuryOpeningCommand(
        commandId: 'money',
        sourceSha256: List.filled(64, 'a').join(),
        snapshotSha256: List.filled(64, 'b').join(),
        occurredAtUtc: at.subtract(const Duration(hours: 4)),
        cashMinor: 100000,
        nequiMinor: 50000,
        reserveMinor: -2000,
        receivablesMinor: 0,
        sourceMetadata: const {'sourceName': 'synthetic'},
      ),
    );
    await inventory.saveSupplier(
      const InventorySupplier(id: 'supplier', name: 'Proveedor sintético'),
    );
    for (final id in ['p1', 'p2']) {
      await inventory.saveProduct(
        CatalogProduct(id: id, name: 'Producto $id', listPriceMinor: 3000),
      );
    }
    await inventory.receivePurchase(
      ReceiptCommand(
        commandId: 'stock',
        supplierId: 'supplier',
        occurredAtUtc: at.subtract(const Duration(hours: 3)),
        dueDate: '2026-10-21',
        lines: const [
          ReceiptLineInput(
            productId: 'p1',
            quantity: 10,
            totalCostMinor: 10001,
          ),
          ReceiptLineInput(productId: 'p2', quantity: 5, totalCostMinor: 2500),
        ],
      ),
    );
  });
  tearDown(() => app.close());
  Future<String> cash(String option) async =>
      (await app.database.query(
            'quick_payment_options',
            where: 'id=?',
            whereArgs: [option],
          )).single['cash_account_id']
          as String;
  CreateEvent command({
    String id = 'event',
    int minimum = 0,
    int fixed = 0,
    int pvp = 10000,
    String? account,
    List<EventProductInput> products = const [],
  }) => CreateEvent(
    commandId: id,
    name: 'Liga sintética',
    minimumPeople: minimum,
    fixedCostMinor: fixed,
    pvpMinor: pvp,
    sourceAccountId: account,
    products: products,
    occurredAtUtc: at,
  );
  Future<String> create(CreateEvent c) async {
    await events.prepare(c);
    return events.confirm(c.commandId);
  }

  Future<Map<String, String>> snapshot() async {
    final tables = await app.database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    return {
      for (final t in tables)
        t['name'] as String: jsonEncode(
          await app.database.query(t['name'] as String),
        ),
    };
  }

  Future<void> sell(
    String event, {
    bool debt = false,
    bool mixed = false,
  }) async {
    await quick.saveAccount(
      SaveQuickSaleAccount(
        id: 'account',
        label: 'Cuenta sintética',
        customerName: debt ? 'Cliente sintético' : '',
        debtorId: debt ? await registerDebtor(app, 'Cliente sintético') : null,
        expectedRevision: 0,
        lines: [
          QuickSaleLine(
            id: 'l1',
            productId: event,
            quantityText: '3',
            unitPriceMinor: 10000,
            paymentOptionId: debt
                ? QuickPaymentOption.creditId
                : 'quick-default:EFECTIVO',
          ),
          if (mixed)
            const QuickSaleLine(
              id: 'l2',
              productId: 'p1',
              quantityText: '1',
              unitPriceMinor: 3000,
              paymentOptionId: 'quick-default:NEQUI',
            ),
        ],
      ),
    );
    await quick.prepareSale(
      commandId: 'sell',
      accountId: 'account',
      expectedRevision: 1,
      occurredAtUtc: at.add(const Duration(hours: 1)),
    );
    await quick.confirmPrepared('sell');
  }

  test(
    'owner-funded fixed cost increases only investment; prizes keep FIFO and retries never duplicate the debt',
    () async {
      final c = command(
        minimum: 3,
        fixed: 1000,
        account: 'investment',
        products: const [
          EventProductInput('p1', 2),
          EventProductInput('p2', 1),
        ],
      );
      final quote = await events.quote(c);
      expect(quote.totalCostMinor, 3501);
      expect(quote.unitCostMinor, 1167);
      await events.prepare(c);
      final id = await events.confirm(c.commandId);
      final after = await snapshot();
      expect(await events.confirm(c.commandId), id);
      expect(await snapshot(), after);
      final money = await SqliteTreasuryStore(app).load();
      expect(money.investmentMinor, 1000);
      expect(money.cashMinor, 100000);
      expect(money.nequiMinor, 50000);
      expect(
        money.movements
            .singleWhere((m) => m.id.startsWith('investment:event:'))
            .amountMinor,
        1000,
      );
      final row = (await app.database.query('events')).single;
      expect(row['funding_mode'], 'investment');
      expect(row['source_account_id'], isNull);
      expect(row['source_account_name_snapshot'], 'Inversión');
      expect(
        (await inventory.load()).stock
            .singleWhere((s) => s.productId == 'p1')
            .quantity,
        8,
      );
      final report = await SqliteReportsStore(
        app,
      ).load(ReportPeriod(start: at, end: at));
      expect(report.outflowTotals.totalMinor, 0);
      expect(report.eventCostsMinor, 3501);
      final refund = SqliteTreasuryOperationStore(app, synthetic: true);
      await refund.ensureDefaults();
      await refund.prepare(
        TreasuryOperationCommand(
          commandId: 'event-refund',
          kind: TreasuryOperationKind.investmentRefund,
          sourceAccountId: await cash('quick-default:EFECTIVO'),
          amountMinor: 1000,
          reason: 'Devolución de inversión',
          occurredAtUtc: at.add(const Duration(hours: 1)),
        ),
      );
      await refund.confirmPrepared('event-refund');
      final paid = await SqliteTreasuryStore(app).load();
      expect(paid.investmentMinor, 0);
      expect(paid.cashMinor, 99000);
      final finalReport = await SqliteReportsStore(
        app,
      ).load(ReportPeriod(start: at, end: at));
      expect(finalReport.investmentRefundsMinor, 1000);
      expect(finalReport.outflowTotals.totalMinor, 0);
      expect(finalReport.eventCostsMinor, 3501);
      await sell(id);
      final sold = await SqliteTreasuryStore(app).load();
      expect(sold.investmentMinor, 0);
      expect(sold.cashMinor, 129000);
      expect(await app.database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );
  test(
    'owner-funded event may exceed cash balances and deactivation does not repay it',
    () async {
      final id = await create(
        command(minimum: 10, fixed: 500000, account: 'investment'),
      );
      await events.deactivate(id);
      final money = await SqliteTreasuryStore(app).load();
      expect(money.investmentMinor, 500000);
      expect(money.cashMinor, 100000);
      expect(money.nequiMinor, 50000);
    },
  );
  test(
    'owner-funded events reject overflow and backdating without side effects',
    () async {
      await create(
        command(
          id: 'maximum',
          minimum: 1,
          fixed: 9223372036854775807,
          account: 'investment',
        ),
      );
      final before = await snapshot();
      await expectLater(
        events.prepare(
          command(id: 'overflow', minimum: 1, fixed: 1, account: 'investment'),
        ),
        throwsA(isA<EventsValidationException>()),
      );
      expect(await snapshot(), before);
      await expectLater(
        events.prepare(
          CreateEvent(
            commandId: 'backdated',
            name: 'Evento anterior',
            minimumPeople: 1,
            fixedCostMinor: 1,
            pvpMinor: 10000,
            sourceAccountId: 'investment',
            products: const [],
            occurredAtUtc: at.subtract(const Duration(hours: 1)),
          ),
        ),
        throwsA(isA<EventsValidationException>()),
      );
      expect(await snapshot(), before);
    },
  );
  test(
    'selecting investment with zero fixed cost creates no owner debt',
    () async {
      await create(command(account: 'investment'));
      expect((await SqliteTreasuryStore(app).load()).investmentMinor, 0);
      expect(
        (await app.database.query('events')).single['funding_mode'],
        'cash',
      );
    },
  );

  test(
    'v19 migration preserves sold cash events, allocations and pending requests with verified backup',
    () async {
      final oldEvent = await create(
        command(
          id: 'old-event',
          minimum: 3,
          fixed: 1000,
          account: await cash('quick-default:EFECTIVO'),
          products: const [EventProductInput('p1', 2)],
        ),
      );
      await sell(oldEvent);
      await events.deactivate(oldEvent);
      await events.prepare(command(id: 'old-pending'));
      await app.database.transaction(restoreReleasedV19ForFixture);
      final oldRows = {
        for (final t in await app.database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
        ))
          t['name'] as String: await app.database.query(t['name'] as String),
      };
      final root = Directory(
        p.join(Directory.current.path, 'tmp', 'event-migration-tests'),
      );
      await root.create(recursive: true);
      final directory = await root.createTemp('v19_');
      final path = p.join(directory.path, 'events.sqlite3');
      await app.database.execute("VACUUM INTO '${path.replaceAll("'", "''")}'");
      await app.close();
      app = await AppDatabase.open(path: path);
      for (final table in oldRows.keys) {
        if (table == 'schema_migrations') continue;
        final columns = oldRows[table]!.isEmpty
            ? null
            : oldRows[table]!.first.keys.toList();
        expect(
          await app.database.query(table, columns: columns),
          oldRows[table],
          reason: table,
        );
      }
      expect(
        (await app.database.query('events')).single['funding_mode'],
        'cash',
      );
      final backupFiles = await Directory(
        p.join(directory.path, 'backups'),
      ).list().toList();
      final backup = backupFiles.whereType<File>().singleWhere(
        (f) => p.basename(f.path).startsWith('events.v19.'),
      );
      final db = await databaseFactoryFfi.openDatabase(
        backup.path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      expect(await db.getVersion(), 19);
      for (final table in oldRows.keys) {
        expect(await db.query(table), oldRows[table], reason: 'backup $table');
      }
      await db.close();
      events = SqliteEventsStore(app, synthetic: true);
      await events.confirm('old-pending');
      await create(
        command(
          id: 'new-investment',
          minimum: 2,
          fixed: 2000,
          account: 'investment',
        ),
      );
      expect((await SqliteTreasuryStore(app).load()).investmentMinor, 2000);
      expect((await app.readHealth())['integrityOk'], isTrue);
      expect(await app.database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      // Kept under ignored tmp for inspection; no operational database is used.
    },
  );

  test(
    'costless event stores PU zero, manual PVP and category with no stock',
    () async {
      final id = await create(command());
      final e = (await events.load()).events.single;
      expect(e.productId, id);
      expect(e.minimumPeople, 0);
      expect(e.unitCostMinor, 0);
      expect(e.pvpMinor, 10000);
      final p = (await inventory.load()).products.singleWhere(
        (p) => p.id == id,
      );
      expect(p.isEvent, isTrue);
      expect(
        (await app.database.query(
          'categories',
          where: 'id=?',
          whereArgs: [p.categoryId],
        )).single['name'],
        'Evento',
      );
      expect(await app.database.query('event_products'), isEmpty);
      expect(
        await app.database.query(
          'journal_lines',
          where:
              'entry_id=(SELECT id FROM journal_entries WHERE document_id=(SELECT document_id FROM events))',
        ),
        isEmpty,
      );
      expect((await app.readHealth())['integrityOk'], isTrue);
    },
  );
  test(
    'multiple prizes and fixed cost consume FIFO and money once, half-up PU',
    () async {
      final c = command(
        minimum: 3,
        fixed: 1000,
        account: await cash('quick-default:EFECTIVO'),
        products: const [
          EventProductInput('p1', 2),
          EventProductInput('p2', 1),
        ],
      );
      final before = await snapshot();
      final quote = await events.quote(c);
      expect(await snapshot(), before);
      expect(quote.productsCostMinor, 2501);
      expect(quote.totalCostMinor, 3501);
      expect(quote.unitCostMinor, 1167);
      await events.prepare(c);
      expect(
        (await inventory.load()).stock
            .singleWhere((s) => s.productId == 'p1')
            .quantity,
        10,
      );
      final id = await events.confirm(c.commandId);
      final after = await snapshot();
      expect(await events.confirm(c.commandId), id);
      expect(await snapshot(), after);
      expect(
        (await inventory.load()).stock
            .singleWhere((s) => s.productId == 'p1')
            .quantity,
        8,
      );
      expect(
        (await quick.load()).stock
            .singleWhere((s) => s.productId == 'p1')
            .totalCostMinor,
        8000,
      );
      final accounts = (await events.load()).accounts;
      expect(
        accounts.singleWhere((a) => a.label == 'Caja').balanceMinor,
        99000,
      );
      expect((await app.database.query('event_cost_allocations')).length, 2);
    },
  );
  for (final input in [
    const EventProductInput('p1', 1),
    const EventProductInput('p2', 99),
  ]) {
    test('invalid minimum or stock is atomic: ${input.productId}', () async {
      final before = await snapshot();
      await expectLater(
        events.prepare(
          command(minimum: input.quantity == 99 ? 1 : 0, products: [input]),
        ),
        throwsA(isA<EventsValidationException>()),
      );
      expect(await snapshot(), before);
    });
  }
  test(
    'fixed cost requires minimum, account, sufficient funds and positive PVP',
    () async {
      for (final c in [
        command(fixed: 1, account: await cash('quick-default:EFECTIVO')),
        command(fixed: 1, minimum: 1),
        command(
          fixed: 50001,
          minimum: 1,
          account: await cash('quick-default:NEQUI'),
        ),
        command(pvp: 0),
      ]) {
        final before = await snapshot();
        await expectLater(
          events.prepare(c),
          throwsA(isA<EventsValidationException>()),
        );
        expect(await snapshot(), before);
      }
    },
  );
  for (final debt in [false, true]) {
    test(
      'event inscriptions ${debt ? 'with debt' : 'paid'} use sale lines and never repeat costs',
      () async {
        final id = await create(
          command(minimum: 2, products: const [EventProductInput('p1', 2)]),
        );
        final costFacts = await app.database.query('event_cost_allocations');
        await sell(id, debt: debt, mixed: true);
        final lines = await app.database.query('sale_lines');
        expect(lines.length, 2);
        final eventLine = lines.singleWhere((l) => l['product_id'] == id);
        expect(eventLine['quantity'], 3);
        expect(eventLine['unit_price_minor'], 10000);
        expect(eventLine['total_cost_minor'], 0);
        expect((await app.database.query('sale_outflows')).length, 1);
        expect(await app.database.query('event_cost_allocations'), costFacts);
        expect(
          (await inventory.load()).stock
              .singleWhere((s) => s.productId == 'p1')
              .quantity,
          7,
        );
        expect(
          (await app.database.query('sales')).single['total_cost_minor'],
          1000,
        );
        final treasury = await SqliteTreasuryStore(app).load();
        expect(treasury.receivablesMinor, debt ? 30000 : 0);
      },
    );
  }
  test(
    'deactivate conserves facts and prevents sales of saved event draft',
    () async {
      final id = await create(command());
      final before = await snapshot();
      await events.deactivate(id);
      final after = await snapshot();
      for (final table in before.keys.where((t) => t != 'catalog_items')) {
        expect(after[table], before[table]);
      }
      expect((await events.load()).events.single.isActive, isFalse);
      expect((await quick.load()).products.any((p) => p.id == id), isFalse);
      await expectLater(sell(id), throwsA(anything));
    },
  );
  test(
    'prepared creation survives new adapter and can be discarded without effects',
    () async {
      await events.prepare(command());
      expect(
        (await SqliteEventsStore(app).load()).pending.single.command.commandId,
        'event',
      );
      await events.discard('event');
      expect((await events.load()).pending, isEmpty);
      expect(await app.database.query('events'), isEmpty);
      await expectLater(
        events.confirm('event'),
        throwsA(isA<EventsValidationException>()),
      );
    },
  );
  test(
    'global command reservation rejects using event request id elsewhere',
    () async {
      await events.prepare(command());
      await expectLater(
        inventory.receivePurchase(
          ReceiptCommand(
            commandId: 'event',
            supplierId: 'supplier',
            occurredAtUtc: at,
            dueDate: '2026-10-21',
            lines: const [
              ReceiptLineInput(
                productId: 'p1',
                quantity: 1,
                totalCostMinor: 10,
              ),
            ],
          ),
        ),
        throwsA(anything),
      );
      expect(await app.database.query('events'), isEmpty);
      await events.confirm('event');
    },
  );
  for (final investment in [false, true]) {
    test(
      'journal failure rolls back money, owner debt and stock; retry succeeds (investment=$investment)',
      () async {
        final c = command(
          minimum: 2,
          fixed: 1000,
          account: investment
              ? 'investment'
              : await cash('quick-default:NEQUI'),
          products: const [EventProductInput('p1', 1)],
        );
        await events.prepare(c);
        final before = await snapshot();
        await app.database.execute(
          "CREATE TRIGGER synthetic_event_failure BEFORE INSERT ON journal_lines BEGIN SELECT RAISE(ABORT,'Synthetic failure'); END",
        );
        await expectLater(events.confirm(c.commandId), throwsA(anything));
        expect(await snapshot(), before);
        await app.database.execute('DROP TRIGGER synthetic_event_failure');
        await events.confirm(c.commandId);
        expect(
          (await events.load()).accounts
              .singleWhere((a) => a.label == 'Nequi')
              .balanceMinor,
          investment ? 50000 : 49000,
        );
        expect(
          (await SqliteTreasuryStore(app).load()).investmentMinor,
          investment ? 1000 : 0,
        );
        expect((await app.database.query('events')).length, 1);
      },
    );
  }
  test(
    'PU rounds half up and preserves original total when division is inexact',
    () async {
      final c = command(
        minimum: 2,
        fixed: 1,
        account: await cash('quick-default:EFECTIVO'),
      );
      final id = await create(c);
      final record = (await events.load()).events.singleWhere(
        (e) => e.productId == id,
      );
      expect(record.unitCostMinor, 1);
      expect(record.totalCostMinor, 1);
      expect(record.fixedCostMinor, 1);
    },
  );
  test(
    'event cannot use another event as physical prize or accept merchandise receipts',
    () async {
      final id = await create(command());
      await expectLater(
        events.prepare(
          command(
            id: 'nested',
            minimum: 1,
            products: [EventProductInput(id, 1)],
          ),
        ),
        throwsA(isA<EventsValidationException>()),
      );
      await expectLater(
        inventory.receivePurchase(
          ReceiptCommand(
            commandId: 'event-merchandise',
            supplierId: 'supplier',
            occurredAtUtc: at,
            dueDate: '2026-10-21',
            lines: [
              ReceiptLineInput(productId: id, quantity: 1, totalCostMinor: 100),
            ],
          ),
        ),
        throwsA(anything),
      );
      expect((await app.database.query('purchases')).length, 1);
    },
  );
  test(
    'confirmed event facts and journal resist rewrite and replacement',
    () async {
      await create(
        command(minimum: 2, products: const [EventProductInput('p1', 1)]),
      );
      for (final table in [
        'events',
        'event_products',
        'event_cost_allocations',
      ]) {
        final row = (await app.database.query(table)).single;
        await expectLater(
          app.database.insert(
            table,
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          ),
          throwsA(anything),
        );
        await expectLater(app.database.delete(table), throwsA(anything));
      }
      final id = (await app.database.query('events')).single['document_id'];
      await expectLater(
        app.database.delete(
          'journal_lines',
          where:
              'entry_id IN(SELECT id FROM journal_entries WHERE document_id=?)',
          whereArgs: [id],
        ),
        throwsA(anything),
      );
    },
  );
}
