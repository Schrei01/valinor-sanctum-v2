import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/features/quick_sales/application/quick_sales_controller.dart';
import 'package:valinor_sanctum_2/features/quick_sales/data/sqlite_quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_store.dart';
import 'package:valinor_sanctum_2/features/reports/data/sqlite_reports_store.dart';
import 'package:valinor_sanctum_2/features/reports/domain/reports_store.dart';
import 'package:valinor_sanctum_2/features/stock_intake/data/sqlite_stock_intake_store.dart';
import 'quick_sales_store_test.dart' show fixture;
import '../support/register_debtor.dart';
import '../support/released_v15_fixture.dart' show restoreReleasedV24ForFixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase app;
  late QuickSalesController c;
  late SqliteQuickSalesStore store;
  late String person;
  setUp(() async {
    app = await AppDatabase.open(path: inMemoryDatabasePath);
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
  });
  String account({int? value = 5000, String productId = 'bulk:sales:magic'}) {
    final id = c.addAccount()!;
    final first = c.accounts.first.lines.first;
    c.editLine(
      id,
      QuickSaleLine(
        id: first.id,
        productId: 'product',
        quantityText: '1',
        unitPriceMinor: 3000,
      ),
    );
    c.addLine(id);
    final second = c.accounts.first.lines.last;
    c.editLine(
      id,
      QuickSaleLine(
        id: second.id,
        productId: productId,
        quantityText: '1',
        unitPriceMinor: value,
      ),
    );
    c.selectDebtor(id, person);
    return id;
  }

  test(
    'three variable-price bulk items are always available and absent from purchases',
    () async {
      await store.ensureBulkProducts();
      await c.load();
      final bulk = c.snapshot!.availableProducts
          .where((p) => p.isVariablePrice && p.name.startsWith('Bulk '))
          .toList();
      expect(bulk.map((p) => p.name).toSet(), {
        'Bulk Magic',
        'Bulk Pokémon',
        'Bulk Yu-Gi-Oh!',
      });
      expect(bulk.every((p) => p.isUnlimited && p.listPriceMinor == 0), isTrue);
      final intake = SqliteStockIntakeStore(app, synthetic: true);
      await intake.ensureDefaults();
      expect(
        (await intake.load()).products.any((p) => p.isVariablePrice),
        isFalse,
      );
      expect(
        await app.database.query('catalog_services', where: "kind='bulk'"),
        hasLength(4),
      );
    },
  );
  for (final variableId in ['bulk:sales:magic', 'rental:sales:games']) {
    for (final mode in ['cash', 'transfer', 'credit', 'split']) {
      test(
        'physical item and $variableId share one account and $mode payment with exact reports and stock',
        () async {
          final id = account(productId: variableId);
          if (mode == 'split') {
            expect(
              c.divideAccount(id, const [
                QuickLinePaymentPart('quick-default:EFECTIVO', 3000),
                QuickLinePaymentPart('quick-default:NEQUI', 2000),
                QuickLinePaymentPart(QuickPaymentOption.creditId, 3000),
              ]),
              isTrue,
            );
          } else {
            c.selectAccountPayment(
              id,
              mode == 'cash'
                  ? 'quick-default:EFECTIVO'
                  : mode == 'transfer'
                  ? 'quick-default:NEQUI'
                  : QuickPaymentOption.creditId,
            );
          }
          expect(c.totalFor(c.accounts.single), BigInt.from(8000));
          expect(await c.register(id), isTrue);
          final data = await store.load();
          expect(data.sales, hasLength(1));
          expect(
            data.stock.singleWhere((s) => s.productId == 'product').quantity,
            9,
          );
          final cash = await SqliteTreasuryStore(app).load();
          expect(
            cash.cashMinor,
            mode == 'cash'
                ? 8000
                : mode == 'split'
                ? 3000
                : 0,
          );
          expect(
            cash.nequiMinor,
            mode == 'transfer'
                ? 8000
                : mode == 'split'
                ? 2000
                : 0,
          );
          expect(
            cash.receivablesMinor,
            mode == 'credit'
                ? 8000
                : mode == 'split'
                ? 3000
                : 0,
          );
          final bulk = (await app.database.query(
            'sale_lines',
            where: 'product_id=?',
            whereArgs: [variableId],
          )).single;
          expect(bulk['quantity'], 1);
          expect(bulk['unit_price_minor'], 5000);
          expect(bulk['total_minor'], 5000);
          expect(bulk['total_cost_minor'], 0);
          expect(
            await app.database.query(
              'sale_outflows',
              where: 'sale_line_id=?',
              whereArgs: [bulk['id']],
            ),
            isEmpty,
          );
          expect(
            (await app.database.query(
              'catalog_items',
              where: 'id=?',
              whereArgs: [variableId],
            )).single['list_price_minor'],
            0,
          );
          final now = DateTime.now().toUtc().subtract(const Duration(hours: 5));
          final period = ReportPeriod(
            start: DateTime.utc(now.year, now.month, now.day),
            end: DateTime.utc(now.year, now.month, now.day, 23, 59),
          );
          final report = await SqliteReportsStore(app).load(period);
          final item = report.groupedItems.singleWhere(
            (i) =>
                i.productName ==
                (variableId == 'rental:sales:games'
                    ? 'Alquiler'
                    : 'Bulk Magic'),
          );
          expect(item.quantity, 1);
          expect(item.amountMinor, 5000);
          expect(
            await app.database.rawQuery('PRAGMA foreign_key_check'),
            isEmpty,
          );
        },
      );
    }
  }
  for (final value in [null, 0, -1]) {
    test('rental rejects missing, zero or negative amount: $value', () async {
      final id = account(productId: 'rental:sales:games', value: value);
      c.selectAccountPayment(id, 'quick-default:EFECTIVO');
      expect(await c.register(id), isFalse);
      expect(await app.database.query('sales'), isEmpty);
      expect((await SqliteTreasuryStore(app).load()).cashMinor, 0);
    });
  }
  test(
    'missing value blocks the whole account; edited amount invalidates its saved split',
    () async {
      final id = account(value: null);
      c.selectAccountPayment(id, 'quick-default:EFECTIVO');
      expect(await c.register(id), isFalse);
      expect(await app.database.query('sales'), isEmpty);
      final line = c.accounts.single.lines.last;
      c.editLine(
        id,
        QuickSaleLine(
          id: line.id,
          productId: line.productId,
          quantityText: '1',
          unitPriceMinor: 5000,
        ),
      );
      expect(
        c.divideAccount(id, const [
          QuickLinePaymentPart('quick-default:EFECTIVO', 8000),
        ]),
        isTrue,
      );
      c.editLine(
        id,
        QuickSaleLine(
          id: line.id,
          productId: line.productId,
          quantityText: '1',
          unitPriceMinor: 7000,
          paymentParts: c.accounts.single.lines.last.paymentParts,
        ),
      );
      expect(c.accounts.single.needsPaymentReview, isTrue);
      expect(await c.register(id), isFalse);
      expect(await app.database.query('sales'), isEmpty);
    },
  );
  test('zero values and card quantities cannot bypass the backend', () async {
    for (final productId in ['bulk:sales:magic', 'rental:sales:games']) {
      for (final entry in [(0, '1'), (-1, '1'), (5000, '2')]) {
        await expectLater(() async {
          final saved = await store.saveAccount(
            SaveQuickSaleAccount(
              id: 'bad-$productId-${entry.$2}-${entry.$1}',
              label: 'Inválida',
              expectedRevision: 0,
              lines: [
                QuickSaleLine(
                  id: 'bad-line-$productId-${entry.$2}-${entry.$1}',
                  productId: productId,
                  quantityText: entry.$2,
                  unitPriceMinor: entry.$1,
                  paymentOptionId: 'quick-default:EFECTIVO',
                ),
              ],
            ),
          );
          await store.prepareSale(
            commandId: 'command-${saved.id}',
            accountId: saved.id,
            expectedRevision: saved.revision,
            occurredAtUtc: DateTime.now().toUtc(),
          );
        }, throwsA(isA<QuickSalesValidationException>()));
      }
    }
    expect(await app.database.query('sales'), isEmpty);
  });
  test('migration v24 preserves a prepared sale and all historical rows', () async {
    // Separate legacy fixture has no bulk defaults; the real app adds them on entry.
    final folder = await Directory(
      p.join(AppConfig.repositoryRootPath, 'tmp'),
    ).createTemp('bulk-migration-');
    final path = p.join(folder.path, 'sanctum2.sqlite3');
    AppDatabase? disk;
    try {
      disk = await AppDatabase.open(path: path);
      await fixture(disk, moneyScale: 0);
      final quick = SqliteQuickSalesStore(disk, synthetic: true);
      await quick.ensureDefaults();
      final saved = await quick.saveAccount(
        SaveQuickSaleAccount(
          id: 'old',
          label: 'Venta anterior',
          expectedRevision: 0,
          lines: [
            const QuickSaleLine(
              id: 'line',
              productId: 'product',
              quantityText: '1',
              unitPriceMinor: 3000,
              paymentOptionId: 'quick-default:EFECTIVO',
            ),
          ],
        ),
      );
      await quick.prepareSale(
        commandId: 'old-request',
        accountId: saved.id,
        expectedRevision: saved.revision,
        occurredAtUtc: DateTime.utc(2026, 11, 6, 15),
      );
      await disk.close();
      disk = null;
      final raw = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await raw.transaction(restoreReleasedV24ForFixture);
      final before = <String, String>{
        for (final table in await raw.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name<>'schema_migrations'",
        ))
          table['name'] as String: jsonEncode(
            (await raw.query(table['name'] as String)).map(jsonEncode).toList()
              ..sort(),
          ),
      };
      await raw.close();
      disk = await AppDatabase.open(path: path);
      for (final row in before.entries) {
        expect(
          jsonEncode(
            (await disk.database.query(row.key)).map(jsonEncode).toList()
              ..sort(),
          ),
          row.value,
          reason: row.key,
        );
      }
      final reopened = SqliteQuickSalesStore(disk, synthetic: true);
      await reopened.ensureBulkProducts();
      await reopened.confirmPrepared('old-request');
      await reopened.confirmPrepared('old-request');
      expect(await disk.database.query('sales'), hasLength(1));
    } finally {
      await disk?.close();
      final resolved = await folder.resolveSymbolicLinks();
      if (!p.isWithin(p.join(AppConfig.repositoryRootPath, 'tmp'), resolved)) {
        throw StateError('Unsafe cleanup');
      }
      await folder.delete(recursive: true);
    }
  });
  test(
    'different customers keep independent bulk values and reports never use the zero catalog price',
    () async {
      final first = account();
      c.selectAccountPayment(first, 'quick-default:EFECTIVO');
      expect(await c.register(first), isTrue);
      final second = account(value: 7000);
      c.selectAccountPayment(second, 'quick-default:EFECTIVO');
      expect(await c.register(second), isTrue);
      final bulk = await app.database.query(
        'sale_lines',
        where: "product_id='bulk:sales:magic'",
        orderBy: 'rowid',
      );
      expect(bulk.map((row) => row['total_minor']), [5000, 7000]);
      final now = DateTime.now().toUtc().subtract(const Duration(hours: 5));
      final report = await SqliteReportsStore(app).load(
        ReportPeriod(
          start: DateTime.utc(now.year, now.month, now.day),
          end: DateTime.utc(now.year, now.month, now.day, 23, 59),
        ),
      );
      final group = report.groupedItems.singleWhere(
        (item) => item.productName == 'Bulk Magic',
      );
      expect(group.amountMinor, 12000);
      expect(group.quantity, 2);
      expect(
        (await app.database.query(
          'catalog_items',
          where: "id='bulk:sales:magic'",
        )).single['list_price_minor'],
        0,
      );
    },
  );
  for (final variableId in ['bulk:sales:magic', 'rental:sales:games']) {
    test(
      'saved mixed account and prepared $variableId value survive real database reopen and retries',
      () async {
        final id = account(productId: variableId);
        c.selectAccountPayment(id, 'quick-default:NEQUI');
        await c.flushAll();
        final folder = await Directory(
          p.join(AppConfig.repositoryRootPath, 'tmp'),
        ).createTemp('bulk-reopen-');
        final path = p.join(folder.path, 'sanctum2.sqlite3');
        AppDatabase? disk;
        try {
          await app.database.execute('VACUUM INTO ?', [path]);
          disk = await AppDatabase.open(path: path);
          var quick = SqliteQuickSalesStore(disk, synthetic: true);
          final saved = (await quick.load()).accounts.single;
          expect(saved.lines.last.unitPriceMinor, 5000);
          expect(saved.lines.last.quantityText, '1');
          await quick.prepareSale(
            commandId: 'bulk-request',
            accountId: id,
            expectedRevision: saved.revision,
            occurredAtUtc: DateTime.now().toUtc(),
          );
          await disk.close();
          disk = null;
          disk = await AppDatabase.open(path: path);
          quick = SqliteQuickSalesStore(disk, synthetic: true);
          await quick.ensureBulkProducts();
          await quick.confirmPrepared('bulk-request');
          await quick.confirmPrepared('bulk-request');
          expect(await disk.database.query('sales'), hasLength(1));
          expect((await SqliteTreasuryStore(disk).load()).nequiMinor, 8000);
          expect(
            (await disk.database.query(
              'sale_lines',
              where: 'product_id=?',
              whereArgs: [variableId],
            )).single['total_minor'],
            5000,
          );
        } finally {
          await disk?.close();
          final resolved = await folder.resolveSymbolicLinks();
          if (!p.isWithin(
            p.join(AppConfig.repositoryRootPath, 'tmp'),
            resolved,
          )) {
            throw StateError('Unsafe cleanup');
          }
          await folder.delete(recursive: true);
        }
      },
    );
  }
}
