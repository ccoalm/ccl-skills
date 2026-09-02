#!/usr/bin/env bash
# Regression for the merge-side binding between the landing candidate and the
# review evidence that inspected it.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
GATE="$DIR/review_ledger_binding.py"
CONTROLLER="$DIR/../../code-review/scripts/review_gate.py"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/review-ledger-binding.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

fails=0
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fails=$((fails+1)); fi; }

[ -f "$GATE" ] || { echo "FAIL: gate missing: $GATE" >&2; exit 1; }
[ -f "$CONTROLLER" ] || { echo "FAIL: controller missing: $CONTROLLER" >&2; exit 1; }

REPO="$WORK/repo"
mkdir -p "$REPO/skills/code-review/scripts" "$REPO/skills/skill-extraction-workflow/scripts" "$REPO/specs/round/evidence"
cp "$CONTROLLER" "$REPO/skills/code-review/scripts/review_gate.py"
# The gate delegates ledger acceptance to the validator; these stubs isolate the
# gate's own contract (recompute the packet, bind it, delegate) from the
# validator's fixture surface, which its own suite already covers.
cat >"$REPO/skills/skill-extraction-workflow/scripts/validate_extraction_review_state.py" <<'PY'
import sys
print("extraction_review_state_ok: stub accepted")
sys.exit(0)
PY
cat >"$WORK/reject-validator.py" <<'PY'
import sys
print("extraction_review_state_invalid: stub rejected")
sys.exit(1)
PY

git -C "$REPO" init -q .
git -C "$REPO" config user.email t@example.invalid
git -C "$REPO" config user.name tester
printf 'baseline\n' >"$REPO/skills/skill-extraction-workflow/SKILL.md"
git -C "$REPO" add -A
git -C "$REPO" commit -qm baseline
BASE="$(git -C "$REPO" rev-parse HEAD)"

run_gate() { python3 "$GATE" --repo-root "$REPO" "$@" 2>&1; }

out="$(run_gate --base "$BASE")"; rc=$?
check "an unchanged reviewed path needs no review evidence" \
  '[ "$rc" = 0 ] && case "$out" in *"no reviewed-path change"*) true;; *) false;; esac'

out="$(CCL_SKILL_BASE_REF= run_gate)"; rc=$?
check "a missing base ref fails closed instead of recording a passing check" \
  '[ "$rc" = 2 ] && case "$out" in *"nothing was checked"*) true;; *) false;; esac'

out="$(CCL_SKILL_BASE_REF= run_gate --allow-unevaluated)"; rc=$?
check "an event with genuinely no base must say so out loud to exit clean" \
  '[ "$rc" = 0 ] && case "$out" in *"nothing was checked"*) true;; *) false;; esac'

out="$(CCL_SKILL_BASE_REF="$BASE" run_gate)"; rc=$?
check "the gate reads the base from the environment variable its diagnostic names" \
  '[ "$rc" = 0 ] && case "$out" in *"no reviewed-path change"*) true;; *) false;; esac'

# The fix batch lands under the reviewed paths.
printf 'baseline\nlanded change\n' >"$REPO/skills/skill-extraction-workflow/SKILL.md"
git -C "$REPO" add -A
git -C "$REPO" commit -qm "landing change"

out="$(run_gate --base "$BASE")"; rc=$?
check "a reviewed-path change with no evidence fails closed" \
  '[ "$rc" = 1 ] && case "$out" in *"no accepted review evidence binds the landing candidate"*) true;; *) false;; esac'
EXPECTED="$(run_gate --base "$BASE" --print-candidate)"
check "the gate can name the candidate hash the evidence must carry" \
  '[ -n "$EXPECTED" ] && case "$out" in *"$EXPECTED"*) true;; *) false;; esac'

# Evidence for a different candidate must not satisfy the gate: this is the exact
# shape the gate exists to catch -- a chain that closed out on the pre-fix tree.
python3 - "$REPO/specs/round/evidence/stale-closeout.json"  <<'JSONGEN'
import json, sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({"schema_version": 3, "closeout_state": "ready_for_human_decision", "controller_receipts": [], "candidate_sha256": "0" * 64}))
JSONGEN
git -C "$REPO" add -A && git -C "$REPO" commit -qm "stale evidence"
out="$(run_gate --base "$BASE")"; rc=$?
check "a ledger bound to another candidate does not satisfy the gate" \
  '[ "$rc" = 1 ] && case "$out" in *"no accepted review evidence"*) true;; *) false;; esac'

