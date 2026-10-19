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
import 'package:valinor_sanctum_2/features/sales/domain/sales_store.dart';
import 'package:valinor_sanctum_2/features/workspace/application/workspace_controller.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/workspace_store.dart';

import '../support/fake_sales_store.dart';
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
  final profile = BusinessProfile(
    profileId: 'test',
    businessName: 'Ludoteca sintética',
    currencyCode: 'COP',
    moneyScale: 2,
    timezone: 'America/Bogota',
    createdAtUtc: DateTime.utc(2026, 10, 19),
  );

  FakeSalesStore store() => FakeSalesStore()
    ..products.add(
      const CatalogProduct(
        id: 'product',
        name: 'Juego sintético',
        listPriceMinor: 1234567,
      ),
    )
    ..stock.add(
      const StockPosition(
        productId: 'product',
        quantity: 3,
        totalCostMinor: 1000,
      ),
    );

  Future<void> open(
    WidgetTester tester,
    FakeSalesStore store, {
    Size size = const Size(1000, 950),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final workspace = FakeWorkspaceStore()..profile = profile;
    final controller = WorkspaceController(
      openSession: () async => WorkspaceSession(
        store: workspace,
        databasePath: 'perfil-sintetico/sanctum2.sqlite3',
        profileId: 'test',
        salesStore: store,
      ),
    );
    await controller.initialize();
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('sales-preview'),
        child: SanctumApp(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ventas'));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }

  Finder input(String prefix) => find.byWidgetPredicate(
    (widget) =>
        widget is TextFormField &&
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith(prefix),
  );

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, Finder finder, String value) async {
    await tester.ensureVisible(finder);
    await tester.enterText(finder, value);
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester) async {
    await enter(tester, find.byKey(const Key('sale-label')), 'Mesa sintética');
    await enter(
      tester,
      find.byKey(const Key('sale-customer')),
      'Cliente sintético',
    );
    final product = find.byWidgetPredicate(
      (widget) =>
          widget is DropdownButtonFormField<String> &&
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith('sale-product-'),
    );
    await tap(tester, product);
    await tap(tester, find.text('Juego sintético').last);
    await enter(tester, input('sale-quantity-'), '2');
    await enter(tester, input('sale-price-'), '12.345,67');
  }

  Future<void> confirm(WidgetTester tester) async {
    await enter(tester, input('sale-due-'), '2099-12-31');
    await tap(tester, find.byKey(const Key('confirm-sale')));
    await tap(tester, find.byKey(const Key('accept-credit-sale')));
  }

  Future<void> capture(WidgetTester tester) async {
    if (!const bool.fromEnvironment('SANCTUM_CAPTURE_SALES_PREVIEW')) return;
    await tester.binding.setSurfaceSize(const Size(1120, 2100));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Ventas y cuentas abiertas'));
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('sales-preview')),
    );
    final output = File(
      p.join(
        AppConfig.repositoryRootPath,
        'docs',
        'images',
        'sales-credit.png',
      ),
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
    'navigation preserves unsaved editor and warning without claiming persisted changes',
    (tester) async {
      final fake = store();
      await open(tester, fake, size: const Size(400, 900));
      await fill(tester);
      await tester.tap(find.text('Sistema'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ventas'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('sale-label')))
            .controller!
            .text,
        'Mesa sintética',
      );
      expect(find.text('Cambios sin guardar'), findsOneWidget);
      expect(fake.drafts, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'validates required identity and exact prices, saves a recoverable account without stock effect',
    (tester) async {
      final fake = store();
      await open(tester, fake, size: const Size(400, 900));
      await tap(tester, find.byKey(const Key('save-sale-draft')));
      expect(fake.savedInputs, isEmpty);
      expect(find.text('Escribe entre 1 y 120 caracteres.'), findsNWidgets(2));
      await fill(tester);
      await tap(tester, find.byKey(const Key('save-sale-draft')));
      expect(fake.drafts, hasLength(1));
      expect(fake.drafts.single.lines.single.unitPriceMinor, 1234567);
      expect(fake.stock.single.quantity, 3);
      expect(find.text('Cambios sin guardar'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await open(tester, fake, size: const Size(400, 900));
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('sale-label')))
            .controller!
            .text,
        'Mesa sintética',
      );
      expect(
        tester.widget<TextFormField>(input('sale-quantity-')).controller!.text,
        '2',
      );
      expect(
        tester.widget<TextFormField>(input('sale-price-')).controller!.text,
        '12.345,67',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'confirms delivery and displays immutable history, historical cost and receivable',
    (tester) async {
      final fake = store();
      await open(tester, fake);
      await fill(tester);
      await confirm(tester);
      expect(fake.sales, hasLength(1));
      expect(fake.stock.single.quantity, 1);
      expect(
        find.textContaining('Venta a crédito confirmada.'),
        findsOneWidget,
      );
      expect(find.text('Por cobrar: COP 24.691,34'), findsOneWidget);
      expect(find.text('Costo histórico: COP 5,00'), findsOneWidget);
      await tap(tester, find.text('Ver entrega (1)'));
      expect(
        find.textContaining(
          'Juego sintético · 2 unidades · Precio: COP 12.345,67',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('sale-label')))
            .controller!
            .text,
        isEmpty,
      );
      if (const bool.fromEnvironment('SANCTUM_CAPTURE_SALES_PREVIEW')) {
        await fill(tester);
        await enter(tester, input('sale-quantity-'), '1');
        await tap(tester, find.byKey(const Key('save-sale-draft')));
        await capture(tester);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'uncertain confirmation locks editing and retries the exact command after reopening',
    (tester) async {
      final fake = store()
        ..confirmationFailure = StateError('reply lost before commit');
      await open(tester, fake);
      await fill(tester);
      await confirm(tester);
      final identity = fake.preparedIds.single;
      expect(find.text('Reintentar la misma venta'), findsOneWidget);
      expect(
        tester.widget<TextFormField>(input('sale-price-')).enabled,
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
      await open(tester, fake);
      expect(find.byKey(const Key('sale-pending')), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('sale-label')))
            .controller!
            .text,
        'Mesa sintética',
      );
      expect(
        tester.widget<TextFormField>(input('sale-quantity-')).enabled,
        isFalse,
      );
      fake.confirmationFailure = null;
      await tap(tester, find.byKey(const Key('confirm-sale')));
      expect(fake.confirmedIds, [identity, identity]);
      expect(fake.sales, hasLength(1));
      expect(fake.stock.single.quantity, 1);
      expect(fake.pending, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'lost acknowledgement after commit retries without a second delivery',
    (tester) async {
      final fake = store()
        ..confirmationFailure = StateError('lost result')
        ..commitBeforeConfirmationFailure = true;
      await open(tester, fake);
      await fill(tester);
      await confirm(tester);
      expect(fake.sales, hasLength(1));
      final identity = fake.confirmedIds.single;
      await tap(tester, find.byKey(const Key('confirm-sale')));
      expect(fake.confirmedIds, [identity, identity]);
      expect(fake.stock.single.quantity, 1);
      expect(fake.sales, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'refresh discovers a committed sale after a lost reply and keeps its account immutable',
    (tester) async {
      final fake = store()
        ..confirmationFailure = StateError('lost result')
        ..commitBeforeConfirmationFailure = true;
      await open(tester, fake);
      await fill(tester);
      await confirm(tester);
      await tap(tester, find.text('Actualizar'));
      expect(find.text('Cuenta entregada'), findsOneWidget);
      expect(
        tester.widget<TextFormField>(input('sale-price-')).enabled,
        isFalse,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('confirm-sale')))
            .onPressed,
        isNull,
      );
      expect(fake.sales, hasLength(1));
      expect(fake.stock.single.quantity, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'deterministic rejection recovers the new draft revision before correction, save and confirmation',
    (tester) async {
      final fake = store()
        ..confirmationFailure = const SalesValidationException(
          'Stock insuficiente.',
        );
      await open(tester, fake);
      await fill(tester);
      await confirm(tester);
      expect(find.text('Stock insuficiente.'), findsOneWidget);
      expect(find.byKey(const Key('unlock-sale')), findsOneWidget);
      expect(
        tester.widget<TextFormField>(input('sale-price-')).enabled,
        isFalse,
      );
      await tap(tester, find.byKey(const Key('unlock-sale')));
      expect(
        tester.widget<TextFormField>(input('sale-price-')).enabled,
        isTrue,
      );
      expect(fake.pending, isEmpty);
      expect(fake.sales, isEmpty);
      expect(fake.stock.single.quantity, 3);
      final unlockedRevision = fake.drafts.single.revision;
      fake.confirmationFailure = null;
      await enter(tester, input('sale-quantity-'), '1');
      await tap(tester, find.byKey(const Key('save-sale-draft')));
      expect(fake.savedInputs.last.expectedRevision, unlockedRevision);
      expect(fake.drafts.single.lines.single.quantity, 1);
      await confirm(tester);
      expect(fake.sales, hasLength(1));
      expect(fake.sales.single.lines.single.quantity, 1);
      expect(fake.stock.single.quantity, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unlock followed by a read failure keeps editing blocked until its revised draft is recovered',
    (tester) async {
      final fake = store()
        ..confirmationFailure = const SalesValidationException(
          'Stock insuficiente.',
        );
      await open(tester, fake);
      await fill(tester);
      await confirm(tester);
      fake.loadFailure = StateError('read unavailable after unlocking');
      await tap(tester, find.byKey(const Key('unlock-sale')));
      expect(fake.pending, isEmpty);
      expect(fake.drafts.single.status, 'open');
      expect(
        tester.widget<TextFormField>(input('sale-price-')).enabled,
        isFalse,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('save-sale-draft')))
            .onPressed,
        isNull,
      );
      expect(
        find.textContaining('hasta recuperar su revisión actual'),
        findsOneWidget,
      );
      fake.loadFailure = null;
      await tap(tester, find.text('Actualizar').first);
      expect(
        tester.widget<TextFormField>(input('sale-price-')).enabled,
        isTrue,
      );
      final unlockedRevision = fake.drafts.single.revision;
      fake.confirmationFailure = null;
      await enter(tester, input('sale-quantity-'), '1');
      await tap(tester, find.byKey(const Key('save-sale-draft')));
      expect(fake.savedInputs.last.expectedRevision, unlockedRevision);
      await confirm(tester);
      expect(fake.sales, hasLength(1));
      expect(fake.stock.single.quantity, 2);
      expect(tester.takeException(), isNull);
    },
  );
}
