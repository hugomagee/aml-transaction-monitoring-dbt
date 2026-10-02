{% for t in eval_targets() %}
select * from ({{ rule_pattern_recall(t[0], t[1]) }})
{% if not loop.last %}union all{% endif %}
{% endfor %}
