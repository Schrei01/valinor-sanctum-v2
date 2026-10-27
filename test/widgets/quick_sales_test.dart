import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
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
    'several accounts and payment rows register in one click while keeping other cards',
    (tester) async {
      await open(tester);
      await tap(tester, find.byKey(const Key('quick-new-account')));
      await tap(tester, find.byKey(const Key('quick-new-account')));
      expect(keyed('quick-card-'), findsNWidgets(2));
      await select(tester, 0, 'Agua sintética');
      await enter(tester, keyed('quick-quantity-').first, '2');
      await tap(tester, keyed('quick-add-line-').first);
      await select(tester, 1, 'Snack sintético');
      await tap(tester, keyed('quick-payment-').at(1));
      await tap(tester, find.text('Transferencia').last);
      await select(tester, 2, 'Agua sintética');
      expect(
        controller.accounts.first.lines.map((line) => line.paymentOptionId),
        ['cash', 'nequi'],
      );
      expect(
        tester.widget<Text>(keyed('quick-total-').first).data,
        'COP 8.000,00',
      );
      expect(
        find.textContaining('Transferencia: COP 2.000,00'),
        findsOneWidget,
      );
      await capture(tester);
      await tap(tester, keyed('quick-register-').first);
      expect(store.sales, hasLength(1));
      expect(store.sales.single.lines.map((line) => line.paymentLabel), [
        'Efectivo',
        'Nequi',
      ]);
      expect(store.sales.single.result.totalMinor, 800000);
      expect(controller.accounts, hasLength(1));
      expect(controller.accounts.single.label, 'Cuenta 2');
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
      await enter(tester, keyed('quick-label-').at(1), 'Cuenta disponible');
      expect(controller.accounts.last.label, 'Cuenta disponible');
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
    '400px layout supports several lines without overflow and keeps payments on each row',
    (tester) async {
      await open(tester, size: const Size(400, 900));
      await tap(tester, find.byKey(const Key('quick-new-account')));
      await select(tester, 0, 'Agua sintética');
      await tap(tester, keyed('quick-add-line-').first);
      await select(tester, 1, 'Snack sintético');
      await tap(tester, keyed('quick-payment-').at(1));
      await tap(tester, find.text('Transferencia').last);
      expect(tester.takeException(), isNull);
      await tap(tester, keyed('quick-register-').first);
      expect(store.sales.single.lines, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );
}
