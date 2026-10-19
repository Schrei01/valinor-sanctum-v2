import 'package:flutter/material.dart';

import '../../../core/domain/money.dart';
import '../../workspace/domain/business_profile.dart';
import '../application/inventory_controller.dart';
import '../domain/inventory_store.dart';
import 'inventory_widgets.dart';

class PurchasesPage extends StatefulWidget {
  const PurchasesPage({
    super.key,
    required this.controller,
    required this.profile,
  });
  final InventoryController controller;
  final BusinessProfile profile;
  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  final _form = GlobalKey<FormState>();
  final _reference = TextEditingController();
  final _due = TextEditingController();
  final List<_ReceiptLineDraft> _lines = [_ReceiptLineDraft()];
  String? _supplierId;
  bool _confirmed = false;
  int _formVersion = 0;
  int _historyPage = 0;

  @override
  void dispose() {
    _reference.dispose();
    _due.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final data = controller.snapshot;
      final locked = controller.busy || controller.pendingReceipt != null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InventoryPageHeading(
            title: 'Compras recibidas',
            subtitle:
                'Registra mercancía ya recibida a crédito: aumenta el inventario y la deuda con el proveedor. Esta compra no es un gasto ni una salida de caja.',
            busy: controller.busy,
            onRefresh: controller.load,
          ),
          if (controller.loadError != null)
            InventoryNotice(
              text: controller.loadError!,
              onRetry: controller.busy ? null : controller.load,
            ),
          if (data == null)
            if (controller.loading)
              const Center(child: CircularProgressIndicator())
            else
              const Text('La información de compras no está disponible.')
          else ...[
            if (_confirmed)
              const Padding(
                padding: EdgeInsets.only(bottom: 20),
                child: Text(
                  'Compra recibida y guardada. Inventario y deuda registrados.',
                  key: Key('receipt-confirmed'),
                  style: TextStyle(
                    color: Color(0xFF183D35),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (controller.receiptError != null)
              InventoryNotice(text: controller.receiptError!),
            if (!data.suppliers.any((value) => value.isActive) ||
                !data.products.any(controller.isProductAvailable))
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Primero crea al menos un producto y un proveedor activo en Catálogo.',
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recibir compra a crédito',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Las cantidades son unidades enteras. Escribe el costo total de cada línea, sin dividirlo entre unidades. Un costo cero debe ser explícito.',
                      ),
                      const SizedBox(height: 24),
                      DropdownButtonFormField<String>(
                        key: ValueKey('receipt-supplier-$_formVersion'),
                        initialValue: _supplierId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Proveedor',
                        ),
                        items: [
                          for (final supplier in data.suppliers.where(
                            (item) => item.isActive || item.id == _supplierId,
                          ))
                            DropdownMenuItem(
                              value: supplier.id,
                              enabled: supplier.isActive,
                              child: Text(
                                '${supplier.name}${supplier.isActive ? '' : ' (archivado)'}',
                              ),
                            ),
                        ],
                        onChanged: locked
                            ? null
                            : (value) => setState(() {
                                _supplierId = value;
                                _confirmed = false;
                              }),
                        validator: (value) =>
                            !data.suppliers.any(
                              (item) => item.id == value && item.isActive,
                            )
                            ? 'Selecciona un proveedor activo.'
                            : null,
                      ),
                      const SizedBox(height: 18),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final width = constraints.maxWidth >= 620
                              ? (constraints.maxWidth - 18) / 2
                              : constraints.maxWidth;
                          return Wrap(
                            spacing: 18,
                            runSpacing: 18,
                            children: [
                              SizedBox(
                                width: width,
                                child: TextFormField(
                                  key: const Key('receipt-reference'),
                                  controller: _reference,
                                  enabled: !locked,
                                  maxLength: 120,
                                  decoration: const InputDecoration(
                                    labelText:
                                        'Referencia del proveedor (opcional)',
                                  ),
                                  validator: (value) =>
                                      RegExp(
                                        r'[\x00-\x1f]',
                                      ).hasMatch(value ?? '')
                                      ? 'La referencia contiene caracteres no válidos.'
                                      : null,
                                ),
                              ),
                              SizedBox(
                                width: width,
                                child: TextFormField(
                                  key: const Key('receipt-due'),
                                  controller: _due,
                                  enabled: !locked,
                                  maxLength: 10,
                                  decoration: const InputDecoration(
                                    labelText: 'Vencimiento',
                                    hintText: 'AAAA-MM-DD',
                                    helperText:
                                        'Fecha de la deuda · recepción con fecha de hoy en Bogotá',
                                  ),
                                  validator: (value) =>
                                      InventoryController.isValidIsoDate(
                                        value?.trim() ?? '',
                                      )
                                      ? null
                                      : 'Escribe una fecha real: AAAA-MM-DD.',
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                      for (var index = 0; index < _lines.length; index++)
                        _lineEditor(_lines[index], index, data, locked),
                      TextButton.icon(
                        key: const Key('receipt-add-line'),
                        onPressed: locked || _lines.length >= 100
                            ? null
                            : () => setState(() {
                                _lines.add(_ReceiptLineDraft());
                                _confirmed = false;
                              }),
                        icon: const Icon(Icons.add),
                        label: const Text('Añadir producto'),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _totalLabel(),
                        key: const Key('receipt-total'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Quedará pendiente de pago. Puedes registrar abonos desde Pagos después de confirmar la recepción.',
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        key: const Key('receive-purchase'),
                        onPressed:
                            controller.busy ||
                                (controller.pendingReceipt == null &&
                                    (!data.suppliers.any(
                                          (value) => value.isActive,
                                        ) ||
                                        !data.products.any(
                                          controller.isProductAvailable,
                                        )))
                            ? null
                            : _receive,
                        icon: Icon(
                          controller.receiving
                              ? Icons.hourglass_empty
                              : controller.pendingReceipt != null
                              ? Icons.refresh
                              : Icons.inventory_2_outlined,
                        ),
                        label: Text(
                          controller.receiving
                              ? 'Confirmando recepción…'
                              : controller.pendingReceipt != null
                              ? 'Reintentar la misma compra'
                              : 'Confirmar recepción a crédito',
                        ),
                      ),
                      if (controller.pendingReceipt != null)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                            'Mantén la aplicación abierta y reintenta esta compra antes de registrar otra.',
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Historial de recepciones',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            const Text(
              'Compras a crédito registradas. Consulta lo pagado y pendiente; aplica abonos desde Pagos.',
            ),
            const SizedBox(height: 16),
            _history(data),
          ],
        ],
      );
    },
  );

  Widget _lineEditor(
    _ReceiptLineDraft line,
    int index,
    InventorySnapshot data,
    bool locked,
  ) => Container(
    key: ValueKey(line.id),
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xFFE4E7E0)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 700;
        final productWidth = wide
            ? constraints.maxWidth - 376
            : constraints.maxWidth;
        final amountWidth = wide
            ? 200.0
            : constraints.maxWidth >= 400
            ? constraints.maxWidth - 160
            : constraints.maxWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Producto ${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'Quitar producto ${index + 1}',
                  onPressed: locked || _lines.length == 1
                      ? null
                      : () => setState(() {
                          _lines.remove(line);
                          line.dispose();
                          _confirmed = false;
                        }),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              crossAxisAlignment: WrapCrossAlignment.start,
              children: [
                SizedBox(
                  width: productWidth,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('receipt-product-${line.id}'),
                    initialValue: line.productId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Producto'),
                    items: [
                      for (final product in data.products.where(
                        (item) =>
                            widget.controller.isProductAvailable(item) ||
                            item.id == line.productId,
                      ))
                        DropdownMenuItem(
                          value: product.id,
                          enabled: widget.controller.isProductAvailable(
                            product,
                          ),
                          child: Text(
                            '${product.name}${widget.controller.isProductAvailable(product) ? '' : ' (no disponible)'}',
                          ),
                        ),
                    ],
                    onChanged: locked
                        ? null
                        : (value) => setState(() {
                            line.productId = value;
                            _confirmed = false;
                          }),
                    validator: (value) =>
                        !data.products.any(
                          (item) =>
                              item.id == value &&
                              widget.controller.isProductAvailable(item),
                        )
                        ? 'Selecciona un producto disponible.'
                        : null,
                  ),
                ),
                SizedBox(
                  width: wide
                      ? 144
                      : constraints.maxWidth < 144
                      ? constraints.maxWidth
                      : 144,
                  child: TextFormField(
                    key: ValueKey('receipt-quantity-${line.id}'),
                    controller: line.quantity,
                    enabled: !locked,
                    decoration: const InputDecoration(labelText: 'Unidades'),
                    validator: (value) {
                      if (!RegExp(r'^[0-9]+$').hasMatch(value?.trim() ?? '')) {
                        return 'Solo enteros.';
                      }
                      final number = BigInt.tryParse(value!.trim());
                      return number == null ||
                              number <= BigInt.zero ||
                              number > Money.maxMinorUnits
                          ? 'Cantidad no válida.'
                          : null;
                    },
                  ),
                ),
                SizedBox(
                  width: amountWidth,
                  child: TextFormField(
                    key: ValueKey('receipt-cost-${line.id}'),
                    controller: line.cost,
                    enabled: !locked,
                    decoration: InputDecoration(
                      labelText: 'Costo TOTAL (${widget.profile.currencyCode})',
                      helperText: '${widget.profile.moneyScale} decimales',
                    ),
                    validator: (value) =>
                        inventoryAmountError(value, widget.profile),
                    onChanged: (_) => setState(() => _confirmed = false),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );

  String _totalLabel() {
    var total = BigInt.zero;
    for (final line in _lines) {
      if (inventoryAmountError(line.cost.text, widget.profile) != null) {
        return 'Total: completa los costos';
      }
      total += Money.parseEsCo(
        line.cost.text,
        currency: widget.profile.currencyCode,
        scale: widget.profile.moneyScale,
      ).asBigInt;
    }
    if (total > Money.maxMinorUnits) return 'Total: supera el límite permitido';
    return 'Total a crédito: ${inventoryMoney(total.toInt(), widget.profile)}';
  }

  Future<void> _receive() async {
    final controller = widget.controller;
    var confirmed = false;
    if (controller.pendingReceipt != null) {
      confirmed = await controller.retryReceipt();
    } else {
      if (!_form.currentState!.validate()) return;
      confirmed = await controller.receivePurchase(
        supplierId: _supplierId!,
        reference: _reference.text,
        dueDate: _due.text.trim(),
        lines: [
          for (final line in _lines)
            ReceiptLineInput(
              productId: line.productId!,
              quantity: BigInt.parse(line.quantity.text.trim()).toInt(),
              totalCostMinor: Money.parseEsCo(
                line.cost.text,
                currency: widget.profile.currencyCode,
                scale: widget.profile.moneyScale,
              ).minorUnits,
            ),
        ],
      );
    }
    if (!mounted || !confirmed) return;
    setState(() {
      _form.currentState!.reset();
      _reference.clear();
      _due.clear();
      _supplierId = null;
      for (final line in _lines) {
        line.dispose();
      }
      _lines
        ..clear()
        ..add(_ReceiptLineDraft());
      _formVersion++;
      _confirmed = true;
      _historyPage = 0;
    });
  }

  Widget _history(InventorySnapshot data) {
    final rows = data.receipts;
    if (rows.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Aún no hay compras recibidas.'),
        ),
      );
    }
    const pageSize = 10;
    final page = _historyPage.clamp(0, (rows.length - 1) ~/ pageSize);
    return Column(
      children: [
        for (final receipt in rows.skip(page * pageSize).take(pageSize))
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 24,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        receipt.supplierName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        inventoryMoney(receipt.totalMinor, widget.profile),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Chip(
                        label: Text(
                          receipt.remainingMinor == 0
                              ? 'Pagada'
                              : 'Recibida a crédito',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pagado: ${inventoryMoney(receipt.paidMinor, widget.profile)} · '
                    'Pendiente: ${inventoryMoney(receipt.remainingMinor, widget.profile)}',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Recepción: ${InventoryController.isoDate(receipt.receivedAtUtc.subtract(const Duration(hours: 5)))} · Vence: ${receipt.dueDate}',
                  ),
                  if (receipt.reference != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('Referencia: ${receipt.reference}'),
                    ),
                  if (receipt.lines.isNotEmpty)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text('Ver productos (${receipt.lines.length})'),
                      children: [
                        for (final line in receipt.lines)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '${line.productName} · ${line.quantity} unidades · '
                                'Costo total: ${inventoryMoney(line.totalCostMinor, widget.profile)}',
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              '${page * pageSize + 1}–${(page * pageSize + pageSize).clamp(0, rows.length)} de ${rows.length}',
            ),
            IconButton(
              tooltip: 'Recepciones anteriores',
              onPressed: page == 0
                  ? null
                  : () => setState(() => _historyPage = page - 1),
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: 'Recepciones siguientes',
              onPressed: (page + 1) * pageSize >= rows.length
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

class _ReceiptLineDraft {
  final String id = InventoryIds.next();
  String? productId;
  final quantity = TextEditingController(text: '1');
  final cost = TextEditingController();
  void dispose() {
    quantity.dispose();
    cost.dispose();
  }
}
