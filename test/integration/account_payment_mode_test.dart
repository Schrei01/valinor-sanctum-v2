import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/features/quick_sales/application/quick_sales_controller.dart';
import 'package:valinor_sanctum_2/features/quick_sales/data/sqlite_quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_store.dart';
import 'quick_sales_store_test.dart' show fixture;
import '../support/register_debtor.dart';
import '../support/released_v15_fixture.dart' show restoreReleasedV17ForFixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AppDatabase app;
  late QuickSalesController c;
  late SqliteQuickSalesStore store;
  late String person;
  String path() => p.join(dir.path, 'sanctum2.sqlite3');
  setUp(() async {
    final parent = Directory(
      p.join(AppConfig.repositoryRootPath, 'tmp', 'account-payment-tests'),
    );
    await parent.create(recursive: true);
    dir = await parent.createTemp('case-');
    app = await AppDatabase.open(path: path());
    await fixture(app, moneyScale: 0);
    person = await registerDebtor(app, 'Persona sintética');
    store = SqliteQuickSalesStore(app, synthetic: true);
    c = QuickSalesController(
      store: store,
      autosaveDelay: const Duration(days: 1),
    );
    await c.load();
  });
  tearDown(() async {
    c.dispose();
    await app.close();
    final resolved = await dir.resolveSymbolicLinks();
    if (!p.isWithin(p.join(AppConfig.repositoryRootPath, 'tmp'), resolved)) {
      throw StateError('Unsafe cleanup');
    }
    await dir.delete(recursive: true);
  });
  void fill(String id, int index, int quantity) {
    final l = c.accounts.single.lines[index];
    c.editLine(
      id,
      QuickSaleLine(
        id: l.id,
        productId: 'product',
        quantityText: '$quantity',
        unitPriceMinor: 10000,
        paymentOptionId: l.paymentOptionId,
        paymentParts: l.paymentParts,
      ),
    );
  }

  String draft() {
    final id = c.addAccount()!;
    fill(id, 0, 2);
    c.addLine(id);
    fill(id, 1, 1);
    return id;
  }

  Future<void> reopen() async {
    await c.flushAll();
    c.dispose();
    await app.close();
    app = await AppDatabase.open(path: path());
    store = SqliteQuickSalesStore(app, synthetic: true);
    c = QuickSalesController(
      store: store,
      autosaveDelay: const Duration(days: 1),
    );
    await c.load();
  }

  const split = [
    QuickLinePaymentPart('quick-default:EFECTIVO', 10000),
    QuickLinePaymentPart('quick-default:NEQUI', 5000),
    QuickLinePaymentPart(QuickPaymentOption.creditId, 15000),
  ];

  test(
    'one method applies to every line, new rows inherit it, and selection survives reopen',
    () async {
      final id = draft();
      c.selectAccountPayment(id, 'quick-default:NEQUI');
      c.addLine(id);
      fill(id, 2, 1);
      expect(
        c.accounts.single.lines.every(
          (l) => l.paymentOptionId == 'quick-default:NEQUI',
        ),
        isTrue,
      );
      await reopen();
      expect(c.accounts.single.paymentMode, 'single');
      expect(c.accounts.single.singlePaymentOptionId, 'quick-default:NEQUI');
      expect(await c.register(id), isTrue);
      final cash = await SqliteTreasuryStore(app).load();
      expect(cash.nequiMinor, 40000);
      expect(cash.cashMinor, 0);
      expect(cash.receivablesMinor, 0);
      expect((await store.load()).stock.single.quantity, 6);
    },
  );

  test(
    'split locks selection and changed consumption blocks confirmation after file reopen until reviewed',
    () async {
      final id = draft();
      c.selectDebtor(id, person);
      expect(c.divideAccount(id, split), isTrue);
      c.selectAccountPayment(id, 'quick-default:NEQUI');
      expect(c.accounts.single.paymentMode, 'split');
      await reopen();
      expect(c.accounts.single.isPaymentSplit, isTrue);
      expect(c.accounts.single.needsPaymentReview, isFalse);
      fill(id, 0, 1);
      expect(c.accounts.single.needsPaymentReview, isTrue);
      await reopen();
      expect(c.accounts.single.needsPaymentReview, isTrue);
      expect(await c.register(id), isFalse);
      await expectLater(
        store.prepareSale(
          commandId: 'unreviewed',
          accountId: id,
          expectedRevision: c.accounts.single.revision,
          occurredAtUtc: DateTime.utc(2026, 10, 28, 16),
        ),
        throwsA(isA<QuickSalesValidationException>()),
      );
      expect(await app.database.query('sales'), isEmpty);
      expect(
        c.divideAccount(id, const [
          QuickLinePaymentPart('quick-default:EFECTIVO', 5000),
          QuickLinePaymentPart('quick-default:NEQUI', 5000),
          QuickLinePaymentPart(QuickPaymentOption.creditId, 10000),
        ]),
        isTrue,
      );
      expect(c.accounts.single.needsPaymentReview, isFalse);
      expect(await c.register(id), isTrue);
      final cash = await SqliteTreasuryStore(app).load();
      expect(cash.cashMinor, 5000);
      expect(cash.nequiMinor, 5000);
      expect(cash.receivablesMinor, 10000);
    },
  );

  test(
    'return to single removes allocation, requires explicit choice and retains the associated person',
    () async {
      final id = draft();
      c.selectDebtor(id, person);
      c.divideAccount(id, split);
      c.returnToSinglePayment(id);
      expect(c.accounts.single.isPaymentSplit, isFalse);
      expect(c.accounts.single.singlePaymentOptionId, isNull);
      expect(
        c.accounts.single.lines.every(
          (l) => l.paymentParts.isEmpty && l.paymentOptionId == null,
        ),
        isTrue,
      );
      await reopen();
      expect(await c.register(id), isFalse);
      expect(c.accounts.single.debtorId, person);
      c.selectAccountPayment(id, 'quick-default:EFECTIVO');
      expect(await c.register(id), isTrue);
      final cash = await SqliteTreasuryStore(app).load();
      expect(cash.cashMinor, 30000);
      expect(cash.receivablesMinor, 0);
    },
  );

  test(
    'same-total edits and deleting rows require review; renaming alone does not',
    () async {
      final id = draft();
      c.selectDebtor(id, person);
      c.divideAccount(id, split);
      c.rename(id, 'Otra etiqueta');
      expect(c.accounts.single.needsPaymentReview, isFalse);
      // Same total, different quantity/price: still requires review.
      final l = c.accounts.single.lines.first;
      c.editLine(
        id,
        QuickSaleLine(
          id: l.id,
          productId: l.productId,
          quantityText: '1',
          unitPriceMinor: 20000,
          paymentParts: l.paymentParts,
        ),
      );
      expect(c.accounts.single.needsPaymentReview, isTrue);
      c.selectDebtor(id, person);
      expect(c.divideAccount(id, split), isTrue);
      c.removeLine(id, c.accounts.single.lines.last.id);
      expect(c.accounts.single.needsPaymentReview, isTrue);
      await reopen();
      expect(c.accounts.single.needsPaymentReview, isTrue);
    },
  );

  test(
    'v17 pending divided request survives v18 unchanged and new settings are locked while prepared',
    () async {
      final id = draft();
      c.selectDebtor(id, person);
      c.divideAccount(id, split);
      await c.flushAll();
      await store.prepareSale(
        commandId: 'prior',
        accountId: id,
        expectedRevision: c.accounts.single.revision,
        occurredAtUtc: DateTime.utc(2026, 10, 28, 16),
      );
      final original = (await app.database.query(
        'quick_sale_requests',
      )).single['canonical_payload'];
      await expectLater(
        app.database.update(
          'quick_sales_accounts',
          {
            'payment_mode': 'single',
            'revision': c.accounts.single.revision + 1,
          },
          where: 'id=?',
          whereArgs: [id],
        ),
        throwsA(
          predicate<Object>(
            (e) => e.toString().contains(
              'Prepared account payment settings are immutable',
            ),
          ),
        ),
      );
      await app.database.transaction(restoreReleasedV17ForFixture);
      final previous = await app.database.query('schema_migrations');
      c.dispose();
      await app.close();
      app = await AppDatabase.open(path: path());
      store = SqliteQuickSalesStore(app, synthetic: true);
      c = QuickSalesController(store: store);
      await c.load();
      expect(c.accounts.single.paymentMode, 'legacy');
      expect(c.accounts.single.isPaymentSplit, isTrue);
      expect(c.accounts.single.needsPaymentReview, isFalse);
      expect(
        (await app.database.query('schema_migrations')).take(17).toList(),
        previous,
      );
      expect(
        (await app.database.query(
          'quick_sale_requests',
        )).single['canonical_payload'],
        original,
      );
      expect((await store.confirmPrepared('prior')).creditMinor, 15000);
      expect(await Directory(p.join(dir.path, 'backups')).list().length, 1);
    },
  );

  test(
    'SQL rejects unchecked split content and incompatible single payment before preparing',
    () async {
      final id = draft();
      c.selectDebtor(id, person);
      c.divideAccount(id, split);
      await c.flushAll();
      await store.prepareSale(
        commandId: 'template',
        accountId: id,
        expectedRevision: c.accounts.single.revision,
        occurredAtUtc: DateTime.utc(2026, 10, 28, 16),
      );
      final row = Map<String, Object?>.from(
        (await app.database.query('quick_sale_requests')).single,
      );
      await app.database.update(
        'quick_sale_requests',
        {'status': 'rejected', 'rejection_reason': 'synthetic'},
        where: 'command_id=?',
        whereArgs: ['template'],
      );
      await store.discardRejected('template');
      final current = (await store.load()).accounts.single;
      // No other data changes are needed: force an unreviewed content signature.
      await app.database.update(
        'quick_sales_accounts',
        {'payment_split_basis': '[]', 'revision': current.revision + 1},
        where: 'id=?',
        whereArgs: [id],
      );
      final before = await app.database.query('journal_lines');
      await expectLater(
        app.database.insert('quick_sale_requests', {
          ...row,
          'command_id': 'forged',
          'sale_command_id': 'forged-sale',
          'collection_command_id': 'forged-collection',
          'legacy_draft_id': 'forged-draft',
          'account_revision': current.revision + 1,
        }),
        throwsA(
          predicate<Object>(
            (e) => e.toString().contains(
              'Choose an account payment or review the division after consumption changes',
            ),
          ),
        ),
      );
      await app.database.update(
        'quick_sales_accounts',
        {
          'payment_mode': 'single',
          'account_payment_option_id': 'quick-default:EFECTIVO',
          'payment_split_basis': '',
          'revision': current.revision + 2,
        },
        where: 'id=?',
        whereArgs: [id],
      );
      await expectLater(
        app.database.insert('quick_sale_requests', {
          ...row,
          'command_id': 'single-forged',
          'sale_command_id': 'single-sale',
          'collection_command_id': 'single-collection',
          'legacy_draft_id': 'single-draft',
          'account_revision': current.revision + 2,
        }),
        throwsA(
          predicate<Object>(
            (e) => e.toString().contains(
              'Choose an account payment or review the division after consumption changes',
            ),
          ),
        ),
      );
      expect(
        jsonEncode(await app.database.query('journal_lines')),
        jsonEncode(before),
      );
    },
  );
}
