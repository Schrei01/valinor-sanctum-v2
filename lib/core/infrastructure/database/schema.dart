import 'dart:convert';
import 'event_schema.dart';
import 'debtor_schema.dart';
import 'legacy_conversion_schema.dart';
import 'total_purchase_schema.dart';
import 'catalog_operations_schema.dart';
part 'split_payment_schema.dart';

/// Immutable bootstrap schema. Later changes require a new schema version.
abstract final class DatabaseSchema {
  static const int version = 18;

  // ASCII VS20: a file-format marker, independent of the original POS.
  static const int applicationId = 0x56533230;
  static const String migrationName = 'foundation_v1';

  /// Detects accidental changes; this checksum is not a security signature.
  static String get migrationChecksum => checksum(statements.join('\n;\n'));

  static const String migration2Name = 'catalog_credit_receipts_v2';
  static String get migration2Checksum =>
      checksum(migration2Statements.join('\n;\n'));

  static const String migration3Name = 'open_tabs_credit_sales_fifo_v3';
  static String get migration3Checksum =>
      checksum(migration3Statements.join('\n;\n'));

  static const String migration4Name = 'customer_collections_v4';
  static String get migration4Checksum =>
      checksum(migration4Statements.join('\n;\n'));

  static const String migration5Name = 'supplier_payments_v5';
  static String get migration5Checksum =>
      checksum(migration5Statements.join('\n;\n'));

  static const String migration6Name = 'quick_counter_sales_v6';
  static String get migration6Checksum =>
      checksum(migration6Statements.join('\n;\n'));

  static const String migration7Name =
      'paid_stock_intakes_and_cash_openings_v7';
  static String get migration7Checksum =>
      checksum(migration7Statements.join('\n;\n'));

  static const String migration8Name = 'initial_inventory_opening_v8';
  static String get migration8Checksum =>
      checksum(migration8Statements.join('\n;\n'));

  static const String migration9Name = 'initial_treasury_opening_v9';
  static String get migration9Checksum =>
      checksum(migration9Statements.join('\n;\n'));

  static const String migration10Name = 'treasury_operations_v10';
  static String get migration10Checksum =>
      checksum(migration10Statements.join('\n;\n'));

  static const String migration11Name = 'quick_sales_customer_credit_v11';
  static String get migration11Checksum =>
      checksum(migration11Statements.join('\n;\n'));

  static String nameForVersion(int version) => switch (version) {
    1 => migrationName,
    2 => migration2Name,
    3 => migration3Name,
    4 => migration4Name,
    5 => migration5Name,
    6 => migration6Name,
    7 => migration7Name,
    8 => migration8Name,
    9 => migration9Name,
    10 => migration10Name,
    11 => migration11Name,
    12 => 'events_and_service_sales_v12',
    13 => 'registered_debtors_and_person_payments_v13',
    14 => 'converted_legacy_history_v14',
    15 => 'total_purchase_cost_and_retail_price_history_v15',
    16 => 'catalog_stock_adjustments_and_day_pass_v16',
    17 => 'split_line_payments_v17',
    18 => 'account_payment_mode_and_review_v18',
    _ => throw ArgumentError.value(version, 'version'),
  };

  static String checksumForVersion(int version) => switch (version) {
    1 => migrationChecksum,
    2 => migration2Checksum,
    3 => migration3Checksum,
    4 => migration4Checksum,
    5 => migration5Checksum,
    6 => migration6Checksum,
    7 => migration7Checksum,
    8 => migration8Checksum,
    9 => migration9Checksum,
    10 => migration10Checksum,
    11 => migration11Checksum,
    12 => checksum(migration12Statements.join('\n;\n')),
    13 => checksum(migration13Statements.join('\n;\n')),
    14 => checksum(migration14Statements.join('\n;\n')),
    15 => checksum(migration15Statements.join('\n;\n')),
    16 => checksum(migration16Statements.join('\n;\n')),
    17 => checksum(migration17Statements.join('\n;\n')),
    18 => checksum(migration18Statements.join('\n;\n')),
    _ => throw ArgumentError.value(version, 'version'),
  };

  static final List<String> migration14Statements = List.unmodifiable(
    LegacyConversionSchema.statements,
  );
  static final List<String> migration17Statements = List.unmodifiable(
    SplitPaymentSchema.build(),
  );
  static final List<String> migration18Statements = List.unmodifiable([
    "ALTER TABLE quick_sales_accounts ADD COLUMN payment_mode TEXT NOT NULL DEFAULT 'legacy' CHECK(payment_mode IN('legacy','single','split'))",
    "ALTER TABLE quick_sales_accounts ADD COLUMN account_payment_option_id TEXT CHECK(account_payment_option_id IS NULL OR length(trim(account_payment_option_id)) BETWEEN 1 AND 160)",
    "ALTER TABLE quick_sales_accounts ADD COLUMN payment_split_basis TEXT NOT NULL DEFAULT '' CHECK(payment_split_basis='' OR (json_valid(payment_split_basis) AND json_type(payment_split_basis)='array'))",
    '''CREATE TRIGGER account_payment_settings_locked
BEFORE UPDATE OF payment_mode,account_payment_option_id,payment_split_basis ON quick_sales_accounts
WHEN (NEW.payment_mode IS NOT OLD.payment_mode OR NEW.account_payment_option_id IS NOT OLD.account_payment_option_id OR NEW.payment_split_basis IS NOT OLD.payment_split_basis)
 AND (OLD.status<>'open' OR NEW.status<>'open' OR EXISTS(SELECT 1 FROM quick_sale_requests WHERE account_id=OLD.id AND status<>'cancelled'))
BEGIN SELECT RAISE(ABORT,'Prepared account payment settings are immutable'); END''',
    '''CREATE TRIGGER account_payment_prepare_guard BEFORE INSERT ON quick_sale_requests BEGIN
SELECT CASE WHEN EXISTS(SELECT 1 FROM quick_sales_accounts a WHERE a.id=NEW.account_id AND (
 (a.payment_mode='single' AND (a.account_payment_option_id IS NULL OR EXISTS(
   SELECT 1 FROM quick_sales_lines s WHERE s.account_id=a.id AND (
    json_array_length(s.payment_split_json)>0 OR s.is_credit<>(a.account_payment_option_id='quick-debt')
    OR (s.is_credit=0 AND s.payment_option_id IS NOT a.account_payment_option_id)))))
 OR (a.payment_mode='split' AND NOT (CASE WHEN json_valid(a.payment_split_basis) THEN
  json_type(a.payment_split_basis)='array' AND json_array_length(a.payment_split_basis)=(SELECT count(*) FROM quick_sales_lines WHERE account_id=a.id)
  AND NOT EXISTS(SELECT 1 FROM quick_sales_lines s WHERE s.account_id=a.id AND NOT EXISTS(
    SELECT 1 FROM json_each(a.payment_split_basis) b WHERE b.key=s.sequence
    AND json_extract(b.value,'\$[0]') IS s.id AND json_extract(b.value,'\$[1]') IS s.product_id
    AND json_extract(b.value,'\$[2]') IS s.quantity_text AND json_extract(b.value,'\$[3]') IS s.unit_price_minor))
  ELSE 0 END))))
THEN RAISE(ABORT,'Choose an account payment or review the division after consumption changes') END; END''',
  ]);
  static final List<String> migration16Statements = List.unmodifiable(
    CatalogOperationsSchema.build(
      releasedEvents: migration12Statements,
      utcKey: _utcSortKey,
    ),
  );
  static final List<String> migration15Statements = List.unmodifiable(
    TotalPurchaseSchema.build(
      released: migration7Statements,
      entryMatches: _paidPurchaseEntryMatches,
    ),
  );

  static final List<String> migration12Statements = List.unmodifiable(
    EventSchema.build(
      salePosting: _openingAwareSalePostingTrigger(),
      purchaseAllocation: _openingAwarePurchaseAllocationTrigger(),
      openingAllocation: migration8Statements.singleWhere(
        (s) => s.startsWith(
          'CREATE TRIGGER inventory_opening_allocations_validate_insert\n',
        ),
      ),
      entryPosting: migration9Statements
          .where(
            (s) => s.startsWith('CREATE TRIGGER entries_validate_posting\n'),
          )
          .last,
      fundsInvalid: _treasuryOperationMoneyInvalid('NEW.id'),
      freezeJournal: _freezeTreasuryOperationJournal(),
      utcKey: _utcSortKey,
    ),
  );

  static final List<String> migration13Statements = List.unmodifiable(
    DebtorSchema.build(
      creditTriggers: migration11Statements
          .where(
            (s) =>
                s.startsWith(
                  'CREATE TRIGGER quick_credit_requests_validate_insert\n',
                ) ||
                s.startsWith(
                  'CREATE TRIGGER quick_sale_requests_validate_update\n',
                ) ||
                s.startsWith(
                  'CREATE TRIGGER quick_line_tenders_validate_insert\n',
                ) ||
                s.startsWith(
                  'CREATE TRIGGER quick_legacy_payments_reject_credit\n',
                ),
          )
          .toList(),
      collectionPosting: migration4Statements.singleWhere(
        (s) => s.startsWith(
          'CREATE TRIGGER collections_validate_document_posting\n',
        ),
      ),
      journalFreeze: _freezeTreasuryOperationJournal(),
      utcKey: _utcSortKey,
    ),
  );

  static String checksum(String input) {
    var hash = BigInt.parse('cbf29ce484222325', radix: 16);
    final prime = BigInt.parse('100000001b3', radix: 16);
    final mask = (BigInt.one << 64) - BigInt.one;
    for (final byte in utf8.encode(input)) {
      hash = ((hash ^ BigInt.from(byte)) * prime) & mask;
    }
    return 'fnv1a64:${hash.toRadixString(16).padLeft(16, '0')}';
  }

  static const List<String> statements = <String>[
    '''
CREATE TABLE schema_migrations (
  version INTEGER PRIMARY KEY CHECK (typeof(version) = 'integer' AND version > 0),
  name TEXT NOT NULL UNIQUE CHECK (length(trim(name)) > 0),
  migration_checksum TEXT NOT NULL CHECK (length(migration_checksum) > 0),
  schema_checksum TEXT NOT NULL CHECK (length(schema_checksum) > 0),
  applied_at_utc TEXT NOT NULL CHECK (length(applied_at_utc) > 0)
)
''',
    '''
CREATE TABLE actors (
  id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(id)) > 0),
  display_name TEXT NOT NULL CHECK (length(trim(display_name)) > 0),
  kind TEXT NOT NULL CHECK (kind IN ('person', 'synthetic', 'system')),
  is_active INTEGER NOT NULL CHECK (typeof(is_active) = 'integer' AND is_active IN (0, 1)),
  created_at_utc TEXT NOT NULL CHECK (length(created_at_utc) > 0)
)
''',
    '''
CREATE TABLE app_profile (
  id INTEGER PRIMARY KEY CHECK (typeof(id) = 'integer' AND id = 1),
  profile_id TEXT NOT NULL UNIQUE CHECK (length(trim(profile_id)) > 0),
  business_name TEXT NOT NULL CHECK (length(trim(business_name)) > 0),
  currency_code TEXT NOT NULL CHECK (currency_code GLOB '[A-Z][A-Z][A-Z]'),
  money_scale INTEGER NOT NULL CHECK (typeof(money_scale) = 'integer' AND money_scale BETWEEN 0 AND 6),
  business_timezone TEXT NOT NULL CHECK (length(trim(business_timezone)) > 0),
  created_at_utc TEXT NOT NULL CHECK (length(created_at_utc) > 0)
)
''',
    '''
CREATE TABLE command_log (
  id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(id)) > 0),
  command_type TEXT NOT NULL CHECK (length(trim(command_type)) > 0),
  payload_hash TEXT NOT NULL CHECK (length(trim(payload_hash)) > 0),
  actor_id TEXT NOT NULL REFERENCES actors(id) ON DELETE RESTRICT,
  response_json TEXT NOT NULL CHECK (length(trim(response_json)) > 0),
  response_version INTEGER NOT NULL CHECK (typeof(response_version) = 'integer' AND response_version > 0),
  committed_at_utc TEXT NOT NULL CHECK (length(committed_at_utc) > 0)
)
''',
    '''
CREATE TABLE business_documents (
  id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(id)) > 0),
  command_id TEXT NOT NULL REFERENCES command_log(id) ON DELETE RESTRICT,
  command_sequence INTEGER NOT NULL CHECK (typeof(command_sequence) = 'integer' AND command_sequence >= 0),
  profile_id TEXT NOT NULL REFERENCES app_profile(profile_id) ON DELETE RESTRICT,
  actor_id TEXT NOT NULL REFERENCES actors(id) ON DELETE RESTRICT,
  type TEXT NOT NULL CHECK (length(trim(type)) > 0),
  status TEXT NOT NULL CHECK (status IN ('draft', 'posted', 'reversed')),
  occurred_at_utc TEXT,
  business_date TEXT,
  recorded_at_utc TEXT NOT NULL CHECK (length(recorded_at_utc) > 0),
  original_document_id TEXT REFERENCES business_documents(id) ON DELETE RESTRICT,
  reason TEXT,
  source_kind TEXT NOT NULL CHECK (source_kind IN ('native', 'legacy', 'synthetic')),
  date_quality TEXT NOT NULL CHECK (date_quality IN ('documented', 'reconstructed', 'unknown')),
  CHECK (status = 'draft' OR (occurred_at_utc IS NOT NULL AND business_date IS NOT NULL)),
  CHECK (original_document_id IS NULL OR original_document_id <> id),
  UNIQUE (command_id, command_sequence)
)
''',
    '''
CREATE TABLE ledger_accounts (
  id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(id)) > 0),
  code TEXT NOT NULL UNIQUE CHECK (length(trim(code)) > 0),
  name TEXT NOT NULL CHECK (length(trim(name)) > 0),
  class TEXT NOT NULL CHECK (class IN ('asset', 'liability', 'equity', 'revenue', 'cost', 'expense')),
  role TEXT NOT NULL CHECK (length(trim(role)) > 0),
  is_active INTEGER NOT NULL CHECK (typeof(is_active) = 'integer' AND is_active IN (0, 1))
)
''',
    '''
CREATE TABLE journal_entries (
  id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(id)) > 0),
  document_id TEXT NOT NULL UNIQUE REFERENCES business_documents(id) ON DELETE RESTRICT,
  status TEXT NOT NULL CHECK (status IN ('draft', 'posted')),
  posted_at_utc TEXT,
  reversal_of_id TEXT REFERENCES journal_entries(id) ON DELETE RESTRICT,
  cost_completeness TEXT NOT NULL CHECK (cost_completeness IN ('complete', 'partial', 'unknown', 'not_applicable')),
  CHECK (status = 'draft' OR posted_at_utc IS NOT NULL),
  CHECK (reversal_of_id IS NULL OR reversal_of_id <> id)
)
''',
    '''
CREATE TABLE journal_lines (
  id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(id)) > 0),
  entry_id TEXT NOT NULL REFERENCES journal_entries(id) ON DELETE RESTRICT,
  sequence INTEGER NOT NULL CHECK (typeof(sequence) = 'integer' AND sequence >= 0),
  account_id TEXT NOT NULL REFERENCES ledger_accounts(id) ON DELETE RESTRICT,
  debit_minor INTEGER NOT NULL CHECK (typeof(debit_minor) = 'integer' AND debit_minor >= 0),
  credit_minor INTEGER NOT NULL CHECK (typeof(credit_minor) = 'integer' AND credit_minor >= 0),
  CHECK ((debit_minor > 0 AND credit_minor = 0) OR (credit_minor > 0 AND debit_minor = 0)),
  UNIQUE (entry_id, sequence)
)
''',
    '''
CREATE TABLE cash_accounts (
  id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(id)) > 0),
  ledger_account_id TEXT NOT NULL UNIQUE REFERENCES ledger_accounts(id) ON DELETE RESTRICT,
  name TEXT NOT NULL CHECK (length(trim(name)) > 0),
  kind TEXT NOT NULL CHECK (kind IN ('cash', 'bank', 'mobile', 'clearing')),
  is_available INTEGER NOT NULL CHECK (typeof(is_available) = 'integer' AND is_available IN (0, 1)),
  is_active INTEGER NOT NULL CHECK (typeof(is_active) = 'integer' AND is_active IN (0, 1))
)
''',
    '''
CREATE TABLE payment_methods (
  id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(id)) > 0),
  code TEXT NOT NULL UNIQUE CHECK (length(trim(code)) > 0),
  name TEXT NOT NULL CHECK (length(trim(name)) > 0),
  is_active INTEGER NOT NULL CHECK (typeof(is_active) = 'integer' AND is_active IN (0, 1))
)
''',
    'CREATE INDEX idx_documents_actor ON business_documents(actor_id)',
    'CREATE INDEX idx_documents_date ON business_documents(business_date)',
    'CREATE INDEX idx_documents_original ON business_documents(original_document_id)',
    'CREATE INDEX idx_entries_reversal ON journal_entries(reversal_of_id)',
    'CREATE INDEX idx_lines_account ON journal_lines(account_id)',
    '''
CREATE TRIGGER profile_currency_immutable_after_posting
BEFORE UPDATE OF profile_id, currency_code, money_scale ON app_profile
WHEN EXISTS (SELECT 1 FROM business_documents WHERE status <> 'draft')
BEGIN
  SELECT RAISE(ABORT, 'Cannot change monetary profile after posting');
END
''',
    '''
CREATE TRIGGER documents_confirmed_no_update
BEFORE UPDATE ON business_documents
WHEN OLD.status <> 'draft'
BEGIN
  SELECT RAISE(ABORT, 'Confirmed documents are immutable; create a correction');
END
''',
    '''
CREATE TRIGGER documents_confirmed_no_delete
BEFORE DELETE ON business_documents
WHEN OLD.status <> 'draft'
BEGIN
  SELECT RAISE(ABORT, 'Confirmed documents cannot be deleted');
END
''',
    '''
CREATE TRIGGER entries_insert_as_draft
BEFORE INSERT ON journal_entries
WHEN NEW.status <> 'draft'
BEGIN
  SELECT RAISE(ABORT, 'Create an entry as draft before posting');
END
''',
    '''
CREATE TRIGGER entries_validate_posting
BEFORE UPDATE OF status ON journal_entries
WHEN OLD.status = 'draft' AND NEW.status = 'posted'
BEGIN
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM business_documents
    WHERE id = NEW.document_id AND status = 'posted'
  ) THEN RAISE(ABORT, 'Post the source document before its entry') END;
  SELECT CASE WHEN (
    SELECT count(*) FROM journal_lines WHERE entry_id = NEW.id
  ) < 2 THEN RAISE(ABORT, 'A posted entry needs at least two lines') END;
  SELECT CASE WHEN (
    SELECT sum(debit_minor) <> sum(credit_minor)
    FROM journal_lines WHERE entry_id = NEW.id
  ) THEN RAISE(ABORT, 'A posted entry must balance') END;
END
''',
    '''
CREATE TRIGGER entries_posted_no_update
BEFORE UPDATE ON journal_entries
WHEN OLD.status = 'posted'
BEGIN
  SELECT RAISE(ABORT, 'Posted entries are immutable; create a reversal');
END
''',
    '''
CREATE TRIGGER entries_posted_no_delete
BEFORE DELETE ON journal_entries
WHEN OLD.status = 'posted'
BEGIN
  SELECT RAISE(ABORT, 'Posted entries cannot be deleted');
END
''',
    '''
CREATE TRIGGER lines_posted_no_insert
BEFORE INSERT ON journal_lines
WHEN EXISTS (SELECT 1 FROM journal_entries WHERE id = NEW.entry_id AND status = 'posted')
BEGIN
  SELECT RAISE(ABORT, 'Posted entry lines are immutable');
END
''',
    '''
CREATE TRIGGER lines_posted_no_update
BEFORE UPDATE ON journal_lines
WHEN EXISTS (
  SELECT 1 FROM journal_entries
  WHERE id IN (OLD.entry_id, NEW.entry_id) AND status = 'posted'
)
BEGIN
  SELECT RAISE(ABORT, 'Posted entry lines are immutable');
END
''',
    '''
CREATE TRIGGER lines_posted_no_delete
BEFORE DELETE ON journal_lines
WHEN EXISTS (SELECT 1 FROM journal_entries WHERE id = OLD.entry_id AND status = 'posted')
BEGIN
  SELECT RAISE(ABORT, 'Posted entry lines are immutable');
END
''',
    '''
CREATE TRIGGER command_log_no_update
BEFORE UPDATE ON command_log
BEGIN
  SELECT RAISE(ABORT, 'Committed command results are immutable');
END
''',
    '''
CREATE TRIGGER command_log_no_delete
BEFORE DELETE ON command_log
BEGIN
  SELECT RAISE(ABORT, 'Committed command results cannot be deleted');
END
''',
  ];

  /// V1 above is a permanent historical input. Append migrations separately.
  static final List<String> migration2Statements = List<String>.unmodifiable([
    '''
ALTER TABLE command_log ADD COLUMN authorization_policy_version TEXT NOT NULL
DEFAULT 'foundation-v1' CHECK (length(trim(authorization_policy_version)) > 0)
''',
    '''
CREATE TABLE categories (
  id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(id)) > 0),
  name TEXT NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 160),
  is_active INTEGER NOT NULL CHECK (typeof(is_active) = 'integer' AND is_active IN (0, 1))
)
''',
    '''
CREATE TABLE counterparties (
  id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(id)) > 0),
  name TEXT NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 160),
  is_customer INTEGER NOT NULL DEFAULT 0 CHECK (typeof(is_customer) = 'integer' AND is_customer = 0),
  is_supplier INTEGER NOT NULL DEFAULT 1 CHECK (typeof(is_supplier) = 'integer' AND is_supplier = 1),
  is_active INTEGER NOT NULL CHECK (typeof(is_active) = 'integer' AND is_active IN (0, 1))
)
''',
    '''
CREATE TABLE catalog_items (
  id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(id)) > 0),
  sku TEXT COLLATE NOCASE UNIQUE CHECK (sku IS NULL OR length(trim(sku)) BETWEEN 1 AND 80),
  name TEXT NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 160),
  kind TEXT NOT NULL CHECK (kind = 'product'),
  category_id TEXT REFERENCES categories(id) ON DELETE RESTRICT,
  unit_code TEXT NOT NULL CHECK (unit_code = 'unit'),
  quantity_scale INTEGER NOT NULL CHECK (typeof(quantity_scale) = 'integer' AND quantity_scale = 0),
  list_price_minor INTEGER NOT NULL CHECK (typeof(list_price_minor) = 'integer' AND list_price_minor >= 0),
  is_active INTEGER NOT NULL CHECK (typeof(is_active) = 'integer' AND is_active IN (0, 1))
)
''',
    '''
CREATE TABLE purchases (
  document_id TEXT PRIMARY KEY NOT NULL REFERENCES business_documents(id) ON DELETE RESTRICT,
  supplier_id TEXT NOT NULL REFERENCES counterparties(id) ON DELETE RESTRICT,
  supplier_name_snapshot TEXT NOT NULL CHECK (length(trim(supplier_name_snapshot)) BETWEEN 1 AND 160),
  supplier_reference TEXT CHECK (supplier_reference IS NULL OR length(trim(supplier_reference)) BETWEEN 1 AND 160),
  received_at_utc TEXT NOT NULL CHECK (length(received_at_utc) > 0),
  due_date TEXT NOT NULL CHECK (length(due_date) = 10),
  payable_minor INTEGER NOT NULL CHECK (typeof(payable_minor) = 'integer' AND payable_minor > 0),
  terms TEXT NOT NULL CHECK (terms = 'credit')
)
''',
    '''
CREATE TABLE purchase_lines (
  id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(id)) > 0),
  purchase_id TEXT NOT NULL REFERENCES purchases(document_id) ON DELETE RESTRICT,
  sequence INTEGER NOT NULL CHECK (typeof(sequence) = 'integer' AND sequence >= 0),
  product_id TEXT NOT NULL REFERENCES catalog_items(id) ON DELETE RESTRICT,
  name_snapshot TEXT NOT NULL CHECK (length(trim(name_snapshot)) BETWEEN 1 AND 160),
  quantity INTEGER NOT NULL CHECK (typeof(quantity) = 'integer' AND quantity > 0),
  acquisition_total_minor INTEGER NOT NULL CHECK (typeof(acquisition_total_minor) = 'integer' AND acquisition_total_minor >= 0),
  cost_quality TEXT NOT NULL CHECK (cost_quality = 'documented'),
  UNIQUE (purchase_id, sequence),
  UNIQUE (purchase_id, product_id)
)
''',
    '''
CREATE TABLE inventory_movements (
  id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(id)) > 0),
  document_id TEXT NOT NULL REFERENCES business_documents(id) ON DELETE RESTRICT,
  sequence INTEGER NOT NULL CHECK (typeof(sequence) = 'integer' AND sequence >= 0),
  stock_sequence INTEGER NOT NULL UNIQUE CHECK (typeof(stock_sequence) = 'integer' AND stock_sequence > 0),
  product_id TEXT NOT NULL REFERENCES catalog_items(id) ON DELETE RESTRICT,
  kind TEXT NOT NULL CHECK (kind = 'purchase'),
  quantity_delta INTEGER NOT NULL CHECK (typeof(quantity_delta) = 'integer' AND quantity_delta > 0),
  value_delta_minor INTEGER NOT NULL CHECK (typeof(value_delta_minor) = 'integer' AND value_delta_minor >= 0),
  purchase_line_id TEXT NOT NULL UNIQUE REFERENCES purchase_lines(id) ON DELETE RESTRICT,
  UNIQUE (document_id, sequence)
)
''',
    '''
CREATE TABLE cost_layers (
  id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(id)) > 0),
  inbound_movement_id TEXT NOT NULL UNIQUE REFERENCES inventory_movements(id) ON DELETE RESTRICT,
  product_id TEXT NOT NULL REFERENCES catalog_items(id) ON DELETE RESTRICT,
  initial_quantity INTEGER NOT NULL CHECK (typeof(initial_quantity) = 'integer' AND initial_quantity > 0),
  total_cost_minor INTEGER NOT NULL CHECK (typeof(total_cost_minor) = 'integer' AND total_cost_minor >= 0),
  cost_quality TEXT NOT NULL CHECK (cost_quality = 'documented'),
  fifo_sequence INTEGER NOT NULL UNIQUE CHECK (typeof(fifo_sequence) = 'integer' AND fifo_sequence > 0),
  acquired_at_utc TEXT NOT NULL CHECK (length(acquired_at_utc) > 0)
)
''',
    '''
CREATE TABLE obligations (
  id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(id)) > 0),
  origin_document_id TEXT NOT NULL REFERENCES business_documents(id) ON DELETE RESTRICT,
  sequence INTEGER NOT NULL CHECK (typeof(sequence) = 'integer' AND sequence >= 0),
  counterparty_id TEXT NOT NULL REFERENCES counterparties(id) ON DELETE RESTRICT,
  kind TEXT NOT NULL CHECK (kind = 'supplier_payable'),
  control_account_id TEXT NOT NULL REFERENCES ledger_accounts(id) ON DELETE RESTRICT,
  initial_minor INTEGER NOT NULL CHECK (typeof(initial_minor) = 'integer' AND initial_minor > 0),
  issued_at_utc TEXT NOT NULL CHECK (length(issued_at_utc) > 0),
  due_date TEXT NOT NULL CHECK (length(due_date) = 10),
  UNIQUE (origin_document_id, sequence)
)
''',
    'CREATE INDEX idx_catalog_category ON catalog_items(category_id)',
    'CREATE INDEX idx_purchases_supplier ON purchases(supplier_id)',
    'CREATE INDEX idx_movements_product ON inventory_movements(product_id, stock_sequence)',
    'CREATE INDEX idx_layers_product ON cost_layers(product_id, fifo_sequence)',
    'CREATE INDEX idx_obligations_counterparty ON obligations(counterparty_id)',
    '''
CREATE TRIGGER purchases_documents_insert_as_draft
BEFORE INSERT ON business_documents
WHEN NEW.type = 'purchase_receipt' AND NEW.status <> 'draft'
BEGIN
  SELECT RAISE(ABORT, 'Create a purchase document as draft before posting');
END
''',
    '''
CREATE TRIGGER purchases_require_receipt_document
BEFORE INSERT ON purchases
WHEN NOT EXISTS (SELECT 1 FROM business_documents WHERE id = NEW.document_id
  AND type = 'purchase_receipt' AND status = 'draft')
BEGIN
  SELECT RAISE(ABORT, 'A purchase requires a draft receipt document');
END
''',
    '''
CREATE TRIGGER purchases_validate_document_posting
BEFORE UPDATE OF status ON business_documents
WHEN OLD.status = 'draft' AND NEW.status = 'posted' AND
  (NEW.type = 'purchase_receipt' OR EXISTS (SELECT 1 FROM purchases WHERE document_id = NEW.id))
BEGIN
  SELECT CASE WHEN NEW.type <> 'purchase_receipt' OR NEW.command_sequence <> 0
    OR NOT EXISTS (SELECT 1 FROM command_log c WHERE c.id = NEW.command_id
      AND c.command_type = 'receive_purchase'
      AND c.actor_id = NEW.actor_id
      AND c.authorization_policy_version = 'development-single-user-v1')
    THEN RAISE(ABORT, 'Invalid purchase command or document type') END;
  SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM purchases p
    JOIN counterparties s ON s.id = p.supplier_id
    WHERE p.document_id = NEW.id AND s.is_active = 1 AND s.is_supplier = 1
      AND p.supplier_name_snapshot = s.name AND p.received_at_utc = NEW.occurred_at_utc
      AND p.due_date >= NEW.business_date AND date(p.due_date) = p.due_date
      AND date(NEW.occurred_at_utc, '-5 hours') = NEW.business_date)
    THEN RAISE(ABORT, 'Purchase header or supplier is invalid') END;
  SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM purchase_lines WHERE purchase_id = NEW.id)
    OR EXISTS (SELECT 1 FROM purchase_lines l JOIN catalog_items c ON c.id = l.product_id
      LEFT JOIN categories k ON k.id = c.category_id
      WHERE l.purchase_id = NEW.id AND (c.is_active <> 1 OR l.name_snapshot <> c.name
        OR (c.category_id IS NOT NULL AND k.is_active <> 1)))
    THEN RAISE(ABORT, 'Purchase lines need active products and categories') END;
  SELECT CASE WHEN (SELECT sum(acquisition_total_minor) FROM purchase_lines WHERE purchase_id = NEW.id)
    <> (SELECT payable_minor FROM purchases WHERE document_id = NEW.id)
    THEN RAISE(ABORT, 'Purchase total must equal its documented line costs') END;
  SELECT CASE WHEN (SELECT count(*) FROM inventory_movements WHERE document_id = NEW.id)
    <> (SELECT count(*) FROM purchase_lines WHERE purchase_id = NEW.id)
    OR EXISTS (SELECT 1 FROM purchase_lines l WHERE l.purchase_id = NEW.id AND NOT EXISTS (
      SELECT 1 FROM inventory_movements m JOIN cost_layers c ON c.inbound_movement_id = m.id
      WHERE m.purchase_line_id = l.id AND m.document_id = NEW.id AND m.sequence = l.sequence
        AND m.product_id = l.product_id AND m.quantity_delta = l.quantity
        AND m.value_delta_minor = l.acquisition_total_minor AND c.product_id = l.product_id
        AND c.initial_quantity = l.quantity AND c.total_cost_minor = l.acquisition_total_minor
        AND c.fifo_sequence = m.stock_sequence AND c.acquired_at_utc = NEW.occurred_at_utc))
    THEN RAISE(ABORT, 'Purchase movements and cost layers must match every line') END;
  SELECT CASE WHEN (SELECT count(*) FROM obligations WHERE origin_document_id = NEW.id) <> 1
    OR NOT EXISTS (SELECT 1 FROM obligations o JOIN purchases p ON p.document_id = o.origin_document_id
      JOIN ledger_accounts a ON a.id = o.control_account_id
      WHERE o.origin_document_id = NEW.id AND o.sequence = 0 AND o.counterparty_id = p.supplier_id
        AND o.initial_minor = p.payable_minor AND o.due_date = p.due_date
        AND o.issued_at_utc = p.received_at_utc AND a.role = 'supplier_payable'
        AND a.class = 'liability' AND a.is_active = 1)
    THEN RAISE(ABORT, 'A credit purchase requires its matching supplier obligation') END;
  SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM journal_entries e
    WHERE e.document_id = NEW.id AND e.status = 'draft' AND e.cost_completeness = 'complete')
    THEN RAISE(ABORT, 'Prepare the purchase journal before posting its document') END;
  SELECT CASE WHEN (SELECT count(*) FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id
    WHERE e.document_id = NEW.id) <> 2
    OR NOT EXISTS (SELECT 1 FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id
      JOIN ledger_accounts a ON a.id = l.account_id JOIN purchases p ON p.document_id = e.document_id
      WHERE e.document_id = NEW.id AND a.class = 'asset' AND a.role = 'inventory'
        AND a.is_active = 1 AND l.debit_minor = p.payable_minor AND l.credit_minor = 0)
    OR NOT EXISTS (SELECT 1 FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id
      JOIN obligations o ON o.origin_document_id = e.document_id
      WHERE e.document_id = NEW.id AND l.account_id = o.control_account_id
        AND l.credit_minor = o.initial_minor AND l.debit_minor = 0)
    THEN RAISE(ABORT, 'A purchase debits inventory and credits its supplier payable') END;
END
''',
    '''
CREATE TRIGGER documents_confirmed_no_replace
BEFORE INSERT ON business_documents
WHEN EXISTS (SELECT 1 FROM business_documents WHERE status <> 'draft'
  AND (id = NEW.id OR (command_id = NEW.command_id AND command_sequence = NEW.command_sequence)))
BEGIN
  SELECT RAISE(ABORT, 'Confirmed documents cannot be replaced');
END
''',
    '''
CREATE TRIGGER documents_confirmed_no_conflicting_update
BEFORE UPDATE ON business_documents
WHEN EXISTS (SELECT 1 FROM business_documents WHERE status <> 'draft'
  AND (id = NEW.id OR (command_id = NEW.command_id AND command_sequence = NEW.command_sequence)))
BEGIN
  SELECT RAISE(ABORT, 'Confirmed documents cannot be replaced through an update');
END
''',
    '''
CREATE TRIGGER command_log_no_replace
BEFORE INSERT ON command_log
WHEN EXISTS (SELECT 1 FROM command_log WHERE id = NEW.id)
BEGIN
  SELECT RAISE(ABORT, 'Committed command results cannot be replaced');
END
''',
    '''
CREATE TRIGGER entries_confirmed_no_replace
BEFORE INSERT ON journal_entries
WHEN EXISTS (SELECT 1 FROM journal_entries e
  JOIN business_documents d ON d.id = e.document_id
  WHERE (e.id = NEW.id OR e.document_id = NEW.document_id)
    AND (e.status = 'posted' OR (d.type = 'purchase_receipt' AND d.status <> 'draft')))
BEGIN
  SELECT RAISE(ABORT, 'Confirmed journal entries cannot be replaced');
END
''',
    '''
CREATE TRIGGER entries_confirmed_no_conflicting_update
BEFORE UPDATE ON journal_entries
WHEN EXISTS (SELECT 1 FROM journal_entries e
  JOIN business_documents d ON d.id = e.document_id
  WHERE e.id <> OLD.id AND (e.id = NEW.id OR e.document_id = NEW.document_id)
    AND (e.status = 'posted' OR (d.type = 'purchase_receipt' AND d.status <> 'draft')))
BEGIN
  SELECT RAISE(ABORT, 'Confirmed journal entries cannot be replaced through an update');
END
''',
    '''
CREATE TRIGGER purchase_entries_confirmed_no_delete
BEFORE DELETE ON journal_entries
WHEN EXISTS (SELECT 1 FROM business_documents d
  WHERE d.id = OLD.document_id AND d.type = 'purchase_receipt' AND d.status <> 'draft')
BEGIN
  SELECT RAISE(ABORT, 'A confirmed purchase requires its journal entry');
END
''',
    '''
CREATE TRIGGER purchase_entries_confirmed_no_rewrite
BEFORE UPDATE ON journal_entries
WHEN EXISTS (SELECT 1 FROM business_documents d
  WHERE d.id = OLD.document_id AND d.type = 'purchase_receipt' AND d.status <> 'draft')
  AND (NEW.id <> OLD.id OR NEW.document_id <> OLD.document_id
    OR NEW.cost_completeness <> OLD.cost_completeness
    OR NEW.reversal_of_id IS NOT OLD.reversal_of_id OR NEW.status <> 'posted')
BEGIN
  SELECT RAISE(ABORT, 'Only posting is allowed on a confirmed purchase journal');
END
''',
    '''
CREATE TRIGGER journal_lines_confirmed_no_replace
BEFORE INSERT ON journal_lines
WHEN EXISTS (SELECT 1 FROM journal_lines l
  JOIN journal_entries e ON e.id = l.entry_id
  JOIN business_documents d ON d.id = e.document_id
  WHERE (l.id = NEW.id OR (l.entry_id = NEW.entry_id AND l.sequence = NEW.sequence))
    AND (e.status = 'posted' OR (d.type = 'purchase_receipt' AND d.status <> 'draft')))
BEGIN
  SELECT RAISE(ABORT, 'Confirmed journal lines cannot be replaced');
END
''',
    '''
CREATE TRIGGER journal_lines_confirmed_no_conflicting_update
BEFORE UPDATE ON journal_lines
WHEN EXISTS (SELECT 1 FROM journal_lines l
  JOIN journal_entries e ON e.id = l.entry_id
  JOIN business_documents d ON d.id = e.document_id
  WHERE (l.id = NEW.id OR (l.entry_id = NEW.entry_id AND l.sequence = NEW.sequence))
    AND (e.status = 'posted' OR (d.type = 'purchase_receipt' AND d.status <> 'draft')))
BEGIN
  SELECT RAISE(ABORT, 'Confirmed journal lines cannot be replaced through an update');
END
''',
    ..._freezeCommercialTable('purchases', 'document_id'),
    ..._freezeCommercialTable('purchase_lines', 'purchase_id'),
    ..._freezeCommercialTable('inventory_movements', 'document_id'),
    ..._freezeCommercialTable('obligations', 'origin_document_id'),
    ..._freezeCommercialTable(
      'cost_layers',
      'inbound_movement_id',
      throughMovement: true,
    ),
    ..._freezePurchaseJournalLines(),
  ]);

