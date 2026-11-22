import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/features/memberships/data/sqlite_membership_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/data/sqlite_quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/quick_sales_store.dart';
import '../support/released_v15_fixture.dart'
    show
        restoreReleasedV27ForFixture,
        restoreReleasedV28ForFixture,
        restoreReleasedV29ForFixture;
import 'quick_sales_store_test.dart' show fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final fromVersion in [27, 28, 29]) {
    test(
      'v$fromVersion migration preserves all prior rows and creates a verified automatic backup',
      () async {
        final folder = await Directory(
          p.join(AppConfig.repositoryRootPath, 'tmp'),
        ).createTemp('membership-migration-');
        final path = p.join(folder.path, 'sanctum2.sqlite3');
        AppDatabase? app;
        try {
          app = await AppDatabase.open(path: path);
          await fixture(app, moneyScale: 0);
          if (fromVersion == 29) {
            final members = SqliteMembershipStore(app, synthetic: true);
            final sales = SqliteQuickSalesStore(app, synthetic: true);
            await sales.ensureDefaults();
            await sales.ensureBulkProducts();
            final id = await members.savePerson(
              commandId: 'migration-person',
              name: 'Persona de migración',
              email: 'migration@example.com',
              birthDay: 29,
              birthMonth: 2,
            );
            final account = await sales.saveAccount(
              SaveQuickSaleAccount(
                id: 'membership-migration',
                label: 'Mensualidad',
                customerName: 'Persona de migración',
                debtorId: id,
                expectedRevision: 0,
                lines: [
                  const QuickSaleLine(
                    id: 'membership-migration-line',
                    productId: SqliteMembershipStore.productId,
                    unitPriceMinor: 109000,
                    paymentOptionId: 'quick-default:EFECTIVO',
                  ),
                ],
              ),
            );
            await sales.prepareSale(
              commandId: 'membership-migration-sale',
              accountId: account.id,
              expectedRevision: account.revision,
              occurredAtUtc: DateTime.now().toUtc(),
            );
            await sales.confirmPrepared('membership-migration-sale');
            expect(
              await app.database.query('membership_periods'),
              hasLength(1),
            );
            expect(
              await app.database.query('membership_voucher_grants'),
              hasLength(1),
            );
          }
          if (fromVersion == 27) {
            await restoreReleasedV27ForFixture(app.database);
          } else if (fromVersion == 28) {
            await restoreReleasedV28ForFixture(app.database);
          } else {
            await restoreReleasedV29ForFixture(app.database);
          }
          final tables = (await app.database.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name<>'schema_migrations' ORDER BY name",
          )).map((r) => r['name'] as String).toList();
          final snapshots = <String, String>{};
          String canonical(List<Map<String, Object?>> rows) =>
              jsonEncode(rows.map(jsonEncode).toList()..sort());
          for (final t in tables) {
            snapshots[t] = canonical(await app.database.query(t));
          }
          await app.close();
          app = await AppDatabase.open(path: path);
          expect(
            (await app.database.rawQuery(
              'PRAGMA user_version',
            )).single.values.single,
            30,
          );
          for (final t in tables) {
            final rows = await app.database.query(t);
            if (t == 'quick_sales_lines' && fromVersion < 29) {
              for (final row in rows) {
                if (fromVersion == 27) row.remove('membership_discount');
                row.remove('voucher_selected');
                row.remove('voucher_minor');
                row.remove('voucher_period_id');
              }
            }
            expect(canonical(rows), snapshots[t], reason: t);
          }
          expect(
            await app.database.rawQuery('PRAGMA foreign_key_check'),
            isEmpty,
          );
          expect(
            (await app.database.rawQuery(
              'PRAGMA integrity_check',
            )).single.values.single,
            'ok',
          );
          final backups = await Directory(
            p.join(folder.path, 'backups'),
          ).list().toList();
          expect(backups, hasLength(1));
          expect(backups.single.path, contains('.v$fromVersion.'));
          await app.close();
          app = await AppDatabase.open(path: path);
          expect(
            await Directory(p.join(folder.path, 'backups')).list().length,
            1,
          );
        } finally {
          await app?.close();
          if (!p.isWithin(
            p.join(AppConfig.repositoryRootPath, 'tmp'),
            await folder.resolveSymbolicLinks(),
          )) {
            throw StateError('Unsafe cleanup');
          }
          await folder.delete(recursive: true);
        }
      },
    );
  }
}
