#!/usr/bin/env bash
# RED-baseline probes for the impact-chain gate's ROW-OWNERSHIP ATTRIBUTION.
#
# Three forms were recorded separately across the 034 batches and registered as
# one deferred hardening item. Reproduction against the current baseline split
# them into two independent roots, and only one is fixed here.
#
#   Leg 0  CONTROL      one owner change, one well-formed row: must be green.
#   Leg A  form 1       an owner restored to base bytes leaves the changed set,
#                       and its surviving row kept vouching for a change the
#                       delivered diff no longer contains.
#   Leg B  form 2       a row citing a path inside the owner package but never
#                       its SKILL.md resolved to nothing, so the declaration it
#                       makes was never evaluated.
#   Leg H  REGRESSION   the register carries other five-column tables; widening
#                       resolution must not drag them into this gate.
#
# FORM 3 IS NOT FIXED HERE, BY DECISION. A stacked branch that integrates its
# upstream branch by merge is still refused a row it cannot supply; the standing
# workaround is to integrate by rebase, which is already the documented practice.
# The suppression that would have fixed it was implemented and then removed: it
# necessarily proxies "this round authored nothing of its own" with a textual
# comparison, and three adversarial review rounds found eight ways through that
# proxy (deletion, relocation, duplication, partial import, dropped import,
# rejected removal, duplicate-line cancellation, and binary/mode invisibility).
# Same class three rounds running is the repo's own signal to question the
# capability rather than patch it again, and the risk is asymmetric: form 3 costs
# an author one rebase, while a leaky suppression silently accepts undeclared
# owner changes — the very failure the two forms above are about. The risk owner
# chose deletion. Reinstating it needs an invariant, not another proxy.
#
# Each leg asserts the DESIRED behavior, and every leg expecting a refusal also
# asserts WHICH refusal. rc alone is a weak oracle: a leg red for a fixture
# defect looks identical to the form reproducing, and both directions of that
# mistake were observed while writing this file. Do not "fix" a leg by relaxing
# its assertion.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
# REVERSE DIFFERENTIAL. Each leg below states which gate behavior it pins, and a
# leg only means something if the gate it replaces fails it. Point this at the
# older gate to check that:
#
#   git show <ref>:skills/skill-extraction-workflow/scripts/impact-chain-gate.rb > /tmp/old.rb
#   IMPACT_CHAIN_GATE=/tmp/old.rb bash "$0"
#
# The legs marked as differential must go RED there. Without the override this
# runs the working-tree gate, which is the ordinary regression direction; the
# override is what makes the reverse direction reproducible instead of a claim
# about a run nobody else can repeat.
GATE="${IMPACT_CHAIN_GATE:-$SCRIPT_DIR/impact-chain-gate.rb}"
[ -f "$GATE" ] || { echo "FAIL: gate not found: $GATE" >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/icattr.XXXXXX")"
trap 'rc=$?; rm -rf "$TMP"; exit $rc' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
note() { echo "  $*"; }

LEDGER_REL="skills/skill-extraction-workflow/references/source-register.md"

# One curated upstream owner package plus the ledger header. The owner body
# carries a numbered normative rule line so a firing-path anchor can resolve to
# a genuinely changed rule rather than to prose.
seed_repo() { # <repo-dir>
  local repo="$1"
  mkdir -p "$repo"
  git -C "$repo" init -q -b trunk
  git -C "$repo" config user.email test@example.invalid
  git -C "$repo" config user.name "Test User"
  git -C "$repo" config commit.gpgsign false
  mkdir -p "$repo/skills/product-rd-workflow" \
           "$repo/skills/testing-strategy" \
           "$repo/skills/skill-extraction-workflow/references"
  cat > "$repo/skills/product-rd-workflow/SKILL.md" <<'MD'
---
name: product-rd-workflow
description: Fixture routing description for the attribution differential.
---

# Fixture Owner

## Rules

- Baseline rule line that the case commits mutate.
MD
  cat > "$repo/skills/testing-strategy/SKILL.md" <<'MD'
---
name: testing-strategy
description: Second fixture owner, used by the upstream-branch round.
---

# Second Fixture Owner

## Rules

- Baseline rule line owned by the upstream integration branch.
MD
  printf '| Lesson | Downstream owner | Behavior | Status | Evidence |\n| --- | --- | --- | --- | --- |\n' \
    > "$repo/$LEDGER_REL"
  git -C "$repo" add -A
  git -C "$repo" commit -qm "seed fixture base"
}

# The owner mutation and the row's firing path are a matched pair. The gate
# resolves a file locator by finding the anchor as a substring of an ADDED line
# in the row's own round diff, requiring that line to be a list item carrying
# normative-action vocabulary. So the rule line must be a real `- ... must ...`
# rule and the anchor must be a token unique to it.
rule_anchor() { printf 'ATTRIBUTION-FIXTURE-%s' "$1"; }

mutate_owner_rule() { # <repo-dir> <owner-slug> <marker>
  local repo="$1" owner="$2" marker="$3"
  printf -- '- Rule %s must be recorded before the round lands.\n' "$(rule_anchor "$marker")" \
    >> "$repo/skills/$owner/SKILL.md"
}

# A complete, well-formed row: valid status, full behavioral-evidence
# declaration, owner-scoped firing path that resolves to the rule line the
# matching mutate_owner_rule added, and the owner key in the evidence cell.
append_valid_row() { # <repo-dir> <owner-slug> <marker> <lesson>
  local repo="$1" owner="$2" marker="$3" lesson="$4"
  printf '| %s | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; result-class: failure; firing-path: file:skills/%s/SKILL.md#%s | `updated` | `%s/SKILL.md` fixture change |\n' \
    "$lesson" "$owner" "$(rule_anchor "$marker")" "$owner" >> "$repo/$LEDGER_REL"
}

run_gate() { # <repo-dir> <base-ref>  -> sets rc, out
  set +e
  out="$(env -u ALIAS_AUDIT_CMD CCL_SKILL_BASE_REF="$2" ruby "$GATE" "$1" 2>&1)"
  rc=$?
  set -e
}

legs_failed=0
# <leg-name> <expected-rc> <form-summary> [expected-token]
# The token is the attribution guard. rc alone is a weak oracle here: a refusal
# for an unrelated reason (a fixture defect, a broken anchor) is still rc=1 and
# would read as the form being closed. When a leg expects a refusal it must
# also name WHICH refusal, so a green leg means the intended predicate fired.
report_leg() {
  if [ "$rc" != "$2" ]; then
    echo "  $1: RED (rc=$rc, want $2) — $3 REPRODUCES"
    note "gate output:"
    printf '%s\n' "$out" | sed 's/^/    | /'
    legs_failed=$((legs_failed + 1))
    return
  fi
  if [ -n "${4:-}" ]; then
    case "$out" in
      *"$4"*) : ;;
      *)
        echo "  $1: RED (rc=$rc as wanted, but the wrong refusal) — expected $4"
        note "gate output:"
        printf '%s\n' "$out" | sed 's/^/    | /'
        legs_failed=$((legs_failed + 1))
        return
        ;;
    esac
  fi
  echo "  $1: PASS (rc=$rc) — $3 does not reproduce on this baseline"
}

