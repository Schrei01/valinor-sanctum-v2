import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/core/infrastructure/storage_paths.dart';
import 'package:valinor_sanctum_2/features/inventory/data/json_reference_inventory_store.dart';
import 'package:valinor_sanctum_2/features/inventory/data/sqlite_inventory_opening_store.dart';
import 'package:valinor_sanctum_2/features/inventory/domain/inventory_opening.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';

/// Writes only a specifically selected independent profile. Selecting that
/// profile for the app is a separate step after reconciliation by the caller.
Future<void> main(List<String> arguments) async {
  AppDatabase? app;
  try {
    final values = <String, String>{};
    final flags = <String>{};
    const valueOptions = {
      '--reference',
      '--profile',
      '--business-name',
      '--money-scale',
      '--command-id',
      '--snapshot-sha256',
      '--occurred-at',
    };
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      if (argument == '--apply' || argument == '--zero-costs-confirmed') {
        if (!flags.add(argument)) {
          throw FormatException('Opción repetida: $argument');
        }
      } else if (valueOptions.contains(argument)) {
        if (values.containsKey(argument) ||
            index + 1 >= arguments.length ||
            arguments[index + 1].startsWith('--')) {
          throw FormatException('Falta el valor de $argument o está repetido.');
        }
        values[argument] = arguments[++index];
      } else {
        throw FormatException('Opción desconocida: $argument');
      }
    }
    if (values.length != valueOptions.length || !flags.contains('--apply')) {
      throw const FormatException(
        'Uso: --reference RUTA --profile PERFIL --business-name NOMBRE '
        '--money-scale ESCALA --command-id ID --snapshot-sha256 HEX '
        '--occurred-at FECHA_UTC [--zero-costs-confirmed] --apply. '
        'Sin --apply no se escribe ningún perfil.',
      );
    }
    if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(values['--snapshot-sha256']!)) {
      throw const FormatException(
        'La huella del snapshot debe ser SHA-256 hexadecimal.',
      );
    }
    final occurred = DateTime.tryParse(values['--occurred-at']!);
    final scale = int.tryParse(values['--money-scale']!);
    if (occurred == null ||
        !occurred.isUtc ||
        scale == null ||
        scale < 0 ||
        scale > 6) {
      throw const FormatException('Fecha UTC o escala monetaria no válida.');
    }
    final referencePath = p.normalize(values['--reference']!);
    if (!p.isAbsolute(referencePath)) {
      throw const FormatException('La ruta del snapshot debe ser absoluta.');
    }
    final reference = await JsonReferenceInventoryStore(
      referencePath,
    ).loadVerified(values['--snapshot-sha256']!);
    if (reference == null) {
      throw const FormatException('No existe el snapshot indicado.');
    }
    final profile = BusinessProfile(
      profileId: values['--profile']!,
      businessName: values['--business-name']!,
      currencyCode: 'COP',
      moneyScale: scale,
      timezone: 'America/Bogota',
      createdAtUtc: occurred,
    );
    final config = AppConfig.fromDefines(
      environment: 'development',
      dataRoot: p.join(AppConfig.repositoryRootPath, 'data', 'development'),
      profileId: profile.profileId,
    );
    final paths = await StoragePaths.resolve(config);
    app = await AppDatabase.open(path: paths.databasePath);
    final result = await SqliteInventoryOpeningStore(app).open(
      InventoryOpeningCommand(
        commandId: values['--command-id']!,
        reference: reference,
        snapshotSha256: values['--snapshot-sha256']!,
        occurredAtUtc: occurred,
        zeroCostsConfirmed: flags.contains('--zero-costs-confirmed'),
      ),
      initialProfile: profile,
    );
    stdout.writeln(
      jsonEncode({
        'profile': profile.profileId,
        'databasePath': paths.databasePath,
        'documentId': result.documentId,
        'commandId': result.commandId,
        'productCount': result.productCount,
        'totalUnits': result.totalUnits,
        'totalCostMinor': result.totalCostMinor,
        'moneyScale': scale,
        'activeProfileChanged': false,
      }),
    );
  } catch (failure) {
    stderr.writeln('No se aplicó la apertura solicitada: $failure');
    exitCode = 1;
  } finally {
    await app?.close();
  }
}
