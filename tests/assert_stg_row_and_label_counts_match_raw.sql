-- Staging must neither drop nor invent transactions or laundering labels.
with raw as (
    select count(*) as n, sum(cast(is_laundering as integer)) as lab
    from {{ raw_ref('transactions') }}
),
stg as (
    select count(*) as n, sum(is_laundering) as lab from {{ ref('stg_transactions') }}
)
select raw.n as raw_n, stg.n as stg_n, raw.lab as raw_lab, stg.lab as stg_lab
from raw, stg
where raw.n <> stg.n or raw.lab <> stg.lab
