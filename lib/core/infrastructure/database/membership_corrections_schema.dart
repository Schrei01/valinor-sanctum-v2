abstract final class MembershipCorrectionsSchema {
  static final statements = <String>[
    '''CREATE TABLE membership_corrections(
      id TEXT PRIMARY KEY NOT NULL, person_id TEXT NOT NULL REFERENCES membership_profiles(person_id),
      period_id TEXT REFERENCES membership_periods(id),
      input_json TEXT NOT NULL CHECK(json_valid(input_json)),
      before_json TEXT NOT NULL CHECK(json_valid(before_json)),
      after_json TEXT NOT NULL CHECK(json_valid(after_json)),
      occurred_at_utc TEXT NOT NULL)''',
    for (final action in ['UPDATE', 'DELETE'])
      "CREATE TRIGGER membership_corrections_no_${action.toLowerCase()} BEFORE $action ON membership_corrections BEGIN SELECT RAISE(ABORT,'Membership corrections are immutable'); END",
    '''CREATE TRIGGER membership_corrections_no_replace BEFORE INSERT ON membership_corrections
      WHEN EXISTS(SELECT 1 FROM membership_corrections WHERE id=NEW.id)
      BEGIN SELECT RAISE(ABORT,'Correction identity is fixed'); END''',
    '''CREATE TRIGGER membership_corrections_validate BEFORE INSERT ON membership_corrections
      BEGIN
      SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM debtors d JOIN membership_profiles p ON p.person_id=d.id
        WHERE d.id=NEW.person_id AND d.is_active=1 AND d.name=json_extract(NEW.before_json,'\$.name')
        AND d.name_key=json_extract(NEW.before_json,'\$.nameKey') AND p.email=json_extract(NEW.before_json,'\$.email')
        AND p.birth_day IS json_extract(NEW.before_json,'\$.birthDay') AND p.birth_month IS json_extract(NEW.before_json,'\$.birthMonth'))
      THEN RAISE(ABORT,'Membership profile changed before correction') END;
      SELECT CASE WHEN NEW.period_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM membership_periods p
        WHERE p.id=NEW.period_id AND p.person_id=NEW.person_id AND p.starts=json_extract(NEW.before_json,'\$.starts') AND p.ends=json_extract(NEW.before_json,'\$.ends'))
      THEN RAISE(ABORT,'Membership period changed before correction') END;
      SELECT CASE WHEN NEW.period_id IS NULL AND (json_extract(NEW.after_json,'\$.starts') IS NOT NULL OR json_extract(NEW.after_json,'\$.ends') IS NOT NULL)
      THEN RAISE(ABORT,'A profile correction cannot create a membership') END;
      SELECT CASE WHEN NEW.period_id IS NOT NULL AND (
        json_type(NEW.after_json,'\$.starts') IS NOT 'text' OR json_type(NEW.after_json,'\$.ends') IS NOT 'text'
        OR
        date(json_extract(NEW.after_json,'\$.starts')) IS NOT json_extract(NEW.after_json,'\$.starts')
        OR json_extract(NEW.after_json,'\$.ends') IS NOT CASE
          WHEN strftime('%d',date(json_extract(NEW.after_json,'\$.starts'),'start of month','+2 months','-1 day'))<strftime('%d',json_extract(NEW.after_json,'\$.starts'))
          THEN date(json_extract(NEW.after_json,'\$.starts'),'start of month','+2 months','-1 day')
          ELSE date(json_extract(NEW.after_json,'\$.starts'),'+1 month') END
        OR EXISTS(SELECT 1 FROM membership_periods p WHERE p.person_id=NEW.person_id AND p.id<>NEW.period_id
          AND p.starts<json_extract(NEW.after_json,'\$.ends') AND p.ends>json_extract(NEW.after_json,'\$.starts')))
      THEN RAISE(ABORT,'Corrected membership dates must be one calendar month without overlaps') END;
      END''',
    'DROP TRIGGER membership_periods_no_update',
    '''CREATE TRIGGER membership_periods_no_update BEFORE UPDATE ON membership_periods
      WHEN NEW.id IS NOT OLD.id OR NEW.person_id IS NOT OLD.person_id OR NEW.sale_request_id IS NOT OLD.sale_request_id OR NEW.amount_minor IS NOT OLD.amount_minor
      OR NOT EXISTS(SELECT 1 FROM membership_corrections c WHERE c.period_id=OLD.id AND c.person_id=OLD.person_id
        AND c.rowid=(SELECT max(rowid) FROM membership_corrections WHERE period_id=OLD.id)
        AND json_extract(c.before_json,'\$.starts')=OLD.starts AND json_extract(c.before_json,'\$.ends')=OLD.ends
        AND json_extract(c.after_json,'\$.starts')=NEW.starts AND json_extract(c.after_json,'\$.ends')=NEW.ends)
      BEGIN SELECT RAISE(ABORT,'Period dates require an audited correction'); END''',
    'DROP TRIGGER debtors_identity_immutable',
    '''CREATE TRIGGER debtors_identity_immutable BEFORE UPDATE ON debtors
      WHEN NEW.id IS NOT OLD.id OR NEW.created_command_id IS NOT OLD.created_command_id OR NEW.created_at_utc IS NOT OLD.created_at_utc
      OR ((NEW.name IS NOT OLD.name OR NEW.name_key IS NOT OLD.name_key) AND NOT EXISTS(
        SELECT 1 FROM membership_corrections c WHERE c.person_id=OLD.id
        AND c.rowid=(SELECT max(rowid) FROM membership_corrections WHERE person_id=OLD.id)
        AND json_extract(c.before_json,'\$.name')=OLD.name AND json_extract(c.before_json,'\$.nameKey')=OLD.name_key
        AND json_extract(c.after_json,'\$.name')=NEW.name AND json_extract(c.after_json,'\$.nameKey')=NEW.name_key))
      BEGIN SELECT RAISE(ABORT,'Person identity is fixed; name changes require an audited correction'); END''',
  ];
}
