import 'package:valinor_sanctum_2/features/collections/domain/collections_store.dart';

class FakeCollectionsStore implements CollectionsStore {
  final accounts = <CollectionAccount>[];
  final methods = <CollectionMethod>[];
  final receivables = <ReceivableSummary>[];
  final pending = <PreparedCollection>[];
  final collections = <ConfirmedCollection>[];
  final preparedInputs = <CollectionCommand>[];
  final confirmedIds = <String>[];
  final _results = <String, CollectionResult>{};
  Object? loadFailure;
  Object? saveFailure;
  Object? preparationFailure;
  Object? confirmationFailure;
  bool persistBeforePreparationFailure = false;
  bool commitBeforeConfirmationFailure = false;

  @override
  Future<CollectionsSnapshot> load() async {
    if (loadFailure != null) throw loadFailure!;
    return CollectionsSnapshot(
      accounts: accounts,
      methods: methods,
      receivables: receivables,
      pendingCollections: pending,
      collections: collections,
    );
  }

  @override
  Future<void> saveAccount(CollectionAccount account) async {
    if (saveFailure != null) throw saveFailure!;
    final old = accounts.where((item) => item.id == account.id).firstOrNull;
    accounts.removeWhere((item) => item.id == account.id);
    accounts.add(
      CollectionAccount(
        id: account.id,
        name: account.name,
        kind: account.kind,
        isAvailable: account.isAvailable,
        isActive: account.isActive,
        balanceMinor: old?.balanceMinor ?? 0,
      ),
    );
  }

  @override
  Future<void> saveMethod(CollectionMethod method) async {
    if (saveFailure != null) throw saveFailure!;
    methods.removeWhere((item) => item.id == method.id);
    methods.add(method);
  }

  @override
  Future<PreparedCollection> prepareCollection(
    CollectionCommand command,
  ) async {
    preparedInputs.add(command);
    final old = pending
        .where((item) => item.commandId == command.commandId)
        .firstOrNull;
    if (old != null) return old;
    if (preparationFailure != null && !persistBeforePreparationFailure) {
      throw preparationFailure!;
    }
    final source = receivables.firstWhere(
      (item) => item.receivableId == command.receivableId,
    );
    final result = PreparedCollection(
      commandId: command.commandId,
      receivableId: command.receivableId,
      label: source.label,
      customerName: source.customerName,
      occurredAtUtc: command.occurredAtUtc,
      preparedAtUtc: command.occurredAtUtc,
      status: 'prepared',
      totalMinor: command.parts.fold(0, (sum, part) => sum + part.amountMinor),
      parts: [
        for (final part in command.parts)
          CollectionPart(
            cashAccountId: part.cashAccountId,
            paymentMethodId: part.paymentMethodId,
            cashAccountName: accounts
                .firstWhere((item) => item.id == part.cashAccountId)
                .name,
            cashAccountKind: accounts
                .firstWhere((item) => item.id == part.cashAccountId)
                .kind,
            paymentMethodCode: methods
                .firstWhere((item) => item.id == part.paymentMethodId)
                .code,
            paymentMethodName: methods
                .firstWhere((item) => item.id == part.paymentMethodId)
                .name,
            amountMinor: part.amountMinor,
          ),
      ],
    );
    pending.add(result);
    if (preparationFailure != null) throw preparationFailure!;
    return result;
  }

  @override
  Future<CollectionResult> confirmPrepared(String commandId) async {
    confirmedIds.add(commandId);
    final old = _results[commandId];
    if (old != null) return old;
    final request = pending.firstWhere((item) => item.commandId == commandId);
    if (confirmationFailure != null && !commitBeforeConfirmationFailure) {
      if (confirmationFailure is CollectionsValidationException) {
        pending.remove(request);
        pending.add(
          PreparedCollection(
            commandId: request.commandId,
            receivableId: request.receivableId,
            label: request.label,
            customerName: request.customerName,
            occurredAtUtc: request.occurredAtUtc,
            preparedAtUtc: request.preparedAtUtc,
            status: 'rejected',
            totalMinor: request.totalMinor,
            parts: request.parts,
          ),
        );
      }
      throw confirmationFailure!;
    }
    final source = receivables.firstWhere(
      (item) => item.receivableId == request.receivableId,
    );
    final result = CollectionResult(
      documentId: 'collection-$commandId',
      commandId: commandId,
      receivableId: source.receivableId,
      totalMinor: request.totalMinor,
      remainingMinor: source.remainingMinor - request.totalMinor,
    );
    _results[commandId] = result;
    collections.insert(
      0,
      ConfirmedCollection(
        documentId: result.documentId,
        commandId: commandId,
        receivableId: source.receivableId,
        label: request.label,
        customerName: request.customerName,
        collectedAtUtc: request.occurredAtUtc,
        totalMinor: request.totalMinor,
        remainingMinor: result.remainingMinor,
        parts: request.parts,
      ),
    );
    receivables.remove(source);
    receivables.add(
      ReceivableSummary(
        receivableId: source.receivableId,
        saleDocumentId: source.saleDocumentId,
        label: source.label,
        customerName: source.customerName,
        issuedAtUtc: source.issuedAtUtc,
        dueDate: source.dueDate,
        initialMinor: source.initialMinor,
        collectedMinor: source.collectedMinor + request.totalMinor,
        remainingMinor: result.remainingMinor,
      ),
    );
    for (final part in request.parts) {
      final account = accounts.firstWhere(
        (item) => item.id == part.cashAccountId,
      );
      accounts.remove(account);
      accounts.add(
        CollectionAccount(
          id: account.id,
          name: account.name,
          kind: account.kind,
          isActive: account.isActive,
          isAvailable: account.isAvailable,
          balanceMinor: account.balanceMinor + part.amountMinor,
        ),
      );
    }
    pending.remove(request);
    if (confirmationFailure != null) throw confirmationFailure!;
    return result;
  }

  @override
  Future<void> discardRejected(String commandId) async {
    final value = pending.firstWhere((item) => item.commandId == commandId);
    if (value.status != 'rejected') {
      throw const CollectionsValidationException(
        'El cobro aún no se puede corregir.',
      );
    }
    pending.remove(value);
  }
}
