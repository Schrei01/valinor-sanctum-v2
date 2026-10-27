import 'package:flutter/foundation.dart';

import '../domain/reports_store.dart';

enum ReportMetric { sales, units, margin, outflows, money }

enum ReportGrouping { day, week, month, category, product, reason, account }

class ReportChartGroup {
  const ReportChartGroup(this.id, this.label, this.value, this.entries);
  final String id, label;
  final int value;
  final List<ReportChartEntry> entries;
}

class ReportChartEntry {
  const ReportChartEntry(this.date, this.concept, this.value, this.documentId);
  final DateTime date;
  final String concept, documentId;
  final int value;
}

class ReportsController extends ChangeNotifier {
  ReportsController({required this.store, DateTime Function()? now})
    : _now = now ?? DateTime.now;
  final ReportsStore store;
  final DateTime Function() _now;
  ReportsSnapshot? snapshot;
  bool busy = false, _disposed = false;
  String? error;
  String? categoryId, productId;
  ReportMetric metric = ReportMetric.sales;
  ReportGrouping grouping = ReportGrouping.day;
  List<ReportChartGroup> _chartGroups = const [];
  List<ReportChartGroup> get chartGroups => _chartGroups;

  DateTime get today {
    final n = _now().toUtc().subtract(const Duration(hours: 5));
    return DateTime.utc(n.year, n.month, n.day);
  }

  Future<void> load() => generate(
    start: snapshot?.period.startLocal ?? today,
    end: snapshot?.period.endLocal ?? today,
    timed: snapshot != null,
  );

  Future<void> generate({
    required DateTime start,
    required DateTime end,
    bool timed = false,
  }) async {
    if (busy || _disposed) return;
    ReportPeriod period;
    try {
      period = timed
          ? ReportPeriod.timed(start: start, end: end)
          : ReportPeriod(start: start, end: end);
    } catch (e) {
      error = e.toString();
      _emit();
      return;
    }
    busy = true;
    error = null;
    _emit();
    try {
      final next = await store.load(period);
      if (_disposed) return;
      next.validate();
      snapshot = next;
      if (categoryId != null &&
          !next.sales.any((s) => s.categoryId == categoryId)) {
        categoryId = null;
        productId = null;
      }
      if (productId != null &&
          !next
              .filteredSales(categoryId: categoryId)
              .any((s) => s.productId == productId)) {
        productId = null;
      }
      _refreshChart();
    } catch (e) {
      error = e.toString();
    } finally {
      busy = false;
      _emit();
    }
  }

  List<ReportSaleLine> get filteredSales =>
      snapshot?.filteredSales(categoryId: categoryId, productId: productId) ??
      const [];
  List<ReportProduct> get products =>
      snapshot?.products(categoryId: categoryId, productId: productId) ??
      const [];

  void selectCategory(String? id) {
    categoryId = id;
    productId = null;
    _safeRefreshChart();
    _emit();
  }

  void selectProduct(String? id) {
    productId = id;
    _safeRefreshChart();
    _emit();
  }

  void clearFilters() {
    categoryId = null;
    productId = null;
    _safeRefreshChart();
    _emit();
  }

  void selectMetric(ReportMetric value) {
    metric = value;
    if (!availableGroupings.contains(grouping)) {
      grouping = ReportGrouping.day;
    }
    _safeRefreshChart();
    _emit();
  }

  void selectGrouping(ReportGrouping value) {
    if (!availableGroupings.contains(value)) return;
    grouping = value;
    _safeRefreshChart();
    _emit();
  }

  List<ReportGrouping> get availableGroupings => switch (metric) {
    ReportMetric.sales || ReportMetric.units || ReportMetric.margin => const [
      ReportGrouping.day,
      ReportGrouping.week,
      ReportGrouping.month,
      ReportGrouping.category,
      ReportGrouping.product,
    ],
    ReportMetric.outflows => const [
      ReportGrouping.day,
      ReportGrouping.week,
      ReportGrouping.month,
      ReportGrouping.reason,
    ],
    ReportMetric.money => const [
      ReportGrouping.day,
      ReportGrouping.week,
      ReportGrouping.month,
      ReportGrouping.account,
    ],
  };

  void _refreshChart() {
    final data = snapshot;
    if (data == null) {
      _chartGroups = const [];
      return;
    }
    final groups = <String, List<ReportChartEntry>>{};
    final labels = <String, String>{};
    void add(
      String key,
      String label,
      DateTime date,
      String concept,
      int value,
      String id,
    ) {
      labels.putIfAbsent(key, () => label);
      groups
          .putIfAbsent(key, () => [])
          .add(ReportChartEntry(date, concept, value, id));
    }

    if (metric == ReportMetric.sales ||
        metric == ReportMetric.units ||
        metric == ReportMetric.margin) {
      for (final row in filteredSales) {
        if (metric == ReportMetric.margin && row.isEvent) continue;
        final label = switch (grouping) {
          ReportGrouping.category => row.categoryName,
          ReportGrouping.product => row.productName,
          _ => _dateGroup(row.occurredAtUtc),
        };
        final groupKey = switch (grouping) {
          ReportGrouping.category => 'category:${row.categoryId}',
          ReportGrouping.product => 'product:${row.productId}',
          _ => label,
        };
        add(
          groupKey,
          label,
          row.occurredAtUtc,
          row.productName,
          switch (metric) {
            ReportMetric.units => row.quantity,
            ReportMetric.margin => row.marginMinor,
            _ => row.salesMinor,
          },
          row.documentId,
        );
      }
    } else {
      for (final row in data.movements) {
        if (row.kind == ReportMovementKind.opening) continue;
        if (metric == ReportMetric.outflows &&
            (row.amountMinor >= 0 || row.kind == ReportMovementKind.transfer)) {
          continue;
        }
        final reason = row.kind == ReportMovementKind.purchasePayment
            ? 'Compras'
            : row.kind == ReportMovementKind.eventPayment
            ? 'Costos de eventos'
            : row.reason.isNotEmpty
            ? row.reason
            : row.concept;
        final label = switch (grouping) {
          ReportGrouping.reason => reason,
          ReportGrouping.account => row.accountName,
          _ => _dateGroup(row.occurredAtUtc),
        };
        add(
          grouping == ReportGrouping.account
              ? 'account:${row.accountId}'
              : label,
          label,
          row.occurredAtUtc,
          row.concept,
          metric == ReportMetric.outflows
              ? reportMinor(-BigInt.from(row.amountMinor))
              : row.amountMinor,
          row.documentId,
        );
      }
    }
    final sorted = groups.entries.toList()
      ..sort((a, b) {
        final label = labels[a.key]!.compareTo(labels[b.key]!);
        return label == 0 ? a.key.compareTo(b.key) : label;
      });
    _chartGroups = List.unmodifiable(
      sorted.map(
        (entry) => ReportChartGroup(
          entry.key,
          labels[entry.key]!,
          reportSum(entry.value.map((row) => row.value)),
          List.unmodifiable(entry.value),
        ),
      ),
    );
  }

  void _safeRefreshChart() {
    try {
      _refreshChart();
    } catch (e) {
      _chartGroups = const [];
      error = e.toString();
    }
  }

  String _dateGroup(DateTime utc) {
    final local = utc.subtract(const Duration(hours: 5));
    var day = DateTime.utc(local.year, local.month, local.day);
    if (grouping == ReportGrouping.week) {
      day = day.subtract(Duration(days: day.weekday - 1));
    }
    if (grouping == ReportGrouping.month) {
      return '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}';
    }
    final label =
        '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    return grouping == ReportGrouping.week ? 'Semana $label' : label;
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