echo "test_impact_chain_round_attribution: row-ownership attribution"

# ---------------------------------------------------------------------------
# Leg 0 — CONTROL. The plain shape every leg below is a variation of: one owner
# change, one well-formed row declaring it. This must be GREEN. Without this
# control a fixture defect (an anchor that does not resolve, a malformed row)
# reads as the form reproducing, and a leg that is red for the wrong reason
# reads as the form being closed. Both directions were observed while writing
# this file, so the control is load-bearing, not ceremony.
# ---------------------------------------------------------------------------
Z="$TMP/leg-0"
seed_repo "$Z"
git -C "$Z" branch fixture-base HEAD
git -C "$Z" switch -q -c case-control
mutate_owner_rule "$Z" product-rd-workflow Z
append_valid_row "$Z" product-rd-workflow Z "Fixture control row"
git -C "$Z" add -A
git -C "$Z" commit -qm "round 1: change the owner and declare it"
run_gate "$Z" fixture-base
if [ "$rc" != 0 ]; then
  echo "  leg 0 (control): BROKEN FIXTURE (rc=$rc, want 0)"
  printf '%s\n' "$out" | sed 's/^/    | /'
  fail "the control shape is not green, so no other leg's verdict means anything"
fi
echo "  leg 0 (control): PASS (rc=0) — the fixture shape itself is green"


