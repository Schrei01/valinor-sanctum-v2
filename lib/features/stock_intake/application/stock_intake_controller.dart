import 'package:flutter/foundation.dart';

import '../../../core/domain/money.dart';
import '../../inventory/domain/inventory_store.dart';
import '../domain/stock_intake_store.dart';

class StockIntakeController extends ChangeNotifier {
  StockIntakeController({required this.store});
  final StockIntakeStore store;
  StockIntakeSnapshot? snapshot;
  bool loading = false;
  bool confirming = false;
  bool savingOpening = false;
  String? loadError;
  String? operationError;
  String? operationNotice;
  int confirmedVersion = 0;
  bool _disposed = false;
  StockIntakeCommand? _preparation;
  PreparedStockIntake? _localPending;
  CashOpeningCommand? _opening;
  final _resolved = <String>{};

  bool get busy => loading || confirming || savingOpening;
  CashOpeningCommand? get pendingOpening => _opening;
  List<PreparedStockIntake> get pendingIntakes => [
    ?_localPending,
    ...?snapshot?.pendingIntakes.where(
      (item) =>
          item.command.commandId != _localPending?.command.commandId &&
          !_resolved.contains(item.command.commandId),
    ),
  ];
  bool get formLocked => busy || pendingIntakes.isNotEmpty || _opening != null;

  Future<void> load() async {
    if (busy || _disposed) return;
    loading = true;
    loadError = null;
    _emit();
    try {
      await store.ensureDefaults();
      await _reload();
    } catch (_) {
      loadError =
          'No se pudieron cargar los productos y saldos. Pulsa Actualizar.';
    } finally {
      loading = false;
      _emit();
    }
  }

  Future<bool> receive({
    CatalogProduct? expectedProduct,
    required String productName,
    String? sku,
    required String categoryId,
    String? supplierId,
    required String supplierName,
    int? unitPurchasePriceMinor,
    int? totalPurchasePriceMinor,
    required int listPriceMinor,
    required int quantity,
    required String paymentOptionId,
    DateTime? occurredAtUtc,
  }) async {
    if (formLocked || _disposed || snapshot == null || loadError != null) {
      return false;
    }
    operationNotice = null;
    operationError = null;
    try {
      _validate(
        productName,
        sku,
        categoryId,
        supplierName,
        unitPurchasePriceMinor,
        totalPurchasePriceMinor,
        listPriceMinor,
        quantity,
        paymentOptionId,
      );
      final now = occurredAtUtc ?? DateTime.now().toUtc();
      if (!now.isUtc) throw ArgumentError('La fecha del ingreso no es válida.');
      final trimmedSku = sku?.trim();
      _preparation = StockIntakeCommand(
        commandId: InventoryIds.next(),
        productId: expectedProduct?.id ?? InventoryIds.next(),
        expectedProduct: expectedProduct,
        productName: productName.trim(),
        sku: trimmedSku == null || trimmedSku.isEmpty ? null : trimmedSku,
        categoryId: categoryId,
        supplierId: supplierId,
        supplierName: supplierName.trim(),
        unitPurchasePriceMinor: unitPurchasePriceMinor,
        totalPurchasePriceMinor: totalPurchasePriceMinor,
        listPriceMinor: listPriceMinor,
        quantity: quantity,
        paymentOptionId: paymentOptionId,
        occurredAtUtc: now,
      );
      _localPending = PreparedStockIntake(
        command: _preparation!,
        status: 'prepared',
        preparedAtUtc: now,
      );
    } catch (failure) {
      operationError = failure is ArgumentError
          ? failure.message?.toString() ?? 'Revisa los datos del ingreso.'
          : 'Revisa los datos del ingreso.';
      _emit();
      return false;
    }
    return _dispatch(_localPending!);
  }

  Future<bool> retry(String commandId) async {
    if (busy || _disposed || _opening != null) return false;
    final pending = pendingIntakes
        .where((item) => item.command.commandId == commandId)
        .firstOrNull;
    if (pending == null || pending.status == 'rejected') return false;
    return _dispatch(pending);
  }

  Future<bool> _dispatch(PreparedStockIntake pending) async {
    confirming = true;
    operationError = null;
    operationNotice = null;
    _emit();
    try {
      if (_preparation?.commandId == pending.command.commandId) {
        _localPending = await store.prepare(_preparation!);
        _preparation = null;
      }
      final result = await store.confirmPrepared(pending.command.commandId);
      assert(result.commandId == pending.command.commandId);
      _markConfirmed(pending.command.commandId);
      await _reload();
      operationNotice =
          'Producto ingresado. Catálogo, existencias y pago guardados.';
      return true;
    } on StockIntakeValidationException catch (failure) {
      if (_preparation != null) {
        _preparation = null;
        _localPending = null;
      } else {
        _localPending = PreparedStockIntake(
          command: pending.command,
          status: 'rejected',
          preparedAtUtc: pending.preparedAtUtc,
          rejectionReason: failure.message,
        );
      }
      operationError = failure.message;
      await _reload();
      return false;
    } catch (_) {
      operationError =
          'No pudimos confirmar el resultado. Conservamos el ingreso: reintenta la misma solicitud. Si quedó guardada, también se recuperará al volver a abrir.';
      return false;
    } finally {
      confirming = false;
      _emit();
    }
  }

