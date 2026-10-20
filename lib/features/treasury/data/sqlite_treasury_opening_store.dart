import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/domain/money.dart';
import '../../../core/infrastructure/database/app_database.dart';
import '../../../core/infrastructure/database/schema.dart';
import '../../workspace/domain/business_profile.dart';
import '../domain/treasury_opening.dart';

/// Establishes one verified financial opening before any monetary operations.
/// Money and aggregate legacy receivables are equity, never sales or payments.
class SqliteTreasuryOpeningStore {
  SqliteTreasuryOpeningStore(this._database, {this.synthetic = false});
  final AppDatabase _database;
  final bool synthetic;
  static const _operator = 'system:local-operator';
  static const _equity = 'system:opening-equity';
  static const _receivables = 'system:legacy-customer-receivables';

  Future<TreasuryOpeningResult> importOpening(
    TreasuryOpeningCommand command,
  ) async {
    final metadata = _validate(command);
    return _database.database.transaction((txn) async {
      final profiles = await txn.query('app_profile', where: 'id=1');
      if (profiles.length != 1) {
        throw const TreasuryOpeningValidationException(
          'Configura el espacio de trabajo primero.',
        );
      }
      final profile = BusinessProfile.fromRow(profiles.single);
      if (profile.timezone != 'America/Bogota') {
        throw const TreasuryOpeningValidationException(
          'La apertura requiere la zona horaria America/Bogota.',
        );
      }
      final prior = await txn.query(
        'command_log',
        where: 'id=?',
        whereArgs: [command.commandId],
      );
      final savedOpenings = prior.isEmpty
          ? <Map<String, Object?>>[]
          : await txn.query(
              'treasury_openings',
              where: 'command_id=?',
              whereArgs: [command.commandId],
            );
      if (prior.isNotEmpty &&
          (prior.single['command_type'] != 'treasury_opening' ||
              savedOpenings.length != 1)) {
        throw const TreasuryOpeningValidationException(
          'El identificador ya corresponde a otra operación o contenido.',
        );
      }
      final accounts = savedOpenings.isEmpty
          ? await _accounts(txn)
          : [
              for (final column in [
                'cash_account_id',
                'nequi_account_id',
                'reserve_account_id',
              ])
                <String, Object?>{'id': savedOpenings.single[column]},
            ];
      final canonical = jsonEncode({
        'version': 1,
        'profileId': profile.profileId,
        'currency': profile.currencyCode,
        'scale': profile.moneyScale,
        'sourceSha256': command.sourceSha256.toLowerCase(),
        'snapshotSha256': command.snapshotSha256.toLowerCase(),
        'occurredAtUtc': command.occurredAtUtc.toIso8601String(),
        'cashAccountId': accounts[0]['id'],
        'nequiAccountId': accounts[1]['id'],
        'reserveAccountId': accounts[2]['id'],
        'cashMinor': command.cashMinor,
        'nequiMinor': command.nequiMinor,
        'reserveMinor': command.reserveMinor,
        'receivablesMinor': command.receivablesMinor,
        'sourceMetadata': metadata,
      });
      if (prior.isNotEmpty) {
        final saved = prior.single;
        if (saved['command_type'] != 'treasury_opening' ||
            saved['response_version'] != 1 ||
            saved['payload_hash'] != DatabaseSchema.checksum(canonical)) {
          throw const TreasuryOpeningValidationException(
            'El identificador ya corresponde a otra operación o contenido.',
          );
        }
        final response = jsonDecode(saved['response_json'] as String);
        if (response is! Map ||
            response['canonicalPayload'] != canonical ||
            response['documentId'] is! String) {
          throw const TreasuryOpeningValidationException(
            'El identificador ya corresponde a otra operación o contenido.',
          );
        }
        return TreasuryOpeningResult(
          documentId: response['documentId'] as String,
          replayed: true,
        );
      }
      await _unusedCommand(txn, command.commandId);
      if ((await txn.query('treasury_openings', limit: 1)).isNotEmpty) {
        throw const TreasuryOpeningValidationException(
          'Este perfil ya tiene una apertura de Tesorería.',
        );
      }
      for (final table in ['cash_openings', 'customer_receivables']) {
        if ((await txn.query(table, limit: 1)).isNotEmpty) {
          throw const TreasuryOpeningValidationException(
            'La apertura requiere cuentas sin saldos iniciales ni deudas propias previas.',
          );
        }
      }
      if ((await txn.rawQuery('''
SELECT line.id FROM journal_lines line
JOIN journal_entries entry ON entry.id=line.entry_id AND entry.status='posted'
JOIN business_documents document ON document.id=entry.document_id AND document.status='posted'
JOIN ledger_accounts ledger ON ledger.id=line.account_id
WHERE ledger.role IN ('cash','receivable') LIMIT 1
''')).isNotEmpty) {
        throw const TreasuryOpeningValidationException(
          'La apertura debe registrarse antes de movimientos monetarios propios.',
        );
      }
      final now = DateTime.now().toUtc().toIso8601String();
      await _systemRows(txn, now);
      final documentId =
          'treasury-opening:${command.snapshotSha256.toLowerCase()}';
      final entryId = 'treasury-entry:${command.snapshotSha256.toLowerCase()}';
      await txn.insert('command_log', {
        'id': command.commandId,
        'command_type': 'treasury_opening',
        'payload_hash': DatabaseSchema.checksum(canonical),
        'actor_id': _operator,
        'response_json': jsonEncode({
          'canonicalPayload': canonical,
          'documentId': documentId,
        }),
        'response_version': 1,
        'committed_at_utc': now,
        'authorization_policy_version': 'development-single-user-v1',
      });
      final occurred = command.occurredAtUtc.toIso8601String();
      final date = command.occurredAtUtc.subtract(const Duration(hours: 5));
      await txn.insert('business_documents', {
        'id': documentId,
        'command_id': command.commandId,
        'command_sequence': 0,
        'profile_id': profile.profileId,
        'actor_id': _operator,
        'type': 'treasury_opening',
        'status': 'draft',
        'occurred_at_utc': occurred,
        'business_date':
            '${date.year.toString().padLeft(4, '0')}-'
            '${date.month.toString().padLeft(2, '0')}-'
            '${date.day.toString().padLeft(2, '0')}',
        'recorded_at_utc': now,
        'reason': 'Saldos iniciales desde copia verificada',
        'source_kind': synthetic ? 'synthetic' : 'legacy',
        'date_quality': 'reconstructed',
      });
      await txn.insert('treasury_openings', {
        'document_id': documentId,
        'command_id': command.commandId,
        'profile_id': profile.profileId,
        'cash_account_id': accounts[0]['id'],
        'nequi_account_id': accounts[1]['id'],
        'reserve_account_id': accounts[2]['id'],
        'cash_minor': command.cashMinor,
        'nequi_minor': command.nequiMinor,
        'reserve_minor': command.reserveMinor,
        'receivables_minor': command.receivablesMinor,
        'source_sha256': command.sourceSha256.toLowerCase(),
        'snapshot_sha256': command.snapshotSha256.toLowerCase(),
        'source_metadata_json': jsonEncode(metadata),
        'occurred_at_utc': occurred,
      });
      await txn.insert('journal_entries', {
        'id': entryId,
        'document_id': documentId,
        'status': 'draft',
        'cost_completeness': 'not_applicable',
      });
      final values = [
        command.cashMinor,
        command.nequiMinor,
        command.reserveMinor,
        command.receivablesMinor,
      ];
      final net = values.fold(
        BigInt.zero,
        (sum, value) => sum + BigInt.from(value),
      );
      final expected = [
        for (final pair in accounts.indexed)
          (
            pair.$2['ledger_account_id'] as String,
            BigInt.from(values[pair.$1]),
          ),
        (_receivables, BigInt.from(command.receivablesMinor)),
        (_equity, -net),
      ].where((line) => line.$2 != BigInt.zero).toList();
      for (final pair in expected.indexed) {
        final signed = pair.$2.$2;
        await txn.insert('journal_lines', {
          'id': '$entryId:${pair.$1}',
          'entry_id': entryId,
          'sequence': pair.$1,
          'account_id': pair.$2.$1,
          'debit_minor': signed.isNegative ? 0 : signed.toInt(),
          'credit_minor': signed.isNegative ? (-signed).toInt() : 0,
        });
      }
      await txn.update(
        'business_documents',
        {'status': 'posted'},
        where: 'id=?',
        whereArgs: [documentId],
      );
      await txn.update(
        'journal_entries',
        {'status': 'posted', 'posted_at_utc': now},
        where: 'id=?',
        whereArgs: [entryId],
      );
      return TreasuryOpeningResult(documentId: documentId, replayed: false);
    }, exclusive: true);
  }

