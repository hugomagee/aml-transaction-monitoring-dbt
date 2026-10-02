"""ML vs rules at equal alert volume. Writes docs/ml_results.md.   `make ml`

Design (fixed before looking at any result):
  * features: marts.fct_alert_features, point-in-time per split window (see its header).
    bank_country is left out of the model; entity_type is one-hot. Labels/pattern tags are not features.
  * account-grouped split: md5(account_id) -> 70% train group / 30% test group. The model trains on
    tune-window rows of train-group accounts and is scored on validate-window rows of test-group
    accounts, so no account is in both train and test AND the test window is later than train.
    A second check scores the tune window's test-group accounts (account-disjoint, same window).
  * models: base features; base + rule-alert features (rf_*). One fixed gradient-boosting config, no tuning.
  * rules are evaluated on the SAME test accounts; an account's rule score is the rule's max score
    in the window and only alerted accounts are eligible. Combined = number of headline rules fired.
  * equal volume: top-N accounts with N = budget/1000 * accounts in the evaluated set (budgets 1, 5,
    10); ties at the cut are resolved pro rata (expected value under random tie-breaking). If a rule
    alerts fewer accounts than N it simply uses all of them and the shortfall is shown.
  * the HI-trained models are applied to LI-Small once (tune and validate windows, all accounts).
"""
import hashlib
import json
from pathlib import Path

import duckdb
import numpy as np
import pandas as pd
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.inspection import permutation_importance
from sklearn.metrics import average_precision_score

ROOT = Path(__file__).resolve().parent.parent
BUDGETS = [1, 5, 10]
RULES = ["rule_fan_in_out", "rule_structuring", "rule_pass_through", "rule_cycles", "rule_baseline_anomaly"]
HEADLINE = RULES[:4]
PARAMS = dict(max_iter=300, learning_rate=0.05, max_leaf_nodes=15, min_samples_leaf=50,
              l2_regularization=1.0, early_stopping=False, random_state=0)


def load(db: Path) -> pd.DataFrame:
    con = duckdb.connect(str(db), read_only=True)
    df = con.execute("select * from marts.fct_alert_features").df()
    con.close()
    return df


def in_train_group(account_id: str) -> bool:
    return int(hashlib.md5(account_id.encode()).hexdigest()[:8], 16) % 10 < 7


def base_cols(df):
    return [c for c in df.columns if c.startswith("f_")]


def rule_cols(df):
    return [c for c in df.columns if c.startswith("rf_")]


def design(df, cols):
    x = df[cols].astype(float).copy()
    for v in ("Corporation", "Partnership", "Sole Proprietorship"):
        x[f"entity_{v}"] = (df["entity_type"] == v).astype(float)
    return x


def topn(score, label, eligible, n):
    """TP and volume in the top-n eligible accounts; ties at the cut resolved pro rata."""
    s = np.where(eligible, score, -np.inf)
    idx = np.where(eligible)[0]
    k = min(n, len(idx))
    if k == 0:
        return 0.0, 0
    order = idx[np.argsort(-s[idx], kind="stable")]
    cut = s[order[k - 1]]
    above = idx[s[idx] > cut]
    tied = idx[s[idx] == cut]
    tp = label[above].sum() + label[tied].sum() * (k - len(above)) / len(tied)
    return float(tp), k


def rule_scores(df, rule):
    n, mx = df[f"rf_{rule}_n"].to_numpy(), df[f"rf_{rule}_max"].to_numpy()
    return mx, n > 0


def combined_scores(df):
    c = sum((df[f"rf_{r}_n"] > 0).astype(int) for r in HEADLINE).to_numpy().astype(float)
    return c, c > 0


def evaluate(df, model_scores):
    """-> rows [(method, ap, {budget: (precision, recall, volume_per_1000)})] on df."""
    y = df["label"].astype(int).to_numpy()
    pos, n_acc = y.sum(), len(df)
    methods = {}
    for r in RULES:
        methods[r + (" [*]" if r == "rule_baseline_anomaly" else "")] = rule_scores(df, r)
    methods["combined_excl_baseline"] = combined_scores(df)
    for name, sc in model_scores.items():
        methods[name] = (sc, np.ones(n_acc, dtype=bool))
    rows = []
    for name, (sc, elig) in methods.items():
        ap = average_precision_score(y, np.where(elig, sc, -1.0))
        res = {}
        for b in BUDGETS:
            n = int(round(b / 1000 * n_acc))
            tp, k = topn(sc, y, elig, n)
            res[b] = (tp / k if k else float("nan"), tp / pos if pos else float("nan"), k * 1000 / n_acc)
        rows.append((name, ap, res))
    return rows, dict(accounts=n_acc, positives=int(pos), base=pos / n_acc)


