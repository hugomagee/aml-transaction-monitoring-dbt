-- RULE: baseline anomaly                                                     (HUGO)
-- (first to cut if time runs short)
-- SCENARIO: an account's activity on one day is far outside its own history.
-- SPEC (fixture-defining):
--   daily total = sent_usd + recv_usd from int_account_daily. Alert on a day when the
--   total >= baseline_ratio * the MEDIAN of the account's earlier daily totals, the total
--   is >= baseline_min_usd, and the account has >= baseline_min_history_days earlier days.
--   Only the first such day per account needs to alert in the fixture. alert_ts =
--   cast(day as timestamp). Score = total / median.
-- PARAMS: var('baseline_ratio', 5)  var('baseline_min_history_days', 3)
--         var('baseline_min_usd', 5000)
-- INPUTS: ref('int_account_daily')  ref('int_account_profile')
-- DO NOT use is_laundering or n_laundering_txns: they are labels.
-- OUTPUT CONTRACT (every rule): rule_id, account_id, alert_ts, score, reason
--   rule_id    varchar    the model name
--   account_id varchar    "<bank>|<account>", must exist in dim_account
--   alert_ts   timestamp  when the condition first became true (not the end of the data)
--   score      double     higher = more suspicious; used for precision@k and threshold sensitivity
--   reason     varchar    human-readable, non-empty, with the numbers behind the alert
--                         e.g. "fan-in: 6 distinct senders within 24h, 31,200 USD total"
-- Thresholds come from var() so the fixture can pin them; tune the defaults, not the fixture.

-- STUB: returns no rows. Replace the select below with your implementation.
-- Run the fixture:  make test-rule RULE=rule_baseline_anomaly
-- Run on data:      make eval RULE=rule_baseline_anomaly   (runs the fixture first)
select
    cast('rule_baseline_anomaly' as varchar)  as rule_id,
    cast(null as varchar)  as account_id,
    cast(null as timestamp) as alert_ts,
    cast(null as double)   as score,
    cast(null as varchar)  as reason
where false
