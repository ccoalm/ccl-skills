#!/usr/bin/env bash
# 043：`source-refuted` 证据类的冻结验收用例（specs/043-evidence-class-source-refuted/frozen-acceptance.md）。
#
# A-F 在闸被触碰之前冻结；G/H 由独立评审与挑战各指出一处滥用路径后补入（**加严**，
# 不是放宽）。通过条件是全部命中——任何一条不符即本轮
# 未完成，**不得**以"主要目标达成"结案，也不得为让 A 变绿而放宽 B–F。
#
# 全部确定性，不调模型。每用例一条分支，互不影响本地未提交改动。
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
GATE="$ROOT/skills/skill-extraction-workflow/scripts/impact-chain-gate.rb"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT INT TERM
fails=0
fail() { echo "FAIL: $*" >&2; fails=$((fails+1)); }
ok()   { echo "  ok   $*"; }

REPO="$TMP/repo"
git clone -q "$ROOT" "$REPO"
git -C "$REPO" config user.email test@example.invalid
git -C "$REPO" config user.name "Test User"

OWNER_REF="skills/product-rd-workflow/SKILL.md"
REGISTER="skills/skill-extraction-workflow/references/source-register.md"
ZLOSS="specs/043-evidence-class-source-refuted/zero-loss-fixture.md"

# 种子：给 owner 的 reference 加一段可被后续用例整段删掉的文本（保证净字节 < 0），
# 以及一份非空的零损失义务对照 fixture。
WITHDRAWN_TEXT='A fixture claim that a later case withdraws wholesale; it is long enough that removing it makes the owner package shrink by a clear margin.'
mkdir -p "$REPO/$(dirname "$ZLOSS")"
printf '# 零损失义务对照\n\n被撤回的原文（逐字）：\n\n> %s\n\n| before 义务 | 去向 |\n| --- | --- |\n| 该段承载的义务 | survives-verbatim: 同文件上一段 |\n' "$WITHDRAWN_TEXT" > "$REPO/$ZLOSS"
printf '\n%s\n' "$WITHDRAWN_TEXT" >> "$REPO/$OWNER_REF"
printf '\n<!-- fixture-withdrawable-start -->\nA fixture claim that a later case withdraws wholesale; it is long enough that removing it makes the owner package shrink by a clear margin, which is what the net-bytes floor checks.\n<!-- fixture-withdrawable-end -->\n' >> "$REPO/$OWNER_REF"
git -C "$REPO" add -A >/dev/null
git -C "$REPO" commit -qm "seed fixtures for source-refuted cases"
git -C "$REPO" branch fixture-base HEAD

new_case() { git -C "$REPO" switch -q -C "$1" fixture-base; git -C "$REPO" branch --set-upstream-to=fixture-base "$1" >/dev/null 2>&1; }
commit_case() { git -C "$REPO" add -A >/dev/null; git -C "$REPO" commit -qm "$1"; }
run_gate() { set +e; OUT="$(env -u CCL_SKILL_BASE_REF ruby "$GATE" "$REPO" 2>&1)"; RC=$?; set -e 2>/dev/null || true; }
add_row() { printf '%s\n' "$1" >> "$REPO/$REGISTER"; }
withdraw_fixture() {  # **纯删除**：只删那一行，不加任何内容。说明文字进 reference。
  python3 - "$REPO/$OWNER_REF" "$WITHDRAWN_TEXT" <<'PYX'
import io,sys
p, txt = sys.argv[1], sys.argv[2]
s = io.open(p, encoding='utf-8').read()
io.open(p, 'w', encoding='utf-8').write(s.replace("\n" + txt + "\n", "\n", 1))
PYX
}

SRC="https://example.invalid/primary-source-that-refutes-the-claim"
FIRING="firing-path: file:skills/product-rd-workflow/SKILL.md#must survive verbatim above"
FIRING_F="firing-path: file:skills/product-rd-workflow/SKILL.md#must record a RED-baseline row before it lands"

