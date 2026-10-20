import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/schema.dart';
import 'package:valinor_sanctum_2/features/stock_intake/data/sqlite_stock_intake_store.dart';
import 'package:valinor_sanctum_2/features/stock_intake/domain/stock_intake_store.dart';
import 'package:valinor_sanctum_2/features/workspace/data/sqlite_workspace_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase app;
  late SqliteStockIntakeStore store;
  late String categoryId;
  setUp(() async {
    app = await AppDatabase.open(path: inMemoryDatabasePath);
    await SqliteWorkspaceStore(app).createProfile(
      BusinessProfile(
        profileId: 'guard-profile',
        businessName: 'Tienda sintética',
        currencyCode: 'COP',
        moneyScale: 2,
        timezone: 'America/Bogota',
        createdAtUtc: DateTime.utc(2026, 10, 19),
      ),
    );
    await app.database.insert('actors', {
      'id': 'guard-actor',
      'display_name': 'Operador sintético',
      'kind': 'synthetic',
      'is_active': 1,
      'created_at_utc': _utc,
    });
    store = SqliteStockIntakeStore(app, synthetic: true);
    await store.ensureDefaults();
    categoryId = (await store.load()).categories
        .singleWhere((c) => c.name == 'Comestible')
        .id;
  });
  tearDown(() => app.close());

  StockIntakeCommand intake(String id) => StockIntakeCommand(
    commandId: id,
    productId: 'product-$id',
    productName: 'Producto sintético',
    categoryId: categoryId,
    supplierName: 'Proveedor sintético',
    unitPurchasePriceMinor: 100,
    listPriceMinor: 250,
    quantity: 2,
    paymentOptionId: 'quick-default:EFECTIVO',
    occurredAtUtc: DateTime.utc(2026, 10, 19, 16),
  );

  Future<void> fund() => store.recordOpeningBalance(
    CashOpeningCommand(
      commandId: 'guard-opening',
      paymentOptionId: 'quick-default:EFECTIVO',
      amountMinor: 10000,
      occurredAtUtc: DateTime.utc(2026, 10, 19, 15),
    ),
  );

  Future<StockIntakeResult> confirmed() async {
    await fund();
    await store.prepare(intake('confirmed'));
    return store.confirmPrepared('confirmed');
  }

  test(
    'v7 appends empty tables and preserves all released v6 inputs',
    () async {
      expect(DatabaseSchema.migration6Checksum, 'fnv1a64:4ccd48022ac15ecc');
      expect(
        DatabaseSchema.nameForVersion(7),
        'paid_stock_intakes_and_cash_openings_v7',
      );
      for (final table in [
        'paid_purchase_requests',
        'paid_purchase_entries',
        'cash_openings',
      ]) {
        expect(await app.database.query(table), isEmpty);
      }
      expect(await app.database.query('journal_lines'), isEmpty);
      expect((await app.readHealth())['schemaVersion'], 7);
    },
  );

  test(
    'intake parent and children remain reserved after cancellation',
    () async {
      final db = app.database;
      await db.insert('paid_purchase_requests', _request);
      for (final (id, type) in [
        ('parent', 'paid_purchase'),
        ('child-purchase', 'receive_purchase'),
        ('child-payment', 'pay_supplier'),
        ('child-payment', 'cash_opening'),
      ]) {
        await expectLater(
          _command(db, id, type),
          throwsA(isA<DatabaseException>()),
        );
      }
      await db.update('paid_purchase_requests', {
        'status': 'rejected',
        'rejection_reason': 'Prueba sintética',
      });
      await db.update('paid_purchase_requests', {'status': 'cancelled'});
      await expectLater(
        _command(db, 'child-payment', 'pay_supplier'),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        db.delete('paid_purchase_requests'),
        throwsA(isA<DatabaseException>()),
      );
    },
  );

  test(
    'prepared intake input and child identities cannot be rewritten or replaced',
    () async {
      final db = app.database;
      await db.insert('paid_purchase_requests', _request);
      for (final values in [
        {'canonical_payload': '{"changed":true}'},
        {'purchase_command_id': 'replacement'},
        {'payment_command_id': 'replacement'},
        {'occurred_at_utc': '2026-10-19T16:00:00.000Z'},
        {'status': 'confirmed'},
      ]) {
        await expectLater(
          db.update('paid_purchase_requests', values),
          throwsA(isA<DatabaseException>()),
        );
      }
      await expectLater(
        db.insert(
          'paid_purchase_requests',
          _request,
          conflictAlgorithm: ConflictAlgorithm.replace,
        ),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        db.insert('paid_purchase_requests', {
          ..._request,
          'canonical_payload': 'invalid json',
        }),
        throwsA(isA<DatabaseException>()),
      );
    },
  );

  test(
    'intake cannot reserve committed IDs or another parent child IDs',
    () async {
      final db = app.database;
      await _command(db, 'taken', 'synthetic_fixture');
      for (final slot in [
        'command_id',
        'purchase_command_id',
        'payment_command_id',
      ]) {
        await expectLater(
          db.insert('paid_purchase_requests', {..._request, slot: 'taken'}),
          throwsA(isA<DatabaseException>()),
        );
      }
      await db.insert('paid_purchase_requests', _request);
      for (final slot in [
        'command_id',
        'purchase_command_id',
        'payment_command_id',
      ]) {
        await expectLater(
          db.insert('paid_purchase_requests', {
            ..._request,
            'command_id': 'second-parent',
            'purchase_command_id': 'second-purchase',
            'payment_command_id': 'second-payment',
            slot: 'child-payment',
          }),
          throwsA(isA<DatabaseException>()),
        );
      }
    },
  );

  test(
    'quick checkout and intake command namespaces cannot overlap in either direction',
    () async {
      final db = app.database;
      await _quickAccount(db);
      await db.insert('paid_purchase_requests', _request);
      for (final slot in [
        'command_id',
        'sale_command_id',
        'collection_command_id',
      ]) {
        await expectLater(
          db.insert('quick_sale_requests', {
            ..._quickRequest,
            slot: 'child-purchase',
          }),
          throwsA(isA<DatabaseException>()),
        );
      }
      await db.insert('quick_sale_requests', _quickRequest);
      for (final slot in [
        'command_id',
        'purchase_command_id',
        'payment_command_id',
      ]) {
        await expectLater(
          db.insert('paid_purchase_requests', {
            ..._request,
            'command_id': 'next-parent',
            'purchase_command_id': 'next-purchase',
            'payment_command_id': 'next-payment',
            slot: 'quick-child-sale',
          }),
          throwsA(isA<DatabaseException>()),
        );
      }
    },
  );

  test(
    'old preparation tables cannot take any reserved intake identity',
    () async {
      final db = app.database;
      await db.insert('paid_purchase_requests', _request);
      for (final id in ['parent', 'child-purchase', 'child-payment']) {
        for (final table in [
          'sale_confirmations',
          'collection_requests',
          'supplier_payment_requests',
        ]) {
          final values = <String, Object?>{
            'command_id': id,
            'canonical_payload': '{}',
            'occurred_at_utc': _utc,
            'prepared_at_utc': _utc,
            'status': 'prepared',
            if (table == 'sale_confirmations') ...{
              'draft_id': 'missing',
              'draft_revision': 1,
              'due_date': '2026-10-19',
            },
            if (table == 'collection_requests') 'receivable_id': 'missing',
            if (table == 'supplier_payment_requests') 'payable_id': 'missing',
          };
          await expectLater(
            db.insert(table, values),
            throwsA(
              predicate(
                (e) =>
                    e is DatabaseException &&
                    e.toString().contains('executing intake'),
              ),
            ),
          );
        }
      }
    },
  );

  test(
    'executing intake permits only exact child command types and cannot close without facts',
    () async {
      final db = app.database;
      await db.insert('paid_purchase_requests', _request);
      await db.update('paid_purchase_requests', {'status': 'executing'});
      await expectLater(
        _command(db, 'child-purchase', 'pay_supplier'),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        _command(db, 'child-payment', 'receive_purchase'),
        throwsA(isA<DatabaseException>()),
      );
      await _command(db, 'parent', 'paid_purchase');
      await expectLater(
        db.update('paid_purchase_requests', {'status': 'confirmed'}),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        db.update('paid_purchase_requests', {
          'status': 'rejected',
          'rejection_reason': 'Prueba',
        }),
        throwsA(isA<DatabaseException>()),
      );
    },
  );

  test(
    'confirmed intake snapshots and linkage cannot be edited, removed or replaced',
    () async {
      final result = await confirmed();
      final db = app.database;
      final entry = (await db.query('paid_purchase_entries')).single;
      expect(entry['purchase_document_id'], result.purchaseDocumentId);
      expect(entry['payment_document_id'], result.paymentDocumentId);
      expect(
        (await db.query('supplier_payments')).single['remaining_minor'],
        0,
      );
      await db.execute('PRAGMA recursive_triggers = OFF');
      for (final mutation in [
        () => db.update('paid_purchase_entries', {
          'unit_purchase_price_minor': 101,
        }),
        () => db.update('paid_purchase_entries', {
          'product_name_snapshot': 'Otra cosa',
        }),
        () => db.delete('paid_purchase_entries'),
        () => db.insert(
          'paid_purchase_entries',
          entry,
          conflictAlgorithm: ConflictAlgorithm.replace,
        ),
        () => db.update('paid_purchase_requests', {
          'status': 'rejected',
          'rejection_reason': 'Prueba',
        }),
      ]) {
        await expectLater(mutation(), throwsA(isA<DatabaseException>()));
      }
      expect((await db.query('paid_purchase_entries')).single, entry);
    },
  );

  test(
    'cash opening has one immutable account identity and exact posted journal',
    () async {
      await fund();
      final db = app.database;
      final opening = (await db.query('cash_openings')).single;
      final entry = (await db.query('journal_entries')).single;
      final lines = await db.query('journal_lines', orderBy: 'sequence');
      expect(lines, hasLength(2));
      expect(lines.first['debit_minor'], 10000);
      expect(lines.last['credit_minor'], 10000);
      await db.execute('PRAGMA recursive_triggers = OFF');
      for (final mutation in [
        () => db.update('cash_openings', {'amount_minor': 10001}),
        () => db.delete('cash_openings'),
        () => db.insert(
          'cash_openings',
          opening,
          conflictAlgorithm: ConflictAlgorithm.replace,
        ),
        () => db.delete('journal_entries'),
        () => db.insert(
          'journal_entries',
          entry,
          conflictAlgorithm: ConflictAlgorithm.replace,
        ),
        () => db.insert(
          'journal_lines',
          lines.first,
          conflictAlgorithm: ConflictAlgorithm.replace,
        ),
      ]) {
        await expectLater(mutation(), throwsA(isA<DatabaseException>()));
      }
      expect((await db.query('cash_openings')).single, opening);
    },
  );

  test(
    'opening document cannot post a wrong cash amount or equity counterparty',
    () async {
      final db = app.database;
      await _openingDraft(db);
      await expectLater(
        db.update(
          'business_documents',
          {'status': 'posted'},
          where: 'id = ?',
          whereArgs: ['raw-opening'],
        ),
        throwsA(isA<DatabaseException>()),
      );
      await db.update(
        'journal_lines',
        {'debit_minor': 10000},
        where: 'id = ?',
        whereArgs: ['raw-opening-debit'],
      );
      await db.update(
        'journal_lines',
        {'credit_minor': 10000},
        where: 'id = ?',
        whereArgs: ['raw-opening-credit'],
      );
      await db.update(
        'business_documents',
        {'status': 'posted'},
        where: 'id = ?',
        whereArgs: ['raw-opening'],
      );
      // The interval between posting the document and posting its journal must
      // also reject REPLACE, even with recursive triggers disabled.
      final entry = (await db.query('journal_entries')).single;
      final line = (await db.query('journal_lines')).first;
      await db.execute('PRAGMA recursive_triggers = OFF');
      await expectLater(
        db.insert(
          'journal_entries',
          entry,
          conflictAlgorithm: ConflictAlgorithm.replace,
        ),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        db.insert(
          'journal_lines',
          line,
          conflictAlgorithm: ConflictAlgorithm.replace,
        ),
        throwsA(isA<DatabaseException>()),
      );
      await db.update('journal_entries', {
        'status': 'posted',
        'posted_at_utc': _utc,
      });
      expect((await app.readHealth())['foreignKeyViolations'], 0);
    },
  );

  test(
    'raw opening rejects zero amounts and direct posted document insertion',
    () async {
      final db = app.database;
      await expectLater(
        _openingDraft(db, amount: 0),
        throwsA(
          predicate(
            (e) =>
                e is DatabaseException &&
                e.toString().contains('CHECK constraint failed'),
          ),
        ),
      );
      expect(await db.query('cash_openings'), isEmpty);
      await expectLater(
        db.insert('business_documents', {
          'id': 'already-posted-opening',
          'command_id': 'raw-opening-command',
          'command_sequence': 1,
          'profile_id': 'guard-profile',
          'actor_id': 'guard-actor',
          'type': 'cash_opening',
          'status': 'posted',
          'occurred_at_utc': _utc,
          'business_date': '2026-10-19',
          'recorded_at_utc': _utc,
          'source_kind': 'synthetic',
          'date_quality': 'documented',
        }),
        throwsA(isA<DatabaseException>()),
      );
    },
  );
}

