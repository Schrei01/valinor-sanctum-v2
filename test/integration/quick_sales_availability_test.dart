import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/data/sqlite_quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/quick_sales_store.dart';
import 'quick_sales_store_test.dart' show fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'selling the last units removes a product from choices and replenishment restores its real quantity',
    () async {
      final app = await AppDatabase.open(path: inMemoryDatabasePath);
      try {
        await fixture(app);
        final store = SqliteQuickSalesStore(app, synthetic: true);
        await store.ensureDefaults();
        final initial = await store.load();
        expect(initial.availableProducts.single.id, 'product');
        expect(initial.stockQuantityFor('product'), 10);
        await store.saveAccount(
          SaveQuickSaleAccount(
            id: 'all-stock',
            label: 'Venta sintética',
            expectedRevision: 0,
            lines: const [
              QuickSaleLine(
                id: 'line',
                productId: 'product',
                quantityText: '10',
                unitPriceMinor: 10000,
                paymentOptionId: 'quick-default:EFECTIVO',
              ),
            ],
          ),
        );
        await store.prepareSale(
          commandId: 'sell-all',
          accountId: 'all-stock',
          expectedRevision: 1,
          occurredAtUtc: DateTime.utc(2026, 10, 19, 12),
        );
        await store.confirmPrepared('sell-all');
        final empty = await store.load();
        expect(empty.stockQuantityFor('product'), 0);
        expect(empty.availableProducts, isEmpty);
        expect(empty.products.single.id, 'product');
        expect(empty.sales.single.lines.single.quantity, 10);
        await SqliteInventoryStore(app, synthetic: true).receivePurchase(
          ReceiptCommand(
            commandId: 'restock',
            supplierId: 'supplier',
            occurredAtUtc: DateTime.utc(2026, 10, 19, 13),
            dueDate: '2026-10-20',
            lines: const [
              ReceiptLineInput(
                productId: 'product',
                quantity: 2,
                totalCostMinor: 2000,
              ),
            ],
          ),
        );
        final replenished = await store.load();
        expect(replenished.availableProducts.single.id, 'product');
        expect(replenished.stockQuantityFor('product'), 2);
        expect(replenished.sales.single.lines.single.quantity, 10);
      } finally {
        await app.close();
      }
    },
  );
}