  /// V2 facts remain intact. Sale outflows and receivables are additional facts;
  /// stock is received quantities/costs less their confirmed sale outflows.
  static final List<String> migration3Statements = List<String>.unmodifiable([
    '''
CREATE TABLE sales_drafts (
  id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(id)) > 0),
  label TEXT NOT NULL CHECK (length(trim(label)) BETWEEN 1 AND 160),
  customer_name TEXT NOT NULL CHECK (length(trim(customer_name)) BETWEEN 1 AND 160),
  revision INTEGER NOT NULL CHECK (typeof(revision) = 'integer' AND revision > 0),
  status TEXT NOT NULL CHECK (status IN ('open', 'prepared', 'confirmed')),
  updated_at_utc TEXT NOT NULL CHECK (length(updated_at_utc) > 0),
  confirmed_document_id TEXT UNIQUE REFERENCES business_documents(id) ON DELETE RESTRICT,
  CHECK ((status = 'confirmed') = (confirmed_document_id IS NOT NULL))
)
''',
    '''
CREATE TABLE sales_draft_lines (
  draft_id TEXT NOT NULL REFERENCES sales_drafts(id) ON DELETE RESTRICT,
  sequence INTEGER NOT NULL CHECK (typeof(sequence) = 'integer' AND sequence >= 0),
  product_id TEXT NOT NULL REFERENCES catalog_items(id) ON DELETE RESTRICT,
  quantity INTEGER NOT NULL CHECK (typeof(quantity) = 'integer' AND quantity > 0),
  unit_price_minor INTEGER NOT NULL CHECK (typeof(unit_price_minor) = 'integer' AND unit_price_minor >= 0),
  PRIMARY KEY (draft_id, sequence),
  UNIQUE (draft_id, product_id)
)
''',
    '''
CREATE TABLE sale_confirmations (
  command_id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(command_id)) > 0),
  draft_id TEXT NOT NULL REFERENCES sales_drafts(id) ON DELETE RESTRICT,
  draft_revision INTEGER NOT NULL CHECK (typeof(draft_revision) = 'integer' AND draft_revision > 0),
  canonical_payload TEXT NOT NULL CHECK (length(trim(canonical_payload)) > 0),
  occurred_at_utc TEXT NOT NULL CHECK (length(occurred_at_utc) > 0),
  due_date TEXT NOT NULL CHECK (length(due_date) = 10),
  prepared_at_utc TEXT NOT NULL CHECK (length(prepared_at_utc) > 0),
  status TEXT NOT NULL CHECK (status IN ('prepared', 'rejected', 'cancelled', 'confirmed')),
  rejection_reason TEXT,
  CHECK ((status IN ('prepared', 'confirmed') AND rejection_reason IS NULL)
    OR (status IN ('rejected', 'cancelled') AND rejection_reason IS NOT NULL
      AND length(trim(rejection_reason)) > 0))
)
''',
    '''
CREATE UNIQUE INDEX idx_confirmations_active_draft ON sale_confirmations(draft_id)
WHERE status <> 'cancelled'
''',
    '''
CREATE TABLE sales (
  document_id TEXT PRIMARY KEY NOT NULL REFERENCES business_documents(id) ON DELETE RESTRICT,
  draft_id TEXT NOT NULL UNIQUE REFERENCES sales_drafts(id) ON DELETE RESTRICT,
  customer_name_snapshot TEXT NOT NULL CHECK (length(trim(customer_name_snapshot)) BETWEEN 1 AND 160),
  label_snapshot TEXT NOT NULL CHECK (length(trim(label_snapshot)) BETWEEN 1 AND 160),
  sold_at_utc TEXT NOT NULL CHECK (length(sold_at_utc) > 0),
  due_date TEXT NOT NULL CHECK (length(due_date) = 10),
  receivable_minor INTEGER NOT NULL CHECK (typeof(receivable_minor) = 'integer' AND receivable_minor > 0),
  total_cost_minor INTEGER NOT NULL CHECK (typeof(total_cost_minor) = 'integer' AND total_cost_minor >= 0),
  terms TEXT NOT NULL CHECK (terms = 'credit'),
  cost_policy TEXT NOT NULL CHECK (cost_policy = 'fifo-front-remainder-v1')
)
''',
    '''
CREATE TABLE sale_lines (
  id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(id)) > 0),
  sale_id TEXT NOT NULL REFERENCES sales(document_id) ON DELETE RESTRICT,
  sequence INTEGER NOT NULL CHECK (typeof(sequence) = 'integer' AND sequence >= 0),
  product_id TEXT NOT NULL REFERENCES catalog_items(id) ON DELETE RESTRICT,
  name_snapshot TEXT NOT NULL CHECK (length(trim(name_snapshot)) BETWEEN 1 AND 160),
  quantity INTEGER NOT NULL CHECK (typeof(quantity) = 'integer' AND quantity > 0),
  unit_price_minor INTEGER NOT NULL CHECK (typeof(unit_price_minor) = 'integer' AND unit_price_minor >= 0),
  total_minor INTEGER NOT NULL CHECK (typeof(total_minor) = 'integer' AND total_minor >= 0),
  total_cost_minor INTEGER NOT NULL CHECK (typeof(total_cost_minor) = 'integer' AND total_cost_minor >= 0),
  CHECK (quantity * unit_price_minor = total_minor
    AND typeof(quantity * unit_price_minor) = 'integer'),
  UNIQUE (sale_id, sequence),
  UNIQUE (sale_id, product_id)
)
''',
    '''
CREATE TABLE sale_outflows (
  id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(id)) > 0),
  document_id TEXT NOT NULL REFERENCES sales(document_id) ON DELETE RESTRICT,
  sequence INTEGER NOT NULL CHECK (typeof(sequence) = 'integer' AND sequence >= 0),
  product_id TEXT NOT NULL REFERENCES catalog_items(id) ON DELETE RESTRICT,
  sale_line_id TEXT NOT NULL UNIQUE REFERENCES sale_lines(id) ON DELETE RESTRICT,
  quantity INTEGER NOT NULL CHECK (typeof(quantity) = 'integer' AND quantity > 0),
  cost_minor INTEGER NOT NULL CHECK (typeof(cost_minor) = 'integer' AND cost_minor >= 0),
  UNIQUE (document_id, sequence)
)
''',
    '''
CREATE TABLE sale_cost_allocations (
  id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(id)) > 0),
  sale_line_id TEXT NOT NULL REFERENCES sale_lines(id) ON DELETE RESTRICT,
  cost_layer_id TEXT NOT NULL REFERENCES cost_layers(id) ON DELETE RESTRICT,
  sequence INTEGER NOT NULL CHECK (typeof(sequence) = 'integer' AND sequence >= 0),
  quantity INTEGER NOT NULL CHECK (typeof(quantity) = 'integer' AND quantity > 0),
  cost_minor INTEGER NOT NULL CHECK (typeof(cost_minor) = 'integer' AND cost_minor >= 0),
  UNIQUE (sale_line_id, sequence),
  UNIQUE (sale_line_id, cost_layer_id)
)
''',
    '''
CREATE TABLE customer_receivables (
  id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(id)) > 0),
  origin_document_id TEXT NOT NULL UNIQUE REFERENCES sales(document_id) ON DELETE RESTRICT,
  customer_name_snapshot TEXT NOT NULL CHECK (length(trim(customer_name_snapshot)) BETWEEN 1 AND 160),
  control_account_id TEXT NOT NULL REFERENCES ledger_accounts(id) ON DELETE RESTRICT,
  initial_minor INTEGER NOT NULL CHECK (typeof(initial_minor) = 'integer' AND initial_minor > 0),
  issued_at_utc TEXT NOT NULL CHECK (length(issued_at_utc) > 0),
  due_date TEXT NOT NULL CHECK (length(due_date) = 10)
)
''',
    'CREATE INDEX idx_sale_lines_product ON sale_lines(product_id)',
    'CREATE INDEX idx_outflows_product ON sale_outflows(product_id)',
    'CREATE INDEX idx_allocations_layer ON sale_cost_allocations(cost_layer_id)',
    '''
CREATE TRIGGER sale_confirmations_reserve_command_id
BEFORE INSERT ON command_log
WHEN EXISTS (SELECT 1 FROM sale_confirmations c WHERE c.command_id = NEW.id
  AND (NEW.command_type <> 'confirm_sale' OR c.status <> 'prepared'))
BEGIN
  SELECT RAISE(ABORT, 'A prepared sale command identifier is reserved for its confirmation');
END
''',
    '''
CREATE TRIGGER purchases_validate_sale_chronology
BEFORE UPDATE OF status ON business_documents
WHEN OLD.status = 'draft' AND NEW.status = 'posted' AND NEW.type = 'purchase_receipt'
BEGIN
  SELECT CASE WHEN EXISTS (SELECT 1 FROM purchase_lines p
    JOIN purchases receipt ON receipt.document_id = p.purchase_id
    JOIN sale_lines l ON l.product_id = p.product_id
    JOIN sales s ON s.document_id = l.sale_id
    JOIN business_documents d ON d.id = s.document_id
    JOIN journal_entries j ON j.document_id = d.id
    WHERE p.purchase_id = NEW.id AND d.status = 'posted' AND j.status = 'posted'
      AND ${_utcSortKey('receipt.received_at_utc')} < ${_utcSortKey('s.sold_at_utc')})
    THEN RAISE(ABORT, 'A receipt cannot predate a confirmed sale of the same product') END;
END
''',
    '''
CREATE TRIGGER sales_drafts_insert_open
BEFORE INSERT ON sales_drafts
WHEN NEW.status <> 'open' OR EXISTS (SELECT 1 FROM sales_drafts WHERE id = NEW.id)
BEGIN
  SELECT RAISE(ABORT, 'Create a new sale account as open; accounts cannot be replaced');
END
''',
    '''
CREATE TRIGGER sales_drafts_validate_update
BEFORE UPDATE ON sales_drafts
BEGIN
  SELECT CASE WHEN NEW.id <> OLD.id OR OLD.status = 'confirmed'
    THEN RAISE(ABORT, 'Confirmed sale accounts are immutable') END;
  SELECT CASE WHEN OLD.status = 'open' AND NEW.status = 'open' AND (
    NEW.revision <> OLD.revision + 1 OR EXISTS (
      SELECT 1 FROM sale_confirmations WHERE draft_id = OLD.id AND status <> 'cancelled'))
    THEN RAISE(ABORT, 'Edit only the latest open account without a pending confirmation') END;
  SELECT CASE WHEN OLD.status = 'open' AND NEW.status = 'prepared' AND (
    NEW.revision <> OLD.revision OR NEW.label <> OLD.label OR NEW.customer_name <> OLD.customer_name
    OR NOT EXISTS (SELECT 1 FROM sale_confirmations WHERE draft_id = OLD.id
      AND draft_revision = OLD.revision AND status = 'prepared'))
    THEN RAISE(ABORT, 'Prepare the exact saved sale account') END;
  SELECT CASE WHEN OLD.status = 'prepared' AND NEW.status = 'open' AND (
    NEW.revision <> OLD.revision + 1 OR NEW.label <> OLD.label OR NEW.customer_name <> OLD.customer_name
    OR EXISTS (SELECT 1 FROM sale_confirmations WHERE draft_id = OLD.id AND status <> 'cancelled'))
    THEN RAISE(ABORT, 'Only a cancelled rejection may reopen its sale account') END;
  SELECT CASE WHEN NEW.status = 'confirmed' AND (
    OLD.status <> 'prepared' OR NEW.revision <> OLD.revision OR NEW.label <> OLD.label
    OR NEW.customer_name <> OLD.customer_name OR NOT EXISTS (
      SELECT 1 FROM sales s JOIN business_documents d ON d.id = s.document_id
      JOIN journal_entries j ON j.document_id = d.id
      JOIN sale_confirmations c ON c.command_id = d.command_id
      WHERE s.draft_id = OLD.id AND s.document_id = NEW.confirmed_document_id
        AND d.status = 'posted' AND j.status = 'posted' AND c.status = 'confirmed'))
    THEN RAISE(ABORT, 'Confirm the sale and its journal before closing its account') END;
  SELECT CASE WHEN OLD.status = 'prepared' AND NEW.status = 'prepared'
    THEN RAISE(ABORT, 'Prepared sale accounts are locked') END;
  SELECT CASE WHEN OLD.status = 'open' AND NEW.status = 'confirmed'
    THEN RAISE(ABORT, 'Prepare a sale account before confirmation') END;
END
''',
    '''
CREATE TRIGGER sales_drafts_no_delete
BEFORE DELETE ON sales_drafts
BEGIN
  SELECT RAISE(ABORT, 'Saved sale accounts cannot be deleted');
END
''',
    ..._freezeSaleDraftLines(),
    '''
CREATE TRIGGER sale_confirmations_validate_insert
BEFORE INSERT ON sale_confirmations
BEGIN
  SELECT CASE WHEN NEW.status <> 'prepared' OR EXISTS (
    SELECT 1 FROM sale_confirmations WHERE command_id = NEW.command_id
      OR (draft_id = NEW.draft_id AND status <> 'cancelled'))
    OR EXISTS (SELECT 1 FROM command_log WHERE id = NEW.command_id)
    THEN RAISE(ABORT, 'Create a unique prepared sale confirmation') END;
  SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM sales_drafts WHERE id = NEW.draft_id
    AND status = 'open' AND revision = NEW.draft_revision)
    OR NOT EXISTS (SELECT 1 FROM sales_draft_lines WHERE draft_id = NEW.draft_id)
    THEN RAISE(ABORT, 'A confirmation requires the current saved open account') END;
END
''',
    '''
CREATE TRIGGER sale_confirmations_validate_update
BEFORE UPDATE ON sale_confirmations
BEGIN
  SELECT CASE WHEN NEW.command_id <> OLD.command_id OR NEW.draft_id <> OLD.draft_id
    OR NEW.draft_revision <> OLD.draft_revision OR NEW.canonical_payload <> OLD.canonical_payload
    OR NEW.occurred_at_utc <> OLD.occurred_at_utc OR NEW.due_date <> OLD.due_date
    OR NEW.prepared_at_utc <> OLD.prepared_at_utc
    THEN RAISE(ABORT, 'Prepared sale input is immutable') END;
  SELECT CASE WHEN NOT ((OLD.status = 'prepared' AND NEW.status IN ('rejected', 'confirmed'))
    OR (OLD.status = 'rejected' AND NEW.status = 'cancelled'))
    THEN RAISE(ABORT, 'Invalid sale confirmation transition') END;
  SELECT CASE WHEN NEW.status IN ('rejected', 'cancelled')
    AND EXISTS (SELECT 1 FROM command_log WHERE id = OLD.command_id)
    THEN RAISE(ABORT, 'A committed sale cannot be rejected or cancelled') END;
  SELECT CASE WHEN NEW.status = 'cancelled' AND NEW.rejection_reason IS NOT OLD.rejection_reason
    THEN RAISE(ABORT, 'The sale rejection reason is historical') END;
  SELECT CASE WHEN NEW.status = 'confirmed' AND NOT EXISTS (
    SELECT 1 FROM business_documents d JOIN sales s ON s.document_id = d.id
    JOIN journal_entries j ON j.document_id = d.id
    WHERE d.command_id = OLD.command_id AND s.draft_id = OLD.draft_id
      AND d.status = 'posted' AND j.status = 'posted')
    THEN RAISE(ABORT, 'Post a sale and its journal before completing confirmation') END;
END
''',
    '''
CREATE TRIGGER sale_confirmations_no_delete
BEFORE DELETE ON sale_confirmations
BEGIN
  SELECT RAISE(ABORT, 'Prepared sale inputs cannot be deleted');
END
''',
    '''
CREATE TRIGGER sales_documents_insert_as_draft
BEFORE INSERT ON business_documents
WHEN NEW.type = 'credit_sale' AND NEW.status <> 'draft'
BEGIN
  SELECT RAISE(ABORT, 'Create a sale document as draft before posting');
END
''',
    '''
CREATE TRIGGER sales_require_draft_document
BEFORE INSERT ON sales
WHEN NOT EXISTS (SELECT 1 FROM business_documents WHERE id = NEW.document_id
  AND type = 'credit_sale' AND status = 'draft')
BEGIN
  SELECT RAISE(ABORT, 'A sale requires a draft credit sale document');
END
''',
    '''
CREATE TRIGGER sale_cost_allocations_validate_insert
BEFORE INSERT ON sale_cost_allocations
BEGIN
  SELECT CASE WHEN EXISTS (SELECT 1 FROM sale_cost_allocations WHERE id = NEW.id
    OR (sale_line_id = NEW.sale_line_id AND sequence = NEW.sequence)
    OR (sale_line_id = NEW.sale_line_id AND cost_layer_id = NEW.cost_layer_id))
    THEN RAISE(ABORT, 'Cost allocations cannot be replaced') END;
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM sale_lines l JOIN sales s ON s.document_id = l.sale_id
    JOIN business_documents d ON d.id = s.document_id
    JOIN cost_layers c ON c.id = NEW.cost_layer_id
    JOIN inventory_movements m ON m.id = c.inbound_movement_id
    JOIN business_documents p ON p.id = m.document_id
    JOIN journal_entries j ON j.document_id = p.id
    WHERE l.id = NEW.sale_line_id AND l.product_id = c.product_id
      AND d.type = 'credit_sale' AND d.status = 'draft'
      AND ${_utcSortKey('c.acquired_at_utc')} <= ${_utcSortKey('s.sold_at_utc')}
      AND p.status = 'posted' AND j.status = 'posted')
    THEN RAISE(ABORT, 'Allocate only a matching confirmed inbound cost layer') END;
  SELECT CASE WHEN NEW.sequence <> (
    SELECT count(*) FROM sale_cost_allocations WHERE sale_line_id = NEW.sale_line_id)
    OR NEW.quantity > (SELECT l.quantity - coalesce((
      SELECT sum(a.quantity) FROM sale_cost_allocations a WHERE a.sale_line_id = l.id), 0)
      FROM sale_lines l WHERE l.id = NEW.sale_line_id)
    OR NEW.quantity > (SELECT c.initial_quantity - coalesce((
      SELECT sum(a.quantity) FROM sale_cost_allocations a WHERE a.cost_layer_id = c.id), 0)
      FROM cost_layers c WHERE c.id = NEW.cost_layer_id)
    THEN RAISE(ABORT, 'A cost allocation cannot exceed remaining sale or layer quantities') END;
  SELECT CASE WHEN EXISTS (
    SELECT 1 FROM cost_layers older JOIN cost_layers chosen ON chosen.id = NEW.cost_layer_id
    JOIN sale_lines l ON l.id = NEW.sale_line_id
    JOIN sales s ON s.document_id = l.sale_id
    JOIN inventory_movements m ON m.id = older.inbound_movement_id
    JOIN business_documents d ON d.id = m.document_id
    JOIN journal_entries j ON j.document_id = d.id
    WHERE older.product_id = chosen.product_id AND older.fifo_sequence < chosen.fifo_sequence
      AND ${_utcSortKey('older.acquired_at_utc')} <= ${_utcSortKey('s.sold_at_utc')}
      AND d.status = 'posted' AND j.status = 'posted'
      AND older.initial_quantity > coalesce((SELECT sum(a.quantity)
        FROM sale_cost_allocations a WHERE a.cost_layer_id = older.id), 0))
    THEN RAISE(ABORT, 'Consume the oldest available cost layer first') END;
  SELECT CASE WHEN NEW.cost_minor <> (SELECT
    NEW.quantity * (c.total_cost_minor / c.initial_quantity)
      + min(NEW.quantity, max(0, c.total_cost_minor % c.initial_quantity - coalesce((
        SELECT sum(a.quantity) FROM sale_cost_allocations a WHERE a.cost_layer_id = c.id), 0)))
    FROM cost_layers c WHERE c.id = NEW.cost_layer_id)
    THEN RAISE(ABORT, 'A FIFO allocation must preserve exact documented cost') END;
END
''',
    for (final action in ['UPDATE', 'DELETE'])
      '''
CREATE TRIGGER sale_cost_allocations_no_${action.toLowerCase()}
BEFORE $action ON sale_cost_allocations
BEGIN
  SELECT RAISE(ABORT, 'FIFO allocations are immutable; roll back an unfinished operation');
END
''',
    '''
CREATE TRIGGER sales_validate_document_posting
BEFORE UPDATE OF status ON business_documents
WHEN OLD.status = 'draft' AND NEW.status = 'posted' AND
  (NEW.type = 'credit_sale' OR EXISTS (SELECT 1 FROM sales WHERE document_id = NEW.id))
BEGIN
  SELECT CASE WHEN NEW.type <> 'credit_sale' OR NEW.command_sequence <> 0
    OR NOT EXISTS (SELECT 1 FROM command_log c WHERE c.id = NEW.command_id
      AND c.command_type = 'confirm_sale' AND c.actor_id = NEW.actor_id
      AND c.authorization_policy_version = 'development-single-user-v1')
    THEN RAISE(ABORT, 'Invalid sale command or document type') END;
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM sales s JOIN sales_drafts a ON a.id = s.draft_id
    JOIN sale_confirmations c ON c.command_id = NEW.command_id
    WHERE s.document_id = NEW.id AND a.status = 'prepared' AND c.status = 'prepared'
      AND c.draft_id = a.id AND c.draft_revision = a.revision
      AND s.label_snapshot = a.label AND s.customer_name_snapshot = a.customer_name
      AND s.sold_at_utc = NEW.occurred_at_utc AND s.sold_at_utc = c.occurred_at_utc
      AND s.due_date = c.due_date AND s.due_date >= NEW.business_date
      AND date(s.due_date) = s.due_date
      AND date(NEW.occurred_at_utc, '-5 hours') = NEW.business_date)
    THEN RAISE(ABORT, 'Sale header must match the durable saved account confirmation') END;
  SELECT CASE WHEN EXISTS (SELECT 1 FROM sale_lines incoming
    JOIN sales current ON current.document_id = incoming.sale_id
    JOIN sale_lines previous ON previous.product_id = incoming.product_id
    JOIN sales earlier ON earlier.document_id = previous.sale_id
    JOIN business_documents d ON d.id = earlier.document_id
    JOIN journal_entries j ON j.document_id = d.id
    WHERE incoming.sale_id = NEW.id AND earlier.document_id <> NEW.id
      AND d.status = 'posted' AND j.status = 'posted'
      AND ${_utcSortKey('earlier.sold_at_utc')} > ${_utcSortKey('current.sold_at_utc')})
    THEN RAISE(ABORT, 'A sale cannot predate a confirmed sale of the same product') END;
  SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM sale_lines WHERE sale_id = NEW.id)
    OR (SELECT count(*) FROM sale_lines WHERE sale_id = NEW.id) <>
      (SELECT count(*) FROM sales_draft_lines l JOIN sales s ON s.draft_id = l.draft_id
        WHERE s.document_id = NEW.id)
    OR EXISTS (SELECT 1 FROM sale_lines l JOIN catalog_items p ON p.id = l.product_id
      LEFT JOIN categories g ON g.id = p.category_id WHERE l.sale_id = NEW.id AND (
        p.is_active <> 1 OR l.name_snapshot <> p.name
        OR (p.category_id IS NOT NULL AND g.is_active <> 1)
        OR NOT EXISTS (SELECT 1 FROM sales_draft_lines d JOIN sales s ON s.draft_id = d.draft_id
          WHERE s.document_id = NEW.id AND d.product_id = l.product_id
            AND d.sequence = l.sequence AND d.quantity = l.quantity
            AND d.unit_price_minor = l.unit_price_minor)))
    THEN RAISE(ABORT, 'Sale lines must match saved quantities, prices and active catalog snapshots') END;
  SELECT CASE WHEN (SELECT sum(total_minor) FROM sale_lines WHERE sale_id = NEW.id)
      <> (SELECT receivable_minor FROM sales WHERE document_id = NEW.id)
    OR (SELECT sum(total_cost_minor) FROM sale_lines WHERE sale_id = NEW.id)
      <> (SELECT total_cost_minor FROM sales WHERE document_id = NEW.id)
    THEN RAISE(ABORT, 'Sale totals must equal their immutable lines') END;
  SELECT CASE WHEN (SELECT count(*) FROM sale_outflows WHERE document_id = NEW.id)
      <> (SELECT count(*) FROM sale_lines WHERE sale_id = NEW.id)
    OR EXISTS (SELECT 1 FROM sale_lines l WHERE l.sale_id = NEW.id AND (
      NOT EXISTS (SELECT 1 FROM sale_outflows o WHERE o.document_id = NEW.id
        AND o.sale_line_id = l.id AND o.sequence = l.sequence AND o.product_id = l.product_id
        AND o.quantity = l.quantity AND o.cost_minor = l.total_cost_minor)
      OR (SELECT coalesce(sum(a.quantity), 0) FROM sale_cost_allocations a
        WHERE a.sale_line_id = l.id) <> l.quantity
      OR (SELECT coalesce(sum(a.cost_minor), 0) FROM sale_cost_allocations a
        WHERE a.sale_line_id = l.id) <> l.total_cost_minor
      OR EXISTS (SELECT 1 FROM sale_cost_allocations a
        JOIN cost_layers c ON c.id = a.cost_layer_id
        JOIN inventory_movements m ON m.id = c.inbound_movement_id
        JOIN business_documents p ON p.id = m.document_id
        JOIN journal_entries j ON j.document_id = p.id
        JOIN sales s ON s.document_id = l.sale_id
        WHERE a.sale_line_id = l.id AND (c.product_id <> l.product_id
          OR ${_utcSortKey('c.acquired_at_utc')} > ${_utcSortKey('s.sold_at_utc')}
          OR p.status <> 'posted' OR j.status <> 'posted'))))
    THEN RAISE(ABORT, 'Each sale line requires its exact stock outflow and FIFO cost allocations') END;
  SELECT CASE WHEN (SELECT count(*) FROM customer_receivables WHERE origin_document_id = NEW.id) <> 1
    OR NOT EXISTS (SELECT 1 FROM customer_receivables r
      JOIN sales s ON s.document_id = r.origin_document_id
      JOIN ledger_accounts a ON a.id = r.control_account_id
      WHERE r.origin_document_id = NEW.id AND r.customer_name_snapshot = s.customer_name_snapshot
        AND r.initial_minor = s.receivable_minor AND r.issued_at_utc = s.sold_at_utc
        AND r.due_date = s.due_date AND a.role = 'customer_receivable'
        AND a.class = 'asset' AND a.is_active = 1)
    THEN RAISE(ABORT, 'A credit sale requires its matching customer receivable') END;
  SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM journal_entries e
    WHERE e.document_id = NEW.id AND e.status = 'draft' AND e.cost_completeness = 'complete')
    THEN RAISE(ABORT, 'Prepare the complete sale journal before posting') END;
  SELECT CASE WHEN (SELECT count(*) FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id
      WHERE e.document_id = NEW.id) <> (SELECT CASE WHEN total_cost_minor > 0 THEN 4 ELSE 2 END
        FROM sales WHERE document_id = NEW.id)
    OR NOT EXISTS (SELECT 1 FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id
      JOIN customer_receivables r ON r.origin_document_id = e.document_id
      WHERE e.document_id = NEW.id AND l.account_id = r.control_account_id
        AND l.debit_minor = r.initial_minor AND l.credit_minor = 0)
    OR NOT EXISTS (SELECT 1 FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id
      JOIN ledger_accounts a ON a.id = l.account_id JOIN sales s ON s.document_id = e.document_id
      WHERE e.document_id = NEW.id AND a.class = 'revenue' AND a.role = 'sales_revenue'
        AND a.is_active = 1 AND l.credit_minor = s.receivable_minor AND l.debit_minor = 0)
    OR EXISTS (SELECT 1 FROM sales s WHERE s.document_id = NEW.id AND s.total_cost_minor > 0
      AND (NOT EXISTS (SELECT 1 FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id
        JOIN ledger_accounts a ON a.id = l.account_id WHERE e.document_id = NEW.id
          AND a.class = 'cost' AND a.role = 'cost_of_sales' AND a.is_active = 1
          AND l.debit_minor = s.total_cost_minor AND l.credit_minor = 0)
        OR NOT EXISTS (SELECT 1 FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id
        JOIN ledger_accounts a ON a.id = l.account_id WHERE e.document_id = NEW.id
          AND a.class = 'asset' AND a.role = 'inventory' AND a.is_active = 1
          AND l.credit_minor = s.total_cost_minor AND l.debit_minor = 0)))
    THEN RAISE(ABORT, 'A sale must post receivable, revenue and its exact documented inventory cost') END;
END
''',
    ..._freezeSaleFacts(
      'sales',
      'document_id',
      'existing.document_id = NEW.document_id OR existing.draft_id = NEW.draft_id',
    ),
    ..._freezeSaleFacts(
      'sale_lines',
      'sale_id',
      '''existing.id = NEW.id
OR (existing.sale_id = NEW.sale_id AND existing.sequence = NEW.sequence)
OR (existing.sale_id = NEW.sale_id AND existing.product_id = NEW.product_id)''',
    ),
    ..._freezeSaleFacts(
      'sale_outflows',
      'document_id',
      '''existing.id = NEW.id
OR existing.sale_line_id = NEW.sale_line_id
OR (existing.document_id = NEW.document_id AND existing.sequence = NEW.sequence)''',
    ),
    ..._freezeSaleFacts(
      'customer_receivables',
      'origin_document_id',
      'existing.id = NEW.id OR existing.origin_document_id = NEW.origin_document_id',
    ),
    ..._freezeSaleJournal(),
  ]);

