import 'package:flutter/material.dart';

import '../../../core/domain/money.dart';
import '../../workspace/domain/business_profile.dart';
import '../application/inventory_controller.dart';
import '../domain/inventory_store.dart';
import 'inventory_widgets.dart';

enum _CatalogTab { products, categories, suppliers }

class CatalogPage extends StatefulWidget {
  const CatalogPage({
    super.key,
    required this.controller,
    required this.profile,
  });
  final InventoryController controller;
  final BusinessProfile profile;

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  _CatalogTab _tab = _CatalogTab.products;
  String _query = '';
  int _page = 0;
  static const _pageSize = 15;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final data = controller.snapshot;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InventoryPageHeading(
            title: 'Catálogo e inventario',
            subtitle:
                'Productos en unidades enteras. Las existencias y su valoración provienen de compras recibidas; los ajustes están pendientes.',
            busy: controller.busy,
            onRefresh: controller.load,
          ),
          if (controller.loadError != null)
            InventoryNotice(
              text: controller.loadError!,
              onRetry: controller.busy ? null : controller.load,
            ),
          if (controller.catalogError != null)
            InventoryNotice(text: controller.catalogError!),
          if (data == null)
            if (controller.loading)
              const Center(child: CircularProgressIndicator())
            else
              const Text('La información del catálogo no está disponible.')
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tab in _CatalogTab.values)
                  ChoiceChip(
                    label: Text(switch (tab) {
                      _CatalogTab.products => 'Productos',
                      _CatalogTab.categories => 'Categorías',
                      _CatalogTab.suppliers => 'Proveedores',
                    }),
                    selected: _tab == tab,
                    onSelected: (_) => setState(() {
                      _tab = tab;
                      _page = 0;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 320,
                  child: TextField(
                    key: const Key('catalog-search'),
                    decoration: const InputDecoration(
                      labelText: 'Buscar por nombre o SKU',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) => setState(() {
                      _query = value.trim().toLowerCase();
                      _page = 0;
                    }),
                  ),
                ),
                FilledButton.icon(
                  key: const Key('catalog-create'),
                  onPressed: controller.busy
                      ? null
                      : () => _create(context, data),
                  icon: const Icon(Icons.add),
                  label: Text(switch (_tab) {
                    _CatalogTab.products => 'Nuevo producto',
                    _CatalogTab.categories => 'Nueva categoría',
                    _CatalogTab.suppliers => 'Nuevo proveedor',
                  }),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_tab == _CatalogTab.products) _products(data) else _names(data),
          ],
        ],
      );
    },
  );

  Widget _products(InventorySnapshot data) {
    final rows = data.products
        .where(
          (item) =>
              item.name.toLowerCase().contains(_query) ||
              (item.sku?.toLowerCase().contains(_query) ?? false),
        )
        .toList();
    final page = _clampedPage(rows.length);
    final positions = {for (final stock in data.stock) stock.productId: stock};
    final categories = {
      for (final category in data.categories) category.id: category.name,
    };
    if (rows.isEmpty) {
      return const _EmptyCatalog(
        'No hay productos para mostrar. Crea el primero para recibir inventario.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              dataRowMinHeight: 64,
              dataRowMaxHeight: 64,
              columns: const [
                DataColumn(label: Text('Producto')),
                DataColumn(label: Text('Precio de lista'), numeric: true),
                DataColumn(label: Text('Unidades'), numeric: true),
                DataColumn(label: Text('Valoración'), numeric: true),
                DataColumn(label: Text('Estado')),
                DataColumn(label: Text('Acciones')),
              ],
              rows: [
                for (final product
                    in rows.skip(page * _pageSize).take(_pageSize))
                  DataRow(
                    cells: [
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 260),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  product.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  [
                                    if (product.sku != null) product.sku!,
                                    if (product.categoryId != null)
                                      categories[product.categoryId] ??
                                          'Categoría no disponible',
                                  ].join(' · '),
                                  style: Theme.of(context).textTheme.bodySmall,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          inventoryMoney(
                            product.listPriceMinor,
                            widget.profile,
                          ),
                        ),
                      ),
                      DataCell(Text('${positions[product.id]?.quantity ?? 0}')),
                      DataCell(
                        Text(
                          inventoryMoney(
                            positions[product.id]?.totalCostMinor ?? 0,
                            widget.profile,
                          ),
                        ),
                      ),
                      DataCell(Text(product.isActive ? 'Activo' : 'Archivado')),
                      DataCell(
                        Row(
                          children: [
                            IconButton(
                              tooltip: 'Editar ${product.name}',
                              onPressed: widget.controller.busy
                                  ? null
                                  : () => _editProduct(product, data),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            TextButton(
                              onPressed: widget.controller.busy
                                  ? null
                                  : () => widget.controller.saveProduct(
                                      CatalogProduct(
                                        id: product.id,
                                        name: product.name,
                                        sku: product.sku,
                                        categoryId: product.categoryId,
                                        listPriceMinor: product.listPriceMinor,
                                        isActive: !product.isActive,
                                      ),
                                    ),
                              child: Text(
                                product.isActive ? 'Archivar' : 'Reactivar',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        _pagination(rows.length, page),
      ],
    );
  }

  Widget _names(InventorySnapshot data) {
    final entries = _tab == _CatalogTab.categories
        ? data.categories
              .map((value) => (value.id, value.name, value.isActive))
              .toList()
        : data.suppliers
              .map((value) => (value.id, value.name, value.isActive))
              .toList();
    final rows = entries
        .where((value) => value.$2.toLowerCase().contains(_query))
        .toList();
    final page = _clampedPage(rows.length);
    if (rows.isEmpty) {
      return _EmptyCatalog(
        _tab == _CatalogTab.categories
            ? 'Aún no hay categorías. Puedes crearlas para organizar los productos.'
            : 'Aún no hay proveedores. Crea uno para registrar compras a crédito.',
      );
    }
    return Column(
      children: [
        for (final entry in rows.skip(page * _pageSize).take(_pageSize))
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 20,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 280,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.$2,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(entry.$3 ? 'Activo' : 'Archivado'),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Editar ${entry.$2}',
                    onPressed: widget.controller.busy
                        ? null
                        : () => _editName(
                            id: entry.$1,
                            name: entry.$2,
                            active: entry.$3,
                          ),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  TextButton(
                    onPressed: widget.controller.busy
                        ? null
                        : () => _saveName(entry.$1, entry.$2, !entry.$3),
                    child: Text(entry.$3 ? 'Archivar' : 'Reactivar'),
                  ),
                ],
              ),
            ),
          ),
        _pagination(rows.length, page),
      ],
    );
  }

  int _clampedPage(int length) =>
      _page.clamp(0, length == 0 ? 0 : (length - 1) ~/ _pageSize);

  Widget _pagination(int length, int page) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          '${page * _pageSize + 1}–${(page * _pageSize + _pageSize).clamp(0, length)} de $length',
        ),
        IconButton(
          tooltip: 'Página anterior',
          onPressed: page == 0 ? null : () => setState(() => _page = page - 1),
          icon: const Icon(Icons.chevron_left),
        ),
        IconButton(
          tooltip: 'Página siguiente',
          onPressed: (page + 1) * _pageSize >= length
              ? null
              : () => setState(() => _page = page + 1),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    ),
  );

  void _create(BuildContext context, InventorySnapshot data) {
    if (_tab == _CatalogTab.products) {
      _editProduct(null, data);
    } else {
      _editName();
    }
  }

  Future<bool> _saveName(String id, String name, bool active) =>
      _tab == _CatalogTab.categories
      ? widget.controller.saveCategory(
          InventoryCategory(id: id, name: name, isActive: active),
        )
      : widget.controller.saveSupplier(
          InventorySupplier(id: id, name: name, isActive: active),
        );

  Future<void> _editName({String? id, String? name, bool active = true}) async {
    final category = _tab == _CatalogTab.categories;
    final editorId = id ?? InventoryIds.next();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _NameDialog(
        controller: widget.controller,
        title:
            '${id == null ? (category ? 'Nueva' : 'Nuevo') : 'Editar'} ${category ? 'categoría' : 'proveedor'}',
        name: name ?? '',
        onSave: (value) => _saveName(editorId, value, active),
      ),
    );
  }

  Future<void> _editProduct(CatalogProduct? product, InventorySnapshot data) =>
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _ProductDialog(
          controller: widget.controller,
          profile: widget.profile,
          categories: data.categories,
          product: product,
        ),
      );
}

