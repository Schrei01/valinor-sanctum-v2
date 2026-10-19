import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/schema.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/sales/data/sqlite_sales_store.dart';
import 'package:valinor_sanctum_2/features/sales/domain/sales_store.dart';
import 'package:valinor_sanctum_2/features/workspace/data/sqlite_workspace_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase app;
  setUp(() async {
    app = await AppDatabase.open(path: inMemoryDatabasePath);
    await _fixture(app);
  });
  tearDown(() => app.close());

  test(
    'v4 preserves historical migration inputs and passes health checks',
    () async {
      expect(DatabaseSchema.migrationChecksum, 'fnv1a64:2b8aa24f7fdff6d1');
      expect(DatabaseSchema.migration2Checksum, 'fnv1a64:7c3f94396eb01ba3');
      expect(DatabaseSchema.nameForVersion(4), 'customer_collections_v4');
      expect(
        DatabaseSchema.checksumForVersion(4),
        DatabaseSchema.migration4Checksum,
      );
      final health = await app.readHealth();
      expect(health['schemaVersion'], DatabaseSchema.version);
      expect(health['integrityOk'], isTrue);
      expect(health['foreignKeyViolations'], 0);
    },
  );

  test(
    'a split collection settles exactly without new stock or revenue',
    () async {
      final beforeSales = await app.database.query('sales');
      final beforeStock = await app.database.query('sale_outflows');
      final beforeCosts = await app.database.query('sale_cost_allocations');
      await _stage(app, 'first', 4000, 6000, split: true);
      await _post(app, 'first');
      expect(
        (await app.database.query(
          'receivable_settlements',
        )).single['amount_minor'],
        4000,
      );
      expect(
        (await app.database.query('collections')).single['remaining_minor'],
        6000,
      );
      expect(await app.database.query('sales'), beforeSales);
      expect(await app.database.query('sale_outflows'), beforeStock);
      expect(await app.database.query('sale_cost_allocations'), beforeCosts);
      final lines = await app.database.query(
        'journal_lines',
        where: 'entry_id = ?',
        whereArgs: ['entry-first'],
      );
      expect(lines, hasLength(2));
      expect(
        lines.fold<int>(0, (sum, row) => sum + (row['debit_minor'] as int)),
        4000,
      );
      expect(
        lines.fold<int>(0, (sum, row) => sum + (row['credit_minor'] as int)),
        4000,
      );
    },
  );

  for (final invalid in ['overpay', 'remaining', 'parts', 'journal']) {
    test(
      'posting rejects inconsistent $invalid atomically at the boundary',
      () async {
        final total = invalid == 'overpay' ? 10001 : 4000;
        await _stage(
          app,
          'invalid',
          total,
          invalid == 'overpay'
              ? 0
              : invalid == 'remaining'
              ? 5999
              : 6000,
          partAmount: invalid == 'parts' ? 3999 : null,
          debitAmount: invalid == 'journal' ? 3999 : null,
        );
        await expectLater(
          _postDocument(app, 'invalid'),
          throwsA(isA<DatabaseException>()),
        );
        expect(
          (await app.database.query(
            'business_documents',
            where: 'id = ?',
            whereArgs: ['doc-invalid'],
          )).single['status'],
          'draft',
        );
        expect(
          (await app.database.query(
            'customer_receivables',
          )).single['initial_minor'],
          10000,
        );
      },
    );
  }

  test('a second collection cannot overpay the remaining receivable', () async {
    await _stage(app, 'first', 4000, 6000);
    await _post(app, 'first');
    await _stage(app, 'second', 6001, 0);
    await expectLater(
      _postDocument(app, 'second'),
      throwsA(isA<DatabaseException>()),
    );
  });

  test(
    'chronology compares mixed fractional precision to microseconds',
    () async {
      await _stage(
        app,
        'first',
        4000,
        6000,
        occurred: '2026-10-19T16:00:00.000001Z',
      );
      await _post(app, 'first');
      await _stage(
        app,
        'earlier',
        1000,
        5000,
        occurred: '2026-10-19T16:00:00.000Z',
      );
      await expectLater(
        _postDocument(app, 'earlier'),
        throwsA(isA<DatabaseException>()),
      );
      await _stage(
        app,
        'later',
        6000,
        0,
        occurred: '2026-10-19T16:00:00.000002Z',
      );
      await _post(app, 'later');
      expect(
        (await app.database.query(
          'collections',
          where: 'document_id = ?',
          whereArgs: ['doc-later'],
        )).single['remaining_minor'],
        0,
      );
    },
  );

  test('collections cannot precede the originating sale', () async {
    await _stage(
      app,
      'early',
      4000,
      6000,
      occurred: '2026-10-19T14:59:59.999999Z',
    );
    await expectLater(
      _postDocument(app, 'early'),
      throwsA(isA<DatabaseException>()),
    );
  });

  test(
    'requests reject noncanonical UTC and accept the final microsecond',
    () async {
      for (final occurred in [
        '2026-10-19T16:00:00Z',
        '2026-10-19T16:00:00.000+00:00',
        '2026-10-19T16:00:00.xyzZ',
        'not-a-valid-timestampxxxZ',
      ]) {
        await expectLater(
          _request(app, 'invalid-$occurred', occurred),
          throwsA(isA<DatabaseException>()),
        );
      }
      await _request(app, 'last-microsecond', '2026-10-19T16:00:00.999999Z');
    },
  );

  test(
    'documents facts and journals freeze as soon as the document posts',
    () async {
      await _stage(app, 'first', 4000, 6000);
      await _postDocument(app, 'first');
      for (final table in [
        'business_documents',
        'collections',
        'collection_parts',
        'receivable_settlements',
        'journal_entries',
        'journal_lines',
      ]) {
        final where = switch (table) {
          'business_documents' => 'id = ?',
          'collections' => 'document_id = ?',
          'collection_parts' || 'receivable_settlements' => 'collection_id = ?',
          'journal_entries' => 'id = ?',
          _ => 'entry_id = ?',
        };
        final arg = table.startsWith('journal_') ? 'entry-first' : 'doc-first';
        final row = (await app.database.query(
          table,
          where: where,
          whereArgs: [arg],
        )).first;
        await expectLater(
          app.database.delete(table, where: where, whereArgs: [arg]),
          throwsA(isA<DatabaseException>()),
          reason: '$table delete',
        );
        await expectLater(
          app.database.insert(
            table,
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          ),
          throwsA(isA<DatabaseException>()),
          reason: '$table replace',
        );
        final update = switch (table) {
          'business_documents' => {'reason': 'Rewrite'},
          'collections' => {'total_minor': 3999},
          'collection_parts' ||
          'receivable_settlements' => {'amount_minor': 3999},
          'journal_entries' => {'cost_completeness': 'complete'},
          _ => {'debit_minor': 3999},
        };
        await expectLater(
          app.database.update(table, update, where: where, whereArgs: [arg]),
          throwsA(isA<DatabaseException>()),
          reason: '$table update',
        );
      }
      await app.database.update(
        'journal_entries',
        {'status': 'posted', 'posted_at_utc': '2026-10-19T16:00:00.000Z'},
        where: 'id = ?',
        whereArgs: ['entry-first'],
      );
    },
  );

  test(
    'catalog names and flags can change but configured identities cannot',
    () async {
      await app.database.update(
        'cash_accounts',
        {'name': 'Caja nueva', 'is_active': 0},
        where: 'id = ?',
        whereArgs: ['cash'],
      );
      await app.database.update(
        'payment_methods',
        {'name': 'Método nuevo', 'is_active': 0},
        where: 'id = ?',
        whereArgs: ['method'],
      );
      await app.database.update(
        'ledger_accounts',
        {'name': 'Dinero renombrado', 'is_active': 0},
        where: 'id = ?',
        whereArgs: ['cash-ledger'],
      );
      for (final edit in [
        ('cash_accounts', {'kind': 'bank'}, 'cash'),
        ('cash_accounts', {'ledger_account_id': 'other-ledger'}, 'cash'),
        ('payment_methods', {'code': 'NEW'}, 'method'),
        ('ledger_accounts', {'role': 'inventory'}, 'cash-ledger'),
        ('ledger_accounts', {'class': 'revenue'}, 'cash-ledger'),
      ]) {
        await expectLater(
          app.database.update(
            edit.$1,
            edit.$2,
            where: 'id = ?',
            whereArgs: [edit.$3],
          ),
          throwsA(isA<DatabaseException>()),
        );
      }
      for (final table in [
        'cash_accounts',
        'payment_methods',
        'ledger_accounts',
      ]) {
        final row = (await app.database.query(
          table,
          where: 'id = ?',
          whereArgs: [
            table == 'ledger_accounts'
                ? 'cash-ledger'
                : table == 'cash_accounts'
                ? 'cash'
                : 'method',
          ],
        )).single;
        await expectLater(
          app.database.insert(
            table,
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          ),
          throwsA(isA<DatabaseException>()),
        );
      }
    },
  );

  test(
    'snapshot names survive renaming while unavailable money still receives',
    () async {
      await _stage(app, 'first', 4000, 6000);
      await app.database.update(
        'cash_accounts',
        {'name': 'Caja renombrada', 'is_available': 0},
        where: 'id = ?',
        whereArgs: ['cash'],
      );
      await app.database.update(
        'payment_methods',
        {'name': 'Pago renombrado'},
        where: 'id = ?',
        whereArgs: ['method'],
      );
      await _post(app, 'first');
      expect(
        (await app.database.query(
          'collection_parts',
        )).single['cash_account_name_snapshot'],
        'Caja sintética',
      );
    },
  );

  test(
    'request command IDs are reserved in both directions and after cancellation',
    () async {
      await _request(app, 'reserved', '2026-10-19T16:00:00.000Z');
      await expectLater(
        _command(app, 'reserved', type: 'receive_purchase'),
        throwsA(isA<DatabaseException>()),
      );
      final sales = SqliteSalesStore(app);
      await sales.saveDraft(
        SaveSaleDraft(
          id: 'second-draft',
          label: 'Otra cuenta',
          customerName: 'Cliente',
          expectedRevision: 0,
          lines: const [
            SaleDraftLine(
              productId: 'product',
              quantity: 1,
              unitPriceMinor: 10000,
            ),
          ],
        ),
      );
      await expectLater(
        sales.prepareConfirmation(
          commandId: 'reserved',
          draftId: 'second-draft',
          expectedRevision: 1,
          occurredAtUtc: DateTime.utc(2026, 10, 19, 16),
          dueDate: '2026-10-20',
        ),
        throwsA(anything),
      );
      await sales.prepareConfirmation(
        commandId: 'sale-reserved',
        draftId: 'second-draft',
        expectedRevision: 1,
        occurredAtUtc: DateTime.utc(2026, 10, 19, 16),
        dueDate: '2026-10-20',
      );
      await expectLater(
        _request(app, 'sale-reserved', '2026-10-19T16:00:00.000Z'),
        throwsA(isA<DatabaseException>()),
      );
      await app.database.update(
        'collection_requests',
        {'status': 'rejected', 'rejection_reason': 'Synthetic rejection'},
        where: 'command_id = ?',
        whereArgs: ['reserved'],
      );
      await app.database.update(
        'collection_requests',
        {'status': 'cancelled'},
        where: 'command_id = ?',
        whereArgs: ['reserved'],
      );
      await expectLater(
        _command(app, 'reserved'),
        throwsA(isA<DatabaseException>()),
      );
    },
  );
}

