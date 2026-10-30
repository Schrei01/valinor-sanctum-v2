import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/features/quick_sales/data/sqlite_quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/quick_sales_store.dart';
import 'quick_sales_store_test.dart' show fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'creation order survives reversed save completion, edits and a new store',
    () async {
      final db = await AppDatabase.open(path: inMemoryDatabasePath);
      addTearDown(db.close);
      await fixture(db);
      final store = SqliteQuickSalesStore(db, synthetic: true);
      await store.ensureDefaults();
      SaveQuickSaleAccount input(
        String id,
        int micro, {
        int revision = 0,
        String? label,
      }) => SaveQuickSaleAccount(
        id: id,
        label: label ?? id,
        createdAtUtc: DateTime.utc(2026, 10, 30, 12, 0, 0, 0, micro),
        expectedRevision: revision,
        lines: const [],
      );
      await store.saveAccount(input('second', 100));
      await store.saveAccount(input('first', 0));
      await store.saveAccount(input('third', 200));
      expect((await store.load()).accounts.map((a) => a.id), [
        'third',
        'second',
        'first',
      ]);
      await store.saveAccount(
        input('first', 0, revision: 1, label: 'Primera editada'),
      );
      expect(
        (await SqliteQuickSalesStore(db).load()).accounts.map((a) => a.id),
        ['third', 'second', 'first'],
      );
      await expectLater(
        store.saveAccount(input('first', 999, revision: 2)),
        throwsA(isA<QuickSalesValidationException>()),
      );
      await expectLater(
        db.database.update('quick_sales_accounts', {
          'created_at_utc': DateTime.utc(2026, 10, 31).toIso8601String(),
        }),
        throwsA(isA<DatabaseException>()),
      );
    },
  );
}
