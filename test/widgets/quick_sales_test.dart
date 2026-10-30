import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/application/quick_sales_controller.dart';
import 'package:valinor_sanctum_2/features/quick_sales/presentation/quick_sales_page.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';

import '../support/fake_quick_sales_store.dart';

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
      for (final file in family.value) {
        loader.addFont(
          Future.value(
            ByteData.sublistView(await File(p.join(fonts, file)).readAsBytes()),
          ),
        );
      }
      await loader.load();
    }
  });

  late FakeQuickSalesStore store;
  late QuickSalesController controller;
  setUp(() {
    store = FakeQuickSalesStore();
    controller = QuickSalesController(store: store);
  });
  tearDown(() => controller.dispose());

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(1120, 1000),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await controller.load();
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('quick-preview'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF183D35),
            ),
            scaffoldBackgroundColor: const Color(0xFFF5F5F0),
            inputDecorationTheme: const InputDecorationTheme(
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white,
            ),
            cardTheme: const CardThemeData(elevation: 0, color: Colors.white),
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: QuickSalesPage(
                controller: controller,
                profile: BusinessProfile(
                  profileId: 'test',
                  businessName: 'Ludoteca sintética',
                  currencyCode: 'COP',
                  moneyScale: 2,
                  timezone: 'America/Bogota',
                  createdAtUtc: DateTime.utc(2026, 10, 19),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async => tester.pumpWidget(const SizedBox()));
  }

  Finder keyed(String prefix) => find.byWidgetPredicate(
    (widget) =>
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith(prefix),
  );

  testWidgets(
    'adding first preserves the older account editor and its entered data',
    (tester) async {
      await open(tester);
      final old = controller.addAccount()!;
      await tester.pumpAndSettle();
      final oldField = find.byKey(ValueKey('quick-label-$old'));
      await tester.enterText(oldField, 'Cuenta conservada');
      await tester.pumpAndSettle();
      final before = tester.element(oldField);
      final newer = controller.addAccount()!;
      await tester.pumpAndSettle();
      expect(controller.accounts.map((a) => a.id), [newer, old]);
      expect(identical(tester.element(oldField), before), isTrue);
      expect(controller.accounts.last.label, 'Cuenta conservada');
      final newCard = find.byKey(ValueKey('quick-account-position-$newer'));
      final oldCard = find.byKey(ValueKey('quick-account-position-$old'));
      expect(
        tester.getTopLeft(newCard).dy,
        lessThan(tester.getTopLeft(oldCard).dy),
      );
      expect(await controller.flushAll(), isTrue);
      await tester.pumpAndSettle();
    },
  );

  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, Finder target, String text) async {
    await tester.ensureVisible(target);
    await tester.enterText(target, text);
    await tester.pumpAndSettle();
  }

  Future<void> select(WidgetTester tester, int row, String product) async {
    await enter(tester, keyed('quick-product-').at(row), product);
    await tap(tester, find.text(product).last);
  }

  Future<void> capture(WidgetTester tester) async {
    if (!const bool.fromEnvironment('SANCTUM_CAPTURE_QUICK_SALES_PREVIEW')) {
      return;
    }
    await tester.binding.setSurfaceSize(const Size(1120, 1300));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Ventas'));
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('quick-preview')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final path = p.join(
        AppConfig.repositoryRootPath,
        'docs',
        'images',
        'quick-sales.png',
      );
      await File(path).parent.create(recursive: true);
      await File(path).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'product suggestions show exact stock, hide exhausted items, and retain unlimited services and events',
    (tester) async {
      final water = store.products.first;
      store.products
        ..clear()
        ..addAll([
          water,
          const CatalogProduct(
            id: 'pass',
            name: 'Pasadía',
            listPriceMinor: 5000,
            isService: true,
          ),
          const CatalogProduct(
            id: 'event',
            name: 'Liga sintética',
            listPriceMinor: 10000,
            isEvent: true,
          ),
          const CatalogProduct(
            id: 'zero',
            name: 'Producto agotado',
            sku: 'AGOTADO-SKU',
            listPriceMinor: 500,
          ),
          const CatalogProduct(
            id: 'missing',
            name: 'Sin ingreso',
            listPriceMinor: 500,
          ),
          const CatalogProduct(
            id: 'inactive',
            name: 'Archivado',
            listPriceMinor: 500,
            isActive: false,
          ),
          const CatalogProduct(
            id: 'closed-event',
            name: 'Evento cerrado',
            listPriceMinor: 500,
            isEvent: true,
            isActive: false,
          ),
        ]);
      store.stock
        ..clear()
        ..addAll(const [
          StockPosition(productId: 'water', quantity: 1234, totalCostMinor: 0),
          StockPosition(productId: 'zero', quantity: 0, totalCostMinor: 0),
          StockPosition(productId: 'inactive', quantity: 3, totalCostMinor: 0),
          StockPosition(
            productId: 'closed-event',
            quantity: 5,
            totalCostMinor: 0,
          ),
        ]);
      await open(tester);
      await tap(tester, find.byKey(const Key('quick-new-account')));
      await tap(tester, keyed('quick-product-'));
      expect(find.text('AGUA · Unidades: 1.234'), findsOneWidget);
      expect(find.text('Ilimitado'), findsNWidgets(2));
      for (final name in [
        'Producto agotado',
        'Sin ingreso',
        'Archivado',
        'Evento cerrado',
      ]) {
        expect(find.text(name), findsNothing);
      }
      await enter(tester, keyed('quick-product-'), 'AGOTADO-SKU');
      expect(find.text('Producto agotado'), findsNothing);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(controller.accounts.single.lines.single.productId, isNull);
      await select(tester, 0, 'Agua sintética');
      expect(find.textContaining('Stock 1.234'), findsOneWidget);
      await controller.flushAll();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'refresh removes stale exhausted options and keeps saved draft lines for correction',
    (tester) async {
      await open(tester);
      await tap(tester, find.byKey(const Key('quick-new-account')));
      await enter(tester, keyed('quick-product-'), 'Agua');
      expect(find.text('Agua sintética'), findsOneWidget);
      store.stock.removeWhere((p) => p.productId == 'water');
      await controller.load();
      await tester.pumpAndSettle();
      expect(find.text('Agua sintética'), findsNothing);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(controller.accounts.single.lines.single.productId, isNull);
      store.stock.add(
        const StockPosition(productId: 'water', quantity: 2, totalCostMinor: 0),
      );
      await controller.load();
      await tester.pumpAndSettle();
      await enter(tester, keyed('quick-product-'), 'AGUA');
      await tap(tester, find.text('Agua sintética').last);
      await controller.flushAll();
      store.stock.removeWhere((p) => p.productId == 'water');
      await controller.load();
      await tester.pumpAndSettle();
      expect(controller.accounts.single.lines.single.productId, 'water');
      expect(find.textContaining('Stock 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'all available product suggestions can be reached beyond the first twenty five',
    (tester) async {
      for (var i = 1; i <= 30; i++) {
        store.products.add(
          CatalogProduct(
            id: 'p$i',
            name: 'Producto sintético $i',
            listPriceMinor: 100,
          ),
        );
        store.stock.add(
          StockPosition(productId: 'p$i', quantity: i, totalCostMinor: 0),
        );
      }
      await open(tester);
      await tap(tester, find.byKey(const Key('quick-new-account')));
      await tap(tester, keyed('quick-product-'));
      await tester.scrollUntilVisible(
        find.text('Producto sintético 30'),
        150,
        scrollable: find
            .descendant(
              of: keyed('quick-options-'),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Unidades: 30'), findsOneWidget);
      await tap(tester, find.text('Producto sintético 30'));
      expect(controller.accounts.single.lines.single.productId, 'p30');
      await controller.flushAll();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty stock points to Compras instead of offering unavailable products',
    (tester) async {
      store.stock.clear();
      await open(tester);
      expect(
        find.text(
          'No hay productos disponibles. Ingresa o repón mercancía desde Compras.',
        ),
        findsOneWidget,
      );
      await tap(tester, find.byKey(const Key('quick-new-account')));
      await enter(tester, keyed('quick-product-'), 'Agua');
      expect(find.text('Agua sintética'), findsNothing);
      expect(store.sales, isEmpty);
    },
  );

  testWidgets(
    'grouped quantity autosaves canonical digits and survives refresh',
    (tester) async {
      await open(tester);
      await tap(tester, find.byKey(const Key('quick-new-account')));
      await select(tester, 0, 'Agua sintética');
      await enter(tester, keyed('quick-quantity-').first, '1000');
      expect(
        tester
            .widget<TextField>(keyed('quick-quantity-').first)
            .controller!
            .text,
        '1.000',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(store.accounts.single.lines.single.quantityText, '1000');
      await tap(tester, find.byKey(const Key('quick-refresh')));
      expect(
        tester
            .widget<TextField>(keyed('quick-quantity-').first)
            .controller!
            .text,
        '1.000',
      );
      expect(controller.accounts.single.lines.single.quantityText, '1000');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'several accounts use one payment each and register while keeping other cards',
    (tester) async {
      await open(tester);
      await tap(tester, find.byKey(const Key('quick-new-account')));
      await tap(tester, find.byKey(const Key('quick-new-account')));
      expect(keyed('quick-card-'), findsNWidgets(2));
      await select(tester, 0, 'Agua sintética');
      await enter(tester, keyed('quick-quantity-').first, '2');
      await tap(tester, keyed('quick-add-line-').first);
      await select(tester, 1, 'Snack sintético');
      await tap(tester, keyed('quick-account-payment-').first);
      await tap(tester, find.text('Transferencia').last);
      await select(tester, 2, 'Agua sintética');
      expect(
        controller.accounts.first.lines.map((line) => line.paymentOptionId),
        ['nequi', 'nequi'],
      );
      expect(
        tester.widget<Text>(keyed('quick-total-').first).data,
        'COP 8.000,00',
      );
      expect(find.text('Transferencia'), findsOneWidget);
      await capture(tester);
      await tap(tester, keyed('quick-register-').first);
      expect(store.sales, hasLength(1));
      expect(store.sales.single.lines.map((line) => line.paymentLabel), [
        'Nequi',
        'Nequi',
      ]);
      expect(store.sales.single.result.totalMinor, 800000);
      expect(controller.accounts, hasLength(1));
      expect(controller.accounts.single.label, 'Cuenta 1');
      expect(controller.accounts.single.lines.single.productId, 'water');
      expect(find.text('Cliente de la cuenta por cobrar'), findsNothing);
      expect(find.text('Confirmar entrega'), findsNothing);
      await tap(tester, find.byKey(const Key('quick-history')));
      expect(
        find.textContaining('Snack sintético · Transferencia'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'typing after selection clears stale product identity before autosaving',
    (tester) async {
      await open(tester);
      await tap(tester, find.byKey(const Key('quick-new-account')));
      await select(tester, 0, 'Agua sintética');
      expect(controller.accounts.single.lines.single.productId, 'water');
      await enter(tester, keyed('quick-product-').first, 'Snack');
      expect(controller.accounts.single.lines.single.productId, isNull);
      expect(controller.accounts.single.lines.single.unitPriceMinor, isNull);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(store.accounts.single.lines.single.productId, isNull);
      await tap(tester, keyed('quick-register-').first);
      expect(store.sales, isEmpty);
      expect(
        find.textContaining('Elige productos y cantidades válidas'),
        findsOneWidget,
      );
    },
  );

  testWidgets('SKU search can select with Enter and moves to quantity', (
    tester,
  ) async {
    await open(tester);
    await tap(tester, find.byKey(const Key('quick-new-account')));
    await enter(tester, keyed('quick-product-').first, 'AGUA');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(controller.accounts.single.lines.single.productId, 'water');
    expect(
      tester
          .widget<TextField>(keyed('quick-quantity-').first)
          .focusNode!
          .hasFocus,
      isTrue,
    );
    await enter(tester, keyed('quick-quantity-').first, '3');
    await tap(tester, keyed('quick-register-').first);
    expect(store.sales.single.result.totalMinor, 900000);
  });

  testWidgets(
    'partial drafts autosave without a save button and reload preserves unsaved edits',
    (tester) async {
      await open(tester);
      await tap(tester, find.byKey(const Key('quick-new-account')));
      await enter(
        tester,
        keyed('quick-label-').first,
        'Mesa junto a la ventana',
      );
      await tap(tester, keyed('quick-add-line-').first);
      await enter(tester, keyed('quick-quantity-').at(1), '');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(store.accounts.single.label, 'Mesa junto a la ventana');
      expect(store.accounts.single.lines.last.quantityText, '');
      expect(store.accounts.single.lines, hasLength(2));
      expect(find.text('Guardar cuenta'), findsNothing);
      await enter(tester, keyed('quick-label-').first, 'Cambio todavía local');
      store.loadFailure = StateError('load failed');
      await tap(tester, find.byKey(const Key('quick-refresh')));
      expect(controller.accounts.single.label, 'Cambio todavía local');
      expect(
        find.textContaining('Tus cuentas y cambios siguen aquí'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'uncertain card is locked independently and retries exact operation',
    (tester) async {
      await open(tester);
      await tap(tester, find.byKey(const Key('quick-new-account')));
      await select(tester, 0, 'Agua sintética');
      store.confirmationFailure = StateError('lost response');
      await tap(tester, keyed('quick-register-').first);
      final firstCommand = store.preparedIds.single;
      expect(keyed('quick-retry-'), findsOneWidget);
      expect(
        tester.widget<TextField>(keyed('quick-product-').first).enabled,
        isFalse,
      );
      await tap(tester, find.byKey(const Key('quick-new-account')));
      await enter(tester, keyed('quick-label-').first, 'Cuenta disponible');
      expect(controller.accounts.first.label, 'Cuenta disponible');
      store.confirmationFailure = null;
      await tap(tester, keyed('quick-retry-').first);
      expect(store.confirmedIds.toSet(), {firstCommand});
      expect(store.sales, hasLength(1));
      expect(controller.accounts.single.label, 'Cuenta disponible');
    },
  );

  testWidgets('populated account needs confirmation before discarding', (
    tester,
  ) async {
    await open(tester);
    await tap(tester, find.byKey(const Key('quick-new-account')));
    await select(tester, 0, 'Agua sintética');
    await tap(tester, keyed('quick-remove-account-').first);
    expect(find.text('¿Quitar esta cuenta?'), findsOneWidget);
    await tap(tester, find.text('Volver'));
    expect(controller.accounts, hasLength(1));
    await tap(tester, keyed('quick-remove-account-').first);
    await tap(tester, find.text('Quitar cuenta').last);
    expect(controller.accounts, isEmpty);
    expect(store.sales, isEmpty);
  });

  testWidgets(
    '400px layout supports several lines and one account payment without overflow',
    (tester) async {
      await open(tester, size: const Size(400, 900));
      await tap(tester, find.byKey(const Key('quick-new-account')));
      await select(tester, 0, 'Agua sintética');
      await tap(tester, keyed('quick-add-line-').first);
      await select(tester, 1, 'Snack sintético');
      await tap(tester, keyed('quick-account-payment-').first);
      await tap(tester, find.text('Transferencia').last);
      expect(tester.takeException(), isNull);
      await tap(tester, keyed('quick-register-').first);
      expect(store.sales.single.lines, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );
}
