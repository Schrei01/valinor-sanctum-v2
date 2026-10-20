import 'package:flutter/foundation.dart';

import '../domain/treasury_store.dart';

class TreasuryController extends ChangeNotifier {
  TreasuryController({required this.store});

  final TreasuryStore store;
  TreasurySnapshot? snapshot;
  bool loading = false;
  String? loadError;
  bool _disposed = false;

  Future<void> load() async {
    if (loading || _disposed) return;
    loading = true;
    loadError = null;
    notifyListeners();
    try {
      await store.ensureDefaults();
      final next = await store.load();
      if (_disposed) return;
      snapshot = next;
    } catch (_) {
      if (_disposed) return;
      loadError = snapshot == null
          ? 'No se pudo cargar Tesorería. Pulsa Actualizar para intentarlo de nuevo.'
          : 'No se pudo actualizar Tesorería. Los saldos y movimientos visibles pueden estar desactualizados.';
    } finally {
      loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
