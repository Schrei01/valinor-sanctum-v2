import '../../collections/domain/collections_store.dart';

enum PreviousDebtSource { includedInLegacy, additional }

class DebtorSummary {
  const DebtorSummary({
    required this.id,
    required this.name,
    required this.balanceMinor,
    this.isActive = true,
    this.hasOpening = false,
  });
  final String id, name;
  final int balanceMinor;
  final bool isActive;
  final bool hasOpening;
}

class DebtorCharge {
  const DebtorCharge({
    required this.receivableId,
    required this.label,
    required this.nameSnapshot,
    required this.occurredAtUtc,
    required this.originalCreditMinor,
    required this.remainingMinor,
    this.isOpening = false,
    this.debtorId,
  });
  final String receivableId, label, nameSnapshot;
  final DateTime occurredAtUtc;
  final int originalCreditMinor, remainingMinor;
  final bool isOpening;
  final String? debtorId;
}

class DebtorPayment {
  const DebtorPayment({
    required this.id,
    required this.debtorId,
    required this.nameSnapshot,
    required this.amountMinor,
    required this.occurredAtUtc,
    required this.paymentLabel,
  });
  final String id, debtorId, nameSnapshot, paymentLabel;
  final int amountMinor;
  final DateTime occurredAtUtc;
  String get displayPaymentLabel => paymentLabel
      .split(' + ')
      .map(
        (label) =>
            label.trim().toLowerCase() == 'nequi' ? 'Transferencia' : label,
      )
      .join(' + ');
}

class DebtorPaymentOption {
  const DebtorPaymentOption(this.id, this.label);
  final String id, label;
  String get displayLabel =>
      label.trim().toLowerCase() == 'nequi' ? 'Transferencia' : label;
}

class DebtorCommand {
  DebtorCommand({
    required this.commandId,
    required this.kind,
    required this.occurredAtUtc,
    this.name,
    this.debtorId,
    this.amountMinor = 0,
    this.previousSource,
    this.paymentOptionId,
    this.receivableId,
  });
  final String commandId, kind;
  final DateTime occurredAtUtc;
  final String? name, debtorId, paymentOptionId, receivableId;
  final int amountMinor;
  final PreviousDebtSource? previousSource;
}

class PreparedDebtorCommand {
  const PreparedDebtorCommand(this.command, this.nameSnapshot, this.status);
  final DebtorCommand command;
  final String nameSnapshot, status;
}

class DebtorsSnapshot {
  DebtorsSnapshot({
    required List<DebtorSummary> debtors,
    required List<DebtorCharge> charges,
    required List<DebtorPayment> payments,
    required List<DebtorPaymentOption> paymentOptions,
    required List<PreparedDebtorCommand> pending,
    required this.unassignedLegacyMinor,
    required List<PreparedCollection> legacyPending,
    Set<String> confirmedCommands = const {},
  }) : debtors = List.unmodifiable(debtors),
       charges = List.unmodifiable(charges),
       payments = List.unmodifiable(payments),
       paymentOptions = List.unmodifiable(paymentOptions),
       pending = List.unmodifiable(pending),
       legacyPending = List.unmodifiable(legacyPending),
       confirmedCommands = Set.unmodifiable(confirmedCommands);
  final List<DebtorSummary> debtors;
  final List<DebtorCharge> charges;
  final List<DebtorPayment> payments;
  final List<DebtorPaymentOption> paymentOptions;
  final List<PreparedDebtorCommand> pending;
  final int unassignedLegacyMinor;
  final List<PreparedCollection> legacyPending;
  final Set<String> confirmedCommands;
}

abstract interface class DebtorsStore {
  Future<DebtorsSnapshot> load();
  Future<PreparedDebtorCommand> prepare(DebtorCommand command);
  Future<String> confirm(String commandId);
  Future<void> discard(String commandId);
  Future<void> setActive(String debtorId, bool active);
  Future<void> retryLegacyCollection(String commandId);
  Future<void> discardLegacyCollection(String commandId);
}

class DebtorsValidationException implements Exception {
  const DebtorsValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}
