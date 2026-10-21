import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/presentation/purchases_page.dart';
import 'package:valinor_sanctum_2/features/stock_intake/application/stock_intake_controller.dart';
import 'package:valinor_sanctum_2/features/stock_intake/domain/stock_intake_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';

import '../support/fake_stock_intake_store.dart';

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
  late FakeStockIntakeStore store;
  late StockIntakeController controller;
  setUp(() {
    store = FakeStockIntakeStore();
    controller = StockIntakeController(store: store);
  });
  tearDown(() => controller.dispose());

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(1120, 1100),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await controller.load();
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('intake-preview'),
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
              child: PurchasesPage(
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
  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, String key, String text) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.enterText(find.byKey(Key(key)), text);
    await tester.pumpAndSettle();
  }

  Future<void> category(WidgetTester tester, String text) async {
    await tap(tester, keyed('intake-category-'));
    await tap(tester, find.text(text).last);
  }

  Future<void> fill(WidgetTester tester) async {
    await enter(tester, 'intake-name', 'Agua sintética');
    await enter(tester, 'intake-sku', 'SYN-AGUA');
    await category(tester, 'Comestible');
    await enter(tester, 'intake-supplier', 'Proveedor sintético');
    await enter(tester, 'intake-cost', '1.234,50');
    await enter(tester, 'intake-pvp', '2.500,00');
    await enter(tester, 'intake-quantity', '3');
  }

  String value(WidgetTester tester, String key) =>
      tester.widget<TextFormField>(find.byKey(Key(key))).controller!.text;
  Future<void> capture(WidgetTester tester) async {
    if (!const bool.fromEnvironment('SANCTUM_CAPTURE_STOCK_INTAKE_PREVIEW')) {
      return;
    }
    await tester.ensureVisible(find.text('Compras'));
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('intake-preview')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final output = File(
        p.join(
          AppConfig.repositoryRootPath,
          'docs',
          'images',
          'stock-intake.png',
        ),
      );
      await output.parent.create(recursive: true);
      await output.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'one form creates product supplier stock and full payment with no credit fields',
    (tester) async {
      await open(tester);
      expect(find.text('Ingreso de productos'), findsOneWidget);
      expect(find.textContaining('Referencia'), findsNothing);
      expect(find.textContaining('Vencimiento'), findsNothing);
      expect(find.textContaining('crédito'), findsNothing);
      await fill(tester);
      expect(find.text('Total de compra: COP 3.703,50'), findsOneWidget);
      await tap(tester, keyed('intake-payment-'));
      await tap(tester, find.text('Transferencia').last);
      expect(find.text('Saldo disponible: COP 5.000,00'), findsOneWidget);
      await capture(tester);
      await tap(tester, find.byKey(const Key('intake-submit')));
      expect(store.preparedCommands, hasLength(1));
      expect(store.preparedCommands.single.paymentOptionId, 'nequi');
      expect(store.preparedCommands.single.unitPurchasePriceMinor, 123450);
      expect(store.entries.single.totalCostMinor, 370350);
      expect(store.stock.single.quantity, 3);
      expect(store.products.single.listPriceMinor, 250000);
      expect(find.text('Agua sintética · 3 unidades'), findsOneWidget);
      expect(find.text('Pagada · Nequi'), findsOneWidget);
      expect(value(tester, 'intake-name'), isEmpty);
      expect(value(tester, 'intake-quantity'), '1');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'selecting existing product prefills catalog and replenishes same identity',
    (tester) async {
      store.products.add(
        const CatalogProduct(
          id: 'water',
          name: 'Agua sintética',
          sku: 'WATER',
          categoryId: 'food',
          listPriceMinor: 250000,
        ),
      );
      store.stock.add(
        const StockPosition(
          productId: 'water',
          quantity: 2,
          totalCostMinor: 200000,
        ),
      );
      store.suppliers.add(
        const InventorySupplier(id: 'supplier', name: 'Proveedor sintético'),
      );
      store.productDefaults['water'] = const ProductIntakeDefaults(
        supplierId: 'supplier',
        supplierName: 'Proveedor sintético',
        unitPurchasePriceMinor: 100000,
      );
      await open(tester);
      await enter(tester, 'intake-name', 'WATER');
      await tap(tester, find.text('Agua sintética').last);
      expect(value(tester, 'intake-sku'), 'WATER');
      expect(value(tester, 'intake-pvp'), '2.500,00');
      expect(value(tester, 'intake-cost'), '1.000,00');
      expect(value(tester, 'intake-supplier'), 'Proveedor sintético');
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(keyed('intake-category-'))
            .initialValue,
        'food',
      );
      expect(find.text('Reponer producto · existencias: 2'), findsOneWidget);
      await enter(tester, 'intake-cost', '1.100');
      await enter(tester, 'intake-pvp', '2.600');
      await enter(tester, 'intake-quantity', '2');
      await controller.load();
      await tester.pumpAndSettle();
      expect(value(tester, 'intake-cost'), '1.100');
      expect(value(tester, 'intake-pvp'), '2.600');
      await tap(tester, find.byKey(const Key('intake-submit')));
      expect(store.preparedCommands.single.productId, 'water');
      expect(store.preparedCommands.single.expectedProduct!.sku, 'WATER');
      expect(store.preparedCommands.single.supplierId, 'supplier');
      expect(store.preparedCommands.single.unitPurchasePriceMinor, 110000);
      expect(store.preparedCommands.single.listPriceMinor, 260000);
      expect(store.stock.single.quantity, 4);
      expect(store.products, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'switching products clears stale supplier and cost but preserves quantity and payment',
    (tester) async {
      store.products.addAll([
        const CatalogProduct(
          id: 'known',
          name: 'Artículo conocido',
          sku: 'KNOWN',
          categoryId: 'item',
          listPriceMinor: 250000,
        ),
        const CatalogProduct(
          id: 'unknown',
          name: 'Artículo sin ingreso previo',
          listPriceMinor: 150000,
        ),
      ]);
      store.suppliers.add(
        const InventorySupplier(id: 'supplier', name: 'Proveedor sintético'),
      );
      store.productDefaults['known'] = const ProductIntakeDefaults(
        supplierId: 'supplier',
        supplierName: 'Proveedor sintético',
        unitPurchasePriceMinor: 0,
      );
      await open(tester);
      await enter(tester, 'intake-quantity', '7');
      await tap(tester, keyed('intake-payment-'));
      await tap(tester, find.text('Transferencia').last);
      await enter(tester, 'intake-name', 'KNOWN');
      await tap(tester, find.text('Artículo conocido').last);
      expect(value(tester, 'intake-cost'), '0,00');
      expect(value(tester, 'intake-supplier'), 'Proveedor sintético');
      expect(value(tester, 'intake-quantity'), '7');
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(keyed('intake-payment-'))
            .initialValue,
        'nequi',
      );
      await enter(tester, 'intake-name', 'sin ingreso');
      await tap(tester, find.text('Artículo sin ingreso previo').last);
      expect(value(tester, 'intake-cost'), isEmpty);
      expect(value(tester, 'intake-supplier'), isEmpty);
      expect(value(tester, 'intake-sku'), isEmpty);
      expect(value(tester, 'intake-pvp'), '1.500,00');
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(keyed('intake-category-'))
            .initialValue,
        isNull,
      );
      await enter(tester, 'intake-name', 'KNOWN');
      await tap(tester, find.text('Artículo conocido').last);
      await enter(tester, 'intake-name', 'Nuevo producto');
      for (final key in [
        'intake-cost',
        'intake-supplier',
        'intake-sku',
        'intake-pvp',
      ]) {
        expect(value(tester, key), isEmpty);
      }
      expect(value(tester, 'intake-quantity'), '7');
      expect(store.preparedCommands, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editing selected product into a new name clears selected identity and SKU',
    (tester) async {
      store.products.add(
        const CatalogProduct(
          id: 'water',
          name: 'Agua sintética',
          sku: 'WATER',
          categoryId: 'food',
          listPriceMinor: 250000,
        ),
      );
      await open(tester);
      await enter(tester, 'intake-name', 'Agua');
      await tap(tester, find.text('Agua sintética').last);
      await enter(tester, 'intake-name', 'Snack sintético');
      expect(find.byKey(const Key('intake-existing')), findsNothing);
      expect(value(tester, 'intake-sku'), isEmpty);
      expect(value(tester, 'intake-pvp'), isEmpty);
      expect(value(tester, 'intake-cost'), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unknown result locks exact form and retry clears only after confirmation',
    (tester) async {
      store.confirmFailure = StateError('lost response');
      store.commitBeforeConfirmFailure = true;
      await open(tester);
      await fill(tester);
      await tap(tester, find.byKey(const Key('intake-submit')));
      final command = store.preparedCommands.single;
      expect(store.entries, hasLength(1));
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('intake-name')))
            .enabled,
        isFalse,
      );
      expect(value(tester, 'intake-cost'), '1.234,50');
      await tap(
        tester,
        find.byKey(ValueKey('intake-retry-${command.commandId}')),
      );
      expect(store.entries, hasLength(1));
      expect(store.confirmedIds, [command.commandId, command.commandId]);
      expect(value(tester, 'intake-name'), isEmpty);
      expect(controller.pendingIntakes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reopened durable pending restores locked values and explicit rejection correction',
    (tester) async {
      store.productDefaults['new-product'] = const ProductIntakeDefaults(
        supplierId: 'other-supplier',
        supplierName: 'Otro proveedor sintético',
        unitPurchasePriceMinor: 900000,
      );
      store.pending.add(
        PreparedStockIntake(
          status: 'rejected',
          rejectionReason: 'Saldo cambió.',
          preparedAtUtc: DateTime.utc(2026, 10, 19),
          command: StockIntakeCommand(
            commandId: 'recover',
            productId: 'new-product',
            productName: 'Agua sintética',
            sku: 'WATER',
            categoryId: 'food',
            supplierName: 'Proveedor sintético',
            unitPurchasePriceMinor: 100000,
            listPriceMinor: 250000,
            quantity: 2,
            paymentOptionId: 'cash',
            occurredAtUtc: DateTime.utc(2026, 10, 19),
          ),
        ),
      );
      await open(tester);
      expect(value(tester, 'intake-name'), 'Agua sintética');
      expect(value(tester, 'intake-quantity'), '2');
      expect(value(tester, 'intake-cost'), '1.000,00');
      expect(value(tester, 'intake-supplier'), 'Proveedor sintético');
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('intake-name')))
            .enabled,
        isFalse,
      );
      await tap(tester, find.text('Corregir ingreso'));
      expect(store.discardedIds, ['recover']);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('intake-name')))
            .enabled,
        isTrue,
      );
      await tap(tester, find.byKey(const Key('intake-submit')));
      expect(store.entries, hasLength(1));
      expect(store.preparedCommands.single.commandId, isNot('recover'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'insufficient funds and fractional quantity do not prepare a purchase',
    (tester) async {
      await open(tester);
      await fill(tester);
      await enter(tester, 'intake-quantity', '10');
      expect(find.byKey(const Key('intake-insufficient')), findsOneWidget);
      await tap(tester, find.byKey(const Key('intake-submit')));
      expect(store.preparedCommands, isEmpty);
      expect(controller.operationError, contains('no alcanza'));
      await enter(tester, 'intake-quantity', '1,5');
      await tap(tester, find.byKey(const Key('intake-submit')));
      expect(
        find.text('Escribe una cantidad entera positiva.'),
        findsOneWidget,
      );
      expect(store.preparedCommands, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'opening dialog declares real positive money once and uncertain retry is safe',
    (tester) async {
      store.openingFailure = StateError('lost response');
      store.commitBeforeOpeningFailure = true;
      await open(tester);
      await tap(tester, find.byKey(const Key('intake-opening')));
      expect(find.textContaining('dinero real'), findsOneWidget);
      await enter(tester, 'opening-amount', '1.000');
      await tap(tester, find.byKey(const Key('opening-save')));
      final first = store.openingCommands.single;
      expect(find.text('Reintentar el mismo saldo'), findsOneWidget);
      await tap(tester, find.byKey(const Key('opening-save')));
      expect(store.openingCommands.last, same(first));
      expect(find.text('Declarar saldo inicial'), findsNothing);
      expect(controller.pendingOpening, isNull);
      expect(controller.snapshot!.paymentOptions.first.balanceMinor, 1100000);
      await tap(tester, find.byKey(const Key('intake-opening')));
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Transferencia'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Efectivo'),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'form fits narrow window and categories include requested three options',
    (tester) async {
      await open(tester, size: const Size(400, 900));
      await tap(tester, keyed('intake-category-'));
      expect(find.text('Comestible'), findsOneWidget);
      expect(find.text('Artículo'), findsOneWidget);
      expect(find.text('Evento'), findsOneWidget);
      await tap(tester, find.text('Artículo'));
      await tester.ensureVisible(find.byKey(const Key('intake-submit')));
      expect(tester.takeException(), isNull);
    },
  );
}
