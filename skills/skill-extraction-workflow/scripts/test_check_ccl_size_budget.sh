#!/usr/bin/env bash
# Integration test for check-size-budget.sh (the block extracted from
# check-ccl-skills.sh). The script has TWO layers and this suite pins both.
#
# Layer 1 — advisory counters stay MACHINE-READABLE and NON-BLOCKING (cases a-d2):
#   - small entrypoint            => exit 0, debt_count=0, severe_debt_count=0, marker
#   - changed entrypoint body>5k  => exit 0, changed_entrypoint_above_recommended, debt=1
#   - base/head trend tokens      => advisory base/head/delta counters + per-file deltas
#   - an UNCHANGED entrypoint >50000 bytes => exit 0, severe_debt_count=1 + severe token
#   - bootstrap over the tripwire BAND but UNCHANGED => exit 0, band advisory only
#     (an untouched over-band file must never hard-red an unrelated MR)
#   - bootstrap missing           => exit 0, size_budget_advisory_partial
#
# Layer 2 — delta-BLOCKING verdict on CHANGED skills/*/SKILL.md (cases e1-e8):
#   - new/crossing over 50000 bytes, or growth of an already-severe entrypoint
#     => exit 1 + entrypoint_size_block
#   - shrink / sub-severe growth / same-size edit / rename-without-growth => exit 0
#   - unresolvable base with a severe changed file => exit 1 partial, and NO ok marker
#   - unresolvable base with a CLEAN tree => nothing was evaluated, so the run
#     reports entrypoint_size_blocking_unevaluated and never the ok marker
#   - e8 anchors the check-ccl-skills.sh wiring (rc propagation, no `|| true`)
#
# Layer 2b — delta-BLOCKING verdict on CHANGED agent-context/session-start.md (cases d3-d8): the
#   every-session injection is permanently severe — ANY net growth blocks;
#   shrink / same-size edit / tracked deletion => exit 0; a agent-context/session-start.md absent
#   from base blocks as a NEW every-session injection; unresolvable base with a
#   changed agent-context/session-start.md => exit 1 partial, and NO ok marker. Base resolution
#   is merge-base, so growth landing on the TARGET branch after divergence
#   (merged in or not) never reddens the branch — only the MR's own diff counts.
#
# Builds a throwaway git repo so debt counts are DETERMINISTIC and do NOT depend on
# the real repository's actual file sizes/counts. Calls check-size-budget.sh directly
# (not the full validator) so unrelated blocking gates do not interfere.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
SIZE_SCRIPT="$SCRIPT_DIR/check-size-budget.sh"
[ -f "$SIZE_SCRIPT" ] || { echo "FAIL: size script not found: $SIZE_SCRIPT" >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sizebudget.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_rc() { [ "$1" = "$2" ] || fail "expected rc=$2 got rc=$1${3:+ ($3)}"; }
assert_contains() { case "$2" in *"$1"*) : ;; *) fail "expected output to contain: $1${3:+ ($3)}";; esac; }
assert_not_contains() { case "$2" in *"$1"*) fail "expected output NOT to contain: $1${3:+ ($3)}";; *) : ;; esac; }

# repeat_char <char> <count> — emit <count> copies of <char> with no newline.
repeat_char() { head -c "$2" /dev/zero | tr '\0' "$1"; }

# Run the size script with a guaranteed-unset base ref env; capture stdout+stderr+rc.
run_size() {
  set +e
  out="$(env -u CCL_SKILL_BASE_REF "$@" bash "$SIZE_SCRIPT" "$REPO" 2>&1)"
  rc=$?
  set -e
}

REPO="$TMP/repo"
mkdir -p "$REPO/skills/demo-skill" "$REPO/agent-context"
git init -q -b main "$REPO"
git -C "$REPO" config user.email test@example.invalid
git -C "$REPO" config user.name "Test User"

SKILL_MD="$REPO/skills/demo-skill/SKILL.md"
cat > "$SKILL_MD" <<'EOF'
---
name: demo-skill
description: baseline skill body for the size-budget integration test.
---

Small clean body well under the recommended ceiling.
EOF
git -C "$REPO" add -A
git -C "$REPO" commit -qm "baseline demo skill"
git -C "$REPO" checkout -qb feature

# Case a: small committed entrypoint, nothing changed => clean counts, marker, exit 0.
run_size
assert_rc "$rc" 0 "small entrypoint should pass non-blocking"
assert_contains "entrypoint_size_debt_count=0" "$out" "no body-char debt"
assert_contains "entrypoint_size_severe_debt_count=0" "$out" "no severe byte debt"
assert_contains "entrypoint_size_debt_count_base=0" "$out" "trend base count available"
assert_contains "entrypoint_size_debt_count_head=0" "$out" "trend head count available"
assert_contains "entrypoint_size_debt_count_delta=+0" "$out" "trend delta is signed"
assert_contains "entrypoint_size_severe_debt_count_base=0" "$out" "severe trend base count available"
assert_contains "entrypoint_size_severe_debt_count_head=0" "$out" "severe trend head count available"
assert_contains "entrypoint_size_severe_debt_count_delta=+0" "$out" "severe trend delta is signed"
assert_contains "entrypoint_size_budget_advisory_ok" "$out" "final advisory marker present"
assert_not_contains "changed_entrypoint_above_recommended" "$out" "no changed-entrypoint token when nothing changed"

