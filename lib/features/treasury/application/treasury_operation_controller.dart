import 'package:flutter/foundation.dart';

import '../../../core/domain/money.dart';
import '../../inventory/domain/inventory_store.dart';
import '../domain/treasury_operation_store.dart';
import '../domain/treasury_store.dart';

class TreasuryOperationController extends ChangeNotifier {
  TreasuryOperationController({required this.store});

  final TreasuryOperationStore store;
  TreasuryOperationSnapshot? snapshot;
  bool loading = false;
  bool confirming = false;
  String? loadError;
  String? operationError;
  String? operationNotice;
  int confirmedVersion = 0;
  bool _disposed = false;
  TreasuryOperationCommand? _preparation;
  PreparedTreasuryOperation? _localPending;
  final _resolved = <String>{};

  bool get busy => loading || confirming;
  bool get formLocked => busy || pendingOperations.isNotEmpty;
  List<PreparedTreasuryOperation> get pendingOperations => [
    ?_localPending,
    ...?snapshot?.pendingOperations.where(
      (item) =>
          item.command.commandId != _localPending?.command.commandId &&
          !_resolved.contains(item.command.commandId),
    ),
  ];

  Future<void> load() async {
    if (busy || _disposed) return;
    loading = true;
    loadError = null;
    _emit();
    try {
      await store.ensureDefaults();
      await _reload();
    } catch (_) {
      loadError = 'No se pudieron cargar las cuentas. Pulsa Actualizar.';
    } finally {
      loading = false;
      _emit();
    }
  }

  Future<bool> record({
    required TreasuryOperationKind kind,
    required String sourceAccountId,
    String? destinationAccountId,
    required int amountMinor,
    required String reason,
    String? note,
    DateTime? occurredAtUtc,
  }) async {
    if (formLocked || _disposed || snapshot == null || loadError != null) {
      return false;
    }
    operationError = null;
    operationNotice = null;
    try {
      final accounts = snapshot!.accounts;
      final source = accounts
          .where((account) => account.id == sourceAccountId)
          .firstOrNull;
      if (source == null ||
          (kind != TreasuryOperationKind.transfer &&
              source.role != TreasuryAccountRole.cash &&
              source.role != TreasuryAccountRole.nequi)) {
        throw ArgumentError('Elige una cuenta válida para la operación.');
      }
      final destination = accounts
          .where((account) => account.id == destinationAccountId)
          .firstOrNull;
      if (kind == TreasuryOperationKind.transfer &&
          (destination == null || destination.id == source.id)) {
        throw ArgumentError('Elige dos cuentas distintas para transferir.');
      }
      if (kind != TreasuryOperationKind.transfer &&
          destinationAccountId != null) {
        throw ArgumentError('Un gasto no tiene cuenta de destino.');
      }
      if (amountMinor <= 0 || BigInt.from(amountMinor) > Money.maxMinorUnits) {
        throw ArgumentError('El valor debe ser mayor que cero.');
      }
      if (amountMinor > source.balanceMinor) {
        throw ArgumentError('El saldo de ${source.name} no alcanza.');
      }
      if (kind == TreasuryOperationKind.investmentRefund &&
          amountMinor > snapshot!.investmentMinor) {
        throw ArgumentError('La devolución supera la inversión pendiente.');
      }
      if (destination != null &&
          BigInt.from(destination.balanceMinor) + BigInt.from(amountMinor) >
              Money.maxMinorUnits) {
        throw ArgumentError('El saldo de destino supera el límite permitido.');
      }
      final normalizedReason = reason.trim();
      final normalizedNote = note?.trim();
      if (kind == TreasuryOperationKind.expense &&
          !const [
            'Arriendo',
            'Aseo',
            'Servicios',
            'Otro',
          ].contains(normalizedReason)) {
        throw ArgumentError('Elige el motivo del gasto.');
      }
      if ((normalizedNote?.length ?? 0) > 500 ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(normalizedNote ?? '')) {
        throw ArgumentError('La observación admite hasta 500 caracteres.');
      }
      final now = occurredAtUtc ?? DateTime.now().toUtc();
      if (!now.isUtc) throw ArgumentError('La fecha no es válida.');
      final command = TreasuryOperationCommand(
        commandId: InventoryIds.next(),
        kind: kind,
        sourceAccountId: source.id,
        destinationAccountId: destination?.id,
        amountMinor: amountMinor,
        reason: kind == TreasuryOperationKind.transfer
            ? 'Transferencia'
            : normalizedReason,
        note: normalizedNote == null || normalizedNote.isEmpty
            ? null
            : normalizedNote,
        occurredAtUtc: now,
      );
      _preparation = command;
      _localPending = PreparedTreasuryOperation(
        command: command,
        status: 'prepared',
        preparedAtUtc: now,
        sourceAccountName: source.name,
        destinationAccountName: destination?.name,
      );
    } catch (failure) {
      operationError = failure is ArgumentError
          ? failure.message?.toString() ?? 'Revisa los datos de la operación.'
          : 'Revisa los datos de la operación.';
      _emit();
      return false;
    }
    return _dispatch(_localPending!);
  }

