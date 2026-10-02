{#
  Evaluation harness. One definition of every metric, used both by the marts
  (fct_rule_*) and by `make eval RULE=<name>` (via dbt show --inline).

  Unit: account. For a time split (day_index range):
    population       accounts with >=1 transaction in the range
    labelled account population account with >=1 laundering transaction in the range
    alerted account  population account with >=1 alert row dated in the range
  splits: all; tune = days 1..tune_last_day; validate = the rest
  (--vars '{tune_last_day: N}', default 7, set in dbt_project.yml).
#}
{% macro rule_eval_base(alerts) %}
splits as (
    select 'all' as split, 1 as day_from, 100000 as day_to
    union all select 'tune', 1, {{ var('tune_last_day') }}
    union all select 'validate', {{ var('tune_last_day') }} + 1, 100000
),
window_start as (select min(day) as d0 from {{ ref('int_account_activity_days') }}),
pop as (
    select s.split, a.account_id, sum(a.n_laundering_txns) as n_lab
    from splits s
    join {{ ref('int_account_activity_days') }} a on a.day_index between s.day_from and s.day_to
    group by 1, 2
),
alert_rows as (
    select account_id, score,
           datediff('day', (select d0 from window_start), cast(alert_ts as date)) + 1 as day_index
    from {{ alerts }}
),
acct_alert as (
    select s.split, r.account_id, max(r.score) as score, (p.n_lab > 0) as is_lab
    from alert_rows r
    join splits s on r.day_index between s.day_from and s.day_to
    join pop p on p.split = s.split and p.account_id = r.account_id
    group by s.split, r.account_id, p.n_lab
),
laundering_txns as (
    select s.split, t.txn_id, t.from_account_id, t.to_account_id, t.pattern_type
    from splits s
    join {{ ref('fct_transactions') }} t on t.is_laundering = 1 and t.day_index between s.day_from and s.day_to
),
txn_hit as (
    select l.split, l.txn_id, l.pattern_type,
           (a1.account_id is not null or a2.account_id is not null) as hit
    from laundering_txns l
    left join acct_alert a1 on a1.split = l.split and a1.account_id = l.from_account_id
    left join acct_alert a2 on a2.split = l.split and a2.account_id = l.to_account_id
)
{% endmacro %}

{% macro rule_performance(alerts, rule_id) %}
with {{ rule_eval_base(alerts) }},
pop_agg as (
    select split, count(*) as n_population, sum((n_lab > 0)::int) as n_labelled_accounts from pop group by 1
),
rows_agg as (
    select s.split, count(*) as n_alert_rows
    from alert_rows r join splits s on r.day_index between s.day_from and s.day_to group by 1
),
ranked as (
    select split, is_lab, row_number() over (partition by split order by score desc, account_id) as rk
    from acct_alert
),
alert_agg as (
    select split, count(*) as n_alerted_accounts, sum(is_lab::int) as tp_accounts,
           sum(is_lab::int) filter (where rk <= 100)  as lab_in_top100,
           sum(is_lab::int) filter (where rk <= 1000) as lab_in_top1000
    from ranked
    group by 1
),
txn_agg as (
    select split, count(*) as n_laundering_txns, sum(hit::int) as n_laundering_txns_caught from txn_hit group by 1
)
select
    '{{ rule_id }}'                                                         as rule_id,
    s.split,
    p.n_population,
    p.n_labelled_accounts,
    coalesce(r.n_alert_rows, 0)                                             as n_alert_rows,
    coalesce(a.n_alerted_accounts, 0)                                       as n_alerted_accounts,
    coalesce(a.tp_accounts, 0)                                              as tp_accounts,
    a.tp_accounts::double / nullif(a.n_alerted_accounts, 0)                 as precision,
    coalesce(a.tp_accounts, 0)::double / nullif(p.n_labelled_accounts, 0)   as account_recall,
    coalesce(a.n_alerted_accounts, 0) * 1000.0 / p.n_population             as alerts_per_1000_accounts,
    t.n_laundering_txns,
    coalesce(t.n_laundering_txns_caught, 0)::double / nullif(t.n_laundering_txns, 0) as txn_recall,
    case when a.n_alerted_accounts >= 100  then a.lab_in_top100  / 100.0  end as precision_at_100,
    case when a.n_alerted_accounts >= 1000 then a.lab_in_top1000 / 1000.0 end as precision_at_1000
from splits s
join pop_agg p using (split)
left join rows_agg r using (split)
left join alert_agg a using (split)
left join txn_agg t using (split)
order by case s.split when 'all' then 0 when 'tune' then 1 else 2 end
{% endmacro %}

{% macro rule_pattern_recall(alerts, rule_id) %}
with {{ rule_eval_base(alerts) }}
select
    '{{ rule_id }}' as rule_id,
    split,
    coalesce(pattern_type, 'UNTAGGED') as pattern_type,
    count(*) as n_laundering_txns,
    sum(hit::int) as n_caught,
    sum(hit::int)::double / count(*) as txn_recall
from txn_hit
group by 1, 2, 3
order by 2, 3
{% endmacro %}

{% macro rule_threshold_sensitivity(alerts, rule_id) %}
{# Raise the score cutoff through the percentiles of the rule's own account
   scores (split = all) and watch precision, recall and alert volume. #}
with {{ rule_eval_base(alerts) }},
all_alerts as (select * from acct_alert where split = 'all'),
cutoffs as (
    {% for p in [0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 0.99] %}
    select {{ p }} as cutoff_pct, quantile_disc(score, {{ p }}) as score_cutoff from all_alerts
    {% if not loop.last %}union all{% endif %}
    {% endfor %}
),
base as (
    select (select count(*) from pop where split = 'all') as n_pop,
           (select count(*) from pop where split = 'all' and n_lab > 0) as n_lab_acc
)
select
    '{{ rule_id }}' as rule_id,
    c.cutoff_pct,
    c.score_cutoff,
    count(*) as n_alerted_accounts,
    sum(a.is_lab::int) as tp_accounts,
    sum(a.is_lab::int)::double / count(*) as precision,
    sum(a.is_lab::int)::double / any_value(b.n_lab_acc) as account_recall,
    count(*) * 1000.0 / any_value(b.n_pop) as alerts_per_1000_accounts
from cutoffs c
join all_alerts a on a.score >= c.score_cutoff
cross join base b
group by 1, 2, 3
order by 2
{% endmacro %}
