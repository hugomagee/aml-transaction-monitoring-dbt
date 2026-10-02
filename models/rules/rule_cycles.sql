-- RULE: cycles                                                                (CLAUDE CODE, autopilot)
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
-- PARAMS: var('cycle_min_hops', 3) [added by implementation: a 2-hop A->B->A is a return,
--         not a cycle; the fixture has no 2-cycles so it is unaffected]
--         var('cycle_max_hops', 6)  var('cycle_min_amount_usd', 500)
--         var('cycle_window_hours', 168)  var('cycle_max_degree', 50)
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

-- AUTHORED BY CLAUDE CODE (autopilot rules, requested by Hugo)
--
-- IMPLEMENTATION: recursive walk over the filtered edge set. A walk starts at every edge and
-- extends with edges that leave the current node, are STRICTLY later than the previous edge,
-- start within cycle_window_hours of the first edge, and do not revisit a node. It closes when
-- an edge returns to the start node. Because time must strictly increase around the loop, each
-- cycle is found exactly once (from its earliest edge).
-- Edge set: amount >= cycle_min_amount_usd, both ends within the degree cap, and both ends
-- having an in-edge and an out-edge in the set (nothing else can sit on a cycle).
-- Every account on a closed cycle alerts at the closing edge's time, once per account per
-- calendar day. Score = bottleneck (smallest edge) USD on the cycle.
-- CAVEAT: degrees in int_account_profile are computed over the whole window, so the hub cap uses
-- some look-ahead (hub status, not labels). Noted in the README limitations.
{% set min_hops = var('cycle_min_hops', 3) %}
{% set max_hops = var('cycle_max_hops', 6) %}
{% set min_usd = var('cycle_min_amount_usd', 500) %}
{% set w = var('cycle_window_hours', 168) %}
{% set cap = var('cycle_max_degree', 50) %}

with recursive hubs as (
    select account_id from {{ ref('int_account_profile') }}
    where out_degree > {{ cap }} or in_degree > {{ cap }}
),
e0 as (
    select txn_id, src, dst, txn_ts, amount_usd
    from {{ ref('int_edges') }}
    where amount_usd >= {{ min_usd }}
      and src not in (select account_id from hubs)
      and dst not in (select account_id from hubs)
),
e as (
    select * from e0
    where src in (select dst from e0) and dst in (select src from e0)
),
walk as (
    select src as start_node, dst as cur, txn_ts as first_ts, txn_ts as last_ts,
           1 as hops, [src, dst] as path, amount_usd as min_amt, false as closed
    from e
    union all
    select w.start_node, x.dst, w.first_ts, x.txn_ts, w.hops + 1,
           case when x.dst = w.start_node then w.path else list_append(w.path, x.dst) end,
           least(w.min_amt, x.amount_usd),
           x.dst = w.start_node
    from walk w
    join e x
      on  x.src = w.cur
      and x.txn_ts >  w.last_ts
      and x.txn_ts <= w.first_ts + interval {{ w }} hours
    where not w.closed
      and w.hops < {{ max_hops }}
      and (x.dst = w.start_node or not list_contains(w.path, x.dst))
),
cycles as (
    select row_number() over () as cycle_id, path, hops, last_ts as closed_ts, min_amt
    from walk
    where closed and hops >= {{ min_hops }}
),
members as (
    select cycle_id, unnest(path) as account_id, hops, closed_ts, min_amt, len(path) as n_accounts
    from cycles
),
daily as (
    select account_id, cast(closed_ts as date) as day,
           min(closed_ts)          as alert_ts,
           max(min_amt)            as bottleneck_usd,
           arg_max(hops, min_amt)  as hops,
           count(*)                as n_cycles
    from members
    group by 1, 2
)
select
    cast('rule_cycles' as varchar) as rule_id,
    account_id,
    alert_ts,
    cast(bottleneck_usd as double) as score,
    'cycle: ' || hops || '-hop loop back to the same account within {{ w }}h, smallest leg '
        || format('{:,.0f}', bottleneck_usd) || ' USD (' || n_cycles || ' cycle(s) that day)' as reason
from daily
