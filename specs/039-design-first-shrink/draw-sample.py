#!/usr/bin/env python3
"""039 抽样脚本：样本是公开输入的确定性函数，无可挑选的自由参数。

seed 由 base commit SHA 推导（本轮开始前即固定、公开、起草方不可控），
因此不存在「先看行、再挑一个好看的 seed」的空间。同样的输入必得同样的名单。

用法: draw-sample.py <base-sha> <register-path>
退出: 0 成功；2 参数或输入错误。
"""
from __future__ import annotations

import random
import re
import sys
from pathlib import Path

POOL_OWNERS = ("skill-extraction-workflow", "code-review")
SAMPLE_SIZE = 30
OWNER_RE = re.compile(r"`([a-z0-9-]+)`")


def build_frame(register: Path) -> list[dict]:
    """台账中带 behavioral-evidence 且第二列能解出 owner 的行，按出现顺序编号。"""
    frame: list[dict] = []
    text = register.read_text(encoding="utf-8")
    for file_line, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        if not stripped.startswith("|") or "behavioral-evidence" not in stripped:
            continue
        cells = [c.strip() for c in stripped.strip("|").split("|")]
        if len(cells) < 2:
            continue
        owner = OWNER_RE.search(cells[1])
        if owner is None:
            continue
        frame.append(
            {"ordinal": len(frame) + 1, "file_line": file_line, "owner": owner.group(1)}
        )
    return frame


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(f"usage: {Path(argv[0]).name} <base-sha> <register-path>", file=sys.stderr)
        return 2
    base_sha, register_path = argv[1], Path(argv[2])
    if not re.fullmatch(r"[0-9a-f]{8,40}", base_sha):
        print(f"base-sha must be 8-40 lowercase hex chars, got {base_sha!r}", file=sys.stderr)
        return 2
    if not register_path.is_file():
        print(f"register not found: {register_path}", file=sys.stderr)
        return 2

    seed = int(base_sha[:8], 16)
    frame = build_frame(register_path)
    pool = [row for row in frame if row["owner"] in POOL_OWNERS]
    if len(pool) < SAMPLE_SIZE:
        print(f"pool has {len(pool)} rows, need {SAMPLE_SIZE}", file=sys.stderr)
        return 2

    print(
        f"frame_all={len(frame)} pool_two_owners={len(pool)} "
        f"seed_source={base_sha[:8]} seed={seed}"
    )
    sample = sorted(
        random.Random(seed).sample(pool, SAMPLE_SIZE), key=lambda row: row["ordinal"]
    )
    print("ordinal:file_line:owner")
    for row in sample:
        print(f"{row['ordinal']}:{row['file_line']}:{row['owner']}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
