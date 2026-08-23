#!/usr/bin/env bash
# Behavioral regression for scripts/run-parallel-suites.sh.
#
# The runner is a scheduling change under every parallel CI lane, so the
# properties that make it safe to adopt are asserted here rather than assumed:
# every suite runs, failures propagate and are named, captured output replays in
# INPUT order (not completion order), concurrency is real, SUITE_JOBS=1 is
# genuinely serial, a missing suite fails before anything launches, and a suite
# path is never handed to a shell.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
RUNNER="$SCRIPT_DIR/run-parallel-suites.sh"
[ -f "$RUNNER" ] || { printf 'FAIL: runner not found: %s\n' "$RUNNER" >&2; exit 1; }

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/parallel-suites-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# slow.sh finishes LAST but is listed FIRST; fast.sh finishes first but is
# listed second. Any implementation that replays in completion order fails the
# ordering assertion below.
printf '#!/usr/bin/env bash\nsleep 2\necho SLOW-MARKER\n' >"$TMP/slow.sh"
printf '#!/usr/bin/env bash\necho FAST-MARKER\n' >"$TMP/fast.sh"
printf '#!/usr/bin/env bash\nsleep 2\necho THIRD-MARKER\n' >"$TMP/third.sh"
printf '#!/usr/bin/env bash\necho BOOM >&2\nexit 3\n' >"$TMP/red.sh"
printf 'print("PY-MARKER")\n' >"$TMP/pysuite.py"

# 1) every suite runs, and output replays in INPUT order
out="$(bash "$RUNNER" --jobs 4 "$TMP/slow.sh" "$TMP/fast.sh" "$TMP/pysuite.py")" \
  || fail "green run exited nonzero"
for marker in SLOW-MARKER FAST-MARKER PY-MARKER; do
  printf '%s' "$out" | grep -q "$marker" || fail "suite output missing: $marker"
done
slow_line="$(printf '%s' "$out" | grep -n 'SLOW-MARKER' | cut -d: -f1)"
fast_line="$(printf '%s' "$out" | grep -n 'FAST-MARKER' | cut -d: -f1)"
py_line="$(printf '%s' "$out" | grep -n 'PY-MARKER' | cut -d: -f1)"
[ "$slow_line" -lt "$fast_line" ] \
  || fail "output replayed in completion order, not input order (slow=$slow_line fast=$fast_line)"
[ "$fast_line" -lt "$py_line" ] || fail "third suite's output out of input order"

# 2) one timing line per suite, in the serial runner's format
timings="$(printf '%s' "$out" | grep -c '^regression_test_timing: test=')"
[ "$timings" = 3 ] || fail "expected 3 timing lines, saw $timings"

# 3) concurrency is REAL: two 2s suites plus an instant one must finish in well
#    under their 4s serial sum. Without this the runner could silently degrade
#    to serial and every lane would quietly lose the speedup.
start="$(date +%s)"
bash "$RUNNER" --jobs 4 "$TMP/slow.sh" "$TMP/third.sh" "$TMP/fast.sh" >/dev/null \
  || fail "concurrent run exited nonzero"
parallel_elapsed="$(( $(date +%s) - start ))"
[ "$parallel_elapsed" -lt 4 ] \
  || fail "jobs=4 took ${parallel_elapsed}s for two 2s suites; concurrency is not happening"

# 4) SUITE_JOBS=1 is genuinely serial (the debugging escape hatch must not lie)
start="$(date +%s)"
SUITE_JOBS=1 bash "$RUNNER" "$TMP/slow.sh" "$TMP/third.sh" >/dev/null \
  || fail "serial run exited nonzero"
serial_elapsed="$(( $(date +%s) - start ))"
[ "$serial_elapsed" -ge 4 ] \
  || fail "SUITE_JOBS=1 took ${serial_elapsed}s for two 2s suites; it is not serial"

# 5) failure propagates, is named, and does not hide the passing suites' output
set +e
red_out="$(bash "$RUNNER" --jobs 4 "$TMP/fast.sh" "$TMP/red.sh" 2>&1)"
red_rc=$?
set -e
[ "$red_rc" -ne 0 ] || fail "a failing suite did not make the runner exit nonzero"
printf '%s' "$red_out" | grep -q 'red.sh' || fail "failure summary does not name the failing suite"
printf '%s' "$red_out" | grep -q 'BOOM' || fail "failing suite's stderr was swallowed"
printf '%s' "$red_out" | grep -q 'FAST-MARKER' || fail "passing suite's output lost on a failed run"
printf '%s' "$red_out" | grep -q 'status=3' || fail "failing suite's exit status not reported"

# 6) a missing suite fails BEFORE anything runs
: >"$TMP/ran-marker"
printf '#!/usr/bin/env bash\necho SHOULD-NOT-RUN > "%s"\n' "$TMP/ran-marker" >"$TMP/canary.sh"
set +e
miss_out="$(bash "$RUNNER" "$TMP/canary.sh" "$TMP/does-not-exist.sh" 2>&1)"
miss_rc=$?
set -e
[ "$miss_rc" -ne 0 ] || fail "a missing suite did not fail the runner"
printf '%s' "$miss_out" | grep -q 'missing suite' || fail "missing-suite failure not reported as such"
[ ! -s "$TMP/ran-marker" ] || fail "suites launched despite a missing suite in the list"

