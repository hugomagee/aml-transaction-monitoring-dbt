{# Directed, time-stamped money movements between two different accounts.
   Self-transfers are excluded: they are not movement and would create
   trivial one-hop cycles. Cycle detection starts from this table. #}
select
    txn_id,
    txn_ts,
    from_account_id as src,
    to_account_id   as dst,
    amount_usd,
    is_laundering
from {{ ref('int_txn_enriched') }}
where not is_self_transfer
