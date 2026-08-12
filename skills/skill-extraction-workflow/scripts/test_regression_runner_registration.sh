#!/usr/bin/env bash
# Guard: every test_*.sh in the extraction scripts/ dir must be registered in
# test_check_ccl_regressions.sh's fast_tests/heavy_tests arrays, or CI
# silently skips it — the false-green class that let test_validate_skill_credential_cwd.sh
# ship unrun. This test asserts zero unregistered on the real repo (so a future
# unwired test turns CI red), and proves the detector actually flags an
# unregistered fixture (non-vacuous).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
RUNNER="$SCRIPT_DIR/test_check_ccl_regressions.sh"
[ -f "$RUNNER" ] || { echo "FAIL: runner not found: $RUNNER" >&2; exit 1; }
fail() { echo "FAIL: $*" >&2; exit 1; }

# (1) Real repo: no sibling test_*.sh is left out of the aggregate arrays.
out="$(bash "$RUNNER" --list-unregistered)"
[ -z "$out" ] || fail "test_*.sh not registered in fast_tests/heavy_tests (CI would not run them):\n$out"

# (2) Non-vacuous: an unregistered fixture IS reported and a registered name is NOT.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/regreg.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
: > "$TMP/test_zzz_unregistered.sh"
: > "$TMP/test_generic_r0_leak_scan.sh"   # a name that IS in fast_tests
fout="$(REGRESSION_SCRIPTS_DIR="$TMP" bash "$RUNNER" --list-unregistered)"
case "$fout" in
  *test_zzz_unregistered.sh*) : ;;
  *) fail "detector did not flag an unregistered fixture\n$fout" ;;
esac
case "$fout" in
  *test_generic_r0_leak_scan.sh*) fail "detector wrongly flagged a registered test\n$fout" ;;
  *) : ;;
esac

echo "test_regression_runner_registration: ok"
