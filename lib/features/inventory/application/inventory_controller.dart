import 'package:flutter/foundation.dart';

import '../../../core/domain/money.dart';
import '../domain/inventory_store.dart';

/// Keeps a receipt's identity and payload until its result is known. Refreshing
/// a screen or retrying an uncertain write must never create another purchase.
class InventoryController extends ChangeNotifier {
  InventoryController({required this.store});

  final InventoryStore store;
  InventorySnapshot? snapshot;
  bool loading = false;
  bool saving = false;
  bool receiving = false;
  String? loadError;
  String? catalogError;
  String? receiptError;
  ReceiptCommand? _pendingReceipt;
  bool _disposed = false;

  ReceiptCommand? get pendingReceipt => _pendingReceipt;
  bool get busy => loading || saving || receiving;

  bool isProductAvailable(CatalogProduct product) =>
      product.isActive &&
      (product.categoryId == null ||
          (snapshot?.categories.any(
                (category) =>
                    category.id == product.categoryId && category.isActive,
              ) ??
              false));

  Future<void> load() async {
    if (busy || _disposed) return;
    loading = true;
    loadError = null;
    _emit();
    await _reload();
    loading = false;
    _emit();
  }

  Future<bool> saveCategory(InventoryCategory category) =>
      _save(() => store.saveCategory(category));

  Future<bool> saveSupplier(InventorySupplier supplier) =>
      _save(() => store.saveSupplier(supplier));

  Future<bool> saveProduct(CatalogProduct product) =>
      _save(() => store.saveProduct(product));

  Future<bool> _save(Future<void> Function() action) async {
    if (busy || _disposed) return false;
    saving = true;
    catalogError = null;
    _emit();
    try {
      await action();
      await _reload();
      // A read failure after a confirmed save does not turn that save into a
      // failed command. The screen retains its last snapshot and offers reload.
      return true;
    } catch (failure) {
      catalogError = _message(
        failure,
        'No se pudo guardar. Vuelve a intentarlo.',
      );
      return false;
    } finally {
      saving = false;
      _emit();
    }
  }

  Future<bool> receivePurchase({
    required String supplierId,
    required List<ReceiptLineInput> lines,
    required String dueDate,
    String? reference,
    DateTime? occurredAtUtc,
  }) async {
    if (busy || _disposed || _pendingReceipt != null) return false;
    final occurred = occurredAtUtc ?? DateTime.now().toUtc();
    try {
      _validateReceipt(supplierId, lines, dueDate, occurred);
      final trimmedReference = reference?.trim();
      if (trimmedReference != null &&
          (trimmedReference.length > 120 ||
              RegExp(r'[\x00-\x1f]').hasMatch(trimmedReference))) {
        throw ArgumentError('La referencia admite hasta 120 caracteres.');
      }
      _pendingReceipt = ReceiptCommand(
        commandId: InventoryIds.next(),
        supplierId: supplierId,
        lines: lines,
        dueDate: dueDate,
        occurredAtUtc: occurred,
        reference: trimmedReference == null || trimmedReference.isEmpty
            ? null
            : trimmedReference,
      );
    } catch (failure) {
      receiptError = _message(failure, 'Revisa los datos de la compra.');
      _emit();
      return false;
    }
    return _dispatchReceipt();
  }

  Future<bool> retryReceipt() async {
    if (busy || _disposed || _pendingReceipt == null) return false;
    return _dispatchReceipt();
  }

  Future<bool> _dispatchReceipt() async {
    receiving = true;
    receiptError = null;
    _emit();
    try {
      await store.receivePurchase(_pendingReceipt!);
      _pendingReceipt = null;
      await _reload();
      return true;
    } on InventoryValidationException catch (failure) {
      // The adapter only uses this error when no receipt was committed.
      _pendingReceipt = null;
      receiptError = failure.message;
      return false;
    } catch (_) {
      receiptError =
          'No pudimos confirmar el resultado. Conservamos esta compra para '
          'reintentar de forma segura; sus datos están bloqueados.';
      return false;
    } finally {
      receiving = false;
      _emit();
    }
  }

  void _validateReceipt(
    String supplierId,
    List<ReceiptLineInput> lines,
    String dueDate,
    DateTime occurred,
  ) {
    final data = snapshot;
    if (data == null ||
        !data.suppliers.any((item) => item.id == supplierId && item.isActive)) {
      throw ArgumentError('Selecciona un proveedor activo.');
    }
    if (!occurred.isUtc) {
      throw ArgumentError('La fecha de recepción no es válida.');
    }
    if (!isValidIsoDate(dueDate)) {
      throw ArgumentError(
        'Escribe un vencimiento real con formato AAAA-MM-DD.',
      );
    }
    final todayBogota = occurred.subtract(const Duration(hours: 5));
    final receivedDate = isoDate(todayBogota);
    if (dueDate.compareTo(receivedDate) < 0) {
      throw ArgumentError(
        'El vencimiento no puede ser anterior a la recepción.',
      );
    }
    if (lines.isEmpty) throw ArgumentError('Añade al menos un producto.');
    final seen = <String>{};
    var total = BigInt.zero;
    for (final line in lines) {
      if (!data.products.any(
        (item) => item.id == line.productId && isProductAvailable(item),
      )) {
        throw ArgumentError('Cada línea debe tener un producto activo.');
      }
      if (!seen.add(line.productId)) {
        throw ArgumentError('Un producto solo puede aparecer en una línea.');
      }
      if (line.quantity <= 0 ||
          BigInt.from(line.quantity) > Money.maxMinorUnits) {
        throw ArgumentError('La cantidad debe ser un entero positivo.');
      }
      if (line.totalCostMinor < 0) {
        throw ArgumentError('El costo total no puede ser negativo.');
      }
      total += BigInt.from(line.totalCostMinor);
    }
    if (total <= BigInt.zero || total > Money.maxMinorUnits) {
      throw ArgumentError(
        'El total debe ser positivo y estar dentro del límite.',
      );
    }
  }

  Future<void> _reload() async {
    try {
      final next = await store.load();
      if (!_disposed) snapshot = next;
      loadError = null;
    } catch (_) {
      loadError =
          'No se pudo actualizar la información. Los datos visibles pueden '
          'estar desactualizados. Pulsa Actualizar.';
    }
  }

  static bool isValidIsoDate(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
    final parsed = DateTime.tryParse(value);
    return parsed != null && isoDate(parsed) == value;
  }

  static String isoDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String _message(Object failure, String fallback) {
    if (failure is InventoryValidationException) return failure.message;
    if (failure is ArgumentError) {
      return failure.message?.toString() ?? fallback;
    }
    return fallback;
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