# ---- A：合规撤回 —— 有类时必须绿，无类时必须红 ----
new_case case-a; withdraw_fixture
add_row "| A fixture claim is refuted by its primary source and is withdrawn wholesale | \`downstream-executor\` | behavioral-evidence: source-refuted; observed-failure: no; result-class: failure | \`updated\` | zero-loss: \`$ZLOSS#零损失义务对照\`; refuting source: $SRC; \`product-rd-workflow/SKILL.md\` |"
commit_case "case A: compliant source-refuted withdrawal"; run_gate
# A 的期望值在裁决后由绿改红：该类不再顶起 RED 底线（见 frozen-acceptance.md 的裁决记录）。
# 合规撤回现在仍然被拦——它要么配一条 RED 行，要么由具名风险 owner 人工放行。
[ "$RC" != "0" ] && ok "A 合规撤回 -> 仍红（该类不顶底线，撤回需人工放行）" || fail "A 不得自动放行"

# ---- B：真行为变更披该标签 —— 任何时候都必须红 ----
new_case case-b
printf '\n- Every fixture change must obtain approval before it lands.\n' >> "$REPO/$OWNER_REF"
add_row "| A newly added normative rule wearing the withdrawal label | \`downstream-executor\` | behavioral-evidence: source-refuted; observed-failure: no; result-class: failure | \`updated\` | zero-loss: \`$ZLOSS#零损失义务对照\`; refuting source: $SRC; \`product-rd-workflow/SKILL.md\` |"
commit_case "case B: real behaviour change wearing the label"; run_gate
[ "$RC" != "0" ] && ok "B 真行为变更披标签 -> 仍红" || fail "B 不得通过（净增却用撤回类）"

# ---- C：缺一手源 URL —— 必须红 ----
new_case case-c; withdraw_fixture
add_row "| A withdrawal whose row cites no refuting source | \`downstream-executor\` | behavioral-evidence: source-refuted; observed-failure: no; result-class: failure | \`updated\` | zero-loss: \`$ZLOSS#零损失义务对照\`; \`product-rd-workflow/SKILL.md\` |"
commit_case "case C: missing refuting source"; run_gate
[ "$RC" != "0" ] && ok "C 缺一手源 -> 仍红" || fail "C 不得通过（无源即无据）"

# ---- D：缺零损失指针 —— 必须红 ----
new_case case-d; withdraw_fixture
add_row "| A withdrawal whose row carries no zero-loss map | \`downstream-executor\` | behavioral-evidence: source-refuted; observed-failure: no; result-class: failure | \`updated\` | refuting source: $SRC; \`product-rd-workflow/SKILL.md\` |"
commit_case "case D: missing zero-loss pointer"; run_gate
[ "$RC" != "0" ] && ok "D 缺零损失指针 -> 仍红" || fail "D 不得通过（义务保全无对照）"

# ---- E：observed-failure: yes; result-class: failure —— 必须红 ----
new_case case-e; withdraw_fixture
add_row "| A withdrawal self-declaring an observed failure | \`downstream-executor\` | behavioral-evidence: source-refuted; observed-failure: yes; result-class: failure | \`updated\` | zero-loss: \`$ZLOSS#零损失义务对照\`; refuting source: $SRC; \`product-rd-workflow/SKILL.md\` |"
commit_case "case E: observed-failure yes"; run_gate
[ "$RC" != "0" ] && ok "E observed-failure: yes; result-class: failure -> 仍红" || fail "E 不得通过（分类语义不得自选）"

# ---- F：既有类不得回归 ----
new_case case-f
printf '\n- Every fixture delivery must record a RED-baseline row before it lands.\n' >> "$REPO/$OWNER_REF"
add_row "| An ordinary behaviour-changing rule with a RED-baseline row | \`downstream-executor\` | behavioral-evidence: RED-baseline; observed-failure: yes; result-class: failure; $FIRING_F | \`updated\` | \`product-rd-workflow/SKILL.md\` |"
commit_case "case F: existing RED-baseline path"; run_gate
if [ "$RC" = "0" ]; then ok "F 既有 RED-baseline 路径 -> 绿（无回归）"; else echo "--- F 完整输出 ---"; printf '%s\n' "$OUT"; fail "F 回归"; fi

