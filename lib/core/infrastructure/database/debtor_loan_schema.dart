import 'investment_schema.dart';

/// v22: owner-funded loans are receivables, never sales or cash withdrawals.
abstract final class DebtorLoanSchema {
  static List<String> build(List<String> released) {
    String object(String name) => released.lastWhere(
      (s) => RegExp('^CREATE (TABLE|TRIGGER|VIEW) $name\\b').hasMatch(s),
    );
    String replace(String sql, String before, String after) {
      if (!sql.contains(before)) {
        throw StateError('Missing loan anchor: $before');
      }
      return sql.replaceFirst(before, after);
    }

    final requests = replace(
      object('debtor_requests'),
      "kind IN('create','opening','payment','assign')",
      "kind IN('create','opening','payment','assign','loan')",
    );
    var links = replace(
      object('debtor_receivables'),
      "source IN('sale','opening','historical')",
      "source IN('sale','opening','historical','loan')",
    );
    links = replace(
      links,
      'CHECK((sales_receivable_id',
      'loan_document_id TEXT UNIQUE REFERENCES debtor_loans(document_id) ON DELETE RESTRICT,\n CHECK((sales_receivable_id',
    );
    links = replace(
      links,
      "CHECK((sales_receivable_id IS NOT NULL AND sales_receivable_id=receivable_id AND opening_document_id IS NULL AND source IN('sale','historical'))\n OR(sales_receivable_id IS NULL AND opening_document_id IS NOT NULL AND source='opening'))",
      "CHECK((sales_receivable_id IS NOT NULL AND sales_receivable_id=receivable_id AND opening_document_id IS NULL AND loan_document_id IS NULL AND source IN('sale','historical'))\n OR(sales_receivable_id IS NULL AND opening_document_id IS NOT NULL AND loan_document_id IS NULL AND source='opening')\n OR(sales_receivable_id IS NULL AND opening_document_id IS NULL AND loan_document_id IS NOT NULL AND source='loan'))",
    );
    final attached = <String, String>{};
    for (final sql in released) {
      final match = RegExp(
        r'^CREATE TRIGGER (\w+)\b.*\bON (debtor_requests|debtor_receivables)\b',
        dotAll: true,
      ).firstMatch(sql);
      if (match != null) attached[match.group(1)!] = sql;
    }
    attached['debtor_requests_update'] = replace(
      attached['debtor_requests_update']!,
      "SELECT CASE WHEN NEW.status='confirmed' AND NEW.kind='assign'",
      "SELECT CASE WHEN NEW.status='confirmed' AND NEW.kind='loan' AND NOT EXISTS(SELECT 1 FROM debtor_loans loan JOIN business_documents d ON d.id=loan.document_id AND d.status='posted' JOIN journal_entries e ON e.document_id=d.id AND e.status='posted' WHERE d.command_id=NEW.command_id AND loan.debtor_id=json_extract(NEW.canonical_payload,'\$.debtorId')) THEN RAISE(ABORT,'Post the exact owner-funded loan before confirming') END;\n SELECT CASE WHEN NEW.status='confirmed' AND NEW.kind='assign'",
    );
    attached['debtor_receivable_validate'] = replace(
      attached['debtor_receivable_validate']!,
      "(NEW.source='sale'",
      "(NEW.source='loan' AND EXISTS(SELECT 1 FROM debtor_loans loan JOIN business_documents d ON d.id=loan.document_id JOIN debtor_requests r ON r.command_id=d.command_id WHERE loan.document_id=NEW.loan_document_id AND loan.debtor_id=NEW.debtor_id AND d.command_id=NEW.command_id AND d.status='draft' AND r.kind='loan' AND r.status='executing' AND NEW.receivable_id=json_extract(r.canonical_payload,'\$.receivableId')))\n OR(NEW.source='sale'",
    );
    final freezes = released
        .where((s) => s.startsWith('CREATE TRIGGER debtor_journal_'))
        .map(
          (s) => s.replaceAll(
            "IN('debtor_opening','debtor_collection')",
            "IN('debtor_opening','debtor_collection','debtor_loan')",
          ),
        );
    return [
      '''CREATE TABLE debtor_loans(
 document_id TEXT PRIMARY KEY NOT NULL REFERENCES business_documents(id) ON DELETE RESTRICT,
 debtor_id TEXT NOT NULL REFERENCES debtors(id) ON DELETE RESTRICT,
 name_snapshot TEXT NOT NULL,
 amount_minor INTEGER NOT NULL CHECK(typeof(amount_minor)='integer' AND amount_minor>0),
 control_account_id TEXT NOT NULL REFERENCES ledger_accounts(id) ON DELETE RESTRICT,
 funding_account_id TEXT NOT NULL REFERENCES ledger_accounts(id) ON DELETE RESTRICT
)''',
      'CREATE INDEX idx_debtor_loans_person ON debtor_loans(debtor_id)',
      'PRAGMA defer_foreign_keys=ON',
      requests.replaceFirst(
        'CREATE TABLE debtor_requests(',
        'CREATE TABLE debtor_requests_v22_buffer(',
      ),
      'INSERT INTO debtor_requests_v22_buffer SELECT * FROM debtor_requests',
      'DROP TABLE debtor_requests',
      requests,
      'INSERT INTO debtor_requests SELECT * FROM debtor_requests_v22_buffer',
      'DROP TABLE debtor_requests_v22_buffer',
      links.replaceFirst(
        'CREATE TABLE debtor_receivables(',
        'CREATE TABLE debtor_receivables_v22_buffer(',
      ),
      'INSERT INTO debtor_receivables_v22_buffer SELECT *,NULL FROM debtor_receivables',
      'DROP TABLE debtor_receivables',
      links,
      'INSERT INTO debtor_receivables SELECT * FROM debtor_receivables_v22_buffer',
      'DROP TABLE debtor_receivables_v22_buffer',
      'CREATE INDEX idx_debtor_receivables_person ON debtor_receivables(debtor_id)',
      ...attached.values,
      'DROP VIEW all_customer_receivables',
      '''${object('all_customer_receivables')}
 UNION ALL SELECT link.receivable_id,loan.document_id,loan.name_snapshot,loan.control_account_id,loan.amount_minor,document.occurred_at_utc,document.business_date
 FROM debtor_loans loan JOIN debtor_receivables link ON link.loan_document_id=loan.document_id
 JOIN business_documents document ON document.id=loan.document_id''',
      'DROP VIEW debtor_expected_journal',
      '''${object('debtor_expected_journal')}
 UNION ALL SELECT document_id,control_account_id,amount_minor,0 FROM debtor_loans
 UNION ALL SELECT document_id,funding_account_id,0,amount_minor FROM debtor_loans''',
      'DROP TRIGGER debtor_document_draft',
      object('debtor_document_draft').replaceAll(
        "IN('debtor_opening','debtor_collection')",
        "IN('debtor_opening','debtor_collection','debtor_loan')",
      ),
      for (final sql in freezes) ...[
        'DROP TRIGGER ${RegExp(r"^CREATE TRIGGER (\w+)").firstMatch(sql)!.group(1)}',
        sql,
      ],
      '''CREATE TRIGGER debtor_loans_insert BEFORE INSERT ON debtor_loans BEGIN
 SELECT CASE WHEN EXISTS(SELECT 1 FROM debtor_loans WHERE document_id=NEW.document_id)
 OR NOT EXISTS(SELECT 1 FROM business_documents WHERE id=NEW.document_id AND status='draft' AND type='debtor_loan')
 THEN RAISE(ABORT,'A loan requires a unique draft loan document') END; END''',
      for (final action in ['UPDATE', 'DELETE'])
        "CREATE TRIGGER debtor_loans_no_${action.toLowerCase()} BEFORE $action ON debtor_loans BEGIN SELECT RAISE(ABORT,'Posted loan facts are immutable'); END",
      _posting.replaceAll(
        'INVESTMENT_BALANCE',
        InvestmentSchema.balanceSql(
          "'investment:owner-payable'",
          creditNormal: true,
        ),
      ),
    ];
  }

