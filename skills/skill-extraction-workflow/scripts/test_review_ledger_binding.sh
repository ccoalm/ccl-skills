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

# Partition: the candidate's Git identity is base..HEAD, but the packet a reviewer
# can read is capped at the controller's byte ceiling. A landing candidate larger
# than one packet used to be unlandable as one pull request -- the whole-candidate
# freeze failed and no ledger could ever bind it -- so authors split the pull
# request instead of the review. A committed landing partition manifest names
# path partitions that together cover every changed file exactly once, each bound
# by its own validated ledger; the gate recomputes every partition and refuses any
# manifest whose parts do not add up to the whole.
PART="$WORK/partition-repo"
mkdir -p "$PART/skills/code-review/scripts" "$PART/skills/skill-extraction-workflow/scripts" "$PART/specs/round/evidence" "$PART/lane-a" "$PART/lane-b"
cp "$CONTROLLER" "$PART/skills/code-review/scripts/review_gate.py"
cat >"$PART/skills/skill-extraction-workflow/scripts/validate_extraction_review_state.py" <<'PY'
import sys
print("extraction_review_state_ok: stub accepted")
sys.exit(0)
PY
git -C "$PART" init -q .
git -C "$PART" config user.email t@example.invalid
git -C "$PART" config user.name tester
printf 'baseline\n' >"$PART/skills/skill-extraction-workflow/SKILL.md"
printf 'baseline\n' >"$PART/lane-a/big.txt"
printf 'baseline\n' >"$PART/lane-b/big.txt"
git -C "$PART" add -A && git -C "$PART" commit -qm baseline
PART_BASE="$(git -C "$PART" rev-parse HEAD)"

run_part() { python3 "$GATE" --repo-root "$PART" "$@" 2>&1; }

# The manifest oracle mirrors the documented canonical form (sorted keys, compact
# separators, UTF-8) independently of the gate, so a drift in either side reds.
cat >"$WORK/write-manifest.py" <<'PY'
import hashlib, json, sys
out, base, aggregate = sys.argv[1], sys.argv[2], sys.argv[3]
partitions = []
for spec in sys.argv[4:]:
    paths, digest = spec.rsplit("=", 1)
    partitions.append({"paths": paths.split(), "candidate_sha256": digest})
body = {"schema_version": 1, "kind": "landing_partition_manifest", "base": base, "partitions": partitions}
if aggregate == "AUTO":
    canonical = json.dumps(body, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    aggregate = hashlib.sha256(canonical).hexdigest()
body["candidate_sha256"] = aggregate
with open(out, "w", encoding="utf-8") as handle:
    json.dump(body, handle, indent=2)
    handle.write("\n")
PY
write_closeout() { python3 - "$1" "$2" <<'PY'
import json, sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({"schema_version": 3, "closeout_state": "ready_for_human_decision", "controller_receipts": [], "candidate_sha256": sys.argv[2]}))
PY
}

# Two lanes each change ~130 KB: either fits one packet, the pair does not.
python3 - "$PART" <<'PY'
import sys
from pathlib import Path
root = Path(sys.argv[1])
for lane in ("lane-a", "lane-b"):
    lines = [f"{lane} line {index:06d} " + "x" * 40 for index in range(2200)]
    (root / lane / "big.txt").write_text("\n".join(lines) + "\n")
PY
git -C "$PART" add -A && git -C "$PART" commit -qm "oversized landing"

out="$(run_part --base "$PART_BASE")"; rc=$?
check "a candidate too large for one packet is refused with the partition recipe, not a bare freeze error" \
  '[ "$rc" = 1 ] && case "$out" in *"exceeds 200000 bytes"*"landing partition manifest"*) true;; *) false;; esac'

MANIFEST_JSON="$(run_part --base "$PART_BASE" --print-manifest --partition lane-a --partition lane-b)"; rc=$?
check "the gate renders a manifest for a partition that covers the whole candidate" \
  '[ "$rc" = 0 ] && python3 -c "import json,sys; m=json.loads(sys.argv[1]); assert m[\"kind\"]==\"landing_partition_manifest\" and len(m[\"partitions\"])==2 and m[\"base\"]==sys.argv[2]" "$MANIFEST_JSON" "$PART_BASE"'

