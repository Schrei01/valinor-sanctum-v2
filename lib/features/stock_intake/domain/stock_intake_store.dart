import '../../inventory/domain/inventory_store.dart';

String _displayPurchasePaymentLabel(String label) =>
    label.trim().toLowerCase() == 'nequi' ? 'Transferencia' : label;

class IntakePaymentOption {
  const IntakePaymentOption({
    required this.id,
    required this.label,
    required this.cashAccountId,
    required this.paymentMethodId,
    required this.balanceMinor,
    required this.openingRecorded,
    required this.canRecordOpening,
    this.isActive = true,
  });
  final String id;
  final String label;
  final String cashAccountId;
  final String paymentMethodId;
  final int balanceMinor;
  final bool openingRecorded;
  final bool canRecordOpening;
  final bool isActive;

  /// Purchases uses a local label without renaming the monetary identity.
  String get displayLabel => _displayPurchasePaymentLabel(label);
}

class StockIntakeCommand {
  const StockIntakeCommand({
    required this.commandId,
    required this.productId,
    this.expectedProduct,
    required this.productName,
    this.sku,
    required this.categoryId,
    this.supplierId,
    required this.supplierName,
    required this.unitPurchasePriceMinor,
    required this.listPriceMinor,
    required this.quantity,
    required this.paymentOptionId,
    required this.occurredAtUtc,
  });
  final String commandId;
  // A new product gets a fresh ID before preparing. An existing product also
  // carries the exact catalog snapshot the operator edited, for conflict checks.
  final String productId;
  final CatalogProduct? expectedProduct;
  final String productName;
  final String? sku;
  final String categoryId;
  final String? supplierId;
  final String supplierName;
  final int unitPurchasePriceMinor;
  final int listPriceMinor;
  final int quantity;
  final String paymentOptionId;
  final DateTime occurredAtUtc;
}

class PreparedStockIntake {
  const PreparedStockIntake({
    required this.command,
    required this.status,
    required this.preparedAtUtc,
    this.rejectionReason,
  });
  final StockIntakeCommand command;
  final String status;
  final DateTime preparedAtUtc;
  final String? rejectionReason;
}

class StockIntakeResult {
  const StockIntakeResult({
    required this.commandId,
    required this.productId,
    required this.purchaseDocumentId,
    required this.paymentDocumentId,
    required this.totalCostMinor,
  });
  final String commandId;
  final String productId;
  final String purchaseDocumentId;
  final String paymentDocumentId;
  final int totalCostMinor;
}

class StockIntakeEntry {
  const StockIntakeEntry({
    required this.commandId,
    required this.productId,
    required this.productName,
    this.sku,
    required this.categoryName,
    required this.supplierName,
    required this.quantity,
    required this.unitPurchasePriceMinor,
    required this.listPriceMinor,
    required this.totalCostMinor,
    required this.paymentLabel,
    required this.occurredAtUtc,
  });
  final String commandId;
  final String productId;
  final String productName;
  final String? sku;
  final String categoryName;
  final String supplierName;
  final int quantity;
  final int unitPurchasePriceMinor;
  final int listPriceMinor;
  final int totalCostMinor;
  final String paymentLabel;
  final DateTime occurredAtUtc;

  /// Keep the recorded label intact while using the current purchases wording.
  String get displayPaymentLabel => _displayPurchasePaymentLabel(paymentLabel);
}

/// Suggested values from the latest posted receipt or initial inventory.
/// A missing unit cost is distinct from a documented zero cost. Supplier fields
/// are present only while that supplier can still be selected for a new intake.
class ProductIntakeDefaults {
  const ProductIntakeDefaults({
    this.supplierId,
    this.supplierName,
    this.unitPurchasePriceMinor,
  });
  final String? supplierId;
  final String? supplierName;
  final int? unitPurchasePriceMinor;
}

class StockIntakeSnapshot {
  StockIntakeSnapshot({
    required List<InventoryCategory> categories,
    required List<InventorySupplier> suppliers,
    required List<CatalogProduct> products,
    required List<StockPosition> stock,
    required List<IntakePaymentOption> paymentOptions,
    required List<PreparedStockIntake> pendingIntakes,
    required List<StockIntakeEntry> entries,
    Map<String, ProductIntakeDefaults> productDefaults = const {},
  }) : categories = List.unmodifiable(categories),
       suppliers = List.unmodifiable(suppliers),
       products = List.unmodifiable(products),
       stock = List.unmodifiable(stock),
       paymentOptions = List.unmodifiable(paymentOptions),
       pendingIntakes = List.unmodifiable(pendingIntakes),
       entries = List.unmodifiable(entries),
       productDefaults = Map.unmodifiable(productDefaults);
  final List<InventoryCategory> categories;
  final List<InventorySupplier> suppliers;
  final List<CatalogProduct> products;
  final List<StockPosition> stock;
  final List<IntakePaymentOption> paymentOptions;
  final List<PreparedStockIntake> pendingIntakes;
  final List<StockIntakeEntry> entries;
  final Map<String, ProductIntakeDefaults> productDefaults;
}

class CashOpeningCommand {
  const CashOpeningCommand({
    required this.commandId,
    required this.paymentOptionId,
    required this.amountMinor,
    required this.occurredAtUtc,
  });
  final String commandId;
  final String paymentOptionId;
  final int amountMinor;
  final DateTime occurredAtUtc;
}

abstract interface class StockIntakeStore {
  Future<void> ensureDefaults();
  Future<StockIntakeSnapshot> load();
  Future<PreparedStockIntake> prepare(StockIntakeCommand command);
  Future<StockIntakeResult> confirmPrepared(String commandId);
  Future<void> discardRejected(String commandId);
  // One explicitly declared positive opening per money account. The command
  // identity and unique account constraint make uncertain retries safe.
  Future<void> recordOpeningBalance(CashOpeningCommand command);
}

class StockIntakeValidationException implements Exception {
  const StockIntakeValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}
