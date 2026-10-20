import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/reference_inventory.dart';

/// Extracts only products from an explicitly supplied backup. The caller must
/// verify the supplied source SHA-256 before and after this read-only extraction.
Future<void> main(List<String> arguments) async {
  try {
    final options = <String, String>{};
    var replace = false;
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      if (argument == '--replace') {
        if (replace) throw const FormatException('--replace está repetido.');
        replace = true;
      } else if (const [
        '--source',
        '--output',
        '--source-sha256',
      ].contains(argument)) {
        if (options.containsKey(argument) ||
            index + 1 >= arguments.length ||
            arguments[index + 1].startsWith('--')) {
          throw FormatException('Falta el valor de $argument o está repetido.');
        }
        options[argument] = arguments[++index];
      } else {
        throw FormatException('Opción desconocida: $argument');
      }
    }
    if (options.length != 3) {
      throw const FormatException(
        'Uso: --source RUTA --output RUTA --source-sha256 HEX [--replace]',
      );
    }
    final reference = await exportReferenceInventory(
      sourcePath: options['--source']!,
      outputPath: options['--output']!,
      sourceSha256: options['--source-sha256']!,
      replace: replace,
    );
    stdout.writeln(
      jsonEncode({
        'output': p.normalize(options['--output']!),
        'products': reference.products.length,
        'totalUnits': reference.totalUnits,
        'sourceReadOnly': true,
      }),
    );
  } catch (failure) {
    stderr.writeln('No se extrajo el inventario: $failure');
    exitCode = 1;
  }
}

Future<ReferenceInventory> exportReferenceInventory({
  required String sourcePath,
  required String outputPath,
  required String sourceSha256,
  bool replace = false,
  DateTime? capturedAtUtc,
}) async {
  if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sourceSha256)) {
    throw const ReferenceInventoryFormatException(
      'La huella de la fuente debe ser un SHA-256 hexadecimal de 64 caracteres.',
    );
  }
  final source = p.normalize(sourcePath);
  final destination = p.normalize(outputPath);
  if (!p.isAbsolute(source) || !p.isAbsolute(destination)) {
    throw ArgumentError('Las rutas de fuente y salida deben ser absolutas.');
  }
  await _verifyRegularPath(source);
  if (await FileSystemEntity.type(source, followLinks: false) !=
      FileSystemEntityType.file) {
    throw ArgumentError('La fuente debe ser un archivo de base de datos.');
  }
  await _verifyOutput(destination, replace: replace);
  if (p.equals(source, destination)) {
    throw ArgumentError('La salida no puede reemplazar la fuente.');
  }

  sqfliteFfiInit();
  final database = await databaseFactoryFfi.openDatabase(
    source,
    options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
  );
  late final ReferenceInventory reference;
  try {
    await database.execute('PRAGMA query_only=ON');
    final columns = {
      for (final row in await database.rawQuery('PRAGMA table_info(products)'))
        (row['name'] as String).toLowerCase(),
    };
    const requiredColumns = {
      'id',
      'name',
      'quantity',
      'price',
      'purchaseprice',
    };
    if (!columns.containsAll(requiredColumns)) {
      throw const ReferenceInventoryFormatException(
        'La tabla products no contiene las columnas de inventario requeridas.',
      );
    }
    // Every SQL identifier below is fixed here, never taken from source values.
    final lot = columns.contains('lote') ? 'lote' : "'' AS lote";
    final category = columns.contains('categoria')
        ? 'categoria AS category_text'
        : "'' AS category_text";
    final supplier = columns.contains('proveedor')
        ? 'proveedor AS supplier_text'
        : "'' AS supplier_text";
    final rows = await database.rawQuery('''
      SELECT id, name, quantity, CAST(price AS TEXT) AS price_text,
             CAST(purchasePrice AS TEXT) AS purchase_price_text,
             $lot, $category, $supplier
      FROM products
      ORDER BY id
    ''');
    reference = ReferenceInventory(
      sourceName: p.basename(source),
      sourceSha256: sourceSha256.toLowerCase(),
      capturedAtUtc: capturedAtUtc ?? DateTime.now().toUtc(),
      products: [
        for (final row in rows)
          ReferenceInventoryProduct(
            id: _sourceInteger(row['id'], 'id').toString(),
            name: _sourceString(row['name'], 'name'),
            quantity: _sourceInteger(row['quantity'], 'quantity'),
            priceMinor: referencePriceToMinor(row['price_text']),
            purchasePriceMinor: referencePriceToMinor(
              row['purchase_price_text'],
            ),
            lot: row['lote'] == null ? '' : _sourceString(row['lote'], 'lote'),
            category: row['category_text'] == null
                ? ''
                : _sourceString(row['category_text'], 'categoria'),
            supplier: row['supplier_text'] == null
                ? ''
                : _sourceString(row['supplier_text'], 'proveedor'),
          ),
      ],
    );
  } finally {
    await database.close();
  }

  // No output is created until all source rows have passed exact validation.
  await _verifyOutput(destination, replace: replace);
  await Directory(p.dirname(destination)).create(recursive: true);
  await _verifyOutput(destination, replace: replace);
  final staging = await Directory(
    p.dirname(destination),
  ).createTemp('.reference-inventory-');
  try {
    final temporary = File(p.join(staging.path, 'inventory.json'));
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'formatVersion': 2,
        'sourceName': reference.sourceName,
        'sourceSha256': reference.sourceSha256,
        'capturedAtUtc': reference.capturedAtUtc.toIso8601String(),
        'currencyCode': reference.currencyCode,
        'moneyScale': reference.moneyScale,
        'products': [
          for (final product in reference.products)
            {
              'id': product.id,
              'name': product.name,
              'quantity': product.quantity,
              'priceMinor': product.priceMinor,
              'purchasePriceMinor': product.purchasePriceMinor,
              'lot': product.lot,
              'category': product.category,
              'supplier': product.supplier,
            },
        ],
      }),
      flush: true,
    );
    await _verifyOutput(destination, replace: replace);
    await temporary.rename(destination);
  } finally {
    // The staging directory was created beneath a freshly verified data path.
    await _verifyRegularPath(staging.path);
    if (!p.isWithin(_dataBoundary, p.normalize(staging.path))) {
      throw StateError('El temporal salió del directorio de datos autorizado.');
    }
    await staging.delete(recursive: true);
  }
  return reference;
}

