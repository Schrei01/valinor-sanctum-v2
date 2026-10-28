import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/features/quick_sales/data/sqlite_quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/debtors/data/sqlite_debtors_store.dart';
import 'package:valinor_sanctum_2/features/debtors/domain/debtors_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_store.dart';
import 'package:valinor_sanctum_2/features/reports/data/sqlite_reports_store.dart';
import 'package:valinor_sanctum_2/features/reports/domain/reports_store.dart';
import 'quick_sales_store_test.dart' show fixture;
import '../support/register_debtor.dart';
import '../support/released_v15_fixture.dart' show restoreReleasedV16ForFixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AppDatabase app;
  late SqliteQuickSalesStore store;
  late String person;
  String getPath() => p.join(dir.path, 'sanctum2.sqlite3');
  setUp(() async {
    final root = Directory(
      p.join(AppConfig.repositoryRootPath, 'tmp', 'split-invariants'),
    );
    await root.create(recursive: true);
    dir = await root.createTemp('case-');
    app = await AppDatabase.open(path: getPath());
    await fixture(app, moneyScale: 0);
    store = SqliteQuickSalesStore(app, synthetic: true);
    await store.ensureDefaults();
    person = await registerDebtor(app, 'Persona sintética');
  });
  tearDown(() async {
    await app.close();
    final target = await dir.resolveSymbolicLinks();
    if (!p.isWithin(p.join(AppConfig.repositoryRootPath, 'tmp'), target)) {
      throw StateError('Unsafe cleanup');
    }
    await dir.delete(recursive: true);
  });
  const parts = [
    QuickLinePaymentPart('quick-default:EFECTIVO', 10000),
    QuickLinePaymentPart('quick-default:NEQUI', 5000),
    QuickLinePaymentPart(QuickPaymentOption.creditId, 15000),
  ];
  Future<QuickSaleAccount> save({
    List<QuickLinePaymentPart> payments = parts,
    String? debtor = 'default',
    String id = 'account',
    int quantity = 1,
    int price = 30000,
    List<QuickSaleLine> extra = const [],
  }) => store.saveAccount(
    SaveQuickSaleAccount(
      id: id,
      label: 'Cuenta sintética',
      expectedRevision: 0,
      debtorId: debtor == 'default' ? person : debtor,
      lines: [
        QuickSaleLine(
          id: 'line-$id',
          productId: 'product',
          quantityText: '$quantity',
          unitPriceMinor: price,
          paymentParts: payments,
        ),
        ...extra,
      ],
    ),
  );
  Future<void> prepare(QuickSaleAccount a, {String command = 'confirm'}) async {
    await store.prepareSale(
      commandId: command,
      accountId: a.id,
      expectedRevision: a.revision,
      occurredAtUtc: DateTime.utc(2026, 10, 28, 15),
    );
  }

  Future<String> facts() async => jsonEncode([
    for (final table in [
      'business_documents',
      'journal_entries',
      'journal_lines',
      'sales',
      'sale_lines',
      'collections',
      'customer_receivables',
      'receivable_settlements',
      'quick_sale_split_tenders',
    ])
      [table, await app.database.query(table)],
  ]);
  Future<String> factsWithoutSplit() async => jsonEncode([
    for (final table in [
      'business_documents',
      'journal_entries',
      'journal_lines',
      'sales',
      'sale_lines',
      'collections',
      'customer_receivables',
      'receivable_settlements',
      'quick_sale_requests',
      'quick_sale_line_payments',
      'quick_sale_line_tenders',
      'command_log',
    ])
      [table, await app.database.query(table)],
  ]);

  test(
    'draft and prepared split recover across file reopen, same-product mixed lines count physical stock once',
    () async {
      final a = await save(
        quantity: 2,
        price: 15000,
        extra: const [
          QuickSaleLine(
            id: 'normal',
            productId: 'product',
            unitPriceMinor: 15000,
            paymentOptionId: 'quick-default:NEQUI',
          ),
        ],
      );
      await app.close();
      app = await AppDatabase.open(path: getPath());
      store = SqliteQuickSalesStore(app, synthetic: true);
      expect(
        (await store.load()).accounts.single.lines.first.paymentParts.length,
        3,
      );
      await prepare(a);
      await app.close();
      app = await AppDatabase.open(path: getPath());
      store = SqliteQuickSalesStore(app, synthetic: true);
      expect((await store.load()).pendingSales.single.creditMinor, 15000);
      final result = await store.confirmPrepared('confirm');
      expect(result.totalMinor, 45000);
      final money = await SqliteTreasuryStore(app).load();
      expect(money.cashMinor, 10000);
      expect(money.nequiMinor, 20000);
      expect(money.receivablesMinor, 15000);
      expect((await store.load()).stock.single.quantity, 7);
      expect(await app.database.query('sale_lines'), hasLength(1));
      final initial = await facts();
      await store.confirmPrepared('confirm');
      expect(await facts(), initial);
      final d = SqliteDebtorsStore(app, synthetic: true);
      await d.prepare(
        DebtorCommand(
          commandId: 'abono',
          kind: 'payment',
          debtorId: person,
          amountMinor: 6000,
          paymentOptionId: 'quick-default:NEQUI',
          occurredAtUtc: DateTime.utc(2026, 10, 28, 16),
        ),
      );
      await d.confirm('abono');
      await d.confirm('abono');
      expect((await SqliteTreasuryStore(app).load()).receivablesMinor, 9000);
      expect((await store.load()).stock.single.quantity, 7);
      final report = await SqliteReportsStore(app).load(
        ReportPeriod(
          start: DateTime.utc(2026, 10, 28),
          end: DateTime.utc(2026, 10, 28),
        ),
      );
      expect(report.salesMinor, 45000);
      expect(report.creditSalesMinor, 15000);
      expect(report.debtorPaymentsMinor, 6000);
    },
  );

  test(
    'invalid totals, missing person and insufficient stock never post partial money or stock',
    () async {
      final before = await facts();
      final wrong = await save(
        payments: const [QuickLinePaymentPart('quick-default:EFECTIVO', 29999)],
      );
      await expectLater(
        prepare(wrong),
        throwsA(isA<QuickSalesValidationException>()),
      );
      expect(await facts(), before);
      final unnamed = await save(id: 'unnamed', debtor: null);
      await expectLater(
        prepare(unnamed),
        throwsA(isA<QuickSalesValidationException>()),
      );
      expect(await facts(), before);
      final overstock = await save(
        id: 'too-many',
        quantity: 11,
        payments: const [
          QuickLinePaymentPart(QuickPaymentOption.creditId, 330000),
        ],
      );
      await prepare(overstock, command: 'too-many');
      await expectLater(
        store.confirmPrepared('too-many'),
        throwsA(isA<QuickSalesValidationException>()),
      );
      expect(await facts(), before);
    },
  );

  test(
    'late SQL failure rolls back all composed operations, then exact retry succeeds',
    () async {
      final a = await save();
      await prepare(a);
      final before = await facts();
      await app.database.execute(
        "CREATE TRIGGER synthetic_split_failure BEFORE INSERT ON quick_sale_split_tenders WHEN NEW.sequence=1 BEGIN SELECT RAISE(ABORT,'synthetic failure'); END",
      );
      await expectLater(store.confirmPrepared('confirm'), throwsA(anything));
      expect(await facts(), before);
      expect((await store.load()).pendingSales.single.status, 'prepared');
      await app.database.execute('DROP TRIGGER synthetic_split_failure');
      expect((await store.confirmPrepared('confirm')).creditMinor, 15000);
    },
  );

  test(
    'prepared identity and confirmed split facts cannot be edited, replaced, deleted or appended',
    () async {
      final a = await save();
      await prepare(a);
      await expectLater(
        app.database.update(
          'quick_sales_lines',
          {'payment_split_json': '[]'},
          where: 'id=?',
          whereArgs: ['line-account'],
        ),
        throwsA(anything),
      );
      final row = (await app.database.query(
        'quick_sale_requests',
        where: 'command_id=?',
        whereArgs: ['confirm'],
      )).single;
      final payload =
          jsonDecode(row['canonical_payload'] as String)
              as Map<String, dynamic>;
      (payload['tenders'] as List).first['totalMinor'] = 9999;
      await expectLater(
        app.database.update(
          'quick_sale_requests',
          {'canonical_payload': jsonEncode(payload)},
          where: 'command_id=?',
          whereArgs: ['confirm'],
        ),
        throwsA(anything),
      );
      await store.confirmPrepared('confirm');
      final before = await facts();
      final tender = (await app.database.query(
        'quick_sale_split_tenders',
      )).first;
      await expectLater(
        app.database.delete(
          'quick_sale_split_tenders',
          where: 'id=?',
          whereArgs: [tender['id']],
        ),
        throwsA(anything),
      );
      await expectLater(
        app.database.update(
          'quick_sale_split_tenders',
          {'total_minor': 1},
          where: 'id=?',
          whereArgs: [tender['id']],
        ),
        throwsA(anything),
      );
      await expectLater(
        app.database.rawInsert(
          'INSERT OR REPLACE INTO quick_sale_split_tenders (${tender.keys.join(',')}) VALUES (${List.filled(tender.length, '?').join(',')})',
          tender.values.toList(),
        ),
        throwsA(anything),
      );
      await expectLater(
        app.database.insert('quick_sale_split_tenders', {
          ...tender,
          'id': 'extra',
          'sequence': 99,
        }),
        throwsA(anything),
      );
      expect(await facts(), before);
    },
  );

  test(
    'SQL rejects missing and duplicate split values even when bypassing store',
    () async {
      await save();
      for (final json in [
        '[{}]',
        '[{"paymentOptionId":"quick-debt"}]',
        '[{"paymentOptionId":"quick-debt","amountMinor":-1}]',
        '[{"paymentOptionId":"quick-debt","amountMinor":1},{"paymentOptionId":"quick-debt","amountMinor":2}]',
      ]) {
        await expectLater(
          app.database.update(
            'quick_sales_lines',
            {'payment_split_json': json},
            where: 'id=?',
            whereArgs: ['line-account'],
          ),
          throwsA(anything),
        );
      }
    },
  );

  test(
    'SQL rejects forged split amounts, quantities, duplicated parts and debtor identities',
    () async {
      final a = await save();
      await prepare(a);
      final request = (await app.database.query(
        'quick_sale_requests',
        where: 'command_id=?',
        whereArgs: ['confirm'],
      )).single;
      await app.database.update(
        'quick_sale_requests',
        {'status': 'rejected', 'rejection_reason': 'synthetic'},
        where: 'command_id=?',
        whereArgs: ['confirm'],
      );
      await store.discardRejected('confirm');
      final revision = (await store.load()).accounts.single.revision;
      final before = await facts();
      for (var i = 0; i < 5; i++) {
        final payload =
            jsonDecode(request['canonical_payload'] as String)
                as Map<String, dynamic>;
        final tenders = payload['tenders'] as List;
        switch (i) {
          case 0:
            tenders[0]['totalMinor'] = 11000;
            tenders[1]['totalMinor'] = 4000;
          case 1:
            tenders[1]['partIndex'] = 0;
          case 2:
            (payload['lines'] as List)[0]['quantity'] = 2;
          case 3:
            payload['debtorId'] = 'missing-person';
          case 4:
            tenders[0]['cashAccountId'] = tenders[1]['cashAccountId'];
        }
        await expectLater(
          app.database.insert('quick_sale_requests', {
            ...request,
            'command_id': 'forged-$i',
            'sale_command_id': 'forged-sale-$i',
            'collection_command_id': 'forged-collection-$i',
            'legacy_draft_id': 'forged-draft-$i',
            'account_revision': revision,
            'canonical_payload': jsonEncode(payload),
          }),
          throwsA(anything),
        );
      }
      expect(await facts(), before);
    },
  );

  test(
    'v16 migration preserves released facts and creates a verified v16 backup',
    () async {
      final a = await store.saveAccount(
        SaveQuickSaleAccount(
          id: 'old',
          label: 'Anterior',
          expectedRevision: 0,
          lines: const [
            QuickSaleLine(
              id: 'old-line',
              productId: 'product',
              unitPriceMinor: 1000,
              paymentOptionId: 'quick-default:EFECTIVO',
            ),
          ],
        ),
      );
      await prepare(a, command: 'old');
      await store.confirmPrepared('old');
      await app.database.transaction(restoreReleasedV16ForFixture);
      final oldMigrations = await app.database.query('schema_migrations');
      final oldLines = await app.database.query('quick_sales_lines');
      final before = await factsWithoutSplit();
      await app.close();
      app = await AppDatabase.open(path: getPath());
      store = SqliteQuickSalesStore(app, synthetic: true);
      expect(await factsWithoutSplit(), before);
      final current = await app.database.query('quick_sales_lines');
      for (var i = 0; i < oldLines.length; i++) {
        expect({...current[i]}..remove('payment_split_json'), oldLines[i]);
        expect(current[i]['payment_split_json'], '[]');
      }
      expect(
        (await app.database.query('schema_migrations')).take(16).toList(),
        oldMigrations,
      );
      final backups = await Directory(
        p.join(dir.path, 'backups'),
      ).list().toList();
      expect(backups, hasLength(1));
      expect((await store.load()).sales.single.result.totalMinor, 1000);
      final next = await save();
      await prepare(next);
      expect((await store.confirmPrepared('confirm')).creditMinor, 15000);
    },
  );
}
