import 'reference_inventory.dart';

class InventoryOpeningCommand {
  const InventoryOpeningCommand({
    required this.commandId,
    required this.reference,
    required this.snapshotSha256,
    required this.occurredAtUtc,
    required this.zeroCostsConfirmed,
  });

  final String commandId;
  final ReferenceInventory reference;
  final String snapshotSha256;
  final DateTime occurredAtUtc;
  final bool zeroCostsConfirmed;
}

class InventoryOpeningResult {
  InventoryOpeningResult({
    required this.documentId,
    required this.commandId,
    required this.productCount,
    required this.totalUnits,
    required this.totalCostMinor,
    required Map<String, String> productIdsBySourceId,
  }) : productIdsBySourceId = Map.unmodifiable(productIdsBySourceId);

  final String documentId;
  final String commandId;
  final int productCount;
  final int totalUnits;
  final int totalCostMinor;
  final Map<String, String> productIdsBySourceId;
}

class InventoryOpeningValidationException implements Exception {
  const InventoryOpeningValidationException(this.message);
  final String message;

  @override
  String toString() => message;
}
