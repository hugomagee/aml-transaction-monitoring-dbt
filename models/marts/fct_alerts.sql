{# Union of every wired rule (see macros/wired_rules.sql). Contract per row:
   rule_id, account_id, alert_ts, score, reason. #}
{% for r in wired_rules() %}
select rule_id, account_id, alert_ts, score, reason from {{ ref(r) }}
{% if not loop.last %}union all{% endif %}
{% endfor %}
