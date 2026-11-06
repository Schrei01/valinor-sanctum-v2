import 'package:flutter/material.dart';
import '../../../core/domain/money.dart';
import '../../../core/presentation/grouped_number_formatter.dart';
import '../../../core/presentation/financial_total.dart';
import '../../stock_intake/application/stock_intake_controller.dart';
import '../../stock_intake/domain/stock_intake_store.dart';
import '../../stock_intake/domain/purchase_pricing.dart';
import '../../workspace/domain/business_profile.dart';
import '../application/inventory_controller.dart';
import '../domain/inventory_store.dart';
import 'inventory_widgets.dart';
part 'purchase_product_form.dart';

class PurchasesPage extends StatefulWidget {
  const PurchasesPage({
    super.key,
    required this.controller,
    required this.profile,
  });
  final StockIntakeController controller;
  final BusinessProfile profile;
  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchaseFormLine {
  _PurchaseFormLine({this.initial});
  final id = InventoryIds.next();
  final key = GlobalKey<_PurchaseProductFormState>();
  final StockIntakeCommand? initial;
}

class _PurchasesPageState extends State<PurchasesPage> {
  final _header = GlobalKey<FormState>();
  final _paid = TextEditingController();
  final _lines = <_PurchaseFormLine>[_PurchaseFormLine()];
  String? _categoryId, _paymentId, _hydrated, _formError;
  bool _paidManual = false;
  int _confirmed = 0, _version = 0, _historyPage = 0;
  @override
  void initState() {
    super.initState();
    _confirmed = widget.controller.confirmedVersion;
    widget.controller.addListener(_changed);
    _hydrate();
  }

  @override
  void didUpdateWidget(covariant PurchasesPage old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _confirmed = widget.controller.confirmedVersion;
      _hydrated = null;
      _hydrate();
    }
  }

  void _changed() {
    if (!mounted) return;
    if (_confirmed != widget.controller.confirmedVersion) {
      _confirmed = widget.controller.confirmedVersion;
      _lines
        ..clear()
        ..add(_PurchaseFormLine());
      _paid.clear();
      _paidManual = false;
      _hydrated = null;
      _formError = null;
      _historyPage = 0;
      _version++;
    }
    _hydrate();
    setState(() {});
  }

  void _hydrate() {
    final batch = widget.controller.pendingBatches.firstOrNull?.command,
        old = widget.controller.pendingIntakes.firstOrNull?.command;
    final id = batch?.commandId ?? old?.commandId;
    if (id == null || id == _hydrated) return;
    _hydrated = id;
    _categoryId = batch?.categoryId ?? old!.categoryId;
    _paymentId = batch?.paymentOptionId ?? old!.paymentOptionId;
    _paid.text = _amount(batch?.totalPaidMinor ?? old!.totalCostMinor);
    _paidManual = true;
    _lines
      ..clear()
      ..addAll([
        for (final item in batch?.items ?? [old!])
          _PurchaseFormLine(initial: item),
      ]);
    _version++;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _paid.dispose();
    super.dispose();
  }

  String _amount(int value) => Money.fromMinorUnits(
    value,
    currency: widget.profile.currencyCode,
    scale: widget.profile.moneyScale,
  ).formatEsCo();
  int? get _paidValue {
    try {
      return Money.parseEsCo(
        _paid.text,
        currency: widget.profile.currencyCode,
        scale: widget.profile.moneyScale,
      ).minorUnits;
    } catch (_) {
      return null;
    }
  }

