{# Per account and calendar day, flows between different accounts only
   (self-transfers excluded). One row per account-day with any activity. #}
with sent as (
    select
        src as account_id, cast(txn_ts as date) as day,
        count(*) as sent_count, sum(amount_usd) as sent_usd,
        max(amount_usd) as max_sent_usd, count(distinct dst) as sent_distinct_counterparties
    from {{ ref('int_edges') }}
    group by 1, 2
),
received as (
    select
        dst as account_id, cast(txn_ts as date) as day,
        count(*) as recv_count, sum(amount_usd) as recv_usd,
        max(amount_usd) as max_recv_usd, count(distinct src) as recv_distinct_counterparties
    from {{ ref('int_edges') }}
    group by 1, 2
)
select
    coalesce(s.account_id, r.account_id) as account_id,
    coalesce(s.day, r.day)               as day,
    coalesce(s.sent_count, 0)            as sent_count,
    coalesce(s.sent_usd, 0)              as sent_usd,
    s.max_sent_usd,
    coalesce(s.sent_distinct_counterparties, 0) as sent_distinct_counterparties,
    coalesce(r.recv_count, 0)            as recv_count,
    coalesce(r.recv_usd, 0)              as recv_usd,
    r.max_recv_usd,
    coalesce(r.recv_distinct_counterparties, 0) as recv_distinct_counterparties
from sent s
full outer join received r on s.account_id = r.account_id and s.day = r.day