out="$(run_part --base "$PART_BASE" --print-manifest --partition lane-a)"; rc=$?
check "rendering refuses a partition that leaves a changed path uncovered" \
  '[ "$rc" != 0 ] && case "$out" in *"uncovered"*"lane-b/big.txt"*) true;; *) false;; esac'

out="$(run_part --base "$PART_BASE" --print-manifest --partition lane-a --partition lane-a/big.txt lane-b)"; rc=$?
check "rendering refuses partitions that overlap on a changed path" \
  '[ "$rc" != 0 ] && case "$out" in *"overlap"*"lane-a/big.txt"*) true;; *) false;; esac'

out="$(run_part --base "$PART_BASE" --print-manifest --partition lane-a --partition lane-a lane-b)"; rc=$?
check "rendering refuses the same path listed in two partitions before touching git" \
  '[ "$rc" != 0 ] && case "$out" in *"listed twice"*"lane-a"*) true;; *) false;; esac'

HASH_A="$(run_part --base "$PART_BASE" --print-candidate --paths lane-a)"
HASH_B="$(run_part --base "$PART_BASE" --print-candidate --paths lane-b)"
check "a partition's hash is exactly what --print-candidate --paths already answers" \
  '[ ${#HASH_A} = 64 ] && python3 -c "import json,sys; m=json.loads(sys.argv[1]); assert [p[\"candidate_sha256\"] for p in m[\"partitions\"]]==[sys.argv[2], sys.argv[3]]" "$MANIFEST_JSON" "$HASH_A" "$HASH_B"'

printf '%s\n' "$MANIFEST_JSON" >"$PART/specs/round/evidence/landing-partitions.json"
git -C "$PART" add -A && git -C "$PART" commit -qm "partition manifest"
out="$(run_part --base "$PART_BASE")"; rc=$?
check "a manifest whose partitions carry no validated ledger is refused, naming the partition" \
  '[ "$rc" = 1 ] && case "$out" in *"no accepted ledger"*"lane-a"*) true;; *) false;; esac'
HASH_A_AFTER="$(run_part --base "$PART_BASE" --print-candidate --paths lane-a)"
check "committing the manifest does not move the partition it describes" \
  '[ "$HASH_A_AFTER" = "$HASH_A" ]'

write_closeout "$PART/specs/round/evidence/closeout-a.json" "$HASH_A"
write_closeout "$PART/specs/round/evidence/closeout-b.json" "$HASH_B"
git -C "$PART" add -A && git -C "$PART" commit -qm "partition ledgers"
out="$(run_part --base "$PART_BASE")"; rc=$?
check "a complete manifest with a validated ledger per partition binds a candidate no single packet could" \
  '[ "$rc" = 0 ] && case "$out" in *"binds the landing candidate"*"2 partitions"*) true;; *) false;; esac'
PART_GOOD="$(git -C "$PART" rev-parse HEAD)"

# Every way the parts can fail to add up to the whole is refused for its own
# reason. Each probe branches from the passing state so the cases stay independent.
MANIFEST="$PART/specs/round/evidence/landing-partitions.json"
probe_part() {
  git -C "$PART" checkout -q -B "probe" "$PART_GOOD"
}

probe_part
python3 "$WORK/write-manifest.py" "$MANIFEST" "$PART_BASE" AUTO "lane-a=$HASH_A"
git -C "$PART" add -A && git -C "$PART" commit -qm "manifest drops a lane"
out="$(run_part --base "$PART_BASE")"; rc=$?
check "a manifest that leaves a changed path in no partition is refused" \
  '[ "$rc" = 1 ] && case "$out" in *"uncovered"*"lane-b/big.txt"*) true;; *) false;; esac'

