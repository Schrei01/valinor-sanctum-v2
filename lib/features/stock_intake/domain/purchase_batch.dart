part of 'stock_intake_store.dart';

class PurchaseBatchCommand {
  PurchaseBatchCommand({
    required this.commandId,
    required this.categoryId,
    required this.paymentOptionId,
    required this.totalPaidMinor,
    required this.occurredAtUtc,
    required List<StockIntakeCommand> items,
  }) : items = List.unmodifiable(items);
  final String commandId, categoryId, paymentOptionId;
  final int totalPaidMinor;
  final DateTime occurredAtUtc;
  final List<StockIntakeCommand> items;

  int get itemsTotalMinor {
    final sum = items.fold(
      BigInt.zero,
      (sum, item) => sum + BigInt.from(item.totalCostMinor),
    );
    if (sum <= BigInt.zero || sum > Money.maxMinorUnits) {
      throw const StockIntakeValidationException(
        'La suma de costos supera el límite permitido.',
      );
    }
    return sum.toInt();
  }

  int get differenceMinor => totalPaidMinor - itemsTotalMinor;

  void validate() {
    if (items.isEmpty ||
        items.length > 100 ||
        !occurredAtUtc.isUtc ||
        totalPaidMinor <= 0 ||
        BigInt.from(totalPaidMinor) > Money.maxMinorUnits) {
      throw const StockIntakeValidationException(
        'Indica un total pagado positivo y entre 1 y 100 productos.',
      );
    }
    final products = <String>{},
        names = <String>{},
        skus = <String>{},
        ids = <String>{commandId};
    for (final item in items) {
      if (item.categoryId != categoryId ||
          item.paymentOptionId != paymentOptionId ||
          item.occurredAtUtc != occurredAtUtc ||
          (item.expectedProduct != null &&
              item.expectedProduct!.categoryId != categoryId)) {
        throw const StockIntakeValidationException(
          'Todos los productos deben pertenecer a la misma categoría y compra.',
        );
      }
      if (!products.add(item.productId) ||
          !names.add(item.productName.trim().toLowerCase()) ||
          !ids.add(item.commandId) ||
          (item.sku?.trim().isNotEmpty == true &&
              !skus.add(item.sku!.trim().toLowerCase()))) {
        throw const StockIntakeValidationException(
          'No repitas un producto o SKU en la misma compra. Suma sus unidades en un solo formulario.',
        );
      }
    }
    itemsTotalMinor;
  }

  /// Inventory and settlement reconcile to actual paid money. The operator's
  /// costs remain separate immutable facts, never replaced by these allocations.
  /// Reserve one minor unit per positive-cost receipt, then apportion exactly.
  List<int> get settlementCosts {
    validate();
    if (totalPaidMinor < items.length) {
      throw const StockIntakeValidationException(
        'El total pagado debe permitir al menos una unidad monetaria mínima por producto.',
      );
    }
    final total = BigInt.from(itemsTotalMinor);
    if (totalPaidMinor == itemsTotalMinor) {
      return List.unmodifiable(items.map((item) => item.totalCostMinor));
    }
    final distributable = BigInt.from(totalPaidMinor);
    final portions = [
      for (final item in items)
        distributable * BigInt.from(item.totalCostMinor),
    ];
    final result = [
      for (final portion in portions)
        (portion ~/ total) < BigInt.one ? 1 : (portion ~/ total).toInt(),
    ];
    var remainder =
        totalPaidMinor - result.fold<int>(0, (sum, value) => sum + value);
    final order = List.generate(items.length, (index) => index)
      ..sort((a, b) {
        final diff = (portions[b] % total).compareTo(portions[a] % total);
        return diff != 0 ? diff : a.compareTo(b);
      });
    if (remainder < 0) {
      final largest = List.generate(items.length, (index) => index)
        ..sort((a, b) => result[b].compareTo(result[a]));
      for (final index in largest) {
        final remove = (-remainder) < (result[index] - 1)
            ? -remainder
            : result[index] - 1;
        result[index] -= remove;
        remainder += remove;
        if (remainder == 0) break;
      }
    }
    for (final index in order) {
      if (remainder-- <= 0) break;
      result[index]++;
    }
    return List.unmodifiable(result);
  }
}

class PreparedPurchaseBatch {
  const PreparedPurchaseBatch({
    required this.command,
    required this.status,
    required this.preparedAtUtc,
    this.rejectionReason,
  });
  final PurchaseBatchCommand command;
  final String status;
  final DateTime preparedAtUtc;
  final String? rejectionReason;
}

class PurchaseBatchEntry {
  const PurchaseBatchEntry({
    required this.command,
    required this.categoryName,
    required this.paymentLabel,
  });
  final PurchaseBatchCommand command;
  final String categoryName, paymentLabel;
}
