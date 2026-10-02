{# Rules whose alerts feed fct_alerts and the fct_rule_* evaluation marts.
   The five rules (autopilot, Claude Code) are added here as each is finished. #}
{% macro wired_rules() %}{{ return(['rule_dummy_all', 'rule_dummy_none', 'rule_fan_in_out', 'rule_structuring', 'rule_pass_through']) }}{% endmacro %}