  BigInt get _costTotal => _lines.fold(
    BigInt.zero,
    (sum, line) =>
        sum +
        BigInt.from(
          line.key.currentState?.enteredCost ??
              line.initial?.totalCostMinor ??
              0,
        ),
  );
  IntakePaymentOption? _payment(StockIntakeSnapshot data) =>
      data.paymentOptions
          .where((o) => o.id == _paymentId && o.isActive)
          .firstOrNull ??
      data.paymentOptions.where((o) => o.isActive).firstOrNull;
  void _lineChanged() {
    if (!mounted) return;
    setState(() {
      if (!_paidManual && _costTotal <= Money.maxMinorUnits) {
        _paid.text = _costTotal > BigInt.zero
            ? _amount(_costTotal.toInt())
            : '';
      }
      _formError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller, data = c.snapshot, locked = c.formLocked;
    return FocusTraversalGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InventoryPageHeading(
            title: 'Compras',
            subtitle:
                'Registra juntos los productos de una compra y el total que pagaste.',
            busy: c.busy,
            onRefresh: c.load,
          ),
          if (c.loadError != null)
            InventoryNotice(
              text: c.loadError!,
              onRetry: c.busy ? null : c.load,
            ),
          if (c.operationError != null)
            InventoryNotice(text: c.operationError!),
          if (_formError != null) InventoryNotice(text: _formError!),
          if (c.operationNotice != null)
            InventoryNotice(
              key: const Key('intake-notice'),
              text: c.operationNotice!,
              kind: InventoryNoticeKind.information,
            ),
          if (data == null)
            c.loading
                ? const Center(child: CircularProgressIndicator())
                : const Text('Los productos y saldos no están disponibles.')
          else ...[
            if (c.pendingOpening != null) _pendingOpening(data),
            for (final pending in c.pendingBatches)
              _pendingCard(
                pending.command.commandId,
                pending.status,
                pending.rejectionReason,
                '${pending.command.items.length} productos · ${inventoryMoney(pending.command.totalPaidMinor, widget.profile)}',
                batch: true,
              ),
            for (final pending in c.pendingIntakes)
              _pendingCard(
                pending.command.commandId,
                pending.status,
                pending.rejectionReason,
                '${pending.command.productName} · ${pending.command.quantity} unidades',
                batch: false,
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _header,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ingreso de productos',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      _fields([
                        TextFormField(
                          key: const Key('intake-paid'),
                          controller: _paid,
                          inputFormatters: [const GroupedNumberFormatter()],
                          enabled: !locked,
                          decoration: InputDecoration(
                            labelText:
                                'Total pagado (${widget.profile.currencyCode})',
                          ),
                          validator: (value) {
                            final error = inventoryAmountError(
                              value,
                              widget.profile,
                            );
                            return error ??
                                ((_paidValue ?? 0) > 0
                                    ? null
                                    : 'Escribe un total pagado mayor que cero.');
                          },
                          onChanged: (_) => setState(() => _paidManual = true),
                        ),
                        DropdownButtonFormField<String>(
                          key: ValueKey('intake-payment-$_version'),
                          initialValue: _payment(data)?.id,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Pagar desde',
                          ),
                          items: [
                            for (final option in data.paymentOptions.where(
                              (o) => o.isActive,
                            ))
                              DropdownMenuItem(
                                value: option.id,
                                child: Text(option.label),
                              ),
                          ],
                          onChanged: locked
                              ? null
                              : (value) => setState(() => _paymentId = value),
                          validator: (value) =>
                              value == null ? 'Elige una cuenta.' : null,
                        ),
                      ]),
                      const SizedBox(height: 12),
                      Text(
                        '${_payment(data)?.isInvestment == true ? 'Inversión por recuperar' : 'Saldo disponible'}: ${inventoryMoney(_payment(data)?.balanceMinor ?? 0, widget.profile)}',
                        key: const Key('intake-balance'),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        key: ValueKey('intake-category-$_version'),
                        initialValue: _categoryId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Categoría de la compra',
                          helperText:
                              'Todos los productos deben tener esta categoría.',
                        ),
                        items: [
                          for (final category in data.categories.where(
                            (cat) =>
                                cat.isActive &&
                                cat.name.trim().toLowerCase() != 'evento',
                          ))
                            DropdownMenuItem(
                              value: category.id,
                              child: Text(category.name),
                            ),
                        ],
                        onChanged: locked
                            ? null
                            : (value) => setState(() {
                                if (_lines.any(
                                  (line) =>
                                      line.key.currentState?.existingCategory !=
                                          null &&
                                      line.key.currentState!.existingCategory !=
                                          value,
                                )) {
                                  _formError =
                                      'Retira los productos de otra categoría antes de cambiar la categoría de la compra.';
                                  _version++;
                                } else {
                                  _categoryId = value;
                                  _formError = null;
                                }
                              }),
                        validator: (value) =>
                            data.categories.any(
                              (cat) =>
                                  cat.id == value &&
                                  cat.isActive &&
                                  cat.name.trim().toLowerCase() != 'evento',
                            )
                            ? null
                            : 'Elige una categoría activa.',
                      ),
                    ],
                  ),
                ),
              ),
            ),
            for (var index = 0; index < _lines.length; index++)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Producto ${index + 1}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          if (_lines.length > 1)
                            IconButton(
                              key: Key('intake-remove-${_lines[index].id}'),
                              tooltip: 'Quitar producto',
                              onPressed: locked
                                  ? null
                                  : () => setState(() {
                                      _lines.removeAt(index);
                                      _lineChanged();
                                    }),
                              icon: const Icon(Icons.close),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _PurchaseProductForm(
                        key: _lines[index].key,
                        id: _lines[index].id,
                        first: index == 0,
                        data: data,
                        profile: widget.profile,
                        locked: locked,
                        categoryId: _categoryId,
                        onChanged: _lineChanged,
                        onCategorySelected: (category) => setState(() {
                          _categoryId = category;
                          _version++;
                        }),
                        initial: _lines[index].initial,
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('intake-add-product'),
              onPressed: locked || _lines.length >= 100
                  ? null
                  : () => setState(() => _lines.add(_PurchaseFormLine())),
              icon: const Icon(Icons.add),
              label: const Text('Agregar producto'),
            ),
            const SizedBox(height: 16),
            _fields([
              FinancialTotal(
                label: 'Costo de los productos',
                value: _costTotal > Money.maxMinorUnits
                    ? 'Supera el límite permitido'
                    : inventoryMoney(_costTotal.toInt(), widget.profile),
                valueKey: const Key('intake-products-total'),
              ),
              FinancialTotal(
                label: 'Total pagado',
                value: _paidValue == null
                    ? 'Completa el total pagado'
                    : inventoryMoney(_paidValue!, widget.profile),
                valueKey: const Key('intake-total'),
              ),
            ]),
            const SizedBox(height: 8),
            Text(
              'Diferencia (pagado − costos): ${_paidValue == null || _costTotal > Money.maxMinorUnits ? '—' : inventoryMoney(_paidValue! - _costTotal.toInt(), widget.profile)}',
              key: const Key('intake-difference'),
            ),
            if (_payment(data)?.isInvestment != true &&
                (_paidValue ?? 0) > (_payment(data)?.balanceMinor ?? 0))
              const Text(
                'El saldo no alcanza para pagar esta compra.',
                key: Key('intake-insufficient'),
              ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  key: const Key('intake-submit'),
                  onPressed: locked || c.loadError != null ? null : _receive,
                  icon: Icon(
                    c.confirming
                        ? Icons.hourglass_empty
                        : Icons.inventory_2_outlined,
                  ),
                  label: Text(
                    c.confirming ? 'Guardando compra…' : 'Registrar compra',
                  ),
                ),
                if (data.paymentOptions.any(
                  (o) => o.isActive && o.canRecordOpening,
                ))
                  OutlinedButton.icon(
                    key: const Key('intake-opening'),
                    onPressed: locked
                        ? null
                        : () => showDialog<void>(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => _OpeningDialog(
                              controller: c,
                              profile: widget.profile,
                              options: data.paymentOptions
                                  .where(
                                    (o) => o.isActive && o.canRecordOpening,
                                  )
                                  .toList(),
                              selected: _payment(data)?.id,
                            ),
                          ),
                    icon: const Icon(Icons.account_balance_wallet_outlined),
                    label: const Text('Saldo inicial'),
                  ),
              ],
            ),
            const SizedBox(height: 32),
            Text(
              'Historial de ingresos',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _history(data),
          ],
        ],
      ),
    );
  }

  Widget _fields(List<Widget> fields) => LayoutBuilder(
    builder: (context, box) => Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        for (final field in fields)
          SizedBox(
            width: box.maxWidth >= 580 ? (box.maxWidth - 16) / 2 : box.maxWidth,
            child: field,
          ),
      ],
    ),
  );
  Future<void> _receive() async {
    var valid = _header.currentState!.validate();
    final payment = _payment(widget.controller.snapshot!);
    if (_categoryId == null || payment == null) return;
    final at = DateTime.now().toUtc(), items = <StockIntakeCommand>[];
    for (final line in _lines) {
      final item = line.key.currentState?.command(
        category: _categoryId!,
        payment: payment.id,
        at: at,
      );
      if (item == null) {
        valid = false;
      } else {
        items.add(item);
      }
    }
    if (!valid) return;
    setState(() => _formError = null);
    await widget.controller.receiveBatch(
      PurchaseBatchCommand(
        commandId: InventoryIds.next(),
        categoryId: _categoryId!,
        paymentOptionId: payment.id,
        totalPaidMinor: _paidValue!,
        occurredAtUtc: at,
        items: items,
      ),
    );
  }

  Widget _pendingOpening(StockIntakeSnapshot data) {
    final opening = widget.controller.pendingOpening!;
    final option = data.paymentOptions
        .where((item) => item.id == opening.paymentOptionId)
        .firstOrNull;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Saldo inicial pendiente: ${option?.label ?? 'Cuenta guardada'} · ${inventoryMoney(opening.amountMinor, widget.profile)}',
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('intake-retry-opening'),
              onPressed: widget.controller.busy
                  ? null
                  : widget.controller.retryOpening,
              child: const Text('Reintentar saldo inicial'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pendingCard(
    String id,
    String status,
    String? reason,
    String description, {
    required bool batch,
  }) => Card(
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            status == 'rejected'
                ? 'Ingreso por corregir'
                : 'Ingreso pendiente de confirmar',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(description),
          if (reason != null) Text(reason),
          const SizedBox(height: 12),
          FilledButton(
            key: ValueKey('intake-retry-$id'),
            onPressed: widget.controller.busy
                ? null
                : () => batch
                      ? (status == 'rejected'
                            ? widget.controller.discardBatch(id)
                            : widget.controller.retryBatch(id))
                      : (status == 'rejected'
                            ? widget.controller.discardRejected(id)
                            : widget.controller.retry(id)),
            child: Text(
              status == 'rejected'
                  ? 'Corregir ingreso'
                  : 'Reintentar el mismo ingreso',
            ),
          ),
        ],
      ),
    ),
  );
  Widget _history(StockIntakeSnapshot data) {
    final cards = <({DateTime at, Widget Function() build})>[
      for (final entry in data.batches)
        (
          at: entry.command.occurredAtUtc,
          build: () => Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${entry.command.items.length} productos · ${entry.categoryName} · Pagada · ${entry.paymentLabel}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  FinancialTotal(
                    label: 'Total pagado',
                    value: inventoryMoney(
                      entry.command.totalPaidMinor,
                      widget.profile,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Costo de los productos: ${inventoryMoney(entry.command.itemsTotalMinor, widget.profile)} · Diferencia: ${inventoryMoney(entry.command.differenceMinor, widget.profile)}',
                  ),
                  for (final item in entry.command.items)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        '${item.productName} · ${item.quantity} unidades\n${item.supplierName} · Costo total: ${inventoryMoney(item.totalCostMinor, widget.profile)} · PVP unitario: ${inventoryMoney(item.listPriceMinor, widget.profile)}',
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Ingreso: ${InventoryController.isoDate(entry.command.occurredAtUtc.subtract(const Duration(hours: 5)))}',
                  ),
                ],
              ),
            ),
          ),
        ),
      for (final entry in data.entries)
        (
          at: entry.occurredAtUtc,
          build: () => Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${entry.productName} · ${entry.quantity} unidades',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Chip(label: Text('Pagada · ${entry.paymentLabel}')),
                  Text(
                    '${entry.supplierName} · ${entry.categoryName}${entry.sku == null ? '' : ' · ${entry.sku}'}',
                  ),
                  Text(
                    'Costo total: ${inventoryMoney(entry.totalCostMinor, widget.profile)} · PVP unitario: ${inventoryMoney(entry.listPriceMinor, widget.profile)}',
                  ),
                  Text(
                    'Ingreso: ${InventoryController.isoDate(entry.occurredAtUtc.subtract(const Duration(hours: 5)))}',
                  ),
                ],
              ),
            ),
          ),
        ),
    ]..sort((a, b) => b.at.compareTo(a.at));
    if (cards.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Aún no hay ingresos de productos.'),
        ),
      );
    }
    final page = _historyPage.clamp(0, (cards.length - 1) ~/ 10);
    return Column(
      children: [
        for (final entry in cards.skip(page * 10).take(10)) entry.build(),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              '${page * 10 + 1}–${(page * 10 + 10).clamp(0, cards.length)} de ${cards.length}',
            ),
            IconButton(
              tooltip: 'Ingresos anteriores',
              onPressed: page == 0
                  ? null
                  : () => setState(() => _historyPage = page - 1),
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: 'Ingresos siguientes',
              onPressed: (page + 1) * 10 >= cards.length
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

class _OpeningDialog extends StatefulWidget {
  const _OpeningDialog({
    required this.controller,
    required this.profile,
    required this.options,
    this.selected,
  });
  final StockIntakeController controller;
  final BusinessProfile profile;
  final List<IntakePaymentOption> options;
  final String? selected;
  @override
  State<_OpeningDialog> createState() => _OpeningDialogState();
}

class _OpeningDialogState extends State<_OpeningDialog> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  late String? _selected =
      widget.options.any((item) => item.id == widget.selected)
      ? widget.selected
      : widget.options.firstOrNull?.id;
  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => AlertDialog(
      title: const Text('Declarar saldo inicial'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Escribe el dinero real que tenías en esta cuenta antes de empezar a registrar movimientos. Se permite una sola vez por cuenta y antes de su primer movimiento.',
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  key: const Key('opening-account'),
                  initialValue: _selected,
                  decoration: const InputDecoration(labelText: 'Cuenta'),
                  isExpanded: true,
                  items: [
                    for (final option in widget.options)
                      DropdownMenuItem(
                        value: option.id,
                        child: Text(option.label),
                      ),
                  ],
                  onChanged:
                      widget.controller.busy ||
                          widget.controller.pendingOpening != null
                      ? null
                      : (value) => setState(() => _selected = value),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('opening-amount'),
                  controller: _amount,
                  inputFormatters: [const GroupedNumberFormatter()],
                  enabled:
                      !widget.controller.busy &&
                      widget.controller.pendingOpening == null,
                  decoration: InputDecoration(
                    labelText: 'Saldo inicial (${widget.profile.currencyCode})',
                  ),
                  validator: (value) {
                    final error = inventoryAmountError(value, widget.profile);
                    if (error != null) return error;
                    return Money.parseEsCo(
                              value!,
                              currency: widget.profile.currencyCode,
                              scale: widget.profile.moneyScale,
                            ).minorUnits >
                            0
                        ? null
                        : 'Escribe un saldo positivo.';
                  },
                ),
                if (widget.controller.operationError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      widget.controller.operationError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: widget.controller.busy
              ? null
              : () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
        FilledButton(
          key: const Key('opening-save'),
          onPressed: widget.controller.busy
              ? null
              : () async {
                  bool saved;
                  if (widget.controller.pendingOpening != null) {
                    saved = await widget.controller.retryOpening();
                  } else {
                    if (!_form.currentState!.validate() || _selected == null) {
                      return;
                    }
                    saved = await widget.controller.recordOpening(
                      paymentOptionId: _selected!,
                      amountMinor: Money.parseEsCo(
                        _amount.text,
                        currency: widget.profile.currencyCode,
                        scale: widget.profile.moneyScale,
                      ).minorUnits,
                    );
                  }
                  if (saved && context.mounted) Navigator.pop(context);
                },
          child: Text(
            widget.controller.savingOpening
                ? 'Guardando…'
                : widget.controller.pendingOpening != null
                ? 'Reintentar el mismo saldo'
                : 'Guardar saldo inicial',
          ),
        ),
      ],
    ),
  );
}
