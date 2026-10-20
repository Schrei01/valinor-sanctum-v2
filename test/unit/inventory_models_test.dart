import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';

void main() {
  test('snapshot copies and freezes every list', () {
    final categories = [const InventoryCategory(id: 'one', name: 'Una')];
    final supplierIds = ['supplier'];
    final links = {'product': supplierIds};
    final snapshot = InventorySnapshot(
      categories: categories,
      suppliers: [],
      products: [],
      stock: [],
      receipts: [],
      productSupplierIds: links,
    );
    categories.clear();
    supplierIds.clear();
    links.clear();
    expect(snapshot.productSupplierIds['product'], ['supplier']);
    expect(() => snapshot.productSupplierIds.clear(), throwsUnsupportedError);
    expect(
      () => snapshot.productSupplierIds['product']!.clear(),
      throwsUnsupportedError,
    );
    expect(snapshot.categories.single.id, 'one');
    expect(() => snapshot.categories.clear(), throwsUnsupportedError);
    expect(() => snapshot.suppliers.clear(), throwsUnsupportedError);
    expect(() => snapshot.products.clear(), throwsUnsupportedError);
    expect(() => snapshot.stock.clear(), throwsUnsupportedError);
    expect(() => snapshot.receipts.clear(), throwsUnsupportedError);
  });

  test('receipt input preserves an immutable copy for uncertain retry', () {
    final lines = [
      const ReceiptLineInput(
        productId: 'product',
        quantity: 1,
        totalCostMinor: 5,
      ),
    ];
    final command = ReceiptCommand(
      commandId: 'receipt',
      supplierId: 'supplier',
      lines: lines,
      dueDate: '2026-10-19',
      occurredAtUtc: DateTime.utc(2026, 10, 19),
    );
    lines.clear();
    expect(command.lines.single.totalCostMinor, 5);
    expect(() => command.lines.clear(), throwsUnsupportedError);
  });

  test('ids have 128 random bits and safe portable syntax', () {
    final ids = List.generate(1000, (_) => InventoryIds.next());
    expect(ids.toSet(), hasLength(ids.length));
    expect(ids.every((id) => RegExp(r'^[a-f0-9]{32}$').hasMatch(id)), isTrue);
  });
}
