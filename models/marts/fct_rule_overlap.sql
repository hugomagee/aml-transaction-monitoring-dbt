{# Pairwise overlap of alerted accounts between wired rules (whole window). #}
with a as (
    select distinct rule_id, account_id from {{ ref('fct_alerts') }} where account_id is not null
),
lab as (select account_id, is_laundering_account from {{ ref('dim_account') }}),
rules as (select distinct rule_id from (
    {% for r in wired_rules() %}select '{{ r }}' as rule_id{% if not loop.last %} union all {% endif %}{% endfor %}
)),
sizes as (select rule_id, count(*) as n_alerted from a group by 1),
inter as (
    select x.rule_id as rule_a, y.rule_id as rule_b,
           count(*) as n_both, sum(l.is_laundering_account::int) as n_both_labelled
    from a x join a y on x.account_id = y.account_id and x.rule_id < y.rule_id
    join lab l on l.account_id = x.account_id
    group by 1, 2
)
select
    ra.rule_id as rule_a,
    rb.rule_id as rule_b,
    coalesce(sa.n_alerted, 0) as n_alerted_a,
    coalesce(sb.n_alerted, 0) as n_alerted_b,
    coalesce(i.n_both, 0) as n_both,
    coalesce(i.n_both_labelled, 0) as n_both_labelled,
    coalesce(i.n_both, 0)::double
        / nullif(coalesce(sa.n_alerted, 0) + coalesce(sb.n_alerted, 0) - coalesce(i.n_both, 0), 0) as jaccard
from rules ra
join rules rb on ra.rule_id < rb.rule_id
left join sizes sa on sa.rule_id = ra.rule_id
left join sizes sb on sb.rule_id = rb.rule_id
left join inter i on i.rule_a = ra.rule_id and i.rule_b = rb.rule_id