# Case b: baseline small -> head grows above recommended (tracked, uncommitted) =>
# stable token + debt_count_delta=+1 + positive per-file delta, still non-blocking.
{ printf '\n'; repeat_char 'A' 6000; printf '\n'; } >> "$SKILL_MD"
run_size
assert_rc "$rc" 0 "changed oversize entrypoint must stay non-blocking"
assert_contains "changed_entrypoint_above_recommended: skills/demo-skill/SKILL.md" "$out" "stable changed-entrypoint token"
assert_contains "recommended_max=5000" "$out" "token cites recommended ceiling"
assert_contains "entrypoint_size_debt_count=1" "$out" "body-char debt counted"
assert_contains "entrypoint_size_debt_count_base=0" "$out" "base debt count is from main"
assert_contains "entrypoint_size_debt_count_head=1" "$out" "head debt count sees working tree"
assert_contains "entrypoint_size_debt_count_delta=+1" "$out" "growth into debt is visible"
assert_contains "entrypoint_size_severe_debt_count_delta=+0" "$out" "non-severe growth leaves severe count unchanged"
assert_contains "changed_entrypoint_size_delta: skills/demo-skill/SKILL.md" "$out" "per-file delta token emitted"
assert_contains "delta_body_chars=+" "$out" "per-file body delta is positive"
assert_contains "delta_bytes=+" "$out" "per-file byte delta is positive"
assert_contains "entrypoint_size_budget_advisory_ok" "$out" "advisory marker still present"
git -C "$REPO" checkout -- "skills/demo-skill/SKILL.md"

# Case b-minus: baseline above recommended -> head shrinks below recommended =>
# debt_count_delta=-1 + negative per-file delta. Create a dedicated baseline branch so
# the aggregate base/head delta is deterministic without depending on repo history.
git -C "$REPO" checkout -qb shrink-baseline main
{ printf '\n'; repeat_char 'C' 6000; printf '\n'; } >> "$SKILL_MD"
git -C "$REPO" add -A
git -C "$REPO" commit -qm "large baseline"
git -C "$REPO" checkout -qb shrink-head
python3 - <<'PY' > "$SKILL_MD"
print("---")
print("name: demo-skill")
print("description: shrink changed entrypoint fixture.")
print("---")
print()
print("Small body after shrink.")
PY
set +e
out="$(CCL_SKILL_BASE_REF=shrink-baseline bash "$SIZE_SCRIPT" "$REPO" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 0 "shrinking oversize entrypoint must stay non-blocking"
assert_contains "changed_entrypoint_below_recommended: skills/demo-skill/SKILL.md" "$out" "shrunk file can also be below recommended"
assert_contains "entrypoint_size_debt_count_base=1" "$out" "base was over recommended"
assert_contains "entrypoint_size_debt_count_head=0" "$out" "head is below recommended"
assert_contains "entrypoint_size_debt_count_delta=-1" "$out" "shrink out of debt is visible"
assert_contains "changed_entrypoint_size_delta: skills/demo-skill/SKILL.md" "$out" "per-file shrink delta token emitted"
assert_contains "delta_body_chars=-" "$out" "per-file body delta is negative"
assert_contains "delta_bytes=-" "$out" "per-file byte delta is negative"
git -C "$REPO" reset --hard -q HEAD
git -C "$REPO" checkout -B feature main

# Case b2: changed entrypoint with body < 1000 chars => stable below-recommended
# token, still non-blocking. This proves the distinct warning branch is covered
# without snapshotting incidental current repository sizes.
python3 - <<'PY' > "$SKILL_MD"
print("---")
print("name: demo-skill")
print("description: tiny changed entrypoint fixture.")
print("---")
print()
print("Tiny body.")
PY
run_size
assert_rc "$rc" 0 "changed tiny entrypoint must stay non-blocking"
assert_contains "changed_entrypoint_below_recommended: skills/demo-skill/SKILL.md" "$out" "stable below-recommended token"
assert_contains "recommended_min=1000" "$out" "token cites recommended floor"
assert_contains "entrypoint_size_debt_count=0" "$out" "tiny body is not over-size debt"
git -C "$REPO" checkout -- "skills/demo-skill/SKILL.md"

