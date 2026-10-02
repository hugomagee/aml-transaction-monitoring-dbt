-- The whole-window split must reproduce dim_account's overall label, and every
-- tune/validate label must be a whole-window label too (a split can only lose labels).
select 'all_split_mismatch' as problem, d.account_id
from {{ ref('dim_account') }} d
join {{ ref('fct_account_split_label') }} l on l.account_id = d.account_id and l.split = 'all'
where d.is_laundering_account <> l.is_laundering_account
union all
select 'split_label_without_overall_label', l.account_id
from {{ ref('fct_account_split_label') }} l
join {{ ref('dim_account') }} d using (account_id)
where l.split <> 'all' and l.is_laundering_account and not d.is_laundering_account