probe_part
python3 "$WORK/write-manifest.py" "$MANIFEST" "$PART_BASE" AUTO "lane-a=$HASH_A" "lane-a/big.txt lane-b=$HASH_B"
git -C "$PART" add -A && git -C "$PART" commit -qm "manifest overlaps"
out="$(run_part --base "$PART_BASE")"; rc=$?
check "a manifest whose partitions overlap is refused before any packet is frozen" \
  '[ "$rc" = 1 ] && case "$out" in *"overlap"*"lane-a/big.txt"*) true;; *) false;; esac'

probe_part
printf 'moved after the manifest was written\n' >>"$PART/lane-a/big.txt"
git -C "$PART" add -A && git -C "$PART" commit -qm "candidate moves after manifest"
out="$(run_part --base "$PART_BASE")"; rc=$?
check "a partition whose recorded hash no longer reproduces is refused" \
  '[ "$rc" = 1 ] && case "$out" in *"lane-a"*"does not reproduce"*) true;; *) false;; esac'

probe_part
python3 "$WORK/write-manifest.py" "$MANIFEST" "0000000000000000000000000000000000000000" AUTO "lane-a=$HASH_A" "lane-b=$HASH_B"
git -C "$PART" add -A && git -C "$PART" commit -qm "manifest names another base"
out="$(run_part --base "$PART_BASE")"; rc=$?
check "a manifest written against another base is refused" \
  '[ "$rc" = 1 ] && case "$out" in *"base"*"fork point"*) true;; *) false;; esac'

probe_part
python3 "$WORK/write-manifest.py" "$MANIFEST" "$PART_BASE" "$(printf 'f%.0s' $(seq 64))" "lane-a=$HASH_A" "lane-b=$HASH_B"
git -C "$PART" add -A && git -C "$PART" commit -qm "manifest aggregate forged"
out="$(run_part --base "$PART_BASE")"; rc=$?
check "a manifest whose aggregate hash does not reproduce its partitions is refused" \
  '[ "$rc" = 1 ] && case "$out" in *"aggregate"*) true;; *) false;; esac'

for bad_path in ":(exclude)lane-b" "-lane-b" "../lane-b" "/lane-b" "lane-*" "lane-?" "lane-[ab]" "lane-\\b"; do
  probe_part
  python3 "$WORK/write-manifest.py" "$MANIFEST" "$PART_BASE" AUTO "lane-a=$HASH_A" "$bad_path=$HASH_B"
  git -C "$PART" add -A && git -C "$PART" commit -qm "manifest smuggles a pathspec"
  out="$(run_part --base "$PART_BASE")"; rc=$?
  check "a manifest partition path shaped like $bad_path is refused as a path, not handed to git" \
    '[ "$rc" = 1 ] && case "$out" in *"partition path"*) true;; *) false;; esac'
done

out="$(run_part --base "$PART_BASE" --print-manifest --partition 'lane-*')"; rc=$?
check "rendering refuses a wildcard partition instead of letting git expand it" \
  '[ "$rc" != 0 ] && case "$out" in *"partition path"*"wildcard"*) true;; *) false;; esac'

# Under a narrowed --paths scope the partition union must equal the reviewed
# changed set, not merely contain it: a partition naming `.` reaches lane-b even
# though only lane-a is under review, and that surplus is refused before any
# packet is frozen. The ledgers are removed so the single-ledger path cannot
# satisfy the narrowed scope first.
probe_part
git -C "$PART" rm -q "$PART/specs/round/evidence/closeout-a.json" "$PART/specs/round/evidence/closeout-b.json"
python3 "$WORK/write-manifest.py" "$MANIFEST" "$PART_BASE" AUTO ".=$(printf '0%.0s' $(seq 64))"
git -C "$PART" add -A && git -C "$PART" commit -qm "manifest reaches outside the reviewed scope"
out="$(run_part --base "$PART_BASE" --paths lane-a)"; rc=$?
check "a partition reaching changed paths outside a narrowed --paths scope is refused, not accepted as covering" \
  '[ "$rc" = 1 ] && case "$out" in *"outside the reviewed scope"*"lane-b/big.txt"*) true;; *) false;; esac'

