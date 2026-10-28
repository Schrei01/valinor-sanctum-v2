import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/features/quick_sales/application/quick_sales_controller.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/quick_sales_store.dart';
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
    Size size = const Size(1120, 1050),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: QuickSalesPage(
              controller: controller,
              profile: BusinessProfile(
                profileId: 'quick-credit-ui',
                businessName: 'Tienda sintética',
                currencyCode: 'COP',
                moneyScale: 2,
                timezone: 'America/Bogota',
                createdAtUtc: DateTime.utc(2026, 10, 20),
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

  Future<void> enter(WidgetTester tester, Finder finder, String value) async {
    await tester.ensureVisible(finder);
    await tester.enterText(finder, value);
    await tester.pumpAndSettle();
    if ((tester.widget<TextField>(finder).key as ValueKey<String>).value
        .startsWith('quick-label-')) {
      await tester.tap(find.text(value).last);
      await tester.pumpAndSettle();
    }
  }

  Future<void> product(WidgetTester tester, int row, String name) async {
    await enter(tester, keyed('quick-product-').at(row), name);
    await tap(tester, find.text(name).last);
  }

  Future<void> payment(WidgetTester tester, int row, String label) async {
    await tap(tester, keyed('quick-account-payment-').at(row));
    await tap(tester, find.text(label).last);
  }

  Future<void> creditAccount(WidgetTester tester) async {
    await tap(tester, find.byKey(const Key('quick-new-account')));
    await product(tester, 0, 'Agua sintética');
    await payment(tester, 0, 'Deudas');
  }

  String customerValue(WidgetTester tester) =>
      controller.accounts.single.customerName;

  testWidgets(
    'person picker fills Cuenta before payment selection and typing clears stale ownership',
    (tester) async {
      await open(tester);
      await tap(tester, find.byKey(const Key('quick-new-account')));
      await tap(tester, keyed('quick-person-picker-'));
      await tap(tester, find.text('Cliente válido').last);
      expect(
        tester.widget<TextField>(keyed('quick-label-')).controller!.text,
        'Cliente válido',
      );
      expect(controller.accounts.single.debtorId, 'Cliente válido');
      expect(controller.hasCreditFor(controller.accounts.single), isFalse);
      await enter(tester, keyed('quick-product-'), 'Agua sintética');
      await tap(tester, find.text('Agua sintética').last);
      await tester.enterText(keyed('quick-label-'), 'Mesa sin titular');
      await tester.pumpAndSettle();
      expect(controller.accounts.single.debtorId, isNull);
      await payment(tester, 0, 'Deudas');
      await tap(tester, keyed('quick-register-'));
      expect(store.sales, isEmpty);
      expect(
        find.text('Asigna esta cuenta a una persona registrada en Deudores.'),
        findsOneWidget,
      );
      await tester.enterText(keyed('quick-label-'), 'Cliente mix');
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(controller.accounts.single.debtorId, 'Cliente mixto');
      expect(
        tester.widget<TextField>(keyed('quick-label-')).controller!.text,
        'Cliente mixto',
      );
      await tap(tester, keyed('quick-register-'));
      expect(store.customerDebts, {'Cliente mixto': 300000});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Deudas asks for the client and blocks anonymous credit', (
    tester,
  ) async {
    await open(tester);
    await tap(tester, find.byKey(const Key('quick-new-account')));
    expect(keyed('quick-label-'), findsOneWidget);
    await product(tester, 0, 'Agua sintética');
    await payment(tester, 0, 'Deudas');
    expect(
      find.text('Selecciona una persona de Deudores para asignarle lo fiado.'),
      findsOneWidget,
    );
    expect(
      find.text('Cobrado: COP 0,00 · Deudas: COP 3.000,00'),
      findsOneWidget,
    );
    await tap(tester, keyed('quick-register-').first);
    expect(
      find.text('Asigna esta cuenta a una persona registrada en Deudores.'),
      findsOneWidget,
    );
    expect(store.preparedIds, isEmpty);
    expect(store.customerDebts, isEmpty);
    expect(store.stock.first.quantity, 20);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'all credit consumes stock and records named debt without money collection',
    (tester) async {
      await open(tester);
      await creditAccount(tester);
      await enter(tester, keyed('quick-label-'), 'Cliente sintético');
      await tap(tester, keyed('quick-register-').first);
      expect(store.sales, hasLength(1));
      expect(store.sales.single.result.creditMinor, 300000);
      expect(store.sales.single.result.collectionDocumentId, isNull);
      expect(store.customerDebts['Cliente sintético'], 300000);
      expect(store.balances.values.every((amount) => amount == 0), isTrue);
      expect(store.stock.first.quantity, 19);
      expect(keyed('quick-card-'), findsNothing);
      await tap(tester, find.byKey(const Key('quick-history')));
      expect(
        find.textContaining(
          'Cliente: Cliente sintético · Deudas: COP 3.000,00',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Agua sintética · Deudas'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'legacy mixed draft opens as divided and preserves its cash transfer and debt',
    (tester) async {
      await open(tester);
      await creditAccount(tester);
      await enter(tester, keyed('quick-label-'), 'Cliente mixto');
      await tap(tester, keyed('quick-add-line-').first);
      await product(tester, 1, 'Snack sintético');
      await tap(tester, keyed('quick-add-line-').first);
      await product(tester, 2, 'Agua sintética');
      final id = controller.accounts.single.id;
      final rows = controller.accounts.single.lines;
      controller.editLine(
        id,
        QuickSaleLine(
          id: rows[1].id,
          productId: rows[1].productId,
          quantityText: rows[1].quantityText,
          unitPriceMinor: rows[1].unitPriceMinor,
          paymentOptionId: 'cash',
        ),
      );
      controller.editLine(
        id,
        QuickSaleLine(
          id: rows[2].id,
          productId: rows[2].productId,
          quantityText: rows[2].quantityText,
          unitPriceMinor: rows[2].unitPriceMinor,
          paymentOptionId: 'nequi',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Pago dividido'), findsOneWidget);
      expect(
        find.text('Cobrado: COP 5.000,00 · Deudas: COP 3.000,00'),
        findsOneWidget,
      );
      await tap(tester, keyed('quick-register-').first);
      expect(store.sales.single.result.totalMinor, 800000);
      expect(store.sales.single.result.creditMinor, 300000);
      expect(store.customerDebts['Cliente mixto'], 300000);
      expect(store.balances['cash-account'], 200000);
      expect(store.balances['nequi-account'], 300000);
      expect(store.stock.first.quantity, 18);
      expect(store.stock.last.quantity, 29);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('client and Deudas selection autosave and survive reopening', (
    tester,
  ) async {
    await open(tester);
    await creditAccount(tester);
    await enter(tester, keyed('quick-label-'), 'Cliente guardado');
    await controller.flushAll();
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    controller = QuickSalesController(store: store);
    await open(tester);
    expect(customerValue(tester), 'Cliente guardado');
    expect(
      controller.accounts.single.lines.single.paymentOptionId,
      QuickPaymentOption.creditId,
    );
    expect(find.text('Deudas'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'account person remains visible for cash and credit without creating debt for paid lines',
    (tester) async {
      await open(tester);
      await creditAccount(tester);
      await enter(tester, keyed('quick-label-'), 'Cliente conservado');
      await payment(tester, 0, 'Efectivo');
      expect(keyed('quick-label-'), findsOneWidget);
      expect(controller.accounts.single.customerName, 'Cliente conservado');
      await controller.flushAll();
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      controller = QuickSalesController(store: store);
      await open(tester);
      expect(keyed('quick-label-'), findsOneWidget);
      expect(controller.accounts.single.customerName, 'Cliente conservado');
      await payment(tester, 0, 'Deudas');
      expect(customerValue(tester), 'Cliente conservado');
      await payment(tester, 0, 'Efectivo');
      await tap(tester, keyed('quick-register-').first);
      expect(store.sales.single.result.creditMinor, 0);
      expect(store.customerDebts, isEmpty);
      expect(store.balances['cash-account'], 300000);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unknown credit response locks client and retry never repeats stock or debt',
    (tester) async {
      await open(tester);
      await creditAccount(tester);
      await enter(tester, keyed('quick-label-'), 'Cliente reintento');
      store.confirmationFailure = StateError('lost response');
      store.commitBeforeFailure = true;
      await tap(tester, keyed('quick-register-').first);
      expect(tester.widget<TextField>(keyed('quick-label-')).enabled, isFalse);
      expect(customerValue(tester), 'Cliente reintento');
      expect(store.stock.first.quantity, 19);
      store.confirmationFailure = null;
      await tap(tester, keyed('quick-retry-').first);
      expect(store.customerDebts['Cliente reintento'], 300000);
      expect(store.stock.first.quantity, 19);
      expect(store.sales, hasLength(1));
      expect(store.confirmedIds.toSet(), {store.preparedIds.single});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'rejected credit correction keeps client and uses a new command',
    (tester) async {
      await open(tester);
      await creditAccount(tester);
      await enter(tester, keyed('quick-label-'), 'Cliente inicial');
      store.confirmationFailure = const QuickSalesValidationException(
        'Stock cambió.',
      );
      await tap(tester, keyed('quick-register-').first);
      final rejectedId = store.preparedIds.single;
      await tap(tester, keyed('quick-unlock-').first);
      expect(customerValue(tester), 'Cliente inicial');
      await enter(tester, keyed('quick-label-'), 'Cliente corregido');
      store.confirmationFailure = null;
      await tap(tester, keyed('quick-register-').first);
      expect(store.preparedIds.last, isNot(rejectedId));
      expect(store.customerDebts, {'Cliente corregido': 300000});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('credit client and summary fit a narrow window', (tester) async {
    await open(tester, size: const Size(400, 900));
    await creditAccount(tester);
    await enter(tester, keyed('quick-label-'), 'Cliente estrecho');
    await tester.ensureVisible(keyed('quick-register-').first);
    expect(tester.takeException(), isNull);
    await tap(tester, keyed('quick-register-').first);
    expect(store.customerDebts['Cliente estrecho'], 300000);
    expect(tester.takeException(), isNull);
  });
}