class _EmptyCatalog extends StatelessWidget {
  const _EmptyCatalog(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(28), child: Text(text)),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.controller,
    required this.title,
    required this.name,
    required this.onSave,
  });
  final InventoryController controller;
  final String title;
  final String name;
  final Future<bool> Function(String) onSave;
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.name);
  bool _attempted = false;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                key: const Key('catalog-name'),
                controller: _name,
                enabled: !widget.controller.busy,
                autofocus: true,
                maxLength: 120,
                decoration: const InputDecoration(labelText: 'Nombre'),
                validator: inventoryNameError,
              ),
              if (_attempted && widget.controller.catalogError != null)
                Text(
                  widget.controller.catalogError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: widget.controller.busy
              ? null
              : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: widget.controller.busy
              ? null
              : () async {
                  if (!_form.currentState!.validate()) return;
                  setState(() => _attempted = true);
                  final saved = await widget.onSave(_name.text.trim());
                  if (saved && context.mounted) Navigator.pop(context);
                },
          child: Text(widget.controller.saving ? 'Guardando…' : 'Guardar'),
        ),
      ],
    ),
  );
}

class _ProductDialog extends StatefulWidget {
  const _ProductDialog({
    required this.controller,
    required this.profile,
    required this.categories,
    this.product,
  });
  final InventoryController controller;
  final BusinessProfile profile;
  final List<InventoryCategory> categories;
  final CatalogProduct? product;
  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<_ProductDialog> {
  final _form = GlobalKey<FormState>();
  late final _editorId = widget.product?.id ?? InventoryIds.next();
  late final _name = TextEditingController(text: widget.product?.name ?? '');
  late final _sku = TextEditingController(text: widget.product?.sku ?? '');
  late final _price = TextEditingController(
    text: widget.product == null
        ? ''
        : Money.fromMinorUnits(
            widget.product!.listPriceMinor,
            currency: widget.profile.currencyCode,
            scale: widget.profile.moneyScale,
          ).formatEsCo(),
  );
  late String? _categoryId = widget.product?.categoryId;
  bool _attempted = false;
  @override
  void dispose() {
    _name.dispose();
    _sku.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => AlertDialog(
      title: Text(
        widget.product == null ? 'Nuevo producto' : 'Editar producto',
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  key: const Key('product-name'),
                  controller: _name,
                  enabled: !widget.controller.busy,
                  autofocus: true,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  validator: inventoryNameError,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('product-sku'),
                  controller: _sku,
                  enabled: !widget.controller.busy,
                  maxLength: 64,
                  decoration: const InputDecoration(
                    labelText: 'SKU (opcional)',
                  ),
                  validator: (value) =>
                      RegExp(r'[\x00-\x1f]').hasMatch(value ?? '')
                      ? 'Escribe un SKU válido.'
                      : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const Key('product-category'),
                  initialValue: _categoryId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Categoría'),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Sin categoría'),
                    ),
                    for (final category in widget.categories.where(
                      (item) => item.isActive || item.id == _categoryId,
                    ))
                      DropdownMenuItem(
                        value: category.id,
                        enabled: category.isActive,
                        child: Text(
                          '${category.name}${category.isActive ? '' : ' (archivada)'}',
                        ),
                      ),
                  ],
                  onChanged: widget.controller.busy
                      ? null
                      : (value) => setState(() => _categoryId = value),
                  validator: (value) =>
                      value != null &&
                          !widget.categories.any(
                            (item) => item.id == value && item.isActive,
                          )
                      ? 'Selecciona una categoría activa o Sin categoría.'
                      : null,
                ),
                const SizedBox(height: 18),
                TextFormField(
                  key: const Key('product-price'),
                  controller: _price,
                  enabled: !widget.controller.busy,
                  decoration: InputDecoration(
                    labelText:
                        'Precio de lista (${widget.profile.currencyCode})',
                    helperText:
                        '${widget.profile.moneyScale} decimales · formato colombiano',
                  ),
                  validator: (value) =>
                      inventoryAmountError(value, widget.profile),
                ),
                const SizedBox(height: 16),
                const Text(
                  'El precio de lista no cambia el costo ni las compras ya recibidas.',
                ),
                if (_attempted && widget.controller.catalogError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      widget.controller.catalogError!,
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
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: widget.controller.busy
              ? null
              : () async {
                  if (!_form.currentState!.validate()) return;
                  setState(() => _attempted = true);
                  final sku = _sku.text.trim();
                  final saved = await widget.controller.saveProduct(
                    CatalogProduct(
                      id: _editorId,
                      name: _name.text.trim(),
                      sku: sku.isEmpty ? null : sku,
                      categoryId: _categoryId,
                      listPriceMinor: Money.parseEsCo(
                        _price.text,
                        currency: widget.profile.currencyCode,
                        scale: widget.profile.moneyScale,
                      ).minorUnits,
                      isActive: widget.product?.isActive ?? true,
                    ),
                  );
                  if (saved && context.mounted) Navigator.pop(context);
                },
          child: Text(
            widget.controller.saving ? 'Guardando…' : 'Guardar producto',
          ),
        ),
      ],
    ),
  );
}
