import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/features/collections/data/sqlite_collections_store.dart';
import 'package:valinor_sanctum_2/features/collections/domain/collections_store.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/data/sqlite_quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/sales/data/sqlite_sales_store.dart';
import 'package:valinor_sanctum_2/features/sales/domain/sales_store.dart';
import 'package:valinor_sanctum_2/features/workspace/data/sqlite_workspace_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase app;
  late SqliteQuickSalesStore quick;
  setUp(() async {
    app = await AppDatabase.open(path: inMemoryDatabasePath);
    quick = SqliteQuickSalesStore(app, synthetic: true);
    await fixture(app);
    await quick.ensureDefaults();
  });
  tearDown(() => app.close());

  QuickSaleLine line(
    String id, {
    int quantity = 1,
    int price = 10000,
    String payment = 'EFECTIVO',
    String product = 'product',
  }) => QuickSaleLine(
    id: id,
    productId: product,
    quantityText: '$quantity',
    unitPriceMinor: price,
    paymentOptionId: 'quick-default:$payment',
  );
  Future<QuickSaleAccount> save(
    String id,
    List<QuickSaleLine> lines, {
    int revision = 0,
  }) => quick.saveAccount(
    SaveQuickSaleAccount(
      id: id,
      label: 'Cuenta $id',
      expectedRevision: revision,
      lines: lines,
    ),
  );
  Future<PreparedQuickSale> prepare(
    String command,
    String id, {
    int revision = 1,
  }) => quick.prepareSale(
    commandId: command,
    accountId: id,
    expectedRevision: revision,
    occurredAtUtc: DateTime.utc(2026, 10, 19, 16),
  );
  Future<int> count(String table) async =>
      (await app.database.query(table)).length;

  test('defaults are idempotent catalog configuration with no money', () async {
    await quick.ensureDefaults();
    final snapshot = await quick.load();
    expect(snapshot.paymentOptions.map((p) => p.label), ['Efectivo', 'Nequi']);
    expect(await count('cash_accounts'), 2);
    expect(await count('payment_methods'), 2);
    expect(await count('collections'), 0);
    expect(
      (await SqliteCollectionsStore(
        app,
      ).load()).accounts.every((a) => a.balanceMinor == 0),
      isTrue,
    );
    expect(await count('journal_entries'), 1); // Purchase only.
  });

  test(
    'independent accounts persist incomplete raw drafts with save replay',
    () async {
      final input = SaveQuickSaleAccount(
        id: 'a',
        label: 'Mesa A',
        expectedRevision: 0,
        lines: const [QuickSaleLine(id: 'a1', quantityText: '')],
      );
      final first = await quick.saveAccount(input);
      final replay = await quick.saveAccount(input);
      expect(replay.revision, first.revision);
      await save('b', [line('b1')]);
      final snapshot = await quick.load();
      expect(snapshot.accounts.length, 2);
      expect(
        snapshot.accounts
            .firstWhere((a) => a.id == 'a')
            .lines
            .single
            .quantityText,
        '',
      );
      expect(snapshot.stock.single.quantity, 10);
      expect(await count('sales'), 0);
      await expectLater(
        prepare('bad', 'a'),
        throwsA(isA<QuickSalesValidationException>()),
      );
      expect(await count('quick_sale_requests'), 0);
    },
  );

  test(
    'default setup reuses existing catalog identities without renaming or creating funds',
    () async {
      final other = await AppDatabase.open(path: inMemoryDatabasePath);
      try {
        await fixture(other);
        final catalogs = SqliteCollectionsStore(other);
        await catalogs.saveAccount(
          const CollectionAccount(
            id: 'existing-cash',
            name: 'Caja del propietario',
            kind: 'cash',
          ),
        );
        await catalogs.saveMethod(
          const CollectionMethod(
            id: 'existing-method',
            code: 'EFECTIVO',
            name: 'Contado personalizado',
          ),
        );
        final store = SqliteQuickSalesStore(other);
        await store.ensureDefaults();
        final option = (await store.load()).paymentOptions.singleWhere(
          (o) => o.label == 'Efectivo',
        );
        expect(option.cashAccountId, 'existing-cash');
        expect(option.paymentMethodId, 'existing-method');
        final current = await catalogs.load();
        expect(
          current.accounts.singleWhere((a) => a.id == 'existing-cash').name,
          'Caja del propietario',
        );
        expect(
          current.methods.singleWhere((m) => m.id == 'existing-method').name,
          'Contado personalizado',
        );
        expect(current.accounts.every((a) => a.balanceMinor == 0), isTrue);
        expect(await other.database.query('collections'), isEmpty);
      } finally {
        await other.close();
      }
    },
  );

  test(
    'one registration atomically sells and fully collects per line',
    () async {
      await save('a', [line('a1', quantity: 2), line('a2', payment: 'NEQUI')]);
      await prepare('fast', 'a');
      final result = await quick.confirmPrepared('fast');
      expect(result.totalMinor, 30000);
      expect(result.totalCostMinor, 3001);
      final snapshot = await quick.load();
      expect(snapshot.accounts, isEmpty);
      expect(snapshot.sales.single.lines.length, 2);
      expect(snapshot.stock.single.quantity, 7);
      expect(await count('sale_lines'), 1);
      expect(await count('sale_outflows'), 1);
      expect(await count('quick_sale_line_payments'), 2);
      final receipts = await SqliteCollectionsStore(app).load();
      expect(receipts.receivables.every((r) => r.remainingMinor == 0), isTrue);
      expect(receipts.collections.single.totalMinor, 30000);
      final balances = {
        for (final a in receipts.accounts) a.kind: a.balanceMinor,
      };
      expect(balances, {'cash': 20000, 'mobile': 10000});
      final sale = (await SqliteSalesStore(app).load()).sales.single;
      expect(sale.remainingMinor, 0);
      expect(sale.totalCostMinor, result.totalCostMinor);
      expect(
        (await app.database.query(
          'business_documents',
          where: 'id=?',
          whereArgs: [result.saleDocumentId],
        )).single['source_kind'],
        'synthetic',
      );
    },
  );

  test(
    'prepared and committed replay never duplicates inventory or money',
    () async {
      await save('a', [line('a1')]);
      final first = await prepare('fast', 'a');
      expect((await prepare('fast', 'a')).commandId, first.commandId);
      final result = await quick.confirmPrepared('fast');
      final facts = await app.database.query('journal_lines');
      final replay = await quick.confirmPrepared('fast');
      expect(replay.saleDocumentId, result.saleDocumentId);
      expect(replay.collectionDocumentId, result.collectionDocumentId);
      expect(await app.database.query('journal_lines'), facts);
      expect(await count('sales'), 1);
      expect(await count('collections'), 1);
    },
  );

  test(
    'failure after sale and receipt rolls everything back and retry recovers',
    () async {
      await save('a', [line('a1')]);
      await prepare('fast', 'a');
      final initial = await app.database.query('journal_lines');
      await app.database.execute(
        "CREATE TEMP TRIGGER fail_quick_fact BEFORE INSERT ON quick_sale_line_payments BEGIN SELECT RAISE(ABORT,'Synthetic storage failure after both child documents'); END",
      );
      await expectLater(
        quick.confirmPrepared('fast'),
        throwsA(isA<DatabaseException>()),
      );
      expect(await count('sales'), 0);
      expect(await count('collections'), 0);
      expect(await count('sales_drafts'), 0);
      expect(await count('customer_receivables'), 0);
      expect(await app.database.query('journal_lines'), initial);
      expect((await quick.load()).pendingSales.single.status, 'prepared');
      expect((await quick.load()).accounts.single.status, 'prepared');
      await app.database.execute('DROP TRIGGER fail_quick_fact');
      final result = await quick.confirmPrepared('fast');
      expect(result.totalMinor, 10000);
      expect(await count('sales'), 1);
    },
  );

  test(
    'two accounts cannot oversell and rejected account can be corrected',
    () async {
      await save('a', [line('a1', quantity: 7)]);
      await save('b', [line('b1', quantity: 7)]);
      await prepare('one', 'a');
      await prepare('two', 'b');
      await quick.confirmPrepared('one');
      await expectLater(
        quick.confirmPrepared('two'),
        throwsA(isA<QuickSalesValidationException>()),
      );
      expect(await count('sales'), 1);
      expect(await count('collections'), 1);
      var snapshot = await quick.load();
      expect(snapshot.pendingSales.single.status, 'rejected');
      expect(snapshot.stock.single.quantity, 3);
      await quick.discardRejected('two');
      snapshot = await quick.load();
      expect(snapshot.accounts.single.revision, 2);
      await save('b', [line('b1', quantity: 3)], revision: 2);
      await prepare('three', 'b', revision: 3);
      await quick.confirmPrepared('three');
      expect((await quick.load()).stock.single.quantity, 0);
      expect(
        (await SqliteCollectionsStore(
          app,
        ).load()).receivables.every((r) => r.remainingMinor == 0),
        isTrue,
      );
    },
  );

  test(
    'stale draft changes and deletion are rejected without affecting other cards',
    () async {
      await save('a', [line('a1')]);
      await save('b', [line('b1')]);
      await save('a', [line('a1', quantity: 2)], revision: 1);
      await expectLater(
        save('a', [line('a1', quantity: 3)], revision: 1),
        throwsA(isA<QuickSalesValidationException>()),
      );
      await expectLater(
        quick.cancelAccount(accountId: 'a', expectedRevision: 1),
        throwsA(isA<QuickSalesValidationException>()),
      );
      await quick.cancelAccount(accountId: 'a', expectedRevision: 2);
      await quick.cancelAccount(accountId: 'a', expectedRevision: 2);
      expect((await quick.load()).accounts.single.id, 'b');
    },
  );

  test(
    'prepared account cannot be edited or cancelled and is never discarded on unknown failure',
    () async {
      await save('a', [line('a1')]);
      await prepare('fast', 'a');
      await expectLater(
        save('a', [line('a1', quantity: 2)], revision: 1),
        throwsA(isA<QuickSalesValidationException>()),
      );
      await expectLater(
        quick.cancelAccount(accountId: 'a', expectedRevision: 1),
        throwsA(isA<QuickSalesValidationException>()),
      );
      await expectLater(
        quick.discardRejected('fast'),
        throwsA(isA<QuickSalesValidationException>()),
      );
      expect((await quick.load()).pendingSales.single.status, 'prepared');
    },
  );

  test(
    'line payment names keep prepared snapshots after catalog rename',
    () async {
      await save('a', [line('a1')]);
      await prepare('fast', 'a');
      final catalogs = SqliteCollectionsStore(app);
      final cash = (await catalogs.load()).accounts.singleWhere(
        (a) => a.kind == 'cash',
      );
      final method = (await catalogs.load()).methods.singleWhere(
        (m) => m.code == 'EFECTIVO',
      );
      await catalogs.saveAccount(
        CollectionAccount(id: cash.id, name: 'Caja nueva', kind: 'cash'),
      );
      await catalogs.saveMethod(
        CollectionMethod(
          id: method.id,
          code: method.code,
          name: 'Efectivo nuevo',
        ),
      );
      await quick.confirmPrepared('fast');
      final fact = (await app.database.query(
        'quick_sale_line_payments',
      )).single;
      expect(fact['cash_account_name_snapshot'], 'Caja');
      expect(fact['payment_method_name_snapshot'], 'Efectivo');
      final collection = (await catalogs.load()).collections.single;
      expect(collection.parts.single.cashAccountName, 'Caja');
      expect(collection.parts.single.paymentMethodName, 'Efectivo');
    },
  );

  test(
    'disabled payment rejects without a partial sale and no accidental cash credit',
    () async {
      await save('a', [line('a1')]);
      await prepare('fast', 'a');
      final catalogs = SqliteCollectionsStore(app);
      final method = (await catalogs.load()).methods.singleWhere(
        (m) => m.code == 'EFECTIVO',
      );
      await catalogs.saveMethod(
        CollectionMethod(
          id: method.id,
          code: method.code,
          name: method.name,
          isActive: false,
        ),
      );
      await expectLater(
        quick.confirmPrepared('fast'),
        throwsA(isA<QuickSalesValidationException>()),
      );
      expect(await count('sales'), 0);
      expect(await count('collections'), 0);
      expect((await quick.load()).pendingSales.single.status, 'rejected');
    },
  );

  test(
    'different prices for the same product require correction before preparing',
    () async {
      await save('a', [line('a1'), line('a2', price: 9999, payment: 'NEQUI')]);
      await expectLater(
        prepare('fast', 'a'),
        throwsA(isA<QuickSalesValidationException>()),
      );
      expect(await count('quick_sale_requests'), 0);
    },
  );

  test(
    'zero priced line retains payment fact while positive lines are collected',
    () async {
      final inventory = SqliteInventoryStore(app);
      await inventory.saveProduct(
        const CatalogProduct(id: 'free', name: 'Regalo', listPriceMinor: 0),
      );
      await inventory.receivePurchase(
        ReceiptCommand(
          commandId: 'free-stock',
          supplierId: 'supplier',
          occurredAtUtc: DateTime.utc(2026, 10, 19, 11),
          dueDate: '2026-10-20',
          lines: const [
            ReceiptLineInput(productId: 'free', quantity: 1, totalCostMinor: 1),
          ],
        ),
      );
      await save('a', [
        line('a1'),
        line('a2', price: 0, product: 'free', payment: 'NEQUI'),
      ]);
      await prepare('fast', 'a');
      await quick.confirmPrepared('fast');
      expect(await count('quick_sale_line_payments'), 2);
      expect(await count('collection_parts'), 1);
      expect((await quick.load()).sales.single.lines.last.totalMinor, 0);
    },
  );

  test('invalid quantities and overflowing totals cannot prepare', () async {
    for (final value in ['', '0', '-1', '1.5', '1e2', '9223372036854775808']) {
      final id = 'quantity-$value';
      await quick.saveAccount(
        SaveQuickSaleAccount(
          id: id,
          label: 'Cantidad',
          expectedRevision: 0,
          lines: [
            QuickSaleLine(
              id: 'line-$value',
              productId: 'product',
              quantityText: value,
              unitPriceMinor: 10000,
              paymentOptionId: 'quick-default:EFECTIVO',
            ),
          ],
        ),
      );
      await expectLater(
        prepare('cmd-$value', id),
        throwsA(isA<QuickSalesValidationException>()),
      );
    }
    expect(await count('quick_sale_requests'), 0);
  });

  test(
    'global reservations protect parent children and internal legacy draft',
    () async {
      await save('a', [line('a1')]);
      await prepare('fast', 'a');
      final request = (await app.database.query('quick_sale_requests')).single;
      final sales = SqliteSalesStore(app);
      await sales.saveDraft(
        SaveSaleDraft(
          id: 'manual',
          label: 'Manual',
          customerName: 'Cliente',
          expectedRevision: 0,
          lines: const [
            SaleDraftLine(
              productId: 'product',
              quantity: 1,
              unitPriceMinor: 10000,
            ),
          ],
        ),
      );
      for (final id in [
        'fast',
        request['sale_command_id'] as String,
        request['collection_command_id'] as String,
      ]) {
        await expectLater(
          sales.prepareConfirmation(
            commandId: id,
            draftId: 'manual',
            expectedRevision: 1,
            occurredAtUtc: DateTime.utc(2026, 10, 19, 16),
            dueDate: '2026-10-20',
          ),
          throwsA(isA<SalesValidationException>()),
        );
        await expectLater(
          sales.confirmPrepared(id),
          throwsA(isA<SalesValidationException>()),
        );
        await expectLater(
          SqliteCollectionsStore(app).confirmPrepared(id),
          throwsA(isA<CollectionsValidationException>()),
        );
        await save('collision-$id', [line('line-$id')]);
        await expectLater(
          prepare(id, 'collision-$id'),
          throwsA(isA<QuickSalesValidationException>()),
        );
      }
      await expectLater(
        sales.saveDraft(
          SaveSaleDraft(
            id: request['legacy_draft_id'] as String,
            label: 'Hijack',
            customerName: 'Cliente',
            expectedRevision: 0,
            lines: const [],
          ),
        ),
        throwsA(isA<SalesValidationException>()),
      );
      await quick.confirmPrepared('fast');
      expect(await count('sales'), 1);
    },
  );

  test(
    'confirmed line facts and durable request cannot be replaced or edited',
    () async {
      await save('a', [line('a1')]);
      await prepare('fast', 'a');
      await quick.confirmPrepared('fast');
      final fact = (await app.database.query(
        'quick_sale_line_payments',
      )).single;
      await expectLater(
        app.database.update(
          'quick_sale_line_payments',
          {'total_minor': 1},
          where: 'id=?',
          whereArgs: [fact['id']],
        ),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        app.database.insert(
          'quick_sale_line_payments',
          fact,
          conflictAlgorithm: ConflictAlgorithm.replace,
        ),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        app.database.delete(
          'quick_sale_requests',
          where: 'command_id=?',
          whereArgs: ['fast'],
        ),
        throwsA(isA<DatabaseException>()),
      );
    },
  );

  test(
    'file reopen recovers prepared operation then stable committed response',
    () async {
      final root = Directory(
        p.join(
          Directory.current.path,
          'tmp',
          'tests',
          'quick-${InventoryIds.next()}',
        ),
      )..createSync(recursive: true);
      final path = p.join(root.path, 'quick.sqlite3');
      var disk = await AppDatabase.open(path: path);
      QuickSaleResult? first;
      try {
        await fixture(disk);
        var store = SqliteQuickSalesStore(disk, synthetic: true);
        await store.ensureDefaults();
        await store.saveAccount(
          SaveQuickSaleAccount(
            id: 'a',
            label: 'Reapertura',
            expectedRevision: 0,
            lines: [line('a1', quantity: 2)],
          ),
        );
        await store.prepareSale(
          commandId: 'restart',
          accountId: 'a',
          expectedRevision: 1,
          occurredAtUtc: DateTime.utc(2026, 10, 19, 16),
        );
        await disk.close();
        disk = await AppDatabase.open(path: path);
        store = SqliteQuickSalesStore(disk, synthetic: true);
        expect((await store.load()).pendingSales.single.commandId, 'restart');
        first = await store.confirmPrepared('restart');
        await disk.close();
        disk = await AppDatabase.open(path: path);
        store = SqliteQuickSalesStore(disk, synthetic: true);
        final replay = await store.confirmPrepared('restart');
        expect(replay.saleDocumentId, first.saleDocumentId);
        expect(replay.collectionDocumentId, first.collectionDocumentId);
        expect(
          (await SqliteCollectionsStore(
            disk,
          ).load()).receivables.every((r) => r.remainingMinor == 0),
          isTrue,
        );
        expect(await disk.database.query('sales'), hasLength(1));
      } finally {
        await disk.close();
      }
    },
  );
}

Future<void> fixture(AppDatabase app) async {
  await SqliteWorkspaceStore(app).createProfile(
    BusinessProfile(
      profileId: 'quick-test',
      businessName: 'Ludoteca sintética',
      currencyCode: 'COP',
      moneyScale: 2,
      timezone: 'America/Bogota',
      createdAtUtc: DateTime.utc(2026, 10, 19),
    ),
  );
  final inventory = SqliteInventoryStore(app, synthetic: true);
  await inventory.saveSupplier(
    const InventorySupplier(id: 'supplier', name: 'Proveedor sintético'),
  );
  await inventory.saveProduct(
    const CatalogProduct(
      id: 'product',
      name: 'Producto sintético',
      listPriceMinor: 10000,
    ),
  );
  await inventory.receivePurchase(
    ReceiptCommand(
      commandId: 'purchase',
      supplierId: 'supplier',
      occurredAtUtc: DateTime.utc(2026, 10, 19, 10),
      dueDate: '2026-10-20',
      lines: const [
        ReceiptLineInput(
          productId: 'product',
          quantity: 10,
          totalCostMinor: 10001,
        ),
      ],
    ),
  );
}
