import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/schema.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase app;
  setUp(() async {
    app = await AppDatabase.open(path: inMemoryDatabasePath);
  });
  tearDown(() => app.close());

  test(
    'v6 appends empty counter tables without changing released inputs',
    () async {
      expect(DatabaseSchema.migration5Checksum, 'fnv1a64:aaf6156fd67b9099');
      expect(DatabaseSchema.nameForVersion(6), 'quick_counter_sales_v6');
      for (final table in [
        'quick_payment_options',
        'quick_sales_accounts',
        'quick_sales_lines',
        'quick_sale_requests',
        'quick_sale_line_payments',
      ]) {
        expect(await app.database.query(table), isEmpty);
      }
      final health = await app.readHealth();
      expect(health['schemaVersion'], DatabaseSchema.version);
      expect(health['schemaChecksumVerified'], isTrue);
      expect(health['migrationChecksumVerified'], isTrue);
      expect(health['foreignKeyViolations'], 0);
    },
  );

  test(
    'payment option identity survives rename and cannot be replaced',
    () async {
      final db = app.database;
      await _paymentCatalog(db);
      final original = (await db.query('quick_payment_options')).single;
      await db.update('quick_payment_options', {
        'label': 'Contado',
        'is_active': 0,
      });
      expect(
        (await db.query('quick_payment_options')).single['label'],
        'Contado',
      );
      for (final mutation in [
        () => db.update('quick_payment_options', {'id': 'other'}),
        () => db.delete('quick_payment_options'),
        () => db.insert(
          'quick_payment_options',
          original,
          conflictAlgorithm: ConflictAlgorithm.replace,
        ),
      ]) {
        await expectLater(mutation(), throwsA(isA<DatabaseException>()));
      }
    },
  );

  test(
    'incomplete raw line fields persist but prepared drafts are locked',
    () async {
      final db = app.database;
      await _account(db, 'account');
      expect((await db.query('quick_sales_lines')).single['quantity_text'], '');
      await db.update('quick_sales_lines', {'quantity_text': '12x'});
      await _prepare(db);
      final original = (await db.query('quick_sales_lines')).single;
      for (final mutation in [
        () => db.update('quick_sales_lines', {'quantity_text': '2'}),
        () => db.delete('quick_sales_lines'),
        () => db.insert(
          'quick_sales_lines',
          original,
          conflictAlgorithm: ConflictAlgorithm.replace,
        ),
        () => db.update('quick_sales_accounts', {
          'status': 'open',
          'revision': 2,
        }),
      ]) {
        await expectLater(mutation(), throwsA(isA<DatabaseException>()));
      }
      await db.update('quick_sale_requests', {
        'status': 'rejected',
        'rejection_reason': 'Stock insuficiente',
      });
      await db.update('quick_sale_requests', {'status': 'cancelled'});
      await db.update('quick_sales_accounts', {
        'status': 'open',
        'revision': 2,
      });
      await db.update('quick_sales_lines', {'quantity_text': '2'});
      expect(
        (await db.query('quick_sales_lines')).single['quantity_text'],
        '2',
      );
    },
  );

  test(
    'all three command IDs remain reserved while prepared or cancelled',
    () async {
      final db = app.database;
      await _actor(db);
      await _account(db, 'account');
      await _prepare(db);
      for (final (id, type) in [
        ('parent', 'quick_sale'),
        ('child-sale', 'confirm_sale'),
        ('child-collection', 'collect_receivable'),
        ('parent', 'receive_purchase'),
        ('child-sale', 'pay_supplier'),
      ]) {
        await expectLater(
          _command(db, id, type),
          throwsA(isA<DatabaseException>()),
        );
      }
      await expectLater(
        db.insert('sales_drafts', {
          'id': 'internal-draft',
          'label': 'Intento',
          'customer_name': 'Mostrador',
          'revision': 1,
          'status': 'open',
          'updated_at_utc': _utc,
        }),
        throwsA(isA<DatabaseException>()),
      );
      await db.update('quick_sale_requests', {
        'status': 'rejected',
        'rejection_reason': 'Prueba',
      });
      await db.update('quick_sale_requests', {'status': 'cancelled'});
      await expectLater(
        _command(db, 'child-sale', 'confirm_sale'),
        throwsA(isA<DatabaseException>()),
      );
    },
  );

  test(
    'quick parent and children cannot reuse existing committed IDs',
    () async {
      final db = app.database;
      await _actor(db);
      await _account(db, 'account');
      await _command(db, 'taken', 'synthetic_fixture');
      for (final slot in [
        'command_id',
        'sale_command_id',
        'collection_command_id',
      ]) {
        await expectLater(
          db.insert('quick_sale_requests', {..._request, slot: 'taken'}),
          throwsA(isA<DatabaseException>()),
        );
      }
      await expectLater(
        db.insert('quick_sale_requests', {
          ..._request,
          'sale_command_id': 'parent',
        }),
        throwsA(isA<DatabaseException>()),
      );
    },
  );

  test(
    'only executing checkout may write its specific child command type',
    () async {
      final db = app.database;
      await _actor(db);
      await _account(db, 'account');
      await _prepare(db);
      await db.update('quick_sale_requests', {'status': 'executing'});
      await expectLater(
        _command(db, 'child-sale', 'collect_receivable'),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        _command(db, 'child-collection', 'confirm_sale'),
        throwsA(isA<DatabaseException>()),
      );
      await _command(db, 'child-sale', 'confirm_sale');
      await _command(db, 'child-collection', 'collect_receivable');
      await _command(db, 'parent', 'quick_sale');
      expect(await db.query('command_log'), hasLength(3));
      await expectLater(
        db.update('quick_sale_requests', {'status': 'confirmed'}),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        db.update('quick_sales_accounts', {
          'status': 'confirmed',
          'confirmed_document_id': 'missing',
        }),
        throwsA(isA<DatabaseException>()),
      );
    },
  );

  test(
    'prepared identity and outcome transitions cannot be overwritten',
    () async {
      final db = app.database;
      await _account(db, 'account');
      await _prepare(db);
      for (final mutation in [
        () => db.update('quick_sale_requests', {'canonical_payload': 'other'}),
        () => db.update('quick_sale_requests', {'sale_command_id': 'other'}),
        () => db.delete('quick_sale_requests'),
        () => db.insert(
          'quick_sale_requests',
          _request,
          conflictAlgorithm: ConflictAlgorithm.replace,
        ),
        () => db.update('quick_sale_requests', {'status': 'confirmed'}),
      ]) {
        await expectLater(mutation(), throwsA(isA<DatabaseException>()));
      }
      await db.update('quick_sale_requests', {
        'status': 'rejected',
        'rejection_reason': 'No hay stock',
      });
      await expectLater(
        db.update('quick_sale_requests', {
          'status': 'cancelled',
          'rejection_reason': 'Cambio',
        }),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        (await db.query('quick_sale_requests')).single['status'],
        'rejected',
      );
    },
  );

  test(
    'replace from another open account cannot evict a prepared line',
    () async {
      final db = app.database;
      await _account(db, 'account');
      await _prepare(db);
      await _account(db, 'other');
      await expectLater(
        db.insert('quick_sales_lines', {
          'id': 'line-account',
          'account_id': 'other',
          'sequence': 1,
          'quantity_text': '3',
        }, conflictAlgorithm: ConflictAlgorithm.replace),
        throwsA(isA<DatabaseException>()),
      );
      expect(await db.query('quick_sales_lines'), hasLength(2));
    },
  );
}

