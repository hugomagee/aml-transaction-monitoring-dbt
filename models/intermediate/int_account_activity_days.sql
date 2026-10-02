{# One row per account and day with any transaction as sender or receiver,
   self-transfers included (counted once). Defines the evaluation population
   for a time split: an account is "in" a split if it was active in it. #}
with ends as (
    select from_account_id as account_id, txn_date, day_index, is_laundering from {{ ref('int_txn_enriched') }}
    union all
    select to_account_id,                 txn_date, day_index, is_laundering
    from {{ ref('int_txn_enriched') }} where not is_self_transfer
)
select
    account_id,
    txn_date as day,
    day_index,
    count(*) as n_txns,
    sum(is_laundering) as n_laundering_txns
from ends
group by 1, 2, 3