# ---------------------------------------------------------------------------
# Leg A — form 1: owner restored to base, row stays green (FALSE-GREEN)
# ---------------------------------------------------------------------------
A="$TMP/leg-a"
seed_repo "$A"
git -C "$A" branch fixture-base HEAD
git -C "$A" switch -q -c case-restore
mutate_owner_rule "$A" product-rd-workflow "A"
append_valid_row "$A" product-rd-workflow A "Fixture restored-owner row"
git -C "$A" add -A
git -C "$A" commit -qm "round 1: change the owner and declare it"
# The restore: exactly what a rebase/conflict resolution that takes the base
# side does. The ledger row is untouched and still reads as a live declaration.
git -C "$A" checkout -q fixture-base -- skills/product-rd-workflow/SKILL.md
git -C "$A" commit -qm "owner restored to base bytes (rebase/conflict restore)" -q
# Guard: the delivered diff really contains no owner change any more.
if git -C "$A" diff --name-only fixture-base HEAD | grep -q '^skills/product-rd-workflow/'; then
  fail "leg A fixture is a no-op: the owner is still changed at HEAD"
fi
git -C "$A" diff --name-only fixture-base HEAD | grep -qx "$LEDGER_REL" \
  || fail "leg A fixture is a no-op: the ledger row did not survive"
run_gate "$A" fixture-base
report_leg "leg A (owner restored to base)" 1 "form 1" "impact_chain_row_vouches_for_unchanged_owner"

# ---------------------------------------------------------------------------
# Leg B — form 2: row without a recognized owner key is never evaluated
# ---------------------------------------------------------------------------
B="$TMP/leg-b"
seed_repo "$B"
git -C "$B" branch fixture-base HEAD
git -C "$B" switch -q -c case-unkeyed
mutate_owner_rule "$B" product-rd-workflow "B"
# Row 1 binds the owner and satisfies the per-round demand.
append_valid_row "$B" product-rd-workflow B "Fixture binding row"
# Row 2 is deliberately INVALID where the gate checks bound rows: the
# behavioral-evidence declaration is truncated (no observed-failure, no
# firing-path) and the evidence cell names only a references/ path, never the
# owning SKILL.md key. If the gate evaluates every added row, this must be
# rejected. If it only ever evaluates rows it managed to bind, this row is
# silently inert.
printf '| Fixture unkeyed row | `downstream-executor` | behavioral-evidence: RED-baseline | `updated` | skills/product-rd-workflow/references/nonexistent-note.md supporting note only |\n' \
  >> "$B/$LEDGER_REL"
git -C "$B" add -A
git -C "$B" commit -qm "round 1: one binding row plus one unkeyed incomplete row"
run_gate "$B" fixture-base
report_leg "leg B (unkeyed row never evaluated)" 1 "form 2" "impact_chain_firing_path_missing"

# ---------------------------------------------------------------------------
# Leg H — UNRELATED TABLE regression. The register carries other five-column
# tables whose rows have a status word and can cite a path inside an owner
# package. Before prefix resolution they never matched an exact
# `<owner>/SKILL.md` and were skipped; that prior behavior must survive, or the
# widening silently drags unrelated bookkeeping into this gate. The row here
# cites a curated owner's reference path and carries NO behavioral-evidence
# declaration, which is the discriminator that keeps it out.
# ---------------------------------------------------------------------------
H="$TMP/leg-h"
seed_repo "$H"
git -C "$H" branch fixture-base HEAD
git -C "$H" switch -q -c case-unrelated
printf '| Note | Owner | Rationale | Status | Reference |\n| --- | --- | --- | --- | --- |\n| Fixture unrelated bookkeeping row | `some-reviewer` | Recorded for traceability, no impact-chain claim | `routed` | see skills/product-rd-workflow/references/relocated-note.md for the rationale |\n' \
  >> "$H/$LEDGER_REL"
git -C "$H" add -A
git -C "$H" commit -qm "round 1: append a row belonging to a different register table"
# Guard: the row really would resolve to a selected owner on a path-only rule.
git -C "$H" show "HEAD:$LEDGER_REL" | grep -q 'skills/product-rd-workflow/references/relocated-note.md' \
  || fail "leg H fixture is a no-op: the unrelated row lost its owner-package path"
