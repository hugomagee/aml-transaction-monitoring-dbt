{# Combined alert set for headline metrics: fan-in/out, structuring, pass-through, cycles.
   rule_baseline_anomaly is excluded (does not transfer across days). One row per account per
   day any of these rules alerted; score = number of distinct rules that fired that account-day
   (rule scores are on different scales, so they are not compared directly). #}
select
    'combined_excl_baseline'                         as rule_id,
    account_id,
    min(alert_ts)                                    as alert_ts,
    cast(count(distinct rule_id) as double)          as score,
    'combined: ' || string_agg(distinct rule_id, ', ' order by rule_id) as reason
from {{ ref('fct_alerts') }}
where rule_id in ({% for r in headline_rules() %}'{{ r }}'{% if not loop.last %}, {% endif %}{% endfor %})
group by account_id, cast(alert_ts as date)
