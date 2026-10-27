import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/app/sanctum_app.dart';
import 'package:valinor_sanctum_2/features/reports/domain/reports_store.dart';
import 'package:valinor_sanctum_2/features/workspace/application/workspace_controller.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/workspace_store.dart';
import '../support/fake_workspace_store.dart';

class _ReportsSpy implements ReportsStore {
  int loads = 0;
  @override
  Future<ReportsSnapshot> load(ReportPeriod period) async {
    loads++;
    return ReportsSnapshot(
      period: period,
      accounts: const [],
      movements: const [],
      sales: const [],
      transfers: const [],
      expenses: const [],
      debtChanges: const [],
      events: const [],
      debtOpeningMinor: 0,
      debtClosingMinor: 0,
      coverageStartUtc: null,
      openingBalancesKnown: true,
      closingBalancesKnown: true,
      warnings: const [],
    );
  }
}

void main() {
  testWidgets(
    'Reportes loads on section entry and refreshes without Inicio or Sistema entries',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final reports = _ReportsSpy();
      final workspace = FakeWorkspaceStore()
        ..profile = BusinessProfile(
          profileId: 'test',
          businessName: 'Ludoteca sintética',
          currencyCode: 'COP',
          moneyScale: 0,
          timezone: 'America/Bogota',
          createdAtUtc: DateTime.utc(2026, 10, 21),
        );
      final controller = WorkspaceController(
        openSession: () async => WorkspaceSession(
          store: workspace,
          databasePath: 'synthetic',
          profileId: 'test',
          reportsStore: reports,
        ),
      );
      await controller.initialize();
      await tester.pumpWidget(SanctumApp(controller: controller));
      await tester.pumpAndSettle();
      expect(reports.loads, 0);
      await tester.ensureVisible(find.text('Reportes'));
      await tester.tap(find.text('Reportes'));
      await tester.pumpAndSettle();
      expect(reports.loads, 1);
      expect(find.text('Reportes'), findsNWidgets(2));
      await tester.ensureVisible(find.text('Catálogo'));
      await tester.tap(find.text('Catálogo'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Reportes'));
      await tester.tap(find.text('Reportes'));
      await tester.pumpAndSettle();
      expect(reports.loads, 2);
      await tester.ensureVisible(find.text('Catálogo'));
      await tester.tap(find.text('Catálogo'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('database-path')), findsNothing);
      expect(find.text('Inicio'), findsNothing);
      expect(find.text('Sistema'), findsNothing);
      expect(find.text('Ventas'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
