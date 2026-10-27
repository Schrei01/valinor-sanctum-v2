import 'dart:math';

bool isDayPassName(String name) =>
    name.trim().toLowerCase().replaceAll('í', 'i') == 'pasadia';

/// Immutable catalog and receipt data. Monetary fields use the profile's minor
/// unit; the adapter validates their range and profile before persisting.
class InventoryCategory {
  const InventoryCategory({
    required this.id,
    required this.name,
    this.isActive = true,
  });
  final String id;
  final String name;
  final bool isActive;
}

class InventorySupplier {
  const InventorySupplier({
    required this.id,
    required this.name,
    this.isActive = true,
  });
  final String id;
  final String name;
  final bool isActive;
}

class CatalogProduct {
  const CatalogProduct({
    required this.id,
    required this.name,
    this.sku,
    this.categoryId,
    required this.listPriceMinor,
    this.isActive = true,
    this.isEvent = false,
    this.isService = false,
  });
  final String id;
  final String name;
  final String? sku;
  final String? categoryId;
  final int listPriceMinor;
  final bool isActive;
  final bool isEvent;
  final bool isService;
  bool get isUnlimited => isEvent || isService;
}

class StockPosition {
  const StockPosition({
    required this.productId,
    required this.quantity,
    required this.totalCostMinor,
  });
  final String productId;
  final int quantity;
  final int totalCostMinor;
}

class PurchaseReceiptLine {
  const PurchaseReceiptLine({
    required this.productName,
    required this.quantity,
    required this.totalCostMinor,
  });
  final String productName;
  final int quantity;
  final int totalCostMinor;
}

class PurchaseReceiptSummary {
  PurchaseReceiptSummary({
    required this.documentId,
    required this.supplierName,
    this.reference,
    required this.totalMinor,
    this.paidMinor = 0,
    required this.receivedAtUtc,
    required this.dueDate,
    List<PurchaseReceiptLine> lines = const [],
  }) : lines = List.unmodifiable(lines);
  final String documentId;
  final String supplierName;
  final String? reference;
  final int totalMinor;
  final int paidMinor;
  int get remainingMinor => totalMinor - paidMinor;
  final DateTime receivedAtUtc;
  final String dueDate;
  final List<PurchaseReceiptLine> lines;
}

class InventorySnapshot {
  InventorySnapshot({
    required List<InventoryCategory> categories,
    required List<InventorySupplier> suppliers,
    required List<CatalogProduct> products,
    required List<StockPosition> stock,
    required List<PurchaseReceiptSummary> receipts,
    Map<String, List<String>> productSupplierIds = const {},
  }) : categories = List.unmodifiable(categories),
       suppliers = List.unmodifiable(suppliers),
       products = List.unmodifiable(products),
       stock = List.unmodifiable(stock),
       receipts = List.unmodifiable(receipts),
       productSupplierIds = Map.unmodifiable({
         for (final entry in productSupplierIds.entries)
           entry.key: List<String>.unmodifiable(entry.value),
       });
  final List<InventoryCategory> categories;
  final List<InventorySupplier> suppliers;
  final List<CatalogProduct> products;
  final List<StockPosition> stock;
  final List<PurchaseReceiptSummary> receipts;

  /// Suppliers that have delivered this product in posted inventory receipts.
  final Map<String, List<String>> productSupplierIds;
}

class ReceiptLineInput {
  const ReceiptLineInput({
    required this.productId,
    required this.quantity,
    required this.totalCostMinor,
  });
  final String productId;
  final int quantity;
  final int totalCostMinor;
}

class ReceiptCommand {
  ReceiptCommand({
    required this.commandId,
    required this.supplierId,
    required List<ReceiptLineInput> lines,
    this.reference,
    required this.dueDate,
    required this.occurredAtUtc,
  }) : lines = List.unmodifiable(lines);
  final String commandId;
  final String supplierId;
  final List<ReceiptLineInput> lines;
  final String? reference;
  final String dueDate;
  final DateTime occurredAtUtc;
}

class ReceiptResult {
  const ReceiptResult({
    required this.documentId,
    required this.commandId,
    required this.totalMinor,
  });
  final String documentId;
  final String commandId;
  final int totalMinor;
}

abstract interface class InventoryStore {
  Future<InventorySnapshot> load();
  Future<void> saveCategory(InventoryCategory category);
  Future<void> saveSupplier(InventorySupplier supplier);
  Future<void> saveProduct(CatalogProduct product);
  Future<ReceiptResult> receivePurchase(ReceiptCommand command);
}

/// A deterministic validation rejection. No receipt was committed by this
/// invocation. Unknown storage failures deliberately do not use this type.
class InventoryValidationException implements Exception {
  const InventoryValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract final class InventoryIds {
  static final Random _random = Random.secure();
  static String next() => List.generate(
    16,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}
