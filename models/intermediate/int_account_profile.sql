{# One row per account in the accounts table, including accounts with no
   transactions. is_laundering_account is the LABEL (account is an endpoint of
   at least one laundering transaction, self-transfers included): it must
   never be used as a feature. Degrees count distinct counterparties among
   non-self flows. #}
with endpoints as (
    select from_account_id as account_id, txn_id, txn_ts, is_laundering, is_self_transfer from {{ ref('int_txn_enriched') }}
    union all
    select to_account_id,                 txn_id, txn_ts, is_laundering, is_self_transfer
    from {{ ref('int_txn_enriched') }} where not is_self_transfer
),
activity as (
    select
        account_id,
        min(txn_ts) as first_txn_ts,
        max(txn_ts) as last_txn_ts,
        count(distinct cast(txn_ts as date)) as active_days,
        sum(is_self_transfer::int) as n_self_transfers,
        sum(is_laundering) as n_laundering_txns
    from endpoints
    group by 1
),
out_flow as (
    select src as account_id, count(*) as n_sent, sum(amount_usd) as sent_usd, count(distinct dst) as out_degree
    from {{ ref('int_edges') }} group by 1
),
in_flow as (
    select dst as account_id, count(*) as n_recv, sum(amount_usd) as recv_usd, count(distinct src) as in_degree
    from {{ ref('int_edges') }} group by 1
)
select
    a.account_id,
    a.bank_id,
    a.bank_country,
    a.entity_id,
    a.entity_type,
    act.first_txn_ts,
    act.last_txn_ts,
    coalesce(act.active_days, 0)        as active_days,
    coalesce(o.n_sent, 0)               as n_sent,
    coalesce(o.sent_usd, 0)             as sent_usd,
    coalesce(o.out_degree, 0)           as out_degree,
    coalesce(i.n_recv, 0)               as n_recv,
    coalesce(i.recv_usd, 0)             as recv_usd,
    coalesce(i.in_degree, 0)            as in_degree,
    coalesce(act.n_self_transfers, 0)   as n_self_transfers,
    coalesce(act.n_laundering_txns, 0)  as n_laundering_txns,
    coalesce(act.n_laundering_txns, 0) > 0 as is_laundering_account
from {{ ref('stg_accounts') }} a
left join activity act using (account_id)
left join out_flow o using (account_id)
left join in_flow i using (account_id)
