part of 'purchases_page.dart';

class _PurchaseProductForm extends StatefulWidget {
  const _PurchaseProductForm({
    super.key,
    required this.id,
    required this.first,
    required this.data,
    required this.profile,
    required this.locked,
    required this.categoryId,
    required this.onChanged,
    required this.onCategorySelected,
    this.initial,
  });
  final String id;
  final bool first, locked;
  final StockIntakeSnapshot data;
  final BusinessProfile profile;
  final String? categoryId;
  final VoidCallback onChanged;
  final ValueChanged<String> onCategorySelected;
  final StockIntakeCommand? initial;
  @override
  State<_PurchaseProductForm> createState() => _PurchaseProductFormState();
}

class _PurchaseProductFormState extends State<_PurchaseProductForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _sku = TextEditingController(),
      _supplier = TextEditingController(),
      _cost = TextEditingController(),
      _pvp = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _productFocus = FocusNode(), _supplierFocus = FocusNode();
  CatalogProduct? _existing;
  String? _supplierId;
  bool _pvpManual = false;
  Key _key(String name) => Key(widget.first ? name : '$name-${widget.id}');

  @override
  void initState() {
    super.initState();
    final c = widget.initial;
    if (c != null) {
      _existing = c.expectedProduct;
      _name.text = c.productName;
      _sku.text = c.sku ?? '';
      _supplier.text = c.supplierName;
      _supplierId = c.supplierId;
      _cost.text = _amount(c.totalCostMinor);
      _quantity.text = '${c.quantity}';
      _pvp.text = _amount(c.listPriceMinor);
      _pvpManual = true;
    }
  }

  @override
  void dispose() {
    for (final field in [_name, _sku, _supplier, _cost, _pvp, _quantity]) {
      field.dispose();
    }
    _productFocus.dispose();
    _supplierFocus.dispose();
    super.dispose();
  }

  int? get enteredCost => _total?.toInt();
  String? get existingCategory => _existing?.categoryId;
  StockIntakeCommand? command({
    required String category,
    required String payment,
    required DateTime at,
  }) {
    if (!_form.currentState!.validate()) return null;
    if (_existing != null && _existing!.categoryId != category) return null;
    return StockIntakeCommand(
      commandId: InventoryIds.next(),
      productId: _existing?.id ?? InventoryIds.next(),
      expectedProduct: _existing,
      productName: _name.text.trim(),
      sku: _sku.text.trim().isEmpty ? null : _sku.text.trim(),
      categoryId: category,
      supplierId: _supplierId,
      supplierName: _supplier.text.trim(),
      totalPurchasePriceMinor: enteredCost,
      listPriceMinor: Money.parseEsCo(
        _pvp.text,
        currency: widget.profile.currencyCode,
        scale: widget.profile.moneyScale,
      ).minorUnits,
      quantity: int.parse(_quantity.text.replaceAll('.', '')),
      paymentOptionId: payment,
      occurredAtUtc: at,
    );
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.locked, data = widget.data;
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _productField(data, locked),
          if (_existing != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Reponer producto · existencias: ${data.stock.where((item) => item.productId == _existing!.id).firstOrNull?.quantity ?? 0}',
                key: _key('intake-existing'),
              ),
            ),
          const SizedBox(height: 16),
          _fields([
            TextFormField(
              key: _key('intake-sku'),
              controller: _sku,
              enabled: !locked,
              maxLength: 64,
              decoration: const InputDecoration(labelText: 'SKU (opcional)'),
              validator: (value) => RegExp(r'[\x00-\x1f]').hasMatch(value ?? '')
                  ? 'Escribe un SKU válido.'
                  : null,
            ),
            _supplierField(data, locked),
          ]),
          const SizedBox(height: 16),
          _fields([
            TextFormField(
              key: _key('intake-quantity'),
              controller: _quantity,
              inputFormatters: [
                const GroupedNumberFormatter(integerOnly: true),
              ],
              enabled: !locked,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Unidades'),
              validator: _quantityError,
              onChanged: (_) {
                setState(_suggest);
                widget.onChanged();
              },
            ),
            TextFormField(
              key: _key('intake-cost'),
              controller: _cost,
              inputFormatters: [const GroupedNumberFormatter()],
              enabled: !locked,
              decoration: InputDecoration(
                labelText:
                    'Costo total de las unidades (${widget.profile.currencyCode})',
              ),
              validator: _positiveAmountError,
              onChanged: (_) {
                setState(_suggest);
                widget.onChanged();
              },
            ),
            TextFormField(
              key: _key('intake-pvp'),
              controller: _pvp,
              inputFormatters: [const GroupedNumberFormatter()],
              enabled: !locked,
              decoration: InputDecoration(
                labelText: 'PVP unitario (${widget.profile.currencyCode})',
              ),
              validator: (value) => inventoryAmountError(value, widget.profile),
              onChanged: (_) => setState(() => _pvpManual = true),
            ),
          ]),
          const SizedBox(height: 8),
          if (_existing != null)
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'PVP anterior: ${inventoryMoney(_existing!.listPriceMinor, widget.profile)}',
                  key: _key('intake-previous-pvp'),
                ),
                TextButton(
                  key: _key('intake-use-previous-pvp'),
                  onPressed: locked
                      ? null
                      : () => setState(() {
                          _pvp.text = _amount(_existing!.listPriceMinor);
                          _pvpManual = true;
                        }),
                  child: const Text('Usar valor'),
                ),
              ],
            ),
          Text(
            _suggestedPvp == null
                ? 'PVP sugerido: completa costo total y cantidad'
                : 'PVP sugerido: ${inventoryMoney(_suggestedPvp!, widget.profile)}',
            key: _key('intake-suggested-pvp'),
          ),
          const Text(
            'Sugerencia = costo total ÷ cantidad ÷ 0,65. Puedes elegir un PVP menor. El PVP elegido aplica a todas las existencias y sus cambios quedan guardados.',
            style: TextStyle(fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  String _amount(int value) => Money.fromMinorUnits(
    value,
    currency: widget.profile.currencyCode,
    scale: widget.profile.moneyScale,
  ).formatEsCo();

  BigInt? get _total {
    try {
      final quantity = BigInt.tryParse(
        _quantity.text.trim().replaceAll('.', ''),
      );
      if (quantity == null ||
          quantity <= BigInt.zero ||
          !RegExp(
            r'^[0-9]+$',
          ).hasMatch(_quantity.text.trim().replaceAll('.', ''))) {
        return null;
      }
      final cost = Money.parseEsCo(
        _cost.text,
        currency: widget.profile.currencyCode,
        scale: widget.profile.moneyScale,
      );
      if (cost.minorUnits <= 0) return null;
      return cost.asBigInt;
    } on FormatException {
      return null;
    } on RangeError {
      return null;
    }
  }

  int? get _suggestedPvp {
    final total = _total;
    final quantity = BigInt.tryParse(_quantity.text.trim().replaceAll('.', ''));
    if (total == null ||
        total > Money.maxMinorUnits ||
        quantity == null ||
        quantity <= BigInt.zero ||
        quantity > Money.maxMinorUnits) {
      return null;
    }
    try {
      return suggestedRetailPriceMinor(
        totalCostMinor: total.toInt(),
        quantity: quantity.toInt(),
      );
    } on RangeError {
      return null;
    }
  }

  void _suggest() {
    final price = _suggestedPvp;
    if (!_pvpManual && price != null) _pvp.text = _amount(price);
  }

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
                          (widget.categoryId == null ||
                              item.categoryId == widget.categoryId) &&
                          data.categories.any(
                            (cat) => cat.id == item.categoryId && cat.isActive,
                          ) &&
                          (item.name.toLowerCase().contains(query) ||
                              (item.sku?.toLowerCase().contains(query) ??
                                  false)),
                    )
                    .take(8);
        },
        onSelected: (product) => setState(() {
          _existing = product;
          if (widget.categoryId == null && product.categoryId != null) {
            widget.onCategorySelected(product.categoryId!);
          }
          _sku.text = product.sku ?? '';
          _pvp.text = _amount(product.listPriceMinor);
          _pvpManual = false;
          final defaults = data.productDefaults[product.id];
          _cost.clear();
          _supplier.text = defaults?.supplierName ?? '';
          _supplierId = defaults?.supplierId;
          widget.onChanged();
        }),
        fieldViewBuilder: (context, controller, focus, submit) => TextFormField(
          key: _key('intake-name'),
          controller: controller,
          focusNode: focus,
          enabled: !locked,
          maxLength: 120,
          decoration: const InputDecoration(
            labelText: 'Nombre del producto',
            hintText: 'Nuevo producto o buscar por nombre / SKU',
          ),
          validator: (value) => isDayPassName(value ?? '')
              ? 'Pasadía es un servicio ilimitado; se vende desde Ventas.'
              : inventoryNameError(value),
          onFieldSubmitted: (_) => submit(),
          onChanged: (value) {
            if (_existing != null && value != _existing!.name) {
              setState(() {
                _existing = null;
                _sku.clear();
                _pvp.clear();
                _pvpManual = false;
                _cost.clear();
                _supplier.clear();
                _supplierId = null;
              });
              widget.onChanged();
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
          key: _key('intake-supplier'),
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
    final text = value?.trim().replaceAll('.', '') ?? '';
    final quantity = BigInt.tryParse(text);
    return !RegExp(r'^[0-9]+$').hasMatch(text) ||
            quantity == null ||
            quantity <= BigInt.zero ||
            quantity > Money.maxMinorUnits
        ? 'Escribe una cantidad entera positiva.'
        : null;
  }
}
