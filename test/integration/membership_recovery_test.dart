import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/features/debtors/data/sqlite_debtors_store.dart';
import 'package:valinor_sanctum_2/features/debtors/domain/debtors_store.dart';
import 'package:valinor_sanctum_2/features/memberships/data/sqlite_membership_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/data/sqlite_quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/account_payment_split.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_store.dart';
import 'quick_sales_store_test.dart' show fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'durable registration and divided voucher consumption survive reopen; repayments never restore the grant',
    () async {
      final folder = await Directory(
        p.join(AppConfig.repositoryRootPath, 'tmp'),
      ).createTemp('membership-reopen-');
      final path = p.join(folder.path, 'sanctum2.sqlite3');
      AppDatabase? app;
      try {
        app = await AppDatabase.open(path: path);
        await fixture(app, moneyScale: 0);
        var sales = SqliteQuickSalesStore(app, synthetic: true),
            members = SqliteMembershipStore(app, synthetic: true);
        await sales.ensureDefaults();
        await sales.ensureBulkProducts();
        final person = await members.savePerson(
          commandId: 'member',
          name: 'Cliente de prueba',
          email: 'test@example.com',
          birthDay: 12,
          birthMonth: 11,
        );
        final now = DateTime.now().toUtc();
        final account = await sales.saveAccount(
          SaveQuickSaleAccount(
            id: 'signup',
            label: 'Cliente de prueba',
            customerName: 'Cliente de prueba',
            debtorId: person,
            expectedRevision: 0,
            lines: const [
              QuickSaleLine(
                id: 'signup-line',
                productId: SqliteMembershipStore.productId,
                unitPriceMinor: 109000,
                paymentOptionId: QuickPaymentOption.creditId,
              ),
            ],
          ),
        );
        await sales.prepareSale(
          commandId: 'signup-sale',
          accountId: account.id,
          expectedRevision: account.revision,
          occurredAtUtc: now,
        );
        await app.close();
        app = await AppDatabase.open(path: path);
        sales = SqliteQuickSalesStore(app, synthetic: true);
        members = SqliteMembershipStore(app, synthetic: true);
        expect((await members.load()).single.periodId, isNull);
        await sales.confirmPrepared('signup-sale');
        await sales.confirmPrepared('signup-sale');
        final period = (await members.load()).single.periodId!;
        final inventory = SqliteInventoryStore(app, synthetic: true);
        await inventory.saveProduct(
          const CatalogProduct(
            id: 'booster',
            name: 'Booster Pokémon',
            listPriceMinor: 25000,
          ),
        );
        await inventory.receivePurchase(
          ReceiptCommand(
            commandId: 'stock',
            supplierId: 'supplier',
            occurredAtUtc: now,
            dueDate: now.toIso8601String().substring(0, 10),
            lines: const [
              ReceiptLineInput(
                productId: 'booster',
                quantity: 3,
                totalCostMinor: 30000,
              ),
            ],
          ),
        );
        final a = QuickSaleAccount(
          id: 'discount',
          label: 'Cliente de prueba',
          customerName: 'Cliente de prueba',
          debtorId: person,
          revision: 0,
          status: 'open',
          updatedAtUtc: now,
          lines: [
            QuickSaleLine(
              id: 'discount-line',
              productId: 'booster',
              unitPriceMinor: 40000,
              useVoucher: true,
              voucherMinor: 30000,
              voucherPeriodId: period,
            ),
          ],
        );
        final lines = allocateAccountPayments(a, const [
          QuickLinePaymentPart('quick-default:EFECTIVO', 5000),
          QuickLinePaymentPart(QuickPaymentOption.creditId, 5000),
        ]);
        final saved = await sales.saveAccount(
          SaveQuickSaleAccount(
            id: a.id,
            label: a.label,
            customerName: a.customerName,
            debtorId: person,
            expectedRevision: 0,
            lines: lines,
            paymentMode: 'split',
            paymentSplitBasis: quickConsumptionKey(lines),
          ),
        );
        await sales.prepareSale(
          commandId: 'discount-sale',
          accountId: saved.id,
          expectedRevision: saved.revision,
          occurredAtUtc: now,
        );
        await app.close();
        app = await AppDatabase.open(path: path);
        sales = SqliteQuickSalesStore(app, synthetic: true);
        members = SqliteMembershipStore(app, synthetic: true);
        expect(
          (await sales.load()).accounts.single.lines.single.useVoucher,
          isTrue,
        );
        await sales.confirmPrepared('discount-sale');
        await sales.confirmPrepared('discount-sale');
        await sales.confirmPrepared('discount-sale');
        await app.close();
        app = await AppDatabase.open(path: path);
        sales = SqliteQuickSalesStore(app, synthetic: true);
        members = SqliteMembershipStore(app, synthetic: true);
        await sales.confirmPrepared('discount-sale');
        final debtors = SqliteDebtorsStore(app, synthetic: true);
        await debtors.prepare(
          DebtorCommand(
            commandId: 'repay',
            kind: 'payment',
            debtorId: person,
            amountMinor: 10000,
            paymentOptionId: 'quick-default:NEQUI',
            occurredAtUtc: now,
          ),
        );
        await debtors.confirm('repay');
        await debtors.confirm('repay');
        expect((await debtors.load()).debtors.single.balanceMinor, 104000);
        final treasury = await SqliteTreasuryStore(app).load();
        expect(treasury.cashMinor, 5000);
        expect(treasury.nequiMinor, 10000);
        expect((await sales.load()).stockQuantityFor('booster'), 2);
        final member = (await members.load()).single;
        expect(member.voucherUsedMinor, 30000);
        expect(member.voucherRemainingMinor, 0);
        expect(await app.database.query('membership_periods'), hasLength(1));
        expect(
          await app.database.rawQuery('PRAGMA foreign_key_check'),
          isEmpty,
        );
      } finally {
        await app?.close();
        if (!p.isWithin(
          p.join(AppConfig.repositoryRootPath, 'tmp'),
          await folder.resolveSymbolicLinks(),
        )) {
          throw StateError('Unsafe cleanup');
        }
        await folder.delete(recursive: true);
      }
    },
  );
}
