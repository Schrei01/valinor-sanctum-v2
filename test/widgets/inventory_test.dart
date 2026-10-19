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

  Finder input(String prefix) => find.byWidgetPredicate(
    (widget) =>
        widget is TextFormField &&
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith(prefix),
  );

  Future<void> select(WidgetTester tester, Finder field, String value) async {
    await tester.ensureVisible(field);
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.text(value).last);
    await tester.pumpAndSettle();
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
    'catalog retains product and category IDs and form after failed save',
    (tester) async {
      final store = FakeInventoryStore()
        ..saveFailure = StateError('unknown save result');
      await open(tester, store);
      await tester.tap(find.text('Catálogo'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('catalog-create')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('product-price')))
            .controller!
            .text,
        isEmpty,
      );
      await tester.enterText(
        find.byKey(const Key('product-name')),
        'Juego sintético',
      );
      await tester.enterText(find.byKey(const Key('product-sku')), 'SYN-01');
      await tester.enterText(
        find.byKey(const Key('product-price')),
        '12.345,67',
      );
      await tester.tap(find.text('Guardar producto'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('product-name')), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('product-price')))
            .controller!
            .text,
        '12.345,67',
      );
      final productId = store.savedProducts.single.id;
      store.saveFailure = null;
      await tester.tap(find.text('Guardar producto'));
      await tester.pumpAndSettle();
      expect(store.savedProducts.last.id, productId);
      expect(store.products.single.listPriceMinor, 1234567);
      expect(find.text('Juego sintético'), findsOneWidget);
      await tester.tap(find.text('Categorías'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('catalog-create')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('catalog-name')), 'Mesa');
      store.saveFailure = StateError('unknown category save result');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      final categoryId = store.savedCategoryIds.single;
      store.saveFailure = null;
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(store.savedCategoryIds.last, categoryId);
      expect(store.categories.single.name, 'Mesa');
      await tester.tap(find.text('Archivar'));
      await tester.pumpAndSettle();
      expect(store.categories.single.isActive, isFalse);
      await tester.tap(find.text('Reactivar'));
      await tester.pumpAndSettle();
      expect(store.categories.single.isActive, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'uncertain receipt survives navigation and retries same payload without duplicates',
    (tester) async {
      final store = FakeInventoryStore()
        ..products.add(
          const CatalogProduct(
            id: 'product',
            name: 'Juego sintético',
            listPriceMinor: 1000,
          ),
        )
        ..suppliers.add(
          const InventorySupplier(id: 'supplier', name: 'Proveedor sintético'),
        )
        ..receiveFailure = StateError('lost confirmation')
        ..commitBeforeReceiveFailure = true;
      await open(tester, store);
      await tester.tap(find.text('Compras'));
      await tester.pumpAndSettle();
      await select(
        tester,
        find.byKey(const ValueKey('receipt-supplier-0')),
        'Proveedor sintético',
      );
      await tester.enterText(
        find.byKey(const Key('receipt-reference')),
        'SYN-REC-001',
      );
      await tester.enterText(
        find.byKey(const Key('receipt-due')),
        '2099-12-31',
      );
      final productField = find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'receipt-product-',
            ),
      );
      await select(tester, productField, 'Juego sintético');
      await tester.enterText(input('receipt-quantity-'), '3');
      await tester.enterText(input('receipt-cost-'), '100,01');
      await tester.ensureVisible(find.byKey(const Key('receive-purchase')));
      await tester.tap(find.byKey(const Key('receive-purchase')));
      await tester.pumpAndSettle();
      expect(store.receipts, hasLength(1));
      expect(find.text('Reintentar la misma compra'), findsOneWidget);
      final original = store.receivedCommands.single;
      await tester.tap(find.text('Sistema'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Catálogo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inicio'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compras'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(input('receipt-cost-')).controller!.text,
        '100,01',
      );
      expect(
        tester.widget<TextFormField>(input('receipt-cost-')).enabled,
        isFalse,
      );
      expect(
        tester
            .widget<TextFormField>(input('receipt-quantity-'))
            .controller!
            .text,
        '3',
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('receipt-reference')))
            .controller!
            .text,
        'SYN-REC-001',
      );
      await tester.ensureVisible(find.byKey(const Key('receive-purchase')));
      await tester.tap(find.byKey(const Key('receive-purchase')));
      await tester.pumpAndSettle();
      expect(identical(store.receivedCommands.last, original), isTrue);
      expect(store.receipts, hasLength(1));
      expect(store.stock.single.quantity, 3);
      expect(store.stock.single.totalCostMinor, 10001);
      expect(
        tester.widget<TextFormField>(input('receipt-cost-')).controller!.text,
        isEmpty,
      );
      expect(find.byKey(const Key('receipt-confirmed')), findsOneWidget);
      await tester.ensureVisible(find.text('Ver productos (1)'));
      await tester.tap(find.text('Ver productos (1)'));
      await tester.pumpAndSettle();
      expect(
        find.text('Juego sintético · 3 unidades · Costo total: COP 100,01'),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.text('Juego sintético · 3 unidades · Costo total: COP 100,01'),
      );
      await capture(tester, 'inventory-purchases');
      await tester.tap(find.text('Catálogo'));
      await tester.pumpAndSettle();
      await capture(tester, 'inventory-catalog');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('configured catalog and receipt form fit a narrow window', (
    tester,
  ) async {
    final store = FakeInventoryStore()
      ..products.add(
        const CatalogProduct(
          id: 'product',
          name: 'Juego sintético',
          listPriceMinor: 1000,
        ),
      )
      ..suppliers.add(
        const InventorySupplier(id: 'supplier', name: 'Proveedor sintético'),
      );
    await open(tester, store, size: const Size(400, 900));
    await tester.tap(find.text('Catálogo'));
    await tester.pumpAndSettle();
    expect(find.text('Juego sintético'), findsOneWidget);
    await tester.tap(find.text('Compras'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('receive-purchase')));
    expect(tester.takeException(), isNull);
  });
}
