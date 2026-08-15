#!/bin/bash
# Deterministic verbatim-fidelity check for the six promoted frozen-bank cases
# (extension-challenge P1: the MANIFEST's machine-comparison claim must be
# reproducible from the tree, not operator-asserted). Compares utterance,
# expected_skill, and must_not_route_to for each promoted id across: the
# measured source evidence file, this round's bank-new-cases.jsonl, and the
# frozen bank. Exit 0 only when every field of every case is byte-equal.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd -P)"
WT="$(git -C "$HERE" rev-parse --show-toplevel)" || exit 1
python3 - "$WT" "$HERE" <<'PYEOF'
import json, sys
wt, here = sys.argv[1], sys.argv[2]

def load(path):
    d = {}
    for l in open(path, encoding="utf-8"):
        l = l.strip()
        if l:
            j = json.loads(l)
            d[j["id"]] = j
    return d

bank = load(wt + "/eval/routing-tasks.jsonl")
newcases = load(here + "/bank-new-cases.jsonl")
src_map = {
    "variant-neg-release-watch-sop": wt + "/eval/evidence/routing-oncall-sop-2026-08-14/bank-variants.jsonl",
    "probe-combined-impl-intent": wt + "/eval/evidence/routing-lift-opencode-config-2026-08-14/bank-probe.jsonl",
    "var-neg-opencode-review": wt + "/eval/evidence/routing-lift-opencode-config-2026-08-14/bank-variants.jsonl",
    "var-neg-tui-commands": wt + "/eval/evidence/routing-lift-opencode-config-2026-08-14/bank-variants.jsonl",
    "var-neg-worktree-first": wt + "/eval/evidence/routing-lift-opencode-config-2026-08-14/bank-variants.jsonl",
    "var-neg-product-shortcut-feature": wt + "/eval/evidence/routing-lift-opencode-config-2026-08-14/bank-variants.jsonl",
}
fields = ("utterance", "expected_skill", "must_not_route_to")
bad = 0
for cid, src_path in src_map.items():
    src = load(src_path)
    if cid not in src:
        print(f"MISSING {cid} in source {src_path}")
        bad += 1
        continue
    for table_name, table in (("frozen-bank", bank), ("bank-new-cases", newcases)):
        if cid not in table:
            print(f"MISSING {cid} in {table_name}")
            bad += 1
            continue
        for f in fields:
            a = table[cid].get(f, [])
            b = src[cid].get(f, [])
            if a != b:
                print(f"MISMATCH {cid} {table_name} {f}: {a!r} != {b!r}")
                bad += 1
print("promoted-case provenance:", "ALL VERBATIM" if bad == 0 else f"{bad} mismatches")
sys.exit(1 if bad else 0)
PYEOF
