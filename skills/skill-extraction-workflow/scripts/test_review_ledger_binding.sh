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

out="$(run_gate)"; rc=$?
check "a missing base ref reports an unevaluated gate rather than a pass verdict" \
  '[ "$rc" = 0 ] && case "$out" in *"gate not evaluated"*) true;; *) false;; esac'

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
check "a wording-only proof bound to the landing candidate satisfies the gate" \
  '[ "$rc" = 0 ] && case "$out" in *"wording-only proof binds"*) true;; *) false;; esac'

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
check "a wording-only proof for another candidate does not satisfy the gate" \
  '[ "$rc" = 1 ] && case "$out" in *"no accepted review evidence"*) true;; *) false;; esac'

if [ "$fails" -gt 0 ]; then
  echo "test_review_ledger_binding: $fails failing case(s)" >&2
  exit 1
fi
echo "test_review_ledger_binding: ok"