# Case c: baseline severe >50KB -> head still severe but smaller => severe count delta
# remains 0 while per-file delta_bytes is negative. Use a second skill so the count is
# exactly 1.
mkdir -p "$REPO/skills/big-skill"
BIG_MD="$REPO/skills/big-skill/SKILL.md"
{
  printf '%s\n' '---'
  printf '%s\n' 'name: big-skill'
  printf '%s\n' 'description: oversized historical entrypoint fixture.'
  printf '%s\n' '---'
  printf '\n'
  repeat_char 'B' 60000
  printf '\n'
} > "$BIG_MD"
git -C "$REPO" add -A
git -C "$REPO" commit -qm "add severe baseline"
git -C "$REPO" branch -f severe-baseline HEAD
{
  printf '%s\n' '---'
  printf '%s\n' 'name: big-skill'
  printf '%s\n' 'description: still oversized historical entrypoint fixture.'
  printf '%s\n' '---'
  printf '\n'
  repeat_char 'D' 55000
  printf '\n'
} > "$BIG_MD"
set +e
out="$(CCL_SKILL_BASE_REF=severe-baseline bash "$SIZE_SCRIPT" "$REPO" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 0 "severe-debt entrypoint must stay non-blocking"
assert_contains "entrypoint_size_severe_debt_count=1" "$out" "severe byte debt counted"
assert_contains "entrypoint_size_severe_debt_count_base=1" "$out" "severe base counted"
assert_contains "entrypoint_size_severe_debt_count_head=1" "$out" "severe head counted"
assert_contains "entrypoint_size_severe_debt_count_delta=+0" "$out" "still-severe shrink does not change severe count"
assert_contains "entrypoint_size_severe_debt: skills/big-skill/SKILL.md" "$out" "per-file severe debt token"
assert_contains "changed_entrypoint_size_delta: skills/big-skill/SKILL.md" "$out" "severe per-file delta token emitted"
assert_contains "delta_bytes=-" "$out" "severe shrink byte delta is negative"
assert_contains "size_budget_info:" "$out" "legacy 50KB info header preserved"
assert_contains "entrypoint_size_budget_advisory_ok" "$out" "advisory marker still present"
git -C "$REPO" reset --hard -q HEAD
rm -rf "$REPO/skills/big-skill"
git -C "$REPO" add -A
git -C "$REPO" commit -qm "remove severe fixture"
git -C "$REPO" checkout -B feature main

# Case c2: added SKILL.md => base missing/head present/delta unknown, while aggregate
# delta remains computable.
mkdir -p "$REPO/skills/added-skill"
ADDED_MD="$REPO/skills/added-skill/SKILL.md"
cat > "$ADDED_MD" <<'EOF'
---
name: added-skill
description: added entrypoint fixture.
---

Added body.
EOF
run_size
assert_rc "$rc" 0 "added entrypoint must stay non-blocking"
assert_contains "changed_entrypoint_size_delta: skills/added-skill/SKILL.md" "$out" "added file delta token emitted"
assert_contains "base_body_chars=missing" "$out" "added file base is missing"
assert_contains "head_body_chars=" "$out" "added file head metric present"
assert_contains "delta_body_chars=unknown" "$out" "added file body delta is unknown, not zero"
assert_contains "base_bytes=missing" "$out" "added file base bytes missing"
assert_contains "head_bytes=" "$out" "added file head bytes present"
assert_contains "delta_bytes=unknown" "$out" "added file byte delta is unknown, not zero"
rm -rf "$REPO/skills/added-skill"

# Case c3: deleted SKILL.md => base present/head missing; aggregate count delta is
# still computable from the working tree.
git -C "$REPO" checkout -B delete-baseline main
mkdir -p "$REPO/skills/delete-skill"
DELETE_MD="$REPO/skills/delete-skill/SKILL.md"
{
  printf '%s\n' '---'
  printf '%s\n' 'name: delete-skill'
  printf '%s\n' 'description: deleted oversize entrypoint fixture.'
  printf '%s\n' '---'
  printf '\n'
  repeat_char 'E' 6000
  printf '\n'
} > "$DELETE_MD"
git -C "$REPO" add -A
git -C "$REPO" commit -qm "delete baseline"
git -C "$REPO" checkout -qb delete-head
rm -f "$DELETE_MD"
set +e
out="$(CCL_SKILL_BASE_REF=delete-baseline bash "$SIZE_SCRIPT" "$REPO" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 0 "deleted entrypoint must stay non-blocking"
assert_contains "entrypoint_size_debt_count_base=1" "$out" "deleted baseline debt counted"
assert_contains "entrypoint_size_debt_count_head=0" "$out" "deleted head debt removed"
assert_contains "entrypoint_size_debt_count_delta=-1" "$out" "deleted debt count delta computable"
assert_contains "changed_entrypoint_size_delta: skills/delete-skill/SKILL.md" "$out" "deleted file delta token emitted"
assert_contains "head_body_chars=missing" "$out" "deleted file head is missing"
assert_contains "delta_body_chars=unknown" "$out" "deleted file body delta is unknown, not zero"
assert_contains "head_bytes=missing" "$out" "deleted file head bytes missing"
assert_contains "delta_bytes=unknown" "$out" "deleted file byte delta is unknown, not zero"
git -C "$REPO" reset --hard -q HEAD
git -C "$REPO" checkout -B feature main

