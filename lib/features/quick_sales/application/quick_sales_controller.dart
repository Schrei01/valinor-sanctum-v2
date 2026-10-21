import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../inventory/domain/inventory_store.dart';
import '../domain/quick_sales_store.dart';

/// Each card saves and recovers independently. Unknown writes retain their
/// exact input so later edits cannot change an operation being retried.
class QuickSalesController extends ChangeNotifier {
  QuickSalesController({
    required this.store,
    this.autosaveDelay = const Duration(milliseconds: 350),
  });

  final QuickSalesStore store;
  final Duration autosaveDelay;
  QuickSalesSnapshot? snapshot;
  bool loading = false;
  String? loadError;
  String? notice;
  final _cards = <String, _CardState>{};
  final _closedIds = <String>{};
  bool _disposed = false;
  bool _defaultsReady = false;
  int _readGeneration = 0;

  List<QuickSaleAccount> get accounts =>
      List.unmodifiable(_cards.values.map((card) => card.account));
  bool get hasUnsavedChanges => _cards.values.any((card) => card.dirty);
  bool isLocked(String id) =>
      _cards[id]?.pending != null || (_cards[id]?.acting ?? false);
  bool isSaving(String id) => _cards[id]?.saving != null;
  bool isDirty(String id) => _cards[id]?.dirty ?? false;
  bool isActing(String id) => _cards[id]?.acting ?? false;
  String? errorFor(String id) => _cards[id]?.error;
  bool canRecoverSaved(String id) => _cards[id]?.saveRejected ?? false;
  int editorEpochFor(String id) => _cards[id]?.editorEpoch ?? 0;
  PreparedQuickSale? pendingFor(String id) => _cards[id]?.pending;

  Future<void> load() async {
    if (_disposed || loading) return;
    loading = true;
    _emit();
    await _reload();
    loading = false;
    _emit();
  }

  Future<void> _reload() async {
    final generation = ++_readGeneration;
    try {
      if (!_defaultsReady) {
        await store.ensureDefaults();
        _defaultsReady = true;
      }
      final next = await store.load();
      if (_disposed || generation != _readGeneration) return;
      snapshot = next;
      loadError = null;
      for (final sold in next.sales) {
        final ids = _cards.entries
            .where((item) => item.value.pending?.commandId == sold.commandId)
            .map((item) => item.key)
            .toList();
        for (final id in ids) {
          _closedIds.add(id);
          _cards.remove(id)?.timer?.cancel();
          notice = sold.result.creditMinor > 0
              ? '${sold.label}: venta con deuda recuperada.'
              : '${sold.label}: venta pagada recuperada.';
        }
      }
      for (final account in next.accounts) {
        if (_closedIds.contains(account.id) ||
            account.status == 'confirmed' ||
            account.status == 'cancelled') {
          continue;
        }
        final card = _cards.putIfAbsent(account.id, () => _CardState(account));
        if (!card.dirty &&
            card.saving == null &&
            !card.acting &&
            account.revision >= card.account.revision) {
          card.account = account;
        }
        final pending = next.pendingSales
            .where((item) => item.accountId == account.id)
            .firstOrNull;
        if (pending != null) {
          card.pending = pending;
          card.preparation = null;
        } else if (card.awaitingUnlock &&
            account.status == 'open' &&
            account.revision > (card.pending?.accountRevision ?? 0)) {
          card.account = account;
          card.pending = null;
          card.preparation = null;
          card.awaitingUnlock = false;
          card.error = null;
          card.editorEpoch++;
        }
      }
      final openIds = next.accounts
          .where(
            (item) => item.status != 'confirmed' && item.status != 'cancelled',
          )
          .map((item) => item.id)
          .toSet();
      for (final entry in _cards.entries.toList()) {
        final card = entry.value;
        if (card.account.revision == 0 ||
            card.saving != null ||
            card.acting ||
            card.pending != null ||
            openIds.contains(entry.key)) {
          continue;
        }
        if (card.dirty) {
          card.saveRejected = true;
          card.error =
              'La cuenta guardada ya no está abierta. Recupera su estado antes de continuar.';
        } else {
          _cards.remove(entry.key)?.timer?.cancel();
        }
      }
    } catch (_) {
      if (_disposed || generation != _readGeneration) return;
      loadError =
          'No se pudo actualizar. Tus cuentas y cambios siguen aquí. '
          'Pulsa Actualizar para recuperar la información.';
    }
  }

