#!/usr/bin/env bash
# 045：给「被裁决方自审」的义务装机械触发器的验收用例
# （specs/045-self-adjudicated-obligation-trigger/plan.md 的 Acceptance matrix）。
#
# 044 轮撤回过度声称时，把若干义务降成了咨询项，连续五轮 challenge 返回同一类：
# 义务的入口条件由被约束方自己陈述，且**跳过时不产生可检测的缺席**。本套件钉的是
# 那个缺席现在可被机械检出。
#
# 两个触发器都键在 diff 的客观事实上，不是散文语义：
#   A  改了 routing 面（SKILL.md 的 frontmatter description，或 eval/routing-tasks.jsonl）
#      ⇒ 该 owner 的台账行必须带 bank-evidence locator，或带留痕的 downscoped token。
#   B  带 behavioral-evidence 的新增台账行 ⇒ 必须带合法 result-class。
#
# 期望红的用例都必须点名 WHICH refusal：rc 单独是弱 oracle，为无关原因（fixture 缺陷、
# 锚点断掉）红同样是 rc=1，会把「形态已关闭」读成绿。
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
GATE="$ROOT/skills/skill-extraction-workflow/scripts/impact-chain-gate.rb"
LEDGER_REL="skills/skill-extraction-workflow/references/source-register.md"
BANK_REL="eval/routing-tasks.jsonl"
PLAN_REL="specs/045-self-adjudicated-obligation-trigger/plan.md"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT INT TERM

REPO="$TMP/repo"
git clone -q "$ROOT" "$REPO"
git -C "$REPO" config user.email test@example.invalid
git -C "$REPO" config user.name "Test User"
# A base WITHOUT the declaration, built by REMOVING it rather than by hoping the
# clone happens not to have it. Once this round is committed, `git clone "$ROOT"`
# carries the declaration, so a fixture that read the clone's HEAD as "before the
# grammar" passed from an uncommitted worktree and failed in CI — green meaning
# "not yet committed", which is the class of false green this suite exists for.
ORIG_HEAD="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" switch -q -C nogrammar-base "$ORIG_HEAD"
python3 - "$REPO/$LEDGER_REL" <<'STRIP'
import io, sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
io.open(p, "w", encoding="utf-8").write(
    "".join(l for l in s.splitlines(keepends=True)
            if "result-class: failure|stable-success|insufficient-evidence" not in l))
STRIP
git -C "$REPO" add -A >/dev/null
git -C "$REPO" commit -qm "fixture base predating the 045 declaration"
PRE_GRAMMAR="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" switch -q -C fixture-seed "$ORIG_HEAD"
# Both triggers only fire for a round whose HEAD ledger declares the grammar, so
# the fixture base must carry that declaration. Seeded explicitly rather than
# inherited from the clone: `git clone` copies commits, so relying on the working
# tree would make the suite pass or fail depending on whether the author had
# committed yet — a green that means "not yet judged".
# A dedicated package for the rename case, so A18 does not have to rename a REAL
# owner and drag the whole rename machinery (and its own refusals) into the leg.
mkdir -p "$REPO/skills/fixture-rename-src"
printf -- '---\nname: fixture-rename-src\ndescription: A fixture routing surface that a later case renames and rewords at once.\n---\n\n# Fixture\n\n- Baseline rule present before any case.\n' > "$REPO/skills/fixture-rename-src/SKILL.md"
printf '\n%s\n' 'Fixture grammar declaration: result-class: failure|stable-success|insufficient-evidence' \
  >> "$REPO/$LEDGER_REL"
git -C "$REPO" add -A >/dev/null
git -C "$REPO" commit -qm "seed grammar declaration for the 045 triggers"
git -C "$REPO" branch -f fixture-base HEAD >/dev/null

OWNER="product-rd-workflow"
NON_CURATED_OWNER="terminal-cli-dev"
NON_CURATED_OWNER2="web-react-dev"

new_case() { git -C "$REPO" switch -q -C "$1" fixture-base; }
commit_case() { git -C "$REPO" add -A >/dev/null; git -C "$REPO" commit -qm "$1"; }

anchor() { printf 'SELF-ADJUDICATION-FIXTURE-%s' "$1"; }

# A normative list rule the firing path can anchor on. Same shape the attribution
# suite uses: the anchor must land on a CHANGED list line carrying a normative verb.
add_owner_rule() { # <marker>
  printf -- '- Rule %s must be recorded before the round lands.\n' "$(anchor "$1")" \
    >> "$REPO/skills/$OWNER/SKILL.md"
}

