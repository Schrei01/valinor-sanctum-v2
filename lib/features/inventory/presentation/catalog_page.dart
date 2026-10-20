import 'package:flutter/material.dart';

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
  final _search = TextEditingController();
  String _query = '';
  int _page = 0;
  static const _pageSize = 15;

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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InventoryPageHeading(
            title: 'Catálogo',
            subtitle:
                'Consulta productos, categorías y proveedores. Ingresa productos y cantidades desde Compras.',
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
                    onSelected: (_) {
                      if (_tab == tab) return;
                      setState(() {
                        _tab = tab;
                        _search.clear();
                        _query = '';
                        _page = 0;
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 320,
              child: TextField(
                key: const Key('catalog-search'),
                controller: _search,
                decoration: InputDecoration(
                  labelText: _tab == _CatalogTab.products
                      ? 'Buscar por nombre o SKU'
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
        'No hay productos para mostrar. Puedes ingresar el primero con su cantidad desde Compras.',
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

  Widget _names(InventorySnapshot data) {
    final entries = _tab == _CatalogTab.categories
        ? data.categories.map((value) => (value.name, value.isActive)).toList()
        : data.suppliers.map((value) => (value.name, value.isActive)).toList();
    final rows = entries
        .where((value) => value.$1.toLowerCase().contains(_query))
        .toList();
    final page = _clampedPage(rows.length);
    if (rows.isEmpty) {
      return _EmptyCatalog(
        _tab == _CatalogTab.categories
            ? 'No hay categorías para mostrar.'
            : 'No hay proveedores para mostrar. Puedes registrarlos al ingresar un producto en Compras.',
      );
    }
    return Column(
      children: [
        for (final entry in rows.skip(page * _pageSize).take(_pageSize))
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.$1,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(entry.$2 ? 'Activo' : 'Archivado'),
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
