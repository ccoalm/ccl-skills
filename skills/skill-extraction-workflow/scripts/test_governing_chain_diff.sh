#!/usr/bin/env bash
# Executable spec for the row-set predicate in references/rule-consolidation.md,
# exercised through scripts/governing-chain-diff.py.
#
# Each case is one edit shape the prose predicate claims to classify. The suite
# is the reason the rule is reproducible rather than asserted: it pins BOTH
# directions — the shapes that must produce a row, and the shapes that must not,
# because a predicate that reports "owes a row" for everything would pass a
# one-directional suite while being useless.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
TOOL="$HERE/governing-chain-diff.py"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0

# run_case <name> <expected-row-count> <expected-reason-or-empty> <before> <after>
run_case() {
  local name="$1" want_rows="$2" want_reason="$3" before="$4" after="$5"
  printf '%s' "$before" >"$WORK/before.md"
  printf '%s' "$after" >"$WORK/after.md"
  local out rc
  out="$(python3 "$TOOL" "$WORK/before.md" "$WORK/after.md" 2>&1)"
  rc=$?
  local got_rows
  got_rows="$(printf '%s\n' "$out" | sed -n 's/^derived row set: //p')"

  if [ "$got_rows" != "$want_rows" ]; then
    printf 'FAIL %-46s expected %s row(s), got %s\n' "$name" "$want_rows" "${got_rows:-?}"
    printf '%s\n' "$out" | sed 's/^/       /'
    fail=$((fail + 1))
    return
  fi
  # Exit status must agree with the row count: 1 when rows exist, 0 when empty.
  local want_rc=1
  [ "$want_rows" = "0" ] && want_rc=0
  if [ "$rc" != "$want_rc" ]; then
    printf 'FAIL %-46s expected rc=%s, got rc=%s\n' "$name" "$want_rc" "$rc"
    fail=$((fail + 1))
    return
  fi
  if [ -n "$want_reason" ] && ! printf '%s\n' "$out" | grep -qF "[$want_reason]"; then
    printf 'FAIL %-46s expected reason %s\n' "$name" "$want_reason"
    printf '%s\n' "$out" | sed 's/^/       /'
    fail=$((fail + 1))
    return
  fi
  printf 'PASS %s\n' "$name"
  pass=$((pass + 1))
}

OBLIGATION='A case that cannot be exercised safely is recorded as a safe-unavailable gap with residual risk.'
HOST_A='- Enforcement mechanisms are verified by a behavioral matrix run against scratch targets only.'
HOST_B='- A guard must pin precision as well as recall, keeping benign near-miss rows permanently.'

# ---------------------------------------------------------------------------
# 1. The originating incident: a qualifier migrates from host A to host B while
#    its own text stays byte-identical. This is the case the whole rule exists
#    for, and the case a diff-of-removed-text scan cannot see.
# ---------------------------------------------------------------------------
run_case "reparented onto a sibling host" 1 "governing-chain-changed" \
"## Core Rules

$HOST_A
  - $OBLIGATION
$HOST_B
" \
"## Core Rules

$HOST_A
$HOST_B
  - $OBLIGATION
"

# ---------------------------------------------------------------------------
# 2. An ancestor is INTERPOSED between an untouched host and an untouched
#    obligation. Pure addition: nothing is deleted or rewritten anywhere.
# ---------------------------------------------------------------------------
run_case "interposed ancestor (pure addition)" 1 "governing-chain-changed" \
"## Core Rules

$HOST_A
  - $OBLIGATION
" \
"## Core Rules

$HOST_A
- A newly interposed rule about mutation blast radius and isolated dependencies.
  - $OBLIGATION
"

# ---------------------------------------------------------------------------
# 3. A GRANDPARENT's condition is rewritten while the immediate parent and the
#    obligation are untouched. Closure under nesting depth: comparing only the
#    nearest parent would miss this. Three rows are owed, not one: the rewritten
#    grandparent itself, plus BOTH descendants whose governing chain moved with
#    it — an edit high in the tree enrols everything under it.
# ---------------------------------------------------------------------------
run_case "grandparent rewritten (nesting closure)" 3 "governing-chain-changed" \
"## Core Rules

- Verification applies to every change that ships operational behavior.
  - Sub-rule about matrices and their required cells.
    - $OBLIGATION
" \
"## Core Rules

- Verification applies only to changes that ship irreversible operational behavior.
  - Sub-rule about matrices and their required cells.
    - $OBLIGATION
"

# ---------------------------------------------------------------------------
# 4. An ancestor is DELETED, re-parenting everything beneath it onto the
#    neighbour above. The obligation's own text never changes. Two rows: the
#    deleted ancestor (it left) and the obligation it used to govern.
# ---------------------------------------------------------------------------
run_case "ancestor deleted (re-parent upward)" 2 "governing-chain-changed" \
"## Core Rules

$HOST_B
$HOST_A
  - $OBLIGATION
" \
"## Core Rules

$HOST_B
  - $OBLIGATION
"

