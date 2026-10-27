import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:valinor_sanctum_2/app/sanctum_app.dart';
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/workspace/application/workspace_controller.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/workspace_store.dart';

import '../support/fake_inventory_store.dart';
import '../support/fake_workspace_store.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final fonts = p.join(
      AppConfig.repositoryRootPath,
      '.tooling',
      'flutter',
      'bin',
      'cache',
      'artifacts',
      'material_fonts',
    );
    for (final family in {
      'Roboto': ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf'],
      'MaterialIcons': ['materialicons-regular.otf'],
    }.entries) {
      final loader = FontLoader(family.key);
      for (final name in family.value) {
        final bytes = await File(p.join(fonts, name)).readAsBytes();
        loader.addFont(Future.value(ByteData.sublistView(bytes)));
      }
      await loader.load();
    }
  });

  Future<WorkspaceController> open(
    WidgetTester tester,
    FakeInventoryStore inventory, {
    bool configured = true,
    Size size = const Size(1280, 960),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final workspace = FakeWorkspaceStore();
    if (configured) {
      workspace.profile = BusinessProfile(
        profileId: 'test',
        businessName: 'Ludoteca sintética',
        currencyCode: 'COP',
        moneyScale: 2,
        timezone: 'America/Bogota',
        createdAtUtc: DateTime.utc(2026, 10, 19),
      );
    }
    final controller = WorkspaceController(
      openSession: () async => WorkspaceSession(
        store: workspace,
        databasePath: 'perfil-sintetico/sanctum2.sqlite3',
        profileId: 'test',
        inventoryStore: inventory,
      ),
    );
    await controller.initialize();
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('inventory-preview'),
        child: SanctumApp(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
    return controller;
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('SANCTUM_CAPTURE_INVENTORY_PREVIEW')) {
      return;
    }
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('inventory-preview')),
    );
    final output = File(
      p.join(AppConfig.repositoryRootPath, 'tmp', 'preview', '$name.png'),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await output.parent.create(recursive: true);
      await output.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'catalog requires configured profile and narrow navigation is usable',
    (tester) async {
      final controller = await open(
        tester,
        FakeInventoryStore(),
        configured: false,
        size: const Size(400, 900),
      );
      expect(find.text('Catálogo'), findsNothing);
      expect(find.text('Compras'), findsNothing);
      expect(find.byKey(const Key('business-name')), findsOneWidget);
      expect(find.byKey(const Key('catalog-create')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('business-name')),
        'Ludoteca sintética',
      );
      await tester.tap(find.byKey(const Key('create-profile')));
      await tester.pumpAndSettle();
      expect(controller.profile!.moneyScale, 0);
      await tester.tap(find.text('Catálogo'));
      await tester.pumpAndSettle();
      expect(find.text('Catálogo'), findsNWidgets(2));
      await tester.tap(find.text('Compras'));
      await tester.pumpAndSettle();
      expect(find.text('Inicio'), findsNothing);
      expect(find.text('Sistema'), findsNothing);
      expect(find.byKey(const Key('receive-purchase')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'category and supplier selectors filter the same product table without writes',
    (tester) async {
      final store = FakeInventoryStore()
        ..categories.addAll(const [
          InventoryCategory(id: 'food', name: 'Comestible'),
          InventoryCategory(id: 'article', name: 'Artículo'),
          InventoryCategory(id: 'event', name: 'Evento'),
        ])
        ..suppliers.addAll(const [
          InventorySupplier(id: 'supplier', name: 'Proveedor sintético'),
          InventorySupplier(
            id: 'old-supplier',
            name: 'Proveedor anterior',
            isActive: false,
          ),
        ])
        ..products.addAll(const [
          CatalogProduct(
            id: 'water',
            name: 'Agua sintética',
            sku: 'SYN-AGUA',
            categoryId: 'food',
            listPriceMinor: 300000,
          ),
          CatalogProduct(
            id: 'game',
            name: 'Juego sintético',
            sku: 'SYN-JUEGO',
            categoryId: 'article',
            listPriceMinor: 500000,
            isActive: false,
          ),
          CatalogProduct(
            id: 'snack',
            name: 'Snack sintético',
            sku: 'SYN-SNACK',
            categoryId: 'food',
            listPriceMinor: 200000,
          ),
          CatalogProduct(
            id: 'empty',
            name: 'Producto agotado',
            sku: 'SYN-AGOTADO',
            categoryId: 'food',
            listPriceMinor: 200000,
          ),
          CatalogProduct(
            id: 'no-stock',
            name: 'Producto sin registro de existencias',
            categoryId: 'food',
            listPriceMinor: 200000,
          ),
        ])
        ..stock.addAll(const [
          StockPosition(
            productId: 'water',
            quantity: 10,
            totalCostMinor: 1200000,
          ),
          StockPosition(productId: 'game', quantity: 3, totalCostMinor: 600000),
          StockPosition(
            productId: 'snack',
            quantity: 2,
            totalCostMinor: 200000,
          ),
          StockPosition(productId: 'empty', quantity: 0, totalCostMinor: 0),
        ])
        ..productSupplierIds.addAll({
          'water': ['supplier'],
          'game': ['old-supplier', 'supplier'],
          'snack': ['old-supplier'],
          'empty': ['old-supplier'],
          'no-stock': ['old-supplier'],
        });
      await open(tester, store);
      await tester.tap(find.text('Catálogo'));
      await tester.pumpAndSettle();
      expect(find.text('Agua sintética'), findsOneWidget);
      expect(find.text('Juego sintético'), findsOneWidget);
      expect(find.text('Producto agotado'), findsNothing);
      expect(find.text('Producto sin registro de existencias'), findsNothing);
      expect(find.text('3 productos con existencias'), findsOneWidget);
      expect(find.text('PVP'), findsOneWidget);
      expect(find.text('Unidades'), findsOneWidget);
      final table = tester.widget<DataTable>(find.byType(DataTable));
      expect(table.columns.map((column) => (column.label as Text).data), [
        'Producto',
        'PVP',
        'Unidades',
        'Proveedor',
      ]);
      expect(
        find.text('Proveedor anterior, Proveedor sintético'),
        findsOneWidget,
      );
      expect(find.text('Estado'), findsNothing);
      expect(find.text('10'), findsOneWidget);
      expect(find.text('Acciones'), findsNothing);
      expect(find.text('Valoración'), findsNothing);
      expect(find.byKey(const Key('catalog-create')), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.text('Archivar'), findsNothing);
      expect(find.text('Reactivar'), findsNothing);
      await capture(tester, 'catalog-filters');

      await tester.enterText(
        find.byKey(const Key('catalog-search')),
        'SYN-AGUA',
      );
      await tester.pumpAndSettle();
      expect(find.text('Agua sintética'), findsOneWidget);
      expect(find.text('Juego sintético'), findsNothing);
      await tester.tap(find.byKey(const Key('catalog-all-products')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('catalog-search')))
            .controller!
            .text,
        isEmpty,
      );
      expect(find.text('Agua sintética'), findsOneWidget);
      expect(find.text('Juego sintético'), findsOneWidget);
      expect(find.text('Snack sintético'), findsOneWidget);
      expect(find.text('Producto agotado'), findsNothing);
      await tester.tap(find.byKey(const Key('catalog-category-filter')));
      await tester.pumpAndSettle();
      expect(find.text('Comestible'), findsWidgets);
      expect(find.text('Artículo'), findsWidgets);
      expect(find.text('Evento'), findsWidgets);
      await capture(tester, 'catalog-category-options');
      await tester.tap(find.text('Comestible').last);
      await tester.pumpAndSettle();
      expect(find.text('Agua sintética'), findsOneWidget);
      expect(find.text('Snack sintético'), findsOneWidget);
      expect(find.text('Juego sintético'), findsNothing);
      expect(find.text('Producto agotado'), findsNothing);
      expect(find.byKey(const Key('catalog-create')), findsNothing);
      await tester.tap(find.byKey(const Key('catalog-supplier-filter')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Proveedor sintético'), findsWidgets);
      expect(find.textContaining('Proveedor anterior'), findsWidgets);
      await tester.tap(find.textContaining('Proveedor anterior').last);
      await tester.pumpAndSettle();
      expect(find.text('Snack sintético'), findsOneWidget);
      expect(find.text('Agua sintética'), findsNothing);
      expect(find.text('Juego sintético'), findsNothing);
      await capture(tester, 'catalog-filtered');
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.text('Archivar'), findsNothing);
      expect(find.text('Reactivar'), findsNothing);
      await tester.enterText(
        find.byKey(const Key('catalog-search')),
        'SYN-JUEGO',
      );
      await tester.pumpAndSettle();
      expect(find.text('Snack sintético'), findsNothing);
      expect(find.text('Juego sintético'), findsNothing);
      expect(
        find.textContaining('No hay productos con existencias que coincidan'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('catalog-all-products')));
      await tester.pumpAndSettle();
      expect(find.text('Agua sintética'), findsOneWidget);
      expect(find.text('Juego sintético'), findsOneWidget);
      expect(find.text('Snack sintético'), findsOneWidget);
      expect(find.text('Producto agotado'), findsNothing);
      expect(find.text('Producto sin registro de existencias'), findsNothing);
      await tester.enterText(
        find.byKey(const Key('catalog-search')),
        'SYN-AGOTADO',
      );
      await tester.pumpAndSettle();
      expect(find.byType(DataTable), findsNothing);
      expect(find.text('Producto agotado'), findsNothing);
      expect(
        find.textContaining('No hay productos con existencias que coincidan'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('catalog-all-products')));
      await tester.pumpAndSettle();
      expect(find.text('3 productos con existencias'), findsOneWidget);
      expect(find.text('Producto agotado'), findsNothing);
      expect(store.saves, 0);
      expect(
        store.stock.singleWhere((stock) => stock.productId == 'water').quantity,
        10,
      );
      expect(
        store.stock.singleWhere((stock) => stock.productId == 'empty').quantity,
        0,
      );
      expect(store.products, hasLength(5));
      expect(
        store.products.singleWhere((p) => p.id == 'game').isActive,
        isFalse,
      );
      expect(store.suppliers.last.isActive, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('configured catalog fits a narrow window', (tester) async {
    final store = FakeInventoryStore()
      ..products.add(
        const CatalogProduct(
          id: 'product',
          name: 'Juego sintético',
          listPriceMinor: 1000,
        ),
      )
      ..stock.add(
        const StockPosition(
          productId: 'product',
          quantity: 1,
          totalCostMinor: 500,
        ),
      );
    await open(tester, store, size: const Size(400, 900));
    await tester.tap(find.text('Catálogo'));
    await tester.pumpAndSettle();
    expect(find.text('Juego sintético'), findsOneWidget);
    expect(find.text('Sin proveedor'), findsOneWidget);
    await capture(tester, 'inventory-catalog');
    expect(tester.takeException(), isNull);
  });
}
