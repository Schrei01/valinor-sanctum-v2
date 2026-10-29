/// V19 adds owner financing without treating it as available cash.
abstract final class InvestmentSchema {
  static List<String> build({
    required List<String> intakeV15,
    required List<String> intakeV7,
  }) {
    String replace(String sql, String before, String after) {
      if (!sql.contains(before)) {
        throw StateError('Missing investment migration anchor: $before');
      }
      return sql.replaceFirst(before, after);
    }

    var table = intakeV15.singleWhere(
      (s) => s.contains('CREATE TABLE paid_purchase_entries_upgrade ('),
    );
    table = table.replaceFirst(
      'paid_purchase_entries_upgrade',
      'paid_purchase_entries_v19',
    );
    table = replace(
      table,
      'REFERENCES supplier_payments(document_id)',
      'REFERENCES business_documents(id)',
    );
    for (final column in [
      'payment_option_id',
      'cash_account_id',
      'payment_method_id',
      'cash_account_name_snapshot',
      'cash_account_kind_snapshot',
      'payment_method_code_snapshot',
      'payment_method_name_snapshot',
    ]) {
      table = replace(table, '$column TEXT NOT NULL', '$column TEXT');
    }
    final end = table.lastIndexOf(')');
    table =
        '${table.substring(0, end)}, CHECK ((payment_option_id IS NULL AND payment_option_label_snapshot=\'Inversión\' AND cash_account_id IS NULL AND payment_method_id IS NULL AND cash_account_name_snapshot IS NULL AND cash_account_kind_snapshot IS NULL AND payment_method_code_snapshot IS NULL AND payment_method_name_snapshot IS NULL) OR (payment_option_id IS NOT NULL AND cash_account_id IS NOT NULL AND payment_method_id IS NOT NULL AND cash_account_name_snapshot IS NOT NULL AND cash_account_kind_snapshot IS NOT NULL AND payment_method_code_snapshot IS NOT NULL AND payment_method_name_snapshot IS NOT NULL))${table.substring(end)}';
    final originalInsert = intakeV15.singleWhere(
      (s) =>
          s.contains('CREATE TRIGGER paid_purchase_entries_validate_insert\n'),
    );
    const start = 'SELECT CASE WHEN NOT (';
    final from = originalInsert.indexOf(start) + start.length;
    final to = originalInsert.indexOf(')\n    THEN RAISE', from);
    if (from < start.length || to < from) {
      throw StateError('Missing paid intake proof');
    }
    final oldMatch = originalInsert.substring(from, to);
    final insert = replace(
      originalInsert,
      oldMatch,
      '($oldMatch OR ${_intakeMatch('NEW')})',
    );
    final update = replace(
      intakeV15.singleWhere(
        (s) => s.contains(
          'CREATE TRIGGER paid_purchase_requests_validate_update\n',
        ),
      ),
      oldMatch.replaceAll('NEW.', 'fact.'),
      '(${oldMatch.replaceAll('NEW.', 'fact.')} OR ${_intakeMatch('fact')})',
    );
    var reserveIds = intakeV7.singleWhere(
      (s) => s.contains(
        'CREATE TRIGGER paid_purchase_requests_reserve_command_ids\n',
      ),
    );
    reserveIds = replace(
      reserveIds,
      "NEW.command_type <> 'pay_supplier'",
      "NEW.command_type <> CASE WHEN json_extract(request.canonical_payload,'\$.paymentOptionId')='investment' THEN 'investment_purchase' ELSE 'pay_supplier' END",
    );
    return [
      '''CREATE TABLE investment_operations (
        document_id TEXT PRIMARY KEY NOT NULL REFERENCES business_documents(id) ON DELETE RESTRICT,
        kind TEXT NOT NULL CHECK(kind IN('opening','purchase','refund')),
        amount_minor INTEGER NOT NULL CHECK(typeof(amount_minor)='integer' AND amount_minor>0),
        payable_id TEXT UNIQUE REFERENCES obligations(id) ON DELETE RESTRICT,
        source_cash_account_id TEXT REFERENCES cash_accounts(id) ON DELETE RESTRICT,
        counter_account_id TEXT NOT NULL REFERENCES ledger_accounts(id) ON DELETE RESTRICT,
        CHECK((kind='purchase' AND payable_id IS NOT NULL AND source_cash_account_id IS NULL) OR (kind IN('opening','refund') AND payable_id IS NULL AND source_cash_account_id IS NOT NULL))
      )''',
      '''CREATE TABLE investment_initialization (
        id INTEGER PRIMARY KEY CHECK(id=1), occurred_at_utc TEXT NOT NULL,
        reserve_balance_minor INTEGER NOT NULL CHECK(typeof(reserve_balance_minor)='integer'),
        document_id TEXT UNIQUE REFERENCES investment_operations(document_id) ON DELETE RESTRICT,
        CHECK((reserve_balance_minor<0 AND document_id IS NOT NULL) OR (reserve_balance_minor>=0 AND document_id IS NULL))
      )''',
      '''CREATE TABLE investment_refund_requests (
        command_id TEXT PRIMARY KEY NOT NULL CHECK(length(trim(command_id)) BETWEEN 1 AND 128),
        canonical_payload TEXT NOT NULL CHECK(json_valid(canonical_payload)),
        occurred_at_utc TEXT NOT NULL, prepared_at_utc TEXT NOT NULL,
        status TEXT NOT NULL CHECK(status IN('prepared','executing','confirmed','rejected','discarded')),
        rejection_reason TEXT,
        CHECK((status IN('prepared','executing','confirmed') AND rejection_reason IS NULL) OR (status IN('rejected','discarded') AND length(trim(rejection_reason))>0))
      )''',
      'DROP TRIGGER paid_purchase_requests_validate_update',
      table,
      'INSERT INTO paid_purchase_entries_v19 SELECT * FROM paid_purchase_entries',
      'DROP TABLE paid_purchase_entries',
      'ALTER TABLE paid_purchase_entries_v19 RENAME TO paid_purchase_entries',
      'CREATE INDEX idx_paid_purchase_entries_product ON paid_purchase_entries(product_id)',
      insert,
      ...intakeV7.where(
        (s) => s.contains('CREATE TRIGGER paid_purchase_entries_no_'),
      ),
      update,
      'DROP TRIGGER paid_purchase_requests_reserve_command_ids',
      reserveIds,
      '''CREATE TRIGGER investment_refund_prepare_guard BEFORE INSERT ON investment_refund_requests BEGIN
        SELECT CASE WHEN NEW.status<>'prepared' OR EXISTS(SELECT 1 FROM investment_refund_requests WHERE command_id=NEW.command_id) OR EXISTS(SELECT 1 FROM command_log WHERE id=NEW.command_id)
          OR EXISTS(SELECT 1 FROM paid_purchase_requests WHERE NEW.command_id IN(command_id,purchase_command_id,payment_command_id))
          OR EXISTS(SELECT 1 FROM treasury_operation_requests WHERE command_id=NEW.command_id)
          THEN RAISE(ABORT,'Create a unique prepared investment refund') END;
      END''',
      '''CREATE TRIGGER investment_refund_transition BEFORE UPDATE ON investment_refund_requests BEGIN
        SELECT CASE WHEN NEW.command_id IS NOT OLD.command_id OR NEW.canonical_payload IS NOT OLD.canonical_payload OR NEW.occurred_at_utc IS NOT OLD.occurred_at_utc OR NEW.prepared_at_utc IS NOT OLD.prepared_at_utc
          OR NOT ((OLD.status='prepared' AND NEW.status IN('executing','rejected')) OR (OLD.status='executing' AND NEW.status='confirmed') OR (OLD.status='rejected' AND NEW.status='discarded'))
          OR (NEW.status='discarded' AND NEW.rejection_reason IS NOT OLD.rejection_reason)
          THEN RAISE(ABORT,'Immutable investment refund and invalid transition') END;
        SELECT CASE WHEN NEW.status IN('rejected','discarded') AND EXISTS(SELECT 1 FROM command_log WHERE id=OLD.command_id)
          THEN RAISE(ABORT,'A committed refund cannot be rejected') END;
        SELECT CASE WHEN NEW.status='confirmed' AND NOT EXISTS(SELECT 1 FROM investment_operations op JOIN business_documents d ON d.id=op.document_id AND d.status='posted' JOIN journal_entries e ON e.document_id=d.id AND e.status='posted' WHERE d.command_id=OLD.command_id AND op.kind='refund')
          THEN RAISE(ABORT,'Refund requires a posted investment operation') END;
      END''',
      '''CREATE TRIGGER investment_refund_reserve BEFORE INSERT ON command_log WHEN EXISTS(SELECT 1 FROM investment_refund_requests r WHERE r.command_id=NEW.id AND (r.status<>'executing' OR NEW.command_type<>'investment_refund')) BEGIN SELECT RAISE(ABORT,'Reserved refund command'); END''',
      '''CREATE TRIGGER investment_no_supplier_double_payment BEFORE INSERT ON supplier_payment_requests WHEN EXISTS(SELECT 1 FROM investment_operations op JOIN business_documents d ON d.id=op.document_id AND d.status='posted' WHERE op.payable_id=NEW.payable_id) BEGIN SELECT RAISE(ABORT,'Purchase already paid by owner investment'); END''',
      '''CREATE TRIGGER investment_fact_draft BEFORE INSERT ON investment_operations BEGIN
        SELECT CASE WHEN EXISTS(SELECT 1 FROM investment_operations WHERE document_id=NEW.document_id) OR NOT EXISTS(SELECT 1 FROM business_documents WHERE id=NEW.document_id AND status='draft' AND type='investment_'||NEW.kind)
          THEN RAISE(ABORT,'Investment facts require a unique draft document') END;
      END''',
      _posting,
      '''CREATE TRIGGER investment_balances_guard BEFORE UPDATE OF status ON business_documents WHEN NEW.status='posted' AND EXISTS(SELECT 1 FROM investment_operations WHERE document_id=NEW.id) BEGIN
        SELECT CASE WHEN EXISTS(SELECT 1 FROM investment_operations op WHERE op.document_id=NEW.id AND (
          ${_balance("'investment:owner-payable'", creditNormal: true)} IS NULL
          OR (op.kind='refund' AND (${_balance("'investment:owner-payable'", creditNormal: true)}<op.amount_minor OR ${_balance('op.counter_account_id')} IS NULL OR ${_balance('op.counter_account_id')}<op.amount_minor))
          OR (op.kind IN('opening','purchase') AND ${_balance("'investment:owner-payable'", creditNormal: true)}>9223372036854775807-op.amount_minor)
          OR (op.kind='opening' AND (${_balance('op.counter_account_id')} IS NULL OR ${_balance('op.counter_account_id')}<>-op.amount_minor OR ${_balance("'investment:owner-payable'", creditNormal: true)}<>0))
        )) THEN RAISE(ABORT,'Investment exceeds pending debt, available funds, or monetary bounds') END;
      END''',
      for (final table in [
        'sale_confirmations',
        'collection_requests',
        'supplier_payment_requests',
        'treasury_operation_requests',
        'debtor_requests',
        'event_requests',
        'stock_adjustment_requests',
        'quick_sale_requests',
        'paid_purchase_requests',
      ])
        '''CREATE TRIGGER ${table}_respect_investment_refund BEFORE INSERT ON $table WHEN EXISTS(SELECT 1 FROM investment_refund_requests r WHERE r.command_id=NEW.command_id
        ${table == 'quick_sale_requests'
            ? 'OR r.command_id IN(NEW.sale_command_id,NEW.collection_command_id)'
            : table == 'paid_purchase_requests'
            ? 'OR r.command_id IN(NEW.purchase_command_id,NEW.payment_command_id)'
            : ''}) BEGIN SELECT RAISE(ABORT,'Identifier reserved by an investment refund'); END''',
      '''CREATE TRIGGER investment_initialization_no_replace BEFORE INSERT ON investment_initialization WHEN EXISTS(SELECT 1 FROM investment_initialization WHERE id=NEW.id) BEGIN SELECT RAISE(ABORT,'Investment initialization is unique'); END''',
      '''CREATE TRIGGER investment_entry_proof BEFORE UPDATE OF status ON journal_entries WHEN NEW.status='posted' AND EXISTS(SELECT 1 FROM investment_operations WHERE document_id=NEW.document_id) BEGIN
        SELECT CASE WHEN (SELECT count(*) FROM journal_lines WHERE entry_id=NEW.id)<>2 OR EXISTS(
          SELECT 1 FROM journal_lines l JOIN investment_operations op ON op.document_id=NEW.document_id WHERE l.entry_id=NEW.id AND NOT (
            (l.sequence=0 AND l.account_id=CASE WHEN op.kind='refund' THEN 'investment:owner-payable' ELSE op.counter_account_id END AND l.debit_minor=op.amount_minor AND l.credit_minor=0)
            OR (l.sequence=1 AND l.account_id=CASE WHEN op.kind='refund' THEN op.counter_account_id ELSE 'investment:owner-payable' END AND l.credit_minor=op.amount_minor AND l.debit_minor=0)))
          THEN RAISE(ABORT,'Investment journal does not match its source') END;
      END''',
      for (final table in [
        'investment_operations',
        'investment_initialization',
        'investment_refund_requests',
      ])
        'CREATE TRIGGER ${table}_no_delete BEFORE DELETE ON $table BEGIN SELECT RAISE(ABORT,\'Investment history is immutable\'); END',
      for (final table in [
        'investment_operations',
        'investment_initialization',
      ])
        'CREATE TRIGGER ${table}_no_update BEFORE UPDATE ON $table BEGIN SELECT RAISE(ABORT,\'Investment history is immutable\'); END',
    ];
  }

