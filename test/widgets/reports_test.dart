import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/features/reports/application/reports_controller.dart';
import 'package:valinor_sanctum_2/features/reports/presentation/reports_page.dart';
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
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await controller.load();
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
      expect(find.byKey(const Key('report-sales-other')), findsNothing);
      expect(find.text('26/10/2026 · 12:00 AM'), findsNWidgets(2));
      expect(find.text('26/10/2026 · 11:59 PM'), findsNWidgets(2));
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
      expect(find.text('25/10/2026 · 12:00 AM'), findsNWidgets(2));
      expect(find.text('26/10/2026 · 12:00 PM'), findsNWidgets(2));
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
      expect(find.text('26/10/2026 · 11:59 PM'), findsNWidgets(2));
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
      expect(find.text('Sin información'), findsNWidgets(4));
      expect(find.textContaining('historial disponible'), findsOneWidget);
      expect(find.text('COP 0,00'), findsNothing);
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
      expect(find.text('Sin información: 2 registro(s).'), findsNWidgets(2));
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
      expect(find.text('Incluye estimado: COP 120,00'), findsNWidgets(2));
      expect(find.text('Total vendido (parcial)'), findsNothing);
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
      expect(find.text('26/10/2026 · 11:59 PM'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );
}
