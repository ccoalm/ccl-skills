#!/usr/bin/env bash
# Regression tests for the non-blocking source-register lifecycle advisory in
# check-ccl-skills.sh. Uses a temp clone with a tiny synthetic register so
# assertions do not depend on the real shared ledger's line numbers or current rows.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
CHECK_SCRIPT="$SCRIPT_DIR/check-ccl-skills.sh"
LIFECYCLE_GATE="$SCRIPT_DIR/source-register-lifecycle.rb"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"
[ -f "$CHECK_SCRIPT" ] || { echo "FAIL: checker not found: $CHECK_SCRIPT" >&2; exit 1; }
[ -f "$LIFECYCLE_GATE" ] || { echo "FAIL: lifecycle gate not found: $LIFECYCLE_GATE" >&2; exit 1; }
[ -d "$ROOT/skills" ] || { echo "FAIL: repo root has no skills/ dir: $ROOT" >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/source-register-lifecycle.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_rc() { [ "$1" = "$2" ] || fail "expected rc=$2 got rc=$1${3:+ ($3)}"; }
assert_contains() { case "$2" in *"$1"*) : ;; *) fail "expected output to contain: $1${3:+ ($3)}";; esac; }
assert_not_contains() { case "$2" in *"$1"*) fail "expected output NOT to contain: $1${3:+ ($3)}";; *) : ;; esac; }

REPO="$TMP/repo"
git clone -q "$ROOT" "$REPO"
git -C "$REPO" config user.email test@example.invalid
git -C "$REPO" config user.name "Test User"
git -C "$REPO" branch fixture-base HEAD
git -C "$REPO" switch -q -c fixture-work
git -C "$REPO" branch --set-upstream-to=fixture-base fixture-work >/dev/null
REGISTER="$REPO/skills/skill-extraction-workflow/references/source-register.md"

write_register() {
  marker="$1"
  cat > "$REGISTER" <<EOF
# Source Register Lifecycle Fixture

Methodology prose must not be counted: supersedes: prose-only revalidate-when: prose-only revalidate-by: 1999-01-01.

| Upstream rule | Downstream owner | Expected executable behavior | Status | Evidence |
| --- | --- | --- | --- | --- |
| Lifecycle fixture | skill-extraction-workflow | supersedes: earlier fixture; revalidate-when: external fixture event; $marker | \`updated\` | source-register lifecycle fixture |
EOF
}

full_check_runs=0
gate_runs=0
# This fixture REPLACES the register with a synthetic lifecycle ledger, so none
# of the real repository's waiver-bearing rows are present. The firing-path gate
# binds each anchored EXEMPT entry to its citing row and fails closed when that
# row is missing, which is correct for production and a false RED here. Declare
# the truth about this ledger instead of weakening the gate: an empty digest
# table means this register binds no waivers.
EMPTY_DIGEST_TABLE="$TMP/empty-exempt-digests.json"
printf '{}\n' > "$EMPTY_DIGEST_TABLE"

run_full_check() {
  full_check_runs=$((full_check_runs + 1))
  set +e
  out="$(env -u ALIAS_AUDIT_CMD -u CCL_SKILL_BASE_REF \
    REGISTER_FIRING_PATH_EXEMPT_DIGESTS="$EMPTY_DIGEST_TABLE" \
    bash "$CHECK_SCRIPT" "$REPO" 2>&1)"
  rc=$?
  set -e
}
run_gate() {
  gate_runs=$((gate_runs + 1))
  set +e
  out="$(ruby "$LIFECYCLE_GATE" "$REGISTER" 2>&1)"
  rc=$?
  set -e
}

# past date: overdue is advisory only, rc remains 0.
write_register "revalidate-by: 2000-01-01"
run_full_check
assert_rc "$rc" 0 "past revalidate-by must remain non-blocking"
assert_contains "revalidate_overdue: source-register has revalidate-by 2000-01-01" "$out" "past date reported"
assert_contains "source_register_lifecycle_advisory: supersedes=1 revalidate_when=1 revalidate_by=1 overdue=1" "$out" "summary counts table-row cues only"
assert_contains "revalidate_check_advisory: 1 overdue marker(s) above" "$out" "existing overdue advisory retained"
assert_contains "ccl_skill_check_interim_ok" "$out" "public fallback still succeeds"

# future date: counted, no overdue line.
write_register "revalidate-by: 2999-01-01"
run_gate
assert_rc "$rc" 0 "future revalidate-by should pass"
assert_not_contains "revalidate_overdue:" "$out" "future date is not overdue"
assert_contains "source_register_lifecycle_advisory: supersedes=1 revalidate_when=1 revalidate_by=1 overdue=0" "$out" "future date counted without overdue"
assert_contains "revalidate_check_ok" "$out" "existing clean marker retained"

# placeholder: ignored by the date matcher and does not crash.
write_register "revalidate-by: <date>"
run_gate
assert_rc "$rc" 0 "placeholder revalidate-by should pass"
assert_not_contains "revalidate_overdue:" "$out" "placeholder is not overdue"
assert_contains "source_register_lifecycle_advisory: supersedes=1 revalidate_when=1 revalidate_by=0 overdue=0" "$out" "placeholder is not counted as a real date"

# invalid date: ignored by Date.strptime and does not crash.
write_register "revalidate-by: 2020-99-99"
run_gate
assert_rc "$rc" 0 "invalid revalidate-by should pass"
assert_not_contains "revalidate_overdue:" "$out" "invalid date is not overdue"
assert_contains "source_register_lifecycle_advisory: supersedes=1 revalidate_when=1 revalidate_by=0 overdue=0" "$out" "invalid date is not counted"

# timestamp: rejected by the lookahead and does not partial-match as a date.
write_register "revalidate-by: 2000-01-01T00:00:00"
run_gate
assert_rc "$rc" 0 "timestamp revalidate-by should pass"
assert_not_contains "revalidate_overdue:" "$out" "timestamp must not partial-match as overdue"
assert_contains "source_register_lifecycle_advisory: supersedes=1 revalidate_when=1 revalidate_by=0 overdue=0" "$out" "timestamp is not counted as a real date"

assert_rc "$full_check_runs" 1 "lifecycle suite must retain exactly one full checker wiring case"
assert_rc "$gate_runs" 4 "remaining lifecycle cases must run the standalone gate"

echo "test_check_ccl_source_register_lifecycle: ok"
