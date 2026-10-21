import 'package:valinor_sanctum_2/features/events/domain/events_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';

class FakeEventsStore implements EventsStore {
  final commands = <CreateEvent>[];
  final confirmed = <String>[];
  final deactivated = <String>[];
  final pending = <PreparedEvent>[];
  final records = <EventRecord>[];
  int loads = 0;
  bool failConfirmation = false;
  bool failLoad = false, loseConfirmationResponse = false;
  InventorySnapshot inventory = InventorySnapshot(
    categories: const [InventoryCategory(id: 'event', name: 'Evento')],
    suppliers: const [],
    products: const [
      CatalogProduct(id: 'p1', name: 'Premio sintético', listPriceMinor: 500),
    ],
    stock: const [
      StockPosition(productId: 'p1', quantity: 10, totalCostMinor: 1000),
    ],
    receipts: const [],
  );
  @override
  Future<EventsSnapshot> load() async {
    loads++;
    if (failLoad) throw StateError('Synthetic read failure');
    return EventsSnapshot(
      inventory: inventory,
      events: records,
      accounts: const [
        EventAccount('cash', 'Caja', 100000),
        EventAccount('nequi', 'Nequi', 50000),
      ],
      pending: pending,
      confirmedCommandIds: confirmed.toSet(),
    );
  }

  @override
  Future<EventQuote> quote(CreateEvent c) async {
    if ((c.fixedCostMinor > 0 || c.products.isNotEmpty) &&
        c.minimumPeople == 0) {
      throw const EventsValidationException(
        'Indica un mínimo de personas mayor que cero.',
      );
    }
    final products = c.products.fold<int>(0, (n, p) => n + p.quantity * 100),
        total = products + c.fixedCostMinor;
    return EventQuote(
      products,
      total,
      c.minimumPeople == 0 ? 0 : total ~/ c.minimumPeople,
    );
  }

  @override
  Future<PreparedEvent> prepare(CreateEvent c) async {
    commands.add(c);
    final p = PreparedEvent(c, await quote(c));
    pending.add(p);
    return p;
  }

  @override
  Future<String> confirm(String id) async {
    if (failConfirmation) {
      throw const EventsValidationException('No se pudo confirmar.');
    }
    confirmed.add(id);
    pending.removeWhere((p) => p.command.commandId == id);
    if (loseConfirmationResponse) throw StateError('Synthetic lost response');
    return 'event-product';
  }

  @override
  Future<void> discard(String id) async {
    pending.removeWhere((p) => p.command.commandId == id);
  }

  @override
  Future<void> deactivate(String id) async {
    deactivated.add(id);
  }
}
