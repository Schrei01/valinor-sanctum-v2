import 'package:flutter/material.dart';
import '../../../core/presentation/grouped_number_formatter.dart';

import '../../inventory/presentation/inventory_widgets.dart';
import '../../workspace/domain/business_profile.dart';
import '../application/reports_controller.dart';
import '../domain/reports_store.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({
    super.key,
    required this.controller,
    required this.profile,
  });
  final ReportsController controller;
  final BusinessProfile profile;

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  late DateTime? _start = widget.controller.snapshot?.period.startLocal;
  DateTime? _chosenEnd;
  DateTime get _end =>
      _chosenEnd ??
      widget.controller.snapshot?.period.endLocal ??
      widget.controller.nowLocal;
  int _page = 0;
  ReportsSnapshot? _pagedSnapshot;
  String? _rangeError;

  String _moment(DateTime value) {
    final day =
        '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year.toString().padLeft(4, '0')}';
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    return '$day · $hour:${value.minute.toString().padLeft(2, '0')} ${value.hour < 12 ? 'AM' : 'PM'}';
  }

  Future<void> _pick(bool start) async {
    final initial = start ? (_start ?? widget.controller.nowLocal) : _end;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1),
      lastDate: DateTime(9998, 12, 31),
      helpText: start ? 'Fecha inicial' : 'Fecha final',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: start ? 'Hora inicial' : 'Hora final',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
      hourLabelText: 'Hora',
      minuteLabelText: 'Minuto',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;
    setState(() {
      final selected = DateTime.utc(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      if (start) {
        _start = selected;
      } else {
        _chosenEnd = selected;
      }
      _rangeError = null;
    });
  }

  Future<void> _generate() async {
    if (_start == null) {
      setState(() => _rangeError = 'Elige una fecha y hora inicial.');
      return;
    }
    if (_end.isBefore(_start!)) {
      setState(
        () => _rangeError =
            'La fecha y hora final deben ser iguales o posteriores a las iniciales.',
      );
      return;
    }
    setState(() => _rangeError = null);
    final end = _end;
    setState(() => _chosenEnd = end);
    await widget.controller.generate(start: _start!, end: end, timed: true);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final data = c.snapshot;
      if (!identical(_pagedSnapshot, data)) {
        _pagedSnapshot = data;
        _page = 0;
      }
      return Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Reportes',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: c.busy || data == null ? null : c.load,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Actualizar'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _selector(true, 'Fecha y hora inicial', _start, c.busy),
                  if (_start != null)
                    IconButton(
                      key: const Key('report-clear-start'),
                      tooltip: 'Quitar fecha inicial',
                      onPressed: c.busy
                          ? null
                          : () => setState(() {
                              _start = null;
                              _rangeError = null;
                            }),
                      icon: const Icon(Icons.clear, size: 18),
                    ),
                  _selector(false, 'Fecha y hora final', _end, c.busy),
                  FilledButton.icon(
                    key: const Key('report-generate'),
                    onPressed: c.busy ? null : _generate,
                    icon: const Icon(Icons.receipt_long_outlined, size: 18),
                    label: Text(c.busy ? 'Consultando…' : 'Generar reporte'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Horario de Bogotá · El rango incluye todo el minuto final.',
                style: _muted,
              ),
              const SizedBox(height: 14),
              if (_rangeError != null) InventoryNotice(text: _rangeError!),
              if (c.busy) const LinearProgressIndicator(),
              if (c.error != null)
                InventoryNotice(
                  text:
                      c.error.toString() +
                      (data == null
                          ? ''
                          : ' Se conserva el último reporte generado.'),
                  onRetry: c.busy ? null : c.load,
                ),
              if (data == null && !c.busy)
                const Text('Elige las fechas y horas y genera el reporte.'),
              if (data != null) _receipt(data),
              if (data != null) ...[const SizedBox(height: 16), _items(data)],
            ],
          ),
        ),
      );
    },
  );

  TextStyle get _muted => TextStyle(
    fontSize: 12,
    height: 1.4,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  );
  Widget _selector(bool start, String label, DateTime? moment, bool busy) =>
      SizedBox(
        width: 258,
        child: OutlinedButton.icon(
          key: Key(start ? 'report-start' : 'report-end'),
          onPressed: busy ? null : () => _pick(start),
          icon: const Icon(Icons.calendar_month_outlined, size: 18),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            alignment: Alignment.centerLeft,
          ),
          label: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 2),
              Text(moment == null ? 'Sin seleccionar' : _moment(moment)),
            ],
          ),
        ),
      );

  Widget _items(ReportsSnapshot data) {
    final rows = data.items;
    final pages = (rows.length / 10).ceil();
    final first = _page * 10;
    final last = (first + 10).clamp(0, rows.length);
    return Card(
      key: const Key('report-items'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Ítems vendidos'),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              const Text('No hay ítems vendidos en este rango.')
            else ...[
              const Text(
                'Más recientes primero · * Importe histórico estimado.',
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 20,
                  columns: const [
                    DataColumn(label: Text('Fecha y hora')),
                    DataColumn(label: Text('Producto')),
                    DataColumn(label: Text('Cantidad'), numeric: true),
                    DataColumn(label: Text('Pago')),
                    DataColumn(label: Text('Importe'), numeric: true),
                  ],
                  rows: [
                    for (final item in rows.skip(first).take(10))
                      DataRow(
                        key: ValueKey('report-item-${item.id}'),
                        cells: [
                          DataCell(
                            Text(
                              _moment(
                                item.occurredAtUtc.subtract(
                                  const Duration(hours: 5),
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(width: 220, child: Text(item.productName)),
                          ),
                          DataCell(
                            Text(
                              item.quantity == null
                                  ? 'Sin información'
                                  : GroupedNumberFormatter.format(
                                      '${item.quantity}',
                                    ),
                            ),
                          ),
                          DataCell(Text(item.paymentMethod)),
                          DataCell(
                            Text(
                              item.amountMinor == null
                                  ? 'Sin información'
                                  : '${inventoryMoney(item.amountMinor!, widget.profile)}${item.isEstimated ? ' *' : ''}',
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${first + 1}–$last de ${rows.length} · Página ${_page + 1} de $pages',
                      key: const Key('report-items-page'),
                    ),
                  ),
                  IconButton(
                    key: const Key('report-items-previous'),
                    tooltip: 'Página anterior',
                    onPressed: _page == 0
                        ? null
                        : () => setState(() => _page--),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  IconButton(
                    key: const Key('report-items-next'),
                    tooltip: 'Página siguiente',
                    onPressed: _page + 1 >= pages
                        ? null
                        : () => setState(() => _page++),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _receipt(ReportsSnapshot data) {
    final sales = data.saleTotals;
    final outflows = data.outflowTotals;
    final colors = Theme.of(context).colorScheme;
    return Card(
      key: const Key('report-receipt'),
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.receipt_long_outlined,
                    color: colors.onPrimaryContainer,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.profile.businessName,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'RESUMEN DE ACTIVIDAD',
                        style: _muted.copyWith(
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Del ${_moment(data.period.startLocal)} al ${_moment(data.period.endLocal)}',
              key: const Key('report-period'),
              style: _muted,
            ),
            const Divider(height: 24),
            _sectionTitle('Saldos'),
            const SizedBox(height: 8),
            _balances(data),
            const Divider(height: 24),
            LayoutBuilder(
              builder: (context, constraints) {
                final salesPanel = _salesPanel(sales);
                final outflowPanel = _outflowPanel(outflows);
                if (constraints.maxWidth < 660) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      salesPanel,
                      const Divider(height: 24),
                      outflowPanel,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: salesPanel),
                    const SizedBox(width: 28),
                    Expanded(child: outflowPanel),
                  ],
                );
              },
            ),
            const Divider(height: 24),
            _transfers(data),
            const SizedBox(height: 10),
            if (data.usesHistoricalBalances)
              _note(
                'Los saldos anteriores a la apertura usan el historial convertido de la copia.',
              ),
            if (!data.openingBalancesKnown || !data.closingBalancesKnown)
              _note(
                'Sin información: el historial disponible no contiene algunos saldos del corte.',
              ),
            if (sales.estimatedSales > 0)
              _note(
                'Incluye ${sales.estimatedSales} registro(s) de ventas antiguas estimadas · ${inventoryMoney(sales.estimatedTotalMinor, widget.profile)}. Cantidad × PVP de la copia; el precio aplicado y los descuentos antiguos no se conservaron.',
              ),
            if (sales.unpricedSales > 0)
              _note(
                'Hay ${sales.unpricedSales} registro(s) de ventas antiguas sin información. Los importes parciales excluyen esos registros.',
              ),
            if (outflows.unpricedRecords > 0)
              _note(
                'Egresos parciales: ${outflows.unpricedRecords} registro(s) sin importe válido.',
              ),
            _note(
              'Ventas: Efectivo + Transferencia + Deudas; sin abonos. Egresos: salidas registradas de Caja y Nequi; sin transferencias internas.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _note(String text) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text(text, style: _muted),
  );
  Widget _transfers(ReportsSnapshot data) {
    final routes = data.transferRoutes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _sectionTitle('Transferencias entre cuentas')),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  data.unpricedTransferRecords > 0
                      ? 'Total trasladado (parcial)'
                      : 'Total trasladado',
                  style: _muted,
                ),
                _amount(
                  'report-transfers-total',
                  data.transferTotalMinor ??
                      (data.knownTransferTotalMinor == 0
                          ? null
                          : data.knownTransferTotalMinor),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (routes.isEmpty && data.unpricedTransferRecords == 0)
          Text('Sin transferencias en este rango.', style: _muted),
        if (routes.isNotEmpty)
          Table(
            columnWidths: const {
              0: FlexColumnWidth(3),
              1: FixedColumnWidth(44),
              2: FlexColumnWidth(1.4),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                children: [
                  Text('Origen / Destino', style: _muted),
                  Text('Mov.', textAlign: TextAlign.center, style: _muted),
                  Text('Importe', textAlign: TextAlign.right, style: _muted),
                ],
              ),
              for (var i = 0; i < routes.length; i++)
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Semantics(
                        key: Key('report-transfer-route-$i'),
                        label:
                            '${routes[i].sourceName} → ${routes[i].destinationName}',
                        child: Wrap(
                          spacing: 5,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              routes[i].sourceName,
                              style: const TextStyle(fontSize: 13),
                            ),
                            const Icon(Icons.arrow_forward_rounded, size: 14),
                            Text(
                              routes[i].destinationName,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Text(
                      '${routes[i].count}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13),
                    ),
                    _amount('report-transfer-amount-$i', routes[i].amountMinor),
                  ],
                ),
            ],
          ),
        if (data.unpricedTransferRecords > 0)
          _note(
            'Total transferido parcial: ${data.unpricedTransferRecords} registro(s) sin información de importe.',
          ),
        if (data.transfers.any((t) => t.isHistorical))
          _note(
            'Incluye transferencias registradas en la copia, con sus cuentas originales.',
          ),
      ],
    );
  }

  Widget _sectionTitle(String title) => Text(
    title.toUpperCase(),
    style: TextStyle(
      fontSize: 12,
      letterSpacing: 1,
      fontWeight: FontWeight.w700,
      color: Theme.of(context).colorScheme.primary,
    ),
  );
  Widget _balances(ReportsSnapshot data) {
    final cash = data.accounts
        .where((a) => a.role == ReportAccountRole.cash)
        .firstOrNull;
    final transfer = data.accounts
        .where((a) => a.role == ReportAccountRole.transfer)
        .firstOrNull;
    Widget cell(Widget child) =>
        Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: child);
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1),
        1: FlexColumnWidth(1.25),
        2: FlexColumnWidth(1.25),
      },
      children: [
        TableRow(
          children: [
            cell(Text('Cuenta', style: _muted)),
            cell(Text('Inicial', textAlign: TextAlign.right, style: _muted)),
            cell(Text('Final', textAlign: TextAlign.right, style: _muted)),
          ],
        ),
        for (final entry in [
          ('Caja', 'cash', cash),
          ('Nequi', 'nequi', transfer),
        ])
          TableRow(
            children: [
              cell(Text(entry.$1)),
              cell(
                _amount('report-opening-${entry.$2}', entry.$3?.openingMinor),
              ),
              cell(
                _amount('report-closing-${entry.$2}', entry.$3?.closingMinor),
              ),
            ],
          ),
      ],
    );
  }

  Widget _salesPanel(ReportSalesTotals totals) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle('Ventas del período'),
      const SizedBox(height: 8),
      _saleRow(
        'report-sales-cash',
        'Caja',
        totals.cashTotalMinor,
        totals.knownCashMinor,
        totals.unpricedCashSales,
      ),
      _saleRow(
        'report-sales-transfer',
        'Nequi / Transferencia',
        totals.transferTotalMinor,
        totals.knownTransferMinor,
        totals.unpricedTransferSales,
      ),
      _saleRow(
        'report-sales-credit',
        'Deudas',
        totals.creditTotalMinor,
        totals.knownCreditMinor,
        totals.unpricedCreditSales,
      ),
      if (totals.knownOtherMinor != 0 || totals.unpricedOtherSales != 0)
        _saleRow(
          'report-sales-other',
          'Otros medios',
          totals.otherTotalMinor,
          totals.knownOtherMinor,
          totals.unpricedOtherSales,
        ),
      _saleRow(
        'report-sales-total',
        'Total vendido',
        totals.totalMinor,
        totals.knownTotalMinor,
        totals.unpricedSales,
        total: true,
      ),
    ],
  );
  Widget _outflowPanel(ReportOutflowTotals totals) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle('Egresos del período'),
      const SizedBox(height: 8),
      _saleRow(
        'report-outflows-cash',
        'Caja',
        totals.cashTotalMinor,
        totals.cashMinor,
        totals.unpricedCashRecords,
      ),
      _saleRow(
        'report-outflows-transfer',
        'Nequi / Transferencia',
        totals.transferTotalMinor,
        totals.transferMinor,
        totals.unpricedTransferRecords,
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Compras, gastos y costos de eventos pagados.',
          style: _muted,
        ),
      ),
      _saleRow(
        'report-outflows-total',
        'Total egresos',
        totals.totalMinor,
        totals.knownTotalMinor,
        totals.unpricedRecords,
        total: true,
        expense: true,
      ),
    ],
  );
  Widget _saleRow(
    String key,
    String label,
    int? amount,
    int known,
    int missing, {
    bool total = false,
    bool expense = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: total ? 10 : 0,
        vertical: total ? 10 : 8,
      ),
      margin: EdgeInsets.only(top: total ? 6 : 0),
      decoration: total
          ? BoxDecoration(
              color: expense
                  ? colors.tertiaryContainer.withValues(alpha: 0.5)
                  : colors.primaryContainer.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
            )
          : null,
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              missing > 0 ? '$label (parcial)' : label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: total ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: _amount(
              key,
              amount ?? (known == 0 ? null : known),
              total: total,
            ),
          ),
        ],
      ),
    );
  }

  Widget _amount(String key, int? amount, {bool total = false}) => Text(
    amount == null ? 'Sin información' : inventoryMoney(amount, widget.profile),
    key: Key(key),
    textAlign: TextAlign.right,
    style: TextStyle(
      fontSize: total ? 17 : 15,
      fontWeight: total ? FontWeight.w700 : FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
}