/// Parses SQLite's textual decimal representation without floating point or
/// rounding. Trailing zeroes are exact; any fractional cent is rejected.
int referencePriceToMinor(Object? input) {
  if (input is! String || input.length > 128) {
    throw const ReferenceInventoryFormatException(
      'Un precio de la copia no es un decimal válido.',
    );
  }
  final match = RegExp(
    r'^([+-]?)([0-9]+)(?:\.([0-9]+))?(?:[eE]([+-]?[0-9]+))?$',
  ).firstMatch(input);
  if (match == null) {
    throw const ReferenceInventoryFormatException(
      'Un precio de la copia no es un decimal válido.',
    );
  }
  final exponent = int.tryParse(match.group(4) ?? '0');
  if (exponent == null || exponent < -1000 || exponent > 1000) {
    throw const ReferenceInventoryFormatException(
      'Un precio de la copia está fuera del rango permitido.',
    );
  }
  final fraction = match.group(3) ?? '';
  var minor = BigInt.parse('${match.group(2)}$fraction');
  final shift = 2 + exponent - fraction.length;
  if (shift >= 0) {
    minor *= BigInt.from(10).pow(shift);
  } else {
    final divisor = BigInt.from(10).pow(-shift);
    if (minor % divisor != BigInt.zero) {
      throw const ReferenceInventoryFormatException(
        'Un precio de la copia tiene fracciones de centavo; no se redondeó.',
      );
    }
    minor ~/= divisor;
  }
  if (match.group(1) == '-') minor = -minor;
  if (minor < BigInt.zero || minor > ReferenceInventory.maxInteger) {
    throw const ReferenceInventoryFormatException(
      'Un precio de la copia está fuera del rango permitido.',
    );
  }
  return minor.toInt();
}

String get _dataBoundary =>
    p.normalize(p.join(AppConfig.repositoryRootPath, 'data'));

Future<void> _verifyOutput(String destination, {required bool replace}) async {
  if (!p.isAbsolute(_dataBoundary) ||
      !p.isWithin(_dataBoundary, destination) ||
      p.extension(destination).toLowerCase() != '.json') {
    throw ArgumentError(
      'La salida JSON debe permanecer en data del proyecto nuevo.',
    );
  }
  await _verifyRegularPath(destination);
  final type = await FileSystemEntity.type(destination, followLinks: false);
  if (type != FileSystemEntityType.notFound &&
      type != FileSystemEntityType.file) {
    throw ArgumentError('La salida debe ser un archivo JSON regular.');
  }
  if (!replace && type != FileSystemEntityType.notFound) {
    throw StateError('La salida ya existe. Usa --replace para reemplazarla.');
  }
}

Future<void> _verifyRegularPath(String path) async {
  final components = p.split(path);
  var current = components.first;
  for (var index = 0; index < components.length; index++) {
    if (index > 0) current = p.join(current, components[index]);
    final type = await FileSystemEntity.type(current, followLinks: false);
    if (type == FileSystemEntityType.notFound) continue;
    if (type == FileSystemEntityType.link) {
      throw FileSystemException('No se admiten enlaces o junctions.', current);
    }
    if (index < components.length - 1 &&
        type != FileSystemEntityType.directory) {
      throw FileSystemException('Un componente no es un directorio.', current);
    }
    final resolved = type == FileSystemEntityType.directory
        ? await Directory(current).resolveSymbolicLinks()
        : await File(current).resolveSymbolicLinks();
    if (!p.equals(p.normalize(resolved), p.normalize(current))) {
      throw FileSystemException('No se admiten rutas con alias.', current);
    }
  }
}

int _sourceInteger(Object? value, String field) {
  if (value is! int) {
    throw ReferenceInventoryFormatException(
      'El campo $field de la fuente debe ser un entero exacto.',
    );
  }
  return value;
}

String _sourceString(Object? value, String field) {
  if (value is! String) {
    throw ReferenceInventoryFormatException(
      'El campo $field de la fuente debe ser texto.',
    );
  }
  return value;
}