  String? addAccount() {
    if (_disposed || snapshot == null) return null;
    var number = 1;
    final labels = _cards.values.map((card) => card.account.label).toSet();
    while (labels.contains('Cuenta $number')) {
      number++;
    }
    final id = InventoryIds.next();
    final account = QuickSaleAccount(
      id: id,
      label: 'Cuenta $number',
      revision: 0,
      status: 'open',
      updatedAtUtc: DateTime.now().toUtc(),
      lines: [_emptyLine()],
    );
    _cards[id] = _CardState(account)..generation = 1;
    _schedule(id);
    notice = null;
    _emit();
    return id;
  }

  QuickSaleLine _emptyLine() => QuickSaleLine(
    id: InventoryIds.next(),
    paymentOptionId: snapshot?.paymentOptions
        .where((item) => item.isActive)
        .firstOrNull
        ?.id,
  );

  void rename(String id, String label) => _change(id, label: label);

  void updateCustomerName(String id, String customerName) =>
      _change(id, customerName: customerName);

  void addLine(String id) {
    final card = _cards[id];
    if (card == null) return;
    if (card.account.lines.length >= 100) {
      card.error = 'Cada cuenta admite hasta 100 líneas.';
      _emit();
      return;
    }
    _change(id, lines: [...card.account.lines, _emptyLine()]);
  }

  void removeLine(String id, String lineId) {
    final card = _cards[id];
    if (card == null) return;
    final lines = card.account.lines
        .where((line) => line.id != lineId)
        .toList();
    _change(id, lines: lines.isEmpty ? [_emptyLine()] : lines);
  }

  void editLine(String id, QuickSaleLine line) {
    final card = _cards[id];
    if (card == null) return;
    _change(
      id,
      lines: [
        for (final current in card.account.lines)
          if (current.id == line.id) line else current,
      ],
    );
  }

  void _change(
    String id, {
    String? label,
    String? customerName,
    List<QuickSaleLine>? lines,
  }) {
    final card = _cards[id];
    if (_disposed || card == null || isLocked(id)) return;
    card.account = _copy(
      card.account,
      label: label,
      customerName: customerName,
      lines: lines,
    );
    card.generation++;
    card.error = null;
    notice = null;
    _schedule(id);
    _emit();
  }

  void _schedule(String id) {
    final card = _cards[id]!;
    card.timer?.cancel();
    card.timer = Timer(autosaveDelay, () => unawaited(flush(id)));
  }

  /// Flushes all revisions through one queue per card. A result lost after a
  /// durable save is retried before any newer local revision is sent.
  Future<bool> flush(String id) async {
    final card = _cards[id];
    if (_disposed || card == null) return false;
    card.timer?.cancel();
    final running = card.saving;
    if (running != null) return running;
    if (!card.dirty && card.uncertainSave == null) return true;
    final done = Completer<bool>();
    card.saving = done.future;
    _emit();
    final ok = await _drain(card);
    card.saving = null;
    done.complete(ok);
    _emit();
    return ok;
  }

  Future<bool> _drain(_CardState card) async {
    while (!_disposed && (card.dirty || card.uncertainSave != null)) {
      final input =
          card.uncertainSave ??
          SaveQuickSaleAccount(
            id: card.account.id,
            label: card.account.label,
            customerName: card.account.customerName,
            expectedRevision: card.account.revision,
            lines: card.account.lines,
          );
      if (card.uncertainSave == null) {
        card.sentGeneration = card.generation;
        card.uncertainSave = input;
      }
      try {
        final saved = await store.saveAccount(input);
        if (_disposed) return false;
        card.account = card.generation == card.sentGeneration
            ? saved
            : _copy(card.account, revision: saved.revision);
        card.savedGeneration = card.sentGeneration;
        card.uncertainSave = null;
        card.error = null;
        card.saveRejected = false;
      } on QuickSalesValidationException catch (failure) {
        card.uncertainSave = null;
        card.error = failure.message;
        card.saveRejected = true;
        return false;
      } catch (_) {
        card.error =
            'No se pudo confirmar el guardado. Conserva la app abierta y '
            'pulsa Reintentar guardado.';
        return false;
      }
    }
    return !_disposed;
  }

