import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/sales/domain/sales_store.dart';

class FakeSalesStore implements SalesStore {
  final drafts = <SaleDraft>[];
  final pending = <SaleConfirmation>[];
  final sales = <ConfirmedSale>[];
  final products = <CatalogProduct>[];
  final stock = <StockPosition>[];
  final savedInputs = <SaveSaleDraft>[];
  final preparedIds = <String>[];
  final confirmedIds = <String>[];
  final _results = <String, SaleResult>{};
  Object? saveFailure;
  Object? loadFailure;
  Object? confirmationFailure;
  Object? preparationFailure;
  bool persistBeforePreparationFailure = false;
  bool commitBeforeConfirmationFailure = false;

  @override
  Future<SalesSnapshot> load() async {
    if (loadFailure != null) throw loadFailure!;
    return SalesSnapshot(
      drafts: drafts,
      pendingConfirmations: pending,
      sales: sales,
      products: products,
      stock: stock,
    );
  }

  @override
  Future<SaleDraft> saveDraft(SaveSaleDraft input) async {
    savedInputs.add(input);
    if (saveFailure != null) throw saveFailure!;
    final current = drafts.where((item) => item.id == input.id).firstOrNull;
    if (current != null && current.revision != input.expectedRevision) {
      throw const SalesValidationException(
        'La cuenta cambió. Actualiza su revisión.',
      );
    }
    final result = SaleDraft(
      id: input.id,
      label: input.label,
      customerName: input.customerName,
      revision: input.expectedRevision + 1,
      status: 'open',
      updatedAtUtc: DateTime.utc(2026, 10, 19),
      lines: input.lines,
    );
    drafts.removeWhere((item) => item.id == result.id);
    drafts.add(result);
    return result;
  }

  @override
  Future<SaleConfirmation> prepareConfirmation({
    required String commandId,
    required String draftId,
    required int expectedRevision,
    required DateTime occurredAtUtc,
    required String dueDate,
  }) async {
    preparedIds.add(commandId);
    final existing = pending
        .where((item) => item.commandId == commandId)
        .firstOrNull;
    if (existing != null) return existing;
    if (preparationFailure != null && !persistBeforePreparationFailure) {
      throw preparationFailure!;
    }
    final draft = drafts.firstWhere((item) => item.id == draftId);
    final result = SaleConfirmation(
      commandId: commandId,
      draftId: draftId,
      draftRevision: expectedRevision,
      occurredAtUtc: occurredAtUtc,
      dueDate: dueDate,
      preparedAtUtc: occurredAtUtc,
      status: 'prepared',
    );
    pending.add(result);
    drafts.remove(draft);
    drafts.add(
      SaleDraft(
        id: draft.id,
        label: draft.label,
        customerName: draft.customerName,
        revision: draft.revision,
        status: 'prepared',
        updatedAtUtc: draft.updatedAtUtc,
        lines: draft.lines,
      ),
    );
    if (preparationFailure != null) throw preparationFailure!;
    return result;
  }

  @override
  Future<SaleResult> confirmPrepared(String commandId) async {
    confirmedIds.add(commandId);
    final old = _results[commandId];
    if (old != null) return old;
    final request = pending.firstWhere((item) => item.commandId == commandId);
    if (confirmationFailure != null && !commitBeforeConfirmationFailure) {
      if (confirmationFailure is SalesValidationException) {
        pending.remove(request);
        pending.add(
          SaleConfirmation(
            commandId: request.commandId,
            draftId: request.draftId,
            draftRevision: request.draftRevision,
            occurredAtUtc: request.occurredAtUtc,
            dueDate: request.dueDate,
            preparedAtUtc: request.preparedAtUtc,
            status: 'rejected',
          ),
        );
      }
      throw confirmationFailure!;
    }
    final draft = drafts.firstWhere((item) => item.id == request.draftId);
    final total = draft.lines.fold<int>(
      0,
      (sum, line) => sum + line.quantity * line.unitPriceMinor,
    );
    const cost = 500;
    final result = SaleResult(
      documentId: 'document-$commandId',
      commandId: commandId,
      totalMinor: total,
      totalCostMinor: cost,
    );
    _results[commandId] = result;
    sales.add(
      ConfirmedSale(
        documentId: result.documentId,
        draftId: draft.id,
        label: draft.label,
        customerName: draft.customerName,
        soldAtUtc: request.occurredAtUtc,
        dueDate: request.dueDate,
        totalMinor: total,
        totalCostMinor: cost,
        lines: [
          for (final line in draft.lines)
            ConfirmedSaleLine(
              productName: products
                  .firstWhere((item) => item.id == line.productId)
                  .name,
              quantity: line.quantity,
              unitPriceMinor: line.unitPriceMinor,
              totalMinor: line.quantity * line.unitPriceMinor,
              totalCostMinor: cost,
            ),
        ],
      ),
    );
    for (final line in draft.lines) {
      final current = stock.firstWhere(
        (item) => item.productId == line.productId,
      );
      stock.remove(current);
      stock.add(
        StockPosition(
          productId: current.productId,
          quantity: current.quantity - line.quantity,
          totalCostMinor: current.totalCostMinor - cost,
        ),
      );
    }
    pending.removeWhere((item) => item.commandId == commandId);
    drafts.remove(draft);
    if (confirmationFailure != null) throw confirmationFailure!;
    return result;
  }

  @override
  Future<void> discardRejected(String commandId) async {
    final request = pending.firstWhere((item) => item.commandId == commandId);
    pending.remove(request);
    final old = drafts.firstWhere((item) => item.id == request.draftId);
    drafts.remove(old);
    drafts.add(
      SaleDraft(
        id: old.id,
        label: old.label,
        customerName: old.customerName,
        revision: old.revision + 1,
        status: 'open',
        updatedAtUtc: old.updatedAtUtc,
        lines: old.lines,
      ),
    );
  }
}