  /// V1 through V3 remain historical inputs. Collections append new facts only.
  static final List<String> migration4Statements = List<String>.unmodifiable([
    '''
CREATE TABLE collection_requests (
  command_id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(command_id)) > 0),
  canonical_payload TEXT NOT NULL CHECK (length(trim(canonical_payload)) > 0),
  receivable_id TEXT NOT NULL REFERENCES customer_receivables(id) ON DELETE RESTRICT,
  occurred_at_utc TEXT NOT NULL CHECK (${_collectionUtc('occurred_at_utc')}),
  prepared_at_utc TEXT NOT NULL CHECK (${_collectionUtc('prepared_at_utc')}),
  status TEXT NOT NULL CHECK (status IN ('prepared', 'rejected', 'cancelled', 'confirmed')),
  rejection_reason TEXT,
  CHECK ((status IN ('prepared', 'confirmed') AND rejection_reason IS NULL)
    OR (status IN ('rejected', 'cancelled') AND rejection_reason IS NOT NULL
      AND length(trim(rejection_reason)) > 0))
)
''',
    '''
CREATE TABLE collections (
  document_id TEXT PRIMARY KEY NOT NULL REFERENCES business_documents(id) ON DELETE RESTRICT,
  receivable_id TEXT NOT NULL REFERENCES customer_receivables(id) ON DELETE RESTRICT,
  sale_label_snapshot TEXT NOT NULL CHECK (length(trim(sale_label_snapshot)) BETWEEN 1 AND 160),
  customer_name_snapshot TEXT NOT NULL CHECK (length(trim(customer_name_snapshot)) BETWEEN 1 AND 160),
  collected_at_utc TEXT NOT NULL CHECK (${_collectionUtc('collected_at_utc')}),
  total_minor INTEGER NOT NULL CHECK (typeof(total_minor) = 'integer' AND total_minor > 0),
  remaining_minor INTEGER NOT NULL CHECK (typeof(remaining_minor) = 'integer' AND remaining_minor >= 0)
)
''',
    '''
CREATE TABLE collection_parts (
  id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(id)) > 0),
  collection_id TEXT NOT NULL REFERENCES collections(document_id) ON DELETE RESTRICT,
  sequence INTEGER NOT NULL CHECK (typeof(sequence) = 'integer' AND sequence >= 0),
  cash_account_id TEXT NOT NULL REFERENCES cash_accounts(id) ON DELETE RESTRICT,
  payment_method_id TEXT NOT NULL REFERENCES payment_methods(id) ON DELETE RESTRICT,
  cash_account_name_snapshot TEXT NOT NULL CHECK (length(trim(cash_account_name_snapshot)) BETWEEN 1 AND 160),
  cash_account_kind_snapshot TEXT NOT NULL CHECK (cash_account_kind_snapshot IN ('cash', 'bank', 'mobile', 'clearing')),
  payment_method_code_snapshot TEXT NOT NULL CHECK (length(trim(payment_method_code_snapshot)) BETWEEN 1 AND 32),
  payment_method_name_snapshot TEXT NOT NULL CHECK (length(trim(payment_method_name_snapshot)) BETWEEN 1 AND 160),
  amount_minor INTEGER NOT NULL CHECK (typeof(amount_minor) = 'integer' AND amount_minor > 0),
  UNIQUE (collection_id, sequence)
)
''',
    '''
CREATE TABLE receivable_settlements (
  id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(id)) > 0),
  receivable_id TEXT NOT NULL REFERENCES customer_receivables(id) ON DELETE RESTRICT,
  collection_id TEXT NOT NULL UNIQUE REFERENCES collections(document_id) ON DELETE RESTRICT,
  amount_minor INTEGER NOT NULL CHECK (typeof(amount_minor) = 'integer' AND amount_minor > 0)
)
''',
    'CREATE INDEX idx_collections_receivable ON collections(receivable_id)',
    'CREATE INDEX idx_collection_parts_cash ON collection_parts(cash_account_id)',
    'CREATE INDEX idx_settlements_receivable ON receivable_settlements(receivable_id)',
    '''
CREATE TRIGGER collection_requests_validate_insert
BEFORE INSERT ON collection_requests
BEGIN
  SELECT CASE WHEN NEW.status <> 'prepared'
    OR EXISTS (SELECT 1 FROM collection_requests WHERE command_id = NEW.command_id)
    OR EXISTS (SELECT 1 FROM command_log WHERE id = NEW.command_id)
    OR EXISTS (SELECT 1 FROM sale_confirmations WHERE command_id = NEW.command_id)
    THEN RAISE(ABORT, 'Create a unique prepared collection request') END;
  SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM customer_receivables r
    JOIN business_documents d ON d.id = r.origin_document_id
    JOIN journal_entries j ON j.document_id = d.id
    WHERE r.id = NEW.receivable_id AND d.status = 'posted' AND j.status = 'posted')
    THEN RAISE(ABORT, 'A collection request requires a confirmed customer receivable') END;
END
''',
    '''
CREATE TRIGGER collection_requests_validate_update
BEFORE UPDATE ON collection_requests
BEGIN
  SELECT CASE WHEN NEW.command_id <> OLD.command_id
    OR NEW.canonical_payload <> OLD.canonical_payload
    OR NEW.receivable_id <> OLD.receivable_id
    OR NEW.occurred_at_utc <> OLD.occurred_at_utc
    OR NEW.prepared_at_utc <> OLD.prepared_at_utc
    THEN RAISE(ABORT, 'Prepared collection input is immutable') END;
  SELECT CASE WHEN NOT ((OLD.status = 'prepared' AND NEW.status IN ('rejected', 'confirmed'))
    OR (OLD.status = 'rejected' AND NEW.status = 'cancelled'))
    THEN RAISE(ABORT, 'Invalid collection request transition') END;
  SELECT CASE WHEN NEW.status IN ('rejected', 'cancelled')
    AND EXISTS (SELECT 1 FROM command_log WHERE id = OLD.command_id)
    THEN RAISE(ABORT, 'A committed collection cannot be rejected or cancelled') END;
  SELECT CASE WHEN NEW.status = 'cancelled' AND NEW.rejection_reason IS NOT OLD.rejection_reason
    THEN RAISE(ABORT, 'The collection rejection reason is historical') END;
  SELECT CASE WHEN NEW.status = 'confirmed' AND NOT EXISTS (
    SELECT 1 FROM business_documents d JOIN collections c ON c.document_id = d.id
    JOIN journal_entries j ON j.document_id = d.id
    WHERE d.command_id = OLD.command_id AND c.receivable_id = OLD.receivable_id
      AND d.type = 'customer_collection' AND d.status = 'posted' AND j.status = 'posted')
    THEN RAISE(ABORT, 'Post a collection and its journal before completing its request') END;
END
''',
    '''
CREATE TRIGGER collection_requests_no_delete
BEFORE DELETE ON collection_requests
BEGIN
  SELECT RAISE(ABORT, 'Prepared collection inputs cannot be deleted');
END
''',
    '''
CREATE TRIGGER collection_requests_reserve_command_id
BEFORE INSERT ON command_log
WHEN EXISTS (SELECT 1 FROM collection_requests c WHERE c.command_id = NEW.id
  AND (NEW.command_type <> 'collect_receivable' OR c.status <> 'prepared'))
BEGIN
  SELECT RAISE(ABORT, 'A prepared collection command identifier is reserved for its collection');
END
''',
    '''
CREATE TRIGGER sale_confirmations_reject_collection_command
BEFORE INSERT ON sale_confirmations
WHEN EXISTS (SELECT 1 FROM collection_requests WHERE command_id = NEW.command_id)
BEGIN
  SELECT RAISE(ABORT, 'Collection request command identifiers cannot be reused for sales');
END
''',
    '''
CREATE TRIGGER command_log_no_replace_v4
BEFORE INSERT ON command_log
WHEN EXISTS (SELECT 1 FROM command_log WHERE id = NEW.id)
BEGIN
  SELECT RAISE(ABORT, 'Committed command results cannot be replaced');
END
''',
    '''
CREATE TRIGGER collections_documents_insert_as_draft
BEFORE INSERT ON business_documents
WHEN NEW.type = 'customer_collection' AND NEW.status <> 'draft'
BEGIN
  SELECT RAISE(ABORT, 'Create a collection document as draft before posting');
END
''',
    '''
CREATE TRIGGER collections_documents_no_replace
BEFORE INSERT ON business_documents
WHEN EXISTS (SELECT 1 FROM business_documents d
  WHERE (d.id = NEW.id OR (d.command_id = NEW.command_id AND d.command_sequence = NEW.command_sequence))
    AND d.type = 'customer_collection' AND d.status <> 'draft')
BEGIN
  SELECT RAISE(ABORT, 'Confirmed collection documents cannot be replaced');
END
''',
    '''
CREATE TRIGGER collections_documents_no_conflicting_update
BEFORE UPDATE ON business_documents
WHEN EXISTS (SELECT 1 FROM business_documents d
  WHERE d.id <> OLD.id AND (d.id = NEW.id OR
    (d.command_id = NEW.command_id AND d.command_sequence = NEW.command_sequence))
    AND d.type = 'customer_collection' AND d.status <> 'draft')
BEGIN
  SELECT RAISE(ABORT, 'Confirmed collection documents cannot be replaced through an update');
END
''',
    '''
CREATE TRIGGER collections_require_draft_document
BEFORE INSERT ON collections
WHEN NOT EXISTS (SELECT 1 FROM business_documents WHERE id = NEW.document_id
  AND type = 'customer_collection' AND status = 'draft')
BEGIN
  SELECT RAISE(ABORT, 'A collection requires a draft collection document');
END
''',
    '''
CREATE TRIGGER collections_validate_document_posting
BEFORE UPDATE OF status ON business_documents
WHEN OLD.status = 'draft' AND NEW.status = 'posted' AND
  (NEW.type = 'customer_collection' OR EXISTS (SELECT 1 FROM collections WHERE document_id = NEW.id))
BEGIN
  SELECT CASE WHEN NEW.type <> 'customer_collection' OR NEW.command_sequence <> 0
    OR NOT EXISTS (SELECT 1 FROM command_log c WHERE c.id = NEW.command_id
      AND c.command_type = 'collect_receivable' AND c.actor_id = NEW.actor_id
      AND c.authorization_policy_version = 'development-single-user-v1')
    THEN RAISE(ABORT, 'Invalid collection command or document type') END;
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM collections c JOIN customer_receivables r ON r.id = c.receivable_id
    JOIN sales s ON s.document_id = r.origin_document_id
    JOIN business_documents sale_doc ON sale_doc.id = s.document_id
    JOIN journal_entries sale_entry ON sale_entry.document_id = sale_doc.id
    JOIN ledger_accounts a ON a.id = r.control_account_id
    JOIN collection_requests request ON request.command_id = NEW.command_id
    WHERE c.document_id = NEW.id AND request.status = 'prepared'
      AND request.receivable_id = c.receivable_id
      AND c.sale_label_snapshot = s.label_snapshot
      AND c.customer_name_snapshot = r.customer_name_snapshot
      AND c.collected_at_utc = request.occurred_at_utc
      AND c.collected_at_utc = NEW.occurred_at_utc
      AND ${_utcSortKey('c.collected_at_utc')} >= ${_utcSortKey('r.issued_at_utc')}
      AND date(NEW.occurred_at_utc, '-5 hours') = NEW.business_date
      AND sale_doc.status = 'posted' AND sale_entry.status = 'posted'
      AND a.class = 'asset' AND a.role = 'customer_receivable' AND a.is_active = 1)
    THEN RAISE(ABORT, 'A collection must match its prepared request and confirmed receivable') END;
  SELECT CASE WHEN EXISTS (SELECT 1 FROM collections current
    JOIN collections previous ON previous.receivable_id = current.receivable_id
    JOIN business_documents d ON d.id = previous.document_id
    WHERE current.document_id = NEW.id AND previous.document_id <> NEW.id AND d.status <> 'draft'
      AND ${_utcSortKey('previous.collected_at_utc')} > ${_utcSortKey('current.collected_at_utc')})
    THEN RAISE(ABORT, 'A collection cannot predate the latest confirmed collection') END;
  SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM collection_parts WHERE collection_id = NEW.id)
    OR (SELECT sum(amount_minor) FROM collection_parts WHERE collection_id = NEW.id)
      <> (SELECT total_minor FROM collections WHERE document_id = NEW.id)
    OR (SELECT min(sequence) FROM collection_parts WHERE collection_id = NEW.id) <> 0
    OR (SELECT max(sequence) + 1 FROM collection_parts WHERE collection_id = NEW.id)
      <> (SELECT count(*) FROM collection_parts WHERE collection_id = NEW.id)
    OR EXISTS (SELECT 1 FROM collection_parts p
      JOIN cash_accounts cash ON cash.id = p.cash_account_id
      JOIN ledger_accounts a ON a.id = cash.ledger_account_id
      JOIN payment_methods method ON method.id = p.payment_method_id
      WHERE p.collection_id = NEW.id AND (cash.is_active <> 1 OR p.cash_account_kind_snapshot <> cash.kind
        OR a.is_active <> 1 OR a.class <> 'asset' OR a.role <> 'cash'
        OR method.is_active <> 1 OR p.payment_method_code_snapshot <> method.code))
    THEN RAISE(ABORT, 'Collection parts must sum exactly and use active money accounts and methods') END;
  SELECT CASE WHEN (SELECT count(*) FROM receivable_settlements WHERE collection_id = NEW.id) <> 1
    OR NOT EXISTS (SELECT 1 FROM receivable_settlements settlement
      JOIN collections c ON c.document_id = settlement.collection_id
      JOIN customer_receivables r ON r.id = c.receivable_id
      WHERE c.document_id = NEW.id AND settlement.receivable_id = c.receivable_id
        AND settlement.amount_minor = c.total_minor
        AND c.total_minor <= r.initial_minor - coalesce((
          SELECT sum(previous.amount_minor) FROM receivable_settlements previous
          JOIN business_documents d ON d.id = previous.collection_id
          WHERE previous.receivable_id = r.id AND previous.collection_id <> NEW.id AND d.status <> 'draft'), 0)
        AND c.remaining_minor = r.initial_minor - c.total_minor - coalesce((
          SELECT sum(previous.amount_minor) FROM receivable_settlements previous
          JOIN business_documents d ON d.id = previous.collection_id
          WHERE previous.receivable_id = r.id AND previous.collection_id <> NEW.id AND d.status <> 'draft'), 0))
    THEN RAISE(ABORT, 'A settlement must apply the exact collection without overpaying its receivable') END;
  SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM journal_entries e
    WHERE e.document_id = NEW.id AND e.status = 'draft' AND e.cost_completeness = 'not_applicable')
    THEN RAISE(ABORT, 'Prepare the collection journal before posting') END;
  SELECT CASE WHEN (SELECT count(*) FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id
      WHERE e.document_id = NEW.id) <> 1 + (SELECT count(DISTINCT a.ledger_account_id)
        FROM collection_parts p JOIN cash_accounts a ON a.id = p.cash_account_id
        WHERE p.collection_id = NEW.id)
    OR NOT EXISTS (SELECT 1 FROM journal_lines l
    JOIN journal_entries e ON e.id = l.entry_id
    JOIN collections c ON c.document_id = e.document_id
    JOIN customer_receivables r ON r.id = c.receivable_id
    WHERE e.document_id = NEW.id AND l.account_id = r.control_account_id
      AND l.credit_minor = c.total_minor AND l.debit_minor = 0)
    OR EXISTS (SELECT 1 FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id
      JOIN collections c ON c.document_id = e.document_id
      JOIN customer_receivables r ON r.id = c.receivable_id
      WHERE e.document_id = NEW.id AND NOT (
        (l.account_id = r.control_account_id AND l.credit_minor = c.total_minor AND l.debit_minor = 0)
        OR (l.credit_minor = 0 AND l.debit_minor > 0 AND EXISTS (
          SELECT 1 FROM collection_parts p JOIN cash_accounts a ON a.id = p.cash_account_id
          WHERE p.collection_id = NEW.id AND a.ledger_account_id = l.account_id))))
    OR EXISTS (SELECT 1 FROM collection_parts p JOIN cash_accounts a ON a.id = p.cash_account_id
      WHERE p.collection_id = NEW.id AND (SELECT coalesce(sum(l.debit_minor), 0)
        FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id
        WHERE e.document_id = NEW.id AND l.account_id = a.ledger_account_id)
        <> (SELECT sum(part.amount_minor) FROM collection_parts part
          JOIN cash_accounts other ON other.id = part.cash_account_id
          WHERE part.collection_id = NEW.id AND other.ledger_account_id = a.ledger_account_id))
    OR (SELECT sum(l.credit_minor) FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id
      WHERE e.document_id = NEW.id) <> (SELECT total_minor FROM collections WHERE document_id = NEW.id)
    THEN RAISE(ABORT, 'A collection must debit its exact money accounts and credit only its receivable') END;
END
''',
    ..._freezeCollectionFacts(
      'collections',
      'document_id',
      'existing.document_id = NEW.document_id',
    ),
    ..._freezeCollectionFacts(
      'collection_parts',
      'collection_id',
      'existing.id = NEW.id OR (existing.collection_id = NEW.collection_id AND existing.sequence = NEW.sequence)',
    ),
    ..._freezeCollectionFacts(
      'receivable_settlements',
      'collection_id',
      'existing.id = NEW.id OR existing.collection_id = NEW.collection_id',
    ),
    ..._freezeCollectionJournal(),
    ..._freezeCollectionCatalogs(),
  ]);

  /// Released V1 through V4 remain permanent inputs; payments append facts.
  static final List<String> migration5Statements = List<String>.unmodifiable([
    '''
CREATE TABLE supplier_payment_requests (
  command_id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(command_id)) > 0),
  canonical_payload TEXT NOT NULL CHECK (length(trim(canonical_payload)) > 0),
  payable_id TEXT NOT NULL REFERENCES obligations(id) ON DELETE RESTRICT,
  occurred_at_utc TEXT NOT NULL CHECK (${_collectionUtc('occurred_at_utc')}),
  prepared_at_utc TEXT NOT NULL CHECK (${_collectionUtc('prepared_at_utc')}),
  status TEXT NOT NULL CHECK (status IN ('prepared', 'rejected', 'cancelled', 'confirmed')),
  rejection_reason TEXT,
  CHECK ((status IN ('prepared', 'confirmed') AND rejection_reason IS NULL)
    OR (status IN ('rejected', 'cancelled') AND rejection_reason IS NOT NULL
      AND length(trim(rejection_reason)) > 0))
)
''',
    '''
CREATE TABLE supplier_payments (
  document_id TEXT PRIMARY KEY NOT NULL REFERENCES business_documents(id) ON DELETE RESTRICT,
  payable_id TEXT NOT NULL REFERENCES obligations(id) ON DELETE RESTRICT,
  purchase_label_snapshot TEXT NOT NULL CHECK (length(trim(purchase_label_snapshot)) BETWEEN 1 AND 160),
  supplier_name_snapshot TEXT NOT NULL CHECK (length(trim(supplier_name_snapshot)) BETWEEN 1 AND 160),
  paid_at_utc TEXT NOT NULL CHECK (${_collectionUtc('paid_at_utc')}),
  total_minor INTEGER NOT NULL CHECK (typeof(total_minor) = 'integer' AND total_minor > 0),
  remaining_minor INTEGER NOT NULL CHECK (typeof(remaining_minor) = 'integer' AND remaining_minor >= 0)
)
''',
    '''
CREATE TABLE supplier_payment_parts (
  id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(id)) > 0),
  supplier_payment_id TEXT NOT NULL REFERENCES supplier_payments(document_id) ON DELETE RESTRICT,
  sequence INTEGER NOT NULL CHECK (typeof(sequence) = 'integer' AND sequence >= 0),
  cash_account_id TEXT NOT NULL REFERENCES cash_accounts(id) ON DELETE RESTRICT,
  payment_method_id TEXT NOT NULL REFERENCES payment_methods(id) ON DELETE RESTRICT,
  cash_account_name_snapshot TEXT NOT NULL CHECK (length(trim(cash_account_name_snapshot)) BETWEEN 1 AND 160),
  cash_account_kind_snapshot TEXT NOT NULL CHECK (cash_account_kind_snapshot IN ('cash', 'bank', 'mobile', 'clearing')),
  payment_method_code_snapshot TEXT NOT NULL CHECK (length(trim(payment_method_code_snapshot)) BETWEEN 1 AND 32),
  payment_method_name_snapshot TEXT NOT NULL CHECK (length(trim(payment_method_name_snapshot)) BETWEEN 1 AND 160),
  amount_minor INTEGER NOT NULL CHECK (typeof(amount_minor) = 'integer' AND amount_minor > 0),
  UNIQUE (supplier_payment_id, sequence)
)
''',
    '''
CREATE TABLE payable_settlements (
  id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(id)) > 0),
  payable_id TEXT NOT NULL REFERENCES obligations(id) ON DELETE RESTRICT,
  supplier_payment_id TEXT NOT NULL UNIQUE REFERENCES supplier_payments(document_id) ON DELETE RESTRICT,
  amount_minor INTEGER NOT NULL CHECK (typeof(amount_minor) = 'integer' AND amount_minor > 0)
)
''',
    'CREATE INDEX idx_supplier_payments_payable ON supplier_payments(payable_id)',
    'CREATE INDEX idx_supplier_payment_parts_cash ON supplier_payment_parts(cash_account_id)',
    'CREATE INDEX idx_settlements_payable ON payable_settlements(payable_id)',
    '''
CREATE TRIGGER supplier_payment_requests_validate_insert
BEFORE INSERT ON supplier_payment_requests
BEGIN
  SELECT CASE WHEN NEW.status <> 'prepared'
    OR EXISTS (SELECT 1 FROM supplier_payment_requests WHERE command_id = NEW.command_id)
    OR EXISTS (SELECT 1 FROM command_log WHERE id = NEW.command_id)
    OR EXISTS (SELECT 1 FROM sale_confirmations WHERE command_id = NEW.command_id)
    OR EXISTS (SELECT 1 FROM collection_requests WHERE command_id = NEW.command_id)
    THEN RAISE(ABORT, 'Create a unique prepared supplier_payment request') END;
  SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM obligations r
    JOIN business_documents d ON d.id = r.origin_document_id
    JOIN journal_entries j ON j.document_id = d.id
    WHERE r.id = NEW.payable_id AND d.status = 'posted' AND j.status = 'posted')
    THEN RAISE(ABORT, 'A supplier_payment request requires a confirmed supplier payable') END;
END
''',
    '''
CREATE TRIGGER supplier_payment_requests_validate_update
BEFORE UPDATE ON supplier_payment_requests
BEGIN
  SELECT CASE WHEN NEW.command_id <> OLD.command_id
    OR NEW.canonical_payload <> OLD.canonical_payload
    OR NEW.payable_id <> OLD.payable_id
    OR NEW.occurred_at_utc <> OLD.occurred_at_utc
    OR NEW.prepared_at_utc <> OLD.prepared_at_utc
    THEN RAISE(ABORT, 'Prepared supplier_payment input is immutable') END;
  SELECT CASE WHEN NOT ((OLD.status = 'prepared' AND NEW.status IN ('rejected', 'confirmed'))
    OR (OLD.status = 'rejected' AND NEW.status = 'cancelled'))
    THEN RAISE(ABORT, 'Invalid supplier_payment request transition') END;
  SELECT CASE WHEN NEW.status IN ('rejected', 'cancelled')
    AND EXISTS (SELECT 1 FROM command_log WHERE id = OLD.command_id)
    THEN RAISE(ABORT, 'A committed supplier_payment cannot be rejected or cancelled') END;
  SELECT CASE WHEN NEW.status = 'cancelled' AND NEW.rejection_reason IS NOT OLD.rejection_reason
    THEN RAISE(ABORT, 'The supplier_payment rejection reason is historical') END;
  SELECT CASE WHEN NEW.status = 'confirmed' AND NOT EXISTS (
    SELECT 1 FROM business_documents d JOIN supplier_payments c ON c.document_id = d.id
    JOIN journal_entries j ON j.document_id = d.id
    WHERE d.command_id = OLD.command_id AND c.payable_id = OLD.payable_id
      AND d.type = 'supplier_payment' AND d.status = 'posted' AND j.status = 'posted')
    THEN RAISE(ABORT, 'Post a supplier_payment and its journal before completing its request') END;
END
''',
    '''
CREATE TRIGGER supplier_payment_requests_no_delete
BEFORE DELETE ON supplier_payment_requests
BEGIN
  SELECT RAISE(ABORT, 'Prepared supplier_payment inputs cannot be deleted');
END
''',
    '''
CREATE TRIGGER supplier_payment_requests_reserve_command_id
BEFORE INSERT ON command_log
WHEN EXISTS (SELECT 1 FROM supplier_payment_requests c WHERE c.command_id = NEW.id
  AND (NEW.command_type <> 'pay_supplier' OR c.status <> 'prepared'))
BEGIN
  SELECT RAISE(ABORT, 'A prepared supplier_payment command identifier is reserved for its supplier_payment');
END
''',
    '''
CREATE TRIGGER sale_confirmations_reject_supplier_payment_command
BEFORE INSERT ON sale_confirmations
WHEN EXISTS (SELECT 1 FROM supplier_payment_requests WHERE command_id = NEW.command_id)
BEGIN
  SELECT RAISE(ABORT, 'SupplierPayment request command identifiers cannot be reused for sales');
END
''',
    '''
CREATE TRIGGER collection_requests_reject_supplier_payment_command
BEFORE INSERT ON collection_requests
WHEN EXISTS (SELECT 1 FROM supplier_payment_requests WHERE command_id = NEW.command_id)
BEGIN
  SELECT RAISE(ABORT, 'Supplier payment command identifiers cannot be reused for collections');
END
''',
    '''
CREATE TRIGGER supplier_payments_documents_insert_as_draft
BEFORE INSERT ON business_documents
WHEN NEW.type = 'supplier_payment' AND NEW.status <> 'draft'
BEGIN
  SELECT RAISE(ABORT, 'Create a supplier_payment document as draft before posting');
END
''',
    '''
CREATE TRIGGER supplier_payments_documents_no_replace
BEFORE INSERT ON business_documents
WHEN EXISTS (SELECT 1 FROM business_documents d
  WHERE (d.id = NEW.id OR (d.command_id = NEW.command_id AND d.command_sequence = NEW.command_sequence))
    AND d.type = 'supplier_payment' AND d.status <> 'draft')
BEGIN
  SELECT RAISE(ABORT, 'Confirmed supplier_payment documents cannot be replaced');
END
''',
    '''
CREATE TRIGGER supplier_payments_documents_no_conflicting_update
BEFORE UPDATE ON business_documents
WHEN EXISTS (SELECT 1 FROM business_documents d
  WHERE d.id <> OLD.id AND (d.id = NEW.id OR
    (d.command_id = NEW.command_id AND d.command_sequence = NEW.command_sequence))
    AND d.type = 'supplier_payment' AND d.status <> 'draft')
BEGIN
  SELECT RAISE(ABORT, 'Confirmed supplier_payment documents cannot be replaced through an update');
END
''',
    '''
CREATE TRIGGER supplier_payments_require_draft_document
BEFORE INSERT ON supplier_payments
WHEN NOT EXISTS (SELECT 1 FROM business_documents WHERE id = NEW.document_id
  AND type = 'supplier_payment' AND status = 'draft')
BEGIN
  SELECT RAISE(ABORT, 'A supplier_payment requires a draft supplier_payment document');
END
''',
    '''
CREATE TRIGGER supplier_payments_validate_document_posting
BEFORE UPDATE OF status ON business_documents
WHEN OLD.status = 'draft' AND NEW.status = 'posted' AND
  (NEW.type = 'supplier_payment' OR EXISTS (SELECT 1 FROM supplier_payments WHERE document_id = NEW.id))
BEGIN
  SELECT CASE WHEN NEW.type <> 'supplier_payment' OR NEW.command_sequence <> 0
    OR NOT EXISTS (SELECT 1 FROM command_log c WHERE c.id = NEW.command_id
      AND c.command_type = 'pay_supplier' AND c.actor_id = NEW.actor_id
      AND c.authorization_policy_version = 'development-single-user-v1')
    THEN RAISE(ABORT, 'Invalid supplier_payment command or document type') END;
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM supplier_payments c JOIN obligations r ON r.id = c.payable_id
    JOIN purchases p ON p.document_id = r.origin_document_id
    JOIN business_documents purchase_doc ON purchase_doc.id = p.document_id
    JOIN journal_entries purchase_entry ON purchase_entry.document_id = purchase_doc.id
    JOIN ledger_accounts a ON a.id = r.control_account_id
    JOIN supplier_payment_requests request ON request.command_id = NEW.command_id
    WHERE c.document_id = NEW.id AND request.status = 'prepared'
      AND request.payable_id = c.payable_id
      AND c.purchase_label_snapshot = coalesce(p.supplier_reference, p.document_id)
      AND c.supplier_name_snapshot = p.supplier_name_snapshot
      AND c.paid_at_utc = request.occurred_at_utc
      AND c.paid_at_utc = NEW.occurred_at_utc
      AND ${_utcSortKey('c.paid_at_utc')} >= ${_utcSortKey('r.issued_at_utc')}
      AND date(NEW.occurred_at_utc, '-5 hours') = NEW.business_date
      AND purchase_doc.status = 'posted' AND purchase_entry.status = 'posted'
      AND r.kind = 'supplier_payable' AND r.counterparty_id = p.supplier_id
      AND a.class = 'liability' AND a.role = 'supplier_payable' AND a.is_active = 1)
    THEN RAISE(ABORT, 'A supplier_payment must match its prepared request and confirmed payable') END;
  SELECT CASE WHEN EXISTS (SELECT 1 FROM supplier_payments current
    JOIN supplier_payments previous ON previous.payable_id = current.payable_id
    JOIN business_documents d ON d.id = previous.document_id
    WHERE current.document_id = NEW.id AND previous.document_id <> NEW.id AND d.status <> 'draft'
      AND ${_utcSortKey('previous.paid_at_utc')} > ${_utcSortKey('current.paid_at_utc')})
    THEN RAISE(ABORT, 'A supplier_payment cannot predate the latest confirmed supplier_payment') END;
  SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM supplier_payment_parts WHERE supplier_payment_id = NEW.id)
    OR ${_supplierBoundedRemainder('(SELECT total_minor FROM supplier_payments WHERE document_id = NEW.id)', 'supplier_payment_parts', 'supplier_payment_id = NEW.id', 'amount_minor', 'sequence')} <> 0
    OR (SELECT min(sequence) FROM supplier_payment_parts WHERE supplier_payment_id = NEW.id) <> 0
    OR (SELECT max(sequence) FROM supplier_payment_parts WHERE supplier_payment_id = NEW.id)
      <> (SELECT count(*) - 1 FROM supplier_payment_parts WHERE supplier_payment_id = NEW.id)
    OR EXISTS (SELECT 1 FROM supplier_payment_parts p
      JOIN cash_accounts cash ON cash.id = p.cash_account_id
      JOIN ledger_accounts a ON a.id = cash.ledger_account_id
      JOIN payment_methods method ON method.id = p.payment_method_id
      WHERE p.supplier_payment_id = NEW.id AND (cash.is_active <> 1 OR cash.is_available <> 1
        OR p.cash_account_kind_snapshot <> cash.kind
        OR a.is_active <> 1 OR a.class <> 'asset' OR a.role <> 'cash'
        OR method.is_active <> 1 OR p.payment_method_code_snapshot <> method.code))
    THEN RAISE(ABORT, 'Payment parts must sum exactly and use active available money accounts and methods') END;
  SELECT CASE WHEN (SELECT count(*) FROM payable_settlements WHERE supplier_payment_id = NEW.id) <> 1
    OR NOT EXISTS (SELECT 1 FROM payable_settlements settlement
      JOIN supplier_payments c ON c.document_id = settlement.supplier_payment_id
      JOIN obligations r ON r.id = c.payable_id
      WHERE c.document_id = NEW.id AND settlement.payable_id = c.payable_id
        AND settlement.amount_minor = c.total_minor
        AND c.total_minor <= ${_supplierPriorPayableRemainder()}
        AND c.remaining_minor = ${_supplierPriorPayableRemainder()} - c.total_minor)
    THEN RAISE(ABORT, 'A settlement must apply the exact payment without overpaying its payable') END;
  SELECT CASE WHEN EXISTS (SELECT 1 FROM supplier_payment_parts p
    JOIN cash_accounts cash ON cash.id = p.cash_account_id
    JOIN journal_lines line ON line.account_id = cash.ledger_account_id
    JOIN journal_entries entry ON entry.id = line.entry_id
    JOIN business_documents doc ON doc.id = entry.document_id
    WHERE p.supplier_payment_id = NEW.id AND doc.id <> NEW.id
      AND doc.status <> 'draft' AND entry.status = 'posted'
      AND ${_utcSortKey('doc.occurred_at_utc')} > ${_utcSortKey('NEW.occurred_at_utc')})
    THEN RAISE(ABORT, 'A payment cannot predate a confirmed money movement of its accounts') END;
  SELECT CASE WHEN ${_supplierMoneyInsufficient()}
    THEN RAISE(ABORT, 'A payment requires a sufficient representable balance in each money account') END;
  SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM journal_entries e
    WHERE e.document_id = NEW.id AND e.status = 'draft' AND e.cost_completeness = 'not_applicable')
    THEN RAISE(ABORT, 'Prepare the supplier_payment journal before posting') END;
  SELECT CASE WHEN (SELECT count(*) FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id
      WHERE e.document_id = NEW.id) <> 1 + (SELECT count(DISTINCT a.ledger_account_id)
        FROM supplier_payment_parts p JOIN cash_accounts a ON a.id = p.cash_account_id
        WHERE p.supplier_payment_id = NEW.id)
    OR (SELECT count(*) FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id
      JOIN supplier_payments c ON c.document_id = e.document_id
      JOIN obligations r ON r.id = c.payable_id
      WHERE e.document_id = NEW.id AND l.account_id = r.control_account_id
        AND l.debit_minor = c.total_minor AND l.credit_minor = 0) <> 1
    OR EXISTS (SELECT 1 FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id
      JOIN supplier_payments c ON c.document_id = e.document_id
      JOIN obligations r ON r.id = c.payable_id
      WHERE e.document_id = NEW.id AND NOT (
        (l.account_id = r.control_account_id AND l.debit_minor = c.total_minor AND l.credit_minor = 0)
        OR (l.debit_minor = 0 AND l.credit_minor > 0 AND EXISTS (
          SELECT 1 FROM supplier_payment_parts p JOIN cash_accounts a ON a.id = p.cash_account_id
          WHERE p.supplier_payment_id = NEW.id AND a.ledger_account_id = l.account_id))))
    OR EXISTS (SELECT 1 FROM supplier_payment_parts p JOIN cash_accounts a ON a.id = p.cash_account_id
      WHERE p.supplier_payment_id = NEW.id AND (
        (SELECT count(*) FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id
          WHERE e.document_id = NEW.id AND l.account_id = a.ledger_account_id) <> 1
        OR ${_supplierBoundedRemainder('(SELECT l.credit_minor FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id WHERE e.document_id = NEW.id AND l.account_id = a.ledger_account_id LIMIT 1)', 'supplier_payment_parts part JOIN cash_accounts other ON other.id = part.cash_account_id', 'part.supplier_payment_id = NEW.id AND other.ledger_account_id = a.ledger_account_id', 'part.amount_minor', 'part.sequence')} <> 0))
    THEN RAISE(ABORT, 'A payment must debit only its payable and credit its exact money accounts') END;
END
''',
    ..._freezeSupplierPaymentFacts(
      'supplier_payments',
      'document_id',
      'existing.document_id = NEW.document_id',
    ),
    ..._freezeSupplierPaymentFacts(
      'supplier_payment_parts',
      'supplier_payment_id',
      'existing.id = NEW.id OR (existing.supplier_payment_id = NEW.supplier_payment_id AND existing.sequence = NEW.sequence)',
    ),
    ..._freezeSupplierPaymentFacts(
      'payable_settlements',
      'supplier_payment_id',
      'existing.id = NEW.id OR existing.supplier_payment_id = NEW.supplier_payment_id',
    ),
    ..._freezeSupplierPaymentJournal(),
  ]);

