import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../../core/domain/money.dart';
import '../../../core/infrastructure/database/app_database.dart';
import '../../../core/infrastructure/database/investment_ledger.dart';
import '../../../core/infrastructure/database/schema.dart';
import '../domain/treasury_operation_store.dart';

/// Durable refunds of owner financing. No expense, supplier or stock is created.
class SqliteInvestmentRefundStore {
  SqliteInvestmentRefundStore(this.app, {this.synthetic = false});
  final AppDatabase app;
  final bool synthetic;

  static PreparedTreasuryOperation prepared(Map<String, Object?> row) {
    final payload =
        jsonDecode(row['canonical_payload'] as String) as Map<String, dynamic>;
    return PreparedTreasuryOperation(
      command: TreasuryOperationCommand(
        commandId: row['command_id'] as String,
        kind: TreasuryOperationKind.investmentRefund,
        sourceAccountId: payload['sourceAccountId'] as String,
        amountMinor: payload['amountMinor'] as int,
        reason: 'Devolución de inversión',
        note: payload['note'] as String?,
        occurredAtUtc: DateTime.parse(row['occurred_at_utc'] as String),
      ),
      status: row['status'] as String,
      preparedAtUtc: DateTime.parse(row['prepared_at_utc'] as String),
      rejectionReason: row['rejection_reason'] as String?,
      sourceAccountName: payload['sourceAccountName'] as String,
    );
  }

  static Map<String, Object?> _input(TreasuryOperationCommand c) {
    if (c.kind != TreasuryOperationKind.investmentRefund ||
        c.destinationAccountId != null ||
        !RegExp(r'^[A-Za-z0-9:_-]{1,128}$').hasMatch(c.commandId) ||
        c.amountMinor <= 0 ||
        BigInt.from(c.amountMinor) > Money.maxMinorUnits ||
        !c.occurredAtUtc.isUtc ||
        c.occurredAtUtc.year < 1 ||
        c.occurredAtUtc.year > 9998 ||
        (c.note?.length ?? 0) > 500 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(c.note ?? '') ||
        c.reason != 'Devolución de inversión') {
      throw const TreasuryValidationException(
        'Revisa los datos de la devolución.',
      );
    }
    return {
      'sourceAccountId': c.sourceAccountId,
      'amountMinor': c.amountMinor,
      'note': c.note,
      'occurredAtUtc': c.occurredAtUtc.toIso8601String(),
    };
  }

  static Future<Map<String, Object?>> _source(
    DatabaseExecutor txn,
    String id,
  ) async {
    final rows = await txn.rawQuery(
      '''SELECT DISTINCT c.* FROM quick_payment_options q
      JOIN cash_accounts c ON c.id=q.cash_account_id AND c.is_active=1 AND c.is_available=1
      JOIN ledger_accounts l ON l.id=c.ledger_account_id AND l.is_active=1 AND l.class='asset' AND l.role='cash'
      JOIN payment_methods m ON m.id=q.payment_method_id AND m.is_active=1
      WHERE q.id IN('quick-default:EFECTIVO','quick-default:NEQUI') AND q.is_active=1 AND c.id=?''',
      [id],
    );
    if (rows.length != 1) {
      throw const TreasuryValidationException(
        'Elige Caja o Nequi disponibles para devolver la inversión.',
      );
    }
    return rows.single;
  }

  static Future<void> _funds(
    DatabaseExecutor txn,
    Map<String, Object?> source,
    TreasuryOperationCommand command,
  ) async {
    if (await InvestmentLedger.balance(txn) < command.amountMinor) {
      throw const TreasuryValidationException(
        'La devolución supera la inversión pendiente.',
      );
    }
    if (await InvestmentLedger.signedBalance(
          txn,
          source['ledger_account_id'] as String,
        ) <
        BigInt.from(command.amountMinor)) {
      throw const TreasuryValidationException(
        'El saldo de la cuenta no alcanza.',
      );
    }
    try {
      await InvestmentLedger.checkChronology(txn, [
        InvestmentLedger.accountId,
        source['ledger_account_id'] as String,
      ], command.occurredAtUtc);
    } on InvestmentValidationException catch (e) {
      throw TreasuryValidationException(e.message);
    }
  }

  Future<PreparedTreasuryOperation> prepare(
    TreasuryOperationCommand command,
  ) async {
    final input = _input(command);
    return app.database.transaction((txn) async {
      final rows = await txn.query(
        'investment_refund_requests',
        where: 'command_id=?',
        whereArgs: [command.commandId],
      );
      if (rows.isNotEmpty) {
        final old = prepared(rows.single);
        if (jsonEncode(_input(old.command)) != jsonEncode(input)) {
          throw const TreasuryValidationException(
            'El identificador ya corresponde a otra devolución.',
          );
        }
        return old;
      }
      for (final table in [
        'command_log',
        'treasury_operation_requests',
        'supplier_payment_requests',
        'collection_requests',
        'sale_confirmations',
        'debtor_requests',
        'event_requests',
      ]) {
        if ((await txn.query(
          table,
          columns: [table == 'command_log' ? 'id' : 'command_id'],
          where: '${table == 'command_log' ? 'id' : 'command_id'}=?',
          whereArgs: [command.commandId],
        )).isNotEmpty) {
          throw const TreasuryValidationException(
            'El identificador ya corresponde a otra operación.',
          );
        }
      }
      if ((await txn.rawQuery(
            'SELECT command_id FROM quick_sale_requests WHERE ? IN(command_id,sale_command_id,collection_command_id)',
            [command.commandId],
          )).isNotEmpty ||
          (await txn.rawQuery(
            'SELECT command_id FROM paid_purchase_requests WHERE ? IN(command_id,purchase_command_id,payment_command_id)',
            [command.commandId],
          )).isNotEmpty) {
        throw const TreasuryValidationException(
          'El identificador está reservado.',
        );
      }
      final source = await _source(txn, command.sourceAccountId);
      await _funds(txn, source, command);
      final profile = (await txn.query('app_profile', where: 'id=1')).single;
      final row = <String, Object?>{
        'command_id': command.commandId,
        'canonical_payload': jsonEncode({
          'version': 1,
          'profileId': profile['profile_id'],
          'currency': profile['currency_code'],
          'scale': profile['money_scale'],
          ...input,
          'sourceLedgerAccountId': source['ledger_account_id'],
          'sourceAccountName': source['name'],
        }),
        'occurred_at_utc': command.occurredAtUtc.toIso8601String(),
        'prepared_at_utc': DateTime.now().toUtc().toIso8601String(),
        'status': 'prepared',
      };
      await txn.insert('investment_refund_requests', row);
      return prepared(row);
    }, exclusive: true);
  }