# Edit the frontmatter `description` — the routing surface trigger A keys on.
# Appending to the body is NOT this; case A6 pins that distinction.
# The marker written here is deliberately DISTINCT from the rule anchor: the
# firing-path locator requires its anchor to occur exactly once in the file, and
# reusing one token made every A case red on a fixture defect rather than on the
# behaviour under test — a rc=1 that looked like the gate working. A SUFFIX is not
# enough either: the locator counts substring hits, so `…-A1-DESC` still contains
# `…-A1`. The distinguishing part has to come before the shared stem.
edit_description_for_owner() { # <owner> <marker>
  python3 - "$REPO/skills/$1/SKILL.md" "$(anchor "DESC-$2")" <<'PY'
import io, re, sys
path, marker = sys.argv[1], sys.argv[2]
s = io.open(path, encoding="utf-8").read()
m = re.match(r"\A---\s*\n(.*?)\n---\s*\n", s, re.S)
front = m.group(1)
new_front = re.sub(r"(?m)^(description:.*)$", r"\1 " + marker, front, count=1)
io.open(path, "w", encoding="utf-8").write(s[:m.start(1)] + new_front + s[m.end(1):])
PY
}

edit_owner_description() { edit_description_for_owner "$OWNER" "$1"; }

touch_bank() { printf '{"utterance":"fixture %s","expected_owner":"%s"}\n' "$1" "$OWNER" >> "$REPO/$BANK_REL"; }

write_plan() { # <downscope-token or empty>
  mkdir -p "$REPO/$(dirname "$PLAN_REL")"
  {
    printf '# 045 fixture plan\n\n'
    printf -- '- Bank evidence anchor %s must be reachable from the ledger row.\n' "$(anchor BANKEV)"
    # An `[ -n ... ] && printf` tail returns 1 when the token is absent, and the
    # group's status is the script's under errexit — that silently truncated the
    # whole suite after its first leg. Spelled as an if so a no-token call is a
    # normal success, not a run that ends without saying it ended.
    if [ -n "${1:-}" ]; then
      printf -- '- Downscope downscoped:%s is recorded here, so skipping the bank run still leaves an artifact.\n' "$1"
    fi
  } > "$REPO/$PLAN_REL"
  return 0
}

# A row that satisfies every PRE-EXISTING requirement, so each case varies only
# the field under test. Extra evidence fragments are appended verbatim.
append_row() { # <marker> <lesson> <extra-behavior-fragments>
  printf '| %s | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; firing-path: file:skills/%s/SKILL.md#%s%s | `updated` | `%s/SKILL.md` fixture change |\n' \
    "$2" "$OWNER" "$(anchor "$1")" "$3" "$OWNER" >> "$REPO/$LEDGER_REL"
}

run_gate() {
  set +e
  out="$(env -u ALIAS_AUDIT_CMD CCL_SKILL_BASE_REF=fixture-base ruby "$GATE" "$REPO" 2>&1)"
  rc=$?
  set -e
}

legs_failed=0
report_leg() { # <leg-name> <expected-rc> <form-summary> [expected-token ...]
  local name="$1" want="$2" summary="$3" token
  shift 3
  if [ "$name" = "A13" ] && ! printf '%s' "$summary" | grep -qF '`-`'; then
    echo '  A13: RED (summary lost literal `-`)'
    legs_failed=$((legs_failed + 1))
    return
  fi
  if [ "$rc" != "$want" ]; then
    echo "  $name: RED (rc=$rc, want $want) — $summary"
    printf '%s\n' "$out" | sed 's/^/    | /'
    legs_failed=$((legs_failed + 1))
    return
  fi
  for token in "$@"; do
    if [ -n "$token" ] && ! printf '%s' "$out" | grep -qF "$token"; then
      echo "  $name: RED (rc matched but output is missing '$token') — $summary"
      printf '%s\n' "$out" | sed 's/^/    | /'
      legs_failed=$((legs_failed + 1))
      return
    fi
  done
  echo "  ok   $name — $summary"
}

RC_MISSING="impact_chain_bank_evidence_missing"
RC_CLASS="impact_chain_result_class_missing"

# ---- B：result 分类不可省略 ------------------------------------------------
# B1 带合法 result-class -> 通过
new_case case-b1; add_owner_rule B1; write_plan
append_row B1 'A fixture lesson whose row declares its result class' '; result-class: failure'
commit_case "B1"; run_gate
report_leg B1 0 "带合法 result-class 的行通过"

