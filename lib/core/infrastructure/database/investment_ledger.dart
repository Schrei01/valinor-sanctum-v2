import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../domain/money.dart';
import 'schema.dart';

abstract final class InvestmentLedger {
  static const accountId = 'investment:owner-payable';
  static const optionId = 'investment';
  static const operatorId = 'system:local-operator';

  static int checked(BigInt value) {
    if (value < Money.minMinorUnits || value > Money.maxMinorUnits) {
      throw const InvestmentValidationException(
        'El saldo de inversión supera el límite monetario.',
      );
    }
    return value.toInt();
  }

  static Future<BigInt> signedBalance(
    DatabaseExecutor txn,
    String ledger,
  ) async {
    final rows = await txn.rawQuery(
      '''SELECT l.debit_minor,l.credit_minor FROM journal_lines l
      JOIN journal_entries e ON e.id=l.entry_id AND e.status='posted'
      JOIN business_documents d ON d.id=e.document_id AND d.status='posted'
      WHERE l.account_id=?''',
      [ledger],
    );
    return rows.fold<BigInt>(
      BigInt.zero,
      (sum, row) =>
          sum +
          BigInt.from(row['debit_minor'] as int) -
          BigInt.from(row['credit_minor'] as int),
    );
  }

  static Future<int> balance(DatabaseExecutor txn) async =>
      checked(-(await signedBalance(txn, accountId)));

  /// Runs in the migration transaction (or once after creating a fresh profile).
  /// Only the preexisting negative reserve becomes owner debt; no old fact changes.
  static Future<void> initialize(
    DatabaseExecutor txn, {
    bool reclassificationOnly = false,
  }) async {
    final profile = await txn.query('app_profile', where: 'id=1');
    if (profile.isEmpty) return;
    final initialized = (await txn.query(
      'investment_initialization',
    )).isNotEmpty;
    if (reclassificationOnly && initialized) return;
    final reserve = await txn.query(
      'cash_accounts',
      where: 'id=?',
      whereArgs: ['treasury:main-cash'],
    );
    final raw = reserve.isEmpty
        ? BigInt.zero
        : await signedBalance(
            txn,
            reserve.single['ledger_account_id'] as String,
          );
    final prior = checked(raw);
    final at = DateTime.now().toUtc();
    if (reclassificationOnly && raw >= BigInt.zero) {
      await txn.insert('investment_initialization', {
        'id': 1,
        'occurred_at_utc': at.toIso8601String(),
        'reserve_balance_minor': prior,
      });
      return;
    }
    final accounts = await txn.query(
      'ledger_accounts',
      where: 'id=? OR code=?',
      whereArgs: [accountId, 'INVESTMENT:OWNER'],
    );
    if (accounts.isEmpty) {
      await txn.insert('ledger_accounts', {
        'id': accountId,
        'code': 'INVESTMENT:OWNER',
        'name': 'Inversión por recuperar',
        'class': 'liability',
        'role': 'owner_payable',
        'is_active': 1,
      });
    } else if (accounts.length != 1 ||
        accounts.single['id'] != accountId ||
        accounts.single['code'] != 'INVESTMENT:OWNER' ||
        accounts.single['class'] != 'liability' ||
        accounts.single['role'] != 'owner_payable' ||
        accounts.single['is_active'] != 1) {
      throw const InvestmentValidationException(
        'La cuenta de inversión no está disponible.',
      );
    }
    if (initialized) return;
    final amount = raw < BigInt.zero ? checked(-raw) : 0;
    const id = 'investment:initial-reclassification:v19';
    if (amount == 0) {
      await txn.insert('investment_initialization', {
        'id': 1,
        'occurred_at_utc': at.toIso8601String(),
        'reserve_balance_minor': prior,
      });
      return;
    }
    await post(
      txn,
      commandId: id,
      kind: 'opening',
      amount: amount,
      counterLedger: reserve.single['ledger_account_id'] as String,
      sourceCashId: reserve.single['id'] as String,
      occurredAt: at,
      reason: 'Traslado de Caja mayor a Inversión por recuperar',
      canonical: jsonEncode({'version': 1, 'reserveBalanceMinor': prior}),
      beforePosting: (documentId) => txn.insert('investment_initialization', {
        'id': 1,
        'occurred_at_utc': at.toIso8601String(),
        'reserve_balance_minor': prior,
        'document_id': documentId,
      }),
    );
  }

