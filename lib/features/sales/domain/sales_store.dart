import '../../inventory/domain/inventory_store.dart';

class SaleDraftLine {
  const SaleDraftLine({
    required this.productId,
    required this.quantity,
    required this.unitPriceMinor,
  });
  final String productId;
  final int quantity;
  final int unitPriceMinor;
}

class SaleDraft {
  SaleDraft({
    required this.id,
    required this.label,
    required this.customerName,
    required this.revision,
    required this.status,
    required this.updatedAtUtc,
    required List<SaleDraftLine> lines,
    this.confirmedDocumentId,
  }) : lines = List.unmodifiable(lines);
  final String id;
  final String label;
  final String customerName;
  final int revision;

  /// open, prepared or confirmed. Only open drafts are editable.
  final String status;
  final DateTime updatedAtUtc;
  final List<SaleDraftLine> lines;
  final String? confirmedDocumentId;
}

class SaveSaleDraft {
  SaveSaleDraft({
    required this.id,
    required this.label,
    required this.customerName,
    required this.expectedRevision,
    required List<SaleDraftLine> lines,
  }) : lines = List.unmodifiable(lines);
  final String id;
  final String label;
  final String customerName;

  /// Zero creates a draft; an existing draft requires its last saved revision.
  final int expectedRevision;
  final List<SaleDraftLine> lines;
}

class SaleConfirmation {
  const SaleConfirmation({
    required this.commandId,
    required this.draftId,
    required this.draftRevision,
    required this.occurredAtUtc,
    required this.dueDate,
    required this.preparedAtUtc,
    required this.status,
  });
  final String commandId;
  final String draftId;
  final int draftRevision;
  final DateTime occurredAtUtc;
  final String dueDate;
  final DateTime preparedAtUtc;

  /// prepared, rejected, cancelled or confirmed.
  final String status;
}

class SaleResult {
  const SaleResult({
    required this.documentId,
    required this.commandId,
    required this.totalMinor,
    required this.totalCostMinor,
  });
  final String documentId;
  final String commandId;
  final int totalMinor;
  final int totalCostMinor;
}

class ConfirmedSaleLine {
  const ConfirmedSaleLine({
    required this.productName,
    required this.quantity,
    required this.unitPriceMinor,
    required this.totalMinor,
    required this.totalCostMinor,
  });
  final String productName;
  final int quantity;
  final int unitPriceMinor;
  final int totalMinor;
  final int totalCostMinor;
}

class ConfirmedSale {
  ConfirmedSale({
    required this.documentId,
    required this.draftId,
    required this.label,
    required this.customerName,
    required this.soldAtUtc,
    required this.dueDate,
    required this.totalMinor,
    required this.totalCostMinor,
    required List<ConfirmedSaleLine> lines,
    this.paidMinor = 0,
  }) : lines = List.unmodifiable(lines);
  final String documentId;
  final String draftId;
  final String label;
  final String customerName;
  final DateTime soldAtUtc;
  final String dueDate;
  final int totalMinor;
  final int totalCostMinor;
  final List<ConfirmedSaleLine> lines;
  final int paidMinor;
  int get remainingMinor => totalMinor - paidMinor;
}

class SalesSnapshot {
  SalesSnapshot({
    required List<SaleDraft> drafts,
    required List<SaleConfirmation> pendingConfirmations,
    required List<ConfirmedSale> sales,
    required List<CatalogProduct> products,
    required List<StockPosition> stock,
  }) : drafts = List.unmodifiable(drafts),
       pendingConfirmations = List.unmodifiable(pendingConfirmations),
       sales = List.unmodifiable(sales),
       products = List.unmodifiable(products),
       stock = List.unmodifiable(stock);
  final List<SaleDraft> drafts;
  final List<SaleConfirmation> pendingConfirmations;
  final List<ConfirmedSale> sales;
  final List<CatalogProduct> products;
  final List<StockPosition> stock;
}

abstract interface class SalesStore {
  Future<SalesSnapshot> load();
  Future<SaleDraft> saveDraft(SaveSaleDraft draft);

  /// Persists the exact input and locks the draft before committing the sale.
  Future<SaleConfirmation> prepareConfirmation({
    required String commandId,
    required String draftId,
    required int expectedRevision,
    required DateTime occurredAtUtc,
    required String dueDate,
  });

  /// Retries the durable input, returning the same result after a prior commit.
  Future<SaleResult> confirmPrepared(String commandId);

  /// Only a deterministically rejected confirmation may unlock its draft.
  Future<void> discardRejected(String commandId);
}

/// Deterministic rejection: this invocation did not commit a sale. Unknown
/// storage failures deliberately keep the prepared confirmation locked.
class SalesValidationException implements Exception {
  const SalesValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}
