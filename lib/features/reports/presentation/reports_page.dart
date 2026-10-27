import 'package:flutter/material.dart';

import '../../inventory/presentation/inventory_widgets.dart';
import '../../workspace/domain/business_profile.dart';
import '../application/reports_controller.dart';
import '../domain/reports_store.dart';
import 'report_bar_chart.dart';

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
  final _form = GlobalKey<FormState>();
  late final _start = TextEditingController(
    text: _date(
      widget.controller.snapshot?.period.startDate ?? widget.controller.today,
    ),
  );
  late final _end = TextEditingController(
    text: _date(
      widget.controller.snapshot?.period.endDate ?? widget.controller.today,
    ),
  );
  late final _startTime = TextEditingController(
    text: _time(
      widget.controller.snapshot?.period.startLocal ?? widget.controller.today,
    ),
  );
  late final _endTime = TextEditingController(
    text: widget.controller.snapshot == null
        ? '23:59'
        : _time(widget.controller.snapshot!.period.endLocal),
  );
  int _productsPage = 0;
  String _money(int n) => inventoryMoney(n, widget.profile);
  String _balance(int? n) => n == null ? 'Sin información' : _money(n);
  String _date(DateTime day) =>
      '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}/${day.year.toString().padLeft(4, '0')}';
  String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  String _localMoment(DateTime value) => '${_date(value)} ${_time(value)}';
  String _moment(DateTime utc) {
    final d = utc.subtract(const Duration(hours: 5));
    return '${_date(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  DateTime? _parseDate(String? text) {
    final m = RegExp(
      r'^(\d{2})/(\d{2})/(\d{4})$',
    ).firstMatch(text?.trim() ?? '');
    if (m == null) return null;
    final day = int.parse(m[1]!),
        month = int.parse(m[2]!),
        year = int.parse(m[3]!);
    final value = DateTime.utc(year, month, day);
    return value.day == day &&
            value.month == month &&
            value.year == year &&
            year >= 1 &&
            year <= 9998
        ? value
        : null;
  }

  TimeOfDay? _parseTime(String? text) {
    final m = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(text?.trim() ?? '');
    if (m == null) return null;
    final hour = int.parse(m[1]!), minute = int.parse(m[2]!);
    return hour < 24 && minute < 60
        ? TimeOfDay(hour: hour, minute: minute)
        : null;
  }

  DateTime? _selectedMoment(bool start) {
    final date = _parseDate(start ? _start.text : _end.text);
    final time = _parseTime(start ? _startTime.text : _endTime.text);
    if (date == null || time == null) return null;
    return DateTime.utc(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
  }

  Future<void> _pickTime(TextEditingController field) async {
    final selected = await showTimePicker(
      context: context,
      initialTime:
          _parseTime(field.text) ?? const TimeOfDay(hour: 0, minute: 0),
      helpText: field == _startTime ? 'Hora inicial' : 'Hora final',
      cancelText: 'Cancelar',
      confirmText: 'Elegir',
      hourLabelText: 'Hora',
      minuteLabelText: 'Minuto',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (selected != null && mounted) {
      setState(
        () => field.text =
            '${selected.hour.toString().padLeft(2, '0')}:${selected.minute.toString().padLeft(2, '0')}',
      );
    }
  }

  Future<void> _pick(TextEditingController field) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _parseDate(field.text) ?? widget.controller.today,
      firstDate: DateTime(1),
      lastDate: DateTime(9998, 12, 31),
      helpText: field == _start ? 'Fecha inicial' : 'Fecha final',
      cancelText: 'Cancelar',
      confirmText: 'Elegir',
    );
    if (selected != null && mounted) {
      setState(() => field.text = _date(selected));
    }
  }

  Future<void> _generate() async {
    if (!_form.currentState!.validate()) return;
    _productsPage = 0;
    await widget.controller.generate(
      start: _selectedMoment(true)!,
      end: _selectedMoment(false)!,
      timed: true,
    );
  }

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    _startTime.dispose();
    _endTime.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      var data = c.snapshot;
      String? displayError;
      try {
        if (data != null) _validateDisplay(data);
      } catch (e) {
        displayError = e.toString();
        data = null;
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InventoryPageHeading(
            title: 'Reportes',
            subtitle:
                'Consulta ventas, dinero, deudas y resultados de un período. Solo se incluyen operaciones confirmadas.',
            busy: c.busy,
            onRefresh: c.load,
          ),
          Form(
            key: _form,
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _dateField(
                  'report-start-date',
                  'Fecha inicial',
                  _start,
                  c.busy,
                ),
                _timeField(
                  'report-start-time',
                  'Hora inicial',
                  _startTime,
                  c.busy,
                ),
                _dateField('report-end-date', 'Fecha final', _end, c.busy),
                _timeField('report-end-time', 'Hora final', _endTime, c.busy),
                FilledButton.icon(
                  key: const Key('report-generate'),
                  onPressed: c.busy ? null : _generate,
                  icon: const Icon(Icons.bar_chart),
                  label: Text(c.busy ? 'Generando…' : 'Generar reporte'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Horario de Bogotá · formato de 24 horas. Se incluye todo el minuto final. Para días completos usa 00:00–23:59.',
          ),
          const SizedBox(height: 20),
          if (c.busy)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: LinearProgressIndicator(),
            ),
          if (c.error != null)
            InventoryNotice(
              text:
                  '${c.error}${data == null ? '' : ' Se conserva el último reporte generado.'}',
              onRetry: c.busy ? null : c.load,
            ),
          if (displayError != null) InventoryNotice(text: displayError),
          if (data == null && !c.busy && displayError == null)
            const Text('Elige las fechas y genera el reporte.'),
          if (data != null) ...[
            Text(
              'Reporte del ${_localMoment(data.period.startLocal)} al ${_localMoment(data.period.endLocal)}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (data.movements.isEmpty &&
                data.sales.isEmpty &&
                data.debtChanges.isEmpty &&
                data.expenses.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'No hay operaciones confirmadas en este rango. Prueba otras fechas. Los saldos pueden incluir movimientos anteriores; las ventas sin confirmar no aparecen.',
                ),
              ),
            for (final warning in data.warnings)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  warning,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const Text(
              'Los saldos y totales generales abarcan todo el período. Los filtros de Categoría y Producto se aplican al detalle de ventas y sus gráficas.',
            ),
            const SizedBox(height: 20),
            _accounts(data),
            const SizedBox(height: 20),
            _totals(data),
            const SizedBox(height: 20),
            _debts(data),
            const SizedBox(height: 24),
            _sales(data),
            const SizedBox(height: 24),
            _chart(data),
            const SizedBox(height: 24),
            _transfers(data),
            const SizedBox(height: 24),
            _events(data),
          ],
        ],
      );
    },
  );
  void _validateDisplay(ReportsSnapshot data) {
    for (final value in [
      data.salesMinor,
      data.creditSalesMinor,
      data.saleReceiptsMinor,
      data.debtorPaymentsMinor,
      data.outflowsMinor,
      data.costOfGoodsMinor,
      data.physicalMarginMinor,
      data.eventCostsMinor,
      data.operatingExpensesMinor,
      data.operatingResultMinor,
      data.additionalDebtMinor,
    ]) {
      reportMinor(BigInt.from(value));
    }
    for (final account in data.accounts) {
      _accountSum(
        data,
        account,
        (m) =>
            m.amountMinor > 0 &&
            m.kind != ReportMovementKind.transfer &&
            m.kind != ReportMovementKind.opening,
      );
      _negate(
        _accountSum(
          data,
          account,
          (m) =>
              m.amountMinor < 0 &&
              m.kind != ReportMovementKind.transfer &&
              m.kind != ReportMovementKind.opening,
        ),
      );
      _accountSum(data, account, (m) => m.kind == ReportMovementKind.transfer);
      _accountSum(data, account, (m) => m.kind == ReportMovementKind.opening);
      reportSum(
        data.movements
            .where((m) => m.accountId == account.id)
            .map((m) => m.amountMinor),
      );
    }
    final rows = widget.controller.filteredSales;
    reportSum(rows.map((s) => s.salesMinor));
    reportSum(rows.map((s) => s.quantity));
    for (final product in widget.controller.products) {
      product.marginMinor;
    }
    reportSum(data.transfers.map((t) => t.amountMinor));
    reportSum(data.debtChanges.map((d) => d.amountMinor));
    for (final event in data.events) {
      event.resultMinor;
    }
  }

  int _negate(int n) => reportMinor(-BigInt.from(n));
  Widget _dateField(
    String key,
    String label,
    TextEditingController field,
    bool busy,
  ) => SizedBox(
    width: 210,
    child: TextFormField(
      key: Key(key),
      controller: field,
      enabled: !busy,
      decoration: InputDecoration(
        labelText: label,
        hintText: 'dd/mm/aaaa',
        suffixIcon: IconButton(
          tooltip: 'Elegir $label',
          onPressed: busy ? null : () => _pick(field),
          icon: const Icon(Icons.calendar_month_outlined),
        ),
      ),
      validator: (v) {
        if (_parseDate(v) == null) return 'Usa dd/mm/aaaa.';
        if (field == _end &&
            _selectedMoment(true) != null &&
            _selectedMoment(false) != null &&
            _selectedMoment(false)!.isBefore(_selectedMoment(true)!)) {
          return 'Debe ser igual o posterior al inicio.';
        }
        return null;
      },
    ),
  );
  Widget _timeField(
    String key,
    String label,
    TextEditingController field,
    bool busy,
  ) => SizedBox(
    width: 155,
    child: TextFormField(
      key: Key(key),
      controller: field,
      enabled: !busy,
      decoration: InputDecoration(
        labelText: label,
        hintText: 'HH:mm',
        suffixIcon: IconButton(
          tooltip: 'Elegir $label',
          onPressed: busy ? null : () => _pickTime(field),
          icon: const Icon(Icons.schedule),
        ),
      ),
      validator: (v) => _parseTime(v) == null ? 'Usa HH:mm (00–23).' : null,
    ),
  );
  Widget _panel(String title, List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    ),
  );
  Widget _accounts(
    ReportsSnapshot data,
  ) => _panel('Caja, Transferencia y Caja mayor', [
    const Text(
      'Ingresos y egresos excluyen transferencias internas y aperturas. Pulsa una cifra para consultar los movimientos de esa cuenta.',
    ),
    const SizedBox(height: 10),
    SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 18,
        horizontalMargin: 12,
        columns: const [
          DataColumn(label: Text('Cuenta')),
          DataColumn(label: Text('Inicial'), numeric: true),
          DataColumn(label: Text('Ingresos'), numeric: true),
          DataColumn(label: Text('Egresos'), numeric: true),
          DataColumn(label: Text('Transferencias netas'), numeric: true),
          DataColumn(label: Text('Aperturas / otros saldos'), numeric: true),
          DataColumn(label: Text('Final'), numeric: true),
        ],
        rows: [
          for (final account in data.accounts)
            DataRow(
              cells: [
                DataCell(Text(_accountName(account))),
                DataCell(
                  Text(_balance(account.openingMinor)),
                  onTap: () => _accountDetails(data, account),
                ),
                DataCell(
                  Text(
                    _money(
                      _accountSum(
                        data,
                        account,
                        (m) =>
                            m.amountMinor > 0 &&
                            m.kind != ReportMovementKind.transfer &&
                            m.kind != ReportMovementKind.opening,
                      ),
                    ),
                  ),
                  onTap: () => _accountDetails(data, account),
                ),
                DataCell(
                  Text(
                    _money(
                      _negate(
                        _accountSum(
                          data,
                          account,
                          (m) =>
                              m.amountMinor < 0 &&
                              m.kind != ReportMovementKind.transfer &&
                              m.kind != ReportMovementKind.opening,
                        ),
                      ),
                    ),
                  ),
                  onTap: () => _accountDetails(data, account),
                ),
                DataCell(
                  Text(
                    _money(
                      _accountSum(
                        data,
                        account,
                        (m) => m.kind == ReportMovementKind.transfer,
                      ),
                    ),
                  ),
                  onTap: () => _accountDetails(data, account),
                ),
                DataCell(
                  Text(
                    _money(
                      _accountSum(
                        data,
                        account,
                        (m) => m.kind == ReportMovementKind.opening,
                      ),
                    ),
                  ),
                  onTap: () => _accountDetails(data, account),
                ),
                DataCell(
                  Text(_balance(account.closingMinor)),
                  onTap: () => _accountDetails(data, account),
                ),
              ],
            ),
        ],
      ),
    ),
  ]);
  String _accountName(ReportAccount account) =>
      account.role == ReportAccountRole.transfer
      ? 'Transferencia (${account.name})'
      : account.name;
  int _accountSum(
    ReportsSnapshot data,
    ReportAccount account,
    bool Function(ReportMovement) include,
  ) => reportSum(
    data.movements
        .where((m) => m.accountId == account.id && include(m))
        .map((m) => m.amountMinor),
  );
  Widget _totals(ReportsSnapshot d) => _panel('Resumen del período', [
    Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _total(
          'Ventas totales',
          d.salesMinor,
          () => _saleDetails('Ventas totales', d.sales),
        ),
        _total(
          'Ventas a Deudas',
          d.creditSalesMinor,
          () => _saleDetails(
            'Ventas a Deudas',
            d.sales.where((s) => s.creditMinor > 0).toList(),
            value: (s) => s.creditMinor,
          ),
        ),
        _total(
          'Ventas cobradas',
          d.saleReceiptsMinor,
          () => _movementDetails(
            'Ventas cobradas',
            d.movements
                .where((m) => m.kind == ReportMovementKind.saleReceipt)
                .toList(),
          ),
        ),
        _total(
          'Abonos de deudores',
          d.debtorPaymentsMinor,
          () => _movementDetails(
            'Abonos de deudores',
            d.movements
                .where((m) => m.kind == ReportMovementKind.debtorPayment)
                .toList(),
          ),
        ),
        _total(
          'Egresos',
          d.outflowsMinor,
          () => _movementDetails(
            'Egresos',
            d.movements
                .where(
                  (m) =>
                      m.amountMinor < 0 &&
                      m.kind != ReportMovementKind.transfer &&
                      m.kind != ReportMovementKind.opening,
                )
                .toList(),
          ),
        ),
        _total(
          'Costo de productos vendidos',
          d.costOfGoodsMinor,
          () => _saleDetails(
            'Costo de productos vendidos',
            d.sales.where((s) => !s.isEvent).toList(),
            value: (s) => s.costMinor,
          ),
        ),
        _total(
          'Margen bruto de productos físicos',
          d.physicalMarginMinor,
          () => _saleDetails(
            'Margen bruto de productos físicos',
            d.sales.where((s) => !s.isEvent).toList(),
            value: (s) => s.marginMinor,
          ),
        ),
        _total(
          'Costos de eventos',
          d.eventCostsMinor,
          () => _expenseDetails(
            'Costos de eventos',
            d.expenses.where((e) => e.isEvent).toList(),
          ),
        ),
        _total(
          'Gastos registrados',
          d.operatingExpensesMinor,
          () => _expenseDetails(
            'Gastos registrados',
            d.expenses.where((e) => !e.isEvent).toList(),
          ),
        ),
        _total(
          'Resultado operativo',
          d.operatingResultMinor,
          () => _operatingDetails(d),
          emphasize: true,
        ),
      ],
    ),
    const SizedBox(height: 14),
    const Text(
      'Ventas totales incluyen lo fiado. Los abonos recuperan deudas y no vuelven a sumar ventas. Resultado operativo = ventas − costo de productos vendidos − costos de eventos creados en el período − gastos registrados. Las compras de inventario no se descuentan dos veces.',
    ),
  ]);
  Widget _total(
    String label,
    int amount,
    VoidCallback onTap, {
    bool emphasize = false,
  }) => SizedBox(
    width: 242,
    child: Card(
      color: emphasize
          ? Theme.of(context).colorScheme.secondaryContainer
          : Theme.of(context).colorScheme.surfaceContainerLow,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
              const SizedBox(height: 8),
              Text(
                _money(amount),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: amount < 0
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
              ),
              const SizedBox(height: 6),
              const Text('Ver detalle', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    ),
  );
  Widget _debts(ReportsSnapshot d) => _panel('Deudas de clientes', [
    Wrap(
      spacing: 24,
      runSpacing: 12,
      children: [
        Text('Inicial: ${_balance(d.debtOpeningMinor)}'),
        Text('Nuevas ventas fiadas: ${_money(d.creditSalesMinor)}'),
        Text('Deuda anterior adicional: ${_money(d.additionalDebtMinor)}'),
        Text('Abonos: ${_money(d.debtorPaymentsMinor)}'),
        Text('Final: ${_balance(d.debtClosingMinor)}'),
      ],
    ),
    const SizedBox(height: 12),
    const Text(
      'Identificar deuda ya incluida en la cartera inicial no aumenta el total. Las declaraciones adicionales se muestran separadas de las ventas.',
    ),
    TextButton(
      onPressed: () => _detail('Saldos anteriores declarados', [
        for (final row in d.debtChanges)
          _DetailRow(
            _moment(row.occurredAtUtc),
            '${row.concept}${row.isLegacyAssignment ? ' · Ya incluida en la cartera anterior' : ''}',
            row.amountMinor,
          ),
      ]),
      child: const Text('Ver declaraciones de deuda anterior'),
    ),
  ]);
  Widget _sales(ReportsSnapshot d) {
    final c = widget.controller;
    final categories = <String, String>{
      for (final s in d.sales) s.categoryId: s.categoryName,
    };
    final categoryEntries = categories.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final available = d.products(categoryId: c.categoryId);
    final products = c.products;
    final page = _productsPage.clamp(
      0,
      products.isEmpty ? 0 : (products.length - 1) ~/ 10,
    );
    return _panel('Productos vendidos', [
      Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 250,
            child: DropdownButtonFormField<String>(
              key: ValueKey('report-category-${c.categoryId}'),
              initialValue: c.categoryId == null
                  ? ''
                  : 'category:${c.categoryId}',
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Categoría actual del catálogo',
              ),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('Todas las categorías'),
                ),
                for (final category in categoryEntries)
                  DropdownMenuItem(
                    value: 'category:${category.key}',
                    child: Text(
                      category.value,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                _productsPage = 0;
                c.selectCategory(
                  value == '' || value == null
                      ? null
                      : value.substring('category:'.length),
                );
              },
            ),
          ),
          SizedBox(
            width: 250,
            child: DropdownButtonFormField<String>(
              key: ValueKey('report-product-${c.productId}-${c.categoryId}'),
              initialValue: c.productId ?? '',
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Producto'),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('Todos los productos'),
                ),
                for (final product in available)
                  DropdownMenuItem(
                    value: product.productId,
                    child: Text(product.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) {
                _productsPage = 0;
                c.selectProduct(value == '' ? null : value);
              },
            ),
          ),
          TextButton(
            onPressed: () {
              _productsPage = 0;
              c.clearFilters();
            },
            child: const Text('Limpiar filtros de ventas'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Text(
        'Venta filtrada: ${_money(reportSum(c.filteredSales.map((s) => s.salesMinor)))} · Unidades: ${reportSum(c.filteredSales.map((s) => s.quantity))}',
      ),
      const SizedBox(height: 12),
      if (products.isEmpty)
        const Text('No hay productos vendidos con estas fechas y filtros.'),
      if (products.isNotEmpty)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            showCheckboxColumn: false,
            columns: const [
              DataColumn(label: Text('Producto')),
              DataColumn(label: Text('Categoría actual')),
              DataColumn(label: Text('Cantidad'), numeric: true),
              DataColumn(label: Text('Vendido'), numeric: true),
              DataColumn(label: Text('Costo histórico'), numeric: true),
              DataColumn(label: Text('Margen'), numeric: true),
            ],
            rows: [
              for (final p in products.skip(page * 10).take(10))
                DataRow(
                  onSelectChanged: (_) => _saleDetails(
                    p.name,
                    c.filteredSales
                        .where((s) => s.productId == p.productId)
                        .toList(),
                  ),
                  cells: [
                    DataCell(Text(p.name)),
                    DataCell(Text(p.categoryName)),
                    DataCell(Text('${p.quantity}')),
                    DataCell(Text(_money(p.salesMinor))),
                    DataCell(
                      Text(p.isEvent ? 'Ver evento' : _money(p.costMinor)),
                    ),
                    DataCell(
                      Text(p.isEvent ? 'Ver evento' : _money(p.marginMinor)),
                    ),
                  ],
                ),
            ],
          ),
        ),
      if (products.length > 10)
        _pager(
          products.length,
          page,
          (next) => setState(() => _productsPage = next),
        ),
      const SizedBox(height: 10),
      const Text(
        'Los precios y costos corresponden a cada venta confirmada, aunque el producto esté agotado o desactivado. La categoría corresponde al catálogo actual. Los costos reales de eventos se consultan en su resultado separado.',
      ),
    ]);
  }

  Widget _chart(ReportsSnapshot d) {
    final c = widget.controller;
    return _panel('Gráfica de barras', [
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          SizedBox(
            width: 290,
            child: DropdownButtonFormField<ReportMetric>(
              key: const Key('report-chart-metric'),
              initialValue: c.metric,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Mostrar'),
              items: [
                for (final metric in ReportMetric.values)
                  DropdownMenuItem(
                    value: metric,
                    child: Text(
                      _metric(metric),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) {
                if (v != null) c.selectMetric(v);
              },
            ),
          ),
          SizedBox(
            width: 230,
            child: DropdownButtonFormField<ReportGrouping>(
              key: ValueKey('report-chart-group-${c.metric}-${c.grouping}'),
              initialValue: c.grouping,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Agrupar por'),
              items: [
                for (final group in c.availableGroupings)
                  DropdownMenuItem(value: group, child: Text(_group(group))),
              ],
              onChanged: (v) {
                if (v != null) c.selectGrouping(v);
              },
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Text(switch (c.metric) {
        ReportMetric.margin =>
          'Margen de productos físicos vendidos. Los eventos se muestran en su resultado propio.',
        ReportMetric.outflows =>
          'Salidas de dinero del período, incluyendo compras, gastos y costo fijo de eventos. Excluye transferencias internas y aperturas. Los filtros de productos no alteran esta gráfica.',
        ReportMetric.money =>
          'Movimiento neto de dinero, incluyendo las dos partes de cada transferencia. Las transferencias se compensan al sumar todas las cuentas. Excluye aperturas; los filtros de productos no alteran esta gráfica.',
        _ =>
          'Se aplican los filtros de Categoría y Producto del listado de ventas.',
      }),
      const SizedBox(height: 12),
      ReportBarChart(
        data: [
          for (final group in c.chartGroups)
            ReportBarDatum(
              id: group.id,
              label: group.label,
              value: group.value,
            ),
        ],
        formatValue: c.metric == ReportMetric.units ? (n) => '$n' : _money,
        valueLabel: _metric(c.metric),
        onSelect: (bar) {
          final group = c.chartGroups.firstWhere((g) => g.id == bar.id);
          _detail('${_metric(c.metric)} · ${bar.label}', [
            for (final row in group.entries)
              _DetailRow(_moment(row.date), row.concept, row.value),
          ], units: c.metric == ReportMetric.units);
        },
      ),
    ]);
  }

  Widget _transfers(ReportsSnapshot d) => _panel('Transferencias internas', [
    const Text(
      'Cada transferencia aparece una vez con su origen y destino. No suma ventas, gastos ni ganancias.',
    ),
    const SizedBox(height: 10),
    if (d.transfers.isEmpty)
      const Text('No hay transferencias en este período.'),
    if (d.transfers.isNotEmpty)
      TextButton(
        onPressed: () => _detail('Transferencias internas', [
          for (final row in d.transfers)
            _DetailRow(
              _moment(row.occurredAtUtc),
              '${row.sourceName} → ${row.destinationName}${row.note.isEmpty ? '' : ' · ${row.note}'}',
              row.amountMinor,
            ),
        ]),
        child: Text(
          'Ver ${d.transfers.length} transferencias · ${_money(reportSum(d.transfers.map((t) => t.amountMinor)))}',
        ),
      ),
  ]);
  Widget _events(
    ReportsSnapshot d,
  ) => _panel('Resultado acumulado por evento', [
    Text(
      'Inscripciones acumuladas hasta el ${_date(d.period.endDate)}, menos el costo real de cada evento una sola vez. Este acumulado puede incluir fechas anteriores al inicio del reporte y es distinto del resultado operativo del período.',
    ),
    const SizedBox(height: 12),
    if (d.events.isEmpty)
      const Text('No hay eventos creados hasta el corte seleccionado.'),
    if (d.events.isNotEmpty)
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 18,
          horizontalMargin: 12,
          columns: const [
            DataColumn(label: Text('Evento')),
            DataColumn(label: Text('Creado')),
            DataColumn(label: Text('Inscripciones'), numeric: true),
            DataColumn(label: Text('Vendido'), numeric: true),
            DataColumn(label: Text('Costo real'), numeric: true),
            DataColumn(label: Text('Resultado'), numeric: true),
          ],
          rows: [
            for (final e in d.events)
              DataRow(
                cells: [
                  DataCell(Text(e.name)),
                  DataCell(
                    Text(
                      _date(e.createdAtUtc.subtract(const Duration(hours: 5))),
                    ),
                  ),
                  DataCell(Text('${e.quantity}')),
                  DataCell(Text(_money(e.salesMinor))),
                  DataCell(Text(_money(e.costMinor))),
                  DataCell(
                    Text(
                      _money(e.resultMinor),
                      style: TextStyle(
                        color: e.resultMinor < 0
                            ? Theme.of(context).colorScheme.error
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
  ]);
  String _metric(ReportMetric m) => switch (m) {
    ReportMetric.sales => 'Ventas',
    ReportMetric.units => 'Unidades vendidas',
    ReportMetric.margin => 'Margen de productos físicos',
    ReportMetric.outflows => 'Egresos',
    ReportMetric.money => 'Movimiento neto de dinero',
  };
  String _group(ReportGrouping g) => switch (g) {
    ReportGrouping.day => 'Día',
    ReportGrouping.week => 'Semana',
    ReportGrouping.month => 'Mes',
    ReportGrouping.category => 'Categoría actual',
    ReportGrouping.product => 'Producto',
    ReportGrouping.reason => 'Motivo',
    ReportGrouping.account => 'Cuenta',
  };
  Widget _pager(int length, int page, ValueChanged<int> select) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text('${page * 10 + 1}–${(page * 10 + 10).clamp(0, length)} de $length'),
      IconButton(
        tooltip: 'Productos anteriores',
        onPressed: page == 0 ? null : () => select(page - 1),
        icon: const Icon(Icons.chevron_left),
      ),
      IconButton(
        tooltip: 'Productos siguientes',
        onPressed: (page + 1) * 10 >= length ? null : () => select(page + 1),
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );
  void _accountDetails(ReportsSnapshot d, ReportAccount account) => _detail(
    'Movimientos de ${_accountName(account)}',
    [
      for (final m in d.movements.where((m) => m.accountId == account.id))
        _DetailRow(
          _moment(m.occurredAtUtc),
          '${_movementKind(m.kind)} · ${m.concept}',
          m.amountMinor,
        ),
    ],
    explanation:
        'Inicial: ${_balance(account.openingMinor)} · Final: ${_balance(account.closingMinor)}. El saldo inicial corresponde a lo registrado antes de comenzar el período. La tabla muestra todos los movimientos de esta cuenta dentro del rango, incluidas transferencias y aperturas.',
  );
  void _movementDetails(String title, List<ReportMovement> rows) =>
      _detail(title, [
        for (final row in rows)
          _DetailRow(
            _moment(row.occurredAtUtc),
            '${row.accountName} · ${row.concept}',
            row.amountMinor,
          ),
      ]);
  void _saleDetails(
    String title,
    List<ReportSaleLine> rows, {
    int Function(ReportSaleLine)? value,
  }) => _detail(title, [
    for (final row in rows)
      _DetailRow(
        _moment(row.occurredAtUtc),
        '${row.saleLabel} · ${row.productName} · ${row.quantity} un.${row.isEvent ? ' · Inscripción, costo en el resultado del evento' : ''}',
        value?.call(row) ?? row.salesMinor,
      ),
  ]);
  void _expenseDetails(String title, List<ReportExpense> rows) =>
      _detail(title, [
        for (final row in rows)
          _DetailRow(
            _moment(row.occurredAtUtc),
            '${row.reason} · ${row.concept}',
            row.amountMinor,
          ),
      ]);
  void _operatingDetails(ReportsSnapshot d) => _detail(
    'Composición del resultado operativo',
    [
      for (final row in d.sales)
        _DetailRow(
          _moment(row.occurredAtUtc),
          'Venta · ${row.productName}',
          row.salesMinor,
        ),
      for (final row in d.sales.where((s) => !s.isEvent))
        _DetailRow(
          _moment(row.occurredAtUtc),
          'Costo vendido · ${row.productName}',
          -row.costMinor,
        ),
      for (final row in d.expenses)
        _DetailRow(
          _moment(row.occurredAtUtc),
          '${row.isEvent ? 'Costo de evento' : 'Gasto'} · ${row.concept}',
          -row.amountMinor,
        ),
    ],
    explanation:
        'La suma de estas partidas es el resultado operativo del período. Las compras de inventario, los abonos y las transferencias no se restan ni suman como nuevas ventas o ganancias.',
  );
  String _movementKind(ReportMovementKind k) => switch (k) {
    ReportMovementKind.saleReceipt => 'Venta cobrada',
    ReportMovementKind.debtorPayment => 'Abono',
    ReportMovementKind.purchasePayment => 'Compra',
    ReportMovementKind.expense => 'Gasto',
    ReportMovementKind.eventPayment => 'Costo fijo de evento',
    ReportMovementKind.transfer => 'Transferencia interna',
    ReportMovementKind.opening => 'Saldo inicial registrado',
    ReportMovementKind.other => 'Otro movimiento',
  };
  Future<void> _detail(
    String title,
    List<_DetailRow> rows, {
    String? explanation,
    bool units = false,
  }) => showDialog<void>(
    context: context,
    builder: (context) => _DetailDialog(
      title: title,
      rows: rows,
      explanation: explanation,
      format: units ? (n) => '$n' : _money,
    ),
  );
}

class _DetailRow {
  const _DetailRow(this.date, this.concept, this.amount);
  final String date, concept;
  final int amount;
}

class _DetailDialog extends StatefulWidget {
  const _DetailDialog({
    required this.title,
    required this.rows,
    required this.format,
    this.explanation,
  });
  final String title;
  final List<_DetailRow> rows;
  final String Function(int) format;
  final String? explanation;
  @override
  State<_DetailDialog> createState() => _DetailDialogState();
}

class _DetailDialogState extends State<_DetailDialog> {
  int page = 0;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 850,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.explanation != null) ...[
              Text(widget.explanation!),
              const SizedBox(height: 12),
            ],
            Text(
              'Total de las partidas: ${widget.format(reportSum(widget.rows.map((r) => r.amount)))}',
            ),
            const SizedBox(height: 12),
            if (widget.rows.isEmpty)
              const Text('No hay operaciones para este detalle.'),
            for (final row in widget.rows.skip(page * 15).take(15))
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.date,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(row.concept),
                    Text(
                      widget.format(row.amount),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: row.amount < 0
                            ? Theme.of(context).colorScheme.error
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            if (widget.rows.length > 15)
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${page * 15 + 1}–${(page * 15 + 15).clamp(0, widget.rows.length)} de ${widget.rows.length}',
                  ),
                  IconButton(
                    tooltip: 'Partidas anteriores',
                    onPressed: page == 0 ? null : () => setState(() => page--),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  IconButton(
                    tooltip: 'Partidas siguientes',
                    onPressed: (page + 1) * 15 >= widget.rows.length
                        ? null
                        : () => setState(() => page++),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cerrar'),
      ),
    ],
  );
}
