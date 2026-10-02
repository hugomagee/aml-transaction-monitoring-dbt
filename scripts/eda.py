"""Profile the raw tables and write docs/eda_notes.md. Every number in the
notes is produced by this script: `python scripts/eda.py [hi li]`."""
import sys
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent.parent
con = duckdb.connect(str(ROOT / "data" / "aml.duckdb"), read_only=True)
KEY = "timestamp,from_bank,from_account,to_bank,to_account,amount_received,receiving_currency,amount_paid,payment_currency,payment_format,is_laundering"


def q(sql):
    return con.execute(sql).fetchall()


def table(headers, rows):
    out = ["| " + " | ".join(headers) + " |", "|" + "---|" * len(headers)]
    out += ["| " + " | ".join(f"{v:,}" if isinstance(v, int) else str(v) for v in r) + " |" for r in rows]
    return "\n".join(out)


def section(p: str) -> str:
    t, a, pt = f"raw.{p}_transactions", f"raw.{p}_accounts", f"raw.{p}_patterns"
    n, lab = q(f"select count(*), sum(is_laundering::int) from {t}")[0]
    lo, hi = q(f"select min(strptime(timestamp,'%Y/%m/%d %H:%M')), max(strptime(timestamp,'%Y/%m/%d %H:%M')) from {t}")[0]
    ndays = q(f"select count(distinct substr(timestamp,1,10)) from {t}")[0][0]
    daily = q(f"select substr(timestamp,1,10) d, count(*), sum(is_laundering::int) from {t} group by 1 order by 1")
    dups = q(f"select count(*) - count(distinct ({KEY})) from {t}")[0][0]
    selft = q(f"select count(*), sum(is_laundering::int) from {t} where from_bank=to_bank and from_account=to_account")[0]
    ccy_diff = q(f"select count(*) from {t} where receiving_currency<>payment_currency")[0][0]
    amt_diff = q(f"select count(*) from {t} where receiving_currency=payment_currency and amount_received<>amount_paid")[0][0]
    nonpos = q(f"select count(*) from {t} where try_cast(amount_paid as double) <= 0 or try_cast(amount_received as double) <= 0")[0][0]
    ccys = q(f"select payment_currency, count(*), sum(is_laundering::int) from {t} group by 1 order by 2 desc")
    fmts = q(f"select payment_format, count(*), sum(is_laundering::int) from {t} group by 1 order by 2 desc")
    nulls = q("select " + ",".join(f"sum(({c} is null or trim({c})='')::int)" for c in KEY.split(",")) + f" from {t}")[0]
    nacc = q(f"select count(*) from (select from_account a from {t} union select to_account from {t})")[0][0]
    nacc_tab = q(f"select count(*), count(distinct account_number) from {a}")[0]
    orphan = q(f"select count(*) from (select from_account a from {t} union select to_account from {t}) x where a not in (select account_number from {a})")[0][0]
    lab_acc = q(f"select count(*) from (select from_account a from {t} where is_laundering='1' union select to_account from {t} where is_laundering='1')")[0][0]
    npat, nptype = q(f"select count(distinct pattern_id), count(distinct pattern_type) from {pt}")[0]
    ptypes = q(f"select pattern_type, count(distinct pattern_id), count(*) from {pt} group by 1 order by 3 desc")
    covered = q(f"select count(distinct ({KEY})) from {pt}")[0][0]
    covered_lab = q(f"select count(*) from (select distinct {KEY} from {t} where is_laundering='1') l semi join (select distinct {KEY} from {pt}) p using ({KEY})")[0][0]
    lab_distinct = q(f"select count(distinct ({KEY})) from {t} where is_laundering='1'")[0][0]
    pat_unlab = q(f"select count(*) from (select distinct {KEY} from {pt}) p where is_laundering<>'1'")[0][0]
    o = [f"## {p.upper()}-Small\n"]
    o.append(f"- Transactions: {n:,}; laundering: {lab:,} ({lab / n:.4%}); distinct accounts in transactions: {nacc:,}")
    o.append(f"- Window: {lo} to {hi} ({ndays} calendar days)")
    o.append(f"- Exact duplicate rows (all columns): {dups:,}")
    o.append(f"- Self-transfers (same bank+account both sides): {selft[0]:,}, of which laundering: {selft[1] or 0:,}")
    o.append(f"- Cross-currency rows (receiving <> payment currency): {ccy_diff:,}; same currency but amounts differ: {amt_diff:,}")
    o.append(f"- Rows with a non-positive amount: {nonpos:,}")
    o.append(f"- Null/blank cells per column: " + ", ".join(f"{c}={v or 0}" for c, v in zip(KEY.split(","), nulls)))
    o.append(f"- Accounts table: {nacc_tab[0]:,} rows, {nacc_tab[1]:,} distinct account numbers; transaction accounts missing from it: {orphan:,}")
    o.append(f"- Accounts that are an endpoint of at least one laundering transaction: {lab_acc:,} ({lab_acc / nacc:.3%} of accounts)")
    o.append(f"- Patterns file: {npat:,} groups, {nptype} types, {covered:,} distinct transaction rows; of {lab_distinct:,} distinct laundering rows, {covered_lab:,} appear in Patterns.txt ({covered_lab / lab_distinct:.1%}); pattern rows labelled 0: {pat_unlab:,}\n")
    o.append("**Daily volume**\n\n" + table(["day", "txns", "laundering"], [(d, c, s) for d, c, s in daily]) + "\n")
    o.append("**Payment currency**\n\n" + table(["currency", "txns", "laundering"], ccys) + "\n")
    o.append("**Payment format**\n\n" + table(["format", "txns", "laundering"], fmts) + "\n")
    o.append("**Pattern types**\n\n" + table(["type", "groups", "rows"], ptypes) + "\n")
    return "\n".join(o)


def main():
    avail = {r[0].split("_")[0] for r in q("select table_name from information_schema.tables where table_schema='raw'")}
    wanted = [p for p in (sys.argv[1:] or ["hi", "li"]) if p in avail]
    body = "# EDA notes\n\nGenerated by `python scripts/eda.py`; do not edit by hand.\n\n" + "\n".join(section(p) for p in wanted)
    (ROOT / "docs" / "eda_notes.md").write_text(body)
    print(body)


main()
