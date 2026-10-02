-- RULE: cycles                                                                (HUGO)
-- SCENARIO: money leaves an account, passes through others, and returns to it.
-- SPEC (fixture-defining) - every bound below exists for a reason; document it:
--   a cycle is a path of time-ordered edges (each edge STRICTLY later than the previous)
--   that returns to the start account, with:
--     <= cycle_max_hops edges          (recursion depth / cost)
--     every edge >= cycle_min_amount_usd  (ignore dust)
--     last edge - first edge <= cycle_window_hours  (stale loops are not laundering)
--     no account with out_degree or in_degree > cycle_max_degree  (hubs explode the search)
--   Alert every account on a qualifying cycle. alert_ts = timestamp of the closing edge
--   (earliest across the account's cycles). Suggested implementation: recursive CTE.
-- PARAMS: var('cycle_max_hops', 5)  var('cycle_min_amount_usd', 1000)
--         var('cycle_window_hours', 72)  var('cycle_max_degree', 50)
-- INPUTS: ref('int_edges')  ref('int_account_profile')  (out_degree, in_degree)
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
-- Run the fixture:  make test-rule RULE=rule_cycles
-- Run on data:      make eval RULE=rule_cycles   (runs the fixture first)
select
    cast('rule_cycles' as varchar)  as rule_id,
    cast(null as varchar)  as account_id,
    cast(null as timestamp) as alert_ts,
    cast(null as double)   as score,
    cast(null as varchar)  as reason
where false
