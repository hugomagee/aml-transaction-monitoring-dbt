"""make eval RULE=<model>: build one rule model, then print its metrics.

Metrics come from the same macros as the fct_rule_* marts (macros/rule_eval.sql),
rendered with `dbt compile --inline` and run in DuckDB, so there is one definition.
Usage: python scripts/eval_rule.py rule_fan_in_out [tune_last_day]
"""
import os
import subprocess
import sys
from pathlib import Path

import duckdb
import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
DBT = str(ROOT / ".venv" / "bin" / "dbt")
ENV = {**os.environ, "DBT_PROFILES_DIR": str(ROOT)}


def dbt(*args: str) -> str:
    r = subprocess.run([DBT, *args], cwd=ROOT, env=ENV, capture_output=True, text=True)
    if r.returncode:
        sys.exit(r.stdout + r.stderr)
    return r.stdout


def show(title: str, macro: str, rule: str, extra_vars: str) -> None:
    sql = f"{{{{ {macro}(ref('{rule}'), '{rule}') }}}}"
    out = dbt("compile", "--inline", sql, "--vars", extra_vars)
    compiled = out.split("Compiled inline node is:", 1)[-1].strip()
    con = duckdb.connect(str(ROOT / "data" / "aml.duckdb"), read_only=True)
    df = con.execute(compiled).df()
    with pd.option_context("display.width", 250, "display.max_columns", None,
                           "display.float_format", "{:.4f}".format):
        print(f"\n== {title} ==\n{df.to_string(index=False)}")


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit("usage: make eval RULE=<model name>   (e.g. rule_dummy_all)")
    rule = sys.argv[1]
    extra = f"{{tune_last_day: {sys.argv[2]}}}" if len(sys.argv) > 2 else "{}"
    print(dbt("run", "--select", rule, "--vars", extra).strip().splitlines()[-1])
    show("performance (account unit)", "rule_performance", rule, extra)
    show("recall by pattern type", "rule_pattern_recall", rule, extra)
    show("threshold sensitivity (split=all)", "rule_threshold_sensitivity", rule, extra)


if __name__ == "__main__":
    main()