  static String _intakeMatch(String f) =>
      '''EXISTS(
    SELECT 1 FROM paid_purchase_requests r JOIN purchases p ON p.document_id=$f.purchase_document_id
    JOIN business_documents pd ON pd.id=p.document_id AND pd.status='posted'
    JOIN journal_entries pe ON pe.document_id=pd.id AND pe.status='posted'
    JOIN purchase_lines line ON line.purchase_id=p.document_id
    JOIN obligations payable ON payable.origin_document_id=p.document_id
    JOIN investment_operations op ON op.document_id=$f.payment_document_id AND op.kind='purchase'
    JOIN business_documents od ON od.id=op.document_id AND od.status='posted'
    JOIN journal_entries oe ON oe.document_id=od.id AND oe.status='posted'
    JOIN catalog_items product ON product.id=$f.product_id
    JOIN categories cat ON cat.id=$f.category_id AND cat.is_active=1
    JOIN counterparties supplier ON supplier.id=$f.supplier_id AND supplier.is_active=1 AND supplier.is_supplier=1
    WHERE r.command_id=$f.request_id AND r.status='executing'
      AND json_extract(r.canonical_payload,'\$.version') IN(1,2) AND json_extract(r.canonical_payload,'\$.paymentOptionId')='investment'
      AND $f.payment_option_id IS NULL AND $f.payment_option_label_snapshot='Inversión'
      AND pd.command_id=r.purchase_command_id AND od.command_id=r.payment_command_id AND od.actor_id=pd.actor_id AND od.profile_id=pd.profile_id
      AND pd.occurred_at_utc=r.occurred_at_utc AND od.occurred_at_utc=r.occurred_at_utc
      AND p.supplier_id=$f.supplier_id AND p.supplier_name_snapshot=$f.supplier_name_snapshot AND supplier.name=$f.supplier_name_snapshot
      AND p.payable_minor=$f.total_cost_minor AND p.supplier_reference IS NULL AND p.due_date=pd.business_date
      AND op.payable_id=payable.id AND op.amount_minor=$f.total_cost_minor
      AND (SELECT count(*) FROM purchase_lines WHERE purchase_id=p.document_id)=1
      AND line.product_id=$f.product_id AND line.name_snapshot=$f.product_name_snapshot AND line.quantity=$f.quantity AND line.acquisition_total_minor=$f.total_cost_minor
      AND product.is_active=1 AND product.name=$f.product_name_snapshot AND product.sku IS $f.sku_snapshot AND product.category_id=$f.category_id AND product.list_price_minor=$f.list_price_minor AND cat.name=$f.category_name_snapshot
      AND json_extract(r.canonical_payload,'\$.profileId') IS pd.profile_id
      AND json_extract(r.canonical_payload,'\$.occurredAtUtc') IS r.occurred_at_utc
      ${[('productId', 'product_id'), ('productName', 'product_name_snapshot'), ('sku', 'sku_snapshot'), ('categoryId', 'category_id'), ('categoryName', 'category_name_snapshot'), ('supplierId', 'supplier_id'), ('supplierName', 'supplier_name_snapshot'), ('quantity', 'quantity'), ('unitPurchasePriceMinor', 'unit_purchase_price_minor'), ('listPriceMinor', 'list_price_minor'), ('totalCostMinor', 'total_cost_minor')].map((a) => "AND json_extract(r.canonical_payload,'\$.${a.$1}') IS $f.${a.$2}").join('\n')}
      AND ((json_extract(r.canonical_payload,'\$.version')=1 AND $f.unit_purchase_price_minor IS NOT NULL AND typeof($f.unit_purchase_price_minor * $f.quantity)='integer' AND $f.unit_purchase_price_minor * $f.quantity=$f.total_cost_minor)
      OR (json_extract(r.canonical_payload,'\$.version')=2 AND json_extract(r.canonical_payload,'\$.input.totalPurchasePriceMinor') IS $f.total_cost_minor
      AND json_extract(r.canonical_payload,'\$.input.unitPurchasePriceMinor') IS NULL
      AND json_extract(r.canonical_payload,'\$.input.quantity') IS $f.quantity
      AND $f.unit_purchase_price_minor IS CASE WHEN $f.total_cost_minor % $f.quantity=0 THEN $f.total_cost_minor/$f.quantity END))
  )''';

