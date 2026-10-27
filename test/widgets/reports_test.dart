import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/features/reports/application/reports_controller.dart';
import 'package:valinor_sanctum_2/features/reports/presentation/report_bar_chart.dart';
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

  Future<void> enter(WidgetTester tester, String key, String value) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.enterText(finder, value);
    await tester.pumpAndSettle();
  }

  Finder keyed(String prefix) => find.byWidgetPredicate(
    (widget) =>
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith(prefix),
  );

  testWidgets(
    'invalid calendar date and inverted range do not read or replace report',
    (tester) async {
      await open(tester);
      await enter(tester, 'report-start-date', '31/02/2026');
      await tap(tester, find.byKey(const Key('report-generate')));
      expect(find.text('Usa dd/mm/aaaa.'), findsOneWidget);
      expect(store.queries, hasLength(1));
      await enter(tester, 'report-start-date', '27/10/2026');
      await tap(tester, find.byKey(const Key('report-generate')));
      expect(
        find.text('Debe ser igual o posterior al inicio.'),
        findsOneWidget,
      );
      expect(store.queries, hasLength(1));
      await enter(tester, 'report-start-date', '25/10/2026');
      await tap(tester, find.byKey(const Key('report-generate')));
      expect(store.queries, hasLength(2));
      expect(
        find.text('Reporte del 25/10/2026 00:00 al 26/10/2026 23:59'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'hour inputs validate a same-day interval and include its final minute',
    (tester) async {
      await open(tester);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('report-start-time')))
            .controller!
            .text,
        '00:00',
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('report-end-time')))
            .controller!
            .text,
        '23:59',
      );
      await enter(tester, 'report-start-time', '25:00');
      await tap(tester, find.byKey(const Key('report-generate')));
      expect(find.text('Usa HH:mm (00–23).'), findsOneWidget);
      expect(store.queries, hasLength(1));
      await enter(tester, 'report-start-time', '14:30');
      await enter(tester, 'report-end-time', '14:29');
      await tap(tester, find.byKey(const Key('report-generate')));
      expect(
        find.text('Debe ser igual o posterior al inicio.'),
        findsOneWidget,
      );
      expect(store.queries, hasLength(1));
      await enter(tester, 'report-end-time', '14:30');
      await tap(tester, find.byKey(const Key('report-generate')));
      final p = store.queries.last;
      expect(p.startUtc, DateTime.utc(2026, 10, 26, 19, 30));
      expect(p.endExclusiveUtc, DateTime.utc(2026, 10, 26, 19, 31));
      expect(
        find.text('Reporte del 26/10/2026 14:30 al 26/10/2026 14:30'),
        findsOneWidget,
      );
      await tap(tester, find.byTooltip('Elegir Hora inicial'));
      expect(find.byType(TimePickerDialog), findsOneWidget);
      await tap(tester, find.text('Cancelar'));
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('report-start-time')))
            .controller!
            .text,
        '14:30',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'uncategorized sold products can be selected separately from all categories',
    (tester) async {
      store.uncategorized = true;
      await open(tester);
      expect(tester.takeException(), isNull);
      await tap(tester, keyed('report-category-'));
      await tap(tester, find.text('Sin categoría').last);
      expect(controller.categoryId, '');
      expect(controller.products.single.productId, 'p1');
      expect(controller.snapshot!.salesMinor, 30000);
      await tap(tester, keyed('report-category-'));
      await tap(tester, find.text('Todas las categorías').last);
      expect(controller.categoryId, isNull);
      expect(controller.products, hasLength(2));
      expect(store.queries, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'negative margin bars remain visible and open their underlying sale detail',
    (tester) async {
      await open(tester);
      await tap(tester, find.byKey(const Key('report-chart-metric')));
      await tap(tester, find.text('Margen de productos físicos').last);
      expect(controller.metric, ReportMetric.margin);
      final chart = tester.widget<ReportBarChart>(find.byType(ReportBarChart));
      expect(chart.data.single.value, -2000);
      await tap(
        tester,
        find.byKey(ValueKey('report-bar-${chart.data.single.id}')),
      );
      expect(find.textContaining('Producto con pérdida'), findsWidgets);
      expect(find.text('Total de las partidas: COP -20,00'), findsOneWidget);
      await tap(tester, find.text('Cerrar'));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'narrow view preserves unknown balances and shows actual event result separately',
    (tester) async {
      store.unknownBalances = true;
      await open(tester, size: const Size(620, 1000));
      expect(find.text('Sin información'), findsNWidgets(4));
      expect(find.text('Inicial: Sin información'), findsOneWidget);
      expect(find.text('Final: Sin información'), findsOneWidget);
      await tester.ensureVisible(find.text('Resultado acumulado por evento'));
      await tester.pumpAndSettle();
      expect(find.text('COP 180,00'), findsWidgets);
      expect(find.text('Costo real'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'summary drilldown separates abonos from sales and preserves last report on read failure',
    (tester) async {
      await open(tester);
      await tap(tester, find.text('Abonos de deudores').first);
      expect(find.textContaining('Abono anterior'), findsOneWidget);
      expect(find.text('Total de las partidas: COP 50,00'), findsOneWidget);
      await tap(tester, find.text('Cerrar'));
      store.failure = StateError('Lectura sintética fallida');
      await tap(tester, find.byKey(const Key('report-generate')));
      expect(
        find.textContaining('Se conserva el último reporte generado.'),
        findsOneWidget,
      );
      expect(controller.snapshot!.salesMinor, 30000);
      expect(tester.takeException(), isNull);
    },
  );
}
