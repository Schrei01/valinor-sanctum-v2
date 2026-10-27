import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/app/sanctum_app.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/stock_adjustment_store.dart';
import 'package:valinor_sanctum_2/features/workspace/application/workspace_controller.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/workspace_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';
import '../support/fake_inventory_store.dart';
import '../support/fake_workspace_store.dart';

class AdjustmentInventory extends FakeInventoryStore
    implements StockAdjustmentStore {
  final pending = <String, StockAdjustmentCommand>{};
  final applied = <String>{};
  bool loseResponse = false;
  @override
  Future<List<StockAdjustmentCommand>> pendingAdjustments() async =>
      pending.values.where((c) => !applied.contains(c.commandId)).toList();
  @override
  Future<void> prepareAdjustment(StockAdjustmentCommand c) async {
    pending.putIfAbsent(c.commandId, () => c);
  }

  @override
  Future<void> confirmAdjustment(String id) async {
    if (applied.contains(id)) return;
    final c = pending[id]!,
        position = stock.singleWhere((s) => s.productId == c.productId);
    if (c.quantity > position.quantity) {
      throw const StockAdjustmentValidationException('Sin existencias');
    }
    stock.remove(position);
    stock.add(
      StockPosition(
        productId: c.productId,
        quantity: position.quantity - c.quantity,
        totalCostMinor: 0,
      ),
    );
    applied.add(id);
    if (loseResponse) {
      loseResponse = false;
      throw StateError('lost reply');
    }
  }

  @override
  Future<void> discardAdjustment(String id) async {
    pending.remove(id);
  }
}

