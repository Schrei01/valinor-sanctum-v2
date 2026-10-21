import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/domain/money.dart';
import '../../../core/infrastructure/database/app_database.dart';
import '../../../core/infrastructure/database/schema.dart';
import '../../inventory/domain/inventory_store.dart';
import '../../workspace/domain/business_profile.dart';
import '../domain/stock_intake_store.dart';

/// A declared starting balance is equity, never income or a supplier debt.
/// One opening per account, before any posted money movements, prevents a
/// current balance from being accidentally added on top of recorded sales.
class SqliteCashOpeningRecorder {
  SqliteCashOpeningRecorder(this._database, {this.synthetic = false});
  final AppDatabase _database;
  final bool synthetic;
  static const _operator = 'system:local-operator';
  static const _equity = 'system:opening-equity';

  Future<void> record(CashOpeningCommand command) async {
    for (final id in [command.commandId, command.paymentOptionId]) {
      if (!RegExp(r'^[A-Za-z0-9:_-]{1,128}$').hasMatch(id)) {
        throw const StockIntakeValidationException('Identificador no válido.');
      }
    }
    if (command.amountMinor <= 0 ||
        BigInt.from(command.amountMinor) > Money.maxMinorUnits) {
      throw const StockIntakeValidationException(
        'El saldo inicial debe ser positivo y estar dentro del rango permitido.',
      );
    }
    final time = command.occurredAtUtc;
    if (!time.isUtc || time.year < 1 || time.year > 9999) {
      throw const StockIntakeValidationException('La fecha no es válida.');
    }
    final date = time.subtract(const Duration(hours: 5));
    if (date.year < 1 || date.year > 9999) {
      throw const StockIntakeValidationException('La fecha no es válida.');
    }
    await _database.database.transaction((txn) async {
      final profileRows = await txn.query('app_profile', where: 'id=1');
      if (profileRows.length != 1) {
        throw const StockIntakeValidationException(
          'Configura el espacio de trabajo primero.',
        );
      }
      final profile = BusinessProfile.fromRow(profileRows.single);
      if (profile.timezone != 'America/Bogota') {
        throw const StockIntakeValidationException(
          'El saldo inicial requiere la zona horaria America/Bogota.',
        );
      }
      final canonical = jsonEncode({
        'version': 1,
        'profileId': profile.profileId,
        'currency': profile.currencyCode,
        'scale': profile.moneyScale,
        'paymentOptionId': command.paymentOptionId,
        'amountMinor': command.amountMinor,
        'occurredAtUtc': time.toIso8601String(),
      });
      final prior = await txn.query(
        'command_log',
        where: 'id=?',
        whereArgs: [command.commandId],
      );
      if (prior.isNotEmpty) {
        final row = prior.single;
        if (row['command_type'] != 'cash_opening' ||
            row['response_version'] != 1 ||
            row['payload_hash'] != DatabaseSchema.checksum(canonical)) {
          throw const StockIntakeValidationException(
            'El identificador ya corresponde a otra operación.',
          );
        }
        final response = jsonDecode(row['response_json'] as String);
        if (response is! Map || response['canonicalPayload'] != canonical) {
          throw const StockIntakeValidationException(
            'El identificador ya corresponde a otra operación.',
          );
        }
        return;
      }
      await _unused(txn, command.commandId);
      final options = await txn.rawQuery(
        '''
SELECT a.*, l.class, l.role, l.is_active AS ledger_active,
       m.is_active AS method_active, q.is_active AS option_active
FROM quick_payment_options q
JOIN cash_accounts a ON a.id=q.cash_account_id
JOIN payment_methods m ON m.id=q.payment_method_id
JOIN ledger_accounts l ON l.id=a.ledger_account_id
WHERE q.id=?
''',
        [command.paymentOptionId],
      );
      if (options.length != 1 ||
          options.single['is_active'] != 1 ||
          options.single['is_available'] != 1 ||
          options.single['ledger_active'] != 1 ||
          options.single['method_active'] != 1 ||
          options.single['option_active'] != 1 ||
          options.single['class'] != 'asset' ||
          options.single['role'] != 'cash') {
        throw const StockIntakeValidationException(
          'Selecciona una cuenta de Efectivo o Nequi disponible.',
        );
      }
      final account = options.single;
      if ((await txn.rawQuery(
        '''
SELECT document_id FROM treasury_openings
WHERE cash_account_id=? OR nequi_account_id=? OR reserve_account_id=? LIMIT 1
''',
        [account['id'], account['id'], account['id']],
      )).isNotEmpty) {
        throw const StockIntakeValidationException(
          'Esta cuenta ya tiene un saldo inicial importado de la copia.',
        );
      }
      if ((await txn.query(
        'cash_openings',
        where: 'cash_account_id=?',
        whereArgs: [account['id']],
      )).isNotEmpty) {
        throw const StockIntakeValidationException(
          'Esta cuenta ya tiene un saldo inicial registrado.',
        );
      }
      if ((await txn.rawQuery(
        '''
SELECT l.id FROM journal_lines l
JOIN journal_entries e ON e.id=l.entry_id AND e.status='posted'
JOIN business_documents d ON d.id=e.document_id AND d.status='posted'
WHERE l.account_id=? LIMIT 1
''',
        [account['ledger_account_id']],
      )).isNotEmpty) {
        throw const StockIntakeValidationException(
          'El saldo inicial se registra antes del primer movimiento de la cuenta.',
        );
      }
      final now = DateTime.now().toUtc().toIso8601String();
      await _systemRows(txn, now);
      final documentId = InventoryIds.next();
      final entryId = InventoryIds.next();
      final occurredAt = time.toIso8601String();
      await txn.insert('command_log', {
        'id': command.commandId,
        'command_type': 'cash_opening',
        'payload_hash': DatabaseSchema.checksum(canonical),
        'actor_id': _operator,
        'response_json': jsonEncode({
          'canonicalPayload': canonical,
          'result': {
            'documentId': documentId,
            'amountMinor': command.amountMinor,
          },
        }),
        'response_version': 1,
        'committed_at_utc': now,
        'authorization_policy_version': 'development-single-user-v1',
      });
      await txn.insert('business_documents', {
        'id': documentId,
        'command_id': command.commandId,
        'command_sequence': 0,
        'profile_id': profile.profileId,
        'actor_id': _operator,
        'type': 'cash_opening',
        'status': 'draft',
        'occurred_at_utc': occurredAt,
        'business_date':
            '${date.year.toString().padLeft(4, '0')}-'
            '${date.month.toString().padLeft(2, '0')}-'
            '${date.day.toString().padLeft(2, '0')}',
        'recorded_at_utc': now,
        'reason': 'Saldo inicial declarado por el usuario',
        'source_kind': synthetic ? 'synthetic' : 'native',
        'date_quality': 'documented',
      });
      await txn.insert('cash_openings', {
        'document_id': documentId,
        'command_id': command.commandId,
        'cash_account_id': account['id'],
        'amount_minor': command.amountMinor,
        'occurred_at_utc': occurredAt,
      });
      await txn.insert('journal_entries', {
        'id': entryId,
        'document_id': documentId,
        'status': 'draft',
        'cost_completeness': 'not_applicable',
      });
      for (final line in [
        (account['ledger_account_id'] as String, command.amountMinor, 0),
        (_equity, 0, command.amountMinor),
      ].indexed) {
        await txn.insert('journal_lines', {
          'id': InventoryIds.next(),
          'entry_id': entryId,
          'sequence': line.$1,
          'account_id': line.$2.$1,
          'debit_minor': line.$2.$2,
          'credit_minor': line.$2.$3,
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
    }, exclusive: true);
  }

  static Future<void> _unused(DatabaseExecutor txn, String commandId) async {
    for (final table in [
      'sale_confirmations',
      'collection_requests',
      'supplier_payment_requests',
    ]) {
      if ((await txn.query(
        table,
        columns: ['command_id'],
        where: 'command_id=?',
        whereArgs: [commandId],
      )).isNotEmpty) {
        throw const StockIntakeValidationException(
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
        [commandId, commandId, commandId],
      )).isNotEmpty) {
        throw const StockIntakeValidationException(
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
      throw const StockIntakeValidationException(
        'El operador no está disponible.',
      );
    }
    final ledgers = await txn.query(
      'ledger_accounts',
      where: 'id=?',
      whereArgs: [_equity],
    );
    if (ledgers.isEmpty) {
      await txn.insert('ledger_accounts', {
        'id': _equity,
        'code': 'OPENING-EQUITY',
        'name': 'Saldos iniciales declarados',
        'class': 'equity',
        'role': 'opening_balance',
        'is_active': 1,
      });
    } else if (ledgers.single['class'] != 'equity' ||
        ledgers.single['role'] != 'opening_balance' ||
        ledgers.single['is_active'] != 1) {
      throw const StockIntakeValidationException(
        'La cuenta interna de saldos iniciales no está disponible.',
      );
    }
  }
}
