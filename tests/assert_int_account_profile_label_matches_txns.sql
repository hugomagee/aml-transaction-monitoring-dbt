-- Account label = endpoint of >=1 laundering transaction. Re-derive it from
-- staging and require identical sets.
with expected as (
    select from_account_id as account_id from {{ ref('stg_transactions') }} where is_laundering = 1
    union
    select to_account_id from {{ ref('stg_transactions') }} where is_laundering = 1
),
actual as (select account_id from {{ ref('int_account_profile') }} where is_laundering_account)
select 'missing' as problem, account_id from (select * from expected except select * from actual)
union all
select 'extra', account_id from (select * from actual except select * from expected)
