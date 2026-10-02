{# Transactions and patterns zero-pad bank ids ('010'); the accounts file does not ('10'). #}
{% macro bank_id(col) %}cast(cast({{ col }} as bigint) as varchar){% endmacro %}