# ---- G：混合行 —— 同 owner 一条合规撤回 + 一条真行为变更的 semantic-control。必须红 ----
#      独立评审 REVIEW-1：any? 顶起底线时，真行为变更会搭便车。
new_case case-g; withdraw_fixture
printf '\n- Every unrelated fixture delivery must obtain approval before it lands. zzmixedrule\n' >> "$REPO/$OWNER_REF"
add_row "| A compliant withdrawal alongside an unrelated change | \`downstream-executor\` | behavioral-evidence: source-refuted; observed-failure: no; result-class: failure | \`updated\` | zero-loss: \`$ZLOSS#零损失义务对照\`; refuting source: $SRC; \`product-rd-workflow/SKILL.md\` |"
add_row "| An unrelated behaviour change riding along on a stable-control label | \`downstream-executor\` | behavioral-evidence: semantic-control; observed-failure: no; result-class: failure; firing-path: file:skills/product-rd-workflow/SKILL.md#must obtain approval before it lands | \`updated\` | \`product-rd-workflow/SKILL.md\` |"
commit_case "case G: mixed rows"; run_gate
[ "$RC" != "0" ] && ok "G 混合行 -> 仍红" || fail "G 不得通过（真行为变更搭撤回的便车）"

# ---- H：抵消式新增 + 假锚点 —— 必须红 ----
#      独立挑战 CHALLENGE-1：删无关文字凑净负、加一条新规则、指针写不存在的锚。
new_case case-h; withdraw_fixture
printf '\n- Every smuggled fixture rule must be rejected by the withdrawal class. zzsmuggled\n' >> "$REPO/$OWNER_REF"
add_row "| A smuggled rule hidden behind an offsetting deletion | \`downstream-executor\` | behavioral-evidence: source-refuted; observed-failure: no; result-class: failure | \`updated\` | zero-loss: \`README.md#no-such-anchor-exists-here\`; refuting source: $SRC; \`product-rd-workflow/SKILL.md\` |"
commit_case "case H: offset addition with bogus anchor"; run_gate
[ "$RC" != "0" ] && ok "H 抵消式新增 + 假锚点 -> 仍红" || fail "H 不得通过（新增规范行 / 锚点不解析）"

# ---- I：脚本改动、零删除 —— 必须红（旧代理谓词看不见脚本）----
new_case case-i
printf '\n# fixture: an added shell line that changes behaviour without matching any prose predicate\n' >> "$REPO/skills/product-rd-workflow/scripts/check-agent-contract-coverage.sh"
add_row "| A script change wearing the withdrawal label with nothing deleted | \`downstream-executor\` | behavioral-evidence: source-refuted; observed-failure: no; result-class: failure | \`updated\` | zero-loss: \`$ZLOSS#零损失义务对照\`; refuting source: $SRC; \`product-rd-workflow/SKILL.md\` |"
commit_case "case I: script change, no deletion"; run_gate
[ "$RC" != "0" ] && ok "I 脚本改动零删除 -> 仍红" || fail "I 不得通过（非 .md、且无删除）"

# ---- J：`Always` 规则、零删除 —— 必须红（旧谓词故意排除 always）----
new_case case-j
printf '\n- Always authenticate fixture requests before dispatch.\n' >> "$REPO/$OWNER_REF"
add_row "| An Always-phrased rule wearing the withdrawal label with nothing deleted | \`downstream-executor\` | behavioral-evidence: source-refuted; observed-failure: no; result-class: failure | \`updated\` | zero-loss: \`$ZLOSS#零损失义务对照\`; refuting source: $SRC; \`product-rd-workflow/SKILL.md\` |"
commit_case "case J: Always rule, no deletion"; run_gate
[ "$RC" != "0" ] && ok "J Always 规则零删除 -> 仍红" || fail "J 不得通过（有新增行）"

# ---- K：改权限 + 一次真删除 —— 必须红 ----
#      独立评审：chmod 在 --name-status 里显示为 M、在 --numstat 里记 0/0。
new_case case-k; withdraw_fixture
chmod 755 "$REPO/skills/product-rd-workflow/references/adr-convention.md"
add_row "| A mode change riding along with a genuine deletion | \`downstream-executor\` | behavioral-evidence: source-refuted; observed-failure: no; result-class: failure | \`updated\` | zero-loss: \`$ZLOSS#零损失义务对照\`; refuting source: $SRC; \`product-rd-workflow/SKILL.md\` |"
commit_case "case K: chmod plus deletion"; run_gate
[ "$RC" != "0" ] && ok "K 改权限 + 删除 -> 仍红" || fail "K 不得通过（mode 变更未被 numstat 反映）"

