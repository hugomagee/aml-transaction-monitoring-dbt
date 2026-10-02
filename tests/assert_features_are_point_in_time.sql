-- Re-derive three features for the TUNE split from staging restricted to days 1..tune_last_day
-- and require equality with the mart for every account. If a tune feature looked at a later
-- transaction (or at the whole window) the numbers would differ.
with start as (select min(txn_date) as d0 from {{ ref('stg_transactions') }}),
tx as (
    select from_account_id, to_account_id, is_self_transfer,
           datediff('day', (select d0 from start), txn_date) + 1 as day_index
    from {{ ref('stg_transactions') }}
),
win as (select * from tx where day_index <= {{ var('tune_last_day') }}),
sent as (select from_account_id as account_id, count(*) as n from win where not is_self_transfer group by 1),
recv as (select to_account_id as account_id, count(*) as n from win where not is_self_transfer group by 1),
selft as (select from_account_id as account_id, count(*) as n from win where is_self_transfer group by 1),
deg as (select from_account_id as account_id, count(distinct to_account_id) as n from win where not is_self_transfer group by 1)
select f.account_id, f.f_n_sent, coalesce(s.n, 0) as exp_sent, f.f_n_recv, coalesce(r.n, 0) as exp_recv,
       f.f_n_self, coalesce(sf.n, 0) as exp_self, f.f_out_degree, coalesce(d.n, 0) as exp_deg
from {{ ref('fct_alert_features') }} f
left join sent s using (account_id)
left join recv r using (account_id)
left join selft sf using (account_id)
left join deg d using (account_id)
where f.split = 'tune'
  and (f.f_n_sent <> coalesce(s.n, 0) or f.f_n_recv <> coalesce(r.n, 0)
       or f.f_n_self <> coalesce(sf.n, 0) or f.f_out_degree <> coalesce(d.n, 0))
