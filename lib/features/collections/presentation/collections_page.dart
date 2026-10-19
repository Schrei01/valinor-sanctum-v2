import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/domain/money.dart';
import '../../inventory/application/inventory_controller.dart';
import '../../inventory/domain/inventory_store.dart';
import '../../inventory/presentation/inventory_widgets.dart';
import '../../workspace/domain/business_profile.dart';
import '../application/collections_controller.dart';
import '../domain/collections_store.dart';

class CollectionsPage extends StatefulWidget {
  const CollectionsPage({
    super.key,
    required this.controller,
    required this.profile,
  });
  final CollectionsController controller;
  final BusinessProfile profile;
  @override
  State<CollectionsPage> createState() => _CollectionsPageState();
}

class _CollectionsPageState extends State<CollectionsPage> {
  final _form = GlobalKey<FormState>();
  final _accountForm = GlobalKey<FormState>();
  final _methodForm = GlobalKey<FormState>();
  final _accountName = TextEditingController();
  final _methodName = TextEditingController();
  final _methodCode = TextEditingController();
  final _parts = <_PartEditor>[];
  String? _receivableId;
  String? _pendingId;
  String? _accountId;
  String? _methodId;
  String _accountKind = 'cash';
  bool _accountAvailable = true;
  bool _accountActive = true;
  bool _methodActive = true;
  bool _dirty = false;
  bool _configurationDirty = false;
  int _editorVersion = 0;
  int _configurationVersion = 0;
  int _historyPage = 0;

