import 'package:valinor_sanctum_2/features/debtors/domain/debtors_store.dart';

class FakeDebtorsStore implements DebtorsStore {
  final people = <DebtorSummary>[];
  final charges = <DebtorCharge>[];
  final payments = <DebtorPayment>[];
  final requests = <String, PreparedDebtorCommand>{};
  final results = <String, String>{};
  final inputs = <DebtorCommand>[];
  final confirmed = <String>[];
  bool failLoad = false, failConfirm = false, loseResponse = false;
  int legacy = 1000000;
  final options = <DebtorPaymentOption>[
    const DebtorPaymentOption('cash', 'Efectivo'),
    const DebtorPaymentOption('nequi', 'Nequi'),
  ];
  @override
  Future<DebtorsSnapshot> load() async {
    if (failLoad) throw StateError('Read failed');
    return DebtorsSnapshot(
      debtors: people,
      charges: charges,
      payments: payments,
      paymentOptions: options,
      pending: requests.values.where((r) => r.status == 'prepared').toList(),
      unassignedLegacyMinor: legacy,
      legacyPending: [],
      confirmedCommands: results.keys.toSet(),
    );
  }

  @override
  Future<PreparedDebtorCommand> prepare(DebtorCommand c) async {
    inputs.add(c);
    return requests.putIfAbsent(
      c.commandId,
      () => PreparedDebtorCommand(
        c,
        c.name ?? people.firstWhere((p) => p.id == c.debtorId).name,
        'prepared',
      ),
    );
  }

  @override
  Future<String> confirm(String id) async {
    if (results.containsKey(id)) return results[id]!;
    if (failConfirm) {
      throw const DebtorsValidationException('Operación rechazada.');
    }
    final r = requests[id]!, c = r.command;
    final personId = c.debtorId ?? 'person-${people.length}';
    if (c.kind == 'create') {
      people.add(
        DebtorSummary(
          id: personId,
          name: c.name!.trim(),
          balanceMinor: c.amountMinor,
          hasOpening: c.amountMinor > 0,
        ),
      );
    } else {
      final index = people.indexWhere((p) => p.id == personId),
          p = people[index];
      people[index] = DebtorSummary(
        id: p.id,
        name: p.name,
        balanceMinor:
            p.balanceMinor +
            (c.kind == 'payment' ? -c.amountMinor : c.amountMinor),
        isActive: p.isActive,
        hasOpening: p.hasOpening || c.kind == 'opening',
      );
    }
    if ((c.kind == 'create' || c.kind == 'opening') &&
        c.amountMinor > 0 &&
        c.previousSource == PreviousDebtSource.includedInLegacy) {
      legacy -= c.amountMinor;
    }
    if (c.kind == 'payment') {
      payments.add(
        DebtorPayment(
          id: id,
          debtorId: personId,
          nameSnapshot: r.nameSnapshot,
          amountMinor: c.amountMinor,
          occurredAtUtc: c.occurredAtUtc,
          paymentLabel: options
              .firstWhere((o) => o.id == c.paymentOptionId)
              .label,
        ),
      );
    }
    requests.remove(id);
    results[id] = personId;
    confirmed.add(id);
    if (loseResponse) throw StateError('Response lost');
    return personId;
  }

  @override
  Future<void> discard(String id) async {
    requests.remove(id);
  }

  @override
  Future<void> setActive(String id, bool active) async {
    final i = people.indexWhere((p) => p.id == id), p = people[i];
    people[i] = DebtorSummary(
      id: id,
      name: p.name,
      balanceMinor: p.balanceMinor,
      isActive: active,
      hasOpening: p.hasOpening,
    );
  }

  @override
  Future<void> retryLegacyCollection(String id) async {}
  @override
  Future<void> discardLegacyCollection(String id) async {}
}
