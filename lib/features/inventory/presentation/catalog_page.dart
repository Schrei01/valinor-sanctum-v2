import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/domain/money.dart';
import '../../workspace/domain/business_profile.dart';
import '../application/inventory_controller.dart';
import '../domain/inventory_store.dart';
import '../domain/reference_inventory.dart';
import 'inventory_widgets.dart';

class CatalogPage extends StatefulWidget {
  const CatalogPage({
    super.key,
    required this.controller,
    required this.profile,
    this.referenceStore,
  });
  final InventoryController controller;
  final BusinessProfile profile;
  final ReferenceInventoryStore? referenceStore;

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  final _search = TextEditingController();
  String _query = '';
  String? _categoryId;
  String? _supplierId;
  int _page = 0;
  ReferenceInventory? _reference;
  bool _referenceLoading = false;
  String? _referenceError;
  bool _showReference = false;
  bool _sourceChosen = false;
  int _referenceGeneration = 0;
  static const _pageSize = 15;

  @override
  void initState() {
    super.initState();
    unawaited(_loadReference());
  }

  @override
  void didUpdateWidget(covariant CatalogPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.referenceStore != widget.referenceStore) {
      _reference = null;
      _referenceLoading = false;
      _referenceError = null;
      _showReference = false;
      _sourceChosen = false;
      _clearFilters();
      unawaited(_loadReference());
    }
  }

  Future<void> _loadReference() async {
    final store = widget.referenceStore;
    final generation = ++_referenceGeneration;
    if (store == null) {
      if (_referenceLoading || _referenceError != null) {
        setState(() {
          _referenceLoading = false;
          _referenceError = null;
        });
      }
      return;
    }
    setState(() {
      _referenceLoading = true;
      _referenceError = null;
    });
    try {
      final next = await store.load();
      if (!mounted || generation != _referenceGeneration) return;
      setState(() {
        _reference = next;
        if (next != null && !_sourceChosen) {
          _sourceChosen = true;
          _showReference = true;
          _clearFilters();
        } else if (next == null && _showReference) {
          _showReference = false;
          _clearFilters();
        }
      });
    } catch (_) {
      if (!mounted || generation != _referenceGeneration) return;
      setState(() {
        _referenceError =
            'No se pudo leer el inventario de la copia. Pulsa Actualizar para '
            'reintentar. El catálogo de esta app sigue disponible.';
      });
    } finally {
      if (mounted && generation == _referenceGeneration) {
        setState(() => _referenceLoading = false);
      }
    }
  }

  Future<void> _refresh() async {
    await Future.wait([widget.controller.load(), _loadReference()]);
  }

  void _clearFilters() {
    _categoryId = null;
    _supplierId = null;
    _search.clear();
    _query = '';
    _page = 0;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final data = controller.snapshot;
      final reference = _reference;
      final showingReference = _showReference && reference != null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InventoryPageHeading(
            title: 'Catálogo',
            subtitle: showingReference
                ? 'Consulta el inventario guardado en la copia.'
                : 'Filtra productos por categoría o proveedor. Ingresa productos y cantidades desde Compras.',
            busy: controller.busy || _referenceLoading,
            onRefresh: _refresh,
          ),
          if (_referenceLoading && reference == null)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text('Cargando inventario de la copia…'),
            ),
          if (_referenceError != null)
            InventoryNotice(
              text: _referenceError!,
              onRetry: _referenceLoading ? null : _loadReference,
            ),
          if (reference != null) ...[
            SizedBox(
              width: 320,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Fuente'),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    key: const Key('catalog-source'),
                    value: showingReference ? 'reference' : 'app',
                    isExpanded: true,
                    isDense: true,
                    items: const [
                      DropdownMenuItem(
                        value: 'reference',
                        child: Text('Inventario de la copia'),
                      ),
                      DropdownMenuItem(
                        value: 'app',
                        child: Text('Catálogo de esta app'),
                      ),
                    ],
                    onChanged: (value) => setState(() {
                      _sourceChosen = true;
                      _showReference = value == 'reference';
                      _clearFilters();
                    }),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
          if (_showReference && reference != null) ...[
            _referenceProducts(reference),
          ] else ...[
            if (controller.loadError != null)
              InventoryNotice(
                text: controller.loadError!,
                onRetry: controller.busy ? null : controller.load,
              ),
            if (data == null)
              if (controller.loading)
                const Center(child: CircularProgressIndicator())
              else
                const Text('La información del catálogo no está disponible.')
            else ...[
              _filters(data),
              const SizedBox(height: 20),
              SizedBox(
                width: 320,
                child: TextField(
                  key: const Key('catalog-search'),
                  controller: _search,
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
              const SizedBox(height: 20),
              _products(data),
            ],
          ],
        ],
      );
    },
  );

  Widget _filters(InventorySnapshot data) => _filterControls(
    categories: [
      for (final category in data.categories)
        (
          category.id,
          '${category.name}${category.isActive ? '' : ' (Archivada)'}',
        ),
    ],
    suppliers: [
      for (final supplier in data.suppliers)
        (
          supplier.id,
          '${supplier.name}${supplier.isActive ? '' : ' (Archivado)'}',
        ),
    ],
  );

  Widget _filterControls({
    required List<(String, String)> categories,
    required List<(String, String)> suppliers,
    bool showCategory = true,
    bool showSupplier = true,
  }) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth < 260 ? constraints.maxWidth : 260.0;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (showCategory)
            SizedBox(
              width: width,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Categoría'),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    key: const Key('catalog-category-filter'),
                    value: _categoryId ?? '',
                    isExpanded: true,
                    isDense: true,
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Todas las categorías'),
                      ),
                      for (final category in categories)
                        DropdownMenuItem(
                          value: category.$1,
                          child: Text(
                            category.$2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if (_categoryId != null &&
                          !categories.any((item) => item.$1 == _categoryId))
                        DropdownMenuItem(
                          value: _categoryId,
                          child: const Text('Categoría no disponible'),
                        ),
                    ],
                    onChanged: (value) => setState(() {
                      _categoryId = value == '' ? null : value;
                      _page = 0;
                    }),
                  ),
                ),
              ),
            ),
          if (showSupplier)
            SizedBox(
              width: width,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Proveedor'),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    key: const Key('catalog-supplier-filter'),
                    value: _supplierId ?? '',
                    isExpanded: true,
                    isDense: true,
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Todos los proveedores'),
                      ),
                      for (final supplier in suppliers)
                        DropdownMenuItem(
                          value: supplier.$1,
                          child: Text(
                            supplier.$2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if (_supplierId != null &&
                          !suppliers.any((item) => item.$1 == _supplierId))
                        DropdownMenuItem(
                          value: _supplierId,
                          child: const Text('Proveedor no disponible'),
                        ),
                    ],
                    onChanged: (value) => setState(() {
                      _supplierId = value == '' ? null : value;
                      _page = 0;
                    }),
                  ),
                ),
              ),
            ),
          TextButton.icon(
            key: const Key('catalog-all-products'),
            onPressed: () => setState(_clearFilters),
            icon: const Icon(Icons.filter_alt_off_outlined),
            label: const Text('Todos los productos'),
          ),
        ],
      );
    },
  );

  Widget _referenceProducts(ReferenceInventory reference) {
    final available = reference.products
        .where((product) => product.quantity > 0)
        .toList();
    final hasLots = reference.products.any((product) => product.lot.isNotEmpty);
    final rows = available
        .where(
          (product) =>
              (_categoryId == null || product.category == _categoryId) &&
              (_supplierId == null || product.supplier == _supplierId) &&
              (product.name.toLowerCase().contains(_query) ||
                  product.lot.toLowerCase().contains(_query)),
        )
        .toList();
    final page = _clampedPage(rows.length);
    final captured = reference.capturedAtUtc.subtract(const Duration(hours: 5));
    final capturedText =
        '${captured.day.toString().padLeft(2, '0')}/'
        '${captured.month.toString().padLeft(2, '0')}/${captured.year} '
        '${captured.hour.toString().padLeft(2, '0')}:'
        '${captured.minute.toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Copia extraída el $capturedText (Colombia). '
          'Estos productos no están disponibles en Ventas de esta app.',
        ),
        const SizedBox(height: 8),
        if (reference.categories.isEmpty && reference.suppliers.isEmpty)
          const Text('La copia no contiene categorías ni proveedores.'),
        const SizedBox(height: 8),
        Text(
          '${reference.products.length} ${reference.products.length == 1 ? 'registro' : 'registros'} en la copia · '
          '${reference.totalUnits} ${reference.totalUnits == 1 ? 'unidad' : 'unidades'}. Solo se muestran productos con existencias.',
          key: const Key('reference-inventory-totals'),
        ),
        const SizedBox(height: 20),
        _filterControls(
          categories: [
            for (final value in reference.categories) (value, value),
          ],
          suppliers: [for (final value in reference.suppliers) (value, value)],
          showCategory: reference.categories.isNotEmpty,
          showSupplier: reference.suppliers.isNotEmpty,
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: 320,
          child: TextField(
            key: const Key('catalog-search'),
            controller: _search,
            decoration: InputDecoration(
              labelText: hasLots
                  ? 'Buscar por nombre o lote'
                  : 'Buscar por nombre',
              prefixIcon: const Icon(Icons.search),
            ),
            onChanged: (value) => setState(() {
              _query = value.trim().toLowerCase();
              _page = 0;
            }),
          ),
        ),
        const SizedBox(height: 20),
        if (rows.isEmpty)
          _EmptyCatalog(
            available.isEmpty
                ? 'No hay productos con existencias en la copia.'
                : 'No hay productos con existencias que coincidan con la búsqueda y los filtros.',
          )
        else ...[
          Text(
            '${rows.length} ${rows.length == 1 ? 'producto' : 'productos'} con existencias',
          ),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                dataRowMinHeight: 64,
                dataRowMaxHeight: 64,
                columns: const [
                  DataColumn(label: Text('Producto')),
                  DataColumn(label: Text('PVP'), numeric: true),
                  DataColumn(label: Text('Unidades'), numeric: true),
                  DataColumn(label: Text('Estado')),
                ],
                rows: [
                  for (final product
                      in rows.skip(page * _pageSize).take(_pageSize))
                    DataRow(
                      cells: [
                        DataCell(
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 260),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  product.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (product.category.isNotEmpty ||
                                    product.supplier.isNotEmpty)
                                  Text(
                                    [product.category, product.supplier]
                                        .where((value) => value.isNotEmpty)
                                        .join(' · '),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                if (product.lot.isNotEmpty)
                                  Text(
                                    'Lote: ${product.lot}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            Money.fromMinorUnits(
                              product.priceMinor,
                              currency: reference.currencyCode,
                              scale: reference.moneyScale,
                            ).formatEsCo(includeCurrency: true),
                          ),
                        ),
                        DataCell(Text('${product.quantity}')),
                        const DataCell(Text('Con existencias')),
                      ],
                    ),
                ],
              ),
            ),
          ),
          _pagination(rows.length, page),
        ],
      ],
    );
  }

  Widget _products(InventorySnapshot data) {
    final positions = {for (final stock in data.stock) stock.productId: stock};
    final available = data.products
        .where((item) => (positions[item.id]?.quantity ?? 0) > 0)
        .toList();
    final rows = available
        .where(
          (item) =>
              (_categoryId == null || item.categoryId == _categoryId) &&
              (_supplierId == null ||
                  (data.productSupplierIds[item.id]?.contains(_supplierId) ??
                      false)) &&
              (item.name.toLowerCase().contains(_query) ||
                  (item.sku?.toLowerCase().contains(_query) ?? false)),
        )
        .toList();
    final page = _clampedPage(rows.length);
    final categories = {
      for (final category in data.categories) category.id: category.name,
    };
    if (rows.isEmpty) {
      return _EmptyCatalog(
        available.isEmpty
            ? 'No hay productos con existencias. Ingresa productos y cantidades desde Compras.'
            : 'No hay productos con existencias que coincidan con la búsqueda y los filtros.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${rows.length} ${rows.length == 1 ? 'producto' : 'productos'} con existencias',
        ),
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              dataRowMinHeight: 64,
              dataRowMaxHeight: 64,
              columns: const [
                DataColumn(label: Text('Producto')),
                DataColumn(label: Text('PVP'), numeric: true),
                DataColumn(label: Text('Unidades'), numeric: true),
                DataColumn(label: Text('Estado')),
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
                      DataCell(Text(product.isActive ? 'Activo' : 'Archivado')),
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
}

class _EmptyCatalog extends StatelessWidget {
  const _EmptyCatalog(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(28), child: Text(text)),
  );
}
