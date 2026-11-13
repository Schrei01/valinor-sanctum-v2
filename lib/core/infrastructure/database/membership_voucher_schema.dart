/// A voucher settles only the new sale that redeemed it. It is a non-cash
/// allowance, never a cash account or a repayment of older personal debt.
abstract final class MembershipVoucherSchema {
  static List<String> build(List<String> debtors, List<String> payment) => [
    "ALTER TABLE quick_sales_lines ADD COLUMN voucher_selected INTEGER NOT NULL DEFAULT 0 CHECK(voucher_selected IN(0,1))",
    "ALTER TABLE quick_sales_lines ADD COLUMN voucher_minor INTEGER NOT NULL DEFAULT 0 CHECK(typeof(voucher_minor)='integer' AND voucher_minor>=0)",
    'ALTER TABLE quick_sales_lines ADD COLUMN voucher_period_id TEXT REFERENCES membership_periods(id)',
    '''CREATE TABLE membership_voucher_grants(
      period_id TEXT PRIMARY KEY NOT NULL REFERENCES membership_periods(id),
      amount_minor INTEGER NOT NULL CHECK(typeof(amount_minor)='integer' AND amount_minor>0))''',
    '''CREATE TABLE membership_voucher_plans(
      request_id TEXT PRIMARY KEY NOT NULL REFERENCES quick_sale_requests(command_id) DEFERRABLE INITIALLY DEFERRED,
      account_id TEXT NOT NULL REFERENCES quick_sales_accounts(id),
      period_id TEXT NOT NULL REFERENCES membership_voucher_grants(period_id),
      command_id TEXT NOT NULL UNIQUE,
      occurred_at_utc TEXT NOT NULL,
      amount_minor INTEGER NOT NULL CHECK(typeof(amount_minor)='integer' AND amount_minor>0),
      allocations_json TEXT NOT NULL CHECK(json_valid(allocations_json) AND json_type(allocations_json)='array'))''',
    '''CREATE TABLE membership_voucher_collections(
      document_id TEXT PRIMARY KEY NOT NULL REFERENCES business_documents(id),
      request_id TEXT NOT NULL UNIQUE REFERENCES membership_voucher_plans(request_id),
      receivable_id TEXT NOT NULL REFERENCES customer_receivables(id),
      amount_minor INTEGER NOT NULL CHECK(typeof(amount_minor)='integer' AND amount_minor>0))''',
    'DROP VIEW all_receivable_settlements',
    '''CREATE VIEW all_receivable_settlements AS
 SELECT id,receivable_id,collection_id,amount_minor FROM receivable_settlements
 UNION ALL SELECT id,receivable_id,collection_id,amount_minor FROM debtor_payment_allocations
 UNION ALL SELECT document_id,receivable_id,document_id,amount_minor FROM membership_voucher_collections''',
    'DROP TRIGGER collections_validate_document_posting',
    debtors
        .singleWhere(
          (s) => s.startsWith(
            'CREATE TRIGGER collections_validate_document_posting\n',
          ),
        )
        .replaceFirst(
          '\nBEGIN\n',
          '\n AND NOT EXISTS(SELECT 1 FROM membership_voucher_collections WHERE document_id=NEW.id)\nBEGIN\n',
        ),
    'DROP TRIGGER account_payment_prepare_guard',
    payment
        .singleWhere(
          (s) => s.startsWith('CREATE TRIGGER account_payment_prepare_guard '),
        )
        .replaceFirst(
          "(a.payment_mode='single' AND (",
          "(a.payment_mode='single' AND NOT EXISTS(SELECT 1 FROM membership_voucher_plans WHERE request_id=NEW.command_id) AND (",
        ),
    '''CREATE TRIGGER voucher_request_input BEFORE INSERT ON quick_sale_requests
      WHEN coalesce(json_extract(NEW.canonical_payload,'\$.voucherMinor'),0)>0 OR EXISTS(SELECT 1 FROM membership_voucher_plans WHERE request_id=NEW.command_id)
      BEGIN SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM membership_voucher_plans p
        WHERE p.request_id=NEW.command_id AND p.account_id=NEW.account_id AND p.occurred_at_utc=NEW.occurred_at_utc
        AND p.amount_minor=json_extract(NEW.canonical_payload,'\$.voucherMinor')
        AND p.amount_minor<=json_extract(NEW.canonical_payload,'\$.creditMinor'))
        OR EXISTS(SELECT 1 FROM quick_sales_accounts a JOIN quick_sales_lines s ON s.account_id=a.id
          WHERE a.id=NEW.account_id AND a.payment_mode='single' AND (
          (s.voucher_minor=0 AND (json_array_length(s.payment_split_json)>0 OR s.is_credit<>(a.account_payment_option_id='quick-debt')
            OR (s.is_credit=0 AND s.payment_option_id IS NOT a.account_payment_option_id)))
          OR (s.voucher_minor>0 AND (
            (CAST(s.quantity_text AS INTEGER)*s.unit_price_minor>s.voucher_minor AND a.account_payment_option_id IS NULL)
            OR EXISTS(SELECT 1 FROM json_each(s.payment_split_json) part WHERE json_extract(part.value,'\$.paymentOptionId')<>'quick-debt'
              AND json_extract(part.value,'\$.paymentOptionId') IS NOT a.account_payment_option_id)
            OR coalesce((SELECT sum(json_extract(value,'\$.amountMinor')) FROM json_each(s.payment_split_json)
              WHERE json_extract(value,'\$.paymentOptionId')='quick-debt'),0)<>
              s.voucher_minor+CASE WHEN a.account_payment_option_id='quick-debt' THEN CAST(s.quantity_text AS INTEGER)*s.unit_price_minor-s.voucher_minor ELSE 0 END))))
        THEN RAISE(ABORT,'Voucher checkout must preserve the chosen payment of the remainder') END; END''',
    '''CREATE TRIGGER voucher_grant_validate BEFORE INSERT ON membership_voucher_grants
      BEGIN SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM membership_periods p
        JOIN membership_sale_plans s ON s.request_id=p.sale_request_id, app_profile profile
        WHERE p.id=NEW.period_id AND EXISTS(SELECT 1 FROM json_each(s.payload) WHERE json_extract(value,'\$.kind')='signup')
        AND NEW.amount_minor=CASE profile.money_scale WHEN 0 THEN 30000 WHEN 1 THEN 300000 WHEN 2 THEN 3000000
          WHEN 3 THEN 30000000 WHEN 4 THEN 300000000 WHEN 5 THEN 3000000000 WHEN 6 THEN 30000000000 END)
      THEN RAISE(ABORT,'Voucher grants require a confirmed monthly enrollment intent') END; END''',
    '''CREATE TRIGGER voucher_plan_validate BEFORE INSERT ON membership_voucher_plans
      BEGIN SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM quick_sales_accounts a
        JOIN membership_periods p ON p.person_id=a.debtor_id JOIN membership_voucher_grants g ON g.period_id=p.id
        WHERE a.id=NEW.account_id AND a.status='open' AND p.id=NEW.period_id
        AND date(NEW.occurred_at_utc,'-5 hours')>=p.starts AND date(NEW.occurred_at_utc,'-5 hours')<p.ends)
      OR json_array_length(NEW.allocations_json)=0
      OR (SELECT sum(json_extract(value,'\$.amountMinor')) FROM json_each(NEW.allocations_json))<>NEW.amount_minor
      OR json_array_length(NEW.allocations_json)<>(SELECT count(*) FROM quick_sales_lines WHERE account_id=NEW.account_id AND voucher_minor>0)
      OR EXISTS(SELECT 1 FROM json_each(NEW.allocations_json) part WHERE NOT EXISTS(
        SELECT 1 FROM quick_sales_lines l WHERE l.id=json_extract(part.value,'\$.lineId') AND l.account_id=NEW.account_id
        AND l.voucher_selected=1 AND l.voucher_period_id=NEW.period_id AND l.voucher_minor=json_extract(part.value,'\$.amountMinor')
        AND l.product_id=json_extract(part.value,'\$.productId') AND l.product_id<>'membership:elven'
        AND l.voucher_minor>0 AND l.voucher_minor<=CAST(l.quantity_text AS INTEGER)*l.unit_price_minor))
      OR (SELECT count(DISTINCT json_extract(value,'\$.lineId')) FROM json_each(NEW.allocations_json))<>json_array_length(NEW.allocations_json)
      THEN RAISE(ABORT,'Voucher plan must match saved consumption and membership') END; END''',
    '''CREATE TRIGGER voucher_document_posting BEFORE UPDATE OF status ON business_documents
      WHEN OLD.status='draft' AND NEW.status='posted' AND EXISTS(SELECT 1 FROM membership_voucher_collections WHERE document_id=NEW.id)
      BEGIN
        SELECT CASE WHEN NEW.type<>'customer_collection' OR NEW.command_sequence<>0
          OR NOT EXISTS(SELECT 1 FROM membership_voucher_collections v
          JOIN membership_voucher_plans p ON p.request_id=v.request_id
          JOIN membership_periods period ON period.id=p.period_id
          JOIN membership_voucher_grants g ON g.period_id=period.id
          JOIN quick_sale_requests request ON request.command_id=p.request_id AND request.status='confirmed'
          JOIN command_log parent ON parent.id=request.command_id
          JOIN customer_receivables r ON r.id=v.receivable_id
          JOIN command_log c ON c.id=NEW.command_id AND c.command_type='membership_voucher'
          WHERE v.document_id=NEW.id AND p.command_id=NEW.command_id AND c.actor_id=NEW.actor_id
          AND c.authorization_policy_version='development-single-user-v1'
          AND NEW.occurred_at_utc=p.occurred_at_utc AND NEW.occurred_at_utc=request.occurred_at_utc
          AND NEW.business_date=date(NEW.occurred_at_utc,'-5 hours')
          AND date('now','-5 hours')>=period.starts AND date('now','-5 hours')<period.ends
          AND r.origin_document_id=json_extract(parent.response_json,'\$.result.saleDocumentId')
          AND v.amount_minor=p.amount_minor
          AND v.amount_minor<=g.amount_minor-coalesce((SELECT sum(other.amount_minor) FROM membership_voucher_collections other
            JOIN membership_voucher_plans op ON op.request_id=other.request_id
            JOIN business_documents d ON d.id=other.document_id AND d.status='posted'
            JOIN journal_entries e ON e.document_id=d.id AND e.status='posted' WHERE op.period_id=p.period_id AND other.document_id<>NEW.id),0)
          AND v.amount_minor<=r.initial_minor-coalesce((SELECT sum(s.amount_minor) FROM all_receivable_settlements s
            JOIN business_documents d ON d.id=s.collection_id AND d.status='posted'
            JOIN journal_entries e ON e.document_id=d.id AND e.status='posted' WHERE s.receivable_id=r.id AND s.collection_id<>NEW.id),0))
          OR EXISTS(SELECT 1 FROM collections WHERE document_id=NEW.id)
          THEN RAISE(ABORT,'Voucher must redeem available credit against its own confirmed sale') END;
        SELECT CASE WHEN NOT (${journal('NEW.id')})
          THEN RAISE(ABORT,'Voucher requires an exact non-cash allowance journal') END;
      END''',
    '''CREATE TRIGGER voucher_entry_posting BEFORE UPDATE OF status ON journal_entries
      WHEN OLD.status='draft' AND NEW.status='posted' AND EXISTS(SELECT 1 FROM membership_voucher_collections WHERE document_id=NEW.document_id)
      BEGIN
      SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM membership_voucher_collections v
        JOIN membership_voucher_plans p ON p.request_id=v.request_id
        JOIN membership_voucher_grants g ON g.period_id=p.period_id
        JOIN membership_periods period ON period.id=p.period_id
        JOIN customer_receivables r ON r.id=v.receivable_id
        WHERE v.document_id=NEW.document_id
        AND date('now','-5 hours')>=period.starts AND date('now','-5 hours')<period.ends
        AND v.amount_minor<=g.amount_minor-coalesce((SELECT sum(other.amount_minor) FROM membership_voucher_collections other
          JOIN membership_voucher_plans op ON op.request_id=other.request_id
          JOIN business_documents d ON d.id=other.document_id AND d.status='posted'
          JOIN journal_entries e ON e.document_id=d.id AND e.status='posted'
          WHERE op.period_id=p.period_id AND other.document_id<>NEW.document_id),0)
        AND v.amount_minor<=r.initial_minor-coalesce((SELECT sum(s.amount_minor) FROM all_receivable_settlements s
          JOIN business_documents d ON d.id=s.collection_id AND d.status='posted'
          JOIN journal_entries e ON e.document_id=d.id AND e.status='posted'
          WHERE s.receivable_id=r.id AND s.collection_id<>NEW.document_id),0))
        THEN RAISE(ABORT,'Voucher availability must still hold when its journal posts') END;
      SELECT CASE WHEN NOT (${journal('NEW.document_id')})
        THEN RAISE(ABORT,'Voucher journal changed before confirmation') END; END''',
    for (final table in [
      'membership_voucher_grants',
      'membership_voucher_plans',
      'membership_voucher_collections',
    ]) ...[
      for (final action in ['UPDATE', 'DELETE'])
        "CREATE TRIGGER ${table}_no_${action.toLowerCase()} BEFORE $action ON $table BEGIN SELECT RAISE(ABORT,'Voucher facts are immutable'); END",
    ],
    for (final spec in [
      ('membership_voucher_grants', 'existing.period_id=NEW.period_id'),
      (
        'membership_voucher_plans',
        'existing.request_id=NEW.request_id OR existing.command_id=NEW.command_id',
      ),
      (
        'membership_voucher_collections',
        'existing.document_id=NEW.document_id OR existing.request_id=NEW.request_id',
      ),
    ])
      '''CREATE TRIGGER ${spec.$1}_no_replace BEFORE INSERT ON ${spec.$1}
        WHEN EXISTS(SELECT 1 FROM ${spec.$1} existing WHERE ${spec.$2})
        BEGIN SELECT RAISE(ABORT,'Voucher identities cannot be replaced'); END''',
    '''CREATE TRIGGER voucher_collection_requires_draft BEFORE INSERT ON membership_voucher_collections
      WHEN NOT EXISTS(SELECT 1 FROM business_documents WHERE id=NEW.document_id AND status='draft' AND type='customer_collection')
      BEGIN SELECT RAISE(ABORT,'Create the voucher document as draft'); END''',
  ];
  static String journal(String doc) =>
      '''
    (SELECT count(*) FROM journal_lines l JOIN journal_entries e ON e.id=l.entry_id WHERE e.document_id=$doc)=2
    AND EXISTS(SELECT 1 FROM membership_voucher_collections v JOIN customer_receivables r ON r.id=v.receivable_id
      JOIN journal_entries e ON e.document_id=v.document_id JOIN journal_lines l ON l.entry_id=e.id
      JOIN ledger_accounts a ON a.id=l.account_id AND a.is_active=1
      WHERE v.document_id=$doc AND a.id='membership:voucher-allowance' AND a.class='expense' AND a.role='membership_benefit'
      AND l.debit_minor=v.amount_minor AND l.credit_minor=0)
    AND EXISTS(SELECT 1 FROM membership_voucher_collections v JOIN customer_receivables r ON r.id=v.receivable_id
      JOIN journal_entries e ON e.document_id=v.document_id JOIN journal_lines l ON l.entry_id=e.id
      WHERE v.document_id=$doc AND l.account_id=r.control_account_id AND l.credit_minor=v.amount_minor AND l.debit_minor=0)
  ''';
}