probe_part
git -C "$PART" rm -q "$PART/specs/round/evidence/closeout-b.json"
git -C "$PART" commit -qm "one ledger missing"
out="$(run_part --base "$PART_BASE")"; rc=$?
check "a manifest with one partition unbound is refused, naming that partition" \
  '[ "$rc" = 1 ] && case "$out" in *"no accepted ledger"*"lane-b"*) true;; *) false;; esac'

git -C "$PART" checkout -q -B "landing" "$PART_GOOD"
out="$(run_part --base "$PART_BASE")"; rc=$?
check "the passing partition state still passes after the probes" \
  '[ "$rc" = 0 ]'

# Chain: an integration branch accumulates several reviewed rounds, each merged
# with its own ledger bound at its own base, and is then promoted as one pull
# request. No single ledger binds the promotion candidate, and a path partition
# cannot either when two rounds append to the same file: that file's promotion
# diff is the sum of both appends and no round ever froze that sum. Every byte
# of the promotion reached the branch through a first-parent merge whose second
# parent is a reviewed head, so the gate walks that chain and rebinds each round
# in a detached checkout at the round's own base, requiring every merge to be
# exactly the automatic merge of its parents.
CHAIN="$WORK/chain-repo"
mkdir -p "$CHAIN/skills/code-review/scripts" "$CHAIN/skills/skill-extraction-workflow/scripts" "$CHAIN/specs"
cp "$CONTROLLER" "$CHAIN/skills/code-review/scripts/review_gate.py"
# This stub has a rule, unlike the accept-all stubs above, so a round can forge a
# ledger the real validator would reject and the suite can tell whose validator
# judged it.
STRICT_VALIDATOR='import json, sys
payload = json.load(open(sys.argv[1], encoding="utf-8"))
if payload.get("closeout_state") == "ready_for_human_decision":
    print("extraction_review_state_ok: stub accepted")
    sys.exit(0)
print("extraction_review_state_invalid: stub rejected")
sys.exit(1)
'
printf '%s' "$STRICT_VALIDATOR" >"$CHAIN/skills/skill-extraction-workflow/scripts/validate_extraction_review_state.py"
git -C "$CHAIN" init -q -b main .
git -C "$CHAIN" config user.email t@example.invalid
git -C "$CHAIN" config user.name tester
printf 'baseline\n' >"$CHAIN/skills/skill-extraction-workflow/SKILL.md"
printf '| row | owner |\n' >"$CHAIN/skills/skill-extraction-workflow/register.md"
printf 'baseline\n' >"$CHAIN/README.md"
git -C "$CHAIN" add -A && git -C "$CHAIN" commit -qm baseline
CHAIN_BASE="$(git -C "$CHAIN" rev-parse HEAD)"
git -C "$CHAIN" checkout -q -b dev

run_chain() { python3 "$GATE" --repo-root "$CHAIN" "$@" 2>&1; }

# Land one reviewed round on the integration branch: branch, edit, ledger bound
# to the round's own candidate (its base is the integration tip it forked from),
# then a non-fast-forward merge so the round is one first-parent step.
land_round() {
  local name="$1" ledger="$2"; shift 2
  git -C "$CHAIN" checkout -q -b "round-$name" dev
  "$@"
  git -C "$CHAIN" add -A && git -C "$CHAIN" commit -qm "round $name"
  if [ "$ledger" = with-ledger ]; then
    local digest
    digest="$(run_chain --base dev --print-candidate)"
    mkdir -p "$CHAIN/specs/$name/evidence"
    write_closeout "$CHAIN/specs/$name/evidence/closeout.json" "$digest"
    git -C "$CHAIN" add -A && git -C "$CHAIN" commit -qm "round $name ledger"
  fi
  git -C "$CHAIN" checkout -q dev
  git -C "$CHAIN" merge -q --no-ff -m "merge round $name" "round-$name"
}
edit_round_a() {
  printf 'baseline\nround a\n' >"$CHAIN/skills/skill-extraction-workflow/SKILL.md"
  printf '| round a | owner |\n' >>"$CHAIN/skills/skill-extraction-workflow/register.md"
}
edit_round_b() {
  mkdir -p "$CHAIN/lane"
  printf 'round b\n' >"$CHAIN/lane/file.txt"
  printf '| round b | owner |\n' >>"$CHAIN/skills/skill-extraction-workflow/register.md"
}
land_round a with-ledger edit_round_a
land_round b with-ledger edit_round_b
CHAIN_TWO="$(git -C "$CHAIN" rev-parse HEAD)"

