import 'package:valinor_sanctum_2/features/collections/domain/collections_store.dart';
import 'package:valinor_sanctum_2/features/supplier_payments/domain/supplier_payments_store.dart';

class FakeSupplierPaymentsStore implements SupplierPaymentsStore {
  final accounts = <CollectionAccount>[];
  final methods = <CollectionMethod>[];
  final payables = <PayableSummary>[];
  final pending = <PreparedSupplierPayment>[];
  final payments = <ConfirmedSupplierPayment>[];
  final preparedInputs = <SupplierPaymentCommand>[];
  final confirmedIds = <String>[];
  final _results = <String, SupplierPaymentResult>{};
  Object? loadFailure;
  Object? saveFailure;
  Object? preparationFailure;
  Object? confirmationFailure;
  bool persistBeforePreparationFailure = false;
  bool commitBeforeConfirmationFailure = false;

  @override
  Future<SupplierPaymentsSnapshot> load() async {
    if (loadFailure != null) throw loadFailure!;
    return SupplierPaymentsSnapshot(
      accounts: accounts,
      methods: methods,
      payables: payables,
      pendingPayments: pending,
      payments: payments,
    );
  }

  @override
  Future<PreparedSupplierPayment> preparePayment(
    SupplierPaymentCommand command,
  ) async {
    preparedInputs.add(command);
    final old = pending
        .where((item) => item.commandId == command.commandId)
        .firstOrNull;
    if (old != null) return old;
    if (preparationFailure != null && !persistBeforePreparationFailure) {
      throw preparationFailure!;
    }
    final source = payables.firstWhere(
      (item) => item.payableId == command.payableId,
    );
    final result = PreparedSupplierPayment(
      commandId: command.commandId,
      payableId: command.payableId,
      label: source.label,
      supplierName: source.supplierName,
      occurredAtUtc: command.occurredAtUtc,
      preparedAtUtc: command.occurredAtUtc,
      status: 'prepared',
      totalMinor: command.parts.fold(0, (sum, part) => sum + part.amountMinor),
      parts: [
        for (final part in command.parts)
          SupplierPaymentPart(
            cashAccountId: part.cashAccountId,
            paymentMethodId: part.paymentMethodId,
            cashAccountName: accounts
                .firstWhere((item) => item.id == part.cashAccountId)
                .name,
            cashAccountKind: accounts
                .firstWhere((item) => item.id == part.cashAccountId)
                .kind,
            paymentMethodCode: methods
                .firstWhere((item) => item.id == part.paymentMethodId)
                .code,
            paymentMethodName: methods
                .firstWhere((item) => item.id == part.paymentMethodId)
                .name,
            amountMinor: part.amountMinor,
          ),
      ],
    );
    pending.add(result);
    if (preparationFailure != null) throw preparationFailure!;
    return result;
  }

  @override
  Future<SupplierPaymentResult> confirmPrepared(String commandId) async {
    confirmedIds.add(commandId);
    final old = _results[commandId];
    if (old != null) return old;
    final request = pending.firstWhere((item) => item.commandId == commandId);
    if (confirmationFailure != null && !commitBeforeConfirmationFailure) {
      if (confirmationFailure is SupplierPaymentsValidationException) {
        pending.remove(request);
        pending.add(
          PreparedSupplierPayment(
            commandId: request.commandId,
            payableId: request.payableId,
            label: request.label,
            supplierName: request.supplierName,
            occurredAtUtc: request.occurredAtUtc,
            preparedAtUtc: request.preparedAtUtc,
            status: 'rejected',
            totalMinor: request.totalMinor,
            parts: request.parts,
          ),
        );
      }
      throw confirmationFailure!;
    }
    final source = payables.firstWhere(
      (item) => item.payableId == request.payableId,
    );
    final result = SupplierPaymentResult(
      documentId: 'supplier-payment-$commandId',
      commandId: commandId,
      payableId: source.payableId,
      totalMinor: request.totalMinor,
      remainingMinor: source.remainingMinor - request.totalMinor,
    );
    _results[commandId] = result;
    payments.insert(
      0,
      ConfirmedSupplierPayment(
        documentId: result.documentId,
        commandId: commandId,
        payableId: source.payableId,
        label: request.label,
        supplierName: request.supplierName,
        paidAtUtc: request.occurredAtUtc,
        totalMinor: request.totalMinor,
        remainingMinor: result.remainingMinor,
        parts: request.parts,
      ),
    );
    payables.remove(source);
    payables.add(
      PayableSummary(
        payableId: source.payableId,
        purchaseDocumentId: source.purchaseDocumentId,
        label: source.label,
        supplierName: source.supplierName,
        issuedAtUtc: source.issuedAtUtc,
        dueDate: source.dueDate,
        initialMinor: source.initialMinor,
        paidMinor: source.paidMinor + request.totalMinor,
        remainingMinor: result.remainingMinor,
      ),
    );
    for (final part in request.parts) {
      final account = accounts.firstWhere(
        (item) => item.id == part.cashAccountId,
      );
      accounts.remove(account);
      accounts.add(
        CollectionAccount(
          id: account.id,
          name: account.name,
          kind: account.kind,
          isActive: account.isActive,
          isAvailable: account.isAvailable,
          balanceMinor: account.balanceMinor - part.amountMinor,
        ),
      );
    }
    pending.remove(request);
    if (confirmationFailure != null) throw confirmationFailure!;
    return result;
  }

  @override
  Future<void> discardRejected(String commandId) async {
    final value = pending.firstWhere((item) => item.commandId == commandId);
    if (value.status != 'rejected') {
      throw const SupplierPaymentsValidationException(
        'El pago aún no se puede corregir.',
      );
    }
    pending.remove(value);
  }
}