  static const _posting =
      r'''CREATE TRIGGER debtor_loan_posting BEFORE UPDATE OF status ON business_documents
 WHEN NEW.status='posted' AND (NEW.type='debtor_loan' OR EXISTS(SELECT 1 FROM debtor_loans WHERE document_id=NEW.id)) BEGIN
 SELECT CASE WHEN OLD.status<>'draft' OR NEW.type<>'debtor_loan' OR NEW.command_sequence<>0
 OR date(NEW.occurred_at_utc,'-5 hours') IS NOT NEW.business_date OR NEW.date_quality<>'documented'
 OR NOT EXISTS(SELECT 1 FROM debtor_loans loan
 JOIN debtors person ON person.id=loan.debtor_id AND person.is_active=1
 JOIN debtor_receivables link ON link.loan_document_id=loan.document_id AND link.source='loan' AND link.debtor_id=loan.debtor_id
 JOIN debtor_requests request ON request.command_id=NEW.command_id AND request.kind='loan' AND request.status='executing'
 JOIN command_log command ON command.id=request.command_id AND command.command_type='debtor_operation' AND command.actor_id=NEW.actor_id
 JOIN actors actor ON actor.id=NEW.actor_id AND actor.is_active=1
 JOIN app_profile profile ON profile.profile_id=NEW.profile_id AND profile.business_timezone='America/Bogota'
 JOIN ledger_accounts control ON control.id=loan.control_account_id AND control.id='system:customer-receivable' AND control.class='asset' AND control.role='customer_receivable' AND control.is_active=1
 JOIN ledger_accounts funding ON funding.id=loan.funding_account_id AND funding.id='investment:owner-payable' AND funding.class='liability' AND funding.role='owner_payable' AND funding.is_active=1
 WHERE loan.document_id=NEW.id AND link.command_id=NEW.command_id
 AND loan.debtor_id=json_extract(request.canonical_payload,'$.debtorId')
 AND loan.name_snapshot=person.name AND loan.name_snapshot=json_extract(request.canonical_payload,'$.nameSnapshot')
 AND loan.amount_minor=json_extract(request.canonical_payload,'$.amountMinor')
 AND json_extract(request.canonical_payload,'$.paymentOptionId')='investment'
 AND link.receivable_id=json_extract(request.canonical_payload,'$.receivableId')
 AND json_extract(request.canonical_payload,'$.profileId')=profile.profile_id
 AND json_extract(request.canonical_payload,'$.currency')=profile.currency_code AND json_extract(request.canonical_payload,'$.scale')=profile.money_scale
 AND json_extract(request.canonical_payload,'$.occurredAtUtc')=NEW.occurred_at_utc
 AND command.authorization_policy_version='development-single-user-v1'
 AND json_extract(command.response_json,'$.canonicalPayload')=request.canonical_payload
 AND json_extract(command.response_json,'$.result.documentId')=NEW.id)
 THEN RAISE(ABORT,'Loan requires its exact person, investment and executing request') END;
 SELECT CASE WHEN EXISTS(SELECT 1 FROM journal_lines line JOIN journal_entries entry ON entry.id=line.entry_id AND entry.status='posted'
 JOIN business_documents previous ON previous.id=entry.document_id AND previous.status='posted'
 WHERE line.account_id IN('investment:owner-payable','system:customer-receivable') AND julianday(previous.occurred_at_utc)>julianday(NEW.occurred_at_utc))
 THEN RAISE(ABORT,'Loan cannot precede a later investment or receivable movement') END;
 SELECT CASE WHEN (SELECT count(*) FROM journal_lines line JOIN journal_entries entry ON entry.id=line.entry_id WHERE entry.document_id=NEW.id)<>2
 OR NOT EXISTS(SELECT 1 FROM journal_entries WHERE document_id=NEW.id AND status='draft' AND cost_completeness='not_applicable' AND reversal_of_id IS NULL)
 OR EXISTS(SELECT 1 FROM debtor_expected_journal expected WHERE expected.document_id=NEW.id AND NOT EXISTS(SELECT 1 FROM journal_lines line JOIN journal_entries entry ON entry.id=line.entry_id WHERE entry.document_id=NEW.id AND line.account_id=expected.account_id AND line.debit_minor=expected.debit_minor AND line.credit_minor=expected.credit_minor))
 THEN RAISE(ABORT,'Loan requires exactly receivable debit and investment credit') END;
 SELECT CASE WHEN INVESTMENT_BALANCE IS NULL OR INVESTMENT_BALANCE > 9223372036854775807-(SELECT amount_minor FROM debtor_loans WHERE document_id=NEW.id)
 OR (SELECT coalesce(sum(remaining_minor),0) FROM customer_receivable_balances)+(SELECT coalesce(sum(line.debit_minor-line.credit_minor),0) FROM journal_lines line JOIN journal_entries e ON e.id=line.entry_id AND e.status='posted' JOIN business_documents d ON d.id=e.document_id AND d.status='posted' WHERE line.account_id='system:legacy-customer-receivables') > 9223372036854775807-(SELECT amount_minor FROM debtor_loans WHERE document_id=NEW.id)
 THEN RAISE(ABORT,'Loan exceeds investment or receivable capacity') END;
 END''';
}
