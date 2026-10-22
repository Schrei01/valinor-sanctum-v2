import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/domain/money.dart';
import '../../inventory/application/inventory_controller.dart';
import '../../inventory/domain/inventory_store.dart';
import '../../inventory/presentation/inventory_widgets.dart';
import '../../workspace/domain/business_profile.dart';
import '../application/supplier_payments_controller.dart';
import '../domain/supplier_payments_store.dart';

class SupplierPaymentsPage extends StatefulWidget {
  const SupplierPaymentsPage({
    super.key,
    required this.controller,
    required this.profile,
  });
  final SupplierPaymentsController controller;
  final BusinessProfile profile;
  @override
  State<SupplierPaymentsPage> createState() => _SupplierPaymentsPageState();
}

class _SupplierPaymentsPageState extends State<SupplierPaymentsPage> {
  final _form = GlobalKey<FormState>();
  final _parts = <_PartEditor>[];
  String? _payableId;
  String? _pendingId;
  bool _dirty = false;

  int _editorVersion = 0;

  int _historyPage = 0;

  @override
  void dispose() {
    for (final part in _parts) {
      part.dispose();
    }
    super.dispose();
  }

  String _money(int value) => inventoryMoney(value, widget.profile);
  String _amount(int value) => Money.fromMinorUnits(
    value,
    currency: widget.profile.currencyCode,
    scale: widget.profile.moneyScale,
  ).formatEsCo();

  void _edit(PayableSummary? payable, {PreparedSupplierPayment? pending}) {
    _payableId = pending?.payableId ?? payable?.payableId;
    _pendingId = pending?.commandId;
    for (final part in _parts) {
      part.dispose();
    }
    _parts
      ..clear()
      ..addAll([
        if (pending != null)
          for (final part in pending.parts)
            _PartEditor(
              accountId: part.cashAccountId,
              methodId: part.paymentMethodId,
              amount: _amount(part.amountMinor),
            ),
      ]);
    if (_parts.isEmpty) _parts.add(_PartEditor());
    _dirty = false;
    _editorVersion++;
  }

