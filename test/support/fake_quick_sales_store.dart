import 'dart:async';
import 'dart:convert';
import 'package:valinor_sanctum_2/features/debtors/domain/debtors_store.dart';

import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/quick_sales_store.dart';

class FakeQuickSalesStore implements QuickSalesStore {
  final debtors = <DebtorSummary>[
    for (final name in [
      'Cliente sintético',
      'Cliente mixto',
      'Cliente guardado',
      'Cliente conservado',
      'Cliente reintento',
      'Cliente inicial',
      'Cliente corregido',
      'Cliente estrecho',
      'Cliente válido',
      'Cliente fijo',
      'Cliente preparado',
      'Cliente posterior',
    ])
      DebtorSummary(id: name, name: name, balanceMinor: 0),
  ];
  final accounts = <QuickSaleAccount>[];
  final products = <CatalogProduct>[
    const CatalogProduct(
      id: 'water',
      name: 'Agua sintética',
      sku: 'AGUA',
      listPriceMinor: 300000,
    ),
    const CatalogProduct(
      id: 'snack',
      name: 'Snack sintético',
      sku: 'SNACK',
      listPriceMinor: 200000,
    ),
  ];
  final stock = <StockPosition>[
    const StockPosition(
      productId: 'water',
      quantity: 20,
      totalCostMinor: 2000000,
    ),
    const StockPosition(
      productId: 'snack',
      quantity: 30,
      totalCostMinor: 1500000,
    ),
  ];
  final options = <QuickPaymentOption>[];
  final pending = <PreparedQuickSale>[];
  final sales = <ConfirmedQuickSale>[];
  final balances = <String, int>{'cash-account': 0, 'nequi-account': 0};
  final customerDebts = <String, int>{};
  final savedInputs = <SaveQuickSaleAccount>[];
  final preparedIds = <String>[];
  final confirmedIds = <String>[];
  final _saved = <String, QuickSaleAccount>{};
  final _results = <String, QuickSaleResult>{};
  int defaultsCalls = 0;
  int activeSaves = 0;
  int maximumActiveSaves = 0;
  Object? loadFailure;
  Object? saveFailure;
  Object? preparationFailure;
  Object? confirmationFailure;
  bool saveBeforeFailure = false;
  bool prepareBeforeFailure = false;
  bool commitBeforeFailure = false;
  Completer<void>? saveGate;
  Completer<void>? loadGate;

  @override
  Future<void> ensureDefaults() async {
    defaultsCalls++;
    if (options.isNotEmpty) return;
    options.addAll([
      const QuickPaymentOption(
        id: 'cash',
        label: 'Efectivo',
        cashAccountId: 'cash-account',
        paymentMethodId: 'cash-method',
      ),
      const QuickPaymentOption(
        id: 'nequi',
        label: 'Nequi',
        cashAccountId: 'nequi-account',
        paymentMethodId: 'nequi-method',
      ),
      const QuickPaymentOption(
        id: QuickPaymentOption.creditId,
        label: 'Deudas',
        cashAccountId: '',
        paymentMethodId: '',
        isCredit: true,
      ),
    ]);
  }

  @override
  Future<QuickSalesSnapshot> load() async {
    if (loadFailure != null) throw loadFailure!;
    final result = QuickSalesSnapshot(
      accounts: accounts,
      debtors: debtors,
      products: products,
      stock: stock,
      paymentOptions: options,
      pendingSales: pending,
      sales: sales,
    );
    final gate = loadGate;
    await gate?.future;
    return result;
  }

  String _key(SaveQuickSaleAccount input) => jsonEncode([
    input.id,
    input.expectedRevision,
    input.label,
    input.customerName,
    input.debtorId,
    input.paymentMode,
    input.accountPaymentOptionId,
    input.paymentSplitBasis,
    for (final line in input.lines)
      [
        line.id,
        line.productId,
        line.quantityText,
        line.unitPriceMinor,
        line.paymentOptionId,
        line.paymentParts.map((p) => p.toJson()).toList(),
      ],
  ]);