worktrees_before="$(git -C "$CHAIN" worktree list --porcelain)"
tree_before="$(git -C "$CHAIN" status --porcelain --ignored)"
out="$(run_chain --base "$CHAIN_BASE")"; rc=$?
check "two rounds appending to one file bind through the first-parent chain where no single ledger or path partition can" \
  '[ "$rc" = 0 ] && case "$out" in *"first-parent chain"*"2 rounds"*"specs/b/evidence/closeout.json"*"specs/a/evidence/closeout.json"*) true;; *) false;; esac'
check "walking the chain leaves no detached checkout registered and the bound tree byte-identical" \
  '[ "$(git -C "$CHAIN" worktree list --porcelain)" = "$worktrees_before" ] && [ "$(git -C "$CHAIN" status --porcelain --ignored)" = "$tree_before" ]'

out="$(run_chain --base "$CHAIN_BASE" --paths skills)"; rc=$?
check "a narrowed --paths scope does not evaluate the chain, because each round's ledger binds the whole round" \
  '[ "$rc" = 1 ] && case "$out" in *"default path set"*) true;; *) false;; esac'

# The promotion pull request is brought up to date with its target: the target
# advanced, and the sync merge's second parent is already on the base. That step
# owes no evidence, but it must still be exactly the automatic merge.
git -C "$CHAIN" checkout -q main
printf 'baseline\nfixed on the target\n' >"$CHAIN/README.md"
git -C "$CHAIN" add -A && git -C "$CHAIN" commit -qm "target advances"
CHAIN_MAIN="$(git -C "$CHAIN" rev-parse HEAD)"
git -C "$CHAIN" checkout -q dev
git -C "$CHAIN" merge -q --no-ff -m "sync target into dev" main
out="$(run_chain --base "$CHAIN_MAIN")"; rc=$?
check "a sync merge of the advanced target on top of the chain owes no evidence and still binds" \
  '[ "$rc" = 0 ] && case "$out" in *"first-parent chain"*"2 rounds"*"sync"*) true;; *) false;; esac'
CHAIN_GOOD="$(git -C "$CHAIN" rev-parse HEAD)"

# A round the integration branch advanced past before it merged: its fork point
# is not the merge's first parent, the merge is still the automatic one, and the
# round's ledger was bound at its own fork point.
git -C "$CHAIN" checkout -q -b round-late dev
printf 'round late\n' >"$CHAIN/lane/late.txt"
git -C "$CHAIN" add -A && git -C "$CHAIN" commit -qm "round late"
LATE_DIGEST="$(run_chain --base dev --print-candidate)"
mkdir -p "$CHAIN/specs/late/evidence"
write_closeout "$CHAIN/specs/late/evidence/closeout.json" "$LATE_DIGEST"
git -C "$CHAIN" add -A && git -C "$CHAIN" commit -qm "round late ledger"
git -C "$CHAIN" checkout -q dev
edit_round_c() { printf 'round c\n' >"$CHAIN/lane/c.txt"; }
land_round c with-ledger edit_round_c
git -C "$CHAIN" merge -q --no-ff -m "merge round late" round-late
out="$(run_chain --base "$CHAIN_MAIN")"; rc=$?
check "a round merged after the integration branch advanced still binds at its own fork point" \
  '[ "$rc" = 0 ] && case "$out" in *"first-parent chain"*"4 rounds"*) true;; *) false;; esac'
