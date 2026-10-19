import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';
import 'package:valinor_sanctum_2/features/sales/data/sqlite_sales_store.dart';
import 'package:valinor_sanctum_2/features/sales/domain/sales_store.dart';
import 'package:valinor_sanctum_2/features/workspace/data/sqlite_workspace_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase app;
  late SqliteInventoryStore inventory;
  late SqliteSalesStore sales;

  setUp(() async {
    app = await AppDatabase.open(path: inMemoryDatabasePath);
    inventory = SqliteInventoryStore(app, synthetic: true);
    sales = SqliteSalesStore(app, synthetic: true);
    await SqliteWorkspaceStore(app).createProfile(
      BusinessProfile(
        profileId: 'sales-schema-test',
        businessName: 'Ludoteca sintética',
        currencyCode: 'COP',
        moneyScale: 2,
        timezone: 'America/Bogota',
        createdAtUtc: DateTime.utc(2026, 10, 18),
      ),
    );
    await inventory.saveSupplier(
      const InventorySupplier(id: 'supplier', name: 'Proveedor sintético'),
    );
    await inventory.saveProduct(
      const CatalogProduct(
        id: 'product',
        name: 'Producto sintético',
        listPriceMinor: 900,
      ),
    );
    await inventory.receivePurchase(
      ReceiptCommand(
        commandId: 'purchase',
        supplierId: 'supplier',
        lines: const [
          ReceiptLineInput(
            productId: 'product',
            quantity: 3,
            totalCostMinor: 1001,
          ),
        ],
        dueDate: '2026-10-21',
        occurredAtUtc: DateTime.utc(2026, 10, 18, 12),
      ),
    );
  });
  tearDown(() => app.close());

  Future<void> prepare() async {
    await sales.saveDraft(
      SaveSaleDraft(
        id: 'draft',
        label: 'Mesa sintética',
        customerName: 'Cliente sintético',
        expectedRevision: 0,
        lines: const [
          SaleDraftLine(productId: 'product', quantity: 2, unitPriceMinor: 900),
        ],
      ),
    );
    await sales.prepareConfirmation(
      commandId: 'confirm',
      draftId: 'draft',
      expectedRevision: 1,
      occurredAtUtc: DateTime.utc(2026, 10, 19, 12),
      dueDate: '2026-10-21',
    );
  }

  Future<void> blocked(Future<Object?> operation, String reason) =>
      expectLater(operation, throwsA(isA<DatabaseException>()), reason: reason);

  test(
    'all confirmed sale facts resist SQL mutation deletion and replacement',
    () async {
      await prepare();
      final result = await sales.confirmPrepared('confirm');
      for (final entry in {
        'sales': 'document_id',
        'sale_lines': 'id',
        'sale_outflows': 'id',
        'sale_cost_allocations': 'id',
        'customer_receivables': 'id',
        'sales_drafts': 'id',
        'sale_confirmations': 'command_id',
      }.entries) {
        final rows = await app.database.query(entry.key);
        expect(rows, hasLength(1), reason: entry.key);
        final row = rows.single;
        await blocked(
          app.database.update(entry.key, {entry.value: row[entry.value]}),
          '${entry.key} UPDATE',
        );
        await blocked(app.database.delete(entry.key), '${entry.key} DELETE');
        await blocked(
          app.database.insert(
            entry.key,
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          ),
          '${entry.key} REPLACE',
        );
      }
      expect((await sales.load()).sales.single.documentId, result.documentId);
      expect((await inventory.load()).stock.single.quantity, 1);
      expect((await app.readHealth())['integrityOk'], isTrue);
    },
  );

  test(
    'unique-key aliases cannot replace confirmed rows with a different id',
    () async {
      await prepare();
      final result = await sales.confirmPrepared('confirm');
      for (final table in [
        'sales',
        'sale_lines',
        'sale_outflows',
        'sale_cost_allocations',
        'customer_receivables',
        'journal_entries',
        'journal_lines',
        'business_documents',
      ]) {
        final row = (await app.database.query(
          table,
          where: switch (table) {
            'sales' => 'document_id = ?',
            'sale_lines' => 'sale_id = ?',
            'sale_outflows' || 'journal_entries' => 'document_id = ?',
            'customer_receivables' => 'origin_document_id = ?',
            'business_documents' => 'id = ?',
            _ => null,
          },
          whereArgs: ['sale_cost_allocations', 'journal_lines'].contains(table)
              ? null
              : [result.documentId],
          limit: 1,
        )).single;
        final primaryKey = table == 'sales' ? 'document_id' : 'id';
        await blocked(
          app.database.insert(table, {
            ...row,
            primaryKey: 'replacement:$table',
          }, conflictAlgorithm: ConflictAlgorithm.replace),
          '$table unique alias',
        );
      }
      final current = (await sales.load()).sales.single;
      expect(current.documentId, result.documentId);
      expect(current.totalCostMinor, 668);
    },
  );

  test(
    'prepared input and account cannot be edited erased replaced or falsely completed',
    () async {
      await prepare();
      final confirmation = (await app.database.query(
        'sale_confirmations',
      )).single;
      final draft = (await app.database.query('sales_drafts')).single;
      final line = (await app.database.query('sales_draft_lines')).single;
      final purchaseCommand = (await app.database.query(
        'command_log',
        where: 'id = ?',
        whereArgs: ['purchase'],
      )).single;
      await blocked(
        app.database.insert('command_log', {
          ...purchaseCommand,
          'id': 'confirm',
        }, conflictAlgorithm: ConflictAlgorithm.replace),
        'a purchase cannot consume a reserved sale command identifier',
      );
      for (final update in [
        {'canonical_payload': 'different'},
        {'draft_revision': 2},
        {'occurred_at_utc': '2026-10-20T12:00:00.000Z'},
        {'due_date': '2026-10-22'},
        {'status': 'confirmed'},
        {'status': 'rejected'},
      ]) {
        await blocked(
          app.database.update('sale_confirmations', update),
          '$update',
        );
      }
      await blocked(
        app.database.delete('sale_confirmations'),
        'confirmation DELETE',
      );
      await blocked(
        app.database.insert('sale_confirmations', {
          ...confirmation,
          'command_id': 'replacement-command',
        }, conflictAlgorithm: ConflictAlgorithm.replace),
        'active draft unique alias',
      );
      await blocked(
        app.database.update('sales_drafts', {'label': 'Changed'}),
        'draft UPDATE',
      );
      await blocked(app.database.delete('sales_drafts'), 'draft DELETE');
      await blocked(
        app.database.insert('sales_drafts', {
          ...draft,
          'status': 'open',
        }, conflictAlgorithm: ConflictAlgorithm.replace),
        'draft REPLACE',
      );
      await blocked(
        app.database.update('sales_draft_lines', {'quantity': 1}),
        'line UPDATE',
      );
      await blocked(app.database.delete('sales_draft_lines'), 'line DELETE');
      await blocked(
        app.database.insert('sales_draft_lines', {
          ...line,
          'quantity': 1,
        }, conflictAlgorithm: ConflictAlgorithm.replace),
        'line REPLACE',
      );
      expect(
        (await app.database.query('sale_confirmations')).single,
        confirmation,
      );
      expect((await app.database.query('sales_draft_lines')).single, line);
      expect((await sales.confirmPrepared('confirm')).totalCostMinor, 668);
    },
  );

  test(
    'sale journal is locked between document posting and entry posting',
    () async {
      await prepare();
      await app.database.execute('''
CREATE TRIGGER test_mutate_journal_in_posting_gap
AFTER UPDATE OF status ON business_documents
WHEN NEW.type = 'credit_sale' AND NEW.status = 'posted'
BEGIN
  UPDATE journal_lines SET debit_minor = debit_minor + 1
  WHERE entry_id = (SELECT id FROM journal_entries WHERE document_id = NEW.id)
    AND debit_minor > 0;
END
''');
      await blocked(
        sales.confirmPrepared('confirm'),
        'posting-gap journal mutation',
      );
      expect(await app.database.query('sales'), isEmpty);
      expect(await app.database.query('customer_receivables'), isEmpty);
      expect(await app.database.query('sale_cost_allocations'), isEmpty);
      expect(
        (await app.database.query('sale_confirmations')).single['status'],
        'prepared',
      );
      expect((await inventory.load()).stock.single.quantity, 3);
      await app.database.execute(
        'DROP TRIGGER test_mutate_journal_in_posting_gap',
      );
      expect((await sales.confirmPrepared('confirm')).totalCostMinor, 668);
    },
  );

  test(
    'SQL allocations reject skipped FIFO layers wrong rounding and future stock',
    () async {
      await inventory.receivePurchase(
        ReceiptCommand(
          commandId: 'purchase-newer',
          supplierId: 'supplier',
          lines: const [
            ReceiptLineInput(
              productId: 'product',
              quantity: 3,
              totalCostMinor: 600,
            ),
          ],
          dueDate: '2026-10-21',
          occurredAtUtc: DateTime.utc(2026, 10, 18, 13),
        ),
      );
      await inventory.receivePurchase(
        ReceiptCommand(
          commandId: 'purchase-future',
          supplierId: 'supplier',
          lines: const [
            ReceiptLineInput(
              productId: 'product',
              quantity: 3,
              totalCostMinor: 900,
            ),
          ],
          dueDate: '2026-10-21',
          occurredAtUtc: DateTime.utc(2026, 10, 20, 13),
        ),
      );
      await prepare();
      await _stageSale(app);
      final layers = await app.database.query(
        'cost_layers',
        orderBy: 'fifo_sequence',
      );
      Map<String, Object?> allocation(String layer, int quantity, int cost) => {
        'id': 'allocation',
        'sale_line_id': 'staged-line',
        'cost_layer_id': layer,
        'sequence': 0,
        'quantity': quantity,
        'cost_minor': cost,
      };
      await blocked(
        app.database.insert(
          'sale_cost_allocations',
          allocation(layers[1]['id'] as String, 1, 200),
        ),
        'skip oldest layer',
      );
      await blocked(
        app.database.insert(
          'sale_cost_allocations',
          allocation(layers[2]['id'] as String, 1, 300),
        ),
        'future layer',
      );
      await blocked(
        app.database.insert(
          'sale_cost_allocations',
          allocation(layers[0]['id'] as String, 1, 333),
        ),
        'rounded cost mismatch',
      );
      await blocked(
        app.database.insert(
          'sale_cost_allocations',
          allocation(layers[0]['id'] as String, 3, 1001),
        ),
        'quantity exceeds sale',
      );
      await app.database.insert(
        'sale_cost_allocations',
        allocation(layers[0]['id'] as String, 2, 668),
      );
      final inserted = (await app.database.query(
        'sale_cost_allocations',
      )).single;
      await blocked(
        app.database.update('sale_cost_allocations', {'cost_minor': 667}),
        'allocation cannot be rewritten while document is draft',
      );
      await blocked(
        app.database.delete('sale_cost_allocations'),
        'allocation cannot be deleted',
      );
      await blocked(
        app.database.insert(
          'sale_cost_allocations',
          inserted,
          conflictAlgorithm: ConflictAlgorithm.replace,
        ),
        'allocation cannot be replaced',
      );
      await blocked(
        app.database.update(
          'business_documents',
          {'status': 'posted'},
          where: 'id = ?',
          whereArgs: ['staged-sale'],
        ),
        'cannot post without outflow/receivable/journal',
      );
      expect(
        (await app.database.query(
          'business_documents',
          where: 'id = ?',
          whereArgs: ['staged-sale'],
        )).single['status'],
        'draft',
      );
    },
  );

  test(
    'SQL rejects backdated receipts without rewriting confirmed sale costs',
    () async {
      await prepare();
      await sales.confirmPrepared('confirm');
      await expectLater(
        app.database.transaction((txn) async {
          final sourceDocument = (await txn.query(
            'business_documents',
            where: 'command_id = ?',
            whereArgs: ['purchase'],
          )).single;
          final originalId = sourceDocument['id']! as String;
          final originalCommand = (await txn.query(
            'command_log',
            where: 'id = ?',
            whereArgs: ['purchase'],
          )).single;
          final originalPurchase = (await txn.query('purchases')).single;
          final originalLine = (await txn.query('purchase_lines')).single;
          final originalMovement = (await txn.query(
            'inventory_movements',
          )).single;
          final originalLayer = (await txn.query('cost_layers')).single;
          final originalObligation = (await txn.query('obligations')).single;
          final originalEntry = (await txn.query(
            'journal_entries',
            where: 'document_id = ?',
            whereArgs: [originalId],
          )).single;
          final originalJournal = await txn.query(
            'journal_lines',
            where: 'entry_id = ?',
            whereArgs: [originalEntry['id']],
          );
          await txn.insert('command_log', {
            ...originalCommand,
            'id': 'backdated-command',
          });
          await txn.insert('business_documents', {
            ...sourceDocument,
            'id': 'backdated-receipt',
            'command_id': 'backdated-command',
            'status': 'draft',
          });
          await txn.insert('purchases', {
            ...originalPurchase,
            'document_id': 'backdated-receipt',
          });
          await txn.insert('purchase_lines', {
            ...originalLine,
            'id': 'backdated-line',
            'purchase_id': 'backdated-receipt',
          });
          await txn.insert('inventory_movements', {
            ...originalMovement,
            'id': 'backdated-movement',
            'document_id': 'backdated-receipt',
            'purchase_line_id': 'backdated-line',
            'stock_sequence': 2,
          });
          await txn.insert('cost_layers', {
            ...originalLayer,
            'id': 'backdated-layer',
            'inbound_movement_id': 'backdated-movement',
            'fifo_sequence': 2,
          });
          await txn.insert('obligations', {
            ...originalObligation,
            'id': 'backdated-obligation',
            'origin_document_id': 'backdated-receipt',
          });
          await txn.insert('journal_entries', {
            ...originalEntry,
            'id': 'backdated-entry',
            'document_id': 'backdated-receipt',
            'status': 'draft',
            'posted_at_utc': null,
          });
          for (final line in originalJournal) {
            await txn.insert('journal_lines', {
              ...line,
              'id': 'backdated-journal-${line['sequence']}',
              'entry_id': 'backdated-entry',
            });
          }
          await txn.update(
            'business_documents',
            {'status': 'posted'},
            where: 'id = ?',
            whereArgs: ['backdated-receipt'],
          );
        }),
        throwsA(
          isA<DatabaseException>().having(
            (e) => e.toString(),
            'message',
            contains('A receipt cannot predate a confirmed sale'),
          ),
        ),
      );
      expect(await app.database.query('purchases'), hasLength(1));
      expect((await sales.load()).sales.single.totalCostMinor, 668);
      expect((await inventory.load()).stock.single.totalCostMinor, 333);
    },
  );

  test(
    'SQL rejects a sale dated before another confirmed sale of its product',
    () async {
      await prepare();
      await sales.confirmPrepared('confirm');
      await sales.saveDraft(
        SaveSaleDraft(
          id: 'past-draft',
          label: 'Mesa sintética',
          customerName: 'Cliente sintético',
          expectedRevision: 0,
          lines: const [
            SaleDraftLine(
              productId: 'product',
              quantity: 2,
              unitPriceMinor: 900,
            ),
          ],
        ),
      );
      await sales.prepareConfirmation(
        commandId: 'past-confirm',
        draftId: 'past-draft',
        expectedRevision: 1,
        occurredAtUtc: DateTime.utc(2026, 10, 18, 13),
        dueDate: '2026-10-21',
      );
      await _stageSale(
        app,
        commandId: 'past-confirm',
        draftId: 'past-draft',
        occurredAt: '2026-10-18T13:00:00.000Z',
      );
      await expectLater(
        app.database.update(
          'business_documents',
          {'status': 'posted'},
          where: 'id = ?',
          whereArgs: ['staged-sale'],
        ),
        throwsA(
          isA<DatabaseException>().having(
            (e) => e.toString(),
            'message',
            contains('A sale cannot predate a confirmed sale'),
          ),
        ),
      );
    },
  );
}