  @override
  Future<QuickSaleAccount> saveAccount(SaveQuickSaleAccount input) async {
    savedInputs.add(input);
    activeSaves++;
    if (activeSaves > maximumActiveSaves) maximumActiveSaves = activeSaves;
    try {
      await saveGate?.future;
      final key = _key(input);
      if (_saved[key] != null) return _saved[key]!;
      if (saveFailure != null && !saveBeforeFailure) throw saveFailure!;
      final current = accounts.where((item) => item.id == input.id).firstOrNull;
      if ((current?.revision ?? 0) != input.expectedRevision) {
        throw const QuickSalesValidationException(
          'La cuenta cambió; actualiza.',
        );
      }
      final saved = QuickSaleAccount(
        id: input.id,
        label: input.label,
        customerName: input.customerName,
        debtorId: input.debtorId,
        paymentMode: input.paymentMode,
        accountPaymentOptionId: input.accountPaymentOptionId,
        paymentSplitBasis: input.paymentSplitBasis,
        revision: input.expectedRevision + 1,
        status: 'open',
        updatedAtUtc: DateTime.utc(2026, 10, 19),
        lines: input.lines,
      );
      accounts.removeWhere((item) => item.id == input.id);
      accounts.add(saved);
      _saved[key] = saved;
      if (saveFailure != null) throw saveFailure!;
      return saved;
    } finally {
      activeSaves--;
    }
  }

  @override
  Future<void> cancelAccount({
    required String accountId,
    required int expectedRevision,
  }) async {
    accounts.removeWhere((item) => item.id == accountId);
  }

  @override
  Future<PreparedQuickSale> prepareSale({
    required String commandId,
    required String accountId,
    required int expectedRevision,
    required DateTime occurredAtUtc,
  }) async {
    preparedIds.add(commandId);
    final prior = pending
        .where((item) => item.commandId == commandId)
        .firstOrNull;
    if (prior != null) return prior;
    if (preparationFailure != null && !prepareBeforeFailure) {
      throw preparationFailure!;
    }
    final account = accounts.firstWhere((item) => item.id == accountId);
    if (account.lines.any(
      (line) =>
          line.productId == null ||
          (int.tryParse(line.quantityText) ?? 0) <= 0 ||
          line.paymentOptionId == null,
    )) {
      throw const QuickSalesValidationException(
        'Selecciona producto, cantidad y forma de pago en cada línea.',
      );
    }
    final hasCredit = account.lines.any(
      (line) => line.paymentOptionId == QuickPaymentOption.creditId,
    );
    if (hasCredit &&
        (account.debtorId == null || account.customerName.trim().isEmpty)) {
      throw const QuickSalesValidationException(
        'Escribe el nombre del cliente.',
      );
    }
    final credit = account.lines
        .where((line) => line.paymentOptionId == QuickPaymentOption.creditId)
        .fold(
          0,
          (sum, line) =>
              sum + line.unitPriceMinor! * int.parse(line.quantityText),
        );
    final prepared = PreparedQuickSale(
      commandId: commandId,
      accountId: accountId,
      accountRevision: expectedRevision,
      label: account.label,
      totalMinor: account.lines.fold(
        0,
        (sum, line) =>
            sum + line.unitPriceMinor! * int.parse(line.quantityText),
      ),
      creditMinor: credit,
      customerName: hasCredit ? account.customerName.trim() : '',
      debtorId: hasCredit ? account.debtorId : null,
      occurredAtUtc: occurredAtUtc,
      preparedAtUtc: occurredAtUtc,
      status: 'prepared',
    );
    pending.add(prepared);
    if (preparationFailure != null) throw preparationFailure!;
    return prepared;
  }

