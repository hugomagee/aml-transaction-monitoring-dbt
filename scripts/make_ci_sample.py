"""Build the deterministic CI sample from the full HI-Small files.

    python scripts/make_ci_sample.py        (needs `make data`; writes ci/sample/)

Design (documented in ci/sample/MANIFEST.json, written by this script):
  1. keep EVERY laundering transaction (so every pattern row survives);
  2. fill to ~TARGET rows from non-laundering transactions in two strata:
       - rows touching an account that is an endpoint of a laundering transaction
         (QUOTA_TOUCHING of them: labelled accounts keep some ordinary activity);
       - all other rows (the remainder);
     within a stratum rows are taken in md5(row || SEED) order, so the sample is a
     pure function of the input and the seed (no random(), stable across versions);
  3. keep the accounts-table rows for every account that appears in the sample;
  4. Patterns.txt is copied whole (all its rows are laundering rows, asserted).
Outputs are gzipped with a fixed mtime so the bytes are reproducible.
The sample proves the pipeline builds and its tests hold; it does NOT preserve
graph structure, so rule performance on it means nothing.
"""
import gzip
import hashlib
import json
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "data" / "raw"
OUT = ROOT / "ci" / "sample"
SEED = "aml-ci-sample-v1"
TARGET = 100_000
QUOTA_TOUCHING = 40_000
TXN_COLS = ["timestamp", "from_bank", "from_account", "to_bank", "to_account", "amount_received",
            "receiving_currency", "amount_paid", "payment_currency", "payment_format", "is_laundering"]
ACC_COLS = ["bank_name", "bank_id", "account_number", "entity_id", "entity_name"]


def write_gz(path: Path, header: str, body: str) -> str:
    data = ((header + "\n" if header else "") + body).encode()
    with open(path, "wb") as raw, gzip.GzipFile(fileobj=raw, mode="wb", mtime=0, filename="") as gz:
        gz.write(data)
    return hashlib.sha256(path.read_bytes()).hexdigest()


def first_line(path: Path) -> str:
    with open(path) as f:
        return f.readline().rstrip("\n")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect()
    cols = ", ".join(f"'{c}'" for c in TXN_COLS)
    con.execute(f"""create table t as select *, md5(concat_ws('|', {', '.join(TXN_COLS)}, '{SEED}')) as h
        from read_csv('{RAW / "HI-Small_Trans.csv"}', header=true, all_varchar=true, names={TXN_COLS})""")
    con.execute("""create macro acct(b, a) as cast(cast(b as bigint) as varchar) || '|' || a""")
    con.execute("""create table lab as
        select acct(from_bank, from_account) as id from t where is_laundering = '1'
        union select acct(to_bank, to_account) from t where is_laundering = '1'""")
    con.execute("""create table t2 as select *,
        (acct(from_bank, from_account) in (select id from lab)
         or acct(to_bank, to_account) in (select id from lab)) as touching from t""")
    n_lab = con.execute("select count(*) from t2 where is_laundering = '1'").fetchone()[0]
    quota_touch = min(QUOTA_TOUCHING, TARGET - n_lab)
    quota_other = TARGET - n_lab - quota_touch
    con.execute(f"""create table picked as
        select * from t2 where is_laundering = '1'
        union all select * from (select * from t2 where is_laundering = '0' and touching
                                 order by h limit {quota_touch})
        union all select * from (select * from t2 where is_laundering = '0' and not touching
                                 order by h limit {quota_other})""")
    sample = con.execute(f"select {', '.join(TXN_COLS)} from picked order by timestamp, h").fetchall()
    sha = {}
    sha["HI-Small_Trans.csv.gz"] = write_gz(
        OUT / "HI-Small_Trans.csv.gz", first_line(RAW / "HI-Small_Trans.csv"),
        "\n".join(",".join(r) for r in sample) + "\n")

    con.execute("create table ends as select acct(from_bank, from_account) as id from picked "
                "union select acct(to_bank, to_account) from picked")
    con.execute(f"""create table acc as select * from read_csv('{RAW / "HI-Small_accounts.csv"}',
        header=true, all_varchar=true, names={ACC_COLS})""")
    accs = con.execute(f"""select {', '.join(ACC_COLS)} from acc
        where acct(bank_id, account_number) in (select id from ends) order by bank_id, account_number""").fetchall()
    # entity/bank names contain no commas or quotes in this dataset; assert rather than assume
    assert not any(("," in v or '"' in v) for r in accs for v in r), "unexpected CSV special character"
    sha["HI-Small_accounts.csv.gz"] = write_gz(
        OUT / "HI-Small_accounts.csv.gz", first_line(RAW / "HI-Small_accounts.csv"),
        "\n".join(",".join(r) for r in accs) + "\n")

    pat = (RAW / "HI-Small_Patterns.txt").read_text()
    sample_keys = {",".join(r) for r in sample}
    pat_rows = [l for l in pat.splitlines() if l[:2] == "20"]
    missing = [l for l in pat_rows if l not in sample_keys]
    assert not missing, f"{len(missing)} pattern rows are not in the sample"
    sha["HI-Small_Patterns.txt.gz"] = write_gz(OUT / "HI-Small_Patterns.txt.gz", "", pat.rstrip("\n") + "\n")

    manifest = {
        "seed": SEED, "target_rows": TARGET, "quota_touching_labelled": quota_touch,
        "quota_other": quota_other, "transactions": len(sample), "laundering_transactions": n_lab,
        "accounts": len(accs), "pattern_rows_all_present": True, "sha256": sha,
    }
    (OUT / "MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
