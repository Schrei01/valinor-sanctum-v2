import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/domain/money.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/schema.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_opening_store.dart';
import 'package:valinor_sanctum_2/features/treasury/domain/treasury_opening.dart';
import 'package:valinor_sanctum_2/features/collections/data/sqlite_collections_store.dart';
import 'package:valinor_sanctum_2/features/collections/domain/collections_store.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/data/sqlite_quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/sales/data/sqlite_sales_store.dart';
import 'package:valinor_sanctum_2/features/sales/domain/sales_store.dart';
import 'package:valinor_sanctum_2/features/stock_intake/data/sqlite_stock_intake_store.dart';
import 'package:valinor_sanctum_2/features/stock_intake/domain/stock_intake_store.dart';
import 'package:valinor_sanctum_2/features/supplier_payments/data/sqlite_supplier_payments_store.dart';
import 'package:valinor_sanctum_2/features/supplier_payments/domain/supplier_payments_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_store.dart';
import 'package:valinor_sanctum_2/features/treasury/domain/treasury_store.dart';
import 'package:valinor_sanctum_2/features/workspace/data/sqlite_workspace_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase app;
  late SqliteTreasuryStore treasury;
  setUp(() async {
    app = await AppDatabase.open(path: inMemoryDatabasePath);
    treasury = SqliteTreasuryStore(app);
    await SqliteWorkspaceStore(app).createProfile(
      BusinessProfile(
        profileId: 'treasury-test',
        businessName: 'Ludoteca sintética',
        currencyCode: 'COP',
        moneyScale: 2,
        timezone: 'America/Bogota',
        createdAtUtc: DateTime.utc(2026, 10, 20),
      ),
    );
  });
  tearDown(() => app.close());

  Future<Map<String, Object?>> option(String code) async =>
      (await app.database.query(
        'quick_payment_options',
        where: 'id=?',
        whereArgs: ['quick-default:$code'],
      )).single;

  test(
    'imported balances reconcile with the dashboard and subsequent money movements',
    () async {
      await treasury.ensureDefaults();
      final result = await SqliteTreasuryOpeningStore(app, synthetic: true)
          .importOpening(
            TreasuryOpeningCommand(
              commandId: 'synthetic-treasury-opening',
              sourceSha256: 'a' * 64,
              snapshotSha256: 'b' * 64,
              occurredAtUtc: DateTime.utc(2026, 10, 20, 8),
              cashMinor: 100,
              nequiMinor: 200,
              reserveMinor: -50,
              receivablesMinor: 80,
              sourceMetadata: const {'source': 'synthetic'},
            ),
          );
      var snapshot = await treasury.load();
      expect(snapshot.cashMinor, 100);
      expect(snapshot.nequiMinor, 200);
      expect(snapshot.reserveMinor, -50);
      expect(snapshot.receivablesMinor, 80);
      expect(snapshot.legacyReceivablesMinor, 80);
      expect(snapshot.totalAvailableMinor, 300);
      expect(snapshot.movements, hasLength(3));
      expect(
        snapshot.movements.every(
          (movement) => movement.documentId == result.documentId,
        ),
        isTrue,
      );
      expect(
        snapshot.movements.every(
          (movement) => movement.concept == 'Saldo inicial de la copia',
        ),
        isTrue,
      );
      expect(await app.database.query('sales'), isEmpty);
      expect(await app.database.query('customer_receivables'), isEmpty);
      expect(await app.database.query('cash_openings'), isEmpty);
      final cash = (await option('EFECTIVO'))['cash_account_id'] as String;
      await _journal(
        app,
        'later-money',
        cash,
        25,
        at: DateTime.utc(2026, 10, 20, 12),
      );
      snapshot = await treasury.load();
      expect(snapshot.cashMinor, 125);
      expect(snapshot.totalAvailableMinor, 325);
      expect(snapshot.receivablesMinor, 80);
      final stockIntake = SqliteStockIntakeStore(app, synthetic: true);
      final options = (await stockIntake.load()).paymentOptions;
      expect(
        options.every(
          (option) => option.openingRecorded && !option.canRecordOpening,
        ),
        isTrue,
      );
    },
  );

  test(
    'defaults create identities only and replay never invents funds',
    () async {
      await treasury.ensureDefaults();
      final firstAccounts = await app.database.query(
        'cash_accounts',
        orderBy: 'id',
      );
      final firstLedgers = await app.database.query(
        'ledger_accounts',
        orderBy: 'id',
      );
      final firstOptions = await app.database.query(
        'quick_payment_options',
        orderBy: 'id',
      );
      await treasury.ensureDefaults();
      expect(
        await app.database.query('cash_accounts', orderBy: 'id'),
        firstAccounts,
      );
      expect(
        await app.database.query('ledger_accounts', orderBy: 'id'),
        firstLedgers,
      );
      expect(
        await app.database.query('quick_payment_options', orderBy: 'id'),
        firstOptions,
      );
      expect(firstAccounts, hasLength(3));
      expect(firstOptions, hasLength(2));
      expect(
        firstOptions.every(
          (row) =>
              row['cash_account_id'] != SqliteTreasuryStore.reserveAccountId,
        ),
        isTrue,
      );
      for (final table in [
        'command_log',
        'business_documents',
        'journal_entries',
        'journal_lines',
      ]) {
        expect(await app.database.query(table), isEmpty, reason: table);
      }
      final snapshot = await treasury.load();
      expect(snapshot.accounts.map((a) => a.role), [
        TreasuryAccountRole.cash,
        TreasuryAccountRole.nequi,
        TreasuryAccountRole.reserve,
      ]);
      expect(snapshot.accounts.every((a) => a.balanceMinor == 0), isTrue);
      expect(snapshot.totalAvailableMinor, 0);
      expect(snapshot.receivablesMinor, 0);
      expect(snapshot.movements, isEmpty);
      expect(() => snapshot.accounts.clear(), throwsUnsupportedError);
      expect(() => snapshot.movements.clear(), throwsUnsupportedError);
      expect((await app.readHealth())['schemaVersion'], DatabaseSchema.version);
    },
  );

  test(
    'roles use stable option IDs and reserve and other accounts stay out of total',
    () async {
      await treasury.ensureDefaults();
      final cash = (await option('EFECTIVO'))['cash_account_id'] as String;
      final nequi = (await option('NEQUI'))['cash_account_id'] as String;
      final catalogs = SqliteCollectionsStore(app);
      await catalogs.saveAccount(
        CollectionAccount(
          id: cash,
          name: 'Billetera personalizada',
          kind: 'cash',
        ),
      );
      await catalogs.saveAccount(
        CollectionAccount(id: nequi, name: 'Otra etiqueta', kind: 'mobile'),
      );
      await catalogs.saveAccount(
        const CollectionAccount(id: 'other', name: 'Nequi', kind: 'bank'),
      );
      await _journal(app, 'cash-funds', cash, 100);
      await _journal(app, 'nequi-funds', nequi, 200);
      await _journal(
        app,
        'reserve-funds',
        SqliteTreasuryStore.reserveAccountId,
        300,
      );
      await _journal(app, 'other-funds', 'other', 400);
      final snapshot = await treasury.load();
      expect(snapshot.cashMinor, 100);
      expect(snapshot.nequiMinor, 200);
      expect(snapshot.reserveMinor, 300);
      expect(snapshot.totalAvailableMinor, 300);
      expect(
        snapshot.accounts.singleWhere((a) => a.id == 'other').role,
        TreasuryAccountRole.other,
      );
      expect(snapshot.movements, hasLength(4));
      final before = await app.database.query('journal_lines', orderBy: 'id');
      await treasury.ensureDefaults();
      await treasury.load();
      expect(await app.database.query('journal_lines', orderBy: 'id'), before);
    },
  );

  test(
    'openings paid purchases quick sales collections and supplier payments reconcile',
    () async {
      await treasury.ensureDefaults();
      final intake = SqliteStockIntakeStore(app, synthetic: true);
      await intake.ensureDefaults();
      final category = (await intake.load()).categories.first.id;
      for (final spec in [('EFECTIVO', 100000), ('NEQUI', 50000)]) {
        await intake.recordOpeningBalance(
          CashOpeningCommand(
            commandId: 'opening-${spec.$1}',
            paymentOptionId: 'quick-default:${spec.$1}',
            amountMinor: spec.$2,
            occurredAtUtc: DateTime.utc(2026, 10, 20, 8),
          ),
        );
      }
      await intake.prepare(
        StockIntakeCommand(
          commandId: 'paid-purchase',
          productId: 'product',
          productName: 'Producto sintético',
          categoryId: category,
          supplierName: 'Proveedor sintético',
          unitPurchasePriceMinor: 1000,
          listPriceMinor: 1500,
          quantity: 5,
          paymentOptionId: 'quick-default:EFECTIVO',
          occurredAtUtc: DateTime.utc(2026, 10, 20, 10),
        ),
      );
      await intake.confirmPrepared('paid-purchase');
      final quick = SqliteQuickSalesStore(app, synthetic: true);
      await quick.saveAccount(
        SaveQuickSaleAccount(
          id: 'counter',
          label: 'Mostrador sintético',
          expectedRevision: 0,
          lines: const [
            QuickSaleLine(
              id: 'line-cash',
              productId: 'product',
              unitPriceMinor: 1500,
              paymentOptionId: 'quick-default:EFECTIVO',
            ),
            QuickSaleLine(
              id: 'line-nequi',
              productId: 'product',
              unitPriceMinor: 1500,
              paymentOptionId: 'quick-default:NEQUI',
            ),
          ],
        ),
      );
      await quick.prepareSale(
        commandId: 'quick-sale',
        accountId: 'counter',
        expectedRevision: 1,
        occurredAtUtc: DateTime.utc(2026, 10, 20, 16),
      );
      await quick.confirmPrepared('quick-sale');
      final sales = SqliteSalesStore(app, synthetic: true);
      await _creditSale(sales, 'credit', 4000);
      final collections = SqliteCollectionsStore(app, synthetic: true);
      final debt = (await collections.load()).receivables.singleWhere(
        (r) => r.remainingMinor > 0,
      );
      final nequi = await option('NEQUI');
      await collections.prepareCollection(
        CollectionCommand(
          commandId: 'partial',
          receivableId: debt.receivableId,
          occurredAtUtc: DateTime.utc(2026, 10, 20, 18),
          parts: [
            CollectionPartInput(
              cashAccountId: nequi['cash_account_id'] as String,
              paymentMethodId: nequi['payment_method_id'] as String,
              amountMinor: 1000,
            ),
          ],
        ),
      );
      await collections.confirmPrepared('partial');
      final inventory = SqliteInventoryStore(app, synthetic: true);
      await inventory.saveSupplier(
        const InventorySupplier(
          id: 'historical-supplier',
          name: 'Proveedor histórico sintético',
        ),
      );
      await inventory.saveProduct(
        const CatalogProduct(
          id: 'other-product',
          name: 'Otro producto sintético',
          listPriceMinor: 5000,
        ),
      );
      await inventory.receivePurchase(
        ReceiptCommand(
          commandId: 'unpaid-purchase',
          supplierId: 'historical-supplier',
          occurredAtUtc: DateTime.utc(2026, 10, 20, 19),
          dueDate: '2026-10-21',
          lines: const [
            ReceiptLineInput(
              productId: 'other-product',
              quantity: 1,
              totalCostMinor: 4000,
            ),
          ],
        ),
      );
      final payments = SqliteSupplierPaymentsStore(app, synthetic: true);
      final payable = (await payments.load()).payables.singleWhere(
        (p) => p.remainingMinor > 0,
      );
      final cash = await option('EFECTIVO');
      await payments.preparePayment(
        SupplierPaymentCommand(
          commandId: 'supplier-partial',
          payableId: payable.payableId,
          occurredAtUtc: DateTime.utc(2026, 10, 20, 20),
          parts: [
            SupplierPaymentPartInput(
              cashAccountId: cash['cash_account_id'] as String,
              paymentMethodId: cash['payment_method_id'] as String,
              amountMinor: 1000,
            ),
          ],
        ),
      );
      await payments.confirmPrepared('supplier-partial');
      await sales.saveDraft(
        SaveSaleDraft(
          id: 'draft',
          label: 'Sin confirmar',
          customerName: 'Cliente de prueba',
          expectedRevision: 0,
          lines: const [
            SaleDraftLine(
              productId: 'product',
              quantity: 1,
              unitPriceMinor: 9999,
            ),
          ],
        ),
      );
      final snapshot = await treasury.load();
      expect(snapshot.cashMinor, 95500);
      expect(snapshot.nequiMinor, 52500);
      expect(snapshot.reserveMinor, 0);
      expect(snapshot.totalAvailableMinor, 148000);
      expect(
        snapshot.receivablesMinor,
        3000,
      ); // Customer debt, not supplier debt.
      expect(snapshot.movements, hasLength(7));
      expect(snapshot.movements.first.amountMinor, -1000);
      expect(snapshot.movements.first.concept, startsWith('Pago a proveedor:'));
      expect(
        snapshot.movements.where((m) => m.concept.startsWith('Venta:')),
        hasLength(2),
      );
      expect(
        snapshot.movements
            .where((m) => m.concept.startsWith('Compra:'))
            .single
            .amountMinor,
        -5000,
      );
      for (final account in snapshot.accounts) {
        final recorded = snapshot.movements
            .where((m) => m.cashAccountId == account.id)
            .fold(
              BigInt.zero,
              (sum, movement) => sum + BigInt.from(movement.amountMinor),
            );
        expect(recorded, BigInt.from(account.balanceMinor));
        expect(
          (await collections.load()).accounts
              .singleWhere((a) => a.id == account.id)
              .balanceMinor,
          account.balanceMinor,
        );
      }
      await collections.confirmPrepared('partial');
      await payments.confirmPrepared('supplier-partial');
      await quick.confirmPrepared('quick-sale');
      final replay = await treasury.load();
      expect(replay.totalAvailableMinor, snapshot.totalAvailableMinor);
      expect(replay.receivablesMinor, snapshot.receivablesMinor);
      expect(
        replay.movements.map((m) => m.id),
        snapshot.movements.map((m) => m.id),
      );
    },
  );

  test(
    'only posted document and posted journal affect balances and history',
    () async {
      await treasury.ensureDefaults();
      final cash = (await option('EFECTIVO'))['cash_account_id'] as String;
      await _journal(
        app,
        'both-draft',
        cash,
        100,
        documentPosted: false,
        journalPosted: false,
      );
      await _journal(app, 'entry-draft', cash, 200, journalPosted: false);
      await _journal(app, 'both-posted', cash, 300);
      final snapshot = await treasury.load();
      expect(snapshot.cashMinor, 300);
      expect(snapshot.movements.single.documentId, 'doc:both-posted');
      expect(snapshot.receivablesMinor, 0);
    },
  );

  test(
    'history retains fifty per account with stable ordering and complete balances',
    () async {
      await treasury.ensureDefaults();
      final cash = (await option('EFECTIVO'))['cash_account_id'] as String;
      final nequi = (await option('NEQUI'))['cash_account_id'] as String;
      await _journal(
        app,
        'old-nequi',
        nequi,
        7,
        at: DateTime.utc(2026, 10, 19),
      );
      for (var i = 0; i < 52; i++) {
        await _journal(
          app,
          'cash-${i.toString().padLeft(2, '0')}',
          cash,
          1,
          at: DateTime.utc(2026, 10, 20, 15, i),
        );
      }
      final first = await treasury.load();
      final second = await treasury.load();
      expect(first.cashMinor, 52);
      expect(first.nequiMinor, 7);
      expect(first.movements, hasLength(51));
      expect(
        first.movements.where((m) => m.cashAccountId == cash),
        hasLength(50),
      );
      expect(first.movements.last.cashAccountId, nequi);
      expect(first.movements.first.documentId, 'doc:cash-51');
      expect(
        first.movements.map((m) => m.id),
        second.movements.map((m) => m.id),
      );
    },
  );

  test(
    'BigInt preserves exact net when intermediate cash totals exceed int64',
    () async {
      await treasury.ensureDefaults();
      final cash = (await option('EFECTIVO'))['cash_account_id'] as String;
      final max = Money.maxMinorUnits.toInt();
      await _journal(app, 'large-one', cash, max);
      await _journal(app, 'large-two', cash, max);
      await _journal(app, 'large-out', cash, -max);
      final snapshot = await treasury.load();
      expect(snapshot.cashMinor, max);
      expect(snapshot.totalAvailableMinor, max);
      expect(
        snapshot.movements.map((m) => m.amountMinor),
        everyElement(anyOf(max, -max)),
      );
      await _journal(app, 'overflow', cash, 1);
      await expectLater(
        treasury.load(),
        throwsA(isA<TreasuryValidationException>()),
      );
    },
  );

  test(
    'combined available money overflow is rejected rather than wrapped',
    () async {
      await treasury.ensureDefaults();
      final cash = (await option('EFECTIVO'))['cash_account_id'] as String;
      final nequi = (await option('NEQUI'))['cash_account_id'] as String;
      await _journal(app, 'max-cash', cash, Money.maxMinorUnits.toInt());
      await _journal(app, 'one-nequi', nequi, 1);
      await expectLater(
        treasury.load(),
        throwsA(isA<TreasuryValidationException>()),
      );
    },
  );

  test(
    'receivable aggregate overflow is rejected and prepared sale is excluded',
    () async {
      await treasury.ensureDefaults();
      final inventory = SqliteInventoryStore(app, synthetic: true);
      await inventory.saveSupplier(
        const InventorySupplier(id: 'supplier', name: 'Proveedor sintético'),
      );
      await inventory.saveProduct(
        const CatalogProduct(
          id: 'product',
          name: 'Producto sintético',
          listPriceMinor: 1,
        ),
      );
      await inventory.receivePurchase(
        ReceiptCommand(
          commandId: 'stock',
          supplierId: 'supplier',
          occurredAtUtc: DateTime.utc(2026, 10, 20, 10),
          dueDate: '2026-10-21',
          lines: const [
            ReceiptLineInput(
              productId: 'product',
              quantity: 3,
              totalCostMinor: 3,
            ),
          ],
        ),
      );
      final sales = SqliteSalesStore(app, synthetic: true);
      // Each posted sale also debits its FIFO cost, so keep every individual
      // journal safely in range while the combined receivables can overflow.
      final half = (Money.maxMinorUnits ~/ BigInt.two).toInt();
      await _creditSale(sales, 'large-one', half);
      await _creditSale(sales, 'large-two', half);
      expect(
        (await treasury.load()).receivablesMinor,
        (Money.maxMinorUnits - BigInt.one).toInt(),
      );
      await _creditSale(sales, 'pending', 2, confirm: false);
      expect(
        (await treasury.load()).receivablesMinor,
        (Money.maxMinorUnits - BigInt.one).toInt(),
      );
      await sales.confirmPrepared('sale-pending');
      await expectLater(
        treasury.load(),
        throwsA(isA<TreasuryValidationException>()),
      );
    },
  );

  test(
    'reserve identity collision fails without repurposing the existing account',
    () async {
      await SqliteCollectionsStore(app).saveAccount(
        const CollectionAccount(
          id: SqliteTreasuryStore.reserveAccountId,
          name: 'Cuenta anterior',
          kind: 'mobile',
        ),
      );
      final before = (await app.database.query(
        'cash_accounts',
        where: 'id=?',
        whereArgs: [SqliteTreasuryStore.reserveAccountId],
      )).single;
      await expectLater(
        treasury.ensureDefaults(),
        throwsA(isA<TreasuryValidationException>()),
      );
      expect(
        (await app.database.query(
          'cash_accounts',
          where: 'id=?',
          whereArgs: [SqliteTreasuryStore.reserveAccountId],
        )).single,
        before,
      );
      expect(await app.database.query('journal_entries'), isEmpty);
    },
  );
}

