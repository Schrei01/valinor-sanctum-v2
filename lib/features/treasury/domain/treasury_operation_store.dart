import 'treasury_store.dart';

export 'treasury_store.dart' show TreasuryValidationException;

enum TreasuryOperationKind { expense, transfer, investmentRefund }

class TreasuryOperationCommand {
  const TreasuryOperationCommand({
    required this.commandId,
    required this.kind,
    required this.sourceAccountId,
    this.destinationAccountId,
    required this.amountMinor,
    required this.reason,
    this.note,
    required this.occurredAtUtc,
  });
  final String commandId;
  final TreasuryOperationKind kind;
  final String sourceAccountId;
  final String? destinationAccountId;
  final int amountMinor;
  final String reason;
  final String? note;
  final DateTime occurredAtUtc;
}

class PreparedTreasuryOperation {
  const PreparedTreasuryOperation({
    required this.command,
    required this.status,
    required this.preparedAtUtc,
    this.rejectionReason,
    required this.sourceAccountName,
    this.destinationAccountName,
  });
  final TreasuryOperationCommand command;
  final String status;
  final DateTime preparedAtUtc;
  final String? rejectionReason;
  final String sourceAccountName;
  final String? destinationAccountName;
}

class TreasuryOperationResult {
  const TreasuryOperationResult({
    required this.commandId,
    required this.documentId,
    required this.kind,
    required this.amountMinor,
  });
  final String commandId;
  final String documentId;
  final TreasuryOperationKind kind;
  final int amountMinor;
}

class TreasuryOperationSnapshot {
  TreasuryOperationSnapshot({
    this.investmentMinor = 0,
    required List<TreasuryAccount> accounts,
    required List<PreparedTreasuryOperation> pendingOperations,
    required Set<String> confirmedCommandIds,
  }) : accounts = List.unmodifiable(accounts),
       pendingOperations = List.unmodifiable(pendingOperations),
       confirmedCommandIds = Set.unmodifiable(confirmedCommandIds);

  /// Active, available cash accounts with active monetary ledgers only.
  final List<TreasuryAccount> accounts;
  final int investmentMinor;
  final List<PreparedTreasuryOperation> pendingOperations;
  final Set<String> confirmedCommandIds;
}

abstract interface class TreasuryOperationStore {
  Future<void> ensureDefaults();
  Future<TreasuryOperationSnapshot> load();
  Future<PreparedTreasuryOperation> prepare(TreasuryOperationCommand command);
  Future<TreasuryOperationResult> confirmPrepared(String commandId);
  Future<void> discardRejected(String commandId);
}
