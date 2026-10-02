{# Per-split account labels. Within a split an account is labelled only if it
   is an endpoint of a laundering transaction dated inside that split's day
   window, so a tune-split label can never depend on a later transaction.
   Rows exist only for accounts active in the split (the evaluation population).
   dim_account.is_laundering_account stays as the whole-window label. #}
with splits as ({{ eval_splits() }})
select
    s.split,
    a.account_id,
    sum(a.n_txns)              as n_txns,
    sum(a.n_laundering_txns)   as n_laundering_txns,
    sum(a.n_laundering_txns) > 0 as is_laundering_account
from splits s
join {{ ref('int_account_activity_days') }} a
    on a.day_index between s.day_from and s.day_to
group by 1, 2
