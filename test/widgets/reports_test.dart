import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/features/reports/application/reports_controller.dart';
import 'package:valinor_sanctum_2/features/reports/presentation/reports_page.dart';
import 'package:valinor_sanctum_2/features/reports/domain/reports_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';
import '../support/fake_reports_store.dart';

void main() {
  late FakeReportsStore store;
  late ReportsController controller;
  setUp(() {
    store = FakeReportsStore();
    controller = ReportsController(
      store: store,
      now: () => DateTime.utc(2026, 10, 26, 18),
    );
  });
  tearDown(() => controller.dispose());
  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(1000, 850),
    bool generated = true,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    if (generated) {
      await controller.generate(start: controller.today, end: controller.today);
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ReportsPage(
              controller: controller,
              profile: BusinessProfile(
                profileId: 'test',
                businessName: 'Sintética',
                currencyCode: 'COP',
                moneyScale: 2,
                timezone: 'America/Bogota',
                createdAtUtc: DateTime.utc(2026, 10, 26),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async => tester.pumpWidget(const SizedBox()));
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> dateThenTime(WidgetTester tester, String key, int day) async {
    await tap(tester, find.byKey(Key(key)));
    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(find.byType(TimePickerDialog), findsNothing);
    await tap(tester, find.text('$day').last);
    await tap(tester, find.text('Aceptar'));
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.byType(TimePickerDialog), findsOneWidget);
    expect(find.text('AM'), findsOneWidget);
    expect(find.text('PM'), findsOneWidget);
  }

  Future<void> acceptTime(
    WidgetTester tester,
    String hour,
    String minute,
    String period,
  ) async {
    await tap(tester, find.byIcon(Icons.keyboard_outlined));
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), hour);
    await tester.enterText(fields.at(1), minute);
    await tap(tester, find.text(period));
    await tap(tester, find.text('Aceptar'));
  }

  String value(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(Key(key))).data!;

  testWidgets(
    'initial date is empty, end is current Bogotá minute, and no query runs until start is chosen',
    (tester) async {
      await open(tester, generated: false);
      expect(store.queries, isEmpty);
      expect(find.text('Sin seleccionar'), findsOneWidget);
      expect(find.text('26/10/2026 · 1:00 PM'), findsOneWidget);
      expect(find.byKey(const Key('report-receipt')), findsNothing);
      await tap(tester, find.byKey(const Key('report-generate')));
      expect(find.text('Elige una fecha y hora inicial.'), findsOneWidget);
      expect(store.queries, isEmpty);
      await dateThenTime(tester, 'report-start', 25);
      await acceptTime(tester, '10', '00', 'AM');
      await tap(tester, find.byKey(const Key('report-generate')));
      expect(store.queries.single.startUtc, DateTime.utc(2026, 10, 25, 15));
      expect(
        store.queries.single.endExclusiveUtc,
        DateTime.utc(2026, 10, 26, 18, 1),
      );
      await tap(tester, find.byKey(const Key('report-clear-start')));
      expect(find.text('Sin seleccionar'), findsOneWidget);
      await tap(tester, find.byKey(const Key('report-generate')));
      expect(store.queries, hasLength(1));
    },
  );

  testWidgets(
    'sold items show ten records per page, including unknown and estimated prices, and reset after a new report',
    (tester) async {
      store.itemRows = [
        for (var i = 0; i < 21; i++)
          ReportItem(
            id: 'row-$i',
            productName: 'Producto $i',
            occurredAtUtc: DateTime.utc(2026, 10, 26, 15, i),
            quantity: i == 20 ? 1000 : 1,
            amountMinor: i == 0 ? null : 1000,
            paymentMethod: 'Efectivo',
            isEstimated: i == 1,
          ),
      ];
      await open(tester);
      DataTable table() =>
          tester.widget<DataTable>(find.byType(DataTable).last);
      expect(table().rows, hasLength(10));
      expect(find.text('Producto 20'), findsOneWidget);
      expect(find.text('Producto 10'), findsNothing);
      expect(find.text('1.000'), findsOneWidget);
      await tap(tester, find.byKey(const Key('report-items-next')));
      expect(table().rows, hasLength(10));
      expect(find.text('Producto 10'), findsOneWidget);
      expect(find.text('Producto 20'), findsNothing);
      expect(find.text('COP 10,00 *'), findsOneWidget);
      await tap(tester, find.byKey(const Key('report-items-next')));
      expect(table().rows, hasLength(1));
      expect(find.text('Producto 0'), findsOneWidget);
      expect(find.text('Sin información'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('report-items-next')))
            .onPressed,
        isNull,
      );
      await tap(tester, find.byKey(const Key('report-items-previous')));
      expect(table().rows, hasLength(10));
      await controller.generate(start: controller.today, end: controller.today);
      await tester.pumpAndSettle();
      expect(table().rows, hasLength(10));
      expect(find.text('Producto 20'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('report-items-previous')))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'converted historical balances remain identified with sales totals',
    (tester) async {
      store.convertedHistory = true;
      await open(tester);
      expect(
        find.textContaining('historial convertido de la copia'),
        findsOneWidget,
      );
      expect(value(tester, 'report-opening-cash'), 'COP 1.000,00');
      expect(find.text('Productos vendidos'), findsNothing);
    },
  );

  testWidgets(
    'balances and sale tender totals are shown at their generated cutoffs',
    (tester) async {
      // Real font metrics are required for the compact receipt height assertion.
      await tester.runAsync(() async {
        final loader = FontLoader('Roboto');
        for (final font in [
          'roboto-regular.ttf',
          'roboto-medium.ttf',
          'roboto-bold.ttf',
        ]) {
          loader.addFont(
            Future.value(
              ByteData.sublistView(
                await File(
                  '.tooling/flutter/bin/cache/artifacts/material_fonts/$font',
                ).readAsBytes(),
              ),
            ),
          );
        }
        await loader.load();
      });
      await open(tester);
      expect(value(tester, 'report-opening-cash'), 'COP 1.000,00');
      expect(value(tester, 'report-opening-nequi'), 'COP 500,00');
      expect(value(tester, 'report-closing-cash'), 'COP 940,00');
      expect(value(tester, 'report-closing-nequi'), 'COP 800,00');
      // Abonos and internal transfers affect balances, but are not new sales.
      expect(value(tester, 'report-sales-cash'), 'COP 60,00');
      expect(value(tester, 'report-sales-transfer'), 'COP 200,00');
      expect(value(tester, 'report-sales-credit'), 'COP 40,00');
      expect(value(tester, 'report-sales-total'), 'COP 300,00');
      expect(value(tester, 'report-outflows-cash'), 'COP 70,00');
      expect(value(tester, 'report-outflows-transfer'), 'COP 0,00');
      expect(value(tester, 'report-outflows-total'), 'COP 70,00');
      expect(value(tester, 'report-transfers-total'), 'COP 100,00');
      expect(value(tester, 'report-debtors-total'), 'COP 290,00');
      expect(value(tester, 'report-debtor-one'), 'COP 180,00');
      expect(value(tester, 'report-debtor-two'), 'COP 110,00');
      expect(
        tester.getTopLeft(find.text('NOTAS DEL REPORTE').first).dy,
        greaterThan(
          tester.getBottomRight(find.byKey(const Key('report-items'))).dy,
        ),
      );
      expect(
        tester
            .widget<Semantics>(find.byKey(const Key('report-transfer-route-0')))
            .properties
            .label,
        'Caja → Nequi',
      );
      expect(value(tester, 'report-transfer-amount-0'), 'COP 100,00');
      expect(
        tester.getBottomRight(find.byKey(const Key('report-receipt'))).dy,
        lessThan(850),
      );
      expect(find.byKey(const Key('report-sales-other')), findsNothing);
      expect(find.textContaining('26/10/2026 · 12:00 AM'), findsNWidgets(2));
      expect(find.textContaining('26/10/2026 · 11:59 PM'), findsNWidgets(2));
      for (final label in [
        'Gráfica de barras',
        'Productos vendidos',
        'Resumen del período',
        'Caja mayor',
        'Resultado acumulado por evento',
      ]) {
        expect(find.text(label), findsNothing);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'date is followed by AM PM time and midnight/noon retain their correct instants',
    (tester) async {
      await open(tester);
      await dateThenTime(tester, 'report-start', 25);
      await acceptTime(tester, '12', '00', 'AM');
      await dateThenTime(tester, 'report-end', 26);
      await acceptTime(tester, '12', '00', 'PM');
      await tap(tester, find.byKey(const Key('report-generate')));
      final p = store.queries.last;
      expect(p.startUtc, DateTime.utc(2026, 10, 25, 5));
      expect(p.endExclusiveUtc, DateTime.utc(2026, 10, 26, 17, 1));
      expect(find.textContaining('25/10/2026 · 12:00 AM'), findsNWidgets(2));
      expect(find.textContaining('26/10/2026 · 12:00 PM'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'canceling either dialog leaves the whole previous selection unchanged',
    (tester) async {
      await open(tester);
      await tap(tester, find.byKey(const Key('report-start')));
      await tap(tester, find.text('Cancelar'));
      expect(find.byType(TimePickerDialog), findsNothing);
      await dateThenTime(tester, 'report-end', 25);
      await tap(tester, find.text('Cancelar'));
      expect(find.textContaining('26/10/2026 · 11:59 PM'), findsNWidgets(2));
      await tap(tester, find.byKey(const Key('report-generate')));
      expect(store.queries.last.endExclusiveUtc, DateTime.utc(2026, 10, 27, 5));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'inverted selection preserves the previous report and never reads',
    (tester) async {
      await open(tester);
      await dateThenTime(tester, 'report-start', 27);
      await acceptTime(tester, '1', '30', 'PM');
      await tap(tester, find.byKey(const Key('report-generate')));
      expect(
        find.text(
          'La fecha y hora final deben ser iguales o posteriores a las iniciales.',
        ),
        findsOneWidget,
      );
      expect(store.queries, hasLength(1));
      expect(value(tester, 'report-opening-cash'), 'COP 1.000,00');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'narrow screen preserves missing balances without showing invented zero',
    (tester) async {
      store.unknownBalances = true;
      await open(tester, size: const Size(620, 1000));
      expect(find.text('Sin información'), findsNWidgets(5));
      expect(value(tester, 'report-debtors-total'), 'Sin información');
      expect(find.textContaining('historial disponible'), findsOneWidget);
      expect(value(tester, 'report-opening-cash'), 'Sin información');
      expect(value(tester, 'report-closing-nequi'), 'Sin información');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'missing historical amounts retain known subtotals and exact unaffected channels on narrow screens',
    (tester) async {
      store.unpricedCashSales = 2;
      await open(tester, size: const Size(620, 1000));
      expect(value(tester, 'report-sales-cash'), 'COP 60,00');
      expect(value(tester, 'report-sales-transfer'), 'COP 200,00');
      expect(value(tester, 'report-sales-credit'), 'COP 40,00');
      expect(value(tester, 'report-sales-total'), 'COP 300,00');
      expect(find.text('Total vendido (parcial)'), findsOneWidget);
      expect(
        find.textContaining('Hay 2 registro(s) de ventas antiguas'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byKey(const Key('report-sales-total')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'historical estimates and native revenue share the range totals with explicit quality',
    (tester) async {
      store.estimatedCashMinor = 12000;
      store.estimatedSales = 3;
      await open(tester);
      expect(value(tester, 'report-sales-cash'), 'COP 180,00');
      expect(value(tester, 'report-sales-total'), 'COP 420,00');
      expect(find.textContaining('Incluye 3 registro(s)'), findsOneWidget);
      expect(find.textContaining('· COP 120,00'), findsOneWidget);
      expect(find.text('Total vendido (parcial)'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty transfer range shows zero without hiding the other report values',
    (tester) async {
      store.noTransfers = true;
      await open(tester);
      expect(value(tester, 'report-transfers-total'), 'COP 0,00');
      expect(find.text('Sin transferencias en este rango.'), findsOneWidget);
      expect(find.byKey(const Key('report-transfer-route-0')), findsNothing);
      expect(value(tester, 'report-sales-total'), 'COP 300,00');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'historical transfer with missing companion amount is identified as partial',
    (tester) async {
      store.unpricedTransferRecords = 1;
      store.transferRows = [
        ReportTransfer(
          documentId: 'old',
          occurredAtUtc: DateTime.utc(2026, 10, 26),
          sourceAccountId: 'reserve',
          sourceName: 'Caja Mayor',
          destinationAccountId: 'debt',
          destinationName: 'Deudas',
          amountMinor: 12500,
          note: '',
          isHistorical: true,
        ),
      ];
      await open(tester, size: const Size(620, 1100));
      expect(value(tester, 'report-transfers-total'), 'COP 125,00');
      expect(
        tester
            .widget<Semantics>(find.byKey(const Key('report-transfer-route-0')))
            .properties
            .label,
        'Caja mayor → Deudas',
      );
      expect(find.text('Total trasladado (parcial)'), findsOneWidget);
      expect(
        find.textContaining('1 registro(s) sin información de importe'),
        findsOneWidget,
      );
      expect(value(tester, 'report-outflows-total'), 'COP 70,00');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed refresh retains the four balances and their last generated timestamps',
    (tester) async {
      await open(tester);
      store.failure = StateError('Fallo sintético');
      await tap(tester, find.byKey(const Key('report-generate')));
      expect(
        find.textContaining('Se conserva el último reporte generado.'),
        findsOneWidget,
      );
      expect(value(tester, 'report-closing-nequi'), 'COP 800,00');
      expect(value(tester, 'report-sales-total'), 'COP 300,00');
      expect(find.textContaining('26/10/2026 · 11:59 PM'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('all debtor rows expand the receipt without a nested scroll', (
    tester,
  ) async {
    store.debtorRows = [
      for (var i = 0; i < 30; i++)
        ReportDebtorBalance(
          id: 'p$i',
          name: 'Persona $i',
          amountMinor: i == 29 ? 0 : 1000,
        ),
    ];
    store.transferRows = [
      for (final route in [
        ('Caja', 'Nequi'),
        ('Nequi', 'Caja'),
        ('Caja', 'Caja mayor'),
        ('Caja mayor', 'Caja'),
        ('Nequi', 'Caja mayor'),
        ('Caja mayor', 'Nequi'),
      ].indexed)
        ReportTransfer(
          documentId: 't${route.$1}',
          occurredAtUtc: DateTime.utc(2026, 10, 26),
          sourceAccountId: route.$2.$1,
          sourceName: route.$2.$1,
          destinationAccountId: route.$2.$2,
          destinationName: route.$2.$2,
          amountMinor: 100,
          note: '',
        ),
    ];
    await open(tester);
    final list = find.byKey(const Key('report-debtors-details'));
    final receipt = find.byKey(const Key('report-receipt'));
    expect(tester.getSize(list).height, greaterThan(600));
    expect(
      find.descendant(of: list, matching: find.byType(Scrollable)),
      findsNothing,
    );
    final lastPerson = find.byKey(const Key('report-debtor-p29'));
    expect(
      tester.getBottomRight(lastPerson).dy,
      lessThan(tester.getBottomRight(receipt).dy),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('report-debtors-total'))).dy,
      greaterThan(tester.getBottomRight(lastPerson).dy),
    );
    expect(
      tester.getSize(find.byKey(const Key('report-transfers-details'))).height,
      lessThanOrEqualTo(120),
    );
    await tester.ensureVisible(lastPerson);
    await tester.pumpAndSettle();
    expect(find.text('Persona 29').hitTestable(), findsOneWidget);
    expect(
      find.byKey(const Key('report-debtors-total')).hitTestable(),
      findsOneWidget,
    );
    expect(value(tester, 'report-debtors-total'), 'COP 290,00');
    expect(tester.takeException(), isNull);
  });
}
