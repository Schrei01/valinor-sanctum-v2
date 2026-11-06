import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/features/workspace/data/sqlite_workspace_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';
import 'package:valinor_sanctum_2/features/stock_intake/data/sqlite_stock_intake_store.dart';
import 'package:valinor_sanctum_2/features/stock_intake/domain/stock_intake_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_operation_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_store.dart';
import 'package:valinor_sanctum_2/features/reports/data/sqlite_reports_store.dart';
import 'package:valinor_sanctum_2/features/reports/domain/reports_store.dart';
import 'package:valinor_sanctum_2/features/treasury/domain/treasury_operation_store.dart';
import '../support/released_v15_fixture.dart';

Future<Map<String, String>> facts(DatabaseExecutor db) async => {
  for (final t in await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
  ))
    t['name'] as String: jsonEncode(
      (await db.query(t['name'] as String)).map(jsonEncode).toList()..sort(),
    ),
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final spec in [
    ('EFECTIVO', false),
    ('NEQUI', false),
    ('EFECTIVO', true),
  ]) {
    final option = spec.$1, futureVoidedExpense = spec.$2;
    test(
      'v22 pending $option purchase recovers once after voided expense is excluded by v23 (future void: $futureVoidedExpense)',
      () async {
        final folder = await Directory(
          p.join(AppConfig.repositoryRootPath, 'tmp'),
        ).createTemp('voided-purchase-');
        final path = p.join(folder.path, 'sanctum2.sqlite3');
        AppDatabase? app;
        try {
          app = await AppDatabase.open(path: path);
          await SqliteWorkspaceStore(app).createProfile(
            BusinessProfile(
              profileId: 'test',
              businessName: 'Sintética',
              currencyCode: 'COP',
              moneyScale: 0,
              timezone: 'America/Bogota',
              createdAtUtc: DateTime.utc(2026, 10, 20),
            ),
          );
          var intake = SqliteStockIntakeStore(app, synthetic: true);
          await intake.ensureDefaults();
          await intake.recordOpeningBalance(
            CashOpeningCommand(
              commandId: 'opening',
              paymentOptionId: 'quick-default:$option',
              amountMinor: 100000,
              occurredAtUtc: DateTime.utc(2026, 10, 20, 8),
            ),
          );
          final operations = SqliteTreasuryOperationStore(app, synthetic: true);
          await operations.ensureDefaults();
          final account =
              (await app.database.query(
                    'quick_payment_options',
                    where: 'id=?',
                    whereArgs: ['quick-default:$option'],
                  )).single['cash_account_id']
                  as String;
          await operations.prepare(
            TreasuryOperationCommand(
              commandId: 'wrong-expense',
              kind: TreasuryOperationKind.expense,
              sourceAccountId: account,
              amountMinor: 70000,
              reason: 'Otro',
              occurredAtUtc: DateTime.utc(
                2026,
                10,
                20,
                futureVoidedExpense ? 11 : 9,
              ),
            ),
          );
          final expense = await operations.confirmPrepared('wrong-expense');
          // Reconstruct the exact supported database state from the owner's audited
          // cancellation: retain original lines and request; only void the document.
          await app.database.transaction((txn) async {
            final guards = await txn.rawQuery(
              "SELECT name,sql FROM sqlite_master WHERE type='trigger' AND name IN('documents_confirmed_no_update','documents_confirmed_no_conflicting_update')",
            );
            for (final g in guards) {
              await txn.execute('DROP TRIGGER ${g['name']}');
            }
            await txn.update(
              'business_documents',
              {'status': 'reversed'},
              where: 'id=?',
              whereArgs: [expense.documentId],
            );
            for (final g in guards) {
              await txn.execute(g['sql'] as String);
            }
          });
          final category = (await intake.load()).categories.first.id;
          await intake.prepare(
            StockIntakeCommand(
              commandId: 'pending',
              productId: 'hit',
              productName: 'Bebida sintética',
              categoryId: category,
              supplierName: 'Proveedor sintético',
              totalPurchasePriceMinor: 60000,
              listPriceMinor: 4000,
              quantity: 24,
              paymentOptionId: 'quick-default:$option',
              occurredAtUtc: DateTime.utc(2026, 10, 20, 10),
            ),
          );
          await app.database.transaction(restoreReleasedV22ForFixture);
          final before = await facts(app.database);
          await expectLater(
            intake.confirmPrepared('pending'),
            throwsA(
              predicate(
                (e) => e.toString().contains(
                  futureVoidedExpense
                      ? 'cannot predate a confirmed money movement'
                      : 'sufficient representable balance',
                ),
              ),
            ),
          );
          expect(
            await facts(app.database),
            before,
            reason: 'failed old confirmation rolls back every fact',
          );
          final canonical = (await app.database.query(
            'paid_purchase_requests',
          )).single['canonical_payload'];
          await app.close();
          app = null;
          app = await AppDatabase.open(path: path);
          expect(await app.database.getVersion(), AppDatabase.schemaVersion);
          final after = await facts(app.database);
          for (final name in before.keys.where(
            (n) => n != 'schema_migrations',
          )) {
            expect(after[name], before[name], reason: name);
          }
          expect(
            (await app.database.query(
              'paid_purchase_requests',
            )).single['canonical_payload'],
            canonical,
          );
          final backup = (await Directory(
            p.join(folder.path, 'backups'),
          ).list().toList()).whereType<File>().single;
          final backupDb = await databaseFactoryFfi.openDatabase(
            backup.path,
            options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
          );
          try {
            expect(await facts(backupDb), before);
          } finally {
            await backupDb.close();
          }
          intake = SqliteStockIntakeStore(app, synthetic: true);
          final result = await intake.confirmPrepared('pending');
          final committed = await facts(app.database);
          expect(
            (await intake.confirmPrepared('pending')).paymentDocumentId,
            result.paymentDocumentId,
          );
          expect(await facts(app.database), committed);
          final data = await intake.load();
          expect(data.stock.single.quantity, 24);
          expect(data.stock.single.totalCostMinor, 60000);
          expect(data.entries.single.totalCostMinor, 60000);
          final treasury = await SqliteTreasuryStore(app).load();
          expect(
            option == 'EFECTIVO' ? treasury.cashMinor : treasury.nequiMinor,
            40000,
          );
          final report = await SqliteReportsStore(app).load(
            ReportPeriod(
              start: DateTime.utc(2026, 10, 20),
              end: DateTime.utc(2026, 10, 20),
            ),
          );
          expect(report.outflowTotals.totalMinor, 60000);
          expect(report.operatingExpensesMinor, 0);
          expect(report.salesMinor, 0);
          expect(
            data.paymentOptions
                .singleWhere((o) => o.id == 'quick-default:$option')
                .balanceMinor,
            40000,
          );
          expect(
            (await app.database.query(
              'business_documents',
              where: 'id=?',
              whereArgs: [expense.documentId],
            )).single['status'],
            'reversed',
          );
          expect(
            await app.database.rawQuery('PRAGMA foreign_key_check'),
            isEmpty,
          );
        } finally {
          await app?.close();
          if (!p.isWithin(
            p.join(AppConfig.repositoryRootPath, 'tmp'),
            folder.path,
          )) {
            throw StateError('Unsafe test cleanup');
          }
          await folder.delete(recursive: true);
        }
      },
    );
  }
}
