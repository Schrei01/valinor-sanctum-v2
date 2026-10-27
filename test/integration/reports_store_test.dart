import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/features/reports/domain/reports_store.dart';
import 'package:valinor_sanctum_2/features/reports/data/sqlite_reports_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/data/sqlite_quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_inventory_store.dart';
import 'package:valinor_sanctum_2/features/debtors/domain/debtors_store.dart';
import 'package:valinor_sanctum_2/features/debtors/data/sqlite_debtors_store.dart';
import 'package:valinor_sanctum_2/features/events/domain/events_store.dart';
import 'package:valinor_sanctum_2/features/events/data/sqlite_events_store.dart';
import 'package:valinor_sanctum_2/features/treasury/domain/treasury_operation_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_operation_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_store.dart';
import 'package:valinor_sanctum_2/features/stock_intake/data/sqlite_stock_intake_store.dart';
import 'package:valinor_sanctum_2/features/stock_intake/domain/stock_intake_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_opening_store.dart';
import 'package:valinor_sanctum_2/features/treasury/domain/treasury_opening.dart';
import 'package:valinor_sanctum_2/features/sales/domain/sales_store.dart';
import 'package:valinor_sanctum_2/features/sales/data/sqlite_sales_store.dart';
import 'package:valinor_sanctum_2/features/collections/domain/collections_store.dart';
import 'package:valinor_sanctum_2/features/collections/data/sqlite_collections_store.dart';
import '../support/register_debtor.dart';
import 'quick_sales_store_test.dart' show fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase app;
  late SqliteReportsStore reports;
  final day = DateTime.utc(2026, 10, 20);
  final at = DateTime.utc(2026, 10, 20, 14);
  ReportPeriod period([DateTime? date]) =>
      ReportPeriod(start: date ?? day, end: date ?? day);
  setUp(() async {
    app = await AppDatabase.open(path: inMemoryDatabasePath);
    await fixture(app);
    reports = SqliteReportsStore(app);
  });
  tearDown(() => app.close());
  Future<void> money({DateTime? date}) async {
    await SqliteTreasuryStore(app).ensureDefaults();
    await SqliteTreasuryOpeningStore(app, synthetic: true).importOpening(
      TreasuryOpeningCommand(
        commandId: 'opening',
        sourceSha256: 'a' * 64,
        snapshotSha256: 'b' * 64,
        occurredAtUtc: date ?? at.subtract(const Duration(days: 1)),
        cashMinor: 100000,
        nequiMinor: 50000,
        reserveMinor: -2000,
        receivablesMinor: 30000,
        sourceMetadata: const {'sourceName': 'synthetic'},
      ),
    );
  }

  Future<String> sell(
    String id, {
    bool mixed = false,
    String product = 'product',
    int qty = 1,
    int price = 10000,
    DateTime? date,
    String? debtor,
  }) async {
    final quick = SqliteQuickSalesStore(app, synthetic: true);
    await quick.ensureDefaults();
    await quick.saveAccount(
      SaveQuickSaleAccount(
        id: id,
        label: 'Cuenta $id',
        expectedRevision: 0,
        debtorId: debtor,
        lines: [
          QuickSaleLine(
            id: '$id-1',
            productId: product,
            quantityText: '$qty',
            unitPriceMinor: price,
            paymentOptionId: mixed
                ? QuickPaymentOption.creditId
                : 'quick-default:EFECTIVO',
          ),
          if (mixed)
            QuickSaleLine(
              id: '$id-2',
              productId: product,
              quantityText: '1',
              unitPriceMinor: price,
              paymentOptionId: 'quick-default:NEQUI',
            ),
        ],
      ),
    );
    await quick.prepareSale(
      commandId: 'sale-$id',
      accountId: id,
      expectedRevision: 1,
      occurredAtUtc: date ?? at,
    );
    final result = await quick.confirmPrepared('sale-$id');
    return result.saleDocumentId;
  }

  Future<Map<String, String>> rows() async => {
    for (final t in await app.database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    ))
      t['name'] as String: jsonEncode(
        await app.database.query(t['name'] as String),
      ),
  };

  test(
    'read model never writes defaults and native empty money starts at known zero',
    () async {
      final before = await rows();
      final data = await reports.load(period());
      expect(data.accounts, isEmpty);
      expect(data.openingBalancesKnown, isTrue);
      expect(data.debtOpeningMinor, 0);
      expect(data.salesMinor, 0);
      expect(await rows(), before);
    },
  );
  test(
    'import coverage makes earlier start and closing unknown instead of zero',
    () async {
      await money(date: at);
      final before = await reports.load(period(DateTime.utc(2026, 10, 19)));
      expect(before.openingBalancesKnown, isFalse);
      expect(before.closingBalancesKnown, isFalse);
      expect(
        before.accounts.every(
          (a) => a.openingMinor == null && a.closingMinor == null,
        ),
        isTrue,
      );
      expect(before.debtOpeningMinor, isNull);
      expect(before.debtClosingMinor, isNull);
      final straddling = await reports.load(period());
      expect(straddling.openingBalancesKnown, isFalse);
      expect(straddling.closingBalancesKnown, isTrue);
      expect(
        straddling.accounts
            .singleWhere((a) => a.role == ReportAccountRole.cash)
            .closingMinor,
        100000,
      );
      expect(straddling.debtClosingMinor, 30000);
    },
  );
  test(
    'mixed lines aggregate one physical sale without duplicate tender quantity or cost',
    () async {
      await money();
      final person = await registerDebtor(app, 'Persona sintética');
      await sell('mixed', mixed: true, debtor: person);
      final data = await reports.load(period());
      expect(data.sales, hasLength(1));
      expect(data.products().single.quantity, 2);
      expect(data.salesMinor, 20000);
      expect(data.creditSalesMinor, 10000);
      expect(data.costOfGoodsMinor, 2001);
      expect(data.saleReceiptsMinor, 10000);
      expect(data.saleTotals.cashTotalMinor, 0);
      expect(data.saleTotals.transferTotalMinor, 10000);
      expect(data.saleTotals.creditTotalMinor, 10000);
      expect(data.saleTotals.totalMinor, 20000);
      expect(data.debtorPaymentsMinor, 0);
      expect(data.debtOpeningMinor, 30000);
      expect(data.debtClosingMinor, 40000);
    },
  );
  test(
    'intraday range reconciles balances and selects both minute edges without writing',
    () async {
      await money();
      await sell('before', date: DateTime.utc(2026, 10, 20, 14, 0, 59));
      await sell('first', date: DateTime.utc(2026, 10, 20, 14, 1));
      await sell('last', date: DateTime.utc(2026, 10, 20, 14, 1, 59, 999, 999));
      await sell('after', date: DateTime.utc(2026, 10, 20, 14, 2));
      final before = await rows();
      final data = await reports.load(
        ReportPeriod.timed(
          start: DateTime.utc(2026, 10, 20, 9, 1),
          end: DateTime.utc(2026, 10, 20, 9, 1),
        ),
      );
      expect(data.sales, hasLength(2));
      expect(data.salesMinor, 20000);
      expect(data.saleReceiptsMinor, 20000);
      expect(data.saleTotals.cashTotalMinor, 20000);
      expect(data.saleTotals.totalMinor, 20000);
      final cash = data.accounts.singleWhere(
        (a) => a.role == ReportAccountRole.cash,
      );
      expect(cash.openingMinor, 110000);
      expect(cash.closingMinor, 130000);
      expect(await rows(), before);
    },
  );
  test(
    'import exactly at the first Bogotá midnight does not invent the preceding opening balance',
    () async {
      await money(date: DateTime.utc(2026, 10, 20, 5));
      final data = await reports.load(period());
      expect(data.openingBalancesKnown, isFalse);
      expect(data.accounts.every((a) => a.openingMinor == null), isTrue);
      expect(data.debtOpeningMinor, isNull);
      expect(data.closingBalancesKnown, isTrue);
      expect(
        data.accounts
            .singleWhere((a) => a.role == ReportAccountRole.cash)
            .closingMinor,
        100000,
      );
      expect(data.debtClosingMinor, 30000);
      expect(
        data.movements.where((m) => m.kind == ReportMovementKind.opening),
        hasLength(3),
      );
    },
  );
  test(
    'later abono enters cash once, reduces historical debt and creates no period sale',
    () async {
      await money();
      final person = await registerDebtor(app, 'Persona sintética');
      await sell(
        'mixed',
        mixed: true,
        debtor: person,
        date: at
            .subtract(const Duration(days: 1))
            .add(const Duration(hours: 2)),
      );
      final debtors = SqliteDebtorsStore(app, synthetic: true);
      await debtors.prepare(
        DebtorCommand(
          commandId: 'pay',
          kind: 'payment',
          debtorId: person,
          amountMinor: 6000,
          paymentOptionId: 'quick-default:EFECTIVO',
          occurredAtUtc: at,
        ),
      );
      await debtors.confirm('pay');
      final before = await rows();
      final data = await reports.load(period());
      expect(data.salesMinor, 0);
      expect(data.saleReceiptsMinor, 0);
      expect(data.debtorPaymentsMinor, 6000);
      expect(data.saleTotals.cashTotalMinor, 0);
      expect(data.saleTotals.totalMinor, 0);
      expect(
        data.movements.where((m) => m.kind == ReportMovementKind.debtorPayment),
        hasLength(1),
      );
      expect(data.debtOpeningMinor, 40000);
      expect(data.debtClosingMinor, 34000);
      expect(
        data.debtorBalances.singleWhere((d) => d.id == person).amountMinor,
        4000,
      );
      expect(
        data.debtorBalances
            .singleWhere((d) => d.id == 'unassigned')
            .amountMinor,
        30000,
      );
      final earlier = await reports.load(
        ReportPeriod.timed(
          start: DateTime.utc(2026, 10, 19),
          end: DateTime.utc(2026, 10, 20, 8, 59),
        ),
      );
      expect(
        earlier.debtorBalances.singleWhere((d) => d.id == person).amountMinor,
        10000,
      );
      expect(earlier.debtClosingMinor, 40000);
      expect(await rows(), before);
    },
  );
  test(
    'internal transfer has two account legs but no receipt, expense or profit',
    () async {
      await money();
      final operations = SqliteTreasuryOperationStore(app, synthetic: true);
      await operations.ensureDefaults();
      final accounts = (await operations.load()).accounts;
      final cash = accounts.singleWhere((a) => a.name == 'Caja'),
          nequi = accounts.singleWhere((a) => a.name == 'Nequi');
      await operations.prepare(
        TreasuryOperationCommand(
          commandId: 'transfer',
          kind: TreasuryOperationKind.transfer,
          sourceAccountId: cash.id,
          destinationAccountId: nequi.id,
          amountMinor: 12000,
          reason: 'Transferencia',
          occurredAtUtc: at,
        ),
      );
      await operations.confirmPrepared('transfer');
      final data = await reports.load(period());
      expect(data.transfers, hasLength(1));
      expect(data.transfers.single.amountMinor, 12000);
      expect(data.knownTransferTotalMinor, 12000);
      expect(data.transferRoutes.single.count, 1);
      expect(
        data.movements.where((m) => m.kind == ReportMovementKind.transfer),
        hasLength(2),
      );
      expect(data.outflowsMinor, 0);
      expect(data.outflowTotals.totalMinor, 0);
      expect(data.saleReceiptsMinor, 0);
      expect(data.operatingResultMinor, 0);
      expect(data.saleTotals.cashTotalMinor, 0);
      expect(data.saleTotals.transferTotalMinor, 0);
      expect(data.saleTotals.totalMinor, 0);
      expect(
        data.accounts
            .singleWhere((a) => a.role == ReportAccountRole.cash)
            .closingMinor,
        88000,
      );
      expect(
        data.accounts
            .singleWhere((a) => a.role == ReportAccountRole.transfer)
            .closingMinor,
        62000,
      );
    },
  );
  test(
    'old included debt is reassignment and additional debt is not a sale',
    () async {
      await money();
      final debtors = SqliteDebtorsStore(app, synthetic: true);
      await debtors.load();
      for (final c in [
        DebtorCommand(
          commandId: 'included',
          kind: 'create',
          name: 'Anterior incluida',
          amountMinor: 10000,
          previousSource: PreviousDebtSource.includedInLegacy,
          occurredAtUtc: at,
        ),
        DebtorCommand(
          commandId: 'additional',
          kind: 'create',
          name: 'Anterior adicional',
          amountMinor: 5000,
          previousSource: PreviousDebtSource.additional,
          occurredAtUtc: at,
        ),
      ]) {
        await debtors.prepare(c);
        await debtors.confirm(c.commandId);
      }
      final data = await reports.load(period());
      expect(data.salesMinor, 0);
      expect(data.saleReceiptsMinor, 0);
      expect(data.additionalDebtMinor, 5000);
      expect(
        data.debtChanges.where((d) => d.isLegacyAssignment).single.amountMinor,
        10000,
      );
      expect(data.debtOpeningMinor, 30000);
      expect(data.debtClosingMinor, 35000);
      expect(
        {for (final d in data.debtorBalances) d.name: d.amountMinor},
        {
          'Anterior incluida': 10000,
          'Anterior adicional': 5000,
          'Sin asignar': 20000,
        },
      );
      final beforeAssignment = await reports.load(
        ReportPeriod.timed(
          start: DateTime.utc(2026, 10, 19),
          end: DateTime.utc(2026, 10, 20, 8, 59),
        ),
      );
      expect(beforeAssignment.debtorBalances.single.id, 'unassigned');
      expect(beforeAssignment.debtorBalances.single.amountMinor, 30000);
    },
  );
  test(
    'physical reports keep actual historical price and FIFO cost after product changes',
    () async {
      await money();
      await sell('cash');
      final inventory = SqliteInventoryStore(app, synthetic: true);
      await inventory.saveProduct(
        const CatalogProduct(
          id: 'product',
          name: 'Nombre nuevo',
          listPriceMinor: 80000,
        ),
      );
      final data = await reports.load(period());
      expect(data.sales.single.productName, 'Producto sintético');
      expect(data.salesMinor, 10000);
      expect(data.costOfGoodsMinor, 1001);
      expect(data.physicalMarginMinor, 8999);
    },
  );
  test(
    'event actual costs occur once on creation and lifetime result uses inscriptions through cutoff',
    () async {
      await money();
      final cash =
          (await app.database.query(
                'quick_payment_options',
                where: "id='quick-default:EFECTIVO'",
              )).single['cash_account_id']
              as String;
      final events = SqliteEventsStore(app, synthetic: true);
      await events.prepare(
        CreateEvent(
          commandId: 'event',
          name: 'Liga sintética',
          minimumPeople: 2,
          fixedCostMinor: 1000,
          pvpMinor: 10000,
          sourceAccountId: cash,
          products: const [EventProductInput('product', 1)],
          occurredAtUtc: at
              .subtract(const Duration(days: 1))
              .add(const Duration(hours: 1)),
        ),
      );
      final id = await events.confirm('event');
      await sell('entry', product: id, qty: 3);
      final current = await reports.load(period());
      expect(current.salesMinor, 30000);
      expect(current.costOfGoodsMinor, 0);
      expect(current.eventCostsMinor, 0);
      expect(current.operatingResultMinor, 30000);
      expect(current.events.single.quantity, 3);
      expect(current.events.single.costMinor, 2001);
      expect(current.events.single.resultMinor, 27999);
      final creation = await reports.load(period(DateTime.utc(2026, 10, 19)));
      expect(creation.eventCostsMinor, 2001);
      expect(creation.outflowTotals.totalMinor, 1000);
      expect(current.outflowTotals.totalMinor, 0);
      expect(creation.operatingResultMinor, -2001);
      expect(creation.events.single.resultMinor, -2001);
    },
  );
  test(
    'inclusive Bogotá end day preserves subsecond boundary exactly',
    () async {
      await money();
      await sell('last', date: DateTime.utc(2026, 10, 21, 4, 59, 59, 999, 999));
      await sell('next', date: DateTime.utc(2026, 10, 21, 5));
      final data = await reports.load(period());
      expect(data.salesMinor, 10000);
      expect(data.sales.single.saleLabel, 'Cuenta last');
      final next = await reports.load(period(DateTime.utc(2026, 10, 21)));
      expect(next.sales.single.saleLabel, 'Cuenta next');
    },
  );
  test(
    'cash purchase is outflow but cost is recognized only when stock sells; expense reduces result',
    () async {
      await money();
      final intake = SqliteStockIntakeStore(app, synthetic: true);
      await intake.ensureDefaults();
      final category = (await intake.load()).categories.singleWhere(
        (c) => c.name == 'Comestible',
      );
      await intake.prepare(
        StockIntakeCommand(
          commandId: 'intake',
          productId: 'other',
          productName: 'Producto de reposición',
          categoryId: category.id,
          supplierName: 'Otro proveedor',
          unitPurchasePriceMinor: 1000,
          listPriceMinor: 3000,
          quantity: 2,
          paymentOptionId: 'quick-default:EFECTIVO',
          occurredAtUtc: at.subtract(const Duration(hours: 1)),
        ),
      );
      await intake.confirmPrepared('intake');
      await sell('cash');
      final operations = SqliteTreasuryOperationStore(app, synthetic: true);
      await operations.ensureDefaults();
      final cash = (await operations.load()).accounts.singleWhere(
        (a) => a.name == 'Caja',
      );
      await operations.prepare(
        TreasuryOperationCommand(
          commandId: 'expense',
          kind: TreasuryOperationKind.expense,
          sourceAccountId: cash.id,
          amountMinor: 2000,
          reason: 'Aseo',
          occurredAtUtc: at.add(const Duration(hours: 1)),
        ),
      );
      await operations.confirmPrepared('expense');
      final data = await reports.load(period());
      expect(data.outflowsMinor, 4000);
      expect(data.outflowTotals.cashMinor, 4000);
      expect(data.outflowTotals.transferMinor, 0);
      expect(data.outflowTotals.totalMinor, 4000);
      expect(data.saleTotals.cashTotalMinor, 10000);
      expect(data.saleTotals.totalMinor, 10000);
      expect(
        data.movements
            .singleWhere((m) => m.kind == ReportMovementKind.purchasePayment)
            .amountMinor,
        -2000,
      );
      expect(data.costOfGoodsMinor, 1001);
      expect(data.operatingExpensesMinor, 2000);
      expect(data.operatingResultMinor, 6999);
      expect(
        data.accounts
            .singleWhere((a) => a.role == ReportAccountRole.cash)
            .closingMinor,
        106000,
      );
    },
  );
  test('report includes more than latest fifty account movements', () async {
    await money();
    final operations = SqliteTreasuryOperationStore(app, synthetic: true);
    await operations.ensureDefaults();
    final cash = (await operations.load()).accounts.singleWhere(
      (a) => a.name == 'Caja',
    );
    for (var index = 0; index < 55; index++) {
      final id = 'expense-$index';
      await operations.prepare(
        TreasuryOperationCommand(
          commandId: id,
          kind: TreasuryOperationKind.expense,
          sourceAccountId: cash.id,
          amountMinor: 100,
          reason: 'Otro',
          occurredAtUtc: at.add(Duration(minutes: index)),
        ),
      );
      await operations.confirmPrepared(id);
    }
    final data = await reports.load(period());
    expect(data.movements, hasLength(55));
    expect(data.outflowsMinor, 5500);
    expect(data.operatingExpensesMinor, 5500);
    expect(
      data.accounts
          .singleWhere((a) => a.role == ReportAccountRole.cash)
          .closingMinor,
      94500,
    );
  });
  test(
    'historical plain credit sale and legacy abono retain separate revenue and money',
    () async {
      await money();
      final sales = SqliteSalesStore(app, synthetic: true);
      await sales.saveDraft(
        SaveSaleDraft(
          id: 'historical',
          label: 'Cuenta histórica',
          customerName: 'Persona histórica',
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
      await sales.prepareConfirmation(
        commandId: 'historic-sale',
        draftId: 'historical',
        expectedRevision: 1,
        occurredAtUtc: at,
        dueDate: '2026-10-21',
      );
      await sales.confirmPrepared('historic-sale');
      final option = (await app.database.query(
        'quick_payment_options',
        where: "id='quick-default:EFECTIVO'",
      )).single;
      final receivable = (await app.database.query(
        'customer_receivables',
      )).single;
      final collections = SqliteCollectionsStore(app, synthetic: true);
      await collections.prepareCollection(
        CollectionCommand(
          commandId: 'historical-abono',
          receivableId: receivable['id'] as String,
          occurredAtUtc: at.add(const Duration(hours: 1)),
          parts: [
            CollectionPartInput(
              cashAccountId: option['cash_account_id'] as String,
              paymentMethodId: option['payment_method_id'] as String,
              amountMinor: 4000,
            ),
          ],
        ),
      );
      await collections.confirmPrepared('historical-abono');
      final before = await rows();
      final data = await reports.load(period());
      expect(data.salesMinor, 10000);
      expect(data.creditSalesMinor, 10000);
      expect(data.saleReceiptsMinor, 0);
      expect(data.debtorPaymentsMinor, 4000);
      expect(data.saleTotals.cashTotalMinor, 0);
      expect(data.saleTotals.creditTotalMinor, 10000);
      expect(data.saleTotals.totalMinor, 10000);
      expect(data.debtClosingMinor, 36000);
      expect(await rows(), before);
      expect(data.debtorBalances.single.id, 'unassigned');
      expect(data.debtorBalances.single.amountMinor, 36000);
      final person = await registerDebtor(app, 'Titular asignado después');
      final debtors = SqliteDebtorsStore(app, synthetic: true);
      await debtors.prepare(
        DebtorCommand(
          commandId: 'assign-history',
          kind: 'assign',
          debtorId: person,
          receivableId: receivable['id'] as String,
          occurredAtUtc: at.add(const Duration(hours: 2)),
        ),
      );
      await debtors.confirm('assign-history');
      final earlier = await reports.load(
        ReportPeriod.timed(start: day, end: DateTime.utc(2026, 10, 20, 10, 59)),
      );
      expect(earlier.debtorBalances.single.id, 'unassigned');
      expect(earlier.debtorBalances.single.amountMinor, 36000);
      final assigned = await reports.load(period());
      expect(
        assigned.debtorBalances.singleWhere((d) => d.id == person).amountMinor,
        6000,
      );
      expect(
        assigned.debtorBalances
            .singleWhere((d) => d.id == 'unassigned')
            .amountMinor,
        30000,
      );
    },
  );
  test(
    'same product paid by cash, transfer and credit reconciles a single sales quantity',
    () async {
      await money();
      final person = await registerDebtor(app, 'Persona sintética');
      final quick = SqliteQuickSalesStore(app, synthetic: true);
      await quick.saveAccount(
        SaveQuickSaleAccount(
          id: 'three',
          label: 'Cuenta mixta',
          expectedRevision: 0,
          debtorId: person,
          lines: [
            for (final entry in [
              'quick-default:EFECTIVO',
              'quick-default:NEQUI',
              QuickPaymentOption.creditId,
            ].indexed)
              QuickSaleLine(
                id: 'line-${entry.$1}',
                productId: 'product',
                quantityText: '1',
                unitPriceMinor: 10000,
                paymentOptionId: entry.$2,
              ),
          ],
        ),
      );
      await quick.prepareSale(
        commandId: 'three-sale',
        accountId: 'three',
        expectedRevision: 1,
        occurredAtUtc: at,
      );
      await quick.confirmPrepared('three-sale');
      final data = await reports.load(period());
      expect(data.products().single.quantity, 3);
      expect(data.sales.single.cashMinor, 10000);
      expect(data.sales.single.transferMinor, 10000);
      expect(data.sales.single.creditMinor, 10000);
      expect(data.salesMinor, 30000);
      expect(data.saleTotals.cashTotalMinor, 10000);
      expect(data.saleTotals.transferTotalMinor, 10000);
      expect(data.saleTotals.creditTotalMinor, 10000);
      expect(data.saleTotals.totalMinor, 30000);
      expect(data.saleReceiptsMinor, 20000);
      expect(data.debtorPaymentsMinor, 0);
      expect(data.creditSalesMinor, 10000);
      expect(data.debtClosingMinor, 40000);
    },
  );
  test(
    'large valid turnover rejects an overflowing report without changing stored operations',
    () async {
      await money();
      const amount = 6000000000000000000;
      final operations = SqliteTreasuryOperationStore(app, synthetic: true);
      await operations.ensureDefaults();
      final cash = (await operations.load()).accounts.singleWhere(
        (a) => a.name == 'Caja',
      );
      await sell('turnover-first', price: amount);
      await operations.prepare(
        TreasuryOperationCommand(
          commandId: 'turnover-expense',
          kind: TreasuryOperationKind.expense,
          sourceAccountId: cash.id,
          amountMinor: amount,
          reason: 'Otro',
          occurredAtUtc: at.add(const Duration(minutes: 1)),
        ),
      );
      await operations.confirmPrepared('turnover-expense');
      await sell(
        'turnover-second',
        price: amount,
        date: at.add(const Duration(minutes: 2)),
      );
      final before = await rows();
      await expectLater(
        reports.load(period()),
        throwsA(isA<ReportsValidationException>()),
      );
      expect(await rows(), before);
      expect(
        (await operations.load()).accounts
            .singleWhere((a) => a.name == 'Caja')
            .balanceMinor,
        6000000000000100000,
      );
    },
  );
}
