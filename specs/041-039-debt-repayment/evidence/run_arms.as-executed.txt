#!/usr/bin/env bash
# 041 批 2：槽位 2/9 双删臂 + 归因臂。按 preregister-slot-2-9-round2.md 执行。
set -uo pipefail

WT=/Users/asen/work/code/src/github.com/ccoalm/ccl-skills/.work/worktrees/041-039-debt-repayment
OUT=/private/tmp/claude-501/-Users-asen-work-code-src-github-com-ccoalm-ccl-skills/31f30275-a994-40b6-9a27-b07dd96786c5/scratchpad/arms
SKILL="$WT/skills/skill-extraction-workflow/SKILL.md"
BANK="$OUT/bank-single.jsonl"
mkdir -p "$OUT"

# 单用例 bank：route-opencode-global-snapshot-audit，逐字节取自冻结 bank
grep '"route-opencode-global-snapshot-audit"' "$WT/eval/routing-tasks.jsonl" > "$BANK"
test -s "$BANK" || { echo "FATAL: bank extraction empty"; exit 1; }
echo "bank line: $(wc -c < "$BANK") bytes"

A=' / 核查全局安装点（~/.config/opencode 等）旧快照是否遮蔽本仓技能'
B=' / 本仓（ccl-skills 等共享技能仓）OpenCode 项目配置·命令治理'

apply() { # $1 = arm name; deletes spans listed in $2..
  local arm="$1"; shift
  python3 - "$SKILL" "$@" <<'PY'
import sys
path, spans = sys.argv[1], sys.argv[2:]
s = open(path, encoding='utf-8').read()
for sp in spans:
    if sp not in s:
        print("FATAL: span not found:", sp[:40]); sys.exit(1)
    s = s.replace(sp, "", 1)
open(path, 'w', encoding='utf-8').write(s)
print("applied", len(spans), "span(s)")
PY
}

run_arm() {
  local arm="$1"; shift
  echo "=== ARM $arm ==="
  apply "$arm" "$@" || return 1
  # 突变有效性：description 行必须真的变了
  if git -C "$WT" diff --quiet -- skills/skill-extraction-workflow/SKILL.md; then
    echo "FATAL: mutation not applied for $arm"; return 1
  fi
  local pass=0
  for i in 1 2 3 4 5; do
    ruby "$WT/skills/skill-extraction-workflow/scripts/eval-routing-bank.rb" "$WT" \
      --bank "$BANK" --timeout 120 --json "$OUT/$arm-run$i.json" > "$OUT/$arm-run$i.txt" 2>&1
    line=$(grep -o '[0-9]*/[0-9]* pass' "$OUT/$arm-run$i.txt" | head -1)
    sel=$(python3 -c "import json,sys;d=json.load(open('$OUT/$arm-run$i.json'));r=d.get('results',d.get('tasks',[]));print(r[0].get('selected_skill') or r[0].get('selected') if r else 'NA')" 2>/dev/null || echo NA)
    echo "  run$i: $line  selected=$sel"
    case "$line" in 1/1*) pass=$((pass+1));; esac
  done
  echo "ARM $arm pass_count=$pass/5"
  git -C "$WT" checkout -- skills/skill-extraction-workflow/SKILL.md
  git -C "$WT" diff --quiet && echo "restore clean: OK" || echo "FATAL: restore dirty"
}

run_arm "del-AB" "$A" "$B"
run_arm "del-B" "$B"
echo "=== DONE ==="
