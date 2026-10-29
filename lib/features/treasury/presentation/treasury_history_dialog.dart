import 'package:flutter/material.dart';
import '../../../core/domain/money.dart';
import '../../workspace/domain/business_profile.dart';
import '../domain/legacy_treasury_snapshot.dart';
import '../domain/treasury_store.dart';

/// One read-only history, with original row identities and no monetary reposting.
class TreasuryHistoryDialog extends StatefulWidget {
  const TreasuryHistoryDialog({
    super.key,
    required this.profile,
    required this.loadCurrent,
    this.legacyStore,
  });
  final BusinessProfile profile;
  final Future<TreasurySnapshot> Function() loadCurrent;
  final LegacyTreasuryStore? legacyStore;
  @override
  State<TreasuryHistoryDialog> createState() => _TreasuryHistoryDialogState();
}

class _TreasuryHistoryDialogState extends State<TreasuryHistoryDialog> {
  static const _names = {
    'cash': 'Caja',
    'nequi': 'Nequi',
    'reserve': 'Caja mayor',
    'receivables': 'Deudas',
    'investment': 'Inversión por recuperar',
  };
  late Future<List<_HistoryRow>> _rows;
  String _account = '';
  DateTime? _start, _end;
  int _page = 0;
  @override
  void initState() {
    super.initState();
    _rows = _load();
  }

  String _money(int n, int scale) => Money.fromMinorUnits(
    n,
    currency: widget.profile.currencyCode,
    scale: scale,
  ).formatEsCo(includeCurrency: true);
  Future<List<_HistoryRow>> _load() async {
    final current = await widget.loadCurrent();
    final rows = <_HistoryRow>[];
    final accounts = {
      for (final a in current.accounts)
        a.id: a.role == TreasuryAccountRole.other
            ? a.id
            : a.role == TreasuryAccountRole.cash
            ? 'cash'
            : a.role.name,
    };
    for (final m in current.movements) {
      rows.add(
        _HistoryRow(
          'native:${m.id}',
          m.occurredAtUtc,
          {accounts[m.cashAccountId] ?? m.cashAccountId},
          m.accountName,
          m.concept,
          _money(m.amountMinor, widget.profile.moneyScale),
        ),
      );
    }
    final old = await widget.legacyStore?.load();
    if (old != null) {
      for (final m in old.movements) {
        final raw = m.sourceDateRaw;
        final withOffset = RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(raw);
        final date = DateTime.tryParse(withOffset ? raw : '${raw}Z');
        final at = date == null
            ? null
            : withOffset
            ? date.toUtc()
            : date.add(const Duration(hours: 5));
        final roles = {
          if (m.fromRole != null) m.fromRole!,
          if (m.toRole != null) m.toRole!,
        };
        final label = m.type == 'transferencia'
            ? '${_names[m.fromRole]} → ${_names[m.toRole]}'
            : _names[m.fromRole ?? m.toRole] ?? 'Cuenta';
        rows.add(
          _HistoryRow(
            'previous:${m.sourceTable}:${m.sourceRowId}',
            at,
            roles,
            label,
            m.reason,
            '${m.type == 'transferencia' ? 'Traspaso · ' : ''}${_money(m.type == 'egreso' ? -m.amountMinor : m.amountMinor, old.moneyScale)}',
          ),
        );
      }
    }
    rows.sort((a, b) {
      final d = (b.at ?? DateTime.utc(1)).compareTo(a.at ?? DateTime.utc(1));
      return d == 0 ? a.id.compareTo(b.id) : d;
    });
    return rows;
  }

