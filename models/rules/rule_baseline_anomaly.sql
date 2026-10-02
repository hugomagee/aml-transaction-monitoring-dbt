-- RULE: baseline anomaly                                                     (CLAUDE CODE, autopilot)
-- (first to cut if time runs short)
-- SCENARIO: an account's activity on one day is far outside its own history.
-- SPEC (fixture-defining):
--   daily total = sent_usd + recv_usd from int_account_daily. Alert on a day when the
--   total >= baseline_ratio * the MEDIAN of the account's earlier daily totals, the total
--   is >= baseline_min_usd, and the account has >= baseline_min_history_days earlier days.
--   Only the first such day per account needs to alert in the fixture. alert_ts =
--   cast(day as timestamp). Score = total / median.
-- PARAMS: var('baseline_ratio', 3)  var('baseline_min_history_days', 2)
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

-- AUTHORED BY CLAUDE CODE (autopilot rules, requested by Hugo)
--
-- IMPLEMENTATION: per account, the median of daily totals over its EARLIER active days is the
-- baseline (rows exist only for days with activity, so inactive days are not zeros). A day
-- alerts when total >= ratio * baseline, total >= min USD, and >= min_history earlier days.
-- Every qualifying day alerts (a persistent change keeps alerting). Score = total / baseline.
-- Only earlier days feed the baseline, so nothing here looks ahead.
{% set ratio = var('baseline_ratio', 3) %}
{% set hist = var('baseline_min_history_days', 2) %}
{% set min_usd = var('baseline_min_usd', 5000) %}

with daily as (
    select account_id, day, sent_usd + recv_usd as total_usd
    from {{ ref('int_account_daily') }}
),
with_baseline as (
    select
        account_id, day, total_usd,
        count(*) over prev                      as n_hist,
        quantile_cont(total_usd, 0.5) over prev as baseline_usd
    from daily
    window prev as (
        partition by account_id order by day
        rows between unbounded preceding and 1 preceding
    )
)
select
    cast('rule_baseline_anomaly' as varchar) as rule_id,
    account_id,
    cast(day as timestamp)                   as alert_ts,
    cast(total_usd / baseline_usd as double) as score,
    'baseline anomaly: ' || format('{:,.0f}', total_usd) || ' USD moved in a day, '
        || format('{:.1f}', total_usd / baseline_usd) || 'x the median of its '
        || n_hist || ' earlier active days (' || format('{:,.0f}', baseline_usd) || ' USD)' as reason
from with_baseline
where n_hist >= {{ hist }}
  and total_usd >= {{ min_usd }}
  and baseline_usd > 0
  and total_usd >= {{ ratio }} * baseline_usd
