import 'package:flutter/foundation.dart';
import '../domain/events_store.dart';

class EventsController extends ChangeNotifier {
  EventsController({required this.store});
  final EventsStore store;
  EventsSnapshot? snapshot;
  String? error, message;
  CreateEvent? uncertainCreation;
  bool busy = false, _disposed = false;
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

  Future<bool> create(CreateEvent command) => _run(
    () async {
      await store.prepare(command);
      await store.confirm(command.commandId);
      message = 'Evento creado. Ya está disponible en Catálogo y Ventas.';
    },
    creation: command,
    confirmedId: command.commandId,
  );
  Future<bool> retry(String id) => _run(() async {
    await store.confirm(id);
    message = 'Evento creado sin repetir los descuentos.';
  }, confirmedId: id);
  Future<bool> discard(String id) => _run(() async {
    await store.discard(id);
    message = 'Solicitud descartada sin registrar el evento.';
  });
  Future<bool> deactivate(String id) => _run(() async {
    await store.deactivate(id);
    message = 'Evento desactivado. Sus costos e historial se conservan.';
  });
  Future<bool> _run(
    Future<void> Function() action, {
    CreateEvent? creation,
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
          snapshot!.confirmedCommandIds.contains(confirmedId)) {
        ok = true;
        error = null;
        message = 'Evento creado. Ya está disponible en Catálogo y Ventas.';
      }
      if (creation != null || confirmedId == uncertainCreation?.commandId) {
        uncertainCreation = null;
      }
    } catch (e) {
      if (!ok && creation != null) uncertainCreation = creation;
      error ??=
          'No se pudo actualizar. Pulsa Actualizar para recuperar la solicitud: $e';
    }
    busy = false;
    _emit();
    return ok;
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
