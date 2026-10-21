import 'dart:convert';
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
import 'package:valinor_sanctum_2/features/quick_sales/data/sqlite_quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/sales/data/sqlite_sales_store.dart';
import 'package:valinor_sanctum_2/features/sales/domain/sales_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_opening_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_store.dart';
import 'package:valinor_sanctum_2/features/treasury/domain/treasury_opening.dart';
import 'package:valinor_sanctum_2/features/workspace/data/sqlite_workspace_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase app;
  late SqliteQuickSalesStore quick;
  final at = DateTime.utc(2026, 10, 19, 16);

  setUp(() async {
    app = await AppDatabase.open(path: inMemoryDatabasePath);
    await _fixture(app);
    quick = SqliteQuickSalesStore(app, synthetic: true);
    await quick.ensureDefaults();
  });
  tearDown(() => app.close());

  QuickSaleLine line(
    String id, {
    int quantity = 1,
    int price = 10000,
    String payment = QuickPaymentOption.creditId,
    String product = 'product',
  }) => QuickSaleLine(
    id: id,
    productId: product,
    quantityText: '$quantity',
    unitPriceMinor: price,
    paymentOptionId: payment,
  );

  Future<QuickSaleAccount> save(
    String id,
    List<QuickSaleLine> lines, {
    String customer = 'Cliente sintético',
    int revision = 0,
  }) => quick.saveAccount(
    SaveQuickSaleAccount(
      id: id,
      label: 'Cuenta $id',
      customerName: customer,
      expectedRevision: revision,
      lines: lines,
    ),
  );

  Future<PreparedQuickSale> prepare(String command, String id) =>
      quick.prepareSale(
        commandId: command,
        accountId: id,
        expectedRevision: 1,
        occurredAtUtc: at,
      );

  Future<int> count(String table) async =>
      (await app.database.query(table)).length;

  Future<void> addFreeProduct() async {
    final inventory = SqliteInventoryStore(app, synthetic: true);
    await inventory.saveProduct(
      const CatalogProduct(
        id: 'gift',
        name: 'Regalo sintético',
        listPriceMinor: 0,
      ),
    );
    await inventory.receivePurchase(
      ReceiptCommand(
        commandId: 'gift-stock',
        supplierId: 'supplier',
        occurredAtUtc: DateTime.utc(2026, 10, 19, 11),
        dueDate: '2026-10-20',
        lines: const [
          ReceiptLineInput(productId: 'gift', quantity: 1, totalCostMinor: 1),
        ],
      ),
    );
  }

  test('credit is a virtual tender and creates no monetary identity', () async {
    await quick.ensureDefaults();
    final options = (await quick.load()).paymentOptions;
    expect(options.map((o) => o.label), ['Efectivo', 'Nequi', 'Deudas']);
    final credit = options.singleWhere((o) => o.isCredit);
    expect(credit.id, QuickPaymentOption.creditId);
    expect(credit.cashAccountId, isEmpty);
    expect(credit.paymentMethodId, isEmpty);
    expect(await count('quick_payment_options'), 2);
    expect(await count('cash_accounts'), 2);
    expect(await count('payment_methods'), 2);
    expect(await count('collections'), 0);
  });

  test(
    'customer and credit mode persist and participate in save CAS',
    () async {
      final first = await save('a', [line('a1')], customer: '  Ana  ');
      expect(first.customerName, 'Ana');
      expect((await save('a', [line('a1')], customer: 'Ana')).revision, 1);
      final row = (await app.database.query('quick_sales_lines')).single;
      expect(row['is_credit'], 1);
      expect(row['payment_option_id'], isNull);
      final loaded = (await quick.load()).accounts.single;
      expect(loaded.customerName, 'Ana');
      expect(loaded.lines.single.paymentOptionId, QuickPaymentOption.creditId);
      await expectLater(
        save('a', [line('a1')], customer: 'Otra persona'),
        throwsA(isA<QuickSalesValidationException>()),
      );
      final updated = await save(
        'a',
        [line('a1')],
        customer: 'Eva',
        revision: 1,
      );
      expect(updated.revision, 2);
      expect(updated.customerName, 'Eva');
    },
  );

  test(
    'credit requires an explicit customer and rejects invalid names',
    () async {
      await save('blank', [line('blank1')], customer: '   ');
      await expectLater(
        prepare('blank-command', 'blank'),
        throwsA(isA<QuickSalesValidationException>()),
      );
      for (final name in ['A\nB', 'A\u007fB', List.filled(121, 'x').join()]) {
        await expectLater(
          save('invalid', [line('invalid1')], customer: name),
          throwsA(isA<QuickSalesValidationException>()),
        );
      }
      expect(await count('quick_sale_requests'), 0);
      expect(await count('sales'), 0);
    },
  );

  test(
    'all credit posts FIFO cost and PVP debt without collecting money',
    () async {
      await save('a', [line('a1', quantity: 2)], customer: 'Ana');
      final pending = await prepare('credit', 'a');
      expect(pending.creditMinor, 20000);
      expect(pending.customerName, 'Ana');
      expect(await count('sales'), 0);
      expect((await quick.load()).stock.single.quantity, 10);
      final result = await quick.confirmPrepared('credit');
      expect(result.totalMinor, 20000);
      expect(result.creditMinor, 20000);
      expect(result.totalCostMinor, 2001);
      expect(result.collectionDocumentId, isNull);
      expect(result.customerName, 'Ana');
      expect(await count('collections'), 0);
      expect(await count('collection_requests'), 0);
      expect(await count('receivable_settlements'), 0);
      expect(await count('quick_sale_line_payments'), 0);
      final fact = (await app.database.query('quick_sale_line_tenders')).single;
      expect(fact['is_credit'], 1);
      expect(fact['customer_name_snapshot'], 'Ana');
      expect(fact['cash_account_id'], isNull);
      expect(fact['payment_method_id'], isNull);
      expect(fact['collection_document_id'], isNull);
      final snapshot = await quick.load();
      expect(snapshot.stock.single.quantity, 8);
      expect(snapshot.sales.single.lines.single.isCredit, isTrue);
      expect(snapshot.sales.single.lines.single.paymentLabel, 'Deudas');
      final cobros = await SqliteCollectionsStore(app).load();
      expect(cobros.receivables.single.customerName, 'Ana');
      expect(cobros.receivables.single.remainingMinor, 20000);
      expect(cobros.accounts.every((a) => a.balanceMinor == 0), isTrue);
      final treasury = SqliteTreasuryStore(app);
      await treasury.ensureDefaults();
      final balances = await treasury.load();
      expect(balances.receivablesMinor, 20000);
      expect(balances.totalAvailableMinor, 0);
      expect(balances.movements, isEmpty);
    },
  );

  test(
    'mixed account collects paid lines and retains only credit residual',
    () async {
      await save('mixed', [
        line('cash', payment: 'quick-default:EFECTIVO'),
        line('nequi', payment: 'quick-default:NEQUI'),
        line('credit'),
      ]);
      await prepare('mixed-command', 'mixed');
      final result = await quick.confirmPrepared('mixed-command');
      expect(result.totalMinor, 30000);
      expect(result.creditMinor, 10000);
      expect(result.totalCostMinor, 3001);
      expect(result.collectionDocumentId, isNotNull);
      expect(await count('sales'), 1);
      expect(await count('collections'), 1);
      expect(await count('collection_parts'), 2);
      expect(await count('quick_sale_line_payments'), 0);
      final facts = await app.database.query(
        'quick_sale_line_tenders',
        orderBy: 'sequence',
      );
      expect(facts.map((r) => r['is_credit']), [0, 0, 1]);
      expect(facts.last['collection_document_id'], isNull);
      expect(
        facts.first['collection_document_id'],
        result.collectionDocumentId,
      );
      final cobros = await SqliteCollectionsStore(app).load();
      expect(cobros.receivables.single.initialMinor, 30000);
      expect(cobros.receivables.single.remainingMinor, 10000);
      expect(cobros.accounts.map((a) => a.balanceMinor), everyElement(10000));
      final treasury = SqliteTreasuryStore(app);
      await treasury.ensureDefaults();
      final balances = await treasury.load();
      expect(balances.cashMinor, 10000);
      expect(balances.nequiMinor, 10000);
      expect(balances.receivablesMinor, 10000);
      expect(balances.movements, hasLength(2));
      expect(
        balances.movements.map((m) => m.concept),
        everyElement('Venta: Cuenta mixed'),
      );
      final history = (await quick.load()).sales.single;
      expect(history.lines.map((l) => l.paymentLabel), [
        'Efectivo',
        'Nequi',
        'Deudas',
      ]);
    },
  );

  test(
    'Cobros subsequently settles debt without another stock or revenue sale',
    () async {
      await save('a', [line('a1', quantity: 2)], customer: 'Ana');
      await prepare('credit', 'a');
      final first = await quick.confirmPrepared('credit');
      final collections = SqliteCollectionsStore(app, synthetic: true);
      final before = await collections.load();
      final cash = before.accounts.singleWhere((a) => a.kind == 'cash');
      final method = before.methods.singleWhere((m) => m.code == 'EFECTIVO');
      final movements = await app.database.query('inventory_movements');
      final allocations = await app.database.query('sale_cost_allocations');
      await collections.prepareCollection(
        CollectionCommand(
          commandId: 'later-collection',
          receivableId: before.receivables.single.receivableId,
          occurredAtUtc: at.add(const Duration(hours: 1)),
          parts: [
            CollectionPartInput(
              cashAccountId: cash.id,
              paymentMethodId: method.id,
              amountMinor: 20000,
            ),
          ],
        ),
      );
      final paid = await collections.confirmPrepared('later-collection');
      expect(paid.remainingMinor, 0);
      expect(
        (await collections.confirmPrepared('later-collection')).documentId,
        paid.documentId,
      );
      expect(await app.database.query('inventory_movements'), movements);
      expect(await app.database.query('sale_cost_allocations'), allocations);
      expect(await count('sales'), 1);
      expect((await quick.load()).stock.single.quantity, 8);
      expect((await collections.load()).receivables.single.remainingMinor, 0);
      final treasury = SqliteTreasuryStore(app);
      await treasury.ensureDefaults();
      final balances = await treasury.load();
      expect(balances.cashMinor, 20000);
      expect(balances.receivablesMinor, 0);
      expect(balances.movements.single.concept, 'Cobro: Cuenta a · Ana');
      final replay = await quick.confirmPrepared('credit');
      expect(replay.saleDocumentId, first.saleDocumentId);
      expect(
        replay.creditMinor,
        20000,
      ); // Original commit response, not live debt.
    },
  );

  test(
    'all credit with a zero price cash line has facts without a collection',
    () async {
      await addFreeProduct();
      await save('a', [
        line('debt'),
        line(
          'free-cash',
          product: 'gift',
          price: 0,
          payment: 'quick-default:EFECTIVO',
        ),
      ]);
      await prepare('all-credit-free', 'a');
      final result = await quick.confirmPrepared('all-credit-free');
      expect(result.collectionDocumentId, isNull);
      expect(result.creditMinor, 10000);
      expect(await count('collections'), 0);
      final facts = await app.database.query(
        'quick_sale_line_tenders',
        orderBy: 'sequence',
      );
      expect(facts, hasLength(2));
      expect(facts.last['is_credit'], 0);
      expect(facts.last['cash_account_id'], isNotNull);
      expect(facts.last['collection_document_id'], isNull);
      expect(facts.last['total_minor'], 0);
      expect(
        (await quick.load()).sales.single.lines.last.paymentLabel,
        'Efectivo',
      );
    },
  );

  test(
    'zero price credit line selects v2 but leaves no debt after paid sale',
    () async {
      await addFreeProduct();
      await save('a', [
        line('cash', payment: 'quick-default:EFECTIVO'),
        line('free-debt', product: 'gift', price: 0),
      ]);
      await prepare('paid-free-credit', 'a');
      final result = await quick.confirmPrepared('paid-free-credit');
      expect(result.creditMinor, 0);
      expect(result.collectionDocumentId, isNotNull);
      expect(
        (await SqliteCollectionsStore(
          app,
        ).load()).receivables.single.remainingMinor,
        0,
      );
      final facts = await app.database.query(
        'quick_sale_line_tenders',
        orderBy: 'sequence',
      );
      expect(facts.last['is_credit'], 1);
      expect(facts.last['collection_document_id'], isNull);
      expect(facts.last['cash_account_id'], isNull);
    },
  );

  test(
    'unknown failure rolls all child effects back and preserves retry',
    () async {
      await save('a', [
        line('credit'),
        line('cash', payment: 'quick-default:EFECTIVO'),
      ]);
      await prepare('retry', 'a');
      await app.database.execute('''
CREATE TRIGGER synthetic_quick_failure BEFORE UPDATE OF status ON quick_sale_requests
WHEN NEW.command_id='retry' AND NEW.status='confirmed'
BEGIN SELECT RAISE(ABORT, 'synthetic storage interruption'); END
''');
      await expectLater(
        quick.confirmPrepared('retry'),
        throwsA(isA<DatabaseException>()),
      );
      for (final table in [
        'sales',
        'collections',
        'customer_receivables',
        'quick_sale_line_tenders',
      ]) {
        expect(await count(table), 0, reason: table);
      }
      expect((await quick.load()).pendingSales.single.status, 'prepared');
      expect((await quick.load()).stock.single.quantity, 10);
      await app.database.execute('DROP TRIGGER synthetic_quick_failure');
      final first = await quick.confirmPrepared('retry');
      final replay = await quick.confirmPrepared('retry');
      expect(replay.saleDocumentId, first.saleDocumentId);
      expect(replay.collectionDocumentId, first.collectionDocumentId);
      expect(await count('sales'), 1);
      expect(await count('collections'), 1);
      expect(await count('quick_sale_line_tenders'), 2);
    },
  );

  test(
    'competing preparations reject insufficient stock without partial credit',
    () async {
      await save('a', [line('a1', quantity: 6)]);
      await save('b', [line('b1', quantity: 6)]);
      await prepare('first', 'a');
      await prepare('second', 'b');
      await quick.confirmPrepared('first');
      await expectLater(
        quick.confirmPrepared('second'),
        throwsA(isA<QuickSalesValidationException>()),
      );
      expect(await count('sales'), 1);
      expect(await count('collections'), 0);
      expect(await count('quick_sale_line_tenders'), 1);
      final state = await quick.load();
      expect(state.stock.single.quantity, 4);
      expect(state.pendingSales.single.status, 'rejected');
      expect(
        (await SqliteCollectionsStore(
          app,
        ).load()).receivables.single.remainingMinor,
        60000,
      );
      await quick.discardRejected('second');
      expect(
        (await quick.load()).accounts.single.customerName,
        'Cliente sintético',
      );
      expect(
        (await quick.load()).accounts.single.lines.single.paymentOptionId,
        QuickPaymentOption.creditId,
      );
    },
  );

  test(
    'prepared customer and credit selection cannot be edited or cancelled',
    () async {
      await save('a', [line('a1')]);
      await prepare('locked', 'a');
      await expectLater(
        save('a', [line('a1')], customer: 'Otro', revision: 1),
        throwsA(isA<QuickSalesValidationException>()),
      );
      await expectLater(
        quick.cancelAccount(accountId: 'a', expectedRevision: 1),
        throwsA(isA<QuickSalesValidationException>()),
      );
      await expectLater(
        app.database.update(
          'quick_sales_accounts',
          {'customer_name': 'Otro'},
          where: 'id=?',
          whereArgs: ['a'],
        ),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        app.database.update(
          'quick_sales_lines',
          {'is_credit': 0},
          where: 'id=?',
          whereArgs: ['a1'],
        ),
        throwsA(isA<DatabaseException>()),
      );
      await quick.confirmPrepared('locked');
    },
  );

  test(
    'all-credit reservation also protects the unused collection child ID',
    () async {
      await save('a', [line('a1')]);
      await prepare('reserved', 'a');
      final request = (await app.database.query('quick_sale_requests')).single;
      final collections = SqliteCollectionsStore(app);
      final sales = SqliteSalesStore(app);
      for (final id in [
        'reserved',
        request['sale_command_id'] as String,
        request['collection_command_id'] as String,
      ]) {
        await expectLater(
          collections.confirmPrepared(id),
          throwsA(isA<CollectionsValidationException>()),
        );
        await expectLater(
          sales.confirmPrepared(id),
          throwsA(isA<SalesValidationException>()),
        );
        await save('account-$id', [line('line-$id')]);
        await expectLater(
          prepare(id, 'account-$id'),
          throwsA(isA<QuickSalesValidationException>()),
        );
      }
      await quick.confirmPrepared('reserved');
      expect(await count('collections'), 0);
      expect(await count('sales'), 1);
    },
  );

  test(
    'replay survives catalog archive and immutable credit facts reject edits',
    () async {
      await save('a', [line('a1')]);
      await prepare('credit', 'a');
      final first = await quick.confirmPrepared('credit');
      await SqliteInventoryStore(app).saveProduct(
        const CatalogProduct(
          id: 'product',
          name: 'Archivado',
          listPriceMinor: 20000,
          isActive: false,
        ),
      );
      final replay = await quick.confirmPrepared('credit');
      expect(replay.saleDocumentId, first.saleDocumentId);
      expect(replay.creditMinor, first.creditMinor);
      final fact = (await app.database.query('quick_sale_line_tenders')).single;
      await expectLater(
        app.database.update(
          'quick_sale_line_tenders',
          {'total_minor': 1},
          where: 'id=?',
          whereArgs: [fact['id']],
        ),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        app.database.insert(
          'quick_sale_line_tenders',
          fact,
          conflictAlgorithm: ConflictAlgorithm.replace,
        ),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        app.database.delete('quick_sale_line_tenders'),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        (await quick.load()).sales.single.lines.single.productName,
        'Producto sintético',
      );
    },
  );

  test('cash-only uses the exact v1 canonical and result shape', () async {
    await save('cash', [
      line('cash-line', payment: 'quick-default:EFECTIVO'),
    ], customer: 'Nombre opcional');
    await prepare('legacy-cash', 'cash');
    final request = (await app.database.query('quick_sale_requests')).single;
    final option = (await app.database.query(
      'quick_payment_options',
      where: 'id=?',
      whereArgs: ['quick-default:EFECTIVO'],
    )).single;
    final cash = (await app.database.query(
      'cash_accounts',
      where: 'id=?',
      whereArgs: [option['cash_account_id']],
    )).single;
    final method = (await app.database.query(
      'payment_methods',
      where: 'id=?',
      whereArgs: [option['payment_method_id']],
    )).single;
    expect(
      request['canonical_payload'],
      jsonEncode({
        'version': 1,
        'profileId': 'quick-credit-test',
        'currency': 'COP',
        'scale': 2,
        'label': 'Cuenta cash',
        'occurredAtUtc': at.toIso8601String(),
        'totalMinor': 10000,
        'lines': [
          {
            'lineId': 'cash-line',
            'productId': 'product',
            'productName': 'Producto sintético',
            'quantity': 1,
            'unitPriceMinor': 10000,
            'totalMinor': 10000,
            'paymentOptionId': option['id'],
            'paymentOptionLabel': option['label'],
            'cashAccountId': cash['id'],
            'paymentMethodId': method['id'],
            'cashAccountName': cash['name'],
            'cashAccountKind': cash['kind'],
            'paymentMethodCode': method['code'],
            'paymentMethodName': method['name'],
          },
        ],
      }),
    );
    final result = await quick.confirmPrepared('legacy-cash');
    expect(result.creditMinor, 0);
    expect(result.customerName, isEmpty);
    expect(result.collectionDocumentId, isNotNull);
    expect(await count('quick_sale_line_payments'), 1);
    expect(await count('quick_sale_line_tenders'), 0);
    final log = (await app.database.query(
      'command_log',
      where: 'id=?',
      whereArgs: ['legacy-cash'],
    )).single;
    final response =
        jsonDecode(log['response_json'] as String) as Map<String, dynamic>;
    expect((response['result'] as Map).keys, [
      'commandId',
      'saleDocumentId',
      'collectionDocumentId',
      'totalMinor',
      'totalCostMinor',
    ]);
  });

  test(
    'credit capacity checks final residual using exact aggregate arithmetic',
    () async {
      final sales = SqliteSalesStore(app, synthetic: true);
      final half = (Money.maxMinorUnits ~/ BigInt.two).toInt();
      await _largeCredit(sales, 'large-one', half, at);
      await _largeCredit(sales, 'large-two', half, at);
      await save('too-large', [line('overflow', price: 2)]);
      await expectLater(
        prepare('overflow-command', 'too-large'),
        throwsA(isA<QuickSalesValidationException>()),
      );
      expect(await count('quick_sale_requests'), 0);
      // Gross sale adds 2, exceeding aggregate capacity transiently. The paid
      // portion is collected in the same transaction, so final credit adds only 1.
      await save('fits', [
        line('paid', price: 1, payment: 'quick-default:EFECTIVO'),
        line('debt', price: 1),
      ]);
      await prepare('fits-command', 'fits');
      final result = await quick.confirmPrepared('fits-command');
      expect(result.creditMinor, 1);
      final treasury = SqliteTreasuryStore(app);
      await treasury.ensureDefaults();
      expect(
        (await treasury.load()).receivablesMinor,
        Money.maxMinorUnits.toInt(),
      );
      expect((await treasury.load()).cashMinor, 1);
    },
  );

  test(
    'confirmation rechecks capacity after another prepared sale wins',
    () async {
      final sales = SqliteSalesStore(app, synthetic: true);
      final half = (Money.maxMinorUnits ~/ BigInt.two).toInt();
      await _largeCredit(sales, 'large-one', half, at);
      await _largeCredit(sales, 'large-two', half, at);
      await save('a', [line('a1', price: 1)]);
      await save('b', [line('b1', price: 1)]);
      await prepare('a-command', 'a');
      await prepare('b-command', 'b');
      await quick.confirmPrepared('a-command');
      await expectLater(
        quick.confirmPrepared('b-command'),
        throwsA(isA<QuickSalesValidationException>()),
      );
      expect(await count('sales'), 3);
      expect(await count('quick_sale_line_tenders'), 1);
      expect((await quick.load()).pendingSales.single.status, 'rejected');
    },
  );

  test(
    'credit capacity includes aggregate legacy debt without creating a customer',
    () async {
      final treasury = SqliteTreasuryStore(app);
      await treasury.ensureDefaults();
      final legacyDebt = (Money.maxMinorUnits - BigInt.one).toInt();
      await SqliteTreasuryOpeningStore(app, synthetic: true).importOpening(
        TreasuryOpeningCommand(
          commandId: 'synthetic-opening',
          sourceSha256: List.filled(64, 'a').join(),
          snapshotSha256: List.filled(64, 'b').join(),
          occurredAtUtc: at.subtract(const Duration(hours: 1)),
          cashMinor: 0,
          nequiMinor: 0,
          reserveMinor: 0,
          receivablesMinor: legacyDebt,
          sourceMetadata: {
            'sourceName': 'synthetic.db',
            'rows': {'cash': 1, 'nequi': 2, 'reserve': 3, 'receivables': 4},
          },
        ),
      );
      expect((await SqliteCollectionsStore(app).load()).receivables, isEmpty);
      await save('overflow', [line('overflow-line', price: 2)]);
      await expectLater(
        prepare('overflow-command', 'overflow'),
        throwsA(isA<QuickSalesValidationException>()),
      );
      await save('fits', [line('fits-line', price: 1)]);
      await prepare('fits-command', 'fits');
      await quick.confirmPrepared('fits-command');
      final balances = await treasury.load();
      expect(balances.receivablesMinor, Money.maxMinorUnits.toInt());
      expect(balances.legacyReceivablesMinor, legacyDebt);
      expect(
        (await SqliteCollectionsStore(
          app,
        ).load()).receivables.single.remainingMinor,
        1,
      );
    },
  );

  test(
    'file reopen recovers mixed preparation and stable committed response',
    () async {
      final root = Directory(
        p.join(
          Directory.current.path,
          'tmp',
          'tests',
          'quick-credit-${InventoryIds.next()}',
        ),
      )..createSync(recursive: true);
      final path = p.join(root.path, 'credit.sqlite3');
      var disk = await AppDatabase.open(path: path);
      try {
        await _fixture(disk);
        var store = SqliteQuickSalesStore(disk, synthetic: true);
        await store.ensureDefaults();
        await store.saveAccount(
          SaveQuickSaleAccount(
            id: 'disk',
            label: 'Cuenta durable',
            customerName: 'Ana',
            expectedRevision: 0,
            lines: [
              line('disk-debt'),
              line('disk-cash', payment: 'quick-default:EFECTIVO'),
            ],
          ),
        );
        await store.prepareSale(
          commandId: 'restart',
          accountId: 'disk',
          expectedRevision: 1,
          occurredAtUtc: at,
        );
        await disk.close();
        disk = await AppDatabase.open(path: path);
        store = SqliteQuickSalesStore(disk, synthetic: true);
        final pending = (await store.load()).pendingSales.single;
        expect(pending.creditMinor, 10000);
        expect(pending.customerName, 'Ana');
        final first = await store.confirmPrepared('restart');
        await disk.close();
        disk = await AppDatabase.open(path: path);
        store = SqliteQuickSalesStore(disk, synthetic: true);
        final replay = await store.confirmPrepared('restart');
        expect(replay.saleDocumentId, first.saleDocumentId);
        expect(replay.collectionDocumentId, first.collectionDocumentId);
        expect(replay.creditMinor, 10000);
        expect(
          (await SqliteCollectionsStore(
            disk,
          ).load()).receivables.single.remainingMinor,
          10000,
        );
        expect(await disk.database.query('sales'), hasLength(1));
        expect(await disk.database.query('collections'), hasLength(1));
      } finally {
        await disk.close();
      }
    },
  );
}

Future<void> _largeCredit(
  SqliteSalesStore sales,
  String id,
  int price,
  DateTime at,
) async {
  await sales.saveDraft(
    SaveSaleDraft(
      id: id,
      label: id,
      customerName: 'Cliente previo',
      expectedRevision: 0,
      lines: [
        SaleDraftLine(productId: 'product', quantity: 1, unitPriceMinor: price),
      ],
    ),
  );
  await sales.prepareConfirmation(
    commandId: 'sale-$id',
    draftId: id,
    expectedRevision: 1,
    occurredAtUtc: at,
    dueDate: '2026-10-20',
  );
  await sales.confirmPrepared('sale-$id');
}

Future<void> _fixture(AppDatabase app) async {
  await SqliteWorkspaceStore(app).createProfile(
    BusinessProfile(
      profileId: 'quick-credit-test',
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
