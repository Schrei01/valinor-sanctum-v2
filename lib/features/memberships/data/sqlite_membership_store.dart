import 'dart:convert';
import 'dart:math' as math;
import '../../../core/domain/money.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../../core/infrastructure/database/app_database.dart';
import '../../debtors/data/sqlite_debtors_store.dart';
import '../../debtors/domain/debtors_store.dart';

import '../../quick_sales/domain/quick_sales_store.dart';
import '../domain/membership.dart';

class SqliteMembershipStore implements MembershipStore {
  SqliteMembershipStore(this.database, {this.synthetic = false});
  final AppDatabase database;
  final bool synthetic;
  static const productId = 'membership:elven';
  static bool eligible(String name) {
    final n = name.toLowerCase().replaceAll('é', 'e').replaceAll('ó', 'o');
    return n.contains('booster') &&
        (n.contains('magic') ||
            n.contains('pokemon') ||
            RegExp(r'yu[\s\-]*gi|yugi').hasMatch(n));
  }

  static int discounted(int price) =>
      (price ~/ 100) * 80 + ((price % 100) * 80 + 50) ~/ 100;
  static Never fail(String message) =>
      throw QuickSalesValidationException(message);

  static Future<void> ensure(Transaction txn) async {
    final profile = (await txn.query('app_profile')).single;
    final scale = profile['money_scale'] as int;
    final rows = await txn.query(
      'catalog_items',
      where: 'id=?',
      whereArgs: [productId],
    );
    if (rows.isEmpty) {
      await txn.insert('catalog_items', {
        'id': productId,
        'name': 'Mensualidad Élfica',
        'kind': 'product',
        'unit_code': 'unit',
        'quantity_scale': 0,
        'list_price_minor': 109000 * math.pow(10, scale).toInt(),
        'is_active': 1,
      });
      await txn.insert('catalog_services', {
        'product_id': productId,
        'kind': 'day_pass',
      });
    } else if ((await txn.query(
          'catalog_services',
          where: "product_id=? AND kind='day_pass'",
          whereArgs: [productId],
        )).length !=
        1) {
      fail(
        'La identidad de Mensualidad Élfica está ocupada por otro producto.',
      );
    }
  }

  static Future<List<Membership>> read(
    DatabaseExecutor txn,
    DateTime atUtc,
  ) async {
    final profiles = await txn.rawQuery(
      '''SELECT p.*,d.name FROM membership_profiles p JOIN debtors d ON d.id=p.person_id ORDER BY d.name COLLATE NOCASE''',
    );
    final profile = (await txn.query('app_profile')).single;
    final result = <Membership>[];
    final day = membershipDay(atUtc).toIso8601String().substring(0, 10);
    for (final p in profiles) {
      final periods = await txn.rawQuery(
        '''SELECT * FROM membership_periods WHERE person_id=? ORDER BY CASE WHEN starts<=? AND ends>? THEN 0 WHEN starts>? THEN 1 ELSE 2 END, CASE WHEN starts>? THEN starts END ASC, starts DESC''',
        [p['person_id'], day, day, day, day],
      );
      final period = periods.firstOrNull;
      final benefits = period == null
          ? <Map<String, Object?>>[]
          : await txn.query(
              'membership_benefits',
              where: 'period_id=?',
              whereArgs: [period['id']],
            );
      final grants = period == null
          ? <Map<String, Object?>>[]
          : await txn.rawQuery(
              '''SELECT g.amount_minor,
        coalesce((SELECT sum(v.amount_minor) FROM membership_voucher_collections v
          JOIN membership_voucher_plans p ON p.request_id=v.request_id
          JOIN business_documents d ON d.id=v.document_id AND d.status='posted'
          JOIN journal_entries e ON e.document_id=d.id AND e.status='posted'
          WHERE p.period_id=g.period_id),0) used_minor
        FROM membership_voucher_grants g WHERE g.period_id=?''',
              [period['id']],
            );
      result.add(
        Membership(
          personId: p['person_id'] as String,
          name: p['name'] as String,
          email: p['email'] as String,
          moneyScale: profile['money_scale'] as int,
          currencyCode: profile['currency_code'] as String,
          voucherGrantedMinor: grants.firstOrNull?['amount_minor'] as int? ?? 0,
          voucherUsedMinor: grants.firstOrNull?['used_minor'] as int? ?? 0,
          birthDay: p['birth_day'] as int?,
          birthMonth: p['birth_month'] as int?,
          periodId: period?['id'] as String?,
          starts: period == null
              ? null
              : DateTime.parse('${period['starts']}T00:00:00Z'),
          ends: period == null
              ? null
              : DateTime.parse('${period['ends']}T00:00:00Z'),
          includedClaimed: benefits.any((b) => b['kind'] == 'included'),
          discountsUsed: benefits
              .where((b) => b['kind'] == 'discount')
              .fold(0, (n, b) => n + (b['quantity'] as int)),
        ),
      );
    }
    return result;
  }