  BigInt totalFor(QuickSaleAccount account) => account.lines.fold(
    BigInt.zero,
    (sum, line) =>
        sum +
        BigInt.from(line.unitPriceMinor ?? 0) *
            BigInt.from(int.tryParse(line.quantityText) ?? 0),
  );

  bool hasCreditFor(QuickSaleAccount account) => account.lines.any(
    (line) => line.paymentOptionId == QuickPaymentOption.creditId,
  );

  BigInt creditTotalFor(QuickSaleAccount account) => account.lines
      .where((line) => line.paymentOptionId == QuickPaymentOption.creditId)
      .fold(
        BigInt.zero,
        (sum, line) =>
            sum +
            BigInt.from(line.unitPriceMinor ?? 0) *
                BigInt.from(int.tryParse(line.quantityText) ?? 0),
      );

  Future<bool> register(String id) async {
    final card = _cards[id];
    if (_disposed || card == null || isLocked(id)) return false;
    card.acting = true;
    card.error = null;
    _emit();
    if (!await flush(id)) {
      card.acting = false;
      _emit();
      return false;
    }
    final now = DateTime.now().toUtc();
    final total = totalFor(card.account);
    if (total <= BigInt.zero || total > BigInt.from(0x7fffffffffffffff)) {
      card.error =
          'Elige productos y cantidades válidas para registrar la venta.';
      card.acting = false;
      _emit();
      return false;
    }
    final customer = card.account.customerName.trim();
    if (hasCreditFor(card.account) &&
        (customer.isEmpty ||
            customer.length > 120 ||
            RegExp(r'[\x00-\x1f\x7f]').hasMatch(customer))) {
      card.error = 'Escribe el nombre del cliente para registrar la deuda.';
      card.acting = false;
      _emit();
      return false;
    }
    final preparation = _Preparation(
      commandId: InventoryIds.next(),
      accountId: id,
      revision: card.account.revision,
      occurredAtUtc: now,
    );
    card.preparation = preparation;
    card.pending = PreparedQuickSale(
      commandId: preparation.commandId,
      accountId: id,
      accountRevision: card.account.revision,
      label: card.account.label,
      totalMinor: total.toInt(),
      creditMinor: creditTotalFor(card.account).toInt(),
      customerName: hasCreditFor(card.account) ? customer : '',
      occurredAtUtc: now,
      preparedAtUtc: now,
      status: 'prepared',
    );
    return _dispatch(card);
  }

  Future<bool> retry(String id) async {
    final card = _cards[id];
    if (_disposed ||
        card == null ||
        card.acting ||
        card.pending == null ||
        card.pending!.status == 'rejected') {
      return false;
    }
    card.acting = true;
    return _dispatch(card);
  }

  Future<bool> _dispatch(_CardState card) async {
    final pending = card.pending!;
    card.error = null;
    _emit();
    try {
      final preparation = card.preparation;
      if (preparation != null) {
        card.pending = await store.prepareSale(
          commandId: preparation.commandId,
          accountId: preparation.accountId,
          expectedRevision: preparation.revision,
          occurredAtUtc: preparation.occurredAtUtc,
        );
        card.preparation = null;
      }
      final result = await store.confirmPrepared(pending.commandId);
      _closedIds.add(card.account.id);
      _cards.remove(card.account.id)?.timer?.cancel();
      notice = result.creditMinor > 0
          ? '${card.account.label}: venta registrada con deuda a nombre de ${result.customerName}.'
          : '${card.account.label}: venta registrada y pagada.';
      await _reload();
      return true;
    } on QuickSalesValidationException catch (failure) {
      if (card.preparation != null) {
        card.preparation = null;
        card.pending = null;
      } else {
        card.pending = PreparedQuickSale(
          commandId: pending.commandId,
          accountId: pending.accountId,
          accountRevision: pending.accountRevision,
          label: pending.label,
          totalMinor: pending.totalMinor,
          creditMinor: pending.creditMinor,
          customerName: pending.customerName,
          occurredAtUtc: pending.occurredAtUtc,
          preparedAtUtc: pending.preparedAtUtc,
          status: 'rejected',
          rejectionReason: failure.message,
        );
      }
      card.error = failure.message;
      await _reload();
      return false;
    } catch (_) {
      card.error =
          'No se pudo confirmar el resultado. Reintenta esta misma venta; '
          'las otras cuentas siguen disponibles.';
      return false;
    } finally {
      card.acting = false;
      _emit();
    }
  }