  /// Quick checkout composes the released sale and collection facts in one
  /// transaction. Its durable parent reserves both internal command IDs.
  static final List<String> migration6Statements = List<String>.unmodifiable([
    '''
CREATE TABLE quick_payment_options (
  id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(id)) > 0),
  label TEXT NOT NULL CHECK (length(trim(label)) BETWEEN 1 AND 160),
  cash_account_id TEXT NOT NULL REFERENCES cash_accounts(id) ON DELETE RESTRICT,
  payment_method_id TEXT NOT NULL REFERENCES payment_methods(id) ON DELETE RESTRICT,
  is_active INTEGER NOT NULL CHECK (typeof(is_active) = 'integer' AND is_active IN (0, 1))
)
''',
    '''
CREATE TABLE quick_sales_accounts (
  id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(id)) > 0),
  label TEXT NOT NULL CHECK (length(label) <= 160),
  revision INTEGER NOT NULL CHECK (typeof(revision) = 'integer' AND revision > 0),
  status TEXT NOT NULL CHECK (status IN ('open', 'prepared', 'confirmed', 'cancelled')),
  updated_at_utc TEXT NOT NULL CHECK (${_collectionUtc('updated_at_utc')}),
  confirmed_document_id TEXT UNIQUE REFERENCES sales(document_id) ON DELETE RESTRICT,
  CHECK ((status = 'confirmed') = (confirmed_document_id IS NOT NULL))
)
''',
    '''
CREATE TABLE quick_sales_lines (
  id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(id)) > 0),
  account_id TEXT NOT NULL REFERENCES quick_sales_accounts(id) ON DELETE RESTRICT,
  sequence INTEGER NOT NULL CHECK (typeof(sequence) = 'integer' AND sequence >= 0),
  product_id TEXT REFERENCES catalog_items(id) ON DELETE RESTRICT,
  quantity_text TEXT NOT NULL,
  unit_price_minor INTEGER CHECK (unit_price_minor IS NULL OR
    (typeof(unit_price_minor) = 'integer' AND unit_price_minor >= 0)),
  payment_option_id TEXT REFERENCES quick_payment_options(id) ON DELETE RESTRICT,
  UNIQUE (account_id, sequence)
)
''',
    '''
CREATE TABLE quick_sale_requests (
  command_id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(command_id)) > 0),
  account_id TEXT NOT NULL REFERENCES quick_sales_accounts(id) ON DELETE RESTRICT,
  account_revision INTEGER NOT NULL CHECK (typeof(account_revision) = 'integer' AND account_revision > 0),
  canonical_payload TEXT NOT NULL CHECK (length(trim(canonical_payload)) > 0),
  occurred_at_utc TEXT NOT NULL CHECK (${_collectionUtc('occurred_at_utc')}),
  prepared_at_utc TEXT NOT NULL CHECK (${_collectionUtc('prepared_at_utc')}),
  status TEXT NOT NULL CHECK (status IN ('prepared', 'executing', 'rejected', 'cancelled', 'confirmed')),
  rejection_reason TEXT,
  sale_command_id TEXT NOT NULL UNIQUE CHECK (length(trim(sale_command_id)) > 0),
  collection_command_id TEXT NOT NULL UNIQUE CHECK (length(trim(collection_command_id)) > 0),
  legacy_draft_id TEXT NOT NULL UNIQUE CHECK (length(trim(legacy_draft_id)) > 0),
  CHECK (command_id <> sale_command_id AND command_id <> collection_command_id
    AND sale_command_id <> collection_command_id),
  CHECK ((status IN ('prepared', 'executing', 'confirmed') AND rejection_reason IS NULL)
    OR (status IN ('rejected', 'cancelled') AND rejection_reason IS NOT NULL
      AND length(trim(rejection_reason)) > 0))
)
''',
    '''
CREATE TABLE quick_sale_line_payments (
  id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(id)) > 0),
  request_id TEXT NOT NULL REFERENCES quick_sale_requests(command_id) ON DELETE RESTRICT,
  sequence INTEGER NOT NULL CHECK (typeof(sequence) = 'integer' AND sequence >= 0),
  source_line_id TEXT NOT NULL UNIQUE REFERENCES quick_sales_lines(id) ON DELETE RESTRICT,
  sale_document_id TEXT NOT NULL REFERENCES sales(document_id) ON DELETE RESTRICT,
  sale_line_id TEXT NOT NULL REFERENCES sale_lines(id) ON DELETE RESTRICT,
  collection_document_id TEXT NOT NULL REFERENCES collections(document_id) ON DELETE RESTRICT,
  product_id TEXT NOT NULL REFERENCES catalog_items(id) ON DELETE RESTRICT,
  product_name_snapshot TEXT NOT NULL CHECK (length(trim(product_name_snapshot)) BETWEEN 1 AND 160),
  quantity INTEGER NOT NULL CHECK (typeof(quantity) = 'integer' AND quantity > 0),
  unit_price_minor INTEGER NOT NULL CHECK (typeof(unit_price_minor) = 'integer' AND unit_price_minor >= 0),
  total_minor INTEGER NOT NULL CHECK (typeof(total_minor) = 'integer' AND total_minor >= 0
    AND typeof(quantity * unit_price_minor) = 'integer' AND quantity * unit_price_minor = total_minor),
  payment_option_id TEXT NOT NULL REFERENCES quick_payment_options(id) ON DELETE RESTRICT,
  payment_option_label_snapshot TEXT NOT NULL CHECK (length(trim(payment_option_label_snapshot)) BETWEEN 1 AND 160),
  cash_account_id TEXT NOT NULL REFERENCES cash_accounts(id) ON DELETE RESTRICT,
  payment_method_id TEXT NOT NULL REFERENCES payment_methods(id) ON DELETE RESTRICT,
  cash_account_name_snapshot TEXT NOT NULL CHECK (length(trim(cash_account_name_snapshot)) BETWEEN 1 AND 160),
  cash_account_kind_snapshot TEXT NOT NULL CHECK (cash_account_kind_snapshot IN ('cash', 'bank', 'mobile', 'clearing')),
  payment_method_code_snapshot TEXT NOT NULL CHECK (length(trim(payment_method_code_snapshot)) BETWEEN 1 AND 32),
  payment_method_name_snapshot TEXT NOT NULL CHECK (length(trim(payment_method_name_snapshot)) BETWEEN 1 AND 160),
  UNIQUE (request_id, sequence)
)
''',
    'CREATE INDEX idx_quick_requests_account ON quick_sale_requests(account_id)',
    'CREATE INDEX idx_quick_line_payments_sale ON quick_sale_line_payments(sale_document_id)',
    '''
CREATE TRIGGER quick_payment_options_no_replace
BEFORE INSERT ON quick_payment_options
WHEN EXISTS (SELECT 1 FROM quick_payment_options WHERE id = NEW.id)
BEGIN
  SELECT RAISE(ABORT, 'Payment options cannot be replaced');
END
''',
    '''
CREATE TRIGGER quick_payment_options_identity_immutable
BEFORE UPDATE ON quick_payment_options
WHEN NEW.id <> OLD.id OR NEW.cash_account_id <> OLD.cash_account_id
  OR NEW.payment_method_id <> OLD.payment_method_id
BEGIN
  SELECT RAISE(ABORT, 'Payment option identity is immutable; archive it instead');
END
''',
    '''
CREATE TRIGGER quick_payment_options_no_delete
BEFORE DELETE ON quick_payment_options
BEGIN
  SELECT RAISE(ABORT, 'Archive payment options instead of deleting them');
END
''',
    '''
CREATE TRIGGER quick_sales_accounts_insert_open
BEFORE INSERT ON quick_sales_accounts
WHEN NEW.status <> 'open' OR NEW.revision <> 1
  OR EXISTS (SELECT 1 FROM quick_sales_accounts WHERE id = NEW.id)
BEGIN
  SELECT RAISE(ABORT, 'Create a new quick account as open at revision one');
END
''',
    '''
CREATE TRIGGER quick_sales_accounts_validate_update
BEFORE UPDATE ON quick_sales_accounts
BEGIN
  SELECT CASE WHEN NEW.id <> OLD.id OR OLD.status IN ('confirmed', 'cancelled')
    THEN RAISE(ABORT, 'Closed quick accounts are immutable') END;
  SELECT CASE WHEN NOT (
    (OLD.status = 'open' AND NEW.status IN ('open', 'prepared', 'cancelled'))
    OR (OLD.status = 'prepared' AND NEW.status IN ('open', 'confirmed')))
    THEN RAISE(ABORT, 'Invalid quick account transition') END;
  SELECT CASE WHEN OLD.status = 'open' AND NEW.status = 'open'
    AND (NEW.revision <> OLD.revision + 1 OR EXISTS (SELECT 1 FROM quick_sale_requests
      WHERE account_id = OLD.id AND status <> 'cancelled'))
    THEN RAISE(ABORT, 'Edit only the latest open quick account') END;
  SELECT CASE WHEN NEW.status = 'prepared' AND (
    NEW.revision <> OLD.revision OR NEW.label <> OLD.label OR NOT EXISTS (
      SELECT 1 FROM quick_sale_requests WHERE account_id = OLD.id
        AND account_revision = OLD.revision AND status = 'prepared'))
    THEN RAISE(ABORT, 'Prepare the exact saved quick account') END;
  SELECT CASE WHEN OLD.status = 'prepared' AND NEW.status = 'open' AND (
    NEW.revision <> OLD.revision + 1 OR NEW.label <> OLD.label OR EXISTS (
      SELECT 1 FROM quick_sale_requests WHERE account_id = OLD.id AND status <> 'cancelled'))
    THEN RAISE(ABORT, 'Only a cancelled rejection may reopen a quick account') END;
  SELECT CASE WHEN NEW.status = 'cancelled' AND (
    NEW.revision <> OLD.revision OR NEW.label <> OLD.label OR EXISTS (
      SELECT 1 FROM quick_sale_requests WHERE account_id = OLD.id AND status <> 'cancelled'))
    THEN RAISE(ABORT, 'Only an unprepared open quick account may be cancelled') END;
  SELECT CASE WHEN NEW.status = 'confirmed' AND (
    NEW.revision <> OLD.revision OR NEW.label <> OLD.label OR NOT EXISTS (
      SELECT 1 FROM quick_sale_requests request JOIN business_documents doc
        ON doc.command_id = request.sale_command_id
      WHERE request.account_id = OLD.id AND request.account_revision = OLD.revision
        AND request.status = 'confirmed' AND doc.id = NEW.confirmed_document_id))
    THEN RAISE(ABORT, 'Complete checkout before closing its quick account') END;
END
''',
    '''
CREATE TRIGGER quick_sales_accounts_no_delete
BEFORE DELETE ON quick_sales_accounts
BEGIN
  SELECT RAISE(ABORT, 'Saved quick accounts cannot be deleted');
END
''',
    ..._freezeQuickDraftLines(),
    '''
CREATE TRIGGER quick_sale_requests_validate_insert
BEFORE INSERT ON quick_sale_requests
BEGIN
  SELECT CASE WHEN NEW.status <> 'prepared'
    OR EXISTS (SELECT 1 FROM quick_sale_requests WHERE command_id IN
      (NEW.command_id, NEW.sale_command_id, NEW.collection_command_id)
      OR sale_command_id IN (NEW.command_id, NEW.sale_command_id, NEW.collection_command_id)
      OR collection_command_id IN (NEW.command_id, NEW.sale_command_id, NEW.collection_command_id)
      OR legacy_draft_id = NEW.legacy_draft_id
      OR (account_id = NEW.account_id AND status <> 'cancelled'))
    OR EXISTS (SELECT 1 FROM command_log WHERE id IN
      (NEW.command_id, NEW.sale_command_id, NEW.collection_command_id))
    OR EXISTS (SELECT 1 FROM sale_confirmations WHERE command_id IN
      (NEW.command_id, NEW.sale_command_id, NEW.collection_command_id))
    OR EXISTS (SELECT 1 FROM collection_requests WHERE command_id IN
      (NEW.command_id, NEW.sale_command_id, NEW.collection_command_id))
    OR EXISTS (SELECT 1 FROM supplier_payment_requests WHERE command_id IN
      (NEW.command_id, NEW.sale_command_id, NEW.collection_command_id))
    OR EXISTS (SELECT 1 FROM sales_drafts WHERE id = NEW.legacy_draft_id)
    THEN RAISE(ABORT, 'Create a unique prepared quick sale and reserve its child identifiers') END;
  SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM quick_sales_accounts
    WHERE id = NEW.account_id AND status = 'open' AND revision = NEW.account_revision
      AND length(trim(label)) BETWEEN 1 AND 160)
    OR NOT EXISTS (SELECT 1 FROM quick_sales_lines WHERE account_id = NEW.account_id)
    THEN RAISE(ABORT, 'Prepare the current saved open quick account') END;
END
''',
    '''
CREATE TRIGGER quick_sale_requests_validate_update
BEFORE UPDATE ON quick_sale_requests
BEGIN
  SELECT CASE WHEN NEW.command_id <> OLD.command_id OR NEW.account_id <> OLD.account_id
    OR NEW.account_revision <> OLD.account_revision OR NEW.canonical_payload <> OLD.canonical_payload
    OR NEW.occurred_at_utc <> OLD.occurred_at_utc OR NEW.prepared_at_utc <> OLD.prepared_at_utc
    OR NEW.sale_command_id <> OLD.sale_command_id OR NEW.collection_command_id <> OLD.collection_command_id
    OR NEW.legacy_draft_id <> OLD.legacy_draft_id
    THEN RAISE(ABORT, 'Prepared quick sale input and child identities are immutable') END;
  SELECT CASE WHEN NOT ((OLD.status = 'prepared' AND NEW.status IN ('executing', 'rejected'))
    OR (OLD.status = 'executing' AND NEW.status = 'confirmed')
    OR (OLD.status = 'rejected' AND NEW.status = 'cancelled'))
    THEN RAISE(ABORT, 'Invalid quick sale request transition') END;
  SELECT CASE WHEN NEW.status IN ('rejected', 'cancelled') AND (
    EXISTS (SELECT 1 FROM command_log WHERE id IN
      (OLD.command_id, OLD.sale_command_id, OLD.collection_command_id))
    OR EXISTS (SELECT 1 FROM sale_confirmations WHERE command_id = OLD.sale_command_id)
    OR EXISTS (SELECT 1 FROM collection_requests WHERE command_id = OLD.collection_command_id)
    OR EXISTS (SELECT 1 FROM quick_sale_line_payments WHERE request_id = OLD.command_id))
    THEN RAISE(ABORT, 'A committed quick sale cannot be rejected or cancelled') END;
  SELECT CASE WHEN NEW.status = 'cancelled' AND NEW.rejection_reason IS NOT OLD.rejection_reason
    THEN RAISE(ABORT, 'Quick sale rejection reasons are historical') END;
  SELECT CASE WHEN NEW.status = 'executing' AND NOT EXISTS (
    SELECT 1 FROM quick_sales_accounts WHERE id = OLD.account_id
      AND status = 'prepared' AND revision = OLD.account_revision)
    THEN RAISE(ABORT, 'Execute only the exact prepared quick account') END;
  SELECT CASE WHEN NEW.status = 'confirmed' AND NOT (${_quickConfirmedResult()})
    THEN RAISE(ABORT, 'Quick checkout requires a posted sale, full collection, and exact line payments') END;
END
''',
    '''
CREATE TRIGGER quick_sale_requests_no_delete
BEFORE DELETE ON quick_sale_requests
BEGIN
  SELECT RAISE(ABORT, 'Durable quick sale requests cannot be deleted');
END
''',
    '''
CREATE TRIGGER quick_sale_requests_reserve_command_ids
BEFORE INSERT ON command_log
WHEN EXISTS (SELECT 1 FROM quick_sale_requests request WHERE
  (NEW.id = request.command_id AND (request.status <> 'executing' OR NEW.command_type <> 'quick_sale'))
  OR (NEW.id = request.sale_command_id AND (request.status <> 'executing' OR NEW.command_type <> 'confirm_sale'))
  OR (NEW.id = request.collection_command_id AND (request.status <> 'executing' OR NEW.command_type <> 'collect_receivable')))
BEGIN
  SELECT RAISE(ABORT, 'Quick checkout identifiers are reserved for its executing parent and children');
END
''',
    for (final table in [
      'sale_confirmations',
      'collection_requests',
      'supplier_payment_requests',
    ])
      '''
CREATE TRIGGER ${table}_respect_quick_command_ids
BEFORE INSERT ON $table
WHEN EXISTS (SELECT 1 FROM quick_sale_requests request WHERE
  NEW.command_id IN (request.command_id, request.sale_command_id, request.collection_command_id)
  AND NOT (request.status = 'executing' AND ${table == 'sale_confirmations'
          ? 'NEW.command_id = request.sale_command_id AND NEW.draft_id = request.legacy_draft_id'
          : table == 'collection_requests'
          ? 'NEW.command_id = request.collection_command_id'
          : '0'}))
BEGIN
  SELECT RAISE(ABORT, 'Only an executing quick checkout may prepare its exact child command');
END
''',
    '''
CREATE TRIGGER sales_drafts_respect_quick_reserved_draft
BEFORE INSERT ON sales_drafts
WHEN EXISTS (SELECT 1 FROM quick_sale_requests request
  WHERE request.legacy_draft_id = NEW.id AND request.status <> 'executing')
BEGIN
  SELECT RAISE(ABORT, 'An internal quick checkout draft is reserved for its executing request');
END
''',
    '''
CREATE TRIGGER quick_line_payments_validate_insert
BEFORE INSERT ON quick_sale_line_payments
BEGIN
  SELECT CASE WHEN EXISTS (SELECT 1 FROM quick_sale_line_payments existing
    WHERE existing.id = NEW.id OR existing.source_line_id = NEW.source_line_id
      OR (existing.request_id = NEW.request_id AND existing.sequence = NEW.sequence))
    THEN RAISE(ABORT, 'Quick sale payment facts cannot be replaced') END;
  SELECT CASE WHEN NOT EXISTS (
    SELECT 1 FROM quick_sale_requests request
    JOIN quick_sales_lines source ON source.account_id = request.account_id
    JOIN quick_payment_options option ON option.id = source.payment_option_id
    JOIN sale_lines line ON line.id = NEW.sale_line_id
    JOIN business_documents sale_doc ON sale_doc.id = line.sale_id
    JOIN journal_entries sale_entry ON sale_entry.document_id = sale_doc.id
    JOIN collections collection ON collection.document_id = NEW.collection_document_id
    JOIN business_documents collection_doc ON collection_doc.id = collection.document_id
    JOIN journal_entries collection_entry ON collection_entry.document_id = collection_doc.id
    JOIN customer_receivables receivable ON receivable.id = collection.receivable_id
    WHERE request.command_id = NEW.request_id AND request.status = 'executing'
      AND source.id = NEW.source_line_id AND source.sequence = NEW.sequence
      AND source.product_id = NEW.product_id AND source.unit_price_minor = NEW.unit_price_minor
      AND trim(source.quantity_text) NOT GLOB '*[^0-9]*'
      AND ltrim(trim(source.quantity_text), '0') = CAST(NEW.quantity AS TEXT)
      AND option.id = NEW.payment_option_id AND option.is_active = 1 AND option.cash_account_id = NEW.cash_account_id
      AND option.payment_method_id = NEW.payment_method_id
      AND line.sale_id = NEW.sale_document_id AND line.product_id = NEW.product_id
      AND line.unit_price_minor = NEW.unit_price_minor AND line.name_snapshot = NEW.product_name_snapshot
      AND sale_doc.command_id = request.sale_command_id AND sale_doc.status = 'posted'
      AND sale_entry.status = 'posted' AND collection_doc.command_id = request.collection_command_id
      AND collection_doc.status = 'posted' AND collection_entry.status = 'posted'
      AND receivable.origin_document_id = sale_doc.id AND collection.remaining_minor = 0
      AND collection.total_minor = receivable.initial_minor
      AND (NEW.total_minor = 0 OR EXISTS (SELECT 1 FROM collection_parts part
        WHERE part.collection_id = collection.document_id
          AND part.cash_account_id = NEW.cash_account_id AND part.payment_method_id = NEW.payment_method_id
          AND part.cash_account_name_snapshot = NEW.cash_account_name_snapshot
          AND part.cash_account_kind_snapshot = NEW.cash_account_kind_snapshot
          AND part.payment_method_code_snapshot = NEW.payment_method_code_snapshot
          AND part.payment_method_name_snapshot = NEW.payment_method_name_snapshot)))
    THEN RAISE(ABORT, 'Quick line payment must match its source and posted sale and collection') END;
END
''',
    for (final action in ['UPDATE', 'DELETE'])
      '''
CREATE TRIGGER quick_line_payments_no_${action.toLowerCase()}
BEFORE $action ON quick_sale_line_payments
BEGIN
  SELECT RAISE(ABORT, 'Quick sale payment history is immutable');
END
''',
  ]);

  /// Paid stock intakes reuse the immutable purchase and payment facts. Their
  /// parent commits only when both children and the captured catalog facts agree.
  static final List<String> migration7Statements = List<String>.unmodifiable([
    '''
CREATE TABLE paid_purchase_requests (
  command_id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(command_id)) > 0),
  canonical_payload TEXT NOT NULL CHECK (json_valid(canonical_payload)),
  occurred_at_utc TEXT NOT NULL CHECK (${_collectionUtc('occurred_at_utc')}),
  prepared_at_utc TEXT NOT NULL CHECK (${_collectionUtc('prepared_at_utc')}),
  status TEXT NOT NULL CHECK (status IN ('prepared', 'executing', 'rejected', 'cancelled', 'confirmed')),
  rejection_reason TEXT,
  purchase_command_id TEXT NOT NULL UNIQUE CHECK (length(trim(purchase_command_id)) > 0),
  payment_command_id TEXT NOT NULL UNIQUE CHECK (length(trim(payment_command_id)) > 0),
  CHECK (command_id <> purchase_command_id AND command_id <> payment_command_id
    AND purchase_command_id <> payment_command_id),
  CHECK ((status IN ('prepared', 'executing', 'confirmed') AND rejection_reason IS NULL)
    OR (status IN ('rejected', 'cancelled') AND rejection_reason IS NOT NULL
      AND length(trim(rejection_reason)) > 0))
)
''',
    '''
CREATE TABLE paid_purchase_entries (
  request_id TEXT PRIMARY KEY NOT NULL REFERENCES paid_purchase_requests(command_id) ON DELETE RESTRICT,
  purchase_document_id TEXT NOT NULL UNIQUE REFERENCES purchases(document_id) ON DELETE RESTRICT,
  payment_document_id TEXT NOT NULL UNIQUE REFERENCES supplier_payments(document_id) ON DELETE RESTRICT,
  product_id TEXT NOT NULL REFERENCES catalog_items(id) ON DELETE RESTRICT,
  product_name_snapshot TEXT NOT NULL CHECK (length(trim(product_name_snapshot)) BETWEEN 1 AND 160),
  sku_snapshot TEXT CHECK (sku_snapshot IS NULL OR length(trim(sku_snapshot)) BETWEEN 1 AND 80),
  category_id TEXT NOT NULL REFERENCES categories(id) ON DELETE RESTRICT,
  category_name_snapshot TEXT NOT NULL CHECK (length(trim(category_name_snapshot)) BETWEEN 1 AND 160),
  supplier_id TEXT NOT NULL REFERENCES counterparties(id) ON DELETE RESTRICT,
  supplier_name_snapshot TEXT NOT NULL CHECK (length(trim(supplier_name_snapshot)) BETWEEN 1 AND 160),
  quantity INTEGER NOT NULL CHECK (typeof(quantity) = 'integer' AND quantity > 0),
  unit_purchase_price_minor INTEGER NOT NULL CHECK (typeof(unit_purchase_price_minor) = 'integer' AND unit_purchase_price_minor > 0),
  list_price_minor INTEGER NOT NULL CHECK (typeof(list_price_minor) = 'integer' AND list_price_minor >= 0
    AND typeof(quantity * list_price_minor) = 'integer'),
  total_cost_minor INTEGER NOT NULL CHECK (typeof(total_cost_minor) = 'integer' AND total_cost_minor > 0
    AND typeof(quantity * unit_purchase_price_minor) = 'integer'
    AND quantity * unit_purchase_price_minor = total_cost_minor),
  payment_option_id TEXT NOT NULL REFERENCES quick_payment_options(id) ON DELETE RESTRICT,
  payment_option_label_snapshot TEXT NOT NULL CHECK (length(trim(payment_option_label_snapshot)) BETWEEN 1 AND 160),
  cash_account_id TEXT NOT NULL REFERENCES cash_accounts(id) ON DELETE RESTRICT,
  payment_method_id TEXT NOT NULL REFERENCES payment_methods(id) ON DELETE RESTRICT,
  cash_account_name_snapshot TEXT NOT NULL CHECK (length(trim(cash_account_name_snapshot)) BETWEEN 1 AND 160),
  cash_account_kind_snapshot TEXT NOT NULL CHECK (cash_account_kind_snapshot IN ('cash', 'bank', 'mobile', 'clearing')),
  payment_method_code_snapshot TEXT NOT NULL CHECK (length(trim(payment_method_code_snapshot)) BETWEEN 1 AND 32),
  payment_method_name_snapshot TEXT NOT NULL CHECK (length(trim(payment_method_name_snapshot)) BETWEEN 1 AND 160)
)
''',
    '''
CREATE TABLE cash_openings (
  document_id TEXT PRIMARY KEY NOT NULL REFERENCES business_documents(id) ON DELETE RESTRICT,
  command_id TEXT NOT NULL UNIQUE REFERENCES command_log(id) ON DELETE RESTRICT,
  cash_account_id TEXT NOT NULL UNIQUE REFERENCES cash_accounts(id) ON DELETE RESTRICT,
  amount_minor INTEGER NOT NULL CHECK (typeof(amount_minor) = 'integer' AND amount_minor > 0),
  occurred_at_utc TEXT NOT NULL CHECK (${_collectionUtc('occurred_at_utc')})
)
''',
    'CREATE INDEX idx_paid_purchase_entries_product ON paid_purchase_entries(product_id)',
    '''
CREATE TRIGGER paid_purchase_requests_validate_insert
BEFORE INSERT ON paid_purchase_requests
BEGIN
  SELECT CASE WHEN NEW.status <> 'prepared'
    OR EXISTS (SELECT 1 FROM paid_purchase_requests WHERE command_id IN
      (NEW.command_id, NEW.purchase_command_id, NEW.payment_command_id)
      OR purchase_command_id IN (NEW.command_id, NEW.purchase_command_id, NEW.payment_command_id)
      OR payment_command_id IN (NEW.command_id, NEW.purchase_command_id, NEW.payment_command_id))
    OR EXISTS (SELECT 1 FROM command_log WHERE id IN
      (NEW.command_id, NEW.purchase_command_id, NEW.payment_command_id))
    OR EXISTS (SELECT 1 FROM sale_confirmations WHERE command_id IN
      (NEW.command_id, NEW.purchase_command_id, NEW.payment_command_id))
    OR EXISTS (SELECT 1 FROM collection_requests WHERE command_id IN
      (NEW.command_id, NEW.purchase_command_id, NEW.payment_command_id))
    OR EXISTS (SELECT 1 FROM supplier_payment_requests WHERE command_id IN
      (NEW.command_id, NEW.purchase_command_id, NEW.payment_command_id))
    OR EXISTS (SELECT 1 FROM quick_sale_requests WHERE command_id IN
      (NEW.command_id, NEW.purchase_command_id, NEW.payment_command_id)
      OR sale_command_id IN (NEW.command_id, NEW.purchase_command_id, NEW.payment_command_id)
      OR collection_command_id IN (NEW.command_id, NEW.purchase_command_id, NEW.payment_command_id))
    THEN RAISE(ABORT, 'Create a unique prepared intake and reserve its child identifiers') END;
END
''',
    '''
CREATE TRIGGER paid_purchase_requests_validate_update
BEFORE UPDATE ON paid_purchase_requests
BEGIN
  SELECT CASE WHEN NEW.command_id <> OLD.command_id OR NEW.canonical_payload <> OLD.canonical_payload
    OR NEW.occurred_at_utc <> OLD.occurred_at_utc OR NEW.prepared_at_utc <> OLD.prepared_at_utc
    OR NEW.purchase_command_id <> OLD.purchase_command_id OR NEW.payment_command_id <> OLD.payment_command_id
    THEN RAISE(ABORT, 'Prepared intake input and child identities are immutable') END;
  SELECT CASE WHEN NOT ((OLD.status = 'prepared' AND NEW.status IN ('executing', 'rejected'))
    OR (OLD.status = 'executing' AND NEW.status = 'confirmed')
    OR (OLD.status = 'rejected' AND NEW.status = 'cancelled'))
    THEN RAISE(ABORT, 'Invalid intake request transition') END;
  SELECT CASE WHEN NEW.status IN ('rejected', 'cancelled') AND (
    EXISTS (SELECT 1 FROM command_log WHERE id IN
      (OLD.command_id, OLD.purchase_command_id, OLD.payment_command_id))
    OR EXISTS (SELECT 1 FROM supplier_payment_requests WHERE command_id = OLD.payment_command_id)
    OR EXISTS (SELECT 1 FROM paid_purchase_entries WHERE request_id = OLD.command_id))
    THEN RAISE(ABORT, 'A committed intake cannot be rejected or cancelled') END;
  SELECT CASE WHEN NEW.status = 'cancelled' AND NEW.rejection_reason IS NOT OLD.rejection_reason
    THEN RAISE(ABORT, 'Intake rejection reasons are historical') END;
  SELECT CASE WHEN NEW.status = 'confirmed' AND NOT (${_paidPurchaseConfirmedResult()})
    THEN RAISE(ABORT, 'An intake requires its posted purchase, full payment and exact history') END;
END
''',
    '''
CREATE TRIGGER paid_purchase_requests_no_delete
BEFORE DELETE ON paid_purchase_requests
BEGIN
  SELECT RAISE(ABORT, 'Durable intake requests cannot be deleted');
END
''',
    '''
CREATE TRIGGER paid_purchase_requests_reserve_command_ids
BEFORE INSERT ON command_log
WHEN EXISTS (SELECT 1 FROM paid_purchase_requests request WHERE
  (NEW.id = request.command_id AND (request.status <> 'executing' OR NEW.command_type <> 'paid_purchase'))
  OR (NEW.id = request.purchase_command_id AND (request.status <> 'executing' OR NEW.command_type <> 'receive_purchase'))
  OR (NEW.id = request.payment_command_id AND (request.status <> 'executing' OR NEW.command_type <> 'pay_supplier')))
BEGIN
  SELECT RAISE(ABORT, 'Intake command identifiers are reserved for its executing parent and children');
END
''',
    for (final table in [
      'sale_confirmations',
      'collection_requests',
      'supplier_payment_requests',
    ])
      '''
CREATE TRIGGER ${table}_respect_intake_command_ids
BEFORE INSERT ON $table
WHEN EXISTS (SELECT 1 FROM paid_purchase_requests request WHERE
  NEW.command_id IN (request.command_id, request.purchase_command_id, request.payment_command_id)
  AND NOT (${table == 'supplier_payment_requests' ? "request.status = 'executing' AND NEW.command_id = request.payment_command_id" : '0'}))
BEGIN
  SELECT RAISE(ABORT, 'Only an executing intake may prepare its exact payment command');
END
''',
    '''
CREATE TRIGGER quick_sale_requests_respect_intake_command_ids
BEFORE INSERT ON quick_sale_requests
WHEN EXISTS (SELECT 1 FROM paid_purchase_requests request WHERE
  request.command_id IN (NEW.command_id, NEW.sale_command_id, NEW.collection_command_id)
  OR request.purchase_command_id IN (NEW.command_id, NEW.sale_command_id, NEW.collection_command_id)
  OR request.payment_command_id IN (NEW.command_id, NEW.sale_command_id, NEW.collection_command_id))
BEGIN
  SELECT RAISE(ABORT, 'Quick checkout cannot use a reserved intake command identifier');
END
''',
    '''
CREATE TRIGGER paid_purchase_entries_validate_insert
BEFORE INSERT ON paid_purchase_entries
BEGIN
  SELECT CASE WHEN EXISTS (SELECT 1 FROM paid_purchase_entries WHERE request_id = NEW.request_id
    OR purchase_document_id = NEW.purchase_document_id OR payment_document_id = NEW.payment_document_id)
    THEN RAISE(ABORT, 'Intake history cannot be replaced') END;
  SELECT CASE WHEN NOT (${_paidPurchaseEntryMatches('NEW')})
    THEN RAISE(ABORT, 'Intake history must match captured input and its posted full purchase payment') END;
END
''',
    for (final action in ['UPDATE', 'DELETE'])
      '''
CREATE TRIGGER paid_purchase_entries_no_${action.toLowerCase()}
BEFORE $action ON paid_purchase_entries
BEGIN
  SELECT RAISE(ABORT, 'Paid intake history is immutable');
END
''',
    '''
CREATE TRIGGER cash_openings_documents_insert_as_draft
BEFORE INSERT ON business_documents
WHEN NEW.type = 'cash_opening' AND NEW.status <> 'draft'
BEGIN
  SELECT RAISE(ABORT, 'Create a cash opening document as draft before posting');
END
''',
    '''
CREATE TRIGGER cash_openings_validate_insert
BEFORE INSERT ON cash_openings
BEGIN
  SELECT CASE WHEN EXISTS (SELECT 1 FROM cash_openings WHERE document_id = NEW.document_id
    OR command_id = NEW.command_id OR cash_account_id = NEW.cash_account_id)
    THEN RAISE(ABORT, 'A money account may have only one immutable opening') END;
  SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM business_documents d
    JOIN command_log c ON c.id = d.command_id JOIN cash_accounts a ON a.id = NEW.cash_account_id
    JOIN ledger_accounts ledger ON ledger.id = a.ledger_account_id
    WHERE d.id = NEW.document_id AND d.command_id = NEW.command_id
      AND d.type = 'cash_opening' AND d.status = 'draft' AND d.occurred_at_utc = NEW.occurred_at_utc
      AND c.command_type = 'cash_opening' AND c.actor_id = d.actor_id
      AND c.authorization_policy_version = 'development-single-user-v1'
      AND a.is_active = 1 AND a.is_available = 1 AND ledger.is_active = 1
      AND ledger.class = 'asset' AND ledger.role = 'cash')
    OR EXISTS (SELECT 1 FROM cash_accounts cash JOIN journal_lines line ON line.account_id = cash.ledger_account_id
      JOIN journal_entries entry ON entry.id = line.entry_id AND entry.status = 'posted'
      JOIN business_documents document ON document.id = entry.document_id AND document.status = 'posted'
      WHERE cash.id = NEW.cash_account_id)
    THEN RAISE(ABORT, 'Record an explicit opening only before a money account has posted movements') END;
END
''',
    '''
CREATE TRIGGER cash_openings_validate_document_posting
BEFORE UPDATE OF status ON business_documents
WHEN OLD.status = 'draft' AND NEW.status = 'posted' AND
  (NEW.type = 'cash_opening' OR EXISTS (SELECT 1 FROM cash_openings WHERE document_id = NEW.id))
BEGIN
  SELECT CASE WHEN NEW.type <> 'cash_opening' OR NEW.command_sequence <> 0
    OR date(NEW.occurred_at_utc, '-5 hours') <> NEW.business_date
    OR NOT EXISTS (SELECT 1 FROM cash_openings opening JOIN command_log command ON command.id = opening.command_id
      JOIN cash_accounts cash ON cash.id = opening.cash_account_id
      JOIN ledger_accounts account ON account.id = cash.ledger_account_id
      WHERE opening.document_id = NEW.id AND opening.command_id = NEW.command_id
        AND opening.occurred_at_utc = NEW.occurred_at_utc AND command.command_type = 'cash_opening'
        AND command.actor_id = NEW.actor_id AND command.authorization_policy_version = 'development-single-user-v1'
        AND cash.is_active = 1 AND cash.is_available = 1 AND account.is_active = 1
        AND account.class = 'asset' AND account.role = 'cash')
    THEN RAISE(ABORT, 'Cash opening document or money account is invalid') END;
  SELECT CASE WHEN EXISTS (SELECT 1 FROM cash_openings opening JOIN cash_accounts cash ON cash.id = opening.cash_account_id
    JOIN journal_lines line ON line.account_id = cash.ledger_account_id
    JOIN journal_entries entry ON entry.id = line.entry_id AND entry.status = 'posted'
    JOIN business_documents document ON document.id = entry.document_id AND document.status = 'posted'
    WHERE opening.document_id = NEW.id AND document.id <> NEW.id)
    THEN RAISE(ABORT, 'A cash opening must precede all posted money account movements') END;
  SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM journal_entries WHERE document_id = NEW.id
    AND status = 'draft' AND cost_completeness = 'not_applicable')
    OR (SELECT count(*) FROM journal_lines line JOIN journal_entries entry ON entry.id = line.entry_id
      WHERE entry.document_id = NEW.id) <> 2
    OR NOT EXISTS (SELECT 1 FROM cash_openings opening JOIN cash_accounts cash ON cash.id = opening.cash_account_id
      JOIN journal_entries entry ON entry.document_id = opening.document_id
      JOIN journal_lines line ON line.entry_id = entry.id
      WHERE opening.document_id = NEW.id AND line.account_id = cash.ledger_account_id
        AND line.debit_minor = opening.amount_minor AND line.credit_minor = 0)
    OR NOT EXISTS (SELECT 1 FROM cash_openings opening JOIN journal_entries entry ON entry.document_id = opening.document_id
      JOIN journal_lines line ON line.entry_id = entry.id JOIN ledger_accounts account ON account.id = line.account_id
      WHERE opening.document_id = NEW.id AND account.id = 'system:opening-equity' AND account.class = 'equity'
        AND account.role = 'opening_balance' AND account.is_active = 1
        AND line.debit_minor = 0 AND line.credit_minor = opening.amount_minor)
    THEN RAISE(ABORT, 'An explicit cash opening debits money and credits opening equity exactly once') END;
END
''',
    ..._freezeCashOpeningFacts(),
  ]);

