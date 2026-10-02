{# Rules whose alerts feed fct_alerts and the fct_rule_* evaluation marts.
   The five rules (autopilot, Claude Code) are wired in; the dummies prove the harness. #}
{% macro wired_rules() %}{{ return(['rule_dummy_all', 'rule_dummy_none', 'rule_fan_in_out', 'rule_structuring', 'rule_pass_through', 'rule_cycles', 'rule_baseline_anomaly']) }}{% endmacro %}

{# The real rules, and the subset used for headline combined metrics. rule_baseline_anomaly is
   kept in every per-rule table but left out of the headline set: its alert rate does not
   transfer across days (8.2 per 1,000 accounts on tune vs 84 on validate; cold-start baseline). #}
{% macro real_rules() %}{{ return(['rule_fan_in_out', 'rule_structuring', 'rule_pass_through', 'rule_cycles', 'rule_baseline_anomaly']) }}{% endmacro %}
{% macro headline_rules() %}{{ return(['rule_fan_in_out', 'rule_structuring', 'rule_pass_through', 'rule_cycles']) }}{% endmacro %}

{# (relation, rule_id) pairs evaluated by fct_rule_performance, fct_rule_pattern_recall and
   fct_rule_threshold_sensitivity: every wired rule plus the two combined alert sets. #}
{% macro eval_targets() %}
    {%- set t = [] -%}
    {%- for r in wired_rules() -%}{%- do t.append([ref(r), r]) -%}{%- endfor -%}
    {%- do t.append([ref('fct_alerts_combined_headline'), 'combined_excl_baseline']) -%}
    {%- do t.append([ref('fct_alerts_combined_all'), 'combined_incl_baseline']) -%}
    {{ return(t) }}
{% endmacro %}
