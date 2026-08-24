# 事后校验：每一轮是否真的产出了一份可解析、单用例、零 grader-error 的报告，
# 以及两臂是否跑在两个不同的 description 表面上。
# 这是对 run_arms.sh「只读 pass 行、不校验退出码」这一缺陷的补证——
# 缺陷真实存在，但它没有咬到本次数据，证据在此，可独立复跑。
import json, glob, os, sys
d = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
rows = []
for p in sorted(glob.glob(os.path.join(d, "del-*-run*.json"))):
    r = json.load(open(p))
    res = (r.get("results") or r.get("tasks_detail") or [])
    sel = (res[0].get("selected") if res else None)
    rows.append((os.path.basename(p), r.get("tasks"), r.get("pass"), r.get("fail"),
                 r.get("error"), sel, r["routing_surface"]["descriptions_sha256"]))
print(f"{'file':22}{'tasks':6}{'pass':5}{'fail':5}{'err':4} selected")
for f, t, p_, fa, e, s, h in rows:
    print(f"{f:22}{t:<6}{p_:<5}{fa:<5}{e:<4} {s}")
print()
print("grader_error_total  =", sum(r[4] or 0 for r in rows))
print("every_report_1_task =", all(r[1] == 1 for r in rows))
print("verdict_accounted   =", all((r[2] or 0)+(r[3] or 0)+(r[4] or 0) == 1 for r in rows))
surf = {}
for f, *_rest in rows: pass
for r in rows: surf.setdefault(r[6], []).append(r[0].split("-run")[0])
print("distinct_surfaces   =", len(surf))
for h, arms in surf.items(): print("   ", h[:16], "->", sorted(set(arms)))
