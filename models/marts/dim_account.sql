select
    p.*,
    a.bank_name,
    a.entity_name
from {{ ref('int_account_profile') }} p
join {{ ref('stg_accounts') }} a using (account_id)
