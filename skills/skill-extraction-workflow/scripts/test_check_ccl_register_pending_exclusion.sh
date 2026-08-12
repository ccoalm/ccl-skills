#!/usr/bin/env bash
# Regression tests for the register-pending <-> clean-landing mutual exclusion in
# check-ccl-skills.sh. The prose rule ("any `pending` row blocks a
# complete/final claim"; an `interim` checkpoint is not complete either) had no
# machine firing point, so a run could emit the clean-landing token while a changed
# register row was still pending/interim — the blind spot the dual-track challenge
# caught by hand. This test proves the token is now forced to interim in that case.
#
# Uses ALIAS_AUDIT_CMD=true as a stand-in passing private audit so R0 is private-ok
# (r0_status=private-ok): that isolates the pending/interim downgrade from the
# separate R0 interim path. Clones this repo so assertions are independent of the
# outer worktree diff.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
CHECK_SCRIPT="$SCRIPT_DIR/check-ccl-skills.sh"
PENDING_GATE="$SCRIPT_DIR/source-register-pending-status.rb"
[ -f "$CHECK_SCRIPT" ] || { echo "FAIL: checker not found: $CHECK_SCRIPT" >&2; exit 1; }
[ -f "$PENDING_GATE" ] || { echo "FAIL: pending-status gate not found: $PENDING_GATE" >&2; exit 1; }
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/regpending.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_rc() { [ "$1" = "$2" ] || fail "expected rc=$2 got rc=$1${3:+ ($3)}"; }
assert_contains() { case "$2" in *"$1"*) : ;; *) fail "expected output to contain: $1${3:+ ($3)}";; esac; }
assert_not_contains() { case "$2" in *"$1"*) fail "expected output NOT to contain: $1${3:+ ($3)}";; *) : ;; esac; }
assert_last_line() {
  last_line="$(printf '%s\n' "$2" | tail -n 1)"
  [ "$last_line" = "$1" ] || fail "expected final line to be: $1; got: $last_line${3:+ ($3)}"
}

REPO="$TMP/repo"
git clone -q "$ROOT" "$REPO"
git -C "$REPO" config user.email test@example.invalid
git -C "$REPO" config user.name "Test User"
git -C "$REPO" branch fixture-base HEAD
REGISTER="$REPO/skills/skill-extraction-workflow/references/source-register.md"

new_case() {
  git -C "$REPO" switch -q -C "$1" fixture-base
  git -C "$REPO" branch --set-upstream-to=fixture-base "$1" >/dev/null 2>&1
}
commit_case() { git -C "$REPO" add -A; git -C "$REPO" commit -qm "$1"; }
# The first case retains the full-checker wiring assertion. Remaining cases test
# the extracted parser directly so unrelated repository scans are not repeated.
full_check_runs=0
gate_runs=0
run_full_check() {
  full_check_runs=$((full_check_runs + 1))
  set +e
  out="$(env -u CCL_SKILL_BASE_REF ALIAS_AUDIT_CMD='true' bash "$CHECK_SCRIPT" "$REPO" 2>&1)"
  rc=$?
  set -e
}
run_gate() {
  gate_runs=$((gate_runs + 1))
  set +e
  out="$(env -u CCL_SKILL_BASE_REF ruby "$PENDING_GATE" "$REPO" 2>&1)"
  rc=$?
  set -e
}

# Case 1: a `pending`-status row added to the register forces interim even with a
# clean private R0 audit (this is the RED-baseline case: before the change the run
# emitted ccl_skill_check_clean_ok).
new_case case-pending
printf '| Fixture pending item | `some-owner` | behavior not yet landed | `pending` | fixture evidence |\n' >> "$REGISTER"
commit_case "add a pending register row"
run_full_check
assert_rc "$rc" 0 "a pending row is a downgrade, not a hard block"
assert_contains "r0_status=private-ok" "$out" "private audit ran clean (isolates the pending downgrade)"
assert_contains "register_nonterminal_status_added" "$out" "checker should name the pending-row cause"
assert_not_contains "ccl_skill_check_clean_ok" "$out" "a pending row must block the clean-landing token"
assert_contains "ccl_skill_check_interim_ok" "$out" "the run must be forced to interim"
assert_last_line "ccl_skill_check_interim_ok" "$out" "interim token must be the final line"

