import 'package:flutter/material.dart';

import '../../../core/domain/money.dart';
import '../../workspace/domain/business_profile.dart';

String inventoryMoney(int amount, BusinessProfile profile) =>
    Money.fromMinorUnits(
      amount,
      currency: profile.currencyCode,
      scale: profile.moneyScale,
    ).formatEsCo(includeCurrency: true);

String? inventoryNameError(String? value) {
  final name = value?.trim() ?? '';
  if (name.isEmpty ||
      name.length > 120 ||
      RegExp(r'[\x00-\x1f]').hasMatch(name)) {
    return 'Escribe entre 1 y 120 caracteres.';
  }
  return null;
}

String? inventoryAmountError(String? value, BusinessProfile profile) {
  try {
    final amount = Money.parseEsCo(
      value ?? '',
      currency: profile.currencyCode,
      scale: profile.moneyScale,
    );
    if (amount.isNegative) return 'El importe no puede ser negativo.';
    return null;
  } on FormatException {
    return 'Usa puntos para miles y coma decimal (hasta ${profile.moneyScale} decimales).';
  } on RangeError {
    return 'El importe supera el límite permitido.';
  }
}

class InventoryNotice extends StatelessWidget {
  const InventoryNotice({super.key, required this.text, this.onRetry});
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text),
        if (onRetry != null)
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Actualizar'),
          ),
      ],
    ),
  );
}

class InventoryPageHeading extends StatelessWidget {
  const InventoryPageHeading({
    super.key,
    required this.title,
    required this.subtitle,
    required this.busy,
    required this.onRefresh,
  });
  final String title;
  final String subtitle;
  final bool busy;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 24,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
          OutlinedButton.icon(
            onPressed: busy ? null : onRefresh,
            icon: const Icon(Icons.refresh),
            label: Text(busy ? 'Procesando…' : 'Actualizar'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Text(
        subtitle,
        style: const TextStyle(color: Color(0xFF65716A), height: 1.5),
      ),
      const SizedBox(height: 24),
    ],
  );
}