# Case c4: no git / merge-base unavailable => base/delta unknown/partial marker, rc 0.
NONGIT="$TMP/nongit"
mkdir -p "$NONGIT/skills/nogit-skill"
cat > "$NONGIT/skills/nogit-skill/SKILL.md" <<'EOF'
---
name: nogit-skill
description: non git fixture.
---

Body.
EOF
OLD_REPO="$REPO"
REPO="$NONGIT"
run_size
REPO="$OLD_REPO"
assert_rc "$rc" 0 "non-git directory must stay non-blocking"
assert_not_contains "entrypoint_size_blocking_ok" "$out" "a non-git run evaluated no delta and must not claim a blocking pass"
assert_contains "entrypoint_size_trend_partial: base=unknown" "$out" "non-git base is partial/unknown"
assert_contains "entrypoint_size_debt_count_base=unknown" "$out" "non-git base count unknown"
assert_contains "entrypoint_size_debt_count_delta=unknown" "$out" "non-git delta unknown"

set +e
out="$(CCL_SKILL_BASE_REF=refs/heads/does-not-exist bash "$SIZE_SCRIPT" "$REPO" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 0 "unavailable merge-base must stay non-blocking"
assert_contains "entrypoint_size_trend_partial: base=unknown" "$out" "missing base ref is partial/unknown"
assert_contains "entrypoint_size_debt_count_base=unknown" "$out" "missing base ref count unknown"
assert_contains "entrypoint_size_debt_count_delta=unknown" "$out" "missing base ref delta unknown"

# Case d1: agent-context/session-start.md over the tripwire band but UNCHANGED vs base => band
# advisory only, exit 0, marker. (Force the band low so a small fixture trips it
# deterministically. The file is committed on main and never touched on the
# branch: an over-band but UNTOUCHED agent-context/session-start.md must never hard-red an
# unrelated MR — only net growth blocks, see d3.)
git -C "$REPO" checkout -q main
printf 'every-session injection content that exceeds the tiny tripwire band.\n' > "$REPO/agent-context/session-start.md"
git -C "$REPO" add -A
git -C "$REPO" commit -qm "bootstrap baseline on main"
git -C "$REPO" checkout -qB feature
run_size BOOTSTRAP_BYTE_TRIPWIRE=10
assert_rc "$rc" 0 "over-band but unchanged bootstrap must stay non-blocking"
assert_contains "size_budget_advisory: agent-context/session-start.md is" "$out" "over-band advisory emitted"
assert_contains "tripwire" "$out" "advisory names the tripwire band"
assert_contains "size_budget_advisory_ok" "$out" "readable bootstrap keeps ok state"
assert_contains "entrypoint_size_budget_advisory_ok" "$out" "advisory marker present"
assert_not_contains "entrypoint_size_block: " "$out" "untouched bootstrap must not enter the blocking verdict"
assert_not_contains "changed_bootstrap_size_delta" "$out" "unchanged bootstrap emits no delta token"

# Case d2: tracked agent-context/session-start.md deleted (uncommitted) => nothing left to
# size-gate; partial marker (equivalent legacy signal), exit 0, no block.
rm -f "$REPO/agent-context/session-start.md"
run_size
assert_rc "$rc" 0 "missing bootstrap must stay non-blocking"
assert_contains "size_budget_advisory_partial" "$out" "missing bootstrap yields partial marker"
assert_contains "agent-context/session-start.md missing or unreadable" "$out" "partial reason reported"
assert_not_contains "entrypoint_size_block: " "$out" "deleted bootstrap has no size-gate object"

# Case d3: agent-context/session-start.md net GROWTH (uncommitted append) => block, rc 1. The
# every-session injection is permanently severe: any head_bytes > base_bytes
# fails the gate, regardless of the (advisory) band.
git -C "$REPO" checkout -- agent-context/session-start.md
printf 'one more line of always-on growth.\n' >> "$REPO/agent-context/session-start.md"
run_size
assert_rc "$rc" 1 "bootstrap net growth must block"
assert_contains "entrypoint_size_block: agent-context/session-start.md grew base_bytes=" "$out" "bootstrap-growth block token names base/head bytes"
assert_contains "changed_bootstrap_size_delta: agent-context/session-start.md" "$out" "bootstrap delta token emitted"
assert_contains "entrypoint_size_blocking_failed" "$out" "failed marker present"
assert_not_contains "entrypoint_size_blocking_ok" "$out" "no ok marker next to a block"
git -C "$REPO" checkout -- agent-context/session-start.md

