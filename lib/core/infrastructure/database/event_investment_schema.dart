import 'investment_schema.dart';

/// Preserve the complete event graph while allowing a non-cash funding source.
abstract final class EventInvestmentSchema {
  static List<String> build(List<String> released) {
    String replace(String source, String old, String next) {
      if (!source.contains(old)) {
        throw StateError('Missing event investment anchor: $old');
      }
      return source.replaceFirst(old, next);
    }

    String table(String name) =>
        released.singleWhere((s) => s.startsWith('CREATE TABLE $name ('));
    var header = table('events');
    header = replace(
      header,
      ' CHECK(typeof(fixed_cost_minor+products_cost_minor)',
      " funding_mode TEXT NOT NULL DEFAULT 'cash' CHECK(funding_mode IN('cash','investment')),\n CHECK(typeof(fixed_cost_minor+products_cost_minor)",
    );
    header = replace(
      header,
      ''' CHECK((fixed_cost_minor=0 AND source_account_id IS NULL AND source_account_name_snapshot IS NULL) OR
   (fixed_cost_minor>0 AND source_account_id IS NOT NULL AND source_account_name_snapshot IS NOT NULL AND minimum_people>0)),''',
      ''' CHECK((fixed_cost_minor=0 AND source_account_id IS NULL AND source_account_name_snapshot IS NULL AND funding_mode='cash') OR
   (fixed_cost_minor>0 AND minimum_people>0 AND ((funding_mode='cash' AND source_account_id IS NOT NULL AND source_account_name_snapshot IS NOT NULL)
     OR (funding_mode='investment' AND source_account_id IS NULL AND source_account_name_snapshot='Inversión')))),''',
    );
    var posting = released.singleWhere(
      (s) => s.startsWith('CREATE TRIGGER events_posting '),
    );
    posting = replace(
      posting,
      "json_extract(request.canonical_payload,'\$.sourceAccountId') IS event.source_account_id",
      "json_extract(request.canonical_payload,'\$.sourceAccountId') IS CASE WHEN event.funding_mode='investment' THEN 'investment' ELSE event.source_account_id END",
    );
    posting = replace(
      posting,
      'WHERE event.document_id=NEW.id AND event.fixed_cost_minor>0 AND NOT EXISTS(',
      "WHERE event.document_id=NEW.id AND event.funding_mode='cash' AND event.fixed_cost_minor>0 AND NOT EXISTS(",
    );
    final graph = {
      'events': header,
      'event_products': table('event_products'),
      'event_cost_allocations': table('event_cost_allocations'),
    };
    const order = ['events', 'event_products', 'event_cost_allocations'];
    String buffer(String sql) {
      for (final name in order) {
        sql = sql
            .replaceAll(
              'CREATE TABLE $name (',
              'CREATE TABLE ${name}_v20_buffer (',
            )
            .replaceAll('REFERENCES $name(', 'REFERENCES ${name}_v20_buffer(');
      }
      return sql;
    }

    final triggers = released
        .where(
          (s) => RegExp(
            r'^CREATE TRIGGER \w+ .*\bON (events|event_products|event_cost_allocations)\b',
            dotAll: true,
          ).hasMatch(s),
        )
        .toList();
    return [
      for (final name in order) buffer(graph[name]!),
      "INSERT INTO events_v20_buffer SELECT *, 'cash' FROM events",
      'INSERT INTO event_products_v20_buffer SELECT * FROM event_products',
      'INSERT INTO event_cost_allocations_v20_buffer SELECT * FROM event_cost_allocations',
      for (final sql in triggers)
        'DROP TRIGGER ${RegExp(r'^CREATE TRIGGER (\w+)').firstMatch(sql)!.group(1)}',
      for (final name in order.reversed) 'DROP TABLE $name',
      for (final name in order) ...[
        graph[name]!,
        'INSERT INTO $name SELECT * FROM ${name}_v20_buffer',
      ],
      for (final name in order.reversed) 'DROP TABLE ${name}_v20_buffer',
      ...released.where((s) => s.startsWith('CREATE INDEX idx_event_')),
      ...triggers,
      'DROP TRIGGER events_posting',
      posting,
      'DROP VIEW event_expected_journal',
      '''CREATE VIEW event_expected_journal AS
 SELECT document_id,'events:costs' AS account_id,total_cost_minor AS debit_minor,0 AS credit_minor FROM events WHERE total_cost_minor>0
 UNION ALL SELECT document_id,'system:inventory',0,products_cost_minor FROM events WHERE products_cost_minor>0
 UNION ALL SELECT event.document_id,cash.ledger_account_id,0,event.fixed_cost_minor FROM events event
 JOIN cash_accounts cash ON cash.id=event.source_account_id WHERE event.fixed_cost_minor>0 AND event.funding_mode='cash'
 UNION ALL SELECT document_id,'investment:owner-payable',0,fixed_cost_minor FROM events WHERE fixed_cost_minor>0 AND funding_mode='investment' ''',
      '''CREATE TRIGGER event_investment_posting BEFORE UPDATE OF status ON business_documents
 WHEN NEW.status='posted' AND EXISTS(SELECT 1 FROM events WHERE document_id=NEW.id AND funding_mode='investment') BEGIN
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM ledger_accounts WHERE id='investment:owner-payable' AND class='liability' AND role='owner_payable' AND is_active=1)
 OR EXISTS(SELECT 1 FROM events ev WHERE ev.document_id=NEW.id AND (
   ${InvestmentSchema.balanceQuery("'investment:owner-payable'", creditNormal: true)} IS NULL
   OR ${InvestmentSchema.balanceQuery("'investment:owner-payable'", creditNormal: true)}>9223372036854775807-ev.fixed_cost_minor))
 OR EXISTS(SELECT 1 FROM journal_lines l JOIN journal_entries e ON e.id=l.entry_id AND e.status='posted'
 JOIN business_documents d ON d.id=e.document_id AND d.status='posted' WHERE l.account_id='investment:owner-payable' AND julianday(d.occurred_at_utc)>julianday(NEW.occurred_at_utc))
 THEN RAISE(ABORT,'Event investment requires a valid owner liability, bounded balance and chronological posting') END;
 END''',
    ];
  }
}
