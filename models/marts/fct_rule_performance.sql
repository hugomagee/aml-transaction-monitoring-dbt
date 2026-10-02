{% for r in wired_rules() %}
select * from ({{ rule_performance(ref(r), r) }})
{% if not loop.last %}union all{% endif %}
{% endfor %}