run_gate "$H" fixture-base
report_leg "leg H (unrelated five-column table row)" 0 "the unrelated-table regression"

# ---------------------------------------------------------------------------
# Leg L — MULTI-OWNER blocking. Resolving to more than one selected owner used
# to warn and drop the row, which is the worst pairing: the author sees a
# warning, the row is never evaluated, and the exit code says the gate passed.
# Without a leg here a regression back to warn-and-drop leaves every other leg
# green while an explicit acceptance requirement fails.
# ---------------------------------------------------------------------------
L="$TMP/leg-l"
seed_repo "$L"
git -C "$L" branch fixture-base HEAD
git -C "$L" switch -q -c case-ambiguous
mutate_owner_rule "$L" product-rd-workflow L
mutate_owner_rule "$L" testing-strategy L2
# Both owners are separately and validly declared, so the ONLY thing left for
# the gate to object to is the ambiguous row. Without these two the round would
# fail for a missing declaration instead, and the leg would pass against a gate
# that still merely warns — which is exactly what it must detect.
append_valid_row "$L" product-rd-workflow L "Fixture first owner row"
append_valid_row "$L" testing-strategy L2 "Fixture second owner row"
printf '| Fixture ambiguous row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; result-class: failure; firing-path: file:skills/product-rd-workflow/SKILL.md#%s | `updated` | `product-rd-workflow/SKILL.md` and `testing-strategy/SKILL.md` both changed and are cited in one row |\n' \
  "$(rule_anchor L)" >> "$L/$LEDGER_REL"
git -C "$L" add -A
git -C "$L" commit -qm "round 1: one row citing two changed selected owners"
run_gate "$L" fixture-base
report_leg "leg L (row resolving to two selected owners)" 1 "the multi-owner warn-and-drop" "impact_chain_row_ambiguous"

# ---------------------------------------------------------------------------
# Leg M — NON-CURATED owner. A row about a skill outside the curated upstream
# list is outside this gate's jurisdiction and must stay skipped, declaration or
# not. This is the acceptance requirement that the widening must not start
# selecting owners the curated list never picked.
# ---------------------------------------------------------------------------
M="$TMP/leg-m"
seed_repo "$M"
mkdir -p "$M/skills/worktree-isolation"
cat > "$M/skills/worktree-isolation/SKILL.md" <<'MD'
---
name: worktree-isolation
description: A fixture skill deliberately outside the curated upstream-owner list.
---

# Non-curated Fixture Owner

## Rules

- Baseline rule line owned by a skill this gate does not govern.
MD
git -C "$M" add -A
git -C "$M" commit -qm "seed a non-curated owner package"
git -C "$M" branch fixture-base HEAD
git -C "$M" switch -q -c case-noncurated
printf -- '- Rule %s must be recorded before the round lands.\n' "$(rule_anchor M)" \
  >> "$M/skills/worktree-isolation/SKILL.md"
printf '| Fixture non-curated row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; result-class: failure; firing-path: file:skills/worktree-isolation/SKILL.md#%s | `updated` | `worktree-isolation/SKILL.md` changed; this skill is not a curated upstream owner |\n' \
  "$(rule_anchor M)" >> "$M/$LEDGER_REL"
git -C "$M" add -A
git -C "$M" commit -qm "round 1: change a non-curated owner and record it"
run_gate "$M" fixture-base
report_leg "leg M (non-curated owner stays out of scope)" 0 "the curated-list bypass"

# ---------------------------------------------------------------------------
# Leg N — MULTI-OWNER, NO DECLARATION. Leg L pins that a declaring row citing two
# selected owners blocks. This pins the other side: an unrelated register row
# that happens to mention two curated owners in prose asserts nothing this gate
# owns, so promoting its old warning to a merge block would be the same
# unrelated-table regression leg H guards. The two legs together are what make
# the blocking change scoped rather than blanket.
# ---------------------------------------------------------------------------
N="$TMP/leg-n"
seed_repo "$N"
git -C "$N" branch fixture-base HEAD
git -C "$N" switch -q -c case-ambiguous-undeclared
printf '| Note | Owner | Rationale | Status | Reference |\n| --- | --- | --- | --- | --- |\n| Fixture cross-owner bookkeeping note | `some-reviewer` | Recorded for traceability; this row makes no impact-chain claim | `routed` | compares how product-rd-workflow/SKILL.md and testing-strategy/SKILL.md phrase the same gate |\n' \
  >> "$N/$LEDGER_REL"