# B2 缺 result-class -> 红，且必须是这条拒绝
new_case case-b2; add_owner_rule B2; write_plan
append_row B2 'A fixture lesson whose row omits its result class' ''
commit_case "B2"; run_gate
report_leg B2 1 "缺 result-class 被拒（关闭「整格省略」这条绕过）" "$RC_CLASS"

# B3 result-class 值不在枚举 -> 红
new_case case-b3; add_owner_rule B3; write_plan
append_row B3 'A fixture lesson whose row invents a result class' '; result-class: probably-fine'
commit_case "B3"; run_gate
report_leg B3 1 "非枚举 result-class 被拒" "$RC_CLASS"

# B4 不带 behavioral-evidence 的行 + 无 owner 改动 -> 不触发
new_case case-b4; write_plan
printf '| A fixture row that declares nothing | `downstream-executor` | note only | `not-applicable` | supporting note |\n' \
  >> "$REPO/$LEDGER_REL"
commit_case "B4"; run_gate
report_leg B4 0 "非本闸的行不被拖进 result-class 义务（保持既有 bifurcation）"

# ---- A：routing 面改动必须带 bank 证据 -------------------------------------
# A1 改 description + 带可解析 bank-evidence -> 通过
new_case case-a1; add_owner_rule A1; edit_owner_description A1; write_plan
append_row A1 'A fixture lesson whose routing-surface change carries bank evidence' \
  "; result-class: failure; bank-evidence: file:$PLAN_REL#$(anchor BANKEV)"
commit_case "A1"; run_gate
report_leg A1 0 "改 description 且带 bank-evidence 通过"

# A2 改 description 但无 bank-evidence -> 红
new_case case-a2; add_owner_rule A2; edit_owner_description A2; write_plan
append_row A2 'A fixture lesson whose routing-surface change carries no bank evidence' '; result-class: failure'
commit_case "A2"; run_gate
report_leg A2 1 "改 description 却无 bank-evidence 被拒（关闭「不跑就没工件」）" "$RC_MISSING"

# A3 改 task-bank 但无 bank-evidence -> 红
new_case case-a3; add_owner_rule A3; touch_bank A3; write_plan
append_row A3 'A fixture lesson that edits the task bank without bank evidence' '; result-class: failure'
commit_case "A3"; run_gate
report_leg A3 1 "改 task-bank 却无 bank-evidence 被拒" "$RC_MISSING"

# A4 显式降范围且 token 留痕在 plan -> 通过
new_case case-a4; add_owner_rule A4; edit_owner_description A4; write_plan "DOWNSCOPE-A4"
append_row A4 'A fixture lesson that downscopes the bank run on the record' \
  '; result-class: failure; bank-evidence: downscoped:DOWNSCOPE-A4'
commit_case "A4"; run_gate
report_leg A4 0 "降范围带留痕 token 通过（降范围仍产生工件）"

# A5 降范围但 token 不在任何 plan -> 红
new_case case-a5; add_owner_rule A5; edit_owner_description A5; write_plan
append_row A5 'A fixture lesson that downscopes with no recorded reason' \
  '; result-class: failure; bank-evidence: downscoped:DOWNSCOPE-A5'
commit_case "A5"; run_gate
report_leg A5 1 "降范围 token 无留痕被拒（否则 downscoped: 就是新的自审出口）" "$RC_MISSING"

# A6 只改 SKILL.md 正文、未动 description -> 不触发
new_case case-a6; add_owner_rule A6; write_plan
append_row A6 'A fixture lesson that edits only the body' '; result-class: failure'
commit_case "A6"; run_gate
report_leg A6 0 "只改正文不触发 bank 义务（避免把正文编辑拖进来）"

# A7 bank-evidence 指回 owner 自己的包 -> 红
# 「工件存在」不等于「工件是证据」：description-only 的改动若能拿刚写下的那行当自己的
# bank 证据，闸就只是在核对一个自指的存在性。这条是本轮唯一一次收紧谓词，也正是本轮
# 要消灭的形态本身。
new_case case-a7; add_owner_rule A7; edit_owner_description A7; write_plan
append_row A7 'A fixture lesson citing its own package as bank evidence' \
  "; result-class: failure; bank-evidence: file:skills/$OWNER/SKILL.md#$(anchor A7)"