# Case d4: agent-context/session-start.md shrink => allowed, rc 0 (shrinking the always-on layer
# is the encouraged direction, same family rule as severe entrypoints).
printf 'tiny.\n' > "$REPO/agent-context/session-start.md"
run_size
assert_rc "$rc" 0 "shrinking bootstrap must pass"
assert_contains "bootstrap_size_delta_ok: agent-context/session-start.md" "$out" "no-net-growth token emitted"
assert_contains "entrypoint_size_blocking_ok" "$out" "shrink is allowed"
git -C "$REPO" checkout -- agent-context/session-start.md

# Case d5: same byte size, different content (edited, not grown) => allowed.
boot_base_bytes=$(git -C "$REPO" show main:agent-context/session-start.md | wc -c | tr -d ' ')
{ repeat_char 'z' $(( boot_base_bytes - 1 )); printf '\n'; } > "$REPO/agent-context/session-start.md.tmp"
mv "$REPO/agent-context/session-start.md.tmp" "$REPO/agent-context/session-start.md"
[ "$(wc -c < "$REPO/agent-context/session-start.md" | tr -d ' ')" = "$boot_base_bytes" ] || fail "d5 fixture: byte count drifted from base"
run_size
assert_rc "$rc" 0 "same-size edit of bootstrap must pass"
assert_contains "bootstrap_size_delta_ok: agent-context/session-start.md" "$out" "same-size edit emits no-net-growth token"
assert_contains "entrypoint_size_blocking_ok" "$out" "same-size edit allowed"
git -C "$REPO" checkout -- agent-context/session-start.md

# Case d6: agent-context/session-start.md absent from BASE (new every-session-injection file,
# untracked) => block like a new severe entrypoint. Fresh repo for a clean base.
REPO2="$TMP/repo-bootstrap-new"
mkdir -p "$REPO2/skills/demo-skill" "$REPO2/agent-context"
git init -q -b main "$REPO2"
git -C "$REPO2" config user.email test@example.invalid
git -C "$REPO2" config user.name "Test User"
cp "$SKILL_MD" "$REPO2/skills/demo-skill/SKILL.md"
git -C "$REPO2" add -A
git -C "$REPO2" commit -qm "baseline without bootstrap"
git -C "$REPO2" checkout -qb feature
printf 'brand-new always-on injection surface.\n' > "$REPO2/agent-context/session-start.md"
set +e
out="$(env -u CCL_SKILL_BASE_REF bash "$SIZE_SCRIPT" "$REPO2" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 1 "a agent-context/session-start.md absent from base must block as a new every-session injection"
assert_contains "entrypoint_size_block: agent-context/session-start.md: new every-session-injection file" "$out" "new-injection block token"
assert_not_contains "entrypoint_size_blocking_ok" "$out" "no ok marker next to a block"

# Case d7: changed agent-context/session-start.md with an UNRESOLVABLE base => fail-closed
# partial, rc 1, NO ok markers (same family rule as a severe changed file).
printf 'growth under a lost base.\n' >> "$REPO/agent-context/session-start.md"
set +e
out="$(env CCL_SKILL_BASE_REF=definitely-not-a-ref bash "$SIZE_SCRIPT" "$REPO" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 1 "changed bootstrap with unknown base must fail closed"
assert_contains "entrypoint_size_block_partial: agent-context/session-start.md: base unknown" "$out" "partial names agent-context/session-start.md"
assert_contains "entrypoint_size_blocking_failed" "$out" "failed marker present"
assert_not_contains "entrypoint_size_blocking_ok" "$out" "no false ok next to partial"
assert_not_contains "entrypoint_size_budget_advisory_ok" "$out" "no legacy ok next to failure"
git -C "$REPO" checkout -- agent-context/session-start.md

# Case d8: growth landing on the BASE side after divergence never reddens the
# branch — base resolution is merge-base, so only the MR's own diff counts.
# Not merged => the target-branch growth is unreachable from HEAD (invisible);
# merged => the merge-base absorbs it. Only growth inside the branch's own diff
# blocks (d3).
git -C "$REPO" checkout -q main
printf 'growth landing on main after the branch diverged.\n' >> "$REPO/agent-context/session-start.md"
git -C "$REPO" commit -qam "main-side growth after divergence"
git -C "$REPO" checkout -q feature
run_size
assert_rc "$rc" 0 "base-side growth must not red the branch"
assert_contains "entrypoint_size_blocking_ok" "$out" "not-merged inherited growth is invisible"
git -C "$REPO" merge -q -m "merge main into feature" main
run_size
assert_rc "$rc" 0 "merged base-side growth must not red the branch either"
assert_contains "entrypoint_size_blocking_ok" "$out" "merged inherited growth is absorbed by merge-base"