def table(rows, info):
    head = "| method | PR-AUC | " + " | ".join(f"@{b}/1000: precision (recall) [volume]" for b in BUDGETS) + " |"
    sep = "|---|---|" + "---|" * len(BUDGETS)
    out = [head, sep]
    for name, ap, res in rows:
        cells = []
        for b in BUDGETS:
            p, r, v = res[b]
            cells.append("n/a" if np.isnan(p) else f"{p:.1%} ({r:.1%}) [{v:.2f}]")
        out.append(f"| {name} | {ap:.4f} | " + " | ".join(cells) + " |")
    out.append(f"\nEvaluated on {info['accounts']:,} accounts, {info['positives']:,} labelled "
               f"(base rate {info['base']:.2%}; PR-AUC of a random ranking = base rate). "
               f"`[volume]` = alerts actually used per 1,000 accounts; below the budget means the rule has fewer alerts.")
    return "\n".join(out)


def ml_precision_at_volume(df, scores, per_1000):
    """Precision of an ML score in the top accounts at a given volume (alerts per 1,000 accounts)."""
    y = df["label"].astype(int).to_numpy()
    n = max(1, int(round(per_1000 / 1000 * len(df))))
    tp, k = topn(scores, y, np.ones(len(y), dtype=bool), n)
    return tp / k


def verdict(rows, label, df, model_scores):
    """Compare like with like: a rule only competes at a budget it can actually fill (>= 90% of it);
    a rule that alerts fewer accounts is compared with ML at that rule's own volume."""
    lines = []
    mls = [r for r in rows if r[0].startswith("ML")]
    rules = [r for r in rows if r[0].startswith(("rule_", "combined"))]
    for b in BUDGETS:
        full = [r for r in rules if r[2][b][2] >= 0.9 * b]
        ml = max(mls, key=lambda r: r[2][b][0])
        if full:
            rule = max(full, key=lambda r: np.nan_to_num(r[2][b][0]))
            rp, mp = rule[2][b][0], ml[2][b][0]
            word = "beats" if mp > rp * 1.05 else ("is level with" if mp > rp * 0.95 else "does NOT beat")
            lines.append(f"- {label}, {b} alerts/1,000: best rule that fills the budget is {rule[0]} at {rp:.1%} "
                         f"precision; best ML ({ml[0]}) at {mp:.1%} {word} it (within 5% counts as level).")
    for r in rules:
        v = r[2][BUDGETS[-1]][2]
        if v < 0.9 * BUDGETS[-1]:
            p_rule = r[2][BUDGETS[-1]][0]
            if np.isnan(p_rule):
                continue
            ml_name, ml_scores = max(model_scores.items(), key=lambda kv: ml_precision_at_volume(df, kv[1], v))
            p_ml = ml_precision_at_volume(df, ml_scores, v)
            word = "beats" if p_ml > p_rule * 1.05 else ("is level with" if p_ml > p_rule * 0.95 else "does NOT beat")
            lines.append(f"- {label}, at {r[0]}'s own volume ({v:.2f}/1,000): rule precision {p_rule:.1%}; "
                         f"best ML ({ml_name}) at the same volume {p_ml:.1%} {word} it.")
    return "\n".join(lines)


def _selfcheck() -> None:
    """Tie handling: 4 accounts tied at the cut, 1 labelled, take 2 of them -> expected TP 0.5."""
    sc = np.array([2.0, 1.0, 1.0, 1.0, 1.0])
    y = np.array([0, 1, 0, 0, 0])
    tp, k = topn(sc, y, np.ones(5, dtype=bool), 3)
    assert k == 3 and abs(tp - 0.5) < 1e-9, (tp, k)
    tp, k = topn(sc, y, np.array([True, False, False, False, False]), 3)
    assert k == 1 and tp == 0.0


