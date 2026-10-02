{# Same as fct_alerts_combined_headline but INCLUDING rule_baseline_anomaly, for the
   with/without comparison. #}
select
    'combined_incl_baseline'                         as rule_id,
    account_id,
    min(alert_ts)                                    as alert_ts,
    cast(count(distinct rule_id) as double)          as score,
    'combined: ' || string_agg(distinct rule_id, ', ' order by rule_id) as reason
from {{ ref('fct_alerts') }}
where rule_id in ({% for r in real_rules() %}'{{ r }}'{% if not loop.last %}, {% endif %}{% endfor %})
group by account_id, cast(alert_ts as date)
