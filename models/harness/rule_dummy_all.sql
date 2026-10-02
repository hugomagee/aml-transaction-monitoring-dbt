-- Harness-proving dummy: alert every account on every day it has activity.
-- Expect recall 1.0 and precision equal to the base rate of labelled accounts.
select
    'rule_dummy_all'                                      as rule_id,
    account_id,
    cast(day as timestamp)                                as alert_ts,
    cast(1.0 as double)                                   as score,
    'dummy: alert every active account (harness check)'   as reason
from {{ ref('int_account_activity_days') }}
