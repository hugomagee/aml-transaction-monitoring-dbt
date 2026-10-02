-- Explainability is the point: every alert carries a human-readable reason.
select rule_id, account_id from {{ ref('fct_alerts') }}
where reason is null or trim(reason) = ''
