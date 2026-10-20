import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/infrastructure/database/app_database.dart';
import '../../quick_sales/data/sqlite_quick_sales_store.dart';
import '../domain/treasury_store.dart';

/// A read model over posted facts, with a separate, initially empty reserve.
class SqliteTreasuryStore implements TreasuryStore {
  SqliteTreasuryStore(this._database);
  final AppDatabase _database;

  static const reserveAccountId = 'treasury:main-cash';
  static const _reserveLedgerId = 'money:treasury:main-cash';
  static const _reserveLedgerCode = 'TREASURY:MAIN-CASH';

  @override
  Future<void> ensureDefaults() async {
    // Quick checkout chooses existing cash accounts when configuring Efectivo.
    // Configure it first so a fresh reserve can never become the sale account.
    await SqliteQuickSalesStore(_database).ensureDefaults();
    await _database.database.transaction((txn) async {
      await _requireProfile(txn);
      final ledgers = await txn.query(
        'ledger_accounts',
        where: 'id=? OR code=?',
        whereArgs: [_reserveLedgerId, _reserveLedgerCode],
      );
      if (ledgers.isEmpty) {
        await txn.insert('ledger_accounts', {
          'id': _reserveLedgerId,
          'code': _reserveLedgerCode,
          'name': 'Caja mayor',
          'class': 'asset',
          'role': 'cash',
          'is_active': 1,
        });
      } else if (ledgers.length != 1 ||
          ledgers.single['id'] != _reserveLedgerId ||
          ledgers.single['code'] != _reserveLedgerCode ||
          ledgers.single['class'] != 'asset' ||
          ledgers.single['role'] != 'cash') {
        throw const TreasuryValidationException(
          'La identidad de Caja mayor está ocupada por otra cuenta.',
        );
      }
      final accounts = await txn.query(
        'cash_accounts',
        where: 'id=? OR ledger_account_id=?',
        whereArgs: [reserveAccountId, _reserveLedgerId],
      );
      if (accounts.isEmpty) {
        await txn.insert('cash_accounts', {
          'id': reserveAccountId,
          'ledger_account_id': _reserveLedgerId,
          'name': 'Caja mayor',
          'kind': 'cash',
          'is_available': 1,
          'is_active': 1,
        });
      } else if (accounts.length != 1 ||
          accounts.single['id'] != reserveAccountId ||
          accounts.single['ledger_account_id'] != _reserveLedgerId ||
          accounts.single['kind'] != 'cash') {
        throw const TreasuryValidationException(
          'La identidad de Caja mayor está ocupada por otra cuenta.',
        );
      }
    }, exclusive: true);
  }

  @override
  Future<TreasurySnapshot> load() => _database.database.transaction((
    txn,
  ) async {
    await _requireProfile(txn);
    final accountRows = await txn.rawQuery('''
SELECT c.* FROM cash_accounts c
JOIN ledger_accounts l ON l.id=c.ledger_account_id
WHERE l.class='asset' AND l.role='cash'
ORDER BY c.name COLLATE NOCASE,c.id
''');
    final options = await txn.query(
      'quick_payment_options',
      where: 'id IN (?,?)',
      whereArgs: ['quick-default:EFECTIVO', 'quick-default:NEQUI'],
    );
    final roles = <String, TreasuryAccountRole>{
      reserveAccountId: TreasuryAccountRole.reserve,
    };
    for (final spec in [
      ('quick-default:EFECTIVO', TreasuryAccountRole.cash),
      ('quick-default:NEQUI', TreasuryAccountRole.nequi),
    ]) {
      final matches = options.where((option) => option['id'] == spec.$1);
      if (matches.length != 1) {
        throw const TreasuryValidationException(
          'Configura las cuentas de Efectivo y Nequi primero.',
        );
      }
      final id = matches.single['cash_account_id'] as String;
      if (roles.containsKey(id) ||
          !accountRows.any((account) => account['id'] == id)) {
        throw const TreasuryValidationException(
          'Efectivo, Nequi y Caja mayor requieren cuentas monetarias distintas.',
        );
      }
      roles[id] = spec.$2;
    }

    // Read every line for exact balances; never aggregate money with SQLite
    // SUM or native int, both of which can overflow before the final net.
    final lines = await txn.rawQuery('''
SELECT l.debit_minor,l.credit_minor,c.id cash_account_id,c.name account_name,
 d.id document_id,d.occurred_at_utc,d.type,
 col.sale_label_snapshot,col.customer_name_snapshot,
 pay.supplier_name_snapshot,
 EXISTS(SELECT 1 FROM quick_sale_line_payments q
   WHERE q.collection_document_id=d.id) is_quick_sale,
 EXISTS(SELECT 1 FROM paid_purchase_entries p
   WHERE p.payment_document_id=d.id) is_paid_purchase
FROM journal_lines l
JOIN journal_entries e ON e.id=l.entry_id AND e.status='posted'
JOIN business_documents d ON d.id=e.document_id AND d.status='posted'
JOIN cash_accounts c ON c.ledger_account_id=l.account_id
JOIN ledger_accounts a ON a.id=l.account_id AND a.class='asset' AND a.role='cash'
LEFT JOIN collections col ON col.document_id=d.id
LEFT JOIN supplier_payments pay ON pay.document_id=d.id
ORDER BY d.occurred_at_utc DESC,d.id,c.id,l.sequence,l.id
''');
    final balances = <String, BigInt>{};
    final grouped = <(String, String), _MovementAccumulator>{};
    for (final line in lines) {
      final account = line['cash_account_id'] as String;
      final document = line['document_id'] as String;
      final amount =
          BigInt.from(line['debit_minor'] as int) -
          BigInt.from(line['credit_minor'] as int);
      balances[account] = (balances[account] ?? BigInt.zero) + amount;
      final movement = grouped.putIfAbsent((
        document,
        account,
      ), () => _MovementAccumulator(line));
      movement.amount += amount;
    }
    final accounts = accountRows.map((row) {
      final id = row['id'] as String;
      return TreasuryAccount(
        id: id,
        name: row['name'] as String,
        role: roles[id] ?? TreasuryAccountRole.other,
        balanceMinor: treasuryCheckedMinor(
          balances[id] ?? BigInt.zero,
          'Saldo de ${row['name']}',
        ),
      );
    }).toList();
    accounts.sort((a, b) {
      final role = a.role.index.compareTo(b.role.index);
      if (role != 0) return role;
      final name = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return name != 0 ? name : a.id.compareTo(b.id);
    });
    final movements = grouped.values.map((item) => item.build()).toList()
      ..sort((a, b) {
        final time = b.occurredAtUtc.compareTo(a.occurredAtUtc);
        if (time != 0) return time;
        final document = a.documentId.compareTo(b.documentId);
        return document != 0
            ? document
            : a.cashAccountId.compareTo(b.cashAccountId);
      });
    final counts = <String, int>{};
    final recent = movements.where((movement) {
      final count = (counts[movement.cashAccountId] ?? 0) + 1;
      counts[movement.cashAccountId] = count;
      return count <= 50;
    }).toList();
    final legacyRows = await txn.rawQuery('''
SELECT o.receivables_minor FROM treasury_openings o
JOIN business_documents d ON d.id=o.document_id AND d.status='posted'
JOIN journal_entries e ON e.document_id=d.id AND e.status='posted'
''');
    final legacyReceivables = legacyRows.fold(
      BigInt.zero,
      (sum, row) => sum + BigInt.from(row['receivables_minor'] as int),
    );
    final totalReceivables =
        BigInt.from(await _receivables(txn)) + legacyReceivables;
    final snapshot = TreasurySnapshot(
      accounts: accounts,
      receivablesMinor: treasuryCheckedMinor(
        totalReceivables,
        'Deudas de clientes',
      ),
      legacyReceivablesMinor: treasuryCheckedMinor(
        legacyReceivables,
        'Cartera anterior',
      ),
      movements: recent,
    );
    // Reject an overflowing combined dashboard total before returning it.
    snapshot.totalAvailableMinor;
    return snapshot;
  });