# 7) a suite path is data, never a shell command: a path containing shell
#    metacharacters must run as a file, not be interpreted.
#    The canary is relative and the runner is invoked from $TMP, so an evaluated
#    path would leave $TMP/pwned behind; a filename cannot contain a slash.
mkdir -p "$TMP/dir with spaces"
evil_name='$(touch pwned);echo hi;.sh'
printf '#!/usr/bin/env bash\necho ODD-PATH-MARKER\n' >"$TMP/dir with spaces/$evil_name"
odd_out="$(cd "$TMP" && bash "$RUNNER" --jobs 2 "dir with spaces/$evil_name")" \
  || fail "odd-path suite did not run"
printf '%s' "$odd_out" | grep -q 'ODD-PATH-MARKER' || fail "odd-path suite produced no output"
[ ! -e "$TMP/pwned" ] || fail "suite path was evaluated by a shell"

# 8) an invalid jobs value is rejected rather than silently defaulted
set +e
bash "$RUNNER" --jobs 0 "$TMP/fast.sh" >/dev/null 2>&1; zero_rc=$?
bash "$RUNNER" --jobs abc "$TMP/fast.sh" >/dev/null 2>&1; word_rc=$?
set -e
[ "$zero_rc" -ne 0 ] || fail "--jobs 0 was accepted"
[ "$word_rc" -ne 0 ] || fail "--jobs abc was accepted"

# 9) a missing option operand is a usage error, not an infinite parse loop.
#    Guarded by a hard timeout: the defect this catches HANGS rather than fails,
#    so a plain exit-code assertion would never return.
#    The option must sit in PARSER position: after a positional the parser has
#    already stopped, so a probe there would pass even with the guard removed.
#    And the expected code is asserted exactly — merely excluding the timeout's
#    124 would also accept a 127 from a missing watchdog.
#    The watchdog is built from bash itself rather than timeout(1), which stock
#    macOS does not ship -- requiring it would make `make test-repo-gates`
#    unrunnable there on a host the runner otherwise supports.
run_with_deadline() {  # <seconds> <command...>; 137 means the deadline killed it
  local secs="$1"; shift
  "$@" >/dev/null 2>&1 &
  local cmd_pid=$!
  ( sleep "$secs"; kill -KILL "$cmd_pid" 2>/dev/null ) &
  local watchdog=$!
  local rc=0
  wait "$cmd_pid" 2>/dev/null || rc=$?
  kill -KILL "$watchdog" 2>/dev/null || true
  wait "$watchdog" 2>/dev/null || true
  return "$rc"
}
set +e
run_with_deadline 10 bash "$RUNNER" --jobs; noval_rc=$?
run_with_deadline 10 bash "$RUNNER" --label; nolabel_rc=$?
set -e
[ "$noval_rc" = 2 ] || fail "a --jobs with no value must exit 2, got $noval_rc"
[ "$nolabel_rc" = 2 ] || fail "a --label with no value must exit 2, got $nolabel_rc"

# 9b) a FAILING suite whose path contains spaces is reported as one failure.
mkdir -p "$TMP/fail dir"
printf '#!/usr/bin/env bash\nexit 4\n' >"$TMP/fail dir/red suite.sh"
set +e
ws_out="$(bash "$RUNNER" --jobs 2 "$TMP/fail dir/red suite.sh" 2>&1)"
ws_rc=$?
set -e
[ "$ws_rc" -ne 0 ] || fail "a failing whitespace path did not fail the runner"
printf '%s' "$ws_out" | grep -q '1 suite(s) failed' \
  || fail "a failing path with spaces was miscounted: $(printf '%s' "$ws_out" | grep 'suite(s) failed')"

# 10) a dash-prefixed suite name must EXECUTE, not be read as an interpreter
#     option. `bash --help` exits 0 without running anything, so the marker is
#     the only thing separating a real run from a false green.
printf '#!/usr/bin/env bash\necho DASH-MARKER\n' >"$TMP/--help"
dash_out="$(cd "$TMP" && bash "$RUNNER" --jobs 2 -- "./--help")" \
  || fail "dash-prefixed suite did not run"
printf '%s' "$dash_out" | grep -q 'DASH-MARKER' \
  || fail "dash-prefixed suite was read as an interpreter option, not executed"

# 11) cancellation terminates running suites instead of orphaning them. The
#     canary writes its marker only if it outlives the cancellation, so a leaked
#     child is detectable after the runner is gone.
#     SIGTERM, not SIGINT: a script started as a background job inherits an
#     IGNORED SIGINT, and a signal ignored on entry cannot be trapped — an
#     INT-based probe would therefore test the harness, not the runner. TERM is
#     also what a cancelled CI step actually delivers.
printf '#!/usr/bin/env bash\nsleep 6\ntouch "%s/leaked"\n' "$TMP" >"$TMP/canary-long.sh"
bash "$RUNNER" --jobs 2 "$TMP/canary-long.sh" >/dev/null 2>&1 &
runner_pid=$!
sleep 1
kill -TERM "$runner_pid" 2>/dev/null || true
wait "$runner_pid" 2>/dev/null || true
kill -0 "$runner_pid" 2>/dev/null && fail "runner survived SIGTERM"
sleep 7
[ ! -e "$TMP/leaked" ] \
  || fail "a suite survived cancellation and kept running after the runner exited"

echo "run_parallel_suites_ok"
