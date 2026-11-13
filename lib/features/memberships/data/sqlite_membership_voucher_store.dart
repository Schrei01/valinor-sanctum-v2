import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../../core/infrastructure/database/app_database.dart';
import '../../../core/infrastructure/database/schema.dart';
import '../../inventory/domain/inventory_store.dart';
import '../../quick_sales/domain/quick_sales_store.dart';
import '../../quick_sales/domain/account_voucher.dart';
import '../domain/membership.dart';
import 'sqlite_membership_store.dart';

abstract final class SqliteMembershipVoucherStore {
  static Future<void> prepare(
    DatabaseExecutor txn,
    QuickSaleAccount account,
    String requestId,
    DateTime at,
  ) async {
    if (!account.lines.any((l) => l.useVoucher || l.voucherMinor > 0)) return;
    if (account.paymentMode == 'legacy') {
      SqliteMembershipStore.fail(
        'Revisa la forma de pago de la cuenta antes de usar su bono.',
      );
    }
    final member = (await SqliteMembershipStore.read(
      txn,
      at,
    )).where((m) => m.personId == account.debtorId).firstOrNull;
    if (member == null ||
        !member.activeAt(at) ||
        member.voucherRemainingMinor <= 0) {
      SqliteMembershipStore.fail(
        'Esta persona no tiene un bono vigente disponible.',
      );
    }
    final expected = allocateVoucher(
      account.lines,
      member.voucherRemainingMinor,
      member.periodId,
    );
    final allocations = <Map<String, Object?>>[];
    for (var i = 0; i < account.lines.length; i++) {
      final l = account.lines[i];
      if (l.useVoucher && l.productId == SqliteMembershipStore.productId) {
        SqliteMembershipStore.fail('El bono no puede pagar una mensualidad.');
      }
      if (l.voucherMinor != expected[i].voucherMinor ||
          l.voucherPeriodId != expected[i].voucherPeriodId) {
        SqliteMembershipStore.fail(
          'El bono disponible cambió. Actualiza y revisa la cuenta y su pago.',
        );
      }
      if (l.voucherMinor <= 0) continue;
      final product = (await txn.query(
        'catalog_items',
        where: 'id=? AND is_active=1',
        whereArgs: [l.productId],
      )).single;
      allocations.add({
        'lineId': l.id,
        'productId': l.productId,
        'name': product['name'],
        'quantity': int.parse(l.quantityText),
        'unitPriceMinor': l.unitPriceMinor,
        'amountMinor': l.voucherMinor,
      });
    }
    final total = accountVoucher(account).toInt();
    if (total <= 0) {
      SqliteMembershipStore.fail(
        'Selecciona un consumo válido para redimir el bono.',
      );
    }
    await txn.insert('membership_voucher_plans', {
      'request_id': requestId,
      'account_id': account.id,
      'period_id': member.periodId,
      'command_id': InventoryIds.next(),
      'occurred_at_utc': at.toIso8601String(),
      'amount_minor': total,
      'allocations_json': jsonEncode(allocations),
    });
  }

