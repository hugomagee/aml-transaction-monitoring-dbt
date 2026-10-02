-- RULE: structuring                                                          (HUGO)
-- SCENARIO: a sender splits value into several payments just under a reporting
--   threshold to avoid attention.
-- SPEC (fixture-defining):
--   alert a sender with >= structuring_min_txns payments whose amount_usd lies in
--   [threshold*(1-band), threshold) within any structuring_window_hours window.
--   Self-transfers are ignored. alert_ts = timestamp of the payment that completes
--   the count. Score = number of in-band payments in the window.
-- PARAMS: var('structuring_threshold_usd', 10000)  var('structuring_band_pct', 0.10)
--         var('structuring_min_txns', 3)           var('structuring_window_hours', 72)
-- NOTE: amount_usd uses static approximate FX (seeds/fx_rates_approx.csv); the band is
--   only as good as that approximation. Say so in the README.
-- INPUTS: ref('int_txn_enriched')  (txn_id, txn_ts, from_account_id, to_account_id,
--         amount_usd, payment_format, format_risk_weight, is_self_transfer, ...)
-- DO NOT use is_laundering, pattern_id or pattern_type: they are labels.
-- OUTPUT CONTRACT (every rule): rule_id, account_id, alert_ts, score, reason
--   rule_id    varchar    the model name
--   account_id varchar    "<bank>|<account>", must exist in dim_account
--   alert_ts   timestamp  when the condition first became true (not the end of the data)
--   score      double     higher = more suspicious; used for precision@k and threshold sensitivity
--   reason     varchar    human-readable, non-empty, with the numbers behind the alert
--                         e.g. "fan-in: 6 distinct senders within 24h, 31,200 USD total"
-- Thresholds come from var() so the fixture can pin them; tune the defaults, not the fixture.

-- STUB: returns no rows. Replace the select below with your implementation.
-- Run the fixture:  make test-rule RULE=rule_structuring
-- Run on data:      make eval RULE=rule_structuring   (runs the fixture first)
select
    cast('rule_structuring' as varchar)  as rule_id,
    cast(null as varchar)  as account_id,
    cast(null as timestamp) as alert_ts,
    cast(null as double)   as score,
    cast(null as varchar)  as reason
where false
