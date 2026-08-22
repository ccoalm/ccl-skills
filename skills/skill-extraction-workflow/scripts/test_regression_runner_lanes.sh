#!/usr/bin/env bash
# Lane-semantics regression for test_check_ccl_regressions.sh (036 challenge
# P2): --heavy-only must run exactly the heavy_tests entries and no fast entry,
# propagate a failing heavy suite, and end with its own token; --fast must run
# exactly the fast_tests entries and no heavy entry. Runs the real runner
# against a stub fixture tree via REGRESSION_SCRIPTS_DIR, so it proves the mode
# dispatch in seconds without executing the real multi-minute suites. The stub
# list is derived from the runner's own arrays, so a lane edit cannot drift the
# fixture.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
RUNNER="$SCRIPT_DIR/test_check_ccl_regressions.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

extract_lane() {
  # Bare entry tokens of one array block, comments stripped.
  sed -n "/^${1}=(/,/^)/p" "$RUNNER" | sed -e '/^#/d' -e '/=($/d' -e '/^)$/d' \
    -e 's/[[:space:]]*#.*$//' -e 's/^[[:space:]]*//' -e '/^$/d'
}

fast_lane="$(extract_lane fast_tests)"
heavy_lane="$(extract_lane heavy_tests)"
[ -n "$fast_lane" ] || fail "could not extract fast_tests from the runner"
[ -n "$heavy_lane" ] || fail "could not extract heavy_tests from the runner"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FIX="$TMP/skills/skill-extraction-workflow/scripts"
mkdir -p "$FIX"
LOG="$TMP/ran.log"

write_stub() {
  local entry="$1"
  local path="$FIX/$entry"
  mkdir -p "$(dirname "$path")"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s" >> "%s"\n' "$entry" "$LOG" >"$path"
}
while IFS= read -r entry; do write_stub "$entry"; done <<<"$fast_lane"
while IFS= read -r entry; do write_stub "$entry"; done <<<"$heavy_lane"

run_mode() {
  : >"$LOG"
  REGRESSION_SCRIPTS_DIR="$FIX" bash "$RUNNER" "$1" >"$TMP/out.$2" 2>&1
}

# --heavy-only: exactly the heavy lane, its own token, no fast token.
run_mode --heavy-only heavy || fail "--heavy-only exited nonzero on passing stubs"
diff <(sort <<<"$heavy_lane") <(sort "$LOG") >/dev/null \
  || fail "--heavy-only did not run exactly the heavy_tests entries"
grep -q '^test_check_ccl_regressions_heavy_only_ok$' "$TMP/out.heavy" \
  || fail "--heavy-only missing its completion token"
if grep -q 'test_check_ccl_regressions_fast_ok\|test_check_ccl_regressions_full_ok' "$TMP/out.heavy"; then
  fail "--heavy-only emitted a fast/full token"
fi

# --fast: exactly the fast lane, fast token, no heavy entry.
run_mode --fast fast || fail "--fast exited nonzero on passing stubs"
diff <(sort <<<"$fast_lane") <(sort "$LOG") >/dev/null \
  || fail "--fast did not run exactly the fast_tests entries"
grep -q '^test_check_ccl_regressions_fast_ok$' "$TMP/out.fast" \
  || fail "--fast missing its completion token"

# --full: both lanes, full token.
run_mode --full full || fail "--full exited nonzero on passing stubs"
diff <(sort <(printf '%s\n%s\n' "$fast_lane" "$heavy_lane")) <(sort "$LOG") >/dev/null \
  || fail "--full did not run exactly fast_tests + heavy_tests"
grep -q '^test_check_ccl_regressions_full_ok$' "$TMP/out.full" \
  || fail "--full missing its completion token"

# Failure propagation: a red heavy stub must fail --heavy-only.
first_heavy="$(head -n 1 <<<"$heavy_lane")"
printf '#!/usr/bin/env bash\nexit 1\n' >"$FIX/$first_heavy"
if REGRESSION_SCRIPTS_DIR="$FIX" bash "$RUNNER" --heavy-only >"$TMP/out.red" 2>&1; then
  fail "--heavy-only exited zero although a heavy stub failed"
fi
write_stub "$first_heavy"

# Unregistered-sibling enforcement (036 challenge P1): an unregistered
# test_*.sh must hard-fail every execution mode, independent of the
# registration guard test staying registered.
: >"$FIX/test_unregistered_probe.sh"
if REGRESSION_SCRIPTS_DIR="$FIX" bash "$RUNNER" --fast >"$TMP/out.unreg" 2>&1; then
  fail "--fast exited zero although an unregistered sibling test exists"
fi
grep -q 'test_unregistered_probe.sh' "$TMP/out.unreg" \
  || fail "unregistered-sibling failure did not name the offending file"
rm "$FIX/test_unregistered_probe.sh"

echo "regression_runner_lanes_ok"