  @override
  Future<List<Membership>> load({DateTime? atUtc}) => database.database
      .transaction((txn) => read(txn, atUtc ?? DateTime.now().toUtc()));

  @override
  Future<String> savePerson({
    required String commandId,
    String? personId,
    required String name,
    required String email,
    int? birthDay,
    int? birthMonth,
  }) async {
    final address = email.trim();
    if (address.isNotEmpty &&
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(address)) {
      fail('Revisa el correo electrónico.');
    }
    if (address.length > 254 ||
        ((birthDay == null) != (birthMonth == null)) ||
        (birthDay != null &&
            (birthMonth! < 1 ||
                birthMonth > 12 ||
                birthDay < 1 ||
                birthDay > DateTime.utc(2000, birthMonth + 1, 0).day))) {
      fail('Revisa el día y mes de nacimiento.');
    }
    var id = personId;
    if (id == null) {
      final debtors = SqliteDebtorsStore(database, synthetic: synthetic);
      await debtors.prepare(
        DebtorCommand(
          commandId: commandId,
          kind: 'create',
          name: name.trim(),
          occurredAtUtc: DateTime.now().toUtc(),
        ),
      );
      id = await debtors.confirm(commandId);
    }
    await database.database.transaction((txn) async {
      if ((await txn.query(
            'debtors',
            where: 'id=? AND is_active=1',
            whereArgs: [id],
          )).length !=
          1) {
        fail('Selecciona una persona habilitada.');
      }
      final data = {
        'email': address,
        'birth_day': birthDay,
        'birth_month': birthMonth,
      };
      final old = await txn.query(
        'membership_profiles',
        where: 'person_id=?',
        whereArgs: [id],
      );
      if (old.isEmpty) {
        await txn.insert('membership_profiles', {'person_id': id, ...data});
      } else {
        await txn.update(
          'membership_profiles',
          data,
          where: 'person_id=?',
          whereArgs: [id],
        );
      }
    });
    return id;
  }

  /// Snapshot benefit intent before preparing checkout. Revalidated inside the
  /// same exclusive transaction as money, stock, receivables and confirmation.
  static Future<void> prepareSale(
    DatabaseExecutor txn,
    QuickSaleAccount account,
    String requestId,
    DateTime atUtc,
  ) async {
    final signup = account.lines
        .where((l) => l.productId == productId)
        .toList();
    final discounts = account.lines.where((l) => l.membershipDiscount).toList();
    if (discounts.isNotEmpty) {
      fail(
        'Los beneficios de boosters fueron reemplazados por el bono. Quita el descuento anterior.',
      );
    }
    if (signup.isEmpty) return;
    if (account.debtorId == null) {
      fail('Asocia la cuenta a una persona para usar Membresías.');
    }
    final people = await read(txn, atUtc);
    final person = people
        .where((p) => p.personId == account.debtorId)
        .firstOrNull;
    if (person == null) {
      fail('Completa primero los datos de la persona en Membresías.');
    }
    final plans = <Map<String, Object?>>[];
    if (signup.isNotEmpty) {
      final catalog = (await txn.query(
        'catalog_items',
        where: 'id=?',
        whereArgs: [productId],
      )).single;
      if (signup.length != 1 ||
          signup.single.quantityText != '1' ||
          signup.single.unitPriceMinor != catalog['list_price_minor']) {
        fail('Registra una mensualidad por cuenta con su valor vigente.');
      }
      final last = await txn.query(
        'membership_periods',
        where: 'person_id=?',
        whereArgs: [account.debtorId],
        orderBy: 'ends DESC',
        limit: 1,
      );
      var start = membershipDay(atUtc);
      if (last.isNotEmpty) {
        final end = DateTime.parse('${last.single['ends']}T00:00:00Z');
        if (end.isAfter(start)) start = end;
      }
      plans.add({
        'kind': 'signup',
        'personId': person.personId,
        'start': start.toIso8601String().substring(0, 10),
        'end': membershipNextMonth(start).toIso8601String().substring(0, 10),
        'amount': signup.single.unitPriceMinor,
      });
    }
    await txn.insert('membership_sale_plans', {
      'request_id': requestId,
      'payload': jsonEncode(plans),
    });
  }

