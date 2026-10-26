import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/features/reports/application/reports_controller.dart';
import 'package:valinor_sanctum_2/features/reports/domain/reports_store.dart';
import '../support/fake_reports_store.dart';

ReportsSnapshot withSales(ReportsSnapshot s, List<ReportSaleLine> sales) =>
    ReportsSnapshot(
      period: s.period,
      accounts: s.accounts,
      movements: s.movements,
      sales: sales,
      transfers: s.transfers,
      expenses: s.expenses,
      debtChanges: s.debtChanges,
      events: s.events,
      debtOpeningMinor: s.debtOpeningMinor,
      debtClosingMinor: s.debtClosingMinor,
      coverageStartUtc: s.coverageStartUtc,
      openingBalancesKnown: s.openingBalancesKnown,
      closingBalancesKnown: s.closingBalancesKnown,
      warnings: s.warnings,
    );
ReportSaleLine sale(
  String id,
  String name,
  DateTime at, {
  int revenue = 100,
  String product = 'p1',
}) => ReportSaleLine(
  id: id,
  documentId: 'sale-$id',
  saleLabel: 'Cuenta',
  occurredAtUtc: at,
  productId: product,
  productName: name,
  categoryId: 'food',
  categoryName: 'Comestible',
  quantity: 1,
  salesMinor: revenue,
  costMinor: 0,
  cashMinor: revenue,
  transferMinor: 0,
  creditMinor: 0,
  isEvent: false,
);

void main() {
  test(
    'today uses Bogotá and inclusive days stop before next local midnight',
    () async {
      final store = FakeReportsStore();
      final c = ReportsController(
        store: store,
        now: () => DateTime.utc(2026, 10, 26, 2),
      );
      addTearDown(c.dispose);
      await c.load();
      final p = store.queries.single;
      expect(p.startDate, DateTime.utc(2026, 10, 25));
      expect(
        p.contains(DateTime.utc(2026, 10, 25, 4, 59, 59, 999, 999)),
        isFalse,
      );
      expect(p.contains(DateTime.utc(2026, 10, 25, 5)), isTrue);
      expect(
        p.contains(DateTime.utc(2026, 10, 26, 4, 59, 59, 999, 999)),
        isTrue,
      );
      expect(p.contains(DateTime.utc(2026, 10, 26, 5)), isFalse);
    },
  );
  test(
    'invalid range and failed read preserve last generated report',
    () async {
      final store = FakeReportsStore();
      final controller = ReportsController(store: store);
      addTearDown(controller.dispose);
      await controller.load();
      final old = controller.snapshot;
      await controller.generate(
        start: DateTime.utc(2026, 10, 27),
        end: DateTime.utc(2026, 10, 26),
      );
      expect(store.queries, hasLength(1));
      expect(controller.snapshot, same(old));
      expect(controller.error, isNotNull);
      store.failure = StateError('No se pudo leer');
      await controller.load();
      expect(controller.snapshot, same(old));
      expect(controller.error, contains('No se pudo leer'));
    },
  );
  test(
    'sales filters leave global summary intact and margin bars retain losses',
    () async {
      final c = ReportsController(store: FakeReportsStore());
      addTearDown(c.dispose);
      await c.load();
      c.selectCategory('food');
      expect(c.products.single.productId, 'p1');
      expect(c.snapshot!.salesMinor, 30000);
      c.selectMetric(ReportMetric.margin);
      expect(c.chartGroups.single.value, -2000);
      expect(c.chartGroups.single.entries.single.documentId, 'physical-sale');
      c.selectCategory('event');
      expect(c.chartGroups, isEmpty);
      c.selectMetric(ReportMetric.outflows);
      c.selectGrouping(ReportGrouping.reason);
      expect(c.chartGroups.single.label, 'Aseo');
      expect(c.chartGroups.single.value, 7000);
      c.selectMetric(ReportMetric.money);
      expect(c.availableGroupings, contains(ReportGrouping.account));
      expect(c.grouping, ReportGrouping.day);
      expect(c.chartGroups.single.value, 24000);
    },
  );
  test(
    'chart product identity survives rename and distinguishes equal names',
    () async {
      final store = FakeReportsStore()
        ..build = (period) {
          final at = period.startUtc;
          return withSales(reportFixture(period), [
            sale('one', 'Nombre anterior', at),
            sale('two', 'Nombre nuevo', at),
            sale('three', 'Nombre anterior', at, product: 'different'),
          ]);
        };
      final c = ReportsController(store: store);
      addTearDown(c.dispose);
      await c.load();
      c.selectGrouping(ReportGrouping.product);
      expect(c.chartGroups, hasLength(2));
      expect(c.chartGroups.singleWhere((g) => g.id == 'product:p1').value, 200);
      expect(
        c.chartGroups.singleWhere((g) => g.id == 'product:different').value,
        100,
      );
    },
  );
  test('overflow is rejected before exposing a snapshot to widgets', () async {
    final store = FakeReportsStore();
    final controller = ReportsController(store: store);
    addTearDown(controller.dispose);
    await controller.load();
    final old = controller.snapshot;
    store.build = (period) => withSales(reportFixture(period), [
      sale(
        'huge',
        'Importe máximo',
        period.startUtc,
        revenue: 0x7fffffffffffffff,
      ),
      sale(
        'extra',
        'Importe adicional',
        period.startUtc,
        revenue: 1,
        product: 'p2',
      ),
    ]);
    await controller.load();
    expect(controller.snapshot, same(old));
    expect(controller.error, contains('rango monetario'));
  });
  test(
    'overlapping generation is ignored while one coherent read is pending',
    () async {
      final store = FakeReportsStore()..gate = Completer<void>();
      final c = ReportsController(store: store);
      addTearDown(c.dispose);
      final pending = c.load();
      await c.generate(
        start: DateTime.utc(2026, 10, 1),
        end: DateTime.utc(2026, 10, 2),
      );
      expect(store.queries, hasLength(1));
      expect(c.busy, isTrue);
      store.gate!.complete();
      await pending;
      expect(c.snapshot, isNotNull);
      expect(c.busy, isFalse);
    },
  );
}
