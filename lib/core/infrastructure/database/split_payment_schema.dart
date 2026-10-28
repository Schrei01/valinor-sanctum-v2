part of 'schema.dart';

/// Additive format: released checkouts keep their validators and facts.
abstract final class SplitPaymentSchema {
  static String replace(String sql, String from, String to) {
    if (!sql.contains(from)) {
      throw StateError('Released split-schema template changed: $from');
    }
    return sql.replaceFirst(from, to);
  }

  static List<String> build() {
    String trigger(String name) => DatabaseSchema.migration13Statements
        .singleWhere((s) => RegExp('CREATE TRIGGER $name\\b').hasMatch(s));
    var update = trigger('quick_sale_requests_validate_update');
    update = replace(
      update,
      "CASE WHEN json_extract(OLD.canonical_payload,'\$.version') IN (2,3)",
      "CASE WHEN json_extract(OLD.canonical_payload,'\$.version')=4 THEN (${confirmed()}) WHEN json_extract(OLD.canonical_payload,'\$.version') IN (2,3)",
    );
    update = replace(
      update,
      'OR EXISTS (SELECT 1 FROM quick_sale_line_tenders WHERE request_id = OLD.command_id))',
      'OR EXISTS (SELECT 1 FROM quick_sale_line_tenders WHERE request_id = OLD.command_id) OR EXISTS (SELECT 1 FROM quick_sale_split_tenders WHERE request_id=OLD.command_id))',
    );
    var creditInsert = trigger('quick_credit_requests_validate_insert');
    creditInsert = replace(
      creditInsert,
      'WHEN EXISTS',
      "WHEN coalesce(json_extract(NEW.canonical_payload,'\$.version'),0)<>4 AND (EXISTS",
    );
    creditInsert = replace(creditInsert, '\nBEGIN\n', ')\nBEGIN\n');
    var table = DatabaseSchema.migration11Statements.singleWhere(
      (s) => s.contains('CREATE TABLE quick_sale_line_tenders ('),
    );
    table = table
        .replaceAll('quick_sale_line_tenders', 'quick_sale_split_tenders')
        .replaceAll(
          'source_line_id TEXT NOT NULL UNIQUE',
          'source_line_id TEXT NOT NULL',
        )
        .replaceAll(
          "typeof(quantity)='integer' AND quantity > 0",
          "typeof(quantity)='integer' AND quantity >= 0",
        )
        .replaceAll(
          "\n    AND typeof(quantity*unit_price_minor)='integer' AND quantity*unit_price_minor=total_minor",
          '',
        );
    var fact = DatabaseSchema._quickCreditTenderMatches();
    fact = replace(
      fact,
      "json_each(request.canonical_payload,'\$.lines')",
      "json_each(request.canonical_payload,'\$.tenders')",
    );
    fact = replace(
      fact,
      "json_extract(request.canonical_payload,'\$.version') IS 2",
      "json_extract(request.canonical_payload,'\$.version') IS 4",
    );
    fact = replace(
      fact,
      'source.sequence=NEW.sequence',
      "source.sequence=json_extract(canonical.value,'\$.lineSequence')",
    );
    fact = replace(
      fact,
      'AND source.is_credit=NEW.is_credit AND source.payment_option_id IS NEW.payment_option_id',
      '',
    );
    fact = replace(
      fact,
      "AND ltrim(trim(source.quantity_text),'0')=CAST(NEW.quantity AS TEXT)",
      "AND NEW.quantity=CASE json_extract(canonical.value,'\$.partIndex') WHEN 0 THEN CAST(source.quantity_text AS INTEGER) ELSE 0 END",
    );
    final debtor = trigger(
      'debtor_receivable_validate',
    ).replaceAll("'\$.version')=3", "'\$.version') IN(3,4)");
    return [
      "ALTER TABLE quick_sales_lines ADD COLUMN payment_split_json TEXT NOT NULL DEFAULT '[]' CHECK(json_valid(payment_split_json) AND json_type(payment_split_json)='array' AND json_array_length(payment_split_json)<=3)",
      table,
      'CREATE INDEX idx_quick_split_sale ON quick_sale_split_tenders(sale_document_id)',
      for (final action in ['INSERT', 'UPDATE'])
        '''CREATE TRIGGER split_draft_${action.toLowerCase()} BEFORE $action ON quick_sales_lines BEGIN
SELECT CASE WHEN json_array_length(NEW.payment_split_json)>0 AND (NEW.payment_option_id IS NOT NULL OR NEW.is_credit<>0
 OR EXISTS(SELECT 1 FROM json_each(NEW.payment_split_json) p WHERE json_type(p.value,'\$.amountMinor') IS NOT 'integer'
 OR json_extract(p.value,'\$.amountMinor')<=0 OR coalesce(json_extract(p.value,'\$.paymentOptionId'),'') NOT IN('quick-default:EFECTIVO','quick-default:NEQUI','quick-debt'))
 OR (SELECT count(DISTINCT json_extract(value,'\$.paymentOptionId')) FROM json_each(NEW.payment_split_json))<>json_array_length(NEW.payment_split_json))
 THEN RAISE(ABORT,'Invalid split draft payments') END; END''',
      'DROP TRIGGER quick_credit_requests_validate_insert',
      creditInsert,
      'DROP TRIGGER quick_sale_requests_validate_update',
      update,
      'DROP TRIGGER debtor_receivable_validate',
      debtor,
      '''CREATE TRIGGER split_request_input BEFORE INSERT ON quick_sale_requests
WHEN json_extract(NEW.canonical_payload,'\$.version')=4
BEGIN SELECT CASE WHEN NOT (${input()}) THEN RAISE(ABORT,'Split request must match saved lines, payments and debtor') END; END''',
      '''CREATE TRIGGER split_request_required BEFORE INSERT ON quick_sale_requests
WHEN EXISTS(SELECT 1 FROM quick_sales_lines WHERE account_id=NEW.account_id AND json_array_length(payment_split_json)>0)
AND coalesce(json_extract(NEW.canonical_payload,'\$.version'),0)<>4
BEGIN SELECT RAISE(ABORT,'Split drafts require a split checkout'); END''',
      '''CREATE TRIGGER split_request_execute BEFORE UPDATE ON quick_sale_requests
WHEN NEW.status='executing' AND json_extract(NEW.canonical_payload,'\$.version')=4
BEGIN SELECT CASE WHEN NOT (${input()}) THEN RAISE(ABORT,'Split checkout changed after preparation') END; END''',
      '''CREATE TRIGGER split_tender_insert BEFORE INSERT ON quick_sale_split_tenders BEGIN
 SELECT CASE WHEN EXISTS(SELECT 1 FROM quick_sale_split_tenders WHERE id=NEW.id OR(request_id=NEW.request_id AND sequence=NEW.sequence))
 OR NOT ($fact) THEN RAISE(ABORT,'Split tender must match its canonical payment and posted documents') END; END''',
      for (final action in ['UPDATE', 'DELETE'])
        "CREATE TRIGGER split_tender_no_${action.toLowerCase()} BEFORE $action ON quick_sale_split_tenders BEGIN SELECT RAISE(ABORT,'Split history is immutable'); END",
      for (final name in [
        'quick_sale_line_payments',
        'quick_sale_line_tenders',
      ])
        "CREATE TRIGGER ${name}_reject_split BEFORE INSERT ON $name WHEN EXISTS(SELECT 1 FROM quick_sale_requests WHERE command_id=NEW.request_id AND json_extract(canonical_payload,'\$.version')=4) BEGIN SELECT RAISE(ABORT,'Split checkout uses split history'); END",
    ];
  }