  /// Read posted lines in insertion order with checked integer additions.
  /// Never use floating aggregates or SUM, even when gross flows exceed int64.
  static String _balance(String account, {bool creditNormal = false}) =>
      '''(
    WITH RECURSIVE movements(n,amount) AS (
      SELECT row_number() OVER(ORDER BY l.rowid), ${creditNormal ? 'l.credit_minor-l.debit_minor' : 'l.debit_minor-l.credit_minor'}
      FROM journal_lines l JOIN journal_entries e ON e.id=l.entry_id AND e.status='posted'
      JOIN business_documents d ON d.id=e.document_id AND d.status='posted' WHERE l.account_id=$account
    ), running(n,value,valid) AS (SELECT 0,0,1 UNION ALL
      SELECT m.n, CASE WHEN valid=1 AND (CASE WHEN m.amount>=0 THEN value<=9223372036854775807-m.amount ELSE value>=(-9223372036854775807-1)-m.amount END) THEN value+m.amount ELSE 0 END,
      CASE WHEN valid=1 AND (CASE WHEN m.amount>=0 THEN value<=9223372036854775807-m.amount ELSE value>=(-9223372036854775807-1)-m.amount END) THEN 1 ELSE 0 END
      FROM running JOIN movements m ON m.n=running.n+1)
    SELECT CASE WHEN valid=1 THEN value END FROM running ORDER BY n DESC LIMIT 1)''';

