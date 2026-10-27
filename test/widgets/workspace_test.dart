import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:valinor_sanctum_2/app/sanctum_app.dart';
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/features/workspace/application/workspace_controller.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/workspace_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';
import '../support/fake_quick_sales_store.dart';
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
      for (final file in family.value) {
        final bytes = await File(p.join(fonts, file)).readAsBytes();
        loader.addFont(Future.value(ByteData.sublistView(bytes)));
      }
      await loader.load();
    }
  });

  testWidgets(
    'empty workspace automatically configures Valinor and opens sales',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = FakeWorkspaceStore();
      final controller = WorkspaceController(
        openSession: () async => WorkspaceSession(
          store: store,
          databasePath: 'synthetic',
          profileId: 'test',
          quickSalesStore: FakeQuickSalesStore(),
        ),
      );
      await controller.initialize();
      await tester.pumpWidget(SanctumApp(controller: controller));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('create-profile')), findsNothing);
      expect(find.byKey(const Key('business-name')), findsNothing);
      expect(store.profile!.businessName, 'Valinor');
      expect(store.profile!.currencyCode, 'COP');
      expect(find.byKey(const Key('quick-new-account')), findsOneWidget);
      expect(find.text('Ventas'), findsNWidgets(2));
      expect(store.profile!.moneyScale, 0);
      expect(find.byKey(const Key('money-scale')), findsNothing);
      expect(find.text('Inicio'), findsNothing);
      expect(find.text('Sistema'), findsNothing);
      expect(store.saves, 1);
      await tester.tap(find.text('Eventos'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('events-empty')), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'narrow window creates a zero-decimal profile and shows only commercial navigation',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = FakeWorkspaceStore();
      final controller = WorkspaceController(
        openSession: () async => fakeSession(store),
      );
      await controller.initialize();
      await tester.pumpWidget(SanctumApp(controller: controller));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('create-profile')), findsNothing);
      expect(store.profile!.businessName, 'Valinor');
      expect(store.profile!.moneyScale, 0);
      await tester.tap(find.text('Eventos'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('events-empty')), findsNothing);
      await tester.tap(find.text('Reportes'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('database-path')), findsNothing);
      expect(find.text('Inicio'), findsNothing);
      expect(find.text('Sistema'), findsNothing);
      for (final label in [
        'Catálogo',
        'Compras',
        'Ventas',
        'Deudores',
        'Tesorería',
        'Eventos',
        'Reportes',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets('bootstrap preview uses synthetic data and no database', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = FakeWorkspaceStore();
    final controller = WorkspaceController(
      openSession: () async => fakeSession(store),
    );
    await controller.initialize();
    const boundaryKey = Key('preview');
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: SanctumApp(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Configura tu espacio'), findsNothing);
    expect(find.text('Valinor'), findsOneWidget);
    expect(find.byKey(const Key('money-scale')), findsNothing);
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('SANCTUM_CAPTURE_PREVIEW')) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      final output = File(
        p.join(AppConfig.repositoryRootPath, 'tmp', 'preview', 'bootstrap.png'),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await output.parent.create(recursive: true);
        await output.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets(
    'an existing workspace opens Ventas directly and never writes its configuration',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = FakeWorkspaceStore()
        ..profile = BusinessProfile(
          profileId: 'test',
          businessName: 'Ludoteca sintética',
          currencyCode: 'COP',
          timezone: 'America/Bogota',
          createdAtUtc: DateTime.utc(2026, 10, 26),
        );
      final quick = FakeQuickSalesStore();
      final controller = WorkspaceController(
        openSession: () async => WorkspaceSession(
          store: store,
          databasePath: 'synthetic',
          profileId: 'test',
          quickSalesStore: quick,
        ),
      );
      await controller.initialize();
      await tester.pumpWidget(SanctumApp(controller: controller));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('quick-new-account')), findsOneWidget);
      expect(find.text('Ventas'), findsNWidgets(2));
      expect(find.text('Inicio'), findsNothing);
      expect(find.text('Sistema'), findsNothing);
      expect(find.byKey(const Key('create-profile')), findsNothing);
      expect(store.saves, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
