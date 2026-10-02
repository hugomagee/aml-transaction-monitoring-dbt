{% for r in wired_rules() %}
select * from ({{ rule_threshold_sensitivity(ref(r), r) }})
{% if not loop.last %}union all{% endif %}
{% endfor %}
