-- RULE: pass-through / rapid movement                                         (HUGO)
-- SCENARIO: an account is a conduit: value comes in and almost all of it leaves again
--   quickly to someone other than the sender.
-- SPEC (fixture-defining):
--   for each incoming edge with amount_usd >= pass_min_amount_usd, sum the account's
--   outgoing amounts to accounts OTHER than that sender within (receipt, receipt +
--   pass_window_hours]. Alert when the sum reaches pass_forward_ratio * incoming amount.
--   Several outgoing payments may add up. alert_ts = timestamp of the outgoing payment
--   that completes the ratio. Money sent straight back to the sender does not count.
-- PARAMS: var('pass_min_amount_usd', 1000)  var('pass_forward_ratio', 0.9)
--         var('pass_window_hours', 24)
-- INPUTS: ref('int_edges')
-- DO NOT use is_laundering: it is the label.
-- OUTPUT CONTRACT (every rule): rule_id, account_id, alert_ts, score, reason
--   rule_id    varchar    the model name
--   account_id varchar    "<bank>|<account>", must exist in dim_account
--   alert_ts   timestamp  when the condition first became true (not the end of the data)
--   score      double     higher = more suspicious; used for precision@k and threshold sensitivity
--   reason     varchar    human-readable, non-empty, with the numbers behind the alert
--                         e.g. "fan-in: 6 distinct senders within 24h, 31,200 USD total"
-- Thresholds come from var() so the fixture can pin them; tune the defaults, not the fixture.

-- STUB: returns no rows. Replace the select below with your implementation.
-- Run the fixture:  make test-rule RULE=rule_pass_through
-- Run on data:      make eval RULE=rule_pass_through   (runs the fixture first)
select
    cast('rule_pass_through' as varchar)  as rule_id,
    cast(null as varchar)  as account_id,
    cast(null as timestamp) as alert_ts,
    cast(null as double)   as score,
    cast(null as varchar)  as reason
where false