  @override
  Future<QuickSaleResult> confirmPrepared(String commandId) async {
    confirmedIds.add(commandId);
    final old = _results[commandId];
    if (old != null) return old;
    final prepared = pending.firstWhere((item) => item.commandId == commandId);
    if (confirmationFailure != null && !commitBeforeFailure) {
      if (confirmationFailure is QuickSalesValidationException) {
        pending.remove(prepared);
        pending.add(
          PreparedQuickSale(
            commandId: commandId,
            accountId: prepared.accountId,
            accountRevision: prepared.accountRevision,
            label: prepared.label,
            totalMinor: prepared.totalMinor,
            creditMinor: prepared.creditMinor,
            customerName: prepared.customerName,
            debtorId: prepared.debtorId,
            occurredAtUtc: prepared.occurredAtUtc,
            preparedAtUtc: prepared.preparedAtUtc,
            status: 'rejected',
            rejectionReason: confirmationFailure.toString(),
          ),
        );
      }
      throw confirmationFailure!;
    }
    final account = accounts.firstWhere(
      (item) => item.id == prepared.accountId,
    );
    final result = QuickSaleResult(
      commandId: commandId,
      saleDocumentId: 'sale-$commandId',
      collectionDocumentId: prepared.totalMinor == prepared.creditMinor
          ? null
          : 'collection-$commandId',
      totalMinor: prepared.totalMinor,
      totalCostMinor: 100000,
      creditMinor: prepared.creditMinor,
      customerName: prepared.customerName,
      debtorId: prepared.debtorId,
    );
    _results[commandId] = result;
    for (final line in account.lines) {
      final quantity = int.parse(line.quantityText);
      final amount = quantity * line.unitPriceMinor!;
      if (line.paymentOptionId == QuickPaymentOption.creditId) {
        customerDebts.update(
          prepared.customerName,
          (current) => current + amount,
          ifAbsent: () => amount,
        );
      } else {
        final option = options.firstWhere(
          (item) => item.id == line.paymentOptionId,
        );
        balances.update(
          option.cashAccountId,
          (current) => current + amount,
          ifAbsent: () => amount,
        );
      }
      final stockIndex = stock.indexWhere(
        (item) => item.productId == line.productId,
      );
      final position = stock[stockIndex];
      stock[stockIndex] = StockPosition(
        productId: position.productId,
        quantity: position.quantity - quantity,
        totalCostMinor:
            position.totalCostMinor -
            (position.quantity == 0
                    ? 0
                    : position.totalCostMinor ~/ position.quantity) *
                quantity,
      );
    }
    sales.insert(
      0,
      ConfirmedQuickSale(
        commandId: commandId,
        label: prepared.label,
        soldAtUtc: prepared.occurredAtUtc,
        result: result,
        lines: [
          for (final line in account.lines)
            ConfirmedQuickSaleLine(
              productName: products
                  .firstWhere((item) => item.id == line.productId)
                  .name,
              quantity: int.parse(line.quantityText),
              unitPriceMinor: line.unitPriceMinor!,
              totalMinor: int.parse(line.quantityText) * line.unitPriceMinor!,
              paymentLabel: options
                  .firstWhere((item) => item.id == line.paymentOptionId)
                  .label,
              isCredit: line.paymentOptionId == QuickPaymentOption.creditId,
            ),
        ],
      ),
    );
    pending.remove(prepared);
    accounts.remove(account);
    if (confirmationFailure != null) throw confirmationFailure!;
    return result;
  }

  @override
  Future<void> discardRejected(String commandId) async {
    final prepared = pending.firstWhere((item) => item.commandId == commandId);
    if (prepared.status != 'rejected') throw StateError('Not rejected');
    final account = accounts.firstWhere(
      (item) => item.id == prepared.accountId,
    );
    pending.remove(prepared);
    accounts.remove(account);
    accounts.add(
      QuickSaleAccount(
        id: account.id,
        label: account.label,
        customerName: account.customerName,
        debtorId: account.debtorId,
        paymentMode: account.paymentMode,
        accountPaymentOptionId: account.accountPaymentOptionId,
        paymentSplitBasis: account.paymentSplitBasis,
        revision: account.revision + 1,
        status: 'open',
        updatedAtUtc: account.updatedAtUtc,
        lines: account.lines,
      ),
    );
  }
}