  Future<bool> retry(String commandId) async {
    if (busy || _disposed) return false;
    final pending = pendingOperations
        .where((item) => item.command.commandId == commandId)
        .firstOrNull;
    if (pending == null || pending.status == 'rejected') return false;
    return _dispatch(pending);
  }

  Future<bool> _dispatch(PreparedTreasuryOperation pending) async {
    confirming = true;
    operationError = null;
    operationNotice = null;
    _emit();
    var canonical = pending;
    try {
      if (_preparation?.commandId == pending.command.commandId) {
        canonical = await store.prepare(_preparation!);
        _localPending = canonical;
        _preparation = null;
      }
      if (canonical.status == 'rejected') {
        throw TreasuryValidationException(
          canonical.rejectionReason ?? 'La operación fue rechazada.',
        );
      }
      final result = await store.confirmPrepared(canonical.command.commandId);
      assert(result.commandId == canonical.command.commandId);
      _markConfirmed(canonical.command.commandId);
      await _reload();
      operationNotice = canonical.command.kind == TreasuryOperationKind.expense
          ? 'Gasto registrado. El saldo de la cuenta se actualizó.'
          : canonical.command.kind == TreasuryOperationKind.investmentRefund
          ? 'Devolución registrada. Se actualizaron la inversión pendiente y la cuenta de pago.'
          : 'Transferencia registrada. Los saldos de ambas cuentas se actualizaron.';
      return true;
    } on TreasuryValidationException catch (failure) {
      if (_preparation != null) {
        _preparation = null;
        _localPending = null;
      } else {
        _localPending = PreparedTreasuryOperation(
          command: canonical.command,
          status: 'rejected',
          preparedAtUtc: canonical.preparedAtUtc,
          rejectionReason: failure.message,
          sourceAccountName: canonical.sourceAccountName,
          destinationAccountName: canonical.destinationAccountName,
        );
      }
      operationError = failure.message;
      await _reload();
      return false;
    } catch (_) {
      operationError =
          'No pudimos confirmar el resultado. Conservamos la operación: reintenta la misma solicitud. Si quedó guardada, también se recuperará al volver a abrir.';
      return false;
    } finally {
      confirming = false;
      _emit();
    }
  }

  Future<bool> discardRejected(String commandId) async {
    if (busy || _disposed) return false;
    final pending = pendingOperations
        .where((item) => item.command.commandId == commandId)
        .firstOrNull;
    if (pending?.status != 'rejected') return false;
    confirming = true;
    operationError = null;
    _emit();
    try {
      await store.discardRejected(commandId);
      _resolved.add(commandId);
      if (_localPending?.command.commandId == commandId) _localPending = null;
      _preparation = null;
      await _reload();
      operationNotice = 'Puedes corregir los datos y registrar la operación.';
      return true;
    } catch (_) {
      operationError = 'No se pudo habilitar la corrección. Reintenta.';
      return false;
    } finally {
      confirming = false;
      _emit();
    }
  }

  void _markConfirmed(String commandId) {
    if (_resolved.add(commandId)) confirmedVersion++;
    if (_localPending?.command.commandId == commandId) _localPending = null;
    if (_preparation?.commandId == commandId) _preparation = null;
  }

  Future<void> _reload() async {
    try {
      final next = await store.load();
      if (_disposed) return;
      snapshot = next;
      loadError = null;
      final local = _localPending;
      if (local == null) return;
      if (next.confirmedCommandIds.contains(local.command.commandId)) {
        _markConfirmed(local.command.commandId);
        operationError = null;
        operationNotice =
            'Operación recuperada como confirmada. Los saldos ya están actualizados.';
      } else {
        final persisted = next.pendingOperations
            .where((item) => item.command.commandId == local.command.commandId)
            .firstOrNull;
        if (persisted != null) {
          _localPending = persisted;
          _preparation = null;
        }
      }
    } catch (_) {
      loadError =
          'No se pudo actualizar la información. Pulsa Actualizar antes de registrar otra operación.';
    }
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
