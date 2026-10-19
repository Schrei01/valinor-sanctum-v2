import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/domain/money.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/sales/data/sqlite_sales_store.dart';
import 'package:valinor_sanctum_2/features/sales/domain/sales_store.dart';
import 'package:valinor_sanctum_2/features/workspace/data/sqlite_workspace_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase app;
  late SqliteInventoryStore inventory;
  late SqliteSalesStore sales;
  setUp(() async {
    app = await AppDatabase.open(path: inMemoryDatabasePath);
    inventory = SqliteInventoryStore(app);
    sales = SqliteSalesStore(app);
  });
  tearDown(() => app.close());

  Future<void> setup({int quantity = 3, int cost = 1001}) async {
    await _catalog(app);
    await inventory.receivePurchase(_receipt('purchase', quantity, cost));
  }

  Future<void> prepare({
    String draft = 'draft',
    String command = 'sale',
    int quantity = 2,
    int price = 1500,
  }) async {
    await sales.saveDraft(_draft(draft, quantity, price));
    await sales.prepareConfirmation(
      commandId: command,
      draftId: draft,
      expectedRevision: 1,
      occurredAtUtc: DateTime.utc(2026, 10, 19, 15),
      dueDate: '2026-10-20',
    );
  }

  test(
    'drafts survive in storage without reserving or changing stock or journals',
    () async {
      await setup();
      final before = await app.database.query('journal_lines');
      await sales.saveDraft(_draft('draft', 5, 1500));
      final snapshot = await SqliteSalesStore(app).load();
      expect(snapshot.drafts.single.lines.single.quantity, 5);
      expect(snapshot.drafts.single.status, 'open');
      expect(snapshot.stock.single.quantity, 3);
      expect(snapshot.sales, isEmpty);
      expect(await app.database.query('journal_lines'), before);
      expect(await app.database.query('customer_receivables'), isEmpty);
    },
  );

  test(
    'sale posts exact FIFO stock receivable and balanced accounting atomically',
    () async {
      await setup();
      await prepare();
      final result = await sales.confirmPrepared('sale');
      expect(result.totalMinor, 3000);
      expect(result.totalCostMinor, 668);
      final stock = (await inventory.load()).stock.single;
      expect(stock.quantity, 1);
      expect(stock.totalCostMinor, 333);
      final snapshot = await sales.load();
      expect(snapshot.drafts, isEmpty);
      expect(snapshot.pendingConfirmations, isEmpty);
      expect(snapshot.sales.single.customerName, 'Cliente sintético');
      expect(snapshot.sales.single.lines.single.totalCostMinor, 668);
      expect(
        (await app.database.query(
          'customer_receivables',
        )).single['initial_minor'],
        3000,
      );
      final entry = (await app.database.query(
        'journal_entries',
        where: 'document_id = ?',
        whereArgs: [result.documentId],
      )).single;
      final lines = await app.database.query(
        'journal_lines',
        where: 'entry_id = ?',
        whereArgs: [entry['id']],
      );
      expect(
        lines.fold<int>(0, (sum, row) => sum + (row['debit_minor'] as int)),
        3668,
      );
      expect(
        lines.fold<int>(0, (sum, row) => sum + (row['credit_minor'] as int)),
        3668,
      );
      expect(entry['status'], 'posted');
      expect(
        (await app.database.query('sales')).single['cost_policy'],
        'fifo-front-remainder-v1',
      );
      expect(await app.database.query('cash_accounts'), isEmpty);
    },
  );

  test(
    'persistent confirmation retry returns original sale after catalog changes',
    () async {
      await setup();
      await prepare();
      final first = await sales.confirmPrepared('sale');
      await inventory.saveProduct(
        const CatalogProduct(
          id: 'product',
          name: 'Otro nombre',
          listPriceMinor: 99,
          isActive: false,
        ),
      );
      final retry = await SqliteSalesStore(app).confirmPrepared('sale');
      expect(retry.documentId, first.documentId);
      expect(retry.totalCostMinor, first.totalCostMinor);
      final snapshot = await sales.load();
      expect(
        snapshot.sales.single.lines.single.productName,
        'Producto sintético',
      );
      expect(snapshot.sales.single.lines.single.unitPriceMinor, 1500);
      expect(snapshot.products, isEmpty);
      expect(snapshot.stock.single.quantity, 1);
      for (final table in [
        'sales',
        'sale_lines',
        'sale_outflows',
        'sale_cost_allocations',
        'customer_receivables',
      ]) {
        expect(await app.database.query(table), hasLength(1), reason: table);
      }
    },
  );

  test(
    'saved draft retry and optimistic revision reject stale edits',
    () async {
      await setup();
      final first = await sales.saveDraft(_draft('draft', 1, 1500));
      final retry = await sales.saveDraft(_draft('draft', 1, 1500));
      expect(retry.revision, first.revision);
      await expectLater(
        sales.saveDraft(_draft('draft', 2, 1500)),
        throwsA(isA<SalesValidationException>()),
      );
      final edited = await sales.saveDraft(
        _draft('draft', 2, 1500, revision: 1),
      );
      expect(edited.revision, 2);
    },
  );

  test(
    'prepared input locks editing and is recovered by a new adapter',
    () async {
      await setup();
      await prepare();
      final recovered = await SqliteSalesStore(app).load();
      expect(recovered.pendingConfirmations.single.commandId, 'sale');
      expect(recovered.drafts.single.status, 'prepared');
      await expectLater(
        sales.saveDraft(_draft('draft', 1, 1500, revision: 1)),
        throwsA(isA<SalesValidationException>()),
      );
      await expectLater(
        sales.discardRejected('sale'),
        throwsA(isA<SalesValidationException>()),
      );
      await SqliteSalesStore(app).confirmPrepared('sale');
      expect((await inventory.load()).stock.single.quantity, 1);
    },
  );

  test(
    'same preparation identity cannot change dates revision or account',
    () async {
      await setup();
      await prepare();
      final retry = await sales.prepareConfirmation(
        commandId: 'sale',
        draftId: 'draft',
        expectedRevision: 1,
        occurredAtUtc: DateTime.utc(2026, 10, 19, 15),
        dueDate: '2026-10-20',
      );
      expect(retry.status, 'prepared');
      await expectLater(
        sales.prepareConfirmation(
          commandId: 'sale',
          draftId: 'draft',
          expectedRevision: 1,
          occurredAtUtc: DateTime.utc(2026, 10, 19, 15),
          dueDate: '2026-10-21',
        ),
        throwsA(isA<SalesValidationException>()),
      );
      await sales.confirmPrepared('sale');
      await expectLater(
        sales.discardRejected('sale'),
        throwsA(isA<SalesValidationException>()),
      );
    },
  );

  test(
    'insufficient stock rejects without effects and only then allows unlock',
    () async {
      await setup();
      await prepare(quantity: 4);
      await expectLater(
        sales.confirmPrepared('sale'),
        throwsA(isA<SalesValidationException>()),
      );
      expect(await app.database.query('sales'), isEmpty);
      expect(await app.database.query('sale_outflows'), isEmpty);
      expect(await app.database.query('customer_receivables'), isEmpty);
      expect(await app.database.query('command_log'), hasLength(1));
      expect(
        (await sales.load()).pendingConfirmations.single.status,
        'rejected',
      );
      await sales.discardRejected('sale');
      final draft = (await sales.load()).drafts.single;
      expect(draft.status, 'open');
      expect(draft.revision, 2);
      await expectLater(
        sales.confirmPrepared('sale'),
        throwsA(isA<SalesValidationException>()),
      );
      await sales.saveDraft(_draft('draft', 1, 1500, revision: 2));
      await sales.prepareConfirmation(
        commandId: 'second',
        draftId: 'draft',
        expectedRevision: 3,
        occurredAtUtc: DateTime.utc(2026, 10, 19, 15),
        dueDate: '2026-10-20',
      );
      await sales.confirmPrepared('second');
      expect((await inventory.load()).stock.single.quantity, 2);
    },
  );

  test(
    'prepared sale identity cannot be consumed by a purchase command',
    () async {
      await setup();
      await prepare();
      await expectLater(
        inventory.receivePurchase(_receipt('sale', 1, 900)),
        throwsA(isA<InventoryValidationException>()),
      );
      expect(await app.database.query('purchases'), hasLength(1));
      expect(
        (await sales.load()).pendingConfirmations.single.status,
        'prepared',
      );
      final result = await sales.confirmPrepared('sale');
      expect(result.totalMinor, 3000);
      expect((await inventory.load()).stock.single.quantity, 1);
      expect(await app.database.query('sales'), hasLength(1));
    },
  );

  test(
    'FIFO spans layers and exhausts the exact original cost across sales',
    () async {
      await setup();
      await inventory.receivePurchase(_receipt('second-purchase', 2, 701));
      await prepare(quantity: 4);
      final first = await sales.confirmPrepared('sale');
      expect(first.totalCostMinor, 1352);
      expect((await inventory.load()).stock.single.totalCostMinor, 350);
      await prepare(draft: 'second-draft', command: 'second-sale', quantity: 1);
      final second = await sales.confirmPrepared('second-sale');
      expect(second.totalCostMinor, 350);
      expect((await inventory.load()).stock.single.quantity, 0);
      expect((await inventory.load()).stock.single.totalCostMinor, 0);
      expect(first.totalCostMinor + second.totalCostMinor, 1702);
    },
  );

  test(
    'documented zero cost remains complete and needs only revenue journal',
    () async {
      await _catalog(app);
      await inventory.saveProduct(
        const CatalogProduct(id: 'paid', name: 'Otro', listPriceMinor: 1),
      );
      await inventory.receivePurchase(
        ReceiptCommand(
          commandId: 'purchase',
          supplierId: 'supplier',
          occurredAtUtc: DateTime.utc(2026, 10, 19, 10),
          dueDate: '2026-10-20',
          lines: [
            const ReceiptLineInput(
              productId: 'product',
              quantity: 3,
              totalCostMinor: 0,
            ),
            const ReceiptLineInput(
              productId: 'paid',
              quantity: 1,
              totalCostMinor: 1,
            ),
          ],
        ),
      );
      await prepare();
      final result = await sales.confirmPrepared('sale');
      expect(result.totalCostMinor, 0);
      final entry = (await app.database.query(
        'journal_entries',
        where: 'document_id = ?',
        whereArgs: [result.documentId],
      )).single;
      expect(entry['cost_completeness'], 'complete');
      expect(
        await app.database.query(
          'journal_lines',
          where: 'entry_id = ?',
          whereArgs: [entry['id']],
        ),
        hasLength(2),
      );
    },
  );

  test('sale cannot consume purchases acquired after its date', () async {
    await setup();
    await sales.saveDraft(_draft('draft', 1, 100));
    await sales.prepareConfirmation(
      commandId: 'backdated',
      draftId: 'draft',
      expectedRevision: 1,
      occurredAtUtc: DateTime.utc(2026, 10, 18, 15),
      dueDate: '2026-10-20',
    );
    await expectLater(
      sales.confirmPrepared('backdated'),
      throwsA(isA<SalesValidationException>()),
    );
    expect((await inventory.load()).stock.single.quantity, 3);
  });

  test(
    'purchase cannot introduce retroactive stock behind a confirmed sale',
    () async {
      await setup();
      await prepare();
      await sales.confirmPrepared('sale');
      await expectLater(
        inventory.receivePurchase(_receipt('retroactive-purchase', 1, 900)),
        throwsA(isA<InventoryValidationException>()),
      );
      expect(await app.database.query('purchases'), hasLength(1));
      expect(await app.database.query('cost_layers'), hasLength(1));
      expect((await inventory.load()).stock.single.quantity, 1);
      expect((await inventory.load()).stock.single.totalCostMinor, 333);
    },
  );

  test(
    'a delayed confirmation cannot move FIFO history behind a later sale',
    () async {
      await setup();
      await sales.saveDraft(_draft('early-draft', 1, 100));
      await sales.prepareConfirmation(
        commandId: 'early',
        draftId: 'early-draft',
        expectedRevision: 1,
        occurredAtUtc: DateTime.utc(2026, 10, 19, 14),
        dueDate: '2026-10-20',
      );
      await prepare(quantity: 1);
      await sales.confirmPrepared('sale');
      await expectLater(
        sales.confirmPrepared('early'),
        throwsA(isA<SalesValidationException>()),
      );
      expect(await app.database.query('sales'), hasLength(1));
      expect(
        (await sales.load()).pendingConfirmations.single.status,
        'rejected',
      );
      expect((await inventory.load()).stock.single.quantity, 2);
      expect((await inventory.load()).stock.single.totalCostMinor, 667);
    },
  );

  test(
    'chronology comparisons preserve microseconds with mixed ISO precision',
    () async {
      await setup();
      await sales.saveDraft(_draft('first', 1, 100));
      final at = DateTime.utc(2026, 10, 19, 15);
      await sales.prepareConfirmation(
        commandId: 'first-sale',
        draftId: 'first',
        expectedRevision: 1,
        occurredAtUtc: at,
        dueDate: '2026-10-20',
      );
      await sales.confirmPrepared('first-sale');
      await sales.saveDraft(_draft('second', 1, 100));
      await sales.prepareConfirmation(
        commandId: 'second-sale',
        draftId: 'second',
        expectedRevision: 1,
        occurredAtUtc: at.add(const Duration(microseconds: 1)),
        dueDate: '2026-10-20',
      );
      await sales.confirmPrepared('second-sale');
      await sales.saveDraft(_draft('third', 1, 100));
      await sales.prepareConfirmation(
        commandId: 'third-sale',
        draftId: 'third',
        expectedRevision: 1,
        occurredAtUtc: at,
        dueDate: '2026-10-20',
      );
      await expectLater(
        sales.confirmPrepared('third-sale'),
        throwsA(isA<SalesValidationException>()),
      );
      expect((await inventory.load()).stock.single.quantity, 1);
    },
  );

  test(
    'sale journal aggregate overflow rejects before any sale effects',
    () async {
      await setup(quantity: 1, cost: 1);
      await prepare(quantity: 1, price: Money.maxMinorUnits.toInt());
      await expectLater(
        sales.confirmPrepared('sale'),
        throwsA(isA<SalesValidationException>()),
      );
      expect(await app.database.query('sales'), isEmpty);
      expect((await inventory.load()).stock.single.quantity, 1);
      expect(
        (await sales.load()).pendingConfirmations.single.status,
        'rejected',
      );
    },
  );

  test(
    'storage exception rolls back all sale facts and preserves prepared recovery',
    () async {
      await setup();
      await prepare();
      // A storage failure is deliberately not converted into deterministic rejection.
      await app.database.execute(
        '''CREATE TRIGGER test_fail_sale BEFORE INSERT ON customer_receivables
BEGIN SELECT RAISE(ABORT, 'synthetic storage failure'); END''',
      );
      await expectLater(
        sales.confirmPrepared('sale'),
        throwsA(isA<DatabaseException>()),
      );
      for (final table in [
        'sales',
        'sale_lines',
        'sale_outflows',
        'sale_cost_allocations',
        'customer_receivables',
      ]) {
        expect(await app.database.query(table), isEmpty, reason: table);
      }
      expect(
        (await sales.load()).pendingConfirmations.single.status,
        'prepared',
      );
      expect(await app.database.query('command_log'), hasLength(1));
      await app.database.execute('DROP TRIGGER test_fail_sale');
      await sales.confirmPrepared('sale');
      expect((await inventory.load()).stock.single.quantity, 1);
    },
  );

  test(
    'concurrent confirmations cannot oversell the same remaining stock',
    () async {
      await setup();
      await prepare();
      await prepare(draft: 'other-draft', command: 'other-sale');
      final outcomes = await Future.wait([
        sales
            .confirmPrepared('sale')
            .then<Object>((r) => r)
            .catchError((Object e) => e),
        sales
            .confirmPrepared('other-sale')
            .then<Object>((r) => r)
            .catchError((Object e) => e),
      ]);
      expect(outcomes.whereType<SaleResult>(), hasLength(1));
      expect(outcomes.whereType<SalesValidationException>(), hasLength(1));
      expect((await inventory.load()).stock.single.quantity, 1);
    },
  );

  test(
    'confirmed sales remain immutable through SQL update delete and replacement',
    () async {
      await setup();
      await prepare();
      await sales.confirmPrepared('sale');
      for (final table in [
        'sales',
        'sale_lines',
        'sale_outflows',
        'sale_cost_allocations',
        'customer_receivables',
        'sale_confirmations',
      ]) {
        final row = (await app.database.query(table)).single;
        final key = table == 'sales'
            ? 'document_id'
            : table == 'sale_confirmations'
            ? 'command_id'
            : 'id';
        await expectLater(
          app.database.delete(table, where: '$key = ?', whereArgs: [row[key]]),
          throwsA(isA<DatabaseException>()),
          reason: table,
        );
        await expectLater(
          app.database.update(
            table,
            row,
            where: '$key = ?',
            whereArgs: [row[key]],
          ),
          throwsA(isA<DatabaseException>()),
          reason: table,
        );
        await expectLater(
          app.database.insert(
            table,
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          ),
          throwsA(isA<DatabaseException>()),
          reason: table,
        );
      }
      final draft = (await app.database.query('sales_drafts')).single;
      await expectLater(
        app.database.insert(
          'sales_drafts',
          draft,
          conflictAlgorithm: ConflictAlgorithm.replace,
        ),
        throwsA(isA<DatabaseException>()),
      );
      final line = (await app.database.query('sales_draft_lines')).single;
      await expectLater(
        app.database.insert(
          'sales_draft_lines',
          line,
          conflictAlgorithm: ConflictAlgorithm.replace,
        ),
        throwsA(isA<DatabaseException>()),
      );
    },
  );

  test(
    'file reopen recovers prepared sale then committed retry without duplicates',
    () async {
      final root = Directory(
        p.join(Directory.current.path, 'tmp', 'sales-tests'),
      );
      await root.create(recursive: true);
      final fixture = await root.createTemp('persistent-');
      final path = p.join(fixture.path, 'sales.sqlite3');
      AppDatabase? disk = await AppDatabase.open(path: path);
      try {
        await _catalog(disk);
        await SqliteInventoryStore(
          disk,
        ).receivePurchase(_receipt('purchase', 3, 1001));
        var adapter = SqliteSalesStore(disk);
        await adapter.saveDraft(_draft('draft', 2, 1500));
        await adapter.prepareConfirmation(
          commandId: 'sale',
          draftId: 'draft',
          expectedRevision: 1,
          occurredAtUtc: DateTime.utc(2026, 10, 19, 15),
          dueDate: '2026-10-20',
        );
        await disk.close();
        disk = await AppDatabase.open(path: path);
        adapter = SqliteSalesStore(disk);
        expect(
          (await adapter.load()).pendingConfirmations.single.commandId,
          'sale',
        );
        final original = await adapter.confirmPrepared('sale');
        await disk.close();
        disk = await AppDatabase.open(path: path);
        adapter = SqliteSalesStore(disk);
        expect(
          (await adapter.confirmPrepared('sale')).documentId,
          original.documentId,
        );
        expect((await adapter.load()).stock.single.quantity, 1);
        expect(await disk.database.query('sales'), hasLength(1));
        expect((await disk.readHealth())['integrityOk'], isTrue);
      } finally {
        await disk?.close();
        final resolved = await fixture.resolveSymbolicLinks();
        if (!p.isWithin(await root.resolveSymbolicLinks(), resolved)) {
          throw StateError('Unsafe fixture path');
        }
        await Directory(resolved).delete(recursive: true);
      }
    },
  );
}

