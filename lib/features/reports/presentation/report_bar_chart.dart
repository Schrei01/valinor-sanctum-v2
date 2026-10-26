import 'package:flutter/material.dart';

class ReportBarDatum {
  const ReportBarDatum({
    required this.label,
    required this.value,
    this.id = '',
  });
  final String id, label;
  final int value;
}

/// Geometry uses bounded ratios; monetary labels retain their exact integers.
class ReportBarChart extends StatefulWidget {
  const ReportBarChart({
    super.key,
    required this.data,
    required this.formatValue,
    required this.valueLabel,
    this.onSelect,
  });
  final List<ReportBarDatum> data;
  final String Function(int) formatValue;
  final String valueLabel;
  final void Function(ReportBarDatum)? onSelect;

  @override
  State<ReportBarChart> createState() => _ReportBarChartState();
}

class _ReportBarChartState extends State<ReportBarChart> {
  int _page = 0;
  static const _pageSize = 10;

  @override
  void didUpdateWidget(covariant ReportBarChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.data, widget.data)) _page = 0;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.data.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Text('No hay movimientos para esta gráfica y sus filtros.'),
      );
    }
    final pages = (widget.data.length + _pageSize - 1) ~/ _pageSize;
    final page = _page.clamp(0, pages - 1);
    final visible = widget.data.skip(page * _pageSize).take(_pageSize).toList();
    final positive = visible.fold<BigInt>(BigInt.zero, (max, item) {
      final value = BigInt.from(item.value);
      return value > max ? value : max;
    });
    final negative = visible.fold<BigInt>(BigInt.zero, (min, item) {
      final value = BigInt.from(item.value);
      return value < min ? value : min;
    });
    final span = positive - negative;
    final actualSpan = span == BigInt.zero ? BigInt.one : span;
    double ratio(BigInt n) =>
        ((n * BigInt.from(100000)) ~/ actualSpan).toInt() / 100000;
    final baseline = ratio(positive);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Las barras rojas representan valores negativos.'),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth < visible.length * 76
                ? visible.length * 76.0
                : constraints.maxWidth;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: width,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final item in visible)
                      Expanded(
                        child: Semantics(
                          label:
                              '${item.label}: ${widget.formatValue(item.value)}',
                          button: widget.onSelect != null,
                          child: Tooltip(
                            message:
                                '${item.label}: ${widget.formatValue(item.value)}',
                            child: InkWell(
                              onTap: widget.onSelect == null
                                  ? null
                                  : () => widget.onSelect!(item),
                              child: Column(
                                children: [
                                  SizedBox(
                                    height: 210,
                                    width: double.infinity,
                                    child: CustomPaint(
                                      key: ValueKey(
                                        'report-bar-${item.id.isEmpty ? item.label : item.id}',
                                      ),
                                      painter: _BarPainter(
                                        valueRatio: ratio(
                                          BigInt.from(item.value),
                                        ),
                                        baseline: baseline,
                                        negative: item.value < 0,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    child: Text(
                                      item.label,
                                      textAlign: TextAlign.center,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 20),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            showCheckboxColumn: false,
            columns: [
              const DataColumn(label: Text('Grupo')),
              DataColumn(label: Text(widget.valueLabel), numeric: true),
            ],
            rows: [
              for (final item in visible)
                DataRow(
                  onSelectChanged: widget.onSelect == null
                      ? null
                      : (_) => widget.onSelect!(item),
                  cells: [
                    DataCell(Text(item.label)),
                    DataCell(
                      Text(
                        widget.formatValue(item.value),
                        style: item.value < 0
                            ? TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              )
                            : null,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        if (pages > 1)
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(
                'Grupos ${page * _pageSize + 1}–${page * _pageSize + visible.length} de ${widget.data.length}',
              ),
              IconButton(
                tooltip: 'Grupos anteriores',
                onPressed: page == 0
                    ? null
                    : () => setState(() => _page = page - 1),
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: 'Grupos siguientes',
                onPressed: page + 1 >= pages
                    ? null
                    : () => setState(() => _page = page + 1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
      ],
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.valueRatio,
    required this.baseline,
    required this.negative,
  });
  final double valueRatio, baseline;
  final bool negative;
  @override
  void paint(Canvas canvas, Size size) {
    const padding = 8.0;
    final height = size.height - padding * 2;
    final y = padding + baseline * height;
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = const Color(0xFF81948C)
        ..strokeWidth = 1,
    );
    final end = y - valueRatio * height;
    final top = y < end ? y : end;
    final bottom = y > end ? y : end;
    final left = size.width * .22;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(left, top, size.width - left, bottom),
        const Radius.circular(4),
      ),
      Paint()
        ..color = negative ? const Color(0xFFB3463D) : const Color(0xFF117263),
    );
  }

  @override
  bool shouldRepaint(covariant _BarPainter oldDelegate) =>
      valueRatio != oldDelegate.valueRatio ||
      baseline != oldDelegate.baseline ||
      negative != oldDelegate.negative;
}