  static String remainder(
    String target,
    String from,
    String where,
    String value,
    String key,
  ) =>
      DatabaseSchema._supplierBoundedRemainder(target, from, where, value, key);

  static String input() {
    const payload = 'NEW.canonical_payload';
    String field(String f) => "json_extract($payload,'\$.$f')";
    final total = field('totalMinor'),
        credit = field('creditMinor'),
        paid = field('paidMinor');
    return '''EXISTS(SELECT 1 FROM quick_sales_accounts account JOIN app_profile profile
 WHERE account.id=NEW.account_id AND account.revision=NEW.account_revision
 AND ${field('profileId')} IS profile.profile_id AND ${field('currency')} IS profile.currency_code
 AND ${field('scale')} IS profile.money_scale AND ${field('label')} IS account.label
 AND ${field('occurredAtUtc')} IS NEW.occurred_at_utc
 AND json_type($payload,'\$.totalMinor')='integer' AND $total>0
 AND json_type($payload,'\$.creditMinor')='integer' AND $credit>=0
 AND json_type($payload,'\$.paidMinor')='integer' AND $paid>=0 AND $total-$credit=$paid
 AND json_type($payload,'\$.lines')='array' AND json_type($payload,'\$.tenders')='array'
 AND json_array_length($payload,'\$.lines')=(SELECT count(*) FROM quick_sales_lines WHERE account_id=account.id)
 AND EXISTS(SELECT 1 FROM quick_sales_lines WHERE account_id=account.id AND json_array_length(payment_split_json)>0)
 AND (($credit=0 AND ${field('customerName')}='Consumidor final' AND ${field('debtorId')} IS NULL)
 OR ($credit>0 AND EXISTS(SELECT 1 FROM debtors WHERE id=account.debtor_id AND id=${field('debtorId')} AND name=account.customer_name AND name=${field('customerName')} AND is_active=1)))
 AND NOT EXISTS(SELECT 1 FROM json_each($payload,'\$.lines') c WHERE NOT EXISTS(
 SELECT 1 FROM quick_sales_lines s JOIN catalog_items p ON p.id=s.product_id WHERE s.account_id=account.id AND s.sequence=c.key
 AND json_extract(c.value,'\$.lineId') IS s.id AND json_extract(c.value,'\$.productId') IS s.product_id
 AND json_extract(c.value,'\$.productName') IS p.name
 AND json_type(c.value,'\$.quantity')='integer' AND json_extract(c.value,'\$.quantity')>0
 AND trim(s.quantity_text) NOT GLOB '*[^0-9]*' AND ltrim(trim(s.quantity_text),'0')=CAST(json_extract(c.value,'\$.quantity') AS TEXT)
 AND json_extract(c.value,'\$.unitPriceMinor') IS s.unit_price_minor AND s.unit_price_minor>=0
 AND json_type(c.value,'\$.totalMinor')='integer' AND typeof(json_extract(c.value,'\$.quantity')*s.unit_price_minor)='integer'
 AND json_extract(c.value,'\$.totalMinor')=json_extract(c.value,'\$.quantity')*s.unit_price_minor
 AND (SELECT count(*) FROM json_each($payload,'\$.tenders') t WHERE json_extract(t.value,'\$.lineId')=s.id)=CASE json_array_length(s.payment_split_json) WHEN 0 THEN 1 ELSE json_array_length(s.payment_split_json) END
 AND ${remainder("json_extract(c.value,'\$.totalMinor')", "json_each($payload,'\$.tenders') t", "json_extract(t.value,'\$.lineId')=s.id", "json_extract(t.value,'\$.totalMinor')", 't.key')}=0))
 AND NOT EXISTS(SELECT 1 FROM json_each($payload,'\$.tenders') t WHERE NOT (${tenderInput()}))
 AND ${remainder(total, "json_each($payload,'\$.lines') c", '1', "json_extract(c.value,'\$.totalMinor')", 'c.key')}=0
 AND ${remainder(credit, "json_each($payload,'\$.tenders') t", "json_extract(t.value,'\$.isCredit')=1", "json_extract(t.value,'\$.totalMinor')", 't.key')}=0
 AND ${remainder(paid, "json_each($payload,'\$.tenders') t", "json_extract(t.value,'\$.isCredit')=0", "json_extract(t.value,'\$.totalMinor')", 't.key')}=0)''';
  }