  String _date(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  String _moment(DateTime? utc) {
    if (utc == null) return 'Sin fecha';
    final d = utc.subtract(const Duration(hours: 5));
    return '${_date(d)} · ${d.hour % 12 == 0 ? 12 : d.hour % 12}:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  Future<void> _pick(bool start) async {
    final now = DateTime.now().toUtc().subtract(const Duration(hours: 5));
    final chosen = await showDatePicker(
      context: context,
      initialDate: (start ? _start : _end) ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(9998),
      helpText: start ? 'Desde' : 'Hasta',
    );
    if (chosen != null && mounted) {
      setState(() {
        if (start) {
          _start = chosen;
        } else {
          _end = chosen;
        }
        _page = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Historial de movimientos'),
    content: SizedBox(
      width: 980,
      height: 540,
      child: FutureBuilder<List<_HistoryRow>>(
        future: _rows,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('No se pudo cargar el historial completo.'),
                TextButton(
                  onPressed: () => setState(() {
                    _rows = _load();
                  }),
                  child: const Text('Reintentar'),
                ),
              ],
            );
          }
          final rows = snapshot.data!.where((r) {
            if (_account.isNotEmpty && !r.accounts.contains(_account)) {
              return false;
            }
            if (_start == null && _end == null) return true;
            if (r.at == null) return false;
            final local = r.at!.subtract(const Duration(hours: 5));
            final date = DateTime(local.year, local.month, local.day);
            return (_start == null || !date.isBefore(_start!)) &&
                (_end == null || !date.isAfter(_end!));
          }).toList();
          final pages = (rows.length + 9) ~/ 10;
          final page = _page.clamp(0, pages == 0 ? 0 : pages - 1);
          final accounts = {for (final r in snapshot.data!) ...r.accounts};
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 210,
                      child: DropdownButtonFormField<String>(
                        key: const Key('history-account'),
                        initialValue: _account,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Cuenta'),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('Todas las cuentas'),
                          ),
                          for (final a in accounts.toList()..sort())
                            DropdownMenuItem(
                              value: a,
                              child: Text(_names[a] ?? a),
                            ),
                        ],
                        onChanged: (v) => setState(() {
                          _account = v!;
                          _page = 0;
                        }),
                      ),
                    ),
                    TextButton(
                      key: const Key('history-start'),
                      onPressed: () => _pick(true),
                      child: Text(
                        _start == null
                            ? 'Desde: todas las fechas'
                            : 'Desde: ${_date(_start!)}',
                      ),
                    ),
                    TextButton(
                      key: const Key('history-end'),
                      onPressed: () => _pick(false),
                      child: Text(
                        _end == null
                            ? 'Hasta: todas las fechas'
                            : 'Hasta: ${_date(_end!)}',
                      ),
                    ),
                    if (_start != null || _end != null || _account.isNotEmpty)
                      TextButton(
                        onPressed: () => setState(() {
                          _start = null;
                          _end = null;
                          _account = '';
                          _page = 0;
                        }),
                        child: const Text('Limpiar filtros'),
                      ),
                  ],
                ),
                if (_start != null && _end != null && _start!.isAfter(_end!))
                  const Text('La fecha inicial debe ser anterior a la final.'),
                const SizedBox(height: 12),
                if (rows.isEmpty)
                  const Text('Sin movimientos para estos filtros.')
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      key: const Key('treasury-all-history'),
                      columns: const [
                        DataColumn(label: Text('Fecha')),
                        DataColumn(label: Text('Cuenta')),
                        DataColumn(label: Text('Concepto')),
                        DataColumn(label: Text('Movimiento'), numeric: true),
                      ],
                      rows: [
                        for (final r in rows.skip(page * 10).take(10))
                          DataRow(
                            key: ValueKey(r.id),
                            cells: [
                              DataCell(Text(_moment(r.at))),
                              DataCell(
                                SizedBox(width: 160, child: Text(r.account)),
                              ),
                              DataCell(
                                SizedBox(
                                  width: 290,
                                  child: Text(
                                    r.concept,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              DataCell(Text(r.amount)),
                            ],
                          ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${rows.length} movimientos · Página ${pages == 0 ? 0 : page + 1} de $pages',
                      ),
                    ),
                    IconButton(
                      key: const Key('history-previous'),
                      onPressed: page > 0
                          ? () => setState(() => _page = page - 1)
                          : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    IconButton(
                      key: const Key('history-next'),
                      onPressed: page + 1 < pages
                          ? () => setState(() => _page = page + 1)
                          : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cerrar'),
      ),
    ],
  );
}

class _HistoryRow {
  const _HistoryRow(
    this.id,
    this.at,
    this.accounts,
    this.account,
    this.concept,
    this.amount,
  );
  final String id, account, concept, amount;
  final DateTime? at;
  final Set<String> accounts;
}
