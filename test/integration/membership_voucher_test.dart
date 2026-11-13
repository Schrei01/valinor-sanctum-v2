import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/features/memberships/data/sqlite_membership_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/data/sqlite_quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/account_voucher.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/account_payment_split.dart';
import 'package:valinor_sanctum_2/features/quick_sales/application/quick_sales_controller.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/events/data/sqlite_events_store.dart';
import 'package:valinor_sanctum_2/features/events/domain/events_store.dart';
import 'package:valinor_sanctum_2/features/debtors/data/sqlite_debtors_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_store.dart';
import 'package:valinor_sanctum_2/features/reports/data/sqlite_reports_store.dart';
import 'package:valinor_sanctum_2/features/reports/domain/reports_store.dart';
import 'quick_sales_store_test.dart' show fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase app;
  late SqliteQuickSalesStore sales;
  late SqliteMembershipStore members;
  late String person;
  late DateTime now;
  setUp(() async {
    app = await AppDatabase.open(path: inMemoryDatabasePath);
    await fixture(app, moneyScale: 0);
    sales = SqliteQuickSalesStore(app, synthetic: true);
    members = SqliteMembershipStore(app, synthetic: true);
    await sales.ensureDefaults();
    await sales.ensureBulkProducts();
    now = DateTime.now().toUtc();
    person = await members.savePerson(
      commandId: 'person',
      name: 'Persona sintética',
      email: '',
      birthDay: 12,
      birthMonth: 11,
    );
    final a = await sales.saveAccount(
      SaveQuickSaleAccount(
        id: 'enroll',
        label: 'Persona sintética',
        customerName: 'Persona sintética',
        debtorId: person,
        expectedRevision: 0,
        lines: const [
          QuickSaleLine(
            id: 'enroll-line',
            productId: SqliteMembershipStore.productId,
            unitPriceMinor: 109000,
            paymentOptionId: 'quick-default:EFECTIVO',
          ),
        ],
      ),
    );
    await sales.prepareSale(
      commandId: 'enroll-sale',
      accountId: a.id,
      expectedRevision: a.revision,
      occurredAtUtc: now,
    );
    await sales.confirmPrepared('enroll-sale');
  });
  tearDown(() => app.close());
  QuickSalesController controller() => QuickSalesController(
    store: sales,
    autosaveDelay: const Duration(days: 1),
  );
  String cart(
    QuickSalesController c, {
    int price = 10000,
    bool selected = true,
  }) {
    final id = c.addAccount()!;
    c.selectDebtor(id, person);
    final line = c.accounts.singleWhere((a) => a.id == id).lines.single;
    c.editLine(
      id,
      QuickSaleLine(
        id: line.id,
        productId: 'product',
        unitPriceMinor: price,
        paymentOptionId: line.paymentOptionId,
        useVoucher: selected,
      ),
    );
    return id;
  }

  test(
    'controller permits a zero-priced item beside a fully covered cart',
    () async {
      final inventory = SqliteInventoryStore(app, synthetic: true);
      await inventory.saveProduct(
        const CatalogProduct(id: 'free', name: 'Regalo', listPriceMinor: 0),
      );
      await inventory.receivePurchase(
        ReceiptCommand(
          commandId: 'free-stock',
          supplierId: 'supplier',
          occurredAtUtc: now.subtract(const Duration(minutes: 1)),
          dueDate: '2026-12-01',
          lines: const [
            ReceiptLineInput(productId: 'free', quantity: 1, totalCostMinor: 1),
          ],
        ),
      );
      final c = controller();
      addTearDown(c.dispose);
      await c.load();
      final id = cart(c);
      c.addLine(id);
      final l = c.accounts.single.lines.last;
      c.editLine(
        id,
        QuickSaleLine(
          id: l.id,
          productId: 'free',
          unitPriceMinor: 0,
          paymentOptionId: l.paymentOptionId,
        ),
      );
      expect(c.accounts.single.singlePaymentOptionId, isNull);
      expect(await c.register(id), isTrue, reason: c.errorFor(id));
      expect((await sales.load()).stockQuantityFor('free'), 0);
      expect((await members.load()).single.voucherRemainingMinor, 20000);
    },
  );
  test(
    'controller confirms a fully covered cart without choosing a payment',
    () async {
      final c = controller();
      addTearDown(c.dispose);
      await c.load();
      final id = cart(c);
      expect(c.accounts.single.singlePaymentOptionId, isNull);
      expect(accountPayable(c.accounts.single), BigInt.zero);
      expect(await c.flush(id), isTrue, reason: c.errorFor(id));
      final reloaded = controller();
      addTearDown(reloaded.dispose);
      await reloaded.load();
      expect(reloaded.accounts.single.lines.single.useVoucher, isTrue);
      expect(reloaded.accounts.single.lines.single.voucherMinor, 10000);
      expect(
        await reloaded.register(id),
        isTrue,
        reason: reloaded.errorFor(id),
      );
      expect((await members.load()).single.voucherRemainingMinor, 20000);
      expect((await SqliteTreasuryStore(app).load()).cashMinor, 109000);
      expect(
        (await SqliteDebtorsStore(
          app,
        ).load()).debtors.singleWhere((p) => p.id == person).balanceMinor,
        0,
      );
    },
  );
  test(
    'controller splits only the excess and recalculates another open cart',
    () async {
      final c = controller();
      addTearDown(c.dispose);
      await c.load();
      final other = cart(c);
      final id = cart(c, price: 40000);
      expect(
        c.divideAccount(id, const [
          QuickLinePaymentPart('quick-default:EFECTIVO', 5000),
          QuickLinePaymentPart(QuickPaymentOption.creditId, 5000),
        ]),
        isTrue,
        reason: c.errorFor(id),
      );
      expect(await c.flush(id), isTrue, reason: c.errorFor(id));
      expect(await c.register(id), isTrue, reason: c.errorFor(id));
      final remaining = c.accounts.singleWhere((a) => a.id == other);
      expect(remaining.lines.single.voucherMinor, 0);
      expect(accountPayable(remaining), BigInt.from(10000));
      expect(await c.register(other), isFalse);
      expect(c.errorFor(other), contains('forma de pago'));
      expect((await SqliteTreasuryStore(app).load()).cashMinor, 114000);
      expect(
        (await SqliteDebtorsStore(
          app,
        ).load()).debtors.singleWhere((p) => p.id == person).balanceMinor,
        5000,
      );
      expect((await sales.load()).stockQuantityFor('product'), 9);
    },
  );
  test(
    'changing consumption invalidates the remainder split until reviewed',
    () async {
      final c = controller();
      addTearDown(c.dispose);
      await c.load();
      final id = cart(c, price: 40000);
      expect(
        c.divideAccount(id, const [
          QuickLinePaymentPart('quick-default:EFECTIVO', 10000),
        ]),
        isTrue,
      );
      var l = c.accounts.single.lines.single;
      c.editLine(
        id,
        QuickSaleLine(
          id: l.id,
          productId: l.productId,
          quantityText: '2',
          unitPriceMinor: l.unitPriceMinor,
          paymentOptionId: l.paymentOptionId,
          paymentParts: l.paymentParts,
          useVoucher: true,
          voucherMinor: l.voucherMinor,
          voucherPeriodId: l.voucherPeriodId,
        ),
      );
      expect(c.accounts.single.needsPaymentReview, isTrue);
      expect(await c.register(id), isFalse);
      expect(c.errorFor(id), contains('consumo cambió'));
      // Reducing the whole cart below the grant needs no money or old division.
      l = c.accounts.single.lines.single;
      c.editLine(
        id,
        QuickSaleLine(
          id: l.id,
          productId: l.productId,
          unitPriceMinor: 20000,
          paymentOptionId: l.paymentOptionId,
          paymentParts: l.paymentParts,
          useVoucher: true,
          voucherMinor: l.voucherMinor,
          voucherPeriodId: l.voucherPeriodId,
        ),
      );
      expect(c.accounts.single.paymentMode, 'single');
      expect(c.accounts.single.singlePaymentOptionId, isNull);
      expect(await c.register(id), isTrue, reason: c.errorFor(id));
      expect((await SqliteTreasuryStore(app).load()).cashMinor, 109000);
    },
  );
  Future<QuickSaleAccount> prepare(
    String id, {
    int price = 10000,
    int quantity = 1,
    bool selected = true,
    List<QuickLinePaymentPart>? parts,
  }) async {
    final m = (await members.load()).single;
    var lines = allocateVoucher(
      [
        QuickSaleLine(
          id: '$id-line',
          productId: 'product',
          quantityText: '$quantity',
          unitPriceMinor: price,
          paymentOptionId: 'quick-default:EFECTIVO',
          useVoucher: selected,
        ),
      ],
      m.voucherRemainingMinor,
      m.periodId,
    );
    if (parts != null) {
      lines = allocateAccountPayments(
        QuickSaleAccount(
          id: id,
          label: 'Persona sintética',
          revision: 0,
          status: 'open',
          updatedAtUtc: now,
          lines: lines,
        ),
        parts,
      );
    }
    final a = await sales.saveAccount(
      SaveQuickSaleAccount(
        id: id,
        label: 'Persona sintética',
        customerName: 'Persona sintética',
        debtorId: person,
        expectedRevision: 0,
        lines: lines,
        paymentMode: parts == null ? 'single' : 'split',
        accountPaymentOptionId: parts == null ? 'quick-default:EFECTIVO' : null,
        paymentSplitBasis: parts == null ? '' : quickConsumptionKey(lines),
      ),
    );
    await sales.prepareSale(
      commandId: '$id-sale',
      accountId: a.id,
      expectedRevision: a.revision,
      occurredAtUtc: now,
    );
    return a;
  }

  test(
    'fully covered consumption settles without cash or personal debt and retries once',
    () async {
      expect((await members.load()).single.voucherRemainingMinor, 30000);
      await prepare('first');
      final result = await sales.confirmPrepared('first-sale');
      expect(result.voucherMinor, 10000);
      expect(result.creditMinor, 0);
      await sales.confirmPrepared('first-sale');
      expect((await members.load()).single.voucherRemainingMinor, 20000);
      expect((await sales.load()).stockQuantityFor('product'), 9);
      expect((await SqliteTreasuryStore(app).load()).cashMinor, 109000);
      expect(
        (await SqliteDebtorsStore(
          app,
          synthetic: true,
        ).load()).debtors.single.balanceMinor,
        0,
      );
      expect(
        (await sales.load()).sales
            .singleWhere((s) => s.commandId == 'first-sale')
            .lines
            .single
            .paymentLabel,
        'Bono',
      );
      expect(await app.database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );
  test(
    'a partly covered multi-unit line keeps exact quantities and the cash remainder',
    () async {
      await prepare('odd', price: 10001, quantity: 3);
      final result = await sales.confirmPrepared('odd-sale');
      expect(result.voucherMinor, 30000);
      expect(result.creditMinor, 0);
      expect((await members.load()).single.voucherRemainingMinor, 0);
      expect((await sales.load()).stockQuantityFor('product'), 7);
      expect((await SqliteTreasuryStore(app).load()).cashMinor, 109003);
      final row = (await app.database.query(
        'sale_lines',
        where: 'sale_id=?',
        whereArgs: [result.saleDocumentId],
      )).single;
      expect(row['quantity'], 3);
      expect(row['unit_price_minor'], 10001);
      expect(row['total_minor'], 30003);
    },
  );
  test(
    'voucher and divided remainder add only real credit to the person',
    () async {
      await prepare(
        'split',
        price: 40000,
        parts: const [
          QuickLinePaymentPart('quick-default:EFECTIVO', 4000),
          QuickLinePaymentPart('quick-default:NEQUI', 3000),
          QuickLinePaymentPart(QuickPaymentOption.creditId, 3000),
        ],
      );
      final r = await sales.confirmPrepared('split-sale');
      expect(r.creditMinor, 3000);
      expect(r.voucherMinor, 30000);
      final debt = (await SqliteDebtorsStore(app, synthetic: true).load());
      expect(debt.debtors.single.balanceMinor, 3000);
      expect(
        debt.charges
            .singleWhere(
              (c) => c.debtorId == person && c.originalCreditMinor > 0,
            )
            .originalCreditMinor,
        3000,
      );
      final money = await SqliteTreasuryStore(app).load();
      expect(money.cashMinor, 113000);
      expect(money.nequiMinor, 3000);
    },
  );
  test('two prepared accounts cannot redeem the same grant', () async {
    await prepare('one', price: 30000);
    await prepare('two', price: 30000);
    await sales.confirmPrepared('one-sale');
    await expectLater(
      sales.confirmPrepared('two-sale'),
      throwsA(isA<QuickSalesValidationException>()),
    );
    expect((await sales.load()).stockQuantityFor('product'), 9);
    expect((await members.load()).single.voucherRemainingMinor, 0);
    expect((await SqliteTreasuryStore(app).load()).cashMinor, 109000);
  });
  test(
    'checked and unchecked lines of the same product preserve price and quantity',
    () async {
      final m = (await members.load()).single;
      final lines = allocateVoucher(
        const [
          QuickSaleLine(
            id: 'covered',
            productId: 'product',
            unitPriceMinor: 20000,
            useVoucher: true,
            paymentOptionId: 'quick-default:EFECTIVO',
          ),
          QuickSaleLine(
            id: 'money',
            productId: 'product',
            unitPriceMinor: 20000,
            paymentOptionId: 'quick-default:EFECTIVO',
          ),
        ],
        m.voucherRemainingMinor,
        m.periodId,
      );
      final a = await sales.saveAccount(
        SaveQuickSaleAccount(
          id: 'mixed',
          label: 'Mixta',
          customerName: 'Persona sintética',
          debtorId: person,
          expectedRevision: 0,
          paymentMode: 'single',
          accountPaymentOptionId: 'quick-default:EFECTIVO',
          lines: lines,
        ),
      );
      await sales.prepareSale(
        commandId: 'mixed-sale',
        accountId: a.id,
        expectedRevision: a.revision,
        occurredAtUtc: now,
      );
      final r = await sales.confirmPrepared('mixed-sale');
      expect(r.voucherMinor, 20000);
      expect(r.creditMinor, 0);
      expect((await sales.load()).stockQuantityFor('product'), 8);
      expect((await members.load()).single.voucherRemainingMinor, 10000);
      expect((await SqliteTreasuryStore(app).load()).cashMinor, 129000);
      final facts = await app.database.query(
        'sale_lines',
        where: 'sale_id=?',
        whereArgs: [r.saleDocumentId],
      );
      expect(facts.single['quantity'], 2);
      expect(facts.single['unit_price_minor'], 20000);
    },
  );
  test(
    'stock failure never consumes a voucher and posted facts resist replacement',
    () async {
      await prepare('all-stock', price: 1000, quantity: 10);
      await prepare('no-stock', price: 1000);
      await sales.confirmPrepared('all-stock-sale');
      await expectLater(
        sales.confirmPrepared('no-stock-sale'),
        throwsA(isA<QuickSalesValidationException>()),
      );
      final before = (await members.load()).single;
      expect(before.voucherRemainingMinor, 20000);
      final grant = (await app.database.query(
        'membership_voucher_grants',
      )).single;
      await expectLater(
        app.database.insert(
          'membership_voucher_grants',
          grant,
          conflictAlgorithm: ConflictAlgorithm.replace,
        ),
        throwsA(anything),
      );
      final redemption = (await app.database.query(
        'membership_voucher_collections',
      )).single;
      await expectLater(
        app.database.insert('membership_voucher_collections', {
          ...redemption,
          'amount_minor': 1,
        }, conflictAlgorithm: ConflictAlgorithm.replace),
        throwsA(anything),
      );
      expect((await members.load()).single.voucherRemainingMinor, 20000);
      expect((await sales.load()).stockQuantityFor('product'), 0);
    },
  );
  test(
    'voucher cannot pay a membership or be prepared outside its valid period',
    () async {
      final m = (await members.load()).single;
      final a = await sales.saveAccount(
        SaveQuickSaleAccount(
          id: 'fee',
          label: 'Mensualidad',
          customerName: 'Persona sintética',
          debtorId: person,
          expectedRevision: 0,
          paymentMode: 'single',
          accountPaymentOptionId: 'quick-default:EFECTIVO',
          lines: const [
            QuickSaleLine(
              id: 'fee-line',
              productId: SqliteMembershipStore.productId,
              unitPriceMinor: 109000,
              useVoucher: true,
              paymentOptionId: 'quick-default:EFECTIVO',
            ),
          ],
        ),
      );
      await expectLater(
        sales.prepareSale(
          commandId: 'bad-fee',
          accountId: a.id,
          expectedRevision: a.revision,
          occurredAtUtc: now,
        ),
        throwsA(isA<QuickSalesValidationException>()),
      );
      final lines = allocateVoucher(
        const [
          QuickSaleLine(
            id: 'outside-line',
            productId: 'product',
            unitPriceMinor: 10000,
            useVoucher: true,
            paymentOptionId: 'quick-default:EFECTIVO',
          ),
        ],
        m.voucherRemainingMinor,
        m.periodId,
      );
      final b = await sales.saveAccount(
        SaveQuickSaleAccount(
          id: 'outside',
          label: 'Fuera de vigencia',
          customerName: 'Persona sintética',
          debtorId: person,
          expectedRevision: 0,
          paymentMode: 'single',
          accountPaymentOptionId: 'quick-default:EFECTIVO',
          lines: lines,
        ),
      );
      await expectLater(
        sales.prepareSale(
          commandId: 'outside-sale',
          accountId: b.id,
          expectedRevision: b.revision,
          occurredAtUtc: m.ends!.add(const Duration(hours: 5)),
        ),
        throwsA(isA<QuickSalesValidationException>()),
      );
      expect((await members.load()).single.voucherRemainingMinor, 30000);
      expect(
        await app.database.query('membership_voucher_collections'),
        isEmpty,
      );
    },
  );
  test(
    'event results deduct voucher allowances from enrollment revenue',
    () async {
      final events = SqliteEventsStore(app, synthetic: true);
      await events.prepare(
        CreateEvent(
          commandId: 'voucher-event',
          name: 'Evento sintético',
          minimumPeople: 0,
          fixedCostMinor: 0,
          pvpMinor: 40000,
          products: const [],
          occurredAtUtc: now.subtract(const Duration(minutes: 1)),
        ),
      );
      final product = await events.confirm('voucher-event');
      final c = controller();
      addTearDown(c.dispose);
      await c.load();
      final id = c.addAccount()!;
      c.selectDebtor(id, person);
      final line = c.accounts.single.lines.single;
      c.editLine(
        id,
        QuickSaleLine(
          id: line.id,
          productId: product,
          unitPriceMinor: 40000,
          paymentOptionId: line.paymentOptionId,
          useVoucher: true,
        ),
      );
      expect(await c.register(id), isTrue, reason: c.errorFor(id));
      final local = DateTime.now().toUtc().subtract(const Duration(hours: 5));
      final report = await SqliteReportsStore(app).load(
        ReportPeriod.timed(
          start: local.subtract(const Duration(hours: 1)),
          end: local.add(const Duration(minutes: 1)),
        ),
      );
      expect(report.events.single.salesMinor, 10000);
      expect(report.voucherConsumptionMinor, 30000);
    },
  );
  test(
    'reports separate voucher consumption from money and credit without duplicate revenue',
    () async {
      await prepare(
        'report',
        price: 40000,
        parts: const [
          QuickLinePaymentPart('quick-default:EFECTIVO', 4000),
          QuickLinePaymentPart('quick-default:NEQUI', 3000),
          QuickLinePaymentPart(QuickPaymentOption.creditId, 3000),
        ],
      );
      await sales.confirmPrepared('report-sale');
      final local = now.subtract(const Duration(hours: 5));
      final report = await SqliteReportsStore(app).load(
        ReportPeriod.timed(
          start: local.subtract(const Duration(minutes: 1)),
          end: local.add(const Duration(minutes: 1)),
        ),
      );
      expect(report.saleTotals.knownTotalMinor, 119000);
      expect(report.saleTotals.knownCashMinor, 113000);
      expect(report.saleTotals.knownTransferMinor, 3000);
      expect(report.saleTotals.knownCreditMinor, 3000);
      expect(report.voucherConsumptionMinor, 30000);
      expect(report.outflowTotals.cashMinor, 0);
      expect(report.outflowTotals.transferMinor, 0);
      expect(
        report.sales.singleWhere((s) => s.productId == 'product').quantity,
        1,
      );
      expect(
        report.items
            .singleWhere((i) => i.productName == 'Producto sintético')
            .paymentMethod,
        contains('Bono'),
      );
    },
  );
}
