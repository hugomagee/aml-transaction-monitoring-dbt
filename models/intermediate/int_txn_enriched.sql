{# Adds USD amounts (static approximate FX), the prior format risk weight and,
   for diagnosis only, the Patterns.txt tag. The pattern key is unique, so the
   left join cannot fan out (asserted by a singular test). #}
select
    t.txn_id,
    t.txn_ts,
    t.txn_date,
    datediff('day', min(t.txn_date) over (), t.txn_date) + 1   as day_index,
    t.from_account_id,
    t.to_account_id,
    t.amount_paid * fx_p.usd_per_unit                          as amount_usd,
    t.amount_received * fx_r.usd_per_unit                      as amount_received_usd,
    t.payment_currency,
    t.receiving_currency,
    t.payment_format,
    r.risk_weight                                              as format_risk_weight,
    t.is_self_transfer,
    (t.payment_currency <> t.receiving_currency)               as is_cross_currency,
    t.is_laundering,
    p.pattern_id,
    p.pattern_type
from {{ ref('stg_transactions') }} t
left join {{ ref('fx_rates_approx') }} fx_p on fx_p.currency = t.payment_currency
left join {{ ref('fx_rates_approx') }} fx_r on fx_r.currency = t.receiving_currency
left join {{ ref('payment_format_risk') }} r on r.payment_format = t.payment_format
left join {{ ref('stg_patterns') }} p
    on  p.txn_ts = t.txn_ts
    and p.from_account_id = t.from_account_id
    and p.to_account_id = t.to_account_id
    and p.amount_paid = t.amount_paid
    and p.payment_currency = t.payment_currency
    and p.amount_received = t.amount_received
    and p.receiving_currency = t.receiving_currency
    and p.payment_format = t.payment_format
    and p.is_laundering = t.is_laundering
