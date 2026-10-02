{{ config(materialized='table') }}

{# Bank ids are zero-padded in the transactions file but not in the accounts
   file, so they are normalised to the integer form (see bank_id macro). Typed, renamed, with a deterministic surrogate key. Exact duplicate rows
   (a handful exist) are kept and get distinct txn_ids: dropping them would
   break label-count reconciliation with the raw file. #}
select
    row_number() over (
        order by timestamp, from_bank, from_account, to_bank, to_account,
                 amount_paid, payment_currency, amount_received,
                 receiving_currency, payment_format, is_laundering
    )::bigint                                              as txn_id,
    strptime(timestamp, '%Y/%m/%d %H:%M')                  as txn_ts,
    cast(strptime(timestamp, '%Y/%m/%d %H:%M') as date)    as txn_date,
    {{ bank_id('from_bank') }}                             as from_bank,
    from_account,
    {{ bank_id('to_bank') }}                               as to_bank,
    to_account,
    {{ bank_id('from_bank') }} || '|' || from_account      as from_account_id,
    {{ bank_id('to_bank') }}   || '|' || to_account        as to_account_id,
    cast(amount_received as double)                        as amount_received,
    receiving_currency,
    cast(amount_paid as double)                            as amount_paid,
    payment_currency,
    payment_format,
    cast(is_laundering as integer)                         as is_laundering,
    (cast(from_bank as bigint) = cast(to_bank as bigint) and from_account = to_account)    as is_self_transfer
from {{ raw_ref('transactions') }}
