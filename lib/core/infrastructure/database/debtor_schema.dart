abstract final class DebtorSchema {
  static List<String> build({
    required List<String> creditTriggers,
    required String collectionPosting,
    required List<String> journalFreeze,
    required String Function(String) utcKey,
  }) {
    String credit(String sql) => sql
        .replaceAll("'\$.version') IS 2", "'\$.version') IN (2,3)")
        .replaceAll("'\$.version')=2", "'\$.version') IN (2,3)");
    collectionPosting = collectionPosting.replaceAll(
      'FROM receivable_settlements previous',
      'FROM all_receivable_settlements previous',
    );
    return [
      '''CREATE TABLE debtors (
 id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL CHECK(length(trim(name)) BETWEEN 1 AND 120),
 name_key TEXT NOT NULL UNIQUE CHECK(length(trim(name_key))>0),
 is_active INTEGER NOT NULL CHECK(typeof(is_active)='integer' AND is_active IN(0,1)),
 created_command_id TEXT NOT NULL UNIQUE REFERENCES command_log(id) ON DELETE RESTRICT,
 created_at_utc TEXT NOT NULL
)''',
      'ALTER TABLE quick_sales_accounts ADD COLUMN debtor_id TEXT REFERENCES debtors(id) ON DELETE RESTRICT',
      '''CREATE TABLE legacy_quick_debtor_requests(command_id TEXT PRIMARY KEY NOT NULL REFERENCES quick_sale_requests(command_id) ON DELETE RESTRICT)''',
      "INSERT INTO legacy_quick_debtor_requests SELECT command_id FROM quick_sale_requests WHERE json_valid(canonical_payload) AND json_extract(canonical_payload,'\$.version')=2",
      for (final action in ['INSERT', 'UPDATE', 'DELETE'])
        "CREATE TRIGGER legacy_quick_debtor_requests_no_${action.toLowerCase()} BEFORE $action ON legacy_quick_debtor_requests BEGIN SELECT RAISE(ABORT,'Legacy credit request identities are fixed at migration'); END",
      '''CREATE TABLE debtor_requests(
 command_id TEXT PRIMARY KEY NOT NULL, kind TEXT NOT NULL CHECK(kind IN('create','opening','payment','assign')),
 canonical_payload TEXT NOT NULL CHECK(json_valid(canonical_payload)), prepared_at_utc TEXT NOT NULL,
 status TEXT NOT NULL CHECK(status IN('prepared','executing','confirmed','discarded'))
)''',
      '''CREATE TABLE debtor_openings(
 document_id TEXT PRIMARY KEY NOT NULL REFERENCES business_documents(id) ON DELETE RESTRICT,
 debtor_id TEXT NOT NULL UNIQUE REFERENCES debtors(id) ON DELETE RESTRICT,
 name_snapshot TEXT NOT NULL,
 source TEXT NOT NULL CHECK(source IN('legacy','additional')),
 amount_minor INTEGER NOT NULL CHECK(typeof(amount_minor)='integer' AND amount_minor>0),
 offset_account_id TEXT NOT NULL REFERENCES ledger_accounts(id) ON DELETE RESTRICT,
 control_account_id TEXT NOT NULL REFERENCES ledger_accounts(id) ON DELETE RESTRICT
)''',
      '''CREATE TABLE debtor_receivables(
 receivable_id TEXT PRIMARY KEY NOT NULL,
 sales_receivable_id TEXT UNIQUE REFERENCES customer_receivables(id) ON DELETE RESTRICT,
 opening_document_id TEXT UNIQUE REFERENCES debtor_openings(document_id) ON DELETE RESTRICT,
 debtor_id TEXT NOT NULL REFERENCES debtors(id) ON DELETE RESTRICT,
 source TEXT NOT NULL CHECK(source IN('sale','opening','historical')),
 command_id TEXT NOT NULL REFERENCES command_log(id) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
 assigned_at_utc TEXT NOT NULL,
 CHECK((sales_receivable_id IS NOT NULL AND sales_receivable_id=receivable_id AND opening_document_id IS NULL AND source IN('sale','historical'))
 OR(sales_receivable_id IS NULL AND opening_document_id IS NOT NULL AND source='opening'))
)''',
      'CREATE INDEX idx_debtor_receivables_person ON debtor_receivables(debtor_id)',
      '''CREATE TABLE debtor_payments(
 document_id TEXT PRIMARY KEY NOT NULL REFERENCES business_documents(id) ON DELETE RESTRICT,
 debtor_id TEXT NOT NULL REFERENCES debtors(id) ON DELETE RESTRICT,
 name_snapshot TEXT NOT NULL,
 payment_option_id TEXT NOT NULL REFERENCES quick_payment_options(id) ON DELETE RESTRICT,
 cash_account_id TEXT NOT NULL REFERENCES cash_accounts(id) ON DELETE RESTRICT,
 payment_method_id TEXT NOT NULL REFERENCES payment_methods(id) ON DELETE RESTRICT,
 payment_label_snapshot TEXT NOT NULL,
 cash_account_name_snapshot TEXT NOT NULL,
 payment_method_code_snapshot TEXT NOT NULL,
 amount_minor INTEGER NOT NULL CHECK(typeof(amount_minor)='integer' AND amount_minor>0)
)''',
      '''CREATE TABLE debtor_payment_allocations(
 id TEXT PRIMARY KEY NOT NULL,
 collection_id TEXT NOT NULL REFERENCES debtor_payments(document_id) ON DELETE RESTRICT,
 receivable_id TEXT NOT NULL REFERENCES debtor_receivables(receivable_id) ON DELETE RESTRICT,
 sequence INTEGER NOT NULL CHECK(typeof(sequence)='integer' AND sequence>=0),
 amount_minor INTEGER NOT NULL CHECK(typeof(amount_minor)='integer' AND amount_minor>0),
 UNIQUE(collection_id,receivable_id),UNIQUE(collection_id,sequence)
)''',
      'CREATE INDEX idx_debtor_allocations_receivable ON debtor_payment_allocations(receivable_id)',
      '''CREATE VIEW all_receivable_settlements AS
 SELECT id,receivable_id,collection_id,amount_minor FROM receivable_settlements
 UNION ALL SELECT id,receivable_id,collection_id,amount_minor FROM debtor_payment_allocations''',
      '''CREATE VIEW all_customer_receivables AS
 SELECT id,origin_document_id,customer_name_snapshot,control_account_id,initial_minor,issued_at_utc,due_date FROM customer_receivables
 UNION ALL SELECT link.receivable_id,opening.document_id,opening.name_snapshot,opening.control_account_id,opening.amount_minor,document.occurred_at_utc,document.business_date
 FROM debtor_openings opening JOIN debtor_receivables link ON link.opening_document_id=opening.document_id
 JOIN business_documents document ON document.id=opening.document_id''',
      '''CREATE VIEW customer_receivable_balances AS
 SELECT receivable.*,receivable.initial_minor-coalesce((SELECT sum(settlement.amount_minor) FROM all_receivable_settlements settlement
 JOIN business_documents doc ON doc.id=settlement.collection_id AND doc.status='posted'
 JOIN journal_entries entry ON entry.document_id=doc.id AND entry.status='posted'
 WHERE settlement.receivable_id=receivable.id),0) AS remaining_minor
 FROM all_customer_receivables receivable JOIN business_documents document ON document.id=receivable.origin_document_id AND document.status='posted'
 JOIN journal_entries journal ON journal.document_id=document.id AND journal.status='posted' ''',
      '''CREATE VIEW debtor_expected_journal AS
 SELECT opening.document_id,'system:customer-receivable' AS account_id,opening.amount_minor AS debit_minor,0 AS credit_minor FROM debtor_openings opening
 UNION ALL SELECT opening.document_id,opening.offset_account_id,0,opening.amount_minor FROM debtor_openings opening
 UNION ALL SELECT payment.document_id,cash.ledger_account_id,payment.amount_minor,0 FROM debtor_payments payment JOIN cash_accounts cash ON cash.id=payment.cash_account_id
 UNION ALL SELECT allocation.collection_id,receivable.control_account_id,0,sum(allocation.amount_minor)
 FROM debtor_payment_allocations allocation JOIN all_customer_receivables receivable ON receivable.id=allocation.receivable_id
 GROUP BY allocation.collection_id,receivable.control_account_id''',
      'DROP TRIGGER collections_validate_document_posting',
      collectionPosting,
      for (final trigger in creditTriggers) ...[
        'DROP TRIGGER ${RegExp(r"CREATE TRIGGER (\w+)").firstMatch(trigger)!.group(1)}',
        credit(trigger),
      ],
      '''CREATE TRIGGER quick_registered_debtor_insert BEFORE INSERT ON quick_sale_requests
 WHEN json_valid(NEW.canonical_payload) AND json_extract(NEW.canonical_payload,'\$.version') IN(2,3)
 BEGIN SELECT CASE WHEN json_extract(NEW.canonical_payload,'\$.version')<>3 OR NOT EXISTS(
 SELECT 1 FROM quick_sales_accounts account JOIN debtors debtor ON debtor.id=account.debtor_id
 WHERE account.id=NEW.account_id AND debtor.is_active=1 AND debtor.name=account.customer_name
 AND json_extract(NEW.canonical_payload,'\$.debtorId') IS debtor.id)
 THEN RAISE(ABORT,'Select one registered active debtor before preparing credit') END; END''',
      '''CREATE TRIGGER quick_registered_debtor_update BEFORE UPDATE ON quick_sale_requests
 WHEN NEW.status IN('executing','confirmed') AND json_valid(NEW.canonical_payload) AND json_extract(NEW.canonical_payload,'\$.version') IN(2,3)
 BEGIN
 SELECT CASE WHEN json_extract(NEW.canonical_payload,'\$.version')=2 AND NOT EXISTS(SELECT 1 FROM legacy_quick_debtor_requests WHERE command_id=NEW.command_id)
 THEN RAISE(ABORT,'Only released legacy credit requests can use version two') END;
 SELECT CASE WHEN json_extract(NEW.canonical_payload,'\$.version')=3 AND NOT EXISTS(SELECT 1 FROM quick_sales_accounts account JOIN debtors debtor ON debtor.id=account.debtor_id
 WHERE account.id=NEW.account_id AND debtor.id=json_extract(NEW.canonical_payload,'\$.debtorId') AND debtor.name=json_extract(NEW.canonical_payload,'\$.customerName') AND debtor.is_active=1)
 THEN RAISE(ABORT,'Prepared credit retains its registered debtor') END;
 SELECT CASE WHEN NEW.status='confirmed' AND json_extract(NEW.canonical_payload,'\$.version')=3 AND NOT EXISTS(
 SELECT 1 FROM debtor_receivables link JOIN customer_receivables receivable ON receivable.id=link.receivable_id
 JOIN business_documents sale ON sale.id=receivable.origin_document_id JOIN command_log command ON command.id=NEW.command_id
 WHERE sale.command_id=NEW.sale_command_id AND link.debtor_id=json_extract(NEW.canonical_payload,'\$.debtorId')
 AND link.command_id=NEW.command_id AND link.source='sale' AND json_extract(command.response_json,'\$.result.debtorId') IS link.debtor_id)
 THEN RAISE(ABORT,'Confirmed credit must belong to its exact registered debtor') END;
 END''',
      '''CREATE TRIGGER quick_registered_debtor_locked BEFORE UPDATE OF debtor_id ON quick_sales_accounts
 WHEN NEW.debtor_id IS NOT OLD.debtor_id AND (OLD.status<>'open' OR NEW.status<>'open' OR EXISTS(SELECT 1 FROM quick_sale_requests WHERE account_id=OLD.id AND status<>'cancelled'))
 BEGIN SELECT RAISE(ABORT,'Prepared or closed debtor identity is immutable'); END''',
      '''CREATE TRIGGER debtor_receivable_validate BEFORE INSERT ON debtor_receivables BEGIN
 SELECT CASE WHEN NOT(
 (NEW.source='sale' AND EXISTS(SELECT 1 FROM customer_receivables receivable JOIN business_documents document ON document.id=receivable.origin_document_id
 JOIN quick_sale_requests request ON request.sale_command_id=document.command_id AND request.command_id=NEW.command_id
 WHERE receivable.id=NEW.receivable_id AND request.status='executing' AND json_extract(request.canonical_payload,'\$.version')=3
 AND json_extract(request.canonical_payload,'\$.debtorId') IS NEW.debtor_id))
 OR(NEW.source='opening' AND EXISTS(SELECT 1 FROM debtor_openings opening
 JOIN business_documents document ON document.id=opening.document_id WHERE opening.document_id=NEW.opening_document_id AND opening.debtor_id=NEW.debtor_id
 AND document.command_id=NEW.command_id AND document.status='draft'))
 OR(NEW.source='historical' AND EXISTS(SELECT 1 FROM debtor_requests request JOIN customer_receivable_balances receivable ON receivable.id=NEW.receivable_id
 WHERE request.command_id=NEW.command_id AND request.kind='assign' AND request.status='executing'
 AND json_extract(request.canonical_payload,'\$.debtorId') IS NEW.debtor_id AND json_extract(request.canonical_payload,'\$.receivableId') IS NEW.receivable_id
 AND NOT EXISTS(SELECT 1 FROM business_documents document JOIN quick_sale_requests checkout ON checkout.sale_command_id=document.command_id
 WHERE document.id=receivable.origin_document_id AND checkout.status<>'confirmed'))))
 THEN RAISE(ABORT,'A receivable requires its exact original or explicit historical debtor assignment') END; END''',
      '''CREATE TRIGGER debtor_requests_insert BEFORE INSERT ON debtor_requests BEGIN
 SELECT CASE WHEN NEW.status<>'prepared' OR EXISTS(SELECT 1 FROM debtor_requests WHERE command_id=NEW.command_id)
 OR EXISTS(SELECT 1 FROM command_log WHERE id=NEW.command_id)
 OR EXISTS(SELECT 1 FROM sale_confirmations WHERE command_id=NEW.command_id)
 OR EXISTS(SELECT 1 FROM collection_requests WHERE command_id=NEW.command_id)
 OR EXISTS(SELECT 1 FROM supplier_payment_requests WHERE command_id=NEW.command_id)
 OR EXISTS(SELECT 1 FROM treasury_operation_requests WHERE command_id=NEW.command_id)
 OR EXISTS(SELECT 1 FROM event_requests WHERE command_id=NEW.command_id)
 OR EXISTS(SELECT 1 FROM quick_sale_requests WHERE NEW.command_id IN(command_id,sale_command_id,collection_command_id))
 OR EXISTS(SELECT 1 FROM paid_purchase_requests WHERE NEW.command_id IN(command_id,purchase_command_id,payment_command_id))
 THEN RAISE(ABORT,'Debtor command identifier already reserved') END; END''',
      '''CREATE TRIGGER debtor_requests_update BEFORE UPDATE ON debtor_requests BEGIN
 SELECT CASE WHEN NEW.command_id<>OLD.command_id OR NEW.kind<>OLD.kind OR NEW.canonical_payload<>OLD.canonical_payload OR NEW.prepared_at_utc<>OLD.prepared_at_utc
 OR NOT((OLD.status='prepared' AND NEW.status IN('executing','discarded')) OR(OLD.status='executing' AND NEW.status='confirmed'))
 OR(NEW.status='discarded' AND EXISTS(SELECT 1 FROM command_log WHERE id=OLD.command_id))
 THEN RAISE(ABORT,'Invalid durable debtor request transition') END;
 SELECT CASE WHEN NEW.status='confirmed' AND NOT EXISTS(SELECT 1 FROM command_log command WHERE command.id=NEW.command_id AND command.command_type='debtor_operation'
 AND json_extract(command.response_json,'\$.canonicalPayload') IS NEW.canonical_payload)
 THEN RAISE(ABORT,'Debtor operation must retain its exact result') END;
 SELECT CASE WHEN NEW.status='confirmed' AND NEW.kind='create' AND NOT EXISTS(SELECT 1 FROM debtors debtor WHERE debtor.created_command_id=NEW.command_id
 AND debtor.id=json_extract(NEW.canonical_payload,'\$.debtorId') AND debtor.name=json_extract(NEW.canonical_payload,'\$.name')
 AND ((json_extract(NEW.canonical_payload,'\$.amountMinor')=0 AND NOT EXISTS(SELECT 1 FROM debtor_openings WHERE debtor_id=debtor.id))
 OR EXISTS(SELECT 1 FROM debtor_openings opening JOIN business_documents document ON document.id=opening.document_id AND document.status='posted'
 JOIN journal_entries entry ON entry.document_id=document.id AND entry.status='posted' WHERE opening.debtor_id=debtor.id AND document.command_id=NEW.command_id)))
 THEN RAISE(ABORT,'Create the person and exact optional opening before confirming') END;
 SELECT CASE WHEN NEW.status='confirmed' AND NEW.kind='opening' AND NOT EXISTS(SELECT 1 FROM debtor_openings opening JOIN business_documents document ON document.id=opening.document_id AND document.status='posted'
 JOIN journal_entries entry ON entry.document_id=document.id AND entry.status='posted' WHERE document.command_id=NEW.command_id AND opening.debtor_id=json_extract(NEW.canonical_payload,'\$.debtorId'))
 THEN RAISE(ABORT,'Post the exact previous debt before confirming') END;
 SELECT CASE WHEN NEW.status='confirmed' AND NEW.kind='payment' AND NOT EXISTS(SELECT 1 FROM debtor_payments payment JOIN business_documents document ON document.id=payment.document_id AND document.status='posted'
 JOIN journal_entries entry ON entry.document_id=document.id AND entry.status='posted' WHERE document.command_id=NEW.command_id)
 THEN RAISE(ABORT,'Post the whole debtor payment before confirming') END;
 SELECT CASE WHEN NEW.status='confirmed' AND NEW.kind='assign' AND NOT EXISTS(SELECT 1 FROM debtor_receivables WHERE command_id=NEW.command_id AND source='historical')
 THEN RAISE(ABORT,'Retain the historical debtor assignment before confirming') END; END''',
      "CREATE TRIGGER debtor_requests_delete BEFORE DELETE ON debtor_requests BEGIN SELECT RAISE(ABORT,'Debtor requests are durable'); END",
      '''CREATE TRIGGER debtor_command_reserved BEFORE INSERT ON command_log WHEN EXISTS(SELECT 1 FROM debtor_requests WHERE command_id=NEW.id)
 BEGIN SELECT CASE WHEN NEW.command_type<>'debtor_operation' OR NOT EXISTS(SELECT 1 FROM debtor_requests request WHERE request.command_id=NEW.id
 AND request.status='executing' AND request.canonical_payload=json_extract(NEW.response_json,'\$.canonicalPayload'))
 THEN RAISE(ABORT,'Debtor command reserved for its exact executing request') END; END''',
      for (final table in [
        'sale_confirmations',
        'collection_requests',
        'supplier_payment_requests',
        'treasury_operation_requests',
        'event_requests',
        'quick_sale_requests',
        'paid_purchase_requests',
      ])
        '''CREATE TRIGGER ${table}_respect_debtor BEFORE INSERT ON $table
 WHEN EXISTS(SELECT 1 FROM debtor_requests WHERE command_id=NEW.command_id
 ${table == 'quick_sale_requests'
            ? 'OR command_id IN(NEW.sale_command_id,NEW.collection_command_id)'
            : table == 'paid_purchase_requests'
            ? 'OR command_id IN(NEW.purchase_command_id,NEW.payment_command_id)'
            : ''})
 BEGIN SELECT RAISE(ABORT,'Identifier reserved by a debtor operation'); END''',
      '''CREATE TRIGGER debtors_no_replace BEFORE INSERT ON debtors WHEN EXISTS(SELECT 1 FROM debtors WHERE id=NEW.id OR name_key=NEW.name_key OR created_command_id=NEW.created_command_id)
 BEGIN SELECT RAISE(ABORT,'Registered person cannot be replaced'); END''',
      '''CREATE TRIGGER debtors_identity_immutable BEFORE UPDATE ON debtors WHEN NEW.id<>OLD.id OR NEW.name<>OLD.name OR NEW.name_key<>OLD.name_key OR NEW.created_command_id<>OLD.created_command_id OR NEW.created_at_utc<>OLD.created_at_utc
 BEGIN SELECT RAISE(ABORT,'Registered person identity and history are stable'); END''',
      "CREATE TRIGGER debtors_no_delete BEFORE DELETE ON debtors BEGIN SELECT RAISE(ABORT,'Keep registered people and their history'); END",
      '''CREATE TRIGGER debtor_document_draft BEFORE INSERT ON business_documents WHEN NEW.type IN('debtor_opening','debtor_collection') AND NEW.status<>'draft'
 BEGIN SELECT RAISE(ABORT,'Create debtor documents as draft'); END''',
      '''CREATE TRIGGER debtor_document_posting BEFORE UPDATE OF status ON business_documents
 WHEN OLD.status='draft' AND NEW.status='posted' AND (NEW.type IN('debtor_opening','debtor_collection') OR EXISTS(SELECT 1 FROM debtor_openings WHERE document_id=NEW.id) OR EXISTS(SELECT 1 FROM debtor_payments WHERE document_id=NEW.id))
 BEGIN
 SELECT CASE WHEN NEW.command_sequence<>0 OR date(NEW.occurred_at_utc,'-5 hours') IS NOT NEW.business_date
 OR NOT EXISTS(SELECT 1 FROM debtor_requests request JOIN command_log command ON command.id=request.command_id
 JOIN app_profile profile ON profile.profile_id=NEW.profile_id
 WHERE request.command_id=NEW.command_id AND request.status='executing' AND command.command_type='debtor_operation' AND command.actor_id=NEW.actor_id
 AND command.authorization_policy_version='development-single-user-v1' AND request.canonical_payload=json_extract(command.response_json,'\$.canonicalPayload')
 AND json_extract(request.canonical_payload,'\$.profileId')=profile.profile_id AND json_extract(request.canonical_payload,'\$.currency')=profile.currency_code AND json_extract(request.canonical_payload,'\$.scale')=profile.money_scale
 AND json_extract(request.canonical_payload,'\$.occurredAtUtc')=NEW.occurred_at_utc AND json_extract(command.response_json,'\$.result.documentId')=NEW.id
 AND ((request.kind IN('create','opening') AND NEW.type='debtor_opening') OR(request.kind='payment' AND NEW.type='debtor_collection')))
 THEN RAISE(ABORT,'Debtor document requires its exact executing request') END;
 SELECT CASE WHEN NEW.type='debtor_opening' AND NOT EXISTS(SELECT 1 FROM debtor_openings opening JOIN debtors debtor ON debtor.id=opening.debtor_id
 JOIN all_customer_receivables receivable ON receivable.origin_document_id=opening.document_id JOIN debtor_receivables link ON link.receivable_id=receivable.id
 JOIN debtor_requests request ON request.command_id=NEW.command_id JOIN ledger_accounts control ON control.id=receivable.control_account_id
 JOIN ledger_accounts offset ON offset.id=opening.offset_account_id
 WHERE opening.document_id=NEW.id AND opening.debtor_id=json_extract(request.canonical_payload,'\$.debtorId') AND opening.name_snapshot=debtor.name
 AND opening.name_snapshot=json_extract(request.canonical_payload,'\$.nameSnapshot') AND opening.amount_minor=json_extract(request.canonical_payload,'\$.amountMinor')
 AND opening.source=json_extract(request.canonical_payload,'\$.previousSource') AND receivable.initial_minor=opening.amount_minor
 AND receivable.customer_name_snapshot=opening.name_snapshot AND receivable.issued_at_utc=NEW.occurred_at_utc AND link.debtor_id=opening.debtor_id AND link.source='opening' AND link.command_id=NEW.command_id
 AND control.id='system:customer-receivable' AND control.class='asset' AND control.role='customer_receivable' AND control.is_active=1 AND offset.is_active=1
 AND ((opening.source='legacy' AND offset.id='system:legacy-customer-receivables' AND offset.class='asset' AND offset.role='receivable'
 AND opening.amount_minor<=coalesce((SELECT sum(line.debit_minor-line.credit_minor) FROM journal_lines line JOIN journal_entries entry ON entry.id=line.entry_id AND entry.status='posted'
 JOIN business_documents document ON document.id=entry.document_id AND document.status='posted' WHERE line.account_id=offset.id AND document.id<>NEW.id),0))
 OR(opening.source='additional' AND offset.id='debtors:opening-equity' AND offset.class='equity' AND offset.role='opening_balance')))
 THEN RAISE(ABORT,'Previous debt must be exact and cannot duplicate or exceed unassigned legacy debt') END;
 SELECT CASE WHEN NEW.type='debtor_collection' AND NOT EXISTS(SELECT 1 FROM debtor_payments payment JOIN debtors debtor ON debtor.id=payment.debtor_id
 JOIN debtor_requests request ON request.command_id=NEW.command_id JOIN quick_payment_options option ON option.id=payment.payment_option_id
 JOIN cash_accounts cash ON cash.id=payment.cash_account_id JOIN ledger_accounts ledger ON ledger.id=cash.ledger_account_id
 JOIN payment_methods method ON method.id=payment.payment_method_id
 WHERE payment.document_id=NEW.id AND payment.debtor_id=json_extract(request.canonical_payload,'\$.debtorId') AND payment.name_snapshot=debtor.name
 AND payment.amount_minor=json_extract(request.canonical_payload,'\$.amountMinor') AND payment.payment_option_id=json_extract(request.canonical_payload,'\$.paymentOptionId')
 AND option.id IN('quick-default:EFECTIVO','quick-default:NEQUI') AND option.is_active=1 AND option.cash_account_id=cash.id AND option.payment_method_id=method.id
 AND ledger.id=json_extract(request.canonical_payload,'\$.cashLedgerAccountId')
 AND payment.name_snapshot=json_extract(request.canonical_payload,'\$.nameSnapshot')
 AND payment.cash_account_id=json_extract(request.canonical_payload,'\$.cashAccountId')
 AND payment.payment_method_id=json_extract(request.canonical_payload,'\$.paymentMethodId')
 AND payment.payment_label_snapshot=json_extract(request.canonical_payload,'\$.paymentOptionLabel')
 AND payment.cash_account_name_snapshot=json_extract(request.canonical_payload,'\$.cashAccountName')
 AND payment.payment_method_code_snapshot=json_extract(request.canonical_payload,'\$.paymentMethodCode')
 AND option.label=payment.payment_label_snapshot AND cash.name=payment.cash_account_name_snapshot AND method.code=payment.payment_method_code_snapshot
 AND cash.is_active=1 AND cash.is_available=1 AND ledger.is_active=1 AND ledger.class='asset' AND ledger.role='cash' AND method.is_active=1
 AND (SELECT count(*) FROM debtor_payment_allocations WHERE collection_id=NEW.id)=json_array_length(request.canonical_payload,'\$.allocations')
 AND payment.amount_minor=(SELECT sum(amount_minor) FROM debtor_payment_allocations WHERE collection_id=NEW.id))
 THEN RAISE(ABORT,'Debtor payment requires its exact person, account and allocations') END;
 SELECT CASE WHEN NEW.type='debtor_collection' AND EXISTS(SELECT 1 FROM debtor_payment_allocations allocation
 JOIN all_customer_receivables receivable ON receivable.id=allocation.receivable_id JOIN debtor_receivables link ON link.receivable_id=receivable.id
 JOIN business_documents origin ON origin.id=receivable.origin_document_id JOIN journal_entries origin_entry ON origin_entry.document_id=origin.id
 JOIN ledger_accounts control ON control.id=receivable.control_account_id JOIN debtor_payments payment ON payment.document_id=allocation.collection_id
 JOIN debtor_requests request ON request.command_id=NEW.command_id
 WHERE allocation.collection_id=NEW.id AND (link.debtor_id<>payment.debtor_id OR origin.status<>'posted' OR origin_entry.status<>'posted'
 OR control.class<>'asset' OR control.role<>'customer_receivable' OR control.is_active<>1 OR ${utcKey('origin.occurred_at_utc')}>${utcKey('NEW.occurred_at_utc')}
 OR allocation.amount_minor>receivable.initial_minor-coalesce((SELECT sum(previous.amount_minor) FROM all_receivable_settlements previous JOIN business_documents document ON document.id=previous.collection_id
 WHERE previous.receivable_id=receivable.id AND document.status<>'draft' AND document.id<>NEW.id),0)
 OR NOT EXISTS(SELECT 1 FROM json_each(request.canonical_payload,'\$.allocations') planned WHERE json_extract(planned.value,'\$.receivableId')=receivable.id
 AND json_extract(planned.value,'\$.amountMinor')=allocation.amount_minor AND planned.key=allocation.sequence)))
 THEN RAISE(ABORT,'Apply payment once to the exact debtor balances without overpayment') END;
 SELECT CASE WHEN NEW.type='debtor_collection' AND EXISTS(SELECT 1 FROM debtor_payments payment JOIN cash_accounts cash ON cash.id=payment.cash_account_id
 JOIN journal_lines line ON line.account_id=cash.ledger_account_id JOIN journal_entries entry ON entry.id=line.entry_id AND entry.status='posted'
 JOIN business_documents previous ON previous.id=entry.document_id AND previous.status='posted' WHERE payment.document_id=NEW.id
 AND previous.id<>NEW.id AND ${utcKey('previous.occurred_at_utc')}>${utcKey('NEW.occurred_at_utc')})
 THEN RAISE(ABORT,'Payment cannot precede the latest account movement') END;
 SELECT CASE WHEN NEW.type='debtor_collection' AND EXISTS(
 SELECT 1 FROM debtor_payments payment JOIN cash_accounts cash ON cash.id=payment.cash_account_id
 WHERE payment.document_id=NEW.id AND coalesce((SELECT sum(line.debit_minor-line.credit_minor)
 FROM journal_lines line JOIN journal_entries entry ON entry.id=line.entry_id AND entry.status='posted'
 JOIN business_documents document ON document.id=entry.document_id AND document.status='posted'
 WHERE line.account_id=cash.ledger_account_id),0)>9223372036854775807-payment.amount_minor)
 THEN RAISE(ABORT,'Debtor payment exceeds account capacity') END;
 SELECT CASE WHEN NEW.type='debtor_opening' AND EXISTS(SELECT 1 FROM debtor_openings opening WHERE opening.document_id=NEW.id AND opening.source='additional'
 AND coalesce((SELECT sum(remaining_minor) FROM customer_receivable_balances),0)+coalesce((SELECT sum(line.debit_minor-line.credit_minor)
 FROM journal_lines line JOIN journal_entries entry ON entry.id=line.entry_id AND entry.status='posted'
 JOIN business_documents document ON document.id=entry.document_id AND document.status='posted'
 WHERE line.account_id='system:legacy-customer-receivables'),0)>9223372036854775807-opening.amount_minor)
 THEN RAISE(ABORT,'Previous debt exceeds total receivable capacity') END;
 SELECT CASE WHEN NEW.type='debtor_collection' AND EXISTS(SELECT 1 FROM debtor_payment_allocations allocation
 JOIN all_receivable_settlements previous ON previous.receivable_id=allocation.receivable_id AND previous.collection_id<>NEW.id
 JOIN business_documents document ON document.id=previous.collection_id AND document.status='posted'
 WHERE allocation.collection_id=NEW.id AND ${utcKey('document.occurred_at_utc')}>${utcKey('NEW.occurred_at_utc')})
 THEN RAISE(ABORT,'Payment cannot precede the latest debt payment') END;
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM journal_entries WHERE document_id=NEW.id AND status='draft' AND cost_completeness='not_applicable' AND reversal_of_id IS NULL)
 OR(SELECT count(*) FROM journal_lines line JOIN journal_entries entry ON entry.id=line.entry_id WHERE entry.document_id=NEW.id)
 <> (SELECT count(*) FROM debtor_expected_journal WHERE document_id=NEW.id)
 OR EXISTS(SELECT 1 FROM debtor_expected_journal expected WHERE expected.document_id=NEW.id AND NOT EXISTS(SELECT 1 FROM journal_lines line JOIN journal_entries entry ON entry.id=line.entry_id
 WHERE entry.document_id=NEW.id AND line.account_id=expected.account_id AND line.debit_minor=expected.debit_minor AND line.credit_minor=expected.credit_minor))
 THEN RAISE(ABORT,'Debtor operation requires its exact balanced receivable journal') END;
 END''',
      for (final table in [
        'debtor_openings',
        'debtor_payments',
        'debtor_payment_allocations',
        'debtor_receivables',
      ]) ...[
        for (final action in ['UPDATE', 'DELETE'])
          "CREATE TRIGGER ${table}_no_${action.toLowerCase()} BEFORE $action ON $table BEGIN SELECT RAISE(ABORT,'Debtor financial facts and assignments are immutable'); END",
        '''CREATE TRIGGER ${table}_no_replace BEFORE INSERT ON $table WHEN EXISTS(SELECT 1 FROM $table WHERE
 ${table == 'debtor_openings'
            ? 'document_id=NEW.document_id OR debtor_id=NEW.debtor_id'
            : table == 'debtor_payments'
            ? 'document_id=NEW.document_id'
            : table == 'debtor_receivables'
            ? 'receivable_id=NEW.receivable_id'
            : 'id=NEW.id OR(collection_id=NEW.collection_id AND(receivable_id=NEW.receivable_id OR sequence=NEW.sequence))'})
 ${table == 'debtor_receivables' ? '' : "OR EXISTS(SELECT 1 FROM business_documents document WHERE document.id=${table == 'debtor_payment_allocations' ? 'NEW.collection_id' : 'NEW.document_id'} AND document.status<>'draft')"}
 BEGIN SELECT RAISE(ABORT,'Debtor facts cannot be replaced or appended after posting'); END''',
      ],
      for (final journal in journalFreeze)
        journal
            .replaceAll('treasury_operation_', 'debtor_journal_')
            .replaceAll(
              'JOIN treasury_operations operation',
              'JOIN business_documents operation',
            )
            .replaceAll(
              'operation.document_id=document.id',
              "operation.id=document.id AND document.type IN('debtor_opening','debtor_collection')",
            ),
    ];
  }
}
