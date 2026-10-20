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
      await open(
        tester,
        FakeInventoryStore(),
        configured: false,
        size: const Size(400, 900),
      );
      await tester.tap(find.text('Catálogo'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Primero configura tu espacio'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('catalog-create')), findsNothing);
      await tester.tap(find.text('Compras'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Primero configura tu espacio'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('receive-purchase')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'catalog filters are read only and search resets when changing lists',
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
        ])
        ..stock.add(
          const StockPosition(
            productId: 'water',
            quantity: 10,
            totalCostMinor: 1200000,
          ),
        );
      await open(tester, store);
      await tester.tap(find.text('Catálogo'));
      await tester.pumpAndSettle();
      expect(find.text('Agua sintética'), findsOneWidget);
      expect(find.text('Juego sintético'), findsOneWidget);
      expect(find.text('PVP'), findsOneWidget);
      expect(find.text('Unidades'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(find.text('Acciones'), findsNothing);
      expect(find.text('Valoración'), findsNothing);
      expect(find.byKey(const Key('catalog-create')), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.text('Archivar'), findsNothing);
      expect(find.text('Reactivar'), findsNothing);
      await capture(tester, 'catalog-readonly');

      await tester.enterText(
        find.byKey(const Key('catalog-search')),
        'SYN-AGUA',
      );
      await tester.pumpAndSettle();
      expect(find.text('Agua sintética'), findsOneWidget);
      expect(find.text('Juego sintético'), findsNothing);
      await tester.tap(find.text('Categorías'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('catalog-search')))
            .controller!
            .text,
        isEmpty,
      );
      expect(find.text('Comestible'), findsOneWidget);
      expect(find.text('Artículo'), findsOneWidget);
      expect(find.text('Evento'), findsOneWidget);
      expect(find.text('Agua sintética'), findsNothing);
      expect(find.byKey(const Key('catalog-create')), findsNothing);
      await tester.enterText(find.byKey(const Key('catalog-search')), 'evento');
      await tester.pumpAndSettle();
      expect(find.text('Evento'), findsOneWidget);
      expect(find.text('Comestible'), findsNothing);
      await tester.tap(find.text('Proveedores'));
      await tester.pumpAndSettle();
      expect(find.text('Proveedor sintético'), findsOneWidget);
      expect(find.text('Proveedor anterior'), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.text('Archivar'), findsNothing);
      expect(find.text('Reactivar'), findsNothing);
      await tester.enterText(
        find.byKey(const Key('catalog-search')),
        'anterior',
      );
      await tester.pumpAndSettle();
      expect(find.text('Proveedor sintético'), findsNothing);
      expect(find.text('Proveedor anterior'), findsOneWidget);
      expect(store.saves, 0);
      expect(store.stock.single.quantity, 10);
      expect(store.products.last.isActive, isFalse);
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
      );
    await open(tester, store, size: const Size(400, 900));
    await tester.tap(find.text('Catálogo'));
    await tester.pumpAndSettle();
    expect(find.text('Juego sintético'), findsOneWidget);
    await capture(tester, 'inventory-catalog');
    expect(tester.takeException(), isNull);
  });
}
