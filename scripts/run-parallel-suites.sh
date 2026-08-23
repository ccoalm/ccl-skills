#!/usr/bin/env bash
# Run independent test suites with bounded concurrency.
#
# Why this exists: the repo's slowest CI jobs are dominated by suites that WAIT
# (process timeouts, stub sleeps) or spawn independent subprocesses, not by CPU
# in the runner shell. Executing them serially therefore burns wall-clock the
# machine is not using. This runner keeps every suite's assertions untouched and
# changes only the schedule, so a lane's cost drops from "sum of its suites" to
# "its slowest suite".
#
# Contract (relied on by the Makefile lanes and the regression runner):
#   - Suites are given as paths; the interpreter is chosen by extension
#     (.py -> python3, everything else -> bash). Nothing is passed through a
#     shell string, so a path can never be interpreted as a command.
#   - Each suite's stdout+stderr is captured and replayed in INPUT ORDER after
#     the run, so parallel output never interleaves into unreadable logs.
#   - One `regression_test_timing: test=<name> seconds=<n> status=<rc>` line per
#     suite, matching the serial runner's existing format.
#   - Exit is nonzero if ANY suite failed, and every failure is named at the end.
#   - SUITE_JOBS=1 reproduces serial execution exactly (same order, same output)
#     for debugging a suspected concurrency interaction.
#
# Safety precondition, verified per lane before adopting this runner: suites in
# one lane must not share mutable out-of-repo state (fixed temp paths, ports,
# $HOME/global git config, shared caches). Every suite this repo runs in a lane
# builds its own `mktemp -d` workspace; see specs/037-ci-intra-job-parallel/plan.md
# for the audit. Adding a suite that violates that precondition to a parallel
# lane is a correctness bug this runner cannot detect for you.
set -uo pipefail

usage() {
  cat <<'EOF'
Usage: run-parallel-suites.sh [--jobs N] [--label NAME] <suite-path>...

Runs each suite path with bounded concurrency, replays captured output in input
order, and exits nonzero if any suite failed.

  --jobs N   max concurrent suites (default: $SUITE_JOBS, else CPU count capped at 8)
  --label    name used in the summary line (default: parallel-suites)
EOF
}

jobs_n="${SUITE_JOBS:-}"
label="parallel-suites"
while [ "$#" -gt 0 ]; do
  case "$1" in
    # The operand check is load-bearing: without it a trailing `--jobs` leaves
    # `shift 2` failing under `set +e`, the arguments unchanged, and the parser
    # spinning on the same option forever instead of reporting a usage error.
    --jobs)
      [ "$#" -ge 2 ] || { printf '%s requires a value\n' "$1" >&2; usage >&2; exit 2; }
      jobs_n="$2"; shift 2 ;;
    --label)
      [ "$#" -ge 2 ] || { printf '%s requires a value\n' "$1" >&2; usage >&2; exit 2; }
      label="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) usage >&2; exit 2 ;;
    *) break ;;
  esac
done

if [ -z "$jobs_n" ]; then
  jobs_n="$( (command -v nproc >/dev/null 2>&1 && nproc) \
    || sysctl -n hw.ncpu 2>/dev/null || echo 4 )"
  [ "$jobs_n" -gt 8 ] 2>/dev/null && jobs_n=8
fi
case "$jobs_n" in
  ''|*[!0-9]*) printf 'invalid --jobs/SUITE_JOBS value: %s\n' "$jobs_n" >&2; exit 2 ;;
esac
[ "$jobs_n" -ge 1 ] || { printf 'jobs must be >= 1\n' >&2; exit 2; }
[ "$#" -ge 1 ] || { usage >&2; exit 2; }

# Fail before launching anything: a missing suite must not be discovered halfway
# through a parallel run, where its failure competes with real output. This is
# the serial runner's own missing-file precondition, kept.
for suite in "$@"; do
  [ -f "$suite" ] || { printf 'FAIL: missing suite: %s\n' "$suite" >&2; exit 1; }
done

work="$(mktemp -d "${TMPDIR:-/tmp}/parallel-suites.XXXXXX")" || exit 1

# Cancellation must not orphan suites. Exiting straight from the signal handler
# would let the EXIT trap delete the capture directory while suites are still
# running and writing into it, leaving processes alive after the gate ended and
# their status lost. So: terminate the running children, give them a moment,
# kill what remains, and only then clean up.
# Job control is enabled so each background suite becomes its own process-group
# leader. Without it every child shares this shell's group, and signalling the
# subshell PID alone leaves the suite's OWN children (the `sleep`, the python,
# the git clone) running — which is exactly how a cancelled gate orphans work.
# With it, `kill -- -PID` reaches the whole suite subtree.
set -m

terminate_children() {
  local pids pid waited=0
  pids="$(jobs -rp 2>/dev/null)"
  [ -n "$pids" ] || return 0
  for pid in $pids; do kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true; done
  while [ "$waited" -lt 20 ] && [ -n "$(jobs -rp 2>/dev/null)" ]; do
    sleep 0.1
    waited=$((waited + 1))
  done
  for pid in $(jobs -rp 2>/dev/null); do
    kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
  done
  return 0
}
trap 'rm -rf "$work"' EXIT
trap 'terminate_children; exit 130' INT
trap 'terminate_children; exit 143' TERM

index=0
for suite in "$@"; do
  # Bash 3.2 has no `wait -n`; poll the running-job count instead. `-p` is
  # load-bearing: plain `jobs -r` prints each job's full command text, and these
  # jobs are multi-line compound commands, so `wc -l` would count LINES and the
  # semaphore would read one running job as ~8 and degrade to serial. The
  # concurrency assertion in test_run_parallel_suites.sh caught exactly that.
  while [ "$(jobs -rp 2>/dev/null | wc -l)" -ge "$jobs_n" ]; do sleep 0.1; done
  (
    started="$(date +%s)"
    # `--` before the path: a suite legitimately named `--help` (or any
    # dash-prefixed name) would otherwise be read as an interpreter OPTION, and
    # `bash --help` exits 0 without running anything — a false green.
    case "$suite" in
      *.py) python3 -- "$suite" >"$work/out.$index" 2>&1; rc=$? ;;
      *)    bash    -- "$suite" >"$work/out.$index" 2>&1; rc=$? ;;
    esac
    printf '%s\n' "$rc" >"$work/rc.$index"
    printf '%s\n' "$(( $(date +%s) - started ))" >"$work/sec.$index"
  ) &
  index=$((index + 1))
done
wait

failed=""
index=0
for suite in "$@"; do
  rc="$(cat "$work/rc.$index" 2>/dev/null || echo 1)"
  sec="$(cat "$work/sec.$index" 2>/dev/null || echo 0)"
  printf '===== %s (status=%s, %ss)\n' "$suite" "$rc" "$sec"
  cat "$work/out.$index" 2>/dev/null
  printf 'regression_test_timing: test=%s seconds=%s status=%s\n' "$suite" "$sec" "$rc"
  [ "$rc" = 0 ] || failed="$failed $suite"
  index=$((index + 1))
done

if [ -n "$failed" ]; then
  printf 'FAIL: %s: %s suite(s) failed:%s\n' "$label" "$(printf '%s' "$failed" | wc -w | tr -d ' ')" "$failed" >&2
  exit 1
fi
printf '%s_ok: %s suites, jobs=%s\n' "$label" "$#" "$jobs_n"
