/// v21: positive count corrections reuse normal FIFO layers, without purchases.
abstract final class StockCorrectionSchema {
  static List<String> build({
    required List<String> inventory,
    required List<String> adjustments,
    required String Function(String) utcKey,
  }) {
    String released(String name) => adjustments.singleWhere(
      (s) => RegExp('^CREATE (TRIGGER|VIEW) $name\\b').hasMatch(s),
    );
    String replace(String source, String before, String after) {
      if (!source.contains(before)) {
        throw StateError('Missing stock correction anchor: $before');
      }
      return source.replaceFirst(before, after);
    }

    var movement = inventory.singleWhere(
      (s) => s.contains('CREATE TABLE inventory_movements ('),
    );
    movement = replace(
      movement,
      "kind TEXT NOT NULL CHECK (kind = 'purchase')",
      "kind TEXT NOT NULL CHECK (kind IN ('purchase','adjustment'))",
    );
    movement = replace(
      movement,
      'purchase_line_id TEXT NOT NULL UNIQUE',
      'purchase_line_id TEXT UNIQUE',
    );
    movement = replace(
      movement,
      'UNIQUE (document_id, sequence)',
      "stock_addition_id TEXT UNIQUE REFERENCES stock_additions(id) ON DELETE RESTRICT,\n  CHECK((kind='purchase' AND purchase_line_id IS NOT NULL AND stock_addition_id IS NULL) OR (kind='adjustment' AND purchase_line_id IS NULL AND stock_addition_id IS NOT NULL)),\n  UNIQUE (document_id, sequence)",
    );
    final movementTriggers = inventory
        .where(
          (s) => RegExp(
            r'^\s*CREATE TRIGGER \w+\s+.*\bON inventory_movements\b',
            dotAll: true,
          ).hasMatch(s),
        )
        .toList();
    final modified = <String>[
      replace(
        replace(
          released('adjustment_posting'),
          "(NEW.type='stock_adjustment' OR EXISTS(SELECT 1 FROM stock_adjustments WHERE document_id=NEW.id))",
          "(NEW.type='stock_adjustment' OR EXISTS(SELECT 1 FROM stock_adjustments WHERE document_id=NEW.id)) AND NOT EXISTS(SELECT 1 FROM stock_additions WHERE document_id=NEW.id)",
        ),
        "WHERE adjustment.document_id=NEW.id AND request.status='prepared'",
        "WHERE adjustment.document_id=NEW.id AND coalesce(json_extract(request.canonical_payload,'\$.isAddition'),0)=0 AND request.status='prepared'",
      ),
      released('stock_adjustment_requests_update').replaceAll(
        'FROM stock_adjustments event',
        'FROM inventory_adjustment_facts event',
      ),
      released('entries_validate_posting').replaceAll(
        'FROM stock_adjustments adjustment',
        'FROM inventory_adjustment_facts adjustment',
      ),
      released(
        'inventory_adjustment_chronology',
      ).replaceAll('FROM stock_adjustments', 'FROM inventory_adjustment_facts'),
      for (final sql in adjustments.where(
        (s) => s.startsWith('CREATE TRIGGER adjustment_journal_'),
      ))
        sql.replaceAll(
          'JOIN stock_adjustments operation',
          'JOIN inventory_adjustment_facts operation',
        ),
    ];
    return [
      'ALTER TABLE quick_sales_accounts ADD COLUMN created_at_utc TEXT CHECK(created_at_utc IS NULL OR (julianday(created_at_utc) IS NOT NULL AND substr(created_at_utc,-1)=\'Z\'))',
      '''CREATE TRIGGER quick_account_creation_immutable BEFORE UPDATE OF created_at_utc ON quick_sales_accounts
 WHEN NEW.created_at_utc IS NOT OLD.created_at_utc BEGIN SELECT RAISE(ABORT,'Account creation time is immutable'); END''',
      '''CREATE TABLE stock_additions (
 id TEXT PRIMARY KEY NOT NULL,
 document_id TEXT NOT NULL UNIQUE REFERENCES business_documents(id) ON DELETE RESTRICT,
 product_id TEXT NOT NULL REFERENCES catalog_items(id) ON DELETE RESTRICT,
 name_snapshot TEXT NOT NULL,
 quantity INTEGER NOT NULL CHECK(typeof(quantity)='integer' AND quantity>0),
 unit_cost_minor INTEGER NOT NULL CHECK(typeof(unit_cost_minor)='integer' AND unit_cost_minor>=0),
 cost_minor INTEGER NOT NULL CHECK(typeof(cost_minor)='integer' AND cost_minor>=0 AND typeof(quantity*unit_cost_minor)='integer' AND cost_minor=quantity*unit_cost_minor),
 reference_cost_layer_id TEXT REFERENCES cost_layers(id) ON DELETE RESTRICT,
 reference_opening_item_id TEXT REFERENCES inventory_opening_items(id) ON DELETE RESTRICT,
 reason TEXT NOT NULL CHECK(length(trim(reason)) BETWEEN 1 AND 300),
 CHECK((reference_cost_layer_id IS NULL)<>(reference_opening_item_id IS NULL)))''',
      'CREATE INDEX idx_stock_additions_product ON stock_additions(product_id)',
      // Defer, never disable, the child references while replacing their parent.
      'PRAGMA defer_foreign_keys=ON',
      movement.replaceFirst(
        'CREATE TABLE inventory_movements (',
        'CREATE TABLE inventory_movements_v21_buffer (',
      ),
      'INSERT INTO inventory_movements_v21_buffer SELECT *,NULL FROM inventory_movements',
      'DROP TABLE inventory_movements',
      movement,
      'INSERT INTO inventory_movements SELECT * FROM inventory_movements_v21_buffer',
      'DROP TABLE inventory_movements_v21_buffer',
      ...inventory.where((s) => s.startsWith('CREATE INDEX idx_movements_')),
      ...movementTriggers,
      '''CREATE VIEW inventory_adjustment_facts AS
 SELECT document_id,product_id,cost_minor FROM stock_adjustments
 UNION ALL SELECT document_id,product_id,cost_minor FROM stock_additions''',
      '''CREATE VIEW inventory_reference_costs AS
 SELECT layer.id,layer.product_id,layer.total_cost_minor/layer.initial_quantity+
 CASE WHEN layer.total_cost_minor%layer.initial_quantity>=layer.initial_quantity/2+layer.initial_quantity%2 THEN 1 ELSE 0 END unit_cost_minor,
 'purchase' source_kind,layer.acquired_at_utc,layer.fifo_sequence FROM cost_layers layer
 JOIN inventory_movements movement ON movement.id=layer.inbound_movement_id AND movement.kind='purchase'
 JOIN business_documents d ON d.id=movement.document_id AND d.status='posted'
 JOIN journal_entries e ON e.document_id=d.id AND e.status='posted'
 UNION ALL SELECT item.id,item.product_id,item.unit_cost_minor,'opening',opening.occurred_at_utc,0
 FROM inventory_opening_items item JOIN inventory_openings opening ON opening.document_id=item.opening_id
 JOIN business_documents d ON d.id=opening.document_id AND d.status='posted'
 JOIN journal_entries e ON e.document_id=d.id AND e.status='posted' ''',
      'DROP VIEW stock_adjustment_expected_journal',
      '${released('stock_adjustment_expected_journal')}\n UNION ALL SELECT document_id,\'system:inventory\',cost_minor,0 FROM stock_additions WHERE cost_minor>0\n UNION ALL SELECT document_id,\'inventory:adjustment-expense\',0,cost_minor FROM stock_additions WHERE cost_minor>0',
      for (final sql in modified) ...[
        'DROP TRIGGER ${RegExp(r'^CREATE TRIGGER (\w+)').firstMatch(sql)!.group(1)}',
        sql,
      ],
      for (final action in ['UPDATE', 'DELETE'])
        "CREATE TRIGGER stock_additions_no_${action.toLowerCase()} BEFORE $action ON stock_additions BEGIN SELECT RAISE(ABORT,'Count corrections are immutable'); END",
      '''CREATE TRIGGER stock_additions_insert BEFORE INSERT ON stock_additions BEGIN
 SELECT CASE WHEN EXISTS(SELECT 1 FROM stock_additions WHERE id=NEW.id OR document_id=NEW.document_id)
 OR NOT EXISTS(SELECT 1 FROM business_documents WHERE id=NEW.document_id AND type='stock_adjustment' AND status='draft')
 THEN RAISE(ABORT,'Positive correction requires a new draft document') END; END''',
      '''CREATE TRIGGER stock_addition_posting BEFORE UPDATE OF status ON business_documents
 WHEN NEW.status='posted' AND EXISTS(SELECT 1 FROM stock_additions WHERE document_id=NEW.id) BEGIN
 SELECT CASE WHEN OLD.status<>'draft' OR NEW.type<>'stock_adjustment' OR NEW.command_sequence<>0
 OR date(NEW.occurred_at_utc,'-5 hours') IS NOT NEW.business_date
 OR EXISTS(SELECT 1 FROM stock_adjustments WHERE document_id=NEW.id)
 OR NOT EXISTS(SELECT 1 FROM stock_additions a JOIN catalog_items p ON p.id=a.product_id
 JOIN command_log c ON c.id=NEW.command_id JOIN stock_adjustment_requests r ON r.command_id=c.id AND r.status='prepared'
 JOIN app_profile profile ON profile.profile_id=NEW.profile_id JOIN actors actor ON actor.id=NEW.actor_id AND actor.is_active=1
 WHERE a.document_id=NEW.id AND c.command_type='stock_adjustment' AND c.actor_id=NEW.actor_id
 AND c.authorization_policy_version='development-single-user-v1' AND r.canonical_payload=json_extract(c.response_json,'\$.canonicalPayload')
 AND json_extract(r.canonical_payload,'\$.isAddition')=1
 AND json_extract(r.canonical_payload,'\$.commandId')=NEW.command_id
 AND json_extract(r.canonical_payload,'\$.productId')=a.product_id
 AND json_extract(r.canonical_payload,'\$.quantity')=a.quantity
 AND json_extract(r.canonical_payload,'\$.reason')=a.reason AND a.reason=NEW.reason
 AND json_extract(r.canonical_payload,'\$.occurredAtUtc')=NEW.occurred_at_utc
 AND json_extract(r.canonical_payload,'\$.profileId')=NEW.profile_id
 AND json_extract(r.canonical_payload,'\$.currency')=profile.currency_code
 AND json_extract(r.canonical_payload,'\$.scale')=profile.money_scale
 AND json_extract(r.canonical_payload,'\$.costMinor')=a.cost_minor
 AND json_extract(r.canonical_payload,'\$.productName')=a.name_snapshot AND a.name_snapshot=p.name
 AND json_extract(r.canonical_payload,'\$.referenceId')=coalesce(a.reference_cost_layer_id,a.reference_opening_item_id)
 AND json_extract(r.canonical_payload,'\$.referenceSource')=CASE WHEN a.reference_cost_layer_id IS NULL THEN 'opening' ELSE 'purchase' END
 AND NOT EXISTS(SELECT 1 FROM events WHERE product_id=p.id) AND NOT EXISTS(SELECT 1 FROM catalog_services WHERE product_id=p.id)
 AND EXISTS(SELECT 1 FROM inventory_reference_costs ref WHERE ref.product_id=p.id
 AND ref.id=coalesce(a.reference_cost_layer_id,a.reference_opening_item_id)
 AND ref.source_kind=CASE WHEN a.reference_cost_layer_id IS NULL THEN 'opening' ELSE 'purchase' END
 AND ref.unit_cost_minor=a.unit_cost_minor
 AND ${utcKey('ref.acquired_at_utc')}<=${utcKey('NEW.occurred_at_utc')}
 AND ref.id=(SELECT id FROM inventory_reference_costs WHERE product_id=p.id ORDER BY ${utcKey('acquired_at_utc')} DESC,fifo_sequence DESC,id DESC LIMIT 1))
 AND coalesce((SELECT sum(layer.initial_quantity-coalesce((SELECT sum(usage.quantity) FROM inventory_cost_usage usage WHERE
 (layer.source_kind='purchase' AND usage.cost_layer_id=layer.id) OR(layer.source_kind='opening' AND usage.opening_item_id=layer.id)),0)) FROM inventory_effective_layers layer WHERE layer.product_id=p.id),0)<=9223372036854775807-a.quantity
 AND coalesce((SELECT sum(layer.total_cost_minor-coalesce((SELECT sum(usage.cost_minor) FROM inventory_cost_usage usage WHERE
 (layer.source_kind='purchase' AND usage.cost_layer_id=layer.id) OR(layer.source_kind='opening' AND usage.opening_item_id=layer.id)),0)) FROM inventory_effective_layers layer WHERE layer.product_id=p.id),0)<=9223372036854775807-a.cost_minor
 AND (SELECT count(*) FROM inventory_movements WHERE document_id=NEW.id)=1
 AND EXISTS(SELECT 1 FROM inventory_movements m JOIN cost_layers layer ON layer.inbound_movement_id=m.id
 WHERE m.document_id=NEW.id AND m.stock_addition_id=a.id AND m.kind='adjustment' AND m.sequence=0 AND m.purchase_line_id IS NULL
 AND m.product_id=a.product_id AND m.quantity_delta=a.quantity AND m.value_delta_minor=a.cost_minor
 AND layer.product_id=a.product_id AND layer.initial_quantity=a.quantity AND layer.total_cost_minor=a.cost_minor
 AND layer.fifo_sequence=m.stock_sequence AND layer.acquired_at_utc=NEW.occurred_at_utc AND layer.cost_quality='documented'))
 THEN RAISE(ABORT,'Positive correction requires exact prepared stock and last registered cost') END;
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM journal_entries WHERE document_id=NEW.id AND status='draft' AND cost_completeness='complete' AND reversal_of_id IS NULL)
 OR (SELECT count(*) FROM journal_lines l JOIN journal_entries e ON e.id=l.entry_id WHERE e.document_id=NEW.id)<>(SELECT count(*) FROM stock_adjustment_expected_journal WHERE document_id=NEW.id)
 OR EXISTS(SELECT 1 FROM stock_adjustment_expected_journal expected WHERE expected.document_id=NEW.id AND NOT EXISTS(
 SELECT 1 FROM journal_entries e JOIN journal_lines l ON l.entry_id=e.id JOIN ledger_accounts account ON account.id=l.account_id AND account.is_active=1
 WHERE e.document_id=NEW.id AND l.account_id=expected.account_id AND l.debit_minor=expected.debit_minor AND l.credit_minor=expected.credit_minor
 AND ((account.id='system:inventory' AND account.class='asset' AND account.role='inventory') OR(account.id='inventory:adjustment-expense' AND account.class='expense' AND account.role='inventory_adjustment'))))
 THEN RAISE(ABORT,'Positive correction requires its exact non-cash journal') END; END''',
    ];
  }
}
