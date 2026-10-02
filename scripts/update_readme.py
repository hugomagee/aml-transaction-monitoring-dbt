"""Fill the generated blocks of README.md (headline, results tables, lineage graph) from the repo.
    python scripts/update_readme.py     (needs `make build`, `make ml`; LI is optional)
Blocks are delimited by <!-- BEGIN:name --> / <!-- END:name -->; everything else is hand-written."""
import json
import re
import subprocess
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent.parent
README = ROOT / "README.md"
ml = json.loads((ROOT / "docs" / "ml_results.json").read_text())
NO_ARTIFACT = "ML base, no artifact features"


def q(db: str, sql: str):
    path = ROOT / "data" / db
    if not path.exists():
        return []
    con = duckdb.connect(str(path), read_only=True)
    try:
        return con.execute(sql).fetchall()
    finally:
        con.close()


PERF = """select rule_id, split, n_alerted_accounts, precision, account_recall, alerts_per_1000_accounts,
          n_labelled_accounts::double / n_population as base
          from marts.fct_rule_performance"""


def perf(db):
    return {(r[0], r[1]): r for r in q(db, PERF)}


hi, li = perf("aml.duckdb"), perf("li.duckdb")


def cell(d, rule, split):
    r = d.get((rule, split))
    if not r:
        return "n/a | n/a | n/a | n/a"
    prec, rec, per, base = r[3], r[4], r[5], r[6]
    return f"{prec:.1%} | {rec:.1%} | {per:.1f} | {prec / base:.1f}x" if prec is not None else f"n/a | {rec:.1%} | {per:.1f} | n/a"


def headline() -> str:
    r = hi[("rule_fan_in_out", "validate")]
    prec, per, base = r[3], r[5], r[6]
    m = {x["method"]: x for x in ml["HI_validate"]["rows"]}
    mlp = m["ML base"]["b5"][0]
    abl = m[NO_ARTIFACT]["b5"][0]
    return (f"On the synthetic IBM AMLworld data, the best hand-written rule (fan-in/out) alerts on {per:.1f} of every "
            f"1,000 accounts at {prec:.1%} precision against a {base:.2%} base rate (about {prec / base:.0f}x lift, days 8-18 of "
            f"HI-Small), but a gradient-boosted model on point-in-time account features beats every rule at equal volume "
            f"({mlp:.1%} precision at 5 alerts per 1,000 on held-out accounts; {abl:.1%} after removing four features that proxy "
            f"simulator behaviour), so the rules are a baseline, not a detector.")


def results_table() -> str:
    rules = ["rule_fan_in_out", "rule_structuring", "rule_pass_through", "rule_cycles", "rule_baseline_anomaly [*]",
             "combined_excl_baseline"]
    head = ("| rule | HI tune: precision / recall / alerts per 1,000 / lift | HI validate: precision / recall / per 1,000 / lift "
            "| LI-Small (frozen, whole window): precision / recall / per 1,000 / lift |\n|---|---|---|---|")
    rows = []
    for r in rules:
        rid = r.replace(" [*]", "")
        def c(d, sp):
            return cell(d, rid, sp).replace(" | ", " / ")
        rows.append(f"| {r} | {c(hi, 'tune')} | {c(hi, 'validate')} | {c(li, 'all')} |")
    base = {s: hi[("rule_dummy_all", s)][3] for s in ("tune", "validate")}
    li_base = li.get(("rule_dummy_all", "all"))
    foot = (f"\n\nBase rates (share of active accounts that are labelled): HI tune {base['tune']:.2%}, HI validate "
            f"{base['validate']:.2%}" + (f", LI whole window {li_base[3]:.2%}" if li_base else "") +
            ". Lift = precision / base rate. [*] rule_baseline_anomaly does not transfer across days "
            "(8.2 alerts/1,000 on tune vs 84 on validate; cold-start baseline) and is left out of the combined headline set. "
            "Full tables, recall by pattern type and rule overlap: [docs/rule_results.md](docs/rule_results.md).")
    return "\n".join([head] + rows) + foot