  /// The ordinary checkout first creates its exact sale/collection facts. This
  /// allowance then clears the voucher portion in the SAME caller transaction.
  /// No other connection can observe the intermediate receivable balance.
  static Future<int> settle(
    AppDatabase app,
    Transaction txn,
    String requestId,
    QuickSaleResult sale, {
    required bool synthetic,
  }) async {
    final plans = await txn.query(
      'membership_voucher_plans',
      where: 'request_id=?',
      whereArgs: [requestId],
    );
    if (plans.isEmpty) return 0;
    final p = plans.single, amount = p['amount_minor'] as int;
    final prior = await txn.query(
      'membership_voucher_collections',
      where: 'request_id=?',
      whereArgs: [requestId],
    );
    if (prior.isNotEmpty) return amount;
    final period = (await txn.query(
      'membership_periods',
      where: 'id=?',
      whereArgs: [p['period_id']],
    )).single;
    final member = (await SqliteMembershipStore.read(
      txn,
      DateTime.now().toUtc(),
    )).where((m) => m.personId == period['person_id']).single;
    if (member.periodId != p['period_id'] ||
        !member.activeAt(DateTime.now().toUtc()) ||
        member.voucherRemainingMinor < amount) {
      SqliteMembershipStore.fail(
        'El bono venció o ya fue usado en otra cuenta. Libera y revisa esta venta.',
      );
    }
    final receivable = (await txn.query(
      'customer_receivables',
      where: 'origin_document_id=?',
      whereArgs: [sale.saleDocumentId],
    )).single;
    final now = DateTime.now().toUtc().toIso8601String(),
        cmd = p['command_id'] as String;
    if ((await txn.query(
      'command_log',
      where: 'id=?',
      whereArgs: [cmd],
    )).isNotEmpty) {
      SqliteMembershipStore.fail(
        'El identificador del bono ya pertenece a otra operación.',
      );
    }
    final account = await txn.query(
      'ledger_accounts',
      where: "id='membership:voucher-allowance'",
    );
    if (account.isEmpty) {
      await txn.insert('ledger_accounts', {
        'id': 'membership:voucher-allowance',
        'code': 'MEMBER:VOUCHER',
        'name': 'Consumo incluido en membresías',
        'class': 'expense',
        'role': 'membership_benefit',
        'is_active': 1,
      });
    } else if (account.single['class'] != 'expense' ||
        account.single['role'] != 'membership_benefit' ||
        account.single['is_active'] != 1) {
      SqliteMembershipStore.fail(
        'La cuenta contable del bono no está disponible.',
      );
    }
    final doc = InventoryIds.next(), entry = InventoryIds.next();
    final profile = (await txn.query('app_profile')).single;
    await txn.insert('command_log', {
      'id': cmd,
      'command_type': 'membership_voucher',
      'payload_hash': DatabaseSchema.checksum(jsonEncode(p)),
      'actor_id': 'system:local-operator',
      'response_json': jsonEncode({
        'requestId': requestId,
        'documentId': doc,
        'amountMinor': amount,
      }),
      'response_version': 1,
      'committed_at_utc': now,
      'authorization_policy_version': 'development-single-user-v1',
    });
    final at = DateTime.parse(p['occurred_at_utc'] as String).toUtc();
    await txn.insert('business_documents', {
      'id': doc,
      'command_id': cmd,
      'command_sequence': 0,
      'profile_id': profile['profile_id'],
      'actor_id': 'system:local-operator',
      'type': 'customer_collection',
      'status': 'draft',
      'occurred_at_utc': at.toIso8601String(),
      'business_date': membershipDay(at).toIso8601String().substring(0, 10),
      'recorded_at_utc': now,
      'source_kind': synthetic ? 'synthetic' : 'native',
      'date_quality': 'documented',
    });
    await txn.insert('membership_voucher_collections', {
      'document_id': doc,
      'request_id': requestId,
      'receivable_id': receivable['id'],
      'amount_minor': amount,
    });
    await txn.insert('journal_entries', {
      'id': entry,
      'document_id': doc,
      'status': 'draft',
      'cost_completeness': 'not_applicable',
    });
    for (final part in [
      ('membership:voucher-allowance', amount, 0),
      (receivable['control_account_id'] as String, 0, amount),
    ].indexed) {
      await txn.insert('journal_lines', {
        'id': InventoryIds.next(),
        'entry_id': entry,
        'sequence': part.$1,
        'account_id': part.$2.$1,
        'debit_minor': part.$2.$2,
        'credit_minor': part.$2.$3,
      });
    }
    await txn.update(
      'business_documents',
      {'status': 'posted'},
      where: 'id=?',
      whereArgs: [doc],
    );
    await txn.update(
      'journal_entries',
      {'status': 'posted', 'posted_at_utc': now},
      where: 'id=?',
      whereArgs: [entry],
    );
    return amount;
  }

  static QuickSaleResult visible(QuickSaleResult raw, int voucher) =>
      QuickSaleResult(
        commandId: raw.commandId,
        saleDocumentId: raw.saleDocumentId,
        collectionDocumentId: raw.collectionDocumentId,
        totalMinor: raw.totalMinor,
        totalCostMinor: raw.totalCostMinor,
        creditMinor: raw.creditMinor - voucher,
        voucherMinor: voucher,
        customerName: raw.customerName,
        debtorId: raw.debtorId,
      );
}
