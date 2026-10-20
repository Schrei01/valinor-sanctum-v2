import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:valinor_sanctum_2/core/infrastructure/app_config.dart';
import 'package:valinor_sanctum_2/core/infrastructure/database/app_database.dart';
import 'package:valinor_sanctum_2/core/infrastructure/storage_paths.dart';
import 'package:valinor_sanctum_2/features/treasury/data/json_legacy_treasury_store.dart';
import 'package:valinor_sanctum_2/features/treasury/data/sqlite_treasury_opening_store.dart';
import 'package:valinor_sanctum_2/features/treasury/domain/treasury_opening.dart';
import 'package:valinor_sanctum_2/features/workspace/domain/business_profile.dart';

/// Applies only verified opening balances to an explicitly named existing
/// development profile. Historical movements remain a separate local JSON.
Future<void> main(List<String> arguments) async {
  AppDatabase? app;
  try {
    const requiredOptions = {
      '--snapshot',
      '--snapshot-sha256',
      '--profile',
      '--command-id',
      '--occurred-at',
    };
    final values = <String, String>{};
    final flags = <String>{};
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      if (const {
        '--apply',
        '--negative-reserve-confirmed',
      }.contains(argument)) {
        if (!flags.add(argument)) {
          throw FormatException('Opción repetida: $argument');
        }
      } else if (requiredOptions.contains(argument)) {
        if (values.containsKey(argument) ||
            index + 1 >= arguments.length ||
            arguments[index + 1].startsWith('--')) {
          throw FormatException(
            'Falta un valor o la opción está repetida: $argument',
          );
        }
        values[argument] = arguments[++index];
      } else {
        throw FormatException('Opción desconocida: $argument');
      }
    }
    if (values.length != requiredOptions.length || !flags.contains('--apply')) {
      throw const FormatException(
        'Uso: --snapshot RUTA --snapshot-sha256 HEX --profile PERFIL '
        '--command-id ID --occurred-at FECHA_UTC '
        '[--negative-reserve-confirmed] --apply. Sin --apply no se abre ninguna base.',
      );
    }
    final occurred = DateTime.tryParse(values['--occurred-at']!);
    if (occurred == null || !occurred.isUtc) {
      throw const FormatException(
        'La fecha de apertura debe incluir zona UTC.',
      );
    }
    final snapshotPath = p.normalize(values['--snapshot']!);
    final dataRoot = p.join(AppConfig.repositoryRootPath, 'data');
    if (!p.isAbsolute(snapshotPath) ||
        !p.isWithin(dataRoot, snapshotPath) ||
        p.extension(snapshotPath).toLowerCase() != '.json') {
      throw const FormatException(
        'El snapshot debe ser JSON privado dentro de data del proyecto nuevo.',
      );
    }
    final snapshotFile = File(snapshotPath);
    if (!await snapshotFile.exists() ||
        !p.equals(await snapshotFile.resolveSymbolicLinks(), snapshotPath)) {
      throw const FormatException(
        'El snapshot no existe o su ruta contiene un enlace.',
      );
    }
    final snapshot = await JsonLegacyTreasuryStore(
      snapshotPath,
    ).loadVerified(values['--snapshot-sha256']!);
    if (snapshot == null) throw const FormatException('No existe el snapshot.');
    if (snapshot.balanceByRole('reserve').amountMinor < 0 &&
        !flags.contains('--negative-reserve-confirmed')) {
      throw const FormatException(
        'Un saldo negativo de Caja mayor requiere confirmación expresa de su valor.',
      );
    }
    final config = AppConfig.fromDefines(
      environment: 'development',
      dataRoot: p.join(dataRoot, 'development'),
      profileId: values['--profile']!,
    );
    final paths = await StoragePaths.resolve(config);
    if (!await File(paths.databasePath).exists()) {
      throw const FormatException(
        'El perfil debe existir; esta herramienta no crea ni cambia perfiles.',
      );
    }
    app = await AppDatabase.open(path: paths.databasePath);
    final profiles = await app.database.query('app_profile', where: 'id=1');
    if (profiles.length != 1) {
      throw const FormatException('El perfil no está configurado.');
    }
    final profile = BusinessProfile.fromRow(profiles.single);
    if (profile.profileId != config.profileId ||
        profile.currencyCode != snapshot.currencyCode ||
        profile.moneyScale != snapshot.moneyScale) {
      throw const FormatException(
        'El perfil, divisa o escala no coinciden con el snapshot.',
      );
    }
    final inventoryOrigins = await app.database.query(
      'inventory_openings',
      columns: ['source_sha256'],
    );
    if (inventoryOrigins.any(
      (row) =>
          (row['source_sha256'] as String).toLowerCase() !=
          snapshot.sourceSha256.toLowerCase(),
    )) {
      throw const FormatException(
        'La copia no coincide con la usada para el inventario inicial; concilia el corte antes de cargar saldos.',
      );
    }
    final result = await SqliteTreasuryOpeningStore(app).importOpening(
      TreasuryOpeningCommand(
        commandId: values['--command-id']!,
        sourceSha256: snapshot.sourceSha256,
        snapshotSha256: values['--snapshot-sha256']!,
        occurredAtUtc: occurred,
        cashMinor: snapshot.balanceByRole('cash').amountMinor,
        nequiMinor: snapshot.balanceByRole('nequi').amountMinor,
        reserveMinor: snapshot.balanceByRole('reserve').amountMinor,
        receivablesMinor: snapshot.balanceByRole('receivables').amountMinor,
        sourceMetadata: {
          'sourceName': snapshot.sourceName,
          'extractedAtUtc': snapshot.extractedAtUtc.toIso8601String(),
          'balances': [
            for (final balance in snapshot.balances)
              {
                'role': balance.role,
                'sourceTable': balance.sourceTable,
                'sourceRowId': balance.sourceRowId,
                'sourceDateRaw': balance.sourceDateRaw,
              },
          ],
          'historyReposted': false,
          'negativeReserveConfirmed': flags.contains(
            '--negative-reserve-confirmed',
          ),
        },
      ),
    );
    stdout.writeln(
      jsonEncode({
        'profile': config.profileId,
        'documentId': result.documentId,
        'replayed': result.replayed,
        'activeProfileChanged': false,
        'historyReposted': false,
      }),
    );
  } catch (failure) {
    stderr.writeln('No se aplicó la apertura solicitada: $failure');
    exitCode = 1;
  } finally {
    await app?.close();
  }
}
