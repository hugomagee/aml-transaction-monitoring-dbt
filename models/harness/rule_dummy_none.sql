-- Harness-proving dummy: alert nobody. Expect recall 0 and undefined precision.
select
    cast('rule_dummy_none' as varchar)  as rule_id,
    cast(null as varchar)               as account_id,
    cast(null as timestamp)             as alert_ts,
    cast(null as double)                as score,
    cast(null as varchar)               as reason
where false
