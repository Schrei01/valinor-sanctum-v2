import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/features/memberships/data/sqlite_membership_store.dart';
import 'package:valinor_sanctum_2/features/memberships/domain/membership.dart';
import 'package:valinor_sanctum_2/features/quick_sales/data/sqlite_quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/account_payment_split.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/debtors/data/sqlite_debtors_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_store.dart';
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
      commandId: 'create-member',
      name: 'Miembro sintético',
      email: 'member@example.com',
      birthDay: 29,
      birthMonth: 2,
    );
    final inventory = SqliteInventoryStore(app, synthetic: true);
    await inventory.saveProduct(
      const CatalogProduct(
        id: 'booster',
        name: 'Booster Magic',
        listPriceMinor: 25000,
      ),
    );
    await inventory.receivePurchase(
      ReceiptCommand(
        commandId: 'boosters-in',
        supplierId: 'supplier',
        occurredAtUtc: DateTime.utc(2026, 10, 19, 11),
        dueDate: '2026-10-20',
        lines: const [
          ReceiptLineInput(
            productId: 'booster',
            quantity: 10,
            totalCostMinor: 100000,
          ),
        ],
      ),
    );
  });
  tearDown(() => app.close());
  Future<QuickSaleAccount> account(
    String id,
    List<QuickSaleLine> lines, {
    bool split = false,
    String? owner,
  }) async {
    final a = QuickSaleAccount(
      id: id,
      label: 'Miembro sintético',
      revision: 0,
      status: 'open',
      updatedAtUtc: now,
      customerName: 'Miembro sintético',
      debtorId: owner ?? person,
      lines: lines,
    );
    final allocated = split
        ? allocateAccountPayments(a, const [
            QuickLinePaymentPart('quick-default:EFECTIVO', 60000),
            QuickLinePaymentPart(QuickPaymentOption.creditId, 49000),
          ])
        : lines;
    return sales.saveAccount(
      SaveQuickSaleAccount(
        id: id,
        label: a.label,
        expectedRevision: 0,
        customerName: a.customerName,
        debtorId: a.debtorId,
        lines: allocated,
        paymentMode: split ? 'split' : 'legacy',
        paymentSplitBasis: split ? quickConsumptionKey(allocated) : '',
      ),
    );
  }

  QuickSaleLine signup(String id) => QuickSaleLine(
    id: id,
    productId: SqliteMembershipStore.productId,
    unitPriceMinor: 109000,
    paymentOptionId: QuickPaymentOption.creditId,
  );
  QuickSaleLine booster(
    String id, {
    int qty = 1,
    int price = 20000,
    bool discount = true,
  }) => QuickSaleLine(
    id: id,
    productId: 'booster',
    quantityText: '$qty',
    unitPriceMinor: price,
    paymentOptionId: 'quick-default:EFECTIVO',
    membershipDiscount: discount,
  );
  Future<void> prepare(String id, QuickSaleAccount a) => sales.prepareSale(
    commandId: id,
    accountId: a.id,
    expectedRevision: a.revision,
    occurredAtUtc: now,
  );
  Future<void> enroll() async {
    final a = await account('signup', [signup('member-line')]);
    await prepare('enroll', a);
    await sales.confirmPrepared('enroll');
  }

  test('calendar boundaries, leap year, timezone and expiry are exclusive', () {
    expect(
      membershipNextMonth(DateTime.utc(2026, 1, 31)),
      DateTime.utc(2026, 2, 28),
    );
    expect(
      membershipNextMonth(DateTime.utc(2028, 1, 31)),
      DateTime.utc(2028, 2, 29),
    );
    expect(
      membershipNextMonth(DateTime.utc(2026, 12, 12)),
      DateTime.utc(2027, 1, 12),
    );
    expect(
      membershipDay(DateTime.utc(2026, 11, 12, 4, 59)),
      DateTime.utc(2026, 11, 11),
    );
    final m = Membership(
      personId: 'x',
      name: 'X',
      email: '',
      starts: DateTime.utc(2026, 11, 12),
      ends: DateTime.utc(2026, 12, 12),
    );
    expect(m.activeAt(DateTime.utc(2026, 12, 12, 4, 59)), isTrue);
    expect(m.activeAt(DateTime.utc(2026, 12, 12, 5)), isFalse);
  });
  test(
    'debt registration activates once and retry creates no second period or debt',
    () async {
      await enroll();
      await sales.confirmPrepared('enroll');
      final m = (await members.load()).single;
      expect(m.activeAt(now), isTrue);
      expect(m.starts, membershipDay(now));
      expect(
        (await SqliteDebtorsStore(
          app,
          synthetic: true,
        ).load()).debtors.single.balanceMinor,
        109000,
      );
      expect((await SqliteTreasuryStore(app).load()).cashMinor, 0);
      expect(await app.database.query('membership_periods'), hasLength(1));
    },
  );
  test('partial payment records only 49000 debt and 60000 cash', () async {
    final a = await account('partial', [signup('p-line')], split: true);
    await prepare('partial-sale', a);
    await sales.confirmPrepared('partial-sale');
    expect((await members.load()).single.activeAt(now), isTrue);
    expect(
      (await SqliteDebtorsStore(
        app,
        synthetic: true,
      ).load()).debtors.single.balanceMinor,
      49000,
    );
    expect((await SqliteTreasuryStore(app).load()).cashMinor, 60000);
  });
  test(
    'included delivery consumes one unit and cost exactly once, never cash',
    () async {
      await enroll();
      final period = (await members.load()).single.periodId!;
      await members.claimIncluded(
        commandId: 'free',
        periodId: period,
        productId: 'booster',
        atUtc: now,
      );
      await members.claimIncluded(
        commandId: 'free',
        periodId: period,
        productId: 'booster',
        atUtc: now,
      );
      expect((await members.load()).single.includedClaimed, isTrue);
      expect((await sales.load()).stockQuantityFor('booster'), 9);
      expect((await SqliteTreasuryStore(app).load()).cashMinor, 0);
      await expectLater(
        members.claimIncluded(
          commandId: 'another-free',
          periodId: period,
          productId: 'booster',
          atUtc: now,
        ),
        throwsA(isA<QuickSalesValidationException>()),
      );
    },
  );
  test('two discounted boosters consume stock and charge 40000 once', () async {
    await enroll();
    final a = await account('discount', [booster('b-line', qty: 2)]);
    await prepare('discount-sale', a);
    await sales.confirmPrepared('discount-sale');
    await sales.confirmPrepared('discount-sale');
    expect((await members.load()).single.discountsUsed, 2);
    expect((await sales.load()).stockQuantityFor('booster'), 8);
    expect((await SqliteTreasuryStore(app).load()).cashMinor, 40000);
    final b = await account('over', [booster('over-line')]);
    await expectLater(
      prepare('over-sale', b),
      throwsA(isA<QuickSalesValidationException>()),
    );
    expect(
      await app.database.query(
        'membership_sale_plans',
        where: 'request_id=?',
        whereArgs: ['over-sale'],
      ),
      isEmpty,
    );
  });
  test(
    'competing prepared accounts cannot use the same two discounts',
    () async {
      await enroll();
      final a = await account('first', [booster('first-line', qty: 2)]),
          b = await account('second', [booster('second-line', qty: 2)]);
      await prepare('first-sale', a);
      await prepare('second-sale', b);
      await sales.confirmPrepared('first-sale');
      await expectLater(
        sales.confirmPrepared('second-sale'),
        throwsA(isA<QuickSalesValidationException>()),
      );
      expect((await sales.load()).stockQuantityFor('booster'), 8);
      expect((await SqliteTreasuryStore(app).load()).cashMinor, 40000);
      expect((await members.load()).single.discountsUsed, 2);
    },
  );
  test(
    'renewal appends a calendar period and does not reset current benefits',
    () async {
      await enroll();
      final current = (await members.load()).single;
      await members.claimIncluded(
        commandId: 'free',
        periodId: current.periodId!,
        productId: 'booster',
        atUtc: now,
      );
      final a = await account('renew', [signup('renew-line')]);
      await prepare('renew-sale', a);
      await sales.confirmPrepared('renew-sale');
      final rows = await app.database.query(
        'membership_periods',
        orderBy: 'starts',
      );
      expect(rows, hasLength(2));
      expect(rows.last['starts'], rows.first['ends']);
      expect((await members.load()).single.includedClaimed, isTrue);
      final next = DateTime.parse('${rows.last['starts']}T05:00:00Z');
      final renewed = (await members.load(atUtc: next)).single;
      expect(renewed.activeAt(next), isTrue);
      expect(renewed.includedClaimed, isFalse);
      expect(renewed.discountsUsed, 0);
    },
  );
  test(
    'wrong booster, invalid price, missing profile and inactive membership are rejected',
    () async {
      await expectLater(
        account('no-profile', [signup('no-profile-line')], owner: 'missing'),
        throwsA(isA<QuickSalesValidationException>()),
      );
      final a = await account('no-membership', [booster('inactive')]);
      await expectLater(
        prepare('inactive-sale', a),
        throwsA(isA<QuickSalesValidationException>()),
      );
      await enroll();
      final b = await account('wrong-price', [
        booster('wrong-price-line', price: 19999),
      ]);
      await expectLater(
        prepare('wrong-price-sale', b),
        throwsA(isA<QuickSalesValidationException>()),
      );
      await expectLater(
        members.claimIncluded(
          commandId: 'bad-free',
          periodId: (await members.load()).single.periodId!,
          productId: 'product',
          atUtc: now,
        ),
        throwsA(isA<QuickSalesValidationException>()),
      );
      expect(await app.database.query('membership_benefits'), isEmpty);
    },
  );
  test(
    'profile validates real birthdays and updates a registered debtor without duplication',
    () async {
      await members.savePerson(
        commandId: 'edit',
        personId: person,
        name: 'Miembro sintético',
        email: 'new@example.com',
        birthDay: 31,
        birthMonth: 12,
      );
      expect((await members.load()).single.email, 'new@example.com');
      expect((await app.database.query('debtors')), hasLength(1));
      await expectLater(
        members.savePerson(
          commandId: 'bad',
          personId: person,
          name: 'X',
          email: 'bad',
          birthDay: 31,
          birthMonth: 4,
        ),
        throwsA(isA<QuickSalesValidationException>()),
      );
      expect(SqliteMembershipStore.eligible('Booster Heroclix'), isFalse);
      for (final n in [
        'Booster Magic',
        'Booster Pokémon',
        'Booster Yu-Gi-Oh!',
      ]) {
        expect(SqliteMembershipStore.eligible(n), isTrue);
      }
    },
  );
}