git -C "$N" add -A
git -C "$N" commit -qm "round 1: an unrelated row naming two curated owners, declaring nothing"
# Guard: both owner keys must sit in the EVIDENCE cell, which is what ownership
# resolution reads. A fixture that put them in another column would resolve to
# nothing and pass against any gate.
git -C "$N" show "HEAD:$LEDGER_REL" | tail -1 | awk -F'|' '{print $6}' \
  | grep -q 'product-rd-workflow/SKILL.md' \
  || fail "leg N fixture is a no-op: first owner key is not in the evidence cell"
git -C "$N" show "HEAD:$LEDGER_REL" | tail -1 | awk -F'|' '{print $6}' \
  | grep -q 'testing-strategy/SKILL.md' \
  || fail "leg N fixture is a no-op: second owner key is not in the evidence cell"
run_gate "$N" fixture-base
report_leg "leg N (undeclared row naming two owners)" 0 "the blanket multi-owner block"

# ---------------------------------------------------------------------------
# Leg O — the same evasion as leg A, written with a path prefix an author uses
# without meaning anything unusual: `./skills/<owner>/...`. The locator's
# lookbehind refuses a match preceded by a path character, so before the prefix
# allowance this citation resolved to nothing and the row was silently skipped —
# putting a restored owner right back where leg A found it, one keystroke away.
# ---------------------------------------------------------------------------
O="$TMP/leg-o"
seed_repo "$O"
git -C "$O" branch fixture-base HEAD
git -C "$O" switch -q -c case-dotslash
mutate_owner_rule "$O" product-rd-workflow O
printf '| Fixture dot-slash row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; result-class: failure; firing-path: file:skills/product-rd-workflow/SKILL.md#%s | `updated` | see ./skills/product-rd-workflow/references/design-note.md for the rationale |\n' \
  "$(rule_anchor O)" >> "$O/$LEDGER_REL"
git -C "$O" add -A
git -C "$O" commit -qm "round 1: change the owner, cite it with a ./ prefixed path"
git -C "$O" checkout -q fixture-base -- skills/product-rd-workflow/SKILL.md
git -C "$O" commit -qm "owner restored to base bytes" -q
git -C "$O" diff --name-only fixture-base HEAD | grep -q '^skills/product-rd-workflow/' \
  && fail "leg O fixture is a no-op: the owner is still changed at HEAD"
run_gate "$O" fixture-base
report_leg "leg O (restored owner, ./ prefixed citation)" 1 "the path-prefix evasion" "impact_chain_row_vouches_for_unchanged_owner"

# Leg O2 — the rooted counterpart. The adversarial challenge found this one: the
# allowance covered `./skills/` but not `/skills/`, so a rooted citation resolved
# to nothing, and a row that resolves to nothing is skipped before any refusal
# can apply. One character of prefix was the whole evasion.
O2="$TMP/leg-o2"
seed_repo "$O2"
git -C "$O2" branch fixture-base HEAD
git -C "$O2" switch -q -c case-rooted
mutate_owner_rule "$O2" product-rd-workflow O2
printf '| Fixture rooted-path row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; result-class: failure; firing-path: file:skills/product-rd-workflow/SKILL.md#%s | `updated` | see /skills/product-rd-workflow/references/design-note.md for the rationale |\n' \
  "$(rule_anchor O2)" >> "$O2/$LEDGER_REL"
git -C "$O2" add -A
git -C "$O2" commit -qm "round 1: change the owner, cite it with a rooted path"
git -C "$O2" checkout -q fixture-base -- skills/product-rd-workflow/SKILL.md
git -C "$O2" commit -qm "owner restored to base bytes" -q
git -C "$O2" diff --name-only fixture-base HEAD | grep -q '^skills/product-rd-workflow/' \
  && fail "leg O2 fixture is a no-op: the owner is still changed at HEAD"
