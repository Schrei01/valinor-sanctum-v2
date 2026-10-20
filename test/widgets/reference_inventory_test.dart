import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/app/sanctum_app.dart';
import 'package:valinor_sanctum_2/features/inventory/application/inventory_controller.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/reference_inventory.dart';
import 'package:valinor_sanctum_2/features/inventory/presentation/catalog_page.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';
import 'package:valinor_sanctum_2/features/workspace/application/workspace_controller.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/workspace_store.dart';

import '../support/fake_inventory_store.dart';
import '../support/fake_quick_sales_store.dart';
import '../support/fake_workspace_store.dart';

class _FakeReferenceStore implements ReferenceInventoryStore {
  ReferenceInventory? value;
  Object? failure;
  Completer<ReferenceInventory?>? gate;
  int loads = 0;

  @override
  Future<ReferenceInventory?> load() async {
    loads++;
    if (failure != null) throw failure!;
    if (gate != null) return gate!.future;
    return value;
  }
}

ReferenceInventory _reference({List<ReferenceInventoryProduct>? products}) =>
    ReferenceInventory(
      sourceName: 'copia-sintetica.sqlite3',
      sourceSha256: List.filled(64, 'a').join(),
      capturedAtUtc: DateTime.utc(2026, 10, 20, 15, 30),
      products:
          products ??
          const [
            ReferenceInventoryProduct(
              id: 'reference-1',
              name: 'Producto de la copia',
              quantity: 7,
              priceMinor: 1234,
              purchasePriceMinor: 500,
              lot: 'LOTE-SINTETICO',
            ),
            ReferenceInventoryProduct(
              id: 'reference-2',
              name: 'Producto agotado',
              quantity: 0,
              priceMinor: 0,
              purchasePriceMinor: 0,
            ),
          ],
    );

FakeInventoryStore _inventory() => FakeInventoryStore()
  ..categories.add(const InventoryCategory(id: 'food', name: 'Comestible'))
  ..suppliers.add(
    const InventorySupplier(id: 'supplier', name: 'Proveedor app'),
  )
  ..products.add(
    const CatalogProduct(
      id: 'app-1',
      name: 'Producto de esta app',
      listPriceMinor: 777,
      categoryId: 'food',
    ),
  )
  ..stock.add(
    const StockPosition(productId: 'app-1', quantity: 9, totalCostMinor: 4500),
  )
  ..productSupplierIds['app-1'] = ['supplier'];