  Future<bool> discardRejected(String commandId) async {
    if (busy || _disposed) return false;
    final pending = pendingIntakes
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
      operationNotice = 'Puedes corregir el ingreso y registrarlo de nuevo.';
      return true;
    } catch (_) {
      operationError =
          'No se pudo habilitar la corrección. Vuelve a intentarlo.';
      return false;
    } finally {
      confirming = false;
      _emit();
    }
  }

  Future<bool> recordOpening({
    required String paymentOptionId,
    required int amountMinor,
    DateTime? occurredAtUtc,
  }) async {
    if (formLocked || _disposed || snapshot == null || loadError != null) {
      return false;
    }
    final option = snapshot!.paymentOptions
        .where((item) => item.id == paymentOptionId && item.isActive)
        .firstOrNull;
    if (option == null || !option.canRecordOpening || amountMinor <= 0) {
      operationError = 'Elige una cuenta sin movimientos y un saldo positivo.';
      _emit();
      return false;
    }
    final now = occurredAtUtc ?? DateTime.now().toUtc();
    if (!now.isUtc) {
      operationError = 'La fecha del saldo inicial no es válida.';
      _emit();
      return false;
    }
    _opening = CashOpeningCommand(
      commandId: InventoryIds.next(),
      paymentOptionId: paymentOptionId,
      amountMinor: amountMinor,
      occurredAtUtc: now,
    );
    return _dispatchOpening();
  }

  Future<bool> retryOpening() async {
    if (busy || _disposed || _opening == null) return false;
    return _dispatchOpening();
  }

  Future<bool> _dispatchOpening() async {
    savingOpening = true;
    operationError = null;
    operationNotice = null;
    _emit();
    try {
      await store.recordOpeningBalance(_opening!);
      _opening = null;
      await _reload();
      operationNotice = 'Saldo inicial declarado guardado.';
      return true;
    } on StockIntakeValidationException catch (failure) {
      _opening = null;
      operationError = failure.message;
      await _reload();
      return false;
    } catch (_) {
      operationError =
          'No pudimos confirmar el saldo inicial. Reintenta el mismo registro antes de continuar.';
      return false;
    } finally {
      savingOpening = false;
      _emit();
    }
  }

  void _validate(
    String productName,
    String? sku,
    String categoryId,
    String supplierName,
    int? unitPurchasePriceMinor,
    int? totalPurchasePriceMinor,
    int listPriceMinor,
    int quantity,
    String paymentOptionId,
  ) {
    for (final name in [productName, supplierName]) {
      if (name.trim().isEmpty ||
          name.trim().length > 120 ||
          RegExp(r'[\x00-\x1f]').hasMatch(name)) {
        throw ArgumentError(
          'Escribe un nombre de producto y proveedor válidos.',
        );
      }
    }
    if ((sku?.trim().length ?? 0) > 64 ||
        RegExp(r'[\x00-\x1f]').hasMatch(sku ?? '')) {
      throw ArgumentError('El SKU admite hasta 64 caracteres.');
    }
    if (!snapshot!.categories.any(
      (item) => item.id == categoryId && item.isActive,
    )) {
      throw ArgumentError('Selecciona una categoría activa.');
    }
    final total = totalPurchasePriceMinor != null
        ? BigInt.from(totalPurchasePriceMinor)
        : BigInt.from(unitPurchasePriceMinor ?? 0) * BigInt.from(quantity);
    final retailTotal = BigInt.from(listPriceMinor) * BigInt.from(quantity);
    if (quantity <= 0 ||
        BigInt.from(quantity) > Money.maxMinorUnits ||
        (unitPurchasePriceMinor == null) == (totalPurchasePriceMinor == null) ||
        total <= BigInt.zero ||
        listPriceMinor < 0 ||
        total > Money.maxMinorUnits ||
        retailTotal > Money.maxMinorUnits) {
      throw ArgumentError(
        'Revisa la cantidad y los precios: el costo debe ser positivo y los totales deben estar dentro del límite.',
      );
    }
    final option = snapshot!.paymentOptions
        .where((item) => item.id == paymentOptionId && item.isActive)
        .firstOrNull;
    if (option == null) {
      throw ArgumentError('Elige de dónde se paga la compra.');
    }
    if (total > BigInt.from(option.balanceMinor)) {
      throw ArgumentError(
        'El saldo de ${option.label} no alcanza para esta compra.',
      );
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
      if (local != null) {
        if (next.entries.any(
          (item) => item.commandId == local.command.commandId,
        )) {
          _markConfirmed(local.command.commandId);
          operationError = null;
          operationNotice =
              'Ingreso recuperado como confirmado. Catálogo, existencias y pago ya están guardados.';
        } else {
          final persisted = next.pendingIntakes
              .where(
                (item) => item.command.commandId == local.command.commandId,
              )
              .firstOrNull;
          if (persisted != null) {
            _localPending = persisted;
            _preparation = null;
          }
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
