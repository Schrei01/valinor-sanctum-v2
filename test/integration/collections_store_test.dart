import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/domain/money.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/features/collections/data/sqlite_collections_store.dart';
import 'package:valinor_sanctum_2/features/collections/domain/collections_store.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/sales/data/sqlite_sales_store.dart';
import 'package:valinor_sanctum_2/features/sales/domain/sales_store.dart';
import 'package:valinor_sanctum_2/features/workspace/data/sqlite_workspace_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase app;
  late SqliteCollectionsStore collections;
  setUp(() async {
    app = await AppDatabase.open(path: inMemoryDatabasePath);
    collections = SqliteCollectionsStore(app);
  });
  tearDown(() => app.close());

  Future<ReceivableSummary> setup({int price = 10000}) async {
    await _fixture(app, price: price);
    return (await collections.load()).receivables.single;
  }

  Future<PreparedCollection> prepare(
    String id,
    String receivable,
    int amount, {
    DateTime? at,
    List<CollectionPartInput>? parts,
  }) => collections.prepareCollection(
    CollectionCommand(
      commandId: id,
      receivableId: receivable,
      occurredAtUtc: at ?? DateTime.utc(2026, 10, 19, 16),
      parts:
          parts ??
          [
            CollectionPartInput(
              cashAccountId: 'cash',
              paymentMethodId: 'cash-method',
              amountMinor: amount,
            ),
          ],
    ),
  );

  test(
    'configuration never creates journal or opening money and identity remains stable',
    () async {
      await _profile(app);
      await collections.saveAccount(
        const CollectionAccount(
          id: 'cash',
          name: 'Caja sintética',
          kind: 'cash',
          balanceMinor: 999999,
        ),
      );
      await collections.saveMethod(
        const CollectionMethod(
          id: 'cash-method',
          code: 'EFECTIVO',
          name: 'Efectivo',
        ),
      );
      final first = await collections.load();
      expect(first.accounts.single.balanceMinor, 0);
      expect(await app.database.query('journal_lines'), isEmpty);
      expect(await app.database.query('business_documents'), isEmpty);
      await collections.saveAccount(
        const CollectionAccount(
          id: 'cash',
          name: 'Caja renombrada',
          kind: 'cash',
          isActive: false,
        ),
      );
      expect((await collections.load()).accounts.single.isActive, isFalse);
      await expectLater(
        collections.saveAccount(
          const CollectionAccount(id: 'cash', name: 'Banco', kind: 'bank'),
        ),
        throwsA(isA<CollectionsValidationException>()),
      );
      await expectLater(
        collections.saveMethod(
          const CollectionMethod(id: 'cash-method', code: 'OTRO', name: 'Otro'),
        ),
        throwsA(isA<CollectionsValidationException>()),
      );
      await expectLater(
        collections.saveMethod(
          const CollectionMethod(
            id: 'duplicate',
            code: 'EFECTIVO',
            name: 'Otro',
          ),
        ),
        throwsA(isA<CollectionsValidationException>()),
      );
    },
  );

  test(
    'partial receipt posts money and receivable only and full receipt preserves earlier response',
    () async {
      final receivable = await setup();
      final unchanged = <String, List<Map<String, Object?>>>{};
      for (final table in [
        'sales',
        'sale_lines',
        'sale_outflows',
        'sale_cost_allocations',
        'inventory_movements',
        'cost_layers',
        'customer_receivables',
      ]) {
        unchanged[table] = await app.database.query(table);
      }
      await prepare('collect-40', receivable.receivableId, 4000);
      final first = await collections.confirmPrepared('collect-40');
      expect(first.totalMinor, 4000);
      expect(first.remainingMinor, 6000);
      final partial = await collections.load();
      expect(partial.receivables.single.collectedMinor, 4000);
      expect(partial.receivables.single.remainingMinor, 6000);
      expect(partial.accounts.single.balanceMinor, 4000);
      final salePartial = (await SqliteSalesStore(app).load()).sales.single;
      expect(salePartial.paidMinor, 4000);
      expect(salePartial.remainingMinor, 6000);
      final lines = await app.database.rawQuery(
        '''
SELECT l.* FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id
WHERE e.document_id = ? ORDER BY l.sequence
''',
        [first.documentId],
      );
      expect(lines, hasLength(2));
      expect(lines.first['account_id'], 'money:cash');
      expect(lines.first['debit_minor'], 4000);
      expect(lines.last['account_id'], 'system:customer-receivable');
      expect(lines.last['credit_minor'], 4000);
      await prepare(
        'collect-60',
        receivable.receivableId,
        6000,
        at: DateTime.utc(2026, 10, 19, 17),
      );
      expect(
        (await collections.confirmPrepared('collect-60')).remainingMinor,
        0,
      );
      final retry = await SqliteCollectionsStore(
        app,
      ).confirmPrepared('collect-40');
      expect(retry.documentId, first.documentId);
      expect(retry.remainingMinor, 6000);
      final complete = await collections.load();
      expect(complete.receivables.single.remainingMinor, 0);
      expect(
        (await SqliteSalesStore(app).load()).sales.single.remainingMinor,
        0,
      );
      expect(complete.accounts.single.balanceMinor, 10000);
      expect(complete.collections, hasLength(2));
      expect(complete.pendingCollections, isEmpty);
      for (final table in unchanged.keys) {
        expect(
          await app.database.query(table),
          unchanged[table],
          reason: table,
        );
      }
      await expectLater(
        prepare('excess', receivable.receivableId, 1),
        throwsA(isA<CollectionsValidationException>()),
      );
    },
  );

  test(
    'split receipt groups shared account debits and distinguishes unavailable clearing balance',
    () async {
      final receivable = await setup();
      await collections.saveAccount(
        const CollectionAccount(
          id: 'clearing',
          name: 'Tránsito sintético',
          kind: 'clearing',
          isAvailable: false,
        ),
      );
      await collections.saveMethod(
        const CollectionMethod(
          id: 'card-method',
          code: 'TARJETA',
          name: 'Tarjeta',
        ),
      );
      final request = await prepare(
        'split',
        receivable.receivableId,
        0,
        parts: const [
          CollectionPartInput(
            cashAccountId: 'cash',
            paymentMethodId: 'cash-method',
            amountMinor: 2000,
          ),
          CollectionPartInput(
            cashAccountId: 'clearing',
            paymentMethodId: 'card-method',
            amountMinor: 5000,
          ),
          CollectionPartInput(
            cashAccountId: 'cash',
            paymentMethodId: 'card-method',
            amountMinor: 3000,
          ),
        ],
      );
      expect(request.parts, hasLength(3));
      final result = await collections.confirmPrepared('split');
      final lines = await app.database.rawQuery(
        'SELECT l.* FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id WHERE e.document_id = ?',
        [result.documentId],
      );
      expect(lines, hasLength(3));
      expect(
        lines
            .where((row) => row['account_id'] == 'money:cash')
            .single['debit_minor'],
        5000,
      );
      final accounts = (await collections.load()).accounts;
      expect(accounts.firstWhere((a) => a.id == 'clearing').balanceMinor, 5000);
      expect(
        accounts.firstWhere((a) => a.id == 'clearing').isAvailable,
        isFalse,
      );
    },
  );

  test(
    'preparation survives adapter recreation and snapshots survive renames before and after commit',
    () async {
      final receivable = await setup();
      final initial = await prepare('snapshot', receivable.receivableId, 4000);
      await collections.saveAccount(
        const CollectionAccount(id: 'cash', name: 'Caja nueva', kind: 'cash'),
      );
      await collections.saveMethod(
        const CollectionMethod(
          id: 'cash-method',
          code: 'EFECTIVO',
          name: 'Nombre nuevo',
        ),
      );
      final same = await prepare('snapshot', receivable.receivableId, 4000);
      expect(same.preparedAtUtc, initial.preparedAtUtc);
      expect(same.parts.single.cashAccountName, 'Caja sintética');
      final recovered = SqliteCollectionsStore(app);
      expect(
        (await recovered.load()).pendingCollections.single.commandId,
        'snapshot',
      );
      final result = await recovered.confirmPrepared('snapshot');
      await collections.saveAccount(
        const CollectionAccount(
          id: 'cash',
          name: 'Caja archivada',
          kind: 'cash',
          isActive: false,
        ),
      );
      await collections.saveMethod(
        const CollectionMethod(
          id: 'cash-method',
          code: 'EFECTIVO',
          name: 'Medio archivado',
          isActive: false,
        ),
      );
      final history = (await recovered.load()).collections.single;
      expect(history.parts.single.cashAccountName, 'Caja sintética');
      expect(history.parts.single.cashAccountKind, 'cash');
      expect(history.parts.single.paymentMethodName, 'Efectivo');
      expect(history.parts.single.paymentMethodCode, 'EFECTIVO');
      expect(
        (await recovered.confirmPrepared('snapshot')).documentId,
        result.documentId,
      );
      await expectLater(
        recovered.discardRejected('snapshot'),
        throwsA(isA<CollectionsValidationException>()),
      );
    },
  );

  test(
    'prepared total is not a reservation and concurrent stale receipt rejects without overpayment',
    () async {
      final receivable = await setup();
      await prepare('first', receivable.receivableId, 7000);
      await prepare('stale', receivable.receivableId, 7000);
      expect((await collections.load()).accounts.single.balanceMinor, 0);
      await collections.confirmPrepared('first');
      await expectLater(
        collections.confirmPrepared('stale'),
        throwsA(isA<CollectionsValidationException>()),
      );
      final snapshot = await collections.load();
      expect(snapshot.accounts.single.balanceMinor, 7000);
      expect(snapshot.receivables.single.remainingMinor, 3000);
      expect(snapshot.pendingCollections.single.status, 'rejected');
      await collections.discardRejected('stale');
      await collections.discardRejected('stale');
      expect((await collections.load()).pendingCollections, isEmpty);
      await expectLater(
        collections.confirmPrepared('stale'),
        throwsA(isA<CollectionsValidationException>()),
      );
      expect(await app.database.query('collections'), hasLength(1));
    },
  );

  test(
    'archiving a destination or method after preparation causes a discardable rejection',
    () async {
      final receivable = await setup();
      await prepare('archived', receivable.receivableId, 1000);
      await collections.saveMethod(
        const CollectionMethod(
          id: 'cash-method',
          code: 'EFECTIVO',
          name: 'Efectivo',
          isActive: false,
        ),
      );
      await expectLater(
        collections.confirmPrepared('archived'),
        throwsA(isA<CollectionsValidationException>()),
      );
      expect(await app.database.query('collections'), isEmpty);
      expect((await collections.load()).accounts.single.balanceMinor, 0);
      expect(
        (await collections.load()).pendingCollections.single.status,
        'rejected',
      );
      await collections.discardRejected('archived');
      await expectLater(
        prepare('inactive', receivable.receivableId, 1000),
        throwsA(isA<CollectionsValidationException>()),
      );
    },
  );

  test(
    'unknown storage failures roll back every receipt fact and retain recoverable prepared input',
    () async {
      final receivable = await setup();
      await prepare('recoverable', receivable.receivableId, 4000);
      await app.database.execute(
        "CREATE TRIGGER test_receipt_failure BEFORE INSERT ON receivable_settlements BEGIN SELECT RAISE(ABORT, 'synthetic storage failure'); END",
      );
      await expectLater(
        collections.confirmPrepared('recoverable'),
        throwsA(isNot(isA<CollectionsValidationException>())),
      );
      for (final table in [
        'collections',
        'collection_parts',
        'receivable_settlements',
      ]) {
        expect(await app.database.query(table), isEmpty, reason: table);
      }
      expect(
        (await app.database.query(
          'command_log',
          where: 'id = ?',
          whereArgs: ['recoverable'],
        )),
        isEmpty,
      );
      expect(
        (await collections.load()).pendingCollections.single.status,
        'prepared',
      );
      expect((await collections.load()).accounts.single.balanceMinor, 0);
      await expectLater(
        collections.discardRejected('recoverable'),
        throwsA(isA<CollectionsValidationException>()),
      );
      await app.database.execute('DROP TRIGGER test_receipt_failure');
      expect(
        (await collections.confirmPrepared('recoverable')).remainingMinor,
        6000,
      );
    },
  );

  test(
    'chronology compares microseconds rather than variable precision timestamp text',
    () async {
      final receivable = await setup();
      await expectLater(
        prepare(
          'before-sale',
          receivable.receivableId,
          1,
          at: DateTime.utc(2026, 10, 19, 14, 59, 59),
        ),
        throwsA(isA<CollectionsValidationException>()),
      );
      final late = DateTime.utc(2026, 10, 19, 16, 0, 0, 0, 1);
      await prepare('micro', receivable.receivableId, 1000, at: late);
      await collections.confirmPrepared('micro');
      await expectLater(
        prepare(
          'millis',
          receivable.receivableId,
          1000,
          at: DateTime.utc(2026, 10, 19, 16),
        ),
        throwsA(isA<CollectionsValidationException>()),
      );
      await prepare('equal', receivable.receivableId, 1000, at: late);
      await collections.confirmPrepared('equal');
      expect(
        (await collections.load()).receivables.single.collectedMinor,
        2000,
      );
    },
  );

  test(
    'a previously prepared earlier timestamp is rejected if a later receipt wins first',
    () async {
      final receivable = await setup();
      await prepare(
        'earlier',
        receivable.receivableId,
        1000,
        at: DateTime.utc(2026, 10, 19, 16),
      );
      await prepare(
        'later',
        receivable.receivableId,
        1000,
        at: DateTime.utc(2026, 10, 19, 17),
      );
      await collections.confirmPrepared('later');
      await expectLater(
        collections.confirmPrepared('earlier'),
        throwsA(isA<CollectionsValidationException>()),
      );
      expect(
        (await collections.load()).receivables.single.collectedMinor,
        1000,
      );
    },
  );

  test(
    'command IDs remain bound to original complete input and other domains',
    () async {
      final receivable = await setup();
      await prepare('bound', receivable.receivableId, 4000);
      await expectLater(
        prepare('bound', receivable.receivableId, 4001),
        throwsA(isA<CollectionsValidationException>()),
      );
      await expectLater(
        prepare(
          'bound',
          receivable.receivableId,
          4000,
          at: DateTime.utc(2026, 10, 19, 17),
        ),
        throwsA(isA<CollectionsValidationException>()),
      );
      await expectLater(
        prepare('purchase', receivable.receivableId, 1),
        throwsA(isA<CollectionsValidationException>()),
      );
      await expectLater(
        prepare('sale', receivable.receivableId, 1),
        throwsA(isA<CollectionsValidationException>()),
      );
      final sales = SqliteSalesStore(app);
      await sales.saveDraft(_draft('pending-draft', 1, 100));
      await sales.prepareConfirmation(
        commandId: 'pending-sale',
        draftId: 'pending-draft',
        expectedRevision: 1,
        occurredAtUtc: DateTime.utc(2026, 10, 19, 15),
        dueDate: '2026-10-20',
      );
      await expectLater(
        prepare('pending-sale', receivable.receivableId, 1),
        throwsA(isA<CollectionsValidationException>()),
      );
      await collections.confirmPrepared('bound');
      expect(await app.database.query('collections'), hasLength(1));
    },
  );

  test(
    'strict parts reject zero negative duplicate empty non-UTC and out of range totals',
    () async {
      final receivable = await setup();
      for (final amount in [0, -1, 10001]) {
        await expectLater(
          prepare('bad-$amount', receivable.receivableId, amount),
          throwsA(isA<CollectionsValidationException>()),
        );
      }
      await expectLater(
        prepare('empty', receivable.receivableId, 0, parts: []),
        throwsA(isA<CollectionsValidationException>()),
      );
      await expectLater(
        prepare(
          'duplicate',
          receivable.receivableId,
          0,
          parts: const [
            CollectionPartInput(
              cashAccountId: 'cash',
              paymentMethodId: 'cash-method',
              amountMinor: 1,
            ),
            CollectionPartInput(
              cashAccountId: 'cash',
              paymentMethodId: 'cash-method',
              amountMinor: 2,
            ),
          ],
        ),
        throwsA(isA<CollectionsValidationException>()),
      );
      await collections.saveMethod(
        const CollectionMethod(id: 'other', code: 'OTRO', name: 'Otro'),
      );
      await expectLater(
        prepare(
          'overflow',
          receivable.receivableId,
          0,
          parts: [
            CollectionPartInput(
              cashAccountId: 'cash',
              paymentMethodId: 'cash-method',
              amountMinor: Money.maxMinorUnits.toInt(),
            ),
            const CollectionPartInput(
              cashAccountId: 'cash',
              paymentMethodId: 'other',
              amountMinor: 1,
            ),
          ],
        ),
        throwsA(isA<CollectionsValidationException>()),
      );
      await expectLater(
        prepare(
          'local',
          receivable.receivableId,
          1,
          at: DateTime(2026, 10, 19, 16),
        ),
        throwsA(isA<CollectionsValidationException>()),
      );
      expect(await app.database.query('collection_requests'), isEmpty);
    },
  );

  test(
    'a prepared collection reserves its command ID against purchases and sales',
    () async {
      final receivable = await setup();
      await prepare('reserved-collection', receivable.receivableId, 4000);
      await expectLater(
        SqliteInventoryStore(app).receivePurchase(
          ReceiptCommand(
            commandId: 'reserved-collection',
            supplierId: 'supplier',
            occurredAtUtc: DateTime.utc(2026, 10, 19, 17),
            dueDate: '2026-10-20',
            lines: const [
              ReceiptLineInput(
                productId: 'product',
                quantity: 1,
                totalCostMinor: 1,
              ),
            ],
          ),
        ),
        throwsA(isA<InventoryValidationException>()),
      );
      final sales = SqliteSalesStore(app);
      final draft = await sales.saveDraft(_draft('other-draft', 1, 1000));
      await expectLater(
        sales.prepareConfirmation(
          commandId: 'reserved-collection',
          draftId: draft.id,
          expectedRevision: draft.revision,
          occurredAtUtc: DateTime.utc(2026, 10, 19, 17),
          dueDate: '2026-10-20',
        ),
        throwsA(isA<SalesValidationException>()),
      );
      expect(
        (await collections.load()).pendingCollections.single.status,
        'prepared',
      );
      await collections.confirmPrepared('reserved-collection');
      expect(
        (await collections.load()).receivables.single.remainingMinor,
        6000,
      );
    },
  );

  test(
    'money remains exact above the double integer precision limit',
    () async {
      const exact = 9007199254740993;
      final receivable = await setup(price: exact);
      await prepare('exact', receivable.receivableId, exact - 1);
      final first = await collections.confirmPrepared('exact');
      expect(first.remainingMinor, 1);
      await prepare('one', receivable.receivableId, 1);
      await collections.confirmPrepared('one');
      final snapshot = await collections.load();
      expect(snapshot.accounts.single.balanceMinor, exact);
      expect(snapshot.receivables.single.collectedMinor, exact);
      expect(snapshot.receivables.single.remainingMinor, 0);
    },
  );

  test(
    'several valid receivables cannot overflow the registered cash balance',
    () async {
      final first = await setup(price: Money.maxMinorUnits.toInt());
      await prepare('max', first.receivableId, Money.maxMinorUnits.toInt());
      await collections.confirmPrepared('max');
      final sales = SqliteSalesStore(app);
      await sales.saveDraft(_draft('second-draft', 1, 1));
      await sales.prepareConfirmation(
        commandId: 'second-sale',
        draftId: 'second-draft',
        expectedRevision: 1,
        occurredAtUtc: DateTime.utc(2026, 10, 19, 15),
        dueDate: '2026-10-20',
      );
      final secondSale = await sales.confirmPrepared('second-sale');
      final second = (await collections.load()).receivables.firstWhere(
        (r) => r.saleDocumentId == secondSale.documentId,
      );
      await prepare('overflow-balance', second.receivableId, 1);
      await expectLater(
        collections.confirmPrepared('overflow-balance'),
        throwsA(isA<CollectionsValidationException>()),
      );
      final snapshot = await collections.load();
      expect(
        snapshot.accounts.single.balanceMinor,
        Money.maxMinorUnits.toInt(),
      );
      expect(
        snapshot.receivables
            .firstWhere((r) => r.receivableId == second.receivableId)
            .remainingMinor,
        1,
      );
      expect(await app.database.query('collections'), hasLength(1));
    },
  );

  test(
    'prepared and committed receipts recover across closing actual independent database file',
    () async {
      final root = Directory(p.absolute('tmp', 'test-collections'));
      await root.create(recursive: true);
      final directory = await root.createTemp('recovery-');
      final path = p.join(directory.path, 'collections.sqlite3');
      AppDatabase? disk = await AppDatabase.open(path: path);
      try {
        await _fixture(disk);
        var store = SqliteCollectionsStore(disk);
        final receivable = (await store.load()).receivables.single;
        await store.prepareCollection(
          CollectionCommand(
            commandId: 'persistent',
            receivableId: receivable.receivableId,
            occurredAtUtc: DateTime.utc(2026, 10, 19, 16),
            parts: const [
              CollectionPartInput(
                cashAccountId: 'cash',
                paymentMethodId: 'cash-method',
                amountMinor: 4000,
              ),
            ],
          ),
        );
        await disk.close();
        disk = await AppDatabase.open(path: path);
        store = SqliteCollectionsStore(disk);
        expect((await store.load()).pendingCollections.single.totalMinor, 4000);
        final first = await store.confirmPrepared('persistent');
        await disk.close();
        disk = await AppDatabase.open(path: path);
        store = SqliteCollectionsStore(disk);
        expect(
          (await store.confirmPrepared('persistent')).documentId,
          first.documentId,
        );
        final snapshot = await store.load();
        expect(snapshot.receivables.single.remainingMinor, 6000);
        expect(snapshot.accounts.single.balanceMinor, 4000);
        expect(snapshot.collections, hasLength(1));
        expect((await disk.readHealth())['integrityOk'], isTrue);
      } finally {
        await disk?.close();
        final resolved = await directory.resolveSymbolicLinks();
        if (!p.isWithin(await root.resolveSymbolicLinks(), resolved)) {
          throw StateError('Unsafe fixture path');
        }
        await Directory(resolved).delete(recursive: true);
      }
    },
  );
}