run_gate "$O2" fixture-base
report_leg "leg O2 (restored owner, rooted citation)" 1 "the rooted-path evasion" "impact_chain_row_vouches_for_unchanged_owner"

# Leg O3 — the remainder class. Enumerating the characters a filename may hold
# gets it wrong: a citation whose remainder starts `@`, or carries a non-ASCII
# character, failed to match, the optional `skills/` prefix backtracked onto the
# literal `skills`, and the row resolved to nothing — skipped before any refusal
# could apply. Both remainders are exercised in one row because a single
# unresolved citation is enough to lose the whole row.
O3="$TMP/leg-o3"
seed_repo "$O3"
git -C "$O3" branch fixture-base HEAD
git -C "$O3" switch -q -c case-remainder
mutate_owner_rule "$O3" product-rd-workflow O3
printf '| Fixture remainder row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; result-class: failure; firing-path: file:skills/product-rd-workflow/SKILL.md#%s | `updated` | rationale in skills/product-rd-workflow/@design.md and skills/product-rd-workflow/设计说明.md |\n' \
  "$(rule_anchor O3)" >> "$O3/$LEDGER_REL"
git -C "$O3" add -A
git -C "$O3" commit -qm "round 1: cite the owner with unusual but valid path remainders"
git -C "$O3" checkout -q fixture-base -- skills/product-rd-workflow/SKILL.md
git -C "$O3" commit -qm "owner restored to base bytes" -q
git -C "$O3" diff --name-only fixture-base HEAD | grep -q '^skills/product-rd-workflow/' \
  && fail "leg O3 fixture is a no-op: the owner is still changed at HEAD"
run_gate "$O3" fixture-base
report_leg "leg O3 (restored owner, unusual path remainder)" 1 "the remainder-class evasion" "impact_chain_row_vouches_for_unchanged_owner"

# Leg O4 — the Markdown-relative form, the fourth spelling a path parse missed
# and the one that ended the patching: an ordinary `[note](../../<owner>/…)` link
# from the ledger to a file inside the owner package. Legs O through O4 are kept
# together deliberately: each was a separate round of the same class, and the
# resolution is now a membership test over the owner vocabulary, which admits all
# four by construction rather than by four accepted spellings.
O4="$TMP/leg-o4"
seed_repo "$O4"
git -C "$O4" branch fixture-base HEAD
git -C "$O4" switch -q -c case-relative
mutate_owner_rule "$O4" product-rd-workflow O4
printf '| Fixture relative-link row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; result-class: failure; firing-path: file:skills/product-rd-workflow/SKILL.md#%s | `updated` | rationale in [the design note](../../product-rd-workflow/references/design-note.md) |\n' \
  "$(rule_anchor O4)" >> "$O4/$LEDGER_REL"
git -C "$O4" add -A
git -C "$O4" commit -qm "round 1: cite the owner through a Markdown-relative link"
git -C "$O4" checkout -q fixture-base -- skills/product-rd-workflow/SKILL.md
git -C "$O4" commit -qm "owner restored to base bytes" -q
git -C "$O4" diff --name-only fixture-base HEAD | grep -q '^skills/product-rd-workflow/' \
  && fail "leg O4 fixture is a no-op: the owner is still changed at HEAD"
run_gate "$O4" fixture-base
report_leg "leg O4 (restored owner, Markdown-relative link)" 1 "the relative-link evasion" "impact_chain_row_vouches_for_unchanged_owner"

# ---------------------------------------------------------------------------
# Leg P — the refusal an undeclared row still owes. It cites two curated owners
# but only one of them changed, so the OLD predicate filtered the citation down
# to that one owner, bound the row, and rejected it for its missing declaration.
# Sharing the new name-level count with undeclared rows turned that into a
# two-owner ambiguity that merely warns and drops — a refusal quietly lost while
# the change was billed as a tightening. A second, valid row declares the changed
# owner, so the demand is satisfied and this row's own rejection is the only
# thing the verdict can be measuring.
# ---------------------------------------------------------------------------
P1="$TMP/leg-p"
seed_repo "$P1"
git -C "$P1" branch fixture-base HEAD
git -C "$P1" switch -q -c case-undeclared-partial
mutate_owner_rule "$P1" product-rd-workflow P
append_valid_row "$P1" product-rd-workflow P "Fixture declaring row"
printf '| Fixture undeclared row | `downstream-executor` | no declaration here, only prose | `updated` | contrasts `product-rd-workflow/SKILL.md` with `testing-strategy/SKILL.md` |\n' \
  >> "$P1/$LEDGER_REL"