CHAIN_ADVANCED="$(git -C "$CHAIN" rev-parse HEAD)"

# Every way a chain step can fail to be a reviewed round is refused for its own
# reason. Each probe branches from the passing state so the cases stay independent.
probe_chain() { git -C "$CHAIN" checkout -q -B dev "$CHAIN_GOOD"; }

probe_chain
edit_round_d() { printf 'round d\n' >"$CHAIN/lane/d.txt"; }
land_round d no-ledger edit_round_d
UNBOUND_MERGE="$(git -C "$CHAIN" rev-parse --short=12 HEAD)"
out="$(run_chain --base "$CHAIN_MAIN")"; rc=$?
check "a round with no accepted ledger at its own base refuses the whole chain, naming that round" \
  '[ "$rc" = 1 ] && case "$out" in *"round $UNBOUND_MERGE"*"does not bind at its own base"*) true;; *) false;; esac'

probe_chain
printf 'pushed straight to the integration branch\n' >"$CHAIN/lane/direct.txt"
git -C "$CHAIN" add -A && git -C "$CHAIN" commit -qm "direct commit on dev"
DIRECT="$(git -C "$CHAIN" rev-parse --short=12 HEAD)"
out="$(run_chain --base "$CHAIN_MAIN")"; rc=$?
check "a non-merge commit on the integration branch is refused: nothing reviewed binds its content" \
  '[ "$rc" = 1 ] && case "$out" in *"$DIRECT is not a merge commit"*) true;; *) false;; esac'

probe_chain
git -C "$CHAIN" checkout -q -b round-evil dev
printf 'round evil\n' >"$CHAIN/lane/evil.txt"
git -C "$CHAIN" add -A && git -C "$CHAIN" commit -qm "round evil"
EVIL_DIGEST="$(run_chain --base dev --print-candidate)"
mkdir -p "$CHAIN/specs/evil/evidence"
write_closeout "$CHAIN/specs/evil/evidence/closeout.json" "$EVIL_DIGEST"
git -C "$CHAIN" add -A && git -C "$CHAIN" commit -qm "round evil ledger"
git -C "$CHAIN" checkout -q dev
git -C "$CHAIN" merge -q --no-ff --no-commit round-evil
printf 'slipped into the merge commit itself\n' >"$CHAIN/lane/smuggled.txt"
git -C "$CHAIN" add -A && git -C "$CHAIN" commit -qm "merge round evil (with extra content)"
EVIL_MERGE="$(git -C "$CHAIN" rev-parse --short=12 HEAD)"
out="$(run_chain --base "$CHAIN_MAIN")"; rc=$?
check "a merge whose tree is not the automatic merge of its parents is refused, naming the merge" \
  '[ "$rc" = 1 ] && case "$out" in *"$EVIL_MERGE"*"automatic merge"*) true;; *) false;; esac'

probe_chain
git -C "$CHAIN" checkout -q -b round-conflict "$CHAIN_TWO"
printf 'baseline\nconflicting fix\n' >"$CHAIN/README.md"
git -C "$CHAIN" add -A && git -C "$CHAIN" commit -qm "round conflict"
CONFLICT_DIGEST="$(run_chain --base "$CHAIN_TWO" --print-candidate)"
mkdir -p "$CHAIN/specs/conflict/evidence"
write_closeout "$CHAIN/specs/conflict/evidence/closeout.json" "$CONFLICT_DIGEST"
git -C "$CHAIN" add -A && git -C "$CHAIN" commit -qm "round conflict ledger"
git -C "$CHAIN" checkout -q dev
git -C "$CHAIN" merge -q --no-ff --no-commit round-conflict >/dev/null 2>&1 || true
printf 'baseline\nresolved by hand\n' >"$CHAIN/README.md"
git -C "$CHAIN" add -A && git -C "$CHAIN" commit -qm "merge round conflict (resolved by hand)"
CONFLICT_MERGE="$(git -C "$CHAIN" rev-parse --short=12 HEAD)"
out="$(run_chain --base "$CHAIN_MAIN")"; rc=$?
check "a merge that needed hand resolution is refused: the resolution is content no round reviewed" \
  '[ "$rc" = 1 ] && case "$out" in *"$CONFLICT_MERGE"*"automatic merge"*) true;; *) false;; esac'

