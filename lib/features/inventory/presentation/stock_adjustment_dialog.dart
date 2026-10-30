import 'package:flutter/material.dart';
import '../../../core/domain/money.dart';
import '../../../core/presentation/grouped_number_formatter.dart';
import '../application/inventory_controller.dart';
import '../domain/inventory_store.dart';
import '../domain/stock_adjustment_store.dart';

class StockAdjustmentDialog extends StatefulWidget {
  const StockAdjustmentDialog({
    super.key,
    required this.controller,
    required this.store,
  });
  final InventoryController controller;
  final StockAdjustmentStore store;
  @override
  State<StockAdjustmentDialog> createState() => _StockAdjustmentDialogState();
}

class _StockAdjustmentDialogState extends State<StockAdjustmentDialog> {
  final _quantity = TextEditingController(), _reason = TextEditingController();
  String? _productId, _error;
  StockAdjustmentCommand? _pending;
  bool _busy = true;
  bool _loaded = false;
  List<StockAdjustmentCommand> _requests = [];
  Map<String, int> get _positions => {
    for (final s in widget.controller.snapshot?.stock ?? <StockPosition>[])
      s.productId: s.quantity,
  };
  List<CatalogProduct> get _products =>
      (widget.controller.snapshot?.products ?? <CatalogProduct>[])
          .where((p) => !p.isUnlimited)
          .toList();
  CatalogProduct? get _selected => widget.controller.snapshot?.products
      .where((p) => p.id == _productId)
      .firstOrNull;
  int? get _units {
    final n = BigInt.tryParse(_quantity.text.replaceAll('.', ''));
    return n != null && n != BigInt.zero && n.abs() <= Money.maxMinorUnits
        ? n.toInt()
        : null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final pending = await widget.store.pendingAdjustments();
      if (!mounted) return;
      setState(() {
        _requests = pending;
        _loaded = true;
        _pending = pending.firstOrNull;
        if (_pending != null) {
          _productId = _pending!.productId;
          _quantity.text = GroupedNumberFormatter.format(
            '${_pending!.isAddition ? _pending!.quantity : -_pending!.quantity}',
          );
          _reason.text = _pending!.reason;
        }
        _busy = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error =
              'No se pudieron consultar las solicitudes pendientes. Cierra y vuelve a abrir este menú.';
        });
      }
    }
  }

  @override
  void dispose() {
    _quantity.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_loaded) return;
    if (_pending == null) {
      final units = _units;
      if (_productId == null ||
          !_products.any((p) => p.id == _productId) ||
          units == null ||
          BigInt.from(_positions[_productId] ?? 0) + BigInt.from(units) <
              BigInt.zero ||
          BigInt.from(_positions[_productId] ?? 0) + BigInt.from(units) >
              Money.maxMinorUnits) {
        setState(
          () => _error =
              'Elige un producto y un entero distinto de 0. Usa positivo para sumar o negativo para restar, sin dejar existencias negativas.',
        );
        return;
      }
      _pending = StockAdjustmentCommand(
        commandId: InventoryIds.next(),
        productId: _productId!,
        quantity: units.abs(),
        isAddition: units > 0,
        reason: _reason.text.trim().isEmpty
            ? 'Ajuste manual de inventario'
            : _reason.text.trim(),
        occurredAtUtc: DateTime.now().toUtc(),
      );
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.store.prepareAdjustment(_pending!);
      await widget.store.confirmAdjustment(_pending!.commandId);
      if (mounted) Navigator.pop(context, true);
    } on StockAdjustmentValidationException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'No se pudo confirmar el resultado. Reintenta el mismo ajuste; la solicitud queda guardada para evitar duplicados.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _discard() async {
    final pending = _pending;
    if (pending == null || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.store.discardAdjustment(pending.commandId);
      if (!mounted) return;
      setState(() {
        _pending = null;
        _error = null;
      });
      await _load();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'No se pudo descartar. Si el ajuste ya se registró, reintenta para recuperar su confirmación.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = _busy || _pending != null;
    final available = _positions[_productId] ?? 0, units = _units;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('Corregir inventario'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Usa un número positivo para sumar unidades o negativo para restarlas. No registra compras, ventas ni movimientos de dinero.',
                ),
                const SizedBox(height: 16),
                if (_busy) const LinearProgressIndicator(),
                if (_pending != null) ...[
                  Text(
                    'Solicitud guardada: ${_selected?.name ?? _pending!.productId} · ${GroupedNumberFormatter.format('${_pending!.isAddition ? '+' : '-'}${_pending!.quantity}')} unidades',
                  ),
                  if (_requests.length > 1)
                    Text(
                      'Hay ${_requests.length} ajustes pendientes; se resuelve primero el más antiguo.',
                    ),
                ] else
                  Autocomplete<CatalogProduct>(
                    displayStringForOption: (p) => p.name,
                    optionsBuilder: (text) => _products.where(
                      (p) =>
                          p.name.toLowerCase().contains(
                            text.text.trim().toLowerCase(),
                          ) ||
                          (p.sku?.toLowerCase().contains(
                                text.text.trim().toLowerCase(),
                              ) ??
                              false),
                    ),
                    onSelected: (p) => setState(() {
                      _productId = p.id;
                      _error = null;
                    }),
                    fieldViewBuilder: (context, text, focus, submit) =>
                        TextField(
                          key: const Key('stock-adjustment-product'),
                          controller: text,
                          focusNode: focus,
                          enabled: !locked,
                          decoration: const InputDecoration(
                            labelText: 'Producto',
                            hintText: 'Buscar por nombre o SKU',
                          ),
                          onChanged: (value) {
                            if (value != _selected?.name) {
                              setState(() => _productId = null);
                            }
                          },
                          onSubmitted: (_) => submit(),
                        ),
                  ),
                const SizedBox(height: 16),
                if (_selected != null)
                  Text(
                    'Disponibles: ${GroupedNumberFormatter.format('$available')}',
                  ),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('stock-adjustment-quantity'),
                  controller: _quantity,
                  enabled: !locked,
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                  ),
                  inputFormatters: const [GroupedNumberFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Cambio de unidades (+ / −)',
                  ),
                  onChanged: (_) => setState(() => _error = null),
                ),
                if (_selected != null &&
                    units != null &&
                    BigInt.from(available) + BigInt.from(units) >=
                        BigInt.zero &&
                    BigInt.from(available) + BigInt.from(units) <=
                        Money.maxMinorUnits)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Quedarán ${GroupedNumberFormatter.format('${BigInt.from(available) + BigInt.from(units)}')} unidades.',
                      key: const Key('stock-adjustment-remaining'),
                    ),
                  ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('stock-adjustment-reason'),
                  controller: _reason,
                  enabled: !locked,
                  maxLength: 300,
                  decoration: const InputDecoration(
                    labelText: 'Motivo (opcional)',
                  ),
                ),
                if (_error != null)
                  Text(
                    _error!,
                    key: const Key('stock-adjustment-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
          if (_pending != null)
            TextButton(
              key: const Key('stock-adjustment-discard'),
              onPressed: _busy ? null : _discard,
              child: const Text('Descartar solicitud'),
            ),
          FilledButton(
            key: const Key('stock-adjustment-submit'),
            onPressed: _busy || !_loaded ? null : _submit,
            child: Text(
              _busy
                  ? 'Procesando…'
                  : _pending == null
                  ? 'Aplicar ajuste'
                  : 'Reintentar mismo ajuste',
            ),
          ),
        ],
      ),
    );
  }
}
