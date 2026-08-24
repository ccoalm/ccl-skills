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
mkdir -p "$REPO/$(dirname "$ZLOSS")"
printf '# 零损失义务对照（fixture）\n\n| before 义务 | 去向 |\n| --- | --- |\n| 撤回段落承载的义务 A | survives-verbatim: 同文件上一段 |\n' > "$REPO/$ZLOSS"
printf '\n<!-- fixture-withdrawable-start -->\nA fixture claim that a later case withdraws wholesale; it is long enough that removing it makes the owner package shrink by a clear margin, which is what the net-bytes floor checks.\n<!-- fixture-withdrawable-end -->\n' >> "$REPO/$OWNER_REF"
git -C "$REPO" add -A >/dev/null
git -C "$REPO" commit -qm "seed fixtures for source-refuted cases"
git -C "$REPO" branch fixture-base HEAD

new_case() { git -C "$REPO" switch -q -C "$1" fixture-base; git -C "$REPO" branch --set-upstream-to=fixture-base "$1" >/dev/null 2>&1; }
commit_case() { git -C "$REPO" add -A >/dev/null; git -C "$REPO" commit -qm "$1"; }
run_gate() { set +e; OUT="$(env -u CCL_SKILL_BASE_REF ruby "$GATE" "$REPO" 2>&1)"; RC=$?; set -e 2>/dev/null || true; }
add_row() { printf '%s\n' "$1" >> "$REPO/$REGISTER"; }
withdraw_fixture() {  # **纯删除**：撤回只删不加。新增任何规范规则行都会被第四道门槛拒绝，
                      # 说明文字该进 reference，不写在被撤回的那行旁边。
  python3 - "$REPO/$OWNER_REF" <<'PYX'
import io,re,sys
p=sys.argv[1]; s=io.open(p,encoding='utf-8').read()
s=re.sub(r"\n<!-- fixture-withdrawable-start -->.*?<!-- fixture-withdrawable-end -->\n",
         "\n",
         s,flags=re.S)
io.open(p,'w',encoding='utf-8').write(s)
PYX
}
SRC="https://example.invalid/primary-source-that-refutes-the-claim"
FIRING="firing-path: file:skills/product-rd-workflow/SKILL.md#must survive verbatim above"
FIRING_F="firing-path: file:skills/product-rd-workflow/SKILL.md#must record a RED-baseline row before it lands"

# ---- A：合规撤回 —— 有类时必须绿，无类时必须红 ----
new_case case-a; withdraw_fixture
add_row "| A fixture claim is refuted by its primary source and is withdrawn wholesale | \`downstream-executor\` | behavioral-evidence: source-refuted; observed-failure: no | \`updated\` | zero-loss: \`$ZLOSS#零损失义务对照\`; refuting source: $SRC; \`product-rd-workflow/SKILL.md\` |"
commit_case "case A: compliant source-refuted withdrawal"; run_gate
if [ "${EXPECT_A_GREEN:-1}" = "1" ]; then
  [ "$RC" = "0" ] && ok "A 合规撤回 -> 绿" || fail "A 应绿，实得 rc=$RC: $(printf '%s' "$OUT" | tail -2)"
else
  [ "$RC" != "0" ] && ok "A 合规撤回 -> 红（未实现类时的基线）" || fail "A 在未实现类时不该绿"
fi

# ---- B：真行为变更披该标签 —— 任何时候都必须红 ----
new_case case-b
printf '\n- Every fixture change must obtain approval before it lands.\n' >> "$REPO/$OWNER_REF"
add_row "| A newly added normative rule wearing the withdrawal label | \`downstream-executor\` | behavioral-evidence: source-refuted; observed-failure: no | \`updated\` | zero-loss: \`$ZLOSS#零损失义务对照\`; refuting source: $SRC; \`product-rd-workflow/SKILL.md\` |"
commit_case "case B: real behaviour change wearing the label"; run_gate
[ "$RC" != "0" ] && ok "B 真行为变更披标签 -> 仍红" || fail "B 不得通过（净增却用撤回类）"

# ---- C：缺一手源 URL —— 必须红 ----
new_case case-c; withdraw_fixture
add_row "| A withdrawal whose row cites no refuting source | \`downstream-executor\` | behavioral-evidence: source-refuted; observed-failure: no | \`updated\` | zero-loss: \`$ZLOSS#零损失义务对照\`; \`product-rd-workflow/SKILL.md\` |"
commit_case "case C: missing refuting source"; run_gate
[ "$RC" != "0" ] && ok "C 缺一手源 -> 仍红" || fail "C 不得通过（无源即无据）"

# ---- D：缺零损失指针 —— 必须红 ----
new_case case-d; withdraw_fixture
add_row "| A withdrawal whose row carries no zero-loss map | \`downstream-executor\` | behavioral-evidence: source-refuted; observed-failure: no | \`updated\` | refuting source: $SRC; \`product-rd-workflow/SKILL.md\` |"
commit_case "case D: missing zero-loss pointer"; run_gate
[ "$RC" != "0" ] && ok "D 缺零损失指针 -> 仍红" || fail "D 不得通过（义务保全无对照）"

# ---- E：observed-failure: yes —— 必须红 ----
new_case case-e; withdraw_fixture
add_row "| A withdrawal self-declaring an observed failure | \`downstream-executor\` | behavioral-evidence: source-refuted; observed-failure: yes | \`updated\` | zero-loss: \`$ZLOSS#零损失义务对照\`; refuting source: $SRC; \`product-rd-workflow/SKILL.md\` |"
commit_case "case E: observed-failure yes"; run_gate
[ "$RC" != "0" ] && ok "E observed-failure: yes -> 仍红" || fail "E 不得通过（分类语义不得自选）"