# ---- L：指针路径穿越出仓 —— 必须红 ----
new_case case-l; withdraw_fixture
add_row "| A withdrawal whose zero-loss pointer escapes the repository | \`downstream-executor\` | behavioral-evidence: source-refuted; observed-failure: no; result-class: failure | \`updated\` | zero-loss: \`../../../etc/hosts#localhost\`; refuting source: $SRC; \`product-rd-workflow/SKILL.md\` |"
commit_case "case L: traversal pointer"; run_gate
[ "$RC" != "0" ] && ok "L 指针穿越出仓 -> 仍红" || fail "L 不得通过（路径逃出仓库）"

# ---- M：锚点是存在但无意义的单字符子串 —— 必须红 ----
new_case case-m; withdraw_fixture
add_row "| A withdrawal whose anchor is a bare existing substring | \`downstream-executor\` | behavioral-evidence: source-refuted; observed-failure: no; result-class: failure | \`updated\` | zero-loss: \`$ZLOSS#a\`; refuting source: $SRC; \`product-rd-workflow/SKILL.md\` |"
commit_case "case M: one-character substring anchor"; run_gate
[ "$RC" != "0" ] && ok "M 单字符子串锚 -> 仍红" || fail "M 不得通过（锚点未落在标题上）"

# ---- N：锚点是存在但不相干的整词 —— 必须红 ----
new_case case-n; withdraw_fixture
add_row "| A withdrawal whose anchor is an unrelated existing word | \`downstream-executor\` | behavioral-evidence: source-refuted; observed-failure: no; result-class: failure | \`updated\` | zero-loss: \`$ZLOSS#survives-verbatim\`; refuting source: $SRC; \`product-rd-workflow/SKILL.md\` |"
commit_case "case N: unrelated existing substring anchor"; run_gate
[ "$RC" != "0" ] && ok "N 不相干整词锚 -> 仍红" || fail "N 不得通过（锚点未落在标题上）"

# ---- O：既有 semantic-control 路径不得回归（配对 RED 行）----
new_case case-o
printf '\n- Every fixture control rule must be recorded before it lands. zzsemctl\n' >> "$REPO/$OWNER_REF"
add_row "| An unchanged control alongside a RED-baseline row | \`downstream-executor\` | behavioral-evidence: semantic-control; observed-failure: no; result-class: failure; firing-path: file:skills/product-rd-workflow/SKILL.md#must be recorded before it lands | \`updated\` | \`product-rd-workflow/SKILL.md\` |"
add_row "| The behaviour change the control accompanies | \`downstream-executor\` | behavioral-evidence: RED-baseline; observed-failure: yes; result-class: failure; firing-path: file:skills/product-rd-workflow/SKILL.md#must be recorded before it lands | \`updated\` | \`product-rd-workflow/SKILL.md\` |"
commit_case "case O: semantic-control beside RED-baseline"; run_gate
[ "$RC" = "0" ] && ok "O semantic-control + RED-baseline -> 绿（无回归）" || { echo "--- O ---"; printf '%s\n' "$OUT" | tail -3; fail "O 既有路径回归"; }

# ---- P：对照表没有逐字交代被删内容 —— 必须红 ----
new_case case-p; withdraw_fixture
python3 - "$REPO/$ZLOSS" <<'PYP'
import io,sys
p=sys.argv[1]
io.open(p,'w',encoding='utf-8').write("# 零损失义务对照\n\n| before 义务 | 去向 |\n| --- | --- |\n| 某条义务 | survives-verbatim: 别处 |\n")
PYP
add_row "| A withdrawal whose map does not quote what was removed | \`downstream-executor\` | behavioral-evidence: source-refuted; observed-failure: no; result-class: failure | \`updated\` | zero-loss: \`$ZLOSS#零损失义务对照\`; refuting source: $SRC; \`product-rd-workflow/SKILL.md\` |"
commit_case "case P: map does not account for deleted text"; run_gate
[ "$RC" != "0" ] && ok "P 对照表未逐字交代被删内容 -> 仍红" || fail "P 不得通过（删了什么没抄出来）"

echo
if [ "$fails" = "0" ]; then
  echo "all frozen cases behaved as specified"
else
  echo "frozen cases did not all behave as specified"
  exit 1
fi
