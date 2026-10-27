/// v16: traced FIFO write-offs and explicit non-stock day passes.
abstract final class CatalogOperationsSchema {
  static List<String> build({
    required List<String> releasedEvents,
    required String Function(String) utcKey,
  }) {
    String released(String name) => releasedEvents.singleWhere(
      (sql) => sql.startsWith('CREATE TRIGGER $name '),
    );
    final posting = releasedEvents.singleWhere(
      (s) => s.startsWith('CREATE TRIGGER sales_validate_document_posting\n'),
    );
    final entry = releasedEvents.singleWhere(
      (s) => s.startsWith('CREATE TRIGGER entries_validate_posting\n'),
    );
    final allocations = released('event_cost_validate')
        .replaceAll('event_cost_validate', 'stock_adjustment_cost_validate')
        .replaceAll('event_cost_allocations', 'stock_adjustment_allocations')
        .replaceAll('event_products', 'stock_adjustments')
        .replaceAll('event_product_id', 'adjustment_id')
        .replaceAll('part.event_id', 'part.document_id')
        .replaceAll(
          "document.type='event_creation'",
          "document.type='stock_adjustment'",
        );
    final result = <String>[
      '''CREATE TABLE catalog_services (
 product_id TEXT PRIMARY KEY NOT NULL REFERENCES catalog_items(id) ON DELETE RESTRICT,
 kind TEXT NOT NULL CHECK(kind='day_pass'))''',
      '''CREATE TRIGGER services_validate_insert BEFORE INSERT ON catalog_services
 BEGIN SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM catalog_items WHERE id=NEW.product_id
 AND lower(replace(replace(trim(name),'í','i'),'Í','i'))='pasadia')
 OR EXISTS(SELECT 1 FROM inventory_effective_layers layer WHERE layer.product_id=NEW.product_id AND
 layer.total_cost_minor>coalesce((SELECT sum(cost_minor) FROM inventory_cost_usage WHERE
 (layer.source_kind='purchase' AND cost_layer_id=layer.id) OR(layer.source_kind='opening' AND opening_item_id=layer.id)),0))
 THEN RAISE(ABORT,'Only day passes without physical inventory cost can become unlimited services') END; END''',
      '''INSERT INTO catalog_services SELECT id,'day_pass' FROM catalog_items
 WHERE lower(replace(replace(trim(name),'í','i'),'Í','i'))='pasadia'
 AND NOT EXISTS(SELECT 1 FROM events WHERE product_id=catalog_items.id)''',
      '''CREATE TRIGGER catalog_register_day_pass AFTER INSERT ON catalog_items
 WHEN lower(replace(replace(trim(NEW.name),'í','i'),'Í','i'))='pasadia'
 BEGIN INSERT INTO catalog_services VALUES(NEW.id,'day_pass'); END''',
      '''CREATE TRIGGER service_no_purchase BEFORE INSERT ON purchase_lines
 WHEN EXISTS(SELECT 1 FROM catalog_services WHERE product_id=NEW.product_id)
 BEGIN SELECT RAISE(ABORT,'Day passes have unlimited availability and cannot receive purchases'); END''',
      '''CREATE TRIGGER service_no_event_material BEFORE INSERT ON event_products
 WHEN EXISTS(SELECT 1 FROM catalog_services WHERE product_id=NEW.product_id)
 BEGIN SELECT RAISE(ABORT,'Day passes cannot be consumed as physical prizes'); END''',
      '''CREATE TRIGGER service_opening_no_value BEFORE INSERT ON inventory_opening_items
 WHEN NEW.total_cost_minor<>0 AND EXISTS(SELECT 1 FROM catalog_services WHERE product_id=NEW.product_id)
 BEGIN SELECT RAISE(ABORT,'Day passes cannot carry physical opening value'); END''',
      '''CREATE TABLE stock_adjustment_requests (
 command_id TEXT PRIMARY KEY NOT NULL CHECK(length(trim(command_id)) BETWEEN 1 AND 128),
 canonical_payload TEXT NOT NULL CHECK(json_valid(canonical_payload)),
 prepared_at_utc TEXT NOT NULL,
 status TEXT NOT NULL CHECK(status IN('prepared','confirmed','discarded')))''',
      '''CREATE TABLE stock_adjustments (
 id TEXT PRIMARY KEY NOT NULL,
 document_id TEXT NOT NULL UNIQUE REFERENCES business_documents(id) ON DELETE RESTRICT,
 product_id TEXT NOT NULL REFERENCES catalog_items(id) ON DELETE RESTRICT,
 name_snapshot TEXT NOT NULL,
 quantity INTEGER NOT NULL CHECK(typeof(quantity)='integer' AND quantity>0),
 cost_minor INTEGER NOT NULL CHECK(typeof(cost_minor)='integer' AND cost_minor>=0),
 reason TEXT NOT NULL CHECK(length(trim(reason)) BETWEEN 1 AND 300))''',
      '''CREATE TABLE stock_adjustment_allocations (
 id TEXT PRIMARY KEY NOT NULL,
 adjustment_id TEXT NOT NULL REFERENCES stock_adjustments(id) ON DELETE RESTRICT,
 sequence INTEGER NOT NULL CHECK(typeof(sequence)='integer' AND sequence>=0),
 cost_layer_id TEXT REFERENCES cost_layers(id) ON DELETE RESTRICT,
 opening_item_id TEXT REFERENCES inventory_opening_items(id) ON DELETE RESTRICT,
 quantity INTEGER NOT NULL CHECK(typeof(quantity)='integer' AND quantity>0),
 cost_minor INTEGER NOT NULL CHECK(typeof(cost_minor)='integer' AND cost_minor>=0),
 CHECK((cost_layer_id IS NULL)<>(opening_item_id IS NULL)), UNIQUE(adjustment_id,sequence))''',
      'CREATE INDEX idx_adjustment_product ON stock_adjustments(product_id)',
      'CREATE INDEX idx_adjustment_cost ON stock_adjustment_allocations(cost_layer_id)',
      'CREATE INDEX idx_adjustment_opening ON stock_adjustment_allocations(opening_item_id)',
      'DROP VIEW inventory_cost_usage',
      '''CREATE VIEW inventory_cost_usage AS
 SELECT cost_layer_id,NULL AS opening_item_id,quantity,cost_minor FROM sale_cost_allocations
 UNION ALL SELECT NULL,opening_item_id,quantity,cost_minor FROM inventory_opening_allocations
 UNION ALL SELECT cost_layer_id,opening_item_id,quantity,cost_minor FROM event_cost_allocations
 UNION ALL SELECT cost_layer_id,opening_item_id,quantity,cost_minor FROM stock_adjustment_allocations''',
      'DROP TRIGGER sales_validate_document_posting',
      posting.replaceAll(
        '(SELECT product_id FROM events)',
        '(SELECT product_id FROM events UNION SELECT product_id FROM catalog_services)',
      ),
      '''CREATE TRIGGER service_sale_posting BEFORE UPDATE OF status ON business_documents
 WHEN OLD.status='draft' AND NEW.status='posted' AND NEW.type='credit_sale'
 BEGIN SELECT CASE WHEN EXISTS(SELECT 1 FROM sale_lines line JOIN catalog_services service ON service.product_id=line.product_id
 WHERE line.sale_id=NEW.id AND (line.total_cost_minor<>0 OR EXISTS(SELECT 1 FROM sale_outflows WHERE sale_line_id=line.id)
 OR EXISTS(SELECT 1 FROM all_sale_cost_allocations WHERE sale_line_id=line.id)))
 THEN RAISE(ABORT,'Day passes must be sold without physical cost or stock outflows') END; END''',
      'DROP TRIGGER entries_validate_posting',
      entry.replaceFirst(
        "    THEN RAISE(ABORT, 'A posted entry needs at least two lines except a confirmed zero value inventory opening')",
        "    AND NOT EXISTS(SELECT 1 FROM stock_adjustments adjustment JOIN business_documents document ON document.id=adjustment.document_id WHERE adjustment.document_id=NEW.document_id AND document.type='stock_adjustment' AND document.status='posted' AND adjustment.cost_minor=0 AND NEW.cost_completeness='complete' AND NOT EXISTS(SELECT 1 FROM journal_lines WHERE entry_id=NEW.id))\n    THEN RAISE(ABORT, 'A posted entry needs at least two lines except a confirmed zero value inventory opening')",
      ),
      allocations,
      released('event_requests_insert')
          .replaceAll('event_requests', 'stock_adjustment_requests')
          .replaceAll(
            'CREATE TRIGGER stock_adjustment_requests_insert',
            'CREATE TRIGGER stock_adjustment_requests_insert',
          )
          .replaceFirst(
            " OR EXISTS(SELECT 1 FROM command_log",
            " OR EXISTS(SELECT 1 FROM event_requests WHERE command_id=NEW.command_id)\n OR EXISTS(SELECT 1 FROM debtor_requests WHERE command_id=NEW.command_id)\n OR EXISTS(SELECT 1 FROM command_log",
          ),
      released('event_requests_update')
          .replaceAll('event_requests', 'stock_adjustment_requests')
          .replaceAll('FROM events event', 'FROM stock_adjustments event'),
      "CREATE TRIGGER stock_adjustment_requests_delete BEFORE DELETE ON stock_adjustment_requests BEGIN SELECT RAISE(ABORT,'Adjustment requests are durable'); END",
      released('event_command_reserved')
          .replaceAll(
            'event_command_reserved',
            'stock_adjustment_command_reserved',
          )
          .replaceAll('event_requests', 'stock_adjustment_requests')
          .replaceAll("'create_event'", "'stock_adjustment'"),
      for (final table in [
        'sale_confirmations',
        'collection_requests',
        'supplier_payment_requests',
        'treasury_operation_requests',
        'quick_sale_requests',
        'paid_purchase_requests',
        'event_requests',
        'debtor_requests',
      ])
        '''CREATE TRIGGER ${table}_respect_adjustment BEFORE INSERT ON $table
 WHEN EXISTS(SELECT 1 FROM stock_adjustment_requests WHERE command_id=NEW.command_id
 ${table == 'quick_sale_requests'
            ? 'OR command_id IN(NEW.sale_command_id,NEW.collection_command_id)'
            : table == 'paid_purchase_requests'
            ? 'OR command_id IN(NEW.purchase_command_id,NEW.payment_command_id)'
            : ''})
 BEGIN SELECT RAISE(ABORT,'Identifier reserved by stock adjustment'); END''',
      '''CREATE TRIGGER adjustment_draft BEFORE INSERT ON business_documents
 WHEN NEW.type='stock_adjustment' AND NEW.status<>'draft'
 BEGIN SELECT RAISE(ABORT,'Create adjustment as draft'); END''',
      '''CREATE VIEW stock_adjustment_expected_journal AS
 SELECT document_id,'inventory:adjustment-expense' account_id,cost_minor debit_minor,0 credit_minor FROM stock_adjustments WHERE cost_minor>0
 UNION ALL SELECT document_id,'system:inventory',0,cost_minor FROM stock_adjustments WHERE cost_minor>0''',
      '''CREATE TRIGGER adjustment_posting BEFORE UPDATE OF status ON business_documents
 WHEN OLD.status='draft' AND NEW.status='posted' AND (NEW.type='stock_adjustment' OR EXISTS(SELECT 1 FROM stock_adjustments WHERE document_id=NEW.id))
 BEGIN
 SELECT CASE WHEN NEW.type<>'stock_adjustment' OR NEW.command_sequence<>0 OR date(NEW.occurred_at_utc,'-5 hours') IS NOT NEW.business_date
 OR NOT EXISTS(SELECT 1 FROM stock_adjustments adjustment JOIN catalog_items product ON product.id=adjustment.product_id
 LEFT JOIN categories category ON category.id=product.category_id JOIN command_log command ON command.id=NEW.command_id
 JOIN stock_adjustment_requests request ON request.command_id=command.id JOIN app_profile profile ON profile.profile_id=NEW.profile_id
 JOIN actors actor ON actor.id=NEW.actor_id AND actor.is_active=1
 WHERE adjustment.document_id=NEW.id AND request.status='prepared' AND command.command_type='stock_adjustment'
 AND command.actor_id=NEW.actor_id AND command.authorization_policy_version='development-single-user-v1'
 AND product.name=adjustment.name_snapshot
 AND NOT EXISTS(SELECT 1 FROM events WHERE product_id=product.id) AND NOT EXISTS(SELECT 1 FROM catalog_services WHERE product_id=product.id)
 AND request.canonical_payload=json_extract(command.response_json,'\$.canonicalPayload')
 AND json_extract(request.canonical_payload,'\$.productId')=adjustment.product_id
 AND json_extract(request.canonical_payload,'\$.quantity')=adjustment.quantity
 AND json_extract(request.canonical_payload,'\$.reason')=adjustment.reason
 AND json_extract(request.canonical_payload,'\$.occurredAtUtc')=NEW.occurred_at_utc
 AND adjustment.quantity=coalesce((SELECT sum(quantity) FROM stock_adjustment_allocations WHERE adjustment_id=adjustment.id),0)
 AND adjustment.cost_minor=coalesce((SELECT sum(cost_minor) FROM stock_adjustment_allocations WHERE adjustment_id=adjustment.id),0))
 THEN RAISE(ABORT,'Adjustment requires exact prepared physical quantity and FIFO cost') END;
 SELECT CASE WHEN (SELECT count(*) FROM stock_adjustments WHERE document_id=NEW.id)<>1
 OR NOT EXISTS(SELECT 1 FROM journal_entries WHERE document_id=NEW.id AND status='draft' AND cost_completeness='complete' AND reversal_of_id IS NULL)
 OR (SELECT count(*) FROM journal_lines line JOIN journal_entries entry ON entry.id=line.entry_id WHERE entry.document_id=NEW.id)
 <>(SELECT count(*) FROM stock_adjustment_expected_journal WHERE document_id=NEW.id)
 OR EXISTS(SELECT 1 FROM stock_adjustment_expected_journal expected WHERE expected.document_id=NEW.id AND NOT EXISTS(
 SELECT 1 FROM journal_entries entry JOIN journal_lines line ON line.entry_id=entry.id JOIN ledger_accounts account ON account.id=line.account_id AND account.is_active=1
 WHERE entry.document_id=NEW.id AND line.account_id=expected.account_id AND line.debit_minor=expected.debit_minor AND line.credit_minor=expected.credit_minor
 AND ((account.id='inventory:adjustment-expense' AND account.class='expense' AND account.role='inventory_adjustment') OR (account.id='system:inventory' AND account.class='asset' AND account.role='inventory'))))
 THEN RAISE(ABORT,'Adjustment requires exact non-cash inventory expense journal') END; END''',
      for (final table in [
        'stock_adjustments',
        'stock_adjustment_allocations',
      ]) ...[
        for (final action in ['UPDATE', 'DELETE'])
          "CREATE TRIGGER ${table}_no_${action.toLowerCase()} BEFORE $action ON $table BEGIN SELECT RAISE(ABORT,'Stock adjustments are immutable'); END",
        '''CREATE TRIGGER ${table}_no_replace BEFORE INSERT ON $table
 WHEN EXISTS(SELECT 1 FROM $table WHERE id=NEW.id)
 OR NOT EXISTS(SELECT 1 FROM business_documents WHERE id=${table == 'stock_adjustments' ? 'NEW.document_id' : '(SELECT document_id FROM stock_adjustments WHERE id=NEW.adjustment_id)'} AND status='draft' AND type='stock_adjustment')
 BEGIN SELECT RAISE(ABORT,'Stock adjustment cannot be replaced or appended after posting'); END''',
      ],
      for (final sql in releasedEvents.where(
        (s) => s.startsWith('CREATE TRIGGER event_journal_'),
      ))
        sql
            .replaceAll('event_journal_', 'adjustment_journal_')
            .replaceAll(
              'JOIN events operation',
              'JOIN stock_adjustments operation',
            ),
      for (final action in ['UPDATE', 'DELETE'])
        "CREATE TRIGGER services_no_${action.toLowerCase()} BEFORE $action ON catalog_services BEGIN SELECT RAISE(ABORT,'Service classification is permanent'); END",
      '''CREATE TRIGGER services_no_replace BEFORE INSERT ON catalog_services WHEN EXISTS(SELECT 1 FROM catalog_services WHERE product_id=NEW.product_id)
 BEGIN SELECT RAISE(ABORT,'Service classification cannot be replaced'); END''',
    ];
    const affected =
        "SELECT product_id FROM purchase_lines WHERE purchase_id=NEW.id UNION SELECT product_id FROM sale_lines WHERE sale_id=NEW.id UNION SELECT product_id FROM event_products WHERE event_id=NEW.id UNION SELECT product_id FROM stock_adjustments WHERE document_id=NEW.id";
    result.add(
      '''CREATE TRIGGER inventory_adjustment_chronology BEFORE UPDATE OF status ON business_documents
 WHEN OLD.status='draft' AND NEW.status='posted' AND NEW.type IN('purchase_receipt','credit_sale','event_creation','stock_adjustment')
 BEGIN SELECT CASE WHEN EXISTS(SELECT 1 FROM stock_adjustments part JOIN business_documents previous ON previous.id=part.document_id AND previous.status='posted'
 WHERE ${utcKey('previous.occurred_at_utc')}>${utcKey('NEW.occurred_at_utc')} AND part.product_id IN($affected))
 OR (NEW.type='stock_adjustment' AND EXISTS(SELECT 1 FROM business_documents previous WHERE previous.status='posted'
 AND ${utcKey('previous.occurred_at_utc')}>${utcKey('NEW.occurred_at_utc')} AND previous.id IN(
 SELECT purchase_id FROM purchase_lines WHERE product_id IN($affected)
 UNION SELECT sale_id FROM sale_lines WHERE product_id IN($affected)
 UNION SELECT event_id FROM event_products WHERE product_id IN($affected))))
 THEN RAISE(ABORT,'Inventory operations cannot precede confirmed stock consumption') END; END''',
    );
    return result;
  }
}