# Committing evidence must not move the candidate: evidence lives outside the
# reviewed paths, which is what lets a ledger record the tree that carries it.
EXPECTED_AFTER="$(run_gate --base "$BASE" --print-candidate)"
check "committing evidence outside the reviewed paths leaves the candidate unmoved" \
  '[ "$EXPECTED_AFTER" = "$EXPECTED" ]'

# A ledger that binds the landing candidate but fails validation is reported as a
# rejected ledger, never silently ignored. Swapping the validator edits a reviewed
# path, so the candidate moves and the ledger is written against the moved hash.
cp "$WORK/reject-validator.py" "$REPO/skills/skill-extraction-workflow/scripts/validate_extraction_review_state.py"
git -C "$REPO" add -A && git -C "$REPO" commit -qm "rejecting validator"
REJECT_CANDIDATE="$(run_gate --base "$BASE" --print-candidate)"
check "editing a reviewed path moves the candidate the evidence must bind" \
  '[ -n "$REJECT_CANDIDATE" ] && [ "$REJECT_CANDIDATE" != "$EXPECTED" ]'
python3 - "$REPO/specs/round/evidence/closeout.json" "$REJECT_CANDIDATE" <<'JSONGEN'
import json, sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({"schema_version": 3, "closeout_state": "ready_for_human_decision", "controller_receipts": [], "candidate_sha256": sys.argv[2]}))
JSONGEN
git -C "$REPO" add -A && git -C "$REPO" commit -qm "rejected ledger"
out="$(run_gate --base "$BASE")"; rc=$?
check "a bound but invalid ledger is reported as rejected, not ignored" \
  '[ "$rc" = 1 ] && case "$out" in *"rejected ledger"*"stub rejected"*) true;; *) false;; esac'

cat >"$REPO/skills/skill-extraction-workflow/scripts/validate_extraction_review_state.py" <<'ACCEPTSTUB'
import sys
print("extraction_review_state_ok: stub accepted")
sys.exit(0)
ACCEPTSTUB
git -C "$REPO" add -A && git -C "$REPO" commit -qm "accepting validator"
ACCEPT_CANDIDATE="$(run_gate --base "$BASE" --print-candidate)"
python3 - "$REPO/specs/round/evidence/closeout.json" "$ACCEPT_CANDIDATE" <<'JSONGEN'
import json, sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({"schema_version": 3, "closeout_state": "ready_for_human_decision", "controller_receipts": [], "candidate_sha256": sys.argv[2]}))
JSONGEN
git -C "$REPO" add -A && git -C "$REPO" commit -qm "accepted ledger"
out="$(run_gate --base "$BASE")"; rc=$?
check "a validated ledger bound to the landing candidate passes the gate" \
  '[ "$rc" = 0 ] && case "$out" in *"binds the landing candidate"*) true;; *) false;; esac'

# The wording-only lane records a single review receipt rather than a ledger.
rm "$REPO/specs/round/evidence/closeout.json"
python3 - "$REPO/specs/round/evidence/wording-review.json" "$ACCEPT_CANDIDATE" <<'JSONGEN'
import json, sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({"schema_version": 3, "mode": "review", "candidate_sha256": sys.argv[2], "wording_only_proof_sha256": "b" * 64}))
JSONGEN
git -C "$REPO" add -A && git -C "$REPO" commit -qm "wording-only proof"
out="$(run_gate --base "$BASE")"; rc=$?
check "a hand-writable receipt-shaped file never satisfies the gate" \
  '[ "$rc" = 1 ] && case "$out" in *"no accepted review evidence"*) true;; *) false;; esac'