# ---- F：既有类不得回归 ----
new_case case-f
printf '\n- Every fixture delivery must record a RED-baseline row before it lands.\n' >> "$REPO/$OWNER_REF"
add_row "| An ordinary behaviour-changing rule with a RED-baseline row | \`downstream-executor\` | behavioral-evidence: RED-baseline; observed-failure: yes; $FIRING_F | \`updated\` | \`product-rd-workflow/SKILL.md\` |"
commit_case "case F: existing RED-baseline path"; run_gate
if [ "$RC" = "0" ]; then ok "F 既有 RED-baseline 路径 -> 绿（无回归）"; else echo "--- F 完整输出 ---"; printf '%s\n' "$OUT"; fail "F 回归"; fi

# ---- G：混合行 —— 同 owner 一条合规撤回 + 一条真行为变更的 semantic-control。必须红 ----
#      独立评审 REVIEW-1：any? 顶起底线时，真行为变更会搭便车。
new_case case-g; withdraw_fixture
printf '\n- Every unrelated fixture delivery must obtain approval before it lands. zzmixedrule\n' >> "$REPO/$OWNER_REF"
add_row "| A compliant withdrawal alongside an unrelated change | \`downstream-executor\` | behavioral-evidence: source-refuted; observed-failure: no | \`updated\` | zero-loss: \`$ZLOSS#零损失义务对照\`; refuting source: $SRC; \`product-rd-workflow/SKILL.md\` |"
add_row "| An unrelated behaviour change riding along on a stable-control label | \`downstream-executor\` | behavioral-evidence: semantic-control; observed-failure: no; firing-path: file:skills/product-rd-workflow/SKILL.md#must obtain approval before it lands | \`updated\` | \`product-rd-workflow/SKILL.md\` |"
commit_case "case G: mixed rows"; run_gate
[ "$RC" != "0" ] && ok "G 混合行 -> 仍红" || fail "G 不得通过（真行为变更搭撤回的便车）"

# ---- H：抵消式新增 + 假锚点 —— 必须红 ----
#      独立挑战 CHALLENGE-1：删无关文字凑净负、加一条新规则、指针写不存在的锚。
new_case case-h; withdraw_fixture
printf '\n- Every smuggled fixture rule must be rejected by the withdrawal class. zzsmuggled\n' >> "$REPO/$OWNER_REF"
add_row "| A smuggled rule hidden behind an offsetting deletion | \`downstream-executor\` | behavioral-evidence: source-refuted; observed-failure: no | \`updated\` | zero-loss: \`README.md#no-such-anchor-exists-here\`; refuting source: $SRC; \`product-rd-workflow/SKILL.md\` |"
commit_case "case H: offset addition with bogus anchor"; run_gate
[ "$RC" != "0" ] && ok "H 抵消式新增 + 假锚点 -> 仍红" || fail "H 不得通过（新增规范行 / 锚点不解析）"

# ---- I：脚本改动、零删除 —— 必须红（旧代理谓词看不见脚本）----
new_case case-i
printf '\n# fixture: an added shell line that changes behaviour without matching any prose predicate\n' >> "$REPO/skills/product-rd-workflow/scripts/check-agent-contract-coverage.sh"
add_row "| A script change wearing the withdrawal label with nothing deleted | \`downstream-executor\` | behavioral-evidence: source-refuted; observed-failure: no | \`updated\` | zero-loss: \`$ZLOSS#零损失义务对照\`; refuting source: $SRC; \`product-rd-workflow/SKILL.md\` |"
commit_case "case I: script change, no deletion"; run_gate
[ "$RC" != "0" ] && ok "I 脚本改动零删除 -> 仍红" || fail "I 不得通过（非 .md、且无删除）"

# ---- J：`Always` 规则、零删除 —— 必须红（旧谓词故意排除 always）----
new_case case-j
printf '\n- Always authenticate fixture requests before dispatch.\n' >> "$REPO/$OWNER_REF"
add_row "| An Always-phrased rule wearing the withdrawal label with nothing deleted | \`downstream-executor\` | behavioral-evidence: source-refuted; observed-failure: no | \`updated\` | zero-loss: \`$ZLOSS#零损失义务对照\`; refuting source: $SRC; \`product-rd-workflow/SKILL.md\` |"
commit_case "case J: Always rule, no deletion"; run_gate
[ "$RC" != "0" ] && ok "J Always 规则零删除 -> 仍红" || fail "J 不得通过（有新增行）"

# ---- K：改权限 + 一次真删除 —— 必须红 ----
#      独立评审：chmod 在 --name-status 里显示为 M、在 --numstat 里记 0/0。
new_case case-k; withdraw_fixture
chmod 755 "$REPO/skills/product-rd-workflow/references/adr-convention.md"
add_row "| A mode change riding along with a genuine deletion | \`downstream-executor\` | behavioral-evidence: source-refuted; observed-failure: no | \`updated\` | zero-loss: \`$ZLOSS#零损失义务对照\`; refuting source: $SRC; \`product-rd-workflow/SKILL.md\` |"
commit_case "case K: chmod plus deletion"; run_gate
[ "$RC" != "0" ] && ok "K 改权限 + 删除 -> 仍红" || fail "K 不得通过（mode 变更未被 numstat 反映）"

echo
if [ "$fails" = "0" ]; then
  echo "all frozen cases behaved as specified"
else
  echo "frozen cases did not all behave as specified"
  exit 1
fi