  static Object? _canonicalJson(Object? value) {
    if (value == null || value is String || value is bool || value is int) {
      return value;
    }
    if (value is List) return value.map(_canonicalJson).toList(growable: false);
    if (value is Map<String, Object?>) {
      final keys = value.keys.toList()..sort();
      return {for (final key in keys) key: _canonicalJson(value[key])};
    }
    throw const TreasuryOpeningValidationException(
      'La procedencia debe contener JSON exacto, sin números decimales.',
    );
  }

  static Object? _validate(TreasuryOpeningCommand command) {
    if (!RegExp(r'^[A-Za-z0-9:_-]{1,128}$').hasMatch(command.commandId) ||
        !RegExp(r'^[A-Fa-f0-9]{64}$').hasMatch(command.sourceSha256) ||
        !RegExp(r'^[A-Fa-f0-9]{64}$').hasMatch(command.snapshotSha256)) {
      throw const TreasuryOpeningValidationException(
        'Identificador o huellas no válidos.',
      );
    }
    final time = command.occurredAtUtc;
    if (!time.isUtc ||
        time.year < 1 ||
        time.year > 9999 ||
        time.subtract(const Duration(hours: 5)).year < 1) {
      throw const TreasuryOpeningValidationException(
        'La fecha de apertura no es válida.',
      );
    }
    final values = [
      command.cashMinor,
      command.nequiMinor,
      command.reserveMinor,
      command.receivablesMinor,
    ];
    var positive = BigInt.zero;
    var negative = BigInt.zero;
    for (final value in values) {
      final exact = BigInt.from(value);
      if (exact.abs() > Money.maxMinorUnits) {
        throw const TreasuryOpeningValidationException(
          'El saldo excede el rango exacto permitido.',
        );
      }
      if (exact.isNegative) {
        negative -= exact;
      } else {
        positive += exact;
      }
    }
    if (command.receivablesMinor < 0 ||
        positive > Money.maxMinorUnits ||
        negative > Money.maxMinorUnits) {
      throw const TreasuryOpeningValidationException(
        'Deudas debe ser no negativo y los totales del asiento deben estar dentro del rango permitido.',
      );
    }
    return _canonicalJson(command.sourceMetadata);
  }