# Precision: a wording-only receipt for a different candidate must not pass.
python3 - "$REPO/specs/round/evidence/wording-review.json" <<'PY'
import json, sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({
    "schema_version": 3,
    "mode": "review",
    "candidate_sha256": "1" * 64,
    "wording_only_proof_sha256": "b" * 64,
}))
PY
git -C "$REPO" add -A && git -C "$REPO" commit -qm "stale wording-only proof"
out="$(run_gate --base "$BASE")"; rc=$?
check "a receipt-shaped file for another candidate does not satisfy the gate" \
  '[ "$rc" = 1 ] && case "$out" in *"no accepted review evidence"*) true;; *) false;; esac'

# An option-shaped base must not reach git as an option: git diff with no revision
# compares the index to the working tree, which in a clean checkout reports no
# paths and would let the gate pass having compared nothing.
# The environment path is the one that reaches git without an argument parser in
# front of it, which is exactly how such a base arrives in CI.
for bad_base in --quiet --name-only refs/heads/does-not-exist; do
  out="$(CCL_SKILL_BASE_REF="$bad_base" run_gate)"; rc=$?
  check "an unresolvable base ($bad_base) is refused, not silently treated as no change" \
    '[ "$rc" = 1 ] && case "$out" in *"does not resolve to a commit"*) true;; *) false;; esac'
done

out="$(run_gate --base "$BASE^{commit}")"; rc=$?
check "a revision expression that does resolve is still accepted" \
  '[ "$rc" = 1 ] && case "$out" in *"no accepted review evidence"*) true;; *) false;; esac'

# The gate must not perturb the tree it hashes; asserting only that a hash comes
# back would stay green if bytecode writes or packet cleanup regressed.
before_state="$(git -C "$REPO" status --porcelain --ignored)"
run_gate --base "$BASE" --print-candidate >/dev/null 2>&1
after_state="$(git -C "$REPO" status --porcelain --ignored)"
check "running the gate leaves the hashed tree byte-identical" \
  '[ "$before_state" = "$after_state" ]'

# What merges is the committed tree, so uncommitted evidence is not evidence about
# the landing candidate: reading it would accept a ledger nobody can find later.
printf '{"unfinished": true}\n' >"$REPO/specs/round/evidence/uncommitted.json"
out="$(run_gate --base "$BASE")"; rc=$?
check "an uncommitted evidence tree is refused rather than read from disk" \
  '[ "$rc" = 1 ] && case "$out" in *"uncommitted changes"*) true;; *) false;; esac'
rm "$REPO/specs/round/evidence/uncommitted.json"

# An unrelated advance on the base branch must not restate what this branch is:
# measured against the tip it would, and evidence that is still correct would go
# stale every time somebody else merged.
BEFORE_ADVANCE="$(run_gate --base "$BASE" --print-candidate)"
git -C "$REPO" checkout -q -b other-work "$BASE"
printf 'unrelated\n' >"$REPO/skills/code-review/UNRELATED.md"
git -C "$REPO" add -A && git -C "$REPO" commit -qm "unrelated work on the base branch"
ADVANCED="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" checkout -q -
AFTER_ADVANCE="$(run_gate --base "$ADVANCED" --print-candidate)"
check "an unrelated advance on the base branch leaves the candidate unchanged" \
  '[ -n "$BEFORE_ADVANCE" ] && [ "$AFTER_ADVANCE" = "$BEFORE_ADVANCE" ]'

# Scope: which paths the candidate is computed over. A whitelist of the paths the
# round happened to review leaves every other tracked path unbound, so a pull
# request can carry a ledger valid for its skill changes while also landing a root
# build script nobody reviewed -- the extra content does not move the candidate, so
# the existing ledger still passes. The bound set is therefore every tracked path
# except the evidence tree, which must stay outside it: evidence that moved the
# candidate it records could never be committed.
SCOPE="$WORK/scope-repo"
mkdir -p "$SCOPE/skills/code-review/scripts" "$SCOPE/skills/skill-extraction-workflow/scripts" "$SCOPE/specs/round/evidence" "$SCOPE/scripts"
cp "$CONTROLLER" "$SCOPE/skills/code-review/scripts/review_gate.py"
cat >"$SCOPE/skills/skill-extraction-workflow/scripts/validate_extraction_review_state.py" <<'PY'
import sys
print("extraction_review_state_ok: stub accepted")
sys.exit(0)
PY
git -C "$SCOPE" init -q .
git -C "$SCOPE" config user.email t@example.invalid
git -C "$SCOPE" config user.name tester
printf 'baseline\n' >"$SCOPE/skills/skill-extraction-workflow/SKILL.md"
printf 'test:\n\t@echo baseline\n' >"$SCOPE/Makefile"
printf 'baseline\n' >"$SCOPE/README.md"
printf 'baseline\n' >"$SCOPE/scripts/release.sh"
# Committed review history for the earlier round: a plan and a receipt that already
# exist at the base. These are what a later pull request must not be able to rewrite
# unnoticed.
printf 'earlier round plan\n' >"$SCOPE/specs/round/plan.md"
printf '{"schema_version": 3, "closeout_state": "ready_for_human_decision"}\n' \
  >"$SCOPE/specs/round/evidence/history.json"
