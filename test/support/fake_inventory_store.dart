import 'dart:async';

import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';

class FakeInventoryStore implements InventoryStore {
  final categories = <InventoryCategory>[];
  final suppliers = <InventorySupplier>[];
  final products = <CatalogProduct>[];
  final stock = <StockPosition>[];
  final receipts = <PurchaseReceiptSummary>[];
  final receivedCommands = <ReceiptCommand>[];
  final savedProducts = <CatalogProduct>[];
  final savedCategoryIds = <String>[];
  final _results = <String, ReceiptResult>{};
  Object? loadFailure;
  Object? saveFailure;
  Object? receiveFailure;
  bool commitBeforeReceiveFailure = false;
  Completer<void>? receiveGate;
  Completer<void>? saveGate;
  int saves = 0;

  @override
  Future<InventorySnapshot> load() async {
    if (loadFailure != null) throw loadFailure!;
    return InventorySnapshot(
      categories: categories,
      suppliers: suppliers,
      products: products,
      stock: stock,
      receipts: receipts,
    );
  }

  Future<void> _save() async {
    saves++;
    if (saveGate != null) await saveGate!.future;
    if (saveFailure != null) throw saveFailure!;
  }

  @override
  Future<void> saveCategory(InventoryCategory category) async {
    savedCategoryIds.add(category.id);
    await _save();
    categories.removeWhere((item) => item.id == category.id);
    categories.add(category);
  }

  @override
  Future<void> saveSupplier(InventorySupplier supplier) async {
    await _save();
    suppliers.removeWhere((item) => item.id == supplier.id);
    suppliers.add(supplier);
  }

  @override
  Future<void> saveProduct(CatalogProduct product) async {
    savedProducts.add(product);
    await _save();
    products.removeWhere((item) => item.id == product.id);
    products.add(product);
  }

  @override
  Future<ReceiptResult> receivePurchase(ReceiptCommand command) async {
    receivedCommands.add(command);
    if (receiveGate != null) await receiveGate!.future;
    final existing = _results[command.commandId];
    if (existing != null) return existing;
    if (receiveFailure != null && !commitBeforeReceiveFailure) {
      throw receiveFailure!;
    }
    final total = command.lines.fold<int>(
      0,
      (sum, line) => sum + line.totalCostMinor,
    );
    final result = ReceiptResult(
      documentId: 'document-${command.commandId}',
      commandId: command.commandId,
      totalMinor: total,
    );
    _results[command.commandId] = result;
    for (final line in command.lines) {
      final old = stock
          .where((item) => item.productId == line.productId)
          .firstOrNull;
      stock.removeWhere((item) => item.productId == line.productId);
      stock.add(
        StockPosition(
          productId: line.productId,
          quantity: (old?.quantity ?? 0) + line.quantity,
          totalCostMinor: (old?.totalCostMinor ?? 0) + line.totalCostMinor,
        ),
      );
    }
    receipts.insert(
      0,
      PurchaseReceiptSummary(
        documentId: result.documentId,
        supplierName: suppliers
            .firstWhere((item) => item.id == command.supplierId)
            .name,
        reference: command.reference,
        totalMinor: total,
        receivedAtUtc: command.occurredAtUtc,
        dueDate: command.dueDate,
        lines: [
          for (final line in command.lines)
            PurchaseReceiptLine(
              productName: products
                  .firstWhere((item) => item.id == line.productId)
                  .name,
              quantity: line.quantity,
              totalCostMinor: line.totalCostMinor,
            ),
        ],
      ),
    );
    if (receiveFailure != null) throw receiveFailure!;
    return result;
  }
}
