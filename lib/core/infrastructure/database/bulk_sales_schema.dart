/// Extend the non-stock classification without changing released migrations.
abstract final class BulkSalesSchema {
  static List<String> build(List<String> released) => [
    for (final name in [
      'services_validate_insert',
      'services_no_update',
      'services_no_delete',
      'services_no_replace',
    ])
      'DROP TRIGGER $name',
    'CREATE TABLE catalog_services_backup_v25 AS SELECT * FROM catalog_services',
    'DROP TABLE catalog_services',
    '''CREATE TABLE catalog_services (
      product_id TEXT PRIMARY KEY NOT NULL REFERENCES catalog_items(id) ON DELETE RESTRICT,
      kind TEXT NOT NULL CHECK(kind IN('day_pass','bulk')))''',
    'INSERT INTO catalog_services SELECT * FROM catalog_services_backup_v25',
    'DROP TABLE catalog_services_backup_v25',
    released
        .singleWhere(
          (s) => s.startsWith('CREATE TRIGGER services_validate_insert '),
        )
        .replaceFirst(
          "AND lower(replace(replace(trim(name),'í','i'),'Í','i'))='pasadia')",
          "AND ((NEW.kind='day_pass' AND lower(replace(replace(trim(name),'í','i'),'Í','i'))='pasadia') OR (NEW.kind='bulk' AND id IN('bulk:sales:magic','bulk:sales:pokemon','bulk:sales:yugioh') AND list_price_minor=0 AND is_active=1 AND EXISTS(SELECT 1 FROM categories WHERE id=catalog_items.category_id AND is_active=1 AND lower(replace(replace(trim(name),'Í','i'),'í','i')) IN('articulo','articulos')))))",
        ),
    ...released.where((s) => s.startsWith('CREATE TRIGGER services_no_')),
    '''CREATE TRIGGER bulk_sale_posting BEFORE UPDATE OF status ON business_documents
      WHEN OLD.status='draft' AND NEW.status='posted' AND NEW.type='credit_sale'
      BEGIN SELECT CASE WHEN EXISTS(SELECT 1 FROM sale_lines l JOIN catalog_services s ON s.product_id=l.product_id AND s.kind='bulk'
        WHERE l.sale_id=NEW.id AND (l.quantity<>1 OR l.unit_price_minor<=0))
      THEN RAISE(ABORT,'Bulk requires one operation and a positive sold value') END; END''',
  ];
}
