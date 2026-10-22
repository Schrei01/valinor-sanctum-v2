import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/features/debtors/application/debtors_controller.dart';
import 'package:valinor_sanctum_2/features/debtors/domain/debtors_store.dart';
import '../support/fake_debtors_store.dart';

void main() {
  DebtorCommand command() => DebtorCommand(
    commandId: 'one',
    kind: 'create',
    name: 'Persona sintética',
    occurredAtUtc: DateTime.utc(2026, 10, 21),
  );
  test(
    'lost committed response resolves to stable person without duplicate creation',
    () async {
      final s = FakeDebtorsStore()..loseResponse = true;
      final c = DebtorsController(store: s);
      addTearDown(c.dispose);
      expect(await c.submit(command()), isTrue);
      expect(c.error, isNull);
      expect(c.lastPersonId, 'person-0');
      expect(s.people, hasLength(1));
      expect(s.confirmed, ['one']);
    },
  );
  test(
    'unknown write and failed read retains exact input until retry',
    () async {
      final s = FakeDebtorsStore()
        ..failConfirm = true
        ..failLoad = true;
      final c = DebtorsController(store: s);
      addTearDown(c.dispose);
      final input = command();
      expect(await c.submit(input), isFalse);
      expect(c.uncertain, same(input));
      s.failLoad = false;
      await c.load();
      expect(c.uncertain, same(input));
      expect(c.snapshot!.pending, hasLength(1));
      s.failConfirm = false;
      expect(await c.submit(c.uncertain!), isTrue);
      expect(c.uncertain, isNull);
      expect(s.confirmed, ['one']);
    },
  );
  test(
    'known pending rejection can be discarded without person or debt',
    () async {
      final s = FakeDebtorsStore()..failConfirm = true;
      final c = DebtorsController(store: s);
      addTearDown(c.dispose);
      expect(await c.submit(command()), isFalse);
      expect(c.uncertain, isNull);
      expect(c.snapshot!.pending, hasLength(1));
      expect(await c.discard('one'), isTrue);
      expect(c.snapshot!.pending, isEmpty);
      expect(s.people, isEmpty);
    },
  );
}
