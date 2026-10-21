import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/app/sanctum_app.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/application/inventory_controller.dart';
import 'package:valinor_sanctum_2/features/inventory/presentation/catalog_page.dart';
import '../support/fake_inventory_store.dart';
import 'package:valinor_sanctum_2/features/events/application/events_controller.dart';
import 'package:valinor_sanctum_2/features/events/presentation/events_page.dart';
import 'package:valinor_sanctum_2/features/events/domain/events_store.dart';
import 'package:valinor_sanctum_2/features/workspace/application/workspace_controller.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/workspace_store.dart';
import '../support/fake_events_store.dart';
import '../support/fake_workspace_store.dart';

void main() {
  testWidgets(
    'catalog includes active events without stock, hides inactive events and offers only event deactivation',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = FakeInventoryStore()
        ..products.addAll(const [
          CatalogProduct(
            id: 'event',
            name: 'Liga visible',
            isEvent: true,
            listPriceMinor: 1000,
          ),
          CatalogProduct(
            id: 'inactive',
            name: 'Liga desactivada',
            isEvent: true,
            isActive: false,
            listPriceMinor: 1000,
          ),
          CatalogProduct(
            id: 'empty',
            name: 'Producto agotado',
            listPriceMinor: 1000,
          ),
          CatalogProduct(
            id: 'physical',
            name: 'Producto disponible',
            listPriceMinor: 1000,
          ),
        ])
        ..stock.add(
          const StockPosition(
            productId: 'physical',
            quantity: 2,
            totalCostMinor: 500,
          ),
        );
      final controller = InventoryController(store: store);
      await controller.load();
      addTearDown(controller.dispose);
      final deactivated = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CatalogPage(
                controller: controller,
                profile: BusinessProfile(
                  profileId: 'test',
                  businessName: 'Sintético',
                  currencyCode: 'COP',
                  moneyScale: 2,
                  timezone: 'America/Bogota',
                  createdAtUtc: DateTime.utc(2026),
                ),
                onDeactivateEvent: (id) async {
                  deactivated.add(id);
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Liga visible'), findsOneWidget);
      expect(find.text('Producto disponible'), findsOneWidget);
      expect(find.text('Liga desactivada'), findsNothing);
      expect(find.text('Producto agotado'), findsNothing);
      expect(find.text('Desactivar'), findsOneWidget);
      await tester.tap(find.text('Desactivar'));
      await tester.pumpAndSettle();
      expect(deactivated, isEmpty);
      await tester.tap(find.widgetWithText(FilledButton, 'Desactivar'));
      await tester.pumpAndSettle();
      expect(deactivated, ['event']);
      expect(tester.takeException(), isNull);
    },
  );
  final profile = BusinessProfile(
    profileId: 'test',
    businessName: 'Tienda sintética',
    currencyCode: 'COP',
    moneyScale: 2,
    timezone: 'America/Bogota',
    createdAtUtc: DateTime.utc(2026, 10, 21),
  );
  Future<EventsController> mount(
    WidgetTester tester,
    FakeEventsStore store, {
    double width = 1100,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = EventsController(store: store);
    await controller.load();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EventsPage(controller: controller, profile: profile),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('costless creation uses manual PVP and minimum zero', (
    tester,
  ) async {
    final store = FakeEventsStore();
    await mount(tester, store);
    await tester.enterText(
      find.byKey(const Key('event-name')),
      'Pasadía sintético',
    );
    await tester.enterText(find.byKey(const Key('event-pvp')), '15.000');
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('event-create')));
    await tester.pumpAndSettle();
    expect(store.commands.single.name, 'Pasadía sintético');
    expect(store.commands.single.minimumPeople, 0);
    expect(store.commands.single.pvpMinor, 1500000);
    expect(store.confirmed, hasLength(1));
    expect(find.textContaining('Ya está disponible'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('costs require minimum and account without submitting', (
    tester,
  ) async {
    final store = FakeEventsStore();
    await mount(tester, store);
    await tester.enterText(
      find.byKey(const Key('event-name')),
      'Torneo sintético',
    );
    await tester.enterText(find.byKey(const Key('event-pvp')), '10.000');
    await tester.enterText(find.byKey(const Key('event-fixed-cost')), '1.000');
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('event-create')));
    await tester.pumpAndSettle();
    expect(find.text('Con costos o productos, mínimo 1.'), findsOneWidget);
    expect(find.text('Selecciona Caja o Nequi.'), findsOneWidget);
    expect(store.commands, isEmpty);
  });
  testWidgets('multiple prize rows and narrow layout stay usable', (
    tester,
  ) async {
    final store = FakeEventsStore();
    await mount(tester, store, width: 400);
    await tester.ensureVisible(find.byKey(const Key('event-add-product')));
    await tester.tap(find.byKey(const Key('event-add-product')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('event-quantity-0')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const Key('event-add-product')));
    await tester.tap(find.byKey(const Key('event-add-product')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('event-quantity-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 400));
  });
  testWidgets('pending creation locks new form and recovers exact request', (
    tester,
  ) async {
    final store = FakeEventsStore();
    store.pending.add(
      PreparedEvent(
        CreateEvent(
          commandId: 'pending',
          name: 'Liga recuperada',
          minimumPeople: 0,
          fixedCostMinor: 0,
          pvpMinor: 500,
          occurredAtUtc: DateTime.utc(2026, 10, 21),
        ),
        const EventQuote(0, 0, 0),
      ),
    );
    await mount(tester, store);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('event-create')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Reintentar creación'));
    await tester.pumpAndSettle();
    expect(store.confirmed, ['pending']);
    expect(store.commands, isEmpty);
  });
  testWidgets('shell opens Events and refreshes when entering', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = FakeEventsStore(),
        workspace = FakeWorkspaceStore()..profile = profile;
    final controller = WorkspaceController(
      openSession: () async => WorkspaceSession(
        store: workspace,
        databasePath: 'synthetic',
        profileId: 'test',
        eventsStore: store,
      ),
    );
    await controller.initialize();
    await tester.pumpWidget(SanctumApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eventos'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('event-name')), findsOneWidget);
    expect(store.loads, 1);
    await tester.tap(find.text('Inicio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eventos'));
    await tester.pumpAndSettle();
    expect(store.loads, 2);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
