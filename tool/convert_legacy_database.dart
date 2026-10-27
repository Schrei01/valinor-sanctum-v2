import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/features/legacy_conversion/data/sqlite_legacy_conversion.dart';

Future<void> main(List<String> args) async {
  try {
    final values = <String, String>{};
    var apply = false;
    for (var i = 0; i < args.length; i++) {
      if (args[i] == '--apply' && !apply) {
        apply = true;
        continue;
      }
      if (!['--source', '--base', '--output'].contains(args[i]) ||
          values.containsKey(args[i]) ||
          i + 1 >= args.length) {
        throw const FormatException(
          'Uso: --source COPIA --base BASE_PROPIA --output ARCHIVO_NUEVO --apply',
        );
      }
      final key = args[i];
      values[key] = args[++i];
    }
    if (!apply || values.length != 3) {
      throw const FormatException(
        'Se requieren origen, base propia, salida nueva y --apply.',
      );
    }
    final base = p.normalize(values['--base']!),
        output = p.normalize(values['--output']!);
    final root = p.normalize(AppConfig.repositoryRootPath);
    if (!p.isAbsolute(output) ||
        !p.isWithin(root, output) ||
        !p.isWithin(root, base) ||
        await FileSystemEntity.type(output, followLinks: false) !=
            FileSystemEntityType.notFound) {
      throw const FormatException(
        'Base/salida fuera del proyecto o salida existente.',
      );
    }
    await verifyLegacyFilePath(base);
    final parent = Directory(p.dirname(output));
    if (!await parent.exists() ||
        !p.equals(
          p.normalize(await parent.resolveSymbolicLinks()),
          p.normalize(parent.path),
        )) {
      throw const FormatException(
        'La carpeta de salida debe existir y ser canónica.',
      );
    }
    sqfliteFfiInit();
    final original = await databaseFactoryFfi.openDatabase(
      base,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    try {
      // The main DB is opened SQLITE_OPEN_READONLY. VACUUM INTO writes only
      // the new destination and includes committed WAL pages consistently.
      await original.execute('VACUUM main INTO ?', [output]);
    } finally {
      await original.close();
    }
    final candidate = await AppDatabase.open(path: output);
    try {
      final result = await importLegacyHistory(
        target: candidate,
        sourcePath: values['--source']!,
      );
      final health = await candidate.readHealth();
      if (health['integrityOk'] != true ||
          health['foreignKeyViolations'] != 0) {
        throw const FormatException('Falló la validación del candidato.');
      }
      stdout.writeln(
        jsonEncode({
          'output': output,
          ...result.toJson(),
          'schema': health['schemaVersion'],
          'sourceUnmodified': true,
        }),
      );
    } finally {
      await candidate.close();
    }
  } catch (e) {
    stderr.writeln('No se activó ninguna base: $e');
    exitCode = 1;
  }
}