def main() -> None:
    _selfcheck()
    hi = load(ROOT / "data" / "aml.duckdb")
    hi["train"] = hi["account_id"].map(in_train_group)
    feats_a = base_cols(hi)
    feats_b = feats_a + rule_cols(hi)
    tr = hi[(hi.split == "tune") & hi.train]
    y_tr = tr["label"].astype(int)
    models = {}
    for name, cols in (("ML base", feats_a), ("ML base+rules", feats_b)):
        m = HistGradientBoostingClassifier(**PARAMS).fit(design(tr, cols), y_tr)
        models[name] = (m, cols)
    # account-disjointness is by construction; assert it
    te_val = hi[(hi.split == "validate") & ~hi.train]
    te_tune = hi[(hi.split == "tune") & ~hi.train]
    assert set(tr.account_id).isdisjoint(te_val.account_id) and set(tr.account_id).isdisjoint(te_tune.account_id)

    def score(df):
        return {n: m.predict_proba(design(df, c))[:, 1] for n, (m, c) in models.items()}

    sections, ctx = [], {}
    sc_val, sc_tun = score(te_val), score(te_tune)
    r_val, i_val = evaluate(te_val, sc_val)
    r_tun, i_tun = evaluate(te_tune, sc_tun)
    sections.append(("HI-Small: train on tune window, test on validate window, account-disjoint (headline ML result)",
                     r_val, i_val))
    sections.append(("HI-Small: same window (tune), account-disjoint test accounts (separates account effect from time effect)",
                     r_tun, i_tun))
    li_path = ROOT / "data" / "li.duckdb"
    li_rows = []
    if li_path.exists():
        li = load(li_path)
        for sp in ("validate", "tune"):
            d = li[li.split == sp]
            sc = score(d)
            r, i = evaluate(d, sc)
            ctx[sp] = (d, sc)
            li_rows.append((f"LI-Small {sp} window: HI-trained models applied once (never trained or tuned on LI)", r, i))
    sections += li_rows

    sample = tr.sample(n=min(40000, len(tr)), random_state=0)
    pi = permutation_importance(models["ML base"][0], design(sample, feats_a), sample["label"].astype(int),
                                scoring="average_precision", n_repeats=3, random_state=0, n_jobs=1)
    imp = pd.Series(pi.importances_mean, index=design(sample, feats_a).columns).clip(lower=0)
    imp = (imp / imp.sum()).sort_values(ascending=False).head(10)
    n_tr, p_tr = len(tr), int(y_tr.sum())
    md = [f"""# ML vs rules at equal alert volume

Generated by `python scripts/ml_compare.py` (`make ml`); do not edit by hand.

## Setup
- **Unit and label:** account; label = laundering endpoint inside the window (per-split labels).
- **Features:** `marts.fct_alert_features`, computed only from each split's own day window (point-in-time;
  tests: `assert_features_are_point_in_time`, `assert_features_have_no_label_columns`). Excluded: the
  whole-window hub degrees, the pattern-file tags, anything derived from Is Laundering, `bank_country`.
- **Train:** tune window (days 1-7), accounts in the 70% train group: {n_tr:,} accounts, {p_tr:,} labelled.
- **Test:** validate window (days 8+), accounts in the 30% test group (never seen in training, later in
  time). Rules are scored on exactly the same accounts.
- **Model:** scikit-learn HistGradientBoostingClassifier (gradient boosting), one fixed configuration, no hyperparameter tuning (so no peeking at validate).
  `ML base` = base features; `ML base+rules` = base features plus the five rules' alert counts and
  max scores in the window (the rules were tuned on the tune split, whose labels the model also trains on).
- **Equal volume:** top-N accounts with N = budget/1000 x evaluated accounts; ties resolved pro rata.
- [*] rule_baseline_anomaly does not transfer across days (8.2 alerts/1,000 on tune vs 84 on validate; cold-start baseline).
- Caveat: rule alerts use some history/whole-window information the point-in-time features do not
  (cycles' hub cap uses whole-window degree; other rules look back across the split boundary), so the
  rules-as-features model inherits that small look-ahead; the base-feature model does not.
"""]
    for title, rows, info in sections:
        md.append(f"## {title}\n\n{table(rows, info)}\n")
    md.append("## Verdict (generated from the tables above)\n")
    md.append(verdict(r_val, "HI validate", te_val, sc_val) + "\n")
    for (title, rows, info), sp in zip(li_rows, ("validate", "tune")):
        md.append(verdict(rows, title.split(":")[0], *ctx[sp]) + "\n")
    md.append("""## Reading these results (written by Claude Code after seeing them; not generated)

- ML is far ahead of every rule at equal volume, on HI-Small (account-disjoint, later window) and on
  LI-Small (a different dataset the model never saw). It is the opposite of "report only if it wins":
  here the rules lose, and the single best rule (fan-in/out) is a modest lift over the base rate.
- The base-feature model is the pre-declared primary. "Best ML" in the verdict lines picks between the
  two variants after seeing the results, which is mildly optimistic; `ML base` alone is also ahead.
- Do not read the ML lead as "ML detects laundering". The most important features (number of
  currencies sent in, self-transfers, share of risky payment formats) look like properties of how the
  synthetic generator produces laundering accounts, not of real laundering. The data is synthetic and
  generated from the same patterns the rules look for; real-world transfer is untested.
- `ML base+rules` is not reliably better than `ML base`: the rules were tuned on the same tune-split
  labels the model trains on, so their alert features look better in training than they are later.
- Transfer to LI-Small is weaker than on HI-Small (lower base rate, 29% pattern coverage), though
  still well above the rules.
""")
    md.append("## Top base-feature importances (permutation, share of total, ML base, on a 40k train sample)\n\n"
              + "\n".join(f"- `{k}`: {v:.1%}" for k, v in imp.items()) + "\n")
    export = {}
    for key, (title, rows, info) in zip(("HI_validate", "HI_tune", "LI_validate", "LI_tune"), sections):
        export[key] = {"title": title, "info": info, "rows": [
            {"method": n, "pr_auc": ap, **{f"b{b}": list(res[b]) for b in BUDGETS}} for n, ap, res in rows]}
    (ROOT / "docs" / "ml_results.json").write_text(json.dumps(export, indent=1, default=float) + "\n")
    (ROOT / "docs" / "ml_results.md").write_text("\n".join(md))
    print("\n".join(md))


if __name__ == "__main__":
    main()
