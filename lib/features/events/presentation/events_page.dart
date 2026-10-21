import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/domain/money.dart';
import '../../inventory/domain/inventory_store.dart';
import '../../inventory/presentation/inventory_widgets.dart';
import '../../workspace/domain/business_profile.dart';
import '../application/events_controller.dart';
import '../domain/events_store.dart';

class EventsPage extends StatefulWidget {
  const EventsPage({
    super.key,
    required this.controller,
    required this.profile,
  });
  final EventsController controller;
  final BusinessProfile profile;
  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _minimum = TextEditingController(text: '0'),
      _fixed = TextEditingController(text: '0'),
      _pvp = TextEditingController();
  final _products = <_ProductRow>[];
  String? _account, _quoteError;
  EventQuote? _quote;
  Timer? _timer;
  int _generation = 0;
  String _money(int n) => inventoryMoney(n, widget.profile);
  int _amount(String text) => Money.parseEsCo(
    text,
    currency: widget.profile.currencyCode,
    scale: widget.profile.moneyScale,
  ).minorUnits;
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in [_name, _minimum, _fixed, _pvp]) {
      c.dispose();
    }
    for (final p in _products) {
      p.quantity.dispose();
    }
    super.dispose();
  }

  CreateEvent _command() => CreateEvent(
    commandId: InventoryIds.next(),
    name: _name.text.trim().isEmpty ? 'Evento' : _name.text.trim(),
    minimumPeople: int.parse(_minimum.text),
    fixedCostMinor: _amount(_fixed.text),
    pvpMinor: _pvp.text.trim().isEmpty ? 1 : _amount(_pvp.text),
    sourceAccountId: _account,
    occurredAtUtc: DateTime.now().toUtc(),
    products: _products
        .map((p) => EventProductInput(p.id!, int.parse(p.quantity.text)))
        .toList(),
  );
  void _changed() {
    _timer?.cancel();
    final generation = ++_generation;
    setState(() {
      _quote = null;
      _quoteError = null;
    });
    _timer = Timer(const Duration(milliseconds: 350), () async {
      try {
        if (_products.any((p) => p.id == null)) return;
        final quote = await widget.controller.store.quote(_command());
        if (mounted && generation == _generation) {
          setState(() => _quote = quote);
        }
      } catch (e) {
        if (mounted && generation == _generation) {
          setState(
            () => _quoteError = e is EventsValidationException
                ? e.message
                : 'Completa los datos para calcular el PU.',
          );
        }
      }
    });
  }

  Future<void> _create() async {
    if (!_form.currentState!.validate()) return;
    if (_products.any((p) => p.id == null)) return;
    final ok = await widget.controller.create(_command());
    if (ok && mounted) _resetForm();
  }

  void _resetForm() {
    _timer?.cancel();
    ++_generation;
    setState(() {
      _name.clear();
      _minimum.text = '0';
      _fixed.text = '0';
      _pvp.clear();
      _account = null;
      _quote = null;
      _quoteError = null;
      for (final p in _products) {
        p.quantity.dispose();
      }
      _products.clear();
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller, data = controller.snapshot;
      final locked =
          controller.busy ||
          controller.uncertainCreation != null ||
          (data?.pending.isNotEmpty ?? false);
      final stock = {
        for (final s in data?.inventory.stock ?? <StockPosition>[])
          s.productId: s.quantity,
      };
      final products =
          data?.inventory.products
              .where((p) => p.isActive && !p.isEvent && (stock[p.id] ?? 0) > 0)
              .toList() ??
          <CatalogProduct>[];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InventoryPageHeading(
            title: 'Eventos',
            subtitle:
                'Crea pasadías, torneos o ligas. El evento aparecerá en Catálogo y Ventas.',
            busy: controller.busy,
            onRefresh: controller.load,
          ),
          if (controller.error != null)
            InventoryNotice(
              text: controller.error!,
              onRetry: controller.busy ? null : controller.load,
            ),
          if (controller.message != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(controller.message!),
            ),
          if (controller.uncertainCreation != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Verificar creación: ${controller.uncertainCreation!.name}',
                    ),
                    const Text(
                      'No se pudo comprobar el guardado. Reintenta la misma solicitud antes de crear otro evento.',
                    ),
                    FilledButton(
                      onPressed: controller.busy
                          ? null
                          : () async {
                              final ok = await controller.create(
                                controller.uncertainCreation!,
                              );
                              if (ok && mounted) _resetForm();
                            },
                      child: const Text('Verificar y reintentar'),
                    ),
                  ],
                ),
              ),
            ),
          if (data == null)
            if (controller.busy)
              const LinearProgressIndicator()
            else
              const Text(
                'Abre Eventos o pulsa Actualizar para cargar la información.',
              )
          else ...[
            for (final pending in data.pending)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Creación pendiente: ${pending.command.name}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        'Mínimo: ${pending.command.minimumPeople} · Costo fijo: ${_money(pending.command.fixedCostMinor)} · Productos: ${_money(pending.quote.productsCostMinor)}',
                      ),
                      if (pending.command.sourceAccountId != null)
                        Text(
                          'Cuenta: ${data.accounts.where((a) => a.id == pending.command.sourceAccountId).firstOrNull?.label ?? 'Cuenta no disponible'}',
                        ),
                      for (final p in pending.command.products)
                        Text(
                          '${p.quantity} × ${data.inventory.products.where((i) => i.id == p.productId).firstOrNull?.name ?? p.productId}',
                        ),
                      Text(
                        'PU: ${_money(pending.quote.unitCostMinor)} · PVP: ${_money(pending.command.pvpMinor)}',
                      ),
                      const Text(
                        'Reintentar recupera la misma creación sin repetir descuentos. Descartar libera el formulario si no se registró.',
                      ),
                      Wrap(
                        spacing: 12,
                        children: [
                          FilledButton(
                            onPressed: controller.busy
                                ? null
                                : () async {
                                    final ok = await controller.retry(
                                      pending.command.commandId,
                                    );
                                    if (ok && mounted) _resetForm();
                                  },
                            child: const Text('Reintentar creación'),
                          ),
                          TextButton(
                            onPressed: controller.busy
                                ? null
                                : () => controller.discard(
                                    pending.command.commandId,
                                  ),
                            child: const Text('Descartar solicitud'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nuevo evento',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('event-name'),
                        controller: _name,
                        enabled: !locked,
                        maxLength: 160,
                        decoration: const InputDecoration(
                          labelText: 'Nombre',
                          hintText: 'Liga Magic',
                        ),
                        validator: (v) => (v?.trim().isEmpty ?? true)
                            ? 'Escribe el nombre.'
                            : null,
                      ),
                      const Text('Categoría: Evento'),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          SizedBox(
                            width: 240,
                            child: TextFormField(
                              key: const Key('event-minimum'),
                              controller: _minimum,
                              enabled: !locked,
                              decoration: const InputDecoration(
                                labelText: 'Mínimo de personas',
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (_) => _changed(),
                              validator: (v) {
                                final n = BigInt.tryParse(v ?? '');
                                if (n == null ||
                                    n < BigInt.zero ||
                                    n > Money.maxMinorUnits) {
                                  return 'Usa un entero desde 0.';
                                }
                                if ((_products.isNotEmpty ||
                                        (_amountOrZero(_fixed.text) > 0)) &&
                                    n == BigInt.zero) {
                                  return 'Con costos o productos, mínimo 1.';
                                }
                                return null;
                              },
                            ),
                          ),
                          SizedBox(
                            width: 240,
                            child: TextFormField(
                              key: const Key('event-fixed-cost'),
                              controller: _fixed,
                              enabled: !locked,
                              decoration: const InputDecoration(
                                labelText: 'Costo fijo',
                              ),
                              onChanged: (_) => _changed(),
                              validator: (v) =>
                                  inventoryAmountError(v, widget.profile),
                            ),
                          ),
                          SizedBox(
                            width: 240,
                            child: DropdownButtonFormField<String>(
                              key: ValueKey('event-account-$_account'),
                              initialValue: _account,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Pagar costo fijo desde',
                              ),
                              items: [
                                for (final a in data.accounts)
                                  DropdownMenuItem(
                                    value: a.id,
                                    child: Text(
                                      '${a.label} · ${_money(a.balanceMinor)}',
                                    ),
                                  ),
                              ],
                              onChanged: locked
                                  ? null
                                  : (v) {
                                      _account = v;
                                      _changed();
                                    },
                              validator: (v) =>
                                  _amountOrZero(_fixed.text) > 0 && v == null
                                  ? 'Selecciona Caja o Nequi.'
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Productos utilizados (opcional)',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Text(
                        'Se descontarán al crear el evento, al costo de inventario. Puedes agregar varios productos.',
                      ),
                      const SizedBox(height: 12),
                      for (var index = 0; index < _products.length; index++)
                        _productEditor(index, products, stock, locked),
                      OutlinedButton.icon(
                        key: const Key('event-add-product'),
                        onPressed: locked || _products.length >= 100
                            ? null
                            : () {
                                setState(() => _products.add(_ProductRow()));
                                _changed();
                              },
                        icon: const Icon(Icons.add),
                        label: const Text('Agregar producto'),
                      ),
                      const SizedBox(height: 20),
                      if (_quoteError != null)
                        Text(
                          _quoteError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      if (_quote != null) ...[
                        Text(
                          'Productos: ${_money(_quote!.productsCostMinor)} · Costo total: ${_money(_quote!.totalCostMinor)}',
                        ),
                        Text(
                          _amountOrZero(_fixed.text) == 0 && _products.isEmpty
                              ? 'PU: ${_money(0)} · Sin costos para calcular una sugerencia.'
                              : 'PU por inscripción: ${_money(_quote!.unitCostMinor)}',
                        ),
                      ] else if (_products.isEmpty &&
                          _amountOrZero(_fixed.text) == 0)
                        Text(
                          'PU: ${_money(0)} · Sin costos para calcular una sugerencia.',
                        ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: 280,
                        child: TextFormField(
                          key: const Key('event-pvp'),
                          controller: _pvp,
                          enabled: !locked,
                          decoration: const InputDecoration(
                            labelText: 'PVP / inscripción',
                            helperText: 'Precio que cobrarás en Ventas',
                          ),
                          onChanged: (_) => _changed(),
                          validator: (v) {
                            final error = inventoryAmountError(
                              v,
                              widget.profile,
                            );
                            if (error != null) return error;
                            return _amount(v!) <= 0
                                ? 'El PVP debe ser mayor que cero.'
                                : null;
                          },
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Crear registra los costos y descuenta el dinero y los productos una sola vez. El mínimo se usa para el PU; no limita las inscripciones.',
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        key: const Key('event-create'),
                        onPressed: locked ? null : _create,
                        icon: const Icon(Icons.event_available),
                        label: const Text('Crear evento'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Eventos creados',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (data.events.isEmpty) const Text('Aún no has creado eventos.'),
            for (final e in data.events)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${e.name}${e.isActive ? '' : ' · Desactivado'}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          'PVP: ${_money(e.pvpMinor)} · PU: ${_money(e.unitCostMinor)} · Mínimo: ${e.minimumPeople}',
                        ),
                        Text(
                          'Costo fijo: ${_money(e.fixedCostMinor)}${e.sourceAccountName == null ? '' : ' · ${e.sourceAccountName}'} · Productos: ${_money(e.productsCostMinor)} · Total: ${_money(e.totalCostMinor)}',
                        ),
                        for (final p in e.products) Text(p),
                        if (e.isActive)
                          TextButton(
                            onPressed: controller.busy
                                ? null
                                : () => _deactivate(e),
                            child: const Text('Desactivar'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ],
      );
    },
  );
  int _amountOrZero(String text) {
    try {
      return _amount(text);
    } catch (_) {
      return 0;
    }
  }

  Widget _productEditor(
    int index,
    List<CatalogProduct> products,
    Map<String, int> stock,
    bool locked,
  ) {
    final row = _products[index];
    return Padding(
      key: ObjectKey(row),
      padding: const EdgeInsets.only(bottom: 12),
      child: LayoutBuilder(
        builder: (context, c) => Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: c.maxWidth < 400 ? c.maxWidth : 360,
              child: DropdownButtonFormField<String>(
                key: ValueKey('event-product-$index-${row.id}'),
                initialValue: row.id,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Producto del catálogo',
                ),
                items: [
                  if (row.id != null && !products.any((p) => p.id == row.id))
                    DropdownMenuItem(
                      value: row.id,
                      enabled: false,
                      child: const Text('Producto no disponible'),
                    ),
                  for (final p in products.where(
                    (p) =>
                        p.id == row.id || !_products.any((r) => r.id == p.id),
                  ))
                    DropdownMenuItem(
                      value: p.id,
                      child: Text(
                        '${p.name} · ${stock[p.id]} disponibles',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: locked
                    ? null
                    : (v) {
                        row.id = v;
                        _changed();
                      },
                validator: (v) => v == null || !products.any((p) => p.id == v)
                    ? 'Selecciona un producto disponible.'
                    : null,
              ),
            ),
            SizedBox(
              width: 130,
              child: TextFormField(
                key: ValueKey('event-quantity-$index'),
                controller: row.quantity,
                enabled: !locked,
                decoration: const InputDecoration(labelText: 'Cantidad'),
                keyboardType: TextInputType.number,
                onChanged: (_) => _changed(),
                validator: (v) {
                  final n = BigInt.tryParse(v ?? '');
                  return n == null ||
                          n <= BigInt.zero ||
                          n > Money.maxMinorUnits
                      ? 'Entero positivo.'
                      : null;
                },
              ),
            ),
            IconButton(
              tooltip: 'Quitar producto',
              onPressed: locked
                  ? null
                  : () {
                      setState(() => _products.removeAt(index));
                      row.quantity.dispose();
                      _changed();
                    },
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deactivate(EventRecord event) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Desactivar ${event.name}'),
        content: const Text(
          'Dejará de aparecer en Catálogo y Ventas. Sus costos, productos utilizados e inscripciones anteriores se conservarán. No se devuelve dinero ni inventario.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Desactivar'),
          ),
        ],
      ),
    );
    if (accepted == true) await widget.controller.deactivate(event.productId);
  }
}

class _ProductRow {
  String? id;
  final quantity = TextEditingController(text: '1');
}