  /// Initial balances are independent facts, never fabricated purchases/payments.
  /// Released v1-v7 tables and migrations remain unchanged.
  static final List<String> migration8Statements = List.unmodifiable([
    '''
CREATE TABLE inventory_openings (
  document_id TEXT PRIMARY KEY NOT NULL REFERENCES business_documents(id) ON DELETE RESTRICT,
  command_id TEXT NOT NULL UNIQUE REFERENCES command_log(id) ON DELETE RESTRICT,
  profile_id TEXT NOT NULL UNIQUE REFERENCES app_profile(profile_id) ON DELETE RESTRICT,
  source_name TEXT NOT NULL CHECK (length(trim(source_name)) > 0),
  source_sha256 TEXT NOT NULL CHECK (length(source_sha256) = 64 AND source_sha256 NOT GLOB '*[^0-9a-fA-F]*'),
  snapshot_sha256 TEXT NOT NULL CHECK (length(snapshot_sha256) = 64 AND snapshot_sha256 NOT GLOB '*[^0-9a-fA-F]*'),
  occurred_at_utc TEXT NOT NULL CHECK (${_collectionUtc('occurred_at_utc')}),
  total_cost_minor INTEGER NOT NULL CHECK (typeof(total_cost_minor) = 'integer' AND total_cost_minor >= 0)
)
''',
    '''
CREATE TABLE inventory_opening_items (
  id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(id)) > 0),
  opening_id TEXT NOT NULL REFERENCES inventory_openings(document_id) ON DELETE RESTRICT,
  sequence INTEGER NOT NULL CHECK (typeof(sequence) = 'integer' AND sequence >= 0),
  source_product_id TEXT NOT NULL CHECK (length(trim(source_product_id)) > 0),
  product_id TEXT NOT NULL UNIQUE REFERENCES catalog_items(id) ON DELETE RESTRICT,
  name_snapshot TEXT NOT NULL CHECK (length(trim(name_snapshot)) BETWEEN 1 AND 160),
  category_id TEXT REFERENCES categories(id) ON DELETE RESTRICT,
  supplier_id TEXT REFERENCES counterparties(id) ON DELETE RESTRICT,
  unit_price_minor INTEGER NOT NULL CHECK (typeof(unit_price_minor) = 'integer' AND unit_price_minor >= 0),
  unit_cost_minor INTEGER NOT NULL CHECK (typeof(unit_cost_minor) = 'integer' AND unit_cost_minor >= 0),
  quantity INTEGER NOT NULL CHECK (typeof(quantity) = 'integer' AND quantity >= 0),
  total_cost_minor INTEGER NOT NULL CHECK (typeof(total_cost_minor) = 'integer' AND total_cost_minor >= 0),
  zero_cost_confirmed INTEGER NOT NULL CHECK (typeof(zero_cost_confirmed) = 'integer' AND zero_cost_confirmed IN (0, 1)),
  CHECK (unit_cost_minor > 0 OR zero_cost_confirmed = 1),
  CHECK (typeof(quantity * unit_cost_minor) = 'integer' AND total_cost_minor = quantity * unit_cost_minor),
  UNIQUE (opening_id, sequence),
  UNIQUE (opening_id, source_product_id)
)
''',
    '''
CREATE TABLE inventory_opening_allocations (
  id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(id)) > 0),
  sale_line_id TEXT NOT NULL REFERENCES sale_lines(id) ON DELETE RESTRICT,
  opening_item_id TEXT NOT NULL REFERENCES inventory_opening_items(id) ON DELETE RESTRICT,
  sequence INTEGER NOT NULL CHECK (typeof(sequence) = 'integer' AND sequence >= 0),
  quantity INTEGER NOT NULL CHECK (typeof(quantity) = 'integer' AND quantity > 0),
  cost_minor INTEGER NOT NULL CHECK (typeof(cost_minor) = 'integer' AND cost_minor >= 0),
  UNIQUE (sale_line_id, sequence),
  UNIQUE (sale_line_id, opening_item_id)
)
''',
    'CREATE INDEX idx_opening_allocations_item ON inventory_opening_allocations(opening_item_id)',
    '''
CREATE VIEW inventory_opening_layers AS
SELECT item.id, item.product_id, item.quantity AS initial_quantity,
  item.total_cost_minor, opening.occurred_at_utc AS acquired_at_utc,
  opening.document_id, opening.document_id AS opening_id, 0 AS fifo_sequence,
  'opening' AS source_kind, item.id AS source_id
FROM inventory_opening_items item
JOIN inventory_openings opening ON opening.document_id = item.opening_id
JOIN business_documents document ON document.id = opening.document_id AND document.status = 'posted'
JOIN journal_entries entry ON entry.document_id = document.id AND entry.status = 'posted'
WHERE item.quantity > 0
''',
    '''
CREATE VIEW all_sale_cost_allocations AS
SELECT id, sale_line_id, sequence, quantity, cost_minor,
  'purchase' AS source_kind, cost_layer_id AS source_id FROM sale_cost_allocations
UNION ALL
SELECT id, sale_line_id, sequence, quantity, cost_minor,
  'opening' AS source_kind, opening_item_id AS source_id FROM inventory_opening_allocations
''',
    '''
CREATE TRIGGER inventory_openings_documents_insert_as_draft
BEFORE INSERT ON business_documents
WHEN NEW.type = 'inventory_opening' AND NEW.status <> 'draft'
BEGIN
  SELECT RAISE(ABORT, 'Create an inventory opening as draft before posting');
END
''',
    '''
CREATE TRIGGER inventory_openings_validate_insert
BEFORE INSERT ON inventory_openings
BEGIN
  SELECT CASE WHEN EXISTS (SELECT 1 FROM inventory_openings WHERE document_id = NEW.document_id
    OR command_id = NEW.command_id OR profile_id = NEW.profile_id)
    THEN RAISE(ABORT, 'A profile has only one immutable initial inventory opening') END;
  SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM business_documents document
    JOIN command_log command ON command.id = document.command_id
    WHERE document.id = NEW.document_id AND document.type = 'inventory_opening'
      AND document.status = 'draft' AND document.command_sequence = 0
      AND document.command_id = NEW.command_id AND document.profile_id = NEW.profile_id
      AND document.occurred_at_utc = NEW.occurred_at_utc
      AND document.source_kind IN ('legacy', 'synthetic')
      AND document.date_quality = 'reconstructed'
      AND command.command_type = 'inventory_opening' AND command.actor_id = document.actor_id
      AND command.authorization_policy_version = 'development-single-user-v1')
    THEN RAISE(ABORT, 'An initial inventory requires its matching import command and draft document') END;
END
''',
    '''
CREATE TRIGGER inventory_openings_validate_document_posting
BEFORE UPDATE OF status ON business_documents
WHEN OLD.status = 'draft' AND NEW.status = 'posted' AND
  (NEW.type = 'inventory_opening' OR EXISTS (SELECT 1 FROM inventory_openings WHERE document_id = NEW.id))
BEGIN
  SELECT CASE WHEN NEW.type <> 'inventory_opening' OR NEW.command_sequence <> 0
    OR NEW.source_kind NOT IN ('legacy', 'synthetic') OR NEW.date_quality <> 'reconstructed'
    OR date(NEW.occurred_at_utc, '-5 hours') <> NEW.business_date
    OR NOT EXISTS (SELECT 1 FROM inventory_openings opening JOIN command_log command ON command.id = opening.command_id
      WHERE opening.document_id = NEW.id AND opening.command_id = NEW.command_id
        AND opening.profile_id = NEW.profile_id AND opening.occurred_at_utc = NEW.occurred_at_utc
        AND command.command_type = 'inventory_opening' AND command.actor_id = NEW.actor_id
        AND command.authorization_policy_version = 'development-single-user-v1')
    THEN RAISE(ABORT, 'Invalid initial inventory document or command') END;
  SELECT CASE WHEN EXISTS (SELECT 1 FROM business_documents WHERE id <> NEW.id AND status <> 'draft')
    OR EXISTS (SELECT 1 FROM inventory_movements) OR EXISTS (SELECT 1 FROM cost_layers)
    OR EXISTS (SELECT 1 FROM sales) OR EXISTS (SELECT 1 FROM purchases)
    OR NOT EXISTS (SELECT 1 FROM inventory_opening_items WHERE opening_id = NEW.id)
    OR (SELECT count(*) FROM catalog_items) <> (SELECT count(*) FROM inventory_opening_items WHERE opening_id = NEW.id)
    THEN RAISE(ABORT, 'Initial inventory must start in an unused profile and represent its entire catalog') END;
  SELECT CASE WHEN EXISTS (SELECT 1 FROM inventory_opening_items item
    JOIN catalog_items product ON product.id = item.product_id
    LEFT JOIN categories category ON category.id = item.category_id
    LEFT JOIN counterparties supplier ON supplier.id = item.supplier_id
    WHERE item.opening_id = NEW.id AND (product.is_active <> 1 OR product.name <> item.name_snapshot
      OR product.list_price_minor <> item.unit_price_minor OR product.category_id IS NOT item.category_id
      OR (item.category_id IS NOT NULL AND category.is_active <> 1)
      OR (item.supplier_id IS NOT NULL AND (supplier.is_active <> 1 OR supplier.is_supplier <> 1))))
    OR (SELECT sum(total_cost_minor) FROM inventory_opening_items WHERE opening_id = NEW.id)
      <> (SELECT total_cost_minor FROM inventory_openings WHERE document_id = NEW.id)
    THEN RAISE(ABORT, 'Opening quantities, costs and catalog snapshots must agree exactly') END;
  SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM journal_entries WHERE document_id = NEW.id
    AND status = 'draft' AND cost_completeness = 'complete')
    OR (SELECT count(*) FROM journal_lines line JOIN journal_entries entry ON entry.id = line.entry_id
      WHERE entry.document_id = NEW.id) <> (SELECT CASE WHEN total_cost_minor > 0 THEN 2 ELSE 0 END
        FROM inventory_openings WHERE document_id = NEW.id)
    OR EXISTS (SELECT 1 FROM inventory_openings opening WHERE opening.document_id = NEW.id AND opening.total_cost_minor > 0
      AND (NOT EXISTS (SELECT 1 FROM journal_entries entry JOIN journal_lines line ON line.entry_id = entry.id
          JOIN ledger_accounts account ON account.id = line.account_id
          WHERE entry.document_id = NEW.id AND account.role = 'inventory' AND account.class = 'asset'
            AND account.is_active = 1 AND line.debit_minor = opening.total_cost_minor AND line.credit_minor = 0)
        OR NOT EXISTS (SELECT 1 FROM journal_entries entry JOIN journal_lines line ON line.entry_id = entry.id
          JOIN ledger_accounts account ON account.id = line.account_id
          WHERE entry.document_id = NEW.id AND account.id = 'system:opening-equity' AND account.class = 'equity'
            AND account.role = 'opening_balance' AND account.is_active = 1
            AND line.credit_minor = opening.total_cost_minor AND line.debit_minor = 0)))
    THEN RAISE(ABORT, 'An initial inventory debits stock and credits opening equity without money or debt') END;
END
''',
    'DROP TRIGGER entries_validate_posting',
    '''
CREATE TRIGGER entries_validate_posting
BEFORE UPDATE OF status ON journal_entries
WHEN OLD.status = 'draft' AND NEW.status = 'posted'
BEGIN
  SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM business_documents WHERE id = NEW.document_id AND status = 'posted')
    THEN RAISE(ABORT, 'Post the source document before its entry') END;
  SELECT CASE WHEN (SELECT count(*) FROM journal_lines WHERE entry_id = NEW.id) < 2
    AND NOT EXISTS (SELECT 1 FROM inventory_openings opening JOIN business_documents document ON document.id = opening.document_id
      WHERE opening.document_id = NEW.document_id AND opening.total_cost_minor = 0
        AND document.type = 'inventory_opening' AND document.status = 'posted'
        AND NEW.cost_completeness = 'complete'
        AND NOT EXISTS (SELECT 1 FROM journal_lines WHERE entry_id = NEW.id))
    THEN RAISE(ABORT, 'A posted entry needs at least two lines except a confirmed zero value inventory opening') END;
  SELECT CASE WHEN (SELECT sum(debit_minor) <> sum(credit_minor) FROM journal_lines WHERE entry_id = NEW.id)
    THEN RAISE(ABORT, 'A posted entry must balance') END;
END
''',
    '''
CREATE TRIGGER purchases_respect_inventory_opening_chronology
BEFORE UPDATE OF status ON business_documents
WHEN OLD.status = 'draft' AND NEW.status = 'posted' AND NEW.type = 'purchase_receipt'
BEGIN
  SELECT CASE WHEN EXISTS (SELECT 1 FROM purchase_lines line
    JOIN inventory_opening_items item ON item.product_id = line.product_id
    JOIN inventory_openings opening ON opening.document_id = item.opening_id
    JOIN business_documents document ON document.id = opening.document_id AND document.status = 'posted'
    JOIN journal_entries entry ON entry.document_id = document.id AND entry.status = 'posted'
    WHERE line.purchase_id = NEW.id AND ${_utcSortKey('opening.occurred_at_utc')} > ${_utcSortKey('NEW.occurred_at_utc')})
    THEN RAISE(ABORT, 'A purchase cannot precede its product initial inventory opening') END;
END
''',
    'DROP TRIGGER sale_cost_allocations_validate_insert',
    _openingAwarePurchaseAllocationTrigger(),
    '''
CREATE TRIGGER inventory_opening_allocations_validate_insert
BEFORE INSERT ON inventory_opening_allocations
BEGIN
  SELECT CASE WHEN EXISTS (SELECT 1 FROM inventory_opening_allocations WHERE id = NEW.id
    OR (sale_line_id = NEW.sale_line_id AND sequence = NEW.sequence)
    OR (sale_line_id = NEW.sale_line_id AND opening_item_id = NEW.opening_item_id))
    THEN RAISE(ABORT, 'Opening cost allocations cannot be replaced') END;
  SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM sale_lines line JOIN sales sale ON sale.document_id = line.sale_id
    JOIN business_documents document ON document.id = sale.document_id
    JOIN inventory_opening_layers opening ON opening.id = NEW.opening_item_id
    WHERE line.id = NEW.sale_line_id AND line.product_id = opening.product_id
      AND document.type = 'credit_sale' AND document.status = 'draft'
      AND ${_utcSortKey('opening.acquired_at_utc')} <= ${_utcSortKey('sale.sold_at_utc')})
    THEN RAISE(ABORT, 'Allocate only an effective confirmed opening for the matching sale product') END;
  SELECT CASE WHEN NEW.sequence <> (SELECT count(*) FROM all_sale_cost_allocations WHERE sale_line_id = NEW.sale_line_id)
    OR NEW.quantity > (SELECT line.quantity - coalesce((SELECT sum(allocation.quantity) FROM all_sale_cost_allocations allocation
      WHERE allocation.sale_line_id = line.id), 0) FROM sale_lines line WHERE line.id = NEW.sale_line_id)
    OR NEW.quantity > (SELECT opening.quantity - coalesce((SELECT sum(allocation.quantity) FROM inventory_opening_allocations allocation
      WHERE allocation.opening_item_id = opening.id), 0) FROM inventory_opening_items opening WHERE opening.id = NEW.opening_item_id)
    THEN RAISE(ABORT, 'An opening allocation cannot exceed remaining sale or opening quantities') END;
  SELECT CASE WHEN NEW.cost_minor <> (SELECT NEW.quantity * unit_cost_minor FROM inventory_opening_items WHERE id = NEW.opening_item_id)
    THEN RAISE(ABORT, 'An opening allocation must retain its exact confirmed unit cost') END;
END
''',
    for (final action in ['UPDATE', 'DELETE'])
      '''
CREATE TRIGGER inventory_opening_allocations_no_${action.toLowerCase()}
BEFORE $action ON inventory_opening_allocations
BEGIN
  SELECT RAISE(ABORT, 'Opening cost allocations are immutable; roll back an unfinished operation');
END
''',
    'DROP TRIGGER sales_validate_document_posting',
    _openingAwareSalePostingTrigger(),
    ..._freezeInventoryOpeningFacts(),
  ]);

  static String _treasuryPositive(String prefix) =>
      '(max(0,${prefix}cash_minor)+max(0,${prefix}nequi_minor)'
      '+max(0,${prefix}reserve_minor)+${prefix}receivables_minor)';

  static String _treasuryNegative(String prefix) =>
      '(max(0,-${prefix}cash_minor)+max(0,-${prefix}nequi_minor)'
      '+max(0,-${prefix}reserve_minor))';

  /// Legacy balances are a separate opening, preserving released v1-v8 inputs.
  static final List<String> migration9Statements = List.unmodifiable([
    '''
CREATE TABLE treasury_openings (
  document_id TEXT PRIMARY KEY NOT NULL REFERENCES business_documents(id) ON DELETE RESTRICT,
  command_id TEXT NOT NULL UNIQUE REFERENCES command_log(id) ON DELETE RESTRICT,
  profile_id TEXT NOT NULL UNIQUE REFERENCES app_profile(profile_id) ON DELETE RESTRICT,
  cash_account_id TEXT NOT NULL REFERENCES cash_accounts(id) ON DELETE RESTRICT,
  nequi_account_id TEXT NOT NULL REFERENCES cash_accounts(id) ON DELETE RESTRICT,
  reserve_account_id TEXT NOT NULL REFERENCES cash_accounts(id) ON DELETE RESTRICT,
  cash_minor INTEGER NOT NULL CHECK (typeof(cash_minor)='integer' AND cash_minor >= -9223372036854775807),
  nequi_minor INTEGER NOT NULL CHECK (typeof(nequi_minor)='integer' AND nequi_minor >= -9223372036854775807),
  reserve_minor INTEGER NOT NULL CHECK (typeof(reserve_minor)='integer' AND reserve_minor >= -9223372036854775807),
  receivables_minor INTEGER NOT NULL CHECK (typeof(receivables_minor)='integer' AND receivables_minor >= 0),
  source_sha256 TEXT NOT NULL CHECK (length(source_sha256)=64 AND source_sha256 NOT GLOB '*[^0-9a-f]*'),
  snapshot_sha256 TEXT NOT NULL CHECK (length(snapshot_sha256)=64 AND snapshot_sha256 NOT GLOB '*[^0-9a-f]*'),
  source_metadata_json TEXT NOT NULL CHECK (json_valid(source_metadata_json) AND json_type(source_metadata_json)='object'),
  occurred_at_utc TEXT NOT NULL CHECK (${_collectionUtc('occurred_at_utc')}),
  CHECK (cash_account_id <> nequi_account_id AND cash_account_id <> reserve_account_id AND nequi_account_id <> reserve_account_id),
  CHECK (typeof(${_treasuryPositive('')})='integer' AND typeof(${_treasuryNegative('')})='integer')
)
''',
    '''
CREATE VIEW treasury_opening_expected_lines AS
SELECT opening.document_id, cash.ledger_account_id account_id,
 max(0,opening.cash_minor) debit_minor,max(0,-opening.cash_minor) credit_minor
FROM treasury_openings opening JOIN cash_accounts cash ON cash.id=opening.cash_account_id WHERE opening.cash_minor <> 0
UNION ALL
SELECT opening.document_id,cash.ledger_account_id,max(0,opening.nequi_minor),max(0,-opening.nequi_minor)
FROM treasury_openings opening JOIN cash_accounts cash ON cash.id=opening.nequi_account_id WHERE opening.nequi_minor <> 0
UNION ALL
SELECT opening.document_id,cash.ledger_account_id,max(0,opening.reserve_minor),max(0,-opening.reserve_minor)
FROM treasury_openings opening JOIN cash_accounts cash ON cash.id=opening.reserve_account_id WHERE opening.reserve_minor <> 0
UNION ALL
SELECT document_id,'system:legacy-customer-receivables',receivables_minor,0
FROM treasury_openings WHERE receivables_minor > 0
UNION ALL
SELECT document_id,'system:opening-equity',
 max(0,${_treasuryNegative('')}-${_treasuryPositive('')}),
 max(0,${_treasuryPositive('')}-${_treasuryNegative('')})
FROM treasury_openings WHERE ${_treasuryPositive('')} <> ${_treasuryNegative('')}
''',
    '''
CREATE TRIGGER treasury_opening_documents_insert_as_draft
BEFORE INSERT ON business_documents WHEN NEW.type='treasury_opening' AND NEW.status <> 'draft'
BEGIN SELECT RAISE(ABORT, 'Create a treasury opening as draft before posting'); END
''',
    '''
CREATE TRIGGER treasury_openings_validate_insert
BEFORE INSERT ON treasury_openings
BEGIN
  SELECT CASE WHEN EXISTS (SELECT 1 FROM treasury_openings WHERE document_id=NEW.document_id OR command_id=NEW.command_id OR profile_id=NEW.profile_id)
    THEN RAISE(ABORT, 'A profile has one immutable treasury opening') END;
  SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM business_documents document JOIN command_log command ON command.id=document.command_id
    WHERE document.id=NEW.document_id AND document.status='draft' AND document.type='treasury_opening'
      AND document.command_sequence=0 AND document.command_id=NEW.command_id AND document.profile_id=NEW.profile_id
      AND document.occurred_at_utc=NEW.occurred_at_utc AND document.source_kind IN ('legacy','synthetic')
      AND document.date_quality='reconstructed' AND command.command_type='treasury_opening'
      AND command.actor_id=document.actor_id AND command.authorization_policy_version='development-single-user-v1')
    THEN RAISE(ABORT, 'A treasury opening requires its matching draft document and command') END;
  SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM command_log command JOIN app_profile profile ON profile.profile_id=NEW.profile_id
    WHERE command.id=NEW.command_id AND command.response_version=1 AND json_valid(command.response_json)
      AND json_extract(command.response_json,'\$.documentId') IS NEW.document_id
      AND json_valid(json_extract(command.response_json,'\$.canonicalPayload'))
      AND json_extract(json_extract(command.response_json,'\$.canonicalPayload'),'\$.version') IS 1
      AND json_extract(json_extract(command.response_json,'\$.canonicalPayload'),'\$.profileId') IS NEW.profile_id
      AND json_extract(json_extract(command.response_json,'\$.canonicalPayload'),'\$.currency') IS profile.currency_code
      AND json_extract(json_extract(command.response_json,'\$.canonicalPayload'),'\$.scale') IS profile.money_scale
      AND json_extract(json_extract(command.response_json,'\$.canonicalPayload'),'\$.sourceSha256') IS NEW.source_sha256
      AND json_extract(json_extract(command.response_json,'\$.canonicalPayload'),'\$.snapshotSha256') IS NEW.snapshot_sha256
      AND json_extract(json_extract(command.response_json,'\$.canonicalPayload'),'\$.occurredAtUtc') IS NEW.occurred_at_utc
      AND json_extract(json_extract(command.response_json,'\$.canonicalPayload'),'\$.cashAccountId') IS NEW.cash_account_id
      AND json_extract(json_extract(command.response_json,'\$.canonicalPayload'),'\$.nequiAccountId') IS NEW.nequi_account_id
      AND json_extract(json_extract(command.response_json,'\$.canonicalPayload'),'\$.reserveAccountId') IS NEW.reserve_account_id
      AND json_extract(json_extract(command.response_json,'\$.canonicalPayload'),'\$.cashMinor') IS NEW.cash_minor
      AND json_extract(json_extract(command.response_json,'\$.canonicalPayload'),'\$.nequiMinor') IS NEW.nequi_minor
      AND json_extract(json_extract(command.response_json,'\$.canonicalPayload'),'\$.reserveMinor') IS NEW.reserve_minor
      AND json_extract(json_extract(command.response_json,'\$.canonicalPayload'),'\$.receivablesMinor') IS NEW.receivables_minor
      AND json_extract(json_extract(command.response_json,'\$.canonicalPayload'),'\$.sourceMetadata') IS NEW.source_metadata_json)
    THEN RAISE(ABORT, 'Treasury opening balances and provenance must match their committed canonical command') END;
  SELECT CASE WHEN EXISTS (SELECT 1 FROM cash_openings) OR EXISTS (SELECT 1 FROM customer_receivables)
    OR EXISTS (SELECT 1 FROM journal_lines line JOIN journal_entries entry ON entry.id=line.entry_id AND entry.status='posted'
      JOIN business_documents document ON document.id=entry.document_id AND document.status='posted'
      JOIN ledger_accounts account ON account.id=line.account_id WHERE account.role IN ('cash','receivable'))
    THEN RAISE(ABORT, 'Import treasury balances before any own money movements or receivables') END;
END
''',
    '''
CREATE TRIGGER treasury_openings_validate_document_posting
BEFORE UPDATE OF status ON business_documents
WHEN OLD.status='draft' AND NEW.status='posted' AND
 (NEW.type='treasury_opening' OR EXISTS (SELECT 1 FROM treasury_openings WHERE document_id=NEW.id))
BEGIN
  SELECT CASE WHEN NEW.type <> 'treasury_opening' OR NEW.command_sequence <> 0 OR NEW.source_kind NOT IN ('legacy','synthetic')
    OR NEW.date_quality <> 'reconstructed' OR date(NEW.occurred_at_utc,'-5 hours') IS NOT NEW.business_date
    OR NOT EXISTS (SELECT 1 FROM treasury_openings opening JOIN command_log command ON command.id=opening.command_id
      WHERE opening.document_id=NEW.id AND opening.command_id=NEW.command_id AND opening.profile_id=NEW.profile_id
        AND opening.occurred_at_utc=NEW.occurred_at_utc AND command.command_type='treasury_opening'
        AND command.actor_id=NEW.actor_id AND command.authorization_policy_version='development-single-user-v1')
    THEN RAISE(ABORT, 'Invalid treasury opening document or command') END;
  SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM treasury_openings opening
    JOIN quick_payment_options cash_option ON cash_option.id='quick-default:EFECTIVO' AND cash_option.cash_account_id=opening.cash_account_id AND cash_option.is_active=1
    JOIN quick_payment_options nequi_option ON nequi_option.id='quick-default:NEQUI' AND nequi_option.cash_account_id=opening.nequi_account_id AND nequi_option.is_active=1
    WHERE opening.document_id=NEW.id AND opening.reserve_account_id='treasury:main-cash')
    OR EXISTS (SELECT 1 FROM treasury_openings opening JOIN cash_accounts cash
      ON cash.id IN (opening.cash_account_id,opening.nequi_account_id,opening.reserve_account_id)
      JOIN ledger_accounts ledger ON ledger.id=cash.ledger_account_id
      WHERE opening.document_id=NEW.id AND (cash.is_active <> 1 OR cash.is_available <> 1 OR ledger.is_active <> 1 OR ledger.class <> 'asset' OR ledger.role <> 'cash'))
    OR NOT EXISTS (SELECT 1 FROM ledger_accounts WHERE id='system:opening-equity' AND class='equity' AND role='opening_balance' AND is_active=1)
    OR NOT EXISTS (SELECT 1 FROM ledger_accounts WHERE id='system:legacy-customer-receivables' AND class='asset' AND role='receivable' AND is_active=1)
    THEN RAISE(ABORT, 'Treasury opening must use the configured distinct monetary accounts and opening ledgers') END;
  SELECT CASE WHEN EXISTS (SELECT 1 FROM cash_openings) OR EXISTS (SELECT 1 FROM customer_receivables)
    OR EXISTS (SELECT 1 FROM journal_lines line JOIN journal_entries entry ON entry.id=line.entry_id AND entry.status='posted'
      JOIN business_documents document ON document.id=entry.document_id AND document.status='posted'
      JOIN ledger_accounts account ON account.id=line.account_id
      WHERE document.id <> NEW.id AND account.role IN ('cash','receivable'))
    THEN RAISE(ABORT, 'Treasury opening must precede all own money movements and receivables') END;
  SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM journal_entries WHERE document_id=NEW.id AND status='draft' AND cost_completeness='not_applicable')
    OR (SELECT count(*) FROM journal_lines line JOIN journal_entries entry ON entry.id=line.entry_id WHERE entry.document_id=NEW.id)
      <> (SELECT count(*) FROM treasury_opening_expected_lines WHERE document_id=NEW.id)
    OR EXISTS (SELECT 1 FROM treasury_opening_expected_lines expected WHERE expected.document_id=NEW.id AND
      (SELECT count(*) FROM journal_lines line JOIN journal_entries entry ON entry.id=line.entry_id
       WHERE entry.document_id=NEW.id AND line.account_id=expected.account_id
         AND line.debit_minor=expected.debit_minor AND line.credit_minor=expected.credit_minor) <> 1)
    THEN RAISE(ABORT, 'Treasury opening journal must match every exact imported balance and opening equity') END;
END
''',
    'DROP TRIGGER entries_validate_posting',
    _treasuryAwareEntryPostingTrigger(),
    '''
CREATE TRIGGER cash_openings_respect_treasury_opening
BEFORE INSERT ON cash_openings
WHEN EXISTS (SELECT 1 FROM treasury_openings opening WHERE NEW.cash_account_id IN
  (opening.cash_account_id,opening.nequi_account_id,opening.reserve_account_id))
BEGIN SELECT RAISE(ABORT, 'A treasury import already declared this account opening, including zero'); END
''',
    '''
CREATE TRIGGER documents_respect_treasury_opening_chronology
BEFORE UPDATE OF status ON business_documents
WHEN OLD.status='draft' AND NEW.status='posted' AND NEW.type <> 'treasury_opening'
BEGIN
  SELECT CASE WHEN EXISTS (SELECT 1 FROM treasury_openings opening
    JOIN business_documents opening_document ON opening_document.id=opening.document_id AND opening_document.status='posted'
    JOIN journal_entries opening_entry ON opening_entry.document_id=opening.document_id AND opening_entry.status='posted'
    JOIN journal_entries incoming_entry ON incoming_entry.document_id=NEW.id
    JOIN journal_lines incoming_line ON incoming_line.entry_id=incoming_entry.id
    JOIN ledger_accounts incoming_account ON incoming_account.id=incoming_line.account_id
    WHERE opening.profile_id=NEW.profile_id AND incoming_account.role IN ('cash','customer_receivable')
      AND ${_utcSortKey('NEW.occurred_at_utc')} < ${_utcSortKey('opening.occurred_at_utc')})
    THEN RAISE(ABORT, 'Own money movements and receivables cannot precede the treasury opening') END;
END
''',
    '''
CREATE TRIGGER entries_respect_treasury_opening_chronology
BEFORE UPDATE OF status ON journal_entries
WHEN OLD.status='draft' AND NEW.status='posted'
BEGIN
  SELECT CASE WHEN EXISTS (SELECT 1 FROM business_documents incoming_document
    JOIN journal_lines incoming_line ON incoming_line.entry_id=NEW.id
    JOIN ledger_accounts incoming_account ON incoming_account.id=incoming_line.account_id
    JOIN treasury_openings opening ON opening.profile_id=incoming_document.profile_id
    JOIN business_documents opening_document ON opening_document.id=opening.document_id AND opening_document.status='posted'
    JOIN journal_entries opening_entry ON opening_entry.document_id=opening.document_id AND opening_entry.status='posted'
    WHERE incoming_document.id=NEW.document_id AND incoming_document.type <> 'treasury_opening'
      AND incoming_account.role IN ('cash','customer_receivable')
      AND ${_utcSortKey('incoming_document.occurred_at_utc')} < ${_utcSortKey('opening.occurred_at_utc')})
    THEN RAISE(ABORT, 'Own money entries and receivables cannot precede the treasury opening') END;
END
''',
    ..._freezeTreasuryOpeningFacts(),
  ]);