# Case 2: an `interim`-status row behaves the same (interim work is not complete).
new_case case-interim
printf '| Fixture interim item | `some-owner` | checkpoint only | `interim` | fixture evidence |\n' >> "$REGISTER"
commit_case "add an interim register row"
run_gate
assert_rc "$rc" 0 "an interim row is a downgrade, not a hard block"
assert_contains "register_nonterminal_status_added" "$out" "an interim status row must also fire"
assert_last_line "1" "$out" "an interim row must request the final-token downgrade"

# Case 3 (control): a terminal-status row (`updated`) added to the register keeps a
# clean landing. This proves the gate targets the status column, not any occurrence
# of the words, and does not spuriously downgrade normal ledger appends.
new_case case-terminal
printf '| Fixture terminal item | `some-owner` | behavior landed | `updated` | fixture evidence |\n' >> "$REGISTER"
commit_case "add a terminal (updated) register row"
run_gate
assert_rc "$rc" 0 "a terminal row with clean R0 should pass"
assert_not_contains "register_nonterminal_status_added" "$out" "a terminal-status row must not fire the pending gate"
assert_last_line "0" "$out" "a terminal row must preserve the clean-token eligibility"

# Case 4: a capitalized `Pending` status must NOT evade the downgrade (case-fold).
new_case case-cap-pending
printf '| Fixture cap item | `some-owner` | not landed | `Pending` | fixture evidence |\n' >> "$REGISTER"
commit_case "add a capitalized Pending status row"
run_gate
assert_contains "register_nonterminal_status_added" "$out" "a capitalized Pending must still fire"
assert_last_line "1" "$out" "capitalized Pending must request the downgrade"

# Case 5: an INDENTED table row (leading whitespace before the pipe) must not evade.
new_case case-indented
printf ' | Fixture indented item | `some-owner` | not landed | `pending` | fixture evidence |\n' >> "$REGISTER"
commit_case "add an indented pending row"
run_gate
assert_contains "register_nonterminal_status_added" "$out" "an indented pending row must still fire"
assert_last_line "1" "$out" "an indented pending row must request the downgrade"

# Case 6 (control): a non-terminal word in a NON-status cell must NOT force interim
# — only the status column (index 3) counts. Here status is `updated`.
new_case case-nonstatus-word
printf '| `pending` fixture note | `some-owner` | behavior landed | `updated` | fixture evidence |\n' >> "$REGISTER"
commit_case "add a row with pending in a non-status cell"
run_gate
assert_rc "$rc" 0 "a terminal-status row should pass"
assert_not_contains "register_nonterminal_status_added" "$out" "pending in a non-status cell must NOT fire"
assert_last_line "0" "$out" "pending outside status must preserve clean-token eligibility"

# Case 7: a MALFORMED pending row (extra unescaped pipe -> wrong column count) must
# still fail safe (force interim) rather than slip through as clean.
new_case case-malformed-pending
printf '| Fixture pending with raw | pipe | `some-owner` | not landed | `pending` | fixture evidence |\n' >> "$REGISTER"
commit_case "add a malformed (extra-pipe) pending row"
run_gate
assert_contains "register_nonterminal_status_added" "$out" "a malformed pending row must still fire (fail safe)"
assert_last_line "1" "$out" "a malformed pending row must request the downgrade"

assert_rc "$full_check_runs" 1 "pending suite must retain exactly one full checker wiring case"
assert_rc "$gate_runs" 6 "remaining pending parser cases must run the standalone gate"

echo "test_check_ccl_register_pending_exclusion: ok"