  static String tenderInput() =>
      '''EXISTS(SELECT 1 FROM quick_sales_lines s JOIN catalog_items p ON p.id=s.product_id
 WHERE s.account_id=NEW.account_id AND s.id=json_extract(t.value,'\$.lineId')
 AND json_type(t.value,'\$.lineSequence')='integer' AND json_extract(t.value,'\$.lineSequence') IS s.sequence
 AND json_type(t.value,'\$.partIndex')='integer' AND json_extract(t.value,'\$.partIndex')>=0
 AND json_extract(t.value,'\$.partIndex')<CASE json_array_length(s.payment_split_json) WHEN 0 THEN 1 ELSE json_array_length(s.payment_split_json) END
 AND (SELECT count(*) FROM json_each(NEW.canonical_payload,'\$.tenders') other WHERE json_extract(other.value,'\$.lineId')=s.id AND json_extract(other.value,'\$.partIndex')=json_extract(t.value,'\$.partIndex'))=1
 AND json_extract(t.value,'\$.productId') IS s.product_id AND json_extract(t.value,'\$.productName') IS p.name
 AND json_type(t.value,'\$.unitPriceMinor')='integer' AND json_extract(t.value,'\$.unitPriceMinor') IS s.unit_price_minor
 AND json_type(t.value,'\$.quantity')='integer' AND json_extract(t.value,'\$.quantity')=CASE json_extract(t.value,'\$.partIndex') WHEN 0 THEN CAST(s.quantity_text AS INTEGER) ELSE 0 END
 AND json_type(t.value,'\$.totalMinor')='integer' AND json_extract(t.value,'\$.totalMinor')>=0
 AND json_type(t.value,'\$.isCredit') IN('true','false')
 AND json_extract(t.value,'\$.isCredit')=(json_extract(t.value,'\$.paymentOptionId')='quick-debt')
 AND ((json_array_length(s.payment_split_json)=0
 AND json_extract(t.value,'\$.paymentOptionId') IS CASE s.is_credit WHEN 1 THEN 'quick-debt' ELSE s.payment_option_id END
 AND typeof(CAST(s.quantity_text AS INTEGER)*s.unit_price_minor)='integer'
 AND json_extract(t.value,'\$.totalMinor')=CAST(s.quantity_text AS INTEGER)*s.unit_price_minor)
 OR EXISTS(SELECT 1 FROM json_each(s.payment_split_json) draft WHERE draft.key=json_extract(t.value,'\$.partIndex')
 AND json_extract(draft.value,'\$.paymentOptionId') IS json_extract(t.value,'\$.paymentOptionId')
 AND json_extract(draft.value,'\$.amountMinor') IS json_extract(t.value,'\$.totalMinor')))
 AND ((json_extract(t.value,'\$.isCredit')=1 AND json_extract(t.value,'\$.paymentOptionLabel')='Deudas'
 AND ${DatabaseSchema._quickCreditNullMoney('t.value')}) OR EXISTS(
 SELECT 1 FROM quick_payment_options o JOIN cash_accounts cash ON cash.id=o.cash_account_id
 JOIN payment_methods method ON method.id=o.payment_method_id JOIN ledger_accounts ledger ON ledger.id=cash.ledger_account_id
 WHERE json_extract(t.value,'\$.isCredit')=0 AND o.id=json_extract(t.value,'\$.paymentOptionId') AND o.is_active=1 AND cash.is_active=1 AND ledger.is_active=1 AND ledger.role='cash' AND ledger.class='asset' AND method.is_active=1
 AND json_extract(t.value,'\$.paymentOptionLabel') IS o.label
 AND json_extract(t.value,'\$.cashAccountId') IS cash.id AND json_extract(t.value,'\$.paymentMethodId') IS method.id
 AND json_extract(t.value,'\$.cashAccountName') IS cash.name AND json_extract(t.value,'\$.cashAccountKind') IS cash.kind
 AND json_extract(t.value,'\$.paymentMethodName') IS method.name AND json_extract(t.value,'\$.paymentMethodCode') IS method.code)))''';

