#!/usr/bin/env python3
"""Aggregate the paired run: validity, contamination, cost, invocation, per-item rubric rates.

Usage: analyze.py RUN_DIR JUDGE_DIR > summary.md
Scores: met=1, partial=0.5, missed=0; item score per answer averaged over the S items.
Interval: exact two-sided permutation test on per-answer scores (before vs after), per fixture.
"""
import glob, itertools, json, os, random, statistics, sys

run, jdir = sys.argv[1], sys.argv[2]
ARM = {"current": "before", "candidate": "after"}
VAL = {"met": 1.0, "partial": 0.5, "missed": 0.0}

metas = [json.load(open(p)) for p in sorted(glob.glob(os.path.join(run, "*.meta.json")))]
judg = [json.loads(l) for l in open(os.path.join(jdir, "judgments.jsonl")) if l.strip()]
jmap = {r["key"]: r for r in judg if not r.get("error")}
ids = sorted({m["id"] for m in metas})


def contaminated(m):
    """Before arm: anything it read or listed that names the new skill. After arm: anything
    under the before tree. Either way a hit is reported, never silently dropped."""
    bad = []
    for x in m["tool_uses"]:
        blob = json.dumps(x, ensure_ascii=False)
        if m["arm"] == "current" and ("typescript-dev" in blob or "/tsd-eval/after" in blob):
            bad.append(blob[:160])
        if m["arm"] == "candidate" and "/tsd-eval/before" in blob:
            bad.append(blob[:160])
    return bad


def perm_p(a, b, n=20000, seed=1):
    obs = abs(statistics.mean(b) - statistics.mean(a))
    pool, k = a + b, len(a)
    rng, hit = random.Random(seed), 0
    for _ in range(n):
        rng.shuffle(pool)
        if abs(statistics.mean(pool[k:]) - statistics.mean(pool[:k])) >= obs - 1e-12:
            hit += 1
    return (hit + 1) / (n + 1)


print("## Validity, cost, invocation\n")
print("| Fixture | Arm | valid | errors | contaminated | mean cost USD | mean wall s | mean turns | invoked typescript-dev | invoked (any) |")
print("|---|---|---|---|---|---|---|---|---|---|")
for fid in ids:
    for arm in ("current", "candidate"):
        ms = [m for m in metas if m["id"] == fid and m["arm"] == arm]
        ok = [m for m in ms if not m["error"]]
        cont = [m for m in ms if contaminated(m)]
        cost = [m["result"].get("total_cost_usd") or 0 for m in ms]
        inv = sum("ccl-skills:typescript-dev" in (m["skills_invoked"] or []) for m in ok)
        anyinv = sorted({s for m in ok for s in (m["skills_invoked"] or [])})
        print(f"| {fid} | {ARM[arm]} | {len(ok)} | {len(ms)-len(ok)} | {len(cont)} | "
              f"{statistics.mean(cost):.2f} | {statistics.mean(m['wall_s'] for m in ms):.0f} | "
              f"{statistics.mean((m['result'].get('num_turns') or 0) for m in ms):.1f} | {inv}/{len(ok)} | "
              f"{', '.join(s.replace('ccl-skills:', '') for s in anyinv) or '—'} |")
allc = [(m["id"], m["arm"], m["sample"], contaminated(m)) for m in metas if contaminated(m)]
print(f"\nContamination hits: {len(allc)}")
for c in allc:
    print(f"- {c[0]}/{ARM[c[1]]}/s{c[2]}: {c[3][:2]}")

print("\n## Rubric coverage (blinded judge)\n")
print("| Fixture | before mean | after mean | delta | permutation p | judged before/after | W-flags before | W-flags after |")
print("|---|---|---|---|---|---|---|---|")
item_rows = []
for fid in ids:
    sc, wf, n = {}, {}, {}
    for arm in ("current", "candidate"):
        rows = [r for r in jmap.values() if r["id"] == fid and r["arm"] == arm]
        n[arm] = len(rows)
        sc[arm] = [statistics.mean(VAL[v] for v in r["S"].values()) for r in rows]
        wf[arm] = sum(sum(r["W"].values()) for r in rows)
        keys = sorted(rows[0]["S"]) if rows else []
        for k in keys:
            vals = [r["S"][k] for r in rows]
            item_rows.append((fid, k, arm, sum(v == "met" for v in vals), sum(v == "partial" for v in vals),
                              sum(v == "missed" for v in vals)))
        for k in sorted(rows[0]["W"]) if rows else []:
            item_rows.append((fid, k, arm, sum(r["W"][k] for r in rows), None, None))
    if sc["current"] and sc["candidate"]:
        d = statistics.mean(sc["candidate"]) - statistics.mean(sc["current"])
        print(f"| {fid} | {statistics.mean(sc['current']):.2f} | {statistics.mean(sc['candidate']):.2f} | "
              f"{d:+.2f} | {perm_p(sc['current'], sc['candidate']):.4f} | {n['current']}/{n['candidate']} | "
              f"{wf['current']} | {wf['candidate']} |")

print("\n## Per item (met / partial / missed; W = answers showing the weakness)\n")
print("| Fixture | Item | before | after |")
print("|---|---|---|---|")
by = {}
for fid, k, arm, a, b, c in item_rows:
    by.setdefault((fid, k), {})[arm] = f"{a}/{b}/{c}" if b is not None else f"{a}"
for (fid, k), v in sorted(by.items()):
    print(f"| {fid} | {k} | {v.get('current','—')} | {v.get('candidate','—')} |")

print("\n## Judge-reported wrong facts (count of answers with ≥1)\n")
for fid in ids:
    for arm in ("current", "candidate"):
        rows = [r for r in jmap.values() if r["id"] == fid and r["arm"] == arm]
        print(f"- {fid} {ARM[arm]}: {sum(bool(r.get('wrong_facts')) for r in rows)}/{len(rows)}")