def ml_table() -> str:
    out = []
    for key, label in (("HI_validate", "HI-Small validate window, account-disjoint test accounts"),
                       ("LI_validate", "LI-Small validate window, HI-trained model applied once")):
        if key not in ml:
            continue
        d = ml[key]
        keep = ["rule_fan_in_out", "rule_cycles", "combined_excl_baseline", "ML base", NO_ARTIFACT, "ML base+rules"]
        rows = {r["method"]: r for r in d["rows"]}
        out.append(f"**{label}** (base rate {d['info']['base']:.2%}, {d['info']['accounts']:,} accounts)\n")
        out.append("| method | PR-AUC | precision (recall) at 1 / 1,000 | at 5 / 1,000 | at 10 / 1,000 |\n|---|---|---|---|---|")
        for k in keep:
            r = rows[k]
            cells = []
            for b in (1, 5, 10):
                p, rc, v = r[f"b{b}"]
                cells.append(f"{p:.1%} ({rc:.1%})" + ("" if v >= 0.9 * b else f" at only {v:.2f}/1,000"))
            out.append(f"| {k} | {r['pr_auc']:.3f} | " + " | ".join(cells) + " |")
        out.append("")
    out.append("`ML base, no artifact features` drops `f_n_currencies`, `f_n_self`, `f_frac_risky_format` and "
               "`f_frac_cross_currency`, an exclusion list declared before the ablation was run (same model and split; one ablation configuration, see the reproducibility note in docs/ml_results.md). "
               "Equal-volume comparison, ties resolved pro rata; a rule with fewer alerts than the budget uses all of them. "
               "Details, caveats and feature importances: [docs/ml_results.md](docs/ml_results.md).")
    return "\n".join(out)


def lineage() -> str:
    subprocess.run([str(ROOT / ".venv" / "bin" / "dbt"), "parse"], cwd=ROOT, capture_output=True,
                   env={"DBT_PROFILES_DIR": str(ROOT), "PATH": "/usr/bin:/bin"})
    mf = json.loads((ROOT / "target" / "manifest.json").read_text())
    nodes = {k: v for k, v in mf["nodes"].items() if v["resource_type"] in ("model", "seed")}
    nodes.update({k: v for k, v in mf["sources"].items() if v["name"].startswith("hi_")})
    layer_of = lambda n: "sources" if n["resource_type"] == "source" else (
        "seeds" if n["resource_type"] == "seed" else n["path"].split("/")[0])
    order = ["sources", "seeds", "staging", "intermediate", "harness", "rules", "marts"]
    ident = lambda k: re.sub(r"\W", "_", k)
    lines = ["```mermaid", "flowchart LR"]
    for layer in order:
        members = [(k, v) for k, v in nodes.items() if layer_of(v) == layer]
        if not members:
            continue
        lines.append(f"  subgraph {layer}")
        for k, v in sorted(members, key=lambda kv: kv[1]["name"]):
            lines.append(f"    {ident(k)}[{v['name']}]")
        lines.append("  end")
    for k, v in nodes.items():
        for dep in v.get("depends_on", {}).get("nodes", []):
            if dep in nodes:
                lines.append(f"  {ident(dep)} --> {ident(k)}")
    lines.append("```")
    return "\n".join(lines) + "\n\nGenerated from `target/manifest.json` (`python scripts/update_readme.py`); the `li_*` sources mirror `hi_*`."


BLOCKS = {"headline": headline, "results": results_table, "ml": ml_table, "lineage": lineage}


def main() -> None:
    text = README.read_text()
    for name, fn in BLOCKS.items():
        pat = re.compile(rf"(<!-- BEGIN:{name} -->\n).*?(\n<!-- END:{name} -->)", re.S)
        assert pat.search(text), f"missing block {name}"
        text = pat.sub(lambda m: m.group(1) + fn() + m.group(2), text)
    README.write_text(text)
    print("README blocks updated:", ", ".join(BLOCKS))


if __name__ == "__main__":
    main()