SaveSaleDraft _draft(String id, int quantity, int price, {int revision = 0}) =>
    SaveSaleDraft(
      id: id,
      label: 'Mesa sintética',
      customerName: 'Cliente sintético',
      expectedRevision: revision,
      lines: [
        SaleDraftLine(
          productId: 'product',
          quantity: quantity,
          unitPriceMinor: price,
        ),
      ],
    );

ReceiptCommand _receipt(String id, int quantity, int cost) => ReceiptCommand(
  commandId: id,
  supplierId: 'supplier',
  occurredAtUtc: DateTime.utc(2026, 10, 19, 10),
  dueDate: '2026-10-20',
  lines: [
    ReceiptLineInput(
      productId: 'product',
      quantity: quantity,
      totalCostMinor: cost,
    ),
  ],
);

Future<void> _catalog(AppDatabase app) async {
  await SqliteWorkspaceStore(app).createProfile(
    BusinessProfile(
      profileId: 'sales-test',
      businessName: 'Ludoteca sintética',
      currencyCode: 'COP',
      moneyScale: 2,
      timezone: 'America/Bogota',
      createdAtUtc: DateTime.utc(2026, 10, 19),
    ),
  );
  final inventory = SqliteInventoryStore(app);
  await inventory.saveSupplier(
    const InventorySupplier(id: 'supplier', name: 'Proveedor sintético'),
  );
  await inventory.saveProduct(
    const CatalogProduct(
      id: 'product',
      name: 'Producto sintético',
      listPriceMinor: 1500,
    ),
  );
}
