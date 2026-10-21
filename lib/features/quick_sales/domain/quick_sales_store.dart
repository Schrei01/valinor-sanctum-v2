import '../../inventory/domain/inventory_store.dart';

String _displaySalesPaymentLabel(String label) =>
    label.trim().toLowerCase() == 'nequi' ? 'Transferencia' : label;

class QuickSaleLine {
  const QuickSaleLine({
    required this.id,
    this.productId,
    this.quantityText = '1',
    this.unitPriceMinor,
    this.paymentOptionId,
  });
  final String id;
  final String? productId;
  final String quantityText;
  final int? unitPriceMinor;
  final String? paymentOptionId;
}

class QuickSaleAccount {
  QuickSaleAccount({
    required this.id,
    required this.label,
    required this.revision,
    required this.status,
    required this.updatedAtUtc,
    required List<QuickSaleLine> lines,
    this.customerName = '',
    this.confirmedDocumentId,
  }) : lines = List.unmodifiable(lines);
  final String id;
  final String label;
  final String customerName;
  final int revision;
  final String status;
  final DateTime updatedAtUtc;
  final List<QuickSaleLine> lines;
  final String? confirmedDocumentId;
}

class SaveQuickSaleAccount {
  SaveQuickSaleAccount({
    required this.id,
    required this.label,
    required this.expectedRevision,
    required List<QuickSaleLine> lines,
    this.customerName = '',
  }) : lines = List.unmodifiable(lines);
  final String id;
  final String label;
  final String customerName;
  final int expectedRevision;
  final List<QuickSaleLine> lines;
}

class QuickPaymentOption {
  static const creditId = 'quick-debt';

  const QuickPaymentOption({
    required this.id,
    required this.label,
    required this.cashAccountId,
    required this.paymentMethodId,
    this.isActive = true,
    this.isCredit = false,
  });
  final String id;
  final String label;
  final String cashAccountId;
  final String paymentMethodId;
  final bool isActive;
  final bool isCredit;

  /// Sales wording does not rename the stored payment or monetary account.
  String get displayLabel => _displaySalesPaymentLabel(label);
}

class PreparedQuickSale {
  const PreparedQuickSale({
    required this.commandId,
    required this.accountId,
    required this.accountRevision,
    required this.label,
    required this.totalMinor,
    required this.occurredAtUtc,
    required this.preparedAtUtc,
    required this.status,
    this.rejectionReason,
    this.creditMinor = 0,
    this.customerName = '',
  });
  final String commandId;
  final String accountId;
  final int accountRevision;
  final String label;
  final int totalMinor;
  final DateTime occurredAtUtc;
  final DateTime preparedAtUtc;
  final String status;
  final String? rejectionReason;
  final int creditMinor;
  final String customerName;
}

class QuickSaleResult {
  const QuickSaleResult({
    required this.commandId,
    required this.saleDocumentId,
    required this.collectionDocumentId,
    required this.totalMinor,
    required this.totalCostMinor,
    this.creditMinor = 0,
    this.customerName = '',
  });
  final String commandId;
  final String saleDocumentId;
  final String? collectionDocumentId;
  final int totalMinor;
  final int totalCostMinor;
  final int creditMinor;
  final String customerName;
}

class ConfirmedQuickSaleLine {
  const ConfirmedQuickSaleLine({
    required this.productName,
    required this.quantity,
    required this.unitPriceMinor,
    required this.totalMinor,
    required this.paymentLabel,
    this.isCredit = false,
  });
  final String productName;
  final int quantity;
  final int unitPriceMinor;
  final int totalMinor;
  final String paymentLabel;
  final bool isCredit;

  String get displayPaymentLabel => _displaySalesPaymentLabel(paymentLabel);
}

class ConfirmedQuickSale {
  ConfirmedQuickSale({
    required this.commandId,
    required this.label,
    required this.soldAtUtc,
    required this.result,
    required List<ConfirmedQuickSaleLine> lines,
  }) : lines = List.unmodifiable(lines);
  final String commandId;
  final String label;
  final DateTime soldAtUtc;
  final QuickSaleResult result;
  final List<ConfirmedQuickSaleLine> lines;
}

class QuickSalesSnapshot {
  QuickSalesSnapshot({
    required List<QuickSaleAccount> accounts,
    required List<CatalogProduct> products,
    required List<StockPosition> stock,
    required List<QuickPaymentOption> paymentOptions,
    required List<PreparedQuickSale> pendingSales,
    required List<ConfirmedQuickSale> sales,
  }) : accounts = List.unmodifiable(accounts),
       products = List.unmodifiable(products),
       stock = List.unmodifiable(stock),
       paymentOptions = List.unmodifiable(paymentOptions),
       pendingSales = List.unmodifiable(pendingSales),
       sales = List.unmodifiable(sales);
  final List<QuickSaleAccount> accounts;
  final List<CatalogProduct> products;
  final List<StockPosition> stock;
  final List<QuickPaymentOption> paymentOptions;
  final List<PreparedQuickSale> pendingSales;
  final List<ConfirmedQuickSale> sales;
}

abstract interface class QuickSalesStore {
  Future<void> ensureDefaults();
  Future<QuickSalesSnapshot> load();
  Future<QuickSaleAccount> saveAccount(SaveQuickSaleAccount account);
  Future<void> cancelAccount({
    required String accountId,
    required int expectedRevision,
  });
  Future<PreparedQuickSale> prepareSale({
    required String commandId,
    required String accountId,
    required int expectedRevision,
    required DateTime occurredAtUtc,
  });
  Future<QuickSaleResult> confirmPrepared(String commandId);
  Future<void> discardRejected(String commandId);
}

class QuickSalesValidationException implements Exception {
  const QuickSalesValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}
