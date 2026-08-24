#!/usr/bin/env bash
# 043：`source-refuted` 证据类的冻结验收用例（specs/043-evidence-class-source-refuted/frozen-acceptance.md）。
#
# 六条用例在闸被触碰之前就已冻结。通过条件是六条全中——任何一条不符即本轮
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
withdraw_fixture() {  # 改写式撤回：删掉假陈述、留一条带唯一 token 的规范行（真实形态）
  python3 - "$REPO/$OWNER_REF" <<'PYX'
import io,re,sys
p=sys.argv[1]; s=io.open(p,encoding='utf-8').read()
s=re.sub(r"\n<!-- fixture-withdrawable-start -->.*?<!-- fixture-withdrawable-end -->\n",
         "\n- The refuted fixture claim is withdrawn; every obligation it carried must survive verbatim above.\n",
         s,flags=re.S)
io.open(p,'w',encoding='utf-8').write(s)
PYX
}
SRC="https://example.invalid/primary-source-that-refutes-the-claim"
FIRING="firing-path: file:skills/product-rd-workflow/SKILL.md#must survive verbatim above"
FIRING_F="firing-path: file:skills/product-rd-workflow/SKILL.md#must record a RED-baseline row before it lands"

# ---- A：合规撤回 —— 有类时必须绿，无类时必须红 ----
new_case case-a; withdraw_fixture
add_row "| A fixture claim is refuted by its primary source and is withdrawn wholesale | \`downstream-executor\` | behavioral-evidence: source-refuted; observed-failure: no; $FIRING | \`updated\` | zero-loss: \`$ZLOSS#零损失义务对照-fixture\`; refuting source: $SRC; \`product-rd-workflow/SKILL.md\` |"
commit_case "case A: compliant source-refuted withdrawal"; run_gate
if [ "${EXPECT_A_GREEN:-0}" = "1" ]; then
  [ "$RC" = "0" ] && ok "A 合规撤回 -> 绿" || fail "A 应绿，实得 rc=$RC: $(printf '%s' "$OUT" | tail -2)"
else
  [ "$RC" != "0" ] && ok "A 合规撤回 -> 红（未实现类时的基线）" || fail "A 在未实现类时不该绿"
fi

# ---- B：真行为变更披该标签 —— 任何时候都必须红 ----
new_case case-b
printf '\n- Every fixture change must obtain approval before it lands.\n' >> "$REPO/$OWNER_REF"
add_row "| A newly added normative rule wearing the withdrawal label | \`downstream-executor\` | behavioral-evidence: source-refuted; observed-failure: no; $FIRING | \`updated\` | zero-loss: \`$ZLOSS#零损失义务对照-fixture\`; refuting source: $SRC; \`product-rd-workflow/SKILL.md\` |"
commit_case "case B: real behaviour change wearing the label"; run_gate
[ "$RC" != "0" ] && ok "B 真行为变更披标签 -> 仍红" || fail "B 不得通过（净增却用撤回类）"

# ---- C：缺一手源 URL —— 必须红 ----
new_case case-c; withdraw_fixture
add_row "| A withdrawal whose row cites no refuting source | \`downstream-executor\` | behavioral-evidence: source-refuted; observed-failure: no; $FIRING | \`updated\` | zero-loss: \`$ZLOSS#零损失义务对照-fixture\`; \`product-rd-workflow/SKILL.md\` |"
commit_case "case C: missing refuting source"; run_gate
[ "$RC" != "0" ] && ok "C 缺一手源 -> 仍红" || fail "C 不得通过（无源即无据）"

# ---- D：缺零损失指针 —— 必须红 ----
new_case case-d; withdraw_fixture
add_row "| A withdrawal whose row carries no zero-loss map | \`downstream-executor\` | behavioral-evidence: source-refuted; observed-failure: no; $FIRING | \`updated\` | refuting source: $SRC; \`product-rd-workflow/SKILL.md\` |"
commit_case "case D: missing zero-loss pointer"; run_gate
[ "$RC" != "0" ] && ok "D 缺零损失指针 -> 仍红" || fail "D 不得通过（义务保全无对照）"

# ---- E：observed-failure: yes —— 必须红 ----
new_case case-e; withdraw_fixture
add_row "| A withdrawal self-declaring an observed failure | \`downstream-executor\` | behavioral-evidence: source-refuted; observed-failure: yes; $FIRING | \`updated\` | zero-loss: \`$ZLOSS#零损失义务对照-fixture\`; refuting source: $SRC; \`product-rd-workflow/SKILL.md\` |"
commit_case "case E: observed-failure yes"; run_gate
[ "$RC" != "0" ] && ok "E observed-failure: yes -> 仍红" || fail "E 不得通过（分类语义不得自选）"

# ---- F：既有类不得回归 ----
new_case case-f
printf '\n- Every fixture delivery must record a RED-baseline row before it lands.\n' >> "$REPO/$OWNER_REF"
add_row "| An ordinary behaviour-changing rule with a RED-baseline row | \`downstream-executor\` | behavioral-evidence: RED-baseline; observed-failure: yes; $FIRING_F | \`updated\` | \`product-rd-workflow/SKILL.md\` |"
commit_case "case F: existing RED-baseline path"; run_gate
if [ "$RC" = "0" ]; then ok "F 既有 RED-baseline 路径 -> 绿（无回归）"; else echo "--- F 完整输出 ---"; printf '%s\n' "$OUT"; fail "F 回归"; fi

echo
[ "$fails" = "0" ] && echo "source_refuted_cases_ok (6/6)" || { echo "source_refuted_cases_FAILED ($fails)"; exit 1; }
