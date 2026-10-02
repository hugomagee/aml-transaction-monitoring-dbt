-- Marts must carry exactly the labels staging has: laundering transactions and labelled accounts.
with stg as (
    select sum(is_laundering) as lab_txns, count(*) as n_txns from {{ ref('stg_transactions') }}
),
stg_acc as (
    select count(*) as lab_accounts from (
        select from_account_id as a from {{ ref('stg_transactions') }} where is_laundering = 1
        union select to_account_id from {{ ref('stg_transactions') }} where is_laundering = 1
    )
),
mart as (
    select sum(is_laundering) as lab_txns, count(*) as n_txns from {{ ref('fct_transactions') }}
),
mart_acc as (
    select count(*) as lab_accounts from {{ ref('dim_account') }} where is_laundering_account
)
select stg.lab_txns as stg_lab_txns, mart.lab_txns as mart_lab_txns,
       stg_acc.lab_accounts as stg_lab_accounts, mart_acc.lab_accounts as mart_lab_accounts
from stg, stg_acc, mart, mart_acc
where stg.lab_txns <> mart.lab_txns or stg.n_txns <> mart.n_txns
   or stg_acc.lab_accounts <> mart_acc.lab_accounts
