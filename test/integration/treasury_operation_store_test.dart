import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/domain/money.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/features/stock_intake/data/sqlite_cash_opening_recorder.dart';
import 'package:valinor_sanctum_2/features/stock_intake/data/sqlite_stock_intake_store.dart';
import 'package:valinor_sanctum_2/features/stock_intake/domain/stock_intake_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_opening_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_operation_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_store.dart';
import 'package:valinor_sanctum_2/features/treasury/domain/treasury_opening.dart';
import 'package:valinor_sanctum_2/features/treasury/domain/treasury_operation_store.dart';
import 'package:valinor_sanctum_2/features/treasury/domain/treasury_store.dart';
import 'package:valinor_sanctum_2/features/workspace/data/sqlite_workspace_store.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase app;
  late SqliteTreasuryOperationStore store;
  late String cash;
  late String nequi;
  const reserve = SqliteTreasuryStore.reserveAccountId;
  final validation = isA<TreasuryValidationException>();

  setUp(() async {
    app = await AppDatabase.open(path: inMemoryDatabasePath);
    await createProfile(app);
    store = SqliteTreasuryOperationStore(app, synthetic: true);
    await store.ensureDefaults();
    final accounts = (await store.load()).accounts;
    cash = accounts.singleWhere((a) => a.role == TreasuryAccountRole.cash).id;
    nequi = accounts.singleWhere((a) => a.role == TreasuryAccountRole.nequi).id;
  });
  tearDown(() => app.close());

  Future<void> opening({
    int cashAmount = 100000,
    int nequiAmount = 50000,
    int reserveAmount = -10000,
  }) async {
    await SqliteTreasuryOpeningStore(app, synthetic: true).importOpening(
      TreasuryOpeningCommand(
        commandId: 'opening',
        sourceSha256: 'a' * 64,
        snapshotSha256: 'b' * 64,
        occurredAtUtc: DateTime.utc(2026, 10, 20, 8),
        cashMinor: cashAmount,
        nequiMinor: nequiAmount,
        reserveMinor: reserveAmount,
        receivablesMinor: 0,
        sourceMetadata: const {'source': 'synthetic'},
      ),
    );
  }

  TreasuryOperationCommand expense(
    String id, {
    String? source,
    int amount = 10000,
    String reason = 'Arriendo',
    String? note,
    DateTime? at,
  }) => TreasuryOperationCommand(
    commandId: id,
    kind: TreasuryOperationKind.expense,
    sourceAccountId: source ?? cash,
    amountMinor: amount,
    reason: reason,
    note: note,
    occurredAtUtc: at ?? DateTime.utc(2026, 10, 20, 10),
  );
  TreasuryOperationCommand transfer(
    String id, {
    String? source,
    String? destination,
    int amount = 10000,
    DateTime? at,
  }) => TreasuryOperationCommand(
    commandId: id,
    kind: TreasuryOperationKind.transfer,
    sourceAccountId: source ?? cash,
    destinationAccountId: destination ?? nequi,
    amountMinor: amount,
    reason: 'Transferencia',
    occurredAtUtc: at ?? DateTime.utc(2026, 10, 20, 10),
  );
  Future<TreasuryOperationResult> record(TreasuryOperationCommand c) async {
    await store.prepare(c);
    return store.confirmPrepared(c.commandId);
  }

  Future<TreasurySnapshot> treasury() => SqliteTreasuryStore(app).load();

  Future<void> addAccount(String id, {String role = 'cash'}) async {
    await app.database.insert('ledger_accounts', {
      'id': 'money:$id',
      'code': 'TEST:$id',
      'name': id,
      'class': 'asset',
      'role': role,
      'is_active': 1,
    });
    await app.database.insert('cash_accounts', {
      'id': id,
      'ledger_account_id': 'money:$id',
      'name': id,
      'kind': 'bank',
      'is_available': 1,
      'is_active': 1,
    });
  }

  test(
    'defaults are idempotent and configure expense ledger without financial facts',
    () async {
      final before = await app.database.query('ledger_accounts');
      await store.ensureDefaults();
      await store.ensureDefaults();
      expect(await app.database.query('ledger_accounts'), before);
      final snapshot = await store.load();
      expect(snapshot.accounts, hasLength(3));
      expect(snapshot.accounts.every((a) => a.balanceMinor == 0), isTrue);
      expect(snapshot.pendingOperations, isEmpty);
      expect(snapshot.confirmedCommandIds, isEmpty);
      for (final table in [
        'actors',
        'command_log',
        'business_documents',
        'journal_entries',
        'journal_lines',
        'treasury_operations',
      ]) {
        expect(await app.database.query(table), isEmpty, reason: table);
      }
    },
  );

  test(
    'expense ledger identity conflicts reject setup without financial facts',
    () async {
      await app.database.update(
        'ledger_accounts',
        {'role': 'wrong-role'},
        where: 'id=?',
        whereArgs: [SqliteTreasuryOperationStore.expenseAccountId],
      );
      await expectLater(store.ensureDefaults(), throwsA(validation));
      expect(await app.database.query('business_documents'), isEmpty);
      expect(await app.database.query('journal_lines'), isEmpty);
    },
  );

  test(
    'expense posts money and expense once without inventory or debts',
    () async {
      await opening();
      final before = await treasury();
      final result = await record(expense('rent', note: '  Octubre  '));
      final snapshot = await treasury();
      expect(snapshot.cashMinor, 90000);
      expect(snapshot.nequiMinor, 50000);
      expect(snapshot.totalAvailableMinor, before.totalAvailableMinor - 10000);
      expect(snapshot.reserveMinor, -10000);
      expect(snapshot.receivablesMinor, 0);
      final header = (await app.database.query('treasury_operations')).single;
      expect(header['note'], 'Octubre');
      expect(header['document_id'], result.documentId);
      expect(
        header['expense_account_id'],
        SqliteTreasuryOperationStore.expenseAccountId,
      );
      final movement = snapshot.movements.singleWhere(
        (m) => m.documentId == result.documentId,
      );
      expect(movement.concept, 'Gasto: Arriendo · Octubre');
      expect(movement.amountMinor, -10000);
      for (final table in [
        'purchases',
        'sales',
        'inventory_movements',
        'customer_receivables',
        'obligations',
      ]) {
        expect(await app.database.query(table), isEmpty, reason: table);
      }
      final document = (await app.database.query(
        'business_documents',
        where: 'id=?',
        whereArgs: [result.documentId],
      )).single;
      expect(document['business_date'], '2026-10-20');
      expect(document['source_kind'], 'synthetic');
      expect(await app.database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );

  test('Nequi expense and Other details are visible in movement', () async {
    await opening();
    final result = await record(
      expense('other', source: nequi, reason: 'Otro', note: 'Reparación'),
    );
    final snapshot = await treasury();
    expect(snapshot.cashMinor, 100000);
    expect(snapshot.nequiMinor, 40000);
    expect(
      snapshot.movements
          .singleWhere((m) => m.documentId == result.documentId)
          .concept,
      'Gasto: Otro · Reparación',
    );
  });

  test('Other expense accepts an optional observation', () async {
    await opening();
    final result = await record(expense('other-no-note', reason: 'Otro'));
    final movement = (await treasury()).movements.singleWhere(
      (m) => m.documentId == result.documentId,
    );
    expect(movement.concept, 'Gasto: Otro');
    expect(
      (await app.database.query('treasury_operations')).single['note'],
      isNull,
    );
  });

  test(
    'other monetary accounts receive transfers while receivable ledgers are excluded',
    () async {
      await opening();
      await addAccount('additional-bank');
      await addAccount('not-money', role: 'receivable');
      final accounts = (await store.load()).accounts;
      expect(
        accounts.singleWhere((a) => a.id == 'additional-bank').role,
        TreasuryAccountRole.other,
      );
      expect(accounts.any((a) => a.id == 'not-money'), isFalse);
      final result = await record(
        TreasuryOperationCommand(
          commandId: 'transfer-other',
          kind: TreasuryOperationKind.transfer,
          sourceAccountId: cash,
          destinationAccountId: 'additional-bank',
          amountMinor: 1000,
          reason: 'Transferencia',
          note: 'Reserva del día',
          occurredAtUtc: DateTime.utc(2026, 10, 20, 10),
        ),
      );
      final snapshot = await treasury();
      expect(snapshot.cashMinor, 99000);
      expect(snapshot.totalAvailableMinor, 149000);
      expect(
        snapshot.accounts
            .singleWhere((a) => a.id == 'additional-bank')
            .balanceMinor,
        1000,
      );
      expect(
        snapshot.movements
            .where((m) => m.documentId == result.documentId)
            .every((m) => m.concept.endsWith(' · Reserva del día')),
        isTrue,
      );
      await expectLater(
        store.prepare(transfer('debt-destination', destination: 'not-money')),
        throwsA(validation),
      );
    },
  );

  test(
    'transfer has two movements and preserves combined available money',
    () async {
      await opening();
      final result = await record(transfer('cash-to-nequi', amount: 20000));
      final snapshot = await treasury();
      expect(snapshot.cashMinor, 80000);
      expect(snapshot.nequiMinor, 70000);
      expect(snapshot.totalAvailableMinor, 150000);
      final movements = snapshot.movements
          .where((m) => m.documentId == result.documentId)
          .toList();
      expect(movements, hasLength(2));
      expect(
        movements.map((m) => m.amountMinor),
        unorderedEquals([-20000, 20000]),
      );
      expect(
        movements.singleWhere((m) => m.cashAccountId == cash).concept,
        startsWith('Transferencia a:'),
      );
      expect(
        movements.singleWhere((m) => m.cashAccountId == nequi).concept,
        startsWith('Transferencia desde:'),
      );
      final header = (await app.database.query('treasury_operations')).single;
      expect(header['expense_account_id'], isNull);
    },
  );

  test(
    'negative reserve can receive money but cannot spend until funded',
    () async {
      await opening();
      await expectLater(
        store.prepare(
          transfer('reserve-out', source: reserve, destination: cash),
        ),
        throwsA(validation),
      );
      await record(transfer('reserve-in', destination: reserve, amount: 15000));
      var snapshot = await treasury();
      expect(snapshot.reserveMinor, 5000);
      expect(snapshot.totalAvailableMinor, 135000);
      await record(
        transfer(
          'reserve-funded',
          source: reserve,
          destination: nequi,
          amount: 5000,
        ),
      );
      snapshot = await treasury();
      expect(snapshot.reserveMinor, 0);
      expect(snapshot.nequiMinor, 55000);
      expect(snapshot.totalAvailableMinor, 140000);
    },
  );

  test(
    'invalid amounts, same accounts, expense source and malformed details are rejected',
    () async {
      await opening();
      for (final command in [
        expense('zero', amount: 0),
        expense('negative', amount: -1),
        transfer('self', destination: cash),
        expense('reserve-expense', source: reserve),
        expense('invalid-reason', reason: 'Inventado'),
        expense('controls', note: 'x\u007f'),
        expense('date-local', at: DateTime(2026, 10, 20)),
        expense('large-note', note: 'a' * 501),
      ]) {
        await expectLater(
          store.prepare(command),
          throwsA(validation),
          reason: command.commandId,
        );
      }
      expect(await app.database.query('treasury_operation_requests'), isEmpty);
    },
  );

  test(
    'prepared request is immutable, no posting, and replay compares intent',
    () async {
      await opening();
      final c = expense('prepared');
      final first = await store.prepare(c);
      final replay = await store.prepare(c);
      expect(replay.preparedAtUtc, first.preparedAtUtc);
      var snapshot = await store.load();
      expect(snapshot.pendingOperations.single.command.commandId, 'prepared');
      expect(snapshot.confirmedCommandIds, isEmpty);
      expect(await app.database.query('treasury_operations'), isEmpty);
      expect(() => snapshot.accounts.clear(), throwsUnsupportedError);
      expect(() => snapshot.pendingOperations.clear(), throwsUnsupportedError);
      expect(
        () => snapshot.confirmedCommandIds.clear(),
        throwsUnsupportedError,
      );
      await expectLater(
        store.prepare(expense('prepared', amount: 1)),
        throwsA(validation),
      );
      final result = await store.confirmPrepared('prepared');
      snapshot = await store.load();
      expect(snapshot.pendingOperations, isEmpty);
      expect(snapshot.confirmedCommandIds, {'prepared'});
      expect(
        (await store.confirmPrepared('prepared')).documentId,
        result.documentId,
      );
      expect(await app.database.query('treasury_operations'), hasLength(1));
    },
  );

  test(
    'command identities cannot collide with purchase parents or reserved children',
    () async {
      await opening();
      final purchases = SqliteStockIntakeStore(app, synthetic: true);
      await purchases.ensureDefaults();
      final category = (await purchases.load()).categories
          .singleWhere((c) => c.name == 'Comestible')
          .id;
      StockIntakeCommand purchase(String id) => StockIntakeCommand(
        commandId: id,
        productId: 'new-product',
        productName: 'Producto sintético',
        categoryId: category,
        supplierName: 'Proveedor sintético',
        unitPurchasePriceMinor: 100,
        listPriceMinor: 200,
        quantity: 1,
        paymentOptionId: 'quick-default:EFECTIVO',
        occurredAtUtc: DateTime.utc(2026, 10, 20, 10),
      );
      await purchases.prepare(purchase('purchase-parent'));
      final reserved = (await app.database.query(
        'paid_purchase_requests',
      )).single;
      for (final id in [
        'opening',
        reserved['command_id'] as String,
        reserved['purchase_command_id'] as String,
        reserved['payment_command_id'] as String,
      ]) {
        await expectLater(store.prepare(expense(id)), throwsA(validation));
      }
      expect(await app.database.query('treasury_operation_requests'), isEmpty);
      await store.prepare(expense('treasury-reserved'));
      await expectLater(
        purchases.prepare(purchase('treasury-reserved')),
        throwsA(
          anyOf(
            isA<StockIntakeValidationException>(),
            isA<DatabaseException>(),
          ),
        ),
      );
      expect(await app.database.query('paid_purchase_requests'), hasLength(1));
      expect(await app.database.query('treasury_operations'), isEmpty);
    },
  );

  test(
    'result replay survives rename and archived accounts after commit',
    () async {
      await opening();
      final command = transfer('replay');
      final result = await record(command);
      await app.database.update(
        'cash_accounts',
        {'name': 'Renombrada', 'is_active': 0},
        where: 'id=?',
        whereArgs: [cash],
      );
      await app.database.update(
        'ledger_accounts',
        {'is_active': 0},
        where: 'id=?',
        whereArgs: [SqliteTreasuryOperationStore.expenseAccountId],
      );
      final replay = await store.confirmPrepared('replay');
      expect(replay.documentId, result.documentId);
      expect((await store.prepare(command)).status, 'confirmed');
      expect(await app.database.query('treasury_operations'), hasLength(1));
    },
  );

  test(
    'pending snapshots retain names while account rename remains valid',
    () async {
      await opening();
      final prepared = await store.prepare(transfer('rename'));
      await app.database.update(
        'cash_accounts',
        {'name': 'Caja renombrada'},
        where: 'id=?',
        whereArgs: [cash],
      );
      final result = await store.confirmPrepared('rename');
      final header = (await app.database.query('treasury_operations')).single;
      expect(
        header['source_account_name_snapshot'],
        prepared.sourceAccountName,
      );
      final movement = (await treasury()).movements.singleWhere(
        (m) => m.documentId == result.documentId && m.cashAccountId == nequi,
      );
      expect(
        movement.concept,
        'Transferencia desde: ${prepared.sourceAccountName}',
      );
    },
  );

  test(
    'accounts becoming unavailable are rejected and can be discarded',
    () async {
      await opening();
      await store.prepare(expense('unavailable'));
      await app.database.update(
        'cash_accounts',
        {'is_available': 0},
        where: 'id=?',
        whereArgs: [cash],
      );
      expect((await store.load()).accounts.any((a) => a.id == cash), isFalse);
      await expectLater(
        store.confirmPrepared('unavailable'),
        throwsA(validation),
      );
      expect((await store.load()).pendingOperations.single.status, 'rejected');
      await store.discardRejected('unavailable');
      await store.discardRejected('unavailable');
      expect((await store.load()).pendingOperations, isEmpty);
      await expectLater(
        store.prepare(expense('unavailable')),
        throwsA(validation),
      );
      expect(await app.database.query('treasury_operations'), isEmpty);
    },
  );

  test('confirmed and live prepared requests cannot be discarded', () async {
    await opening();
    await store.prepare(expense('live'));
    await expectLater(store.discardRejected('live'), throwsA(validation));
    await store.confirmPrepared('live');
    await expectLater(store.discardRejected('live'), throwsA(validation));
  });

  test(
    'competing prepared expenses recheck funds inside atomic confirmation',
    () async {
      await opening(cashAmount: 100);
      await store.prepare(expense('one', amount: 80));
      await store.prepare(expense('two', amount: 80));
      await store.confirmPrepared('one');
      await expectLater(store.confirmPrepared('two'), throwsA(validation));
      expect((await treasury()).cashMinor, 20);
      expect(await app.database.query('treasury_operations'), hasLength(1));
      expect((await store.load()).pendingOperations.single.status, 'rejected');
    },
  );

  test(
    'chronology checks both accounts at prepare and again after competing movement',
    () async {
      await opening();
      await store.prepare(transfer('old', amount: 10));
      await record(
        expense(
          'new-destination',
          source: nequi,
          amount: 10,
          at: DateTime.utc(2026, 10, 20, 11),
        ),
      );
      await expectLater(store.confirmPrepared('old'), throwsA(validation));
      await expectLater(
        store.prepare(transfer('backdated', amount: 10)),
        throwsA(validation),
      );
      await expectLater(
        store.prepare(
          expense('before-opening', at: DateTime.utc(2026, 10, 20, 7)),
        ),
        throwsA(validation),
      );
    },
  );

  test('destination and dashboard total overflow are rejected exactly', () async {
    await opening(
      cashAmount: 10,
      nequiAmount: Money.maxMinorUnits.toInt() - 10,
      reserveAmount: 0,
    );
    // A separate valid opening funds an additional monetary account. Each
    // journal remains in range while transferring into Caja+Nequi can overflow.
    await addAccount('extra-money');
    final defaultOption = (await app.database.query(
      'quick_payment_options',
      where: 'id=?',
      whereArgs: ['quick-default:EFECTIVO'],
    )).single;
    await app.database.insert('quick_payment_options', {
      'id': 'extra-money-option',
      'label': 'Cuenta adicional',
      'cash_account_id': 'extra-money',
      'payment_method_id': defaultOption['payment_method_id'],
      'is_active': 1,
    });
    await SqliteCashOpeningRecorder(app, synthetic: true).record(
      CashOpeningCommand(
        commandId: 'extra-money-opening',
        paymentOptionId: 'extra-money-option',
        amountMinor: 100,
        occurredAtUtc: DateTime.utc(2026, 10, 20, 9),
      ),
    );
    await expectLater(
      store.prepare(
        transfer(
          'total-overflow',
          source: 'extra-money',
          destination: cash,
          amount: 11,
        ),
      ),
      throwsA(validation),
    );
    await record(transfer('fits', amount: 1));
    expect((await treasury()).totalAvailableMinor, Money.maxMinorUnits.toInt());
    await expectLater(
      store.prepare(
        transfer(
          'destination-overflow',
          source: 'extra-money',
          destination: nequi,
          amount: 20,
        ),
      ),
      throwsA(validation),
    );
  });

  test(
    'failure at journal posting rolls all facts back and durable retry succeeds',
    () async {
      await opening();
      await store.prepare(expense('retry'));
      final before = await treasury();
      await app.database.execute('''
CREATE TRIGGER synthetic_treasury_failure BEFORE UPDATE OF status ON journal_entries
WHEN NEW.status='posted'
BEGIN SELECT RAISE(ABORT,'synthetic fault'); END
''');
      await expectLater(
        store.confirmPrepared('retry'),
        throwsA(isA<DatabaseException>()),
      );
      expect((await treasury()).cashMinor, before.cashMinor);
      expect(await app.database.query('treasury_operations'), isEmpty);
      expect(
        await app.database.query(
          'command_log',
          where: 'id=?',
          whereArgs: ['retry'],
        ),
        isEmpty,
      );
      expect((await store.load()).pendingOperations.single.status, 'prepared');
      await app.database.execute('DROP TRIGGER synthetic_treasury_failure');
      await store.confirmPrepared('retry');
      expect((await treasury()).cashMinor, before.cashMinor - 10000);
      expect(await app.database.query('treasury_operations'), hasLength(1));
    },
  );

  test(
    'prepared and confirmed operation survives actual database reopen',
    () async {
      final temp = await Directory(
        p.join(Directory.current.path, 'tmp'),
      ).createTemp('treasury-operations-');
      final path = p.join(temp.path, 'synthetic.sqlite3');
      var disk = await AppDatabase.open(path: path);
      try {
        await createProfile(disk);
        var durable = SqliteTreasuryOperationStore(disk, synthetic: true);
        await durable.ensureDefaults();
        await SqliteTreasuryOpeningStore(disk, synthetic: true).importOpening(
          TreasuryOpeningCommand(
            commandId: 'disk-opening',
            sourceSha256: 'a' * 64,
            snapshotSha256: 'b' * 64,
            occurredAtUtc: DateTime.utc(2026, 10, 20, 8),
            cashMinor: 100,
            nequiMinor: 0,
            reserveMinor: 0,
            receivablesMinor: 0,
            sourceMetadata: const {'source': 'synthetic'},
          ),
        );
        final diskCash = (await durable.load()).accounts
            .singleWhere((a) => a.role == TreasuryAccountRole.cash)
            .id;
        await durable.prepare(
          TreasuryOperationCommand(
            commandId: 'disk-expense',
            kind: TreasuryOperationKind.expense,
            sourceAccountId: diskCash,
            amountMinor: 30,
            reason: 'Aseo',
            occurredAtUtc: DateTime.utc(2026, 10, 20, 10),
          ),
        );
        await disk.close();
        disk = await AppDatabase.open(path: path);
        durable = SqliteTreasuryOperationStore(disk, synthetic: true);
        expect(
          (await durable.load()).pendingOperations.single.command.amountMinor,
          30,
        );
        final result = await durable.confirmPrepared('disk-expense');
        await disk.close();
        disk = await AppDatabase.open(path: path);
        durable = SqliteTreasuryOperationStore(disk, synthetic: true);
        expect(
          (await durable.confirmPrepared('disk-expense')).documentId,
          result.documentId,
        );
        expect((await SqliteTreasuryStore(disk).load()).cashMinor, 70);
        expect(await disk.database.query('treasury_operations'), hasLength(1));
      } finally {
        await disk.close();
        if (p.isWithin(
          p.join(Directory.current.path, 'tmp'),
          temp.absolute.path,
        )) {
          await temp.delete(recursive: true);
        }
      }
    },
  );
}

Future<void> createProfile(AppDatabase app) =>
    SqliteWorkspaceStore(app).createProfile(
      BusinessProfile(
        profileId: 'treasury-operations-test',
        businessName: 'Ludoteca sintética',
        currencyCode: 'COP',
        moneyScale: 2,
        timezone: 'America/Bogota',
        createdAtUtc: DateTime.utc(2026, 10, 20),
      ),
    );
