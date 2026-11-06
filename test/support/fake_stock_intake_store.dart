import 'dart:async';

import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/stock_intake/domain/stock_intake_store.dart';

class FakeStockIntakeStore implements StockIntakeStore {
  final batchCommands = <PurchaseBatchCommand>[];
  final batchPending = <PreparedPurchaseBatch>[];
  final batchEntries = <PurchaseBatchEntry>[];
  @override
  Future<PreparedPurchaseBatch> prepareBatch(
    PurchaseBatchCommand command,
  ) async {
    batchCommands.add(command);
    if (prepareFailure != null && !persistBeforePrepareFailure) {
      throw prepareFailure!;
    }
    final prior = batchPending
        .where((item) => item.command.commandId == command.commandId)
        .firstOrNull;
    final prepared =
        prior ??
        PreparedPurchaseBatch(
          command: command,
          status: 'prepared',
          preparedAtUtc: command.occurredAtUtc,
        );
    if (prior == null) batchPending.add(prepared);
    if (prepareFailure != null) throw prepareFailure!;
    return prepared;
  }

  @override
  Future<void> confirmBatch(String id) async {
    if (confirmGate != null) await confirmGate!.future;
    if (batchEntries.any((entry) => entry.command.commandId == id)) return;
    final prepared = batchPending.firstWhere(
      (item) => item.command.commandId == id,
    );
    if (confirmFailure is StockIntakeValidationException) {
      batchPending.remove(prepared);
      batchPending.add(
        PreparedPurchaseBatch(
          command: prepared.command,
          status: 'rejected',
          preparedAtUtc: prepared.preparedAtUtc,
          rejectionReason:
              (confirmFailure as StockIntakeValidationException).message,
        ),
      );
      throw confirmFailure!;
    }
    if (confirmFailure != null && !commitBeforeConfirmFailure) {
      throw confirmFailure!;
    }
    final command = prepared.command, costs = command.settlementCosts;
    final failure = confirmFailure;
    confirmFailure = null;
    try {
      for (var index = 0; index < command.items.length; index++) {
        final item = command.items[index];
        final child = StockIntakeCommand(
          commandId: item.commandId,
          productId: item.productId,
          expectedProduct: item.expectedProduct,
          productName: item.productName,
          sku: item.sku,
          categoryId: item.categoryId,
          supplierId: item.supplierId,
          supplierName: item.supplierName,
          totalPurchasePriceMinor: costs[index],
          listPriceMinor: item.listPriceMinor,
          quantity: item.quantity,
          paymentOptionId: item.paymentOptionId,
          occurredAtUtc: item.occurredAtUtc,
        );
        pending.add(
          PreparedStockIntake(
            command: child,
            status: 'prepared',
            preparedAtUtc: command.occurredAtUtc,
          ),
        );
        preparedCommands.add(child);
        await confirmPrepared(child.commandId);
      }
    } finally {
      confirmFailure = failure;
    }
    batchPending.remove(prepared);
    batchEntries.insert(
      0,
      PurchaseBatchEntry(
        command: command,
        categoryName: categories
            .firstWhere((cat) => cat.id == command.categoryId)
            .name,
        paymentLabel: paymentOptions
            .firstWhere((o) => o.id == command.paymentOptionId)
            .label,
      ),
    );
    if (confirmFailure != null) throw confirmFailure!;
  }

  @override
  Future<void> discardBatch(String id) async {
    batchPending.removeWhere(
      (item) => item.command.commandId == id && item.status == 'rejected',
    );
  }

  final categories = <InventoryCategory>[
    const InventoryCategory(id: 'food', name: 'Comestible'),
    const InventoryCategory(id: 'item', name: 'Artículo'),
    const InventoryCategory(id: 'event', name: 'Evento'),
  ];
  final suppliers = <InventorySupplier>[];
  final products = <CatalogProduct>[];
  final stock = <StockPosition>[];
  final productDefaults = <String, ProductIntakeDefaults>{};
  final paymentOptions = <IntakePaymentOption>[
    const IntakePaymentOption(
      id: 'cash',
      label: 'Efectivo',
      cashAccountId: 'cash-account',
      paymentMethodId: 'cash-method',
      balanceMinor: 1000000,
      openingRecorded: false,
      canRecordOpening: true,
    ),
    const IntakePaymentOption(
      id: 'nequi',
      label: 'Nequi',
      cashAccountId: 'nequi-account',
      paymentMethodId: 'nequi-method',
      balanceMinor: 500000,
      openingRecorded: false,
      canRecordOpening: true,
    ),
  ];
  final pending = <PreparedStockIntake>[];
  final entries = <StockIntakeEntry>[];
  final preparedCommands = <StockIntakeCommand>[];
  final confirmedIds = <String>[];
  final openingCommands = <CashOpeningCommand>[];
  final discardedIds = <String>[];
  final _results = <String, StockIntakeResult>{};
  final _openings = <String>{};
  Object? loadFailure;
  Object? prepareFailure;
  Object? confirmFailure;
  Object? openingFailure;
  bool persistBeforePrepareFailure = false;
  bool commitBeforeConfirmFailure = false;
  bool commitBeforeOpeningFailure = false;
  Completer<void>? confirmGate;
  int defaultsCalls = 0;

  @override
  Future<void> ensureDefaults() async {
    defaultsCalls++;
  }

  @override
  Future<StockIntakeSnapshot> load() async {
    if (loadFailure != null) throw loadFailure!;
    return StockIntakeSnapshot(
      categories: categories,
      suppliers: suppliers,
      products: products,
      stock: stock,
      productDefaults: productDefaults,
      paymentOptions: paymentOptions,
      pendingIntakes: pending,
      entries: entries
          .where(
            (entry) => !batchEntries.any(
              (batch) => batch.command.items.any(
                (item) => item.commandId == entry.commandId,
              ),
            ),
          )
          .toList(),
      pendingBatches: batchPending,
      batches: batchEntries,
    );
  }

