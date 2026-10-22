import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/features/debtors/data/sqlite_debtors_store.dart';
import 'package:valinor_sanctum_2/features/debtors/domain/debtors_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_opening_store.dart';
import 'package:valinor_sanctum_2/features/treasury/domain/treasury_opening.dart';
import 'package:valinor_sanctum_2/features/workspace/data/sqlite_workspace_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/data/sqlite_quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/collections/data/sqlite_collections_store.dart';
import 'package:valinor_sanctum_2/features/collections/domain/collections_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase app;
  late SqliteDebtorsStore store;
  late SqliteQuickSalesStore quick;
  final at = DateTime.utc(2026, 10, 21, 18);
  setUp(() async {
    app = await AppDatabase.open(path: inMemoryDatabasePath);
    await SqliteWorkspaceStore(app).createProfile(
      BusinessProfile(
        profileId: 'debtors-test',
        businessName: 'Tienda sintética',
        currencyCode: 'COP',
        moneyScale: 2,
        timezone: 'America/Bogota',
        createdAtUtc: at,
      ),
    );
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
        receivablesMinor: 30000,
        sourceMetadata: const {'sourceName': 'synthetic'},
      ),
    );
    store = SqliteDebtorsStore(app, synthetic: true);
    quick = SqliteQuickSalesStore(app, synthetic: true);
  });
  tearDown(() => app.close());
  Future<String> run(DebtorCommand c) async {
    await store.prepare(c);
    return store.confirm(c.commandId);
  }

  Future<String> person(
    String name, {
    int amount = 0,
    PreviousDebtSource? source,
  }) => run(
    DebtorCommand(
      commandId: 'create-$name',
      kind: 'create',
      name: name,
      amountMinor: amount,
      previousSource: source,
      occurredAtUtc: at,
    ),
  );
  Future<void> pay(
    String id,
    int amount, {
    String command = 'pay',
    String option = 'quick-default:EFECTIVO',
  }) async {
    await run(
      DebtorCommand(
        commandId: command,
        kind: 'payment',
        debtorId: id,
        amountMinor: amount,
        paymentOptionId: option,
        occurredAtUtc: at.add(const Duration(hours: 1)),
      ),
    );
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

  Future<void> stock() async {
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
        commandId: 'stock',
        supplierId: 'supplier',
        occurredAtUtc: at.subtract(const Duration(hours: 3)),
        dueDate: '2026-10-21',
        lines: const [
          ReceiptLineInput(
            productId: 'product',
            quantity: 10,
            totalCostMinor: 1000,
          ),
        ],
      ),
    );
  }

  Future<void> sale(
    String id,
    String? debtor, {
    int qty = 1,
    bool mixed = false,
  }) async {
    final account = await quick.saveAccount(
      SaveQuickSaleAccount(
        id: id,
        label: 'Cuenta $id',
        expectedRevision: 0,
        debtorId: debtor,
        lines: [
          QuickSaleLine(
            id: '$id-debt',
            productId: 'product',
            quantityText: '$qty',
            unitPriceMinor: 10000,
            paymentOptionId: QuickPaymentOption.creditId,
          ),
          if (mixed)
            QuickSaleLine(
              id: '$id-cash',
              productId: 'product',
              quantityText: '1',
              unitPriceMinor: 10000,
              paymentOptionId: 'quick-default:EFECTIVO',
            ),
        ],
      ),
    );
    await quick.prepareSale(
      commandId: 'sale-$id',
      accountId: id,
      expectedRevision: account.revision,
      occurredAtUtc: at.add(Duration(minutes: id == 'b' ? 21 : 20)),
    );
    await quick.confirmPrepared('sale-$id');
  }

  test(
    'registered person starts at zero without money or debt facts',
    () async {
      final before = (await SqliteTreasuryStore(app).load());
      final id = await person('Ana');
      final data = await store.load();
      expect(data.debtors.single.id, id);
      expect(data.debtors.single.balanceMinor, 0);
      expect(await app.database.query('debtor_openings'), isEmpty);
      expect(
        (await SqliteTreasuryStore(app).load()).receivablesMinor,
        before.receivablesMinor,
      );
      final after = await snapshot();
      expect(await store.confirm('create-Ana'), id);
      expect(await snapshot(), after);
    },
  );
  test(
    'legacy debt assignment preserves total and additional debt increases only declared receivables',
    () async {
      final id = await person(
        'Ana',
        amount: 20000,
        source: PreviousDebtSource.includedInLegacy,
      );
      var data = await store.load();
      expect(data.unassignedLegacyMinor, 10000);
      expect(data.debtors.single.balanceMinor, 20000);
      expect((await SqliteTreasuryStore(app).load()).receivablesMinor, 30000);
      await person('Luis', amount: 5000, source: PreviousDebtSource.additional);
      expect((await SqliteTreasuryStore(app).load()).receivablesMinor, 35000);
      expect(await app.database.query('sales'), isEmpty);
      await pay(id, 8000);
      data = await store.load();
      expect(data.debtors.singleWhere((p) => p.id == id).balanceMinor, 12000);
      expect(data.unassignedLegacyMinor, 10000);
      final treasury = await SqliteTreasuryStore(app).load();
      expect(treasury.receivablesMinor, 27000);
      expect(
        treasury.accounts.singleWhere((a) => a.name == 'Caja').balanceMinor,
        108000,
      );
    },
  );
  test(
    'overpayment, duplicate names and excess legacy assignment have no partial effects',
    () async {
      final id = await person(
        'Ana',
        amount: 1000,
        source: PreviousDebtSource.additional,
      );
      for (final c in [
        DebtorCommand(
          commandId: 'over',
          kind: 'payment',
          debtorId: id,
          amountMinor: 1001,
          paymentOptionId: 'quick-default:NEQUI',
          occurredAtUtc: at,
        ),
        DebtorCommand(
          commandId: 'duplicate',
          kind: 'create',
          name: ' ANA ',
          occurredAtUtc: at,
        ),
        DebtorCommand(
          commandId: 'excess',
          kind: 'create',
          name: 'Otro',
          amountMinor: 30001,
          previousSource: PreviousDebtSource.includedInLegacy,
          occurredAtUtc: at,
        ),
      ]) {
        final before = await snapshot();
        await expectLater(
          store.prepare(c),
          throwsA(isA<DebtorsValidationException>()),
        );
        expect(await snapshot(), before);
      }
    },
  );
  test(
    'one registered person receives mixed-sale debt and one abono spans oldest balances',
    () async {
      await stock();
      final id = await person(
        'Ana',
        amount: 5000,
        source: PreviousDebtSource.additional,
      );
      await sale('a', id, mixed: true);
      await sale('b', id, qty: 2);
      expect((await store.load()).debtors.single.balanceMinor, 35000);
      expect((await app.database.query('debtor_receivables')).length, 3);
      expect((await quick.load()).accounts, isEmpty);
      expect(
        (await app.database.query('quick_sale_requests')).every(
          (r) => jsonDecode(r['canonical_payload'] as String)['version'] == 3,
        ),
        isTrue,
      );
      final beforeStock = await app.database.query('sale_outflows');
      await pay(id, 20000, option: 'quick-default:NEQUI');
      final data = await store.load();
      expect(data.debtors.single.balanceMinor, 15000);
      expect(data.payments, hasLength(1));
      expect(data.payments.single.displayPaymentLabel, 'Transferencia');
      expect(
        (await app.database.query('debtor_payment_allocations')).length,
        3,
      );
      expect(await app.database.query('sale_outflows'), beforeStock);
      final after = await snapshot();
      await store.confirm('pay');
      expect(await snapshot(), after);
      expect(
        (await SqliteTreasuryStore(
          app,
        ).load()).accounts.singleWhere((a) => a.name == 'Nequi').balanceMinor,
        70000,
      );
    },
  );
  test(
    'free text cannot replace selection and blocked people still accept abonos',
    () async {
      await stock();
      await expectLater(
        sale('missing', null),
        throwsA(isA<QuickSalesValidationException>()),
      );
      final id = await person(
        'Ana',
        amount: 1000,
        source: PreviousDebtSource.additional,
      );
      await store.setActive(id, false);
      await expectLater(
        sale('blocked', id),
        throwsA(isA<QuickSalesValidationException>()),
      );
      await pay(id, 1000);
      expect((await store.load()).debtors.single.balanceMinor, 0);
    },
  );
  test(
    'legacy collection adapter includes person abonos when checking a sale remaining balance',
    () async {
      await stock();
      final id = await person('Ana');
      await sale('a', id);
      await pay(id, 4000);
      final collections = SqliteCollectionsStore(app, synthetic: true);
      final option = (await app.database.query(
        'quick_payment_options',
        where: 'id=?',
        whereArgs: ['quick-default:EFECTIVO'],
      )).single;
      final receivable = (await app.database.query(
        'customer_receivables',
      )).single;
      await collections.prepareCollection(
        CollectionCommand(
          commandId: 'old-collection',
          receivableId: receivable['id'] as String,
          occurredAtUtc: at.add(const Duration(hours: 2)),
          parts: [
            CollectionPartInput(
              cashAccountId: option['cash_account_id'] as String,
              paymentMethodId: option['payment_method_id'] as String,
              amountMinor: 6000,
            ),
          ],
        ),
      );
      await collections.confirmPrepared('old-collection');
      expect((await store.load()).debtors.single.balanceMinor, 0);
      expect((await app.database.query('sales')).length, 1);
    },
  );
  test(
    'opening after registration is unique and preserves imported total',
    () async {
      final id = await person('Ana');
      await run(
        DebtorCommand(
          commandId: 'opening',
          kind: 'opening',
          debtorId: id,
          amountMinor: 12000,
          previousSource: PreviousDebtSource.includedInLegacy,
          occurredAtUtc: at,
        ),
      );
      expect((await store.load()).debtors.single.balanceMinor, 12000);
      expect((await store.load()).unassignedLegacyMinor, 18000);
      expect((await SqliteTreasuryStore(app).load()).receivablesMinor, 30000);
      final before = await snapshot();
      await expectLater(
        store.prepare(
          DebtorCommand(
            commandId: 'repeat-opening',
            kind: 'opening',
            debtorId: id,
            amountMinor: 1,
            previousSource: PreviousDebtSource.additional,
            occurredAtUtc: at,
          ),
        ),
        throwsA(isA<DebtorsValidationException>()),
      );
      expect(await snapshot(), before);
    },
  );
  test(
    'concurrent prepared abonos cannot overpay changed allocations',
    () async {
      final id = await person(
        'Ana',
        amount: 1000,
        source: PreviousDebtSource.additional,
      );
      for (final command in ['first', 'second']) {
        await store.prepare(
          DebtorCommand(
            commandId: command,
            kind: 'payment',
            debtorId: id,
            amountMinor: 800,
            paymentOptionId: 'quick-default:EFECTIVO',
            occurredAtUtc: at.add(const Duration(hours: 1)),
          ),
        );
      }
      await store.confirm('first');
      final before = await snapshot();
      await expectLater(
        store.confirm('second'),
        throwsA(isA<DebtorsValidationException>()),
      );
      expect(await snapshot(), before);
      expect((await store.load()).debtors.single.balanceMinor, 200);
      await store.discard('second');
      expect((await store.load()).pending, isEmpty);
    },
  );
  test(
    'journal failure rolls back whole payment and permits exact retry',
    () async {
      final id = await person(
        'Ana',
        amount: 1000,
        source: PreviousDebtSource.additional,
      );
      await store.prepare(
        DebtorCommand(
          commandId: 'abono',
          kind: 'payment',
          debtorId: id,
          amountMinor: 400,
          paymentOptionId: 'quick-default:NEQUI',
          occurredAtUtc: at.add(const Duration(hours: 1)),
        ),
      );
      await app.database.execute(
        "CREATE TRIGGER synthetic_failure BEFORE INSERT ON journal_lines BEGIN SELECT RAISE(ABORT,'synthetic'); END",
      );
      final before = await snapshot();
      await expectLater(
        store.confirm('abono'),
        throwsA(isA<DatabaseException>()),
      );
      expect(await snapshot(), before);
      await app.database.execute('DROP TRIGGER synthetic_failure');
      await store.confirm('abono');
      expect((await store.load()).debtors.single.balanceMinor, 600);
      expect(await app.database.query('debtor_payments'), hasLength(1));
    },
  );
  test(
    'posted financial facts and journal resist mutations and replacements',
    () async {
      final id = await person(
        'Ana',
        amount: 1000,
        source: PreviousDebtSource.additional,
      );
      await pay(id, 400);
      for (final table in [
        'debtor_openings',
        'debtor_receivables',
        'debtor_payments',
        'debtor_payment_allocations',
      ]) {
        final row = (await app.database.query(table)).first;
        await expectLater(
          app.database.delete(table),
          throwsA(isA<DatabaseException>()),
        );
        await expectLater(
          app.database.update(table, row),
          throwsA(isA<DatabaseException>()),
        );
        await expectLater(
          app.database.insert(
            table,
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          ),
          throwsA(isA<DatabaseException>()),
        );
      }
      final doc = (await app.database.query(
        'debtor_payments',
      )).single['document_id'];
      final entry = (await app.database.query(
        'journal_entries',
        where: 'document_id=?',
        whereArgs: [doc],
      )).single;
      await expectLater(
        app.database.delete(
          'journal_lines',
          where: 'entry_id=?',
          whereArgs: [entry['id']],
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(await app.database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      expect(
        (await app.database.rawQuery(
          'PRAGMA integrity_check',
        )).single.values.single,
        'ok',
      );
    },
  );
  test(
    'changed destination metadata invalidates prepared cash snapshot',
    () async {
      final id = await person(
        'Ana',
        amount: 1000,
        source: PreviousDebtSource.additional,
      );
      await store.prepare(
        DebtorCommand(
          commandId: 'abono',
          kind: 'payment',
          debtorId: id,
          amountMinor: 400,
          paymentOptionId: 'quick-default:NEQUI',
          occurredAtUtc: at.add(const Duration(hours: 1)),
        ),
      );
      final option = (await app.database.query(
        'quick_payment_options',
        where: "id='quick-default:NEQUI'",
      )).single;
      await app.database.update(
        'cash_accounts',
        {'name': 'Cuenta renombrada'},
        where: 'id=?',
        whereArgs: [option['cash_account_id']],
      );
      final before = await snapshot();
      await expectLater(
        store.confirm('abono'),
        throwsA(isA<DebtorsValidationException>()),
      );
      expect(await snapshot(), before);
    },
  );
}
