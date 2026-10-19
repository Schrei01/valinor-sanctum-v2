import 'dart:convert';

/// Immutable bootstrap schema. Later changes require a new schema version.
abstract final class DatabaseSchema {
  static const int version = 2;

  // ASCII VS20: a file-format marker, independent of the original POS.
  static const int applicationId = 0x56533230;
  static const String migrationName = 'foundation_v1';

  /// Detects accidental changes; this checksum is not a security signature.
  static String get migrationChecksum => checksum(statements.join('\n;\n'));

  static const String migration2Name = 'catalog_credit_receipts_v2';
  static String get migration2Checksum =>
      checksum(migration2Statements.join('\n;\n'));

  static String nameForVersion(int version) => switch (version) {
    1 => migrationName,
    2 => migration2Name,
    _ => throw ArgumentError.value(version, 'version'),
  };

  static String checksumForVersion(int version) => switch (version) {
    1 => migrationChecksum,
    2 => migration2Checksum,
    _ => throw ArgumentError.value(version, 'version'),
  };

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
