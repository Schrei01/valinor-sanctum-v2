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
import 'package:valinor_sanctum_2/features/supplier_payments/data/sqlite_supplier_payments_store.dart';
import 'package:valinor_sanctum_2/features/supplier_payments/domain/supplier_payments_store.dart';
import 'package:valinor_sanctum_2/features/workspace/data/sqlite_workspace_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase app;
  late SqliteSupplierPaymentsStore payments;
  setUp(() async {
    app = await AppDatabase.open(path: inMemoryDatabasePath);
    payments = SqliteSupplierPaymentsStore(app, synthetic: true);
  });
  tearDown(() => app.close());

  Future<PayableSummary> setup({int debt = 10000, int funds = 15000}) async {
    await _fixture(app, debt: debt, funds: funds);
    return (await payments.load()).payables.single;
  }

  Future<PreparedSupplierPayment> prepare(
    String id,
    String payable,
    int amount, {
    DateTime? at,
    List<SupplierPaymentPartInput>? parts,
  }) => payments.preparePayment(
    SupplierPaymentCommand(
      commandId: id,
      payableId: payable,
      occurredAtUtc: at ?? DateTime.utc(2026, 10, 19, 17),
      parts: parts ?? [_part(amount)],
    ),
  );

  test(
    'partial and final payments settle debt and cash without changing commercial facts',
    () async {
      final payable = await setup();
      final facts = <String, List<Map<String, Object?>>>{};
      for (final table in [
        'purchases',
        'purchase_lines',
        'obligations',
        'inventory_movements',
        'cost_layers',
        'sales',
        'sale_lines',
        'sale_outflows',
        'sale_cost_allocations',
        'customer_receivables',
        'collections',
        'collection_parts',
        'receivable_settlements',
      ]) {
        facts[table] = await app.database.query(table);
      }
      await prepare('pay-40', payable.payableId, 4000);
      final first = await payments.confirmPrepared('pay-40');
      expect(first.remainingMinor, 6000);
      final partial = await payments.load();
      expect(partial.payables.single.paidMinor, 4000);
      expect(partial.accounts.single.balanceMinor, 11000);
      final purchase = (await SqliteInventoryStore(app).load()).receipts.single;
      expect(purchase.paidMinor, 4000);
      expect(purchase.remainingMinor, 6000);
      final lines = await app.database.rawQuery(
        '''
SELECT l.* FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id
WHERE e.document_id = ? ORDER BY l.sequence
''',
        [first.documentId],
      );
      expect(lines, hasLength(2));
      expect(lines.first['account_id'], 'money:cash');
      expect(lines.first['credit_minor'], 4000);
      expect(lines.last['account_id'], 'system:supplier-payable');
      expect(lines.last['debit_minor'], 4000);
      await prepare(
        'pay-60',
        payable.payableId,
        6000,
        at: DateTime.utc(2026, 10, 19, 18),
      );
      expect((await payments.confirmPrepared('pay-60')).remainingMinor, 0);
      final retry = await payments.confirmPrepared('pay-40');
      expect(retry.documentId, first.documentId);
      expect(retry.remainingMinor, 6000);
      final complete = await payments.load();
      expect(complete.payables.single.remainingMinor, 0);
      expect(complete.accounts.single.balanceMinor, 5000);
      expect(complete.pendingPayments, isEmpty);
      expect(complete.payments, hasLength(2));
      expect(
        (await SqliteCollectionsStore(app).load()).accounts.single.balanceMinor,
        5000,
      );
      for (final table in facts.keys) {
        expect(await app.database.query(table), facts[table], reason: table);
      }
      await expectLater(prepare('excess', payable.payableId, 1), _rejected);
    },
  );

  test(
    'aggregates different methods using one account before checking funds',
    () async {
      final payable = await setup(debt: 10000, funds: 5000);
      await SqliteCollectionsStore(app).saveMethod(
        const CollectionMethod(id: 'other-method', code: 'OTRO', name: 'Otro'),
      );
      await expectLater(
        prepare(
          'overdraw',
          payable.payableId,
          0,
          parts: [
            _part(3000),
            _part(3000, method: 'other-method'),
          ],
        ),
        _rejected,
      );
      expect(await app.database.query('supplier_payment_requests'), isEmpty);
      await prepare(
        'grouped',
        payable.payableId,
        0,
        parts: [
          _part(2000),
          _part(3000, method: 'other-method'),
        ],
      );
      final result = await payments.confirmPrepared('grouped');
      final rows = await app.database.rawQuery(
        '''
SELECT l.* FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id
WHERE e.document_id = ? AND l.account_id = 'money:cash'
''',
        [result.documentId],
      );
      expect(rows.single['credit_minor'], 5000);
      expect((await payments.load()).accounts.single.balanceMinor, 0);
    },
  );

  test(
    'revalidates funds after another prepared request commits and permits safe discard',
    () async {
      final payable = await setup(debt: 12000, funds: 6000);
      await prepare('winner', payable.payableId, 4000);
      await prepare('stale', payable.payableId, 4000);
      await payments.confirmPrepared('winner');
      await expectLater(payments.confirmPrepared('stale'), _rejected);
      var state = await payments.load();
      expect(state.pendingPayments.single.status, 'rejected');
      expect(state.payables.single.remainingMinor, 8000);
      expect(state.accounts.single.balanceMinor, 2000);
      expect(state.payments, hasLength(1));
      await payments.discardRejected('stale');
      await payments.discardRejected('stale');
      expect((await payments.load()).pendingPayments, isEmpty);
      await expectLater(payments.confirmPrepared('stale'), _rejected);
      await expectLater(payments.discardRejected('winner'), _rejected);
    },
  );

  test('revalidates obligation after competing full settlement', () async {
    final payable = await setup();
    await prepare('full', payable.payableId, 10000);
    await prepare('stale-debt', payable.payableId, 1);
    await payments.confirmPrepared('full');
    await expectLater(payments.confirmPrepared('stale-debt'), _rejected);
    expect((await payments.load()).payments, hasLength(1));
    expect((await payments.load()).accounts.single.balanceMinor, 5000);
  });

  test(
    'requires active available money accounts and active methods at preparation and commit',
    () async {
      final payable = await setup();
      final catalogs = SqliteCollectionsStore(app);
      await prepare('prepared', payable.payableId, 1000);
      await catalogs.saveAccount(
        const CollectionAccount(
          id: 'cash',
          name: 'Caja sintética',
          kind: 'cash',
          isAvailable: false,
        ),
      );
      await expectLater(
        prepare('unavailable', payable.payableId, 1),
        _rejected,
      );
      await expectLater(payments.confirmPrepared('prepared'), _rejected);
      await catalogs.saveAccount(
        const CollectionAccount(
          id: 'cash',
          name: 'Caja sintética',
          kind: 'cash',
          isActive: false,
        ),
      );
      await expectLater(prepare('inactive', payable.payableId, 1), _rejected);
      await catalogs.saveAccount(
        const CollectionAccount(
          id: 'cash',
          name: 'Caja sintética',
          kind: 'cash',
        ),
      );
      await catalogs.saveMethod(
        const CollectionMethod(
          id: 'cash-method',
          code: 'EFECTIVO',
          name: 'Efectivo',
          isActive: false,
        ),
      );
      await expectLater(
        prepare('inactive-method', payable.payableId, 1),
        _rejected,
      );
      expect((await payments.load()).accounts.single.balanceMinor, 15000);
      expect(await app.database.query('supplier_payments'), isEmpty);
    },
  );

  test(
    'snapshots survive renamed suppliers accounts and methods after prepare',
    () async {
      final payable = await setup();
      await prepare('names', payable.payableId, 1000);
      await SqliteInventoryStore(app).saveSupplier(
        const InventorySupplier(
          id: 'supplier',
          name: 'Proveedor renombrado',
          isActive: false,
        ),
      );
      final catalogs = SqliteCollectionsStore(app);
      await catalogs.saveAccount(
        const CollectionAccount(
          id: 'cash',
          name: 'Caja renombrada',
          kind: 'cash',
        ),
      );
      await catalogs.saveMethod(
        const CollectionMethod(
          id: 'cash-method',
          code: 'EFECTIVO',
          name: 'Medio renombrado',
        ),
      );
      await payments.confirmPrepared('names');
      final history = (await payments.load()).payments.single;
      expect(history.supplierName, 'Proveedor sintético');
      expect(history.label, 'FACTURA-SINTETICA');
      expect(history.parts.single.cashAccountName, 'Caja sintética');
      expect(history.parts.single.paymentMethodName, 'Efectivo');
    },
  );

  test(
    'rejects retroactive purchase payment and all later source account movements',
    () async {
      final payable = await setup();
      await expectLater(
        prepare(
          'before-purchase',
          payable.payableId,
          1,
          at: DateTime.utc(2026, 10, 19, 9),
        ),
        _rejected,
      );
      // Existing receipt is exactly .001; lexical timestamp order must not treat
      // .001001 as earlier, or the .001 instant as later.
      await expectLater(
        prepare(
          'before-receipt',
          payable.payableId,
          1,
          at: DateTime.utc(2026, 10, 19, 16, 0, 0, 0, 999),
        ),
        _rejected,
      );
      await prepare(
        'after-micros',
        payable.payableId,
        1000,
        at: DateTime.utc(2026, 10, 19, 16, 0, 0, 1, 1),
      );
      await payments.confirmPrepared('after-micros');
      await expectLater(
        prepare(
          'before-payment',
          payable.payableId,
          1,
          at: DateTime.utc(2026, 10, 19, 16, 0, 0, 1),
        ),
        _rejected,
      );
    },
  );

  test(
    'same command recovers original input and rejects changed payload or other command IDs',
    () async {
      final payable = await setup();
      final original = await prepare('identity', payable.payableId, 4000);
      expect(
        (await prepare('identity', payable.payableId, 4000)).preparedAtUtc,
        original.preparedAtUtc,
      );
      await expectLater(
        prepare('identity', payable.payableId, 4001),
        _rejected,
      );
      for (final reserved in ['purchase', 'sale', 'funding']) {
        await expectLater(prepare(reserved, payable.payableId, 1), _rejected);
      }
      final collections = SqliteCollectionsStore(app);
      final sales = SqliteSalesStore(app);
      await sales.saveDraft(
        SaveSaleDraft(
          id: 'second-draft',
          label: 'Otra mesa',
          customerName: 'Cliente sintético',
          expectedRevision: 0,
          lines: const [
            SaleDraftLine(productId: 'product', quantity: 1, unitPriceMinor: 1),
          ],
        ),
      );
      await sales.prepareConfirmation(
        commandId: 'second-sale',
        draftId: 'second-draft',
        expectedRevision: 1,
        occurredAtUtc: DateTime.utc(2026, 10, 19, 15),
        dueDate: '2026-10-20',
      );
      await sales.confirmPrepared('second-sale');
      final receivable = (await collections.load()).receivables.singleWhere(
        (r) => r.remainingMinor == 1,
      );
      await collections.prepareCollection(
        CollectionCommand(
          commandId: 'receipt-pending',
          receivableId: receivable.receivableId,
          occurredAtUtc: DateTime.utc(2026, 10, 19, 17),
          parts: const [
            CollectionPartInput(
              cashAccountId: 'cash',
              paymentMethodId: 'cash-method',
              amountMinor: 1,
            ),
          ],
        ),
      );
      await expectLater(
        prepare('receipt-pending', payable.payableId, 1),
        _rejected,
      );
      await expectLater(
        collections.prepareCollection(
          CollectionCommand(
            commandId: 'identity',
            receivableId: receivable.receivableId,
            occurredAtUtc: DateTime.utc(2026, 10, 19, 17),
            parts: const [
              CollectionPartInput(
                cashAccountId: 'cash',
                paymentMethodId: 'cash-method',
                amountMinor: 1,
              ),
            ],
          ),
        ),
        throwsA(isA<CollectionsValidationException>()),
      );
    },
  );

  test(
    'two source accounts create one debit and separate exact credits',
    () async {
      final payable = await setup();
      final collections = SqliteCollectionsStore(app);
      await collections.saveAccount(
        const CollectionAccount(
          id: 'bank',
          name: 'Banco sintético',
          kind: 'bank',
        ),
      );
      final sales = SqliteSalesStore(app);
      await sales.saveDraft(
        SaveSaleDraft(
          id: 'bank-draft',
          label: 'Mesa banco',
          customerName: 'Cliente sintético',
          expectedRevision: 0,
          lines: const [
            SaleDraftLine(
              productId: 'product',
              quantity: 1,
              unitPriceMinor: 2000,
            ),
          ],
        ),
      );
      await sales.prepareConfirmation(
        commandId: 'bank-sale',
        draftId: 'bank-draft',
        expectedRevision: 1,
        occurredAtUtc: DateTime.utc(2026, 10, 19, 15),
        dueDate: '2026-10-20',
      );
      final sale = await sales.confirmPrepared('bank-sale');
      final receivable = (await collections.load()).receivables.singleWhere(
        (row) => row.saleDocumentId == sale.documentId,
      );
      await collections.prepareCollection(
        CollectionCommand(
          commandId: 'bank-funding',
          receivableId: receivable.receivableId,
          occurredAtUtc: DateTime.utc(2026, 10, 19, 16),
          parts: const [
            CollectionPartInput(
              cashAccountId: 'bank',
              paymentMethodId: 'cash-method',
              amountMinor: 2000,
            ),
          ],
        ),
      );
      await collections.confirmPrepared('bank-funding');
      await prepare(
        'two-accounts',
        payable.payableId,
        0,
        parts: [
          _part(4000),
          const SupplierPaymentPartInput(
            cashAccountId: 'bank',
            paymentMethodId: 'cash-method',
            amountMinor: 1000,
          ),
        ],
      );
      final result = await payments.confirmPrepared('two-accounts');
      final lines = await app.database.rawQuery(
        '''
SELECT l.* FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id
WHERE e.document_id = ?
''',
        [result.documentId],
      );
      expect(lines, hasLength(3));
      final state = await payments.load();
      expect(
        state.accounts.singleWhere((a) => a.id == 'cash').balanceMinor,
        11000,
      );
      expect(
        state.accounts.singleWhere((a) => a.id == 'bank').balanceMinor,
        1000,
      );
      expect(state.payables.single.remainingMinor, 5000);
      expect(state.payments.single.parts, hasLength(2));
    },
  );

  test(
    'a later receipt invalidates an older prepared payment without losing funds',
    () async {
      final payable = await setup();
      await prepare('old-prepared', payable.payableId, 1000);
      final collections = SqliteCollectionsStore(app);
      final sales = SqliteSalesStore(app);
      await sales.saveDraft(
        SaveSaleDraft(
          id: 'later-draft',
          label: 'Otra mesa',
          customerName: 'Cliente sintético',
          expectedRevision: 0,
          lines: const [
            SaleDraftLine(productId: 'product', quantity: 1, unitPriceMinor: 1),
          ],
        ),
      );
      await sales.prepareConfirmation(
        commandId: 'later-sale',
        draftId: 'later-draft',
        expectedRevision: 1,
        occurredAtUtc: DateTime.utc(2026, 10, 19, 15),
        dueDate: '2026-10-20',
      );
      final sale = await sales.confirmPrepared('later-sale');
      final receivable = (await collections.load()).receivables.singleWhere(
        (row) => row.saleDocumentId == sale.documentId,
      );
      await collections.prepareCollection(
        CollectionCommand(
          commandId: 'later-receipt',
          receivableId: receivable.receivableId,
          occurredAtUtc: DateTime.utc(2026, 10, 19, 18),
          parts: const [
            CollectionPartInput(
              cashAccountId: 'cash',
              paymentMethodId: 'cash-method',
              amountMinor: 1,
            ),
          ],
        ),
      );
      await collections.confirmPrepared('later-receipt');
      await expectLater(payments.confirmPrepared('old-prepared'), _rejected);
      final state = await payments.load();
      expect(state.accounts.single.balanceMinor, 15001);
      expect(state.payables.single.remainingMinor, 10000);
      expect(state.payments, isEmpty);
      expect(state.pendingPayments.single.status, 'rejected');
    },
  );

  test(
    'storage failure rolls back every business effect and preserves recoverable preparation',
    () async {
      final payable = await setup();
      await prepare('retry', payable.payableId, 4000);
      await app.database.execute('''
CREATE TEMP TRIGGER fail_payment BEFORE INSERT ON payable_settlements
BEGIN SELECT RAISE(ABORT, 'synthetic storage failure'); END
''');
      await expectLater(
        payments.confirmPrepared('retry'),
        throwsA(isA<DatabaseException>()),
      );
      expect(await app.database.query('supplier_payments'), isEmpty);
      expect(await app.database.query('supplier_payment_parts'), isEmpty);
      expect(
        await app.database.query(
          'command_log',
          where: 'id = ?',
          whereArgs: ['retry'],
        ),
        isEmpty,
      );
      expect((await payments.load()).pendingPayments.single.status, 'prepared');
      expect((await payments.load()).accounts.single.balanceMinor, 15000);
      await app.database.execute('DROP TRIGGER fail_payment');
      expect((await payments.confirmPrepared('retry')).remainingMinor, 6000);
    },
  );

  test(
    'exact integer amounts above double precision and full int64 are preserved',
    () async {
      final max = Money.maxMinorUnits.toInt();
      final payable = await setup(debt: max, funds: max);
      await prepare('exact', payable.payableId, max - 1);
      expect((await payments.confirmPrepared('exact')).remainingMinor, 1);
      await prepare('last-one', payable.payableId, 1);
      await payments.confirmPrepared('last-one');
      final state = await payments.load();
      expect(state.accounts.single.balanceMinor, 0);
      expect(state.payables.single.paidMinor, max);
      expect(state.payables.single.remainingMinor, 0);
    },
  );

  test(
    'rejects empty duplicate nonpositive overflow and local dates before persistence',
    () async {
      final payable = await setup();
      for (final parts in <List<SupplierPaymentPartInput>>[
        [],
        [_part(0)],
        [_part(-1)],
        [_part(1), _part(1)],
        [_part(Money.maxMinorUnits.toInt()), _part(1, method: 'other')],
      ]) {
        await expectLater(
          prepare('invalid', payable.payableId, 0, parts: parts),
          _rejected,
        );
      }
      await expectLater(
        prepare('local', payable.payableId, 1, at: DateTime(2026, 10, 19, 17)),
        _rejected,
      );
      expect(await app.database.query('supplier_payment_requests'), isEmpty);
    },
  );

  test(
    'large historical gross cash flows retain a representable live balance',
    () async {
      final max = Money.maxMinorUnits.toInt();
      final payable = await setup(debt: max, funds: max);
      await prepare('drain', payable.payableId, max);
      await payments.confirmPrepared('drain');
      final inventory = SqliteInventoryStore(app);
      await inventory.receivePurchase(
        ReceiptCommand(
          commandId: 'new-purchase',
          supplierId: 'supplier',
          occurredAtUtc: DateTime.utc(2026, 10, 19, 18),
          dueDate: '2026-10-20',
          lines: const [
            ReceiptLineInput(
              productId: 'product',
              quantity: 1,
              totalCostMinor: 1,
            ),
          ],
        ),
      );
      final sales = SqliteSalesStore(app);
      await sales.saveDraft(
        SaveSaleDraft(
          id: 'new-draft',
          label: 'Segunda venta',
          customerName: 'Cliente sintético',
          expectedRevision: 0,
          lines: [
            SaleDraftLine(
              productId: 'product',
              quantity: 1,
              unitPriceMinor: max,
            ),
          ],
        ),
      );
      await sales.prepareConfirmation(
        commandId: 'new-sale',
        draftId: 'new-draft',
        expectedRevision: 1,
        occurredAtUtc: DateTime.utc(2026, 10, 19, 18),
        dueDate: '2026-10-20',
      );
      final sale = await sales.confirmPrepared('new-sale');
      final collections = SqliteCollectionsStore(app);
      final receivable = (await collections.load()).receivables.singleWhere(
        (row) => row.saleDocumentId == sale.documentId,
      );
      await collections.prepareCollection(
        CollectionCommand(
          commandId: 'new-funding',
          receivableId: receivable.receivableId,
          occurredAtUtc: DateTime.utc(2026, 10, 19, 19),
          parts: [
            CollectionPartInput(
              cashAccountId: 'cash',
              paymentMethodId: 'cash-method',
              amountMinor: max,
            ),
          ],
        ),
      );
      await collections.confirmPrepared('new-funding');
      final next = (await payments.load()).payables.singleWhere(
        (row) => row.remainingMinor == 1,
      );
      await prepare(
        'pay-again',
        next.payableId,
        1,
        at: DateTime.utc(2026, 10, 19, 20),
      );
      await payments.confirmPrepared('pay-again');
      expect((await payments.load()).accounts.single.balanceMinor, max - 1);
      expect(
        (await payments.load()).payables.every(
          (row) => row.remainingMinor == 0,
        ),
        isTrue,
      );
    },
  );

  test(
    'prepared and committed payment recover after closing independent file',
    () async {
      final root = Directory(p.absolute('tmp', 'test-supplier-payments'));
      await root.create(recursive: true);
      final dir = await root.createTemp('recovery-');
      final path = p.join(dir.path, 'synthetic.sqlite3');
      AppDatabase? disk = await AppDatabase.open(path: path);
      try {
        await _fixture(disk);
        var store = SqliteSupplierPaymentsStore(disk);
        final payable = (await store.load()).payables.single;
        await store.preparePayment(
          SupplierPaymentCommand(
            commandId: 'persistent',
            payableId: payable.payableId,
            occurredAtUtc: DateTime.utc(2026, 10, 19, 17),
            parts: [_part(4000)],
          ),
        );
        await disk.close();
        disk = await AppDatabase.open(path: path);
        store = SqliteSupplierPaymentsStore(disk);
        expect((await store.load()).pendingPayments.single.totalMinor, 4000);
        final result = await store.confirmPrepared('persistent');
        await disk.close();
        disk = await AppDatabase.open(path: path);
        store = SqliteSupplierPaymentsStore(disk);
        expect(
          (await store.confirmPrepared('persistent')).documentId,
          result.documentId,
        );
        expect((await store.load()).payables.single.remainingMinor, 6000);
        expect((await store.load()).accounts.single.balanceMinor, 11000);
        expect((await disk.readHealth())['integrityOk'], isTrue);
      } finally {
        await disk?.close();
        final resolved = await dir.resolveSymbolicLinks();
        if (!p.isWithin(await root.resolveSymbolicLinks(), resolved)) {
          throw StateError('Unsafe fixture path');
        }
        await Directory(resolved).delete(recursive: true);
      }
    },
  );
}

