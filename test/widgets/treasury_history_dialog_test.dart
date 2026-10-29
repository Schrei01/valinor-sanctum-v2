import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/features/treasury/domain/legacy_treasury_snapshot.dart';
import 'package:valinor_sanctum_2/features/treasury/domain/treasury_store.dart';
import 'package:valinor_sanctum_2/features/treasury/presentation/treasury_history_dialog.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';

void main() {
  for (final width in [1200.0, 400.0]) {
    testWidgets(
      'one history preserves old and current movements, pagination and account filtering at $width',
      (t) async {
        await t.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => t.binding.setSurfaceSize(null));
        var fullLoads = 0;
        final old = _OldHistory();
        final profile = BusinessProfile(
          profileId: 'test',
          businessName: 'Sintética',
          currencyCode: 'COP',
          moneyScale: 0,
          timezone: 'America/Bogota',
          createdAtUtc: DateTime.utc(2026, 10, 20),
        );
        final current = TreasurySnapshot(
          accounts: const [
            TreasuryAccount(
              id: 'cash-id',
              name: 'Caja',
              role: TreasuryAccountRole.cash,
              balanceMinor: 50000,
            ),
          ],
          receivablesMinor: 0,
          movements: [
            for (var i = 0; i < 12; i++)
              TreasuryMovement(
                id: 'current-$i',
                cashAccountId: 'cash-id',
                accountName: 'Caja',
                documentId: 'd$i',
                occurredAtUtc: DateTime.utc(2026, 10, 29, 18, i),
                concept: 'Venta sintética $i',
                amountMinor: 1000,
              ),
          ],
        );
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => TreasuryHistoryDialog(
                      profile: profile,
                      legacyStore: old,
                      loadCurrent: () async {
                        fullLoads++;
                        return current;
                      },
                    ),
                  ),
                  child: const Text('Ver historial'),
                ),
              ),
            ),
          ),
        );
        await t.tap(find.text('Ver historial'));
        await t.pumpAndSettle();
        expect(find.text('Historial de movimientos'), findsOneWidget);
        expect(find.textContaining('13 movimientos'), findsOneWidget);
        expect(find.text('Historial de la copia'), findsNothing);
        await t.ensureVisible(find.byKey(const Key('history-next')));
        await t.tap(find.byKey(const Key('history-next')));
        await t.pumpAndSettle();
        expect(find.text('Compra anterior sintética'), findsOneWidget);
        expect(find.text('20/10/2026 · 3:20 PM'), findsOneWidget);
        await t.ensureVisible(find.byKey(const Key('history-account')));
        await t.tap(find.byKey(const Key('history-account')));
        await t.pumpAndSettle();
        await t.tap(find.text('Nequi').last);
        await t.pumpAndSettle();
        expect(find.textContaining('1 movimientos'), findsOneWidget);
        expect(find.text('Compra anterior sintética'), findsOneWidget);
        expect(find.text('Venta sintética 11'), findsNothing);
        expect(fullLoads, 1);
        expect(old.loads, 1);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('history read failure can be retried without reposting data', (
    t,
  ) async {
    var tries = 0;
    final profile = BusinessProfile(
      profileId: 'test',
      businessName: 'Sintética',
      currencyCode: 'COP',
      moneyScale: 0,
      timezone: 'America/Bogota',
      createdAtUtc: DateTime.utc(2026, 10, 20),
    );
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TreasuryHistoryDialog(
            profile: profile,
            loadCurrent: () async {
              if (tries++ == 0) throw StateError('synthetic');
              return TreasurySnapshot(
                accounts: const [],
                receivablesMinor: 0,
                movements: const [],
              );
            },
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(
      find.text('No se pudo cargar el historial completo.'),
      findsOneWidget,
    );
    await t.tap(find.text('Reintentar'));
    await t.pumpAndSettle();
    expect(find.text('Sin movimientos para estos filtros.'), findsOneWidget);
    expect(tries, 2);
    expect(t.takeException(), isNull);
  });
}

class _OldHistory implements LegacyTreasuryStore {
  int loads = 0;
  @override
  Future<LegacyTreasurySnapshot?> load() async {
    loads++;
    return LegacyTreasurySnapshot(
      sourceName: 'sintetica.db',
      sourceSha256: 'a' * 64,
      extractedAtUtc: DateTime.utc(2026, 10, 20),
      moneyScale: 0,
      balances: [
        for (final role in ['cash', 'nequi', 'reserve', 'receivables'])
          LegacyTreasuryBalance(
            role: role,
            sourceTable: LegacyTreasurySnapshot.sourceTables[role]!,
            sourceRowId: 1,
            sourceDateRaw: '2026-10-20T15:00:00',
            amountMinor: 0,
          ),
      ],
      movements: const [
        LegacyTreasuryMovement(
          sourceTable: 'movimientos',
          sourceRowId: 1,
          type: 'egreso',
          fromRole: 'nequi',
          toRole: null,
          amountMinor: 5000,
          reason: 'Compra anterior sintética',
          sourceDateRaw: '2026-10-20T15:20:00',
        ),
      ],
    );
  }
}
