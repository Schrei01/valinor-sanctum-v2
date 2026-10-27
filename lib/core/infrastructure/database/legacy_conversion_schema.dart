abstract final class LegacyConversionSchema {
  static const tables = [
    'caja_mayor',
    'cash',
    'deudas',
    'movimientos',
    'nequi',
    'products',
    'sales',
    'transfermovements',
  ];
  static final List<String> statements = [
    '''CREATE TABLE legacy_conversions (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      source_name TEXT NOT NULL,
      source_sha256 TEXT NOT NULL UNIQUE CHECK (length(source_sha256) = 64),
      content_sha256 TEXT NOT NULL CHECK (length(content_sha256) = 64),
      source_schema_json TEXT NOT NULL CHECK (json_valid(source_schema_json)),
      counts_json TEXT NOT NULL CHECK (json_valid(counts_json)),
      timezone TEXT NOT NULL CHECK (timezone = 'America/Bogota'),
      money_scale INTEGER NOT NULL CHECK (typeof(money_scale) = 'integer' AND money_scale BETWEEN 0 AND 6),
      treasury_opening_id TEXT NOT NULL REFERENCES treasury_openings(document_id) ON DELETE RESTRICT,
      converted_at_utc TEXT NOT NULL,
      status TEXT NOT NULL CHECK (status IN ('draft', 'complete'))
    )''',
    '''CREATE TABLE legacy_source_rows (
      conversion_id INTEGER NOT NULL CHECK (conversion_id = 1) REFERENCES legacy_conversions(id) ON DELETE RESTRICT,
      source_table TEXT NOT NULL CHECK (source_table IN ('caja_mayor','cash','deudas','movimientos','nequi','products','sales','transfermovements')),
      source_id INTEGER NOT NULL CHECK (typeof(source_id) = 'integer' AND source_id > 0),
      row_json TEXT NOT NULL CHECK (json_valid(row_json) AND json_extract(row_json, '\$.id') = source_id),
      PRIMARY KEY (source_table, source_id)
    )''',
    '''CREATE TABLE legacy_balance_history (
      source_table TEXT NOT NULL CHECK (source_table IN ('cash','nequi','caja_mayor','deudas')),
      source_id INTEGER NOT NULL,
      role TEXT NOT NULL CHECK ((source_table = 'cash' AND role = 'cash') OR (source_table = 'nequi' AND role = 'nequi') OR (source_table = 'caja_mayor' AND role = 'reserve') OR (source_table = 'deudas' AND role = 'receivables')),
      source_date_raw TEXT,
      occurred_at_utc TEXT,
      amount_minor INTEGER NOT NULL CHECK (typeof(amount_minor) = 'integer'),
      PRIMARY KEY (source_table, source_id),
      FOREIGN KEY (source_table, source_id) REFERENCES legacy_source_rows(source_table, source_id) ON DELETE RESTRICT
    )''',
    'CREATE INDEX legacy_balance_history_cutoff ON legacy_balance_history(role, occurred_at_utc, source_id)',
    '''CREATE TRIGGER legacy_conversions_validate_insert BEFORE INSERT ON legacy_conversions
    BEGIN
      SELECT CASE WHEN NEW.status <> 'draft' OR NOT EXISTS (
        SELECT 1 FROM treasury_openings t JOIN inventory_openings i ON i.profile_id = t.profile_id
        JOIN app_profile p ON p.profile_id = t.profile_id
        WHERE t.document_id = NEW.treasury_opening_id AND t.source_sha256 = NEW.source_sha256
        AND i.source_sha256 = NEW.source_sha256 AND p.money_scale = NEW.money_scale
      ) THEN RAISE(ABORT, 'Conversion origin does not match operational openings') END;
    END''',
    '''CREATE TRIGGER legacy_conversions_complete BEFORE UPDATE ON legacy_conversions
    BEGIN
      SELECT CASE WHEN OLD.status <> 'draft' OR NEW.status <> 'complete'
      OR NEW.id IS NOT OLD.id OR NEW.source_name IS NOT OLD.source_name
      OR NEW.source_sha256 IS NOT OLD.source_sha256 OR NEW.content_sha256 IS NOT OLD.content_sha256
      OR NEW.source_schema_json IS NOT OLD.source_schema_json OR NEW.counts_json IS NOT OLD.counts_json
      OR NEW.timezone IS NOT OLD.timezone OR NEW.money_scale IS NOT OLD.money_scale
      OR NEW.treasury_opening_id IS NOT OLD.treasury_opening_id OR NEW.converted_at_utc IS NOT OLD.converted_at_utc
      THEN RAISE(ABORT, 'Conversion is immutable') END;
      ${tables.map((table) => "SELECT CASE WHEN (SELECT count(*) FROM legacy_source_rows WHERE source_table = '$table') IS NOT json_extract(NEW.counts_json, '\$.$table') THEN RAISE(ABORT, 'Incomplete conversion archive') END;").join('\n')}
      SELECT CASE WHEN (SELECT count(*) FROM legacy_balance_history) <>
        (SELECT count(*) FROM legacy_source_rows WHERE source_table IN ('cash','nequi','caja_mayor','deudas'))
      THEN RAISE(ABORT, 'Incomplete balance history') END;
    END''',
    "CREATE TRIGGER legacy_conversions_no_delete BEFORE DELETE ON legacy_conversions BEGIN SELECT RAISE(ABORT, 'Conversion is immutable'); END",
    for (final table in ['legacy_source_rows', 'legacy_balance_history']) ...[
      "CREATE TRIGGER ${table}_insert BEFORE INSERT ON $table WHEN NOT EXISTS (SELECT 1 FROM legacy_conversions WHERE id = 1 AND status = 'draft') BEGIN SELECT RAISE(ABORT, 'Conversion is sealed'); END",
      for (final action in ['UPDATE', 'DELETE'])
        "CREATE TRIGGER ${table}_${action.toLowerCase()} BEFORE $action ON $table BEGIN SELECT RAISE(ABORT, 'Converted history is immutable'); END",
    ],
  ];
}
