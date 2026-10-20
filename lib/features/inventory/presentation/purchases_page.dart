import 'package:flutter/material.dart';

import '../../../core/domain/money.dart';
import '../../stock_intake/application/stock_intake_controller.dart';
import '../../stock_intake/domain/stock_intake_store.dart';
import '../../workspace/domain/business_profile.dart';
import '../application/inventory_controller.dart';
import '../domain/inventory_store.dart';
import 'inventory_widgets.dart';

class PurchasesPage extends StatefulWidget {
  const PurchasesPage({
    super.key,
    required this.controller,
    required this.profile,
  });
  final StockIntakeController controller;
  final BusinessProfile profile;
  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _sku = TextEditingController();
  final _supplier = TextEditingController();
  final _cost = TextEditingController();
  final _pvp = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _productFocus = FocusNode();
  final _supplierFocus = FocusNode();
  CatalogProduct? _existing;
  String? _supplierId;
  String? _categoryId;
  String? _paymentOptionId;
  String? _hydratedCommand;
  int _formVersion = 0;
  int _confirmedVersion = 0;
  int _historyPage = 0;

  @override
  void initState() {
    super.initState();
    _confirmedVersion = widget.controller.confirmedVersion;
    widget.controller.addListener(_changed);
    _hydratePending();
  }

