select
    bank_id || '|' || account_number                       as account_id,
    bank_id,
    account_number,
    bank_name,
    split_part(bank_name, ' Bank', 1)                      as bank_country,
    entity_id,
    entity_name,
    split_part(entity_name, ' #', 1)                       as entity_type
from {{ raw_ref('accounts') }}
