#!/usr/bin/env bash
# Regression for check_review_evidence_present.py: a pull request that changes
# skills/ or hooks/ must carry at least one conclusive review result; everything
# else passes untouched. Own throwaway git repo.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
GATE="$SCRIPT_DIR/check_review_evidence_present.py"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/review-evidence.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { pass=$((pass + 1)); echo "ok   - $1"; }

REPO="$TMP/repo"
git init -q "$REPO"
git -C "$REPO" config user.email test@example.invalid
git -C "$REPO" config user.name "Test User"
mkdir -p "$REPO/skills/demo" "$REPO/docs"
printf -- '---\nname: demo\ndescription: demo skill\n---\n\n# demo\n\nKeep the rule, always.\n' > "$REPO/skills/demo/SKILL.md"
echo "# doc" > "$REPO/docs/a.md"
git -C "$REPO" add -A && git -C "$REPO" commit -qm base
BASE="$(git -C "$REPO" rev-parse HEAD)"

result() { # result <path> <mode> <status>
  mkdir -p "$(dirname "$REPO/$1")"
  printf '{"schema_version":3,"mode":"%s","status":"%s","selected_client":"codex"}\n' \
    "$2" "$3" > "$REPO/$1"
}

# case <label> <expected rc> <expected token> <setup...>: reset to base, apply setup, commit, run.
run_case() {
  local label="$1" want_rc="$2" want="$3"; shift 3
  git -C "$REPO" checkout -q --detach "$BASE"
  git -C "$REPO" clean -qfdx
  "$@"
  git -C "$REPO" add -A
  git -C "$REPO" commit -qm case --allow-empty
  set +e
  out="$(python3 "$GATE" --repo-root "$REPO" --base "$BASE" 2>&1)"
  rc=$?
  set -e
  [ "$rc" = "$want_rc" ] || fail "$label: expected rc=$want_rc got rc=$rc: $out"
  case "$out" in *"$want"*) : ;; *) fail "$label: expected '$want': $out" ;; esac
  ok "$label"
}

docs_only() { echo "more" >> "$REPO/docs/a.md"; }
skill_change() { echo "rule" >> "$REPO/skills/demo/SKILL.md"; }
hook_change() { mkdir -p "$REPO/hooks"; echo "#!/bin/sh" > "$REPO/hooks/h.sh"; }
both_passes() { result specs/r1/evidence/round1-review.json review findings; result specs/r1/evidence/round2-challenge.json challenge passed; }

run_case "no skills or hooks change needs nothing" 0 review_evidence_not_required docs_only
run_case "skill change with no evidence is refused" 1 "no conclusive review result" skill_change
run_case "hook change with no evidence is refused" 1 review_evidence_missing hook_change
run_case "review plus challenge passes" 0 "review_evidence_present_ok: 1 review, 1 challenge" \
  bash -c "$(declare -f result skill_change both_passes); REPO='$REPO'; skill_change; both_passes"
run_case "a file replaced by a symlink still needs evidence" 1 review_evidence_missing \
  bash -c "rm '$REPO/skills/demo/SKILL.md'; ln -s ../../docs/a.md '$REPO/skills/demo/SKILL.md'"
run_case "a review alone is enough for the gate" 0 "review_evidence_present_ok: 1 review, 0 challenge" \
  bash -c "$(declare -f result skill_change); REPO='$REPO'; skill_change; result specs/r1/evidence/round1-review.json review passed"
run_case "a challenge alone does not satisfy the gate" 1 review_evidence_missing \
  bash -c "$(declare -f result skill_change); REPO='$REPO'; skill_change; result specs/r1/evidence/round2-challenge.json challenge passed"
run_case "an inconclusive result does not count" 1 review_evidence_missing \
  bash -c "$(declare -f result skill_change); REPO='$REPO'; skill_change; result specs/r1/evidence/round1-review.json review inconclusive"
run_case "a result outside an evidence directory does not count" 1 review_evidence_missing \
  bash -c "$(declare -f result skill_change); REPO='$REPO'; skill_change; result specs/r1/round1-review.json review passed; result specs/r1/round2-challenge.json challenge passed"
run_case "malformed JSON does not count" 1 review_evidence_missing \
  bash -c "mkdir -p '$REPO/specs/r1/evidence'; echo 'not json' > '$REPO/specs/r1/evidence/round1-review.json'; echo rule >> '$REPO/skills/demo/SKILL.md'"

set +e
out="$(python3 "$GATE" --repo-root "$REPO" --base does-not-exist 2>&1)"
rc=$?
set -e
[ "$rc" = 2 ] || fail "an unresolvable base must be unevaluated (rc=2), got rc=$rc"
case "$out" in *review_evidence_unevaluated*) : ;; *) fail "unresolvable base reason: $out" ;; esac
ok "an unresolvable base is unevaluated, never a pass"

[ "$pass" = 11 ] || fail "expected 11 assertions, saw $pass"
echo "test_check_review_evidence_present_ok ($pass assertions)"
