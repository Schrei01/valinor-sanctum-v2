abstract final class MembershipSchema {
  static List<String> build(List<String> services, List<String> base) => [
    // Membership is a fixed-price non-stock service. Existing service identities
    // and released migration SQL remain unchanged.
    'DROP TRIGGER services_validate_insert',
    services
        .singleWhere(
          (s) => s.startsWith('CREATE TRIGGER services_validate_insert '),
        )
        .replaceFirst(
          "NEW.kind='day_pass' AND",
          "NEW.kind='day_pass' AND (id='membership:elven' OR",
        )
        .replaceFirst("='pasadia') OR", "='pasadia')) OR"),
    '''ALTER TABLE quick_sales_lines ADD COLUMN membership_discount INTEGER NOT NULL DEFAULT 0 CHECK(membership_discount IN(0,1))''',
    '''CREATE TABLE membership_profiles(
      person_id TEXT PRIMARY KEY NOT NULL REFERENCES debtors(id),
      email TEXT NOT NULL, birth_day INTEGER, birth_month INTEGER,
      CHECK((birth_day IS NULL AND birth_month IS NULL) OR
        (birth_day BETWEEN 1 AND 31 AND birth_month BETWEEN 1 AND 12)))''',
    '''CREATE TABLE membership_periods(
      id TEXT PRIMARY KEY NOT NULL,
      person_id TEXT NOT NULL REFERENCES membership_profiles(person_id),
      sale_request_id TEXT NOT NULL UNIQUE REFERENCES quick_sale_requests(command_id),
      starts TEXT NOT NULL, ends TEXT NOT NULL CHECK(ends>starts),
      amount_minor INTEGER NOT NULL CHECK(amount_minor>0),
      UNIQUE(person_id,starts))''',
    '''CREATE TABLE membership_benefits(
      id TEXT PRIMARY KEY NOT NULL,
      period_id TEXT NOT NULL REFERENCES membership_periods(id),
      kind TEXT NOT NULL CHECK(kind IN('included','discount')),
      product_id TEXT NOT NULL REFERENCES catalog_items(id),
      product_name TEXT NOT NULL,
      quantity INTEGER NOT NULL CHECK(quantity BETWEEN 1 AND 2),
      base_price_minor INTEGER NOT NULL CHECK(base_price_minor>=0),
      charged_minor INTEGER NOT NULL CHECK(charged_minor>=0),
      occurred_at_utc TEXT NOT NULL,
      source_id TEXT NOT NULL)''',
    "CREATE UNIQUE INDEX idx_membership_included ON membership_benefits(period_id) WHERE kind='included'",
    '''CREATE TRIGGER membership_benefit_limit BEFORE INSERT ON membership_benefits
      BEGIN SELECT CASE WHEN (NEW.kind='included' AND NEW.quantity<>1) OR
        (NEW.kind='discount' AND NEW.quantity+coalesce((SELECT sum(quantity) FROM membership_benefits
          WHERE period_id=NEW.period_id AND kind='discount'),0)>2)
      THEN RAISE(ABORT,'Membership benefit exhausted') END; END''',
    '''CREATE TABLE membership_sale_plans(
      request_id TEXT PRIMARY KEY NOT NULL REFERENCES quick_sale_requests(command_id) DEFERRABLE INITIALLY DEFERRED,
      payload TEXT NOT NULL CHECK(json_valid(payload)))''',
    for (final table in [
      'membership_periods',
      'membership_benefits',
      'membership_sale_plans',
    ])
      for (final action in ['UPDATE', 'DELETE'])
        "CREATE TRIGGER ${table}_no_${action.toLowerCase()} BEFORE $action ON $table BEGIN SELECT RAISE(ABORT,'Membership history is immutable'); END",
  ];
}
