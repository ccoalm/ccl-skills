#!/usr/bin/env python3
"""042 阶段 A 步骤 2：缺陷 #1（`休眠` = 零命中 grep → 不可满足）的当前-baseline 复现。

实腿：对台账每个 `file:` 定位符的锚文本跑一次全仓 `git grep -F`，统计零命中的锚数量。
     039 判据 v1 把 `休眠` 定义为「机械零命中」；若真实锚永远命中，该定义不可满足。
对照腿：合成两个不可能存在的锚，必须返回 0——不能返回零的检查没有鉴别力，
     它的「零命中数=0」就不是证据。
退出：0 = 两条腿都按预期（缺陷 #1 复现）；非 0 = 与预期不符或扫描失败。
"""
import re, subprocess, sys, os
root = sys.argv[1] if len(sys.argv) > 1 else "."
reg = os.path.join(root, "skills/skill-extraction-workflow/references/source-register.md")
anchors, fence = [], False
for line in open(reg, encoding="utf-8"):
    if line.strip().startswith("```"): fence = not fence; continue
    if fence or not line.startswith("|"): continue
    m = re.search(r"(?<!`)firing-path:\s*([^|;]*)", line)
    if not m: continue
    for loc in re.split(r",(?=\s*(?:file|command):)", m.group(1)):
        loc = loc.strip()
        if loc.startswith("file:") and "#" in loc:
            a = loc.split("#", 1)[1].strip()
            if len(a) >= 8: anchors.append(a)
def hits(pat):
    r = subprocess.run(["git", "-C", root, "grep", "-cF", "--", pat],
                       capture_output=True, text=True)
    if r.returncode >= 2: return None
    return sum(int(x.rsplit(":", 1)[1]) for x in r.stdout.strip().split("\n") if ":" in x)
rc = 0
scanned = [(a, hits(a)) for a in anchors]
failed = [a for a, h in scanned if h is None]
zero = [a for a, h in scanned if h == 0]
print(f"  实腿  锚数={len(anchors)} 扫描失败={len(failed)} 零命中={len(zero)}")
if failed or zero != []:
    print("  FAIL  期望：扫描失败=0 且零命中=0"); rc = 1
else:
    print("  PASS  每个真实锚都至少命中一次——`休眠`=零命中 不可满足")
ctl = ["ZZZ-anchor-that-cannot-exist-042", "另一条不可能存在的锚文本-042"]
bad = [(c, hits(c)) for c in ctl if hits(c) != 0]
if bad:
    print(f"  FAIL  对照腿：合成锚未返回 0 -> {bad}，检查无鉴别力"); rc = 1
else:
    print("  PASS  对照腿：合成锚返回 0，检查确有鉴别力")
print("anchor_zero_hit_reproduced: 缺陷 #1 未闭合" if rc == 0 else "anchor_zero_hit_probe_FAILED")
sys.exit(rc)