git -C "$P1" add -A
git -C "$P1" commit -qm "round 1: a declaring row plus an undeclared row citing two owners"
git -C "$P1" diff --name-only fixture-base HEAD | grep -q '^skills/testing-strategy/' \
  && fail "leg P fixture is a no-op: the second cited owner must NOT be changed"
run_gate "$P1" fixture-base
report_leg "leg P (undeclared row, one cited owner changed)" 1 "the lost undeclared-row refusal" "impact_chain_behavior_evidence_missing"

# ---------------------------------------------------------------------------
# Leg S — the MALFORMED-ROW escape. One unescaped pipe puts a row outside the
# five-column parse, and a row outside the parse is invisible to every later
# check. That was survivable while it could only cost the row its own
# completeness; with a refusal now riding on surviving rows it becomes a way to
# buy silence: declare, name a byte-identical owner, add a stray pipe, and the
# range reports nothing at all. Blocking is scoped to that pair — declaration
# plus selected owner — so the register's other malformed prose keeps its
# advisory, which leg S2 pins.
# ---------------------------------------------------------------------------
S1="$TMP/leg-s"
seed_repo "$S1"
git -C "$S1" branch fixture-base HEAD
git -C "$S1" switch -q -c case-malformed
printf '| Fixture smuggled row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; result-class: failure; firing-path: file:skills/product-rd-workflow/SKILL.md#nope | `updated` | rationale in skills/product-rd-workflow/references/note.md, see a|b for the table |\n' \
  >> "$S1/$LEDGER_REL"
git -C "$S1" add -A
git -C "$S1" commit -qm "round 1: a declaring row for a selected owner with an unescaped pipe"
git -C "$S1" diff --name-only fixture-base HEAD | grep -q '^skills/product-rd-workflow/' \
  && fail "leg S fixture is a no-op: the owner must be byte-identical to base"
run_gate "$S1" fixture-base
report_leg "leg S (malformed row buys silence)" 1 "the malformed-row escape" "impact_chain_row_blocking_malformed"

# Leg S2 — the other side: a malformed row that makes no declaration and names no
# selected owner keeps its long-standing advisory. Without this the block is a
# blanket one and the register's other tables start failing merges on prose.
S2="$TMP/leg-s2"
seed_repo "$S2"
git -C "$S2" branch fixture-base HEAD
git -C "$S2" switch -q -c case-malformed-unrelated
printf '| Fixture unrelated malformed note | `some-reviewer` | recorded for traceability | `routed` | see the a|b column of the upstream table |\n' \
  >> "$S2/$LEDGER_REL"
git -C "$S2" add -A
git -C "$S2" commit -qm "round 1: an unrelated malformed row"
run_gate "$S2" fixture-base
report_leg "leg S2 (unrelated malformed row stays advisory)" 0 "the blanket malformed block"

# ---------------------------------------------------------------------------
# Leg S3 — the same escape through a different structural rejection. A stray pipe
# is only one way out of the parse; an empty cell is another, and the row is just
# as invisible afterwards. Blocking the pipe alone would have moved the escape
# rather than closed it.
# ---------------------------------------------------------------------------
S3="$TMP/leg-s3"
seed_repo "$S3"
git -C "$S3" branch fixture-base HEAD
git -C "$S3" switch -q -c case-emptycell
printf '| Fixture empty-cell row |  | behavioral-evidence: RED-baseline; observed-failure: yes; result-class: failure; firing-path: file:skills/product-rd-workflow/SKILL.md#nope | `updated` | rationale in skills/product-rd-workflow/references/note.md |\n' \
  >> "$S3/$LEDGER_REL"
git -C "$S3" add -A
git -C "$S3" commit -qm "round 1: a declaring row for a selected owner with an empty cell"
run_gate "$S3" fixture-base
report_leg "leg S3 (empty cell buys the same silence)" 1 "the empty-cell escape" "impact_chain_row_blocking_malformed"