  Future<void> _select(String id, SupplierPaymentsSnapshot data) async {
    if (widget.controller.busy) return;
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Hay un pago sin confirmar'),
          content: const Text(
            'Los importes del formulario aún no están guardados. Puedes volver o descartarlos para elegir otra compra.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Volver'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Descartar cambios'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    setState(
      () => _edit(data.payables.firstWhere((item) => item.payableId == id)),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final data = controller.snapshot;
      final pending = controller.pendingPayments.firstOrNull;
      if (data != null && pending != null && _pendingId != pending.commandId) {
        _edit(
          data.payables
              .where((item) => item.payableId == pending.payableId)
              .firstOrNull,
          pending: pending,
        );
      }
      if (data != null &&
          pending == null &&
          _pendingId != null &&
          data.payments.any((item) => item.commandId == _pendingId)) {
        _edit(
          data.payables
                  .where(
                    (item) =>
                        item.payableId == _payableId && item.remainingMinor > 0,
                  )
                  .firstOrNull ??
              data.payables
                  .where((item) => item.remainingMinor > 0)
                  .firstOrNull,
        );
        _historyPage = 0;
      }
      if (data != null && _parts.isEmpty) {
        _edit(
          data.payables.where((item) => item.remainingMinor > 0).firstOrNull,
        );
      }
      final locked =
          controller.busy || pending != null || controller.loadError != null;
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true): () {
            if (!locked && data != null) _confirm(data);
          },
        },
        child: FocusTraversalGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InventoryPageHeading(
                title: 'Pagos a proveedores',
                subtitle:
                    'Registra abonos o pagos completos de compras a crédito. El dinero sale de una o varias cuentas con saldo disponible.',
                busy: controller.busy,
                onRefresh: controller.load,
              ),
              if (controller.loadError != null)
                InventoryNotice(
                  text: controller.loadError!,
                  onRetry: controller.busy ? null : controller.load,
                ),
              if (controller.operationError != null)
                InventoryNotice(text: controller.operationError!),
              if (controller.operationNotice != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Text(
                    controller.operationNotice!,
                    key: const Key('supplier-payment-notice'),
                    style: const TextStyle(
                      color: Color(0xFF183D35),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (data == null)
                if (controller.loading)
                  const Center(child: CircularProgressIndicator())
                else
                  const Text('La información de pagos no está disponible.')
              else ...[
                _editor(data, pending, locked),
                const SizedBox(height: 24),
                _balances(data),
                const SizedBox(height: 28),
                Text(
                  'Historial de pagos',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Cada pago conserva las cuentas y los medios usados, y el saldo que quedó en ese momento.',
                  style: TextStyle(color: Color(0xFF65716A), height: 1.5),
                ),
                const SizedBox(height: 16),
                _history(data),
              ],
            ],
          ),
        ),
      );
    },
  );

  Widget _editor(
    SupplierPaymentsSnapshot data,
    PreparedSupplierPayment? pending,
    bool locked,
  ) {
    final selected = data.payables
        .where((item) => item.payableId == _payableId)
        .firstOrNull;
    final candidates = data.payables
        .where(
          (item) => item.remainingMinor > 0 || item.payableId == _payableId,
        )
        .toList();
    final activeAccounts = data.accounts
        .where(
          (item) => item.isActive && item.isAvailable && item.balanceMinor > 0,
        )
        .toList();
    final activeMethods = data.methods.where((item) => item.isActive).toList();
    final total = _total();
    final fundingError = locked ? null : _fundingError(data);
    final remaining = selected == null || total == null
        ? null
        : BigInt.from(selected.remainingMinor) - total;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pending == null
                    ? 'Registrar un pago'
                    : 'Pago pendiente de resolver',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              if (pending != null) ...[
                Container(
                  key: const Key('supplier-payment-pending'),
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4EDD9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    pending.status == 'rejected'
                        ? 'La solicitud fue rechazada sin registrar dinero. Desbloquea para corregirla. Los importes siguen protegidos hasta entonces.'
                        : widget.controller.preparationUncertain
                        ? 'Preparación sin respuesta: los importes están protegidos. Reintenta aquí la misma solicitud para saber si se guardó.'
                        : 'Solicitud guardada: los importes están protegidos. Reintentar recupera este mismo pago y evita duplicarlo.',
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (candidates.isEmpty && pending == null) ...[
                const Text(
                  'No hay compras con saldo pendiente. Registra una recepción a crédito en Compras para pagarla aquí.',
                ),
              ] else ...[
                DropdownButtonFormField<String>(
                  key: ValueKey('supplier-payment-sale-$_editorVersion'),
                  initialValue: _payableId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Compra por pagar',
                  ),
                  items: [
                    for (final item in candidates)
                      DropdownMenuItem(
                        value: item.payableId,
                        child: Text(
                          '${item.label} · ${item.supplierName}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (_payableId != null &&
                        !candidates.any((item) => item.payableId == _payableId))
                      DropdownMenuItem(
                        value: _payableId,
                        child: Text(
                          '${pending?.label ?? 'Compra'} · ${pending?.supplierName ?? ''}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: locked
                      ? null
                      : (value) {
                          if (value != null) _select(value, data);
                        },
                  validator: (value) =>
                      value == null ? 'Selecciona una compra.' : null,
                ),
                const SizedBox(height: 16),
                if (selected != null)
                  Wrap(
                    spacing: 24,
                    runSpacing: 10,
                    children: [
                      Text('Compra: ${_money(selected.initialMinor)}'),
                      Text('Pagado: ${_money(selected.paidMinor)}'),
                      Text(
                        'Pendiente: ${_money(selected.remainingMinor)}',
                        key: const Key('supplier-payment-current-balance'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text('Vence: ${selected.dueDate}'),
                    ],
                  ),
                const SizedBox(height: 20),
                if (activeAccounts.isEmpty || activeMethods.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text(
                      'Necesitas una cuenta activa, disponible y con saldo registrado, y un medio activo. Consulta las cuentas y sus saldos en Tesorería. Los abonos confirmados en Deudores aportan saldo.',
                    ),
                  ),
                for (var index = 0; index < _parts.length; index++)
                  _part(_parts[index], index, data, pending, locked),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('add-supplier-payment-part'),
                      onPressed: locked || _parts.length >= 20
                          ? null
                          : () => setState(() {
                              _parts.add(_PartEditor());
                              _dirty = true;
                            }),
                      icon: const Icon(Icons.add),
                      label: const Text('Añadir medio'),
                    ),
                    TextButton(
                      key: const Key('fill-supplier-payment-total'),
                      onPressed:
                          locked || selected == null || _parts.length != 1
                          ? null
                          : () => setState(() {
                              _parts.single.amount.text = _amount(
                                selected.remainingMinor,
                              );
                              _dirty = true;
                            }),
                      child: const Text('Pagar saldo completo'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  total == null || total > Money.maxMinorUnits
                      ? 'Total del pago: completa los importes'
                      : 'Total del pago: ${_money(total.toInt())}',
                  key: const Key('supplier-payment-total'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (remaining != null && remaining >= BigInt.zero)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Quedará pendiente: ${_money(remaining.toInt())}',
                      key: const Key('supplier-payment-after-balance'),
                    ),
                  ),
                if (remaining != null && remaining < BigInt.zero)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'El pago supera el saldo pendiente.',
                      style: TextStyle(color: Color(0xFFB3261E)),
                    ),
                  ),
                if (fundingError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      fundingError,
                      style: const TextStyle(color: Color(0xFFB3261E)),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  pending != null
                      ? 'Los datos de esta solicitud ya no se pueden editar.'
                      : _dirty
                      ? 'Importes sin confirmar · se conservan al navegar, pero todavía no están guardados.'
                      : 'Completa los datos y confirma para registrar el dinero. Ctrl+Enter abre la revisión.',
                  key: const Key('supplier-payment-editor-state'),
                  style: const TextStyle(color: Color(0xFF65716A)),
                ),
                const SizedBox(height: 20),
                if (pending?.status == 'rejected')
                  OutlinedButton.icon(
                    key: const Key('unlock-supplier-payment'),
                    onPressed: widget.controller.busy
                        ? null
                        : () async {
                            final done = await widget.controller.unlockRejected(
                              pending!.commandId,
                            );
                            if (mounted && done) {
                              setState(() {
                                _pendingId = null;
                                _dirty = true;
                              });
                            }
                          },
                    icon: const Icon(Icons.lock_open),
                    label: const Text('Desbloquear y corregir'),
                  )
                else
                  FilledButton.icon(
                    key: const Key('confirm-supplier-payment'),
                    onPressed: widget.controller.busy
                        ? null
                        : pending != null
                        ? () async {
                            final done = await widget.controller.retry(
                              pending.commandId,
                            );
                            if (mounted && done) _resetAfterSuccess();
                          }
                        : locked ||
                              activeAccounts.isEmpty ||
                              activeMethods.isEmpty
                        ? null
                        : () => _confirm(data),
                    icon: Icon(
                      widget.controller.confirming
                          ? Icons.hourglass_empty
                          : pending != null
                          ? Icons.refresh
                          : Icons.payments_outlined,
                    ),
                    label: Text(
                      widget.controller.confirming
                          ? 'Registrando…'
                          : pending != null
                          ? 'Reintentar el mismo pago'
                          : 'Revisar y confirmar pago',
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _part(
    _PartEditor part,
    int index,
    SupplierPaymentsSnapshot data,
    PreparedSupplierPayment? pending,
    bool locked,
  ) {
    final historical = pending?.parts
        .where(
          (item) =>
              item.cashAccountId == part.accountId &&
              item.paymentMethodId == part.methodId,
        )
        .firstOrNull;
    final accounts = data.accounts
        .where((item) => item.isActive || item.id == part.accountId)
        .toList();
    final methods = data.methods
        .where((item) => item.isActive || item.id == part.methodId)
        .toList();
    return Container(
      key: ValueKey(part.id),
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE4E7E0)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Parte ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: 'Quitar parte ${index + 1}',
                onPressed: locked || _parts.length == 1
                    ? null
                    : () => setState(() {
                        _parts.remove(part);
                        part.dispose();
                        _dirty = true;
                      }),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('supplier-payment-account-${part.id}'),
            initialValue: part.accountId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Cuenta que paga'),
            items: [
              for (final account in accounts)
                DropdownMenuItem(
                  value: account.id,
                  enabled:
                      account.isActive &&
                      account.isAvailable &&
                      account.balanceMinor > 0,
                  child: Text(
                    '${account.name} · ${_money(account.balanceMinor)}${account.isAvailable ? '' : ' · no disponible'}${account.isActive ? '' : ' · archivada'}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (part.accountId != null &&
                  !accounts.any((item) => item.id == part.accountId))
                DropdownMenuItem(
                  value: part.accountId,
                  child: Text(
                    historical?.cashAccountName ?? 'Cuenta no disponible',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: locked
                ? null
                : (value) => setState(() {
                    part.accountId = value;
                    _dirty = true;
                  }),
            validator: (value) => value == null
                ? 'Selecciona una cuenta.'
                : !data.accounts.any(
                        (item) =>
                            item.id == value &&
                            item.isActive &&
                            item.isAvailable &&
                            item.balanceMinor > 0,
                      ) &&
                      !locked
                ? 'Selecciona una cuenta activa, disponible y con saldo.'
                : null,
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 500
                  ? (constraints.maxWidth - 16) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  SizedBox(
                    width: width,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('supplier-payment-method-${part.id}'),
                      initialValue: part.methodId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Medio de pago',
                      ),
                      items: [
                        for (final method in methods)
                          DropdownMenuItem(
                            value: method.id,
                            enabled: method.isActive,
                            child: Text(
                              '${method.name}${method.isActive ? '' : ' · archivado'}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        if (part.methodId != null &&
                            !methods.any((item) => item.id == part.methodId))
                          DropdownMenuItem(
                            value: part.methodId,
                            child: Text(
                              historical?.paymentMethodName ??
                                  'Medio no disponible',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: locked
                          ? null
                          : (value) => setState(() {
                              part.methodId = value;
                              _dirty = true;
                            }),
                      validator: (value) => value == null
                          ? 'Selecciona un medio.'
                          : !data.methods.any(
                                  (item) => item.id == value && item.isActive,
                                ) &&
                                !locked
                          ? 'Selecciona un medio activo.'
                          : null,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: TextFormField(
                      key: ValueKey('supplier-payment-amount-${part.id}'),
                      controller: part.amount,
                      enabled: !locked,
                      decoration: InputDecoration(
                        labelText: 'Importe (${widget.profile.currencyCode})',
                        helperText: '${widget.profile.moneyScale} decimales',
                      ),
                      validator: (value) {
                        final error = inventoryAmountError(
                          value,
                          widget.profile,
                        );
                        if (error != null) return error;
                        return Money.parseEsCo(
                                  value!,
                                  currency: widget.profile.currencyCode,
                                  scale: widget.profile.moneyScale,
                                ).minorUnits <=
                                0
                            ? 'El importe debe ser positivo.'
                            : null;
                      },
                      onChanged: (_) => setState(() => _dirty = true),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  BigInt? _total() {
    var total = BigInt.zero;
    for (final part in _parts) {
      if (inventoryAmountError(part.amount.text, widget.profile) != null) {
        return null;
      }
      total += Money.parseEsCo(
        part.amount.text,
        currency: widget.profile.currencyCode,
        scale: widget.profile.moneyScale,
      ).asBigInt;
    }
    return total;
  }

  String? _fundingError(SupplierPaymentsSnapshot data) {
    final requested = <String, BigInt>{};
    for (final part in _parts) {
      if (part.accountId == null ||
          inventoryAmountError(part.amount.text, widget.profile) != null) {
        continue;
      }
      final amount = Money.parseEsCo(
        part.amount.text,
        currency: widget.profile.currencyCode,
        scale: widget.profile.moneyScale,
      ).asBigInt;
      requested.update(
        part.accountId!,
        (value) => value + amount,
        ifAbsent: () => amount,
      );
    }
    for (final entry in requested.entries) {
      final account = data.accounts
          .where((item) => item.id == entry.key)
          .firstOrNull;
      if (account == null || !account.isActive || !account.isAvailable) {
        return 'La cuenta elegida no está disponible para pagar.';
      }
      if (entry.value > BigInt.from(account.balanceMinor)) {
        return 'Saldo insuficiente en ${account.name}: disponible ${_money(account.balanceMinor)}. Se suman todas las partes de la misma cuenta.';
      }
    }
    return null;
  }

  Future<void> _confirm(SupplierPaymentsSnapshot data) async {
    if (!_form.currentState!.validate()) return;
    final selected = data.payables
        .where((item) => item.payableId == _payableId)
        .firstOrNull;
    final total = _total();
    if (selected == null ||
        total == null ||
        total <= BigInt.zero ||
        total > Money.maxMinorUnits ||
        total > BigInt.from(selected.remainingMinor)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'El total debe ser positivo y no superar el saldo pendiente.',
          ),
        ),
      );
      return;
    }
    final fundingError = _fundingError(data);
    if (fundingError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(fundingError)));
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar dinero entregado'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${selected.label} · ${selected.supplierName}'),
              const SizedBox(height: 16),
              for (final part in _parts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '${data.accounts.firstWhere((item) => item.id == part.accountId).name} · ${data.methods.firstWhere((item) => item.id == part.methodId).name}\n${_money(Money.parseEsCo(part.amount.text, currency: widget.profile.currencyCode, scale: widget.profile.moneyScale).minorUnits)}',
                  ),
                ),
              Text(
                'Total pagado: ${_money(total.toInt())}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Text(
                'Quedará pendiente: ${_money(selected.remainingMinor - total.toInt())}',
              ),
              const SizedBox(height: 16),
              const Text(
                'Confirma cuando hayas realizado el pago. Esta acción registra la salida de dinero y reduce la deuda.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            key: const Key('accept-supplier-payment'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar pago'),
          ),
        ],
      ),
    );
    if (!mounted || accepted != true) return;
    final done = await widget.controller.pay(
      payableId: selected.payableId,
      parts: [
        for (final part in _parts)
          SupplierPaymentPartInput(
            cashAccountId: part.accountId!,
            paymentMethodId: part.methodId!,
            amountMinor: Money.parseEsCo(
              part.amount.text,
              currency: widget.profile.currencyCode,
              scale: widget.profile.moneyScale,
            ).minorUnits,
          ),
      ],
    );
    if (mounted && done) _resetAfterSuccess();
  }

  void _resetAfterSuccess() => setState(() {
    final data = widget.controller.snapshot;
    _edit(
      widget.controller.loadError == null
          ? data?.payables
                    .where(
                      (item) =>
                          item.payableId == _payableId &&
                          item.remainingMinor > 0,
                    )
                    .firstOrNull ??
                data?.payables
                    .where((item) => item.remainingMinor > 0)
                    .firstOrNull
          : null,
    );
    _historyPage = 0;
  });

  Widget _balances(SupplierPaymentsSnapshot data) => Card(
    child: ExpansionTile(
      key: const Key('supplier-payment-balances'),
      initiallyExpanded: data.accounts.isEmpty || data.methods.isEmpty,
      title: const Text('Cuentas y saldos registrados'),
      subtitle: const Text('Consulta cuentas y saldos en Tesorería'),
      tilePadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      childrenPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Solo puedes pagar con dinero registrado en cuentas activas y disponibles. Crear una cuenta no añade saldo. Los cobros aumentan el saldo y los pagos lo reducen.',
            style: TextStyle(color: Color(0xFF65716A), height: 1.5),
          ),
        ),
        const SizedBox(height: 16),
        for (final account in data.accounts)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              '${account.name}${account.isActive ? '' : ' · archivada'}',
            ),
            subtitle: Text(
              '${account.isAvailable ? 'Disponible' : 'No disponible'} · Saldo registrado: ${_money(account.balanceMinor)}',
            ),
          ),
        if (data.accounts.isEmpty) const Text('Aún no hay cuentas monetarias.'),
        if (data.methods.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Aún no hay medios de pago disponibles. Actualiza para cargar los medios locales.',
            ),
          ),
      ],
    ),
  );

  Widget _history(SupplierPaymentsSnapshot data) {
    if (data.payments.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Aún no hay pagos confirmados.'),
        ),
      );
    }
    const pageSize = 10;
    final page = _historyPage.clamp(0, (data.payments.length - 1) ~/ pageSize);
    return Column(
      children: [
        for (final item in data.payments.skip(page * pageSize).take(pageSize))
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${item.label} · ${item.supplierName}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 24,
                    runSpacing: 10,
                    children: [
                      Text(
                        'Pagado: ${_money(item.totalMinor)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Pendiente tras este pago: ${_money(item.remainingMinor)}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pagado: ${InventoryController.isoDate(item.paidAtUtc.subtract(const Duration(hours: 5)))}',
                  ),
                  const Divider(height: 24),
                  for (final part in item.parts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${part.cashAccountName} · ${part.paymentMethodName} · ${_money(part.amountMinor)}',
                      ),
                    ),
                ],
              ),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              '${page * pageSize + 1}–${(page * pageSize + pageSize).clamp(0, data.payments.length)} de ${data.payments.length}',
            ),
            IconButton(
              tooltip: 'Pagos anteriores',
              onPressed: page == 0
                  ? null
                  : () => setState(() => _historyPage = page - 1),
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: 'Pagos siguientes',
              onPressed: (page + 1) * pageSize >= data.payments.length
                  ? null
                  : () => setState(() => _historyPage = page + 1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    );
  }
}

class _PartEditor {
  _PartEditor({this.accountId, this.methodId, String amount = ''})
    : amount = TextEditingController(text: amount);
  final id = InventoryIds.next();
  String? accountId;
  String? methodId;
  final TextEditingController amount;
  void dispose() => amount.dispose();
}
