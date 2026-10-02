-- RULE: fan-in / fan-out                                                     (CLAUDE CODE, autopilot)
-- SCENARIO: many different accounts pay one account in a short time (fan-in), or one
--   account pays many different accounts in a short time (fan-out). Classic collection
--   and distribution behaviour.
-- SPEC (fixture-defining):
--   fan-in : alert an account that receives from >= fan_min_counterparties DISTINCT
--            source accounts within any fan_window_hours window.
--   fan-out: same, on sends to DISTINCT destination accounts.
--   alert_ts = timestamp of the transaction that first completes the threshold.
--   An account can alert on both sides (two rows). Self-transfers are not in int_edges.
-- PARAMS: var('fan_min_counterparties', 6)  var('fan_window_hours', 6)
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

-- AUTHORED BY CLAUDE CODE (autopilot rules, requested by Hugo)
--
-- IMPLEMENTATION: a trailing RANGE window per account over its time-ordered edges.
--   n_cp   = distinct counterparties in (ts - window, ts]   (peers with the same ts included)
--   usd    = total amount in the same window
-- An account alerts the first time n_cp >= fan_min_counterparties. Score is the peak
-- n_cp over the account's history; the reason quotes that peak window's numbers.
-- Accounts whose lifetime distinct-counterparty count is below the threshold can never
-- alert, so they are filtered out first; that keeps the window scan cheap.
{% set k = var('fan_min_counterparties', 6) %}
{% set w = var('fan_window_hours', 6) %}

with in_cand as (
    select dst as account_id from {{ ref('int_edges') }}
    group by 1 having count(distinct src) >= {{ k }}
),
out_cand as (
    select src as account_id from {{ ref('int_edges') }}
    group by 1 having count(distinct dst) >= {{ k }}
),
sides as (
    select 'in' as side, dst as account_id, src as counterparty, txn_ts, amount_usd
    from {{ ref('int_edges') }} where dst in (select account_id from in_cand)
    union all
    select 'out', src, dst, txn_ts, amount_usd
    from {{ ref('int_edges') }} where src in (select account_id from out_cand)
),
windows as (
    select
        side, account_id, txn_ts,
        count(distinct counterparty) over w as n_cp,
        sum(amount_usd) over w              as usd
    from sides
    window w as (
        partition by side, account_id order by txn_ts
        range between interval {{ w }} hours preceding and current row
    )
),
flagged as (
    select * from windows where n_cp >= {{ k }}
),
agg as (
    select
        side, account_id,
        min(txn_ts) as first_ts,
        max(n_cp)   as peak_n,
        arg_max(usd, n_cp) as peak_usd
    from flagged
    group by side, account_id
)
select
    cast('rule_fan_in_out' as varchar) as rule_id,
    account_id,
    first_ts                           as alert_ts,
    cast(peak_n as double)             as score,
    case side when 'in' then 'fan-in: ' || peak_n || ' distinct senders within {{ w }}h'
              else 'fan-out: ' || peak_n || ' distinct receivers within {{ w }}h' end
        || ', ' || format('{:,.0f}', peak_usd) || ' USD in that window' as reason
from agg