const _utc = '2026-10-19T15:00:00.000Z';
const _request = <String, Object?>{
  'command_id': 'parent',
  'canonical_payload': '{"synthetic":true}',
  'occurred_at_utc': _utc,
  'prepared_at_utc': _utc,
  'status': 'prepared',
  'purchase_command_id': 'child-purchase',
  'payment_command_id': 'child-payment',
};
const _quickRequest = <String, Object?>{
  'command_id': 'quick-parent',
  'account_id': 'quick-account',
  'account_revision': 1,
  'canonical_payload': '{}',
  'occurred_at_utc': _utc,
  'prepared_at_utc': _utc,
  'status': 'prepared',
  'sale_command_id': 'quick-child-sale',
  'collection_command_id': 'quick-child-collection',
  'legacy_draft_id': 'quick-internal-draft',
};

Future<void> _command(DatabaseExecutor db, String id, String type) =>
    db.insert('command_log', {
      'id': id,
      'command_type': type,
      'payload_hash': 'synthetic',
      'actor_id': 'guard-actor',
      'response_json': '{}',
      'response_version': 1,
      'committed_at_utc': _utc,
      'authorization_policy_version': 'development-single-user-v1',
    });

Future<void> _quickAccount(DatabaseExecutor db) async {
  await db.insert('quick_sales_accounts', {
    'id': 'quick-account',
    'label': 'Cuenta sintética',
    'revision': 1,
    'status': 'open',
    'updated_at_utc': _utc,
  });
  await db.insert('quick_sales_lines', {
    'id': 'quick-line',
    'account_id': 'quick-account',
    'sequence': 0,
    'quantity_text': '',
  });
}