/// Deliberately incomplete SQL assembly, used to test database guards rather
/// than reusing the backend's own FIFO validation.
Future<void> _stageSale(
  AppDatabase app, {
  String commandId = 'confirm',
  String draftId = 'draft',
  String occurredAt = '2026-10-19T12:00:00.000Z',
}) async {
  final when = occurredAt;
  await app.database.insert('command_log', {
    'id': commandId,
    'command_type': 'confirm_sale',
    'payload_hash': 'test',
    'actor_id': 'system:local-operator',
    'response_json': '{}',
    'response_version': 1,
    'committed_at_utc': when,
    'authorization_policy_version': 'development-single-user-v1',
  });
  await app.database.insert('business_documents', {
    'id': 'staged-sale',
    'command_id': commandId,
    'command_sequence': 0,
    'profile_id': 'sales-schema-test',
    'actor_id': 'system:local-operator',
    'type': 'credit_sale',
    'status': 'draft',
    'occurred_at_utc': when,
    'business_date': occurredAt.substring(0, 10),
    'recorded_at_utc': when,
    'source_kind': 'synthetic',
    'date_quality': 'documented',
  });
  await app.database.insert('sales', {
    'document_id': 'staged-sale',
    'draft_id': draftId,
    'customer_name_snapshot': 'Cliente sintético',
    'label_snapshot': 'Mesa sintética',
    'sold_at_utc': when,
    'due_date': '2026-10-21',
    'receivable_minor': 1800,
    'total_cost_minor': 668,
    'terms': 'credit',
    'cost_policy': 'fifo-front-remainder-v1',
  });
  await app.database.insert('sale_lines', {
    'id': 'staged-line',
    'sale_id': 'staged-sale',
    'sequence': 0,
    'product_id': 'product',
    'name_snapshot': 'Producto sintético',
    'quantity': 2,
    'unit_price_minor': 900,
    'total_minor': 1800,
    'total_cost_minor': 668,
  });
}
