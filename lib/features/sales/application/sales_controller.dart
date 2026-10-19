import 'package:flutter/foundation.dart';

import '../../inventory/domain/inventory_store.dart';
import '../domain/sales_store.dart';

/// Confirmation input is persisted by the store before the sale is dispatched.
/// An uncertain result retains the exact command until its result is recovered.
class SalesController extends ChangeNotifier {
  SalesController({required this.store});
  final SalesStore store;
  SalesSnapshot? snapshot;
  bool loading = false;
  bool saving = false;
  bool confirming = false;
  String? loadError;
  String? operationError;
  String? operationNotice;
  bool _disposed = false;
  _Preparation? _preparation;
  SaleConfirmation? _localPending;

  bool get busy => loading || saving || confirming;

  SaleConfirmation? pendingFor(String draftId) =>
      _localPending?.draftId == draftId
      ? _localPending
      : snapshot?.pendingConfirmations
            .where((item) => item.draftId == draftId)
            .firstOrNull;

  Future<void> load() async {
    if (busy || _disposed) return;
    loading = true;
    loadError = null;
    _emit();
    await _reload();
    loading = false;
    _emit();
  }

  Future<SaleDraft?> saveDraft(SaveSaleDraft input) async {
    if (busy || _disposed || pendingFor(input.id) != null) return null;
    saving = true;
    operationError = null;
    operationNotice = null;
    _emit();
    try {
      final saved = await store.saveDraft(input);
      await _reload();
      operationNotice = 'Cuenta guardada. Aún no descuenta ni reserva stock.';
      return saved;
    } on SalesValidationException catch (failure) {
      operationError = failure.message;
      return null;
    } catch (_) {
      operationError =
          'No pudimos confirmar el guardado. Conserva el formulario y vuelve '
          'a guardarlo; se usará la misma cuenta.';
      return null;
    } finally {
      saving = false;
      _emit();
    }
  }

  Future<bool> confirm({
    required String draftId,
    required int expectedRevision,
    required String dueDate,
    DateTime? occurredAtUtc,
  }) async {
    if (busy || _disposed || pendingFor(draftId) != null) return false;
    if (_localPending != null) {
      operationError =
          'Resuelve la confirmación pendiente de la otra cuenta antes de '
          'confirmar una nueva entrega.';
      _emit();
      return false;
    }
    final now = occurredAtUtc ?? DateTime.now().toUtc();
    _preparation = _Preparation(
      commandId: InventoryIds.next(),
      draftId: draftId,
      revision: expectedRevision,
      dueDate: dueDate,
      occurredAtUtc: now,
    );
    _localPending = _preparation!.asPending;
    return _dispatch(draftId);
  }

  Future<bool> retry(String draftId) async {
    if (busy || _disposed || pendingFor(draftId) == null) return false;
    return _dispatch(draftId);
  }

  Future<bool> _dispatch(String draftId) async {
    final pending = pendingFor(draftId)!;
    confirming = true;
    operationError = null;
    operationNotice = null;
    _emit();
    try {
      final preparation = _preparation;
      if (preparation != null && preparation.draftId == draftId) {
        _localPending = await store.prepareConfirmation(
          commandId: preparation.commandId,
          draftId: preparation.draftId,
          expectedRevision: preparation.revision,
          occurredAtUtc: preparation.occurredAtUtc,
          dueDate: preparation.dueDate,
        );
        _preparation = null;
      }
      await store.confirmPrepared(pending.commandId);
      _localPending = null;
      await _reload();
      operationNotice =
          'Venta a crédito confirmada. Stock, costo histórico y cuenta por '
          'cobrar registrados. No se registró un cobro.';
      return true;
    } on SalesValidationException catch (failure) {
      if (_preparation != null) {
        // A deterministic preparation rejection did not persist a command.
        _preparation = null;
        _localPending = null;
      } else {
        _localPending = SaleConfirmation(
          commandId: pending.commandId,
          draftId: pending.draftId,
          draftRevision: pending.draftRevision,
          occurredAtUtc: pending.occurredAtUtc,
          dueDate: pending.dueDate,
          preparedAtUtc: pending.preparedAtUtc,
          status: 'rejected',
        );
      }
      operationError = failure.message;
      await _reload();
      return false;
    } catch (_) {
      operationError =
          'No pudimos confirmar el resultado. La cuenta está bloqueada. '
          'Reintenta la misma solicitud; si cierras, se recuperará la '
          'confirmación preparada al volver a abrir.';
      return false;
    } finally {
      confirming = false;
      _emit();
    }
  }

  Future<bool> unlockRejected(String draftId) async {
    final pending = pendingFor(draftId);
    if (busy || _disposed || pending?.status != 'rejected') return false;
    confirming = true;
    operationError = null;
    _emit();
    try {
      await store.discardRejected(pending!.commandId);
      _localPending = null;
      await _reload();
      operationNotice = 'Puedes corregir la cuenta y confirmar de nuevo.';
      return true;
    } catch (_) {
      operationError = 'No se pudo desbloquear la cuenta. Vuelve a intentarlo.';
      return false;
    } finally {
      confirming = false;
      _emit();
    }
  }

  Future<void> _reload() async {
    try {
      final next = await store.load();
      if (_disposed) return;
      snapshot = next;
      loadError = null;
      final local = _localPending;
      if (local != null && _preparation == null) {
        final persisted = next.pendingConfirmations
            .where((item) => item.commandId == local.commandId)
            .firstOrNull;
        if (persisted != null) {
          _localPending = persisted;
        } else if (next.sales.any((item) => item.draftId == local.draftId)) {
          _localPending = null;
          operationError = null;
          operationNotice =
              'Venta a crédito recuperada como confirmada. Stock, costo y '
              'cuenta por cobrar registrados. No se registró un cobro.';
        }
      }
    } catch (_) {
      loadError =
          'No se pudo actualizar la información. Los datos visibles pueden '
          'estar desactualizados. Pulsa Actualizar.';
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

class _Preparation {
  const _Preparation({
    required this.commandId,
    required this.draftId,
    required this.revision,
    required this.dueDate,
    required this.occurredAtUtc,
  });
  final String commandId;
  final String draftId;
  final int revision;
  final String dueDate;
  final DateTime occurredAtUtc;
  SaleConfirmation get asPending => SaleConfirmation(
    commandId: commandId,
    draftId: draftId,
    draftRevision: revision,
    occurredAtUtc: occurredAtUtc,
    dueDate: dueDate,
    preparedAtUtc: occurredAtUtc,
    status: 'prepared',
  );
}
