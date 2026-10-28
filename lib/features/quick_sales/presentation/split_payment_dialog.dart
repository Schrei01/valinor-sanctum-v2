import 'package:flutter/material.dart';
import '../../../core/domain/money.dart';
import '../../../core/presentation/grouped_number_formatter.dart';
import '../../inventory/presentation/inventory_widgets.dart';
import '../../workspace/domain/business_profile.dart';
import '../domain/quick_sales_store.dart';

class SplitPaymentSelection {
  const SplitPaymentSelection(this.parts, this.debtorId);
  final List<QuickLinePaymentPart> parts;
  final String? debtorId;
}

class SplitPaymentDialog extends StatefulWidget {
  const SplitPaymentDialog({
    super.key,
    required this.line,
    required this.account,
    required this.data,
    required this.profile,
  });
  final QuickSaleLine line;
  final QuickSaleAccount account;
  final QuickSalesSnapshot data;
  final BusinessProfile profile;
  @override
  State<SplitPaymentDialog> createState() => _SplitPaymentDialogState();
}

class _SplitPaymentDialogState extends State<SplitPaymentDialog> {
  late final options = widget.data.paymentOptions
      .where(
        (p) =>
            (p.isCredit ||
            [
              'EFECTIVO',
              'NEQUI',
            ].any((code) => p.id == 'quick-default:$code') ||
            ['Efectivo', 'Nequi'].contains(p.label)),
      )
      .toList();
  late final fields = {
    for (final p in options)
      p.id: TextEditingController(
        text: _text(
          widget.line.paymentParts
                  .where((s) => s.paymentOptionId == p.id)
                  .firstOrNull
                  ?.amountMinor ??
              0,
        ),
      ),
  };
  late String? debtorId = widget.account.debtorId;
  String? error;
  BigInt get total =>
      BigInt.from(widget.line.unitPriceMinor ?? 0) *
      BigInt.from(int.tryParse(widget.line.quantityText) ?? 0);
  String _text(int minor) => Money.fromMinorUnits(
    minor,
    currency: widget.profile.currencyCode,
    scale: widget.profile.moneyScale,
  ).formatEsCo();
  int value(String id) => Money.parseEsCo(
    fields[id]!.text,
    currency: widget.profile.currencyCode,
    scale: widget.profile.moneyScale,
  ).minorUnits;
  List<QuickLinePaymentPart> parts() => [
    for (final p in options)
      if (value(p.id) != 0) QuickLinePaymentPart(p.id, value(p.id)),
  ];
  void remaining() {
    try {
      final other = options
          .where((p) => !p.isCredit)
          .fold(BigInt.zero, (sum, p) => sum + BigInt.from(value(p.id)));
      final rest = total - other;
      if (rest < BigInt.zero || rest > Money.maxMinorUnits) {
        throw const FormatException('Los pagos superan el total.');
      }
      fields[QuickPaymentOption.creditId]!.text = _text(rest.toInt());
      setState(() => error = null);
    } catch (e) {
      setState(() => error = 'Revisa los importes: $e');
    }
  }

  void save() {
    try {
      final selected = parts();
      if (selected.isEmpty ||
          selected.any((p) => p.amountMinor < 0) ||
          selected.fold(
                BigInt.zero,
                (s, p) => s + BigInt.from(p.amountMinor),
              ) !=
              total) {
        throw const FormatException(
          'La suma debe coincidir exactamente con el total de la línea.',
        );
      }
      if (selected.any(
        (part) =>
            !options.any((p) => p.id == part.paymentOptionId && p.isActive),
      )) {
        throw const FormatException(
          'Retira del reparto las formas de pago inactivas.',
        );
      }
      if (selected.any(
            (p) => p.paymentOptionId == QuickPaymentOption.creditId,
          ) &&
          !widget.data.debtors.any((p) => p.id == debtorId && p.isActive)) {
        throw const FormatException(
          'Selecciona una persona para asignar la deuda.',
        );
      }
      Navigator.pop(
        context,
        SplitPaymentSelection(List.unmodifiable(selected), debtorId),
      );
    } catch (e) {
      setState(
        () => error = e.toString().replaceFirst('FormatException: ', ''),
      );
    }
  }

  @override
  void dispose() {
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    BigInt? assigned;
    try {
      assigned = parts().fold<BigInt>(
        BigInt.zero,
        (s, p) => s + BigInt.from(p.amountMinor),
      );
    } catch (_) {
      assigned = null;
    }
    final people = widget.data.debtors.where((p) => p.isActive).toList();
    return AlertDialog(
      key: const Key('split-payment-dialog'),
      title: const Text('Dividir pago'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Total de la línea: ${inventoryMoney(total.toInt(), widget.profile)}',
              ),
              const SizedBox(height: 16),
              for (final p in options)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    key: ValueKey('split-amount-${p.id}'),
                    controller: fields[p.id],
                    inputFormatters: [const GroupedNumberFormatter()],
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: p.isActive
                          ? p.displayLabel
                          : '${p.displayLabel} (inactivo)',
                    ),
                    onChanged: (_) => setState(() => error = null),
                  ),
                ),
              if (fields.containsKey(QuickPaymentOption.creditId))
                TextButton(
                  onPressed: remaining,
                  child: const Text('Enviar restante a Deudas'),
                ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: const Key('split-debtor'),
                initialValue: people.any((p) => p.id == debtorId)
                    ? debtorId
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Persona para la deuda',
                ),
                items: [
                  for (final p in people)
                    DropdownMenuItem(
                      value: p.id,
                      child: Text(p.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (id) => setState(() => debtorId = id),
              ),
              const SizedBox(height: 8),
              const Text(
                'La persona se aplica a todas las deudas de esta cuenta.',
              ),
              const SizedBox(height: 12),
              Text(
                'Total asignado: ${assigned == null || assigned.abs() > Money.maxMinorUnits ? 'Revisa los importes' : inventoryMoney(assigned.toInt(), widget.profile)}',
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('split-save'),
          onPressed: save,
          child: const Text('Guardar reparto'),
        ),
      ],
    );
  }
}