commit_case "A7"; run_gate
report_leg A7 1 "自指 bank-evidence 被拒（改动本身不是关于它的证据）" "$RC_MISSING"

# G1 该轮 head 的台账未声明该语法 -> 不被追溯约束
# 这是非追溯性的承重件：没有它，新增一个必填字段会在任何回放里追溯拒掉全部历史轮
# （实测 64 个集成点里 34 个），而 verdict-differential 套件会正确地把那报成回归。
# 判据不是日期也不是 commit id（那些是会漂的代理），是「该轮 head 自己有没有声明」。
git -C "$REPO" switch -q -C case-g1 "$PRE_GRAMMAR"
add_owner_rule G1; write_plan
append_row G1 'A fixture lesson landing before the grammar was declared' ''
commit_case "G1"
set +e
out="$(env -u ALIAS_AUDIT_CMD CCL_SKILL_BASE_REF="$PRE_GRAMMAR" ruby "$GATE" "$REPO" 2>&1)"; rc=$?
set -e
report_leg G1 0 "head 未声明该语法的轮不被追溯约束（否则加字段=判死全部历史轮）"

# A8 只改 task-bank、不动任何 owner -> 仍必须红
# 第一版按 owner 迭代，bank-only 的改动根本进不了循环：路由 bank 可以随便动而无任何证据。
# A3 之所以没抓到，是因为它顺手也改了 owner——洞就藏在那条绿用例后面。
new_case case-a8; write_plan; touch_bank A8
printf '| A fixture lesson that moves the routing bank alone | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; result-class: failure | `updated` | supporting note only |\n' \
  >> "$REPO/$LEDGER_REL"
commit_case "A8"; run_gate
report_leg A8 1 "只改 task-bank 也必须带 bank 证据（洞曾藏在 A3 的绿后面）" "$RC_MISSING"

# G2 声明过又被删掉 -> 红（不是「早于规则」，是关掉规则）
new_case case-g2; add_owner_rule G2; write_plan
python3 - "$REPO/$LEDGER_REL" <<'STRIP2'
import io, sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
io.open(p, "w", encoding="utf-8").write(
    "".join(l for l in s.splitlines(keepends=True)
            if "result-class: failure|stable-success|insufficient-evidence" not in l))
STRIP2
append_row G2 'A fixture lesson that quietly removes the declaration' '; result-class: failure'
commit_case "G2"; run_gate
report_leg G2 1 "把声明删掉不等于早于规则，是静默关闭" "impact_chain_grammar_withdrawn"

# A9 只改 task-bank 且**一行台账都不加** -> 仍必须红
# A8 仍然加了行，于是 rows 非空、scope 存在；真正无人守的是「既不动 owner、也不动台账」
# 那条路径——外层进入条件和按行分组的循环都会放它过去。绿用例第二次挡住了它要覆盖的洞。
new_case case-a9; touch_bank A9
commit_case "A9"; run_gate
report_leg A9 1 "只动 bank、零台账行也必须红（外层进入条件曾漏掉这条路径）" "$RC_MISSING"

# A10 两个 owner 各改 description，只有一个带证据 -> 必须红，且点名欠证据的那个
# 义务由每个移动了自己路由面的 owner 各自承担；按轮求值会让一个 owner 的合法 locator
# 把整轮标成已满足，另一个就可以完全省略。
OWNER2="testing-strategy"
new_case case-a10; add_owner_rule A10; edit_owner_description A10; write_plan
printf -- '- Rule %s must be recorded before the round lands.\n' "$(anchor A10B)" >> "$REPO/skills/$OWNER2/SKILL.md"
python3 - "$REPO/skills/$OWNER2/SKILL.md" "$(anchor DESC-A10B)" <<'PY2'
import io, re, sys
path, marker = sys.argv[1], sys.argv[2]
s = io.open(path, encoding="utf-8").read()
m = re.match(r"\A---\s*\n(.*?)\n---\s*\n", s, re.S)
front = m.group(1)
new_front = re.sub(r"(?m)^(description:.*)$", r"\1 " + marker, front, count=1)
io.open(path, "w", encoding="utf-8").write(s[:m.start(1)] + new_front + s[m.end(1):])
PY2
append_row A10 'A fixture lesson whose first owner carries the evidence' \
  "; result-class: failure; bank-evidence: file:$PLAN_REL#$(anchor BANKEV)"
