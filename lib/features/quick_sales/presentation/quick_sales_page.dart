import '../../../core/presentation/grouped_number_formatter.dart';
import 'package:flutter/material.dart';
import '../../debtors/domain/debtors_store.dart';
import '../../../core/presentation/financial_total.dart';

import '../../inventory/domain/inventory_store.dart';
import '../../inventory/presentation/inventory_widgets.dart';
import '../../workspace/domain/business_profile.dart';
import '../application/quick_sales_controller.dart';
import '../domain/quick_sales_store.dart';
import 'split_payment_dialog.dart';

class QuickSalesPage extends StatelessWidget {
  const QuickSalesPage({
    super.key,
    required this.controller,
    required this.profile,
  });
  final QuickSalesController controller;
  final BusinessProfile profile;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final data = controller.snapshot;
      return FocusTraversalGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 20,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Ventas',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                FilledButton.icon(
                  key: const Key('quick-new-account'),
                  onPressed: data == null ? null : controller.addAccount,
                  icon: const Icon(Icons.add),
                  label: const Text('Nueva cuenta'),
                ),
                IconButton(
                  key: const Key('quick-refresh'),
                  onPressed: controller.loading ? null : controller.load,
                  tooltip: 'Actualizar productos y cuentas',
                  icon: controller.loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Abre cuentas, agrega productos y elige cómo pagar cada cuenta.',
            ),
            const SizedBox(height: 18),
            if (controller.loadError != null)
              InventoryNotice(
                text: controller.loadError!,
                onRetry: controller.loading ? null : controller.load,
              ),
            if (controller.notice != null)
              InventoryNotice(
                key: const Key('quick-notice'),
                text: controller.notice!,
                kind: InventoryNoticeKind.information,
              ),
            if (data == null)
              if (controller.loading)
                const Center(child: CircularProgressIndicator())
              else
                const Text('No se pudieron cargar las ventas.')
            else ...[
              if (data.availableProducts.isEmpty)
                const InventoryNotice(
                  text:
                      'No hay productos disponibles. Ingresa o repón mercancía desde Compras.',
                ),
              if (controller.accounts.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: InventoryNotice.informationBackground,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Todo listo. Pulsa Nueva cuenta para atender una venta.',
                    style: TextStyle(
                      color: InventoryNotice.informationForeground,
                    ),
                  ),
                ),
              for (final account in controller.accounts)
                Padding(
                  key: ValueKey('quick-account-position-${account.id}'),
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _QuickAccountCard(
                    key: ValueKey(
                      'quick-card-${account.id}-${controller.editorEpochFor(account.id)}',
                    ),
                    account: account,
                    controller: controller,
                    profile: profile,
                    data: data,
                  ),
                ),
              if (data.sales.isNotEmpty) ...[
                const SizedBox(height: 10),
                ExpansionTile(
                  key: const Key('quick-history'),
                  tilePadding: EdgeInsets.zero,
                  title: Text('Últimas ventas (${data.sales.length})'),
                  children: [
                    for (final sale in data.sales.take(10))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(sale.label),
                        subtitle: Text(
                          [
                            if (sale.result.creditMinor > 0)
                              'Cliente: ${sale.result.customerName} · Deudas: ${inventoryMoney(sale.result.creditMinor, profile)}',
                            ...sale.lines.map(
                              (line) =>
                                  '${line.quantity} × ${line.productName} · ${line.paymentBreakdown.isEmpty ? line.displayPaymentLabel : line.paymentBreakdown.entries.map((p) => "${p.key == 'Nequi' ? 'Transferencia' : p.key} ${inventoryMoney(p.value, profile)}").join(' · ')}',
                            ),
                          ].join('\n'),
                        ),
                        trailing: Text(
                          inventoryMoney(sale.result.totalMinor, profile),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ],
        ),
      );
    },
  );
}

class _QuickAccountCard extends StatefulWidget {
  const _QuickAccountCard({
    super.key,
    required this.account,
    required this.controller,
    required this.profile,
    required this.data,
  });
  final QuickSaleAccount account;
  final QuickSalesController controller;
  final BusinessProfile profile;
  final QuickSalesSnapshot data;

  @override
  State<_QuickAccountCard> createState() => _QuickAccountCardState();
}

