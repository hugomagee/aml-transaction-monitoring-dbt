-- Fails if any staged transaction has a negative amount (zero is also flagged elsewhere via `positive`).
select txn_id from {{ ref('stg_transactions') }}
where amount_paid < 0 or amount_received < 0
