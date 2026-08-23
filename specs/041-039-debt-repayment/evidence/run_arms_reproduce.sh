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
  echo "FATAL: ${SKILL_REL} 有未提交改动；先提交或 stash 再跑（本脚本拒绝在脏目标上做突变）" >&2
  exit 2
fi

# 前置 2：原始字节自己留一份，复原走它，不走 git checkout——
# 这样即便脚本被中断，恢复的也正是本次读到的内容。
ORIG="$(mktemp)"; cp "$SKILL" "$ORIG" || exit 2
# 复原前先确认目标仍逐字节等于本脚本自己写下的内容。模型调用最长 120 秒，
# 期间若有人改了这个文件，无条件盖回旧快照就会静默吞掉那次并发编辑（评审 r3 第 12 条）。
MUTATED=""          # 每次 apply 之后由 run_arm 写入：此刻目标应有的 sha256
RESTORE_REFUSED=0   # 复原被拒过就置 1；置 1 后不再有任何一臂会启动
restore() {
  [ -f "$ORIG" ] || return 0
  if [ -n "$MUTATED" ]; then
    local now; now="$(shasum -a 256 "$SKILL" 2>/dev/null | cut -d' ' -f1)"
    if [ "$now" != "$MUTATED" ]; then
      echo "FATAL: ${SKILL_REL} 在本次运行期间被第三方修改（期望 ${MUTATED}，实得 ${now}）；" >&2
      echo "       不覆盖、保留现场。原始字节留在 ${ORIG}，请人工比对后处置。" >&2
      # 清掉 trap 是为了不让 EXIT 再跑一次 restore；同时**保留** ORIG 供人工比对，
      # 所以这里不能用带 rm 的那三个 trap。
      trap - EXIT INT TERM
      RESTORE_REFUSED=1
      return 1
    fi
  fi
  cp "$ORIG" "$SKILL" || return 1
  # 复原完成后清掉期望哈希：否则 EXIT trap 再跑一次 restore 会拿突变哈希
  # 去比一个已经复原的文件，误报成「被第三方修改」。
  MUTATED=""
}
trap 'restore; rm -f "$ORIG"' EXIT
trap 'restore; rm -f "$ORIG"; exit 130' INT
trap 'restore; rm -f "$ORIG"; exit 143' TERM

grep "\"$TASK_ID\"" "$WT/eval/routing-tasks.jsonl" > "$BANK" || { echo "FATAL: task ${TASK_ID} 不在冻结 bank 里" >&2; exit 2; }
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
  MUTATED="$(shasum -a 256 "$SKILL" | cut -d' ' -f1)"
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
      *)    echo "FATAL: ${arm} run${i} 报告不合格：${verdict}" >&2; return 1;;
    esac
  done
  echo "ARM $arm pass_count=$pass/5"
  # 复原走本次捕获的原始字节，不走 git checkout：即便中途被打断，恢复的也正是读到的内容。
  restore || { echo "FATAL: restore failed" >&2; return 1; }
  git -C "$WT" diff --quiet -- "$SKILL_REL" && echo "restore clean: OK" || { echo "FATAL: restore dirty" >&2; return 1; }
}

# 一臂失败即整体中止：若第一臂的复原被拒（目标被第三方改过），继续跑第二臂会让
# 它在那个并发版本上再突变一次，其后的复原又把 run 前的 ORIG 盖上去——第一次
# 拒绝保住的并发编辑会被第二臂静默删掉（加时轮 h1 第 1 条）。
run_arm "del-AB" "$A" "$B" || { echo "=== ABORTED at del-AB ===" >&2; exit 1; }
run_arm "del-B"  "$B"      || { echo "=== ABORTED at del-B ===" >&2; exit 1; }
echo "=== DONE rc=0 ==="
exit 0