class _QuickAccountCardState extends State<_QuickAccountCard> {
  late final _label = TextEditingController(text: widget.account.label);
  final _labelFocus = FocusNode();

  @override
  void didUpdateWidget(covariant _QuickAccountCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_labelFocus.hasFocus && _label.text != widget.account.label) {
      _label.text = widget.account.label;
    }
  }

  @override
  void dispose() {
    _label.dispose();
    _labelFocus.dispose();
    super.dispose();
  }

  Future<void> _remove() async {
    final account = widget.account;
    final hasData =
        account.lines.any(
          (line) => line.productId != null || line.quantityText != '1',
        ) ||
        !RegExp(r'^Cuenta \d+$').hasMatch(account.label) ||
        account.customerName.trim().isNotEmpty;
    if (hasData) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('¿Quitar esta cuenta?'),
          content: Text(
            'Se descartarán las líneas de ${account.label}. Todavía no se ha registrado una venta.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Volver'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Quitar cuenta'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
    }
    await widget.controller.removeAccount(account.id);
  }

  Future<void> _recoverSaved() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Recuperar la cuenta guardada?'),
        content: const Text(
          'Se descartarán los cambios locales de esta cuenta y se recuperará su última versión guardada. Las otras cuentas se conservan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Recuperar cuenta'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) {
      await widget.controller.recoverSavedAccount(widget.account.id);
    }
  }

  String _money(BigInt amount) =>
      amount.isNegative || amount > BigInt.from(0x7fffffffffffffff)
      ? 'Revisa cantidades'
      : inventoryMoney(amount.toInt(), widget.profile);

  void _choosePerson(DebtorSummary person) {
    _label.value = TextEditingValue(
      text: person.name,
      selection: TextSelection.collapsed(offset: person.name.length),
    );
    widget.controller.selectDebtor(widget.account.id, person.id);
    _labelFocus.unfocus();
  }

  String? _personHint(bool hasCredit) {
    final account = widget.account;
    final people = widget.data.debtors.where((p) => p.isActive).toList();
    final selected = widget.data.debtors
        .where((p) => p.id == account.debtorId)
        .firstOrNull;
    final linked = account.debtorId != null;
    return linked
        ? selected == null || !selected.isActive
              ? '${account.customerName} · Fiado bloqueado'
              : 'Titular: ${selected.name} · Debe ${inventoryMoney(selected.balanceMinor, widget.profile)}'
        : hasCredit
        ? people.isEmpty
              ? 'Primero registra una persona en Deudores.'
              : 'Selecciona una persona de Deudores para asignarle lo fiado.'
        : null;
  }

  Widget _accountField(bool locked) {
    final account = widget.account;
    final people = widget.data.debtors.where((p) => p.isActive).toList();
    return LayoutBuilder(
      builder: (context, constraints) => RawAutocomplete<DebtorSummary>(
        textEditingController: _label,
        focusNode: _labelFocus,
        displayStringForOption: (p) => p.name,
        optionsBuilder: (query) {
          if (locked) return const Iterable<DebtorSummary>.empty();
          final value = query.text.trim().toLowerCase();
          return people.where(
            (p) => value.isEmpty || p.name.toLowerCase().contains(value),
          );
        },
        onSelected: _choosePerson,
        fieldViewBuilder: (context, text, focus, submit) => TextField(
          key: ValueKey('quick-label-${account.id}'),
          controller: text,
          focusNode: focus,
          enabled: !locked,
          maxLength: 120,
          decoration: InputDecoration(
            labelText: 'Cuenta',
            hintText: 'Nombre de cuenta o persona',
            counterText: '',
            isDense: true,
            suffixIcon: PopupMenuButton<String>(
              key: ValueKey('quick-person-picker-${account.id}'),
              tooltip: 'Elegir persona de Deudores',
              enabled: !locked && people.isNotEmpty,
              icon: const Icon(Icons.person_search_outlined),
              constraints: BoxConstraints(
                maxHeight: 320,
                maxWidth: constraints.maxWidth.clamp(160.0, 380.0).toDouble(),
              ),
              onSelected: (id) =>
                  _choosePerson(people.singleWhere((p) => p.id == id)),
              itemBuilder: (context) => [
                for (final p in people)
                  PopupMenuItem(
                    value: p.id,
                    height: 60,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Debe ${inventoryMoney(p.balanceMinor, widget.profile)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          onChanged: (value) => widget.controller.rename(account.id, value),
          onEditingComplete: () {},
          onSubmitted: (_) => submit(),
        ),
        optionsViewBuilder: (context, select, options) {
          final rows = options.toList();
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 5,
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: constraints.maxWidth,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: rows.length,
                    itemBuilder: (context, i) => ListTile(
                      dense: true,
                      selected: AutocompleteHighlightedOption.of(context) == i,
                      title: Text(rows[i].name),
                      subtitle: Text(
                        'Debe ${inventoryMoney(rows[i].balanceMinor, widget.profile)}',
                      ),
                      onTap: () => select(rows[i]),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    final controller = widget.controller;
    final locked = controller.isLocked(account.id);
    final pending = controller.pendingFor(account.id);
    final error = controller.errorFor(account.id);
    final total = controller.totalFor(account);
    final hasCredit = controller.hasCreditFor(account);
    final credit = controller.creditTotalFor(account);
    final isSplit = account.isPaymentSplit;
    final personHint = _personHint(hasCredit);
    final debtBlocked =
        hasCredit &&
        !widget.data.debtors.any((p) => p.id == account.debtorId && p.isActive);
    final singlePayment = account.singlePaymentOptionId;
    final paymentOptions = widget.data.paymentOptions
        .where((p) => p.isActive || p.id == singlePayment)
        .toList();
    final groups = <String, BigInt>{};
    for (final line in account.lines) {
      if (line.isSplit) {
        for (final part in line.paymentParts) {
          final option = widget.data.paymentOptions
              .where((p) => p.id == part.paymentOptionId)
              .firstOrNull;
          if (option != null) {
            groups.update(
              option.displayLabel,
              (v) => v + BigInt.from(part.amountMinor),
              ifAbsent: () => BigInt.from(part.amountMinor),
            );
          }
        }
        continue;
      }
      final option = widget.data.paymentOptions
          .where((item) => item.id == line.paymentOptionId)
          .firstOrNull;
      if (option == null || line.productId == null) continue;
      final amount =
          BigInt.from(line.unitPriceMinor ?? 0) *
          BigInt.from(int.tryParse(line.quantityText) ?? 0);
      groups.update(
        option.displayLabel,
        (current) => current + amount,
        ifAbsent: () => amount,
      );
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _accountField(locked)),
                const SizedBox(width: 12),
                Tooltip(
                  message: controller.isSaving(account.id)
                      ? 'Guardando cambios'
                      : controller.isDirty(account.id)
                      ? 'Cambios pendientes de guardar'
                      : 'Cuenta guardada',
                  child: Icon(
                    controller.isSaving(account.id) ||
                            controller.isDirty(account.id)
                        ? Icons.sync
                        : Icons.check_circle_outline,
                    size: 18,
                    color: const Color(0xFF65716A),
                  ),
                ),
                if (MediaQuery.sizeOf(context).width >= 600) ...[
                  const SizedBox(width: 6),
                  Text(
                    controller.isSaving(account.id)
                        ? 'Guardando…'
                        : controller.isDirty(account.id)
                        ? 'Pendiente'
                        : 'Guardada',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                IconButton(
                  key: ValueKey('quick-remove-account-${account.id}'),
                  tooltip: 'Quitar cuenta',
                  onPressed: locked ? null : _remove,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (final line in account.lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _QuickLineEditor(
                  key: ValueKey('quick-line-${line.id}'),
                  account: account,
                  line: line,
                  data: widget.data,
                  profile: widget.profile,
                  locked: locked,
                  onChanged: (value) => controller.editLine(account.id, value),
                  onRemove: () => controller.removeLine(account.id, line.id),
                ),
              ),
            if (!locked)
              TextButton.icon(
                key: ValueKey('quick-add-line-${account.id}'),
                onPressed: () => controller.addLine(account.id),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Agregar venta'),
              ),
            if (error != null) ...[
              const SizedBox(height: 8),
              InventoryNotice(text: error),
            ],
            if (pending != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  pending.status == 'rejected'
                      ? 'Venta rechazada. Corrige esta cuenta y vuelve a registrarla.'
                      : 'Esta venta espera confirmación. Reintenta para recuperar su resultado sin duplicarla.',
                ),
              ),
            const Divider(),
            if (account.needsPaymentReview)
              const InventoryNotice(
                text:
                    'El consumo cambió. Revisa y guarda de nuevo la división antes de registrar.',
              ),
            Wrap(
              spacing: 20,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 240,
                  child: FinancialTotal(
                    label: 'Total',
                    value: _money(total),
                    valueKey: ValueKey('quick-total-${account.id}'),
                  ),
                ),
                SizedBox(
                  width: 240,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('quick-account-payment-${account.id}'),
                    initialValue: isSplit
                        ? '__account_split__'
                        : paymentOptions.any((p) => p.id == singlePayment)
                        ? singlePayment
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Forma de pago',
                      isDense: true,
                    ),
                    hint: const Text('Selecciona un medio'),
                    items: isSplit
                        ? const [
                            DropdownMenuItem(
                              value: '__account_split__',
                              child: Text('Pago dividido'),
                            ),
                          ]
                        : [
                            for (final option in paymentOptions)
                              DropdownMenuItem(
                                value: option.id,
                                child: Text(
                                  option.isActive
                                      ? option.displayLabel
                                      : '${option.displayLabel} (inactivo)',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                    onChanged: locked || isSplit
                        ? null
                        : (value) => controller.selectAccountPayment(
                            account.id,
                            value,
                          ),
                  ),
                ),
                if (pending == null)
                  SizedBox(
                    width: 180,
                    child: OutlinedButton.icon(
                      key: ValueKey('quick-split-account-${account.id}'),
                      icon: const Icon(Icons.call_split, size: 18),
                      label: Text(
                        isSplit ? 'Editar división' : 'Dividir cuenta',
                      ),
                      onPressed:
                          locked ||
                              controller.loadError != null ||
                              total <= BigInt.zero ||
                              total > BigInt.from(0x7fffffffffffffff)
                          ? null
                          : () async {
                              final result =
                                  await showDialog<SplitPaymentSelection>(
                                    context: context,
                                    builder: (_) => SplitPaymentDialog(
                                      account: account,
                                      data: widget.data,
                                      profile: widget.profile,
                                    ),
                                  );
                              if (!mounted || result == null) return;
                              controller.divideAccount(
                                account.id,
                                result.parts,
                              );
                            },
                    ),
                  ),
                if (pending == null)
                  FilledButton.icon(
                    key: ValueKey('quick-register-${account.id}'),
                    onPressed:
                        locked ||
                            controller.loadError != null ||
                            account.needsPaymentReview ||
                            (account.paymentMode == 'single' &&
                                singlePayment == null)
                        ? null
                        : () => controller.register(account.id),
                    icon: const Icon(Icons.point_of_sale, size: 20),
                    label: Text(
                      controller.isActing(account.id)
                          ? 'Registrando…'
                          : 'Registrar venta',
                    ),
                  )
                else if (pending.status == 'rejected')
                  OutlinedButton(
                    key: ValueKey('quick-unlock-${account.id}'),
                    onPressed: controller.isActing(account.id)
                        ? null
                        : () => controller.unlockRejected(account.id),
                    child: const Text('Corregir cuenta'),
                  )
                else
                  FilledButton.icon(
                    key: ValueKey('quick-retry-${account.id}'),
                    onPressed: controller.isActing(account.id)
                        ? null
                        : () => controller.retry(account.id),
                    icon: const Icon(Icons.refresh),
                    label: Text(
                      controller.isActing(account.id)
                          ? 'Recuperando…'
                          : 'Reintentar venta',
                    ),
                  ),
                if (error != null &&
                    pending == null &&
                    controller.isDirty(account.id))
                  TextButton(
                    onPressed: locked
                        ? null
                        : () => controller.flush(account.id),
                    child: const Text('Reintentar guardado'),
                  ),
                if (controller.canRecoverSaved(account.id))
                  TextButton(
                    key: ValueKey('quick-recover-saved-${account.id}'),
                    onPressed: locked ? null : _recoverSaved,
                    child: const Text('Recuperar cuenta guardada'),
                  ),
              ],
            ),
            if (debtBlocked && personHint != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: InventoryNotice(text: personHint),
              ),
            if ((personHint != null && !debtBlocked) ||
                (hasCredit && !account.needsPaymentReview) ||
                (groups.length > 1 && !account.needsPaymentReview) ||
                (isSplit && pending == null))
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: InventoryNotice.content(
                  key: ValueKey('quick-payment-details-${account.id}'),
                  content: Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (personHint != null && !debtBlocked) Text(personHint),
                      if (hasCredit && !account.needsPaymentReview)
                        Text(
                          'Cobrado: ${_money(total - credit)} · Deudas: ${_money(credit)}',
                          key: ValueKey('quick-credit-summary-${account.id}'),
                        ),
                      if (groups.length > 1 && !account.needsPaymentReview)
                        Text(
                          groups.entries
                              .map(
                                (part) => '${part.key}: ${_money(part.value)}',
                              )
                              .join(' · '),
                        ),
                      if (isSplit && pending == null)
                        TextButton(
                          key: ValueKey('quick-single-payment-${account.id}'),
                          onPressed: locked
                              ? null
                              : () => controller.returnToSinglePayment(
                                  account.id,
                                ),
                          child: const Text('Volver a pago único'),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _QuickLineEditor extends StatefulWidget {
  const _QuickLineEditor({
    super.key,
    required this.account,
    required this.line,
    required this.data,
    required this.profile,
    required this.locked,
    required this.onChanged,
    required this.onRemove,
  });
  final QuickSaleAccount account;
  final QuickSaleLine line;
  final QuickSalesSnapshot data;
  final BusinessProfile profile;
  final bool locked;
  final ValueChanged<QuickSaleLine> onChanged;
  final VoidCallback onRemove;
  @override
  State<_QuickLineEditor> createState() => _QuickLineEditorState();
}

class _QuickLineEditorState extends State<_QuickLineEditor> {
  late final _product = TextEditingController(
    text: _productFor(widget.line.productId)?.name ?? '',
  );
  late final _quantity = TextEditingController(
    text: GroupedNumberFormatter.format(widget.line.quantityText),
  );
  final _productFocus = FocusNode();
  final _quantityFocus = FocusNode();

  CatalogProduct? _productFor(String? id) =>
      widget.data.products.where((item) => item.id == id).firstOrNull;

  @override
  void didUpdateWidget(covariant _QuickLineEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.line.productId != oldWidget.line.productId &&
        widget.line.productId != null) {
      _product.text = _productFor(widget.line.productId)?.name ?? '';
    }
    if (!_quantityFocus.hasFocus &&
        _quantity.text !=
            GroupedNumberFormatter.format(widget.line.quantityText)) {
      _quantity.text = GroupedNumberFormatter.format(widget.line.quantityText);
    }
  }

  @override
  void dispose() {
    _product.dispose();
    _quantity.dispose();
    _productFocus.dispose();
    _quantityFocus.dispose();
    super.dispose();
  }

  void _productChanged(String query) {
    final selected = _productFor(widget.line.productId);
    if (selected != null && query != selected.name) {
      widget.onChanged(
        QuickSaleLine(
          id: widget.line.id,
          quantityText: widget.line.quantityText,
          paymentOptionId: widget.line.paymentOptionId,
          paymentParts: widget.line.paymentParts,
        ),
      );
    }
  }

  void _selected(CatalogProduct candidate) {
    final product = widget.data.availableProducts
        .where((p) => p.id == candidate.id)
        .firstOrNull;
    if (widget.locked || product == null) return;
    final priorPrice = widget.account.lines
        .where(
          (line) => line.id != widget.line.id && line.productId == product.id,
        )
        .firstOrNull
        ?.unitPriceMinor;
    widget.onChanged(
      QuickSaleLine(
        id: widget.line.id,
        productId: product.id,
        quantityText: widget.line.quantityText,
        unitPriceMinor: priorPrice ?? product.listPriceMinor,
        paymentOptionId: widget.line.paymentOptionId,
        paymentParts: widget.line.paymentParts,
      ),
    );
    _quantityFocus.requestFocus();
    _quantity.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _quantity.text.length,
    );
  }

  String _availability(CatalogProduct product) => product.isUnlimited
      ? 'Ilimitado'
      : 'Unidades: ${GroupedNumberFormatter.format('${widget.data.stockQuantityFor(product.id)}')}';

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    final selected = _productFor(line.productId);
    final stock = widget.data.stockQuantityFor(line.productId ?? '');
    final productField = RawAutocomplete<CatalogProduct>(
      textEditingController: _product,
      focusNode: _productFocus,
      displayStringForOption: (item) => item.name,
      optionsBuilder: (query) {
        if (widget.locked) return const Iterable<CatalogProduct>.empty();
        final value = query.text.trim().toLowerCase();
        return widget.data.availableProducts.where(
          (item) =>
              value.isEmpty ||
              item.name.toLowerCase().contains(value) ||
              (item.sku?.toLowerCase().contains(value) ?? false),
        );
      },
      onSelected: _selected,
      fieldViewBuilder: (context, textController, focusNode, submit) => TextField(
        key: ValueKey('quick-product-${line.id}'),
        controller: textController,
        focusNode: focusNode,
        enabled: !widget.locked,
        decoration: InputDecoration(
          labelText: 'Producto',
          hintText: 'Busca por nombre o código',
          isDense: true,
          helperText: selected == null
              ? 'Selecciona un producto'
              : 'Precio ${inventoryMoney(line.unitPriceMinor ?? 0, widget.profile)} · ${selected.isUnlimited ? 'Disponibilidad ilimitada' : 'Stock ${GroupedNumberFormatter.format('$stock')}'}',
        ),
        onChanged: _productChanged,
        textInputAction: TextInputAction.done,
        onEditingComplete: () {},
        onSubmitted: (_) => submit(),
      ),
      optionsViewBuilder: (context, select, options) {
        final available = {
          for (final p in widget.data.availableProducts) p.id: p,
        };
        final rows = options
            .map((p) => available[p.id])
            .whereType<CatalogProduct>()
            .toList();
        if (rows.isEmpty) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 5,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: 240,
                maxWidth: MediaQuery.sizeOf(context).width < 500 ? 285 : 420,
              ),
              child: ListView.builder(
                key: ValueKey('quick-options-${line.id}'),
                padding: const EdgeInsets.symmetric(vertical: 6),
                shrinkWrap: true,
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final product = rows[index];
                  return ListTile(
                    dense: true,
                    title: Text(product.name),
                    subtitle: Text(
                      '${product.sku == null ? '' : '${product.sku} · '}${_availability(product)}',
                    ),
                    trailing: Text(
                      inventoryMoney(product.listPriceMinor, widget.profile),
                    ),
                    onTap: () => select(product),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
    final quantityField = TextField(
      key: ValueKey('quick-quantity-${line.id}'),
      controller: _quantity,
      focusNode: _quantityFocus,
      enabled: !widget.locked,
      keyboardType: TextInputType.number,
      inputFormatters: [
        const GroupedNumberFormatter(integerOnly: true, maxDigits: 10),
      ],
      decoration: const InputDecoration(
        labelText: 'Cant.',
        isDense: true,
        helperText: ' ',
      ),
      textInputAction: TextInputAction.next,
      onChanged: (value) => widget.onChanged(
        QuickSaleLine(
          id: line.id,
          productId: line.productId,
          quantityText: value.replaceAll('.', ''),
          unitPriceMinor: line.unitPriceMinor,
          paymentOptionId: line.paymentOptionId,
          paymentParts: line.paymentParts,
        ),
      ),
    );
    final amount =
        BigInt.from(line.unitPriceMinor ?? 0) *
        BigInt.from(int.tryParse(line.quantityText) ?? 0);
    final subtotal = Text(
      amount > BigInt.from(0x7fffffffffffffff)
          ? 'Revisa cantidad'
          : inventoryMoney(amount.toInt(), widget.profile),
      key: ValueKey('quick-line-total-${line.id}'),
      style: const TextStyle(fontWeight: FontWeight.w600),
    );
    final remove = IconButton(
      key: ValueKey('quick-remove-line-${line.id}'),
      tooltip: 'Quitar línea',
      onPressed: widget.locked ? null : widget.onRemove,
      icon: const Icon(Icons.delete_outline, size: 20),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 650) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                productField,
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 68, child: quantityField),
                    const SizedBox(width: 12),
                    Expanded(child: subtotal),
                    remove,
                  ],
                ),
              ],
            ),
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 4, child: productField),
            const SizedBox(width: 12),
            SizedBox(width: 68, child: quantityField),
            const SizedBox(width: 12),
            SizedBox(
              width: 116,
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: subtotal,
              ),
            ),
            remove,
          ],
        );
      },
    );
  }
}
