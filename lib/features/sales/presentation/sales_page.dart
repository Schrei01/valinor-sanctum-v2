import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/domain/money.dart';
import '../../inventory/application/inventory_controller.dart';
import '../../inventory/domain/inventory_store.dart';
import '../../inventory/presentation/inventory_widgets.dart';
import '../../workspace/domain/business_profile.dart';
import '../application/sales_controller.dart';
import '../domain/sales_store.dart';

class SalesPage extends StatefulWidget {
  const SalesPage({super.key, required this.controller, required this.profile});
  final SalesController controller;
  final BusinessProfile profile;
  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  final _form = GlobalKey<FormState>();
  final _label = TextEditingController();
  final _customer = TextEditingController();
  final _due = TextEditingController();
  final _lines = <_SaleLineEditor>[];
  String? _draftId;
  int _revision = 0;
  int _formVersion = 0;
  int _historyPage = 0;
  int _accountsPage = 0;
  bool _dirty = false;
  final _unlockRevision = <String, int>{};

  @override
  void dispose() {
    _label.dispose();
    _customer.dispose();
    _due.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  void _edit(SaleDraft? draft) {
    _draftId = draft?.id ?? InventoryIds.next();
    _revision = draft?.revision ?? 0;
    _label.text = draft?.label ?? '';
    _customer.text = draft?.customerName ?? '';
    _due.text = widget.controller.pendingFor(_draftId!)?.dueDate ?? '';
    for (final line in _lines) {
      line.dispose();
    }
    _lines
      ..clear()
      ..addAll([
        if (draft != null)
          for (final line in draft.lines)
            _SaleLineEditor(
              productId: line.productId,
              quantity: '${line.quantity}',
              price: _priceText(line.unitPriceMinor),
            ),
      ]);
    if (_lines.isEmpty) _lines.add(_SaleLineEditor());
    _dirty = false;
    _formVersion++;
  }

  String _priceText(int minor) => Money.fromMinorUnits(
    minor,
    currency: widget.profile.currencyCode,
    scale: widget.profile.moneyScale,
  ).formatEsCo();

  Future<void> _select(SaleDraft? draft) async {
    if (widget.controller.busy) return;
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Hay cambios sin guardar'),
          content: const Text(
            'Guarda la cuenta para conservar estos cambios o descártalos antes de cambiar de cuenta.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Volver'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Descartar cambios'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    setState(() => _edit(draft));
  }

  void _changed() => setState(() => _dirty = true);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final data = controller.snapshot;
      if (data != null && _draftId == null) {
        final recovered = data.pendingConfirmations.firstOrNull;
        _edit(
          data.drafts
                  .where((item) => item.id == recovered?.draftId)
                  .firstOrNull ??
              data.drafts.where((item) => item.status == 'open').firstOrNull,
        );
      }
      final selected = data?.drafts
          .where((item) => item.id == _draftId)
          .firstOrNull;
      final unlockRevision = _unlockRevision[_draftId];
      if (selected != null &&
          unlockRevision != null &&
          selected.status == 'open' &&
          selected.revision > unlockRevision &&
          controller.loadError == null &&
          controller.pendingFor(selected.id) == null) {
        _edit(selected);
        _unlockRevision.remove(selected.id);
      }
      final awaitingUnlockedRevision = _unlockRevision.containsKey(_draftId);
      final pending = _draftId == null
          ? null
          : controller.pendingFor(_draftId!);
      final delivered =
          data?.sales.any((item) => item.draftId == _draftId) ?? false;
      final locked =
          controller.busy ||
          awaitingUnlockedRevision ||
          pending != null ||
          delivered ||
          (selected != null && selected.status != 'open');
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
            if (!locked) _save();
          },
        },
        child: FocusTraversalGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InventoryPageHeading(
                title: 'Ventas y cuentas abiertas',
                subtitle:
                    'Guarda una cuenta mientras la preparas. Confirmar la entrega a crédito descuenta mercancía y crea una cuenta por cobrar; el cobro se registrará en una próxima entrega.',
                busy: controller.busy,
                onRefresh: controller.load,
              ),
              if (controller.loadError != null)
                InventoryNotice(
                  text: controller.loadError!,
                  onRetry: controller.busy ? null : controller.load,
                ),
              if (data == null)
                if (controller.loading)
                  const Center(child: CircularProgressIndicator())
                else
                  const Text('La información de ventas no está disponible.')
              else ...[
                if (controller.operationError != null)
                  InventoryNotice(text: controller.operationError!),
                if (controller.operationNotice != null &&
                    !awaitingUnlockedRevision)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Text(
                      controller.operationNotice!,
                      key: const Key('sale-notice'),
                      style: const TextStyle(
                        color: Color(0xFF183D35),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                _accounts(data),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            delivered
                                ? 'Cuenta entregada'
                                : _revision == 0
                                ? 'Nueva cuenta'
                                : 'Cuenta guardada',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Una cuenta sin confirmar no reserva ni descuenta stock. Pulsa Guardar cuenta para recuperarla al volver a abrir.',
                          ),
                          if (delivered)
                            const Padding(
                              padding: EdgeInsets.only(top: 16),
                              child: Text(
                                'Esta cuenta ya tiene una entrega confirmada. Consulta el historial o abre una nueva cuenta; sus datos no se pueden editar.',
                              ),
                            ),
                          if (awaitingUnlockedRevision)
                            const Padding(
                              padding: EdgeInsets.only(top: 16),
                              child: Text(
                                'La cuenta permanecerá bloqueada hasta recuperar su revisión actual. Pulsa Actualizar antes de editar.',
                              ),
                            ),
                          if (_dirty)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                'Cambios sin guardar',
                                key: Key('sale-dirty'),
                              ),
                            ),
                          if (pending != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Text(
                                pending.status == 'rejected'
                                    ? 'La entrega fue rechazada sin registrar una venta. Desbloquea la cuenta para corregirla.'
                                    : 'Hay una confirmación preparada. Los datos están bloqueados para conservar la misma solicitud al reintentar, incluso después de cerrar.',
                                key: const Key('sale-pending'),
                              ),
                            ),
                          const SizedBox(height: 24),
                          TextFormField(
                            key: const Key('sale-label'),
                            controller: _label,
                            enabled: !locked,
                            maxLength: 120,
                            decoration: const InputDecoration(
                              labelText: 'Nombre de la cuenta',
                              hintText: 'Mesa o referencia',
                            ),
                            validator: inventoryNameError,
                            onChanged: (_) => _changed(),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            key: const Key('sale-customer'),
                            controller: _customer,
                            enabled: !locked,
                            maxLength: 120,
                            decoration: const InputDecoration(
                              labelText: 'Cliente de la cuenta por cobrar',
                            ),
                            validator: inventoryNameError,
                            onChanged: (_) => _changed(),
                          ),
                          const SizedBox(height: 20),
                          for (var index = 0; index < _lines.length; index++)
                            _lineEditor(_lines[index], index, data, locked),
                          TextButton.icon(
                            key: const Key('sale-add-line'),
                            onPressed: locked || _lines.length >= 100
                                ? null
                                : () => setState(() {
                                    _lines.add(_SaleLineEditor());
                                    _dirty = true;
                                  }),
                            icon: const Icon(Icons.add),
                            label: const Text('Añadir producto'),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _totalLabel(),
                            key: const Key('sale-total'),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 20),
                          OutlinedButton.icon(
                            key: const Key('save-sale-draft'),
                            onPressed: locked ? null : _save,
                            icon: const Icon(Icons.save_outlined),
                            label: Text(
                              controller.saving
                                  ? 'Guardando…'
                                  : 'Guardar cuenta',
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Atajo: Ctrl+S. Solo las cuentas guardadas se recuperan al reabrir.',
                          ),
                          const Divider(height: 40),
                          TextFormField(
                            key: ValueKey('sale-due-$_formVersion'),
                            controller: _due,
                            enabled: !locked,
                            maxLength: 10,
                            decoration: const InputDecoration(
                              labelText: 'Vencimiento de la venta a crédito',
                              hintText: 'AAAA-MM-DD',
                              helperText:
                                  'Se fija al confirmar · entrega hoy en Bogotá',
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Al confirmar, el total quedará pendiente de cobro. No se registra entrada de dinero.',
                          ),
                          const SizedBox(height: 20),
                          if (pending?.status == 'rejected')
                            FilledButton.icon(
                              key: const Key('unlock-sale'),
                              onPressed: controller.busy
                                  ? null
                                  : awaitingUnlockedRevision
                                  ? controller.load
                                  : _unlock,
                              icon: const Icon(Icons.edit_outlined),
                              label: Text(
                                awaitingUnlockedRevision
                                    ? 'Actualizar cuenta para editar'
                                    : 'Corregir cuenta rechazada',
                              ),
                            )
                          else
                            FilledButton.icon(
                              key: const Key('confirm-sale'),
                              onPressed:
                                  controller.busy || (locked && pending == null)
                                  ? null
                                  : _confirm,
                              icon: Icon(
                                controller.confirming
                                    ? Icons.hourglass_empty
                                    : pending != null
                                    ? Icons.refresh
                                    : Icons.local_shipping_outlined,
                              ),
                              label: Text(
                                controller.confirming
                                    ? 'Confirmando entrega…'
                                    : pending != null
                                    ? 'Reintentar la misma venta'
                                    : 'Confirmar entrega a crédito',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  'Historial de ventas a crédito',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Entregas confirmadas con precios, cliente y costo histórico conservados. Los cobros todavía no están disponibles.',
                ),
                const SizedBox(height: 16),
                _history(data),
              ],
            ],
          ),
        ),
      );
    },
  );

  Widget _accounts(SalesSnapshot data) {
    final accounts = data.drafts
        .where((item) => item.status != 'confirmed')
        .toList();
    const pageSize = 5;
    final page = accounts.isEmpty
        ? 0
        : _accountsPage.clamp(0, (accounts.length - 1) ~/ pageSize);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 24,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Cuentas guardadas (${accounts.length})',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            OutlinedButton.icon(
              key: const Key('new-sale-draft'),
              onPressed: widget.controller.busy ? null : () => _select(null),
              icon: const Icon(Icons.add),
              label: const Text('Nueva cuenta'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (accounts.isEmpty)
          const Text('Aún no hay cuentas abiertas guardadas.'),
        for (final draft in accounts.skip(page * pageSize).take(pageSize))
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              key: ValueKey('open-sale-${draft.id}'),
              selected: draft.id == _draftId,
              title: Text(draft.label),
              subtitle: Text(
                '${draft.customerName} · ${widget.controller.pendingFor(draft.id) == null ? 'Cuenta abierta · sin entrega' : 'Confirmación pendiente'}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: widget.controller.busy || draft.id == _draftId
                  ? null
                  : () => _select(draft),
            ),
          ),
        if (accounts.length > pageSize)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('Página ${page + 1}'),
              IconButton(
                tooltip: 'Cuentas anteriores',
                onPressed: page == 0
                    ? null
                    : () => setState(() => _accountsPage = page - 1),
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: 'Cuentas siguientes',
                onPressed: (page + 1) * pageSize >= accounts.length
                    ? null
                    : () => setState(() => _accountsPage = page + 1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
      ],
    );
  }

  Widget _lineEditor(
    _SaleLineEditor line,
    int index,
    SalesSnapshot data,
    bool locked,
  ) => Container(
    key: ValueKey(line.id),
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xFFE4E7E0)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Producto ${index + 1}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              tooltip: 'Quitar producto ${index + 1}',
              onPressed: locked
                  ? null
                  : () => setState(() {
                      _lines.remove(line);
                      line.dispose();
                      _dirty = true;
                    }),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('sale-product-${line.id}'),
          initialValue: line.productId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Producto'),
          items: [
            for (final product in data.products)
              DropdownMenuItem(value: product.id, child: Text(product.name)),
            if (line.productId != null &&
                !data.products.any((item) => item.id == line.productId))
              DropdownMenuItem(
                value: line.productId,
                enabled: false,
                child: Text('Producto no disponible (${line.productId})'),
              ),
          ],
          onChanged: locked
              ? null
              : (value) => setState(() {
                  line.productId = value;
                  line.price.text = _priceText(
                    data.products
                        .firstWhere((item) => item.id == value)
                        .listPriceMinor,
                  );
                  _dirty = true;
                }),
          validator: (value) =>
              value == null ? 'Selecciona un producto.' : null,
        ),
        if (line.productId != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Stock disponible: ${data.stock.where((item) => item.productId == line.productId).firstOrNull?.quantity ?? 0} · se comprueba al confirmar',
            ),
          ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 500
                ? (constraints.maxWidth - 16) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: width,
                  child: TextFormField(
                    key: ValueKey('sale-quantity-${line.id}'),
                    controller: line.quantity,
                    enabled: !locked,
                    decoration: const InputDecoration(labelText: 'Unidades'),
                    validator: (value) {
                      if (!RegExp(r'^[0-9]+$').hasMatch(value?.trim() ?? '')) {
                        return 'Solo enteros positivos.';
                      }
                      final amount = BigInt.tryParse(value!.trim());
                      return amount == null ||
                              amount <= BigInt.zero ||
                              amount > Money.maxMinorUnits
                          ? 'Cantidad no válida.'
                          : null;
                    },
                    onChanged: (_) => _changed(),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: TextFormField(
                    key: ValueKey('sale-price-${line.id}'),
                    controller: line.price,
                    enabled: !locked,
                    decoration: InputDecoration(
                      labelText:
                          'Precio por unidad (${widget.profile.currencyCode})',
                      helperText: '${widget.profile.moneyScale} decimales',
                    ),
                    validator: (value) =>
                        inventoryAmountError(value, widget.profile),
                    onChanged: (_) => _changed(),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    ),
  );

  BigInt? _total() {
    var total = BigInt.zero;
    for (final line in _lines) {
      final quantity = BigInt.tryParse(line.quantity.text.trim());
      if (quantity == null ||
          quantity <= BigInt.zero ||
          inventoryAmountError(line.price.text, widget.profile) != null) {
        return null;
      }
      total +=
          quantity *
          Money.parseEsCo(
            line.price.text,
            currency: widget.profile.currencyCode,
            scale: widget.profile.moneyScale,
          ).asBigInt;
    }
    return total;
  }

  String _totalLabel() {
    final total = _total();
    if (total == null) return 'Total: completa las cantidades y precios';
    if (total > Money.maxMinorUnits) return 'Total: supera el límite permitido';
    return 'Total a crédito: ${inventoryMoney(total.toInt(), widget.profile)}';
  }

  Future<bool> _save() async {
    if (!_form.currentState!.validate()) return false;
    final total = _total();
    if (total == null || total > Money.maxMinorUnits) return false;
    final saved = await widget.controller.saveDraft(
      SaveSaleDraft(
        id: _draftId!,
        label: _label.text.trim(),
        customerName: _customer.text.trim(),
        expectedRevision: _revision,
        lines: [
          for (final line in _lines)
            SaleDraftLine(
              productId: line.productId!,
              quantity: BigInt.parse(line.quantity.text.trim()).toInt(),
              unitPriceMinor: Money.parseEsCo(
                line.price.text,
                currency: widget.profile.currencyCode,
                scale: widget.profile.moneyScale,
              ).minorUnits,
            ),
        ],
      ),
    );
    if (!mounted || saved == null) return false;
    setState(() {
      _revision = saved.revision;
      _dirty = false;
    });
    return true;
  }

  Future<void> _unlock() async {
    final draftId = _draftId!;
    setState(() => _unlockRevision[draftId] = _revision);
    final unlocked = await widget.controller.unlockRejected(draftId);
    if (!mounted) return;
    setState(() {
      if (!unlocked) _unlockRevision.remove(draftId);
    });
  }

  Future<void> _confirm() async {
    final controller = widget.controller;
    if (controller.pendingFor(_draftId!) != null) {
      final success = await controller.retry(_draftId!);
      if (mounted && success) {
        setState(() {
          _edit(null);
          _historyPage = 0;
        });
      }
      return;
    }
    if (!_form.currentState!.validate()) return;
    final total = _total();
    final due = _due.text.trim();
    if (total == null || total <= BigInt.zero || total > Money.maxMinorUnits) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Añade productos con un total positivo dentro del límite.',
          ),
        ),
      );
      return;
    }
    if (!InventoryController.isValidIsoDate(due)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Escribe un vencimiento real: AAAA-MM-DD.'),
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar entrega a crédito'),
        content: Text(
          'Cliente: ${_customer.text.trim()}\nTotal pendiente de cobro: ${inventoryMoney(total.toInt(), widget.profile)}\n\nEsta entrega descuenta stock y conserva precios y costo histórico. No registra un cobro.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            key: const Key('accept-credit-sale'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar entrega'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    if ((_dirty || _revision == 0) && !await _save()) return;
    final success = await controller.confirm(
      draftId: _draftId!,
      expectedRevision: _revision,
      dueDate: due,
    );
    if (mounted && success) {
      setState(() {
        _edit(null);
        _historyPage = 0;
      });
    }
  }

  Widget _history(SalesSnapshot data) {
    if (data.sales.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Aún no hay entregas confirmadas.'),
        ),
      );
    }
    const pageSize = 10;
    final page = _historyPage.clamp(0, (data.sales.length - 1) ~/ pageSize);
    return Column(
      children: [
        for (final sale in data.sales.skip(page * pageSize).take(pageSize))
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${sale.label} · ${sale.customerName}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 24,
                    runSpacing: 12,
                    children: [
                      Text(
                        'Venta: ${inventoryMoney(sale.totalMinor, widget.profile)}',
                      ),
                      Text(
                        'Por cobrar: ${inventoryMoney(sale.totalMinor, widget.profile)}',
                      ),
                      Text(
                        'Costo histórico: ${inventoryMoney(sale.totalCostMinor, widget.profile)}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Entrega: ${InventoryController.isoDate(sale.soldAtUtc.subtract(const Duration(hours: 5)))} · Vence: ${sale.dueDate}',
                  ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text('Ver entrega (${sale.lines.length})'),
                    children: [
                      for (final line in sale.lines)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${line.productName} · ${line.quantity} unidades · Precio: ${inventoryMoney(line.unitPriceMinor, widget.profile)} · Total: ${inventoryMoney(line.totalMinor, widget.profile)} · Costo: ${inventoryMoney(line.totalCostMinor, widget.profile)}',
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              '${page * pageSize + 1}–${(page * pageSize + pageSize).clamp(0, data.sales.length)} de ${data.sales.length}',
            ),
            IconButton(
              tooltip: 'Ventas anteriores',
              onPressed: page == 0
                  ? null
                  : () => setState(() => _historyPage = page - 1),
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: 'Ventas siguientes',
              onPressed: (page + 1) * pageSize >= data.sales.length
                  ? null
                  : () => setState(() => _historyPage = page + 1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    );
  }
}

class _SaleLineEditor {
  _SaleLineEditor({this.productId, String quantity = '1', String price = ''})
    : quantity = TextEditingController(text: quantity),
      price = TextEditingController(text: price);
  final id = InventoryIds.next();
  String? productId;
  final TextEditingController quantity;
  final TextEditingController price;
  void dispose() {
    quantity.dispose();
    price.dispose();
  }
}