git -C "$SCOPE" add -A
git -C "$SCOPE" commit -qm baseline
SCOPE_BASE="$(git -C "$SCOPE" rev-parse HEAD)"

run_scope() { python3 "$GATE" --repo-root "$SCOPE" "$@" 2>&1; }

# Each of these is an executable or consumer-facing tracked path outside the
# reviewed-skill tree. Landing one with no evidence is the failure the whitelist
# admitted: before the bound set was inverted every one of them reported
# "no reviewed-path change" and merged unreviewed.
for unbound in Makefile README.md scripts/release.sh; do
  git -C "$SCOPE" checkout -q -B "probe" "$SCOPE_BASE"
  printf 'landed unreviewed\n' >>"$SCOPE/$unbound"
  git -C "$SCOPE" add -A && git -C "$SCOPE" commit -qm "land $unbound with no evidence"
  out="$(run_scope --base "$SCOPE_BASE")"; rc=$?
  check "a change to $unbound alone needs review evidence like any other tracked path" \
    '[ "$rc" = 1 ] && case "$out" in *"no accepted review evidence binds the landing candidate"*) true;; *) false;; esac'
done

# The other half of the same decision: a committed receipt stays excluded. If it did
# not, committing a ledger would move the candidate that ledger records and no
# ledger could ever bind its own landing candidate.
git -C "$SCOPE" checkout -q -B "evidence-only" "$SCOPE_BASE"
printf '{"schema_version": 3, "candidate_sha256": "%s"}\n' \
  "0000000000000000000000000000000000000000000000000000000000000000" \
  >"$SCOPE/specs/round/evidence/note.json"
git -C "$SCOPE" add -A && git -C "$SCOPE" commit -qm "land a receipt only"
out="$(run_scope --base "$SCOPE_BASE")"; rc=$?
check "a change confined to added receipts still reports no reviewed-path change" \
  '[ "$rc" = 0 ] && case "$out" in *"no reviewed-path change"*) true;; *) false;; esac'

# The exclusion covers what this round ADDS, not the whole tree. Committed review
# history is the record the gate exists to protect, so rewriting or deleting an
# earlier round's plan or receipt has to reach the candidate like any other change.
for corruption in rewrite-plan rewrite-receipt delete-receipt; do
  git -C "$SCOPE" checkout -q -B "corrupt" "$SCOPE_BASE"
  case "$corruption" in
    rewrite-plan)    printf 'rewritten by a later round\n' >"$SCOPE/specs/round/plan.md";;
    rewrite-receipt) printf '{"schema_version": 3, "closeout_state": "forged"}\n' \
                       >"$SCOPE/specs/round/evidence/history.json";;
    delete-receipt)  rm "$SCOPE/specs/round/evidence/history.json";;
  esac
  git -C "$SCOPE" add -A && git -C "$SCOPE" commit -qm "$corruption"
  out="$(run_scope --base "$SCOPE_BASE")"; rc=$?
  check "a later round cannot $corruption of committed review history without evidence" \
    '[ "$rc" = 1 ] && case "$out" in *"no accepted review evidence binds the landing candidate"*) true;; *) false;; esac'
done

