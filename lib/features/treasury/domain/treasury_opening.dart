/// Verified balances from one legacy snapshot, expressed in profile minor units.
/// Metadata describes provenance; it does not fabricate individual customers.
class TreasuryOpeningCommand {
  const TreasuryOpeningCommand({
    required this.commandId,
    required this.sourceSha256,
    required this.snapshotSha256,
    required this.occurredAtUtc,
    required this.cashMinor,
    required this.nequiMinor,
    required this.reserveMinor,
    required this.receivablesMinor,
    required this.sourceMetadata,
  });

  final String commandId;
  final String sourceSha256;
  final String snapshotSha256;
  final DateTime occurredAtUtc;
  final int cashMinor;
  final int nequiMinor;
  final int reserveMinor;
  final int receivablesMinor;
  final Map<String, Object?> sourceMetadata;
}

class TreasuryOpeningResult {
  const TreasuryOpeningResult({
    required this.documentId,
    required this.replayed,
  });
  final String documentId;
  final bool replayed;
}

class TreasuryOpeningValidationException implements Exception {
  const TreasuryOpeningValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}