  static Future<List<Map<String, Object?>>> _accounts(
    DatabaseExecutor txn,
  ) async {
    final rows = <Map<String, Object?>>[];
    for (final spec in [
      ('quick-default:EFECTIVO', false),
      ('quick-default:NEQUI', false),
      ('treasury:main-cash', true),
    ]) {
      final found = await txn.rawQuery(
        '''
SELECT cash.*, ledger.class,ledger.role,ledger.is_active ledger_active
FROM cash_accounts cash JOIN ledger_accounts ledger ON ledger.id=cash.ledger_account_id
WHERE ${spec.$2 ? 'cash.id=?' : "cash.id=(SELECT cash_account_id FROM quick_payment_options WHERE id=? AND is_active=1)"}
''',
        [spec.$1],
      );
      if (found.length != 1 ||
          found.single['is_active'] != 1 ||
          found.single['is_available'] != 1 ||
          found.single['ledger_active'] != 1 ||
          found.single['class'] != 'asset' ||
          found.single['role'] != 'cash') {
        throw const TreasuryOpeningValidationException(
          'Configura Caja, Nequi y Caja mayor disponibles primero.',
        );
      }
      rows.add(found.single);
    }
    if (rows.map((row) => row['id']).toSet().length != 3) {
      throw const TreasuryOpeningValidationException(
        'Las tres cuentas monetarias deben ser distintas.',
      );
    }
    return rows;
  }

  static Future<void> _unusedCommand(DatabaseExecutor txn, String id) async {
    for (final table in [
      'sale_confirmations',
      'collection_requests',
      'supplier_payment_requests',
    ]) {
      if ((await txn.query(
        table,
        where: 'command_id=?',
        whereArgs: [id],
        limit: 1,
      )).isNotEmpty) {
        throw const TreasuryOpeningValidationException(
          'El identificador está reservado para otra operación.',
        );
      }
    }
    for (final spec in [
      ('quick_sale_requests', 'sale_command_id', 'collection_command_id'),
      ('paid_purchase_requests', 'purchase_command_id', 'payment_command_id'),
    ]) {
      if ((await txn.rawQuery(
        'SELECT command_id FROM ${spec.$1} WHERE command_id=? OR ${spec.$2}=? OR ${spec.$3}=?',
        [id, id, id],
      )).isNotEmpty) {
        throw const TreasuryOpeningValidationException(
          'El identificador está reservado para otra operación.',
        );
      }
    }
  }

  static Future<void> _systemRows(DatabaseExecutor txn, String now) async {
    final actors = await txn.query(
      'actors',
      where: 'id=?',
      whereArgs: [_operator],
    );
    if (actors.isEmpty) {
      await txn.insert('actors', {
        'id': _operator,
        'display_name': 'Operador local',
        'kind': 'system',
        'is_active': 1,
        'created_at_utc': now,
      });
    } else if (actors.single['kind'] != 'system' ||
        actors.single['is_active'] != 1) {
      throw const TreasuryOpeningValidationException(
        'El operador local no está disponible.',
      );
    }
    for (final spec in [
      (
        _equity,
        'OPENING-EQUITY',
        'Saldos iniciales declarados',
        'equity',
        'opening_balance',
      ),
      (
        _receivables,
        'LEGACY-CUSTOMER-RECEIVABLES',
        'Deudas agregadas de clientes desde copia',
        'asset',
        'receivable',
      ),
    ]) {
      final found = await txn.query(
        'ledger_accounts',
        where: 'id=? OR code=?',
        whereArgs: [spec.$1, spec.$2],
      );
      if (found.isEmpty) {
        await txn.insert('ledger_accounts', {
          'id': spec.$1,
          'code': spec.$2,
          'name': spec.$3,
          'class': spec.$4,
          'role': spec.$5,
          'is_active': 1,
        });
      } else if (found.length != 1 ||
          found.single['id'] != spec.$1 ||
          found.single['code'] != spec.$2 ||
          found.single['class'] != spec.$4 ||
          found.single['role'] != spec.$5 ||
          found.single['is_active'] != 1) {
        throw const TreasuryOpeningValidationException(
          'Una cuenta interna de apertura no está disponible.',
        );
      }
    }
  }
}
