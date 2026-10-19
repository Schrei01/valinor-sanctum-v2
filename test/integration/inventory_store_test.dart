import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/domain/money.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/workspace/data/sqlite_workspace_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase app;
  late SqliteInventoryStore store;

  setUp(() async {
    app = await AppDatabase.open(path: inMemoryDatabasePath);
    store = SqliteInventoryStore(app);
  });
  tearDown(() => app.close());

  Future<void> setupCatalog() async {
    await _profile(app);
    await store.saveCategory(
      const InventoryCategory(id: 'category', name: 'Juegos'),
    );
    await store.saveSupplier(
      const InventorySupplier(id: 'supplier', name: 'Proveedor sintético'),
    );
    await store.saveProduct(
      const CatalogProduct(
        id: 'product',
        name: 'Juego sintético',
        sku: 'SKU-01',
        categoryId: 'category',
        listPriceMinor: 4500,
      ),
    );
  }

  test(
    'catalog requires profile and does not seed money or operator',
    () async {
      await expectLater(
        store.saveCategory(const InventoryCategory(id: 'a', name: 'A')),
        throwsA(isA<InventoryValidationException>()),
      );
      await setupCatalog();
      final snapshot = await store.load();
      expect(snapshot.products.single.listPriceMinor, 4500);
      expect(snapshot.stock, isEmpty);
      expect(snapshot.receipts, isEmpty);
      for (final table in [
        'actors',
        'ledger_accounts',
        'business_documents',
        'command_log',
      ]) {
        expect(await app.database.query(table), isEmpty, reason: table);
      }
    },
  );

  test(
    'receipt atomically records inventory cost payable and balanced journal',
    () async {
      await setupCatalog();
      final result = await store.receivePurchase(_command());
      final snapshot = await store.load();
      expect(result.totalMinor, 1001);
      expect(snapshot.stock.single.quantity, 3);
      expect(snapshot.stock.single.totalCostMinor, 1001);
      expect(snapshot.receipts.single.documentId, result.documentId);
      expect(snapshot.receipts.single.reference, 'FAC-01');
      expect(
        (await app.database.query('obligations')).single['initial_minor'],
        1001,
      );
      expect(
        (await app.database.query('cost_layers')).single['total_cost_minor'],
        1001,
      );
      expect(
        (await app.database.query(
          'business_documents',
        )).single['business_date'],
        '2026-10-18',
      );
      expect(
        (await app.database.query('business_documents')).single['status'],
        'posted',
      );
      expect(
        (await app.database.query('journal_entries')).single['status'],
        'posted',
      );
      final journal = await app.database.query(
        'journal_lines',
        orderBy: 'sequence',
      );
      expect(journal.map((r) => r['debit_minor']), [1001, 0]);
      expect(journal.map((r) => r['credit_minor']), [0, 1001]);
      expect(await app.database.query('cash_accounts'), isEmpty);
      final actor = (await app.database.query('actors')).single;
      expect(actor['kind'], 'system');
      expect(actor['display_name'], 'Operador local');
      expect(
        (await app.database.query(
          'command_log',
        )).single['authorization_policy_version'],
        'development-single-user-v1',
      );
    },
  );

  test(
    'identical retry returns persistent response without duplicating facts',
    () async {
      await setupCatalog();
      final first = await store.receivePurchase(_command());
      await store.saveSupplier(
        const InventorySupplier(
          id: 'supplier',
          name: 'Proveedor archivado',
          isActive: false,
        ),
      );
      final second = await store.receivePurchase(_command());
      expect(second.documentId, first.documentId);
      expect(second.commandId, first.commandId);
      expect(second.totalMinor, first.totalMinor);
      for (final table in [
        'purchases',
        'purchase_lines',
        'inventory_movements',
        'cost_layers',
        'obligations',
        'journal_entries',
        'business_documents',
        'command_log',
      ]) {
        expect(await app.database.query(table), hasLength(1), reason: table);
      }
      final payload =
          jsonDecode(
                (await app.database.query(
                      'command_log',
                    )).single['response_json']
                    as String,
              )
              as Map<String, dynamic>;
      expect(payload['canonicalPayload'], isA<String>());
    },
  );

  test('same command identifier with changed payload is rejected', () async {
    await setupCatalog();
    await store.receivePurchase(_command());
    await expectLater(
      store.receivePurchase(_command(cost: 1002)),
      throwsA(isA<InventoryValidationException>()),
    );
    expect((await store.load()).stock.single.totalCostMinor, 1001);
  });

  test(
    'failure at final posting rolls back all receipt and lazy system rows',
    () async {
      await setupCatalog();
      await app.database.execute('''
CREATE TRIGGER test_failure BEFORE UPDATE OF status ON journal_entries
WHEN NEW.status = 'posted' BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END
''');
      await expectLater(
        store.receivePurchase(_command()),
        throwsA(isA<DatabaseException>()),
      );
      for (final table in [
        'actors',
        'ledger_accounts',
        'purchases',
        'purchase_lines',
        'inventory_movements',
        'cost_layers',
        'obligations',
        'journal_lines',
        'journal_entries',
        'business_documents',
        'command_log',
      ]) {
        expect(await app.database.query(table), isEmpty, reason: table);
      }
      await app.database.execute('DROP TRIGGER test_failure');
      await store.receivePurchase(_command());
      expect((await store.load()).stock.single.quantity, 3);
    },
  );

  test(
    'catalog edits and archives retain receipt name snapshots and stock',
    () async {
      await setupCatalog();
      await store.receivePurchase(_command());
      await store.saveProduct(
        const CatalogProduct(
          id: 'product',
          name: 'Nombre nuevo',
          sku: 'SKU-NEW',
          categoryId: 'category',
          listPriceMinor: 9999,
          isActive: false,
        ),
      );
      await store.saveSupplier(
        const InventorySupplier(
          id: 'supplier',
          name: 'Nombre proveedor nuevo',
          isActive: false,
        ),
      );
      await store.saveCategory(
        const InventoryCategory(
          id: 'category',
          name: 'Categoría nueva',
          isActive: false,
        ),
      );
      final snapshot = await store.load();
      expect(snapshot.products.single.name, 'Nombre nuevo');
      expect(snapshot.receipts.single.supplierName, 'Proveedor sintético');
      expect(
        snapshot.receipts.single.lines.single.productName,
        'Juego sintético',
      );
      expect(snapshot.receipts.single.lines.single.quantity, 3);
      expect(snapshot.receipts.single.lines.single.totalCostMinor, 1001);
      expect(
        () => snapshot.receipts.single.lines.clear(),
        throwsUnsupportedError,
      );
      expect(
        (await app.database.query('purchase_lines')).single['name_snapshot'],
        'Juego sintético',
      );
      expect(snapshot.stock.single.quantity, 3);
      expect(snapshot.stock.single.totalCostMinor, 1001);
    },
  );

  for (final inactive in ['supplier', 'product', 'category']) {
    test('new receipt rejects inactive $inactive', () async {
      await setupCatalog();
      switch (inactive) {
        case 'supplier':
          await store.saveSupplier(
            const InventorySupplier(
              id: 'supplier',
              name: 'Proveedor',
              isActive: false,
            ),
          );
        case 'product':
          await store.saveProduct(
            const CatalogProduct(
              id: 'product',
              name: 'Producto',
              listPriceMinor: 1,
              isActive: false,
            ),
          );
        case 'category':
          await store.saveCategory(
            const InventoryCategory(
              id: 'category',
              name: 'Categoría',
              isActive: false,
            ),
          );
      }
      await expectLater(
        store.receivePurchase(_command()),
        throwsA(isA<InventoryValidationException>()),
      );
      expect(await app.database.query('command_log'), isEmpty);
    });
  }

  test(
    'duplicate SKU is case insensitive and nullable SKU is reusable',
    () async {
      await setupCatalog();
      await expectLater(
        store.saveProduct(
          const CatalogProduct(
            id: 'other',
            name: 'Otro',
            sku: 'sku-01',
            listPriceMinor: 1,
          ),
        ),
        throwsA(isA<InventoryValidationException>()),
      );
      await store.saveProduct(
        const CatalogProduct(id: 'other', name: 'Otro', listPriceMinor: 1),
      );
      await store.saveProduct(
        const CatalogProduct(id: 'third', name: 'Tercero', listPriceMinor: 1),
      );
      expect((await store.load()).products, hasLength(3));
    },
  );

  test('real ISO due date and Bogota date boundary are enforced', () async {
    await setupCatalog();
    for (final invalid in [
      '2026-02-30',
      '2026-13-01',
      '2026-10-17',
      '2026-2-01',
      '0000-01-01',
    ]) {
      await expectLater(
        store.receivePurchase(_command(due: invalid)),
        throwsA(isA<InventoryValidationException>()),
        reason: invalid,
      );
    }
    await store.receivePurchase(_command(due: '2026-10-18'));
    expect((await store.load()).receipts.single.dueDate, '2026-10-18');
  });

  test('quantity cost and receipt total are explicit and bounded', () async {
    await setupCatalog();
    for (final command in [
      _command(quantity: 0),
      _command(quantity: -1),
      _command(cost: -1),
      _command(cost: 0),
      ReceiptCommand(
        commandId: 'empty',
        supplierId: 'supplier',
        lines: [],
        dueDate: '2026-10-19',
        occurredAtUtc: DateTime.utc(2026, 10, 19),
      ),
      ReceiptCommand(
        commandId: 'repeated',
        supplierId: 'supplier',
        lines: [
          const ReceiptLineInput(
            productId: 'product',
            quantity: 1,
            totalCostMinor: 1,
          ),
          const ReceiptLineInput(
            productId: 'product',
            quantity: 2,
            totalCostMinor: 1,
          ),
        ],
        dueDate: '2026-10-19',
        occurredAtUtc: DateTime.utc(2026, 10, 19),
      ),
    ]) {
      await expectLater(
        store.receivePurchase(command),
        throwsA(isA<InventoryValidationException>()),
      );
    }
    expect(await app.database.query('command_log'), isEmpty);
  });

  test(
    'zero cost line stays documented when receipt total is positive',
    () async {
      await setupCatalog();
      await store.saveProduct(
        const CatalogProduct(id: 'free', name: 'Incluido', listPriceMinor: 0),
      );
      await store.receivePurchase(
        ReceiptCommand(
          commandId: 'zero-line',
          supplierId: 'supplier',
          lines: [
            const ReceiptLineInput(
              productId: 'free',
              quantity: 1,
              totalCostMinor: 0,
            ),
            const ReceiptLineInput(
              productId: 'product',
              quantity: 1,
              totalCostMinor: 1,
            ),
          ],
          dueDate: '2026-10-19',
          occurredAtUtc: DateTime.utc(2026, 10, 19),
        ),
      );
      final freeLayer = (await app.database.query(
        'cost_layers',
        where: 'product_id = ?',
        whereArgs: ['free'],
      )).single;
      expect(freeLayer['total_cost_minor'], 0);
      expect(freeLayer['cost_quality'], 'documented');
    },
  );

  test(
    'BigInt detects receipt sum and resulting valuation overflow before commit',
    () async {
      await setupCatalog();
      await store.saveProduct(
        const CatalogProduct(id: 'other', name: 'Otro', listPriceMinor: 0),
      );
      final max = Money.maxMinorUnits.toInt();
      await expectLater(
        store.receivePurchase(
          ReceiptCommand(
            commandId: 'overflow',
            supplierId: 'supplier',
            lines: [
              ReceiptLineInput(
                productId: 'product',
                quantity: 1,
                totalCostMinor: max,
              ),
              const ReceiptLineInput(
                productId: 'other',
                quantity: 1,
                totalCostMinor: 1,
              ),
            ],
            dueDate: '2026-10-19',
            occurredAtUtc: DateTime.utc(2026, 10, 19),
          ),
        ),
        throwsA(isA<InventoryValidationException>()),
      );
      expect(await app.database.query('command_log'), isEmpty);
      await store.receivePurchase(_command(cost: max, quantity: 1));
      await expectLater(
        store.receivePurchase(_command(id: 'next', cost: 1)),
        throwsA(isA<InventoryValidationException>()),
      );
      expect((await store.load()).stock.single.totalCostMinor, max);
      expect(await app.database.query('purchases'), hasLength(1));
    },
  );

  test('BigInt detects accumulated quantity overflow', () async {
    await setupCatalog();
    await store.receivePurchase(
      _command(quantity: Money.maxMinorUnits.toInt(), cost: 1),
    );
    await expectLater(
      store.receivePurchase(_command(id: 'next', quantity: 1, cost: 1)),
      throwsA(isA<InventoryValidationException>()),
    );
    expect(
      (await store.load()).stock.single.quantity,
      Money.maxMinorUnits.toInt(),
    );
  });

  test('concurrent identical retries serialize to one receipt', () async {
    await setupCatalog();
    final results = await Future.wait([
      store.receivePurchase(_command()),
      store.receivePurchase(_command()),
    ]);
    expect(results.first.documentId, results.last.documentId);
    expect((await store.load()).stock.single.quantity, 3);
    expect(await app.database.query('command_log'), hasLength(1));
  });

  test(
    'two file connections converge on one receipt for the same command',
    () async {
      final root = Directory(
        p.join(Directory.current.path, 'tmp', 'inventory_tests'),
      );
      await root.create(recursive: true);
      final fixture = await root.createTemp('concurrent_');
      final file = p.join(fixture.path, 'inventory.sqlite3');
      final first = await AppDatabase.open(path: file);
      await _profile(first);
      final firstStore = SqliteInventoryStore(first, synthetic: true);
      await firstStore.saveSupplier(
        const InventorySupplier(id: 'supplier', name: 'Proveedor sintético'),
      );
      await firstStore.saveProduct(
        const CatalogProduct(
          id: 'product',
          name: 'Producto sintético',
          listPriceMinor: 5,
        ),
      );
      final second = await AppDatabase.open(path: file);
      try {
        final secondStore = SqliteInventoryStore(second, synthetic: true);
        Future<Object> receiveAttempt(SqliteInventoryStore target) async {
          try {
            return await target.receivePurchase(_command());
          } on DatabaseException catch (error) {
            // SQLite FFI can serialize both connections in one isolate. Wait
            // until both attempts settle before retrying a blocked connection.
            if (!error.isDatabaseClosedError() &&
                (error.toString().contains('locked') ||
                    error.toString().contains('busy'))) {
              return error;
            }
            rethrow;
          }
        }

        final attempts = await Future.wait([
          receiveAttempt(firstStore),
          receiveAttempt(secondStore),
        ]);
        final outcomes = <ReceiptResult>[];
        for (var index = 0; index < attempts.length; index++) {
          final attempt = attempts[index];
          outcomes.add(
            attempt is ReceiptResult
                ? attempt
                : await (index == 0 ? firstStore : secondStore).receivePurchase(
                    _command(),
                  ),
          );
        }
        expect(outcomes.first.documentId, outcomes.last.documentId);
        expect((await firstStore.load()).stock.single.quantity, 3);
        for (final table in [
          'command_log',
          'business_documents',
          'purchases',
          'inventory_movements',
          'cost_layers',
          'obligations',
          'journal_entries',
        ]) {
          expect(
            await first.database.query(table),
            hasLength(1),
            reason: table,
          );
        }
        expect(
          (await first.database.query(
            'business_documents',
          )).single['source_kind'],
          'synthetic',
        );
      } finally {
        await second.close();
        await first.close();
        final canonicalRoot = await root.resolveSymbolicLinks();
        final canonicalFixture = await fixture.resolveSymbolicLinks();
        if (!p.isWithin(canonicalRoot, canonicalFixture)) {
          throw StateError('Unsafe test fixture cleanup');
        }
        await Directory(canonicalFixture).delete(recursive: true);
      }
    },
  );

  test('file reopen preserves receipt and idempotent response', () async {
    final root = Directory(
      p.join(Directory.current.path, 'tmp', 'inventory_tests'),
    );
    await root.create(recursive: true);
    final fixture = await root.createTemp('fixture_');
    final file = p.join(fixture.path, 'inventory.sqlite3');
    final first = await AppDatabase.open(path: file);
    await _profile(first);
    final firstStore = SqliteInventoryStore(first);
    await firstStore.saveSupplier(
      const InventorySupplier(id: 'supplier', name: 'Proveedor sintético'),
    );
    await firstStore.saveProduct(
      const CatalogProduct(
        id: 'product',
        name: 'Producto sintético',
        listPriceMinor: 5,
      ),
    );
    final result = await firstStore.receivePurchase(_command());
    await first.close();
    final reopened = await AppDatabase.open(path: file);
    try {
      final secondStore = SqliteInventoryStore(reopened);
      final retry = await secondStore.receivePurchase(_command());
      expect(retry.documentId, result.documentId);
      expect((await secondStore.load()).stock.single.quantity, 3);
      expect((await reopened.readHealth())['integrityOk'], isTrue);
    } finally {
      await reopened.close();
      final canonicalRoot = await root.resolveSymbolicLinks();
      final canonicalFixture = await fixture.resolveSymbolicLinks();
      if (!p.isWithin(canonicalRoot, canonicalFixture)) {
        throw StateError('Unsafe test fixture cleanup');
      }
      await Directory(canonicalFixture).delete(recursive: true);
    }
  });
}

ReceiptCommand _command({
  String id = 'receipt-command',
  int cost = 1001,
  int quantity = 3,
  String due = '2026-10-19',
}) => ReceiptCommand(
  commandId: id,
  supplierId: 'supplier',
  lines: [
    ReceiptLineInput(
      productId: 'product',
      quantity: quantity,
      totalCostMinor: cost,
    ),
  ],
  reference: 'FAC-01',
  dueDate: due,
  occurredAtUtc: DateTime.utc(2026, 10, 19, 2),
);

Future<void> _profile(AppDatabase app) =>
    SqliteWorkspaceStore(app).createProfile(
      BusinessProfile(
        profileId: 'inventory-test',
        businessName: 'Ludoteca sintética',
        currencyCode: 'COP',
        moneyScale: 2,
        timezone: 'America/Bogota',
        createdAtUtc: DateTime.utc(2026, 10, 19),
      ),
    );
