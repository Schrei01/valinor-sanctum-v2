import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/features/inventory/data/json_reference_inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/reference_inventory.dart';

import '../../tool/export_reference_inventory.dart' as exporter;

void main() {
  late Directory sandbox;
  late Directory outputDirectory;
  late String source;
  late String output;
  final sha256 = List.filled(64, 'b').join();

  setUp(() async {
    sqfliteFfiInit();
    final temporaryRoot = Directory(
      p.join(AppConfig.repositoryRootPath, 'tmp'),
    );
    final testDataRoot = Directory(
      p.join(AppConfig.repositoryRootPath, 'data', 'test'),
    );
    await temporaryRoot.create(recursive: true);
    await testDataRoot.create(recursive: true);
    sandbox = await temporaryRoot.createTemp('reference_export_test_');
    outputDirectory = await testDataRoot.createTemp('reference_export_test_');
    source = p.join(sandbox.path, 'synthetic.db');
    output = p.join(outputDirectory.path, 'reference-inventory.json');
    final database = await databaseFactoryFfi.openDatabase(
      source,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      await database.execute('''
        CREATE TABLE products (
          id INTEGER PRIMARY KEY, name TEXT, quantity INTEGER,
          price REAL, purchasePrice REAL, lote TEXT
        )
      ''');
      await database.execute('''
        INSERT INTO products VALUES
          (1, 'Nombre repetido', 0, 1250.01, 750.25, 'Lote A'),
          (2, 'Nombre repetido', 5, 1000.0, 600.0, NULL),
          (3, 'Otro producto', 7, 0.0, 0.0, '')
      ''');
      await database.execute('CREATE TABLE private_data (secret TEXT)');
      await database.execute(
        "INSERT INTO private_data VALUES ('must-not-be-exported')",
      );
    } finally {
      await database.close();
    }
  });

  tearDown(() async {
    for (final directory in [sandbox, outputDirectory]) {
      final canonical = p.normalize(await directory.resolveSymbolicLinks());
      if (!p.isWithin(AppConfig.repositoryRootPath, canonical) ||
          !(p.isWithin(
                p.join(AppConfig.repositoryRootPath, 'tmp'),
                canonical,
              ) ||
              p.isWithin(
                p.join(AppConfig.repositoryRootPath, 'data', 'test'),
                canonical,
              ))) {
        throw StateError('Refusing cleanup outside the test sandbox.');
      }
      await directory.delete(recursive: true);
    }
  });

  Future<ReferenceInventory> extract({bool replace = false}) =>
      exporter.exportReferenceInventory(
        sourcePath: source,
        outputPath: output,
        sourceSha256: sha256,
        capturedAtUtc: DateTime.utc(2026, 10, 20, 14),
        replace: replace,
      );

  test(
    'exports only products without changing source bytes or adding sidecars',
    () async {
      final before = await File(source).readAsBytes();
      final reference = await extract();
      expect(await File(source).readAsBytes(), before);
      for (final suffix in ['-journal', '-wal', '-shm']) {
        expect(await File('$source$suffix').exists(), isFalse);
      }
      expect(reference.products, hasLength(3));
      expect(reference.products.map((row) => row.id), ['1', '2', '3']);
      expect(reference.products.map((row) => row.quantity), [0, 5, 7]);
      expect(reference.products.first.name, reference.products[1].name);
      expect(reference.products.first.priceMinor, 125001);
      expect(reference.products.first.purchasePriceMinor, 75025);
      expect(reference.products.first.lot, 'Lote A');
      expect(reference.products[1].lot, '');
      expect(reference.products.last.priceMinor, 0);
      expect(reference.totalUnits, 12);
      final text = await File(output).readAsString();
      expect(text, isNot(contains('private_data')));
      expect(text, isNot(contains('must-not-be-exported')));
      expect(text, isNot(contains(source)));
      final loaded = (await JsonReferenceInventoryStore(output).load())!;
      expect(loaded.sourceName, 'synthetic.db');
      expect(loaded.sourceSha256, sha256);
      expect(loaded.capturedAtUtc, DateTime.utc(2026, 10, 20, 14));
      expect(loaded.totalUnits, 12);
      expect(loaded.products.map((row) => row.id), ['1', '2', '3']);
    },
  );

  test(
    'requires explicit replacement and preserves output on rejected extraction',
    () async {
      await extract();
      final first = await File(output).readAsString();
      await expectLater(extract(), throwsStateError);
      expect(await File(output).readAsString(), first);
      final database = await databaseFactoryFfi.openDatabase(
        source,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      try {
        await database.execute(
          "UPDATE products SET name = 'Nuevo' WHERE id = 1",
        );
      } finally {
        await database.close();
      }
      await extract(replace: true);
      expect(
        (await JsonReferenceInventoryStore(output).load())!.products.first.name,
        'Nuevo',
      );
      final replacement = await File(output).readAsString();
      final invalid = await databaseFactoryFfi.openDatabase(
        source,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      try {
        await invalid.execute('UPDATE products SET price = 0.001 WHERE id = 1');
      } finally {
        await invalid.close();
      }
      await expectLater(
        extract(replace: true),
        throwsA(isA<ReferenceInventoryFormatException>()),
      );
      expect(await File(output).readAsString(), replacement);
    },
  );

  test('rejects missing source and output outside the data boundary', () async {
    final missing = p.join(sandbox.path, 'missing.db');
    await expectLater(
      exporter.exportReferenceInventory(
        sourcePath: missing,
        outputPath: output,
        sourceSha256: sha256,
      ),
      throwsArgumentError,
    );
    expect(await File(missing).exists(), isFalse);
    final outside = p.join(sandbox.path, 'not-under-data.json');
    await expectLater(
      exporter.exportReferenceInventory(
        sourcePath: source,
        outputPath: outside,
        sourceSha256: sha256,
      ),
      throwsArgumentError,
    );
    expect(await File(outside).exists(), isFalse);
    expect(await File(output).exists(), isFalse);
  });

  test('rejects fractional stock before writing any output', () async {
    final database = await databaseFactoryFfi.openDatabase(
      source,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      await database.execute('UPDATE products SET quantity = 1.5 WHERE id = 1');
    } finally {
      await database.close();
    }
    final before = await File(source).readAsBytes();
    await expectLater(
      extract(),
      throwsA(isA<ReferenceInventoryFormatException>()),
    );
    expect(await File(output).exists(), isFalse);
    expect(await File(source).readAsBytes(), before);
  });

  test(
    'decimal conversion is exact and rejects fractions of cents and ranges',
    () {
      for (final entry in <String, int>{
        '0.0': 0,
        '1': 100,
        '1250.01': 125001,
        '750.2500': 75025,
        '1.2e3': 120000,
        '1e-2': 1,
        '92233720368547758.07': 9223372036854775807,
      }.entries) {
        expect(exporter.referencePriceToMinor(entry.key), entry.value);
      }
      for (final invalid in <Object?>[
        '0.001',
        '1e-3',
        '-0.01',
        '92233720368547758.08',
        '1e9999',
        'NaN',
        'Infinity',
        null,
        1.25,
      ]) {
        expect(
          () => exporter.referencePriceToMinor(invalid),
          throwsA(isA<ReferenceInventoryFormatException>()),
          reason: '$invalid',
        );
      }
    },
  );

  test(
    'export JSON has only the agreed fields and integer minor units',
    () async {
      await extract();
      final data = jsonDecode(await File(output).readAsString()) as Map;
      expect(data.keys.toSet(), {
        'formatVersion',
        'sourceName',
        'sourceSha256',
        'capturedAtUtc',
        'currencyCode',
        'moneyScale',
        'products',
      });
      final row = (data['products'] as List).first as Map;
      expect(row.keys.toSet(), {
        'id',
        'name',
        'quantity',
        'priceMinor',
        'purchasePriceMinor',
        'lot',
      });
      expect(row['priceMinor'], isA<int>());
      expect(row['purchasePriceMinor'], isA<int>());
      expect(row['quantity'], isA<int>());
    },
  );
}
