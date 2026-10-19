import '../../collections/domain/collections_store.dart';

class PayableSummary {
  const PayableSummary({
    required this.payableId,
    required this.purchaseDocumentId,
    required this.label,
    required this.supplierName,
    required this.issuedAtUtc,
    required this.dueDate,
    required this.initialMinor,
    required this.paidMinor,
    required this.remainingMinor,
  });
  final String payableId;
  final String purchaseDocumentId;
  final String label;
  final String supplierName;
  final DateTime issuedAtUtc;
  final String dueDate;
  final int initialMinor;
  final int paidMinor;
  final int remainingMinor;
}

class SupplierPaymentPartInput {
  const SupplierPaymentPartInput({
    required this.cashAccountId,
    required this.paymentMethodId,
    required this.amountMinor,
  });
  final String cashAccountId;
  final String paymentMethodId;
  final int amountMinor;
}

class SupplierPaymentCommand {
  SupplierPaymentCommand({
    required this.commandId,
    required this.payableId,
    required this.occurredAtUtc,
    required List<SupplierPaymentPartInput> parts,
  }) : parts = List.unmodifiable(parts);
  final String commandId;
  final String payableId;
  final DateTime occurredAtUtc;
  final List<SupplierPaymentPartInput> parts;
}

class SupplierPaymentPart {
  const SupplierPaymentPart({
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

class PreparedSupplierPayment {
  PreparedSupplierPayment({
    required this.commandId,
    required this.payableId,
    required this.label,
    required this.supplierName,
    required this.occurredAtUtc,
    required this.preparedAtUtc,
    required this.status,
    required this.totalMinor,
    required List<SupplierPaymentPart> parts,
  }) : parts = List.unmodifiable(parts);
  final String commandId;
  final String payableId;
  final String label;
  final String supplierName;
  final DateTime occurredAtUtc;
  final DateTime preparedAtUtc;

  /// prepared, rejected, cancelled or confirmed. Unknown storage failures keep
  /// the original input prepared so reopening can safely retry the same ID.
  final String status;
  final int totalMinor;
  final List<SupplierPaymentPart> parts;
}

class SupplierPaymentResult {
  const SupplierPaymentResult({
    required this.documentId,
    required this.commandId,
    required this.payableId,
    required this.totalMinor,
    required this.remainingMinor,
  });
  final String documentId;
  final String commandId;
  final String payableId;
  final int totalMinor;

  /// Remaining immediately after this commit, not a later live balance.
  final int remainingMinor;
}

class ConfirmedSupplierPayment {
  ConfirmedSupplierPayment({
    required this.documentId,
    required this.commandId,
    required this.payableId,
    required this.label,
    required this.supplierName,
    required this.paidAtUtc,
    required this.totalMinor,
    required this.remainingMinor,
    required List<SupplierPaymentPart> parts,
  }) : parts = List.unmodifiable(parts);
  final String documentId;
  final String commandId;
  final String payableId;
  final String label;
  final String supplierName;
  final DateTime paidAtUtc;
  final int totalMinor;
  final int remainingMinor;
  final List<SupplierPaymentPart> parts;
}

class SupplierPaymentsSnapshot {
  SupplierPaymentsSnapshot({
    required List<CollectionAccount> accounts,
    required List<CollectionMethod> methods,
    required List<PayableSummary> payables,
    required List<PreparedSupplierPayment> pendingPayments,
    required List<ConfirmedSupplierPayment> payments,
  }) : accounts = List.unmodifiable(accounts),
       methods = List.unmodifiable(methods),
       payables = List.unmodifiable(payables),
       pendingPayments = List.unmodifiable(pendingPayments),
       payments = List.unmodifiable(payments);
  final List<CollectionAccount> accounts;
  final List<CollectionMethod> methods;
  final List<PayableSummary> payables;
  final List<PreparedSupplierPayment> pendingPayments;
  final List<ConfirmedSupplierPayment> payments;
}

abstract interface class SupplierPaymentsStore {
  Future<SupplierPaymentsSnapshot> load();
  Future<PreparedSupplierPayment> preparePayment(
    SupplierPaymentCommand command,
  );
  Future<SupplierPaymentResult> confirmPrepared(String commandId);
  Future<void> discardRejected(String commandId);
}

/// Deterministic rejection: no payment was committed by this invocation.
class SupplierPaymentsValidationException implements Exception {
  const SupplierPaymentsValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}