printf '| A fixture lesson whose second owner carries none | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; result-class: failure; firing-path: file:skills/%s/SKILL.md#%s | `updated` | `%s/SKILL.md` fixture change |\n' \
  "$OWNER2" "$(anchor A10B)" "$OWNER2" >> "$REPO/$LEDGER_REL"
commit_case "A10"; run_gate
report_leg A10 1 "多 owner 轮里每个 owner 各自欠证据（一个的 locator 不能替另一个还）" "$OWNER2"

# A11 自指的 command: 形态 -> 也必须红
# 第一版禁令只匹配 `file:skills/<owner>/`。同轮里顺手改了自己包内的一个脚本，就能写成
# `command:skills/<owner>/scripts/x.sh` 让改动给自己作证。两种 locator 都是在指一条路径，
# 禁的是那条路径，不是那个前缀拼法。
new_case case-a11; add_owner_rule A11; edit_owner_description A11; write_plan
printf '#!/usr/bin/env bash\necho fixture\n' > "$REPO/skills/$OWNER/scripts/fixture_a11.sh"
chmod +x "$REPO/skills/$OWNER/scripts/fixture_a11.sh"
append_row A11 'A fixture lesson citing its own package executable as bank evidence' \
  "; result-class: failure; bank-evidence: command:skills/$OWNER/scripts/fixture_a11.sh"
commit_case "A11"; run_gate
report_leg A11 1 "自指的 command: 形态同样被拒（禁的是路径不是前缀拼法）" "$RC_MISSING"

# A12 跨轮不得串扰：轮1 只动 bank 且带证据，轮2 只动某 owner 的正文 -> 整体必须绿
# 曾经 routing_surface_touched 在 bank 变更时对**任何** owner 返回 true，于是轮1 会去要求
# 轮2 那个 owner 的行——把一个不相关的后续提交加进范围，就能改变对前一轮的判定。
# bank 是它自己的 subject，不是所有人的。
new_case case-a12; write_plan
touch_bank A12
printf '| A fixture round that moves the bank with evidence | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; result-class: failure; bank-evidence: file:%s#%s | `updated` | supporting note only |\n' \
  "$PLAN_REL" "$(anchor BANKEV)" >> "$REPO/$LEDGER_REL"
commit_case "A12 round 1: bank only, evidenced"
add_owner_rule A12
append_row A12 'A later unrelated round that edits only owner body text' '; result-class: failure'
commit_case "A12 round 2: unrelated owner body"
run_gate
report_leg A12 0 "跨轮不串扰（bank 是自己的 subject，不是所有 owner 的）"

# A13 退化的 downscope token -> 必须红
# `\S+` 曾接受 `-`，而 include? 会在任意 bullet 行的连字符上命中：`downscoped:-` 就能
# 拿一条什么都没说的记录清偿义务。降范围是要被人查到的决定，偶然出现在散文里的字符不是。
new_case case-a13; add_owner_rule A13; edit_owner_description A13; write_plan
append_row A13 'A fixture lesson downscoping with a degenerate token' \
  '; result-class: failure; bank-evidence: downscoped:-'
commit_case "A13"; run_gate
report_leg A13 1 '退化 token 不算留痕（`-` 会命中任意 bullet 的连字符）' "$RC_MISSING"

# B5 只动 bank 的轮里，声明行同样欠 result-class -> 必须红
# B 曾按变更 owner 收敛，而 bank-only 的轮没有变更 owner：那行声明行压根不被检查，
# 带着合法 bank-evidence 就整轮放行。非追溯性由 grammar 闸独立承担，B 不该再兼这份差事。
new_case case-b5; write_plan; touch_bank B5
printf '| A fixture bank-only round whose declaring row omits its class | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; bank-evidence: file:%s#%s | `updated` | supporting note only |\n' \
  "$PLAN_REL" "$(anchor BANKEV)" >> "$REPO/$LEDGER_REL"
commit_case "B5"; run_gate
report_leg B5 1 "bank-only 轮的声明行同样欠 result-class（owner 收敛曾把它整个跳过）" "$RC_CLASS"

# A14 自指的等价路径拼法 -> 也必须红
# 禁令若拿裸 start_with? 比一种拼法，`./skills/<owner>/…` 与 `a/../` 绕路指的是同一个文件
# 却躲过检查。禁的是位置，就得在位置的规范形上判。
new_case case-a14; add_owner_rule A14; edit_owner_description A14; write_plan
append_row A14 'A fixture lesson citing its own package by an equivalent spelling' \
  "; result-class: failure; bank-evidence: file:./skills/$OWNER/SKILL.md#$(anchor A14)"
