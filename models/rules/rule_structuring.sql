-- RULE: structuring                                                          (CLAUDE CODE, autopilot)
-- SCENARIO: a sender splits value into several payments just under a reporting
--   threshold to avoid attention.
-- SPEC (fixture-defining):
--   alert a sender with >= structuring_min_txns payments whose amount_usd lies in
--   [threshold*(1-band), threshold) within any structuring_window_hours window.
--   Self-transfers are ignored. alert_ts = timestamp of the payment that completes
--   the count. Score = number of in-band payments in the window.
-- PARAMS: var('structuring_threshold_usd', 10000)  var('structuring_band_pct', 0.30)
--         var('structuring_min_txns', 4)           var('structuring_window_hours', 72)
--   structuring_min_txns must be >= 3 (enforced below): a 2-payment pattern is not structuring.
--   Defaults tuned on the TUNE split only (days 1-7): grid band {5,10,20,30}% x min_txns {3,4,5}
--   x window {24,72,168}h; pick = highest account recall with <= 10 alerts per 1,000 accounts.
--   A 30% band is 7,000-10,000 USD: that is "below the threshold", not "just below" it.
--   The fixture pins its own values (band 10%, min_txns 3) and is unaffected.
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

-- AUTHORED BY CLAUDE CODE (autopilot rules, requested by Hugo)
--
-- IMPLEMENTATION: keep non-self payments with amount_usd in [threshold*(1-band), threshold),
-- then a trailing RANGE window per sender counts them. First time the count reaches
-- structuring_min_txns is the alert, once per account per calendar day it holds; score is
-- that day's peak count; the reason quotes the peak window.
{% set thr = var('structuring_threshold_usd', 10000) %}
{% set band = var('structuring_band_pct', 0.30) %}
{% set n = var('structuring_min_txns', 4) %}
{% set w = var('structuring_window_hours', 72) %}
{% if n < 3 %}{{ exceptions.raise_compiler_error('structuring_min_txns must be >= 3: a 2-payment pattern is not structuring') }}{% endif %}

with in_band as (
    select txn_id, txn_ts, from_account_id, amount_usd
    from {{ ref('int_txn_enriched') }}
    where not is_self_transfer
      and amount_usd >= {{ thr }} * (1 - {{ band }})
      and amount_usd <  {{ thr }}
),
windows as (
    select
        from_account_id, txn_ts,
        count(*)        over w as n_txns,
        sum(amount_usd) over w as usd
    from in_band
    window w as (
        partition by from_account_id order by txn_ts
        range between interval {{ w }} hours preceding and current row
    )
),
agg as (
    -- one alert per account per calendar day on which the condition holds: a persistent
    -- offender keeps alerting, so every time split sees it (not only the first day)
    select
        from_account_id as account_id,
        min(txn_ts)          as first_ts,
        max(n_txns)          as peak_n,
        arg_max(usd, n_txns) as peak_usd
    from windows
    where n_txns >= {{ n }}
    group by from_account_id, cast(txn_ts as date)
)
select
    cast('rule_structuring' as varchar) as rule_id,
    account_id,
    first_ts                            as alert_ts,
    cast(peak_n as double)              as score,
    'structuring: ' || peak_n || ' payments of ' || format('{:,.0f}', cast({{ thr * (1 - band) }} as double))
        || '-' || format('{:,.0f}', cast({{ thr }} as double)) || ' USD within {{ w }}h, '
        || format('{:,.0f}', peak_usd) || ' USD total' as reason
from agg
