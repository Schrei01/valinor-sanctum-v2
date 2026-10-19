import 'package:flutter/foundation.dart';

import '../../../core/domain/money.dart';
import '../../inventory/domain/inventory_store.dart';
import '../domain/supplier_payments_store.dart';

class SupplierPaymentsController extends ChangeNotifier {
  SupplierPaymentsController({required this.store});
  final SupplierPaymentsStore store;
  SupplierPaymentsSnapshot? snapshot;
  bool loading = false;
  bool confirming = false;
  String? loadError;
  String? operationError;
  String? operationNotice;
  bool _disposed = false;
  SupplierPaymentCommand? _preparation;
  PreparedSupplierPayment? _localPending;
  final _resolved = <String>{};

  bool get busy => loading || confirming;
  List<PreparedSupplierPayment> get pendingPayments => [
    ?_localPending,
    ...?snapshot?.pendingPayments.where(
      (item) =>
          item.commandId != _localPending?.commandId &&
          !_resolved.contains(item.commandId),
    ),
  ];
  bool get preparationUncertain => _preparation != null && !confirming;

  Future<void> load() async {
    if (busy || _disposed) return;
    loading = true;
    loadError = null;
    _emit();
    await _reload();
    loading = false;
    _emit();
  }

  Future<bool> pay({
    required String payableId,
    required List<SupplierPaymentPartInput> parts,
    DateTime? occurredAtUtc,
  }) async {
    if (busy ||
        _disposed ||
        pendingPayments.isNotEmpty ||
        loadError != null ||
        snapshot == null) {
      return false;
    }
    final data = snapshot!;
    final payable = data.payables
        .where((item) => item.payableId == payableId)
        .firstOrNull;
    final total = parts.fold(
      BigInt.zero,
      (sum, part) => sum + BigInt.from(part.amountMinor),
    );
    if (payable == null ||
        parts.isEmpty ||
        parts.length > 20 ||
        total <= BigInt.zero ||
        total > Money.maxMinorUnits ||
        parts.any((part) => part.amountMinor <= 0) ||
        total > BigInt.from(payable.remainingMinor) ||
        parts.any(
          (part) =>
              !data.accounts.any((item) => item.id == part.cashAccountId) ||
              !data.methods.any((item) => item.id == part.paymentMethodId),
        )) {
      operationError =
          'Revisa la compra, las cuentas y los importes antes de confirmar.';
      _emit();
      return false;
    }
    final now = occurredAtUtc ?? DateTime.now().toUtc();
    _preparation = SupplierPaymentCommand(
      commandId: InventoryIds.next(),
      payableId: payableId,
      occurredAtUtc: now,
      parts: List.unmodifiable(parts),
    );
    _localPending = PreparedSupplierPayment(
      commandId: _preparation!.commandId,
      payableId: payableId,
      supplierName: payable.supplierName,
      label: payable.label,
      occurredAtUtc: now,
      preparedAtUtc: now,
      status: 'prepared',
      totalMinor: total.toInt(),
      parts: [
        for (final part in parts)
          SupplierPaymentPart(
            cashAccountId: part.cashAccountId,
            paymentMethodId: part.paymentMethodId,
            cashAccountName: snapshot!.accounts
                .firstWhere((item) => item.id == part.cashAccountId)
                .name,
            cashAccountKind: snapshot!.accounts
                .firstWhere((item) => item.id == part.cashAccountId)
                .kind,
            paymentMethodCode: snapshot!.methods
                .firstWhere((item) => item.id == part.paymentMethodId)
                .code,
            paymentMethodName: snapshot!.methods
                .firstWhere((item) => item.id == part.paymentMethodId)
                .name,
            amountMinor: part.amountMinor,
          ),
      ],
    );
    return _dispatch(_localPending!);
  }

  Future<bool> retry(String commandId) async {
    if (busy || _disposed) return false;
    final pending = pendingPayments
        .where((item) => item.commandId == commandId)
        .firstOrNull;
    if (pending == null || pending.status == 'rejected') return false;
    return _dispatch(pending);
  }

  Future<bool> _dispatch(PreparedSupplierPayment pending) async {
    confirming = true;
    operationError = null;
    operationNotice = null;
    _emit();
    try {
      final preparation = _preparation;
      if (preparation != null && preparation.commandId == pending.commandId) {
        _localPending = await store.preparePayment(preparation);
        _preparation = null;
      }
      final result = await store.confirmPrepared(pending.commandId);
      _resolved.add(pending.commandId);
      _localPending = null;
      await _reload();
      operationNotice =
          'Pago confirmado. La salida de dinero y la reducción de la deuda quedaron registrados.';
      // The store result is authoritative even when the following read fails.
      assert(result.commandId == pending.commandId);
      return true;
    } on SupplierPaymentsValidationException catch (failure) {
      if (_preparation != null) {
        _preparation = null;
        _localPending = null;
      } else {
        _localPending = PreparedSupplierPayment(
          commandId: pending.commandId,
          payableId: pending.payableId,
          supplierName: pending.supplierName,
          label: pending.label,
          occurredAtUtc: pending.occurredAtUtc,
          preparedAtUtc: pending.preparedAtUtc,
          status: 'rejected',
          totalMinor: pending.totalMinor,
          parts: pending.parts,
        );
      }
      operationError = failure.message;
      await _reload();
      return false;
    } catch (_) {
      operationError = _preparation == null
          ? 'No pudimos confirmar el resultado. El pago permanece bloqueado: reintenta la misma solicitud o recupérala al volver a abrir.'
          : 'La preparación no respondió. Conserva esta ventana y reintenta la misma solicitud. Si quedó guardada, se recuperará al volver a abrir.';
      return false;
    } finally {
      confirming = false;
      _emit();
    }
  }

  Future<bool> unlockRejected(String commandId) async {
    final pending = pendingPayments
        .where((item) => item.commandId == commandId)
        .firstOrNull;
    if (busy || _disposed || pending?.status != 'rejected') return false;
    confirming = true;
    operationError = null;
    _emit();
    try {
      await store.discardRejected(commandId);
      _resolved.add(commandId);
      _localPending = null;
      await _reload();
      operationNotice = loadError == null
          ? 'Puedes corregir el pago y confirmar de nuevo.'
          : 'Pago desbloqueado. Actualiza para recuperar los saldos antes de corregirlo.';
      return true;
    } catch (_) {
      operationError = 'No se pudo desbloquear el pago. Vuelve a intentarlo.';
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
      if (local != null) {
        final confirmed = next.payments
            .where((item) => item.commandId == local.commandId)
            .firstOrNull;
        if (confirmed != null) {
          _resolved.add(local.commandId);
          _localPending = null;
          _preparation = null;
          operationError = null;
          operationNotice =
              'Pago recuperado como confirmado. La salida de dinero ya está registrada.';
        } else {
          final persisted = next.pendingPayments
              .where((item) => item.commandId == local.commandId)
              .firstOrNull;
          if (persisted != null) {
            _localPending = persisted;
            _preparation = null;
          }
        }
      }
    } catch (_) {
      loadError =
          'No se pudo actualizar la información. Los datos visibles pueden estar desactualizados. Actualiza antes de registrar otra operación.';
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