  @override
  void didUpdateWidget(covariant PurchasesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _confirmedVersion = widget.controller.confirmedVersion;
      _hydratePending();
    }
  }

  void _changed() {
    if (!mounted) return;
    if (_confirmedVersion != widget.controller.confirmedVersion) {
      _confirmedVersion = widget.controller.confirmedVersion;
      _name.clear();
      _sku.clear();
      _cost.clear();
      _pvp.clear();
      _quantity.text = '1';
      _existing = null;
      _hydratedCommand = null;
      _formVersion++;
      _historyPage = 0;
    }
    _hydratePending();
    setState(() {});
  }

  void _hydratePending() {
    final pending = widget.controller.pendingIntakes.firstOrNull;
    if (pending == null || _hydratedCommand == pending.command.commandId) {
      return;
    }
    final command = pending.command;
    _hydratedCommand = command.commandId;
    _existing = command.expectedProduct;
    _name.text = command.productName;
    _sku.text = command.sku ?? '';
    _supplier.text = command.supplierName;
    _supplierId = command.supplierId;
    _categoryId = command.categoryId;
    _paymentOptionId = command.paymentOptionId;
    _quantity.text = '${command.quantity}';
    _cost.text = _amount(command.unitPurchasePriceMinor);
    _pvp.text = _amount(command.listPriceMinor);
    _formVersion++;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    for (final field in [_name, _sku, _supplier, _cost, _pvp, _quantity]) {
      field.dispose();
    }
    _productFocus.dispose();
    _supplierFocus.dispose();
    super.dispose();
  }

  String _amount(int value) => Money.fromMinorUnits(
    value,
    currency: widget.profile.currencyCode,
    scale: widget.profile.moneyScale,
  ).formatEsCo();

  IntakePaymentOption? _payment(StockIntakeSnapshot data) =>
      data.paymentOptions
          .where((item) => item.id == _paymentOptionId && item.isActive)
          .firstOrNull ??
      data.paymentOptions.where((item) => item.isActive).firstOrNull;

  BigInt? get _total {
    try {
      final quantity = BigInt.tryParse(_quantity.text.trim());
      if (quantity == null ||
          quantity <= BigInt.zero ||
          !RegExp(r'^[0-9]+$').hasMatch(_quantity.text.trim())) {
        return null;
      }
      final cost = Money.parseEsCo(
        _cost.text,
        currency: widget.profile.currencyCode,
        scale: widget.profile.moneyScale,
      );
      if (cost.minorUnits <= 0) return null;
      return cost.asBigInt * quantity;
    } on FormatException {
      return null;
    } on RangeError {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final data = controller.snapshot;
      final locked = controller.formLocked;
      return FocusTraversalGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InventoryPageHeading(
              title: 'Compras',
              subtitle:
                  'Ingresa productos al catálogo y sus cantidades. La compra se paga completa desde la cuenta elegida.',
              busy: controller.busy,
              onRefresh: controller.load,
            ),
            if (controller.loadError != null)
              InventoryNotice(
                text: controller.loadError!,
                onRetry: controller.busy ? null : controller.load,
              ),
            if (controller.operationError != null)
              InventoryNotice(text: controller.operationError!),
            if (controller.operationNotice != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Text(
                  controller.operationNotice!,
                  key: const Key('intake-notice'),
                  style: const TextStyle(
                    color: Color(0xFF183D35),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (data == null)
              if (controller.loading)
                const Center(child: CircularProgressIndicator())
              else
                const Text('Los productos y saldos no están disponibles.')
            else ...[
              for (final pending in controller.pendingIntakes)
                _pending(pending, data),
              if (controller.pendingOpening != null) _pendingOpening(data),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ingreso de productos',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Escribe un producto nuevo o elige uno existente para completar sus datos y reponerlo.',
                        ),
                        const SizedBox(height: 20),
                        _productField(data, locked),
                        if (_existing != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Reponer producto · existencias: ${data.stock.where((item) => item.productId == _existing!.id).firstOrNull?.quantity ?? 0}',
                              key: const Key('intake-existing'),
                            ),
                          ),
                        const SizedBox(height: 16),
                        _fields([
                          TextFormField(
                            key: const Key('intake-sku'),
                            controller: _sku,
                            enabled: !locked,
                            maxLength: 64,
                            decoration: const InputDecoration(
                              labelText: 'SKU (opcional)',
                            ),
                            validator: (value) =>
                                RegExp(r'[\x00-\x1f]').hasMatch(value ?? '')
                                ? 'Escribe un SKU válido.'
                                : null,
                          ),
                          DropdownButtonFormField<String>(
                            key: ValueKey('intake-category-$_formVersion'),
                            initialValue:
                                data.categories.any(
                                  (item) => item.id == _categoryId,
                                )
                                ? _categoryId
                                : null,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Categoría',
                            ),
                            items: [
                              for (final category in data.categories.where(
                                (item) =>
                                    item.isActive || item.id == _categoryId,
                              ))
                                DropdownMenuItem(
                                  value: category.id,
                                  enabled: category.isActive,
                                  child: Text(
                                    category.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: locked
                                ? null
                                : (value) =>
                                      setState(() => _categoryId = value),
                            validator: (value) =>
                                data.categories.any(
                                  (item) => item.id == value && item.isActive,
                                )
                                ? null
                                : 'Elige una categoría activa.',
                          ),
                        ]),
                        const SizedBox(height: 16),
                        _supplierField(data, locked),
                        const SizedBox(height: 16),
                        _fields([
                          TextFormField(
                            key: const Key('intake-cost'),
                            controller: _cost,
                            enabled: !locked,
                            decoration: InputDecoration(
                              labelText:
                                  'Precio de compra unitario (${widget.profile.currencyCode})',
                            ),
                            validator: (value) => _positiveAmountError(value),
                            onChanged: (_) => setState(() {}),
                          ),
                          TextFormField(
                            key: const Key('intake-pvp'),
                            controller: _pvp,
                            enabled: !locked,
                            decoration: InputDecoration(
                              labelText:
                                  'PVP unitario (${widget.profile.currencyCode})',
                            ),
                            validator: (value) =>
                                inventoryAmountError(value, widget.profile),
                            onChanged: (_) => setState(() {}),
                          ),
                          TextFormField(
                            key: const Key('intake-quantity'),
                            controller: _quantity,
                            enabled: !locked,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Cantidad',
                            ),
                            validator: _quantityError,
                            onChanged: (_) => setState(() {}),
                          ),
                        ]),
                        const SizedBox(height: 20),
                        _fields([
                          DropdownButtonFormField<String>(
                            key: ValueKey('intake-payment-$_formVersion'),
                            initialValue: _payment(data)?.id,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Pagar desde',
                            ),
                            items: [
                              for (final option in data.paymentOptions.where(
                                (item) => item.isActive,
                              ))
                                DropdownMenuItem(
                                  value: option.id,
                                  child: Text(option.label),
                                ),
                            ],
                            onChanged: locked
                                ? null
                                : (value) =>
                                      setState(() => _paymentOptionId = value),
                            validator: (value) =>
                                data.paymentOptions.any(
                                  (item) => item.id == value && item.isActive,
                                )
                                ? null
                                : 'Elige una cuenta.',
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'Saldo disponible: ${inventoryMoney(_payment(data)?.balanceMinor ?? 0, widget.profile)}',
                              key: const Key('intake-balance'),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 16),
                        Text(
                          _total == null
                              ? 'Total de compra: completa precio y cantidad'
                              : _total! > Money.maxMinorUnits
                              ? 'Total de compra: supera el límite permitido'
                              : 'Total de compra: ${inventoryMoney(_total!.toInt(), widget.profile)}',
                          key: const Key('intake-total'),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (_total != null &&
                            _total! >
                                BigInt.from(_payment(data)?.balanceMinor ?? 0))
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'El saldo no alcanza para pagar esta compra.',
                              key: Key('intake-insufficient'),
                            ),
                          ),
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 16,
                          runSpacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            FilledButton.icon(
                              key: const Key('intake-submit'),
                              onPressed: locked || controller.loadError != null
                                  ? null
                                  : _receive,
                              icon: Icon(
                                controller.confirming
                                    ? Icons.hourglass_empty
                                    : Icons.inventory_2_outlined,
                              ),
                              label: Text(
                                controller.confirming
                                    ? 'Guardando ingreso…'
                                    : 'Ingresar producto',
                              ),
                            ),
                            OutlinedButton.icon(
                              key: const Key('intake-opening'),
                              onPressed:
                                  locked ||
                                      controller.loadError != null ||
                                      !data.paymentOptions.any(
                                        (item) =>
                                            item.isActive &&
                                            item.canRecordOpening,
                                      )
                                  ? null
                                  : () => _opening(data),
                              icon: const Icon(
                                Icons.account_balance_wallet_outlined,
                              ),
                              label: const Text('Saldo inicial'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Historial de ingresos',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              _history(data),
            ],
          ],
        ),
      );
    },
  );

  Widget _fields(List<Widget> fields) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 900
          ? fields.length
          : constraints.maxWidth >= 580
          ? 2
          : 1;
      final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final field in fields) SizedBox(width: width, child: field),
        ],
      );
    },
  );

  Widget _productField(StockIntakeSnapshot data, bool locked) =>
      RawAutocomplete<CatalogProduct>(
        textEditingController: _name,
        focusNode: _productFocus,
        displayStringForOption: (item) => item.name,
        optionsBuilder: (text) {
          final query = text.text.trim().toLowerCase();
          return query.isEmpty
              ? const Iterable<CatalogProduct>.empty()
              : data.products
                    .where(
                      (item) =>
                          item.isActive &&
                          (item.name.toLowerCase().contains(query) ||
                              (item.sku?.toLowerCase().contains(query) ??
                                  false)),
                    )
                    .take(8);
        },
        onSelected: (product) => setState(() {
          _existing = product;
          _sku.text = product.sku ?? '';
          _categoryId = product.categoryId;
          _pvp.text = _amount(product.listPriceMinor);
          final defaults = data.productDefaults[product.id];
          final cost = defaults?.unitPurchasePriceMinor;
          _cost.text = cost == null ? '' : _amount(cost);
          _supplier.text = defaults?.supplierName ?? '';
          _supplierId = defaults?.supplierId;
          _formVersion++;
        }),
        fieldViewBuilder: (context, controller, focus, submit) => TextFormField(
          key: const Key('intake-name'),
          controller: controller,
          focusNode: focus,
          enabled: !locked,
          maxLength: 120,
          decoration: const InputDecoration(
            labelText: 'Nombre del producto',
            hintText: 'Nuevo producto o buscar por nombre / SKU',
          ),
          validator: inventoryNameError,
          onFieldSubmitted: (_) => submit(),
          onChanged: (value) {
            if (_existing != null && value != _existing!.name) {
              setState(() {
                _existing = null;
                _sku.clear();
                _pvp.clear();
                _cost.clear();
                _supplier.clear();
                _supplierId = null;
                _categoryId = null;
                _formVersion++;
              });
            }
          },
        ),
        optionsViewBuilder: (context, selected, options) => _suggestions([
          for (final product in options)
            ListTile(
              dense: true,
              title: Text(product.name),
              subtitle: product.sku == null ? null : Text(product.sku!),
              onTap: () => selected(product),
            ),
        ]),
      );

  Widget _supplierField(StockIntakeSnapshot data, bool locked) =>
      RawAutocomplete<InventorySupplier>(
        textEditingController: _supplier,
        focusNode: _supplierFocus,
        displayStringForOption: (item) => item.name,
        optionsBuilder: (text) {
          final query = text.text.trim().toLowerCase();
          return query.isEmpty
              ? const Iterable<InventorySupplier>.empty()
              : data.suppliers
                    .where(
                      (item) =>
                          item.isActive &&
                          item.name.toLowerCase().contains(query),
                    )
                    .take(8);
        },
        onSelected: (supplier) => setState(() => _supplierId = supplier.id),
        fieldViewBuilder: (context, controller, focus, submit) => TextFormField(
          key: const Key('intake-supplier'),
          controller: controller,
          focusNode: focus,
          enabled: !locked,
          maxLength: 120,
          decoration: const InputDecoration(
            labelText: 'Proveedor',
            helperText: 'Elige uno existente o escribe el nombre de uno nuevo.',
          ),
          validator: inventoryNameError,
          onFieldSubmitted: (_) => submit(),
          onChanged: (value) {
            if (_supplierId != null &&
                !data.suppliers.any(
                  (item) => item.id == _supplierId && item.name == value,
                )) {
              setState(() => _supplierId = null);
            }
          },
        ),
        optionsViewBuilder: (context, selected, options) => _suggestions([
          for (final supplier in options)
            ListTile(
              dense: true,
              title: Text(supplier.name),
              onTap: () => selected(supplier),
            ),
        ]),
      );

  Widget _suggestions(List<Widget> children) => Align(
    alignment: Alignment.topLeft,
    child: Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 280),
        child: ListView(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          children: children,
        ),
      ),
    ),
  );

  String? _positiveAmountError(String? value) {
    final error = inventoryAmountError(value, widget.profile);
    if (error != null) return error;
    return Money.parseEsCo(
              value!,
              currency: widget.profile.currencyCode,
              scale: widget.profile.moneyScale,
            ).minorUnits <=
            0
        ? 'Escribe un precio mayor que cero.'
        : null;
  }

  String? _quantityError(String? value) {
    final text = value?.trim() ?? '';
    final quantity = BigInt.tryParse(text);
    return !RegExp(r'^[0-9]+$').hasMatch(text) ||
            quantity == null ||
            quantity <= BigInt.zero ||
            quantity > Money.maxMinorUnits
        ? 'Escribe una cantidad entera positiva.'
        : null;
  }

  Future<void> _receive() async {
    if (!_form.currentState!.validate()) return;
    final payment = _payment(widget.controller.snapshot!);
    if (payment == null) return;
    await widget.controller.receive(
      expectedProduct: _existing,
      productName: _name.text,
      sku: _sku.text,
      categoryId: _categoryId!,
      supplierId: _supplierId,
      supplierName: _supplier.text,
      unitPurchasePriceMinor: Money.parseEsCo(
        _cost.text,
        currency: widget.profile.currencyCode,
        scale: widget.profile.moneyScale,
      ).minorUnits,
      listPriceMinor: Money.parseEsCo(
        _pvp.text,
        currency: widget.profile.currencyCode,
        scale: widget.profile.moneyScale,
      ).minorUnits,
      quantity: BigInt.parse(_quantity.text.trim()).toInt(),
      paymentOptionId: payment.id,
    );
  }

  Widget _pending(PreparedStockIntake pending, StockIntakeSnapshot data) {
    final command = pending.command;
    final payment = data.paymentOptions
        .where((item) => item.id == command.paymentOptionId)
        .firstOrNull;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              pending.status == 'rejected'
                  ? 'Ingreso por corregir'
                  : 'Ingreso pendiente de confirmar',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '${command.productName} · ${command.quantity} unidades · ${payment?.label ?? 'Cuenta guardada'}',
            ),
            if (pending.rejectionReason != null) Text(pending.rejectionReason!),
            const SizedBox(height: 12),
            FilledButton(
              key: ValueKey('intake-retry-${command.commandId}'),
              onPressed: widget.controller.busy
                  ? null
                  : () => pending.status == 'rejected'
                        ? widget.controller.discardRejected(command.commandId)
                        : widget.controller.retry(command.commandId),
              child: Text(
                pending.status == 'rejected'
                    ? 'Corregir ingreso'
                    : 'Reintentar el mismo ingreso',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pendingOpening(StockIntakeSnapshot data) {
    final opening = widget.controller.pendingOpening!;
    final option = data.paymentOptions
        .where((item) => item.id == opening.paymentOptionId)
        .firstOrNull;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Saldo inicial pendiente: ${option?.label ?? 'Cuenta guardada'} · ${inventoryMoney(opening.amountMinor, widget.profile)}',
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('intake-retry-opening'),
              onPressed: widget.controller.busy
                  ? null
                  : widget.controller.retryOpening,
              child: const Text('Reintentar saldo inicial'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _opening(StockIntakeSnapshot data) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _OpeningDialog(
      controller: widget.controller,
      profile: widget.profile,
      options: data.paymentOptions
          .where((item) => item.isActive && item.canRecordOpening)
          .toList(),
      selected: _payment(data)?.id,
    ),
  );

  Widget _history(StockIntakeSnapshot data) {
    final rows = data.entries;
    if (rows.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Aún no hay ingresos de productos.'),
        ),
      );
    }
    const pageSize = 10;
    final page = _historyPage.clamp(0, (rows.length - 1) ~/ pageSize);
    return Column(
      children: [
        for (final entry in rows.skip(page * pageSize).take(pageSize))
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${entry.productName} · ${entry.quantity} unidades',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Chip(label: Text('Pagada · ${entry.paymentLabel}')),
                      Text(
                        inventoryMoney(entry.totalCostMinor, widget.profile),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${entry.supplierName} · ${entry.categoryName}${entry.sku == null ? '' : ' · ${entry.sku}'}',
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Compra unitaria: ${inventoryMoney(entry.unitPurchasePriceMinor, widget.profile)} · PVP: ${inventoryMoney(entry.listPriceMinor, widget.profile)}',
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Ingreso: ${InventoryController.isoDate(entry.occurredAtUtc.subtract(const Duration(hours: 5)))}',
                  ),
                ],
              ),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              '${page * pageSize + 1}–${(page * pageSize + pageSize).clamp(0, rows.length)} de ${rows.length}',
            ),
            IconButton(
              tooltip: 'Ingresos anteriores',
              onPressed: page == 0
                  ? null
                  : () => setState(() => _historyPage = page - 1),
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: 'Ingresos siguientes',
              onPressed: (page + 1) * pageSize >= rows.length
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

class _OpeningDialog extends StatefulWidget {
  const _OpeningDialog({
    required this.controller,
    required this.profile,
    required this.options,
    this.selected,
  });
  final StockIntakeController controller;
  final BusinessProfile profile;
  final List<IntakePaymentOption> options;
  final String? selected;
  @override
  State<_OpeningDialog> createState() => _OpeningDialogState();
}

class _OpeningDialogState extends State<_OpeningDialog> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  late String? _selected =
      widget.options.any((item) => item.id == widget.selected)
      ? widget.selected
      : widget.options.firstOrNull?.id;
  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => AlertDialog(
      title: const Text('Declarar saldo inicial'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Escribe el dinero real que tenías en esta cuenta antes de empezar a registrar movimientos. Se permite una sola vez por cuenta y antes de su primer movimiento.',
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  key: const Key('opening-account'),
                  initialValue: _selected,
                  decoration: const InputDecoration(labelText: 'Cuenta'),
                  isExpanded: true,
                  items: [
                    for (final option in widget.options)
                      DropdownMenuItem(
                        value: option.id,
                        child: Text(option.label),
                      ),
                  ],
                  onChanged:
                      widget.controller.busy ||
                          widget.controller.pendingOpening != null
                      ? null
                      : (value) => setState(() => _selected = value),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('opening-amount'),
                  controller: _amount,
                  enabled:
                      !widget.controller.busy &&
                      widget.controller.pendingOpening == null,
                  decoration: InputDecoration(
                    labelText: 'Saldo inicial (${widget.profile.currencyCode})',
                  ),
                  validator: (value) {
                    final error = inventoryAmountError(value, widget.profile);
                    if (error != null) return error;
                    return Money.parseEsCo(
                              value!,
                              currency: widget.profile.currencyCode,
                              scale: widget.profile.moneyScale,
                            ).minorUnits >
                            0
                        ? null
                        : 'Escribe un saldo positivo.';
                  },
                ),
                if (widget.controller.operationError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      widget.controller.operationError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: widget.controller.busy
              ? null
              : () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
        FilledButton(
          key: const Key('opening-save'),
          onPressed: widget.controller.busy
              ? null
              : () async {
                  bool saved;
                  if (widget.controller.pendingOpening != null) {
                    saved = await widget.controller.retryOpening();
                  } else {
                    if (!_form.currentState!.validate() || _selected == null) {
                      return;
                    }
                    saved = await widget.controller.recordOpening(
                      paymentOptionId: _selected!,
                      amountMinor: Money.parseEsCo(
                        _amount.text,
                        currency: widget.profile.currencyCode,
                        scale: widget.profile.moneyScale,
                      ).minorUnits,
                    );
                  }
                  if (saved && context.mounted) Navigator.pop(context);
                },
          child: Text(
            widget.controller.savingOpening
                ? 'Guardando…'
                : widget.controller.pendingOpening != null
                ? 'Reintentar el mismo saldo'
                : 'Guardar saldo inicial',
          ),
        ),
      ],
    ),
  );
}
