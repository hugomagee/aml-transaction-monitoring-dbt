-- Joins in int_txn_enriched must not drop or fan out rows, and labels must survive.
with s as (select count(*) n, sum(is_laundering) lab from {{ ref('stg_transactions') }}),
     e as (select count(*) n, sum(is_laundering) lab from {{ ref('int_txn_enriched') }})
select s.n as stg_n, e.n as int_n, s.lab as stg_lab, e.lab as int_lab
from s, e where s.n <> e.n or s.lab <> e.lab
