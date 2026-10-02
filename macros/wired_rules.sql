{# Rules whose alerts feed fct_alerts and the fct_rule_* evaluation marts.
   Hugo's five rules are added here when each is wired in (build step 6). #}
{% macro wired_rules() %}{{ return(['rule_dummy_all', 'rule_dummy_none']) }}{% endmacro %}
