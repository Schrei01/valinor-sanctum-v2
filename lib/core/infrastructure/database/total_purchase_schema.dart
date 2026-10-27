/// V15 preserves released intake rows and adds exact total-cost intake plus
/// append-only retail price history. Released migration inputs stay unchanged.
abstract final class TotalPurchaseSchema {
  static List<String> build({
    required List<String> released,
    required String Function(String) entryMatches,
  }) {
    String replace(String source, String old, String next) {
      if (!source.contains(old)) {
        throw StateError('Missing total-cost migration anchor');
      }
      return source.replaceFirst(old, next);
    }

    String match(String fact) {
      final anchor =
          "AND json_extract(request.canonical_payload, '\$.unitPurchasePriceMinor') IS $fact.unit_purchase_price_minor";
      return replace(entryMatches(fact), anchor, '''$anchor
      AND ((json_extract(request.canonical_payload, '\$.version') = 1
        AND $fact.unit_purchase_price_minor IS NOT NULL)
        OR (json_extract(request.canonical_payload, '\$.version') = 2
          AND json_extract(request.canonical_payload, '\$.input.totalPurchasePriceMinor') IS $fact.total_cost_minor
          AND json_extract(request.canonical_payload, '\$.input.unitPurchasePriceMinor') IS NULL
          AND json_extract(request.canonical_payload, '\$.input.quantity') IS $fact.quantity
          AND $fact.unit_purchase_price_minor IS CASE WHEN $fact.total_cost_minor % $fact.quantity = 0
            THEN $fact.total_cost_minor / $fact.quantity END))''');
    }

    var table = released.singleWhere(
      (s) => s.contains('CREATE TABLE paid_purchase_entries ('),
    );
    table = replace(
      table,
      'CREATE TABLE paid_purchase_entries (',
      'CREATE TABLE paid_purchase_entries_upgrade (',
    );
    table = replace(
      table,
      "unit_purchase_price_minor INTEGER NOT NULL CHECK (typeof(unit_purchase_price_minor) = 'integer' AND unit_purchase_price_minor > 0)",
      "unit_purchase_price_minor INTEGER CHECK (unit_purchase_price_minor IS NULL OR (typeof(unit_purchase_price_minor) = 'integer' AND unit_purchase_price_minor > 0))",
    );
    table = replace(
      table,
      "AND typeof(quantity * unit_purchase_price_minor) = 'integer'\n    AND quantity * unit_purchase_price_minor = total_cost_minor",
      "AND (unit_purchase_price_minor IS NULL OR (typeof(quantity * unit_purchase_price_minor) = 'integer'\n    AND quantity * unit_purchase_price_minor = total_cost_minor))",
    );
    var update = released.singleWhere(
      (s) =>
          s.contains('CREATE TRIGGER paid_purchase_requests_validate_update\n'),
    );
    update = replace(update, entryMatches('fact'), match('fact'));
    var insert = released.singleWhere(
      (s) =>
          s.contains('CREATE TRIGGER paid_purchase_entries_validate_insert\n'),
    );
    insert = replace(insert, entryMatches('NEW'), match('NEW'));
    return [
      'DROP TRIGGER paid_purchase_requests_validate_update',
      table,
      'INSERT INTO paid_purchase_entries_upgrade SELECT * FROM paid_purchase_entries',
      'DROP TABLE paid_purchase_entries',
      'ALTER TABLE paid_purchase_entries_upgrade RENAME TO paid_purchase_entries',
      'CREATE INDEX idx_paid_purchase_entries_product ON paid_purchase_entries(product_id)',
      insert,
      ...released.where(
        (s) => s.contains('CREATE TRIGGER paid_purchase_entries_no_'),
      ),
      update,
      '''CREATE TABLE product_price_history (
        id INTEGER PRIMARY KEY,
        product_id TEXT NOT NULL REFERENCES catalog_items(id) ON DELETE RESTRICT,
        previous_price_minor INTEGER CHECK (previous_price_minor IS NULL OR (typeof(previous_price_minor)='integer' AND previous_price_minor>=0)),
        price_minor INTEGER NOT NULL CHECK (typeof(price_minor)='integer' AND price_minor>=0),
        recorded_at_utc TEXT NOT NULL,
        operation_at_utc TEXT,
        request_id TEXT REFERENCES paid_purchase_requests(command_id) ON DELETE RESTRICT,
        source TEXT NOT NULL CHECK (source IN ('baseline','created','changed')),
        CHECK ((source IN ('baseline','created') AND previous_price_minor IS NULL)
          OR (source='changed' AND previous_price_minor IS NOT NULL AND previous_price_minor<>price_minor))
      )''',
      "INSERT INTO product_price_history(product_id,price_minor,recorded_at_utc,source) SELECT id,list_price_minor,strftime('%Y-%m-%dT%H:%M:%fZ','now'),'baseline' FROM catalog_items ORDER BY id",
      'CREATE INDEX product_price_history_product ON product_price_history(product_id,id)',
      r'''CREATE TRIGGER product_price_history_validate_insert BEFORE INSERT ON product_price_history
      BEGIN
        SELECT CASE WHEN NEW.source='baseline' OR EXISTS (SELECT 1 FROM product_price_history WHERE id=NEW.id) OR NOT EXISTS (
          SELECT 1 FROM catalog_items p WHERE p.id=NEW.product_id AND p.list_price_minor=NEW.price_minor)
          OR (NEW.request_id IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM paid_purchase_requests r WHERE r.command_id=NEW.request_id AND r.status='executing'
              AND json_extract(r.canonical_payload,'$.productId')=NEW.product_id
              AND json_extract(r.canonical_payload,'$.listPriceMinor')=NEW.price_minor))
          THEN RAISE(ABORT,'Price history must match the current catalog and purchase') END;
      END''',
      for (final action in ['UPDATE', 'DELETE'])
        'CREATE TRIGGER product_price_history_no_${action.toLowerCase()} BEFORE $action ON product_price_history BEGIN SELECT RAISE(ABORT, \'Price history is immutable\'); END',
      _capture('INSERT', 'created', 'NULL'),
      _capture('UPDATE OF list_price_minor', 'changed', 'OLD.list_price_minor'),
    ];
  }

  static String _capture(String action, String source, String previous) =>
      '''
CREATE TRIGGER catalog_price_history_$source AFTER $action ON catalog_items
${source == 'changed' ? 'WHEN OLD.list_price_minor <> NEW.list_price_minor' : ''}
BEGIN
  INSERT INTO product_price_history(product_id,previous_price_minor,price_minor,recorded_at_utc,operation_at_utc,request_id,source)
  VALUES (NEW.id,$previous,NEW.list_price_minor,strftime('%Y-%m-%dT%H:%M:%fZ','now'),
    (SELECT occurred_at_utc FROM paid_purchase_requests WHERE status='executing'
      AND json_extract(canonical_payload,'\$.productId')=NEW.id
      AND json_extract(canonical_payload,'\$.listPriceMinor')=NEW.list_price_minor ORDER BY command_id LIMIT 1),
    (SELECT command_id FROM paid_purchase_requests WHERE status='executing'
      AND json_extract(canonical_payload,'\$.productId')=NEW.id
      AND json_extract(canonical_payload,'\$.listPriceMinor')=NEW.list_price_minor ORDER BY command_id LIMIT 1), '$source');
END''';
}
