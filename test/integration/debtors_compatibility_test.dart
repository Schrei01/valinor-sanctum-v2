import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/schema.dart';
import 'package:valinor_sanctum_2/features/debtors/data/sqlite_debtors_store.dart';
import 'package:valinor_sanctum_2/features/debtors/domain/debtors_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/data/sqlite_quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/sales/data/sqlite_sales_store.dart';
import 'package:valinor_sanctum_2/features/sales/domain/sales_store.dart';
import '../support/register_debtor.dart';
import 'quick_sales_store_test.dart' show fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final at = DateTime.utc(2026, 10, 19, 16);
  test(
    'historical credit is explicitly assigned without changing financial facts',
    () async {
      final app = await AppDatabase.open(path: inMemoryDatabasePath);
      addTearDown(app.close);
      await fixture(app);
      final sales = SqliteSalesStore(app, synthetic: true);
      await sales.saveDraft(
        SaveSaleDraft(
          id: 'old',
          label: 'Cuenta histórica',
          customerName: 'Nombre anterior',
          expectedRevision: 0,
          lines: [
            SaleDraftLine(
              productId: 'product',
              quantity: 1,
              unitPriceMinor: 10000,
            ),
          ],
        ),
      );
      await sales.prepareConfirmation(
        commandId: 'old-sale',
        draftId: 'old',
        expectedRevision: 1,
        occurredAtUtc: at,
        dueDate: '2026-10-20',
      );
      await sales.confirmPrepared('old-sale');
      final store = SqliteDebtorsStore(app, synthetic: true),
          person = await registerDebtor(app, 'Persona identificada');
      final prior = <String, String>{
        for (final t in [
          'sales',
          'sale_lines',
          'customer_receivables',
          'journal_entries',
          'journal_lines',
          'inventory_movements',
        ])
          t: jsonEncode(await app.database.query(t)),
      };
      final charge = (await store.load()).charges.single;
      await store.prepare(
        DebtorCommand(
          commandId: 'assign',
          kind: 'assign',
          debtorId: person,
          receivableId: charge.receivableId,
          occurredAtUtc: at,
        ),
      );
      await store.confirm('assign');
      expect((await store.load()).debtors.single.balanceMinor, 10000);
      for (final t in prior.keys) {
        expect(jsonEncode(await app.database.query(t)), prior[t]);
      }
      await expectLater(
        store.prepare(
          DebtorCommand(
            commandId: 'assign-again',
            kind: 'assign',
            debtorId: person,
            receivableId: charge.receivableId,
            occurredAtUtc: at,
          ),
        ),
        throwsA(isA<DebtorsValidationException>()),
      );
    },
  );
  test(
    'v12 prepared credit survives v13, confirms and replays with unchanged canonical',
    () async {
      final source = await AppDatabase.open(path: inMemoryDatabasePath);
      addTearDown(source.close);
      await fixture(source);
      final quick = SqliteQuickSalesStore(source, synthetic: true);
      final person = await registerDebtor(source, 'Cliente sintético');
      await quick.saveAccount(
        SaveQuickSaleAccount(
          id: 'account',
          label: 'Cuenta previa',
          customerName: 'Cliente sintético',
          debtorId: person,
          expectedRevision: 0,
          lines: const [
            QuickSaleLine(
              id: 'line',
              productId: 'product',
              quantityText: '1',
              unitPriceMinor: 10000,
              paymentOptionId: QuickPaymentOption.creditId,
            ),
          ],
        ),
      );
      await quick.prepareSale(
        commandId: 'prior-credit',
        accountId: 'account',
        expectedRevision: 1,
        occurredAtUtc: at,
      );
      final request = Map<String, Object?>.from(
        (await source.database.query('quick_sale_requests')).single,
      );
      final payload =
          jsonDecode(request['canonical_payload'] as String)
              as Map<String, dynamic>;
      payload['version'] = 2;
      payload.remove('debtorId');
      request['canonical_payload'] = jsonEncode(payload);
      final folder = Directory(
        'tmp/tests/debtors-migration-${InventoryIds.next()}',
      )..createSync(recursive: true);
      final dbPath = File('${folder.path}/legacy.sqlite3').absolute.path;
      final old = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      for (final statements in [
        DatabaseSchema.statements,
        DatabaseSchema.migration2Statements,
        DatabaseSchema.migration3Statements,
        DatabaseSchema.migration4Statements,
        DatabaseSchema.migration5Statements,
        DatabaseSchema.migration6Statements,
        DatabaseSchema.migration7Statements,
        DatabaseSchema.migration8Statements,
        DatabaseSchema.migration9Statements,
        DatabaseSchema.migration10Statements,
        DatabaseSchema.migration11Statements,
        DatabaseSchema.migration12Statements,
      ].indexed) {
        for (final sql in statements.$2) {
          await old.execute(sql);
        }
        final objects = await old.rawQuery(
          "SELECT type,name,tbl_name,sql FROM sqlite_master WHERE substr(name,1,7)<>'sqlite_' ORDER BY type,name",
        );
        await old.insert('schema_migrations', {
          'version': statements.$1 + 1,
          'name': DatabaseSchema.nameForVersion(statements.$1 + 1),
          'migration_checksum': DatabaseSchema.checksumForVersion(
            statements.$1 + 1,
          ),
          'schema_checksum': DatabaseSchema.checksum(
            jsonEncode(
              objects
                  .map((o) => [o['type'], o['name'], o['tbl_name'], o['sql']])
                  .toList(),
            ),
          ),
          'applied_at_utc': at.toIso8601String(),
        });
      }
      await old.execute(
        'PRAGMA application_id = ${DatabaseSchema.applicationId}',
      );
      await old.execute('PRAGMA user_version = 12');
      for (final table in [
        'actors',
        'app_profile',
        'ledger_accounts',
        'categories',
        'counterparties',
        'catalog_items',
        'cash_accounts',
        'payment_methods',
        'quick_payment_options',
        'quick_sales_accounts',
        'quick_sales_lines',
      ]) {
        for (final row in await source.database.query(table)) {
          final copy = Map<String, Object?>.from(row);
          if (table == 'quick_sales_accounts') {
            copy.remove('debtor_id');
            copy.remove('payment_mode');
            copy.remove('account_payment_option_id');
            copy.remove('payment_split_basis');
            copy['status'] = 'open';
          }
          if (table == 'quick_sales_lines') {
            // This fixture reconstructs v12 before the split column existed.
            copy.remove('payment_split_json');
          }
          await old.insert(table, copy);
        }
      }
      await old.insert('quick_sale_requests', request);
      await old.update('quick_sales_accounts', {
        'status': 'prepared',
      }, where: "id='account'");
      await old.close();
      var migrated = await AppDatabase.open(path: dbPath);
      try {
        expect(await migrated.database.query('legacy_quick_debtor_requests'), [
          {'command_id': 'prior-credit'},
        ]);
        expect(
          (await migrated.database.query(
            'quick_sale_requests',
          )).single['canonical_payload'],
          request['canonical_payload'],
        );
        // Supply synthetic stock after the migration; the pending request itself is unchanged.
        await SqliteInventoryStore(migrated, synthetic: true).receivePurchase(
          ReceiptCommand(
            commandId: 'stock',
            supplierId: 'supplier',
            occurredAtUtc: at.subtract(const Duration(hours: 1)),
            dueDate: '2026-10-20',
            lines: const [
              ReceiptLineInput(
                productId: 'product',
                quantity: 2,
                totalCostMinor: 2000,
              ),
            ],
          ),
        );
        final store = SqliteQuickSalesStore(migrated, synthetic: true);
        final result = await store.confirmPrepared('prior-credit');
        expect(result.creditMinor, 10000);
        expect(result.debtorId, isNull);
        await migrated.close();
        migrated = await AppDatabase.open(path: dbPath);
        final replay = await SqliteQuickSalesStore(
          migrated,
          synthetic: true,
        ).confirmPrepared('prior-credit');
        expect(replay.saleDocumentId, result.saleDocumentId);
        final debtors = SqliteDebtorsStore(migrated, synthetic: true);
        expect((await debtors.load()).charges.single.debtorId, isNull);
        expect(
          await migrated.database.rawQuery('PRAGMA foreign_key_check'),
          isEmpty,
        );
      } finally {
        await migrated.close();
      }
    },
  );
  test(
    'person debt and prepared payment recover across actual file reopen without duplicate money',
    () async {
      final folder = Directory(
        'tmp/tests/debtors-reopen-${InventoryIds.next()}',
      )..createSync(recursive: true);
      final dbPath = File('${folder.path}/debtors.sqlite3').absolute.path;
      var app = await AppDatabase.open(path: dbPath);
      try {
        await fixture(app);
        var store = SqliteDebtorsStore(app, synthetic: true);
        await store.load();
        await store.prepare(
          DebtorCommand(
            commandId: 'person',
            kind: 'create',
            name: 'Persona sintética',
            amountMinor: 10000,
            previousSource: PreviousDebtSource.additional,
            occurredAtUtc: at,
          ),
        );
        final id = await store.confirm('person');
        await store.prepare(
          DebtorCommand(
            commandId: 'payment',
            kind: 'payment',
            debtorId: id,
            amountMinor: 4000,
            paymentOptionId: 'quick-default:NEQUI',
            occurredAtUtc: at.add(const Duration(hours: 1)),
          ),
        );
        await app.close();
        app = await AppDatabase.open(path: dbPath);
        store = SqliteDebtorsStore(app, synthetic: true);
        expect(
          (await store.load()).pending.single.command.commandId,
          'payment',
        );
        expect(await store.confirm('payment'), id);
        await app.close();
        app = await AppDatabase.open(path: dbPath);
        store = SqliteDebtorsStore(app, synthetic: true);
        expect(await store.confirm('payment'), id);
        final data = await store.load();
        expect(data.debtors.single.balanceMinor, 6000);
        expect(data.payments, hasLength(1));
        expect(
          await app.database.query('debtor_payment_allocations'),
          hasLength(1),
        );
      } finally {
        await app.close();
      }
    },
  );
}
