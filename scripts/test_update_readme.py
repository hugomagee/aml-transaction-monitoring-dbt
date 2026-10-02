"""Checks that the README headline wording is computed from the numbers, not hard-coded.
    python scripts/test_update_readme.py"""
import copy
import json
from pathlib import Path

import update_readme as u

ROOT = Path(__file__).resolve().parent.parent
ml = json.loads((ROOT / "docs" / "ml_results.json").read_text())
EXPECTED = ("On the synthetic IBM AMLworld data, the best hand-written rule (fan-in/out) alerts on 5.0 of every 1,000 "
            "accounts at 7.1% precision against a 0.73% base rate (about 10x lift, days 8-18 of HI-Small). A gradient-boosted "
            "model on point-in-time account features does better at equal volume on HI-Small (24.5% precision at 5 alerts "
            "per 1,000 on held-out accounts after removing four features that proxy simulator behaviour; 35.4% with them), "
            "but on LI-Small it is only level with fan-in/out at that volume, so the rules are a baseline, not a detector.")


def with_li_ablated(factor):
    m = copy.deepcopy(ml)
    for r in m["LI_validate"]["rows"]:
        if r["method"] == u.NO_ARTIFACT:
            r["b5"][0] *= factor
    return m


def with_hi_ablated(factor):
    m = copy.deepcopy(ml)
    for r in m["HI_validate"]["rows"]:
        if r["method"] == u.NO_ARTIFACT:
            r["b5"][0] *= factor
    return m


args = (0.0715, 4.99, 0.00733)
base = u.headline_text(*args, ml)
assert base == EXPECTED, base
assert "only level with fan-in/out" in base
assert "ahead of fan-in/out" in u.headline_text(*args, with_li_ablated(1.5))
assert "behind fan-in/out" in u.headline_text(*args, with_li_ablated(0.5))
assert "does worse at equal volume" in u.headline_text(*args, with_hi_ablated(0.1))
print("headline wording follows the data: ok")
