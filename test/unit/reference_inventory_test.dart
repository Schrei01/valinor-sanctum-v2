import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/features/inventory/data/json_reference_inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/reference_inventory.dart';

void main() {
  late Directory sandbox;
  late File file;

  setUp(() async {
    final temporaryRoot = Directory(
      p.join(AppConfig.repositoryRootPath, 'tmp'),
    );
    await temporaryRoot.create(recursive: true);
    sandbox = await temporaryRoot.createTemp('reference_inventory_test_');
    file = File(p.join(sandbox.path, 'reference.json'));
  });

  tearDown(() async {
    final canonical = p.normalize(await sandbox.resolveSymbolicLinks());
    if (!p.isWithin(p.join(AppConfig.repositoryRootPath, 'tmp'), canonical)) {
      throw StateError('Refusing cleanup outside the test sandbox.');
    }
    await sandbox.delete(recursive: true);
  });

  ReferenceInventory snapshot(List<ReferenceInventoryProduct> products) =>
      ReferenceInventory(
        sourceName: 'synthetic.db',
        sourceSha256: List.filled(64, 'a').join(),
        capturedAtUtc: DateTime.utc(2026, 10, 20),
        products: products,
      );

  Map<String, Object?> product({String id = '1', int quantity = 4}) => {
    'id': id,
    'name': 'Producto sintético',
    'quantity': quantity,
    'priceMinor': 125001,
    'purchasePriceMinor': 75025,
    'lot': 'Lote sintético',
  };

  Map<String, Object?> document() => {
    'formatVersion': 1,
    'sourceName': 'synthetic.db',
    'sourceSha256': List.filled(64, 'a').join(),
    'capturedAtUtc': '2026-10-20T12:00:00.000Z',
    'currencyCode': 'COP',
    'moneyScale': 2,
    'products': [product()],
  };

  Future<ReferenceInventory?> load(Map<String, Object?> data) async {
    await file.writeAsString(jsonEncode(data));
    return JsonReferenceInventoryStore(file.path).load();
  }

  test(
    'reference is immutable and preserves zero stock and repeated names',
    () {
      final products = [
        const ReferenceInventoryProduct(
          id: '1',
          name: 'Nombre repetido',
          quantity: 0,
          priceMinor: 10001,
          purchasePriceMinor: 8001,
        ),
        const ReferenceInventoryProduct(
          id: '2',
          name: 'Nombre repetido',
          quantity: 7,
          priceMinor: 10001,
          purchasePriceMinor: 8001,
          lot: 'Lote B',
        ),
      ];
      final reference = snapshot(products);
      products.clear();
      expect(reference.products, hasLength(2));
      expect(reference.products.first.quantity, 0);
      expect(reference.products.first.lot, '');
      expect(reference.products.last.lot, 'Lote B');
      expect(reference.totalUnits, 7);
      expect(reference.currencyCode, 'COP');
      expect(reference.moneyScale, 2);
      expect(() => reference.products.clear(), throwsUnsupportedError);
    },
  );

  test('duplicate identifiers and overflowing total units are rejected', () {
    const row = ReferenceInventoryProduct(
      id: 'same',
      name: 'Producto',
      quantity: 1,
      priceMinor: 100,
      purchasePriceMinor: 50,
    );
    expect(
      () => snapshot([row, row]),
      throwsA(isA<ReferenceInventoryFormatException>()),
    );
    expect(
      () => snapshot([
        ReferenceInventoryProduct(
          id: 'max',
          name: 'Muchos',
          quantity: ReferenceInventory.maxInteger.toInt(),
          priceMinor: 100,
          purchasePriceMinor: 50,
        ),
        row,
      ]),
      throwsA(isA<ReferenceInventoryFormatException>()),
    );
  });

  test('missing local file is the only absent snapshot', () async {
    expect(await JsonReferenceInventoryStore(file.path).load(), isNull);
    await file.writeAsString('{"products":');
    await expectLater(
      JsonReferenceInventoryStore(file.path).load(),
      throwsA(
        isA<ReferenceInventoryFormatException>().having(
          (failure) => failure.message,
          'clear corruption message',
          contains('dañada'),
        ),
      ),
    );
    final empty = document()..['products'] = <Object?>[];
    expect((await load(empty))!.products, isEmpty);
  });

  test('reader preserves exact cents, provenance, rows and lot', () async {
    final data = document()
      ..['products'] = [product(quantity: 0), product(id: '2', quantity: 7)];
    final reference = (await load(data))!;
    expect(reference.sourceName, 'synthetic.db');
    expect(reference.sourceSha256, List.filled(64, 'a').join());
    expect(reference.capturedAtUtc, DateTime.utc(2026, 10, 20, 12));
    expect(reference.products.map((row) => row.id), ['1', '2']);
    expect(reference.products.first.quantity, 0);
    expect(reference.products.first.priceMinor, 125001);
    expect(reference.products.first.purchasePriceMinor, 75025);
    expect(reference.products.first.lot, 'Lote sintético');
    expect(reference.totalUnits, 7);
  });

  test('reader rejects incompatible or incomplete metadata', () async {
    for (final entry in <String, Object?>{
      'formatVersion': 2,
      'currencyCode': 'USD',
      'moneyScale': 0,
      'sourceName': '',
      'sourceSha256': 'not-a-hash',
      'capturedAtUtc': '2026-10-20T12:00:00',
      'products': null,
    }.entries) {
      await expectLater(
        load(document()..[entry.key] = entry.value),
        throwsA(isA<ReferenceInventoryFormatException>()),
        reason: entry.key,
      );
    }
  });

  test(
    'reader rejects duplicate IDs and invalid numeric types or signs',
    () async {
      await expectLater(
        load(document()..['products'] = [product(), product()]),
        throwsA(isA<ReferenceInventoryFormatException>()),
      );
      for (final entry in <String, Object?>{
        'quantity': 1.5,
        'priceMinor': 125001.0,
        'purchasePriceMinor': -1,
        'id': 1,
        'name': '',
        'lot': null,
      }.entries) {
        final row = product()..[entry.key] = entry.value;
        await expectLater(
          load(document()..['products'] = [row]),
          throwsA(isA<ReferenceInventoryFormatException>()),
          reason: entry.key,
        );
      }
      final data = jsonEncode(
        document(),
      ).replaceFirst('125001', '9223372036854775808');
      await file.writeAsString(data);
      await expectLater(
        JsonReferenceInventoryStore(file.path).load(),
        throwsA(isA<ReferenceInventoryFormatException>()),
      );
    },
  );
}