  Future<TreasuryOperationResult> confirm(String id) async {
    try {
      return await app.database.transaction((txn) async {
        final rows = await txn.query(
          'investment_refund_requests',
          where: 'command_id=?',
          whereArgs: [id],
        );
        if (rows.length != 1) {
          throw const TreasuryValidationException(
            'La devolución preparada no existe.',
          );
        }
        final row = rows.single;
        final canonical = row['canonical_payload'] as String;
        final logs = await txn.query(
          'command_log',
          where: 'id=?',
          whereArgs: [id],
        );
        if (logs.isNotEmpty) {
          final log = logs.single;
          final response =
              jsonDecode(log['response_json'] as String)
                  as Map<String, dynamic>;
          if (log['command_type'] != 'investment_refund' ||
              log['payload_hash'] != DatabaseSchema.checksum(canonical) ||
              response['canonicalPayload'] != canonical) {
            throw const TreasuryValidationException(
              'El identificador corresponde a otra operación.',
            );
          }
          return TreasuryOperationResult(
            commandId: id,
            documentId:
                (response['result'] as Map<String, dynamic>)['documentId']
                    as String,
            kind: TreasuryOperationKind.investmentRefund,
            amountMinor: prepared(row).command.amountMinor,
          );
        }
        if (row['status'] != 'prepared') {
          throw const TreasuryValidationException(
            'La devolución ya no está pendiente.',
          );
        }
        final command = prepared(row).command;
        _input(command);
        final payload = jsonDecode(canonical) as Map<String, dynamic>;
        final profile = (await txn.query('app_profile', where: 'id=1')).single;
        if (payload['version'] != 1 ||
            payload['profileId'] != profile['profile_id'] ||
            payload['currency'] != profile['currency_code'] ||
            payload['scale'] != profile['money_scale'] ||
            payload['occurredAtUtc'] != row['occurred_at_utc']) {
          throw const TreasuryValidationException(
            'La configuración monetaria cambió.',
          );
        }
        final source = await _source(txn, command.sourceAccountId);
        if (source['ledger_account_id'] != payload['sourceLedgerAccountId']) {
          throw const TreasuryValidationException(
            'La identidad de la cuenta cambió.',
          );
        }
        await _funds(txn, source, command);
        await txn.update(
          'investment_refund_requests',
          {'status': 'executing'},
          where: 'command_id=?',
          whereArgs: [id],
        );
        final doc = await InvestmentLedger.post(
          txn,
          commandId: id,
          kind: 'refund',
          amount: command.amountMinor,
          counterLedger: source['ledger_account_id'] as String,
          sourceCashId: source['id'] as String,
          occurredAt: command.occurredAtUtc,
          reason: command.reason,
          canonical: canonical,
          synthetic: synthetic,
        );
        await txn.update(
          'investment_refund_requests',
          {'status': 'confirmed'},
          where: 'command_id=?',
          whereArgs: [id],
        );
        return TreasuryOperationResult(
          commandId: id,
          documentId: doc,
          kind: TreasuryOperationKind.investmentRefund,
          amountMinor: command.amountMinor,
        );
      }, exclusive: true);
    } on TreasuryValidationException catch (error) {
      await app.database.transaction((txn) async {
        if ((await txn.query(
          'command_log',
          where: 'id=?',
          whereArgs: [id],
        )).isEmpty) {
          await txn.update(
            'investment_refund_requests',
            {'status': 'rejected', 'rejection_reason': error.message},
            where: "command_id=? AND status='prepared'",
            whereArgs: [id],
          );
        }
      }, exclusive: true);
      rethrow;
    }
  }

  Future<void> discard(String id) => app.database.transaction((txn) async {
    final rows = await txn.query(
      'investment_refund_requests',
      where: 'command_id=?',
      whereArgs: [id],
    );
    if (rows.length != 1) {
      throw const TreasuryValidationException('La devolución no existe.');
    }
    if (rows.single['status'] == 'discarded') return;
    if (rows.single['status'] != 'rejected' ||
        (await txn.query(
          'command_log',
          where: 'id=?',
          whereArgs: [id],
        )).isNotEmpty) {
      throw const TreasuryValidationException(
        'Solo se puede corregir una devolución rechazada.',
      );
    }
    await txn.update(
      'investment_refund_requests',
      {'status': 'discarded'},
      where: 'command_id=?',
      whereArgs: [id],
    );
  }, exclusive: true);
}