Future<void> _fixture(AppDatabase app) async {
  await SqliteWorkspaceStore(app).createProfile(
    BusinessProfile(
      profileId: 'collections-schema-test',
      businessName: 'Ludoteca sintética',
      currencyCode: 'COP',
      moneyScale: 2,
      timezone: 'America/Bogota',
      createdAtUtc: DateTime.utc(2026, 10, 19),
    ),
  );
  final inventory = SqliteInventoryStore(app);
  await inventory.saveSupplier(
    const InventorySupplier(id: 'supplier', name: 'Proveedor sintético'),
  );
  await inventory.saveProduct(
    const CatalogProduct(
      id: 'product',
      name: 'Producto sintético',
      listPriceMinor: 10000,
    ),
  );
  await inventory.receivePurchase(
    ReceiptCommand(
      commandId: 'purchase',
      supplierId: 'supplier',
      occurredAtUtc: DateTime.utc(2026, 10, 19, 10),
      dueDate: '2026-10-20',
      lines: const [
        ReceiptLineInput(
          productId: 'product',
          quantity: 3,
          totalCostMinor: 1001,
        ),
      ],
    ),
  );
  final sales = SqliteSalesStore(app);
  await sales.saveDraft(
    SaveSaleDraft(
      id: 'draft',
      label: 'Mesa sintética',
      customerName: 'Cliente sintético',
      expectedRevision: 0,
      lines: const [
        SaleDraftLine(productId: 'product', quantity: 1, unitPriceMinor: 10000),
      ],
    ),
  );
  await sales.prepareConfirmation(
    commandId: 'sale',
    draftId: 'draft',
    expectedRevision: 1,
    occurredAtUtc: DateTime.utc(2026, 10, 19, 15),
    dueDate: '2026-10-20',
  );
  await sales.confirmPrepared('sale');
  await app.database.insert('ledger_accounts', {
    'id': 'cash-ledger',
    'code': 'CASH-TEST',
    'name': 'Dinero sintético',
    'class': 'asset',
    'role': 'cash',
    'is_active': 1,
  });
  await app.database.insert('cash_accounts', {
    'id': 'cash',
    'ledger_account_id': 'cash-ledger',
    'name': 'Caja sintética',
    'kind': 'cash',
    'is_available': 1,
    'is_active': 1,
  });
  await app.database.insert('payment_methods', {
    'id': 'method',
    'code': 'CASH',
    'name': 'Efectivo sintético',
    'is_active': 1,
  });
}

