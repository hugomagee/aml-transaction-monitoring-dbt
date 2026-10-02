{# Point-in-time account features for the ML comparison, one row per (split, account) for the
   splits `tune` and `validate` (not `all`).
   POINT-IN-TIME: every f_* column is computed ONLY from transactions inside that split's own day
   window, with the same SQL for both splits, so nothing looks at a later split or at the whole
   window. Deliberately NOT used: int_account_profile's whole-window degrees, the pattern-file
   tags, and anything derived from is_laundering except the label column itself.
   rf_* columns are alert counts / max scores of the five rules inside the same window (kept
   apart so the base-feature model can ignore them). `label` = is_laundering_account of
   fct_account_split_label (laundering endpoint inside the window). Never use `label` as input. #}
{% set rules = real_rules() %}
with splits as (
    {{ eval_splits() }}
),
maxday as (select max(day_index) as m, min(day) as d0 from {{ ref('int_account_activity_days') }}),
w as (
    select split, day_from, least(day_to, (select m from maxday)) as day_to,
           least(day_to, (select m from maxday)) - day_from + 1 as n_days
    from splits where split <> 'all'
),
t as (
    select w.split, w.n_days, e.*
    from w join {{ ref('int_txn_enriched') }} e on e.day_index between w.day_from and w.day_to
),
sent as (
    select split, from_account_id as account_id,
           count(*) as n_sent, sum(amount_usd) as sent_usd, count(distinct to_account_id) as out_degree,
           max(amount_usd) as max_sent_usd, avg(amount_usd) as avg_sent_usd,
           count(distinct payment_currency) as n_currencies,
           sum((format_risk_weight >= 2)::int) as risky_sent, sum(is_cross_currency::int) as cross_sent
    from t where not is_self_transfer group by 1, 2
),
recv as (
    select split, to_account_id as account_id,
           count(*) as n_recv, sum(amount_usd) as recv_usd, count(distinct from_account_id) as in_degree,
           max(amount_usd) as max_recv_usd, avg(amount_usd) as avg_recv_usd,
           sum((format_risk_weight >= 2)::int) as risky_recv, sum(is_cross_currency::int) as cross_recv
    from t where not is_self_transfer group by 1, 2
),
selft as (
    select split, from_account_id as account_id, count(*) as n_self from t where is_self_transfer group by 1, 2
),
act as (
    select w.split, a.account_id, count(*) as active_days, max(a.n_txns) as max_txns_day,
           min(a.day_index) - w.day_from as first_day_offset
    from w join {{ ref('int_account_activity_days') }} a on a.day_index between w.day_from and w.day_to
    group by w.split, a.account_id, w.day_from
),
cp as (
    select w.split, d.account_id,
           max(d.sent_distinct_counterparties) as max_sent_cp_day, max(d.recv_distinct_counterparties) as max_recv_cp_day
    from w join {{ ref('int_account_daily') }} d
      on datediff('day', (select d0 from maxday), d.day) + 1 between w.day_from and w.day_to
    group by 1, 2
),
rules as (
    select w.split, a.account_id,
    {% for r in rules %}
           count(*) filter (where a.rule_id = '{{ r }}')            as rf_{{ r }}_n,
           max(a.score) filter (where a.rule_id = '{{ r }}')        as rf_{{ r }}_max{{ ',' if not loop.last }}
    {% endfor %}
    from w join {{ ref('fct_alerts') }} a
      on datediff('day', (select d0 from maxday), cast(a.alert_ts as date)) + 1 between w.day_from and w.day_to
    where a.rule_id in ({% for r in rules %}'{{ r }}'{{ ', ' if not loop.last }}{% endfor %})
    group by 1, 2
)
select
    l.split,
    l.account_id,
    l.is_laundering_account                                         as label,
    d.entity_type, d.bank_country,
    coalesce(s.n_sent, 0)                                           as f_n_sent,
    coalesce(r.n_recv, 0)                                           as f_n_recv,
    coalesce(s.sent_usd, 0)                                         as f_sent_usd,
    coalesce(r.recv_usd, 0)                                         as f_recv_usd,
    coalesce(s.out_degree, 0)                                       as f_out_degree,
    coalesce(r.in_degree, 0)                                        as f_in_degree,
    coalesce(s.max_sent_usd, 0)                                     as f_max_sent_usd,
    coalesce(r.max_recv_usd, 0)                                     as f_max_recv_usd,
    coalesce(s.avg_sent_usd, 0)                                     as f_avg_sent_usd,
    coalesce(r.avg_recv_usd, 0)                                     as f_avg_recv_usd,
    coalesce(sf.n_self, 0)                                          as f_n_self,
    coalesce(s.n_currencies, 0)                                     as f_n_currencies,
    (coalesce(s.sent_usd, 0) + 1) / (coalesce(r.recv_usd, 0) + 1)   as f_sent_recv_ratio,
    (coalesce(s.risky_sent, 0) + coalesce(r.risky_recv, 0))::double
        / nullif(coalesce(s.n_sent, 0) + coalesce(r.n_recv, 0), 0)  as f_frac_risky_format,
    (coalesce(s.cross_sent, 0) + coalesce(r.cross_recv, 0))::double
        / nullif(coalesce(s.n_sent, 0) + coalesce(r.n_recv, 0), 0)  as f_frac_cross_currency,
    coalesce(a.active_days, 0)                                      as f_active_days,
    coalesce(a.max_txns_day, 0)                                     as f_max_txns_day,
    a.first_day_offset::double / w.n_days                           as f_first_day_frac,
    coalesce(cp.max_sent_cp_day, 0)                                 as f_max_sent_cp_day,
    coalesce(cp.max_recv_cp_day, 0)                                 as f_max_recv_cp_day,
    coalesce(s.n_sent, 0)::double / w.n_days                        as f_n_sent_per_day,
    coalesce(r.n_recv, 0)::double / w.n_days                        as f_n_recv_per_day,
    coalesce(s.sent_usd, 0) / w.n_days                              as f_sent_usd_per_day,
    coalesce(r.recv_usd, 0) / w.n_days                              as f_recv_usd_per_day,
    {% for r in rules %}
    coalesce(ru.rf_{{ r }}_n, 0)                                    as rf_{{ r }}_n,
    coalesce(ru.rf_{{ r }}_max, 0)                                  as rf_{{ r }}_max{{ ',' if not loop.last }}
    {% endfor %}
from {{ ref('fct_account_split_label') }} l
join w on w.split = l.split
join {{ ref('dim_account') }} d on d.account_id = l.account_id
left join sent s  on s.split = l.split and s.account_id = l.account_id
left join recv r  on r.split = l.split and r.account_id = l.account_id
left join selft sf on sf.split = l.split and sf.account_id = l.account_id
left join act a   on a.split = l.split and a.account_id = l.account_id
left join cp      on cp.split = l.split and cp.account_id = l.account_id
left join rules ru on ru.split = l.split and ru.account_id = l.account_id
where l.split <> 'all'
