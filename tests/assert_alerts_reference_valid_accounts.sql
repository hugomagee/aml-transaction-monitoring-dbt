select a.rule_id, a.account_id
from {{ ref('fct_alerts') }} a
left join {{ ref('dim_account') }} d on d.account_id = a.account_id
where d.account_id is null
