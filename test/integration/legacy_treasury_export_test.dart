import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/features/treasury/data/json_legacy_treasury_store.dart';
import 'package:valinor_sanctum_2/features/treasury/domain/legacy_treasury_snapshot.dart';

import '../../tool/export_legacy_treasury.dart' as exporter;

void main() {
  late Directory sandbox;
  late Directory outputDirectory;
  late String source;
  late String output;

  setUp(() async {
    sqfliteFfiInit();
    final temporaryRoot = Directory(
      p.join(AppConfig.repositoryRootPath, 'tmp'),
    );
    final testRoot = Directory(
      p.join(AppConfig.repositoryRootPath, 'data', 'test'),
    );
    await temporaryRoot.create(recursive: true);
    await testRoot.create(recursive: true);
    sandbox = await temporaryRoot.createTemp('legacy_treasury_export_');
    outputDirectory = await testRoot.createTemp('legacy_treasury_export_');
    source = p.join(sandbox.path, 'synthetic.db');
    output = p.join(outputDirectory.path, 'legacy-treasury.json');
    final db = await databaseFactoryFfi.openDatabase(
      source,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      for (final table in LegacyTreasurySnapshot.sourceTables.values) {
        await db.execute(
          'CREATE TABLE $table (id INTEGER PRIMARY KEY,total REAL NOT NULL,fecha TEXT)',
        );
        await db.rawInsert('INSERT INTO $table VALUES (1,999,?)', [
          '2026-10-19T12:00:00',
        ]);
        await db.rawInsert('INSERT INTO $table VALUES (2,?,?)', [
          table == 'caja_mayor' ? -25 : 50,
          '2026-10-18T12:00:00.123456',
        ]);
      }
      await db.execute(
        'CREATE TABLE movimientos (id INTEGER PRIMARY KEY,tipo TEXT,cuenta TEXT,monto REAL,motivo TEXT,fecha TEXT)',
      );
      await db.execute(
        'CREATE TABLE transfermovements (id INTEGER PRIMARY KEY,tipo TEXT,cuenta_origen TEXT,cuenta_destino TEXT,monto REAL,motivo TEXT,fecha TEXT)',
      );
      await db.execute(
        "INSERT INTO movimientos VALUES (1,'egreso','Caja',5,'Compra sintética','2026-10-17T12:00:00')",
      );
      await db.execute(
        "INSERT INTO transfermovements VALUES (1,'transferencia','Caja','Nequi',7,'Traslado sintético','2026-10-17T13:00:00')",
      );
      await db.execute('CREATE TABLE private_data (secret TEXT)');
      await db.execute(
        "INSERT INTO private_data VALUES ('must-not-be-exported')",
      );
    } finally {
      await db.close();
    }
  });

  tearDown(() async {
    for (final dir in [sandbox, outputDirectory]) {
      final canonical = await dir.resolveSymbolicLinks();
      if (!(p.isWithin(
            p.join(AppConfig.repositoryRootPath, 'tmp'),
            canonical,
          ) ||
          p.isWithin(
            p.join(AppConfig.repositoryRootPath, 'data', 'test'),
            canonical,
          ))) {
        throw StateError(
          'Refusing cleanup outside synthetic test directories.',
        );
      }
      await dir.delete(recursive: true);
    }
  });

  Future<LegacyTreasurySnapshot> extract({
    int scale = 0,
    String? destination,
  }) => exporter.exportLegacyTreasury(
    sourcePath: source,
    outputPath: destination ?? output,
    moneyScale: scale,
    extractedAtUtc: DateTime.utc(2026, 10, 20, 12),
  );

  Future<void> change(Future<void> Function(Database) body) async {
    final db = await databaseFactoryFfi.openDatabase(
      source,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      await body(db);
    } finally {
      await db.close();
    }
  }

  test(
    'latest ID balances preserve negatives without touching source or exporting other tables',
    () async {
      final before = await File(source).readAsBytes();
      final exported = await extract();
      expect(await File(source).readAsBytes(), before);
      for (final suffix in ['-journal', '-wal', '-shm']) {
        expect(await File('$source$suffix').exists(), isFalse);
      }
      expect(exported.sourceSha256, sha256.convert(before).toString());
      expect(exported.balances.map((row) => row.sourceRowId), [2, 2, 2, 2]);
      expect(exported.balanceByRole('cash').amountMinor, 50);
      expect(exported.balanceByRole('reserve').amountMinor, -25);
      expect(exported.movements.map((row) => row.sourceTable), [
        'transfermovements',
        'movimientos',
      ]);
      final text = await File(output).readAsString();
      expect(text, isNot(contains('must-not-be-exported')));
      expect(text, isNot(contains(source)));
      final loaded = (await JsonLegacyTreasuryStore(output).load())!;
      expect(loaded.toJson(), exported.toJson());
      final again = p.join(outputDirectory.path, 'second.json');
      await extract(destination: again);
      expect(await File(again).readAsString(), text);
    },
  );

  test(
    'history selects latest 50 per account across both tables with transfer deduplication',
    () async {
      await change((db) async {
        await db.delete('movimientos');
        await db.delete('transfermovements');
        for (var index = 0; index < 120; index++) {
          final date = DateTime.utc(
            2026,
            10,
            17,
            12,
          ).add(Duration(seconds: index)).toIso8601String().replaceAll('Z', '');
          await db.rawInsert('INSERT INTO movimientos VALUES (?,?,?,?,?,?)', [
            index + 1,
            'egreso',
            'Caja',
            1,
            'Sintético',
            date,
          ]);
          await db.rawInsert('INSERT INTO movimientos VALUES (?,?,?,?,?,?)', [
            index + 121,
            'egreso',
            'Nequi',
            1,
            'Sintético',
            date,
          ]);
        }
        for (var index = 0; index < 2; index++) {
          await db.rawInsert(
            'INSERT INTO transfermovements VALUES (?,?,?,?,?,?,?)',
            [
              index + 1,
              'transferencia',
              'Caja',
              'Nequi',
              1,
              'Sintético',
              '2026-10-18T12:00:0$index',
            ],
          );
        }
      });
      final exported = await extract();
      expect(exported.movements, hasLength(98));
      for (final role in ['cash', 'nequi']) {
        expect(
          exported.movements.where(
            (row) => row.fromRole == role || row.toRole == role,
          ),
          hasLength(50),
        );
      }
      expect(
        exported.movements.where((row) => row.type == 'transferencia'),
        hasLength(2),
      );
      expect(exported.movements.first.sourceRowId, 2);
    },
  );

  test(
    'fractions are never rounded and explicit scale conversion is exact',
    () async {
      await change((db) async {
        await db.execute('UPDATE cash SET total=1.25 WHERE id=2');
      });
      await expectLater(
        extract(),
        throwsA(isA<LegacyTreasuryFormatException>()),
      );
      expect(await File(output).exists(), isFalse);
      final result = await extract(scale: 2);
      expect(result.balanceByRole('cash').amountMinor, 125);
      expect(result.balanceByRole('reserve').amountMinor, -2500);
    },
  );

  test('existing snapshot is never replaced', () async {
    await extract();
    final original = await File(output).readAsBytes();
    await expectLater(extract(), throwsStateError);
    expect(await File(output).readAsBytes(), original);
  });

  test(
    'missing source and output outside data are rejected without creating files',
    () async {
      final missing = p.join(sandbox.path, 'missing.db');
      await expectLater(
        exporter.exportLegacyTreasury(
          sourcePath: missing,
          outputPath: output,
          moneyScale: 0,
        ),
        throwsArgumentError,
      );
      expect(await File(missing).exists(), isFalse);
      final outside = p.join(sandbox.path, 'outside.json');
      await expectLater(extract(destination: outside), throwsArgumentError);
      expect(await File(outside).exists(), isFalse);
      expect(await File(output).exists(), isFalse);
    },
  );

  test(
    'missing required saldo or invalid source date cannot create partial output',
    () async {
      await change((db) async {
        await db.delete('deudas');
      });
      await expectLater(
        extract(),
        throwsA(isA<LegacyTreasuryFormatException>()),
      );
      expect(await File(output).exists(), isFalse);
      await change((db) async {
        await db.execute(
          "INSERT INTO deudas VALUES (1,1,'2026-02-30T12:00:00')",
        );
      });
      await expectLater(
        extract(),
        throwsA(isA<LegacyTreasuryFormatException>()),
      );
      expect(await File(output).exists(), isFalse);
    },
  );

  test(
    'optional historical tables may be absent without fabricating movements',
    () async {
      await change((db) async {
        await db.execute('DROP TABLE movimientos');
        await db.execute('DROP TABLE transfermovements');
      });
      final result = await extract();
      expect(result.movements, isEmpty);
      final raw = jsonDecode(await File(output).readAsString()) as Map;
      expect(raw['balances'], hasLength(4));
      expect(raw['movements'], isEmpty);
    },
  );

  test(
    'nonempty SQLite source sidecars are rejected before opening or creating output',
    () async {
      final before = await File(source).readAsBytes();
      for (final suffix in ['-wal', '-journal', '-shm']) {
        final sidecar = File('$source$suffix');
        await sidecar.writeAsBytes([1, 2, 3]);
        await expectLater(
          extract(),
          throwsA(isA<LegacyTreasuryFormatException>()),
        );
        expect(await File(output).exists(), isFalse);
        expect(await File(source).readAsBytes(), before);
        await sidecar.delete();
      }
    },
  );
}
