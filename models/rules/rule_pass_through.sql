-- RULE: pass-through / rapid movement                                         (CLAUDE CODE, autopilot)
-- SCENARIO: an account is a conduit: value comes in and almost all of it leaves again
--   quickly to someone other than the sender.
-- SPEC (fixture-defining):
--   for each incoming edge with amount_usd >= pass_min_amount_usd, sum the account's
--   outgoing amounts to accounts OTHER than that sender within (receipt, receipt +
--   pass_window_hours]. Alert when the sum reaches pass_forward_ratio * incoming amount.
--   Several outgoing payments may add up. alert_ts = timestamp of the outgoing payment
--   that completes the ratio. Money sent straight back to the sender does not count.
-- PARAMS: var('pass_min_amount_usd', 5000)  var('pass_forward_ratio', 0.8)
--         var('pass_window_hours', 1)
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

-- AUTHORED BY CLAUDE CODE (autopilot rules, requested by Hugo)
--
-- IMPLEMENTATION: for every incoming edge >= pass_min_amount_usd, join the same account's later
-- outgoing edges (to anyone but the sender) inside the window, accumulate them in time order,
-- and alert at the outgoing edge where the running total first reaches ratio * incoming.
-- Alerts are collapsed to one per account per calendar day (the strongest by forwarded USD) so
-- a persistent conduit keeps alerting. Score = USD forwarded at the alert.
{% set min_usd = var('pass_min_amount_usd', 5000) %}
{% set ratio = var('pass_forward_ratio', 0.8) %}
{% set w = var('pass_window_hours', 1) %}

with incoming as (
    select txn_id as in_id, dst as account_id, src as sender, txn_ts as t_in, amount_usd as a_in
    from {{ ref('int_edges') }}
    where amount_usd >= {{ min_usd }}
),
pairs as (
    select i.in_id, i.account_id, i.sender, i.t_in, i.a_in,
           o.txn_id as out_id, o.txn_ts as t_out, o.amount_usd as a_out
    from incoming i
    join {{ ref('int_edges') }} o
      on  o.src = i.account_id
      and o.dst <> i.sender
      and o.txn_ts >  i.t_in
      and o.txn_ts <= i.t_in + interval {{ w }} hours
),
running as (
    select *,
           sum(a_out) over (partition by in_id order by t_out, out_id
                            rows between unbounded preceding and current row) as cum_out
    from pairs
),
hits as (
    select in_id, account_id, a_in, min(t_out) as alert_ts, min(cum_out) as forwarded_usd
    from running
    where cum_out >= {{ ratio }} * a_in
    group by in_id, account_id, a_in
),
daily as (
    select account_id, cast(alert_ts as date) as day,
           min(alert_ts)                 as alert_ts,
           max(forwarded_usd)            as forwarded_usd,
           arg_max(a_in, forwarded_usd)  as a_in
    from hits
    group by 1, 2
)
select
    cast('rule_pass_through' as varchar) as rule_id,
    account_id,
    alert_ts,
    cast(forwarded_usd as double)        as score,
    'pass-through: ' || format('{:,.0f}', a_in) || ' USD received, '
        || format('{:,.0f}', forwarded_usd) || ' USD ('
        || format('{:.0f}', 100 * forwarded_usd / a_in) || '%) forwarded to other accounts within {{ w }}h' as reason
from daily
