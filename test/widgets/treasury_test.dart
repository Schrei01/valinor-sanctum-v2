import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/features/treasury/application/treasury_controller.dart';
import 'package:valinor_sanctum_2/features/treasury/domain/treasury_store.dart';
import 'package:valinor_sanctum_2/features/treasury/presentation/treasury_page.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';

import '../support/fake_treasury_store.dart';

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
    createdAtUtc: DateTime.utc(2026, 10, 20),
  );

  TreasurySnapshot snapshot({bool withMovements = true}) => TreasurySnapshot(
    accounts: const [
      TreasuryAccount(
        id: 'cash',
        name: 'Caja',
        role: TreasuryAccountRole.cash,
        balanceMinor: 12300,
      ),
      TreasuryAccount(
        id: 'nequi',
        name: 'Nequi',
        role: TreasuryAccountRole.nequi,
        balanceMinor: 4500,
      ),
      TreasuryAccount(
        id: 'reserve',
        name: 'Caja mayor',
        role: TreasuryAccountRole.reserve,
        balanceMinor: 98700,
      ),
      TreasuryAccount(
        id: 'bank',
        name: 'Banco sintético',
        role: TreasuryAccountRole.other,
        balanceMinor: 5000,
      ),
    ],
    receivablesMinor: 78900,
    movements: withMovements
        ? [
            TreasuryMovement(
              id: 'cash-sale',
              cashAccountId: 'cash',
              accountName: 'Caja',
              documentId: 'sale-1',
              occurredAtUtc: DateTime.utc(2026, 10, 20, 4, 30),
              concept: 'Venta sintética',
              amountMinor: 12300,
            ),
            TreasuryMovement(
              id: 'nequi-purchase',
              cashAccountId: 'nequi',
              accountName: 'Nequi',
              documentId: 'purchase-1',
              occurredAtUtc: DateTime.utc(2026, 10, 20, 15, 5),
              concept: 'Compra sintética',
              amountMinor: -2500,
            ),
          ]
        : const [],
  );

  Future<TreasuryController> open(
    WidgetTester tester,
    FakeTreasuryStore fake, {
    Size size = const Size(1400, 1200),
    bool load = true,
    Widget? supplierPaymentsPanel,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = TreasuryController(store: fake);
    if (load) await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF183D35)),
          scaffoldBackgroundColor: const Color(0xFFF5F5F0),
          cardTheme: const CardThemeData(
            elevation: 0,
            margin: EdgeInsets.zero,
            color: Colors.white,
          ),
        ),
        home: RepaintBoundary(
          key: const Key('treasury-preview'),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: TreasuryPage(
                controller: controller,
                profile: profile,
                supplierPaymentsPanel: supplierPaymentsPanel,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
    return controller;
  }

  Future<void> chooseAccount(WidgetTester tester, String name) async {
    final filter = find.byKey(const Key('treasury-account-filter'));
    await tester.ensureVisible(filter);
    await tester.tap(filter);
    await tester.pumpAndSettle();
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'balances distinguish available money, reserve and customer debt',
    (tester) async {
      final fake = FakeTreasuryStore(snapshot: snapshot());
      await open(tester, fake);
      String? amount(String role) =>
          tester.widget<Text>(find.byKey(Key('treasury-amount-$role'))).data;
      expect(amount('cash'), 'COP 123,00');
      expect(amount('nequi'), 'COP 45,00');
      expect(amount('reserve'), 'COP 987,00');
      expect(amount('receivables'), 'COP 789,00');
      expect(amount('other-bank'), 'COP 50,00');
      expect(amount('total'), 'COP 168,00');
      expect(find.text('Caja + Nequi'), findsOneWidget);
      expect(find.text('Lo que deben los clientes'), findsOneWidget);
      expect(fake.defaultsCalls, 1);
      expect(tester.takeException(), isNull);

      if (const bool.fromEnvironment('SANCTUM_CAPTURE_TREASURY_PREVIEW')) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('treasury-preview')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final target = File(
            p.join(
              AppConfig.repositoryRootPath,
              'tmp',
              'previews',
              'treasury.png',
            ),
          );
          await target.parent.create(recursive: true);
          await target.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    },
  );

  testWidgets('history shows signed amounts, Bogotá time and account filters', (
    tester,
  ) async {
    await open(tester, FakeTreasuryStore(snapshot: snapshot()));
    final history = find.byKey(const Key('treasury-movements'));
    expect(
      find.descendant(of: history, matching: find.text('+COP 123,00')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: history, matching: find.text('COP -25,00')),
      findsOneWidget,
    );
    expect(find.text('19/10/2026\n23:30'), findsOneWidget);
    expect(find.text('20/10/2026\n10:05'), findsOneWidget);
    final rows = tester.widget<DataTable>(history).rows;
    expect(rows.first.key, const Key('treasury-movement-nequi-purchase'));
    await chooseAccount(tester, 'Caja');
    expect(find.text('Venta sintética'), findsOneWidget);
    expect(find.text('Compra sintética'), findsNothing);
    await chooseAccount(tester, 'Nequi');
    expect(find.text('Venta sintética'), findsNothing);
    expect(find.text('Compra sintética'), findsOneWidget);
    await chooseAccount(tester, 'Caja mayor');
    expect(
      find.text('Esta cuenta no tiene movimientos recientes.'),
      findsOneWidget,
    );
    await chooseAccount(tester, 'Todas las cuentas');
    expect(find.text('Venta sintética'), findsOneWidget);
    expect(find.text('Compra sintética'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refresh loads current balances and preserves selected account', (
    tester,
  ) async {
    final fake = FakeTreasuryStore(snapshot: snapshot());
    await open(tester, fake);
    await chooseAccount(tester, 'Nequi');
    fake.snapshot = TreasurySnapshot(
      accounts: snapshot().accounts,
      receivablesMinor: 0,
      movements: const [],
    );
    await tester.ensureVisible(find.text('Actualizar').first);
    await tester.tap(find.text('Actualizar').first);
    await tester.pumpAndSettle();
    expect(fake.loadCalls, 2);
    expect(
      find.text('Esta cuenta no tiene movimientos recientes.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('treasury-amount-receivables')))
          .data,
      'COP 0,00',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty history does not fabricate movements', (tester) async {
    await open(
      tester,
      FakeTreasuryStore(snapshot: snapshot(withMovements: false)),
    );
    expect(find.text('Aún no hay movimientos registrados.'), findsOneWidget);
    expect(find.byType(DataTable), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history formats the full negative monetary range exactly', (
    tester,
  ) async {
    final data = TreasurySnapshot(
      accounts: snapshot().accounts,
      receivablesMinor: 0,
      movements: [
        TreasuryMovement(
          id: 'minimum',
          cashAccountId: 'cash',
          accountName: 'Caja',
          documentId: 'synthetic-minimum',
          occurredAtUtc: DateTime.utc(2026, 10, 20),
          concept: 'Egreso de límite sintético',
          amountMinor: int.parse('-9223372036854775808'),
        ),
      ],
    );
    await open(tester, FakeTreasuryStore(snapshot: data));
    expect(find.text('COP -92.233.720.368.547.758,08'), findsOneWidget);
    expect(find.text('Egreso'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'initial load has progress, blocks duplicate reads and recovers',
    (tester) async {
      final fake = FakeTreasuryStore(snapshot: snapshot())
        ..pendingLoad = Completer<TreasurySnapshot>();
      final controller = await open(tester, fake, load: false);
      unawaited(controller.load());
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Procesando…'), findsOneWidget);
      await controller.load();
      expect(fake.loadCalls, 1);
      fake.pendingLoad!.complete(snapshot());
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byKey(const Key('treasury-amount-cash')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'read failure keeps previous balances and retries with fresh data',
    (tester) async {
      final fake = FakeTreasuryStore(snapshot: snapshot());
      final controller = await open(tester, fake);
      fake.loadFailure = StateError('synthetic failure');
      await controller.load();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('treasury-load-error')), findsOneWidget);
      expect(
        find.textContaining('pueden estar desactualizados'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('treasury-amount-cash')), findsOneWidget);
      fake.loadFailure = null;
      await tester.ensureVisible(find.text('Actualizar').first);
      await tester.tap(find.text('Actualizar').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('treasury-load-error')), findsNothing);
      expect(fake.loadCalls, 3);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('first load failure offers retry without zero balance cards', (
    tester,
  ) async {
    final fake = FakeTreasuryStore(snapshot: snapshot())
      ..defaultsFailure = StateError('synthetic failure');
    await open(tester, fake);
    expect(find.textContaining('No se pudo cargar Tesorería'), findsOneWidget);
    expect(find.byKey(const Key('treasury-amount-cash')), findsNothing);
    expect(fake.loadCalls, 0);
    fake.defaultsFailure = null;
    await tester.tap(find.text('Actualizar').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('treasury-amount-cash')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'supplier payment recovery remains accessible when treasury cannot load',
    (tester) async {
      var recoveryRequests = 0;
      final fake = FakeTreasuryStore()
        ..loadFailure = StateError('synthetic treasury failure');
      await open(
        tester,
        fake,
        supplierPaymentsPanel: TextButton(
          onPressed: () => recoveryRequests++,
          child: const Text('Recuperar pago sintético pendiente'),
        ),
      );
      expect(find.byKey(const Key('treasury-load-error')), findsOneWidget);
      expect(find.byKey(const Key('treasury-amount-cash')), findsNothing);
      expect(find.text('Recuperar pago sintético pendiente'), findsNothing);
      await tester.tap(find.text('Pagos a proveedores'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recuperar pago sintético pendiente'));
      expect(recoveryRequests, 1);
      expect(find.byKey(const Key('treasury-load-error')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'narrow view remains usable and legacy payment form stays folded',
    (tester) async {
      await open(
        tester,
        FakeTreasuryStore(snapshot: snapshot()),
        size: const Size(360, 780),
        supplierPaymentsPanel: const Text('Formulario secundario sintético'),
      );
      expect(find.text('Formulario secundario sintético'), findsNothing);
      await chooseAccount(tester, 'Caja mayor');
      expect(
        find.text('Esta cuenta no tiene movimientos recientes.'),
        findsOneWidget,
      );
      final expansion = find.byKey(const Key('treasury-supplier-payments'));
      await tester.ensureVisible(expansion);
      await tester.tap(find.text('Pagos a proveedores'));
      await tester.pumpAndSettle();
      expect(find.text('Formulario secundario sintético'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test('disposing during a read ignores its eventual result', () async {
    final pending = Completer<TreasurySnapshot>();
    final fake = FakeTreasuryStore()..pendingLoad = pending;
    final controller = TreasuryController(store: fake);
    final load = controller.load();
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
    pending.complete(snapshot());
    await load;
    expect(controller.snapshot, isNull);
  });
}
