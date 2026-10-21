import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/app/sanctum_app.dart';
import 'package:valinor_sanctum_2/features/treasury/domain/treasury_store.dart';
import 'package:valinor_sanctum_2/features/workspace/application/workspace_controller.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/workspace_store.dart';

import '../support/fake_treasury_store.dart';
import '../support/fake_treasury_operation_store.dart';
import '../support/fake_workspace_store.dart';

void main() {
  testWidgets('Treasury replaces Payments and refreshes on section entry', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final workspace = FakeWorkspaceStore()
      ..profile = BusinessProfile(
        profileId: 'test',
        businessName: 'Ludoteca sintética',
        currencyCode: 'COP',
        moneyScale: 2,
        timezone: 'America/Bogota',
        createdAtUtc: DateTime.utc(2026, 10, 20),
      );
    TreasurySnapshot snapshot(int cash) => TreasurySnapshot(
      accounts: [
        TreasuryAccount(
          id: 'cash',
          name: 'Caja',
          role: TreasuryAccountRole.cash,
          balanceMinor: cash,
        ),
        const TreasuryAccount(
          id: 'nequi',
          name: 'Nequi',
          role: TreasuryAccountRole.nequi,
          balanceMinor: 5000,
        ),
        const TreasuryAccount(
          id: 'reserve',
          name: 'Caja mayor',
          role: TreasuryAccountRole.reserve,
          balanceMinor: 90000,
        ),
      ],
      receivablesMinor: 70000,
      movements: const [],
    );
    final treasury = FakeTreasuryStore(snapshot: snapshot(10000));
    final operations = FakeTreasuryOperationStore();
    final controller = WorkspaceController(
      openSession: () async => WorkspaceSession(
        store: workspace,
        databasePath: 'perfil-sintetico/sanctum2.sqlite3',
        profileId: 'test',
        treasuryStore: treasury,
        treasuryOperationStore: operations,
      ),
    );
    await controller.initialize();
    await tester.pumpWidget(SanctumApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.text('Pagos'), findsNothing);
    await tester.tap(find.text('Tesorería'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('treasury-balance-cash')), findsOneWidget);
    expect(find.byKey(const Key('treasury-register-expense')), findsOneWidget);
    expect(find.byKey(const Key('treasury-transfer')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('treasury-amount-total'))).data,
      'COP 150,00',
    );
    await tester.tap(find.text('Inicio'));
    await tester.pumpAndSettle();
    treasury.snapshot = snapshot(20000);
    final previousLoads = treasury.loadCalls;
    final previousOperationLoads = operations.loadCalls;
    await tester.tap(find.text('Tesorería'));
    await tester.pumpAndSettle();
    expect(treasury.loadCalls, greaterThan(previousLoads));
    expect(operations.loadCalls, greaterThan(previousOperationLoads));
    expect(
      tester.widget<Text>(find.byKey(const Key('treasury-amount-total'))).data,
      'COP 250,00',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
