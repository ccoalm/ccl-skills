#!/usr/bin/env bash
# Integration test for the R0 clean-vs-interim landing status in
# check-ccl-skills.sh. Proves the FINAL success token is machine-distinguishable:
#   - private alias audit ran clean  => r0_status=private-ok   + ccl_skill_check_clean_ok
#   - no ALIAS_AUDIT_CMD (public fallback only) => r0_status=public-fallback + ccl_skill_check_interim_ok
#   - private alias audit FAILED     => alias_audit_failed, non-zero, no success token
#
# Runs the real validator against THIS repo (the worktree root), toggling only
# ALIAS_AUDIT_CMD. It never writes to the repo (the validator is read-only) and
# never depends on a private alias profile: the "clean" case uses the harmless
# `true` command as a stand-in private audit, the "fail" case uses `false`.
# It mirrors the documented `check-ccl-skills.sh .` validation command (default
# base-ref detection); do NOT export CCL_SKILL_BASE_REF here — it would pollute
# the evidence-card detector's own base-less self-test fixtures.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
CHECK_SCRIPT="$SCRIPT_DIR/check-ccl-skills.sh"
# scripts -> skill-extraction-workflow -> skills -> repo root
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"
[ -f "$CHECK_SCRIPT" ] || { echo "FAIL: check script not found: $CHECK_SCRIPT" >&2; exit 1; }
[ -d "$ROOT/skills" ] || { echo "FAIL: repo root has no skills/ dir: $ROOT" >&2; exit 1; }

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_rc() { [ "$1" = "$2" ] || fail "expected rc=$2 got rc=$1${3:+ ($3)}"; }
assert_contains() { case "$2" in *"$1"*) : ;; *) fail "expected output to contain: $1${3:+ ($3)}";; esac; }
assert_not_contains() { case "$2" in *"$1"*) fail "expected output NOT to contain: $1${3:+ ($3)}";; *) : ;; esac; }
assert_last_line() {
  last_line="$(printf '%s\n' "$2" | tail -n 1)"
  [ "$last_line" = "$1" ] || fail "expected final line to be: $1; got: $last_line${3:+ ($3)}"
}

# This is an integration smoke test over the full validator, not a unit test of
# only the R0 branch: unrelated blocking gates may fail first. If a case below
# fails before token assertions, inspect the full validator output before chasing
# the R0 status logic.

# Case 1: ALIAS_AUDIT_CMD unset + public fallback clean => interim, exit 0.
set +e
out="$(env -u ALIAS_AUDIT_CMD bash "$CHECK_SCRIPT" "$ROOT" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 0 "unset ALIAS_AUDIT_CMD with clean diff should pass"
assert_contains "generic_r0_leak_scan_ok" "$out" "public fallback ran"
assert_contains "alias_audit_unavailable" "$out" "private audit flagged unavailable"
assert_contains "r0_status=public-fallback" "$out" "machine status token (interim)"
assert_contains "ccl_skill_check_ok" "$out" "legacy compatibility token"
assert_contains "ccl_skill_check_interim_ok" "$out" "final interim token"
assert_not_contains "ccl_skill_check_clean_ok" "$out" "interim run must not claim clean landing"
assert_last_line "ccl_skill_check_interim_ok" "$out" "interim token must remain the final line"

# Case 2: private audit present and passing (`true`) => clean, exit 0.
set +e
out="$(env ALIAS_AUDIT_CMD='true' bash "$CHECK_SCRIPT" "$ROOT" 2>&1)"
rc=$?
set -e
assert_rc "$rc" 0 "passing private audit should pass"
assert_contains "alias_audit_ok" "$out" "private audit ran clean"
assert_contains "r0_status=private-ok" "$out" "machine status token (clean)"
assert_contains "ccl_skill_check_ok" "$out" "legacy compatibility token"
assert_contains "ccl_skill_check_clean_ok" "$out" "final clean-landing token"
assert_not_contains "ccl_skill_check_interim_ok" "$out" "clean run must not claim interim"
assert_last_line "ccl_skill_check_clean_ok" "$out" "clean token must remain the final line"

# Case 3: private audit present and failing (`false`) => block, non-zero, no success token.
set +e
out="$(env ALIAS_AUDIT_CMD='false' bash "$CHECK_SCRIPT" "$ROOT" 2>&1)"
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "failing private audit must produce a non-zero exit (got rc=0)"
assert_contains "alias_audit_failed" "$out" "audit failure reported"
assert_not_contains "ccl_skill_check_clean_ok" "$out" "failed audit must not emit clean token"
assert_not_contains "ccl_skill_check_interim_ok" "$out" "failed audit must not emit interim token"

echo "test_check_ccl_r0_status: ok"
