import 'package:flutter/material.dart';

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
  late DateTime _start =
      widget.controller.snapshot?.period.startLocal ?? widget.controller.today;
  late DateTime _end =
      widget.controller.snapshot?.period.endLocal ??
      widget.controller.today.add(const Duration(hours: 23, minutes: 59));
  String? _rangeError;

  String _moment(DateTime value) {
    final day =
        '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year.toString().padLeft(4, '0')}';
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    return '$day · $hour:${value.minute.toString().padLeft(2, '0')} ${value.hour < 12 ? 'AM' : 'PM'}';
  }

  Future<void> _pick(bool start) async {
    final initial = start ? _start : _end;
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
        _end = selected;
      }
      _rangeError = null;
    });
  }

  Future<void> _generate() async {
    if (_end.isBefore(_start)) {
      setState(
        () => _rangeError =
            'La fecha y hora final deben ser iguales o posteriores a las iniciales.',
      );
      return;
    }
    setState(() => _rangeError = null);
    await widget.controller.generate(start: _start, end: _end, timed: true);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final data = c.snapshot;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InventoryPageHeading(
            title: 'Reportes',
            subtitle:
                'Consulta los saldos iniciales y finales de Caja y Nequi.',
            busy: c.busy,
            onRefresh: c.load,
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _selector(true, 'Fecha y hora inicial', _start, c.busy),
              _selector(false, 'Fecha y hora final', _end, c.busy),
              FilledButton.icon(
                key: const Key('report-generate'),
                onPressed: c.busy ? null : _generate,
                icon: const Icon(Icons.account_balance_wallet_outlined),
                label: Text(c.busy ? 'Consultando…' : 'Generar reporte'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Horario de Bogotá. El saldo inicial se toma al comenzar el minuto elegido y el final al terminar el minuto elegido.',
          ),
          const SizedBox(height: 20),
          if (_rangeError != null) InventoryNotice(text: _rangeError!),
          if (c.busy) const LinearProgressIndicator(),
          if (c.error != null)
            InventoryNotice(
              text:
                  '${c.error}${data == null ? '' : ' Se conserva el último reporte generado.'}',
              onRetry: c.busy ? null : c.load,
            ),
          if (data == null && !c.busy)
            const Text('Elige las fechas y horas y genera el reporte.'),
          if (data != null) ...[
            if (!data.openingBalancesKnown || !data.closingBalancesKnown)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(
                  'Sin información: el momento seleccionado es anterior al historial disponible de los saldos. Elige un momento posterior al saldo inicial importado.',
                ),
              ),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [_balances(data, true), _balances(data, false)],
            ),
          ],
        ],
      );
    },
  );

  Widget _selector(bool start, String label, DateTime moment, bool busy) =>
      SizedBox(
        width: 300,
        child: OutlinedButton.icon(
          key: Key(start ? 'report-start' : 'report-end'),
          onPressed: busy ? null : () => _pick(start),
          icon: const Icon(Icons.calendar_month_outlined),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            alignment: Alignment.centerLeft,
          ),
          label: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
              const SizedBox(height: 4),
              Text(_moment(moment)),
            ],
          ),
        ),
      );

  Widget _balances(ReportsSnapshot data, bool opening) {
    final cash = data.accounts
        .where((a) => a.role == ReportAccountRole.cash)
        .firstOrNull;
    final nequi = data.accounts
        .where((a) => a.role == ReportAccountRole.transfer)
        .firstOrNull;
    final prefix = opening ? 'opening' : 'closing';
    return SizedBox(
      width: 340,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                opening ? 'Saldos iniciales' : 'Saldos finales',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                _moment(
                  opening ? data.period.startLocal : data.period.endLocal,
                ),
              ),
              const SizedBox(height: 24),
              _balance(
                'report-$prefix-cash',
                'Caja',
                opening ? cash?.openingMinor : cash?.closingMinor,
              ),
              const Divider(height: 32),
              _balance(
                'report-$prefix-nequi',
                'Nequi',
                opening ? nequi?.openingMinor : nequi?.closingMinor,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _balance(String key, String label, int? amount) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      const SizedBox(height: 4),
      Text(
        amount == null
            ? 'Sin información'
            : inventoryMoney(amount, widget.profile),
        key: Key(key),
        style: Theme.of(context).textTheme.headlineSmall,
      ),
    ],
  );
}
