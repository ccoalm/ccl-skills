#!/usr/bin/env bash
# 槽位 2/9 双删臂 / 归因臂的**可复跑**版本。
#
# 与 `run_arms.as-executed.txt`（041 实际跑出那批数的那份，逐字节保留、已改名为
# 非可执行扩展名以防误跑）的关系：读数规则、跨度、每臂次数完全相同；本版修掉了
# 041 两轮独立评审在那份上找到的两个缺陷：
#   1. 那份只 grep pass 行，不校验 runner 退出码与报告有效性——超时或 grader-error
#      会被静默计成一次「路由失败」，而 0/5 正是承重结论所依赖的数。
#   2. 那份硬编码工作树路径并无条件 `git checkout --`，会在别的克隆里读到无关状态，
#      且会连带丢弃目标文件上无关的未提交改动。
#
# 用法：run_arms_reproduce.sh <repo-root> [out-dir]
# 退出：0 = 两臂跑完且每轮都产出有效报告；非 0 = 任一前置或任一轮不合格（fail-closed）。
set -uo pipefail

WT="${1:?usage: run_arms_reproduce.sh <repo-root> [out-dir]}"
OUT="${2:-$(pwd)/arms-repro}"
SKILL_REL="skills/skill-extraction-workflow/SKILL.md"
SKILL="$WT/$SKILL_REL"
RUNNER="$WT/skills/skill-extraction-workflow/scripts/eval-routing-bank.rb"
BANK="$OUT/bank-single.jsonl"
TASK_ID="route-opencode-global-snapshot-audit"

A=' / 核查全局安装点（~/.config/opencode 等）旧快照是否遮蔽本仓技能'
B=' / 本仓（ccl-skills 等共享技能仓）OpenCode 项目配置·命令治理'

for f in "$SKILL" "$RUNNER" "$WT/eval/routing-tasks.jsonl"; do
  [ -f "$f" ] || { echo "FATAL: missing $f" >&2; exit 2; }
done
mkdir -p "$OUT" || exit 2

# 前置 1：目标文件必须干净。脏树下跑本脚本会在复原时吞掉别人的改动。
if ! git -C "$WT" diff --quiet -- "$SKILL_REL" || ! git -C "$WT" diff --cached --quiet -- "$SKILL_REL"; then
  echo "FATAL: $SKILL_REL 有未提交改动；先提交或 stash 再跑（本脚本拒绝在脏目标上做突变）" >&2
  exit 2
fi

# 前置 2：原始字节自己留一份，复原走它，不走 git checkout——
# 这样即便脚本被中断，恢复的也正是本次读到的内容。
ORIG="$(mktemp)"; cp "$SKILL" "$ORIG" || exit 2
restore() { [ -f "$ORIG" ] && cp "$ORIG" "$SKILL"; }
trap 'restore; rm -f "$ORIG"' EXIT
trap 'restore; rm -f "$ORIG"; exit 130' INT
trap 'restore; rm -f "$ORIG"; exit 143' TERM

grep "\"$TASK_ID\"" "$WT/eval/routing-tasks.jsonl" > "$BANK" || { echo "FATAL: task $TASK_ID 不在冻结 bank 里" >&2; exit 2; }
[ "$(wc -l < "$BANK" | tr -d ' ')" = "1" ] || { echo "FATAL: 单用例 bank 应恰好 1 行" >&2; exit 2; }

apply() { # 逐字节删除给定跨度；任一跨度不存在即失败
  python3 - "$SKILL" "$@" <<'PY'
import sys
path, spans = sys.argv[1], sys.argv[2:]
s = open(path, encoding='utf-8').read()
for sp in spans:
    if sp not in s:
        print("FATAL: span not found:", sp[:40], file=sys.stderr); sys.exit(1)
    s = s.replace(sp, "", 1)
open(path, 'w', encoding='utf-8').write(s)
PY
}

run_arm() { # arm-name, spans...
  local arm="$1"; shift
  echo "=== ARM $arm ==="
  apply "$@" || return 1
  # 突变有效性：目标文件必须真的变了，否则这一臂没有判别力
  if git -C "$WT" diff --quiet -- "$SKILL_REL"; then
    echo "FATAL: mutation not applied for $arm" >&2; return 1
  fi
  local pass=0 i
  for i in 1 2 3 4 5; do
    local json="$OUT/$arm-run$i.json" log="$OUT/$arm-run$i.txt" rc
    ruby "$RUNNER" "$WT" --bank "$BANK" --timeout 120 --json "$json" > "$log" 2>&1
    rc=$?
    # fail-closed：退出码、报告存在性、单用例、零 grader-error、裁决可归账，缺一即整臂作废
    if [ "$rc" -ne 0 ]; then echo "FATAL: $arm run$i runner rc=$rc" >&2; return 1; fi
    local verdict
    verdict=$(python3 - "$json" <<'PY'
import json, sys
try: d = json.load(open(sys.argv[1]))
except Exception as e: print("INVALID", e); raise SystemExit(0)
if d.get("tasks") != 1: print("INVALID tasks!=1"); raise SystemExit(0)
if (d.get("error") or 0) != 0: print("INVALID grader_error"); raise SystemExit(0)
p, f, e = d.get("pass") or 0, d.get("fail") or 0, d.get("error") or 0
if p + f + e != 1: print("INVALID unaccounted"); raise SystemExit(0)
print("PASS" if p == 1 else "FAIL")
PY
)
    case "$verdict" in
      PASS) pass=$((pass+1)); echo "  run$i: PASS";;
      FAIL) echo "  run$i: FAIL";;
      *)    echo "FATAL: $arm run$i 报告不合格：$verdict" >&2; return 1;;
    esac
  done
  echo "ARM $arm pass_count=$pass/5"
  # 复原走本次捕获的原始字节，不走 git checkout：即便中途被打断，恢复的也正是读到的内容。
  restore || { echo "FATAL: restore failed" >&2; return 1; }
  git -C "$WT" diff --quiet -- "$SKILL_REL" && echo "restore clean: OK" || { echo "FATAL: restore dirty" >&2; return 1; }
}

rc=0
run_arm "del-AB" "$A" "$B" || rc=1
run_arm "del-B"  "$B"      || rc=1
echo "=== DONE rc=$rc ==="
exit "$rc"