const _utc = '2026-10-19T15:00:00.000Z';
const _request = <String, Object?>{
  'command_id': 'parent',
  'account_id': 'account',
  'account_revision': 1,
  'canonical_payload': '{"synthetic":true}',
  'occurred_at_utc': _utc,
  'prepared_at_utc': _utc,
  'status': 'prepared',
  'sale_command_id': 'child-sale',
  'collection_command_id': 'child-collection',
  'legacy_draft_id': 'internal-draft',
};

Future<void> _actor(DatabaseExecutor db) => db.insert('actors', {
  'id': 'actor',
  'display_name': 'Operador sintético',
  'kind': 'synthetic',
  'is_active': 1,
  'created_at_utc': _utc,
});

Future<void> _account(DatabaseExecutor db, String id) async {
  await db.insert('quick_sales_accounts', {
    'id': id,
    'label': 'Cuenta sintética',
    'revision': 1,
    'status': 'open',
    'updated_at_utc': _utc,
  });
  await db.insert('quick_sales_lines', {
    'id': 'line-$id',
    'account_id': id,
    'sequence': 0,
    'quantity_text': '',
  });
}

Future<void> _prepare(DatabaseExecutor db) async {
  await db.insert('quick_sale_requests', _request);
  await db.update(
    'quick_sales_accounts',
    {'status': 'prepared'},
    where: 'id = ?',
    whereArgs: ['account'],
  );
}

Future<void> _command(DatabaseExecutor db, String id, String type) =>
    db.insert('command_log', {
      'id': id,
      'command_type': type,
      'payload_hash': 'synthetic',
      'actor_id': 'actor',
      'response_json': '{}',
      'response_version': 1,
      'committed_at_utc': _utc,
      'authorization_policy_version': 'development-single-user-v1',
    });

Future<void> _paymentCatalog(DatabaseExecutor db) async {
  await db.insert('ledger_accounts', {
    'id': 'money',
    'code': 'CASH',
    'name': 'Caja',
    'class': 'asset',
    'role': 'cash',
    'is_active': 1,
  });
  await db.insert('cash_accounts', {
    'id': 'cash',
    'ledger_account_id': 'money',
    'name': 'Caja',
    'kind': 'cash',
    'is_available': 1,
    'is_active': 1,
  });
  await db.insert('payment_methods', {
    'id': 'method',
    'code': 'CASH',
    'name': 'Efectivo',
    'is_active': 1,
  });
  await db.insert('quick_payment_options', {
    'id': 'option',
    'label': 'Efectivo',
    'cash_account_id': 'cash',
    'payment_method_id': 'method',
    'is_active': 1,
  });
}
