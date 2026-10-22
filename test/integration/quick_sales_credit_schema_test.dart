import 'dart:convert';
import '../support/register_debtor.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/schema.dart';
import 'package:valinor_sanctum_2/features/quick_sales/data/sqlite_quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/quick_sales_store.dart';

import 'quick_sales_store_test.dart' show fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase app;
  late SqliteQuickSalesStore quick;
  setUp(() async {
    app = await AppDatabase.open(path: inMemoryDatabasePath);
    await fixture(app);
    quick = SqliteQuickSalesStore(app, synthetic: true);
    await quick.ensureDefaults();
  });
  tearDown(() => app.close());

  Future<void> save({bool mixed = false}) async {
    await quick.saveAccount(
      SaveQuickSaleAccount(
        id: 'account',
        label: 'Cuenta sintética',
        customerName: 'Cliente sintético',
        debtorId: await registerDebtor(app, 'Cliente sintético'),
        expectedRevision: 0,
        lines: [
          const QuickSaleLine(
            id: 'credit-line',
            productId: 'product',
            quantityText: '1',
            unitPriceMinor: 10000,
            paymentOptionId: QuickPaymentOption.creditId,
          ),
          if (mixed)
            QuickSaleLine(
              id: 'paid-line',
              productId: 'product',
              quantityText: '1',
              unitPriceMinor: 10000,
              paymentOptionId: 'quick-default:EFECTIVO',
            ),
        ],
      ),
    );
  }

  Future<void> prepare() => quick.prepareSale(
    commandId: 'parent',
    accountId: 'account',
    expectedRevision: 1,
    occurredAtUtc: DateTime.utc(2026, 10, 19, 16),
  );

  test(
    'v11 adds independent tender facts and defaults legacy drafts to paid',
    () async {
      expect(
        DatabaseSchema.nameForVersion(11),
        'quick_sales_customer_credit_v11',
      );
      expect(await app.database.query('quick_sale_line_tenders'), isEmpty);
      await app.database.insert('quick_sales_accounts', {
        'id': 'old-draft',
        'label': 'Borrador sintético',
        'revision': 1,
        'status': 'open',
        'updated_at_utc': '2026-10-19T15:00:00.000Z',
      });
      await app.database.insert('quick_sales_lines', {
        'id': 'old-line',
        'account_id': 'old-draft',
        'sequence': 0,
        'quantity_text': '',
      });
      expect(
        (await app.database.query(
          'quick_sales_accounts',
        )).single['customer_name'],
        '',
      );
      expect(
        (await app.database.query('quick_sales_lines')).single['is_credit'],
        0,
      );
      expect(await app.database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );

  test('credit draft identity cannot also reference a cash option', () async {
    await save();
    for (final change in [
      {'payment_option_id': 'quick-default:EFECTIVO'},
      {'is_credit': 2},
      {'is_credit': -1},
    ]) {
      await expectLater(
        app.database.update('quick_sales_lines', change),
        throwsA(isA<DatabaseException>()),
      );
    }
    await expectLater(
      app.database.insert('quick_sales_lines', {
        'id': 'forged',
        'account_id': 'account',
        'sequence': 1,
        'quantity_text': '1',
        'is_credit': 1,
        'payment_option_id': 'quick-default:NEQUI',
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test(
    'prepared credit freezes debtor and classification with the source draft',
    () async {
      await save();
      await prepare();
      for (final mutation in [
        () => app.database.update('quick_sales_accounts', {
          'customer_name': 'Otro cliente',
        }),
        () => app.database.update('quick_sales_lines', {'is_credit': 0}),
        () => app.database.update('quick_sales_lines', {
          'payment_option_id': 'quick-default:EFECTIVO',
        }),
        () => app.database
            .update('quick_sale_requests', {'status': 'executing'})
            .then(
              (_) => app.database.update('quick_sale_requests', {
                'status': 'confirmed',
              }),
            ),
      ]) {
        await expectLater(mutation(), throwsA(isA<DatabaseException>()));
      }
      expect(await app.database.query('sales'), isEmpty);
      expect(await app.database.query('quick_sale_line_tenders'), isEmpty);
    },
  );

  test(
    'raw v2 preparation rejects forged customer, totals, line and monetary identity',
    () async {
      await save();
      await prepare();
      final db = app.database;
      final original = (await db.query('quick_sale_requests')).single;
      await db.update('quick_sale_requests', {
        'status': 'rejected',
        'rejection_reason': 'Prueba sintética',
      });
      await db.update('quick_sale_requests', {'status': 'cancelled'});
      await db.update('quick_sales_accounts', {
        'status': 'open',
        'revision': 2,
      });
      final canonical = original['canonical_payload'] as String;
      Map<String, dynamic> payload() =>
          jsonDecode(canonical) as Map<String, dynamic>;
      final changes = <void Function(Map<String, dynamic>)>[
        (p) => p['customerName'] = '',
        (p) => p['customerName'] = 'Otro cliente',
        (p) => p['creditMinor'] = 9999,
        (p) => p['paidMinor'] = 1,
        (p) => p['totalMinor'] = 9999,
        (p) => p['version'] = 1,
        (p) => p['lines'] = [],
        (p) => (p['lines'] as List).first['quantity'] = 2,
        (p) => (p['lines'] as List).first['isCredit'] = false,
        (p) => (p['lines'] as List).first['paymentOptionId'] =
            'quick-default:EFECTIVO',
        (p) => (p['lines'] as List).first['cashAccountId'] = 'ghost-cash',
        (p) => (p['lines'] as List).first['productName'] = 'Otro producto',
        (p) => (p['lines'] as List).first['totalMinor'] = 20000,
      ];
      for (var i = 0; i < changes.length; i++) {
        final changed = payload();
        changes[i](changed);
        await expectLater(
          db.insert('quick_sale_requests', {
            ...original,
            'command_id': 'forged-$i',
            'sale_command_id': 'forged-sale-$i',
            'collection_command_id': 'forged-collection-$i',
            'legacy_draft_id': 'forged-draft-$i',
            'account_revision': 2,
            'status': 'prepared',
            'canonical_payload': jsonEncode(changed),
          }),
          throwsA(isA<DatabaseException>()),
          reason: 'Forgery $i',
        );
      }
      await expectLater(
        db.insert('quick_sale_requests', {
          ...original,
          'command_id': 'invalid-json',
          'sale_command_id': 'invalid-sale',
          'collection_command_id': 'invalid-collection',
          'legacy_draft_id': 'invalid-draft',
          'account_revision': 2,
          'canonical_payload': '{',
        }),
        throwsA(isA<DatabaseException>()),
      );
      // The unmodified snapshot still prepares after the same cancellation. This
      // makes sure rejection above was caused by each forged input, not stale IDs.
      await db.insert('quick_sale_requests', {
        ...original,
        'command_id': 'valid',
        'sale_command_id': 'valid-sale',
        'collection_command_id': 'valid-collection',
        'legacy_draft_id': 'valid-draft',
        'account_revision': 2,
      });
    },
  );

  for (final mixed in [false, true]) {
    test(
      '${mixed ? 'mixed' : 'all credit'} confirmed tender facts are immutable and cannot enter legacy payments',
      () async {
        await save(mixed: mixed);
        await prepare();
        final result = await quick.confirmPrepared('parent');
        final db = app.database;
        final facts = await db.query('quick_sale_line_tenders');
        expect(facts, hasLength(mixed ? 2 : 1));
        expect(await db.query('quick_sale_line_payments'), isEmpty);
        final credit = facts.singleWhere((f) => f['is_credit'] == 1);
        expect(credit['customer_name_snapshot'], 'Cliente sintético');
        for (final field in [
          'cash_account_id',
          'payment_method_id',
          'payment_option_id',
          'collection_document_id',
        ]) {
          expect(credit[field], isNull);
        }
        final legacyCredit = Map<String, Object?>.of(credit)
          ..remove('is_credit')
          ..remove('customer_name_snapshot');
        for (final mutation in [
          () => db.update('quick_sale_line_tenders', {
            'customer_name_snapshot': 'Otro cliente',
          }),
          () => db.update('quick_sale_line_tenders', {'is_credit': 0}),
          () => db.delete('quick_sale_line_tenders'),
          () => db.insert(
            'quick_sale_line_tenders',
            credit,
            conflictAlgorithm: ConflictAlgorithm.replace,
          ),
          () => db.insert('quick_sale_line_tenders', {
            ...credit,
            'id': 'replacement',
          }, conflictAlgorithm: ConflictAlgorithm.replace),
          () => db.insert('quick_sale_line_payments', {
            ...legacyCredit,
            'id': 'legacy-forgery',
          }),
        ]) {
          await expectLater(mutation(), throwsA(isA<DatabaseException>()));
        }
        expect(
          (await db.query('quick_sale_requests')).single['status'],
          'confirmed',
        );
        expect(result.creditMinor, 10000);
        expect(result.collectionDocumentId, mixed ? isNotNull : isNull);
        expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      },
    );
  }
}