# Case d9: committed bootstrap growth with an UNRESOLVABLE base and a CLEAN
# tree => nothing was delta-checked: bootstrap-scoped unevaluated token, rc 0,
# and NEVER the ok token (the base-less state is a caller-side pipeline
# responsibility; CI always exports CCL_SKILL_BASE_REF).
[ -z "$(git -C "$REPO" status --porcelain)" ] || fail "d9 fixture: tree must be clean"
set +e
out="$(env CCL_SKILL_BASE_REF=definitely-not-a-ref bash "$SIZE_SCRIPT" "$REPO" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 0 "base-less clean tree keeps the advisory exit contract"
assert_contains "bootstrap_size_delta_unevaluated: base=unknown — agent-context/session-start.md committed changes were NOT delta-checked" "$out" "bootstrap-scoped unevaluated token present"
assert_not_contains "entrypoint_size_blocking_ok" "$out" "a base-less run must never claim a blocking pass"

# Case d10: the baseline is the SAME path at base and nothing else, so a git mv
# of the always-on layer BLOCKS as a new every-session injection. That is the
# intended verdict, not a gap: a relocation is rare, deliberate, and worth a
# human decision, whereas every automatic recogniser tried here became a way for
# a candidate to nominate its own baseline (see d11). The first half pins that a
# byte-identical move still blocks; the second pins that git's rename pairing is
# never consulted, so an unrelated source cannot be adopted as the yardstick.
REPO3="$TMP/repo-bootstrap-move"
mkdir -p "$REPO3/skills/demo-skill"
git init -q -b main "$REPO3"
git -C "$REPO3" config user.email test@example.invalid
git -C "$REPO3" config user.name "Test User"
cp "$SKILL_MD" "$REPO3/skills/demo-skill/SKILL.md"
printf 'always-on injection body that is about to move, unchanged.\n' > "$REPO3/bootstrap.md"
git -C "$REPO3" add -A
git -C "$REPO3" commit -qm "baseline with bootstrap at the old path"
git -C "$REPO3" checkout -qb feature
mkdir -p "$REPO3/agent-context"
git -C "$REPO3" mv bootstrap.md agent-context/session-start.md
set +e
out="$(env -u CCL_SKILL_BASE_REF bash "$SIZE_SCRIPT" "$REPO3" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 1 "relocating the always-on layer must block — the baseline is the same path at base, nothing else"
assert_contains "new every-session-injection file" "$out" "a relocation reads as a new injection surface and needs a human decision"
assert_not_contains "renamed_from=" "$out" "the gate must not consult git rename pairing at all"
assert_not_contains "entrypoint_size_blocking_ok" "$out" "a relocation must never earn the blocking-ok token"

# Case d11: the budget must not be settable by CHOOSING a baseline. git detects
# renames by content similarity, not identity, so an unrelated tracked file moved
# onto the injection path is reported as a rename of that file. Any mechanism
# that believed such a pairing would let a candidate import a large blob as its
# own yardstick and inject far more than the real bootstrap while the delta still
# read non-positive. Independent review and adversarial challenge both landed on
# that bypass; the gate answers it by having no baseline-nomination path at all.
REPO4="$TMP/repo-bootstrap-baseline-swap"
mkdir -p "$REPO4/skills/demo-skill" "$REPO4/docs"
git init -q -b main "$REPO4"
git -C "$REPO4" config user.email test@example.invalid
git -C "$REPO4" config user.name "Test User"
cp "$SKILL_MD" "$REPO4/skills/demo-skill/SKILL.md"
printf 'the real always-on injection, deliberately small.\n' > "$REPO4/bootstrap.md"
{ printf 'unrelated reference document.\n'; repeat_char y 9000; printf '\n'; } > "$REPO4/docs/big-unrelated.md"
git -C "$REPO4" add -A
git -C "$REPO4" commit -qm "baseline: small bootstrap plus a large unrelated doc"
git -C "$REPO4" checkout -qb feature
mkdir -p "$REPO4/agent-context"
# Byte-identical content makes git report a 100% rename — exactly the pairing a
# rename-following gate would have believed.
git -C "$REPO4" rm -q bootstrap.md
git -C "$REPO4" mv docs/big-unrelated.md agent-context/session-start.md
set +e
out="$(env -u CCL_SKILL_BASE_REF bash "$SIZE_SCRIPT" "$REPO4" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 1 "an unrelated file moved onto the injection path must not become its own baseline"
assert_contains "new every-session-injection file" "$out" "the swap is refused, not measured against the imported blob"
assert_not_contains "docs/big-unrelated.md" "$out" "the unrelated rename source must never appear as a baseline"

# ---------------------------------------------------------------------------
# Delta-blocking series (fresh repo, deterministic): new/crossing severe and
# severe growth block; shrink, sub-severe growth, and same-size edits pass.
REPO="$TMP/repo-blocking"
mkdir -p "$REPO/skills/demo-skill"
git init -q -b main "$REPO"
git -C "$REPO" config user.email test@example.invalid
git -C "$REPO" config user.name "Test User"
SKILL_MD="$REPO/skills/demo-skill/SKILL.md"

write_skill_with_body_bytes() { # <path> <total-bytes-approx>
  {
    printf -- '---\nname: demo-skill\ndescription: blocking series fixture.\n---\n\n'
    repeat_char x "$2"
  } > "$1"
}

