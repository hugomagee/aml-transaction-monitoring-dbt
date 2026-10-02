-- RULE: fan-in / fan-out                                                     (HUGO)
-- SCENARIO: many different accounts pay one account in a short time (fan-in), or one
--   account pays many different accounts in a short time (fan-out). Classic collection
--   and distribution behaviour.
-- SPEC (fixture-defining):
--   fan-in : alert an account that receives from >= fan_min_counterparties DISTINCT
--            source accounts within any fan_window_hours window.
--   fan-out: same, on sends to DISTINCT destination accounts.
--   alert_ts = timestamp of the transaction that first completes the threshold.
--   An account can alert on both sides (two rows). Self-transfers are not in int_edges.
-- PARAMS: var('fan_min_counterparties', 5)  var('fan_window_hours', 24)
-- INPUTS: ref('int_edges')  (txn_id, txn_ts, src, dst, amount_usd, is_laundering)
--         ref('int_account_daily') is also available for a cheaper daily variant.
-- DO NOT use is_laundering or pattern_type: they are labels.
-- OUTPUT CONTRACT (every rule): rule_id, account_id, alert_ts, score, reason
--   rule_id    varchar    the model name
--   account_id varchar    "<bank>|<account>", must exist in dim_account
--   alert_ts   timestamp  when the condition first became true (not the end of the data)
--   score      double     higher = more suspicious; used for precision@k and threshold sensitivity
--   reason     varchar    human-readable, non-empty, with the numbers behind the alert
--                         e.g. "fan-in: 6 distinct senders within 24h, 31,200 USD total"
-- Thresholds come from var() so the fixture can pin them; tune the defaults, not the fixture.

-- STUB: returns no rows. Replace the select below with your implementation.
-- Run the fixture:  make test-rule RULE=rule_fan_in_out
-- Run on data:      make eval RULE=rule_fan_in_out   (runs the fixture first)
select
    cast('rule_fan_in_out' as varchar)  as rule_id,
    cast(null as varchar)  as account_id,
    cast(null as timestamp) as alert_ts,
    cast(null as double)   as score,
    cast(null as varchar)  as reason
where false
