import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/application/inventory_controller.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/presentation/catalog_page.dart';
import 'package:valinor_sanctum_2/features/events/data/sqlite_events_store.dart';
import 'package:valinor_sanctum_2/features/events/domain/events_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';
import '../integration/quick_sales_store_test.dart' show fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fonts =
        '${AppConfig.repositoryRootPath}/.tooling/flutter/bin/cache/artifacts/material_fonts';
    for (final family in {
      'Roboto': ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf'],
      'MaterialIcons': ['materialicons-regular.otf'],
    }.entries) {
      final loader = FontLoader(family.key);
      for (final file in family.value) {
        loader.addFont(
          Future.value(
            ByteData.sublistView(await File('$fonts/$file').readAsBytes()),
          ),
        );
      }
      await loader.load();
    }
  });
  late AppDatabase app;
  late InventoryController controller;
  final page = GlobalKey<CatalogPageState>();
  final boundary = GlobalKey();
  final profile = BusinessProfile(
    profileId: 'quick-test',
    businessName: 'Sintética',
    currencyCode: 'COP',
    moneyScale: 0,
    timezone: 'America/Bogota',
    createdAtUtc: DateTime.utc(2026, 10, 19),
  );
  setUp(() async {
    app = await AppDatabase.open(path: inMemoryDatabasePath);
    await fixture(app, moneyScale: 0);
    final inventory = SqliteInventoryStore(app, synthetic: true);
    await inventory.saveCategory(
      const InventoryCategory(id: 'food', name: 'Comestible'),
    );
    await app.database.update('catalog_items', {
      'category_id': 'food',
    }, where: "id='product'");
    final events = SqliteEventsStore(app, synthetic: true);
    await events.prepare(
      CreateEvent(
        commandId: 'event',
        name: 'Liga sintética',
        minimumPeople: 2,
        fixedCostMinor: 100,
        pvpMinor: 5000,
        sourceAccountId: 'investment',
        occurredAtUtc: DateTime.utc(2026, 11, 7, 10),
        products: const [EventProductInput('product', 2)],
      ),
    );
    await events.confirm('event');
    controller = InventoryController(store: inventory);
    await controller.load();
  });
  tearDown(() async {
    controller.dispose();
    await app.close();
  });
  Future<void> open(WidgetTester t, double width) async {
    await t.binding.setSurfaceSize(Size(width, 1100));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xff183d35),
            ),
            scaffoldBackgroundColor: const Color(0xfff5f5f0),
            inputDecorationTheme: const InputDecorationTheme(
              border: OutlineInputBorder(),
            ),
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: CatalogPage(
                key: page,
                controller: controller,
                profile: profile,
              ),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    addTearDown(() => t.pumpWidget(const SizedBox()));
  }

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 250; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await t.pump(const Duration(milliseconds: 50));
      if (find.byType(LinearProgressIndicator).evaluate().isEmpty &&
          !t.binding.hasScheduledFrame) {
        break;
      }
    }
    await t.pumpAndSettle();
  }

  Future<void> tap(WidgetTester t, Finder f) async {
    await t.ensureVisible(f);
    await t.tap(f);
    await settle(t);
  }

  Future<void> enter(WidgetTester t, String key, String value) async {
    final f = find.byKey(Key(key));
    await t.ensureVisible(f);
    await t.enterText(f, value);
    await t.pumpAndSettle();
  }

  Future<void> choose(WidgetTester t, String kind, String name) async {
    page.currentState!.openStockAdjustment();
    await t.pumpAndSettle();
    expect(find.text('Corregir catálogo'), findsOneWidget);
    await tap(t, find.byKey(Key('catalog-correction-$kind')));
    await enter(t, 'catalog-correction-product', name);
    await tap(t, find.text(name).last);
  }

  Future<void> capture(WidgetTester t, String label, double width) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pumpAndSettle();
    await t.runAsync(() async {
      final picture =
          await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 1);
      final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
      picture.dispose();
      await File(
        '${AppConfig.repositoryRootPath}/tmp/corrections-046-$label-${width.toInt()}.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  for (final width in [1120.0, 400.0]) {
    testWidgets('catalog metadata and event correction review fit at $width', (
      t,
    ) async {
      await open(t, width);
      await choose(t, 'name', 'Producto sintético');
      await enter(t, 'catalog-correction-name', 'Producto corregido');
      await tap(t, find.byKey(const Key('catalog-correction-submit')));
      expect(find.text('Confirmar corrección'), findsOneWidget);
      await tap(t, find.byKey(const Key('catalog-correction-submit')));
      expect(find.byType(AlertDialog), findsNothing);
      await choose(t, 'price', 'Producto corregido');
      await enter(t, 'catalog-correction-price', '0');
      await tap(t, find.byKey(const Key('catalog-correction-submit')));
      expect(find.text('El PVP debe ser mayor que cero.'), findsOneWidget);
      await enter(t, 'catalog-correction-price', '12000');
      await tap(t, find.byKey(const Key('catalog-correction-submit')));
      await tap(t, find.byKey(const Key('catalog-correction-submit')));
      await choose(t, 'event', 'Liga sintética');
      await enter(t, 'catalog-correction-name', 'Liga corregida');
      await enter(t, 'catalog-correction-price', '6000');
      await enter(t, 'catalog-correction-fixed', '50');
      await capture(t, 'event-editor', width);
      await tap(t, find.byTooltip('Quitar artículo'));
      await tap(t, find.byKey(const Key('catalog-correction-submit')));
      expect(find.textContaining('Devolver'), findsWidgets);
      expect(
        find.text('No se devolverá dinero por las reducciones del costo fijo.'),
        findsOneWidget,
      );
      await capture(t, 'event-review', width);
      await tap(t, find.byKey(const Key('catalog-correction-submit')));
      expect(find.byType(AlertDialog), findsNothing);
      await t.runAsync(() async {
        expect((await controller.store.load()).stock.single.quantity, 10);
        expect(
          (await SqliteEventsStore(
            app,
            synthetic: true,
          ).load()).events.single.name,
          'Liga corregida',
        );
      });
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
}
