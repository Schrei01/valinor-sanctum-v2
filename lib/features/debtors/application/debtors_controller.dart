import 'package:flutter/foundation.dart';
import '../domain/debtors_store.dart';

class DebtorsController extends ChangeNotifier {
  DebtorsController({required this.store});
  final DebtorsStore store;
  DebtorsSnapshot? snapshot;
  bool busy = false, _disposed = false;
  String? error, message, lastPersonId;
  DebtorCommand? uncertain;
  Future<void> load() async {
    if (busy || _disposed) return;
    busy = true;
    error = null;
    _emit();
    try {
      snapshot = await store.load();
    } catch (e) {
      error = e.toString();
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<bool> submit(DebtorCommand c) => _run(
    () async {
      await store.prepare(c);
      lastPersonId = await store.confirm(c.commandId);
      message = _success(c.kind);
    },
    command: c,
    confirmedId: c.commandId,
  );
  Future<bool> retry(String id) => _run(() async {
    lastPersonId = await store.confirm(id);
    message = 'Operación recuperada sin repetir movimientos.';
  }, confirmedId: id);
  Future<bool> discard(String id) => _run(() async {
    await store.discard(id);
    message = 'Solicitud descartada sin registrar movimientos.';
  });
  Future<bool> setActive(String id, bool active) => _run(() async {
    await store.setActive(id, active);
    message = active
        ? 'Persona habilitada para nuevas deudas.'
        : 'Fiado bloqueado. Puede seguir abonando su deuda.';
  });
  Future<bool> retryLegacy(String id) => _run(() async {
    await store.retryLegacyCollection(id);
    message = 'Cobro anterior recuperado.';
  });
  Future<bool> discardLegacy(String id) => _run(() async {
    await store.discardLegacyCollection(id);
    message = 'Cobro rechazado liberado.';
  });
  Future<bool> _run(
    Future<void> Function() action, {
    DebtorCommand? command,
    String? confirmedId,
  }) async {
    if (busy || _disposed) return false;
    busy = true;
    error = null;
    message = null;
    _emit();
    var ok = false;
    try {
      await action();
      ok = true;
    } catch (e) {
      error = e.toString();
    }
    try {
      snapshot = await store.load();
      if (confirmedId != null &&
          snapshot!.confirmedCommands.contains(confirmedId)) {
        lastPersonId = await store.confirm(confirmedId);
        ok = true;
        error = null;
        message = command == null
            ? 'Operación recuperada sin repetir movimientos.'
            : _success(command.kind);
      }
      if (command != null || confirmedId == uncertain?.commandId) {
        uncertain = null;
      }
    } catch (e) {
      if (!ok && command != null) uncertain = command;
      error ??=
          'No se pudo verificar el resultado. Reintenta la misma solicitud: $e';
    }
    busy = false;
    _emit();
    return ok;
  }

  String _success(String kind) => switch (kind) {
    'create' => 'Persona registrada. Ya puedes seleccionarla en Ventas.',
    'opening' => 'Saldo anterior registrado.',
    'payment' =>
      'Abono registrado. La deuda y la cuenta de dinero están actualizadas.',
    _ => 'Deuda anterior asignada sin aumentar el total.',
  };
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
