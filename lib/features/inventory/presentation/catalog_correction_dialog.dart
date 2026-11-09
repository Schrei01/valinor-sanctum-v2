import 'package:flutter/material.dart';
import '../../../core/domain/money.dart';
import '../../../core/presentation/grouped_number_formatter.dart';
import '../../events/domain/events_store.dart';
import '../../workspace/domain/business_profile.dart';
import '../application/inventory_controller.dart';
import '../domain/catalog_corrections_store.dart';
import '../domain/inventory_store.dart';
import 'inventory_widgets.dart';

class CatalogCorrectionDialog extends StatefulWidget {
  const CatalogCorrectionDialog({
    super.key,
    required this.controller,
    required this.store,
    required this.profile,
    required this.kind,
  });
  final InventoryController controller;
  final CatalogCorrectionsStore store;
  final BusinessProfile profile;
  final CatalogCorrectionKind kind;
  @override
  State<CatalogCorrectionDialog> createState() =>
      _CatalogCorrectionDialogState();
}

class _EventPart {
  _EventPart(this.productId, String units)
    : quantity = TextEditingController(text: units);
  String? productId;
  final TextEditingController quantity;
}

class _CatalogCorrectionDialogState extends State<CatalogCorrectionDialog> {
  final _name = TextEditingController(),
      _price = TextEditingController(),
      _minimum = TextEditingController(),
      _fixed = TextEditingController();
  final _parts = <_EventPart>[];
  final _retiredParts = <_EventPart>[];
  CatalogProduct? _product;
  CatalogEventState? _event;
  String? _source, _error;
  PreparedCatalogCorrection? _pending;
  CatalogCorrectionCommand? _unconfirmedCommand;
  bool _busy = true;
  bool _loaded = false;
  bool get _isEvent => widget.kind == CatalogCorrectionKind.event;
  bool get _locked =>
      _busy || !_loaded || _pending != null || _unconfirmedCommand != null;
  String _display(int n) => GroupedNumberFormatter.format(
    Money.fromMinorUnits(
      n,
      currency: widget.profile.currencyCode,
      scale: widget.profile.moneyScale,
    ).formatEsCo(),
  );
  int? _amount(TextEditingController c) {
    try {
      return Money.parseEsCo(
        c.text,
        currency: widget.profile.currencyCode,
        scale: widget.profile.moneyScale,
      ).minorUnits;
    } catch (_) {
      return null;
    }
  }

  List<CatalogProduct> get _products =>
      (widget.controller.snapshot?.products ?? <CatalogProduct>[]).where((p) {
        if (_isEvent) return p.isEvent;
        if (p.isUnlimited) return false;
        final category = widget.controller.snapshot!.categories
            .where((c) => c.id == p.categoryId)
            .firstOrNull
            ?.name
            .trim()
            .toLowerCase()
            .replaceAll('í', 'i');
        return [
          'comestible',
          'comestibles',
          'articulo',
          'articulos',
        ].contains(category);
      }).toList();
  List<CatalogProduct> get _physical =>
      (widget.controller.snapshot?.products ?? <CatalogProduct>[])
          .where((p) => !p.isUnlimited)
          .toList();
  @override
  void initState() {
    super.initState();
    _recover();
  }

