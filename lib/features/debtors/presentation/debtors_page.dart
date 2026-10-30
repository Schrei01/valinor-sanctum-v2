import '../../../core/presentation/grouped_number_formatter.dart';
import '../../../core/presentation/financial_total.dart';
import 'package:flutter/material.dart';
import '../../../core/domain/money.dart';
import '../../inventory/domain/inventory_store.dart';
import '../../inventory/presentation/inventory_widgets.dart';
import '../../workspace/domain/business_profile.dart';
import '../application/debtors_controller.dart';
import '../domain/debtors_store.dart';

class DebtorsPage extends StatefulWidget {
  const DebtorsPage({
    super.key,
    required this.controller,
    required this.profile,
  });
  final DebtorsController controller;
  final BusinessProfile profile;
  @override
  State<DebtorsPage> createState() => _DebtorsPageState();
}

class _DebtorsPageState extends State<DebtorsPage> {
  final _amount = TextEditingController(), _search = TextEditingController();
  final _paymentForm = GlobalKey<FormState>();
  String? _selectedId, _optionId;
  String _query = '';
  int _chargePage = 0, _paymentPage = 0;
  String _money(int n) => inventoryMoney(n, widget.profile);
  String _textAmount(int n) => Money.fromMinorUnits(
    n,
    currency: widget.profile.currencyCode,
    scale: widget.profile.moneyScale,
  ).formatEsCo();
  int _parse(String text) => Money.parseEsCo(
    text,
    currency: widget.profile.currencyCode,
    scale: widget.profile.moneyScale,
  ).minorUnits;
  bool get _locked =>
      widget.controller.busy ||
      widget.controller.uncertain != null ||
      (widget.controller.snapshot?.pending.isNotEmpty ?? false);
  @override
  void dispose() {
    _amount.dispose();
    _search.dispose();
    super.dispose();
  }

  void _select(String id) {
    _paymentForm.currentState?.reset();
    setState(() {
      _selectedId = id;
      _amount.clear();
      _chargePage = 0;
      _paymentPage = 0;
    });
  }

  Future<void> _submitted(bool success) async {
    if (success && mounted) {
      setState(() {
        _selectedId = widget.controller.lastPersonId ?? _selectedId;
        _amount.clear();
      });
    }
  }

