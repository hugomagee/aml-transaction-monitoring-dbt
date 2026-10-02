"""Per-day counts and validation-size check for choosing tune_last_day.
Usage: python scripts/split_counts.py   (needs the dbt marts built)"""
from pathlib import Path

import duckdb

con = duckdb.connect(str(Path(__file__).resolve().parent.parent / "data" / "aml.duckdb"), read_only=True)
con.sql("""
with e as (select day_index, from_account_id a, is_laundering l from marts.fct_transactions
           union all select day_index, to_account_id, is_laundering from marts.fct_transactions),
d as (select day_index, count(distinct a) filter (where l = 1) as labelled_accounts from e group by 1),
t as (select day_index, count(*) as transactions, sum(is_laundering) as laundering_txns
      from marts.fct_transactions group by 1)
select * from t join d using (day_index) order by 1""").show(max_rows=40)
print("labelled accounts if validation starts at day k (days k..end):")
for k in range(2, 18):
    n = con.execute("""select count(distinct a) from (
        select from_account_id a from marts.fct_transactions where is_laundering = 1 and day_index >= ?
        union all select to_account_id from marts.fct_transactions where is_laundering = 1 and day_index >= ?)""",
                    [k, k]).fetchone()[0]
    print(f"  k={k:2d} (tune_last_day={k - 1:2d}): {n:,}")