# Baseline: 49KB (sub-severe).
write_skill_with_body_bytes "$SKILL_MD" 49000
git -C "$REPO" add -A
git -C "$REPO" commit -qm "baseline 49k"
git -C "$REPO" checkout -qb feature

# Case e1: 49KB -> 51KB crosses the severe threshold => block, rc 1.
write_skill_with_body_bytes "$SKILL_MD" 51000
run_size
assert_rc "$rc" 1 "crossing into severe must block"
assert_contains "entrypoint_size_block: skills/demo-skill/SKILL.md: new severe entrypoint" "$out" "new-severe block token"
assert_contains "entrypoint_size_blocking_failed" "$out" "failed marker present"

# Case e2: back to 49KB => clean again, rc 0, blocking_ok.
write_skill_with_body_bytes "$SKILL_MD" 49000
run_size
assert_rc "$rc" 0 "sub-severe entrypoint must pass"
assert_contains "entrypoint_size_blocking_ok" "$out" "blocking ok marker"

# Case e3: 51KB on MAIN (inside the merge-base), then grow to 52KB on a branch
# => growth of an already-severe entrypoint blocks. (A 51KB commit merely on the
# feature branch is a new-severe introduction instead — merge-base semantics.)
git -C "$REPO" checkout -q main
write_skill_with_body_bytes "$SKILL_MD" 51000
git -C "$REPO" add -A
git -C "$REPO" commit -qm "base 51k severe on main"
git -C "$REPO" checkout -qb feature2
write_skill_with_body_bytes "$SKILL_MD" 52000
run_size
assert_rc "$rc" 1 "severe growth must block"
assert_contains "entrypoint_size_block: skills/demo-skill/SKILL.md: severe entrypoint grew" "$out" "severe-growth block token"
assert_contains "entrypoint_size_blocking_failed" "$out" "failed marker present"

# Case e4: shrink 52KB -> 50KB (still severe but smaller) => allowed, rc 0.
write_skill_with_body_bytes "$SKILL_MD" 50050
run_size
assert_rc "$rc" 0 "shrinking a severe entrypoint must pass"
assert_contains "entrypoint_size_blocking_ok" "$out" "shrink is allowed"

# Case e5: a brand-new severe file (untracked) => new-severe block.
mkdir -p "$REPO/skills/fresh-skill"
write_skill_with_body_bytes "$REPO/skills/fresh-skill/SKILL.md" 60000
run_size
assert_rc "$rc" 1 "untracked severe file must block"
assert_contains "entrypoint_size_block: skills/fresh-skill/SKILL.md: new severe entrypoint" "$out" "untracked new-severe block"
rm -f "$REPO/skills/fresh-skill/SKILL.md"

# Case e6: same byte size, different content (edited, not grown) => allowed.
# Rebuild the file to the EXACT same byte count (header + padded body).
# Rebuild to EXACTLY the base byte count with different content (true
# same-size edit, not a shrink): merge-base holds the 51k severe state.
base_bytes=$(git -C "$REPO" show "$(git -C "$REPO" merge-base main HEAD):skills/demo-skill/SKILL.md" | wc -c | tr -d ' ')
header_bytes=$(printf -- '---\nname: demo-skill\ndescription: edited same size variant.\n---\n\n' | wc -c | tr -d ' ')
{ printf -- '---\nname: demo-skill\ndescription: edited same size variant.\n---\n\n'; repeat_char y $(( base_bytes - header_bytes )); } > "$SKILL_MD.tmp"
mv "$SKILL_MD.tmp" "$SKILL_MD"
[ "$(wc -c < "$SKILL_MD" | tr -d ' ')" = "$base_bytes" ] || fail "e6 fixture: byte count drifted from base"
run_size
assert_rc "$rc" 0 "same-size edit of a severe entrypoint must pass"
assert_contains "entrypoint_size_blocking_ok" "$out" "same-size edit allowed"

# Case e7b: rename a severe entrypoint to a new path => move_ok, not a block.
# The severe deletion in the same diff covers the new severe file; a net-new
# severe would still block (e1).
git -C "$REPO" checkout -q main 2>/dev/null || git -C "$REPO" checkout -q -b main
write_skill_with_body_bytes "$SKILL_MD" 50050
git -C "$REPO" add -A && git -C "$REPO" commit -qm "50k on main for rename case"
git -C "$REPO" checkout -qb feature3
mkdir -p "$REPO/skills/moved-skill"
git -C "$REPO" mv skills/demo-skill/SKILL.md skills/moved-skill/SKILL.md
run_size
assert_rc "$rc" 0 "rename of a severe entrypoint must pass as move"
assert_contains "entrypoint_size_move_ok: skills/moved-skill/SKILL.md" "$out" "move token names the new path"
assert_contains "entrypoint_size_blocking_ok" "$out" "move does not block"

