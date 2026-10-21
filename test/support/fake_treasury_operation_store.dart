import 'dart:async';

import 'package:valinor_sanctum_2/features/treasury/domain/treasury_operation_store.dart';
import 'package:valinor_sanctum_2/features/treasury/domain/treasury_store.dart';

class FakeTreasuryOperationStore implements TreasuryOperationStore {
  final accounts = <TreasuryAccount>[
    const TreasuryAccount(
      id: 'cash',
      name: 'Caja',
      role: TreasuryAccountRole.cash,
      balanceMinor: 100000,
    ),
    const TreasuryAccount(
      id: 'nequi',
      name: 'Nequi',
      role: TreasuryAccountRole.nequi,
      balanceMinor: 50000,
    ),
    const TreasuryAccount(
      id: 'reserve',
      name: 'Caja mayor',
      role: TreasuryAccountRole.reserve,
      balanceMinor: -20000,
    ),
  ];
  final pending = <PreparedTreasuryOperation>[];
  final preparedCommands = <TreasuryOperationCommand>[];
  final confirmedCalls = <String>[];
  final discardedIds = <String>[];
  final results = <String, TreasuryOperationResult>{};
  Object? defaultsFailure;
  Object? loadFailure;
  Object? prepareFailure;
  Object? confirmFailure;
  Object? discardFailure;
  bool persistBeforePrepareFailure = false;
  bool commitBeforeConfirmFailure = false;
  Completer<void>? confirmGate;
  int loadCalls = 0;
  int defaultsCalls = 0;

  @override
  Future<void> ensureDefaults() async {
    defaultsCalls++;
    if (defaultsFailure != null) throw defaultsFailure!;
  }

  @override
  Future<TreasuryOperationSnapshot> load() async {
    loadCalls++;
    if (loadFailure != null) throw loadFailure!;
    return TreasuryOperationSnapshot(
      accounts: accounts,
      pendingOperations: pending,
      confirmedCommandIds: results.keys.toSet(),
    );
  }

  @override
  Future<PreparedTreasuryOperation> prepare(
    TreasuryOperationCommand command,
  ) async {
    preparedCommands.add(command);
    if (prepareFailure != null && !persistBeforePrepareFailure) {
      throw prepareFailure!;
    }
    final existing = pending
        .where((item) => item.command.commandId == command.commandId)
        .firstOrNull;
    final prepared =
        existing ??
        PreparedTreasuryOperation(
          command: command,
          status: 'prepared',
          preparedAtUtc: command.occurredAtUtc,
          sourceAccountName: accounts
              .firstWhere((account) => account.id == command.sourceAccountId)
              .name,
          destinationAccountName: accounts
              .where((account) => account.id == command.destinationAccountId)
              .firstOrNull
              ?.name,
        );
    if (existing == null) pending.add(prepared);
    if (prepareFailure != null) throw prepareFailure!;
    return prepared;
  }

  @override
  Future<TreasuryOperationResult> confirmPrepared(String commandId) async {
    confirmedCalls.add(commandId);
    if (confirmGate != null) await confirmGate!.future;
    final old = results[commandId];
    if (old != null) return old;
    final prepared = pending.firstWhere(
      (item) => item.command.commandId == commandId,
    );
    if (confirmFailure is TreasuryValidationException) {
      pending.remove(prepared);
      pending.add(
        PreparedTreasuryOperation(
          command: prepared.command,
          status: 'rejected',
          preparedAtUtc: prepared.preparedAtUtc,
          rejectionReason:
              (confirmFailure as TreasuryValidationException).message,
          sourceAccountName: prepared.sourceAccountName,
          destinationAccountName: prepared.destinationAccountName,
        ),
      );
      throw confirmFailure!;
    }
    if (confirmFailure != null && !commitBeforeConfirmFailure) {
      throw confirmFailure!;
    }
    final command = prepared.command;
    for (var index = 0; index < accounts.length; index++) {
      final account = accounts[index];
      var balance = account.balanceMinor;
      if (account.id == command.sourceAccountId) balance -= command.amountMinor;
      if (account.id == command.destinationAccountId) {
        balance += command.amountMinor;
      }
      accounts[index] = TreasuryAccount(
        id: account.id,
        name: account.name,
        role: account.role,
        balanceMinor: balance,
      );
    }
    final result = TreasuryOperationResult(
      commandId: commandId,
      documentId: 'document-$commandId',
      kind: command.kind,
      amountMinor: command.amountMinor,
    );
    results[commandId] = result;
    pending.remove(prepared);
    if (confirmFailure != null) throw confirmFailure!;
    return result;
  }

  @override
  Future<void> discardRejected(String commandId) async {
    discardedIds.add(commandId);
    if (discardFailure != null) throw discardFailure!;
    pending.removeWhere(
      (item) =>
          item.command.commandId == commandId && item.status == 'rejected',
    );
  }
}