# The exclusion is about what a file IS, not where it sits. An evidence directory is
# where receipts belong, but the directory alone must not buy exclusion: otherwise a
# script, a fixture, or any other artifact committed there lands unreviewed while an
# unchanged ledger still passes.
for smuggled in payload.py fixture.bin notes.json; do
  git -C "$SCOPE" checkout -q -B "smuggle" "$SCOPE_BASE"
  mkdir -p "$SCOPE/specs/new-round/evidence"
  case "$smuggled" in
    payload.py)  printf 'import os\nos.system("echo landed")\n' >"$SCOPE/specs/new-round/evidence/$smuggled";;
    fixture.bin) printf 'not text at all\n' >"$SCOPE/specs/new-round/evidence/$smuggled";;
    notes.json)  printf '{"note": "json, but binds no candidate"}\n' >"$SCOPE/specs/new-round/evidence/$smuggled";;
  esac
  git -C "$SCOPE" add -A && git -C "$SCOPE" commit -qm "smuggle $smuggled"
  out="$(run_scope --base "$SCOPE_BASE")"; rc=$?
  check "an added $smuggled under an evidence directory is bound, not excluded" \
    '[ "$rc" = 1 ] && case "$out" in *"no accepted review evidence binds the landing candidate"*) true;; *) false;; esac'
done

# The candidate has to be the tree a clean checkout recomputes. An uncommitted edit
# or a scratch file inside the bound paths would otherwise produce a hash only this
# working copy can reproduce, which the author then records in the ledger.
git -C "$SCOPE" checkout -q -B "dirty-probe" "$SCOPE_BASE"
printf 'scratch\n' >"$SCOPE/scratch-note.txt"
out="$(run_scope --base "$SCOPE_BASE" --print-candidate)"; rc=$?
check "an untracked file inside the bound paths refuses instead of printing an unreproducible hash" \
  '[ "$rc" != 0 ] && case "$out" in *"uncommitted changes"*) true;; *) false;; esac'
rm "$SCOPE/scratch-note.txt"
printf 'unstaged edit\n' >>"$SCOPE/Makefile"
out="$(run_scope --base "$SCOPE_BASE" --print-candidate)"; rc=$?
check "an unstaged edit inside the bound paths refuses instead of printing an unreproducible hash" \
  '[ "$rc" != 0 ] && case "$out" in *"uncommitted changes"*) true;; *) false;; esac'
git -C "$SCOPE" checkout -q -- Makefile
out="$(run_scope --base "$SCOPE_BASE" --print-candidate)"; rc=$?
check "the same clean checkout still reaches its normal verdict" \
  '[ "$rc" = 0 ] && case "$out" in *"no reviewed-path change"*) true;; *) false;; esac'

# The suite above exercises a synthetic repository. The gate must also run against
# the real checkout it ships in, or a break in that path passes every test here.
REAL_ROOT="$(cd "$DIR/../../.." && pwd -P)"
real_out="$(env -u CCL_SKILL_BASE_REF python3 "$GATE" --repo-root "$REAL_ROOT" --base HEAD~1 --print-candidate 2>&1)"; real_rc=$?
# Both outputs are legitimate and which one appears depends on what the parent
# commit happened to touch: a candidate hash when a reviewed path moved, the
# no-change signal when it did not. Accepting only the first makes this assertion
# a function of repository state rather than of the gate.
# Which answer is legitimate depends on the checkout, so decide that FIRST and then
# assert the one matching branch. Accepting every output would make this assertion a
# function of repository state; branching on the state keeps it an assertion about
# the gate. A dirty checkout is a legitimate state for a developer to run in, and
# the gate must refuse there rather than print a hash nobody else can recompute.
real_dirty="$(git -C "$REAL_ROOT" status --porcelain)"
if [ -n "$real_dirty" ]; then
  check "the gate refuses to answer for a real checkout that is not committed" \
    '[ "$real_rc" != 0 ] && case "$real_out" in *"uncommitted changes"*) true;; *) false;; esac'
else
  check "the gate answers for the clean real checkout it ships in, whichever legitimate answer applies" \
    '[ "$real_rc" = 0 ] && { case "$real_out" in [0-9a-f]*) [ ${#real_out} = 64 ];; *) false;; esac || case "$real_out" in *review_ledger_binding_no_change*) true;; *) false;; esac; }'
fi

if [ "$fails" -gt 0 ]; then
  echo "test_review_ledger_binding: $fails failing case(s)" >&2
  exit 1
fi
echo "test_review_ledger_binding: ok"