  @override
  void dispose() {
    _accountName.dispose();
    _methodName.dispose();
    _methodCode.dispose();
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

  void _edit(ReceivableSummary? receivable, {PreparedCollection? pending}) {
    _receivableId = pending?.receivableId ?? receivable?.receivableId;
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

  Future<void> _select(String id, CollectionsSnapshot data) async {
    if (widget.controller.busy) return;
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Hay un cobro sin confirmar'),
          content: const Text(
            'Los importes del formulario aún no están guardados. Puedes volver o descartarlos para elegir otra venta.',
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
      () =>
          _edit(data.receivables.firstWhere((item) => item.receivableId == id)),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final data = controller.snapshot;
      final pending = controller.pendingCollections.firstOrNull;
      if (data != null && pending != null && _pendingId != pending.commandId) {
        _edit(
          data.receivables
              .where((item) => item.receivableId == pending.receivableId)
              .firstOrNull,
          pending: pending,
        );
      }
      if (data != null &&
          pending == null &&
          _pendingId != null &&
          data.collections.any((item) => item.commandId == _pendingId)) {
        _edit(
          data.receivables
                  .where(
                    (item) =>
                        item.receivableId == _receivableId &&
                        item.remainingMinor > 0,
                  )
                  .firstOrNull ??
              data.receivables
                  .where((item) => item.remainingMinor > 0)
                  .firstOrNull,
        );
        _historyPage = 0;
      }
      if (data != null && _parts.isEmpty) {
        _edit(
          data.receivables.where((item) => item.remainingMinor > 0).firstOrNull,
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
                title: 'Cobros y abonos',
                subtitle:
                    'Registra el dinero recibido de una venta a crédito. Puedes abonar una parte o pagar el saldo completo, usando uno o varios medios.',
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
                    key: const Key('collection-notice'),
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
                  const Text('La información de cobros no está disponible.')
              else ...[
                _editor(data, pending, locked),
                const SizedBox(height: 24),
                _configuration(data, locked),
                const SizedBox(height: 28),
                Text(
                  'Historial de cobros',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Cada cobro conserva las cuentas y los medios usados, y el saldo que quedó en ese momento.',
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
    CollectionsSnapshot data,
    PreparedCollection? pending,
    bool locked,
  ) {
    final selected = data.receivables
        .where((item) => item.receivableId == _receivableId)
        .firstOrNull;
    final candidates = data.receivables
        .where(
          (item) =>
              item.remainingMinor > 0 || item.receivableId == _receivableId,
        )
        .toList();
    final activeAccounts = data.accounts
        .where((item) => item.isActive)
        .toList();
    final activeMethods = data.methods.where((item) => item.isActive).toList();
    final total = _total();
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
                    ? 'Registrar un cobro'
                    : 'Cobro pendiente de resolver',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              if (pending != null) ...[
                Container(
                  key: const Key('collection-pending'),
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
                        : 'Solicitud guardada: los importes están protegidos. Reintentar recupera este mismo cobro y evita duplicarlo.',
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (candidates.isEmpty && pending == null) ...[
                const Text(
                  'No hay ventas con saldo pendiente. Confirma una entrega a crédito en Ventas para registrar su cobro.',
                ),
              ] else ...[
                DropdownButtonFormField<String>(
                  key: ValueKey('collection-sale-$_editorVersion'),
                  initialValue: _receivableId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Venta por cobrar',
                  ),
                  items: [
                    for (final item in candidates)
                      DropdownMenuItem(
                        value: item.receivableId,
                        child: Text(
                          '${item.label} · ${item.customerName}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (_receivableId != null &&
                        !candidates.any(
                          (item) => item.receivableId == _receivableId,
                        ))
                      DropdownMenuItem(
                        value: _receivableId,
                        child: Text(
                          '${pending?.label ?? 'Venta'} · ${pending?.customerName ?? ''}',
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
                      value == null ? 'Selecciona una venta.' : null,
                ),
                const SizedBox(height: 16),
                if (selected != null)
                  Wrap(
                    spacing: 24,
                    runSpacing: 10,
                    children: [
                      Text('Venta: ${_money(selected.initialMinor)}'),
                      Text('Cobrado: ${_money(selected.collectedMinor)}'),
                      Text(
                        'Pendiente: ${_money(selected.remainingMinor)}',
                        key: const Key('collection-current-balance'),
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
                      'Configura al menos una cuenta monetaria y un medio de pago activos en la sección de abajo.',
                    ),
                  ),
                for (var index = 0; index < _parts.length; index++)
                  _part(_parts[index], index, data, pending, locked),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('add-collection-part'),
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
                      key: const Key('fill-collection-total'),
                      onPressed:
                          locked || selected == null || _parts.length != 1
                          ? null
                          : () => setState(() {
                              _parts.single.amount.text = _amount(
                                selected.remainingMinor,
                              );
                              _dirty = true;
                            }),
                      child: const Text('Cobrar saldo completo'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  total == null || total > Money.maxMinorUnits
                      ? 'Total del cobro: completa los importes'
                      : 'Total del cobro: ${_money(total.toInt())}',
                  key: const Key('collection-total'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (remaining != null && remaining >= BigInt.zero)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Quedará pendiente: ${_money(remaining.toInt())}',
                      key: const Key('collection-after-balance'),
                    ),
                  ),
                if (remaining != null && remaining < BigInt.zero)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'El cobro supera el saldo pendiente.',
                      style: TextStyle(color: Color(0xFFB3261E)),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  pending != null
                      ? 'Los datos de esta solicitud ya no se pueden editar.'
                      : _dirty
                      ? 'Importes sin confirmar · se conservan al navegar, pero todavía no están guardados.'
                      : 'Completa los datos y confirma para registrar el dinero. Ctrl+Enter abre la revisión.',
                  key: const Key('collection-editor-state'),
                  style: const TextStyle(color: Color(0xFF65716A)),
                ),
                const SizedBox(height: 20),
                if (pending?.status == 'rejected')
                  OutlinedButton.icon(
                    key: const Key('unlock-collection'),
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
                    key: const Key('confirm-collection'),
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
                          ? 'Reintentar el mismo cobro'
                          : 'Revisar y confirmar cobro',
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
    CollectionsSnapshot data,
    PreparedCollection? pending,
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
            key: ValueKey('collection-account-${part.id}'),
            initialValue: part.accountId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Cuenta que recibe'),
            items: [
              for (final account in accounts)
                DropdownMenuItem(
                  value: account.id,
                  enabled: account.isActive,
                  child: Text(
                    '${account.name}${account.isAvailable ? '' : ' · no disponible'}${account.isActive ? '' : ' · archivada'}',
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
                        (item) => item.id == value && item.isActive,
                      ) &&
                      !locked
                ? 'Selecciona una cuenta activa.'
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
                      key: ValueKey('collection-method-${part.id}'),
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
                      key: ValueKey('collection-amount-${part.id}'),
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

  Future<void> _confirm(CollectionsSnapshot data) async {
    if (!_form.currentState!.validate()) return;
    final selected = data.receivables
        .where((item) => item.receivableId == _receivableId)
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
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar dinero recibido'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${selected.label} · ${selected.customerName}'),
              const SizedBox(height: 16),
              for (final part in _parts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '${data.accounts.firstWhere((item) => item.id == part.accountId).name} · ${data.methods.firstWhere((item) => item.id == part.methodId).name}\n${_money(Money.parseEsCo(part.amount.text, currency: widget.profile.currencyCode, scale: widget.profile.moneyScale).minorUnits)}',
                  ),
                ),
              Text(
                'Total recibido: ${_money(total.toInt())}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Text(
                'Quedará pendiente: ${_money(selected.remainingMinor - total.toInt())}',
              ),
              const SizedBox(height: 16),
              const Text(
                'Confirma cuando hayas recibido el dinero. Esta acción registra el ingreso y reduce la deuda.',
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
            key: const Key('accept-collection'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar cobro'),
          ),
        ],
      ),
    );
    if (!mounted || accepted != true) return;
    final done = await widget.controller.collect(
      receivableId: selected.receivableId,
      parts: [
        for (final part in _parts)
          CollectionPartInput(
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
          ? data?.receivables
                    .where(
                      (item) =>
                          item.receivableId == _receivableId &&
                          item.remainingMinor > 0,
                    )
                    .firstOrNull ??
                data?.receivables
                    .where((item) => item.remainingMinor > 0)
                    .firstOrNull
          : null,
    );
    _historyPage = 0;
  });

  Widget _configuration(CollectionsSnapshot data, bool locked) => Card(
    child: ExpansionTile(
      key: const Key('collection-configuration'),
      initiallyExpanded: data.accounts.isEmpty || data.methods.isEmpty,
      title: const Text('Cuentas monetarias y medios'),
      subtitle: const Text('Configuración local y saldos de movimientos'),
      tilePadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      childrenPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Estas cuentas son destinos locales de cobro; no se conectan a un banco. Crear una cuenta no registra dinero ni un saldo de apertura.',
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
              '${_kindLabel(account.kind)} · ${account.isAvailable ? 'Disponible' : 'No disponible'}\nSaldo de movimientos: ${_money(account.balanceMinor)}',
            ),
            isThreeLine: true,
            trailing: IconButton(
              tooltip: 'Editar cuenta ${account.name}',
              onPressed: locked
                  ? null
                  : () => setState(() {
                      _accountId = account.id;
                      _accountName.text = account.name;
                      _accountKind = account.kind;
                      _accountAvailable = account.isAvailable;
                      _accountActive = account.isActive;
                      _configurationVersion++;
                    }),
              icon: const Icon(Icons.edit_outlined),
            ),
          ),
        const Divider(height: 32),
        Form(
          key: _accountForm,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _accountId == null
                    ? 'Nueva cuenta monetaria'
                    : 'Editar cuenta monetaria',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('collection-account-name'),
                controller: _accountName,
                enabled: !locked,
                decoration: const InputDecoration(
                  labelText: 'Nombre de la cuenta',
                ),
                validator: inventoryNameError,
                onChanged: (_) => setState(() => _configurationDirty = true),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: ValueKey('collection-account-kind-$_configurationVersion'),
                initialValue: _accountKind,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Tipo de cuenta'),
                items: [
                  for (final kind in ['cash', 'bank', 'mobile', 'clearing'])
                    DropdownMenuItem(
                      value: kind,
                      child: Text(_kindLabel(kind)),
                    ),
                ],
                onChanged: locked || _accountId != null
                    ? null
                    : (value) => setState(() {
                        _accountKind = value!;
                        _configurationDirty = true;
                      }),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Dinero disponible'),
                subtitle: const Text(
                  'Desactiva si el dinero está por liquidar o no está disponible.',
                ),
                value: _accountAvailable,
                onChanged: locked
                    ? null
                    : (value) => setState(() {
                        _accountAvailable = value;
                        _configurationDirty = true;
                      }),
              ),
              if (_accountId != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Cuenta activa'),
                  value: _accountActive,
                  onChanged: locked
                      ? null
                      : (value) => setState(() {
                          _accountActive = value;
                          _configurationDirty = true;
                        }),
                ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton(
                    key: const Key('save-collection-account'),
                    onPressed: locked ? null : _saveAccount,
                    child: const Text('Guardar cuenta'),
                  ),
                  if (_accountId != null)
                    TextButton(
                      onPressed: locked ? null : () => setState(_clearAccount),
                      child: const Text('Nueva cuenta'),
                    ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 40),
        for (final method in data.methods)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              '${method.name}${method.isActive ? '' : ' · archivado'}',
            ),
            subtitle: Text(method.code),
            trailing: IconButton(
              tooltip: 'Editar medio ${method.name}',
              onPressed: locked
                  ? null
                  : () => setState(() {
                      _methodId = method.id;
                      _methodName.text = method.name;
                      _methodCode.text = method.code;
                      _methodActive = method.isActive;
                    }),
              icon: const Icon(Icons.edit_outlined),
            ),
          ),
        const SizedBox(height: 16),
        Form(
          key: _methodForm,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _methodId == null
                    ? 'Nuevo medio de pago'
                    : 'Editar medio de pago',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('collection-method-name'),
                controller: _methodName,
                enabled: !locked,
                decoration: const InputDecoration(
                  labelText: 'Nombre del medio',
                ),
                validator: inventoryNameError,
                onChanged: (_) => setState(() => _configurationDirty = true),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('collection-method-code'),
                controller: _methodCode,
                enabled: !locked && _methodId == null,
                decoration: const InputDecoration(
                  labelText: 'Código del medio',
                  helperText:
                      'Código estable, por ejemplo EFECTIVO o TRANSFERENCIA.',
                ),
                validator: (value) =>
                    RegExp(
                      r'^[A-Za-z0-9_-]{1,40}$',
                    ).hasMatch(value?.trim() ?? '')
                    ? null
                    : 'Usa 1–40 letras, números, guion o guion bajo.',
                onChanged: (_) => setState(() => _configurationDirty = true),
              ),
              if (_methodId != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Medio activo'),
                  value: _methodActive,
                  onChanged: locked
                      ? null
                      : (value) => setState(() {
                          _methodActive = value;
                          _configurationDirty = true;
                        }),
                ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton(
                    key: const Key('save-collection-method'),
                    onPressed: locked ? null : _saveMethod,
                    child: const Text('Guardar medio'),
                  ),
                  if (_methodId != null)
                    TextButton(
                      onPressed: locked
                          ? null
                          : () => setState(() {
                              _methodId = null;
                              _methodName.clear();
                              _methodCode.clear();
                              _methodActive = true;
                            }),
                      child: const Text('Nuevo medio'),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (_configurationDirty)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Los cambios de configuración se conservan al navegar. Pulsa Guardar en cada formulario para persistirlos.',
                style: TextStyle(color: Color(0xFF65716A)),
              ),
            ),
          ),
      ],
    ),
  );

  String _kindLabel(String kind) => switch (kind) {
    'cash' => 'Efectivo',
    'bank' => 'Banco',
    'mobile' => 'Billetera móvil',
    'clearing' => 'Por liquidar',
    _ => kind,
  };
  void _clearAccount() {
    _accountId = null;
    _accountName.clear();
    _accountKind = 'cash';
    _accountAvailable = true;
    _accountActive = true;
    _configurationVersion++;
  }

  Future<void> _saveAccount() async {
    if (!_accountForm.currentState!.validate()) return;
    _accountId ??= InventoryIds.next();
    final done = await widget.controller.saveAccount(
      CollectionAccount(
        id: _accountId!,
        name: _accountName.text.trim(),
        kind: _accountKind,
        isAvailable: _accountAvailable,
        isActive: _accountActive,
      ),
    );
    if (mounted && done) {
      setState(() {
        _clearAccount();
        _configurationDirty = false;
      });
    }
  }

  Future<void> _saveMethod() async {
    if (!_methodForm.currentState!.validate()) return;
    _methodId ??= InventoryIds.next();
    final done = await widget.controller.saveMethod(
      CollectionMethod(
        id: _methodId!,
        code: _methodCode.text.trim(),
        name: _methodName.text.trim(),
        isActive: _methodActive,
      ),
    );
    if (mounted && done) {
      setState(() {
        _methodId = null;
        _methodName.clear();
        _methodCode.clear();
        _methodActive = true;
        _configurationDirty = false;
      });
    }
  }

  Widget _history(CollectionsSnapshot data) {
    if (data.collections.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Aún no hay cobros confirmados.'),
        ),
      );
    }
    const pageSize = 10;
    final page = _historyPage.clamp(
      0,
      (data.collections.length - 1) ~/ pageSize,
    );
    return Column(
      children: [
        for (final item
            in data.collections.skip(page * pageSize).take(pageSize))
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${item.label} · ${item.customerName}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 24,
                    runSpacing: 10,
                    children: [
                      Text(
                        'Cobrado: ${_money(item.totalMinor)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Pendiente tras este cobro: ${_money(item.remainingMinor)}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Recibido: ${InventoryController.isoDate(item.collectedAtUtc.subtract(const Duration(hours: 5)))}',
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
              '${page * pageSize + 1}–${(page * pageSize + pageSize).clamp(0, data.collections.length)} de ${data.collections.length}',
            ),
            IconButton(
              tooltip: 'Cobros anteriores',
              onPressed: page == 0
                  ? null
                  : () => setState(() => _historyPage = page - 1),
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: 'Cobros siguientes',
              onPressed: (page + 1) * pageSize >= data.collections.length
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