  Future<bool> unlockRejected(String id) async {
    final card = _cards[id];
    if (_disposed ||
        card == null ||
        card.acting ||
        card.pending?.status != 'rejected') {
      return false;
    }
    card.acting = true;
    _emit();
    try {
      await store.discardRejected(card.pending!.commandId);
      card.awaitingUnlock = true;
      final refreshed = await store.load();
      final account = refreshed.accounts.where((item) => item.id == id).first;
      card.account = account;
      card.pending = null;
      card.preparation = null;
      card.awaitingUnlock = false;
      card.editorEpoch++;
      card.error = null;
      snapshot = refreshed;
      return true;
    } catch (_) {
      card.error = 'No se pudo recuperar la cuenta para corregirla. Reintenta.';
      return false;
    } finally {
      card.acting = false;
      _emit();
    }
  }

  Future<bool> removeAccount(String id) async {
    final card = _cards[id];
    if (_disposed || card == null || isLocked(id)) return false;
    card.acting = true;
    _emit();
    try {
      if (!await flush(id)) return false;
      await store.cancelAccount(
        accountId: id,
        expectedRevision: card.account.revision,
      );
      _closedIds.add(id);
      _cards.remove(id)?.timer?.cancel();
      return true;
    } catch (_) {
      card.error = 'No se pudo quitar la cuenta. Pulsa Actualizar y reintenta.';
      return false;
    } finally {
      card.acting = false;
      _emit();
    }
  }

  /// Explicitly discards only this card's local edits after a known rejection.
  /// The page asks the operator before calling it; uncertain writes cannot use
  /// this path because they must replay their original input first.
  Future<bool> recoverSavedAccount(String id) async {
    final card = _cards[id];
    if (_disposed ||
        card == null ||
        card.acting ||
        card.saving != null ||
        !card.saveRejected ||
        card.uncertainSave != null ||
        card.pending != null) {
      return false;
    }
    card.acting = true;
    card.timer?.cancel();
    _emit();
    try {
      final next = await store.load();
      if (_disposed) return false;
      final restored = next.accounts.where((item) => item.id == id).firstOrNull;
      snapshot = next;
      loadError = null;
      if (restored == null) {
        _closedIds.add(id);
        _cards.remove(id);
      } else {
        final state = _CardState(restored)..editorEpoch = card.editorEpoch + 1;
        state.pending = next.pendingSales
            .where((item) => item.accountId == id)
            .firstOrNull;
        _cards[id] = state;
      }
      return true;
    } catch (_) {
      card.error =
          'No se pudo recuperar la cuenta guardada. Tus cambios siguen aquí.';
      return false;
    } finally {
      card.acting = false;
      _emit();
    }
  }

  Future<bool> flushAll() async {
    var ok = true;
    for (final id in _cards.keys.toList()) {
      if (!await flush(id)) ok = false;
    }
    return ok;
  }

  QuickSaleAccount _copy(
    QuickSaleAccount current, {
    String? label,
    String? customerName,
    List<QuickSaleLine>? lines,
    int? revision,
  }) => QuickSaleAccount(
    id: current.id,
    label: label ?? current.label,
    customerName: customerName ?? current.customerName,
    revision: revision ?? current.revision,
    status: current.status,
    updatedAtUtc: current.updatedAtUtc,
    lines: lines ?? current.lines,
    confirmedDocumentId: current.confirmedDocumentId,
  );

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    for (final card in _cards.values) {
      card.timer?.cancel();
    }
    _disposed = true;
    super.dispose();
  }
}

class _CardState {
  _CardState(this.account);
  QuickSaleAccount account;
  int generation = 0;
  int savedGeneration = 0;
  int sentGeneration = 0;
  bool get dirty => generation != savedGeneration;
  Timer? timer;
  Future<bool>? saving;
  SaveQuickSaleAccount? uncertainSave;
  bool acting = false;
  bool saveRejected = false;
  bool awaitingUnlock = false;
  int editorEpoch = 0;
  String? error;
  PreparedQuickSale? pending;
  _Preparation? preparation;
}

class _Preparation {
  const _Preparation({
    required this.commandId,
    required this.accountId,
    required this.revision,
    required this.occurredAtUtc,
  });
  final String commandId;
  final String accountId;
  final int revision;
  final DateTime occurredAtUtc;
}