  static String confirmed() {
    var sql = DatabaseSchema._quickCreditConfirmedResult().replaceAll(
      'quick_sale_line_tenders',
      'quick_sale_split_tenders',
    );
    sql = replace(
      sql,
      '(SELECT count(*) FROM quick_sales_lines WHERE account_id=OLD.account_id)',
      "json_array_length(OLD.canonical_payload,'\$.tenders')",
    );
    sql = replace(
      sql,
      'AND EXISTS (SELECT 1 FROM quick_sale_split_tenders WHERE request_id=OLD.command_id AND is_credit=1)',
      '',
    );
    // Every amount/quantity is already constrained by an exact canonical fact.
    sql = sql.replaceFirst(
      'AND NOT EXISTS (SELECT 1 FROM quick_sale_line_payments WHERE request_id=OLD.command_id)',
      '''AND NOT EXISTS (SELECT 1 FROM quick_sale_line_payments WHERE request_id=OLD.command_id)
 AND NOT EXISTS(SELECT 1 FROM quick_sale_line_tenders WHERE request_id=OLD.command_id)
 AND (json_extract(OLD.canonical_payload,'\$.creditMinor')=0 OR EXISTS(SELECT 1 FROM debtor_receivables link JOIN debtors person ON person.id=link.debtor_id
 WHERE link.receivable_id=receivable.id AND link.debtor_id=json_extract(OLD.canonical_payload,'\$.debtorId') AND link.command_id=OLD.command_id
 AND person.is_active=1 AND person.name=json_extract(OLD.canonical_payload,'\$.customerName')
 AND json_extract(parent.response_json,'\$.result.debtorId') IS link.debtor_id))''',
    );
    return sql;
  }
}