  @override
  Future<PreparedStockIntake> prepare(StockIntakeCommand command) async {
    preparedCommands.add(command);
    if (prepareFailure != null && !persistBeforePrepareFailure) {
      throw prepareFailure!;
    }
    final old = pending
        .where((item) => item.command.commandId == command.commandId)
        .firstOrNull;
    final result =
        old ??
        PreparedStockIntake(
          command: command,
          status: 'prepared',
          preparedAtUtc: command.occurredAtUtc,
        );
    if (old == null) pending.add(result);
    if (prepareFailure != null) throw prepareFailure!;
    return result;
  }

  @override
  Future<StockIntakeResult> confirmPrepared(String commandId) async {
    confirmedIds.add(commandId);
    if (confirmGate != null) await confirmGate!.future;
    final old = _results[commandId];
    if (old != null) return old;
    final prepared = pending.firstWhere(
      (item) => item.command.commandId == commandId,
    );
    if (confirmFailure is StockIntakeValidationException) {
      pending.remove(prepared);
      pending.add(
        PreparedStockIntake(
          command: prepared.command,
          status: 'rejected',
          preparedAtUtc: prepared.preparedAtUtc,
          rejectionReason:
              (confirmFailure as StockIntakeValidationException).message,
        ),
      );
      throw confirmFailure!;
    }
    if (confirmFailure != null && !commitBeforeConfirmFailure) {
      throw confirmFailure!;
    }
    final command = prepared.command;
    final optionIndex = paymentOptions.indexWhere(
      (item) => item.id == command.paymentOptionId,
    );
    final option = paymentOptions[optionIndex];
    final total = command.totalCostMinor;
    final result = StockIntakeResult(
      commandId: commandId,
      productId: command.productId,
      purchaseDocumentId: 'purchase-$commandId',
      paymentDocumentId: 'payment-$commandId',
      totalCostMinor: total,
    );
    _results[commandId] = result;
    final oldStock = stock
        .where((item) => item.productId == command.productId)
        .firstOrNull;
    stock.removeWhere((item) => item.productId == command.productId);
    stock.add(
      StockPosition(
        productId: command.productId,
        quantity: (oldStock?.quantity ?? 0) + command.quantity,
        totalCostMinor: (oldStock?.totalCostMinor ?? 0) + total,
      ),
    );
    products.removeWhere((item) => item.id == command.productId);
    products.add(
      CatalogProduct(
        id: command.productId,
        name: command.productName,
        sku: command.sku,
        categoryId: command.categoryId,
        listPriceMinor: command.listPriceMinor,
      ),
    );
    if (!suppliers.any((item) => item.name == command.supplierName)) {
      suppliers.add(
        InventorySupplier(
          id: command.supplierId ?? 'supplier-$commandId',
          name: command.supplierName,
        ),
      );
    }
    productDefaults[command.productId] = ProductIntakeDefaults(
      supplierId: suppliers
          .firstWhere((item) => item.name == command.supplierName)
          .id,
      supplierName: command.supplierName,
      unitPurchasePriceMinor: command.exactUnitCostMinor,
    );
    paymentOptions[optionIndex] = _option(
      option,
      balance: option.balanceMinor - total,
      canOpen: false,
    );
    entries.insert(
      0,
      StockIntakeEntry(
        commandId: commandId,
        productId: command.productId,
        productName: command.productName,
        sku: command.sku,
        categoryName: categories
            .firstWhere((item) => item.id == command.categoryId)
            .name,
        supplierName: command.supplierName,
        quantity: command.quantity,
        unitPurchasePriceMinor: command.exactUnitCostMinor,
        listPriceMinor: command.listPriceMinor,
        totalCostMinor: total,
        paymentLabel: option.label,
        occurredAtUtc: command.occurredAtUtc,
      ),
    );
    pending.remove(prepared);
    if (confirmFailure != null) throw confirmFailure!;
    return result;
  }

  @override
  Future<void> discardRejected(String commandId) async {
    discardedIds.add(commandId);
    pending.removeWhere(
      (item) =>
          item.command.commandId == commandId && item.status == 'rejected',
    );
  }

  @override
  Future<void> recordOpeningBalance(CashOpeningCommand command) async {
    openingCommands.add(command);
    if (_openings.contains(command.commandId)) return;
    if (openingFailure != null && !commitBeforeOpeningFailure) {
      throw openingFailure!;
    }
    final index = paymentOptions.indexWhere(
      (item) => item.id == command.paymentOptionId,
    );
    final option = paymentOptions[index];
    if (!option.canRecordOpening) {
      throw const StockIntakeValidationException(
        'La cuenta ya tiene movimientos.',
      );
    }
    _openings.add(command.commandId);
    paymentOptions[index] = _option(
      option,
      balance: option.balanceMinor + command.amountMinor,
      openingRecorded: true,
      canOpen: false,
    );
    if (openingFailure != null) throw openingFailure!;
  }

  IntakePaymentOption _option(
    IntakePaymentOption old, {
    required int balance,
    bool? openingRecorded,
    required bool canOpen,
  }) => IntakePaymentOption(
    id: old.id,
    label: old.label,
    cashAccountId: old.cashAccountId,
    paymentMethodId: old.paymentMethodId,
    balanceMinor: balance,
    openingRecorded: openingRecorded ?? old.openingRecorded,
    canRecordOpening: canOpen,
    isActive: old.isActive,
  );
}