  static const _posting =
      r'''CREATE TRIGGER investment_document_proof BEFORE UPDATE OF status ON business_documents
    WHEN NEW.status='posted' AND (NEW.type IN('investment_opening','investment_purchase','investment_refund') OR EXISTS(SELECT 1 FROM investment_operations WHERE document_id=NEW.id)) BEGIN
    SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM investment_operations op JOIN ledger_accounts a ON a.id='investment:owner-payable' AND a.class='liability' AND a.role='owner_payable' AND a.is_active=1 WHERE op.document_id=NEW.id AND NEW.type='investment_'||op.kind)
      THEN RAISE(ABORT,'Missing investment operation or owner liability') END;
    SELECT CASE WHEN EXISTS(SELECT 1 FROM investment_operations op WHERE op.document_id=NEW.id AND (
      (op.kind='opening' AND NOT EXISTS(SELECT 1 FROM investment_initialization init JOIN cash_accounts c ON c.id=op.source_cash_account_id AND c.id='treasury:main-cash' WHERE init.document_id=op.document_id AND init.reserve_balance_minor=-op.amount_minor AND c.ledger_account_id=op.counter_account_id))
      OR (op.kind='purchase' AND NOT EXISTS(SELECT 1 FROM obligations payable JOIN purchases p ON p.document_id=payable.origin_document_id JOIN paid_purchase_requests r ON r.purchase_command_id=(SELECT command_id FROM business_documents WHERE id=p.document_id) WHERE payable.id=op.payable_id AND r.payment_command_id=NEW.command_id AND r.status='executing' AND json_extract(r.canonical_payload,'$.paymentOptionId')='investment' AND payable.initial_minor=op.amount_minor AND payable.control_account_id=op.counter_account_id AND NOT EXISTS(SELECT 1 FROM payable_settlements WHERE payable_id=payable.id)))
      OR (op.kind='refund' AND NOT EXISTS(SELECT 1 FROM investment_refund_requests r JOIN quick_payment_options q ON q.cash_account_id=op.source_cash_account_id AND q.id IN('quick-default:EFECTIVO','quick-default:NEQUI') AND q.is_active=1 JOIN cash_accounts c ON c.id=q.cash_account_id AND c.is_active=1 AND c.is_available=1 JOIN ledger_accounts l ON l.id=c.ledger_account_id AND l.is_active=1 AND l.class='asset' AND l.role='cash' WHERE r.command_id=NEW.command_id AND r.status='executing' AND c.ledger_account_id=op.counter_account_id AND json_extract(r.canonical_payload,'$.sourceAccountId')=c.id AND json_extract(r.canonical_payload,'$.sourceLedgerAccountId')=c.ledger_account_id AND json_extract(r.canonical_payload,'$.amountMinor')=op.amount_minor AND r.occurred_at_utc=NEW.occurred_at_utc AND json_extract(r.canonical_payload,'$.profileId')=NEW.profile_id))
    )) THEN RAISE(ABORT,'Investment source does not match its prepared operation') END;
  END''';
}
