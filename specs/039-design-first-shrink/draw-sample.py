#!/usr/bin/env python3
"""039 抽样脚本：样本是公开输入的确定性函数，无可挑选的自由参数。

seed 由 base commit SHA 推导（本轮开始前即固定、公开、作者不可控），
因此不存在「先看行、再挑一个好看的 seed」的空间。
用法: draw-sample.py <base-sha> <register-path>
"""
import re, random, sys, subprocess

base_sha, reg_path = sys.argv[1], sys.argv[2]
seed = int(base_sha[:8], 16)

frame = []
for i, line in enumerate(open(reg_path).read().split("\n"), start=1):
    if line.strip().startswith("|") and "behavioral-evidence" in line:
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        keys = re.findall(r"`([a-z0-9-]+)`", cells[1]) if len(cells) > 1 else []
        if keys:
            frame.append({"ordinal": len(frame) + 1, "file_line": i, "owner": keys[0]})

pool = [r for r in frame if r["owner"] in ("skill-extraction-workflow", "code-review")]
print(f"frame_all={len(frame)} pool_two_owners={len(pool)} seed_source={base_sha[:8]} seed={seed}")
sample = sorted(random.Random(seed).sample(pool, 30), key=lambda r: r["ordinal"])
print("ordinal:file_line:owner")
for r in sample:
    print(f"{r['ordinal']}:{r['file_line']}:{r['owner']}")
