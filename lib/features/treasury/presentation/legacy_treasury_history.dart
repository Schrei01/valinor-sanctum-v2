import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/domain/money.dart';
import '../../inventory/presentation/inventory_widgets.dart';
import '../domain/legacy_treasury_snapshot.dart';

/// Read-only consultation; these rows never contribute to current balances.
class LegacyTreasuryHistory extends StatefulWidget {
  const LegacyTreasuryHistory({super.key, required this.store});

  final LegacyTreasuryStore store;

  @override
  State<LegacyTreasuryHistory> createState() => _LegacyTreasuryHistoryState();
}

class _LegacyTreasuryHistoryState extends State<LegacyTreasuryHistory> {
  static const _pageSize = 25;
  static const _accounts = {
    'cash': 'Caja',
    'nequi': 'Nequi',
    'reserve': 'Caja mayor',
    'receivables': 'Deudas',
  };

  LegacyTreasurySnapshot? _snapshot;
  bool _loading = false;
  String? _error;
  String? _role;
  int _page = 0;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(LegacyTreasuryHistory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      _snapshot = null;
      _loading = false;
      _role = null;
      _page = 0;
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    if (_loading) return;
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.store.load();
      if (!mounted || request != _request) return;
      setState(() => _snapshot = result);
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = _snapshot == null
            ? 'No se pudo cargar el historial de la copia. Pulsa Actualizar para intentarlo de nuevo.'
            : 'No se pudo actualizar el historial de la copia. La consulta visible puede estar desactualizada.';
      });
    } finally {
      if (mounted && request == _request) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _snapshot;
    if (data == null) {
      if (_loading) {
        return const Card(
          key: Key('legacy-treasury-loading'),
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 16),
                Expanded(child: Text('Cargando historial de la copia…')),
              ],
            ),
          ),
        );
      }
      if (_error != null) {
        return InventoryNotice(
          key: const Key('legacy-treasury-load-error'),
          text: _error!,
          onRetry: _load,
        );
      }
      return const SizedBox.shrink();
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: const Key('legacy-treasury-history'),
        title: const Text('Historial de la copia'),
        subtitle: const Text(
          'Consulta histórica. Estos movimientos ya están incluidos en los saldos iniciales.',
        ),
        childrenPadding: const EdgeInsets.all(20),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_loading) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 16),
          ],
          if (_error != null)
            InventoryNotice(
              key: const Key('legacy-treasury-load-error'),
              text: _error!,
            ),
          _history(data),
        ],
      ),
    );
  }

  Widget _history(LegacyTreasurySnapshot data) {
    final rows = data.movements
        .where(
          (movement) =>
              _role == null ||
              movement.fromRole == _role ||
              movement.toRole == _role,
        )
        .toList();
    final page = _page.clamp(
      0,
      rows.isEmpty ? 0 : (rows.length - 1) ~/ _pageSize,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              key: const Key('legacy-treasury-account-filter'),
              constraints: const BoxConstraints(maxWidth: 380),
              child: DropdownButtonFormField<String>(
                initialValue: _role ?? '',
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Cuenta de la copia',
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Todas las cuentas de la copia'),
                  ),
                  for (final account in _accounts.entries)
                    DropdownMenuItem(
                      value: account.key,
                      child: Text(account.value),
                    ),
                ],
                onChanged: (value) => setState(() {
                  _role = value == null || value.isEmpty ? null : value;
                  _page = 0;
                }),
              ),
            ),
            OutlinedButton.icon(
              key: const Key('legacy-treasury-refresh'),
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
              label: Text(_loading ? 'Procesando…' : 'Actualizar historial'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          'Las fechas se muestran tal como aparecen en la copia. Cada traspaso se muestra una sola vez.',
          style: TextStyle(color: Color(0xFF65716A), height: 1.5),
        ),
        const SizedBox(height: 16),
        if (rows.isEmpty)
          Padding(
            key: const Key('legacy-treasury-empty-history'),
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              _role == null
                  ? 'La copia no contiene movimientos históricos.'
                  : 'La copia no contiene movimientos para esta cuenta.',
            ),
          )
        else ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              key: const Key('legacy-treasury-movements'),
              dataRowMinHeight: 68,
              dataRowMaxHeight: 84,
              columns: const [
                DataColumn(label: Text('Fecha original')),
                DataColumn(label: Text('Cuenta')),
                DataColumn(label: Text('Concepto')),
                DataColumn(label: Text('Movimiento'), numeric: true),
              ],
              rows: [
                for (final movement
                    in rows.skip(page * _pageSize).take(_pageSize))
                  DataRow(
                    key: ValueKey(
                      'legacy-treasury-movement-${movement.sourceTable}-${movement.sourceRowId}',
                    ),
                    cells: [
                      DataCell(
                        _limitedText(
                          movement.sourceDateRaw.isEmpty
                              ? 'Sin fecha en la copia'
                              : movement.sourceDateRaw,
                          220,
                        ),
                      ),
                      DataCell(_limitedText(_accountName(movement), 220)),
                      DataCell(
                        _limitedText(
                          movement.reason.isEmpty
                              ? 'Sin concepto en la copia'
                              : movement.reason,
                          300,
                        ),
                      ),
                      DataCell(_amount(data, movement)),
                    ],
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${page * _pageSize + 1}–${(page * _pageSize + _pageSize).clamp(0, rows.length)} de ${rows.length}',
                ),
                IconButton(
                  key: const Key('legacy-treasury-previous-page'),
                  tooltip: 'Página anterior del historial de la copia',
                  onPressed: page == 0
                      ? null
                      : () => setState(() => _page = page - 1),
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  key: const Key('legacy-treasury-next-page'),
                  tooltip: 'Página siguiente del historial de la copia',
                  onPressed: (page + 1) * _pageSize >= rows.length
                      ? null
                      : () => setState(() => _page = page + 1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _accountName(LegacyTreasuryMovement movement) {
    String label(String? role) => _accounts[role] ?? 'Cuenta no identificada';
    return movement.type == 'transferencia'
        ? '${label(movement.fromRole)} → ${label(movement.toRole)}'
        : label(movement.fromRole ?? movement.toRole);
  }

  Widget _amount(LegacyTreasurySnapshot data, LegacyTreasuryMovement movement) {
    final outgoing = movement.type == 'egreso';
    final transfer = movement.type == 'transferencia';
    final money = Money.fromMinorUnits(
      outgoing ? -movement.amountMinor : movement.amountMinor,
      currency: data.currencyCode,
      scale: data.moneyScale,
    ).formatEsCo(includeCurrency: true);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          transfer || outgoing ? money : '+$money',
          style: TextStyle(
            color: outgoing ? const Color(0xFFA83131) : const Color(0xFF183D35),
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          transfer
              ? 'Traspaso'
              : outgoing
              ? 'Egreso'
              : 'Ingreso',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _limitedText(String value, double width) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: width),
    child: Tooltip(
      message: value,
      child: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
    ),
  );
}
