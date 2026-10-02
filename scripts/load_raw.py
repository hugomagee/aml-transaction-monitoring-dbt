"""Load raw IBM AMLworld files into DuckDB (schema `raw`, no transformation).

Per dataset prefix (hi, li) this creates:
  raw.<p>_transactions  - CSV as-is; the duplicate `Account` header is renamed
                          at ingestion (from_account, to_account). Everything
                          is read as VARCHAR so bank ids keep leading zeros.
  raw.<p>_accounts      - CSV as-is, snake_case headers.
  raw.<p>_patterns      - parsed Patterns.txt: one row per transaction line,
                          tagged with pattern_id and pattern_type.
Usage: python scripts/load_raw.py [hi li]   (default: whatever is in data/raw)
"""
import re
import sys
from pathlib import Path

import duckdb
import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "data" / "raw"
DB = ROOT / "data" / "aml.duckdb"

TXN_COLS = ["timestamp", "from_bank", "from_account", "to_bank", "to_account",
            "amount_received", "receiving_currency", "amount_paid",
            "payment_currency", "payment_format", "is_laundering"]
ACC_COLS = ["bank_name", "bank_id", "account_number", "entity_id", "entity_name"]
BEGIN = re.compile(r"^BEGIN LAUNDERING ATTEMPT - (.+?)(?::|$)")


def parse_patterns(path: Path) -> pd.DataFrame:
    rows, pid, ptype = [], 0, None
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        m = BEGIN.match(line)
        if m:
            pid, ptype = pid + 1, m.group(1).strip()
        elif line.startswith("END LAUNDERING ATTEMPT"):
            ptype = None
        elif ptype is not None:
            rows.append([pid, ptype, *line.split(",")])
    return pd.DataFrame(rows, columns=["pattern_id", "pattern_type", *TXN_COLS])


def load(con: duckdb.DuckDBPyConnection, p: str) -> None:
    name = p.upper()
    trans, accs, pats = (RAW / f"{name}-Small_{s}" for s in
                         ("Trans.csv", "accounts.csv", "Patterns.txt"))
    con.execute(f"""create or replace table raw.{p}_transactions as
        select * from read_csv('{trans}', header=true, all_varchar=true,
                               names={TXN_COLS})""")
    con.execute(f"""create or replace table raw.{p}_accounts as
        select * from read_csv('{accs}', header=true, all_varchar=true,
                               names={ACC_COLS})""")
    patterns = parse_patterns(pats)  # noqa: F841 (read by duckdb replacement scan)
    con.execute(f"create or replace table raw.{p}_patterns as select * from patterns")
    for t in ("transactions", "accounts", "patterns"):
        n = con.execute(f"select count(*) from raw.{p}_{t}").fetchone()[0]
        print(f"raw.{p}_{t}: {n:,} rows")


def main() -> None:
    wanted = sys.argv[1:] or [p for p in ("hi", "li")
                              if (RAW / f"{p.upper()}-Small_Trans.csv").exists()]
    con = duckdb.connect(str(DB))
    con.execute("create schema if not exists raw")
    for p in wanted:
        load(con, p)


if __name__ == "__main__":
    main()