commit_case "A14"; run_gate
report_leg A14 1 "等价路径拼法的自指同样被拒（在规范形上判位置）" "$RC_MISSING"

# A15 token 只是碰巧出现在别的行里 -> 必须红
# 只搜裸 token 时，一个常见英文词就能被无关行命中（`downscoped:evidence` 撞上
# 「Bank evidence anchor …」）。留痕要留的是那句声明本身，不是那个词。
new_case case-a15; add_owner_rule A15; edit_owner_description A15; write_plan
append_row A15 'A fixture lesson downscoping with an incidentally-occurring word' \
  '; result-class: failure; bank-evidence: downscoped:evidence'
commit_case "A15"; run_gate
report_leg A15 1 "token 碰巧出现不算留痕（必须逐字记录 downscoped:<token>）" "$RC_MISSING"

# A16 新技能的第一版 description -> 必须红（创建也是路由面变更）
# 「两侧都要存在」曾把创建一并排除，理由写作「保守」。评审点破：一个新技能的第一版
# description 恰恰决定了哪些请求会到它那里，是最大的一次路由面变更，不是可豁免项。
new_case case-a16; write_plan
mkdir -p "$REPO/skills/fixture-new-owner"
printf -- '---\nname: fixture-new-owner\ndescription: A brand new routing surface that decides which requests reach this skill.\n---\n\n# Fixture\n\n- Rule %s must be recorded before the round lands.\n' "$(anchor A16)" \
  > "$REPO/skills/fixture-new-owner/SKILL.md"
printf '| A fixture lesson introducing a new routing surface | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; result-class: failure; firing-path: file:skills/fixture-new-owner/SKILL.md#%s | `updated` | `fixture-new-owner/SKILL.md` fixture change |\n' \
  "$(anchor A16)" >> "$REPO/$LEDGER_REL"
commit_case "A16"; run_gate
report_leg A16 1 "新技能的第一版 description 也欠 bank 证据（创建不是豁免）" "$RC_MISSING"

# A17 降范围 token 的前缀碰撞 -> 必须红
# `include?` 让 spec 里的 `downscoped:TOKENLONGER` 满足行里的 `downscoped:TOKEN`——
# 别人的 token 顺手替这一行还了债。声明必须在 token 边界处结束。
new_case case-a17; add_owner_rule A17; edit_owner_description A17; write_plan "DOWNSCOPE-A17-LONGER"
append_row A17 'A fixture lesson whose token is a strict prefix of the recorded one' \
  '; result-class: failure; bank-evidence: downscoped:DOWNSCOPE-A17'
commit_case "A17"; run_gate
report_leg A17 1 "前缀碰撞不算留痕（声明须在 token 边界结束）" "$RC_MISSING"

# G3 删掉声明段、却把 marker 塞进一行台账 -> 仍必须按撤回处理
# 在整份 blob 上 include? 时，这样两边都读作「已声明」，撤回检测哑掉，之后每一轮
# 都继续被一个权威已不再陈述的语法判定。G2 抓不到它——它把所有含 marker 的行都删了。
new_case case-g3; add_owner_rule G3; write_plan
python3 - "$REPO/$LEDGER_REL" <<'STRIP3'
import io, sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
kept = [l for l in s.splitlines(keepends=True)
        if "result-class: failure|stable-success|insufficient-evidence" not in l]
kept.append("| A row that merely quotes result-class: failure|stable-success|insufficient-evidence | `x` | note | `not-applicable` | quote only |\n")
io.open(p, "w", encoding="utf-8").write("".join(kept))
STRIP3
append_row G3 'A fixture lesson hiding the marker inside a table row' '; result-class: failure'
commit_case "G3"; run_gate
report_leg G3 1 "marker 藏进台账行不算声明（行会引用，不会立法）" "impact_chain_grammar_withdrawn"