SaveSaleDraft _draft(String id, int quantity, int price) => SaveSaleDraft(
  id: id,
  label: 'Mesa sintética',
  customerName: 'Cliente sintético',
  expectedRevision: 0,
  lines: [
    SaleDraftLine(
      productId: 'product',
      quantity: quantity,
      unitPriceMinor: price,
    ),
  ],
);

Future<void> _fixture(AppDatabase app, {int price = 10000}) async {
  await _profile(app);
  final inventory = SqliteInventoryStore(app);
  await inventory.saveSupplier(
    const InventorySupplier(id: 'supplier', name: 'Proveedor sintético'),
  );
  await inventory.saveProduct(
    CatalogProduct(
      id: 'product',
      name: 'Producto sintético',
      listPriceMinor: price,
    ),
  );
  await inventory.saveProduct(
    const CatalogProduct(
      id: 'cost-bearing-item',
      name: 'Artículo sintético con costo',
      listPriceMinor: 1,
    ),
  );
  await inventory.receivePurchase(
    ReceiptCommand(
      commandId: 'purchase',
      supplierId: 'supplier',
      occurredAtUtc: DateTime.utc(2026, 10, 19, 10),
      dueDate: '2026-10-20',
      lines: const [
        ReceiptLineInput(productId: 'product', quantity: 3, totalCostMinor: 0),
        ReceiptLineInput(
          productId: 'cost-bearing-item',
          quantity: 1,
          totalCostMinor: 1,
        ),
      ],
    ),
  );
  final sales = SqliteSalesStore(app);
  await sales.saveDraft(_draft('draft', 1, price));
  await sales.prepareConfirmation(
    commandId: 'sale',
    draftId: 'draft',
    expectedRevision: 1,
    occurredAtUtc: DateTime.utc(2026, 10, 19, 15),
    dueDate: '2026-10-20',
  );
  await sales.confirmPrepared('sale');
  final collections = SqliteCollectionsStore(app);
  await collections.saveAccount(
    const CollectionAccount(id: 'cash', name: 'Caja sintética', kind: 'cash'),
  );
  await collections.saveMethod(
    const CollectionMethod(
      id: 'cash-method',
      code: 'EFECTIVO',
      name: 'Efectivo',
    ),
  );
}

Future<void> _profile(AppDatabase app) =>
    SqliteWorkspaceStore(app).createProfile(
      BusinessProfile(
        profileId: 'collections-test',
        businessName: 'Ludoteca sintética',
        currencyCode: 'COP',
        moneyScale: 2,
        timezone: 'America/Bogota',
        createdAtUtc: DateTime.utc(2026, 10, 19),
      ),
    );
