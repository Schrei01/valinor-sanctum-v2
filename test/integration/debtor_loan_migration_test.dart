import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/features/workspace/data/sqlite_workspace_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';
import 'package:valinor_sanctum_2/features/debtors/data/sqlite_debtors_store.dart';
import 'package:valinor_sanctum_2/features/debtors/domain/debtors_store.dart';
import '../support/released_v15_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'v21 upgrade backs up and preserves old debts, payments and durable requests; loans survive reopening',
    () async {
      final root = await Directory(
        p.join(AppConfig.repositoryRootPath, 'tmp'),
      ).createTemp('loan-migration-');
      final path = p.join(root.path, 'sanctum2.sqlite3');
      AppDatabase? app;
      final at = DateTime.utc(2026, 11, 2, 18);
      try {
        app = await AppDatabase.open(path: path);
        await SqliteWorkspaceStore(app).createProfile(
          BusinessProfile(
            profileId: 'test',
            businessName: 'Sintética',
            currencyCode: 'COP',
            moneyScale: 0,
            timezone: 'America/Bogota',
            createdAtUtc: at,
          ),
        );
        var store = SqliteDebtorsStore(app, synthetic: true);
        await store.load();
        await store.prepare(
          DebtorCommand(
            commandId: 'person',
            kind: 'create',
            name: 'Ana',
            amountMinor: 12000,
            previousSource: PreviousDebtSource.additional,
            occurredAtUtc: at,
          ),
        );
        final person = await store.confirm('person');
        await store.prepare(
          DebtorCommand(
            commandId: 'pay-before',
            kind: 'payment',
            debtorId: person,
            amountMinor: 2000,
            paymentOptionId: 'quick-default:EFECTIVO',
            occurredAtUtc: at,
          ),
        );
        await store.confirm('pay-before');
        await store.prepare(
          DebtorCommand(
            commandId: 'pending-payment',
            kind: 'payment',
            debtorId: person,
            amountMinor: 1000,
            paymentOptionId: 'quick-default:NEQUI',
            occurredAtUtc: at,
          ),
        );
        await app.database.transaction(restoreReleasedV21ForFixture);
        final oldTables = await app.database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
        );
        final oldColumns = <String, List<String>>{},
            rows = <String, List<String>>{};
        for (final t in oldTables) {
          final name = t['name'] as String;
          oldColumns[name] = (await app.database.rawQuery(
            'PRAGMA table_info($name)',
          )).map((c) => c['name'] as String).toList();
          rows[name] = (await app.database.query(name)).map(jsonEncode).toList()
            ..sort();
        }
        await app.close();
        app = null;
        app = await AppDatabase.open(path: path);
        expect(await app.database.getVersion(), AppDatabase.schemaVersion);
        for (final name in oldColumns.keys) {
          final current = (await app.database.query(
            name,
            columns: oldColumns[name],
            where: name == 'schema_migrations' ? 'version<=21' : null,
          )).map(jsonEncode).toList()..sort();
          expect(current, rows[name], reason: name);
        }
        expect(await app.database.query('debtor_loans'), isEmpty);
        expect(
          (await app.database.query(
            'debtor_receivables',
          )).every((r) => r['loan_document_id'] == null),
          isTrue,
        );
        final backups = root
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.contains('backup'))
            .toList();
        expect(backups, isNotEmpty);
        store = SqliteDebtorsStore(app, synthetic: true);
        expect(
          (await store.load()).pending.single.command.commandId,
          'pending-payment',
        );
        await store.confirm('pending-payment');
        await store.prepare(
          DebtorCommand(
            commandId: 'loan-after',
            kind: 'loan',
            debtorId: person,
            amountMinor: 10000,
            paymentOptionId: 'investment',
            occurredAtUtc: at.add(const Duration(minutes: 1)),
          ),
        );
        await app.close();
        app = null;
        app = await AppDatabase.open(path: path);
        store = SqliteDebtorsStore(app, synthetic: true);
        expect((await store.load()).pending.single.command.kind, 'loan');
        await store.confirm('loan-after');
        await app.close();
        app = null;
        app = await AppDatabase.open(path: path);
        store = SqliteDebtorsStore(app, synthetic: true);
        expect((await store.load()).debtors.single.balanceMinor, 19000);
        await store.confirm('loan-after');
        expect((await store.load()).debtors.single.balanceMinor, 19000);
        expect(
          await app.database.rawQuery('PRAGMA foreign_key_check'),
          isEmpty,
        );
      } finally {
        await app?.close();
        if (!p.isWithin(
          p.join(AppConfig.repositoryRootPath, 'tmp'),
          root.path,
        )) {
          throw StateError('Unsafe test directory');
        }
        await root.delete(recursive: true);
      }
    },
  );
}
