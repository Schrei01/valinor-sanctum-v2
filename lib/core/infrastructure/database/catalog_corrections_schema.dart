/// v27 appends corrections; posted event and sale facts remain immutable.
abstract final class CatalogCorrectionsSchema {
  static List<String> build(List<String> treasury, List<String> stock) {
    final result = <String>[];
    for (final sql in treasury.where(
      (s) => s.contains("'Arriendo','Aseo','Servicios','Otro'"),
    )) {
      final name = RegExp(r'CREATE TRIGGER (\w+)').firstMatch(sql)!.group(1)!;
      result.addAll([
        'DROP TRIGGER $name',
        sql.replaceAll(
          "'Arriendo','Aseo','Servicios','Otro'",
          "'Arriendo','Aseo','Servicios','Agua','Energía','Envíos','Otro'",
        ),
      ]);
    }
    result.addAll([
      '''CREATE TABLE catalog_correction_requests (
 command_id TEXT PRIMARY KEY NOT NULL CHECK(length(command_id) BETWEEN 1 AND 128),
 canonical_payload TEXT NOT NULL CHECK(json_valid(canonical_payload)),
 prepared_at_utc TEXT NOT NULL,
 status TEXT NOT NULL CHECK(status IN('prepared','confirmed','discarded')))''',
      '''CREATE TABLE catalog_corrections (
 sequence INTEGER PRIMARY KEY,
 command_id TEXT NOT NULL UNIQUE REFERENCES command_log(id) ON DELETE RESTRICT,
 product_id TEXT NOT NULL REFERENCES catalog_items(id) ON DELETE RESTRICT,
 kind TEXT NOT NULL CHECK(kind IN('name','price','event')),
 previous_revision TEXT,
 before_json TEXT NOT NULL CHECK(json_valid(before_json)),
 after_json TEXT NOT NULL CHECK(json_valid(after_json)),
 occurred_at_utc TEXT NOT NULL)''',
      'CREATE INDEX catalog_corrections_product ON catalog_corrections(product_id,sequence)',
      '''CREATE TABLE event_return_values (
 stock_command_id TEXT PRIMARY KEY NOT NULL,
 correction_command_id TEXT NOT NULL REFERENCES catalog_correction_requests(command_id) ON DELETE RESTRICT,
 product_id TEXT NOT NULL REFERENCES catalog_items(id) ON DELETE RESTRICT,
 quantity INTEGER NOT NULL CHECK(typeof(quantity)='integer' AND quantity>0),
 unit_cost_minor INTEGER NOT NULL CHECK(typeof(unit_cost_minor)='integer' AND unit_cost_minor>=0),
 cost_minor INTEGER NOT NULL CHECK(typeof(cost_minor)='integer' AND cost_minor>=0 AND typeof(quantity*unit_cost_minor)='integer' AND cost_minor=quantity*unit_cost_minor))''',
      '''CREATE TABLE event_correction_payments (
 document_id TEXT PRIMARY KEY NOT NULL REFERENCES business_documents(id) ON DELETE RESTRICT,
 correction_command_id TEXT NOT NULL UNIQUE REFERENCES catalog_correction_requests(command_id) ON DELETE RESTRICT,
 product_id TEXT NOT NULL REFERENCES events(product_id) ON DELETE RESTRICT,
 source_option_id TEXT NOT NULL,
 source_ledger_id TEXT NOT NULL REFERENCES ledger_accounts(id) ON DELETE RESTRICT,
 amount_minor INTEGER NOT NULL CHECK(typeof(amount_minor)='integer' AND amount_minor>0),
 name_snapshot TEXT NOT NULL)''',
      '''CREATE VIEW event_current_settings AS
 SELECT e.document_id,e.product_id,
 coalesce(c.command_id,e.document_id) revision,
 coalesce(json_extract(c.after_json,'\$.name'),e.name_snapshot) name_snapshot,
 coalesce(json_extract(c.after_json,'\$.minimumPeople'),e.minimum_people) minimum_people,
 coalesce(json_extract(c.after_json,'\$.fixedCostMinor'),e.fixed_cost_minor) fixed_cost_minor,
 coalesce(json_extract(c.after_json,'\$.productsCostMinor'),e.products_cost_minor) products_cost_minor,
 coalesce(json_extract(c.after_json,'\$.totalCostMinor'),e.total_cost_minor) total_cost_minor,
 coalesce(json_extract(c.after_json,'\$.unitCostMinor'),e.unit_cost_minor) unit_cost_minor,
 coalesce(json_extract(c.after_json,'\$.priceMinor'),e.pvp_minor) pvp_minor,
 CASE WHEN c.command_id IS NULL THEN CASE WHEN e.funding_mode='investment' THEN 'investment' ELSE e.source_account_id END ELSE json_extract(c.after_json,'\$.sourceAccountId') END source_option_id,
 CASE WHEN c.command_id IS NULL THEN e.source_account_name_snapshot ELSE json_extract(c.after_json,'\$.sourceAccountName') END source_account_name_snapshot,
 e.fixed_cost_minor+coalesce((SELECT sum(p.amount_minor) FROM event_correction_payments p JOIN business_documents d ON d.id=p.document_id AND d.status='posted' JOIN journal_entries j ON j.document_id=d.id AND j.status='posted' WHERE p.product_id=e.product_id),0) paid_fixed_cost_minor
 FROM events e LEFT JOIN catalog_corrections c ON c.sequence=(SELECT max(sequence) FROM catalog_corrections WHERE product_id=e.product_id AND kind='event')''',
      '''CREATE VIEW event_current_components AS
 SELECT e.product_id event_product_id,p.product_id,p.quantity,p.cost_minor,p.name_snapshot FROM events e JOIN event_products p ON p.event_id=e.document_id
 WHERE NOT EXISTS(SELECT 1 FROM catalog_corrections c WHERE c.product_id=e.product_id AND c.kind='event')
 UNION ALL SELECT c.product_id,json_extract(p.value,'\$.productId'),json_extract(p.value,'\$.quantity'),json_extract(p.value,'\$.costMinor'),json_extract(p.value,'\$.name')
 FROM catalog_corrections c,json_each(c.after_json,'\$.components') p
 WHERE c.kind='event' AND c.sequence=(SELECT max(sequence) FROM catalog_corrections WHERE product_id=c.product_id AND kind='event')''',
      '''CREATE TRIGGER catalog_correction_requests_insert BEFORE INSERT ON catalog_correction_requests BEGIN
 SELECT CASE WHEN NEW.status<>'prepared' OR EXISTS(SELECT 1 FROM catalog_correction_requests WHERE command_id=NEW.command_id)
 OR EXISTS(SELECT 1 FROM command_log WHERE id=NEW.command_id)
 OR EXISTS(SELECT 1 FROM sale_confirmations WHERE command_id=NEW.command_id)
 OR EXISTS(SELECT 1 FROM collection_requests WHERE command_id=NEW.command_id)
 OR EXISTS(SELECT 1 FROM supplier_payment_requests WHERE command_id=NEW.command_id)
 OR EXISTS(SELECT 1 FROM treasury_operation_requests WHERE command_id=NEW.command_id)
 OR EXISTS(SELECT 1 FROM quick_sale_requests WHERE NEW.command_id IN(command_id,sale_command_id,collection_command_id))
 OR EXISTS(SELECT 1 FROM paid_purchase_requests WHERE NEW.command_id IN(command_id,purchase_command_id,payment_command_id))
 OR EXISTS(SELECT 1 FROM event_requests WHERE command_id=NEW.command_id)
 OR EXISTS(SELECT 1 FROM debtor_requests WHERE command_id=NEW.command_id)
 OR EXISTS(SELECT 1 FROM investment_refund_requests WHERE command_id=NEW.command_id)
 OR EXISTS(SELECT 1 FROM stock_adjustment_requests WHERE command_id=NEW.command_id)
 OR EXISTS(SELECT 1 FROM purchase_batch_requests WHERE command_id=NEW.command_id)
 OR json_extract(NEW.canonical_payload,'\$.input.commandId') IS NOT NEW.command_id
 OR json_extract(NEW.canonical_payload,'\$.input.kind') NOT IN('name','price','event')
 THEN RAISE(ABORT,'Correction requires a unique prepared request') END; END''',
      '''CREATE TRIGGER catalog_correction_requests_update BEFORE UPDATE ON catalog_correction_requests BEGIN
 SELECT CASE WHEN NEW.command_id<>OLD.command_id OR NEW.canonical_payload<>OLD.canonical_payload OR NEW.prepared_at_utc<>OLD.prepared_at_utc
 OR OLD.status<>'prepared' OR NEW.status NOT IN('confirmed','discarded')
 OR (NEW.status='confirmed' AND NOT EXISTS(SELECT 1 FROM catalog_corrections c JOIN catalog_items p ON p.id=c.product_id WHERE c.command_id=OLD.command_id AND p.name=json_extract(c.after_json,'\$.name') AND p.list_price_minor=json_extract(c.after_json,'\$.priceMinor')))
 OR (NEW.status='discarded' AND EXISTS(SELECT 1 FROM command_log WHERE id=OLD.command_id))
 THEN RAISE(ABORT,'Invalid correction request transition') END; END''',
      '''CREATE TRIGGER catalog_correction_proof BEFORE INSERT ON catalog_corrections BEGIN
 SELECT CASE WHEN EXISTS(SELECT 1 FROM catalog_corrections WHERE command_id=NEW.command_id)
 OR NOT EXISTS(SELECT 1 FROM catalog_correction_requests r JOIN command_log l ON l.id=r.command_id AND l.command_type='catalog_correction' JOIN catalog_items p ON p.id=NEW.product_id
 WHERE r.command_id=NEW.command_id AND r.status='prepared' AND json_extract(l.response_json,'\$.canonicalPayload')=r.canonical_payload
 AND json_extract(r.canonical_payload,'\$.input.productId')=NEW.product_id AND json_extract(r.canonical_payload,'\$.input.kind')=NEW.kind
 AND json_extract(r.canonical_payload,'\$.before')=NEW.before_json AND json_extract(r.canonical_payload,'\$.after')=NEW.after_json
 AND p.name=json_extract(NEW.before_json,'\$.name') AND p.list_price_minor=json_extract(NEW.before_json,'\$.priceMinor')
 AND (NEW.kind<>'event' OR EXISTS(SELECT 1 FROM event_current_settings s WHERE s.product_id=p.id AND s.revision=NEW.previous_revision)))
 THEN RAISE(ABORT,'Correction does not match its source or current revision') END; END''',
      '''CREATE TRIGGER event_return_values_insert BEFORE INSERT ON event_return_values BEGIN
 SELECT CASE WHEN EXISTS(SELECT 1 FROM event_return_values WHERE stock_command_id=NEW.stock_command_id)
 OR NOT EXISTS(SELECT 1 FROM catalog_correction_requests r,json_each(r.canonical_payload,'\$.stockChanges') s
 WHERE r.command_id=NEW.correction_command_id AND r.status='prepared'
 AND json_extract(s.value,'\$.commandId')=NEW.stock_command_id AND json_extract(s.value,'\$.isAddition')=1
 AND json_extract(s.value,'\$.productId')=NEW.product_id AND json_extract(s.value,'\$.quantity')=NEW.quantity
 AND json_extract(s.value,'\$.unitCost')=NEW.unit_cost_minor AND json_extract(s.value,'\$.costMinor')=NEW.cost_minor)
 THEN RAISE(ABORT,'Event return requires its exact prepared valuation') END; END''',
      '''CREATE TRIGGER event_correction_payment_posting BEFORE UPDATE OF status ON business_documents WHEN NEW.status='posted' AND NEW.type='event_correction_payment' BEGIN
 SELECT CASE WHEN OLD.status<>'draft' OR NOT EXISTS(SELECT 1 FROM event_correction_payments p JOIN catalog_correction_requests r ON r.command_id=p.correction_command_id AND r.status='prepared'
 JOIN command_log l ON l.id=r.command_id AND l.command_type='catalog_correction'
 WHERE p.document_id=NEW.id AND NEW.command_id=r.command_id AND NEW.command_sequence=0
 AND p.amount_minor=json_extract(r.canonical_payload,'\$.after.additionalFixedCost')
 AND p.product_id=json_extract(r.canonical_payload,'\$.input.productId')
 AND p.source_option_id=json_extract(r.canonical_payload,'\$.after.sourceAccountId'))
 THEN RAISE(ABORT,'Event additional cost must match its prepared correction') END; END''',
      '''CREATE TRIGGER event_correction_payment_entry BEFORE UPDATE OF status ON journal_entries WHEN NEW.status='posted' AND EXISTS(SELECT 1 FROM event_correction_payments WHERE document_id=NEW.document_id) BEGIN
 SELECT CASE WHEN (SELECT count(*) FROM journal_lines WHERE entry_id=NEW.id)<>2
 OR NOT EXISTS(SELECT 1 FROM journal_lines l JOIN event_correction_payments p ON p.document_id=NEW.document_id WHERE l.entry_id=NEW.id AND l.sequence=0 AND l.account_id='events:costs' AND l.debit_minor=p.amount_minor AND l.credit_minor=0)
 OR NOT EXISTS(SELECT 1 FROM journal_lines l JOIN event_correction_payments p ON p.document_id=NEW.document_id WHERE l.entry_id=NEW.id AND l.sequence=1 AND l.account_id=p.source_ledger_id AND l.credit_minor=p.amount_minor AND l.debit_minor=0)
 THEN RAISE(ABORT,'Event correction journal must match its exact additional cost') END; END''',
      '''CREATE TRIGGER event_correction_payment_insert BEFORE INSERT ON event_correction_payments BEGIN
 SELECT CASE WHEN EXISTS(SELECT 1 FROM event_correction_payments WHERE document_id=NEW.document_id OR correction_command_id=NEW.correction_command_id)
 OR NOT EXISTS(SELECT 1 FROM business_documents d JOIN catalog_correction_requests r ON r.command_id=NEW.correction_command_id AND r.status='prepared'
 WHERE d.id=NEW.document_id AND d.type='event_correction_payment' AND d.status='draft' AND d.command_id=r.command_id
 AND NEW.product_id=json_extract(r.canonical_payload,'\$.input.productId')
 AND NEW.amount_minor=json_extract(r.canonical_payload,'\$.after.additionalFixedCost')
 AND NEW.source_option_id=json_extract(r.canonical_payload,'\$.after.sourceAccountId')
 AND NEW.source_ledger_id=CASE WHEN NEW.source_option_id='investment' THEN 'investment:owner-payable' ELSE (SELECT ledger_account_id FROM cash_accounts WHERE id=NEW.source_option_id AND is_active=1 AND is_available=1) END)
 THEN RAISE(ABORT,'Event payment requires its exact prepared correction') END; END''',
      "CREATE TRIGGER catalog_corrections_no_replace BEFORE INSERT ON catalog_corrections WHEN EXISTS(SELECT 1 FROM catalog_corrections WHERE sequence=NEW.sequence OR command_id=NEW.command_id) BEGIN SELECT RAISE(ABORT,'Correction history is immutable'); END",
      for (final table in [
        'catalog_corrections',
        'event_return_values',
        'event_correction_payments',
      ])
        for (final action in ['UPDATE', 'DELETE'])
          "CREATE TRIGGER ${table}_no_${action.toLowerCase()} BEFORE $action ON $table BEGIN SELECT RAISE(ABORT,'Correction history is immutable'); END",
      "CREATE TRIGGER catalog_correction_requests_no_delete BEFORE DELETE ON catalog_correction_requests BEGIN SELECT RAISE(ABORT,'Correction requests are durable'); END",
      for (final table in [
        'sale_confirmations',
        'collection_requests',
        'supplier_payment_requests',
        'treasury_operation_requests',
        'quick_sale_requests',
        'paid_purchase_requests',
        'event_requests',
        'debtor_requests',
        'investment_refund_requests',
        'stock_adjustment_requests',
        'purchase_batch_requests',
      ])
        "CREATE TRIGGER ${table}_respect_catalog_correction BEFORE INSERT ON $table WHEN EXISTS(SELECT 1 FROM catalog_correction_requests WHERE command_id=NEW.command_id) BEGIN SELECT RAISE(ABORT,'Identifier reserved by a catalog correction'); END",
      "CREATE TRIGGER catalog_correction_command_reserved BEFORE INSERT ON command_log WHEN EXISTS(SELECT 1 FROM catalog_correction_requests WHERE command_id=NEW.id) AND NEW.command_type<>'catalog_correction' BEGIN SELECT RAISE(ABORT,'Identifier reserved by a catalog correction'); END",
    ]);
    final posting = stock.singleWhere(
      (s) => s.startsWith('CREATE TRIGGER stock_addition_posting '),
    );
    result.addAll([
      'DROP TRIGGER stock_addition_posting',
      posting.replaceFirst(
        'AND ref.unit_cost_minor=a.unit_cost_minor',
        "AND (ref.unit_cost_minor=a.unit_cost_minor OR EXISTS(SELECT 1 FROM event_return_values v WHERE v.stock_command_id=NEW.command_id AND v.product_id=a.product_id AND v.quantity=a.quantity AND v.unit_cost_minor=a.unit_cost_minor AND v.cost_minor=a.cost_minor))",
      ),
    ]);
    return result;
  }
}
