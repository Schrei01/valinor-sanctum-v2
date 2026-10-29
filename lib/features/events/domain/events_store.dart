import '../../inventory/domain/inventory_store.dart';

class EventProductInput {
  const EventProductInput(this.productId, this.quantity);
  final String productId;
  final int quantity;
  Map<String, Object?> toJson() => {
    'productId': productId,
    'quantity': quantity,
  };
}

class CreateEvent {
  CreateEvent({
    required this.commandId,
    required this.name,
    required this.minimumPeople,
    required this.fixedCostMinor,
    required this.pvpMinor,
    required this.occurredAtUtc,
    this.sourceAccountId,
    List<EventProductInput> products = const [],
  }) : products = List.unmodifiable(products);
  final String commandId, name;
  final int minimumPeople, fixedCostMinor, pvpMinor;
  final DateTime occurredAtUtc;
  final String? sourceAccountId;
  final List<EventProductInput> products;
}

class EventQuote {
  const EventQuote(
    this.productsCostMinor,
    this.totalCostMinor,
    this.unitCostMinor,
  );
  final int productsCostMinor, totalCostMinor, unitCostMinor;
}

class EventRecord {
  const EventRecord({
    required this.productId,
    required this.name,
    required this.minimumPeople,
    required this.fixedCostMinor,
    required this.productsCostMinor,
    required this.totalCostMinor,
    required this.unitCostMinor,
    required this.pvpMinor,
    required this.isActive,
    required this.createdAtUtc,
    required this.products,
    this.sourceAccountName,
  });
  final String productId, name;
  final int minimumPeople,
      fixedCostMinor,
      productsCostMinor,
      totalCostMinor,
      unitCostMinor,
      pvpMinor;
  final bool isActive;
  final DateTime createdAtUtc;
  final String? sourceAccountName;
  final List<String> products;
}

class EventAccount {
  const EventAccount(this.id, this.label, this.balanceMinor);
  final String id, label;
  final int balanceMinor;
  bool get isInvestment => id == 'investment';
}

class PreparedEvent {
  const PreparedEvent(this.command, this.quote);
  final CreateEvent command;
  final EventQuote quote;
}

class EventsSnapshot {
  EventsSnapshot({
    required this.inventory,
    required List<EventRecord> events,
    required List<EventAccount> accounts,
    required List<PreparedEvent> pending,
    Set<String> confirmedCommandIds = const {},
  }) : events = List.unmodifiable(events),
       accounts = List.unmodifiable(accounts),
       pending = List.unmodifiable(pending),
       confirmedCommandIds = Set.unmodifiable(confirmedCommandIds);
  final InventorySnapshot inventory;
  final List<EventRecord> events;
  final List<EventAccount> accounts;
  final List<PreparedEvent> pending;
  final Set<String> confirmedCommandIds;
}

abstract interface class EventsStore {
  Future<EventsSnapshot> load();
  Future<EventQuote> quote(CreateEvent command);
  Future<PreparedEvent> prepare(CreateEvent command);
  Future<String> confirm(String commandId);
  Future<void> discard(String commandId);
  Future<void> deactivate(String productId);
}

class EventsValidationException implements Exception {
  const EventsValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}
