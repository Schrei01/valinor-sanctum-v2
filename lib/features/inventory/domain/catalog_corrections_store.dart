import '../../events/domain/events_store.dart';

enum CatalogCorrectionKind { name, price, event }

class CatalogCorrectionCommand {
  CatalogCorrectionCommand({
    required this.commandId,
    required this.productId,
    required this.kind,
    required this.expectedName,
    required this.expectedPriceMinor,
    required this.occurredAtUtc,
    this.name,
    this.priceMinor,
    this.expectedRevision,
    this.minimumPeople,
    this.fixedCostMinor,
    this.sourceAccountId,
    List<EventProductInput> products = const [],
  }) : products = List.unmodifiable(products);
  final String commandId, productId, expectedName;
  final CatalogCorrectionKind kind;
  final int expectedPriceMinor;
  final DateTime occurredAtUtc;
  final String? name, expectedRevision, sourceAccountId;
  final int? priceMinor, minimumPeople, fixedCostMinor;
  final List<EventProductInput> products;
  Map<String, Object?> toJson() => {
    'commandId': commandId,
    'productId': productId,
    'kind': kind.name,
    'expectedName': expectedName,
    'expectedPriceMinor': expectedPriceMinor,
    'occurredAtUtc': occurredAtUtc.toIso8601String(),
    'name': name,
    'priceMinor': priceMinor,
    'expectedRevision': expectedRevision,
    'minimumPeople': minimumPeople,
    'fixedCostMinor': fixedCostMinor,
    'sourceAccountId': sourceAccountId,
    'products':
        (products.toList()..sort((a, b) => a.productId.compareTo(b.productId)))
            .map((p) => p.toJson())
            .toList(),
  };
  factory CatalogCorrectionCommand.fromJson(Map<String, dynamic> j) =>
      CatalogCorrectionCommand(
        commandId: j['commandId'],
        productId: j['productId'],
        kind: CatalogCorrectionKind.values.byName(j['kind']),
        expectedName: j['expectedName'],
        expectedPriceMinor: j['expectedPriceMinor'],
        occurredAtUtc: DateTime.parse(j['occurredAtUtc']),
        name: j['name'],
        priceMinor: j['priceMinor'],
        expectedRevision: j['expectedRevision'],
        minimumPeople: j['minimumPeople'],
        fixedCostMinor: j['fixedCostMinor'],
        sourceAccountId: j['sourceAccountId'],
        products: [
          for (final p in j['products'] as List)
            EventProductInput(p['productId'], p['quantity']),
        ],
      );
}

class PreparedCatalogCorrection {
  const PreparedCatalogCorrection(this.command, this.plan);
  final CatalogCorrectionCommand command;
  final Map<String, dynamic> plan;
}

class CatalogEventState {
  const CatalogEventState(this.values, this.components, this.accounts);
  final Map<String, Object?> values;
  final List<Map<String, Object?>> components;
  final List<EventAccount> accounts;
  String get revision => values['revision'] as String;
  String get name => values['name_snapshot'] as String;
  int get pvpMinor => values['pvp_minor'] as int;
  int get minimumPeople => values['minimum_people'] as int;
  int get fixedCostMinor => values['fixed_cost_minor'] as int;
  String? get sourceAccountId => values['source_option_id'] as String?;
}

abstract interface class CatalogCorrectionsStore {
  Future<CatalogEventState> loadEvent(String productId);
  Future<List<PreparedCatalogCorrection>> pendingCorrections();
  Future<PreparedCatalogCorrection> prepareCorrection(
    CatalogCorrectionCommand command,
  );
  Future<void> confirmCorrection(String commandId);
  Future<void> discardCorrection(String commandId);
}

class CatalogCorrectionValidationException implements Exception {
  const CatalogCorrectionValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}
