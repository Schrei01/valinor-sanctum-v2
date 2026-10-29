import 'package:flutter/material.dart';
import '../../../core/presentation/financial_total.dart';

import '../../inventory/presentation/inventory_widgets.dart';
import '../../workspace/domain/business_profile.dart';
import '../application/treasury_controller.dart';
import '../application/treasury_operation_controller.dart';
import '../domain/legacy_treasury_snapshot.dart';
import '../domain/treasury_store.dart';
import 'treasury_history_dialog.dart';
import 'treasury_operations_panel.dart';

class TreasuryPage extends StatefulWidget {
  const TreasuryPage({
    super.key,
    required this.controller,
    required this.profile,
    this.supplierPaymentsPanel,
    this.legacyStore,
    this.operationController,
  });

  final TreasuryController controller;
  final BusinessProfile profile;
  final Widget? supplierPaymentsPanel;
  final LegacyTreasuryStore? legacyStore;
  final TreasuryOperationController? operationController;

  @override
  State<TreasuryPage> createState() => _TreasuryPageState();
}

class _TreasuryPageState extends State<TreasuryPage> {
  String? _accountId;
  bool _refreshQueued = false;

  Future<void> _refresh() async {
    await Future.wait([
      widget.controller.load(),
      if (widget.operationController != null)
        widget.operationController!.load(),
    ]);
  }

  void _operationConfirmed() {
    if (widget.controller.loading) {
      if (!_refreshQueued) {
        _refreshQueued = true;
        widget.controller.addListener(_afterCurrentLoad);
      }
    } else {
      widget.controller.load();
    }
  }

  void _afterCurrentLoad() {
    if (widget.controller.loading) return;
    widget.controller.removeListener(_afterCurrentLoad);
    _refreshQueued = false;
    if (mounted) widget.controller.load();
  }