probe_chain
git -C "$CHAIN" checkout -q -b round-stale dev
printf 'round stale\n' >"$CHAIN/lane/stale.txt"
git -C "$CHAIN" add -A && git -C "$CHAIN" commit -qm "round stale"
STALE_DIGEST="$(run_chain --base dev --print-candidate)"
mkdir -p "$CHAIN/specs/stale/evidence"
write_closeout "$CHAIN/specs/stale/evidence/closeout.json" "$STALE_DIGEST"
git -C "$CHAIN" add -A && git -C "$CHAIN" commit -qm "round stale ledger"
printf 'edited after the review\n' >>"$CHAIN/lane/stale.txt"
git -C "$CHAIN" add -A && git -C "$CHAIN" commit -qm "round stale moves after its ledger"
git -C "$CHAIN" checkout -q dev
git -C "$CHAIN" merge -q --no-ff -m "merge round stale" round-stale
STALE_MERGE="$(git -C "$CHAIN" rev-parse --short=12 HEAD)"
out="$(run_chain --base "$CHAIN_MAIN")"; rc=$?
check "a round whose ledger binds a candidate it later moved away from is refused" \
  '[ "$rc" = 1 ] && case "$out" in *"round $STALE_MERGE"*"does not bind at its own base"*) true;; *) false;; esac'

# A round is judged with the landing tree's controller and validator, never its
# own: a round that installs an accept-all validator in its own branch, forges a
# ledger the real validator rejects, and is later followed by a round restoring
# the real validator must not bind through history's tools.
probe_chain
git -C "$CHAIN" checkout -q -b round-forged dev
printf 'round forged\n' >"$CHAIN/lane/forged.txt"
printf 'import sys\nprint("extraction_review_state_ok: hollow validator accepts everything")\nsys.exit(0)\n' \
  >"$CHAIN/skills/skill-extraction-workflow/scripts/validate_extraction_review_state.py"
git -C "$CHAIN" add -A && git -C "$CHAIN" commit -qm "round forged"
FORGED_DIGEST="$(run_chain --base dev --print-candidate)"
mkdir -p "$CHAIN/specs/forged/evidence"
python3 - "$CHAIN/specs/forged/evidence/closeout.json" "$FORGED_DIGEST" <<'PY'
import json, sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({"schema_version": 3, "closeout_state": "forged", "controller_receipts": [], "candidate_sha256": sys.argv[2]}))
PY
git -C "$CHAIN" add -A && git -C "$CHAIN" commit -qm "round forged ledger"
git -C "$CHAIN" checkout -q dev
git -C "$CHAIN" merge -q --no-ff -m "merge round forged" round-forged
FORGED_MERGE="$(git -C "$CHAIN" rev-parse --short=12 HEAD)"
edit_round_restore() { printf '%s' "$STRICT_VALIDATOR" >"$CHAIN/skills/skill-extraction-workflow/scripts/validate_extraction_review_state.py"; }
land_round restore with-ledger edit_round_restore
out="$(run_chain --base "$CHAIN_MAIN")"; rc=$?
check "a round that forged a ledger under its own hollow validator is refused even after a later round restored the real one" \
  '[ "$rc" = 1 ] && case "$out" in *"round $FORGED_MERGE"*"does not bind at its own base"*) true;; *) false;; esac'