Future<void> _creditSale(
  SqliteSalesStore sales,
  String id,
  int price, {
  bool confirm = true,
}) async {
  await sales.saveDraft(
    SaveSaleDraft(
      id: id,
      label: 'Cuenta $id',
      customerName: 'Cliente sintético',
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
    occurredAtUtc: DateTime.utc(2026, 10, 20, 17),
    dueDate: '2026-10-21',
  );
  if (confirm) await sales.confirmPrepared('sale-$id');
}

/// Synthetic generic journal fixture; no product, sale, or money command is
/// exposed by Treasury itself. Both posted flags are exercised independently.
Future<void> _journal(
  AppDatabase app,
  String id,
  String account,
  int amount, {
  DateTime? at,
  bool documentPosted = true,
  bool journalPosted = true,
}) async {
  final time = (at ?? DateTime.utc(2026, 10, 20, 12)).toIso8601String();
  final database = app.database;
  if ((await database.query(
    'actors',
    where: 'id=?',
    whereArgs: ['treasury-test-actor'],
  )).isEmpty) {
    await database.insert('actors', {
      'id': 'treasury-test-actor',
      'display_name': 'Operador sintético',
      'kind': 'synthetic',
      'is_active': 1,
      'created_at_utc': time,
    });
  }
  if ((await database.query(
    'ledger_accounts',
    where: 'id=?',
    whereArgs: ['treasury-test-equity'],
  )).isEmpty) {
    await database.insert('ledger_accounts', {
      'id': 'treasury-test-equity',
      'code': 'TEST:EQUITY',
      'name': 'Patrimonio sintético',
      'class': 'equity',
      'role': 'opening_equity',
      'is_active': 1,
    });
  }
  final ledger =
      (await database.query(
            'cash_accounts',
            where: 'id=?',
            whereArgs: [account],
          )).single['ledger_account_id']
          as String;
  await database.insert('command_log', {
    'id': 'cmd:$id',
    'command_type': 'test_journal',
    'payload_hash': id,
    'actor_id': 'treasury-test-actor',
    'response_json': '{}',
    'response_version': 1,
    'committed_at_utc': time,
  });
  await database.insert('business_documents', {
    'id': 'doc:$id',
    'command_id': 'cmd:$id',
    'command_sequence': 0,
    'profile_id': 'treasury-test',
    'actor_id': 'treasury-test-actor',
    'type': 'test_journal',
    'status': 'draft',
    'occurred_at_utc': time,
    'business_date': '2026-10-20',
    'recorded_at_utc': time,
    'source_kind': 'synthetic',
    'date_quality': 'documented',
  });
  await database.insert('journal_entries', {
    'id': 'entry:$id',
    'document_id': 'doc:$id',
    'status': 'draft',
    'cost_completeness': 'not_applicable',
  });
  for (final line in [
    (ledger, amount > 0 ? amount : 0, amount < 0 ? -amount : 0),
    ('treasury-test-equity', amount < 0 ? -amount : 0, amount > 0 ? amount : 0),
  ].indexed) {
    await database.insert('journal_lines', {
      'id': 'line:$id:${line.$1}',
      'entry_id': 'entry:$id',
      'sequence': line.$1,
      'account_id': line.$2.$1,
      'debit_minor': line.$2.$2,
      'credit_minor': line.$2.$3,
    });
  }
  if (documentPosted) {
    await database.update(
      'business_documents',
      {'status': 'posted'},
      where: 'id=?',
      whereArgs: ['doc:$id'],
    );
  }
  if (journalPosted) {
    await database.update(
      'journal_entries',
      {'status': 'posted', 'posted_at_utc': time},
      where: 'id=?',
      whereArgs: ['entry:$id'],
    );
  }
}
