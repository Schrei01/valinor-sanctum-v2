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
    'empty workspace validates input, saves and displays committed profile',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = FakeWorkspaceStore();
      final controller = WorkspaceController(
        openSession: () async => fakeSession(store),
      );
      await controller.initialize();
      await tester.pumpWidget(SanctumApp(controller: controller));
      await tester.tap(find.byKey(const Key('create-profile')));
      await tester.pumpAndSettle();
      expect(store.saves, 0);
      await tester.enterText(
        find.byKey(const Key('business-name')),
        'Ludoteca sintética',
      );
      await tester.tap(find.byKey(const Key('create-profile')));
      await tester.pumpAndSettle();
      expect(find.text('Tu espacio está preparado'), findsOneWidget);
      expect(store.saves, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets('narrow window keeps configuration and diagnostics usable', (
    tester,
  ) async {
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
    await tester.tap(find.text('Sistema'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('database-path')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

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
    expect(find.text('Prepara tu ludoteca'), findsOneWidget);
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
}
