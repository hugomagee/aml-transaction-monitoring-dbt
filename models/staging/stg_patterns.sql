{# One row per transaction line of Patterns.txt. Diagnosis only: never the label. #}
select
    pattern_id::bigint                                     as pattern_id,
    pattern_type,
    strptime(timestamp, '%Y/%m/%d %H:%M')                  as txn_ts,
    {{ bank_id('from_bank') }} || '|' || from_account                       as from_account_id,
    {{ bank_id('to_bank') }} || '|' || to_account                         as to_account_id,
    cast(amount_paid as double)                            as amount_paid,
    payment_currency,
    cast(amount_received as double)                        as amount_received,
    receiving_currency,
    payment_format,
    cast(is_laundering as integer)                         as is_laundering
from {{ raw_ref('patterns') }}