# ---------------------------------------------------------------------------
# 5. Relocation ACROSS sections: chain changes, so a row is owed. This is the
#    shape whose status must be `rehosted` rather than `merged`.
# ---------------------------------------------------------------------------
run_case "relocation across sections" 1 "governing-chain-changed" \
"## Enforcement

$HOST_A
  - $OBLIGATION

## Precision
$HOST_B
" \
"## Enforcement

$HOST_A

## Precision
$HOST_B
  - $OBLIGATION
"

# ---------------------------------------------------------------------------
# 6. The obligation's OWN text is rewritten in place. Chain is untouched, but it
#    left a rewritten line, so it is still in the row set.
# ---------------------------------------------------------------------------
run_case "in-place rewrite of the obligation" 1 "left-a-rewritten-line" \
"## Core Rules

$HOST_A
  - $OBLIGATION
" \
"## Core Rules

$HOST_A
  - A case that cannot be exercised safely is a recorded safe-unavailable gap, never a silent skip.
"

# ---------------------------------------------------------------------------
# 6b. SENTENCE GRANULARITY — the originating incident's real shape. Two dense
#     bullets each carry several gates on ONE physical line, and a trailing
#     qualifier moves from the end of bullet A to the end of bullet B. A
#     line-granular walk reports only "both bullets were rewritten" and never
#     surfaces the clause; the clause itself must appear in the row set.
# ---------------------------------------------------------------------------
run_case "clause moves between dense one-line bullets" 1 "governing-chain-changed" \
"## Core Rules

- Enforcement is proven by a behavioral matrix, never by config inspection. Run it against scratch targets only. $OBLIGATION
- A guard must pin precision as well as recall. Keep benign near-miss rows permanently.
" \
"## Core Rules

- Enforcement is proven by a behavioral matrix, never by config inspection. Run it against scratch targets only.
- A guard must pin precision as well as recall. Keep benign near-miss rows permanently. $OBLIGATION
"

# ---------------------------------------------------------------------------
# NEGATIVE CASES — the predicate must stay silent. Without these, a checker that
# always reports "owes a row" would pass every case above.
# ---------------------------------------------------------------------------

# 7. Appending a new rule at the END of a section re-parents nothing.
run_case "append at section tail (no row)" 0 "" \
"## Core Rules

$HOST_A
  - $OBLIGATION
" \
"## Core Rules

$HOST_A
  - $OBLIGATION
- An entirely new rule appended after everything else in this section.
"

# 7b. An unindented paragraph after a list is a SIBLING of the list, not a child
#     of its last item. Editing that last item must not report the paragraph as
#     re-parented — a false positive here buries the real rows in noise.
run_case "paragraph after list not owned by it" 1 "left-a-rewritten-line" \
"## Core Rules

$HOST_A
$HOST_B

This closing paragraph states a separate obligation about recorded evidence.
" \
"## Core Rules

$HOST_A
- A guard must pin precision as well as recall, and keep near-miss rows for good.

This closing paragraph states a separate obligation about recorded evidence.
"

# 8. Cosmetic rewrapping of the obligation must not register as a change.
run_case "whitespace rewrap only (no row)" 0 "" \
"## Core Rules

$HOST_A
  - $OBLIGATION
" \
"## Core Rules

$HOST_A
  - A case that cannot be exercised safely is recorded as a
    safe-unavailable gap with residual risk.
"

# 9. An ancestor gains a trailing clause. Its scope may have moved, so BOTH the
#    host (its own line left a rewritten line) and everything beneath it (its
#    governing chain changed) owe rows — host identity is normative content,
#    never label or position. This is the direction an author most wants to
#    wave through as "I only added a clause".
run_case "ancestor extended (host + descendants)" 2 "governing-chain-changed" \
"## Core Rules

$HOST_A
  - $OBLIGATION
" \
"## Core Rules

${HOST_A%.} and the matrix records every deny condition observed externally.
  - $OBLIGATION
"

# 10. An UNRELATED section is edited. That rule owes a row for its own rewrite,
#     but the obligation in the untouched section must NOT be dragged in: the
#     predicate is per-obligation, not per-file.
run_case "unrelated section edited (only that rule)" 1 "left-a-rewritten-line" \
"## Other

- Some unrelated rule about routing surfaces and their analyzers.

## Core Rules

$HOST_A
  - $OBLIGATION
" \
"## Other

- Some unrelated rule about routing surfaces rewritten entirely for clarity.

## Core Rules

$HOST_A
  - $OBLIGATION
"

# ---------------------------------------------------------------------------
# CJK handling: fullwidth terminators split dense CJK prose into clause-level
# obligations, and CJK chars count double toward the length floor — otherwise
# short CJK gates and intra-bullet CJK qualifier moves are invisible (observed:
# an 18-char blast-radius question and a 13-char caller-control question were
# dropped from the derived row set of a real consolidation).
# ---------------------------------------------------------------------------
# 11. Short CJK obligations that are deleted must each produce a row. An
#     unweighted 25-char floor drops all three; only the intro survives it.
run_case "cjk: short obligations deleted" 3 "left-a-rewritten-line" \
"## 示例规则

配置涉及配额、权限时，记录必须包含：