  static Future<void> confirmSale(
    DatabaseExecutor txn,
    String requestId,
    DateTime atUtc,
  ) async {
    final rows = await txn.query(
      'membership_sale_plans',
      where: 'request_id=?',
      whereArgs: [requestId],
    );
    if (rows.isEmpty) return;
    final plans = (jsonDecode(rows.single['payload'] as String) as List)
        .cast<Map<String, dynamic>>();
    for (final p in plans) {
      if (p['kind'] == 'signup') {
        if (DateTime.parse(
          '${p['start']}T00:00:00Z',
        ).isBefore(membershipDay(DateTime.now().toUtc()))) {
          fail(
            'Cambió el día de inicio. Libera y vuelve a preparar la inscripción.',
          );
        }
        final overlaps = await txn.rawQuery(
          'SELECT id FROM membership_periods WHERE person_id=? AND starts<? AND ends>?',
          [p['personId'], p['end'], p['start']],
        );
        if (overlaps.isNotEmpty) {
          fail(
            'La membresía ya fue renovada desde otra cuenta. Libera y revisa esta venta.',
          );
        }
        await txn.insert('membership_periods', {
          'id': 'membership:$requestId',
          'person_id': p['personId'],
          'sale_request_id': requestId,
          'starts': p['start'],
          'ends': p['end'],
          'amount_minor': p['amount'],
        });
        final profile = (await txn.query('app_profile')).single;
        await txn.insert('membership_voucher_grants', {
          'period_id': 'membership:$requestId',
          'amount_minor':
              30000 * math.pow(10, profile['money_scale'] as int).toInt(),
        });
      } else {
        final member = (await read(
          txn,
          atUtc,
        )).singleWhere((m) => m.personId == p['personId']);
        if (!member.activeAt(DateTime.now().toUtc()) ||
            member.periodId != p['periodId'] ||
            member.discountsUsed + (p['quantity'] as int) > 2) {
          fail(
            'La vigencia o los descuentos disponibles cambiaron. Revisa la cuenta.',
          );
        }
        final product = (await txn.query(
          'catalog_items',
          where: 'id=?',
          whereArgs: [p['productId']],
        )).single;
        if (product['list_price_minor'] != p['base'] ||
            !eligible(product['name'] as String)) {
          fail('Cambió el precio o el booster. Revisa el descuento.');
        }
        await txn.insert('membership_benefits', {
          'id': '$requestId:${p['lineId']}',
          'period_id': p['periodId'],
          'kind': 'discount',
          'product_id': p['productId'],
          'product_name': p['name'],
          'quantity': p['quantity'],
          'base_price_minor': p['base'],
          'charged_minor': p['charged'],
          'occurred_at_utc': atUtc.toIso8601String(),
          'source_id': requestId,
        });
      }
    }
  }

  @override
  Future<void> claimIncluded({
    required String commandId,
    required String periodId,
    required String productId,
    required DateTime atUtc,
  }) async {
    fail('El booster incluido fue reemplazado por el bono de tienda.');
  }

  @override
  Future<List<({String name, String period, String detail})>> history(
    String personId,
  ) async {
    final periods = await database.database.query(
      'membership_periods',
      where: 'person_id=?',
      whereArgs: [personId],
      orderBy: 'starts DESC',
    );
    final result = <({String name, String period, String detail})>[];
    final profile = (await database.database.query('app_profile')).single;
    for (final p in periods) {
      final benefits = await database.database.query(
        'membership_benefits',
        where: 'period_id=?',
        whereArgs: [p['id']],
        orderBy: 'occurred_at_utc',
      );
      final voucherRows = await database.database.rawQuery(
        '''SELECT p.allocations_json,d.occurred_at_utc
        FROM membership_voucher_collections v JOIN membership_voucher_plans p ON p.request_id=v.request_id
        JOIN business_documents d ON d.id=v.document_id AND d.status='posted'
        JOIN journal_entries e ON e.document_id=d.id AND e.status='posted' WHERE p.period_id=? ORDER BY d.occurred_at_utc''',
        [p['id']],
      );
      final voucherEntries = [
        for (final row in voucherRows)
          for (final item
              in jsonDecode(row['allocations_json'] as String) as List)
            'Bono · ${item['quantity']} × ${item['name']} · ${Money.fromMinorUnits(item['amountMinor'] as int, currency: profile['currency_code'] as String, scale: profile['money_scale'] as int).formatEsCo(includeCurrency: true)} · ${_localMoment(row['occurred_at_utc'] as String)}',
      ];
      final oldEntries = benefits.map(
        (b) =>
            'Beneficio anterior · ${b['kind'] == 'included' ? 'Incluido' : '20 % descuento'} · ${b['quantity']} × ${b['product_name']} · ${_localMoment(b['occurred_at_utc'] as String)}',
      );
      final entries = [...oldEntries, ...voucherEntries];
      result.add((
        name:
            '${_dateLabel(DateTime.parse(p['starts'] as String))} al ${_dateLabel(DateTime.parse(p['ends'] as String))}',
        period: p['id'] as String,
        detail: entries.isEmpty ? 'Sin consumos de bono' : entries.join('\n'),
      ));
    }
    return result;
  }

  static String _dateLabel(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  static String _localMoment(String iso) {
    final d = DateTime.parse(iso).toUtc().subtract(const Duration(hours: 5));
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '${_dateLabel(d)} $h:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
  }
}