# The walk is bounded at exactly 64 steps: a chain of 64 passes, 65 is refused.
# Receipt-only rounds keep the fixture fast, since a round whose only change is
# an excluded receipt binds as "no reviewed-path change" without a freeze.
probe_chain
fill_round() {
  git -C "$CHAIN" checkout -q -b "round-fill-$1" dev
  mkdir -p "$CHAIN/specs/fill-$1/evidence"
  printf '{"schema_version": 3, "candidate_sha256": "%s"}\n' "$(printf '0%.0s' $(seq 64))" >"$CHAIN/specs/fill-$1/evidence/note.json"
  git -C "$CHAIN" add -A && git -C "$CHAIN" commit -qm "fill $1"
  git -C "$CHAIN" checkout -q dev
  git -C "$CHAIN" merge -q --no-ff -m "merge fill $1" "round-fill-$1"
}
for index in $(seq 1 61); do fill_round "$index"; done
out="$(run_chain --base "$CHAIN_MAIN")"; rc=$?
check "a chain of exactly 64 steps is still walked and binds" \
  '[ "$rc" = 0 ] && case "$out" in *"first-parent chain"*"63 rounds"*) true;; *) false;; esac'
fill_round 62
out="$(run_chain --base "$CHAIN_MAIN")"; rc=$?
check "a chain of 65 steps is refused as longer than the bound" \
  '[ "$rc" = 1 ] && case "$out" in *"more than 64 steps"*) true;; *) false;; esac'

# A checkout this run cannot release is an error, never a pass: the removal's
# result is checked and the registry read back, and nothing prunes registrations
# the run did not create. A git shim refuses only `worktree remove`.
git -C "$CHAIN" checkout -q -B dev "$CHAIN_GOOD"
REAL_GIT="$(command -v git)"
mkdir -p "$WORK/fakegit" "$WORK/shim-tmp"
cat >"$WORK/fakegit/git" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "-C" ] && [ "\$3" = "worktree" ] && [ "\$4" = "remove" ]; then
  echo "shim: refusing to remove the worktree" >&2
  exit 1
fi
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$WORK/fakegit/git"
out="$(PATH="$WORK/fakegit:$PATH" TMPDIR="$WORK/shim-tmp" run_chain --base "$CHAIN_MAIN")"; rc=$?
check "a detached checkout that cannot be released turns the verdict into an error, never a pass" \
  '[ "$rc" != 0 ] && case "$out" in *"cannot release the detached checkout"*) case "$out" in *review_ledger_binding_ok*) false;; *) true;; esac;; *) false;; esac'
git -C "$CHAIN" worktree prune

# `git worktree add` can register and populate the checkout and still return
# nonzero. The failure is an error either way, but the registration it left
# behind must be released and verified, not merely have its directory deleted.
mkdir -p "$WORK/fakegit-add" "$WORK/shim-add-tmp"
cat >"$WORK/fakegit-add/git" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "-C" ] && [ "\$3" = "worktree" ] && [ "\$4" = "add" ]; then
  "$REAL_GIT" "\$@"
  echo "shim: worktree add failed after registering" >&2
  exit 1
fi
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$WORK/fakegit-add/git"
worktrees_before="$(git -C "$CHAIN" worktree list --porcelain)"
out="$(PATH="$WORK/fakegit-add:$PATH" TMPDIR="$WORK/shim-add-tmp" run_chain --base "$CHAIN_MAIN")"; rc=$?
check "a checkout creation that fails after registering is an error and leaves no registration or directory behind" \
  '[ "$rc" != 0 ] && case "$out" in *"cannot check out round head"*) case "$out" in *review_ledger_binding_ok*) false;; *) true;; esac;; *) false;; esac && [ "$(git -C "$CHAIN" worktree list --porcelain)" = "$worktrees_before" ] && [ -z "$(ls -A "$WORK/shim-add-tmp")" ]'
git -C "$CHAIN" worktree prune

git -C "$CHAIN" checkout -q -B dev "$CHAIN_ADVANCED"
out="$(run_chain --base "$CHAIN_MAIN")"; rc=$?
check "the passing chain state still passes after the probes" \
  '[ "$rc" = 0 ]'

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