# A18 同一提交里改名 + 改 description -> 必须红
# 目标路径以「只是改名」被豁免、源路径以「没有 head 条目」被豁免，这次编辑就从两者之间
# 溜过去了。豁免给的是「description 没变」，不是「路径动过」。
new_case case-a18; write_plan
git -C "$REPO" mv skills/fixture-rename-src skills/fixture-rename-dst
python3 - "$REPO/skills/fixture-rename-dst/SKILL.md" "$(anchor A18)" <<'PY3'
import io, re, sys
path, marker = sys.argv[1], sys.argv[2]
s = io.open(path, encoding="utf-8").read()
m = re.match(r"\A---\s*\n(.*?)\n---\s*\n", s, re.S)
front = m.group(1)
new_front = re.sub(r"(?m)^(description:.*)$", r"\1 " + marker, front, count=1)
io.open(path, "w", encoding="utf-8").write(s[:m.start(1)] + new_front + s[m.end(1):])
PY3
printf -- '- Rule %s must be recorded before the round lands.\n' "$(anchor A18B)" >> "$REPO/skills/fixture-rename-dst/SKILL.md"
printf '| A fixture lesson renaming an owner and rewording its description at once | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; result-class: failure; firing-path: file:skills/fixture-rename-dst/SKILL.md#%s | `updated` | `fixture-rename-dst/SKILL.md` fixture change |\n' \
  "$(anchor A18B)" >> "$REPO/$LEDGER_REL"
commit_case "A18"; run_gate
report_leg A18 1 "改名同时改 description 不得从两侧豁免之间溜过去" "$RC_MISSING"

# G4 撤回的诊断只能点名本闸真正实现的补救
# 上一版写着「或由具名风险 owner 承担」，而代码里没有任何解析风险 owner 的路径，exit 1
# 是无条件的——一条落不了地的补救承诺，等于把合法的有意撤回堵死却假装有出路。
# 这条钉的是**诊断与实现一致**：不许再出现只存在于措辞里的出口。
new_case case-g4; add_owner_rule G4; write_plan
python3 - "$REPO/$LEDGER_REL" <<'STRIP4'
import io, sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
io.open(p, "w", encoding="utf-8").write(
    "".join(l for l in s.splitlines(keepends=True)
            if "result-class: failure|stable-success|insufficient-evidence" not in l))
STRIP4
append_row G4 'A fixture lesson withdrawing the declaration on purpose' '; result-class: failure'
commit_case "G4"; run_gate
if printf '%s' "$out" | grep -qi "named risk owner"; then
  echo "  G4: RED — 诊断仍在承诺一条本闸未实现的补救（named risk owner）"
  legs_failed=$((legs_failed + 1))
else
  report_leg G4 1 "撤回被拒，且诊断只点名真正实现的补救" "no data-side waiver"
fi

# A19 就地删掉 description 条目（文件保留）-> 必须红
# 「head 没有条目」曾被一律当作删除/改名走。可文件还在、只是不再声明路由面——那和改写它
# 一样是一次路由面变更，而且是让技能整个从路由里消失的那一种。
new_case case-a19; add_owner_rule A19; write_plan
python3 - "$REPO/skills/$OWNER/SKILL.md" <<'PY4'
import io, re, sys
path = sys.argv[1]
s = io.open(path, encoding="utf-8").read()
m = re.match(r"\A---\s*\n(.*?)\n---\s*\n", s, re.S)
front = m.group(1)
kept = [l for l in front.splitlines(keepends=True) if not l.startswith("description:")]
io.open(path, "w", encoding="utf-8").write(s[:m.start(1)] + "".join(kept).rstrip("\n") + s[m.end(1):])
PY4
append_row A19 'A fixture lesson deleting the description entry in place' '; result-class: failure'
commit_case "A19"; run_gate
report_leg A19 1 "就地删掉 description 也是路由面变更（文件还在，不是删除）" "$RC_MISSING"

# A20 非 curated owner 的 description 改动 + 唯一有效证据 -> 必须通过
# routing bank 约束所有技能的 description，但这不等于把该技能提升为 impact-chain owner。
# 行不声明 behavioral-evidence，专门证明 bank owner 解析与 impact-chain owner 解析彼此独立。
new_case case-a20; edit_description_for_owner "$NON_CURATED_OWNER" A20; write_plan
printf '| A fixture non-curated routing surface with bank evidence | `downstream-executor` | bank-evidence: file:%s#%s | `updated` | `%s/SKILL.md` fixture change |\n' "$PLAN_REL" "$(anchor BANKEV)" "$NON_CURATED_OWNER" >> "$REPO/$LEDGER_REL"
commit_case "A20"; run_gate
report_leg A20 0 "非 curated owner 的唯一 bank 证据可被解析，但不进入 impact-chain"

# A21 非 curated owner 的 description 改动 + 零台账行 -> 必须红
# 外层入口若只看 curated owner / ledger / bank，这一轮会完全不执行而静默通过。
new_case case-a21; edit_description_for_owner "$NON_CURATED_OWNER" A21
commit_case "A21"; run_gate
report_leg A21 1 "非 curated owner 改 description 且零台账行仍欠 bank 证据" \
  "$RC_MISSING" "owes bank evidence: $NON_CURATED_OWNER/SKILL.md"

