import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/features/events/application/events_controller.dart';
import 'package:valinor_sanctum_2/features/events/domain/events_store.dart';
import '../support/fake_events_store.dart';

void main() {
  CreateEvent command() => CreateEvent(
    commandId: 'one',
    name: 'Evento sintético',
    minimumPeople: 0,
    fixedCostMinor: 0,
    pvpMinor: 500,
    occurredAtUtc: DateTime.utc(2026, 10, 21),
  );
  test(
    'lost confirmation response is recovered from authoritative confirmed ids',
    () async {
      final store = FakeEventsStore()..loseConfirmationResponse = true;
      final c = EventsController(store: store);
      addTearDown(c.dispose);
      expect(await c.create(command()), isTrue);
      expect(c.error, isNull);
      expect(c.snapshot!.confirmedCommandIds, contains('one'));
      expect(store.confirmed, ['one']);
    },
  );
  test(
    'unknown preparation or confirmation and failed refresh keeps exact command for retry',
    () async {
      final store = FakeEventsStore()
        ..failConfirmation = true
        ..failLoad = true;
      final c = EventsController(store: store);
      addTearDown(c.dispose);
      final input = command();
      expect(await c.create(input), isFalse);
      expect(identical(c.uncertainCreation, input), isTrue);
      store.failLoad = false;
      await c.load();
      expect(c.uncertainCreation, isNotNull);
      expect(c.snapshot!.pending.single.command.commandId, 'one');
      store.failConfirmation = false;
      expect(await c.create(c.uncertainCreation!), isTrue);
      expect(c.uncertainCreation, isNull);
      expect(store.confirmed, ['one']);
    },
  );
  test(
    'known rejection remains pending and can be discarded without confirmation',
    () async {
      final store = FakeEventsStore()..failConfirmation = true;
      final c = EventsController(store: store);
      addTearDown(c.dispose);
      expect(await c.create(command()), isFalse);
      expect(c.snapshot!.pending, hasLength(1));
      expect(c.error, isNotNull);
      expect(await c.discard('one'), isTrue);
      expect(c.snapshot!.pending, isEmpty);
      expect(store.confirmed, isEmpty);
    },
  );
}
