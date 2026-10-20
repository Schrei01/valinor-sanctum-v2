import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/schema.dart';
import 'package:valinor_sanctum_2/features/workspace/data/sqlite_workspace_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';

const _utc = '2026-10-20T15:00:00.000Z';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase app;
  late Database db;
  setUp(() async {
    app = await AppDatabase.open(path: inMemoryDatabasePath);
    db = app.database;
    await SqliteWorkspaceStore(app).createProfile(
      BusinessProfile(
        profileId: 'opening-schema',
        businessName: 'Tienda sintética',
        currencyCode: 'COP',
        moneyScale: 0,
        timezone: 'America/Bogota',
        createdAtUtc: DateTime.utc(2026, 10, 20),
      ),
    );
    await db.insert('actors', {
      'id': 'actor',
      'display_name': 'Operador',
      'kind': 'synthetic',
      'is_active': 1,
      'created_at_utc': _utc,
    });
    for (final (id, code, name, kind, role) in [
      ('inventory', 'INV', 'Inventario', 'asset', 'inventory'),
      ('system:opening-equity', 'EQ', 'Apertura', 'equity', 'opening_balance'),
      ('cash', 'CASH', 'Efectivo', 'asset', 'cash'),
    ]) {
      await db.insert('ledger_accounts', {
        'id': id,
        'code': code,
        'name': name,
        'class': kind,
        'role': role,
        'is_active': 1,
      });
    }
  });
  tearDown(() => app.close());

  Future<void> prepare({
    int cost = 100,
    int quantity = 3,
    bool zeroConfirmed = true,
    bool journal = true,
  }) async {
    await db.insert('catalog_items', {
      'id': 'product',
      'name': 'Producto sintético',
      'kind': 'product',
      'unit_code': 'unit',
      'quantity_scale': 0,
      'list_price_minor': 250,
      'is_active': 1,
    });
    await db.insert('command_log', {
      'id': 'opening-command',
      'command_type': 'inventory_opening',
      'payload_hash': 'synthetic',
      'actor_id': 'actor',
      'response_json': '{}',
      'response_version': 1,
      'committed_at_utc': _utc,
      'authorization_policy_version': 'development-single-user-v1',
    });
    await db.insert('business_documents', {
      'id': 'opening-document',
      'command_id': 'opening-command',
      'command_sequence': 0,
      'profile_id': 'opening-schema',
      'actor_id': 'actor',
      'type': 'inventory_opening',
      'status': 'draft',
      'occurred_at_utc': _utc,
      'business_date': '2026-10-20',
      'recorded_at_utc': _utc,
      'source_kind': 'synthetic',
      'date_quality': 'reconstructed',
    });
    await db.insert('inventory_openings', {
      'document_id': 'opening-document',
      'command_id': 'opening-command',
      'profile_id': 'opening-schema',
      'source_name': 'synthetic.db',
      'source_sha256': List.filled(64, 'a').join(),
      'snapshot_sha256': List.filled(64, 'b').join(),
      'occurred_at_utc': _utc,
      'total_cost_minor': cost * quantity,
    });
    await db.insert('inventory_opening_items', {
      'id': 'opening-item',
      'opening_id': 'opening-document',
      'sequence': 0,
      'source_product_id': '1',
      'product_id': 'product',
      'name_snapshot': 'Producto sintético',
      'unit_price_minor': 250,
      'unit_cost_minor': cost,
      'quantity': quantity,
      'total_cost_minor': cost * quantity,
      'zero_cost_confirmed': zeroConfirmed ? 1 : 0,
    });
    await db.insert('journal_entries', {
      'id': 'opening-entry',
      'document_id': 'opening-document',
      'status': 'draft',
      'cost_completeness': 'complete',
    });
    if (journal && cost * quantity > 0) {
      for (final (sequence, account, debit, credit) in [
        (0, 'inventory', cost * quantity, 0),
        (1, 'system:opening-equity', 0, cost * quantity),
      ]) {
        await db.insert('journal_lines', {
          'id': 'opening-line-$sequence',
          'entry_id': 'opening-entry',
          'sequence': sequence,
          'account_id': account,
          'debit_minor': debit,
          'credit_minor': credit,
        });
      }
    }
  }

  Future<void> postDocument() => db.update(
    'business_documents',
    {'status': 'posted'},
    where: 'id = ?',
    whereArgs: ['opening-document'],
  );
  Future<void> postEntry() => db.update(
    'journal_entries',
    {'status': 'posted', 'posted_at_utc': _utc},
    where: 'id = ?',
    whereArgs: ['opening-entry'],
  );

  test(
    'v8 is additive and fresh opening tables have no fabricated facts',
    () async {
      expect(DatabaseSchema.migrationChecksum, 'fnv1a64:2b8aa24f7fdff6d1');
      expect(DatabaseSchema.migration2Checksum, 'fnv1a64:7c3f94396eb01ba3');
      expect(DatabaseSchema.migration3Checksum, 'fnv1a64:c719534b847edc09');
      expect(DatabaseSchema.migration5Checksum, 'fnv1a64:aaf6156fd67b9099');
      expect(DatabaseSchema.migration6Checksum, 'fnv1a64:4ccd48022ac15ecc');
      expect((await app.readHealth())['schemaVersion'], 8);
      for (final table in [
        'inventory_openings',
        'inventory_opening_items',
        'inventory_opening_allocations',
        'inventory_opening_layers',
        'all_sale_cost_allocations',
      ]) {
        expect(await db.query(table), isEmpty, reason: table);
      }
    },
  );

  test(
    'opening posts stock against equity without purchases money or debt',
    () async {
      await prepare();
      expect(await db.query('inventory_opening_layers'), isEmpty);
      await postDocument();
      expect(await db.query('inventory_opening_layers'), isEmpty);
      await postEntry();
      final layer = (await db.query('inventory_opening_layers')).single;
      expect(layer['initial_quantity'], 3);
      expect(layer['total_cost_minor'], 300);
      expect(layer['source_kind'], 'opening');
      expect(layer['fifo_sequence'], 0);
      for (final table in [
        'purchases',
        'purchase_lines',
        'inventory_movements',
        'cost_layers',
        'obligations',
        'supplier_payments',
        'collections',
      ]) {
        expect(await db.query(table), isEmpty, reason: table);
      }
      expect(
        (await db.query('journal_lines')).map((row) => row['account_id']),
        ['inventory', 'system:opening-equity'],
      );
    },
  );

  test(
    'confirmed zero cost preserves stock with no fabricated journal amount',
    () async {
      await prepare(cost: 0);
      await postDocument();
      await postEntry();
      expect(await db.query('journal_lines'), isEmpty);
      final layer = (await db.query('inventory_opening_layers')).single;
      expect(layer['initial_quantity'], 3);
      expect(layer['total_cost_minor'], 0);
      expect(
        (await db.query(
          'inventory_opening_items',
        )).single['zero_cost_confirmed'],
        1,
      );
    },
  );

  test(
    'exhausted source rows stay mapped without creating saleable layers',
    () async {
      await prepare(quantity: 0);
      await postDocument();
      await postEntry();
      expect(await db.query('inventory_opening_items'), hasLength(1));
      expect(await db.query('inventory_opening_layers'), isEmpty);
    },
  );

  test(
    'missing confirmation never silently treats missing cost as zero',
    () async {
      await expectLater(
        prepare(cost: 0, zeroConfirmed: false),
        throwsA(isA<DatabaseException>()),
      );
      expect(await db.query('inventory_opening_layers'), isEmpty);
    },
  );

  test('opening cannot use cash as its accounting counterpart', () async {
    await prepare();
    await db.update(
      'journal_lines',
      {'account_id': 'cash'},
      where: 'id = ?',
      whereArgs: ['opening-line-1'],
    );
    await expectLater(postDocument(), throwsA(isA<DatabaseException>()));
  });

  test(
    'opening cannot post incomplete value or mismatched catalog identity',
    () async {
      await prepare();
      await db.update('inventory_openings', {'total_cost_minor': 301});
      await expectLater(postDocument(), throwsA(isA<DatabaseException>()));
      await db.update('inventory_openings', {'total_cost_minor': 300});
      await db.update('catalog_items', {'name': 'Nombre distinto'});
      await expectLater(postDocument(), throwsA(isA<DatabaseException>()));
    },
  );

  test(
    'posted document freezes opening facts before journal entry posting',
    () async {
      await prepare();
      await postDocument();
      for (final operation in [
        () => db.update('inventory_opening_items', {'name_snapshot': 'Cambio'}),
        () => db.delete('inventory_opening_items'),
        () => db.update('inventory_openings', {'source_name': 'Cambio'}),
        () => db.delete('inventory_openings'),
        () => db.delete('journal_entries'),
        () => db.update(
          'journal_lines',
          {'debit_minor': 301},
          where: 'id = ?',
          whereArgs: ['opening-line-0'],
        ),
        () => db.insert('journal_entries', {
          'id': 'replacement',
          'document_id': 'opening-document',
          'status': 'draft',
          'cost_completeness': 'complete',
        }, conflictAlgorithm: ConflictAlgorithm.replace),
        () => db.insert('journal_lines', {
          'id': 'replacement',
          'entry_id': 'opening-entry',
          'sequence': 0,
          'account_id': 'inventory',
          'debit_minor': 301,
          'credit_minor': 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace),
      ]) {
        await expectLater(operation(), throwsA(isA<DatabaseException>()));
      }
      await postEntry();
      expect(await db.query('inventory_opening_layers'), hasLength(1));
    },
  );

  test(
    'ordinary documents cannot use the zero line opening exception',
    () async {
      await prepare(cost: 0);
      await db.update('business_documents', {'type': 'other'});
      await expectLater(postDocument(), throwsA(isA<DatabaseException>()));
      await expectLater(postEntry(), throwsA(isA<DatabaseException>()));
    },
  );
}