final _rejected = throwsA(isA<SupplierPaymentsValidationException>());

SupplierPaymentPartInput _part(int amount, {String method = 'cash-method'}) =>
    SupplierPaymentPartInput(
      cashAccountId: 'cash',
      paymentMethodId: method,
      amountMinor: amount,
    );

Future<void> _fixture(
  AppDatabase app, {
  int debt = 10000,
  int funds = 15000,
}) async {
  await SqliteWorkspaceStore(app).createProfile(
    BusinessProfile(
      profileId: 'supplier-payments-test',
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
    CatalogProduct(
      id: 'product',
      name: 'Producto sintético',
      listPriceMinor: funds,
    ),
  );
  await inventory.saveProduct(
    const CatalogProduct(
      id: 'stock',
      name: 'Inventario pendiente',
      listPriceMinor: 1,
    ),
  );
  await inventory.receivePurchase(
    ReceiptCommand(
      commandId: 'purchase',
      supplierId: 'supplier',
      reference: 'FACTURA-SINTETICA',
      occurredAtUtc: DateTime.utc(2026, 10, 19, 10),
      dueDate: '2026-10-20',
      lines: [
        const ReceiptLineInput(
          productId: 'product',
          quantity: 3,
          totalCostMinor: 0,
        ),
        ReceiptLineInput(productId: 'stock', quantity: 1, totalCostMinor: debt),
      ],
    ),
  );
  final sales = SqliteSalesStore(app);
  await sales.saveDraft(
    SaveSaleDraft(
      id: 'draft',
      label: 'Mesa sintética',
      customerName: 'Cliente sintético',
      expectedRevision: 0,
      lines: [
        SaleDraftLine(productId: 'product', quantity: 1, unitPriceMinor: funds),
      ],
    ),
  );
  final draft = (await sales.load()).drafts.single;
  await sales.prepareConfirmation(
    commandId: 'sale',
    draftId: 'draft',
    expectedRevision: draft.revision,
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
  final receivable = (await collections.load()).receivables.single;
  await collections.prepareCollection(
    CollectionCommand(
      commandId: 'funding',
      receivableId: receivable.receivableId,
      occurredAtUtc: DateTime.utc(2026, 10, 19, 16, 0, 0, 1),
      parts: [
        CollectionPartInput(
          cashAccountId: 'cash',
          paymentMethodId: 'cash-method',
          amountMinor: funds,
        ),
      ],
    ),
  );
  await collections.confirmPrepared('funding');
}