  /// Operating expenses and internal transfers have durable input and a single
  /// immutable document. Neither operation creates inventory or a payable.
  static final List<String> migration10Statements = List<String>.unmodifiable([
    '''
CREATE TABLE treasury_operation_requests (
  command_id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(command_id)) > 0),
  canonical_payload TEXT NOT NULL CHECK (json_valid(canonical_payload)),
  occurred_at_utc TEXT NOT NULL CHECK (${_collectionUtc('occurred_at_utc')}),
  prepared_at_utc TEXT NOT NULL CHECK (${_collectionUtc('prepared_at_utc')}),
  status TEXT NOT NULL CHECK (status IN ('prepared','executing','confirmed','rejected','discarded')),
  rejection_reason TEXT,
  CHECK ((status IN ('prepared','executing','confirmed') AND rejection_reason IS NULL)
    OR (status IN ('rejected','discarded') AND rejection_reason IS NOT NULL AND length(trim(rejection_reason)) > 0))
)
''',
    '''
CREATE TABLE treasury_operations (
  document_id TEXT PRIMARY KEY NOT NULL REFERENCES business_documents(id) ON DELETE RESTRICT,
  request_id TEXT NOT NULL UNIQUE REFERENCES treasury_operation_requests(command_id) ON DELETE RESTRICT,
  kind TEXT NOT NULL CHECK (kind IN ('expense','transfer')),
  source_account_id TEXT NOT NULL REFERENCES cash_accounts(id) ON DELETE RESTRICT,
  destination_account_id TEXT REFERENCES cash_accounts(id) ON DELETE RESTRICT,
  source_account_name_snapshot TEXT NOT NULL CHECK (length(trim(source_account_name_snapshot)) BETWEEN 1 AND 160),
  destination_account_name_snapshot TEXT CHECK (destination_account_name_snapshot IS NULL OR length(trim(destination_account_name_snapshot)) BETWEEN 1 AND 160),
  amount_minor INTEGER NOT NULL CHECK (typeof(amount_minor)='integer' AND amount_minor > 0),
  reason TEXT NOT NULL CHECK (length(trim(reason)) BETWEEN 1 AND 160),
  note TEXT CHECK (note IS NULL OR length(trim(note)) BETWEEN 1 AND 500),
  expense_account_id TEXT REFERENCES ledger_accounts(id) ON DELETE RESTRICT,
  CHECK ((kind='expense' AND destination_account_id IS NULL AND destination_account_name_snapshot IS NULL
      AND expense_account_id='treasury:operating-expenses')
    OR (kind='transfer' AND destination_account_id IS NOT NULL AND destination_account_name_snapshot IS NOT NULL
      AND source_account_id <> destination_account_id AND expense_account_id IS NULL))
)
''',
    'CREATE INDEX idx_treasury_operations_source ON treasury_operations(source_account_id)',
    'CREATE INDEX idx_treasury_operations_destination ON treasury_operations(destination_account_id)',
    '''
CREATE VIEW treasury_operation_expected_lines AS
SELECT operation.document_id, cash.ledger_account_id AS account_id,
  0 AS debit_minor, operation.amount_minor AS credit_minor
FROM treasury_operations operation JOIN cash_accounts cash ON cash.id=operation.source_account_id
UNION ALL
SELECT operation.document_id, operation.expense_account_id, operation.amount_minor, 0
FROM treasury_operations operation WHERE operation.kind='expense'
UNION ALL
SELECT operation.document_id, cash.ledger_account_id, operation.amount_minor, 0
FROM treasury_operations operation JOIN cash_accounts cash ON cash.id=operation.destination_account_id
WHERE operation.kind='transfer'
''',
    '''
CREATE TRIGGER treasury_operation_requests_validate_insert
BEFORE INSERT ON treasury_operation_requests
BEGIN
  SELECT CASE WHEN NEW.status <> 'prepared'
    OR EXISTS (SELECT 1 FROM treasury_operation_requests WHERE command_id=NEW.command_id)
    OR EXISTS (SELECT 1 FROM command_log WHERE id=NEW.command_id)
    OR EXISTS (SELECT 1 FROM sale_confirmations WHERE command_id=NEW.command_id)
    OR EXISTS (SELECT 1 FROM collection_requests WHERE command_id=NEW.command_id)
    OR EXISTS (SELECT 1 FROM supplier_payment_requests WHERE command_id=NEW.command_id)
    OR EXISTS (SELECT 1 FROM quick_sale_requests WHERE NEW.command_id IN (command_id,sale_command_id,collection_command_id))
    OR EXISTS (SELECT 1 FROM paid_purchase_requests WHERE NEW.command_id IN (command_id,purchase_command_id,payment_command_id))
    THEN RAISE(ABORT, 'Create a unique prepared treasury operation') END;
  SELECT CASE WHEN json_type(NEW.canonical_payload) IS NOT 'object'
    OR json_extract(NEW.canonical_payload,'\$.version') IS NOT 1
    OR json_extract(NEW.canonical_payload,'\$.commandId') IS NOT NEW.command_id
    OR json_extract(NEW.canonical_payload,'\$.occurredAtUtc') IS NOT NEW.occurred_at_utc
    OR json_extract(NEW.canonical_payload,'\$.kind') NOT IN ('expense','transfer')
    OR json_type(NEW.canonical_payload,'\$.kind') IS NOT 'text'
    OR json_type(NEW.canonical_payload,'\$.amountMinor') IS NOT 'integer'
    OR json_extract(NEW.canonical_payload,'\$.amountMinor') <= 0
    OR json_type(NEW.canonical_payload,'\$.reason') IS NOT 'text'
    OR length(trim(json_extract(NEW.canonical_payload,'\$.reason'))) NOT BETWEEN 1 AND 160
    OR json_type(NEW.canonical_payload,'\$.note') NOT IN ('null','text')
    OR (json_type(NEW.canonical_payload,'\$.note')='text'
      AND length(trim(json_extract(NEW.canonical_payload,'\$.note'))) NOT BETWEEN 1 AND 500)
    OR NOT EXISTS (SELECT 1 FROM app_profile profile
      WHERE json_extract(NEW.canonical_payload,'\$.profileId') IS profile.profile_id
        AND json_extract(NEW.canonical_payload,'\$.currency') IS profile.currency_code
        AND json_extract(NEW.canonical_payload,'\$.scale') IS profile.money_scale)
    OR NOT EXISTS (SELECT 1 FROM cash_accounts cash JOIN ledger_accounts ledger ON ledger.id=cash.ledger_account_id
      WHERE cash.id=json_extract(NEW.canonical_payload,'\$.sourceAccountId')
        AND cash.ledger_account_id=json_extract(NEW.canonical_payload,'\$.sourceLedgerAccountId')
        AND cash.name=json_extract(NEW.canonical_payload,'\$.sourceAccountName')
        AND cash.is_active=1 AND cash.is_available=1 AND ledger.is_active=1 AND ledger.class='asset' AND ledger.role='cash')
    THEN RAISE(ABORT, 'Treasury input must capture its exact monetary profile and active source account') END;
  SELECT CASE WHEN (json_extract(NEW.canonical_payload,'\$.kind')='expense'
      AND (json_type(NEW.canonical_payload,'\$.destinationAccountId') IS NOT 'null'
        OR json_type(NEW.canonical_payload,'\$.destinationLedgerAccountId') IS NOT 'null'
        OR json_type(NEW.canonical_payload,'\$.destinationAccountName') IS NOT 'null'
        OR json_extract(NEW.canonical_payload,'\$.reason') NOT IN ('Arriendo','Aseo','Servicios','Otro')
        OR NOT EXISTS (SELECT 1 FROM quick_payment_options option
          WHERE option.id IN ('quick-default:EFECTIVO','quick-default:NEQUI')
            AND option.cash_account_id=json_extract(NEW.canonical_payload,'\$.sourceAccountId'))))
    OR (json_extract(NEW.canonical_payload,'\$.kind')='transfer'
      AND (json_extract(NEW.canonical_payload,'\$.reason') IS NOT 'Transferencia'
        OR json_extract(NEW.canonical_payload,'\$.destinationAccountId') IS json_extract(NEW.canonical_payload,'\$.sourceAccountId')
        OR NOT EXISTS (SELECT 1 FROM cash_accounts cash JOIN ledger_accounts ledger ON ledger.id=cash.ledger_account_id
          WHERE cash.id=json_extract(NEW.canonical_payload,'\$.destinationAccountId')
            AND cash.ledger_account_id=json_extract(NEW.canonical_payload,'\$.destinationLedgerAccountId')
            AND cash.name=json_extract(NEW.canonical_payload,'\$.destinationAccountName')
            AND cash.is_active=1 AND cash.is_available=1 AND ledger.is_active=1 AND ledger.class='asset' AND ledger.role='cash')))
    THEN RAISE(ABORT, 'A transfer requires a distinct active destination; an expense has no destination') END;
END
''',
    '''
CREATE TRIGGER treasury_operation_requests_validate_update
BEFORE UPDATE ON treasury_operation_requests
BEGIN
  SELECT CASE WHEN NEW.command_id <> OLD.command_id OR NEW.canonical_payload <> OLD.canonical_payload
    OR NEW.occurred_at_utc <> OLD.occurred_at_utc OR NEW.prepared_at_utc <> OLD.prepared_at_utc
    THEN RAISE(ABORT, 'Prepared treasury input is immutable') END;
  SELECT CASE WHEN NOT ((OLD.status='prepared' AND NEW.status IN ('executing','rejected'))
    OR (OLD.status='executing' AND NEW.status='confirmed') OR (OLD.status='rejected' AND NEW.status='discarded'))
    THEN RAISE(ABORT, 'Invalid treasury operation request transition') END;
  SELECT CASE WHEN NEW.status IN ('rejected','discarded') AND
    (EXISTS (SELECT 1 FROM command_log WHERE id=OLD.command_id)
      OR EXISTS (SELECT 1 FROM treasury_operations WHERE request_id=OLD.command_id))
    THEN RAISE(ABORT, 'A committed treasury operation cannot be rejected') END;
  SELECT CASE WHEN NEW.status='discarded' AND NEW.rejection_reason IS NOT OLD.rejection_reason
    THEN RAISE(ABORT, 'Treasury rejection reasons are historical') END;
  SELECT CASE WHEN NEW.status='confirmed' AND NOT EXISTS (
    SELECT 1 FROM treasury_operations operation
    JOIN business_documents document ON document.id=operation.document_id AND document.status='posted'
    JOIN journal_entries entry ON entry.document_id=document.id AND entry.status='posted'
    JOIN command_log command ON command.id=operation.request_id
    WHERE operation.request_id=OLD.command_id AND document.command_id=OLD.command_id
      AND command.command_type='treasury_operation' AND command.response_version=1
      AND json_extract(command.response_json,'\$.canonicalPayload') IS OLD.canonical_payload
      AND json_extract(command.response_json,'\$.result.documentId') IS operation.document_id)
    THEN RAISE(ABORT, 'A treasury operation requires its exact posted document and journal') END;
END
''',
    '''
CREATE TRIGGER treasury_operation_requests_no_delete
BEFORE DELETE ON treasury_operation_requests
BEGIN SELECT RAISE(ABORT, 'Durable treasury requests cannot be deleted'); END
''',
    '''
CREATE TRIGGER treasury_operation_commands_validate_insert
BEFORE INSERT ON command_log
WHEN NEW.command_type='treasury_operation' OR EXISTS (SELECT 1 FROM treasury_operation_requests WHERE command_id=NEW.id)
BEGIN
  SELECT CASE WHEN NEW.command_type <> 'treasury_operation' OR NEW.response_version <> 1
    OR NEW.authorization_policy_version <> 'development-single-user-v1'
    OR NOT EXISTS (SELECT 1 FROM treasury_operation_requests request WHERE request.command_id=NEW.id
      AND request.status='executing' AND json_valid(NEW.response_json)
      AND json_extract(NEW.response_json,'\$.canonicalPayload') IS request.canonical_payload
      AND json_extract(NEW.response_json,'\$.result.commandId') IS request.command_id
      AND json_extract(NEW.response_json,'\$.result.kind') IS json_extract(request.canonical_payload,'\$.kind')
      AND json_extract(NEW.response_json,'\$.result.amountMinor') IS json_extract(request.canonical_payload,'\$.amountMinor')
      AND json_type(NEW.response_json,'\$.result.documentId')='text'
      AND length(trim(json_extract(NEW.response_json,'\$.result.documentId'))) > 0)
    THEN RAISE(ABORT, 'A treasury command identifier is reserved for its exact executing request') END;
END
''',
    for (final table in [
      'sale_confirmations',
      'collection_requests',
      'supplier_payment_requests',
      'quick_sale_requests',
      'paid_purchase_requests',
    ])
      '''
CREATE TRIGGER ${table}_respect_treasury_operation_ids
BEFORE INSERT ON $table
WHEN EXISTS (SELECT 1 FROM treasury_operation_requests request WHERE request.command_id IN
  (NEW.command_id${table == 'quick_sale_requests'
          ? ',NEW.sale_command_id,NEW.collection_command_id'
          : table == 'paid_purchase_requests'
          ? ',NEW.purchase_command_id,NEW.payment_command_id'
          : ''}))
BEGIN SELECT RAISE(ABORT, 'Treasury operation identifiers cannot be reused by another operation'); END
''',
    '''
CREATE TRIGGER treasury_operation_documents_validate_insert
BEFORE INSERT ON business_documents
WHEN NEW.type IN ('cash_expense','cash_transfer')
  OR EXISTS (SELECT 1 FROM treasury_operation_requests WHERE command_id=NEW.command_id)
BEGIN
  SELECT CASE WHEN NEW.status <> 'draft' OR NEW.command_sequence <> 0
    OR NEW.source_kind NOT IN ('native','synthetic') OR NEW.date_quality <> 'documented'
    OR NEW.original_document_id IS NOT NULL
    OR NOT EXISTS (SELECT 1 FROM treasury_operation_requests request
      JOIN command_log command ON command.id=request.command_id
      WHERE request.command_id=NEW.command_id AND request.status='executing'
        AND NEW.type=CASE json_extract(request.canonical_payload,'\$.kind') WHEN 'expense' THEN 'cash_expense' ELSE 'cash_transfer' END
        AND NEW.occurred_at_utc=request.occurred_at_utc
        AND NEW.profile_id=json_extract(request.canonical_payload,'\$.profileId')
        AND command.command_type='treasury_operation' AND command.actor_id=NEW.actor_id
        AND json_extract(command.response_json,'\$.result.documentId') IS NEW.id)
    THEN RAISE(ABORT, 'Create the exact treasury operation document as draft') END;
END
''',
    '''
CREATE TRIGGER treasury_operations_validate_insert
BEFORE INSERT ON treasury_operations
BEGIN
  SELECT CASE WHEN EXISTS (SELECT 1 FROM treasury_operations WHERE document_id=NEW.document_id OR request_id=NEW.request_id)
    THEN RAISE(ABORT, 'Treasury operation history cannot be replaced') END;
  SELECT CASE WHEN NOT (${_treasuryOperationMatches('NEW', requireDraft: true)})
    THEN RAISE(ABORT, 'Treasury operation must match its immutable input and draft document') END;
END
''',
    for (final action in ['UPDATE', 'DELETE'])
      '''
CREATE TRIGGER treasury_operations_no_${action.toLowerCase()}
BEFORE $action ON treasury_operations
BEGIN SELECT RAISE(ABORT, 'Treasury operation history is immutable'); END
''',
    '''
CREATE TRIGGER treasury_operations_validate_document_posting
BEFORE UPDATE OF status ON business_documents
WHEN OLD.status='draft' AND NEW.status='posted' AND (NEW.type IN ('cash_expense','cash_transfer')
  OR EXISTS (SELECT 1 FROM treasury_operations WHERE document_id=NEW.id)
  OR EXISTS (SELECT 1 FROM treasury_operation_requests WHERE command_id=NEW.command_id))
BEGIN
  SELECT CASE WHEN NEW.id <> OLD.id OR NEW.command_id <> OLD.command_id OR NEW.type <> OLD.type
    OR NEW.command_sequence <> OLD.command_sequence OR NEW.profile_id <> OLD.profile_id OR NEW.actor_id <> OLD.actor_id
    OR NEW.occurred_at_utc IS NOT OLD.occurred_at_utc OR NEW.business_date IS NOT OLD.business_date
    OR NEW.source_kind <> OLD.source_kind OR NEW.date_quality <> OLD.date_quality
    OR NEW.reason IS NOT OLD.reason OR NEW.recorded_at_utc <> OLD.recorded_at_utc
    OR NEW.original_document_id IS NOT OLD.original_document_id
    THEN RAISE(ABORT, 'Posting cannot rewrite a treasury operation document') END;
  ${_validateTreasuryOperationPosting('NEW.id')}
END
''',
    '''
CREATE TRIGGER treasury_operations_validate_entry_posting
BEFORE UPDATE OF status ON journal_entries
WHEN OLD.status='draft' AND NEW.status='posted' AND
  (EXISTS (SELECT 1 FROM treasury_operations WHERE document_id IN (OLD.document_id,NEW.document_id))
    OR EXISTS (SELECT 1 FROM business_documents WHERE id IN (OLD.document_id,NEW.document_id) AND type IN ('cash_expense','cash_transfer')))
BEGIN
  SELECT CASE WHEN NEW.id <> OLD.id OR NEW.document_id <> OLD.document_id
    OR NEW.cost_completeness <> 'not_applicable' OR NEW.reversal_of_id IS NOT NULL
    THEN RAISE(ABORT, 'Posting cannot rewrite a treasury operation journal') END;
  ${_validateTreasuryOperationPosting('NEW.document_id')}
END
''',
    ..._freezeTreasuryOperationJournal(),
  ]);

  /// Credit is a tender classification, never a fictitious cash account. Legacy
  /// fully paid checkouts retain their original request and payment facts.
  static final List<String> migration11Statements = List<String>.unmodifiable([
    "ALTER TABLE quick_sales_accounts ADD COLUMN customer_name TEXT NOT NULL DEFAULT '' CHECK (length(trim(customer_name)) <= 160)",
    'ALTER TABLE quick_sales_lines ADD COLUMN is_credit INTEGER NOT NULL DEFAULT 0 CHECK (typeof(is_credit)=\'integer\' AND is_credit IN (0,1))',
    '''
CREATE TABLE quick_sale_line_tenders (
  id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(id)) > 0),
  request_id TEXT NOT NULL REFERENCES quick_sale_requests(command_id) ON DELETE RESTRICT,
  sequence INTEGER NOT NULL CHECK (typeof(sequence)='integer' AND sequence >= 0),
  source_line_id TEXT NOT NULL UNIQUE REFERENCES quick_sales_lines(id) ON DELETE RESTRICT,
  sale_document_id TEXT NOT NULL REFERENCES sales(document_id) ON DELETE RESTRICT,
  sale_line_id TEXT NOT NULL REFERENCES sale_lines(id) ON DELETE RESTRICT,
  collection_document_id TEXT REFERENCES collections(document_id) ON DELETE RESTRICT,
  product_id TEXT NOT NULL REFERENCES catalog_items(id) ON DELETE RESTRICT,
  product_name_snapshot TEXT NOT NULL CHECK (length(trim(product_name_snapshot)) BETWEEN 1 AND 160),
  quantity INTEGER NOT NULL CHECK (typeof(quantity)='integer' AND quantity > 0),
  unit_price_minor INTEGER NOT NULL CHECK (typeof(unit_price_minor)='integer' AND unit_price_minor >= 0),
  total_minor INTEGER NOT NULL CHECK (typeof(total_minor)='integer' AND total_minor >= 0
    AND typeof(quantity*unit_price_minor)='integer' AND quantity*unit_price_minor=total_minor),
  is_credit INTEGER NOT NULL CHECK (typeof(is_credit)='integer' AND is_credit IN (0,1)),
  customer_name_snapshot TEXT NOT NULL CHECK (length(trim(customer_name_snapshot)) BETWEEN 1 AND 160),
  payment_option_id TEXT REFERENCES quick_payment_options(id) ON DELETE RESTRICT,
  payment_option_label_snapshot TEXT NOT NULL CHECK (length(trim(payment_option_label_snapshot)) BETWEEN 1 AND 160),
  cash_account_id TEXT REFERENCES cash_accounts(id) ON DELETE RESTRICT,
  payment_method_id TEXT REFERENCES payment_methods(id) ON DELETE RESTRICT,
  cash_account_name_snapshot TEXT,
  cash_account_kind_snapshot TEXT,
  payment_method_code_snapshot TEXT,
  payment_method_name_snapshot TEXT,
  UNIQUE (request_id,sequence),
  CHECK ((is_credit=1 AND collection_document_id IS NULL AND payment_option_id IS NULL
      AND payment_option_label_snapshot='Deudas' AND cash_account_id IS NULL AND payment_method_id IS NULL
      AND cash_account_name_snapshot IS NULL AND cash_account_kind_snapshot IS NULL
      AND payment_method_code_snapshot IS NULL AND payment_method_name_snapshot IS NULL)
    OR (is_credit=0 AND payment_option_id IS NOT NULL AND cash_account_id IS NOT NULL
      AND payment_method_id IS NOT NULL AND cash_account_name_snapshot IS NOT NULL
      AND length(trim(cash_account_name_snapshot)) BETWEEN 1 AND 160
      AND cash_account_kind_snapshot IS NOT NULL AND cash_account_kind_snapshot IN ('cash','bank','mobile','clearing')
      AND payment_method_code_snapshot IS NOT NULL AND length(trim(payment_method_code_snapshot)) BETWEEN 1 AND 32
      AND payment_method_name_snapshot IS NOT NULL AND length(trim(payment_method_name_snapshot)) BETWEEN 1 AND 160
      AND (total_minor=0 OR collection_document_id IS NOT NULL)))
)
''',
    'CREATE INDEX idx_quick_line_tenders_sale ON quick_sale_line_tenders(sale_document_id)',
    '''
CREATE TRIGGER quick_sales_lines_credit_identity_insert
BEFORE INSERT ON quick_sales_lines
WHEN NEW.is_credit=1 AND NEW.payment_option_id IS NOT NULL
BEGIN SELECT RAISE(ABORT, 'Credit draft lines cannot reference monetary payment options'); END
''',
    '''
CREATE TRIGGER quick_sales_lines_credit_identity_update
BEFORE UPDATE ON quick_sales_lines
WHEN NEW.is_credit=1 AND NEW.payment_option_id IS NOT NULL
BEGIN SELECT RAISE(ABORT, 'Credit draft lines cannot reference monetary payment options'); END
''',
    '''
CREATE TRIGGER quick_sales_customer_locked
BEFORE UPDATE OF customer_name ON quick_sales_accounts
WHEN NEW.customer_name IS NOT OLD.customer_name AND (OLD.status <> 'open' OR NEW.status <> 'open'
  OR EXISTS (SELECT 1 FROM quick_sale_requests WHERE account_id=OLD.id AND status <> 'cancelled'))
BEGIN SELECT RAISE(ABORT, 'A prepared or closed debtor name is immutable'); END
''',
    '''
CREATE TRIGGER quick_credit_requests_validate_insert
BEFORE INSERT ON quick_sale_requests
WHEN EXISTS (SELECT 1 FROM quick_sales_lines WHERE account_id=NEW.account_id AND is_credit=1)
  OR (CASE WHEN json_valid(NEW.canonical_payload) THEN json_extract(NEW.canonical_payload,'\$.version')=2 ELSE 0 END)
BEGIN
  SELECT CASE WHEN NOT json_valid(NEW.canonical_payload)
    THEN RAISE(ABORT, 'Credit checkout requires valid canonical JSON') END;
  SELECT CASE WHEN NOT (${_quickCreditInputMatches('NEW')})
    THEN RAISE(ABORT, 'Credit checkout must capture its named debtor, exact lines and tender totals') END;
END
''',
    'DROP TRIGGER quick_sale_requests_validate_update',
    _quickCreditRequestUpdateTrigger(),
    '''
CREATE TRIGGER quick_line_tenders_validate_insert
BEFORE INSERT ON quick_sale_line_tenders
BEGIN
  SELECT CASE WHEN EXISTS (SELECT 1 FROM quick_sale_line_tenders WHERE id=NEW.id
      OR source_line_id=NEW.source_line_id OR (request_id=NEW.request_id AND sequence=NEW.sequence))
    OR EXISTS (SELECT 1 FROM quick_sale_line_payments WHERE source_line_id=NEW.source_line_id)
    THEN RAISE(ABORT, 'Quick sale tender history cannot be replaced or duplicated') END;
  SELECT CASE WHEN NOT (${_quickCreditTenderMatches()})
    THEN RAISE(ABORT, 'Quick tender must match its canonical source, posted sale and actual collection') END;
END
''',
    for (final action in ['UPDATE', 'DELETE'])
      '''
CREATE TRIGGER quick_line_tenders_no_${action.toLowerCase()}
BEFORE $action ON quick_sale_line_tenders
BEGIN SELECT RAISE(ABORT, 'Quick sale tender history is immutable'); END
''',
    '''
CREATE TRIGGER quick_legacy_payments_reject_credit
BEFORE INSERT ON quick_sale_line_payments
WHEN EXISTS (SELECT 1 FROM quick_sales_lines WHERE id=NEW.source_line_id AND is_credit=1)
  OR EXISTS (SELECT 1 FROM quick_sale_line_tenders WHERE source_line_id=NEW.source_line_id)
  OR EXISTS (SELECT 1 FROM quick_sale_requests WHERE command_id=NEW.request_id
    AND CASE WHEN json_valid(canonical_payload) THEN json_extract(canonical_payload,'\$.version')=2 ELSE 0 END)
BEGIN SELECT RAISE(ABORT, 'Credit checkout uses unified tender history'); END
''',
  ]);

  static String _quickCreditInputMatches(String request) =>
      '''EXISTS (
    SELECT 1 FROM quick_sales_accounts account JOIN app_profile profile
    WHERE account.id=$request.account_id AND account.revision=$request.account_revision
      AND json_type($request.canonical_payload)='object'
      AND json_type($request.canonical_payload,'\$.version')='integer'
      AND json_extract($request.canonical_payload,'\$.version') IS 2
      AND ${_quickCreditTextFields('$request.canonical_payload', ['profileId', 'currency', 'label', 'occurredAtUtc'])}
      AND json_extract($request.canonical_payload,'\$.profileId') IS profile.profile_id
      AND json_extract($request.canonical_payload,'\$.currency') IS profile.currency_code
      AND json_extract($request.canonical_payload,'\$.scale') IS profile.money_scale
      AND json_extract($request.canonical_payload,'\$.label') IS account.label
      AND json_extract($request.canonical_payload,'\$.occurredAtUtc') IS $request.occurred_at_utc
      AND json_type($request.canonical_payload,'\$.customerName')='text'
      AND length(trim(account.customer_name)) BETWEEN 1 AND 160
      AND json_extract($request.canonical_payload,'\$.customerName') IS account.customer_name
      AND json_type($request.canonical_payload,'\$.totalMinor')='integer'
      AND json_extract($request.canonical_payload,'\$.totalMinor') > 0
      AND json_type($request.canonical_payload,'\$.creditMinor')='integer'
      AND json_extract($request.canonical_payload,'\$.creditMinor') >= 0
      AND json_type($request.canonical_payload,'\$.paidMinor')='integer'
      AND json_extract($request.canonical_payload,'\$.paidMinor') >= 0
      AND json_extract($request.canonical_payload,'\$.totalMinor')-json_extract($request.canonical_payload,'\$.creditMinor')
        IS json_extract($request.canonical_payload,'\$.paidMinor')
      AND json_type($request.canonical_payload,'\$.lines')='array'
      AND json_array_length($request.canonical_payload,'\$.lines')=(SELECT count(*) FROM quick_sales_lines WHERE account_id=account.id)
      AND EXISTS (SELECT 1 FROM quick_sales_lines WHERE account_id=account.id AND is_credit=1)
      AND NOT EXISTS (SELECT 1 FROM json_each($request.canonical_payload,'\$.lines') canonical
        WHERE NOT (${_quickCreditCanonicalLineMatches(request)}))
      AND ${_quickCreditCanonicalRemainder(request, 'totalMinor')}=0
      AND ${_quickCreditCanonicalRemainder(request, 'creditMinor', credit: true)}=0
      AND ${_quickCreditCanonicalRemainder(request, 'paidMinor', credit: false)}=0
  )''';

  static String _quickCreditCanonicalRemainder(
    String request,
    String field, {
    bool? credit,
  }) => _supplierBoundedRemainder(
    "json_extract($request.canonical_payload,'\$.$field')",
    "json_each($request.canonical_payload,'\$.lines') canonical",
    credit == null
        ? '1'
        : "json_extract(canonical.value,'\$.isCredit')=${credit ? 1 : 0}",
    "json_extract(canonical.value,'\$.totalMinor')",
    'canonical.key',
  );

  static String _quickCreditCanonicalLineMatches(String request) =>
      '''EXISTS (
    SELECT 1 FROM quick_sales_lines source JOIN catalog_items product ON product.id=source.product_id
    WHERE source.account_id=$request.account_id AND source.sequence=canonical.key
      AND canonical.type='object'
      AND ${_quickCreditTextFields('canonical.value', ['lineId', 'productId', 'productName', 'paymentOptionId', 'paymentOptionLabel'])}
      AND json_extract(canonical.value,'\$.lineId') IS source.id
      AND json_extract(canonical.value,'\$.productId') IS source.product_id
      AND json_extract(canonical.value,'\$.productName') IS product.name
      AND json_type(canonical.value,'\$.isCredit') IN ('true','false')
      AND json_extract(canonical.value,'\$.isCredit') IS source.is_credit
      AND json_type(canonical.value,'\$.quantity')='integer' AND json_extract(canonical.value,'\$.quantity') > 0
      AND trim(source.quantity_text) NOT GLOB '*[^0-9]*'
      AND ltrim(trim(source.quantity_text),'0')=CAST(json_extract(canonical.value,'\$.quantity') AS TEXT)
      AND json_type(canonical.value,'\$.unitPriceMinor')='integer'
      AND json_extract(canonical.value,'\$.unitPriceMinor') IS source.unit_price_minor
      AND source.unit_price_minor >= 0
      AND json_type(canonical.value,'\$.totalMinor')='integer'
      AND typeof(json_extract(canonical.value,'\$.quantity')*source.unit_price_minor)='integer'
      AND json_extract(canonical.value,'\$.quantity')*source.unit_price_minor IS json_extract(canonical.value,'\$.totalMinor')
      AND ((source.is_credit=1 AND source.payment_option_id IS NULL
          AND json_extract(canonical.value,'\$.paymentOptionId') IS 'quick-debt'
          AND json_extract(canonical.value,'\$.paymentOptionLabel') IS 'Deudas'
          AND ${_quickCreditNullMoney('canonical.value')})
        OR (source.is_credit=0 AND EXISTS (
          SELECT 1 FROM quick_payment_options option JOIN cash_accounts cash ON cash.id=option.cash_account_id
          JOIN ledger_accounts ledger ON ledger.id=cash.ledger_account_id
          JOIN payment_methods method ON method.id=option.payment_method_id
          WHERE option.id=source.payment_option_id AND option.is_active=1 AND cash.is_active=1
            AND ${_quickCreditTextFields('canonical.value', ['cashAccountId', 'paymentMethodId', 'cashAccountName', 'cashAccountKind', 'paymentMethodCode', 'paymentMethodName'])}
            AND ledger.is_active=1 AND ledger.class='asset' AND ledger.role='cash' AND method.is_active=1
            AND json_extract(canonical.value,'\$.paymentOptionId') IS option.id
            AND json_extract(canonical.value,'\$.paymentOptionLabel') IS option.label
            AND json_extract(canonical.value,'\$.cashAccountId') IS cash.id
            AND json_extract(canonical.value,'\$.paymentMethodId') IS method.id
            AND json_extract(canonical.value,'\$.cashAccountName') IS cash.name
            AND json_extract(canonical.value,'\$.cashAccountKind') IS cash.kind
            AND json_extract(canonical.value,'\$.paymentMethodCode') IS method.code
            AND json_extract(canonical.value,'\$.paymentMethodName') IS method.name)))
  )''';

  static String _quickCreditNullMoney(String value) => [
    'cashAccountId',
    'paymentMethodId',
    'cashAccountName',
    'cashAccountKind',
    'paymentMethodCode',
    'paymentMethodName',
  ].map((field) => "json_type($value,'\$.$field') IS 'null'").join(' AND ');

  static String _quickCreditTextFields(String value, List<String> fields) =>
      fields
          .map((field) => "json_type($value,'\$.$field') IS 'text'")
          .join(' AND ');

  static String _quickCreditTenderMatches() => '''EXISTS (
    SELECT 1 FROM quick_sale_requests request
    JOIN quick_sales_lines source ON source.account_id=request.account_id
    JOIN json_each(request.canonical_payload,'\$.lines') canonical ON canonical.key=NEW.sequence
    JOIN sale_lines line ON line.id=NEW.sale_line_id
    JOIN sales sale ON sale.document_id=line.sale_id
    JOIN business_documents sale_doc ON sale_doc.id=sale.document_id
    JOIN journal_entries sale_entry ON sale_entry.document_id=sale_doc.id
    WHERE request.command_id=NEW.request_id AND request.status='executing'
      AND json_extract(request.canonical_payload,'\$.version') IS 2
      AND source.id=NEW.source_line_id AND source.sequence=NEW.sequence
      AND source.product_id=NEW.product_id AND source.unit_price_minor=NEW.unit_price_minor
      AND source.is_credit=NEW.is_credit AND source.payment_option_id IS NEW.payment_option_id
      AND trim(source.quantity_text) NOT GLOB '*[^0-9]*'
      AND ltrim(trim(source.quantity_text),'0')=CAST(NEW.quantity AS TEXT)
      AND line.sale_id=NEW.sale_document_id AND line.product_id=NEW.product_id
      AND line.unit_price_minor=NEW.unit_price_minor AND line.name_snapshot=NEW.product_name_snapshot
      AND sale_doc.command_id=request.sale_command_id AND sale_doc.status='posted' AND sale_entry.status='posted'
      AND sale.customer_name_snapshot IS NEW.customer_name_snapshot
      AND NEW.customer_name_snapshot IS json_extract(request.canonical_payload,'\$.customerName')
      AND json_extract(canonical.value,'\$.lineId') IS NEW.source_line_id
      AND json_extract(canonical.value,'\$.productId') IS NEW.product_id
      AND json_extract(canonical.value,'\$.productName') IS NEW.product_name_snapshot
      AND json_extract(canonical.value,'\$.quantity') IS NEW.quantity
      AND json_extract(canonical.value,'\$.unitPriceMinor') IS NEW.unit_price_minor
      AND json_extract(canonical.value,'\$.totalMinor') IS NEW.total_minor
      AND json_extract(canonical.value,'\$.isCredit') IS NEW.is_credit
      AND json_extract(canonical.value,'\$.paymentOptionId') IS CASE NEW.is_credit WHEN 1 THEN 'quick-debt' ELSE NEW.payment_option_id END
      AND json_extract(canonical.value,'\$.paymentOptionLabel') IS NEW.payment_option_label_snapshot
      AND json_extract(canonical.value,'\$.cashAccountId') IS NEW.cash_account_id
      AND json_extract(canonical.value,'\$.paymentMethodId') IS NEW.payment_method_id
      AND json_extract(canonical.value,'\$.cashAccountName') IS NEW.cash_account_name_snapshot
      AND json_extract(canonical.value,'\$.cashAccountKind') IS NEW.cash_account_kind_snapshot
      AND json_extract(canonical.value,'\$.paymentMethodCode') IS NEW.payment_method_code_snapshot
      AND json_extract(canonical.value,'\$.paymentMethodName') IS NEW.payment_method_name_snapshot
      AND (NEW.is_credit=1 OR EXISTS (SELECT 1 FROM quick_payment_options option
        JOIN cash_accounts cash ON cash.id=option.cash_account_id
        JOIN ledger_accounts ledger ON ledger.id=cash.ledger_account_id
        JOIN payment_methods method ON method.id=option.payment_method_id
        WHERE option.id=NEW.payment_option_id AND option.is_active=1
          AND cash.id=NEW.cash_account_id AND cash.is_active=1
          AND cash.kind IS NEW.cash_account_kind_snapshot
          AND ledger.is_active=1 AND ledger.class='asset' AND ledger.role='cash'
          AND method.id=NEW.payment_method_id AND method.is_active=1
          AND method.code IS NEW.payment_method_code_snapshot))
      AND (NEW.is_credit=1
        OR (json_extract(request.canonical_payload,'\$.paidMinor')=0 AND NEW.collection_document_id IS NULL)
        OR EXISTS (SELECT 1 FROM collections collection
          JOIN business_documents collection_doc ON collection_doc.id=collection.document_id
          JOIN journal_entries collection_entry ON collection_entry.document_id=collection_doc.id
          JOIN customer_receivables receivable ON receivable.id=collection.receivable_id
          WHERE collection.document_id=NEW.collection_document_id
            AND collection_doc.command_id=request.collection_command_id AND collection_doc.status='posted'
            AND collection_entry.status='posted' AND receivable.origin_document_id=sale_doc.id
            AND collection.total_minor IS json_extract(request.canonical_payload,'\$.paidMinor')
            AND collection.remaining_minor IS json_extract(request.canonical_payload,'\$.creditMinor')
            AND (NEW.total_minor=0 OR EXISTS (SELECT 1 FROM collection_parts part
              WHERE part.collection_id=collection.document_id AND part.cash_account_id=NEW.cash_account_id
                AND part.payment_method_id=NEW.payment_method_id
                AND part.cash_account_name_snapshot IS NEW.cash_account_name_snapshot
                AND part.cash_account_kind_snapshot IS NEW.cash_account_kind_snapshot
                AND part.payment_method_code_snapshot IS NEW.payment_method_code_snapshot
                AND part.payment_method_name_snapshot IS NEW.payment_method_name_snapshot))))
  )''';

  static String _quickCreditRequestUpdateTrigger() {
    final legacy = migration6Statements.singleWhere(
      (statement) => statement.contains(
        'CREATE TRIGGER quick_sale_requests_validate_update\n',
      ),
    );
    return legacy
        .replaceFirst(
          'OR EXISTS (SELECT 1 FROM quick_sale_line_payments WHERE request_id = OLD.command_id))',
          'OR EXISTS (SELECT 1 FROM quick_sale_line_payments WHERE request_id = OLD.command_id) '
              'OR EXISTS (SELECT 1 FROM quick_sale_line_tenders WHERE request_id = OLD.command_id))',
        )
        .replaceFirst(
          'NOT (${_quickConfirmedResult()})',
          '''NOT (CASE WHEN json_valid(OLD.canonical_payload) THEN
        CASE WHEN json_extract(OLD.canonical_payload,'\$.version')=2 THEN (${_quickCreditConfirmedResult()})
          ELSE (${_quickConfirmedResult()} AND NOT EXISTS (SELECT 1 FROM quick_sales_lines
            WHERE account_id=OLD.account_id AND is_credit=1)
            AND NOT EXISTS (SELECT 1 FROM quick_sale_line_tenders WHERE request_id=OLD.command_id)) END
        ELSE (${_quickConfirmedResult()}) END)''',
        );
  }

