import 'dart:convert';

/// Immutable bootstrap schema. Later changes require a new schema version.
abstract final class DatabaseSchema {
  static const int version = 1;

  // ASCII VS20: a file-format marker, independent of the original POS.
  static const int applicationId = 0x56533230;
  static const String migrationName = 'foundation_v1';

  /// Detects accidental changes; this checksum is not a security signature.
  static String get migrationChecksum => checksum(statements.join('\n;\n'));

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
}