# ---------------------------------------------------------------------------
# Leg S4 — the repair must be accepted. A malformed declaring row corrected in a
# later round must stop blocking, or the gate refuses the very fix it demanded:
# the survival budget applies to malformed lines exactly as it does to parsed
# ones. Round 1 carries a sound row so its own demand is met; round 2 escapes the
# pipe AND lands the rule the corrected row anchors on, because a row is judged
# against the round it lands in — a correction that resolves only against an
# earlier round's diff is not yet a valid row, which is a different rule and not
# what this leg pins.
# ---------------------------------------------------------------------------
S4="$TMP/leg-s4"
seed_repo "$S4"
git -C "$S4" branch fixture-base HEAD
git -C "$S4" switch -q -c case-corrected
mutate_owner_rule "$S4" product-rd-workflow S4
append_valid_row "$S4" product-rd-workflow S4 "Fixture sound row"
printf '| Fixture to-be-corrected row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; result-class: failure; firing-path: file:skills/product-rd-workflow/SKILL.md#%s | `updated` | rationale in skills/product-rd-workflow/references/note.md, see a|b |\n' \
  "$(rule_anchor S4b)" >> "$S4/$LEDGER_REL"
git -C "$S4" add -A
git -C "$S4" commit -qm "round 1: a sound row plus a malformed declaring row"
perl -0pi -e 's/, see a\|b \|/, see a\\|b |/' "$S4/$LEDGER_REL"
grep -q 'see a\\|b' "$S4/$LEDGER_REL" || fail "leg S4 fixture is a no-op: the pipe was not escaped"
mutate_owner_rule "$S4" product-rd-workflow S4b
git -C "$S4" add -A
git -C "$S4" commit -qm "round 2: escape the pipe and land the rule the row anchors on"
run_gate "$S4" fixture-base
report_leg "leg S4 (a corrected malformed row stops blocking)" 0 "the un-repairable block"
# ---------------------------------------------------------------------------
# Leg S5 / S6 — the outer-pipe spellings. Markdown accepts a table row without a
# leading or trailing pipe, so dropping one is a fourth way out of the parse and
# was found separately from the stray pipe, the empty cell and the bad status
# word. The check is now defined by "this line did not become a row" rather than
# by which rejection turned it away, so these two close with the others rather
# than needing their own branch.
# ---------------------------------------------------------------------------
S5="$TMP/leg-s5"
seed_repo "$S5"
git -C "$S5" branch fixture-base HEAD
git -C "$S5" switch -q -c case-noleading
printf 'Fixture no-leading-pipe row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; result-class: failure; firing-path: file:skills/product-rd-workflow/SKILL.md#nope | `updated` | rationale in skills/product-rd-workflow/references/note.md |\n' \
  >> "$S5/$LEDGER_REL"
git -C "$S5" add -A
git -C "$S5" commit -qm "round 1: a declaring row without its leading pipe"
run_gate "$S5" fixture-base
report_leg "leg S5 (no leading pipe)" 1 "the missing-leading-pipe escape" "impact_chain_row_blocking_malformed"

S6="$TMP/leg-s6"
seed_repo "$S6"
git -C "$S6" branch fixture-base HEAD
git -C "$S6" switch -q -c case-notrailing
printf '| Fixture no-trailing-pipe row | `downstream-executor` | behavioral-evidence: RED-baseline; observed-failure: yes; result-class: failure; firing-path: file:skills/product-rd-workflow/SKILL.md#nope | `updated` | rationale in skills/product-rd-workflow/references/note.md\n' \
  >> "$S6/$LEDGER_REL"
git -C "$S6" add -A
git -C "$S6" commit -qm "round 1: a declaring row without its trailing pipe"
run_gate "$S6" fixture-base
report_leg "leg S6 (no trailing pipe)" 1 "the missing-trailing-pipe escape" "impact_chain_row_blocking_malformed"

echo
if [ "$legs_failed" -gt 0 ]; then
  echo "test_impact_chain_round_attribution: $legs_failed/18 legs RED (forms confirmed reproducing)"
  exit 1
fi
echo "test_impact_chain_round_attribution: ok (all forms closed)"