Future<void> _request(AppDatabase app, String id, String occurred) async {
  final receivable = (await app.database.query('customer_receivables')).single;
  await app.database.insert('collection_requests', {
    'command_id': id,
    'canonical_payload': 'synthetic-$id',
    'receivable_id': receivable['id'],
    'occurred_at_utc': occurred,
    'prepared_at_utc': '2026-10-19T16:00:00.000Z',
    'status': 'prepared',
  });
}

Future<void> _command(
  AppDatabase app,
  String id, {
  String type = 'collect_receivable',
}) async {
  final actor = (await app.database.query('command_log')).first['actor_id'];
  await app.database.insert('command_log', {
    'id': id,
    'command_type': type,
    'payload_hash': 'synthetic-$id',
    'actor_id': actor,
    'response_json': '{}',
    'response_version': 1,
    'committed_at_utc': '2026-10-19T16:00:00.000Z',
    'authorization_policy_version': 'development-single-user-v1',
  });
}

Future<void> _stage(
  AppDatabase app,
  String id,
  int amount,
  int remaining, {
  String occurred = '2026-10-19T16:00:00.000Z',
  int? partAmount,
  int? debitAmount,
  bool split = false,
}) async {
  final db = app.database;
  final receivable = (await db.query('customer_receivables')).single;
  await _request(app, id, occurred);
  await _command(app, id);
  final actor = (await db.query('command_log')).first['actor_id'];
  await db.insert('business_documents', {
    'id': 'doc-$id',
    'command_id': id,
    'command_sequence': 0,
    'profile_id': 'collections-schema-test',
    'actor_id': actor,
    'type': 'customer_collection',
    'status': 'draft',
    'occurred_at_utc': occurred,
    'business_date': '2026-10-19',
    'recorded_at_utc': '2026-10-19T16:00:00.000Z',
    'source_kind': 'synthetic',
    'date_quality': 'documented',
  });
  await db.insert('collections', {
    'document_id': 'doc-$id',
    'receivable_id': receivable['id'],
    'sale_label_snapshot': 'Mesa sintética',
    'customer_name_snapshot': 'Cliente sintético',
    'collected_at_utc': occurred,
    'total_minor': amount,
    'remaining_minor': remaining,
  });
  for (var sequence = 0; sequence < (split ? 2 : 1); sequence++) {
    await db.insert('collection_parts', {
      'id': 'part-$id-$sequence',
      'collection_id': 'doc-$id',
      'sequence': sequence,
      'cash_account_id': 'cash',
      'payment_method_id': 'method',
      'cash_account_name_snapshot': 'Caja sintética',
      'cash_account_kind_snapshot': 'cash',
      'payment_method_code_snapshot': 'CASH',
      'payment_method_name_snapshot': 'Efectivo sintético',
      'amount_minor': split ? amount ~/ 2 : partAmount ?? amount,
    });
  }
  await db.insert('receivable_settlements', {
    'id': 'settlement-$id',
    'receivable_id': receivable['id'],
    'collection_id': 'doc-$id',
    'amount_minor': amount,
  });
  await db.insert('journal_entries', {
    'id': 'entry-$id',
    'document_id': 'doc-$id',
    'status': 'draft',
    'cost_completeness': 'not_applicable',
  });
  await db.insert('journal_lines', {
    'id': 'debit-$id',
    'entry_id': 'entry-$id',
    'sequence': 0,
    'account_id': 'cash-ledger',
    'debit_minor': debitAmount ?? amount,
    'credit_minor': 0,
  });
  await db.insert('journal_lines', {
    'id': 'credit-$id',
    'entry_id': 'entry-$id',
    'sequence': 1,
    'account_id': receivable['control_account_id'],
    'debit_minor': 0,
    'credit_minor': amount,
  });
}

Future<void> _postDocument(AppDatabase app, String id) async {
  await app.database.update(
    'business_documents',
    {'status': 'posted'},
    where: 'id = ?',
    whereArgs: ['doc-$id'],
  );
}

Future<void> _post(AppDatabase app, String id) async {
  await _postDocument(app, id);
  await app.database.update(
    'journal_entries',
    {'status': 'posted', 'posted_at_utc': '2026-10-19T16:00:00.000Z'},
    where: 'id = ?',
    whereArgs: ['entry-$id'],
  );
  await app.database.update(
    'collection_requests',
    {'status': 'confirmed'},
    where: 'command_id = ?',
    whereArgs: [id],
  );
}