  static String _quickCreditConfirmedResult() =>
      '''EXISTS (
    SELECT 1 FROM command_log parent
    JOIN business_documents sale_doc ON sale_doc.command_id=OLD.sale_command_id
    JOIN sales sale ON sale.document_id=sale_doc.id
    JOIN journal_entries sale_entry ON sale_entry.document_id=sale_doc.id
    JOIN customer_receivables receivable ON receivable.origin_document_id=sale_doc.id
    JOIN sale_confirmations sale_request ON sale_request.command_id=OLD.sale_command_id
    WHERE parent.id=OLD.command_id AND parent.command_type='quick_sale' AND parent.response_version=1
      AND parent.actor_id=sale_doc.actor_id AND parent.authorization_policy_version='development-single-user-v1'
      AND sale.draft_id=OLD.legacy_draft_id AND sale_doc.status='posted' AND sale_entry.status='posted'
      AND sale_doc.occurred_at_utc=OLD.occurred_at_utc AND sale_request.status='confirmed'
      AND sale.label_snapshot IS json_extract(OLD.canonical_payload,'\$.label')
      AND sale.customer_name_snapshot IS json_extract(OLD.canonical_payload,'\$.customerName')
      AND receivable.customer_name_snapshot IS sale.customer_name_snapshot
      AND sale.receivable_minor IS json_extract(OLD.canonical_payload,'\$.totalMinor')
      AND receivable.initial_minor=sale.receivable_minor
      AND json_valid(parent.response_json)
      AND json_extract(parent.response_json,'\$.canonicalPayload') IS OLD.canonical_payload
      AND json_extract(parent.response_json,'\$.result.commandId') IS OLD.command_id
      AND json_extract(parent.response_json,'\$.result.saleDocumentId') IS sale.document_id
      AND json_type(parent.response_json,'\$.result.totalMinor')='integer'
      AND json_type(parent.response_json,'\$.result.totalCostMinor')='integer'
      AND json_type(parent.response_json,'\$.result.creditMinor')='integer'
      AND json_extract(parent.response_json,'\$.result.totalMinor') IS sale.receivable_minor
      AND json_extract(parent.response_json,'\$.result.totalCostMinor') IS sale.total_cost_minor
      AND json_extract(parent.response_json,'\$.result.creditMinor') IS json_extract(OLD.canonical_payload,'\$.creditMinor')
      AND json_extract(parent.response_json,'\$.result.customerName') IS sale.customer_name_snapshot
      AND NOT EXISTS (SELECT 1 FROM quick_sale_line_payments WHERE request_id=OLD.command_id)
      AND (SELECT count(*) FROM quick_sale_line_tenders WHERE request_id=OLD.command_id)
        =(SELECT count(*) FROM quick_sales_lines WHERE account_id=OLD.account_id)
      AND EXISTS (SELECT 1 FROM quick_sale_line_tenders WHERE request_id=OLD.command_id AND is_credit=1)
      AND ${_supplierBoundedRemainder('sale.receivable_minor', 'quick_sale_line_tenders tender', 'tender.request_id=OLD.command_id', 'tender.total_minor', 'tender.sequence')}=0
      AND ${_supplierBoundedRemainder("json_extract(OLD.canonical_payload,'\$.creditMinor')", 'quick_sale_line_tenders tender', 'tender.request_id=OLD.command_id AND tender.is_credit=1', 'tender.total_minor', 'tender.sequence')}=0
      AND ${_supplierBoundedRemainder("json_extract(OLD.canonical_payload,'\$.paidMinor')", 'quick_sale_line_tenders tender', 'tender.request_id=OLD.command_id AND tender.is_credit=0', 'tender.total_minor', 'tender.sequence')}=0
      AND NOT EXISTS (SELECT 1 FROM sale_lines line WHERE line.sale_id=sale.document_id AND
        ${_supplierBoundedRemainder('line.quantity', 'quick_sale_line_tenders tender', 'tender.request_id=OLD.command_id AND tender.sale_line_id=line.id', 'tender.quantity', 'tender.sequence')}<>0)
      AND ${_supplierBoundedRemainder('receivable.initial_minor', 'receivable_settlements settlement JOIN business_documents settled_doc ON settled_doc.id=settlement.collection_id', "settlement.receivable_id=receivable.id AND settled_doc.status='posted'", 'settlement.amount_minor', 'settlement.collection_id')} IS json_extract(OLD.canonical_payload,'\$.creditMinor')
      AND ((json_extract(OLD.canonical_payload,'\$.paidMinor')=0
          AND json_type(parent.response_json,'\$.result.collectionDocumentId')='null'
          AND NOT EXISTS (SELECT 1 FROM command_log WHERE id=OLD.collection_command_id)
          AND NOT EXISTS (SELECT 1 FROM collection_requests WHERE command_id=OLD.collection_command_id)
          AND NOT EXISTS (SELECT 1 FROM business_documents WHERE command_id=OLD.collection_command_id)
          AND NOT EXISTS (SELECT 1 FROM collections WHERE receivable_id=receivable.id))
        OR EXISTS (SELECT 1 FROM collections collection
          JOIN business_documents collection_doc ON collection_doc.id=collection.document_id
          JOIN journal_entries collection_entry ON collection_entry.document_id=collection_doc.id
          JOIN collection_requests collection_request ON collection_request.command_id=OLD.collection_command_id
          WHERE collection_doc.command_id=OLD.collection_command_id AND collection_doc.status='posted'
            AND collection_entry.status='posted' AND collection_request.status='confirmed'
            AND collection_request.receivable_id=receivable.id AND collection.receivable_id=receivable.id
            AND collection_doc.actor_id=parent.actor_id AND collection_doc.occurred_at_utc=OLD.occurred_at_utc
            AND collection.total_minor IS json_extract(OLD.canonical_payload,'\$.paidMinor')
            AND collection.remaining_minor IS json_extract(OLD.canonical_payload,'\$.creditMinor')
            AND json_extract(parent.response_json,'\$.result.collectionDocumentId') IS collection.document_id
            AND NOT EXISTS (SELECT 1 FROM collection_parts part WHERE part.collection_id=collection.document_id AND
              ${_supplierBoundedRemainder('part.amount_minor', 'quick_sale_line_tenders tender', 'tender.request_id=OLD.command_id AND tender.is_credit=0 AND tender.cash_account_id=part.cash_account_id AND tender.payment_method_id=part.payment_method_id', 'tender.total_minor', 'tender.sequence')}<>0)
            AND NOT EXISTS (SELECT 1 FROM quick_sale_line_tenders tender WHERE tender.request_id=OLD.command_id
              AND tender.is_credit=0 AND tender.total_minor > 0 AND NOT EXISTS (SELECT 1 FROM collection_parts part
                WHERE part.collection_id=collection.document_id AND part.cash_account_id=tender.cash_account_id
                  AND part.payment_method_id=tender.payment_method_id))))
  )''';

  static String _treasuryOperationMatches(
    String fact, {
    bool requireDraft = false,
  }) =>
      '''EXISTS (
    SELECT 1 FROM treasury_operation_requests request
    JOIN business_documents document ON document.id=$fact.document_id
    JOIN command_log command ON command.id=request.command_id
    JOIN app_profile profile ON profile.profile_id=document.profile_id
    JOIN cash_accounts source ON source.id=$fact.source_account_id
    JOIN ledger_accounts source_ledger ON source_ledger.id=source.ledger_account_id
    WHERE request.command_id=$fact.request_id AND request.status='executing'
      ${requireDraft ? "AND document.status='draft'" : ''}
      AND document.command_id=request.command_id AND document.command_sequence=0
      AND document.recorded_at_utc IS command.committed_at_utc
      AND document.type=CASE $fact.kind WHEN 'expense' THEN 'cash_expense' ELSE 'cash_transfer' END
      AND document.source_kind IN ('native','synthetic') AND document.date_quality='documented'
      AND document.original_document_id IS NULL
      AND document.occurred_at_utc=request.occurred_at_utc
      AND document.reason IS $fact.reason
      AND date(document.occurred_at_utc,'-5 hours') IS document.business_date
      AND command.command_type='treasury_operation' AND command.actor_id=document.actor_id
      AND command.authorization_policy_version='development-single-user-v1'
      AND command.response_version=1 AND json_valid(command.response_json)
      AND json_extract(command.response_json,'\$.canonicalPayload') IS request.canonical_payload
      AND json_extract(command.response_json,'\$.result.documentId') IS document.id
      AND json_extract(request.canonical_payload,'\$.profileId') IS profile.profile_id
      AND json_extract(request.canonical_payload,'\$.currency') IS profile.currency_code
      AND json_extract(request.canonical_payload,'\$.scale') IS profile.money_scale
      AND json_extract(request.canonical_payload,'\$.kind') IS $fact.kind
      AND json_extract(request.canonical_payload,'\$.sourceAccountId') IS $fact.source_account_id
      AND json_extract(request.canonical_payload,'\$.sourceLedgerAccountId') IS source.ledger_account_id
      AND json_extract(request.canonical_payload,'\$.sourceAccountName') IS $fact.source_account_name_snapshot
      AND json_extract(request.canonical_payload,'\$.destinationAccountId') IS $fact.destination_account_id
      AND json_extract(request.canonical_payload,'\$.destinationAccountName') IS $fact.destination_account_name_snapshot
      AND json_extract(request.canonical_payload,'\$.amountMinor') IS $fact.amount_minor
      AND json_extract(request.canonical_payload,'\$.reason') IS $fact.reason
      AND json_extract(request.canonical_payload,'\$.note') IS $fact.note
      AND source.is_active=1 AND source.is_available=1 AND source_ledger.is_active=1
      AND source_ledger.class='asset' AND source_ledger.role='cash'
      AND (($fact.kind='expense' AND $fact.destination_account_id IS NULL
          AND $fact.expense_account_id='treasury:operating-expenses'
          AND $fact.reason IN ('Arriendo','Aseo','Servicios','Otro')
          AND EXISTS (SELECT 1 FROM quick_payment_options option
            WHERE option.id IN ('quick-default:EFECTIVO','quick-default:NEQUI')
              AND option.cash_account_id=$fact.source_account_id)
          AND EXISTS (SELECT 1 FROM ledger_accounts expense WHERE expense.id=$fact.expense_account_id
            AND expense.code='TREASURY:EXPENSE' AND expense.class='expense' AND expense.role='operating_expense' AND expense.is_active=1))
        OR ($fact.kind='transfer' AND $fact.expense_account_id IS NULL AND $fact.reason='Transferencia'
          AND $fact.destination_account_id <> $fact.source_account_id
          AND EXISTS (SELECT 1 FROM cash_accounts destination JOIN ledger_accounts ledger ON ledger.id=destination.ledger_account_id
            WHERE destination.id=$fact.destination_account_id AND destination.is_active=1 AND destination.is_available=1
              AND ledger.id=json_extract(request.canonical_payload,'\$.destinationLedgerAccountId')
              AND ledger.is_active=1 AND ledger.class='asset' AND ledger.role='cash'))))''';

  static String _validateTreasuryOperationPosting(String documentId) =>
      '''
  SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM treasury_operations operation WHERE operation.document_id=$documentId
    AND ${_treasuryOperationMatches('operation')})
    THEN RAISE(ABORT, 'Treasury posting requires its exact immutable operation and active accounts') END;
  SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM journal_entries entry WHERE entry.document_id=$documentId
      AND entry.cost_completeness='not_applicable' AND entry.reversal_of_id IS NULL)
    OR (SELECT count(*) FROM journal_lines line JOIN journal_entries entry ON entry.id=line.entry_id
      WHERE entry.document_id=$documentId) <> 2
    OR EXISTS (SELECT 1 FROM treasury_operation_expected_lines expected WHERE expected.document_id=$documentId AND
      (SELECT count(*) FROM journal_lines line JOIN journal_entries entry ON entry.id=line.entry_id
        WHERE entry.document_id=$documentId AND line.account_id=expected.account_id
          AND line.debit_minor=expected.debit_minor AND line.credit_minor=expected.credit_minor) <> 1)
    THEN RAISE(ABORT, 'Treasury journal must contain its two exact expense or transfer lines') END;
  SELECT CASE WHEN EXISTS (SELECT 1 FROM treasury_operations operation
    JOIN business_documents incoming ON incoming.id=operation.document_id
    JOIN cash_accounts cash ON cash.id IN (operation.source_account_id,operation.destination_account_id)
    JOIN journal_lines line ON line.account_id=cash.ledger_account_id
    JOIN journal_entries entry ON entry.id=line.entry_id
    JOIN business_documents previous ON previous.id=entry.document_id
    WHERE operation.document_id=$documentId AND previous.id <> incoming.id AND previous.status='posted'
      AND (entry.status='posted' OR previous.type IN ('cash_expense','cash_transfer'))
      AND ${_utcSortKey('previous.occurred_at_utc')} > ${_utcSortKey('incoming.occurred_at_utc')})
    THEN RAISE(ABORT, 'Treasury operations cannot precede money movements of either account') END;
  SELECT CASE WHEN ${_treasuryOperationMoneyInvalid(documentId)}
    THEN RAISE(ABORT, 'Treasury operation requires sufficient source funds and representable balances') END;
''';

  // Exact chronological addition avoids overflow of gross historical SUMs.
  // Posted documents of this migration reserve funds before journal posting.
  static String _treasuryOperationMoneyInvalid(String documentId) =>
      '''EXISTS (
    WITH RECURSIVE accounts AS (
      SELECT cash.id,cash.ledger_account_id,operation.source_account_id,operation.amount_minor
      FROM treasury_operations operation JOIN cash_accounts cash
        ON cash.id IN (operation.source_account_id,operation.destination_account_id)
      WHERE operation.document_id=$documentId
    ), ordered AS (
      SELECT account.id,line.debit_minor,line.credit_minor,
        row_number() OVER (PARTITION BY account.id ORDER BY
          ${_utcSortKey('document.occurred_at_utc')},document.recorded_at_utc,document.id,line.sequence) AS n
      FROM accounts account JOIN journal_lines line ON line.account_id=account.ledger_account_id
      JOIN journal_entries entry ON entry.id=line.entry_id
      JOIN business_documents document ON document.id=entry.document_id
      WHERE document.id <> $documentId AND document.status='posted'
        AND (entry.status='posted' OR document.type IN ('cash_expense','cash_transfer'))
    ), balances(id,n,balance,valid) AS (
      SELECT id,0,0,1 FROM accounts
      UNION ALL
      SELECT prior.id,line.n,
        CASE WHEN prior.valid=0 THEN 0 WHEN line.debit_minor > 0 THEN
          CASE WHEN prior.balance <= 9223372036854775807-line.debit_minor THEN prior.balance+line.debit_minor ELSE 0 END
          ELSE CASE WHEN prior.balance >= -9223372036854775808+line.credit_minor THEN prior.balance-line.credit_minor ELSE 0 END END,
        CASE WHEN prior.valid=1 AND ((line.debit_minor > 0 AND prior.balance <= 9223372036854775807-line.debit_minor)
          OR (line.credit_minor > 0 AND prior.balance >= -9223372036854775808+line.credit_minor)) THEN 1 ELSE 0 END
      FROM balances prior JOIN ordered line ON line.id=prior.id AND line.n=prior.n+1
    ) SELECT 1 FROM accounts account WHERE NOT EXISTS (
      SELECT 1 FROM balances final WHERE final.id=account.id AND final.valid=1
        AND final.n=(SELECT count(*) FROM ordered WHERE id=account.id)
        AND ((account.id=account.source_account_id AND final.balance >= account.amount_minor)
          OR (account.id <> account.source_account_id AND final.balance <= 9223372036854775807-account.amount_minor)))
  )''';

  static List<String> _freezeTreasuryOperationJournal() {
    String frozen(String documentId) =>
        '''EXISTS (SELECT 1 FROM business_documents document
      JOIN treasury_operations operation ON operation.document_id=document.id
      WHERE document.id=$documentId AND document.status <> 'draft')''';
    String lineFrozen(String entryId) =>
        '''EXISTS (SELECT 1 FROM journal_entries entry
      WHERE entry.id=$entryId AND ${frozen('entry.document_id')})''';
    return [
      '''
CREATE TRIGGER treasury_operation_entries_no_replace
BEFORE INSERT ON journal_entries
WHEN EXISTS (SELECT 1 FROM journal_entries existing WHERE (existing.id=NEW.id OR existing.document_id=NEW.document_id)
  AND ${frozen('existing.document_id')})
BEGIN SELECT RAISE(ABORT, 'Confirmed treasury journals cannot be replaced'); END
''',
      '''
CREATE TRIGGER treasury_operation_entries_no_conflicting_update
BEFORE UPDATE ON journal_entries
WHEN EXISTS (SELECT 1 FROM journal_entries existing WHERE existing.id <> OLD.id
  AND (existing.id=NEW.id OR existing.document_id=NEW.document_id) AND ${frozen('existing.document_id')})
BEGIN SELECT RAISE(ABORT, 'Confirmed treasury journals cannot be replaced through an update'); END
''',
      for (final action in ['UPDATE', 'DELETE'])
        '''
CREATE TRIGGER treasury_operation_entries_no_${action.toLowerCase()}
BEFORE $action ON journal_entries
WHEN ${frozen('OLD.document_id')}
  ${action == 'UPDATE' ? "AND NOT (OLD.status='draft' AND NEW.status='posted' AND NEW.id=OLD.id AND NEW.document_id=OLD.document_id AND NEW.cost_completeness=OLD.cost_completeness AND NEW.reversal_of_id IS OLD.reversal_of_id)" : ''}
BEGIN SELECT RAISE(ABORT, 'Confirmed treasury documents retain their exact journal'); END
''',
      '''
CREATE TRIGGER treasury_operation_lines_no_replace
BEFORE INSERT ON journal_lines
WHEN EXISTS (SELECT 1 FROM journal_lines existing WHERE
  (existing.id=NEW.id OR (existing.entry_id=NEW.entry_id AND existing.sequence=NEW.sequence)) AND ${lineFrozen('existing.entry_id')})
BEGIN SELECT RAISE(ABORT, 'Confirmed treasury lines cannot be replaced'); END
''',
      '''
CREATE TRIGGER treasury_operation_lines_no_conflicting_update
BEFORE UPDATE ON journal_lines
WHEN EXISTS (SELECT 1 FROM journal_lines existing WHERE existing.id <> OLD.id
  AND (existing.id=NEW.id OR (existing.entry_id=NEW.entry_id AND existing.sequence=NEW.sequence)) AND ${lineFrozen('existing.entry_id')})
BEGIN SELECT RAISE(ABORT, 'Confirmed treasury lines cannot be replaced through an update'); END
''',
      for (final action in ['INSERT', 'UPDATE', 'DELETE'])
        '''
CREATE TRIGGER treasury_operation_lines_no_${action.toLowerCase()}
BEFORE $action ON journal_lines
WHEN ${action == 'DELETE'
            ? lineFrozen('OLD.entry_id')
            : action == 'INSERT'
            ? lineFrozen('NEW.entry_id')
            : '(${lineFrozen('OLD.entry_id')} OR ${lineFrozen('NEW.entry_id')})'}
BEGIN SELECT RAISE(ABORT, 'Confirmed treasury journal lines are immutable'); END
''',
    ];
  }

  static String _treasuryAwareEntryPostingTrigger() {
    final previous = migration8Statements.singleWhere(
      (statement) =>
          statement.contains('CREATE TRIGGER entries_validate_posting\n'),
    );
    return previous.replaceFirst(
      "    THEN RAISE(ABORT, 'A posted entry needs at least two lines except a confirmed zero value inventory opening') END;",
      '''    AND NOT EXISTS (SELECT 1 FROM treasury_openings opening JOIN business_documents document ON document.id=opening.document_id
      WHERE opening.document_id=NEW.document_id AND opening.cash_minor=0 AND opening.nequi_minor=0
        AND opening.reserve_minor=0 AND opening.receivables_minor=0 AND document.type='treasury_opening'
        AND document.status='posted' AND NEW.cost_completeness='not_applicable'
        AND NOT EXISTS (SELECT 1 FROM journal_lines WHERE entry_id=NEW.id))
    THEN RAISE(ABORT, 'A posted entry needs at least two lines except a confirmed zero value opening') END;''',
    );
  }

  static List<String> _freezeTreasuryOpeningFacts() {
    String confirmed(String id) =>
        '''EXISTS (SELECT 1 FROM business_documents document
WHERE document.id=$id AND document.status <> 'draft')''';
    return [
      for (final action in ['UPDATE', 'DELETE'])
        '''
CREATE TRIGGER treasury_openings_no_${action.toLowerCase()}
BEFORE $action ON treasury_openings
BEGIN SELECT RAISE(ABORT, 'Imported treasury balances and provenance are immutable'); END
''',
      '''
CREATE TRIGGER treasury_opening_entries_no_replace
BEFORE INSERT ON journal_entries
WHEN EXISTS (SELECT 1 FROM journal_entries existing JOIN treasury_openings opening ON opening.document_id=existing.document_id
 WHERE (existing.id=NEW.id OR existing.document_id=NEW.document_id) AND ${confirmed('existing.document_id')})
BEGIN SELECT RAISE(ABORT, 'Confirmed treasury opening entry cannot be replaced'); END
''',
      '''
CREATE TRIGGER treasury_opening_entries_no_conflicting_update
BEFORE UPDATE ON journal_entries
WHEN EXISTS (SELECT 1 FROM journal_entries existing JOIN treasury_openings opening ON opening.document_id=existing.document_id
 WHERE existing.id <> OLD.id AND (existing.id=NEW.id OR existing.document_id=NEW.document_id)
 AND ${confirmed('existing.document_id')})
BEGIN SELECT RAISE(ABORT, 'Treasury opening entry cannot be replaced through another entry'); END
''',
      '''
CREATE TRIGGER treasury_opening_lines_no_replace
BEFORE INSERT ON journal_lines
WHEN EXISTS (SELECT 1 FROM journal_lines existing JOIN journal_entries entry ON entry.id=existing.entry_id
 JOIN treasury_openings opening ON opening.document_id=entry.document_id
 WHERE (existing.id=NEW.id OR (existing.entry_id=NEW.entry_id AND existing.sequence=NEW.sequence)) AND ${confirmed('entry.document_id')})
BEGIN SELECT RAISE(ABORT, 'Confirmed treasury opening lines cannot be replaced'); END
''',
      for (final action in ['UPDATE', 'DELETE'])
        '''
CREATE TRIGGER treasury_opening_entries_no_${action.toLowerCase()}
BEFORE $action ON journal_entries
WHEN EXISTS (SELECT 1 FROM treasury_openings opening WHERE opening.document_id=OLD.document_id AND ${confirmed('OLD.document_id')})
 ${action == 'UPDATE' ? "AND NOT (OLD.status='draft' AND NEW.status='posted' AND NEW.id=OLD.id AND NEW.document_id=OLD.document_id AND NEW.reversal_of_id IS OLD.reversal_of_id AND NEW.cost_completeness=OLD.cost_completeness)" : ''}
BEGIN SELECT RAISE(ABORT, 'Confirmed treasury opening retains its exact entry'); END
''',
      for (final action in ['INSERT', 'UPDATE', 'DELETE'])
        '''
CREATE TRIGGER treasury_opening_lines_no_${action.toLowerCase()}
BEFORE $action ON journal_lines
WHEN EXISTS (SELECT 1 FROM journal_entries entry JOIN treasury_openings opening ON opening.document_id=entry.document_id
 WHERE entry.id=${action == 'DELETE' ? 'OLD' : 'NEW'}.entry_id AND ${confirmed('entry.document_id')})
 ${action == 'UPDATE' ? "OR EXISTS (SELECT 1 FROM journal_entries entry JOIN treasury_openings opening ON opening.document_id=entry.document_id WHERE entry.id=OLD.entry_id AND ${confirmed('entry.document_id')})" : ''}
BEGIN SELECT RAISE(ABORT, 'Confirmed treasury opening lines are immutable'); END
''',
      '''
CREATE TRIGGER treasury_opening_lines_no_conflicting_update
BEFORE UPDATE ON journal_lines
WHEN EXISTS (SELECT 1 FROM journal_lines existing JOIN journal_entries entry ON entry.id=existing.entry_id
 JOIN treasury_openings opening ON opening.document_id=entry.document_id
 WHERE existing.id <> OLD.id AND (existing.id=NEW.id OR (existing.entry_id=NEW.entry_id AND existing.sequence=NEW.sequence))
 AND ${confirmed('entry.document_id')})
BEGIN SELECT RAISE(ABORT, 'Treasury opening lines cannot be replaced through another line'); END
''',
    ];
  }

  static String _openingAwarePurchaseAllocationTrigger() {
    var sql = migration3Statements.singleWhere(
      (statement) => statement.contains(
        'CREATE TRIGGER sale_cost_allocations_validate_insert\n',
      ),
    );
    sql = sql
        .replaceAll(
          'SELECT count(*) FROM sale_cost_allocations WHERE sale_line_id = NEW.sale_line_id',
          'SELECT count(*) FROM all_sale_cost_allocations WHERE sale_line_id = NEW.sale_line_id',
        )
        .replaceAll(
          'SELECT sum(a.quantity) FROM sale_cost_allocations a WHERE a.sale_line_id = l.id',
          'SELECT sum(a.quantity) FROM all_sale_cost_allocations a WHERE a.sale_line_id = l.id',
        );
    return sql.replaceFirst(
      "  SELECT CASE WHEN NEW.cost_minor <>",
      '''  SELECT CASE WHEN EXISTS (SELECT 1 FROM inventory_opening_layers opening
    JOIN cost_layers chosen ON chosen.id = NEW.cost_layer_id
    JOIN sale_lines line ON line.id = NEW.sale_line_id JOIN sales sale ON sale.document_id = line.sale_id
    WHERE opening.product_id = chosen.product_id
      AND ${_utcSortKey('opening.acquired_at_utc')} <= ${_utcSortKey('sale.sold_at_utc')}
      AND opening.initial_quantity > coalesce((SELECT sum(allocation.quantity) FROM inventory_opening_allocations allocation
        WHERE allocation.opening_item_id = opening.id), 0))
    THEN RAISE(ABORT, 'Consume initial inventory before later purchased layers') END;
  SELECT CASE WHEN NEW.cost_minor <>''',
    );
  }

  static String _openingAwareSalePostingTrigger() {
    var sql = migration3Statements.singleWhere(
      (statement) => statement.contains(
        'CREATE TRIGGER sales_validate_document_posting\n',
      ),
    );
    sql = sql
        .replaceAll(
          'SELECT coalesce(sum(a.quantity), 0) FROM sale_cost_allocations a',
          'SELECT coalesce(sum(a.quantity), 0) FROM all_sale_cost_allocations a',
        )
        .replaceAll(
          'SELECT coalesce(sum(a.cost_minor), 0) FROM sale_cost_allocations a',
          'SELECT coalesce(sum(a.cost_minor), 0) FROM all_sale_cost_allocations a',
        );
    return sql.replaceFirst(
      "  SELECT CASE WHEN (SELECT count(*) FROM customer_receivables",
      '''  SELECT CASE WHEN EXISTS (SELECT 1 FROM inventory_opening_allocations allocation
    JOIN sale_lines line ON line.id = allocation.sale_line_id JOIN sales sale ON sale.document_id = line.sale_id
    JOIN inventory_opening_items item ON item.id = allocation.opening_item_id
    LEFT JOIN inventory_opening_layers opening ON opening.id = item.id
    WHERE line.sale_id = NEW.id AND (opening.id IS NULL OR item.product_id <> line.product_id
      OR ${_utcSortKey('opening.acquired_at_utc')} > ${_utcSortKey('sale.sold_at_utc')}))
    THEN RAISE(ABORT, 'Each opening allocation must match its effective confirmed source') END;
  SELECT CASE WHEN (SELECT count(*) FROM customer_receivables''',
    );
  }

  static List<String> _freezeInventoryOpeningFacts() {
    String confirmed(String document) =>
        '''EXISTS (SELECT 1 FROM business_documents document
WHERE document.id = $document AND document.status <> 'draft')''';
    return [
      '''
CREATE TRIGGER inventory_opening_journal_entries_no_replace
BEFORE INSERT ON journal_entries
WHEN EXISTS (SELECT 1 FROM journal_entries existing JOIN inventory_openings opening ON opening.document_id = existing.document_id
  JOIN business_documents document ON document.id = opening.document_id
  WHERE (existing.id = NEW.id OR existing.document_id = NEW.document_id) AND document.status <> 'draft')
BEGIN
  SELECT RAISE(ABORT, 'Confirmed initial inventory journal entries cannot be replaced');
END
''',
      '''
CREATE TRIGGER inventory_opening_journal_lines_no_replace
BEFORE INSERT ON journal_lines
WHEN EXISTS (SELECT 1 FROM journal_lines existing JOIN journal_entries entry ON entry.id = existing.entry_id
  JOIN inventory_openings opening ON opening.document_id = entry.document_id
  JOIN business_documents document ON document.id = opening.document_id
  WHERE (existing.id = NEW.id OR (existing.entry_id = NEW.entry_id AND existing.sequence = NEW.sequence))
    AND document.status <> 'draft')
BEGIN
  SELECT RAISE(ABORT, 'Confirmed initial inventory journal lines cannot be replaced');
END
''',
      for (final table in ['inventory_openings', 'inventory_opening_items'])
        for (final action in ['INSERT', 'UPDATE', 'DELETE'])
          '''
CREATE TRIGGER ${table}_confirmed_no_${action.toLowerCase()}
BEFORE $action ON $table
WHEN ${action == 'INSERT'
              ? '(${confirmed('NEW.${table == 'inventory_openings' ? 'document_id' : 'opening_id'}')} OR EXISTS (SELECT 1 FROM $table existing WHERE ${table == 'inventory_openings' ? '(existing.document_id = NEW.document_id OR existing.profile_id = NEW.profile_id OR existing.command_id = NEW.command_id)' : '(existing.id = NEW.id OR existing.product_id = NEW.product_id OR (existing.opening_id = NEW.opening_id AND (existing.sequence = NEW.sequence OR existing.source_product_id = NEW.source_product_id)))'} AND ${confirmed('existing.${table == 'inventory_openings' ? 'document_id' : 'opening_id'}')}))'
              : action == 'DELETE'
              ? confirmed('OLD.${table == 'inventory_openings' ? 'document_id' : 'opening_id'}')
              : '(${confirmed('OLD.${table == 'inventory_openings' ? 'document_id' : 'opening_id'}')} OR ${confirmed('NEW.${table == 'inventory_openings' ? 'document_id' : 'opening_id'}')})'}
BEGIN
  SELECT RAISE(ABORT, 'Confirmed initial inventory history is immutable');
END
''',
      for (final action in ['INSERT', 'UPDATE', 'DELETE'])
        '''
CREATE TRIGGER inventory_opening_journal_lines_no_${action.toLowerCase()}
BEFORE $action ON journal_lines
WHEN EXISTS (SELECT 1 FROM journal_entries entry JOIN inventory_openings opening ON opening.document_id = entry.document_id
  JOIN business_documents document ON document.id = opening.document_id
  WHERE entry.id = ${action == 'DELETE' ? 'OLD' : 'NEW'}.entry_id AND document.status <> 'draft')
  ${action == 'UPDATE' ? "OR EXISTS (SELECT 1 FROM journal_entries entry JOIN inventory_openings opening ON opening.document_id = entry.document_id JOIN business_documents document ON document.id = opening.document_id WHERE entry.id = OLD.entry_id AND document.status <> 'draft')" : ''}
BEGIN
  SELECT RAISE(ABORT, 'Confirmed initial inventory retains its exact journal lines');
END
''',
      for (final action in ['UPDATE', 'DELETE'])
        '''
CREATE TRIGGER inventory_opening_journal_entries_no_${action.toLowerCase()}
BEFORE $action ON journal_entries
WHEN EXISTS (SELECT 1 FROM inventory_openings opening JOIN business_documents document ON document.id = opening.document_id
  WHERE opening.document_id = OLD.document_id AND document.status <> 'draft')
  ${action == 'UPDATE' ? "AND NOT (OLD.status = 'draft' AND NEW.status = 'posted' AND NEW.id = OLD.id AND NEW.document_id = OLD.document_id AND NEW.reversal_of_id IS OLD.reversal_of_id AND NEW.cost_completeness = OLD.cost_completeness)" : ''}
BEGIN
  SELECT RAISE(ABORT, 'Confirmed initial inventory retains its exact journal entry');
END
''',
    ];
  }

  static String _paidPurchaseEntryMatches(String fact) =>
      '''EXISTS (
    SELECT 1 FROM paid_purchase_requests request
    JOIN purchases purchase ON purchase.document_id = $fact.purchase_document_id
    JOIN business_documents purchase_doc ON purchase_doc.id = purchase.document_id
    JOIN journal_entries purchase_entry ON purchase_entry.document_id = purchase_doc.id
    JOIN purchase_lines line ON line.purchase_id = purchase.document_id
    JOIN obligations payable ON payable.origin_document_id = purchase.document_id
    JOIN supplier_payments payment ON payment.document_id = $fact.payment_document_id
    JOIN business_documents payment_doc ON payment_doc.id = payment.document_id
    JOIN journal_entries payment_entry ON payment_entry.document_id = payment_doc.id
    JOIN supplier_payment_requests payment_request ON payment_request.command_id = payment_doc.command_id
    JOIN payable_settlements settlement ON settlement.supplier_payment_id = payment.document_id
    JOIN supplier_payment_parts part ON part.supplier_payment_id = payment.document_id
    JOIN catalog_items product ON product.id = $fact.product_id
    JOIN categories category ON category.id = $fact.category_id
    JOIN counterparties supplier ON supplier.id = $fact.supplier_id
    JOIN quick_payment_options option ON option.id = $fact.payment_option_id
    WHERE request.command_id = $fact.request_id AND request.status = 'executing'
      AND purchase_doc.command_id = request.purchase_command_id AND payment_doc.command_id = request.payment_command_id
      AND purchase_doc.status = 'posted' AND purchase_entry.status = 'posted'
      AND payment_doc.status = 'posted' AND payment_entry.status = 'posted' AND payment_request.status = 'confirmed'
      AND purchase_doc.actor_id = payment_doc.actor_id AND purchase_doc.profile_id = payment_doc.profile_id
      AND purchase_doc.occurred_at_utc = request.occurred_at_utc AND payment_doc.occurred_at_utc = request.occurred_at_utc
      AND json_extract(request.canonical_payload, '\$.occurredAtUtc') IS request.occurred_at_utc
      AND json_extract(request.canonical_payload, '\$.profileId') IS purchase_doc.profile_id
      AND purchase.supplier_id = $fact.supplier_id AND purchase.supplier_name_snapshot = $fact.supplier_name_snapshot
      AND purchase.payable_minor = $fact.total_cost_minor AND purchase.supplier_reference IS NULL
      AND purchase.due_date = purchase_doc.business_date
      AND (SELECT count(*) FROM purchase_lines WHERE purchase_id = purchase.document_id) = 1
      AND line.product_id = $fact.product_id AND line.name_snapshot = $fact.product_name_snapshot
      AND line.quantity = $fact.quantity AND line.acquisition_total_minor = $fact.total_cost_minor
      AND product.is_active = 1 AND product.name = $fact.product_name_snapshot AND product.sku IS $fact.sku_snapshot
      AND product.category_id = $fact.category_id AND product.list_price_minor = $fact.list_price_minor
      AND category.is_active = 1 AND category.name = $fact.category_name_snapshot
      AND supplier.is_active = 1 AND supplier.is_supplier = 1 AND supplier.name = $fact.supplier_name_snapshot
      AND payment.payable_id = payable.id AND payment.total_minor = $fact.total_cost_minor AND payment.remaining_minor = 0
      AND settlement.payable_id = payable.id AND settlement.amount_minor = $fact.total_cost_minor
      AND (SELECT count(*) FROM payable_settlements WHERE payable_id = payable.id) = 1
      AND (SELECT count(*) FROM supplier_payment_parts WHERE supplier_payment_id = payment.document_id) = 1
      AND part.amount_minor = $fact.total_cost_minor AND part.cash_account_id = $fact.cash_account_id
      AND part.payment_method_id = $fact.payment_method_id
      AND part.cash_account_name_snapshot = $fact.cash_account_name_snapshot
      AND part.cash_account_kind_snapshot = $fact.cash_account_kind_snapshot
      AND part.payment_method_code_snapshot = $fact.payment_method_code_snapshot
      AND part.payment_method_name_snapshot = $fact.payment_method_name_snapshot
      AND option.is_active = 1 AND option.cash_account_id = $fact.cash_account_id AND option.payment_method_id = $fact.payment_method_id
      AND json_extract(request.canonical_payload, '\$.productId') IS $fact.product_id
      AND json_extract(request.canonical_payload, '\$.productName') IS $fact.product_name_snapshot
      AND json_extract(request.canonical_payload, '\$.sku') IS $fact.sku_snapshot
      AND json_extract(request.canonical_payload, '\$.categoryId') IS $fact.category_id
      AND json_extract(request.canonical_payload, '\$.categoryName') IS $fact.category_name_snapshot
      AND json_extract(request.canonical_payload, '\$.supplierId') IS $fact.supplier_id
      AND json_extract(request.canonical_payload, '\$.supplierName') IS $fact.supplier_name_snapshot
      AND json_extract(request.canonical_payload, '\$.quantity') IS $fact.quantity
      AND json_extract(request.canonical_payload, '\$.unitPurchasePriceMinor') IS $fact.unit_purchase_price_minor
      AND json_extract(request.canonical_payload, '\$.listPriceMinor') IS $fact.list_price_minor
      AND json_extract(request.canonical_payload, '\$.totalCostMinor') IS $fact.total_cost_minor
      AND json_extract(request.canonical_payload, '\$.paymentOptionId') IS $fact.payment_option_id
      AND json_extract(request.canonical_payload, '\$.paymentOptionLabel') IS $fact.payment_option_label_snapshot
      AND json_extract(request.canonical_payload, '\$.cashAccountId') IS $fact.cash_account_id
      AND json_extract(request.canonical_payload, '\$.paymentMethodId') IS $fact.payment_method_id
      AND json_extract(request.canonical_payload, '\$.cashAccountName') IS $fact.cash_account_name_snapshot
      AND json_extract(request.canonical_payload, '\$.cashAccountKind') IS $fact.cash_account_kind_snapshot
      AND json_extract(request.canonical_payload, '\$.paymentMethodCode') IS $fact.payment_method_code_snapshot
      AND json_extract(request.canonical_payload, '\$.paymentMethodName') IS $fact.payment_method_name_snapshot
  )''';

  static String _paidPurchaseConfirmedResult() =>
      '''EXISTS (
    SELECT 1 FROM paid_purchase_entries fact JOIN command_log parent ON parent.id = fact.request_id
    JOIN business_documents purchase_doc ON purchase_doc.id = fact.purchase_document_id
    JOIN business_documents payment_doc ON payment_doc.id = fact.payment_document_id
    WHERE fact.request_id = OLD.command_id AND parent.command_type = 'paid_purchase'
      AND parent.actor_id = purchase_doc.actor_id AND parent.actor_id = payment_doc.actor_id
      AND parent.authorization_policy_version = 'development-single-user-v1'
      AND purchase_doc.command_id = OLD.purchase_command_id AND payment_doc.command_id = OLD.payment_command_id
      AND ${_paidPurchaseEntryMatches('fact')}
  )''';

