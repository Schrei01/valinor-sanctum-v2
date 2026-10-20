import 'dart:async';

import 'package:valinor_sanctum_2/features/treasury/domain/treasury_store.dart';

class FakeTreasuryStore implements TreasuryStore {
  FakeTreasuryStore({TreasurySnapshot? snapshot})
    : snapshot =
          snapshot ??
          TreasurySnapshot(
            accounts: const [],
            receivablesMinor: 0,
            movements: const [],
          );

  TreasurySnapshot snapshot;
  Object? loadFailure;
  Object? defaultsFailure;
  Completer<TreasurySnapshot>? pendingLoad;
  int loadCalls = 0;
  int defaultsCalls = 0;

  @override
  Future<void> ensureDefaults() async {
    defaultsCalls++;
    if (defaultsFailure != null) throw defaultsFailure!;
  }

  @override
  Future<TreasurySnapshot> load() async {
    loadCalls++;
    if (loadFailure != null) throw loadFailure!;
    if (pendingLoad != null) return pendingLoad!.future;
    return snapshot;
  }
}
