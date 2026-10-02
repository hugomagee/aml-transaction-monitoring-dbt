{% for r in wired_rules() %}
select * from ({{ rule_pattern_recall(ref(r), r) }})
{% if not loop.last %}union all{% endif %}
{% endfor %}