void main() {
  late AdjustmentInventory inventory;
  late WorkspaceController workspace;
  setUp(() async {
    inventory = AdjustmentInventory()
      ..products.addAll(const [
        CatalogProduct(
          id: 'cola',
          name: 'Cocacola sintética',
          listPriceMinor: 1000,
        ),
        CatalogProduct(
          id: 'snack',
          name: 'Snack sintético',
          listPriceMinor: 2000,
        ),
        CatalogProduct(id: 'empty', name: 'Agotado', listPriceMinor: 999999),
        CatalogProduct(
          id: 'pass',
          name: 'Pasadía',
          listPriceMinor: 5000,
          isService: true,
        ),
        CatalogProduct(
          id: 'event',
          name: 'Liga sintética',
          listPriceMinor: 5000,
          isEvent: true,
        ),
      ])
      ..stock.addAll(const [
        StockPosition(productId: 'cola', quantity: 2, totalCostMinor: 0),
        StockPosition(productId: 'snack', quantity: 3, totalCostMinor: 0),
        StockPosition(productId: 'pass', quantity: 658, totalCostMinor: 0),
      ]);
    final source = FakeWorkspaceStore()
      ..profile = BusinessProfile(
        profileId: 'test',
        businessName: 'Sintética',
        currencyCode: 'COP',
        moneyScale: 0,
        timezone: 'America/Bogota',
        createdAtUtc: DateTime.utc(2026, 10, 27),
      );
    workspace = WorkspaceController(
      openSession: () async => WorkspaceSession(
        store: source,
        databasePath: 'synthetic',
        profileId: 'test',
        inventoryStore: inventory,
      ),
    );
    await workspace.initialize();
  });
  tearDown(() => workspace.dispose());
  Future<void> open(WidgetTester t, {Size size = const Size(1500, 950)}) async {
    await t.binding.setSurfaceSize(size);
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(SanctumApp(controller: workspace));
    await t.pumpAndSettle();
  }

  Future<void> tap(WidgetTester t, Finder f) async {
    await t.ensureVisible(f);
    await t.tap(f);
    await t.pumpAndSettle();
  }

  Future<void> shortcut(WidgetTester t) async {
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyD);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pumpAndSettle();
  }

  Future<void> choose(WidgetTester t) async {
    await t.enterText(
      find.byKey(const Key('stock-adjustment-product')),
      'Cocacola',
    );
    await t.pumpAndSettle();
    await tap(t, find.text('Cocacola sintética').last);
    await t.enterText(find.byKey(const Key('stock-adjustment-quantity')), '2');
    await t.pumpAndSettle();
  }

  testWidgets(
    'Ctrl D is confined to Catalog and subtracting to zero hides product and updates full value',
    (t) async {
      await open(t);
      await shortcut(t);
      expect(find.byType(AlertDialog), findsNothing);
      await tap(t, find.text('Catálogo'));
      expect(find.text('Agotado'), findsNothing);
      expect(find.text('Ilimitado'), findsNWidgets(2));
      expect(find.text('COP 8.000'), findsOneWidget);
      await shortcut(t);
      expect(find.text('Descontar unidades'), findsNWidgets(2));
      await choose(t);
      expect(find.text('Quedarán 0 unidades.'), findsOneWidget);
      await tap(t, find.byKey(const Key('stock-adjustment-submit')));
      expect(find.byType(AlertDialog), findsNothing);
      expect(inventory.applied, hasLength(1));
      expect(find.text('Cocacola sintética'), findsNothing);
      expect(find.text('COP 6.000'), findsOneWidget);
      await tap(t, find.text('Compras'));
      await shortcut(t);
      expect(find.byType(AlertDialog), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('inventory value ignores search and fits narrow screens', (
    t,
  ) async {
    await open(t, size: const Size(620, 950));
    await tap(t, find.text('Catálogo'));
    await t.enterText(find.byKey(const Key('catalog-search')), 'Cocacola');
    await t.pumpAndSettle();
    expect(find.text('Snack sintético'), findsNothing);
    expect(find.text('COP 8.000'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('value spans every page and includes archived physical stock', (
    t,
  ) async {
    inventory.products.add(
      const CatalogProduct(
        id: 'old',
        name: 'Archivado',
        listPriceMinor: 100,
        isActive: false,
      ),
    );
    inventory.stock.add(
      const StockPosition(productId: 'old', quantity: 1, totalCostMinor: 0),
    );
    for (var i = 0; i < 18; i++) {
      inventory.products.add(
        CatalogProduct(id: 'extra-$i', name: 'Extra $i', listPriceMinor: 100),
      );
      inventory.stock.add(
        StockPosition(productId: 'extra-$i', quantity: 1, totalCostMinor: 0),
      );
    }
    await open(t);
    await tap(t, find.text('Catálogo'));
    expect(find.text('COP 9.900'), findsOneWidget);
    await tap(t, find.byTooltip('Página siguiente'));
    expect(find.text('COP 9.900'), findsOneWidget);
    await t.enterText(find.byKey(const Key('catalog-search')), 'Cocacola');
    await t.pumpAndSettle();
    expect(find.text('COP 9.900'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('retail sum is exact above a signed 64-bit amount', (t) async {
    inventory.products.add(
      const CatalogProduct(
        id: 'large',
        name: 'Valor alto sintético',
        listPriceMinor: 0x7fffffffffffffff,
      ),
    );
    inventory.stock.add(
      const StockPosition(productId: 'large', quantity: 2, totalCostMinor: 0),
    );
    await open(t);
    await tap(t, find.text('Catálogo'));
    expect(find.text('COP 18.446.744.073.709.559.614'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'unknown response retries the same command and never discounts twice',
    (t) async {
      inventory.loseResponse = true;
      await open(t);
      await tap(t, find.text('Catálogo'));
      await tap(t, find.byKey(const Key('catalog-search')));
      await shortcut(t);
      await choose(t);
      await tap(t, find.byKey(const Key('stock-adjustment-submit')));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Reintentar mismo descuento'), findsOneWidget);
      await tap(t, find.byKey(const Key('stock-adjustment-submit')));
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        inventory.stock.singleWhere((s) => s.productId == 'cola').quantity,
        0,
      );
      expect(inventory.applied, hasLength(1));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
}
