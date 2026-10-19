import 'package:flutter/foundation.dart';

import '../../inventory/domain/inventory_store.dart';
import '../domain/collections_store.dart';

class CollectionsController extends ChangeNotifier {
  CollectionsController({required this.store});
  final CollectionsStore store;
  CollectionsSnapshot? snapshot;
  bool loading = false;
  bool saving = false;
  bool confirming = false;
  String? loadError;
  String? operationError;
  String? operationNotice;
  bool _disposed = false;
  CollectionCommand? _preparation;
  PreparedCollection? _localPending;
  final _resolved = <String>{};

  bool get busy => loading || saving || confirming;
  List<PreparedCollection> get pendingCollections => [
    ?_localPending,
    ...?snapshot?.pendingCollections.where(
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

  Future<bool> saveAccount(CollectionAccount input) => _save(
    () => store.saveAccount(input),
    'Cuenta monetaria guardada. No se añadió un saldo de apertura.',
  );

  Future<bool> saveMethod(CollectionMethod input) =>
      _save(() => store.saveMethod(input), 'Medio de pago guardado.');

  Future<bool> _save(Future<void> Function() save, String notice) async {
    if (busy ||
        _disposed ||
        pendingCollections.isNotEmpty ||
        loadError != null) {
      return false;
    }
    saving = true;
    operationError = null;
    operationNotice = null;
    _emit();
    try {
      await save();
      await _reload();
      operationNotice = notice;
      return true;
    } on CollectionsValidationException catch (failure) {
      operationError = failure.message;
      return false;
    } catch (_) {
      operationError =
          'No pudimos confirmar el guardado. Conserva el formulario y vuelve a guardarlo; se usará la misma identidad.';
      return false;
    } finally {
      saving = false;
      _emit();
    }
  }

  Future<bool> collect({
    required String receivableId,
    required List<CollectionPartInput> parts,
    DateTime? occurredAtUtc,
  }) async {
    if (busy ||
        _disposed ||
        pendingCollections.isNotEmpty ||
        loadError != null) {
      return false;
    }
    final now = occurredAtUtc ?? DateTime.now().toUtc();
    _preparation = CollectionCommand(
      commandId: InventoryIds.next(),
      receivableId: receivableId,
      occurredAtUtc: now,
      parts: parts,
    );
    final receivable = snapshot!.receivables.firstWhere(
      (item) => item.receivableId == receivableId,
    );
    _localPending = PreparedCollection(
      commandId: _preparation!.commandId,
      receivableId: receivableId,
      customerName: receivable.customerName,
      label: receivable.label,
      occurredAtUtc: now,
      preparedAtUtc: now,
      status: 'prepared',
      totalMinor: parts.fold(0, (sum, part) => sum + part.amountMinor),
      parts: [
        for (final part in parts)
          CollectionPart(
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
    final pending = pendingCollections
        .where((item) => item.commandId == commandId)
        .firstOrNull;
    if (pending == null || pending.status == 'rejected') return false;
    return _dispatch(pending);
  }

  Future<bool> _dispatch(PreparedCollection pending) async {
    confirming = true;
    operationError = null;
    operationNotice = null;
    _emit();
    try {
      final preparation = _preparation;
      if (preparation != null && preparation.commandId == pending.commandId) {
        _localPending = await store.prepareCollection(preparation);
        _preparation = null;
      }
      final result = await store.confirmPrepared(pending.commandId);
      _resolved.add(pending.commandId);
      _localPending = null;
      await _reload();
      operationNotice =
          'Cobro confirmado. El ingreso y la reducción de la deuda quedaron registrados.';
      // The store result is authoritative even when the following read fails.
      assert(result.commandId == pending.commandId);
      return true;
    } on CollectionsValidationException catch (failure) {
      if (_preparation != null) {
        _preparation = null;
        _localPending = null;
      } else {
        _localPending = PreparedCollection(
          commandId: pending.commandId,
          receivableId: pending.receivableId,
          customerName: pending.customerName,
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
          ? 'No pudimos confirmar el resultado. El cobro permanece bloqueado: reintenta la misma solicitud o recupérala al volver a abrir.'
          : 'La preparación no respondió. Conserva esta ventana y reintenta la misma solicitud. Si quedó guardada, se recuperará al volver a abrir.';
      return false;
    } finally {
      confirming = false;
      _emit();
    }
  }

  Future<bool> unlockRejected(String commandId) async {
    final pending = pendingCollections
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
          ? 'Puedes corregir el cobro y confirmar de nuevo.'
          : 'Cobro desbloqueado. Actualiza para recuperar los saldos antes de corregirlo.';
      return true;
    } catch (_) {
      operationError = 'No se pudo desbloquear el cobro. Vuelve a intentarlo.';
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
        final confirmed = next.collections
            .where((item) => item.commandId == local.commandId)
            .firstOrNull;
        if (confirmed != null) {
          _resolved.add(local.commandId);
          _localPending = null;
          _preparation = null;
          operationError = null;
          operationNotice =
              'Cobro recuperado como confirmado. El ingreso ya está registrado.';
        } else {
          final persisted = next.pendingCollections
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