  static List<String> _freezeCashOpeningFacts() => [
    '''
CREATE TRIGGER cash_opening_entries_no_replace
BEFORE INSERT ON journal_entries
WHEN EXISTS (SELECT 1 FROM journal_entries existing JOIN cash_openings opening ON opening.document_id = existing.document_id
  JOIN business_documents document ON document.id = opening.document_id
  WHERE (existing.id = NEW.id OR existing.document_id = NEW.document_id) AND document.status <> 'draft')
BEGIN
  SELECT RAISE(ABORT, 'Confirmed cash opening journal entries cannot be replaced');
END
''',
    '''
CREATE TRIGGER cash_opening_entries_no_conflicting_update
BEFORE UPDATE ON journal_entries
WHEN EXISTS (SELECT 1 FROM journal_entries existing JOIN cash_openings opening ON opening.document_id = existing.document_id
  JOIN business_documents document ON document.id = opening.document_id
  WHERE existing.id <> OLD.id AND (existing.id = NEW.id OR existing.document_id = NEW.document_id)
    AND document.status <> 'draft')
BEGIN
  SELECT RAISE(ABORT, 'Confirmed cash opening journal entries cannot be replaced through an update');
END
''',
    '''
CREATE TRIGGER cash_opening_lines_no_replace
BEFORE INSERT ON journal_lines
WHEN EXISTS (SELECT 1 FROM journal_lines existing JOIN journal_entries entry ON entry.id = existing.entry_id
  JOIN cash_openings opening ON opening.document_id = entry.document_id
  JOIN business_documents document ON document.id = opening.document_id
  WHERE (existing.id = NEW.id OR (existing.entry_id = NEW.entry_id AND existing.sequence = NEW.sequence))
    AND document.status <> 'draft')
BEGIN
  SELECT RAISE(ABORT, 'Confirmed cash opening journal lines cannot be replaced');
END
''',
    '''
CREATE TRIGGER cash_opening_lines_no_conflicting_update
BEFORE UPDATE ON journal_lines
WHEN EXISTS (SELECT 1 FROM journal_lines existing JOIN journal_entries entry ON entry.id = existing.entry_id
  JOIN cash_openings opening ON opening.document_id = entry.document_id
  JOIN business_documents document ON document.id = opening.document_id
  WHERE existing.id <> OLD.id AND (existing.id = NEW.id OR (existing.entry_id = NEW.entry_id AND existing.sequence = NEW.sequence))
    AND document.status <> 'draft')
BEGIN
  SELECT RAISE(ABORT, 'Confirmed cash opening journal lines cannot be replaced through an update');
END
''',
    for (final action in ['UPDATE', 'DELETE'])
      '''
CREATE TRIGGER cash_openings_no_${action.toLowerCase()}
BEFORE $action ON cash_openings
BEGIN
  SELECT RAISE(ABORT, 'Explicit opening balances are immutable');
END
''',
    for (final action in ['UPDATE', 'DELETE'])
      '''
CREATE TRIGGER cash_opening_entries_no_${action.toLowerCase()}
BEFORE $action ON journal_entries
WHEN EXISTS (SELECT 1 FROM cash_openings opening JOIN business_documents document ON document.id = opening.document_id
  WHERE opening.document_id = OLD.document_id AND document.status <> 'draft')
  ${action == 'UPDATE' ? "AND NOT (OLD.status = 'draft' AND NEW.status = 'posted' AND NEW.id = OLD.id AND NEW.document_id = OLD.document_id AND NEW.reversal_of_id IS OLD.reversal_of_id AND NEW.cost_completeness = OLD.cost_completeness)" : ''}
BEGIN
  SELECT RAISE(ABORT, 'Confirmed cash openings retain their exact journal');
END
''',
    for (final action in ['INSERT', 'UPDATE', 'DELETE'])
      '''
CREATE TRIGGER cash_opening_lines_no_${action.toLowerCase()}
BEFORE $action ON journal_lines
WHEN EXISTS (SELECT 1 FROM journal_entries entry JOIN cash_openings opening ON opening.document_id = entry.document_id
  JOIN business_documents document ON document.id = opening.document_id
  WHERE entry.id = ${action == 'DELETE' ? 'OLD' : 'NEW'}.entry_id AND document.status <> 'draft')
  ${action == 'UPDATE' ? "OR EXISTS (SELECT 1 FROM journal_entries entry JOIN cash_openings opening ON opening.document_id = entry.document_id JOIN business_documents document ON document.id = opening.document_id WHERE entry.id = OLD.entry_id AND document.status <> 'draft')" : ''}
BEGIN
  SELECT RAISE(ABORT, 'Confirmed cash opening journal lines are immutable');
END
''',
  ];

  static List<String> _freezeQuickDraftLines() {
    String locked(String row) =>
        '''EXISTS (SELECT 1 FROM quick_sales_accounts account
WHERE account.id = $row.account_id AND (account.status <> 'open' OR EXISTS (
  SELECT 1 FROM quick_sale_requests request WHERE request.account_id = account.id
    AND request.status <> 'cancelled')))''';
    return [
      for (final action in ['INSERT', 'UPDATE', 'DELETE'])
        '''
CREATE TRIGGER quick_sales_lines_locked_no_${action.toLowerCase()}
BEFORE $action ON quick_sales_lines
WHEN ${action == 'INSERT'
            ? '(${locked('NEW')} OR EXISTS (SELECT 1 FROM quick_sales_lines existing WHERE (existing.id = NEW.id OR (existing.account_id = NEW.account_id AND existing.sequence = NEW.sequence)) AND ${locked('existing')}))'
            : action == 'DELETE'
            ? locked('OLD')
            : '(${locked('OLD')} OR ${locked('NEW')} OR EXISTS (SELECT 1 FROM quick_sales_lines existing WHERE existing.id <> OLD.id AND (existing.id = NEW.id OR (existing.account_id = NEW.account_id AND existing.sequence = NEW.sequence)) AND ${locked('existing')}))'}
BEGIN
  SELECT RAISE(ABORT, 'Prepared and closed quick account lines are locked');
END
''',
    ];
  }

  static String _quickConfirmedResult() =>
      '''EXISTS (
    SELECT 1 FROM command_log parent
    JOIN business_documents sale_doc ON sale_doc.command_id = OLD.sale_command_id
    JOIN sales sale ON sale.document_id = sale_doc.id
    JOIN journal_entries sale_entry ON sale_entry.document_id = sale_doc.id
    JOIN customer_receivables receivable ON receivable.origin_document_id = sale_doc.id
    JOIN business_documents collection_doc ON collection_doc.command_id = OLD.collection_command_id
    JOIN collections collection ON collection.document_id = collection_doc.id
    JOIN journal_entries collection_entry ON collection_entry.document_id = collection_doc.id
    JOIN sale_confirmations sale_request ON sale_request.command_id = OLD.sale_command_id
    JOIN collection_requests collection_request ON collection_request.command_id = OLD.collection_command_id
    WHERE parent.id = OLD.command_id AND parent.command_type = 'quick_sale'
      AND parent.actor_id = sale_doc.actor_id AND sale_doc.actor_id = collection_doc.actor_id
      AND parent.authorization_policy_version = 'development-single-user-v1'
      AND sale.draft_id = OLD.legacy_draft_id AND sale_doc.status = 'posted' AND sale_entry.status = 'posted'
      AND sale_doc.occurred_at_utc = OLD.occurred_at_utc AND collection_doc.occurred_at_utc = OLD.occurred_at_utc
      AND collection_doc.status = 'posted' AND collection_entry.status = 'posted'
      AND sale_request.status = 'confirmed' AND collection_request.status = 'confirmed'
      AND collection.receivable_id = receivable.id AND collection.total_minor = sale.receivable_minor
      AND collection.remaining_minor = 0
      AND (SELECT count(*) FROM quick_sale_line_payments WHERE request_id = OLD.command_id)
        = (SELECT count(*) FROM quick_sales_lines WHERE account_id = OLD.account_id)
      AND EXISTS (SELECT 1 FROM quick_sale_line_payments WHERE request_id = OLD.command_id)
      AND ${_supplierBoundedRemainder('sale.receivable_minor', 'quick_sale_line_payments payment', 'payment.request_id = OLD.command_id', 'payment.total_minor', 'payment.sequence')} = 0
      AND NOT EXISTS (SELECT 1 FROM sale_lines line WHERE line.sale_id = sale.document_id
        AND ${_supplierBoundedRemainder('line.quantity', 'quick_sale_line_payments payment', 'payment.request_id = OLD.command_id AND payment.sale_line_id = line.id', 'payment.quantity', 'payment.sequence')} <> 0)
      AND NOT EXISTS (SELECT 1 FROM collection_parts part WHERE part.collection_id = collection.document_id
        AND ${_supplierBoundedRemainder('part.amount_minor', 'quick_sale_line_payments payment', 'payment.request_id = OLD.command_id AND payment.cash_account_id = part.cash_account_id AND payment.payment_method_id = part.payment_method_id', 'payment.total_minor', 'payment.sequence')} <> 0)
      AND NOT EXISTS (SELECT 1 FROM quick_sale_line_payments payment WHERE payment.request_id = OLD.command_id
        AND payment.total_minor > 0 AND NOT EXISTS (SELECT 1 FROM collection_parts part
          WHERE part.collection_id = collection.document_id AND part.cash_account_id = payment.cash_account_id
            AND part.payment_method_id = payment.payment_method_id)))''';

  // Subtract positive facts from an int64 budget rather than SUMming them.
  // A malformed aggregate becomes -1 without overflowing or using floats.
  static String _supplierBoundedRemainder(
    String initial,
    String source,
    String condition,
    String amount,
    String order,
  ) =>
      '''(WITH RECURSIVE ordered AS (
    SELECT $amount AS amount, row_number() OVER (ORDER BY $order) AS n
    FROM $source WHERE $condition
  ), budget(n, remaining) AS (
    SELECT 0, $initial
    UNION ALL
    SELECT ordered.n, CASE WHEN ordered.amount <= budget.remaining
      THEN budget.remaining - ordered.amount ELSE -1 END
    FROM budget JOIN ordered ON ordered.n = budget.n + 1
    WHERE budget.remaining >= 0
  ) SELECT remaining FROM budget ORDER BY n DESC LIMIT 1)''';

  static String _supplierPriorPayableRemainder() => _supplierBoundedRemainder(
    'r.initial_minor',
    'payable_settlements previous JOIN business_documents previous_doc '
        'ON previous_doc.id = previous.supplier_payment_id',
    "previous.payable_id = r.id AND previous.supplier_payment_id <> NEW.id "
        "AND previous_doc.status <> 'draft'",
    'previous.amount_minor',
    'previous.supplier_payment_id',
  );

  // Preserve integer precision even when historical gross debits exceed int64.
  // Each chronological intermediate must be representable; invalid historical
  // balances are refused conservatively instead of wrapping or rounding.
  static String _supplierMoneyInsufficient() =>
      '''EXISTS (
    WITH RECURSIVE accounts AS (
      SELECT DISTINCT cash.id, cash.ledger_account_id
      FROM supplier_payment_parts part JOIN cash_accounts cash ON cash.id = part.cash_account_id
      WHERE part.supplier_payment_id = NEW.id
    ), ordered AS (
      SELECT account.id, line.debit_minor, line.credit_minor,
        row_number() OVER (PARTITION BY account.id ORDER BY
          ${_utcSortKey('doc.occurred_at_utc')}, doc.recorded_at_utc, doc.id, line.sequence) AS n
      FROM accounts account JOIN journal_lines line ON line.account_id = account.ledger_account_id
      JOIN journal_entries entry ON entry.id = line.entry_id
      JOIN business_documents doc ON doc.id = entry.document_id
      WHERE doc.id <> NEW.id AND doc.status <> 'draft'
        AND (entry.status = 'posted' OR doc.type = 'supplier_payment')
    ), balances(id, n, balance, valid) AS (
      SELECT id, 0, 0, 1 FROM accounts
      UNION ALL
      SELECT prior.id, line.n,
        CASE WHEN prior.valid = 0 THEN 0
          WHEN line.debit_minor > 0 THEN CASE
            WHEN prior.balance <= 9223372036854775807 - line.debit_minor
              THEN prior.balance + line.debit_minor ELSE 0 END
          ELSE CASE WHEN prior.balance >= -9223372036854775808 + line.credit_minor
            THEN prior.balance - line.credit_minor ELSE 0 END END,
        CASE WHEN prior.valid = 1 AND
          ((line.debit_minor > 0 AND prior.balance <= 9223372036854775807 - line.debit_minor)
          OR (line.credit_minor > 0 AND prior.balance >= -9223372036854775808 + line.credit_minor))
          THEN 1 ELSE 0 END
      FROM balances prior JOIN ordered line ON line.id = prior.id AND line.n = prior.n + 1
    ) SELECT 1 FROM accounts account WHERE NOT EXISTS (
      SELECT 1 FROM balances final WHERE final.id = account.id AND final.valid = 1
        AND final.n = (SELECT count(*) FROM ordered WHERE id = account.id)
        AND ${_supplierBoundedRemainder('final.balance', 'supplier_payment_parts part', 'part.supplier_payment_id = NEW.id AND part.cash_account_id = account.id', 'part.amount_minor', 'part.sequence')} >= 0)
  )''';

  static List<String> _freezeSupplierPaymentFacts(
    String table,
    String documentColumn,
    String conflicts,
  ) {
    String confirmed(String row) =>
        '''EXISTS (SELECT 1 FROM business_documents d
WHERE d.id = $row.$documentColumn AND d.status <> 'draft')''';
    final insertGuard = '''(${confirmed('NEW')} OR EXISTS (
SELECT 1 FROM $table existing WHERE ($conflicts) AND ${confirmed('existing')}))''';
    return [
      for (final action in ['INSERT', 'UPDATE', 'DELETE'])
        '''
CREATE TRIGGER ${table}_confirmed_no_${action.toLowerCase()}
BEFORE $action ON $table
WHEN ${action == 'INSERT'
            ? insertGuard
            : action == 'DELETE'
            ? confirmed('OLD')
            : '(${confirmed('OLD')} OR $insertGuard)'}
BEGIN
  SELECT RAISE(ABORT, 'Confirmed supplier_payment history is immutable');
END
''',
    ];
  }

  static List<String> _freezeSupplierPaymentJournal() {
    String confirmed(String row) =>
        '''EXISTS (SELECT 1 FROM business_documents d
WHERE d.id = $row.document_id AND d.type = 'supplier_payment' AND d.status <> 'draft')''';
    String linesConfirmed(String row) =>
        '''EXISTS (SELECT 1 FROM journal_entries e
JOIN business_documents d ON d.id = e.document_id
WHERE e.id = $row.entry_id AND d.type = 'supplier_payment' AND d.status <> 'draft')''';
    return [
      '''
CREATE TRIGGER supplier_payment_entries_confirmed_no_delete
BEFORE DELETE ON journal_entries
WHEN ${confirmed('OLD')}
BEGIN
  SELECT RAISE(ABORT, 'A confirmed supplier_payment requires its journal entry');
END
''',
      '''
CREATE TRIGGER supplier_payment_entries_confirmed_no_rewrite
BEFORE UPDATE ON journal_entries
WHEN ${confirmed('OLD')}
  AND (NEW.id <> OLD.id OR NEW.document_id <> OLD.document_id
    OR NEW.cost_completeness <> OLD.cost_completeness
    OR NEW.reversal_of_id IS NOT OLD.reversal_of_id OR NEW.status <> 'posted')
BEGIN
  SELECT RAISE(ABORT, 'Only posting is allowed on a confirmed supplier_payment journal');
END
''',
      '''
CREATE TRIGGER supplier_payment_entries_confirmed_no_replace
BEFORE INSERT ON journal_entries
WHEN EXISTS (SELECT 1 FROM journal_entries e JOIN business_documents d ON d.id = e.document_id
  WHERE (e.id = NEW.id OR e.document_id = NEW.document_id)
    AND d.type = 'supplier_payment' AND d.status <> 'draft')
BEGIN
  SELECT RAISE(ABORT, 'Confirmed supplier_payment journal entries cannot be replaced');
END
''',
      '''
CREATE TRIGGER supplier_payment_entries_confirmed_no_conflicting_update
BEFORE UPDATE ON journal_entries
WHEN EXISTS (SELECT 1 FROM journal_entries e JOIN business_documents d ON d.id = e.document_id
  WHERE e.id <> OLD.id AND (e.id = NEW.id OR e.document_id = NEW.document_id)
    AND d.type = 'supplier_payment' AND d.status <> 'draft')
BEGIN
  SELECT RAISE(ABORT, 'Confirmed supplier_payment journal entries cannot be replaced through an update');
END
''',
      for (final action in ['INSERT', 'UPDATE', 'DELETE'])
        '''
CREATE TRIGGER supplier_payment_journal_lines_confirmed_no_${action.toLowerCase()}
BEFORE $action ON journal_lines
WHEN ${action == 'INSERT'
            ? linesConfirmed('NEW')
            : action == 'DELETE'
            ? linesConfirmed('OLD')
            : '(${linesConfirmed('OLD')} OR ${linesConfirmed('NEW')})'}
BEGIN
  SELECT RAISE(ABORT, 'Confirmed supplier_payment journal lines are immutable');
END
''',
      '''
CREATE TRIGGER supplier_payment_journal_lines_confirmed_no_replace
BEFORE INSERT ON journal_lines
WHEN EXISTS (SELECT 1 FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id
  JOIN business_documents d ON d.id = e.document_id
  WHERE (l.id = NEW.id OR (l.entry_id = NEW.entry_id AND l.sequence = NEW.sequence))
    AND d.type = 'supplier_payment' AND d.status <> 'draft')
BEGIN
  SELECT RAISE(ABORT, 'Confirmed supplier_payment journal lines cannot be replaced');
END
''',
      '''
CREATE TRIGGER supplier_payment_journal_lines_confirmed_no_conflicting_update
BEFORE UPDATE ON journal_lines
WHEN EXISTS (SELECT 1 FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id
  JOIN business_documents d ON d.id = e.document_id
  WHERE l.id <> OLD.id AND (l.id = NEW.id OR (l.entry_id = NEW.entry_id AND l.sequence = NEW.sequence))
    AND d.type = 'supplier_payment' AND d.status <> 'draft')
BEGIN
  SELECT RAISE(ABORT, 'Confirmed supplier_payment journal lines cannot be replaced through an update');
END
''',
    ];
  }

  static String _collectionUtc(String column) =>
      "length($column) IN (24, 27) AND substr($column, 20, 1) = '.' "
      "AND substr($column, -1) = 'Z' "
      "AND substr($column, 21, length($column) - 21) NOT GLOB '*[^0-9]*' "
      "AND strftime('%Y-%m-%dT%H:%M:%S', substr($column, 1, 19) || 'Z') IS NOT NULL "
      "AND strftime('%Y-%m-%dT%H:%M:%S', substr($column, 1, 19) || 'Z') = substr($column, 1, 19)";

  static List<String> _freezeCollectionFacts(
    String table,
    String documentColumn,
    String conflicts,
  ) {
    String confirmed(String row) =>
        '''EXISTS (SELECT 1 FROM business_documents d
WHERE d.id = $row.$documentColumn AND d.status <> 'draft')''';
    final insertGuard = '''(${confirmed('NEW')} OR EXISTS (
SELECT 1 FROM $table existing WHERE ($conflicts) AND ${confirmed('existing')}))''';
    return [
      for (final action in ['INSERT', 'UPDATE', 'DELETE'])
        '''
CREATE TRIGGER ${table}_confirmed_no_${action.toLowerCase()}
BEFORE $action ON $table
WHEN ${action == 'INSERT'
            ? insertGuard
            : action == 'DELETE'
            ? confirmed('OLD')
            : '(${confirmed('OLD')} OR $insertGuard)'}
BEGIN
  SELECT RAISE(ABORT, 'Confirmed collection history is immutable');
END
''',
    ];
  }

  static List<String> _freezeCollectionJournal() {
    String confirmed(String row) =>
        '''EXISTS (SELECT 1 FROM business_documents d
WHERE d.id = $row.document_id AND d.type = 'customer_collection' AND d.status <> 'draft')''';
    String linesConfirmed(String row) =>
        '''EXISTS (SELECT 1 FROM journal_entries e
JOIN business_documents d ON d.id = e.document_id
WHERE e.id = $row.entry_id AND d.type = 'customer_collection' AND d.status <> 'draft')''';
    return [
      '''
CREATE TRIGGER collection_entries_confirmed_no_delete
BEFORE DELETE ON journal_entries
WHEN ${confirmed('OLD')}
BEGIN
  SELECT RAISE(ABORT, 'A confirmed collection requires its journal entry');
END
''',
      '''
CREATE TRIGGER collection_entries_confirmed_no_rewrite
BEFORE UPDATE ON journal_entries
WHEN ${confirmed('OLD')}
  AND (NEW.id <> OLD.id OR NEW.document_id <> OLD.document_id
    OR NEW.cost_completeness <> OLD.cost_completeness
    OR NEW.reversal_of_id IS NOT OLD.reversal_of_id OR NEW.status <> 'posted')
BEGIN
  SELECT RAISE(ABORT, 'Only posting is allowed on a confirmed collection journal');
END
''',
      '''
CREATE TRIGGER collection_entries_confirmed_no_replace
BEFORE INSERT ON journal_entries
WHEN EXISTS (SELECT 1 FROM journal_entries e JOIN business_documents d ON d.id = e.document_id
  WHERE (e.id = NEW.id OR e.document_id = NEW.document_id)
    AND d.type = 'customer_collection' AND d.status <> 'draft')
BEGIN
  SELECT RAISE(ABORT, 'Confirmed collection journal entries cannot be replaced');
END
''',
      '''
CREATE TRIGGER collection_entries_confirmed_no_conflicting_update
BEFORE UPDATE ON journal_entries
WHEN EXISTS (SELECT 1 FROM journal_entries e JOIN business_documents d ON d.id = e.document_id
  WHERE e.id <> OLD.id AND (e.id = NEW.id OR e.document_id = NEW.document_id)
    AND d.type = 'customer_collection' AND d.status <> 'draft')
BEGIN
  SELECT RAISE(ABORT, 'Confirmed collection journal entries cannot be replaced through an update');
END
''',
      for (final action in ['INSERT', 'UPDATE', 'DELETE'])
        '''
CREATE TRIGGER collection_journal_lines_confirmed_no_${action.toLowerCase()}
BEFORE $action ON journal_lines
WHEN ${action == 'INSERT'
            ? linesConfirmed('NEW')
            : action == 'DELETE'
            ? linesConfirmed('OLD')
            : '(${linesConfirmed('OLD')} OR ${linesConfirmed('NEW')})'}
BEGIN
  SELECT RAISE(ABORT, 'Confirmed collection journal lines are immutable');
END
''',
      '''
CREATE TRIGGER collection_journal_lines_confirmed_no_replace
BEFORE INSERT ON journal_lines
WHEN EXISTS (SELECT 1 FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id
  JOIN business_documents d ON d.id = e.document_id
  WHERE (l.id = NEW.id OR (l.entry_id = NEW.entry_id AND l.sequence = NEW.sequence))
    AND d.type = 'customer_collection' AND d.status <> 'draft')
BEGIN
  SELECT RAISE(ABORT, 'Confirmed collection journal lines cannot be replaced');
END
''',
      '''
CREATE TRIGGER collection_journal_lines_confirmed_no_conflicting_update
BEFORE UPDATE ON journal_lines
WHEN EXISTS (SELECT 1 FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id
  JOIN business_documents d ON d.id = e.document_id
  WHERE l.id <> OLD.id AND (l.id = NEW.id OR (l.entry_id = NEW.entry_id AND l.sequence = NEW.sequence))
    AND d.type = 'customer_collection' AND d.status <> 'draft')
BEGIN
  SELECT RAISE(ABORT, 'Confirmed collection journal lines cannot be replaced through an update');
END
''',
    ];
  }

  static List<String> _freezeCollectionCatalogs() {
    String ledgerUsed(String alias) =>
        '''(EXISTS (SELECT 1 FROM cash_accounts WHERE ledger_account_id = $alias.id)
OR EXISTS (SELECT 1 FROM journal_lines WHERE account_id = $alias.id)
OR EXISTS (SELECT 1 FROM customer_receivables WHERE control_account_id = $alias.id)
OR EXISTS (SELECT 1 FROM obligations WHERE control_account_id = $alias.id))''';
    return [
      '''
CREATE TRIGGER ledger_accounts_used_identity_immutable_v4
BEFORE UPDATE ON ledger_accounts
WHEN ${ledgerUsed('OLD')} AND (NEW.id <> OLD.id OR NEW.code <> OLD.code
  OR NEW.class <> OLD.class OR NEW.role <> OLD.role)
BEGIN
  SELECT RAISE(ABORT, 'Configured or used ledger account identity and role are immutable');
END
''',
      '''
CREATE TRIGGER ledger_accounts_used_no_replace_v4
BEFORE INSERT ON ledger_accounts
WHEN EXISTS (SELECT 1 FROM ledger_accounts existing
  WHERE (existing.id = NEW.id OR existing.code = NEW.code) AND ${ledgerUsed('existing')})
BEGIN
  SELECT RAISE(ABORT, 'Configured or used ledger accounts cannot be replaced');
END
''',
      '''
CREATE TRIGGER ledger_accounts_used_no_conflicting_update_v4
BEFORE UPDATE ON ledger_accounts
WHEN EXISTS (SELECT 1 FROM ledger_accounts existing WHERE existing.id <> OLD.id
  AND (existing.id = NEW.id OR existing.code = NEW.code) AND ${ledgerUsed('existing')})
BEGIN
  SELECT RAISE(ABORT, 'Configured or used ledger accounts cannot be replaced through an update');
END
''',
      for (final table in ['cash_accounts', 'payment_methods']) ...[
        '''
CREATE TRIGGER ${table}_identity_immutable_v4
BEFORE UPDATE ON $table
WHEN NEW.id <> OLD.id OR ${table == 'cash_accounts' ? 'NEW.ledger_account_id <> OLD.ledger_account_id OR NEW.kind <> OLD.kind' : 'NEW.code <> OLD.code'}
BEGIN
  SELECT RAISE(ABORT, 'Configured payment identity is immutable; archive it instead');
END
''',
        '''
CREATE TRIGGER ${table}_no_replace_v4
BEFORE INSERT ON $table
WHEN EXISTS (SELECT 1 FROM $table existing WHERE existing.id = NEW.id OR
  ${table == 'cash_accounts' ? 'existing.ledger_account_id = NEW.ledger_account_id' : 'existing.code = NEW.code'})
BEGIN
  SELECT RAISE(ABORT, 'Configured payment catalogs cannot be replaced');
END
''',
        '''
CREATE TRIGGER ${table}_no_delete_v4
BEFORE DELETE ON $table
BEGIN
  SELECT RAISE(ABORT, 'Configured payment catalogs must be archived instead of deleted');
END
''',
      ],
    ];
  }

  // Dart emits three or six fractional digits. Padding to microseconds keeps
  // chronological ordering exact without SQLite's millisecond date rounding.
  static String _utcSortKey(String column) =>
      "(substr($column, 1, 19) || '.' || "
      "substr(substr($column, 21, length($column) - 21) || '000000', 1, 6) || 'Z')";

  static List<String> _freezeSaleDraftLines() {
    String locked(String row) =>
        '''EXISTS (SELECT 1 FROM sales_drafts d
WHERE d.id = $row.draft_id AND (d.status <> 'open' OR EXISTS (
SELECT 1 FROM sale_confirmations c WHERE c.draft_id = d.id AND c.status <> 'cancelled')))''';
    return [
      for (final action in ['INSERT', 'UPDATE', 'DELETE'])
        '''
CREATE TRIGGER sales_draft_lines_locked_no_${action.toLowerCase()}
BEFORE $action ON sales_draft_lines
WHEN ${action == 'INSERT'
            ? locked('NEW')
            : action == 'DELETE'
            ? locked('OLD')
            : '(${locked('OLD')} OR ${locked('NEW')})'}
BEGIN
  SELECT RAISE(ABORT, 'Prepared and confirmed sale account lines are locked');
END
''',
    ];
  }

  static List<String> _freezeSaleFacts(
    String table,
    String documentColumn,
    String conflicts,
  ) {
    String confirmed(String row) =>
        '''EXISTS (SELECT 1 FROM business_documents d
WHERE d.id = $row.$documentColumn AND d.status <> 'draft')''';
    final insertGuard = '''(${confirmed('NEW')} OR EXISTS (
SELECT 1 FROM $table existing WHERE ($conflicts) AND ${confirmed('existing')}))''';
    return [
      for (final action in ['INSERT', 'UPDATE', 'DELETE'])
        '''
CREATE TRIGGER ${table}_confirmed_no_${action.toLowerCase()}
BEFORE $action ON $table
WHEN ${action == 'INSERT'
            ? insertGuard
            : action == 'DELETE'
            ? confirmed('OLD')
            : '(${confirmed('OLD')} OR $insertGuard)'}
BEGIN
  SELECT RAISE(ABORT, 'Confirmed sale history is immutable');
END
''',
    ];
  }

  static List<String> _freezeSaleJournal() {
    String confirmed(String row) =>
        '''EXISTS (SELECT 1 FROM business_documents d
WHERE d.id = $row.document_id AND d.type = 'credit_sale' AND d.status <> 'draft')''';
    String linesConfirmed(String row) =>
        '''EXISTS (SELECT 1 FROM journal_entries e
JOIN business_documents d ON d.id = e.document_id
WHERE e.id = $row.entry_id AND d.type = 'credit_sale' AND d.status <> 'draft')''';
    return [
      '''
CREATE TRIGGER sale_entries_confirmed_no_delete
BEFORE DELETE ON journal_entries
WHEN ${confirmed('OLD')}
BEGIN
  SELECT RAISE(ABORT, 'A confirmed sale requires its journal entry');
END
''',
      '''
CREATE TRIGGER sale_entries_confirmed_no_rewrite
BEFORE UPDATE ON journal_entries
WHEN ${confirmed('OLD')}
  AND (NEW.id <> OLD.id OR NEW.document_id <> OLD.document_id
    OR NEW.cost_completeness <> OLD.cost_completeness
    OR NEW.reversal_of_id IS NOT OLD.reversal_of_id OR NEW.status <> 'posted')
BEGIN
  SELECT RAISE(ABORT, 'Only posting is allowed on a confirmed sale journal');
END
''',
      '''
CREATE TRIGGER sale_entries_confirmed_no_replace
BEFORE INSERT ON journal_entries
WHEN EXISTS (SELECT 1 FROM journal_entries e
  JOIN business_documents d ON d.id = e.document_id
  WHERE (e.id = NEW.id OR e.document_id = NEW.document_id)
    AND d.type = 'credit_sale' AND d.status <> 'draft')
BEGIN
  SELECT RAISE(ABORT, 'Confirmed sale journal entries cannot be replaced');
END
''',
      '''
CREATE TRIGGER sale_entries_confirmed_no_conflicting_update
BEFORE UPDATE ON journal_entries
WHEN EXISTS (SELECT 1 FROM journal_entries e
  JOIN business_documents d ON d.id = e.document_id
  WHERE e.id <> OLD.id AND (e.id = NEW.id OR e.document_id = NEW.document_id)
    AND d.type = 'credit_sale' AND d.status <> 'draft')
BEGIN
  SELECT RAISE(ABORT, 'Confirmed sale journal entries cannot be replaced through an update');
END
''',
      for (final action in ['INSERT', 'UPDATE', 'DELETE'])
        '''
CREATE TRIGGER sale_journal_lines_confirmed_no_${action.toLowerCase()}
BEFORE $action ON journal_lines
WHEN ${action == 'INSERT'
            ? linesConfirmed('NEW')
            : action == 'DELETE'
            ? linesConfirmed('OLD')
            : '(${linesConfirmed('OLD')} OR ${linesConfirmed('NEW')})'}
BEGIN
  SELECT RAISE(ABORT, 'Confirmed sale journal lines are immutable');
END
''',
      '''
CREATE TRIGGER sale_journal_lines_confirmed_no_replace
BEFORE INSERT ON journal_lines
WHEN EXISTS (SELECT 1 FROM journal_lines l
  JOIN journal_entries e ON e.id = l.entry_id
  JOIN business_documents d ON d.id = e.document_id
  WHERE (l.id = NEW.id OR (l.entry_id = NEW.entry_id AND l.sequence = NEW.sequence))
    AND d.type = 'credit_sale' AND d.status <> 'draft')
BEGIN
  SELECT RAISE(ABORT, 'Confirmed sale journal lines cannot be replaced');
END
''',
      '''
CREATE TRIGGER sale_journal_lines_confirmed_no_conflicting_update
BEFORE UPDATE ON journal_lines
WHEN EXISTS (SELECT 1 FROM journal_lines l
  JOIN journal_entries e ON e.id = l.entry_id
  JOIN business_documents d ON d.id = e.document_id
  WHERE (l.id = NEW.id OR (l.entry_id = NEW.entry_id AND l.sequence = NEW.sequence))
    AND d.type = 'credit_sale' AND d.status <> 'draft')
BEGIN
  SELECT RAISE(ABORT, 'Confirmed sale journal lines cannot be replaced through an update');
END
''',
    ];
  }

  static List<String> _freezeCommercialTable(
    String table,
    String documentColumn, {
    bool throughMovement = false,
  }) {
    String confirmed(String row) => throughMovement
        ? '''EXISTS (SELECT 1 FROM inventory_movements m
JOIN business_documents d ON d.id = m.document_id
WHERE m.id = $row.$documentColumn AND d.status <> 'draft')'''
        : '''EXISTS (SELECT 1 FROM business_documents d
WHERE d.id = $row.$documentColumn AND d.status <> 'draft')''';
    final conflict = switch (table) {
      'purchases' => 'existing.document_id = NEW.document_id',
      'inventory_movements' =>
        '''existing.id = NEW.id
OR existing.stock_sequence = NEW.stock_sequence
OR existing.purchase_line_id = NEW.purchase_line_id
OR (existing.document_id = NEW.document_id AND existing.sequence = NEW.sequence)''',
      'cost_layers' =>
        '''existing.id = NEW.id
OR existing.inbound_movement_id = NEW.inbound_movement_id
OR existing.fifo_sequence = NEW.fifo_sequence''',
      _ => 'existing.id = NEW.id',
    };
    final insertGuard = '''(${confirmed('NEW')} OR EXISTS (
SELECT 1 FROM $table existing WHERE ($conflict) AND ${confirmed('existing')}))''';
    return [
      for (final action in ['INSERT', 'UPDATE', 'DELETE'])
        '''
CREATE TRIGGER ${table}_confirmed_no_${action.toLowerCase()}
BEFORE $action ON $table
WHEN ${action == 'INSERT'
            ? insertGuard
            : action == 'DELETE'
            ? confirmed('OLD')
            : '(${confirmed('OLD')} OR $insertGuard)'}
BEGIN
  SELECT RAISE(ABORT, 'Confirmed purchase history is immutable');
END
''',
    ];
  }

  static List<String> _freezePurchaseJournalLines() {
    String confirmed(String row) => '''EXISTS (SELECT 1 FROM journal_entries e
JOIN business_documents d ON d.id = e.document_id
WHERE e.id = $row.entry_id AND d.type = 'purchase_receipt' AND d.status <> 'draft')''';
    return [
      for (final action in ['INSERT', 'UPDATE', 'DELETE'])
        '''
CREATE TRIGGER purchase_journal_lines_confirmed_no_${action.toLowerCase()}
BEFORE $action ON journal_lines
WHEN ${action == 'INSERT'
            ? confirmed('NEW')
            : action == 'DELETE'
            ? confirmed('OLD')
            : '(${confirmed('OLD')} OR ${confirmed('NEW')})'}
BEGIN
  SELECT RAISE(ABORT, 'Confirmed purchase journal lines are immutable');
END
''',
    ];
  }
}