void main() {
  Future<InventoryController> open(
    WidgetTester tester,
    FakeInventoryStore inventory, {
    ReferenceInventoryStore? reference,
    Size size = const Size(1100, 950),
    bool settle = true,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = InventoryController(store: inventory);
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: CatalogPage(
                controller: controller,
                profile: BusinessProfile(
                  profileId: 'synthetic',
                  businessName: 'Ludoteca sintética',
                  currencyCode: 'COP',
                  moneyScale: 0,
                  timezone: 'America/Bogota',
                  createdAtUtc: DateTime.utc(2026, 10, 20),
                ),
                referenceStore: reference,
              ),
            ),
          ),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
    return controller;
  }

  Future<void> selectSource(WidgetTester tester, String label) async {
    await tester.tap(find.byKey(const Key('catalog-source')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'missing reference preserves the operational catalog without a selector',
    (tester) async {
      final inventory = _inventory();
      final reference = _FakeReferenceStore();
      await open(tester, inventory, reference: reference);
      expect(find.byKey(const Key('catalog-source')), findsNothing);
      expect(find.text('Producto de esta app'), findsOneWidget);
      expect(find.byKey(const Key('catalog-category-filter')), findsOneWidget);
      expect(find.textContaining('No se pudo leer'), findsNothing);
      expect(reference.loads, 1);
      expect(inventory.saves, 0);
      expect(inventory.receivedCommands, isEmpty);
    },
  );

  testWidgets(
    'valid reference defaults to isolated read only stock and its own money scale',
    (tester) async {
      final inventory = _inventory();
      final reference = _FakeReferenceStore()..value = _reference();
      await open(tester, inventory, reference: reference);
      expect(find.text('Producto de la copia'), findsOneWidget);
      expect(find.text('Producto agotado'), findsNothing);
      expect(find.text('Producto de esta app'), findsNothing);
      expect(find.text('Lote: LOTE-SINTETICO'), findsOneWidget);
      expect(find.text('COP 12,34'), findsOneWidget);
      expect(find.text('COP 0,00'), findsNothing);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('0'), findsNothing);
      expect(find.text('Sin proveedor'), findsOneWidget);
      expect(find.text('Estado'), findsNothing);
      final table = tester.widget<DataTable>(find.byType(DataTable));
      expect(table.columns.map((column) => (column.label as Text).data), [
        'Producto',
        'PVP',
        'Unidades',
        'Proveedor',
      ]);
      expect(find.text('Agotado'), findsNothing);
      expect(find.text('Activo'), findsNothing);
      expect(
        find.text(
          '2 registros en la copia · 7 unidades. Solo se muestran productos con existencias.',
        ),
        findsOneWidget,
      );
      expect(find.text('1 producto con existencias'), findsOneWidget);
      expect(find.textContaining('20/10/2026 10:30'), findsOneWidget);
      expect(
        find.textContaining('no están disponibles en Ventas'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('catalog-category-filter')), findsNothing);
      expect(find.byKey(const Key('catalog-supplier-filter')), findsNothing);
      expect(
        find.text('La copia no contiene categorías ni proveedores.'),
        findsOneWidget,
      );
      expect(find.text('Acciones'), findsNothing);
      expect(find.text('Valoración'), findsNothing);
      expect(find.text('Archivar'), findsNothing);
      expect(find.byKey(const Key('catalog-create')), findsNothing);

      await tester.enterText(
        find.byKey(const Key('catalog-search')),
        'lote-sintetico',
      );
      await tester.pumpAndSettle();
      expect(find.text('Producto de la copia'), findsOneWidget);
      expect(find.text('Producto agotado'), findsNothing);
      expect(reference.loads, 1);
      await selectSource(tester, 'Catálogo de esta app');
      expect(find.text('Producto de esta app'), findsOneWidget);
      expect(find.text('Producto de la copia'), findsNothing);
      expect(find.text('COP 777'), findsOneWidget);
      expect(find.text('9'), findsOneWidget);
      expect(find.byKey(const Key('catalog-category-filter')), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('catalog-search')))
            .controller!
            .text,
        isEmpty,
      );
      await tester.enterText(find.byKey(const Key('catalog-search')), 'app');
      await tester.pumpAndSettle();
      await selectSource(tester, 'Inventario de la copia');
      expect(find.text('Producto agotado'), findsNothing);
      expect(find.text('Producto de la copia'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('catalog-search')))
            .controller!
            .text,
        isEmpty,
      );
      expect(reference.loads, 1);
      expect(inventory.saves, 0);
      expect(inventory.receivedCommands, isEmpty);
      expect(inventory.products.single.listPriceMinor, 777);
      expect(inventory.stock.single.quantity, 9);
      expect(reference.value!.products, hasLength(2));
      expect(reference.value!.products.last.quantity, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reference pagination and search never include out of stock rows', (
    tester,
  ) async {
    final inventory = _inventory();
    final reference = _FakeReferenceStore()
      ..value = _reference(
        products: List.generate(
          18,
          (index) => ReferenceInventoryProduct(
            id: 'reference-$index',
            name: 'Referencia ${index.toString().padLeft(2, '0')}',
            quantity: index == 0 ? 0 : 1,
            priceMinor: 100,
            purchasePriceMinor: 50,
          ),
        ),
      );
    await open(
      tester,
      inventory,
      reference: reference,
      size: const Size(1100, 1600),
    );
    await tester.ensureVisible(find.byTooltip('Página siguiente'));
    await tester.tap(find.byTooltip('Página siguiente'));
    await tester.pumpAndSettle();
    expect(find.text('Referencia 17'), findsOneWidget);
    expect(find.text('Referencia 00'), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('catalog-search')));
    await tester.enterText(
      find.byKey(const Key('catalog-search')),
      'Referencia 01',
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(DataTable),
        matching: find.text('Referencia 01'),
      ),
      findsOneWidget,
    );
    expect(find.text('Agotado'), findsNothing);
    expect(find.text('1–1 de 1'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('catalog-search')),
      'Referencia 00',
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'No hay productos con existencias que coincidan con la búsqueda y los filtros.',
      ),
      findsOneWidget,
    );
    expect(reference.loads, 1);
    expect(inventory.saves, 0);
    expect(reference.value!.products, hasLength(18));
    expect(reference.value!.products.first.quantity, 0);
  });

  testWidgets('corrupt reference is an explicit error and retry restores it', (
    tester,
  ) async {
    final inventory = _inventory();
    final reference = _FakeReferenceStore()
      ..failure = const FormatException('synthetic invalid data');
    await open(tester, inventory, reference: reference);
    expect(
      find.textContaining('No se pudo leer el inventario de la copia'),
      findsOneWidget,
    );
    expect(find.text('Producto de esta app'), findsOneWidget);
    expect(find.byKey(const Key('catalog-source')), findsNothing);
    expect(find.textContaining('no contiene productos'), findsNothing);
    reference
      ..failure = null
      ..value = _reference();
    await tester.tap(find.widgetWithText(TextButton, 'Actualizar'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No se pudo leer el inventario de la copia'),
      findsNothing,
    );
    expect(find.text('Producto de la copia'), findsOneWidget);
    expect(reference.loads, 2);
    expect(inventory.saves, 0);
    expect(inventory.receivedCommands, isEmpty);
  });

  testWidgets('loading reference is visible and refresh reloads both sources', (
    tester,
  ) async {
    final inventory = _inventory();
    final reference = _FakeReferenceStore()
      ..gate = Completer<ReferenceInventory?>();
    await open(tester, inventory, reference: reference, settle: false);
    expect(find.text('Cargando inventario de la copia…'), findsOneWidget);
    expect(find.text('Producto de esta app'), findsOneWidget);
    reference.gate!.complete(_reference());
    await tester.pumpAndSettle();
    await selectSource(tester, 'Catálogo de esta app');
    inventory.products.add(
      const CatalogProduct(
        id: 'app-2',
        name: 'Nuevo en esta app',
        listPriceMinor: 200,
      ),
    );
    inventory.stock.add(
      const StockPosition(productId: 'app-2', quantity: 1, totalCostMinor: 100),
    );
    reference
      ..gate = null
      ..value = _reference(
        products: const [
          ReferenceInventoryProduct(
            id: 'new-reference',
            name: 'Corte actualizado',
            quantity: 4,
            priceMinor: 200,
            purchasePriceMinor: 100,
          ),
        ],
      );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Actualizar'));
    await tester.pumpAndSettle();
    expect(find.text('Nuevo en esta app'), findsOneWidget);
    expect(reference.loads, 2);
    await selectSource(tester, 'Inventario de la copia');
    expect(find.text('Corte actualizado'), findsOneWidget);
    expect(find.text('Producto de la copia'), findsNothing);
    expect(inventory.saves, 0);
  });

  testWidgets('reference catalog fits a narrow window', (tester) async {
    final inventory = _inventory();
    final reference = _FakeReferenceStore()..value = _reference();
    await open(
      tester,
      inventory,
      reference: reference,
      size: const Size(400, 900),
    );
    expect(find.byKey(const Key('catalog-source')), findsOneWidget);
    expect(find.text('Producto de la copia'), findsOneWidget);
    expect(find.byType(DataTable), findsOneWidget);
    await tester.enterText(find.byKey(const Key('catalog-search')), 'agotado');
    await tester.pumpAndSettle();
    expect(find.text('Producto agotado'), findsNothing);
    expect(find.text('Producto de la copia'), findsNothing);
    expect(
      find.textContaining('No hay productos con existencias que coincidan'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('catalog-all-products')));
    await tester.pumpAndSettle();
    expect(find.text('Producto de la copia'), findsOneWidget);
    expect(find.text('Producto agotado'), findsNothing);
    expect(inventory.saves, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reference category and supplier filters combine without exposing exhausted products',
    (tester) async {
      final inventory = _inventory();
      final reference = _FakeReferenceStore()
        ..value = _reference(
          products: const [
            ReferenceInventoryProduct(
              id: 'water',
              name: 'Agua de referencia',
              quantity: 3,
              priceMinor: 0,
              purchasePriceMinor: 0,
              category: 'Bebidas',
              supplier: 'Distribuidora A',
            ),
            ReferenceInventoryProduct(
              id: 'snack',
              name: 'Snack de referencia',
              quantity: 2,
              priceMinor: 200,
              purchasePriceMinor: 100,
              category: 'Comestible',
              supplier: 'Distribuidora A',
            ),
            ReferenceInventoryProduct(
              id: 'game',
              name: 'Juego de referencia',
              quantity: 1,
              priceMinor: 500,
              purchasePriceMinor: 300,
              category: 'Artículo',
              supplier: 'Distribuidora B',
            ),
            ReferenceInventoryProduct(
              id: 'drink',
              name: 'Bebida de referencia',
              quantity: 4,
              priceMinor: 300,
              purchasePriceMinor: 200,
              category: 'Bebidas',
              supplier: 'Distribuidora B',
            ),
            ReferenceInventoryProduct(
              id: 'empty',
              name: 'Agotado de referencia',
              quantity: 0,
              priceMinor: 100,
              purchasePriceMinor: 50,
              category: 'Bebidas',
              supplier: 'Distribuidora A',
            ),
          ],
        );
      await open(tester, inventory, reference: reference);
      expect(find.text('Buscar por nombre'), findsOneWidget);
      expect(find.text('Buscar por nombre o lote'), findsNothing);
      expect(find.textContaining('Lote:'), findsNothing);
      expect(
        find.text('La copia no contiene categorías ni proveedores.'),
        findsNothing,
      );
      expect(find.text('4 productos con existencias'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DataTable),
          matching: find.text('Distribuidora A'),
        ),
        findsNWidgets(2),
      );
      expect(
        find.descendant(
          of: find.byType(DataTable),
          matching: find.text('Distribuidora B'),
        ),
        findsNWidgets(2),
      );
      expect(find.text('Agotado de referencia'), findsNothing);
      expect(find.text('COP 0,00'), findsOneWidget);
      await tester.tap(find.byKey(const Key('catalog-category-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bebidas').last);
      await tester.pumpAndSettle();
      expect(find.text('Agua de referencia'), findsOneWidget);
      expect(find.text('Bebida de referencia'), findsOneWidget);
      expect(find.text('Snack de referencia'), findsNothing);
      expect(find.text('Juego de referencia'), findsNothing);
      expect(find.text('Agotado de referencia'), findsNothing);
      expect(find.text('2 productos con existencias'), findsOneWidget);
      await tester.tap(find.byKey(const Key('catalog-supplier-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Distribuidora A').last);
      await tester.pumpAndSettle();
      expect(find.text('Agua de referencia'), findsOneWidget);
      expect(find.text('Bebida de referencia'), findsNothing);
      expect(find.text('Snack de referencia'), findsNothing);
      expect(find.text('Agotado de referencia'), findsNothing);
      expect(find.text('1 producto con existencias'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('catalog-search')),
        'Agotado',
      );
      await tester.pumpAndSettle();
      expect(find.byType(DataTable), findsNothing);
      expect(find.text('Agotado de referencia'), findsNothing);
      await tester.tap(find.byKey(const Key('catalog-all-products')));
      await tester.pumpAndSettle();
      expect(find.text('4 productos con existencias'), findsOneWidget);
      expect(find.text('Agotado de referencia'), findsNothing);
      await selectSource(tester, 'Catálogo de esta app');
      expect(find.text('Producto de esta app'), findsOneWidget);
      expect(
        tester
            .widget<DropdownButton<String>>(
              find.byKey(const Key('catalog-category-filter')),
            )
            .value,
        '',
      );
      expect(
        tester
            .widget<DropdownButton<String>>(
              find.byKey(const Key('catalog-supplier-filter')),
            )
            .value,
        '',
      );
      expect(reference.value!.products, hasLength(5));
      expect(reference.value!.products.last.quantity, 0);
      expect(inventory.saves, 0);
      expect(inventory.receivedCommands, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an entirely exhausted reference remains intact and explains the empty list',
    (tester) async {
      final inventory = _inventory();
      final reference = _FakeReferenceStore()
        ..value = _reference(
          products: const [
            ReferenceInventoryProduct(
              id: 'empty',
              name: 'Producto agotado',
              quantity: 0,
              priceMinor: 100,
              purchasePriceMinor: 50,
            ),
          ],
        );
      await open(tester, inventory, reference: reference);
      expect(find.text('Producto agotado'), findsNothing);
      expect(find.byType(DataTable), findsNothing);
      expect(
        find.text('No hay productos con existencias en la copia.'),
        findsOneWidget,
      );
      expect(
        find.text(
          '1 registro en la copia · 0 unidades. Solo se muestran productos con existencias.',
        ),
        findsOneWidget,
      );
      expect(reference.value!.products.single.name, 'Producto agotado');
      expect(reference.value!.products.single.quantity, 0);
      expect(inventory.saves, 0);
    },
  );

  testWidgets(
    'workspace injects the reference into Catalog without changing Sales',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final inventory = _inventory();
      final reference = _FakeReferenceStore()..value = _reference();
      final quickSales = FakeQuickSalesStore();
      final quickProductIds = quickSales.products
          .map((product) => product.id)
          .toList();
      final workspace = FakeWorkspaceStore()
        ..profile = BusinessProfile(
          profileId: 'synthetic',
          businessName: 'Ludoteca sintética',
          currencyCode: 'COP',
          moneyScale: 0,
          timezone: 'America/Bogota',
          createdAtUtc: DateTime.utc(2026, 10, 20),
        );
      final controller = WorkspaceController(
        openSession: () async => WorkspaceSession(
          store: workspace,
          databasePath: 'synthetic/sanctum2.sqlite3',
          profileId: 'synthetic',
          inventoryStore: inventory,
          referenceInventoryStore: reference,
          quickSalesStore: quickSales,
        ),
      );
      await controller.initialize();
      await tester.pumpWidget(SanctumApp(controller: controller));
      await tester.pumpAndSettle();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      });
      await tester.tap(find.text('Catálogo'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('catalog-source')), findsOneWidget);
      expect(find.text('Producto de la copia'), findsOneWidget);
      expect(find.text('COP 12,34'), findsOneWidget);
      await tester.tap(find.text('Ventas'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('catalog-source')), findsNothing);
      expect(find.text('Producto de la copia'), findsNothing);
      expect(quickSales.products.map((product) => product.id), quickProductIds);
      expect(quickSales.savedInputs, isEmpty);
      expect(quickSales.preparedIds, isEmpty);
      expect(quickSales.confirmedIds, isEmpty);
      expect(inventory.saves, 0);
      expect(inventory.receivedCommands, isEmpty);
      expect(inventory.stock.single.quantity, 9);
      expect(workspace.saves, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