Future<void> _openingDraft(DatabaseExecutor db, {int amount = 10000}) async {
  final option = (await db.query(
    'quick_payment_options',
    where: 'id = ?',
    whereArgs: ['quick-default:EFECTIVO'],
  )).single;
  final cash = (await db.query(
    'cash_accounts',
    where: 'id = ?',
    whereArgs: [option['cash_account_id']],
  )).single;
  await db.insert('ledger_accounts', {
    'id': 'system:opening-equity',
    'code': 'OPEN',
    'name': 'Saldo inicial explícito',
    'class': 'equity',
    'role': 'opening_balance',
    'is_active': 1,
  });
  await _command(db, 'raw-opening-command', 'cash_opening');
  await db.insert('business_documents', {
    'id': 'raw-opening',
    'command_id': 'raw-opening-command',
    'command_sequence': 0,
    'profile_id': 'guard-profile',
    'actor_id': 'guard-actor',
    'type': 'cash_opening',
    'status': 'draft',
    'occurred_at_utc': _utc,
    'business_date': '2026-10-19',
    'recorded_at_utc': _utc,
    'source_kind': 'synthetic',
    'date_quality': 'documented',
  });
  await db.insert('cash_openings', {
    'document_id': 'raw-opening',
    'command_id': 'raw-opening-command',
    'cash_account_id': cash['id'],
    'amount_minor': amount,
    'occurred_at_utc': _utc,
  });
  await db.insert('journal_entries', {
    'id': 'raw-opening-entry',
    'document_id': 'raw-opening',
    'status': 'draft',
    'cost_completeness': 'not_applicable',
  });
  await db.insert('journal_lines', {
    'id': 'raw-opening-debit',
    'entry_id': 'raw-opening-entry',
    'sequence': 0,
    'account_id': cash['ledger_account_id'],
    'debit_minor': 1,
    'credit_minor': 0,
  });
  await db.insert('journal_lines', {
    'id': 'raw-opening-credit',
    'entry_id': 'raw-opening-entry',
    'sequence': 1,
    'account_id': 'system:opening-equity',
    'debit_minor': 0,
    'credit_minor': 1,
  });
}
