abstract final class PurchaseBatchSchema {
  static const statements = <String>[
    '''CREATE TABLE purchase_batch_requests (
      command_id TEXT PRIMARY KEY NOT NULL CHECK(length(trim(command_id))>0),
      canonical_payload TEXT NOT NULL CHECK(json_valid(canonical_payload)),
      category_id TEXT NOT NULL REFERENCES categories(id),
      category_name_snapshot TEXT NOT NULL,
      payment_option_id TEXT NOT NULL,
      payment_label_snapshot TEXT NOT NULL,
      items_total_minor INTEGER NOT NULL CHECK(typeof(items_total_minor)='integer' AND items_total_minor>0),
      total_paid_minor INTEGER NOT NULL CHECK(typeof(total_paid_minor)='integer' AND total_paid_minor>0),
      occurred_at_utc TEXT NOT NULL,
      prepared_at_utc TEXT NOT NULL,
      status TEXT NOT NULL CHECK(status IN('prepared','confirmed','rejected','discarded')),
      rejection_reason TEXT
    )''',
    '''CREATE TABLE purchase_batch_items (
      batch_id TEXT NOT NULL REFERENCES purchase_batch_requests(command_id),
      sequence INTEGER NOT NULL CHECK(typeof(sequence)='integer' AND sequence>=0),
      child_command_id TEXT NOT NULL UNIQUE,
      declared_cost_minor INTEGER NOT NULL CHECK(typeof(declared_cost_minor)='integer' AND declared_cost_minor>0),
      settlement_cost_minor INTEGER NOT NULL CHECK(typeof(settlement_cost_minor)='integer' AND settlement_cost_minor>0),
      PRIMARY KEY(batch_id,sequence)
    )''',
    '''CREATE TRIGGER purchase_batch_insert BEFORE INSERT ON purchase_batch_requests BEGIN
      SELECT CASE WHEN NEW.status<>'prepared' OR NEW.rejection_reason IS NOT NULL
        OR EXISTS(SELECT 1 FROM command_log WHERE id=NEW.command_id)
        OR NEW.category_id IS NOT json_extract(NEW.canonical_payload,'\$.categoryId')
        OR NEW.payment_option_id IS NOT json_extract(NEW.canonical_payload,'\$.paymentOptionId')
        OR NEW.total_paid_minor IS NOT json_extract(NEW.canonical_payload,'\$.totalPaidMinor')
        OR NEW.occurred_at_utc IS NOT json_extract(NEW.canonical_payload,'\$.occurredAtUtc')
        OR json_extract(NEW.canonical_payload,'\$.version') IS NOT 1
        OR json_type(NEW.canonical_payload,'\$.items') IS NOT 'array'
        OR json_array_length(NEW.canonical_payload,'\$.items') NOT BETWEEN 1 AND 100
        THEN RAISE(ABORT,'Invalid prepared purchase batch') END;
    END''',
    '''CREATE TRIGGER purchase_batch_item_insert BEFORE INSERT ON purchase_batch_items BEGIN
      SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM purchase_batch_requests r
        WHERE r.command_id=NEW.batch_id AND r.status='prepared'
        AND NEW.child_command_id IS json_extract(r.canonical_payload,'\$.items['||NEW.sequence||'].input.commandId')
        AND NEW.declared_cost_minor IS json_extract(r.canonical_payload,'\$.items['||NEW.sequence||'].declaredCostMinor')
        AND NEW.settlement_cost_minor IS json_extract(r.canonical_payload,'\$.items['||NEW.sequence||'].settlementCostMinor'))
        THEN RAISE(ABORT,'Purchase batch item must match prepared payload') END;
    END''',
    '''CREATE TRIGGER purchase_batch_update BEFORE UPDATE ON purchase_batch_requests BEGIN
      SELECT CASE WHEN NEW.command_id IS NOT OLD.command_id OR NEW.canonical_payload IS NOT OLD.canonical_payload
        OR NEW.category_id IS NOT OLD.category_id OR NEW.category_name_snapshot IS NOT OLD.category_name_snapshot
        OR NEW.payment_option_id IS NOT OLD.payment_option_id OR NEW.payment_label_snapshot IS NOT OLD.payment_label_snapshot
        OR NEW.total_paid_minor IS NOT OLD.total_paid_minor OR NEW.items_total_minor IS NOT OLD.items_total_minor
        OR NEW.occurred_at_utc IS NOT OLD.occurred_at_utc OR NEW.prepared_at_utc IS NOT OLD.prepared_at_utc
        OR NOT ((OLD.status='prepared' AND NEW.status IN('confirmed','rejected')) OR (OLD.status='rejected' AND NEW.status='discarded'))
        THEN RAISE(ABORT,'Purchase batch is immutable except valid resolution') END;
      SELECT CASE WHEN NEW.status='confirmed' AND (
        (SELECT count(*) FROM purchase_batch_items WHERE batch_id=NEW.command_id)<>json_array_length(NEW.canonical_payload,'\$.items')
        OR (SELECT sum(declared_cost_minor) FROM purchase_batch_items WHERE batch_id=NEW.command_id) IS NOT NEW.items_total_minor
        OR (SELECT sum(settlement_cost_minor) FROM purchase_batch_items WHERE batch_id=NEW.command_id) IS NOT NEW.total_paid_minor
        OR EXISTS(SELECT 1 FROM purchase_batch_items i LEFT JOIN paid_purchase_entries e ON e.request_id=i.child_command_id
          LEFT JOIN paid_purchase_requests r ON r.command_id=e.request_id
          WHERE i.batch_id=NEW.command_id AND (e.request_id IS NULL OR r.status<>'confirmed'
            OR e.total_cost_minor<>i.settlement_cost_minor OR e.category_id<>NEW.category_id
            OR e.category_name_snapshot<>NEW.category_name_snapshot OR r.occurred_at_utc<>NEW.occurred_at_utc
            OR e.product_id IS NOT json_extract(NEW.canonical_payload,'\$.items['||i.sequence||'].input.productId')
            OR e.product_name_snapshot IS NOT json_extract(NEW.canonical_payload,'\$.items['||i.sequence||'].input.productName')
            OR e.sku_snapshot IS NOT json_extract(NEW.canonical_payload,'\$.items['||i.sequence||'].input.sku')
            OR json_extract(r.canonical_payload,'\$.input.supplierName') IS NOT json_extract(NEW.canonical_payload,'\$.items['||i.sequence||'].input.supplierName')
            OR e.quantity IS NOT json_extract(NEW.canonical_payload,'\$.items['||i.sequence||'].input.quantity')
            OR e.list_price_minor IS NOT json_extract(NEW.canonical_payload,'\$.items['||i.sequence||'].input.listPriceMinor')
            OR json_extract(r.canonical_payload,'\$.paymentOptionId')<>NEW.payment_option_id)))
        THEN RAISE(ABORT,'Purchase batch requires all receipts and exact payment') END;
    END''',
    '''CREATE TRIGGER purchase_batch_command_reserved BEFORE INSERT ON command_log
      WHEN EXISTS(SELECT 1 FROM purchase_batch_requests WHERE command_id=NEW.id)
        OR (EXISTS(SELECT 1 FROM purchase_batch_items WHERE child_command_id=NEW.id)
          AND NOT(NEW.command_type='paid_purchase' AND EXISTS(SELECT 1 FROM paid_purchase_requests WHERE command_id=NEW.id AND status='executing')))
      BEGIN SELECT RAISE(ABORT,'Command identity belongs to purchase batch'); END''',
    '''CREATE TRIGGER purchase_batch_no_delete BEFORE DELETE ON purchase_batch_requests
      BEGIN SELECT RAISE(ABORT,'Purchase batch history is immutable'); END''',
    '''CREATE TRIGGER purchase_batch_items_no_delete BEFORE DELETE ON purchase_batch_items
      BEGIN SELECT RAISE(ABORT,'Purchase batch history is immutable'); END''',
    '''CREATE TRIGGER purchase_batch_items_no_update BEFORE UPDATE ON purchase_batch_items
      BEGIN SELECT RAISE(ABORT,'Purchase batch history is immutable'); END''',
    '''CREATE VIEW purchase_spending AS
      SELECT command_id purchase_id,category_id,category_name_snapshot category_name,
        payment_option_id,payment_label_snapshot payment_label,total_paid_minor amount_paid_minor,occurred_at_utc
      FROM purchase_batch_requests WHERE status='confirmed'
      UNION ALL
      SELECT e.request_id,e.category_id,e.category_name_snapshot,coalesce(e.payment_option_id,'investment'),
        e.payment_option_label_snapshot,e.total_cost_minor,r.occurred_at_utc
      FROM paid_purchase_entries e JOIN paid_purchase_requests r ON r.command_id=e.request_id AND r.status='confirmed'
      WHERE NOT EXISTS(SELECT 1 FROM purchase_batch_items b WHERE b.child_command_id=e.request_id)
    ''',
    '''CREATE VIEW purchase_item_costs AS
      SELECT r.command_id purchase_id,json_extract(line.value,'\$.input.productId') product_id,
        json_extract(line.value,'\$.input.productName') product_name,
        r.category_id,r.category_name_snapshot category_name,
        json_extract(line.value,'\$.input.supplierName') supplier_name,
        json_extract(line.value,'\$.input.quantity') quantity,
        i.declared_cost_minor cost_minor,r.occurred_at_utc
      FROM purchase_batch_requests r JOIN purchase_batch_items i ON i.batch_id=r.command_id,
        json_each(r.canonical_payload,'\$.items') line
      WHERE r.status='confirmed' AND cast(line.key AS INTEGER)=i.sequence
      UNION ALL
      SELECT e.request_id,e.product_id,e.product_name_snapshot,e.category_id,e.category_name_snapshot,
        e.supplier_name_snapshot,e.quantity,e.total_cost_minor,r.occurred_at_utc
      FROM paid_purchase_entries e JOIN paid_purchase_requests r ON r.command_id=e.request_id AND r.status='confirmed'
      WHERE NOT EXISTS(SELECT 1 FROM purchase_batch_items b WHERE b.child_command_id=e.request_id)
    ''',
  ];
}
