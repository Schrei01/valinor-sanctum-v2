import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/features/memberships/data/sqlite_membership_store.dart';
import 'package:valinor_sanctum_2/features/memberships/domain/membership.dart';
import 'package:valinor_sanctum_2/features/memberships/domain/membership_corrections.dart';
import 'package:valinor_sanctum_2/features/quick_sales/data/sqlite_quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/quick_sales_store.dart';
import 'package:valinor_sanctum_2/features/quick_sales/domain/account_voucher.dart';
import 'quick_sales_store_test.dart' show fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase app;
  late SqliteMembershipStore members;
  late SqliteQuickSalesStore sales;
  late String person;
  late DateTime now;
  setUp(() async {
    app = await AppDatabase.open(path: inMemoryDatabasePath);
    await fixture(app, moneyScale: 0);
    members = SqliteMembershipStore(app, synthetic: true);
    sales = SqliteQuickSalesStore(app, synthetic: true);
    await sales.ensureDefaults();
    await sales.ensureBulkProducts();
    now = DateTime.now().toUtc();
    person = await members.savePerson(
      commandId: 'person',
      name: 'Nombre anterior',
      email: 'old@example.com',
      birthDay: 12,
      birthMonth: 6,
    );
  });
  tearDown(() => app.close());
  Future<void> enroll(String id) async {
    final a = await sales.saveAccount(
      SaveQuickSaleAccount(
        id: id,
        label: 'Mensualidad',
        customerName: 'Nombre anterior',
        debtorId: person,
        expectedRevision: 0,
        lines: [
          QuickSaleLine(
            id: '$id-line',
            productId: SqliteMembershipStore.productId,
            unitPriceMinor: 109000,
            paymentOptionId: 'quick-default:EFECTIVO',
          ),
        ],
      ),
    );
    await sales.prepareSale(
      commandId: '$id-sale',
      accountId: id,
      expectedRevision: a.revision,
      occurredAtUtc: now,
    );
    await sales.confirmPrepared('$id-sale');
  }

  Future<Membership> member() async =>
      (await members.load()).singleWhere((m) => m.personId == person);
  CorrectMembershipPerson command(
    String id,
    Membership m, {
    String name = 'Nombre corregido',
    DateTime? start,
  }) => CorrectMembershipPerson(
    commandId: id,
    expected: m,
    name: name,
    email: 'new@example.com',
    birthDay: 21,
    birthMonth: 11,
    start: start ?? m.starts,
  );
  Future<Map<String, String>> facts() async {
    return {
      for (final t in (await app.database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
      )).map((r) => r['name'] as String))
        if (![
          'membership_corrections',
          'membership_profiles',
          'membership_periods',
          'debtors',
        ].contains(t))
          t: jsonEncode(
            (await app.database.query(t)).map(jsonEncode).toList()..sort(),
          ),
    };
  }

  test(
    'registered person name and birthday can be corrected before any enrollment',
    () async {
      final m = await member();
      final before = await facts();
      await members.correctPerson(command('profile', m));
      final next = await member();
      expect(next.name, 'Nombre corregido');
      expect(next.birthDay, 21);
      expect(next.birthMonth, 11);
      expect(next.periodId, isNull);
      expect(next.voucherGrantedMinor, 0);
      expect(await facts(), before);
      expect((await app.database.query('membership_corrections')).length, 1);
    },
  );
  test(
    'audited date/name correction preserves vouchers, posted sales and all money/stock facts; retry is idempotent',
    () async {
      await enroll('enroll');
      var m = await member();
      final lines = allocateVoucher(
        const [
          QuickSaleLine(
            id: 'consume-line',
            productId: 'product',
            unitPriceMinor: 10000,
            useVoucher: true,
          ),
        ],
        m.voucherRemainingMinor,
        m.periodId,
      );
      final a = await sales.saveAccount(
        SaveQuickSaleAccount(
          id: 'consume',
          label: 'Consumo',
          customerName: m.name,
          debtorId: person,
          expectedRevision: 0,
          paymentMode: 'single',
          lines: lines,
        ),
      );
      await sales.prepareSale(
        commandId: 'consume-sale',
        accountId: a.id,
        expectedRevision: a.revision,
        occurredAtUtc: now,
      );
      await sales.confirmPrepared('consume-sale');
      m = await member();
      expect(m.voucherRemainingMinor, 20000);
      final before = await facts();
      final start = m.starts!.subtract(const Duration(days: 1));
      final c = command('edit', m, start: start);
      await members.correctPerson(c);
      await members.correctPerson(c);
      final next = await member();
      expect(next.periodId, m.periodId);
      expect(next.starts, start);
      expect(next.ends, membershipNextMonth(start));
      expect(next.voucherGrantedMinor, 30000);
      expect(next.voucherUsedMinor, 10000);
      expect(next.voucherRemainingMinor, 20000);
      expect(await facts(), before);
      expect(await app.database.query('membership_corrections'), hasLength(1));
      expect(await app.database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await expectLater(
        members.correctPerson(
          command(
            'exclude-consumption',
            next,
            start: membershipDay(now).add(const Duration(days: 1)),
          ),
        ),
        throwsA(isA<QuickSalesValidationException>()),
      );
      final audit = (await app.database.query('membership_corrections')).single;
      await expectLater(
        app.database.update('membership_corrections', {'after_json': '{}'}),
        throwsA(anything),
      );
      await expectLater(
        app.database.delete('membership_corrections'),
        throwsA(anything),
      );
      await expectLater(
        app.database.insert(
          'membership_corrections',
          audit,
          conflictAlgorithm: ConflictAlgorithm.replace,
        ),
        throwsA(anything),
      );
      await expectLater(
        members.correctPerson(command('stale', m)),
        throwsA(isA<QuickSalesValidationException>()),
      );
      await expectLater(
        members.correctPerson(command('edit', m, name: 'Otra solicitud')),
        throwsA(isA<QuickSalesValidationException>()),
      );
    },
  );
  test(
    'a failure after the audit append rolls back the whole correction',
    () async {
      await enroll('rollback');
      final m = await member();
      final before = await facts();
      await app.database.execute(
        "CREATE TRIGGER fail_profile BEFORE UPDATE ON membership_profiles BEGIN SELECT RAISE(ABORT,'injected failure'); END",
      );
      await expectLater(
        members.correctPerson(
          command(
            'rollback-edit',
            m,
            start: m.starts!.subtract(const Duration(days: 1)),
          ),
        ),
        throwsA(anything),
      );
      expect((await member()).name, m.name);
      expect((await member()).starts, m.starts);
      expect(await facts(), before);
      expect(await app.database.query('membership_corrections'), isEmpty);
    },
  );
  test(
    'future renewals cannot overlap and unrelated identities stay protected',
    () async {
      await enroll('first');
      await enroll('second');
      final m = await member();
      final before = await facts();
      await expectLater(
        members.correctPerson(
          command('overlap', m, start: m.starts!.add(const Duration(days: 1))),
        ),
        throwsA(isA<QuickSalesValidationException>()),
      );
      expect(await facts(), before);
      expect(await app.database.query('membership_corrections'), isEmpty);
      await expectLater(
        app.database.update(
          'debtors',
          {'name': 'Directo'},
          where: 'id=?',
          whereArgs: [person],
        ),
        throwsA(anything),
      );
      await expectLater(
        app.database.update(
          'membership_periods',
          {'starts': '2020-01-01'},
          where: 'id=?',
          whereArgs: [m.periodId],
        ),
        throwsA(anything),
      );
      await expectLater(
        app.database.update(
          'membership_voucher_grants',
          {'amount_minor': 90000},
          where: 'period_id=?',
          whereArgs: [m.periodId],
        ),
        throwsA(anything),
      );
    },
  );
  test(
    'duplicate names and invalid birthdays are rejected without partial changes',
    () async {
      await members.savePerson(
        commandId: 'other',
        name: 'Otra persona',
        email: '',
      );
      final m = await member();
      await expectLater(
        members.correctPerson(command('duplicate', m, name: 'Otra persona')),
        throwsA(isA<QuickSalesValidationException>()),
      );
      await expectLater(
        members.correctPerson(
          CorrectMembershipPerson(
            commandId: 'invalid',
            expected: m,
            name: 'Nuevo',
            email: '',
            birthDay: 31,
            birthMonth: 4,
          ),
        ),
        throwsA(isA<QuickSalesValidationException>()),
      );
      expect((await member()).name, m.name);
      expect(await app.database.query('membership_corrections'), isEmpty);
    },
  );
  test(
    'audited dates clamp month ends and keep leap-year calendar months',
    () async {
      await enroll('calendar');
      for (final start in [
        DateTime.utc(2026, 1, 31),
        DateTime.utc(2024, 2, 29),
      ]) {
        final previous = await member();
        final before = await facts();
        await members.correctPerson(
          command('calendar-$start', previous, start: start),
        );
        final corrected = await member();
        expect(corrected.starts, start);
        expect(corrected.ends, membershipNextMonth(start));
        expect(await facts(), before);
      }
    },
  );
}