1. 哪些字段由调用方自行填报。
2. 缺省值被覆盖之后的影响范围。
" \
"## 示例规则

配置涉及配额、权限时，记录必须逐项包含三项检查的答案。
"

# 12. A CJK qualifier migrates between two dense CJK hosts. Fullwidth sentence
#     splitting keeps the moved sentence's content key stable, so this is one
#     governing-chain-changed row — not two left-a-rewritten-line rows.
run_case "cjk: qualifier reparented between dense hosts" 1 "governing-chain-changed" \
"## Core Rules

- 执行机制只在隔离目标上验证。不能安全演练的情形记为不可用缺口并附残余风险。
- 精度守卫必须钉住误报与漏报两侧，良性近似行永久保留在套件里。
" \
"## Core Rules

- 执行机制只在隔离目标上验证。
- 精度守卫必须钉住误报与漏报两侧，良性近似行永久保留在套件里。不能安全演练的情形记为不可用缺口并附残余风险。
"

# 13. A CJK obligation of ≤12 chars (effective-len below the unconditional 25
#     floor) must still produce a row: ideograph-bearing text uses a
#     16-effective-char floor. The unconditional floor drops it (observed: a
#     real 10-char caller-control obligation had to be hand-added to a
#     consolidation table). Fixture sits OFF the floor boundary (host eff 21,
#     deleted clause eff 18) so a normalize tweak cannot flip it.
run_case "cjk: sub-floor short obligation deleted" 1 "left-a-rewritten-line" \
"## 示例规则

- 记录来源出处与推导过程。不得伪造证据来源。
- 另一条无关规则保持原样不动。
" \
"## 示例规则

- 记录来源出处与推导过程。
- 另一条无关规则保持原样不动。
"

# 14. The CJK floor must TRACK a non-default min_chars in both directions
#     (a flat floor would make the knob inert or, worse, raise the floor when
#     the caller lowers it — a silent row-set loss). The CLI exposes no
#     min_chars flag, so this case drives the module API directly.
floor_output="$(python3 - "$TOOL" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location('gcd', sys.argv[1])
m = importlib.util.module_from_spec(spec)
sys.modules['gcd'] = m
spec.loader.exec_module(m)
# min_chars=40: CJK floor 26 drops the 9-char (eff 18) obligation from parse.
raised = [o for o in m.parse("- 记录来源与推导。不得伪造证据来源。\n", min_chars=40)
          if '伪造' in o.text]
# min_chars=10: CJK floor 6 keeps the 4-char (eff 8) obligation.
lowered = [o for o in m.parse("- 记录推导。不得伪造。\n", min_chars=10)
           if '伪造' in o.text]
# Direct floor pins (not inferred from row counts): eff len doubles ideographs
# only; scaled floor applies to ideograph text; fullwidth punct is neutral.
pins = [
    m.effective_len("不得伪造。") == 9,  # 5 chars + 4 ideographs; 。 is neutral
    m.length_floor("不得伪造。", 25) == 16,
    m.length_floor("plain english", 25) == 25,
    m.length_floor("Keep it minimal。", 25) == 25,
    m.effective_len("Keep it minimal。") == 16,
]
print(f"raised={len(raised)} lowered={len(lowered)} pins={int(all(pins))}")
PYEOF
)"
if [ "$floor_output" = 'raised=0 lowered=1 pins=1' ]; then
  printf 'PASS %s\n' "cjk: floor tracks non-default min_chars both ways"
  pass=$((pass + 1))
else
  printf 'FAIL %-46s got %s\n' "cjk: floor tracks non-default min_chars both ways" "$floor_output"
  fail=$((fail + 1))
fi

# 15. One fullwidth punctuation mark must NOT flip an English block onto the
#     scaled floor: a short English clause ending in 。 stays subject to the
#     min_chars floor and its deletion derives no row.
run_case "cjk: fullwidth punct does not flip english floor" 0 "" \
"## Core Rules

- Keep the gate minimal。
- An unrelated English rule that stays exactly as it was written.
" \
"## Core Rules

- An unrelated English rule that stays exactly as it was written.
"

# ---------------------------------------------------------------------------
# 16. Anchor self-check: prove the harness can actually fail. A deliberately
#     wrong expectation must be reported as FAIL, otherwise every PASS above is
#     evidence of nothing. Run in a subshell so the real counters stay clean.
# ---------------------------------------------------------------------------
mutant_output="$(
  pass=0; fail=0
  run_case "self-check (expected to fail)" 0 "" \
"## Core Rules

$HOST_A
  - $OBLIGATION
$HOST_B
" \
"## Core Rules

$HOST_A
$HOST_B
  - $OBLIGATION
"
  printf 'fail=%s' "$fail"
)"
if printf '%s' "$mutant_output" | grep -q 'fail=1'; then
  printf 'PASS %s\n' "harness self-check reports a wrong expectation"
  pass=$((pass + 1))
else
  printf 'FAIL %s\n' "harness self-check did NOT report a wrong expectation"
  fail=$((fail + 1))
fi

printf 'governing-chain-diff: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
