import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/features/debtors/data/sqlite_debtors_store.dart';
import 'package:valinor_sanctum_2/features/debtors/domain/debtors_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_store.dart';

Future<String> registerDebtor(AppDatabase app, String name) async {
  final store = SqliteDebtorsStore(app, synthetic: true);
  final prior = (await store.load()).debtors
      .where((p) => p.name == name.trim())
      .firstOrNull;
  if (prior != null) return prior.id;
  final id = InventoryIds.next();
  await store.prepare(
    DebtorCommand(
      commandId: id,
      kind: 'create',
      name: name.trim(),
      occurredAtUtc: DateTime.utc(2026, 10, 19, 12),
    ),
  );
  return store.confirm(id);
}
