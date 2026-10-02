-- Independent derivation straight from staging: for every split, the labelled
-- account set must equal the endpoints of laundering transactions dated inside
-- that split's window. Any label leaking from another window shows up here.
with splits as ({{ eval_splits() }}),
txn_day as (
    select from_account_id, to_account_id, is_laundering,
           datediff('day', (select min(txn_date) from {{ ref('stg_transactions') }}), txn_date) + 1 as day_index
    from {{ ref('stg_transactions') }}
),
expected as (
    select s.split, e.account_id
    from splits s
    join (
        select from_account_id as account_id, day_index from txn_day where is_laundering = 1
        union all
        select to_account_id, day_index from txn_day where is_laundering = 1
    ) e on e.day_index between s.day_from and s.day_to
    group by 1, 2
),
actual as (
    select split, account_id from {{ ref('fct_account_split_label') }} where is_laundering_account
)
select 'missing' as problem, split, account_id from (select * from expected except select * from actual)
union all
select 'extra', split, account_id from (select * from actual except select * from expected)
