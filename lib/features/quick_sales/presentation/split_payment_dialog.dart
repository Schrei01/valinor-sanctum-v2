import 'package:flutter/material.dart';
import '../../../core/domain/money.dart';
import '../../../core/presentation/grouped_number_formatter.dart';
import '../../inventory/presentation/inventory_widgets.dart';
import '../../workspace/domain/business_profile.dart';
import '../domain/quick_sales_store.dart';
import '../domain/account_payment_split.dart';

class SplitPaymentSelection {
  const SplitPaymentSelection(this.parts);
  final List<QuickLinePaymentPart> parts;
}

class SplitPaymentDialog extends StatefulWidget {
  const SplitPaymentDialog({
    super.key,
    required this.account,
    required this.data,
    required this.profile,
  });
  final QuickSaleAccount account;
  final QuickSalesSnapshot data;
  final BusinessProfile profile;
  @override
  State<SplitPaymentDialog> createState() => _SplitPaymentDialogState();
}

class _SplitPaymentDialogState extends State<SplitPaymentDialog> {
  late final totals = accountPaymentTotals(widget.account);
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
        text: (totals[p.id] ?? BigInt.zero).abs() > Money.maxMinorUnits
            ? ''
            : _text((totals[p.id] ?? BigInt.zero).toInt()),
      ),
  };
  String? error;
  BigInt get total => widget.account.lines.fold(
    BigInt.zero,
    (sum, line) =>
        sum +
        BigInt.from(line.unitPriceMinor ?? 0) *
            (BigInt.tryParse(line.quantityText.trim()) ?? BigInt.zero),
  );
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
          'La suma debe coincidir exactamente con el total de la cuenta.',
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
          !widget.data.debtors.any(
            (p) => p.id == widget.account.debtorId && p.isActive,
          )) {
        throw const FormatException(
          'Asocia la cuenta a una persona en el encabezado de Ventas para registrar deuda.',
        );
      }
      Navigator.pop(
        context,
        SplitPaymentSelection(List.unmodifiable(selected)),
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
    final person = widget.data.debtors
        .where((p) => p.id == widget.account.debtorId)
        .firstOrNull;
    return AlertDialog(
      key: const Key('split-payment-dialog'),
      title: const Text('Dividir cuenta'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Total de la cuenta: ${inventoryMoney(total.toInt(), widget.profile)}',
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
              Text(
                person == null
                    ? 'Para fiar, asocia esta cuenta a una persona en el encabezado de Ventas.'
                    : person.isActive
                    ? 'La deuda se asignará a ${person.name}.'
                    : '${person.name} tiene bloqueado el fiado.',
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
