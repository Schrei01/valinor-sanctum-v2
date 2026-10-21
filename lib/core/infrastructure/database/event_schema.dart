/// Additive v12. Historical migrations remain byte-for-byte inputs.
abstract final class EventSchema {
  static List<String> build({
    required String salePosting,
    required String purchaseAllocation,
    required String openingAllocation,
    required String entryPosting,
    required String fundsInvalid,
    required List<String> freezeJournal,
    required String Function(String) utcKey,
  }) {
    String usage(String sql) => sql
        .replaceAll(
          'FROM sale_cost_allocations a WHERE a.cost_layer_id',
          'FROM inventory_cost_usage a WHERE a.cost_layer_id',
        )
        .replaceAll(
          'FROM inventory_opening_allocations allocation\n        WHERE allocation.opening_item_id',
          'FROM inventory_cost_usage allocation\n        WHERE allocation.opening_item_id',
        )
        .replaceAll(
          'FROM inventory_opening_allocations allocation\n      WHERE allocation.opening_item_id',
          'FROM inventory_cost_usage allocation\n      WHERE allocation.opening_item_id',
        );
    final start = salePosting.indexOf(
      '  SELECT CASE WHEN (SELECT count(*) FROM sale_outflows',
    );
    final end = salePosting.indexOf(
      '  SELECT CASE WHEN EXISTS (SELECT 1 FROM inventory_opening_allocations',
      start,
    );
    final physical = salePosting
        .substring(start, end)
        .replaceFirst(
          '(SELECT count(*) FROM sale_lines WHERE sale_id = NEW.id)',
          '(SELECT count(*) FROM sale_lines WHERE sale_id = NEW.id AND product_id NOT IN (SELECT product_id FROM events))',
        )
        .replaceFirst(
          'WHERE l.sale_id = NEW.id AND (',
          'WHERE l.sale_id = NEW.id AND l.product_id NOT IN (SELECT product_id FROM events) AND (',
        );
    salePosting = salePosting.replaceRange(start, end, '''$physical
  SELECT CASE WHEN EXISTS (SELECT 1 FROM sale_lines line JOIN events event ON event.product_id=line.product_id
    JOIN business_documents origin ON origin.id=event.document_id JOIN journal_entries entry ON entry.document_id=origin.id
    WHERE line.sale_id=NEW.id AND (line.total_cost_minor <> 0 OR origin.status <> 'posted' OR entry.status <> 'posted'
      OR ${utcKey('origin.occurred_at_utc')} > ${utcKey('NEW.occurred_at_utc')}
      OR EXISTS (SELECT 1 FROM sale_outflows WHERE sale_line_id=line.id)
      OR EXISTS (SELECT 1 FROM all_sale_cost_allocations WHERE sale_line_id=line.id)))
    THEN RAISE(ABORT, 'Event inscriptions have no stock outflow or repeated cost') END;
''');
    final money = fundsInvalid
        .replaceAll('treasury_operations operation', 'events operation')
        .replaceAll(
          'operation.amount_minor',
          'operation.fixed_cost_minor AS amount_minor',
        )
        .replaceAll(
          'ON cash.id IN (operation.source_account_id,operation.destination_account_id)',
          'ON cash.id=operation.source_account_id',
        )
        .replaceAll(
          "('cash_expense','cash_transfer')",
          "('cash_expense','cash_transfer','event_creation')",
        );
    final result = <String>[
      '''CREATE TABLE event_requests (
 command_id TEXT PRIMARY KEY NOT NULL CHECK(length(trim(command_id)) BETWEEN 1 AND 128),
 canonical_payload TEXT NOT NULL CHECK(json_valid(canonical_payload)),
 prepared_at_utc TEXT NOT NULL,
 status TEXT NOT NULL CHECK(status IN ('prepared','confirmed','discarded'))
)''',
      '''CREATE TABLE events (
 document_id TEXT PRIMARY KEY NOT NULL REFERENCES business_documents(id) ON DELETE RESTRICT,
 product_id TEXT NOT NULL UNIQUE REFERENCES catalog_items(id) ON DELETE RESTRICT,
 name_snapshot TEXT NOT NULL CHECK(length(trim(name_snapshot)) BETWEEN 1 AND 160),
 minimum_people INTEGER NOT NULL CHECK(typeof(minimum_people)='integer' AND minimum_people>=0),
 fixed_cost_minor INTEGER NOT NULL CHECK(typeof(fixed_cost_minor)='integer' AND fixed_cost_minor>=0),
 source_account_id TEXT REFERENCES cash_accounts(id) ON DELETE RESTRICT,
 source_account_name_snapshot TEXT,
 products_cost_minor INTEGER NOT NULL CHECK(typeof(products_cost_minor)='integer' AND products_cost_minor>=0),
 total_cost_minor INTEGER NOT NULL CHECK(typeof(total_cost_minor)='integer' AND total_cost_minor>=0),
 unit_cost_minor INTEGER NOT NULL CHECK(typeof(unit_cost_minor)='integer' AND unit_cost_minor>=0),
 pvp_minor INTEGER NOT NULL CHECK(typeof(pvp_minor)='integer' AND pvp_minor>0),
 CHECK(typeof(fixed_cost_minor+products_cost_minor)='integer' AND total_cost_minor=fixed_cost_minor+products_cost_minor),
 CHECK((fixed_cost_minor=0 AND source_account_id IS NULL AND source_account_name_snapshot IS NULL) OR
   (fixed_cost_minor>0 AND source_account_id IS NOT NULL AND source_account_name_snapshot IS NOT NULL AND minimum_people>0)),
 CHECK(unit_cost_minor=CASE WHEN minimum_people=0 THEN 0 ELSE total_cost_minor/minimum_people +
   CASE WHEN total_cost_minor%minimum_people >= minimum_people/2+minimum_people%2 THEN 1 ELSE 0 END END)
)''',
      '''CREATE TABLE event_products (
 id TEXT PRIMARY KEY NOT NULL,
 event_id TEXT NOT NULL REFERENCES events(document_id) ON DELETE RESTRICT,
 sequence INTEGER NOT NULL CHECK(typeof(sequence)='integer' AND sequence>=0),
 product_id TEXT NOT NULL REFERENCES catalog_items(id) ON DELETE RESTRICT,
 name_snapshot TEXT NOT NULL,
 quantity INTEGER NOT NULL CHECK(typeof(quantity)='integer' AND quantity>0),
 cost_minor INTEGER NOT NULL CHECK(typeof(cost_minor)='integer' AND cost_minor>=0),
 UNIQUE(event_id,sequence), UNIQUE(event_id,product_id)
)''',
      '''CREATE TABLE event_cost_allocations (
 id TEXT PRIMARY KEY NOT NULL,
 event_product_id TEXT NOT NULL REFERENCES event_products(id) ON DELETE RESTRICT,
 sequence INTEGER NOT NULL CHECK(typeof(sequence)='integer' AND sequence>=0),
 cost_layer_id TEXT REFERENCES cost_layers(id) ON DELETE RESTRICT,
 opening_item_id TEXT REFERENCES inventory_opening_items(id) ON DELETE RESTRICT,
 quantity INTEGER NOT NULL CHECK(typeof(quantity)='integer' AND quantity>0),
 cost_minor INTEGER NOT NULL CHECK(typeof(cost_minor)='integer' AND cost_minor>=0),
 CHECK((cost_layer_id IS NULL) <> (opening_item_id IS NULL)),
 UNIQUE(event_product_id,sequence), UNIQUE(event_product_id,cost_layer_id), UNIQUE(event_product_id,opening_item_id)
)''',
      'CREATE INDEX idx_event_cost_purchase ON event_cost_allocations(cost_layer_id)',
      'CREATE INDEX idx_event_cost_opening ON event_cost_allocations(opening_item_id)',
      '''CREATE VIEW inventory_cost_usage AS
 SELECT cost_layer_id,NULL AS opening_item_id,quantity,cost_minor FROM sale_cost_allocations
 UNION ALL SELECT NULL,opening_item_id,quantity,cost_minor FROM inventory_opening_allocations
 UNION ALL SELECT cost_layer_id,opening_item_id,quantity,cost_minor FROM event_cost_allocations''',
      '''CREATE VIEW inventory_effective_layers AS
 SELECT layer.id,layer.product_id,layer.initial_quantity,layer.total_cost_minor,layer.fifo_sequence,
 layer.acquired_at_utc,'purchase' AS source_kind FROM cost_layers layer
 JOIN inventory_movements movement ON movement.id=layer.inbound_movement_id
 JOIN business_documents document ON document.id=movement.document_id AND document.status='posted'
 JOIN journal_entries entry ON entry.document_id=document.id AND entry.status='posted'
 UNION ALL SELECT id,product_id,initial_quantity,total_cost_minor,fifo_sequence,acquired_at_utc,source_kind FROM inventory_opening_layers''',
      '''CREATE VIEW event_expected_journal AS
 SELECT document_id,'events:costs' AS account_id,total_cost_minor AS debit_minor,0 AS credit_minor FROM events WHERE total_cost_minor>0
 UNION ALL SELECT document_id,'system:inventory',0,products_cost_minor FROM events WHERE products_cost_minor>0
 UNION ALL SELECT event.document_id,cash.ledger_account_id,0,event.fixed_cost_minor FROM events event
 JOIN cash_accounts cash ON cash.id=event.source_account_id WHERE event.fixed_cost_minor>0''',
      'DROP TRIGGER sales_validate_document_posting',
      salePosting,
      'DROP TRIGGER sale_cost_allocations_validate_insert',
      usage(purchaseAllocation),
      'DROP TRIGGER inventory_opening_allocations_validate_insert',
      usage(openingAllocation),
      'DROP TRIGGER entries_validate_posting',
      entryPosting.replaceFirst(
        "    THEN RAISE(ABORT, 'A posted entry needs at least two lines except a confirmed zero value opening') END;",
        '''    AND NOT EXISTS (SELECT 1 FROM events event JOIN business_documents document ON document.id=event.document_id
      WHERE event.document_id=NEW.document_id AND document.type='event_creation' AND document.status='posted'
      AND event.total_cost_minor=0 AND NEW.cost_completeness='complete' AND NOT EXISTS(SELECT 1 FROM journal_lines WHERE entry_id=NEW.id))
    THEN RAISE(ABORT, 'A posted entry needs at least two lines except a confirmed zero value inventory opening') END;''',
      ),
      '''CREATE TRIGGER event_requests_insert BEFORE INSERT ON event_requests BEGIN
 SELECT CASE WHEN NEW.status <> 'prepared' OR EXISTS(SELECT 1 FROM event_requests WHERE command_id=NEW.command_id)
 OR EXISTS(SELECT 1 FROM command_log WHERE id=NEW.command_id)
 OR EXISTS(SELECT 1 FROM sale_confirmations WHERE command_id=NEW.command_id)
 OR EXISTS(SELECT 1 FROM collection_requests WHERE command_id=NEW.command_id)
 OR EXISTS(SELECT 1 FROM supplier_payment_requests WHERE command_id=NEW.command_id)
 OR EXISTS(SELECT 1 FROM treasury_operation_requests WHERE command_id=NEW.command_id)
 OR EXISTS(SELECT 1 FROM quick_sale_requests WHERE NEW.command_id IN(command_id,sale_command_id,collection_command_id))
 OR EXISTS(SELECT 1 FROM paid_purchase_requests WHERE NEW.command_id IN(command_id,purchase_command_id,payment_command_id))
 THEN RAISE(ABORT,'Event command identifier already reserved') END; END''',
      '''CREATE TRIGGER event_requests_update BEFORE UPDATE ON event_requests BEGIN
 SELECT CASE WHEN NEW.command_id<>OLD.command_id OR NEW.canonical_payload<>OLD.canonical_payload OR NEW.prepared_at_utc<>OLD.prepared_at_utc
 OR OLD.status<>'prepared' OR NEW.status NOT IN('confirmed','discarded')
 OR (NEW.status='confirmed' AND NOT EXISTS(SELECT 1 FROM events event JOIN business_documents document ON document.id=event.document_id
 JOIN journal_entries entry ON entry.document_id=document.id WHERE document.command_id=OLD.command_id AND document.status='posted' AND entry.status='posted'))
 OR (NEW.status='discarded' AND EXISTS(SELECT 1 FROM command_log WHERE id=OLD.command_id))
 THEN RAISE(ABORT,'Invalid event request transition') END; END''',
      "CREATE TRIGGER event_requests_delete BEFORE DELETE ON event_requests BEGIN SELECT RAISE(ABORT,'Event requests are durable'); END",
      '''CREATE TRIGGER event_command_reserved BEFORE INSERT ON command_log
 WHEN EXISTS(SELECT 1 FROM event_requests request WHERE request.command_id=NEW.id)
 BEGIN SELECT CASE WHEN NEW.command_type<>'create_event' OR NOT EXISTS(SELECT 1 FROM event_requests request WHERE request.command_id=NEW.id
 AND request.status='prepared' AND request.canonical_payload=json_extract(NEW.response_json,'\$.canonicalPayload'))
 THEN RAISE(ABORT,'Event identifier reserved for exact prepared creation') END; END''',
      for (final table in [
        'sale_confirmations',
        'collection_requests',
        'supplier_payment_requests',
        'treasury_operation_requests',
        'quick_sale_requests',
        'paid_purchase_requests',
      ])
        '''CREATE TRIGGER ${table}_respect_event BEFORE INSERT ON $table
 WHEN EXISTS(SELECT 1 FROM event_requests WHERE command_id=NEW.command_id
 ${table == 'quick_sale_requests'
            ? 'OR command_id IN(NEW.sale_command_id,NEW.collection_command_id)'
            : table == 'paid_purchase_requests'
            ? 'OR command_id IN(NEW.purchase_command_id,NEW.payment_command_id)'
            : ''})
 BEGIN SELECT RAISE(ABORT,'Identifier reserved by an event creation'); END''',
      '''CREATE TRIGGER events_document_draft BEFORE INSERT ON business_documents WHEN NEW.type='event_creation' AND NEW.status<>'draft'
 BEGIN SELECT RAISE(ABORT,'Create event document as draft'); END''',
      '''CREATE TRIGGER events_posting BEFORE UPDATE OF status ON business_documents
 WHEN OLD.status='draft' AND NEW.status='posted' AND (NEW.type='event_creation' OR EXISTS(SELECT 1 FROM events WHERE document_id=NEW.id))
 BEGIN
 SELECT CASE WHEN NEW.type<>'event_creation' OR NEW.command_sequence<>0 OR date(NEW.occurred_at_utc,'-5 hours') IS NOT NEW.business_date
 OR NOT EXISTS(SELECT 1 FROM events event JOIN catalog_items product ON product.id=event.product_id
 JOIN categories category ON category.id=product.category_id JOIN command_log command ON command.id=NEW.command_id
 JOIN app_profile profile ON profile.profile_id=NEW.profile_id
 JOIN event_requests request ON request.command_id=command.id
 WHERE event.document_id=NEW.id AND product.is_active=1 AND product.name=event.name_snapshot AND product.list_price_minor=event.pvp_minor
 AND category.is_active=1 AND lower(trim(category.name))='evento' AND command.command_type='create_event'
 AND command.actor_id=NEW.actor_id AND request.status='prepared' AND command.authorization_policy_version='development-single-user-v1'
 AND request.canonical_payload=json_extract(command.response_json,'\$.canonicalPayload')
 AND json_extract(request.canonical_payload,'\$.name')=event.name_snapshot
 AND json_extract(request.canonical_payload,'\$.minimumPeople')=event.minimum_people
 AND json_extract(request.canonical_payload,'\$.fixedCostMinor')=event.fixed_cost_minor
 AND json_extract(request.canonical_payload,'\$.sourceAccountId') IS event.source_account_id
 AND json_extract(request.canonical_payload,'\$.pvpMinor')=event.pvp_minor
 AND json_extract(request.canonical_payload,'\$.occurredAtUtc')=NEW.occurred_at_utc
 AND json_extract(request.canonical_payload,'\$.profileId')=NEW.profile_id
 AND json_extract(request.canonical_payload,'\$.version')=1
 AND json_extract(request.canonical_payload,'\$.currency')=profile.currency_code
 AND json_extract(request.canonical_payload,'\$.scale')=profile.money_scale
 AND json_extract(request.canonical_payload,'\$.productsCostMinor')=event.products_cost_minor
 AND json_extract(request.canonical_payload,'\$.totalCostMinor')=event.total_cost_minor
 AND json_extract(request.canonical_payload,'\$.unitCostMinor')=event.unit_cost_minor
 AND json_extract(command.response_json,'\$.result.documentId')=NEW.id
 AND json_extract(command.response_json,'\$.result.productId')=event.product_id
 AND json_array_length(json_extract(request.canonical_payload,'\$.products'))=(SELECT count(*) FROM event_products WHERE event_id=NEW.id))
 THEN RAISE(ABORT,'Event must match its prepared command and catalog item') END;
 SELECT CASE WHEN EXISTS(SELECT 1 FROM events event WHERE event.document_id=NEW.id AND
 (event.products_cost_minor<>coalesce((SELECT sum(cost_minor) FROM event_products WHERE event_id=NEW.id),0)
 OR (event.minimum_people=0 AND EXISTS(SELECT 1 FROM event_products WHERE event_id=NEW.id))))
 OR EXISTS(SELECT 1 FROM event_products part JOIN catalog_items product ON product.id=part.product_id
 LEFT JOIN categories category ON category.id=product.category_id
 WHERE part.event_id=NEW.id AND (product.is_active<>1 OR (product.category_id IS NOT NULL AND category.is_active<>1)
 OR part.name_snapshot<>product.name OR EXISTS(SELECT 1 FROM events WHERE product_id=part.product_id)
 OR part.quantity<>coalesce((SELECT sum(quantity) FROM event_cost_allocations WHERE event_product_id=part.id),0)
 OR part.cost_minor<>coalesce((SELECT sum(cost_minor) FROM event_cost_allocations WHERE event_product_id=part.id),0)
 OR NOT EXISTS(SELECT 1 FROM event_requests request,json_each(request.canonical_payload,'\$.products') input WHERE request.command_id=NEW.command_id
 AND json_extract(input.value,'\$.productId')=part.product_id AND json_extract(input.value,'\$.quantity')=part.quantity)))
 THEN RAISE(ABORT,'Event products require exact stock consumption and minimum people') END;
 SELECT CASE WHEN EXISTS(SELECT 1 FROM events event WHERE event.document_id=NEW.id AND
 (EXISTS(SELECT 1 FROM purchase_lines WHERE product_id=event.product_id)
 OR EXISTS(SELECT 1 FROM inventory_opening_items WHERE product_id=event.product_id)))
 OR EXISTS(SELECT 1 FROM event_products part JOIN sale_lines line ON line.product_id=part.product_id
 JOIN business_documents previous ON previous.id=line.sale_id AND previous.status='posted'
 WHERE part.event_id=NEW.id AND ${utcKey('previous.occurred_at_utc')}>${utcKey('NEW.occurred_at_utc')})
 OR EXISTS(SELECT 1 FROM events event JOIN cash_accounts cash ON cash.id=event.source_account_id
 JOIN journal_lines line ON line.account_id=cash.ledger_account_id JOIN journal_entries entry ON entry.id=line.entry_id
 JOIN business_documents previous ON previous.id=entry.document_id AND previous.status='posted'
 WHERE event.document_id=NEW.id AND previous.id<>NEW.id AND entry.status='posted'
 AND ${utcKey('previous.occurred_at_utc')}>${utcKey('NEW.occurred_at_utc')})
 THEN RAISE(ABORT,'Event creation must preserve inventory and money chronology') END;
 SELECT CASE WHEN EXISTS(SELECT 1 FROM events event WHERE event.document_id=NEW.id AND event.fixed_cost_minor>0 AND NOT EXISTS(
 SELECT 1 FROM cash_accounts cash JOIN ledger_accounts ledger ON ledger.id=cash.ledger_account_id JOIN quick_payment_options option ON option.cash_account_id=cash.id
 WHERE cash.id=event.source_account_id AND cash.name=event.source_account_name_snapshot AND cash.is_active=1 AND cash.is_available=1
 AND ledger.is_active=1 AND ledger.class='asset' AND ledger.role='cash' AND option.id IN('quick-default:EFECTIVO','quick-default:NEQUI')))
 OR $money THEN RAISE(ABORT,'Event requires sufficient funds in Caja or Nequi') END;
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM journal_entries WHERE document_id=NEW.id AND status='draft' AND cost_completeness='complete' AND reversal_of_id IS NULL)
 OR (SELECT count(*) FROM journal_lines line JOIN journal_entries entry ON entry.id=line.entry_id WHERE entry.document_id=NEW.id)
 <> (SELECT count(*) FROM event_expected_journal WHERE document_id=NEW.id)
 OR EXISTS(SELECT 1 FROM event_expected_journal expected WHERE expected.document_id=NEW.id AND NOT EXISTS(
 SELECT 1 FROM journal_entries entry JOIN journal_lines line ON line.entry_id=entry.id JOIN ledger_accounts account ON account.id=line.account_id
 WHERE entry.document_id=NEW.id AND line.account_id=expected.account_id AND line.debit_minor=expected.debit_minor AND line.credit_minor=expected.credit_minor AND account.is_active=1
 AND (account.id<>'events:costs' OR (account.class='expense' AND account.role='event_cost'))
 AND (account.id<>'system:inventory' OR (account.class='asset' AND account.role='inventory'))))
 THEN RAISE(ABORT,'Event requires its exact cost, inventory and money journal') END;
 END''',
      '''CREATE TRIGGER event_cost_validate BEFORE INSERT ON event_cost_allocations BEGIN
 SELECT CASE WHEN EXISTS(SELECT 1 FROM event_cost_allocations WHERE id=NEW.id OR (event_product_id=NEW.event_product_id AND sequence=NEW.sequence)
 OR(event_product_id=NEW.event_product_id AND cost_layer_id IS NEW.cost_layer_id AND opening_item_id IS NEW.opening_item_id))
 OR NOT EXISTS(SELECT 1 FROM event_products part JOIN business_documents document ON document.id=part.event_id
 JOIN inventory_effective_layers layer ON layer.product_id=part.product_id
 WHERE part.id=NEW.event_product_id AND document.status='draft' AND document.type='event_creation'
 AND layer.id=coalesce(NEW.cost_layer_id,NEW.opening_item_id) AND layer.source_kind=CASE WHEN NEW.cost_layer_id IS NULL THEN 'opening' ELSE 'purchase' END
 AND ${utcKey('layer.acquired_at_utc')}<=${utcKey('document.occurred_at_utc')}
 AND NEW.quantity <= layer.initial_quantity-coalesce((SELECT sum(quantity) FROM inventory_cost_usage WHERE
 (NEW.cost_layer_id IS NOT NULL AND cost_layer_id=NEW.cost_layer_id) OR (NEW.opening_item_id IS NOT NULL AND opening_item_id=NEW.opening_item_id)),0)
 AND NEW.cost_minor=NEW.quantity*(layer.total_cost_minor/layer.initial_quantity)+min(NEW.quantity,max(0,layer.total_cost_minor%layer.initial_quantity-
 coalesce((SELECT sum(quantity) FROM inventory_cost_usage WHERE (NEW.cost_layer_id IS NOT NULL AND cost_layer_id=NEW.cost_layer_id)
 OR (NEW.opening_item_id IS NOT NULL AND opening_item_id=NEW.opening_item_id)),0))))
 OR NEW.sequence<>(SELECT count(*) FROM event_cost_allocations WHERE event_product_id=NEW.event_product_id)
 OR NEW.quantity>(SELECT quantity-coalesce((SELECT sum(quantity) FROM event_cost_allocations WHERE event_product_id=NEW.event_product_id),0) FROM event_products WHERE id=NEW.event_product_id)
 THEN RAISE(ABORT,'Invalid event FIFO cost allocation') END;
 SELECT CASE WHEN EXISTS(SELECT 1 FROM inventory_effective_layers older JOIN inventory_effective_layers chosen ON chosen.id=coalesce(NEW.cost_layer_id,NEW.opening_item_id)
 AND chosen.source_kind=CASE WHEN NEW.cost_layer_id IS NULL THEN 'opening' ELSE 'purchase' END
 JOIN event_products part ON part.id=NEW.event_product_id JOIN business_documents document ON document.id=part.event_id
 WHERE older.product_id=chosen.product_id AND (older.fifo_sequence<chosen.fifo_sequence OR (older.fifo_sequence=chosen.fifo_sequence AND older.id<chosen.id))
 AND ${utcKey('older.acquired_at_utc')}<=${utcKey('document.occurred_at_utc')}
 AND older.initial_quantity>coalesce((SELECT sum(quantity) FROM inventory_cost_usage WHERE
 (older.source_kind='purchase' AND cost_layer_id=older.id) OR(older.source_kind='opening' AND opening_item_id=older.id)),0))
 THEN RAISE(ABORT,'Consume oldest event inventory first') END; END''',
      for (final table in [
        'events',
        'event_products',
        'event_cost_allocations',
      ]) ...[
        for (final action in ['UPDATE', 'DELETE'])
          "CREATE TRIGGER ${table}_no_${action.toLowerCase()} BEFORE $action ON $table BEGIN SELECT RAISE(ABORT,'Event costs and consumption are immutable'); END",
        '''CREATE TRIGGER ${table}_no_replace BEFORE INSERT ON $table
 WHEN EXISTS(SELECT 1 FROM $table WHERE ${table == 'events' ? 'document_id=NEW.document_id OR product_id=NEW.product_id' : 'id=NEW.id'})
 OR EXISTS(SELECT 1 FROM business_documents document WHERE document.id=${table == 'events'
            ? 'NEW.document_id'
            : table == 'event_products'
            ? 'NEW.event_id'
            : '(SELECT event_id FROM event_products WHERE id=NEW.event_product_id)'} AND document.status<>'draft')
 BEGIN SELECT RAISE(ABORT,'Event facts cannot be replaced or appended after posting'); END''',
      ],
      for (final trigger in freezeJournal)
        trigger
            .replaceAll('treasury_operation_', 'event_journal_')
            .replaceAll(
              'JOIN treasury_operations operation',
              'JOIN events operation',
            ),
      for (final type in ['purchase_receipt', 'credit_sale', 'event_creation'])
        '''CREATE TRIGGER ${type}_respect_event_chronology BEFORE UPDATE OF status ON business_documents
 WHEN OLD.status='draft' AND NEW.status='posted' AND NEW.type='$type'
 BEGIN SELECT CASE WHEN EXISTS(SELECT 1 FROM event_products part JOIN business_documents previous ON previous.id=part.event_id AND previous.status='posted'
 WHERE ${utcKey('previous.occurred_at_utc')}>${utcKey('NEW.occurred_at_utc')} AND part.product_id IN(
 ${type == 'purchase_receipt'
            ? 'SELECT product_id FROM purchase_lines WHERE purchase_id=NEW.id'
            : type == 'credit_sale'
            ? 'SELECT product_id FROM sale_lines WHERE sale_id=NEW.id'
            : 'SELECT product_id FROM event_products WHERE event_id=NEW.id'}))
 THEN RAISE(ABORT,'Inventory operation cannot precede event consumption') END; END''',
      '''CREATE TRIGGER event_no_physical_receipt BEFORE INSERT ON purchase_lines WHEN EXISTS(SELECT 1 FROM events WHERE product_id=NEW.product_id)
 BEGIN SELECT RAISE(ABORT,'Events cannot receive physical inventory'); END''',
    ];
    return result;
  }
}
