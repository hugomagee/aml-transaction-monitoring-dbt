{# Resolve a raw table for the dataset selected by --vars '{dataset: li}' (default hi). #}
{% macro raw_ref(name) %}{{ source('raw', var('dataset', 'hi') ~ '_' ~ name) }}{% endmacro %}