  static Future<void> checkChronology(
    DatabaseExecutor txn,
    Iterable<String> ledgers,
    DateTime at,
  ) async {
    if (!at.isUtc || at.year < 1 || at.year > 9998) {
      throw const InvestmentValidationException(
        'La fecha debe ser UTC y válida.',
      );
    }
    for (final ledger in ledgers) {
      final rows = await txn.rawQuery(
        '''SELECT d.occurred_at_utc FROM journal_lines l
        JOIN journal_entries e ON e.id=l.entry_id AND e.status='posted'
        JOIN business_documents d ON d.id=e.document_id AND d.status='posted' WHERE l.account_id=?''',
        [ledger],
      );
      if (rows.any(
        (row) => DateTime.parse(row['occurred_at_utc'] as String).isAfter(at),
      )) {
        throw const InvestmentValidationException(
          'La operación no puede ser anterior al último movimiento de la cuenta o inversión.',
        );
      }
    }
  }

  static Future<void> checkPurchase(
    DatabaseExecutor txn,
    int amount,
    DateTime at,
  ) async {
    await checkChronology(txn, [accountId], at);
    checked(BigInt.from(await balance(txn)) + BigInt.from(amount));
  }

  /// Exact two-line settlement: supplier payable -> owner payable, or refund.
  /// IDs are reserved by the durable parent; every write shares its transaction.
  static Future<String> post(
    DatabaseExecutor txn, {
    required String commandId,
    required String kind,
    required int amount,
    required String counterLedger,
    String? sourceCashId,
    String? payableId,
    required DateTime occurredAt,
    required String reason,
    required String canonical,
    bool synthetic = false,
    Future<Object?> Function(String)? beforePosting,
  }) async {
    if (amount <= 0) {
      throw const InvestmentValidationException('El valor debe ser positivo.');
    }
    final profile = (await txn.query('app_profile', where: 'id=1')).single;
    if (profile['business_timezone'] != 'America/Bogota') {
      throw const InvestmentValidationException(
        'La inversión requiere horario de Bogotá.',
      );
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final actor = await txn.query(
      'actors',
      where: 'id=?',
      whereArgs: [operatorId],
    );
    if (actor.isEmpty) {
      await txn.insert('actors', {
        'id': operatorId,
        'display_name': 'Operador local',
        'kind': 'system',
        'is_active': 1,
        'created_at_utc': now,
      });
    } else if (actor.single['is_active'] != 1) {
      throw const InvestmentValidationException(
        'El operador local no está disponible.',
      );
    }
    final document = '$commandId:document';
    final entry = '$commandId:journal';
    await txn.insert('command_log', {
      'id': commandId,
      'command_type': 'investment_$kind',
      'payload_hash': DatabaseSchema.checksum(canonical),
      'actor_id': operatorId,
      'response_json': jsonEncode({
        'canonicalPayload': canonical,
        'result': {'documentId': document, 'amountMinor': amount},
      }),
      'response_version': 1,
      'committed_at_utc': now,
      'authorization_policy_version': 'development-single-user-v1',
    });
    final local = occurredAt.subtract(const Duration(hours: 5));
    final date =
        '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    await txn.insert('business_documents', {
      'id': document,
      'command_id': commandId,
      'command_sequence': 0,
      'profile_id': profile['profile_id'],
      'actor_id': operatorId,
      'type': 'investment_$kind',
      'status': 'draft',
      'occurred_at_utc': occurredAt.toIso8601String(),
      'business_date': date,
      'recorded_at_utc': now,
      'reason': reason,
      'source_kind': synthetic ? 'synthetic' : 'native',
      'date_quality': 'documented',
    });
    await txn.insert('investment_operations', {
      'document_id': document,
      'kind': kind,
      'amount_minor': amount,
      'payable_id': payableId,
      'source_cash_account_id': sourceCashId,
      'counter_account_id': counterLedger,
    });
    await txn.insert('journal_entries', {
      'id': entry,
      'document_id': document,
      'status': 'draft',
      'cost_completeness': 'not_applicable',
    });
    for (final line in [
      (kind == 'refund' ? accountId : counterLedger, amount, 0),
      (kind == 'refund' ? counterLedger : accountId, 0, amount),
    ].indexed) {
      await txn.insert('journal_lines', {
        'id': '$entry:${line.$1}',
        'entry_id': entry,
        'sequence': line.$1,
        'account_id': line.$2.$1,
        'debit_minor': line.$2.$2,
        'credit_minor': line.$2.$3,
      });
    }
    await beforePosting?.call(document);
    await txn.update(
      'business_documents',
      {'status': 'posted'},
      where: 'id=?',
      whereArgs: [document],
    );
    await txn.update(
      'journal_entries',
      {'status': 'posted', 'posted_at_utc': now},
      where: 'id=?',
      whereArgs: [entry],
    );
    return document;
  }
}

class InvestmentValidationException implements Exception {
  const InvestmentValidationException(this.message);
  final String message;
}