  @override
  void didUpdateWidget(covariant TreasuryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller && _refreshQueued) {
      oldWidget.controller.removeListener(_afterCurrentLoad);
      _refreshQueued = false;
      _operationConfirmed();
    }
  }

  @override
  void dispose() {
    if (_refreshQueued) widget.controller.removeListener(_afterCurrentLoad);
    super.dispose();
  }

  String _money(int value) => inventoryMoney(value, widget.profile);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final data = controller.snapshot;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InventoryPageHeading(
            title: 'Tesorería',
            subtitle:
                'Consulta tus saldos, registra gastos y transfiere dinero entre cuentas.',
            busy: controller.loading,
            onRefresh: _refresh,
          ),
          if (controller.loadError != null)
            InventoryNotice(
              key: const Key('treasury-load-error'),
              text: controller.loadError!,
              onRetry: controller.loading ? null : controller.load,
            ),
          if (widget.operationController != null) ...[
            TreasuryOperationsPanel(
              controller: widget.operationController!,
              profile: widget.profile,
              onConfirmed: _operationConfirmed,
            ),
            const SizedBox(height: 24),
          ],
          if (data == null) ...[
            if (controller.loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (controller.loadError == null)
              const Text('La información de Tesorería no está disponible.'),
          ] else ...[
            if (controller.loading) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 16),
            ],
            _balances(data),
            const SizedBox(height: 28),
            _history(data),
          ],
          if (widget.supplierPaymentsPanel != null) ...[
            const SizedBox(height: 28),
            Card(
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                key: const Key('treasury-supplier-payments'),
                title: const Text('Pagos a proveedores'),
                subtitle: const Text('Compras a crédito anteriores'),
                childrenPadding: const EdgeInsets.all(20),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [widget.supplierPaymentsPanel!],
              ),
            ),
          ],
        ],
      );
    },
  );

  Widget _balances(TreasurySnapshot data) => LayoutBuilder(
    builder: (context, constraints) {
      const gap = 12.0;
      final columns = constraints.maxWidth >= 1180
          ? 6
          : constraints.maxWidth >= 700
          ? 3
          : constraints.maxWidth >= 440
          ? 2
          : 1;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      final extraAccounts = data.accounts
          .where((account) => account.role == TreasuryAccountRole.other)
          .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              _balanceCard(
                keyName: 'cash',
                title: 'Caja',
                subtitle: 'Efectivo disponible',
                amount: data.cashMinor,
                icon: Icons.payments_outlined,
                width: width,
              ),
              _balanceCard(
                keyName: 'nequi',
                title: 'Nequi',
                subtitle: 'Saldo registrado',
                amount: data.nequiMinor,
                icon: Icons.phone_android_outlined,
                width: width,
              ),
              _balanceCard(
                keyName: 'investment',
                title: 'Inversión por recuperar',
                subtitle: 'Pendiente de devolución',
                amount: data.investmentMinor,
                icon: Icons.handshake_outlined,
                width: width,
              ),
              _balanceCard(
                keyName: 'reserve',
                title: 'Caja mayor',
                subtitle: 'Reserva independiente',
                amount: data.reserveMinor,
                icon: Icons.savings_outlined,
                width: width,
              ),
              _balanceCard(
                keyName: 'receivables',
                title: 'Deudas',
                subtitle: 'Lo que deben los clientes',
                amount: data.receivablesMinor,
                icon: Icons.receipt_long_outlined,
                width: width,
                note: data.legacyReceivablesMinor > 0
                    ? 'Incluye ${_money(data.legacyReceivablesMinor)} de cartera anterior sin detalle por cliente.'
                    : null,
              ),
              _balanceCard(
                keyName: 'total',
                title: 'Total disponible',
                subtitle: 'Caja + Nequi',
                amount: data.totalAvailableMinor,
                icon: Icons.account_balance_wallet_outlined,
                width: width,
              ),
            ],
          ),
          if (extraAccounts.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Otras cuentas',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final account in extraAccounts)
                  _balanceCard(
                    keyName: 'other-${account.id}',
                    title: account.name,
                    subtitle: 'Saldo registrado',
                    amount: account.balanceMinor,
                    icon: Icons.account_balance_outlined,
                    width: width,
                  ),
              ],
            ),
          ],
        ],
      );
    },
  );

  Widget _balanceCard({
    required String keyName,
    required String title,
    required String subtitle,
    required int amount,
    required IconData icon,
    required double width,
    String? note,
  }) {
    final colors = Theme.of(context).colorScheme;
    final foreground = colors.onPrimaryContainer;
    return SizedBox(
      width: width,
      child: Card(
        key: Key('treasury-balance-$keyName'),
        color: colors.surface,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: foreground, size: 24),
              const SizedBox(height: 14),
              FinancialTotal(
                label: title,
                value: _money(amount),
                valueKey: Key('treasury-amount-$keyName'),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: TextStyle(color: colors.onSurfaceVariant, height: 1.4),
              ),
              if (note != null) ...[
                const SizedBox(height: 8),
                Text(
                  note,
                  key: const Key('treasury-legacy-receivables-note'),
                  style: const TextStyle(color: Color(0xFF65716A), height: 1.4),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _history(TreasurySnapshot data) {
    final selectedId =
        (_accountId == 'investment' ||
            data.accounts.any((account) => account.id == _accountId))
        ? _accountId
        : null;
    final movements =
        data.movements
            .where(
              (movement) =>
                  selectedId == null || movement.cashAccountId == selectedId,
            )
            .toList()
          ..sort((a, b) {
            final date = b.occurredAtUtc.compareTo(a.occurredAtUtc);
            return date == 0 ? b.id.compareTo(a.id) : date;
          });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Últimos movimientos',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            TextButton.icon(
              key: const Key('treasury-view-history'),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => TreasuryHistoryDialog(
                  profile: widget.profile,
                  legacyStore: widget.legacyStore,
                  loadCurrent: () =>
                      widget.controller.store.load(fullHistory: true),
                ),
              ),
              icon: const Icon(Icons.history),
              label: const Text('Ver historial'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Los ingresos suman a la cuenta y los egresos se descuentan. Últimos 50 movimientos por cuenta, en horario de Bogotá.',
          style: TextStyle(color: Color(0xFF65716A), height: 1.5),
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          key: const Key('treasury-account-filter'),
          constraints: const BoxConstraints(maxWidth: 380),
          child: DropdownButtonFormField<String>(
            key: ValueKey(
              'treasury-filter-${selectedId ?? ''}-${data.accounts.map((account) => account.id).join(',')}',
            ),
            initialValue: selectedId ?? '',
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Cuenta'),
            items: [
              const DropdownMenuItem(
                value: '',
                child: Text('Todas las cuentas'),
              ),
              const DropdownMenuItem(
                value: 'investment',
                child: Text('Inversión por recuperar'),
              ),
              for (final account in data.accounts)
                DropdownMenuItem(
                  value: account.id,
                  child: Text(
                    account.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) => setState(
              () => _accountId = value == null || value.isEmpty ? null : value,
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (movements.isEmpty)
          Card(
            key: const Key('treasury-empty-history'),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                selectedId == null
                    ? 'Aún no hay movimientos registrados.'
                    : 'Esta cuenta no tiene movimientos recientes.',
              ),
            ),
          )
        else
          Card(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                key: const Key('treasury-movements'),
                dataRowMinHeight: 68,
                dataRowMaxHeight: 84,
                columns: const [
                  DataColumn(label: Text('Fecha')),
                  DataColumn(label: Text('Cuenta')),
                  DataColumn(label: Text('Concepto')),
                  DataColumn(label: Text('Movimiento'), numeric: true),
                ],
                rows: [
                  for (final movement in movements)
                    DataRow(
                      key: ValueKey('treasury-movement-${movement.id}'),
                      cells: [
                        DataCell(Text(_dateTime(movement.occurredAtUtc))),
                        DataCell(_limitedText(movement.accountName, 180)),
                        DataCell(_limitedText(movement.concept, 300)),
                        DataCell(
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                movement.amountMinor < 0
                                    ? _money(movement.amountMinor)
                                    : '+${_money(movement.amountMinor)}',
                                style: TextStyle(
                                  color: movement.amountMinor < 0
                                      ? const Color(0xFFA83131)
                                      : const Color(0xFF183D35),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                movement.cashAccountId == 'investment'
                                    ? movement.amountMinor < 0
                                          ? 'Devolución'
                                          : 'Inversión'
                                    : movement.amountMinor < 0
                                    ? 'Egreso'
                                    : 'Ingreso',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _limitedText(String value, double maxWidth) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: maxWidth),
    child: Tooltip(
      message: value,
      child: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
    ),
  );

  String _dateTime(DateTime utc) {
    final date = utc.toUtc().subtract(const Duration(hours: 5));
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year}\n'
        '${two(date.hour)}:${two(date.minute)}';
  }
}