  Future<void> _recover() async {
    try {
      final requests = await widget.store.pendingCorrections();
      final request = requests
          .where((r) => r.command.kind == widget.kind)
          .firstOrNull;
      if (!mounted) return;
      if (request != null) {
        _pending = request;
        _product = widget.controller.snapshot?.products
            .where((p) => p.id == request.command.productId)
            .firstOrNull;
        _name.text = request.command.name ?? request.command.expectedName;
        _price.text = _display(
          request.command.priceMinor ?? request.command.expectedPriceMinor,
        );
        if (_isEvent) {
          _event = await widget.store.loadEvent(request.command.productId);
          _minimum.text = '${request.command.minimumPeople}';
          _fixed.text = _display(request.command.fixedCostMinor!);
          _source = request.command.sourceAccountId;
          for (final p in request.command.products) {
            _parts.add(_EventPart(p.productId, '${p.quantity}'));
          }
        }
      }
      _loaded = true;
    } catch (_) {
      _error =
          'No se pudieron recuperar las correcciones pendientes. Cierra y vuelve a abrir el menú.';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _select(CatalogProduct p) async {
    if (_locked) return;
    setState(() {
      _product = p;
      _event = null;
      _name.text = p.name;
      _price.text = _display(p.listPriceMinor);
      _error = null;
      _busy = _isEvent;
    });
    if (!_isEvent) return;
    try {
      final state = await widget.store.loadEvent(p.id);
      if (!mounted) return;
      _retiredParts.addAll(_parts);
      _parts.clear();
      setState(() {
        _event = state;
        _minimum.text = GroupedNumberFormatter.format('${state.minimumPeople}');
        _fixed.text = _display(state.fixedCostMinor);
        _source = state.sourceAccountId;
        for (final part in state.components) {
          _parts.add(
            _EventPart(
              part['product_id'] as String,
              GroupedNumberFormatter.format('${part['quantity']}'),
            ),
          );
        }
      });
    } on CatalogCorrectionValidationException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'No se pudo consultar el evento. Intenta de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _price, _minimum, _fixed]) {
      c.dispose();
    }
    for (final p in [..._parts, ..._retiredParts]) {
      p.quantity.dispose();
    }
    super.dispose();
  }

  Future<void> _prepare() async {
    if (_busy || !_loaded || _pending != null || _product == null) return;
    final selected = _product!;
    final products = <EventProductInput>[];
    if (_isEvent) {
      for (final part in _parts) {
        final qty = int.tryParse(part.quantity.text.replaceAll('.', ''));
        if (part.productId == null || qty == null || qty <= 0) {
          setState(
            () =>
                _error = 'Selecciona los artículos y sus cantidades positivas.',
          );
          return;
        }
        products.add(EventProductInput(part.productId!, qty));
      }
    }
    final command =
        _unconfirmedCommand ??
        CatalogCorrectionCommand(
          commandId: InventoryIds.next(),
          productId: selected.id,
          kind: widget.kind,
          expectedName: selected.name,
          expectedPriceMinor: selected.listPriceMinor,
          occurredAtUtc: DateTime.now().toUtc(),
          name: widget.kind == CatalogCorrectionKind.price ? null : _name.text,
          priceMinor: widget.kind == CatalogCorrectionKind.name
              ? null
              : _amount(_price),
          expectedRevision: _event?.revision,
          minimumPeople: _isEvent
              ? int.tryParse(_minimum.text.replaceAll('.', ''))
              : null,
          fixedCostMinor: _isEvent ? _amount(_fixed) : null,
          sourceAccountId: _source,
          products: products,
        );
    _unconfirmedCommand = command;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final pending = await widget.store.prepareCorrection(command);
      if (mounted) setState(() => _pending = pending);
    } on CatalogCorrectionValidationException catch (e) {
      if (mounted) {
        setState(() {
          _unconfirmedCommand = null;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'No se pudo confirmar la preparación. Cierra y vuelve a abrir el menú para recuperar la solicitud.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    if (_busy || _pending == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.store.confirmCorrection(_pending!.command.commandId);
      if (mounted) Navigator.pop(context, true);
    } on CatalogCorrectionValidationException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'No se pudo confirmar el resultado. Reintenta la misma corrección para evitar duplicados.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _discard() async {
    if (_busy || _pending == null) return;
    setState(() => _busy = true);
    try {
      await widget.store.discardCorrection(_pending!.command.commandId);
      await widget.controller.load();
      if (mounted) {
        setState(() {
          _pending = null;
          _unconfirmedCommand = null;
          _product = null;
          _event = null;
          _error = null;
        });
      }
    } on CatalogCorrectionValidationException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'No se pudo descartar. Reintenta para recuperar el resultado.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _moneyField(
    String label,
    TextEditingController controller,
    String key,
  ) => TextField(
    key: Key(key),
    controller: controller,
    enabled: !_locked,
    keyboardType: TextInputType.number,
    inputFormatters: [const GroupedNumberFormatter()],
    decoration: InputDecoration(labelText: label),
  );
  List<Map<String, dynamic>> _stockSummary(
    PreparedCatalogCorrection correction,
  ) {
    final grouped = <String, Map<String, dynamic>>{};
    for (final change in correction.plan['stockChanges'] as List) {
      final key = '${change['productId']}:${change['isAddition']}';
      final row = grouped.putIfAbsent(
        key,
        () => {
          'name': change['name'],
          'isAddition': change['isAddition'],
          'quantity': 0,
        },
      );
      row['quantity'] = (row['quantity'] as int) + (change['quantity'] as int);
    }
    return grouped.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pending;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(
          _isEvent
              ? 'Corregir evento'
              : widget.kind == CatalogCorrectionKind.name
              ? 'Corregir nombre'
              : 'Corregir PVP',
        ),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_busy) const LinearProgressIndicator(),
                if (pending == null) ...[
                  Autocomplete<CatalogProduct>(
                    displayStringForOption: (p) => p.name,
                    optionsBuilder: (t) => _products.where(
                      (p) =>
                          p.name.toLowerCase().contains(
                            t.text.trim().toLowerCase(),
                          ) ||
                          (p.sku?.toLowerCase().contains(
                                t.text.trim().toLowerCase(),
                              ) ??
                              false),
                    ),
                    onSelected: _select,
                    fieldViewBuilder: (context, text, focus, submit) =>
                        TextField(
                          key: const Key('catalog-correction-product'),
                          controller: text,
                          focusNode: focus,
                          enabled: !_locked,
                          decoration: InputDecoration(
                            labelText: _isEvent ? 'Evento' : 'Producto',
                            hintText: 'Buscar por nombre o SKU',
                          ),
                          onChanged: (value) {
                            if (value != _product?.name) {
                              setState(() {
                                _product = null;
                                _event = null;
                              });
                            }
                          },
                          onSubmitted: (_) => submit(),
                        ),
                  ),
                  if (_product != null) ...[
                    const SizedBox(height: 16),
                    if (widget.kind != CatalogCorrectionKind.price)
                      TextField(
                        key: const Key('catalog-correction-name'),
                        controller: _name,
                        enabled: !_locked,
                        maxLength: 120,
                        decoration: const InputDecoration(labelText: 'Nombre'),
                      ),
                    if (widget.kind != CatalogCorrectionKind.name) ...[
                      Text(
                        'PVP anterior: ${inventoryMoney(_product!.listPriceMinor, widget.profile)}',
                      ),
                      const SizedBox(height: 8),
                      _moneyField(
                        'PVP (${widget.profile.currencyCode})',
                        _price,
                        'catalog-correction-price',
                      ),
                    ],
                    if (_isEvent && _event != null) ...[
                      const SizedBox(height: 16),
                      TextField(
                        key: const Key('catalog-correction-minimum'),
                        controller: _minimum,
                        enabled: !_locked,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          const GroupedNumberFormatter(integerOnly: true),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Mínimo de personas',
                        ),
                      ),
                      const SizedBox(height: 16),
                      _moneyField(
                        'Costo fijo (${widget.profile.currencyCode})',
                        _fixed,
                        'catalog-correction-fixed',
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        key: const Key('catalog-correction-source'),
                        initialValue:
                            _event!.accounts.any((a) => a.id == _source)
                            ? _source
                            : null,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Costo fijo adicional desde',
                        ),
                        items: [
                          for (final a in _event!.accounts)
                            DropdownMenuItem(value: a.id, child: Text(a.label)),
                        ],
                        onChanged: _locked
                            ? null
                            : (v) => setState(() => _source = v),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Si aumenta el costo fijo, se cobra el adicional. Las rebajas no devuelven dinero. Los artículos retirados sí regresan al inventario.',
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Artículos del evento',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      for (final part in _parts) ...[
                        const SizedBox(height: 10),
                        LayoutBuilder(
                          builder: (context, c) {
                            final product = DropdownButtonFormField<String>(
                              initialValue: part.productId,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Artículo',
                              ),
                              items: [
                                for (final p in _physical)
                                  DropdownMenuItem(
                                    value: p.id,
                                    child: Text(
                                      p.name,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: _locked
                                  ? null
                                  : (v) => setState(() => part.productId = v),
                            );
                            final quantity = TextField(
                              controller: part.quantity,
                              enabled: !_locked,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                const GroupedNumberFormatter(integerOnly: true),
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Unidades',
                              ),
                            );
                            final remove = IconButton(
                              tooltip: 'Quitar artículo',
                              onPressed: _locked
                                  ? null
                                  : () => setState(() {
                                      _parts.remove(part);
                                      _retiredParts.add(part);
                                    }),
                              icon: const Icon(Icons.delete_outline),
                            );
                            return c.maxWidth < 420
                                ? Column(
                                    children: [
                                      product,
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(child: quantity),
                                          remove,
                                        ],
                                      ),
                                    ],
                                  )
                                : Row(
                                    children: [
                                      Expanded(child: product),
                                      const SizedBox(width: 10),
                                      SizedBox(width: 90, child: quantity),
                                      remove,
                                    ],
                                  );
                          },
                        ),
                      ],
                      TextButton.icon(
                        key: const Key('catalog-correction-add-part'),
                        onPressed: _locked
                            ? null
                            : () => setState(
                                () => _parts.add(_EventPart(null, '1')),
                              ),
                        icon: const Icon(Icons.add),
                        label: const Text('Agregar artículo'),
                      ),
                    ],
                  ],
                ] else ...[
                  Text(
                    'Ítem: ${pending.command.expectedName}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  if (pending.command.kind != CatalogCorrectionKind.price)
                    Text('Nombre: ${pending.plan['after']['name']}'),
                  Text(
                    'PVP: ${inventoryMoney(pending.plan['after']['priceMinor'] as int, widget.profile)}',
                  ),
                  if (_isEvent) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Costo por persona: ${inventoryMoney(pending.plan['after']['unitCostMinor'] as int, widget.profile)}',
                    ),
                    Text(
                      'Costo fijo adicional a pagar: ${inventoryMoney(pending.plan['after']['additionalFixedCost'] as int, widget.profile)}',
                    ),
                    if ((pending.plan['after']['additionalFixedCost'] as int) >
                        0)
                      Text(
                        'Pagar desde: ${pending.plan['after']['sourceAccountName']}',
                      ),
                    Text(
                      'Costo fijo pagado acumulado: ${inventoryMoney(pending.plan['after']['paidFixedCostMinor'] as int, widget.profile)}',
                    ),
                    for (final change in _stockSummary(pending))
                      Text(
                        '${change['isAddition'] == true ? 'Devolver' : 'Descontar'} ${GroupedNumberFormatter.format('${change['quantity']}')} × ${change['name']}',
                      ),
                    const SizedBox(height: 8),
                    const Text(
                      'No se devolverá dinero por las reducciones del costo fijo.',
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Text(
                    'Las ventas y los movimientos anteriores conservan sus valores originales.',
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  InventoryNotice(
                    key: const Key('catalog-correction-error'),
                    text: _error!,
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: const Text('Cerrar'),
          ),
          if (pending != null)
            TextButton(
              onPressed: _busy ? null : _discard,
              child: const Text('Descartar solicitud'),
            ),
          FilledButton(
            key: const Key('catalog-correction-submit'),
            onPressed:
                _busy || !_loaded || (_product == null && pending == null)
                ? null
                : pending == null
                ? _prepare
                : _confirm,
            child: Text(
              pending == null ? 'Revisar cambios' : 'Confirmar corrección',
            ),
          ),
        ],
      ),
    );
  }
}
