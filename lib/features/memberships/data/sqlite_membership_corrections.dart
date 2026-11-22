import 'dart:convert';
import '../../../core/infrastructure/database/app_database.dart';
import '../domain/membership.dart';
import '../domain/membership_corrections.dart';
import 'sqlite_membership_store.dart';

abstract final class SqliteMembershipCorrections {
  static String nameKey(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  static String? date(DateTime? value) =>
      value?.toIso8601String().substring(0, 10);
  static Map<String, Object?> snapshot(Membership m) => {
    'name': m.name,
    'nameKey': nameKey(m.name),
    'email': m.email,
    'birthDay': m.birthDay,
    'birthMonth': m.birthMonth,
    'periodId': m.periodId,
    'starts': date(m.starts),
    'ends': date(m.ends),
  };
  static Future<void> correct(
    AppDatabase app,
    CorrectMembershipPerson c,
  ) async {
    final name = c.name.trim(), email = c.email.trim();
    if (name.isEmpty ||
        name.length > 120 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(name)) {
      SqliteMembershipStore.fail(
        'Escribe un nombre válido de hasta 120 caracteres.',
      );
    }
    if (email.length > 254 ||
        (email.isNotEmpty &&
            !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email))) {
      SqliteMembershipStore.fail('Revisa el correo electrónico.');
    }
    if ((c.birthDay == null) != (c.birthMonth == null) ||
        (c.birthDay != null &&
            (c.birthMonth! < 1 ||
                c.birthMonth! > 12 ||
                c.birthDay! < 1 ||
                c.birthDay! > DateTime.utc(2000, c.birthMonth! + 1, 0).day))) {
      SqliteMembershipStore.fail('Revisa el día y mes de nacimiento.');
    }
    final start = c.start == null
        ? null
        : DateTime.utc(c.start!.year, c.start!.month, c.start!.day);
    final input = jsonEncode({
      'personId': c.expected.personId,
      'expected': snapshot(c.expected),
      'name': name,
      'email': email,
      'birthDay': c.birthDay,
      'birthMonth': c.birthMonth,
      'start': date(start),
    });
    await app.database.transaction((txn) async {
      final prior = await txn.query(
        'membership_corrections',
        where: 'id=?',
        whereArgs: [c.commandId],
      );
      if (prior.isNotEmpty) {
        if (prior.single['input_json'] != input) {
          SqliteMembershipStore.fail(
            'La solicitud ya corresponde a otra corrección. Vuelve a abrir el formulario.',
          );
        }
        return;
      }
      final current = (await SqliteMembershipStore.read(
        txn,
        DateTime.now().toUtc(),
      )).where((m) => m.personId == c.expected.personId).firstOrNull;
      if (current == null ||
          jsonEncode(snapshot(current)) != jsonEncode(snapshot(c.expected))) {
        SqliteMembershipStore.fail(
          'Los datos cambiaron. Cierra y vuelve a abrir la ficha antes de corregir.',
        );
      }
      final collision = await txn.query(
        'debtors',
        where: 'name_key=? AND id<>?',
        whereArgs: [nameKey(name), current.personId],
      );
      if (collision.isNotEmpty) {
        SqliteMembershipStore.fail('Ya existe otra persona con ese nombre.');
      }
      if (current.periodId == null && start != null ||
          current.periodId != null && start == null) {
        SqliteMembershipStore.fail(
          'La fecha de inicio requiere una mensualidad ya registrada.',
        );
      }
      final end = start == null ? null : membershipNextMonth(start);
      final datesChanged = date(start) != date(current.starts);
      if (datesChanged) {
        if ((await txn.rawQuery(
          'SELECT id FROM membership_periods WHERE person_id=? AND id<>? AND starts<? AND ends>?',
          [current.personId, current.periodId, date(end), date(start)],
        )).isNotEmpty) {
          SqliteMembershipStore.fail(
            'La nueva vigencia se cruza con otra mensualidad de esta persona.',
          );
        }
        if ((await txn.rawQuery(
          '''SELECT r.command_id FROM quick_sale_requests r JOIN quick_sales_accounts a ON a.id=r.account_id
          WHERE a.debtor_id=? AND r.status IN('prepared','rejected')''',
          [current.personId],
        )).isNotEmpty) {
          SqliteMembershipStore.fail(
            'Resuelve la venta pendiente de esta persona antes de cambiar la fecha.',
          );
        }
        if ((await txn.rawQuery(
          '''SELECT v.document_id FROM membership_voucher_collections v
          JOIN membership_voucher_plans p ON p.request_id=v.request_id
          JOIN business_documents d ON d.id=v.document_id AND d.status='posted'
          WHERE p.period_id=? AND (date(d.occurred_at_utc,'-5 hours')<? OR date(d.occurred_at_utc,'-5 hours')>=?)''',
          [current.periodId, date(start), date(end)],
        )).isNotEmpty) {
          SqliteMembershipStore.fail(
            'La nueva vigencia debe incluir los consumos de bono ya registrados.',
          );
        }
      }
      final before = snapshot(current);
      final after = {
        ...before,
        'name': name,
        'nameKey': nameKey(name),
        'email': email,
        'birthDay': c.birthDay,
        'birthMonth': c.birthMonth,
        'starts': date(start),
        'ends': date(end),
      };
      if (jsonEncode(before) == jsonEncode(after)) return;
      await txn.insert('membership_corrections', {
        'id': c.commandId,
        'person_id': current.personId,
        'period_id': current.periodId,
        'input_json': input,
        'before_json': jsonEncode(before),
        'after_json': jsonEncode(after),
        'occurred_at_utc': DateTime.now().toUtc().toIso8601String(),
      });
      await txn.update(
        'debtors',
        {'name': name, 'name_key': nameKey(name)},
        where: 'id=?',
        whereArgs: [current.personId],
      );
      await txn.update(
        'membership_profiles',
        {'email': email, 'birth_day': c.birthDay, 'birth_month': c.birthMonth},
        where: 'person_id=?',
        whereArgs: [current.personId],
      );
      if (datesChanged) {
        await txn.update(
          'membership_periods',
          {'starts': date(start), 'ends': date(end)},
          where: 'id=?',
          whereArgs: [current.periodId],
        );
      }
    }, exclusive: true);
  }
}