  static Future<int> _receivables(DatabaseExecutor txn) async {
    final rows = await txn.rawQuery('''
SELECT r.id,r.initial_minor FROM customer_receivables r
JOIN sales s ON s.document_id=r.origin_document_id
JOIN business_documents d ON d.id=s.document_id AND d.status='posted'
JOIN journal_entries e ON e.document_id=d.id AND e.status='posted'
''');
    final payments = await txn.rawQuery('''
SELECT r.receivable_id,r.amount_minor FROM receivable_settlements r
JOIN business_documents d ON d.id=r.collection_id AND d.status='posted'
JOIN journal_entries e ON e.document_id=d.id AND e.status='posted'
''');
    final collected = <String, BigInt>{};
    for (final row in payments) {
      final id = row['receivable_id'] as String;
      collected[id] =
          (collected[id] ?? BigInt.zero) +
          BigInt.from(row['amount_minor'] as int);
    }
    var total = BigInt.zero;
    for (final row in rows) {
      final remaining =
          BigInt.from(row['initial_minor'] as int) -
          (collected[row['id']] ?? BigInt.zero);
      if (remaining.isNegative) {
        throw const TreasuryValidationException(
          'Una cuenta por cobrar tiene un saldo inconsistente.',
        );
      }
      total += remaining;
    }
    return treasuryCheckedMinor(total, 'Deudas de clientes');
  }

  static Future<void> _requireProfile(DatabaseExecutor txn) async {
    if ((await txn.query('app_profile', where: 'id=1')).length != 1) {
      throw const TreasuryValidationException(
        'Configura el espacio de trabajo primero.',
      );
    }
  }
}

class _MovementAccumulator {
  _MovementAccumulator(this.row);
  final Map<String, Object?> row;
  BigInt amount = BigInt.zero;

  TreasuryMovement build() {
    final account = row['cash_account_id'] as String;
    final document = row['document_id'] as String;
    final concept = switch (row['type']) {
      'cash_opening' => 'Saldo inicial',
      'treasury_opening' => 'Saldo inicial de la copia',
      'customer_collection' when row['is_quick_sale'] == 1 =>
        'Venta: ${row['sale_label_snapshot']}',
      'customer_collection' =>
        'Cobro: ${row['sale_label_snapshot']} · ${row['customer_name_snapshot']}',
      'supplier_payment' when row['is_paid_purchase'] == 1 =>
        'Compra: ${row['supplier_name_snapshot']}',
      'supplier_payment' =>
        'Pago a proveedor: ${row['supplier_name_snapshot']}',
      _ => 'Movimiento: ${row['type']}',
    };
    return TreasuryMovement(
      id: '${document.length}:$document$account',
      cashAccountId: account,
      accountName: row['account_name'] as String,
      documentId: document,
      occurredAtUtc: DateTime.parse(row['occurred_at_utc'] as String).toUtc(),
      concept: concept,
      amountMinor: treasuryCheckedMinor(amount, 'Movimiento de la cuenta'),
    );
  }
}
