import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/features/treasury/domain/legacy_treasury_snapshot.dart';
import 'package:valinor_sanctum_2/features/treasury/presentation/legacy_treasury_history.dart';

void main() {
  const movements = [
    LegacyTreasuryMovement(
      sourceTable: 'movimientos',
      sourceRowId: 3,
      type: 'ingreso',
      fromRole: null,
      toRole: 'cash',
      amountMinor: 12345,
      reason: 'Ingreso sintético anterior',
      sourceDateRaw: '2026-10-20T16:20:00.000',
    ),
    LegacyTreasuryMovement(
      sourceTable: 'transfermovements',
      sourceRowId: 2,
      type: 'transferencia',
      fromRole: 'cash',
      toRole: 'nequi',
      amountMinor: 5600,
      reason: 'Traspaso sintético anterior',
      sourceDateRaw: '2026-10-20T16:10:00.000',
    ),
    LegacyTreasuryMovement(
      sourceTable: 'movimientos',
      sourceRowId: 1,
      type: 'egreso',
      fromRole: 'reserve',
      toRole: null,
      amountMinor: 2500,
      reason: 'Egreso sintético anterior',
      sourceDateRaw: '2026-10-20T16:00:00.000',
    ),
  ];

  LegacyTreasurySnapshot snapshot({
    List<LegacyTreasuryMovement> rows = movements,
  }) => LegacyTreasurySnapshot(
    sourceName: 'copia-sintetica.db',
    sourceSha256: List.filled(64, 'a').join(),
    extractedAtUtc: DateTime.utc(2026, 10, 20, 22),
    moneyScale: 2,
    balances: const [
      LegacyTreasuryBalance(
        role: 'cash',
        sourceTable: 'cash',
        sourceRowId: 1,
        sourceDateRaw: '2026-10-20T16:20:00.000',
        amountMinor: 0,
      ),
      LegacyTreasuryBalance(
        role: 'nequi',
        sourceTable: 'nequi',
        sourceRowId: 1,
        sourceDateRaw: '2026-10-20T16:20:00.000',
        amountMinor: 0,
      ),
      LegacyTreasuryBalance(
        role: 'reserve',
        sourceTable: 'caja_mayor',
        sourceRowId: 1,
        sourceDateRaw: '2026-10-20T16:20:00.000',
        amountMinor: -100,
      ),
      LegacyTreasuryBalance(
        role: 'receivables',
        sourceTable: 'deudas',
        sourceRowId: 1,
        sourceDateRaw: '2026-10-20T16:20:00.000',
        amountMinor: 200,
      ),
    ],
    movements: rows,
  );

  Future<void> open(
    WidgetTester tester,
    _FakeLegacyTreasuryStore store, {
    Size size = const Size(920, 850),
    bool settle = true,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: LegacyTreasuryHistory(store: store),
          ),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  Future<void> expand(WidgetTester tester) async {
    await tester.tap(find.text('Historial de la copia'));
    await tester.pumpAndSettle();
  }

  Future<void> chooseAccount(WidgetTester tester, String name) async {
    final filter = find.byKey(const Key('legacy-treasury-account-filter'));
    await tester.ensureVisible(filter);
    await tester.tap(filter);
    await tester.pumpAndSettle();
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }

  testWidgets('a missing source leaves no extra history controls', (
    tester,
  ) async {
    final store = _FakeLegacyTreasuryStore();
    await open(tester, store);
    expect(store.loadCalls, 1);
    expect(find.text('Historial de la copia'), findsNothing);
    expect(find.byType(DataTable), findsNothing);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history starts folded and preserves raw source dates', (
    tester,
  ) async {
    await open(tester, _FakeLegacyTreasuryStore(snapshot: snapshot()));
    expect(find.text('Historial de la copia'), findsOneWidget);
    expect(
      find.text(
        'Consulta histórica. Estos movimientos ya están incluidos en los saldos iniciales.',
      ),
      findsOneWidget,
    );
    expect(find.byType(DataTable), findsNothing);
    await expand(tester);
    expect(find.text('2026-10-20T16:20:00.000'), findsOneWidget);
    expect(find.text('+COP 123,45'), findsOneWidget);
    expect(find.text('COP -25,00'), findsOneWidget);
    expect(find.text('COP 56,00'), findsOneWidget);
    expect(find.text('Caja → Nequi'), findsOneWidget);
    expect(find.text('Traspaso'), findsOneWidget);
    final table = tester.widget<DataTable>(
      find.byKey(const Key('legacy-treasury-movements')),
    );
    expect(table.rows.length, 3);
    expect(
      table.rows.first.key,
      const Key('legacy-treasury-movement-movimientos-3'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a transfer belongs to both account filters without duplication',
    (tester) async {
      await open(tester, _FakeLegacyTreasuryStore(snapshot: snapshot()));
      await expand(tester);
      await chooseAccount(tester, 'Caja');
      expect(find.text('Ingreso sintético anterior'), findsOneWidget);
      expect(find.text('Traspaso sintético anterior'), findsOneWidget);
      expect(find.text('Egreso sintético anterior'), findsNothing);
      await chooseAccount(tester, 'Nequi');
      expect(find.text('Traspaso sintético anterior'), findsOneWidget);
      expect(find.text('Ingreso sintético anterior'), findsNothing);
      await chooseAccount(tester, 'Caja mayor');
      expect(find.text('Egreso sintético anterior'), findsOneWidget);
      expect(find.text('Traspaso sintético anterior'), findsNothing);
      await chooseAccount(tester, 'Deudas');
      expect(
        find.text('La copia no contiene movimientos para esta cuenta.'),
        findsOneWidget,
      );
      await chooseAccount(tester, 'Todas las cuentas de la copia');
      expect(find.text('Traspaso sintético anterior'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('initial loading is visible and read failure can be retried', (
    tester,
  ) async {
    final pending = Completer<LegacyTreasurySnapshot?>();
    final store = _FakeLegacyTreasuryStore()..pendingLoad = pending;
    await open(tester, store, settle: false);
    expect(find.byKey(const Key('legacy-treasury-loading')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(store.loadCalls, 1);
    pending.completeError(StateError('synthetic read failure'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('legacy-treasury-load-error')), findsOneWidget);
    expect(find.byType(DataTable), findsNothing);
    store.pendingLoad = null;
    store.snapshot = snapshot();
    await tester.tap(find.text('Actualizar'));
    await tester.pumpAndSettle();
    expect(store.loadCalls, 2);
    expect(find.text('Historial de la copia'), findsOneWidget);
    expect(find.byKey(const Key('legacy-treasury-load-error')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refresh keeps selection and prevents overlapping reads', (
    tester,
  ) async {
    final store = _FakeLegacyTreasuryStore(snapshot: snapshot());
    await open(tester, store);
    await expand(tester);
    await chooseAccount(tester, 'Nequi');
    final pending = Completer<LegacyTreasurySnapshot?>();
    store.pendingLoad = pending;
    final refresh = find.byKey(const Key('legacy-treasury-refresh'));
    await tester.ensureVisible(refresh);
    await tester.tap(refresh);
    await tester.pump();
    expect(store.loadCalls, 2);
    expect(tester.widget<OutlinedButton>(refresh).onPressed, isNull);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Traspaso sintético anterior'), findsOneWidget);
    pending.complete(snapshot(rows: const []));
    await tester.pumpAndSettle();
    expect(
      find.text('La copia no contiene movimientos para esta cuenta.'),
      findsOneWidget,
    );
    expect(tester.widget<OutlinedButton>(refresh).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a refresh failure keeps the last history with a stale warning', (
    tester,
  ) async {
    final store = _FakeLegacyTreasuryStore(snapshot: snapshot());
    await open(tester, store);
    await expand(tester);
    store.failure = StateError('synthetic refresh failure');
    final refresh = find.byKey(const Key('legacy-treasury-refresh'));
    await tester.ensureVisible(refresh);
    await tester.tap(refresh);
    await tester.pumpAndSettle();
    expect(find.text('Ingreso sintético anterior'), findsOneWidget);
    expect(find.textContaining('puede estar desactualizada'), findsOneWidget);
    store.failure = null;
    store.snapshot = snapshot(rows: const []);
    await tester.ensureVisible(refresh);
    await tester.tap(refresh);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('legacy-treasury-load-error')), findsNothing);
    expect(
      find.text('La copia no contiene movimientos históricos.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow history paginates and resets its page when filtering', (
    tester,
  ) async {
    final rows = List.generate(
      27,
      (index) => LegacyTreasuryMovement(
        sourceTable: 'movimientos',
        sourceRowId: 27 - index,
        type: 'ingreso',
        fromRole: null,
        toRole: 'cash',
        amountMinor: 100,
        reason: 'Movimiento sintético ${27 - index}',
        sourceDateRaw: '2026-10-20T16:20:00.000',
      ),
    );
    await open(
      tester,
      _FakeLegacyTreasuryStore(snapshot: snapshot(rows: rows)),
      size: const Size(360, 780),
    );
    await expand(tester);
    final table = find.byKey(const Key('legacy-treasury-movements'));
    expect(tester.widget<DataTable>(table).rows.length, 25);
    expect(find.text('1–25 de 27'), findsOneWidget);
    final next = find.byKey(const Key('legacy-treasury-next-page'));
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(tester.widget<DataTable>(table).rows.length, 2);
    expect(find.text('26–27 de 27'), findsOneWidget);
    await chooseAccount(tester, 'Nequi');
    expect(find.byType(DataTable), findsNothing);
    await chooseAccount(tester, 'Caja');
    expect(tester.widget<DataTable>(table).rows.length, 25);
    expect(find.text('1–25 de 27'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing source discards an older asynchronous result', (
    tester,
  ) async {
    final pending = Completer<LegacyTreasurySnapshot?>();
    final old = _FakeLegacyTreasuryStore()..pendingLoad = pending;
    await open(tester, old, settle: false);
    final replacement = _FakeLegacyTreasuryStore(
      snapshot: snapshot(rows: [movements.first]),
    );
    await open(tester, replacement);
    pending.complete(snapshot());
    await tester.pumpAndSettle();
    await expand(tester);
    expect(find.text('Ingreso sintético anterior'), findsOneWidget);
    expect(find.text('Traspaso sintético anterior'), findsNothing);
    expect(old.loadCalls, 1);
    expect(replacement.loadCalls, 1);
    expect(tester.takeException(), isNull);
  });
}

class _FakeLegacyTreasuryStore implements LegacyTreasuryStore {
  _FakeLegacyTreasuryStore({this.snapshot});

  LegacyTreasurySnapshot? snapshot;
  Object? failure;
  Completer<LegacyTreasurySnapshot?>? pendingLoad;
  int loadCalls = 0;

  @override
  Future<LegacyTreasurySnapshot?> load() async {
    loadCalls++;
    if (failure != null) throw failure!;
    if (pendingLoad != null) return pendingLoad!.future;
    return snapshot;
  }
}
