class StockAdjustmentCommand {
  const StockAdjustmentCommand({
    required this.commandId,
    required this.productId,
    required this.quantity,
    required this.reason,
    required this.occurredAtUtc,
  });
  final String commandId, productId, reason;
  final int quantity;
  final DateTime occurredAtUtc;
}

abstract interface class StockAdjustmentStore {
  Future<List<StockAdjustmentCommand>> pendingAdjustments();
  Future<void> prepareAdjustment(StockAdjustmentCommand command);
  Future<void> confirmAdjustment(String commandId);
  Future<void> discardAdjustment(String commandId);
}

class StockAdjustmentValidationException implements Exception {
  const StockAdjustmentValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}
