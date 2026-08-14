#!/usr/bin/env python3
"""Deterministic aggregate recompute artifact generator (chain r2 challenge P1 fix).

Enumerates every raw round file behind the aggregates cited in this round's
closeout (this round's baseline plus the in-tree oncall-round evidence arms),
records each file's sha256 and the per-round verdict for the two load-bearing
case ids, and recomputes every cited total from those raw files. Output is
deterministic (sorted paths, no timestamps): run from anywhere as
`python3 recompute-aggregates.py > aggregates-recomputed.json` and diff against
the committed artifact.
"""
import hashlib
import json
import os
import subprocess
import sys

CASES = ("p3-log-plus-test", "new-observability-fields")
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = subprocess.check_output(
    ["git", "-C", HERE, "rev-parse", "--show-toplevel"], text=True
).strip()
ONCALL = "eval/evidence/routing-oncall-sop-2026-08-14"
THIS = "eval/evidence/routing-p3-log-plus-test-2026-08-14"


def sha256(path):
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


rows = []
for base in (ONCALL, THIS):
    absbase = os.path.join(ROOT, base)
    for dirpath, dirnames, filenames in os.walk(absbase):
        dirnames.sort()
        for name in sorted(filenames):
            if not name.startswith("round-") or not name.endswith(".json"):
                continue
            if name.endswith(".binding.json"):
                continue
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, ROOT)
            data = json.load(open(path))
            for res in data.get("results", []):
                if res.get("id") in CASES:
                    rows.append(
                        {
                            "file": rel,
                            "sha256": sha256(path),
                            "group": os.path.relpath(dirpath, ROOT),
                            "case": res["id"],
                            "status": res.get("status"),
                            "selected": res.get("selected"),
                            "confidence": res.get("confidence"),
                        }
                    )

rows.sort(key=lambda r: (r["file"], r["case"]))

groups = {}
for r in rows:
    g = groups.setdefault(r["group"], {c: {"pass": 0, "n": 0} for c in CASES})
    if r["case"] in g:
        g[r["case"]]["n"] += 1
        if r["status"] == "PASS":
            g[r["case"]]["pass"] += 1

def tally(group, case):
    g = groups.get(group, {}).get(case, {"pass": 0, "n": 0})
    return "{}/{}".format(g["pass"], g["n"])

P3 = "p3-log-plus-test"
SIB = "new-observability-fields"
nb = ONCALL + "/neighbor-before"
na = ONCALL + "/neighbor-after"
post_change_groups = [
    ONCALL + "/superseded-wording-v1/neighbor-after",
    ONCALL + "/superseded-wording-v2/neighbor-after",
    ONCALL + "/superseded-unbound-v3/neighbor-after",
    ONCALL + "/superseded-bound-v3-desc-only/neighbor-after",
    na,
]
post_pass = sum(groups.get(g, {}).get(P3, {}).get("pass", 0) for g in post_change_groups)
post_n = sum(groups.get(g, {}).get(P3, {}).get("n", 0) for g in post_change_groups)
sib_pass = sum(groups.get(g, {}).get(SIB, {}).get("pass", 0) for g in (nb, na))
sib_n = sum(groups.get(g, {}).get(SIB, {}).get("n", 0) for g in (nb, na))
bound_groups_25 = [THIS + "/baseline-rounds", nb, na]
mn_hits_25 = sum(
    1
    for r in rows
    if r["case"] == P3 and r["group"] in bound_groups_25 and r["selected"] == "testing-strategy"
)
mn_n_25 = sum(1 for r in rows if r["case"] == P3 and r["group"] in bound_groups_25)
mn_hits_all = sum(1 for r in rows if r["case"] == P3 and r["selected"] == "testing-strategy")
mn_n_all = sum(1 for r in rows if r["case"] == P3)

out = {
    "note": "deterministic recompute of every aggregate cited by this round's closeout; per-round rows below are the raw basis",
    "recomputed_claims": {
        "this_round_baseline_p3": tally(THIS + "/baseline-rounds", P3),
        "oncall_neighbor_before_p3 (claimed 5/9, base 6a795af arm)": tally(nb, P3),
        "oncall_post_change_arms_p3 (claimed 19/27, v1+v2+unbound-v3+desc-bound-v3+full-surface-bound)": "{}/{}".format(post_pass, post_n),
        "token_sibling_new_observability_fields (claimed 15/15)": "{}/{}".format(sib_pass, sib_n),
        "p3_must_not_testing_strategy_hits_bound_25 (claimed 0 across this baseline + oncall neighbor-before/after)": "{} hits in {} rounds".format(mn_hits_25, mn_n_25),
        "p3_must_not_testing_strategy_hits_all_enumerated": "{} hits in {} rounds".format(mn_hits_all, mn_n_all),
    },
    "group_tallies": {
        g: {c: "{}/{}".format(v[c]["pass"], v[c]["n"]) for c in CASES if v[c]["n"]}
        for g, v in sorted(groups.items())
        if any(v[c]["n"] for c in CASES)
    },
    "rows": rows,
}
json.dump(out, sys.stdout, ensure_ascii=False, indent=2)
sys.stdout.write("\n")