  Future<void> _pay(DebtorSummary person) async {
    if (!_paymentForm.currentState!.validate()) return;
    await _submitted(
      await widget.controller.submit(
        DebtorCommand(
          commandId: InventoryIds.next(),
          kind: 'payment',
          debtorId: person.id,
          amountMinor: _parse(_amount.text),
          paymentOptionId: _optionId,
          occurredAtUtc: DateTime.now().toUtc(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller,
          data = c.snapshot,
          selected = data?.debtors
              .where((p) => p.id == _selectedId)
              .firstOrNull;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InventoryPageHeading(
            title: 'Deudores',
            subtitle:
                'Registra personas, consulta sus deudas y recibe abonos en Efectivo o Transferencia.',
            busy: c.busy,
            onRefresh: c.load,
          ),
          if (c.error != null)
            InventoryNotice(text: c.error!, onRetry: c.busy ? null : c.load),
          if (c.message != null)
            InventoryNotice(
              text: c.message!,
              kind: InventoryNoticeKind.information,
            ),
          if (c.uncertain != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'No se pudo verificar el guardado. Reintenta la misma solicitud antes de registrar otro movimiento.',
                    ),
                    FilledButton(
                      onPressed: c.busy
                          ? null
                          : () async =>
                                _submitted(await c.submit(c.uncertain!)),
                      child: const Text('Verificar y reintentar'),
                    ),
                  ],
                ),
              ),
            ),
          if (data == null)
            if (c.busy)
              const LinearProgressIndicator()
            else
              const Text(
                'Abre Deudores o pulsa Actualizar para cargar la información.',
              )
          else ...[
            FinancialTotal(
              label: 'Total deudas',
              value: _money(
                data.debtors.fold(
                      0,
                      (sum, person) => sum + person.balanceMinor,
                    ) +
                    data.unassignedLegacyMinor +
                    data.charges
                        .where((charge) => charge.debtorId == null)
                        .fold(0, (sum, charge) => sum + charge.remainingMinor),
              ),
              valueKey: const Key('debtors-total'),
            ),
            const SizedBox(height: 16),
            for (final pending in data.pending)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_kindLabel(pending.command.kind)} pendiente · ${pending.nameSnapshot}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (pending.command.amountMinor > 0)
                        Text(_money(pending.command.amountMinor)),
                      if (pending.command.previousSource != null)
                        Text(
                          pending.command.previousSource ==
                                  PreviousDebtSource.includedInLegacy
                              ? 'Incluida en la cartera anterior'
                              : 'Deuda adicional no registrada',
                        ),
                      if (pending.command.paymentOptionId != null)
                        Text(
                          data.paymentOptions
                                  .where(
                                    (p) =>
                                        p.id == pending.command.paymentOptionId,
                                  )
                                  .firstOrNull
                                  ?.displayLabel ??
                              'Medio no disponible',
                        ),
                      const Text(
                        'Reintentar recupera la misma operación sin repetir movimientos. Descartar libera una solicitud no confirmada.',
                      ),
                      Wrap(
                        spacing: 12,
                        children: [
                          FilledButton(
                            onPressed: c.busy
                                ? null
                                : () async => _submitted(
                                    await c.retry(pending.command.commandId),
                                  ),
                            child: const Text('Reintentar operación'),
                          ),
                          TextButton(
                            onPressed: c.busy
                                ? null
                                : () => c.discard(pending.command.commandId),
                            child: const Text('Descartar solicitud'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  key: const Key('debtor-add'),
                  onPressed: _locked ? null : () => _createOrOpening(data),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Registrar persona'),
                ),
                SizedBox(
                  width: 300,
                  child: TextField(
                    key: const Key('debtor-search'),
                    controller: _search,
                    decoration: const InputDecoration(
                      labelText: 'Buscar persona',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) =>
                        setState(() => _query = v.trim().toLowerCase()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final people = _people(data);
                final details = selected == null
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Selecciona una persona para consultar su cuenta o registrar un abono.',
                        ),
                      )
                    : _details(data, selected);
                if (constraints.maxWidth < 760) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [people, const SizedBox(height: 20), details],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 280, child: people),
                    const SizedBox(width: 20),
                    Expanded(child: details),
                  ],
                );
              },
            ),
            const SizedBox(height: 28),
            _unassigned(data),
            if (data.legacyPending.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                'Cobros anteriores pendientes',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              for (final pending in data.legacyPending)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${pending.customerName} · ${pending.label} · ${_money(pending.totalMinor)}',
                        ),
                        const Text(
                          'Solicitud conservada de la versión anterior. Recuperarla no crea una venta nueva.',
                        ),
                        TextButton(
                          onPressed: _locked
                              ? null
                              : () => pending.status == 'rejected'
                                    ? c.discardLegacy(pending.commandId)
                                    : c.retryLegacy(pending.commandId),
                          child: Text(
                            pending.status == 'rejected'
                                ? 'Liberar cobro rechazado'
                                : 'Reintentar cobro anterior',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ],
      );
    },
  );
  Widget _people(DebtorsSnapshot data) {
    final people = data.debtors
        .where((p) => p.name.toLowerCase().contains(_query))
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Personas (${people.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (people.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('No hay personas que mostrar.'),
              ),
            for (final p in people)
              ListTile(
                key: ValueKey('debtor-person-${p.id}'),
                selected: _selectedId == p.id,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                title: Text(p.name),
                subtitle: Text(
                  '${_money(p.balanceMinor)}${p.isActive ? '' : ' · Fiado bloqueado'}',
                ),
                onTap: widget.controller.busy ? null : () => _select(p.id),
              ),
          ],
        ),
      ),
    );
  }

  Widget _details(DebtorsSnapshot data, DebtorSummary person) {
    final charges =
        data.charges
            .where((d) => d.debtorId == person.id && d.originalCreditMinor > 0)
            .toList()
          ..sort((a, b) => b.occurredAtUtc.compareTo(a.occurredAtUtc));
    final payments = data.payments
        .where((p) => p.debtorId == person.id)
        .toList();
    final chargePage = _chargePage.clamp(
          0,
          charges.isEmpty ? 0 : (charges.length - 1) ~/ 10,
        ),
        paymentPage = _paymentPage.clamp(
          0,
          payments.isEmpty ? 0 : (payments.length - 1) ~/ 10,
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(person.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            FinancialTotal(
              label: 'Deuda pendiente',
              value: _money(person.balanceMinor),
              valueKey: const Key('debtor-balance'),
            ),
            if (!person.isActive)
              const Text(
                'Esta persona no puede recibir nuevas ventas a Deudas. Puede seguir abonando.',
              ),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _locked ? null : () => _availability(person),
                  child: Text(
                    person.isActive ? 'Bloquear fiado' : 'Habilitar fiado',
                  ),
                ),
                if (!person.hasOpening)
                  TextButton(
                    key: const Key('debtor-add-opening'),
                    onPressed: _locked
                        ? null
                        : () => _createOrOpening(data, person: person),
                    child: const Text('Registrar deuda anterior'),
                  ),
              ],
            ),
            const Divider(height: 28),
            Text(
              'Registrar abono',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Form(
              key: _paymentForm,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: 230,
                        child: TextFormField(
                          key: const Key('debtor-payment-amount'),
                          controller: _amount,
                          inputFormatters: [const GroupedNumberFormatter()],
                          enabled: !_locked && person.balanceMinor > 0,
                          decoration: const InputDecoration(
                            labelText: 'Valor del abono',
                          ),
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            final error = inventoryAmountError(
                              v,
                              widget.profile,
                            );
                            if (error != null) return error;
                            final n = _parse(v!);
                            return n <= 0
                                ? 'El abono debe ser positivo.'
                                : n > person.balanceMinor
                                ? 'Supera la deuda pendiente.'
                                : null;
                          },
                        ),
                      ),
                      SizedBox(
                        width: 230,
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('debtor-payment-option-$_optionId'),
                          initialValue: _optionId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Medio de pago',
                          ),
                          items: [
                            if (_optionId != null &&
                                !data.paymentOptions.any(
                                  (o) => o.id == _optionId,
                                ))
                              DropdownMenuItem(
                                value: _optionId,
                                enabled: false,
                                child: const Text('Medio no disponible'),
                              ),
                            for (final o in data.paymentOptions)
                              DropdownMenuItem(
                                value: o.id,
                                child: Text(o.displayLabel),
                              ),
                          ],
                          onChanged: _locked || person.balanceMinor == 0
                              ? null
                              : (v) => setState(() => _optionId = v),
                          validator: (v) =>
                              v == null ||
                                  !data.paymentOptions.any((o) => o.id == v)
                              ? 'Elige Efectivo o Transferencia.'
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton(
                        onPressed: _locked || person.balanceMinor == 0
                            ? null
                            : () => setState(
                                () => _amount.text = _textAmount(
                                  person.balanceMinor,
                                ),
                              ),
                        child: const Text('Pagar todo'),
                      ),
                      FilledButton(
                        key: const Key('debtor-confirm-payment'),
                        onPressed: _locked || person.balanceMinor == 0
                            ? null
                            : () => _pay(person),
                        child: const Text('Registrar abono'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Se aplica primero a las deudas más antiguas y entra a Caja o a la cuenta de Transferencia. No genera otra venta ni descuenta inventario.',
                  ),
                ],
              ),
            ),
            const Divider(height: 32),
            Text(
              'Deudas registradas',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (charges.isEmpty)
              const Text('No hay deudas registradas para esta persona.'),
            for (final d in charges.skip(chargePage * 10).take(10))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${d.isOpening ? 'Saldo anterior' : d.label} · ${_date(d.occurredAtUtc)}',
                    ),
                    Text(
                      'Valor fiado: ${_money(d.originalCreditMinor)} · Pendiente: ${_money(d.remainingMinor)}',
                    ),
                    if (d.nameSnapshot != person.name)
                      Text('Registrada originalmente como ${d.nameSnapshot}'),
                  ],
                ),
              ),
            if (charges.length > 10)
              _pagination(
                charges.length,
                chargePage,
                (v) => setState(() => _chargePage = v),
              ),
            const Divider(height: 28),
            Text('Abonos', style: Theme.of(context).textTheme.titleMedium),
            if (payments.isEmpty) const Text('Aún no hay abonos.'),
            for (final p in payments.skip(paymentPage * 10).take(10))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '${_date(p.occurredAtUtc)} · ${_money(p.amountMinor)} · ${p.displayPaymentLabel}',
                ),
              ),
            if (payments.length > 10)
              _pagination(
                payments.length,
                paymentPage,
                (v) => setState(() => _paymentPage = v),
              ),
          ],
        ),
      ),
    );
  }

  Widget _unassigned(DebtorsSnapshot data) {
    final unassigned = data.charges
        .where((d) => d.debtorId == null && d.remainingMinor > 0)
        .toList();
    if (data.unassignedLegacyMinor == 0 && unassigned.isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Deudas anteriores por identificar',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (data.unassignedLegacyMinor > 0) ...[
              Text(
                'Cartera de la copia sin asignar: ${_money(data.unassignedLegacyMinor)}',
              ),
              const Text(
                'Para identificar una parte, registra el saldo anterior de la persona y elige Ya incluida en la cartera anterior. Esto no aumenta la deuda total.',
              ),
            ],
            for (final debt in unassigned)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${debt.nameSnapshot} · ${debt.label}'),
                subtitle: Text('Pendiente: ${_money(debt.remainingMinor)}'),
                trailing: TextButton(
                  onPressed: _locked ? null : () => _assign(data, debt),
                  child: const Text('Asignar persona'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _createOrOpening(
    DebtorsSnapshot data, {
    DebtorSummary? person,
  }) async {
    final form = GlobalKey<FormState>(),
        name = TextEditingController(text: person?.name ?? ''),
        initial = TextEditingController(text: '0');
    PreviousDebtSource? source;
    String? error;
    var busy = false;
    try {
      final route = DialogRoute<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialog) => AlertDialog(
            title: Text(
              person == null
                  ? 'Registrar persona'
                  : 'Deuda anterior de ${person.name}',
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Form(
                  key: form,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      TextFormField(
                        key: const Key('debtor-name'),
                        controller: name,
                        enabled: person == null && !busy,
                        maxLength: 120,
                        decoration: const InputDecoration(
                          labelText: 'Nombre de la persona',
                        ),
                        validator: (v) => (v?.trim().isEmpty ?? true)
                            ? 'Escribe un nombre.'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('debtor-initial-amount'),
                        controller: initial,
                        inputFormatters: [const GroupedNumberFormatter()],
                        enabled: !busy,
                        decoration: InputDecoration(
                          labelText: 'Deuda anterior',
                          helperText: person == null
                              ? 'Usa 0 si comienza sin deuda.'
                              : null,
                        ),
                        onChanged: (_) => setDialog(() {}),
                        validator: (v) {
                          final e = inventoryAmountError(v, widget.profile);
                          if (e != null) return e;
                          return person != null && _parse(v!) == 0
                              ? 'Indica un importe positivo.'
                              : null;
                        },
                      ),
                      if (_tryAmount(initial.text) > 0) ...[
                        const SizedBox(height: 16),
                        DropdownButtonFormField<PreviousDebtSource>(
                          key: const Key('debtor-initial-source'),
                          initialValue: source,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Procedencia de esta deuda',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: PreviousDebtSource.includedInLegacy,
                              child: Text('Ya incluida en la cartera anterior'),
                            ),
                            DropdownMenuItem(
                              value: PreviousDebtSource.additional,
                              child: Text('Deuda adicional no registrada'),
                            ),
                          ],
                          onChanged: busy
                              ? null
                              : (v) => setDialog(() => source = v),
                          validator: (v) => v == null
                              ? 'Indica si ya estaba incluida.'
                              : null,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Cartera anterior disponible para asignar: ${_money(data.unassignedLegacyMinor)}',
                        ),
                        Text(
                          source == PreviousDebtSource.additional
                              ? 'Esta opción aumenta la deuda total. No registra ingreso de dinero.'
                              : 'Identifica una parte de la cartera anterior sin volver a sumarla.',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                key: const Key('debtor-create-confirm'),
                onPressed: busy
                    ? null
                    : () async {
                        if (!form.currentState!.validate()) return;
                        setDialog(() {
                          busy = true;
                          error = null;
                        });
                        final command = DebtorCommand(
                          commandId: InventoryIds.next(),
                          kind: person == null ? 'create' : 'opening',
                          name: person == null ? name.text : null,
                          debtorId: person?.id,
                          amountMinor: _parse(initial.text),
                          previousSource: source,
                          occurredAtUtc: DateTime.now().toUtc(),
                        );
                        final ok = await widget.controller.submit(command);
                        if (!dialogContext.mounted) return;
                        if (ok ||
                            widget.controller.uncertain != null ||
                            (widget.controller.snapshot?.pending.any(
                                  (p) =>
                                      p.command.commandId == command.commandId,
                                ) ??
                                false)) {
                          Navigator.pop(dialogContext);
                          await _submitted(ok);
                        } else {
                          setDialog(() {
                            busy = false;
                            error = widget.controller.error;
                          });
                        }
                      },
                child: Text(busy ? 'Guardando…' : 'Guardar'),
              ),
            ],
          ),
        ),
      );
      await Navigator.of(context).push(route);
      await route.completed;
    } finally {
      name.dispose();
      initial.dispose();
    }
  }

  Future<void> _assign(DebtorsSnapshot data, DebtorCharge debt) async {
    String? person;
    final form = GlobalKey<FormState>();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Asignar deuda anterior'),
        content: SizedBox(
          width: 450,
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${debt.nameSnapshot} · ${debt.label} · ${_money(debt.remainingMinor)}',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: const Key('debtor-assignment-person'),
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Persona registrada',
                  ),
                  items: [
                    for (final p in data.debtors)
                      DropdownMenuItem(value: p.id, child: Text(p.name)),
                  ],
                  onChanged: (v) => person = v,
                  validator: (v) =>
                      v == null ? 'Selecciona una persona.' : null,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Se conserva la venta original y no se aumenta la deuda total ni se mueve dinero.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(context, true);
            },
            child: const Text('Asignar'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await _submitted(
        await widget.controller.submit(
          DebtorCommand(
            commandId: InventoryIds.next(),
            kind: 'assign',
            debtorId: person,
            receivableId: debt.receivableId,
            occurredAtUtc: DateTime.now().toUtc(),
          ),
        ),
      );
    }
  }

  Future<void> _availability(DebtorSummary person) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          person.isActive
              ? 'Bloquear fiado a ${person.name}'
              : 'Habilitar fiado a ${person.name}',
        ),
        content: Text(
          person.isActive
              ? 'No podrá recibir nuevas ventas a Deudas. Se conservan su saldo e historial y podrá seguir abonando.'
              : 'Volverá a estar disponible para nuevas ventas a Deudas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.controller.setActive(person.id, !person.isActive);
    }
  }

  Widget _pagination(int length, int page, void Function(int) select) => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      IconButton(
        onPressed: page == 0 ? null : () => select(page - 1),
        icon: const Icon(Icons.chevron_left),
      ),
      Text('${page + 1} / ${(length + 9) ~/ 10}'),
      IconButton(
        onPressed: (page + 1) * 10 >= length ? null : () => select(page + 1),
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );
  int _tryAmount(String v) {
    try {
      return _parse(v);
    } catch (_) {
      return 0;
    }
  }

  String _date(DateTime v) {
    final d = v.toUtc().subtract(const Duration(hours: 5));
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  String _kindLabel(String kind) => switch (kind) {
    'create' => 'Persona',
    'opening' => 'Saldo anterior',
    'payment' => 'Abono',
    _ => 'Asignación',
  };
}