# Case e7d: the file STAYS at the renamed path and grows => the move credit is
# withdrawn and it blocks as a NEW severe entrypoint (the R pair no longer covers
# it because head > source). This is the real rename-and-grow shape; e7c below
# moves the file BACK to its base path, which git reports as an ordinary same-path
# modification and therefore exercises the growth branch instead — keep both, they
# are different branches of the verdict.
write_skill_with_body_bytes "$REPO/skills/moved-skill/SKILL.md" 62000
run_size
assert_rc "$rc" 1 "rename that also grows must block"
assert_contains "entrypoint_size_block: skills/moved-skill/SKILL.md: new severe entrypoint" "$out" "rename+growth blocks as new-severe, not as growth"
assert_not_contains "entrypoint_size_move_ok" "$out" "move credit must not survive growth"
assert_not_contains "entrypoint_size_blocking_ok" "$out" "no ok marker next to a block"
write_skill_with_body_bytes "$REPO/skills/moved-skill/SKILL.md" 50050

# Case e7c: moving the file BACK to a path that is already severe in base, and
# growing it, blocks on the severe-growth branch (same-path modification).
git -C "$REPO" mv skills/moved-skill/SKILL.md skills/demo-skill/SKILL.md
write_skill_with_body_bytes "$REPO/skills/demo-skill/SKILL.md" 62000
run_size
assert_rc "$rc" 1 "move-back-and-grow must block"
assert_contains "entrypoint_size_block: skills/demo-skill/SKILL.md: severe entrypoint grew" "$out" "an already-severe base path that grows blocks as growth"

# Case e7: base unknown (bad CCL_SKILL_BASE_REF) + severe UNTRACKED file
# (visible in `changed` regardless of base) => fail-closed partial, rc 1, NO ok
# markers (the P0 false-pass shape). Note: committed-only changes without a
# resolvable base are invisible to the delta gate by design — CI always exports
# CCL_SKILL_BASE_REF.
mkdir -p "$REPO/skills/rogue-skill"
write_skill_with_body_bytes "$REPO/skills/rogue-skill/SKILL.md" 51000
set +e
out="$(env CCL_SKILL_BASE_REF=definitely-not-a-ref bash "$SIZE_SCRIPT" "$REPO" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 1 "unknown base must fail closed"
assert_contains "entrypoint_size_block_partial: skills/rogue-skill/SKILL.md: base unknown" "$out" "partial names the file"
assert_contains "entrypoint_size_blocking_failed" "$out" "failed marker present"
assert_not_contains "entrypoint_size_blocking_ok" "$out" "no false ok next to partial"
assert_not_contains "entrypoint_size_budget_advisory_ok" "$out" "no legacy ok next to failure"
rm -rf "$REPO/skills/rogue-skill"

# Case e9: committed-only severe growth with an UNRESOLVABLE base and a CLEAN
# tree. The delta gate cannot see the committed change at all, so it evaluates
# nothing — it must NOT print entrypoint_size_blocking_ok, because a consumer
# gating on that token would otherwise earn a pass simply by losing its base.
# The exit code stays 0 on purpose (the script also runs outside a worktree);
# reddening this state is the caller's pipeline decision, and CI always exports
# CCL_SKILL_BASE_REF.
git -C "$REPO" add -A
git -C "$REPO" commit -qm "commit the severe growth so the tree is clean"
[ -z "$(git -C "$REPO" status --porcelain)" ] || fail "e9 fixture: tree must be clean"
set +e
out="$(env CCL_SKILL_BASE_REF=definitely-not-a-ref bash "$SIZE_SCRIPT" "$REPO" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 0 "base-less clean tree keeps the advisory exit contract"
assert_contains "entrypoint_size_blocking_unevaluated" "$out" "un-evaluated delta gate says so"
assert_not_contains "entrypoint_size_blocking_ok" "$out" "a base-less run must never claim a blocking pass"

# Case e8: gate wiring anchors — the validator must fail the gate on non-zero
# and must not demote the size gate back to advisory.
validator="$SCRIPT_DIR/check-ccl-skills.sh"
grep -q '|| size_budget_rc=\$?' "$validator" || fail "validator no longer records size-gate rc"
grep -q 'entrypoint_size_budget_blocking_failed (block or partial' "$validator" || fail "validator missing blocking failure message"
grep -q 'check-size-budget.sh missing' "$validator" || fail "validator missing missing-script fail-closed branch"
grep -q 'entrypoint_size_budget_infra_failed' "$validator" || fail "validator missing infra-failure distinction (ruby crash/missing must not read as size block)"
size_wiring_line="$(grep -F 'bash "$size_budget_script" "$root" ||' "$validator")"
[ -n "$size_wiring_line" ] || fail "validator size-gate invocation line not found (wiring anchor moved?)"
case "$size_wiring_line" in
  *"|| true"*) fail "validator demoted size gate back to || true advisory" ;;
esac

echo "test_check_ccl_size_budget: ok"
