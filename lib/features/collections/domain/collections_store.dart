/// Locally configured destinations. A new account never creates an opening
/// balance; [balanceMinor] contains only posted journal movements.
class CollectionAccount {
  const CollectionAccount({
    required this.id,
    required this.name,
    required this.kind,
    this.isAvailable = true,
    this.isActive = true,
    this.balanceMinor = 0,
  });
  final String id;
  final String name;
  final String kind;
  final bool isAvailable;
  final bool isActive;
  final int balanceMinor;
}

class CollectionMethod {
  const CollectionMethod({
    required this.id,
    required this.code,
    required this.name,
    this.isActive = true,
  });
  final String id;
  final String code;
  final String name;
  final bool isActive;
}

class ReceivableSummary {
  const ReceivableSummary({
    required this.receivableId,
    required this.saleDocumentId,
    required this.label,
    required this.customerName,
    required this.issuedAtUtc,
    required this.dueDate,
    required this.initialMinor,
    required this.collectedMinor,
    required this.remainingMinor,
  });
  final String receivableId;
  final String saleDocumentId;
  final String label;
  final String customerName;
  final DateTime issuedAtUtc;
  final String dueDate;
  final int initialMinor;
  final int collectedMinor;
  final int remainingMinor;
}

class CollectionPartInput {
  const CollectionPartInput({
    required this.cashAccountId,
    required this.paymentMethodId,
    required this.amountMinor,
  });
  final String cashAccountId;
  final String paymentMethodId;
  final int amountMinor;
}

class CollectionCommand {
  CollectionCommand({
    required this.commandId,
    required this.receivableId,
    required this.occurredAtUtc,
    required List<CollectionPartInput> parts,
  }) : parts = List.unmodifiable(parts);
  final String commandId;
  final String receivableId;
  final DateTime occurredAtUtc;
  final List<CollectionPartInput> parts;
}

class CollectionPart {
  const CollectionPart({
    required this.cashAccountId,
    required this.paymentMethodId,
    required this.cashAccountName,
    required this.cashAccountKind,
    required this.paymentMethodCode,
    required this.paymentMethodName,
    required this.amountMinor,
  });
  final String cashAccountId;
  final String paymentMethodId;
  final String cashAccountName;
  final String cashAccountKind;
  final String paymentMethodCode;
  final String paymentMethodName;
  final int amountMinor;
}

class PreparedCollection {
  PreparedCollection({
    required this.commandId,
    required this.receivableId,
    required this.label,
    required this.customerName,
    required this.occurredAtUtc,
    required this.preparedAtUtc,
    required this.status,
    required this.totalMinor,
    required List<CollectionPart> parts,
  }) : parts = List.unmodifiable(parts);
  final String commandId;
  final String receivableId;
  final String label;
  final String customerName;
  final DateTime occurredAtUtc;
  final DateTime preparedAtUtc;

  /// prepared, rejected, cancelled or confirmed. Unknown storage failures keep
  /// the original input prepared so reopening can safely retry the same ID.
  final String status;
  final int totalMinor;
  final List<CollectionPart> parts;
}

class CollectionResult {
  const CollectionResult({
    required this.documentId,
    required this.commandId,
    required this.receivableId,
    required this.totalMinor,
    required this.remainingMinor,
  });
  final String documentId;
  final String commandId;
  final String receivableId;
  final int totalMinor;

  /// Remaining immediately after this commit, not a later live balance.
  final int remainingMinor;
}

class ConfirmedCollection {
  ConfirmedCollection({
    required this.documentId,
    required this.commandId,
    required this.receivableId,
    required this.label,
    required this.customerName,
    required this.collectedAtUtc,
    required this.totalMinor,
    required this.remainingMinor,
    required List<CollectionPart> parts,
  }) : parts = List.unmodifiable(parts);
  final String documentId;
  final String commandId;
  final String receivableId;
  final String label;
  final String customerName;
  final DateTime collectedAtUtc;
  final int totalMinor;
  final int remainingMinor;
  final List<CollectionPart> parts;
}

class CollectionsSnapshot {
  CollectionsSnapshot({
    required List<CollectionAccount> accounts,
    required List<CollectionMethod> methods,
    required List<ReceivableSummary> receivables,
    required List<PreparedCollection> pendingCollections,
    required List<ConfirmedCollection> collections,
  }) : accounts = List.unmodifiable(accounts),
       methods = List.unmodifiable(methods),
       receivables = List.unmodifiable(receivables),
       pendingCollections = List.unmodifiable(pendingCollections),
       collections = List.unmodifiable(collections);
  final List<CollectionAccount> accounts;
  final List<CollectionMethod> methods;
  final List<ReceivableSummary> receivables;
  final List<PreparedCollection> pendingCollections;
  final List<ConfirmedCollection> collections;
}

abstract interface class CollectionsStore {
  Future<CollectionsSnapshot> load();
  Future<void> saveAccount(CollectionAccount account);
  Future<void> saveMethod(CollectionMethod method);
  Future<PreparedCollection> prepareCollection(CollectionCommand command);
  Future<CollectionResult> confirmPrepared(String commandId);
  Future<void> discardRejected(String commandId);
}

/// Deterministic rejection: no payment was committed by this invocation.
class CollectionsValidationException implements Exception {
  const CollectionsValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}
