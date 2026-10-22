import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:valinor_sanctum_2/features/collections/application/collections_controller.dart';
import 'package:valinor_sanctum_2/features/collections/presentation/collections_page.dart';
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/features/collections/domain/collections_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';
import '../support/fake_collections_store.dart';

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
  FakeCollectionsStore store({bool configured = true}) => FakeCollectionsStore()
    ..accounts.addAll(
      configured
          ? [
              const CollectionAccount(
                id: 'cash',
                name: 'Caja sintética',
                kind: 'cash',
              ),
            ]
          : [],
    )
    ..methods.addAll(
      configured
          ? [
              const CollectionMethod(
                id: 'cash-method',
                code: 'EFECTIVO',
                name: 'Efectivo',
              ),
            ]
          : [],
    )
    ..receivables.add(
      ReceivableSummary(
        receivableId: 'receivable',
        saleDocumentId: 'sale',
        label: 'Mesa sintética',
        customerName: 'Cliente sintético',
        issuedAtUtc: DateTime.utc(2026, 10, 19),
        dueDate: '2099-12-31',
        initialMinor: 10000,
        collectedMinor: 0,
        remainingMinor: 10000,
      ),
    );

  Future<void> open(
    WidgetTester tester,
    FakeCollectionsStore fake, {
    Size size = const Size(1120, 1000),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final profile = BusinessProfile(
      profileId: 'test',
      businessName: 'Ludoteca sintética',
      currencyCode: 'COP',
      moneyScale: 2,
      timezone: 'America/Bogota',
      createdAtUtc: DateTime.utc(2026, 10, 19),
    );
    final controller = CollectionsController(store: fake);
    await controller.load();
    var section = 0;
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('collections-preview'),
        child: MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    Wrap(
                      children: [
                        TextButton(
                          onPressed: () => setState(() => section = 0),
                          child: const Text('Cobros'),
                        ),
                        TextButton(
                          onPressed: () => setState(() => section = 1),
                          child: const Text('Sistema'),
                        ),
                      ],
                    ),
                    IndexedStack(
                      index: section,
                      children: [
                        CollectionsPage(
                          controller: controller,
                          profile: profile,
                        ),
                        const SizedBox(),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cobros'));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }

  Finder keyed(String prefix) => find.byWidgetPredicate(
    (w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith(prefix),
  );
  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, Finder target, String value) async {
    await tester.ensureVisible(target);
    await tester.enterText(target, value);
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester, String amount) async {
    await tap(tester, keyed('collection-account-').first);
    await tap(tester, find.text('Caja sintética').last);
    await tap(tester, keyed('collection-method-').first);
    await tap(tester, find.text('Efectivo').last);
    await enter(tester, keyed('collection-amount-').first, amount);
  }

  Future<void> confirm(WidgetTester tester) async {
    await tap(tester, find.byKey(const Key('confirm-collection')));
    await tap(tester, find.byKey(const Key('accept-collection')));
  }

  Future<void> capture(WidgetTester tester) async {
    if (!const bool.fromEnvironment('SANCTUM_CAPTURE_COLLECTIONS_PREVIEW')) {
      return;
    }
    await tester.binding.setSurfaceSize(const Size(1120, 2400));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Cobros y abonos'));
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('collections-preview')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        p.join(
          AppConfig.repositoryRootPath,
          'docs',
          'images',
          'collections-credit.png',
        ),
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'local configuration creates no opening balance and permits a partial payment',
    (tester) async {
      final fake = store(configured: false);
      await open(tester, fake);
      await enter(
        tester,
        find.byKey(const Key('collection-account-name')),
        'Caja sintética',
      );
      await tap(tester, find.byKey(const Key('save-collection-account')));
      expect(fake.accounts.single.balanceMinor, 0);
      await enter(
        tester,
        find.byKey(const Key('collection-method-name')),
        'Efectivo',
      );
      await enter(
        tester,
        find.byKey(const Key('collection-method-code')),
        'EFECTIVO',
      );
      await tap(tester, find.byKey(const Key('save-collection-method')));
      expect(fake.collections, isEmpty);
      await fill(tester, '40,00');
      await confirm(tester);
      expect(fake.receivables.single.remainingMinor, 6000);
      expect(fake.accounts.single.balanceMinor, 4000);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('partial and final receipt use the exact remaining balance', (
    tester,
  ) async {
    final fake = store();
    await open(tester, fake);
    await fill(tester, '40,00');
    await confirm(tester);
    expect(fake.receivables.single.collectedMinor, 4000);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('collection-current-balance')))
          .data,
      'Pendiente: COP 60,00',
    );
    await capture(tester);
    await fill(tester, '1,00');
    await tap(tester, find.byKey(const Key('fill-collection-total')));
    expect(
      tester.widget<Text>(find.byKey(const Key('collection-total'))).data,
      'Total del cobro: COP 60,00',
    );
    await confirm(tester);
    expect(fake.receivables.single.remainingMinor, 0);
    expect(fake.accounts.single.balanceMinor, 10000);
    expect(fake.collections, hasLength(2));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'uncertain collection is recovered after reopening and retries the same identity',
    (tester) async {
      final fake = store()..confirmationFailure = StateError('unknown result');
      await open(tester, fake);
      await fill(tester, '40,00');
      await confirm(tester);
      final identity = fake.preparedInputs.single.commandId;
      expect(fake.collections, isEmpty);
      expect(
        tester.widget<TextFormField>(keyed('collection-amount-').first).enabled,
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
      await open(tester, fake);
      expect(find.text('Reintentar el mismo cobro'), findsOneWidget);
      fake.confirmationFailure = null;
      await tap(tester, find.byKey(const Key('confirm-collection')));
      expect(fake.confirmedIds, [identity, identity]);
      expect(fake.collections, hasLength(1));
      expect(fake.receivables.single.remainingMinor, 6000);
    },
  );
  testWidgets(
    'lost commit reply and failed refresh never enable another collection before recovery',
    (tester) async {
      final fake = store()
        ..confirmationFailure = StateError('lost reply')
        ..commitBeforeConfirmationFailure = true;
      await open(tester, fake);
      await fill(tester, '40,00');
      await confirm(tester);
      final identity = fake.preparedInputs.single.commandId;
      expect(fake.collections, hasLength(1));
      fake.confirmationFailure = null;
      fake.loadFailure = StateError('read failed');
      await tap(tester, find.byKey(const Key('confirm-collection')));
      expect(fake.confirmedIds, [identity, identity]);
      expect(fake.collections, hasLength(1));
      expect(
        tester.widget<TextFormField>(keyed('collection-amount-').first).enabled,
        isFalse,
      );
      fake.loadFailure = null;
      await tap(tester, find.text('Actualizar').first);
      expect(fake.receivables.single.remainingMinor, 6000);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'rejected collection can be corrected and narrow navigation preserves unsaved input',
    (tester) async {
      final fake = store()
        ..confirmationFailure = const CollectionsValidationException(
          'Saldo cambió',
        );
      await open(tester, fake, size: const Size(400, 900));
      await fill(tester, '40,00');
      await tap(tester, find.text('Sistema'));
      await tap(tester, find.text('Cobros'));
      expect(
        tester
            .widget<TextFormField>(keyed('collection-amount-').first)
            .controller!
            .text,
        '40,00',
      );
      await confirm(tester);
      expect(fake.pending.single.status, 'rejected');
      fake.confirmationFailure = null;
      await tap(tester, find.byKey(const Key('unlock-collection')));
      await enter(tester, keyed('collection-amount-').first, '30,00');
      await confirm(tester);
      expect(fake.collections.single.totalMinor, 3000);
      expect(fake.receivables.single.remainingMinor, 7000);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'refresh of a committed unknown receipt clears the previous amount',
    (tester) async {
      final fake = store()
        ..confirmationFailure = StateError('lost commit reply')
        ..commitBeforeConfirmationFailure = true;
      await open(tester, fake);
      await fill(tester, '40,00');
      await confirm(tester);
      expect(fake.collections, hasLength(1));
      expect(
        tester.widget<TextFormField>(keyed('collection-amount-').first).enabled,
        isFalse,
      );
      await tap(tester, find.text('Actualizar').first);
      final amount = tester.widget<TextFormField>(
        keyed('collection-amount-').first,
      );
      expect(amount.enabled, isTrue);
      expect(amount.controller!.text, isEmpty);
      expect(find.text('Reintentar el mismo cobro'), findsNothing);
      expect(fake.receivables.single.remainingMinor, 6000);
      expect(fake.preparedInputs, hasLength(1));
      expect(fake.collections, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
}