# A22 一行同时绑定两个非 curated owner -> 不能替任一 owner 清偿
# owner 解析必须保持一行一 owner；否则一个 locator 会把同轮另一个 description 改动也标绿。
new_case case-a22
edit_description_for_owner "$NON_CURATED_OWNER" A22A
edit_description_for_owner "$NON_CURATED_OWNER2" A22B
write_plan
printf '| A fixture ambiguous non-curated routing row | `downstream-executor` | bank-evidence: file:%s#%s | `updated` | `%s/SKILL.md` and `%s/SKILL.md` fixture changes |\n' "$PLAN_REL" "$(anchor BANKEV)" "$NON_CURATED_OWNER" "$NON_CURATED_OWNER2" >> "$REPO/$LEDGER_REL"
commit_case "A22"; run_gate
report_leg A22 1 "一行不能替两个非 curated owner 清偿 bank 证据" \
  "$RC_MISSING" \
  "owes bank evidence: $NON_CURATED_OWNER/SKILL.md" \
  "owes bank evidence: $NON_CURATED_OWNER2/SKILL.md"

# A23 未知或已删除的 owner 路径在 bank resolver 前就必须被 missing-file 闸拒绝
# 独立 review 怀疑过滤会把双路径压成唯一 owner；实际调用路径先检查每个精确
# `<owner>/SKILL.md` 在该轮 head 是否存在，因此拼错/过期路径不能抵达 bank 清偿。
new_case case-a23; edit_description_for_owner "$NON_CURATED_OWNER" A23; write_plan
printf '| A fixture routing row with a stale owner alias | `downstream-executor` | bank-evidence: file:%s#%s | `updated` | `%s/SKILL.md` and `fixture-stale-owner/SKILL.md` fixture claims |\n' "$PLAN_REL" "$(anchor BANKEV)" "$NON_CURATED_OWNER" >> "$REPO/$LEDGER_REL"
commit_case "A23"; run_gate
report_leg A23 1 "未知 owner 路径在 bank 解析前被 evidence missing-file 闸拒绝" \
  "impact_chain_evidence_missing_file" "missing: fixture-stale-owner/SKILL.md"

# A24 Node implementation owner 的 description + 外部 bank 证据 -> 必须绿
SAVED_OWNER="$OWNER"
OWNER="nodejs-service-dev"
new_case case-a20; add_owner_rule A24; edit_owner_description A24; write_plan
append_row A24 'The Node implementation owner carries external bank evidence' \
  "; result-class: failure; bank-evidence: file:$PLAN_REL#$(anchor BANKEV)"
commit_case "A24"; run_gate
report_leg A24 0 "Node implementation owner 的 bank 证据可被 owner-scoped gate 消费"
OWNER="$SAVED_OWNER"

# A25 存量非 curated 技能改 description：义务存在，且经 bank-only 解析可清偿 -> 必须绿
# 前一轮曾把 created-surface pickup 限定在 base 不存在的技能，理由是「非 curated 的
# 义务行无法绑定、红无法清偿」；bank-only resolver 合入后该前提不再成立——本腿钉的
# 就是「可清偿」这一半：欠债的那一半由 A21 钉（零行必须红）。
new_case case-a21; add_owner_rule A25; write_plan
append_row A25 'A curated owner row rides along while an existing non-curated sibling edits its description' \
  '; result-class: failure'
SAVED_OWNER="$OWNER"
OWNER="web-react-dev"; edit_owner_description A25; OWNER="$SAVED_OWNER"
printf '| A fixture existing non-curated routing surface with bank evidence | `downstream-executor` | bank-evidence: file:%s#%s | `updated` | `web-react-dev/SKILL.md` fixture change |\n' "$PLAN_REL" "$(anchor BANKEV)" >> "$REPO/$LEDGER_REL"
commit_case "A25"; run_gate
report_leg A25 0 '存量非 curated owner 的 description 编辑欠 bank 证据且可被 bank-only 行清偿'

echo "impact_chain_self_adjudication: legs_failed=$legs_failed"
if [ "$legs_failed" -ne 0 ]; then
  echo "impact_chain_self_adjudication_failed=$legs_failed" >&2
  exit 1
fi
echo "impact_chain_self_adjudication_ok"
