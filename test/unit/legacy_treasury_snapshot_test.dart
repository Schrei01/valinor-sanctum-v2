import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/features/treasury/data/json_legacy_treasury_store.dart';
import 'package:valinor_sanctum_2/features/treasury/domain/legacy_treasury_snapshot.dart';

void main() {
  late Directory sandbox;
  late File file;
  final invalid = throwsA(isA<LegacyTreasuryFormatException>());

  setUp(() async {
    final root = Directory(p.join(AppConfig.repositoryRootPath, 'tmp'));
    await root.create(recursive: true);
    sandbox = await root.createTemp('legacy_treasury_unit_');
    file = File(p.join(sandbox.path, 'legacy-treasury.json'));
  });

  tearDown(() async {
    final resolved = await sandbox.resolveSymbolicLinks();
    if (!p.isWithin(p.join(AppConfig.repositoryRootPath, 'tmp'), resolved)) {
      throw StateError(
        'Refusing cleanup outside the synthetic test directory.',
      );
    }
    await sandbox.delete(recursive: true);
  });

  LegacyTreasurySnapshot snapshot() => LegacyTreasurySnapshot(
    sourceName: 'synthetic.db',
    sourceSha256: List.filled(64, 'a').join(),
    extractedAtUtc: DateTime.utc(2026, 10, 20, 12),
    moneyScale: 0,
    balances: [
      for (final entry in LegacyTreasurySnapshot.sourceTables.entries)
        LegacyTreasuryBalance(
          role: entry.key,
          sourceTable: entry.value,
          sourceRowId: 2,
          sourceDateRaw: '2026-10-18T01:24:21.123456',
          amountMinor: entry.key == 'reserve' ? -25 : 50,
        ),
    ],
    movements: const [
      LegacyTreasuryMovement(
        sourceTable: 'movimientos',
        sourceRowId: 1,
        type: 'egreso',
        fromRole: 'cash',
        toRole: null,
        amountMinor: 5,
        reason: 'Compra sintética',
        sourceDateRaw: '2026-10-17T20:00:00.123456',
      ),
      LegacyTreasuryMovement(
        sourceTable: 'transfermovements',
        sourceRowId: 1,
        type: 'transferencia',
        fromRole: 'cash',
        toRole: 'nequi',
        amountMinor: 7,
        reason: 'Traslado sintético',
        sourceDateRaw: '2026-10-17T21:00:00',
      ),
    ],
  );

  Map<String, dynamic> document() =>
      jsonDecode(jsonEncode(snapshot().toJson())) as Map<String, dynamic>;

  test('immutable snapshot preserves signed balances and raw dates', () {
    final original = snapshot();
    final roundTrip = LegacyTreasurySnapshot.fromJson(document());
    expect(roundTrip.toJson(), original.toJson());
    expect(roundTrip.balanceByRole('reserve').amountMinor, -25);
    expect(
      roundTrip.balanceByRole('cash').sourceDateRaw,
      '2026-10-18T01:24:21.123456',
    );
    expect(roundTrip.movements.last.fromRole, 'cash');
    expect(roundTrip.movements.last.toRole, 'nequi');
    expect(() => roundTrip.balances.clear(), throwsUnsupportedError);
    expect(() => roundTrip.movements.clear(), throwsUnsupportedError);
  });

  test('all four roles and exact source tables are mandatory and unique', () {
    final missing = document();
    (missing['balances'] as List).removeLast();
    expect(() => LegacyTreasurySnapshot.fromJson(missing), invalid);
    final duplicate = document();
    (duplicate['balances'] as List).add((duplicate['balances'] as List).first);
    expect(() => LegacyTreasurySnapshot.fromJson(duplicate), invalid);
    for (final field in [
      'role',
      'sourceTable',
      'sourceRowId',
      'amountMinor',
      'sourceDateRaw',
    ]) {
      final changed = document();
      ((changed['balances'] as List).first as Map)[field] = switch (field) {
        'role' => 'unknown',
        'sourceTable' => 'nequi',
        'sourceRowId' => 0,
        'amountMinor' => 1.5,
        _ => '2026-02-30T12:00:00',
      };
      expect(
        () => LegacyTreasurySnapshot.fromJson(changed),
        invalid,
        reason: field,
      );
    }
  });

  test(
    'metadata rejects unsupported versions currency scale source and UTC date',
    () {
      for (final entry in <String, Object?>{
        'formatVersion': 2,
        'sourceName': '../source.db',
        'sourceSha256': 'bad',
        'currencyCode': 'USD',
        'moneyScale': 7,
        'extractedAtUtc': '2026-10-20T12:00:00',
      }.entries) {
        final changed = document()..[entry.key] = entry.value;
        expect(
          () => LegacyTreasurySnapshot.fromJson(changed),
          invalid,
          reason: entry.key,
        );
      }
      for (final date in [
        '2026-02-29T12:00:00.000Z',
        '2026-10-20T24:00:00Z',
        '0000-01-01T00:00:00Z',
      ]) {
        final changed = document()..['extractedAtUtc'] = date;
        expect(
          () => LegacyTreasurySnapshot.fromJson(changed),
          invalid,
          reason: date,
        );
      }
    },
  );

  test(
    'history rejects duplicate rows unknown accounts and inconsistent direction',
    () {
      final duplicate = document();
      (duplicate['movements'] as List).add(
        (duplicate['movements'] as List).first,
      );
      expect(() => LegacyTreasurySnapshot.fromJson(duplicate), invalid);
      for (final entry in <String, Object?>{
        'sourceTable': 'sales',
        'sourceRowId': -1,
        'type': 'transferencia',
        'fromRole': 'unknown',
        'toRole': 'cash',
        'amountMinor': 0,
        'reason': ' ',
        'sourceDateRaw': '2026-10-18T25:00:00',
      }.entries) {
        final changed = document();
        ((changed['movements'] as List).first as Map)[entry.key] = entry.value;
        expect(
          () => LegacyTreasurySnapshot.fromJson(changed),
          invalid,
          reason: entry.key,
        );
      }
      final transfer = document();
      ((transfer['movements'] as List).last as Map)['toRole'] = 'cash';
      expect(() => LegacyTreasurySnapshot.fromJson(transfer), invalid);
      final absent = document()..remove('movements');
      expect(LegacyTreasurySnapshot.fromJson(absent).movements, isEmpty);
    },
  );

  test(
    'raw source dates require real calendar dates without adding time zones',
    () {
      for (final date in [
        '2026-02-29T12:00:00',
        '2026-01-01T12:61:00',
        '2026-01-01T12:00:00+99:99',
        'not-a-date',
        '',
      ]) {
        final changed = document();
        ((changed['balances'] as List).first as Map)['sourceDateRaw'] = date;
        expect(
          () => LegacyTreasurySnapshot.fromJson(changed),
          invalid,
          reason: date,
        );
      }
      for (final date in ['2024-02-29T12:00:00', '2026-01-01T12:00:00-05:00']) {
        final changed = document();
        ((changed['balances'] as List).first as Map)['sourceDateRaw'] = date;
        expect(
          LegacyTreasurySnapshot.fromJson(changed).balances.first.sourceDateRaw,
          date,
        );
      }
    },
  );

  test('income points to its account and consultation history is bounded', () {
    final income = document();
    final row = (income['movements'] as List).first as Map;
    row['type'] = 'ingreso';
    row['fromRole'] = null;
    row['toRole'] = 'reserve';
    final loaded = LegacyTreasurySnapshot.fromJson(income);
    expect(loaded.movements.first.fromRole, isNull);
    expect(loaded.movements.first.toRole, 'reserve');
    final tooMany = document();
    tooMany['movements'] = [
      for (var index = 1; index <= 201; index++) {...row, 'sourceRowId': index},
    ];
    expect(() => LegacyTreasurySnapshot.fromJson(tooMany), invalid);
  });

  test(
    'decimal conversion preserves sign scale exact exponents and int64 endpoints',
    () {
      for (final entry in <String, int>{
        '0.0': 0,
        '+25.000': 25,
        '-25.000': -25,
        '1.2e3': 1200,
        '9223372036854775807': 9223372036854775807,
        '-9223372036854775808': -9223372036854775808,
      }.entries) {
        expect(
          legacyTreasuryAmountToMinor(entry.key, moneyScale: 0),
          entry.value,
        );
      }
      expect(legacyTreasuryAmountToMinor('-1.25', moneyScale: 2), -125);
      expect(legacyTreasuryAmountToMinor('1e-6', moneyScale: 6), 1);
      for (final input in <Object?>[
        '1.5',
        '1e-1',
        '9223372036854775808',
        '-9223372036854775809',
        'NaN',
        'Infinity',
        '1e9999',
        1.0,
        null,
      ]) {
        expect(
          () => legacyTreasuryAmountToMinor(input, moneyScale: 0),
          invalid,
          reason: '$input',
        );
      }
      expect(() => legacyTreasuryAmountToMinor('1', moneyScale: -1), invalid);
    },
  );

  test(
    'missing local file is absent but corruption and directories are failures',
    () async {
      final store = JsonLegacyTreasuryStore(file.path);
      expect(await store.load(), isNull);
      await file.writeAsString('{');
      await expectLater(store.load(), invalid);
      await expectLater(JsonLegacyTreasuryStore(sandbox.path).load(), invalid);
    },
  );

  test(
    'verified loading checks fingerprint and parses the same bytes',
    () async {
      final bytes = utf8.encode(jsonEncode(document()));
      await file.writeAsBytes(bytes);
      final expected = sha256.convert(bytes).toString();
      final store = JsonLegacyTreasuryStore(file.path);
      expect(
        (await store.loadVerified(expected.toUpperCase()))!.balances,
        hasLength(4),
      );
      final pinned = JsonLegacyTreasuryStore(
        file.path,
        expectedSha256: expected,
      );
      expect((await pinned.load())!.balances, hasLength(4));
      await file.writeAsString(
        jsonEncode(document()..['sourceName'] = 'changed.db'),
      );
      await expectLater(store.loadVerified(expected), invalid);
      await expectLater(pinned.load(), invalid);
      await expectLater(store.loadVerified('invalid-hash'), invalid);
    },
  );
}
