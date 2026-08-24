#!/usr/bin/env bash
# Proves an aborted test_review_gate.sh leaves no reviewer wrapper behind, by both of
# the mechanisms that keep that true.
#
# The suite's reviewer wrappers are deliberately TERM-immune and the controller starts
# them with start_new_session=True, so they sit in their own session where no signal
# aimed at the suite's process group can reach them. That makes the controller the only
# party that reaps them on the happy path. Both legs below remove the controller FIRST —
# the way a tree-kill, a CI cancellation, or a host suspend does — and then abort the
# suite two different ways:
#
#   leg 1  SIGTERM the suite: its cleanup trap runs and must reap the abandoned wrapper.
#   leg 2  SIGKILL the suite: nothing can trap that, so no reaper runs at all and the
#          wrapper must die on the fixture's own lifetime bound instead.
#
# Leg 2 exists because leg 1 alone stays green if the fixture's bound were restored to
# an unbounded loop: the trap would still reap it. It was an unbounded loop that turned
# this defect into a wrapper observed alive for 39 hours with ppid=1, ignoring SIGTERM.
#
# Each leg runs the suite under a private TMPDIR so every process this probe may signal
# is identified by a path no other run can share. Nothing here matches on the shared
# `review-gate-test.` prefix: a concurrent lane running the same suite would be killed
# by that, which is precisely the class scripts/test_lane_isolation.py keeps out of the
# parallel lanes.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SUITE="$DIR/test_review_gate.sh"
# How long an abandoned wrapper may still be alive after the suite is gone.
GRACE="${ABORT_LEAK_PROBE_GRACE:-30}"
# Bound on reaching the target case. The suite reaches it in ~2min on an idle host; the
# headroom is for a slow runner, NOT for sharing one — this probe runs in its own job
# precisely because a shared runner stretches that round past any budget.
REACH="${ABORT_LEAK_PROBE_REACH:-420}"
# Leg 2 shortens the fixture's own bound so the leg does not have to wait out the 300s
# default; leg 2's runtime is essentially this number, because the leg ends by watching
# the abandoned wrapper reach it. The constraint is the budget each case gives ITS
# WRAPPER — the `--timeout` the controller passes down, which is 5s for the claude hang
# case this probe aborts in and under 12s for the fallback hang cases that run before it
# (per those cases' own assertions) — NOT the case's `--total-timeout`, which bounds the
# whole gate rather than the wrapper. 25 keeps ~2x margin over the largest of those while
# taking 20s off the job: measured on CI, this job was the longest branch at 213s against
# 188s for the previous longest, so that 20s is the difference between adding a critical
# path and landing inside the existing one.
LEG2_HANG_BOUND="${ABORT_LEAK_PROBE_HANG_BOUND:-25}"
# Which leg(s) to run: `1`, `2`, or `all`. Each leg needs its OWN full run of the suite —
# one abort must be trappable and the other must not — and that pair, not the leg-2 wait,
# is what makes this the longest CI branch. Measured: cutting the leg-2 bound 45s -> 25s
# moved the job 213s -> 214s, i.e. not at all. So CI runs the legs as two parallel jobs
# and each stays well under the next-longest branch; `all` remains the local default.
ABORT_LEAK_PROBE_LEG="${ABORT_LEAK_PROBE_LEG:-all}"
case "$ABORT_LEAK_PROBE_LEG" in
  1|2|all) : ;;
  *) echo "ABORT_LEAK_PROBE_LEG must be 1, 2, or all" >&2; exit 2 ;;
esac
# Which fixture stub to orphan. The suite generates TWO of them — the claude stub and the
# shared candidate stub the fallback clients run — and they carry the same hang behavior
# and the same lifetime bound. A probe pinned to one leaves the other's bound revertible
# with the probe still green, so CI points its two jobs at different stubs.
ABORT_LEAK_PROBE_CLIENT="${ABORT_LEAK_PROBE_CLIENT:-claude}"
case "$ABORT_LEAK_PROBE_CLIENT" in
  claude) PROBE_BEHAVIOR_FILE=claude_behavior; PROBE_WRAPPER=claude_review.sh ;;
  fallback) PROBE_BEHAVIOR_FILE=kimi_behavior; PROBE_WRAPPER=kimi_review.sh ;;
  *) echo "ABORT_LEAK_PROBE_CLIENT must be claude or fallback" >&2; exit 2 ;;
esac

fails=0
check() {
  if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fails=$((fails+1)); fi
}

PROBE_TMP=""
PROBE_TMP_REAL=""
suite_pid=""
suite_pgid=""
suite_start=""
wrapper_pid=""
wrapper_pgid=""

# Every process a leg starts carries that leg's private tmp path in argv. The needles go
# through the environment, not `awk -v`: `ps -e` lists this very awk, and an argv-passed
# needle makes the scanner match itself.
probe_processes() {
  [ -n "$PROBE_TMP_REAL" ] || return 0
  ps -eo pid=,stat=,command= 2>/dev/null |
    PROBE_A="$PROBE_TMP/" PROBE_B="$PROBE_TMP_REAL/" \
    awk 'BEGIN { a = ENVIRON["PROBE_A"]; b = ENVIRON["PROBE_B"] }
         (index($0, a) || index($0, b)) && $2 !~ /Z/ { print $1 }'
}

# Never let the probe become the leak it tests for — and never on someone else's
# processes: `suite_pgid` and any pid read earlier are cached numbers the OS recycles,
# so ownership is re-proved against the live process table at the moment of signalling.
# A group is signalled only while it still contains a process carrying this probe's
# private tmp path; everything else is signalled by pid, which `probe_processes` has
# just re-matched by that same path.
probe_group_is_ours() {
  ps -eo pgid=,stat=,command= 2>/dev/null |
    PROBE_A="$PROBE_TMP/" PROBE_B="$PROBE_TMP_REAL/" PROBE_PGID="$1" \
    awk 'BEGIN { a = ENVIRON["PROBE_A"]; b = ENVIRON["PROBE_B"]; g = ENVIRON["PROBE_PGID"]; found = 1 }
         $1 == g && $2 !~ /Z/ && (index($0, a) || index($0, b)) { found = 0; exit }
         END { exit found }'
}
# The suite's pid and group id were captured minutes earlier and the OS recycles both,
# so every signal aimed at them re-proves identity first: the pid must still be running
# THIS suite script and must still lead the group we recorded. Validating the group
# through a live member we can name is what makes the group signal safe — a
# tmp-path-membership test would not do here, because by design the controller (the one
# group member carrying that path) has just been killed.
suite_is_ours() {
  case "${suite_pid:-}" in ''|*[!0-9]*) return 1 ;; esac
  case "${suite_pgid:-}" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$suite_pid" 2>/dev/null || return 1
  case "$(ps -o command= -p "$suite_pid" 2>/dev/null || true)" in
    *"$SUITE"*) : ;;
    *) return 1 ;;
  esac
  [ "$(ps -o pgid= -p "$suite_pid" 2>/dev/null | tr -d ' ')" = "$suite_pgid" ] || return 1
  # Start time, not just argv and group: with job control the suite's pgid equals its
  # own pid, so those two conditions collapse into "this pid is running this script" —
  # which a recycled pid on another run of the SAME suite would also satisfy. The launch
  # instant is what separates our process from its namesake.
  [ -n "$suite_start" ] || return 1
  [ "$(ps -o lstart= -p "$suite_pid" 2>/dev/null || true)" = "$suite_start" ] || return 1
  return 0
}
signal_suite() {
  suite_is_ours || return 0
  kill -"$1" -"$suite_pgid" 2>/dev/null || true
  kill -"$1" "$suite_pid" 2>/dev/null || true
}
cleanup() {
  local pid probe_cmd
  signal_suite KILL
  for pid in $(probe_processes); do
    # Re-check immediately before signalling: a pid read even a moment ago can already be
    # a stranger's. This narrows the window to the width of one `ps`; a shell cannot close
    # it entirely, because there is no portable kill-by-handle, and that residual TOCTOU
    # is a documented boundary rather than an oversight.
    # Match BOTH spellings, like probe_processes does: on a host where the temp dir is a
    # symlink (macOS /var -> /private/var) a process can carry either form, and a check
    # that knows only one silently skips a process this probe started.
    probe_cmd="$(ps -o command= -p "$pid" 2>/dev/null || true)"
    case "$probe_cmd" in
      *"$PROBE_TMP/"*|*"$PROBE_TMP_REAL/"*) : ;;
      *) continue ;;
    esac
    probe_group_is_ours "$pid" && kill -KILL -"$pid" 2>/dev/null || true
    kill -KILL "$pid" 2>/dev/null || true
  done
  [ -z "$PROBE_TMP" ] || rm -rf "$PROBE_TMP"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

# Selecting the target reads the suite's OWN state rather than pattern-matching an argv
# tail. Two earlier selectors failed here and each failure is the reason for this shape:
# picking by lifetime chose one of the behaviors that merely sleeps and then exits on its
# own (`quota_slow` 2s, `passed_slow` 5s), so the probe was green against a broken suite;
# and matching `--focus process-group-timeout` in the command line depends on how ps
# renders a long argv — it found the case when the probe ran alone and found nothing at
# all under `make`, burning the whole reach budget twice. The behavior file is written by
# the suite before it starts the case, so "a hang case is running now" is a fact to read,
# not a shape to guess. It also matches the FIRST hang case rather than the last, so the
# probe reaches its target sooner.
#
# The wrapper and the `( ... ) &` child it backgrounds share a command line, so "the
# first matching ps row" is whichever the kernel lists first. Picking the child would
# make the next step read the WRAPPER as the controller — and the wrapper's own command
# line satisfies the tmp-path validation, so that mistake would sail through and the leg
# would kill the wrong process. Select by ancestry: the wrapper is the match whose parent
# is the controller.
suite_work_dir() {
  local dir
  for dir in "$PROBE_TMP_REAL"/review-gate-test.*; do
    [ -d "$dir" ] && printf '%s\n' "$dir" && return 0
  done
  return 1
}
live_wrapper() {
  local work behavior pid parent_cmd
  work="$(suite_work_dir)" || return 0
  behavior="$(cat "$work/state/$PROBE_BEHAVIOR_FILE" 2>/dev/null || true)"
  [ "$behavior" = "hang" ] || return 0
  for pid in $(ps -eo pid=,command= 2>/dev/null |
      grep -e "$PROBE_TMP/" -e "$PROBE_TMP_REAL/" -F |
      grep -F "$PROBE_WRAPPER" |
      grep -v '[g]rep' |
      awk '{print $1}'); do
    parent_cmd="$(ps -o command= -p "$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')" 2>/dev/null || true)"
    case "$parent_cmd" in
      *review_gate.py*) printf '%s\n' "$pid"; return 0 ;;
    esac
  done
  return 0
}

# Runs the suite until the target wrapper is in flight, then removes its controller so
# the wrapper is orphaned with no reaper but the suite itself. Sets wrapper_pid.
# $1 is the value for the fixture's lifetime bound, or empty for its default.
orphan_target_wrapper() {
  local hang_bound="$1" candidate controller_pid controller_ok deadline suite_died
  PROBE_TMP="$(mktemp -d "${TMPDIR:-/tmp}/review-gate-abort-probe.XXXXXX")" || return 1
  PROBE_TMP_REAL="$(cd "$PROBE_TMP" && pwd -P)" || return 1
  wrapper_pid=""

  # Job control so the suite gets its own process group and the probe can signal that
  # group without signalling itself.
  set -m
  TMPDIR="$PROBE_TMP" REVIEW_GATE_TEST_HANG_SECONDS="$hang_bound" \
    bash "$SUITE" >/dev/null 2>&1 &
  suite_pid=$!
  suite_pgid="$(ps -o pgid= -p "$suite_pid" 2>/dev/null | tr -d ' ')"
  suite_start="$(ps -o lstart= -p "$suite_pid" 2>/dev/null || true)"

  deadline=$(( $(date +%s) + REACH ))
  suite_died=0
  while [ "$(date +%s)" -lt "$deadline" ]; do
    candidate="$(live_wrapper)"
    if [ -n "$candidate" ]; then wrapper_pid="$candidate"; break; fi
    kill -0 "$suite_pid" 2>/dev/null || { suite_died=1; break; }
    sleep 0.1
  done
  if [ -z "$wrapper_pid" ]; then
    # Say WHICH failure this is. "unreached" alone cannot distinguish a suite that ran
    # fine but never got to a hang case inside the budget from a suite that died early —
    # and a run of this probe under `make` failed exactly here with no way to tell them
    # apart, which is why the distinction is printed rather than inferred.
    if [ "$suite_died" = 1 ]; then
      wait "$suite_pid" 2>/dev/null
      printf 'abort_leak_probe_unreached: the suite exited (status %s) before any hang case was observed\n' "$?" >&2
    else
      printf 'abort_leak_probe_unreached: %ss budget elapsed with the suite still running; last behavior=%s\n' \
        "$REACH" "$(cat "$(suite_work_dir 2>/dev/null)/state/claude_behavior" 2>/dev/null || printf unknown)" >&2
    fi
    return 1
  fi

  # Validate the target before signalling it, never after. Between selecting the wrapper
  # and reading its parent the wrapper can be reaped and its pid reused, so this value is
  # untrustworthy by construction: it can be 1 (already orphaned) or an unrelated
  # process. `kill -KILL 1` is harmless for an unprivileged user but not for a root
  # container, and no probe should be the thing that finds that out.
  controller_pid="$(ps -o ppid= -p "$wrapper_pid" 2>/dev/null | tr -d ' ')"
  controller_ok=0
  case "$controller_pid" in
    ''|*[!0-9]*) : ;;
    *)
      if [ "$controller_pid" -gt 1 ] \
        && [ "$(ps -o ppid= -p "$wrapper_pid" 2>/dev/null | tr -d ' ')" = "$controller_pid" ] \
        && { case "$(ps -o command= -p "$controller_pid" 2>/dev/null || true)" in
               *"$PROBE_TMP/"*|*"$PROBE_TMP_REAL/"*) true ;; *) false ;; esac; }; then
        controller_ok=1
      fi
      ;;
  esac
  if [ "$controller_ok" != 1 ]; then
    printf 'abort leak setup: refusing to signal pid=%s (not this run'"'"'s controller)\n' \
      "${controller_pid:-none}" >&2
    return 1
  fi
  # Order matters: the controller must die BEFORE the suite, or its own timeout path
  # reaps the wrapper and the leg proves nothing about the suite. `kill` returning is
  # not that proof: confirm here, once, that the controller is really gone and the
  # wrapper really was reparented, so BOTH legs inherit a verified precondition instead
  # of each re-deriving it (leg 2 had no such check, and its later kill of the suite
  # group could have removed the controller itself — making every remaining assertion
  # pass without the required ordering ever holding).
  wrapper_pgid="$(ps -o pgid= -p "$wrapper_pid" 2>/dev/null | tr -d ' ')"
  kill -KILL "$controller_pid" 2>/dev/null || true
  deadline=$(( $(date +%s) + 10 ))
  while :; do
    if ! kill -0 "$controller_pid" 2>/dev/null ||
       [ -n "$(ps -o stat= -p "$controller_pid" 2>/dev/null | grep Z || true)" ]; then
      break
    fi
    if [ "$(date +%s)" -ge "$deadline" ]; then
      echo "abort leak setup: controller $controller_pid survived SIGKILL" >&2
      return 1
    fi
    sleep 0.5
  done
  while :; do
    [ "$(ps -o ppid= -p "$wrapper_pid" 2>/dev/null | tr -d ' ')" = "1" ] && return 0
    kill -0 "$wrapper_pid" 2>/dev/null || {
      echo "abort leak setup: wrapper $wrapper_pid died with its controller" >&2
      return 1
    }
    if [ "$(date +%s)" -ge "$deadline" ]; then
      echo "abort leak setup: wrapper $wrapper_pid was never reparented" >&2
      return 1
    fi
    sleep 0.5
  done
}

await_suite_exit() {
  local deadline
  deadline=$(( $(date +%s) + GRACE ))
  while kill -0 "$suite_pid" 2>/dev/null; do
    [ "$(date +%s)" -ge "$deadline" ] && break
    sleep 0.5
  done
  kill -0 "$suite_pid" 2>/dev/null && return 1
  return 0
}

# The verdict is about the GROUP, not the leader. The wrapper backgrounds a TERM-immune
# child in that same group; a cleanup that kills the session leader but misses the child
# leaves the leak in place while "the wrapper is gone" reads true — and the probe's own
# cleanup would then erase the very evidence the leg exists to surface. Residue under the
# leg's private tmp path is checked too, so a survivor that left the group still counts.
wrapper_group_members_alive() {
  [ -n "$wrapper_pgid" ] || return 0
  ps -eo pid=,pgid=,stat= 2>/dev/null |
    awk -v want="$wrapper_pgid" '$2 == want && $3 !~ /Z/ { print $1 }'
}
wrapper_gone_within() {
  local deadline members residue
  deadline=$(( $(date +%s) + $1 ))
  while :; do
    members="$(wrapper_group_members_alive | tr '\n' ' ')"
    residue="$(probe_processes | tr '\n' ' ')"
    case "$members$residue" in
      *[0-9]*) : ;;
      *) return 0 ;;
    esac
    [ "$(date +%s)" -ge "$deadline" ] && break
    sleep 1
  done
  printf 'abort leak: group members alive: %s | private-path residue: %s\n' \
    "${members:-none}" "${residue:-none}" >&2
  return 1
}

diagnose_wrapper() {
  printf 'abort leak diagnostic (%s): wrapper=%s %s\n' "$1" "$wrapper_pid" \
    "$(ps -o pid=,ppid=,etime=,stat= -p "$wrapper_pid" 2>/dev/null | tr -s ' ')" >&2
}

# ---- leg 1: a trappable abort — the suite's own cleanup must reap the wrapper --------
if [ "$ABORT_LEAK_PROBE_LEG" = 1 ] || [ "$ABORT_LEAK_PROBE_LEG" = all ]; then
leg1_orphaned=0
orphan_target_wrapper "" && leg1_orphaned=1
check "leg1: the controller was removed and the wrapper reparented to init" '[ "$leg1_orphaned" = 1 ]'
if [ "$leg1_orphaned" = 1 ]; then
  signal_suite TERM
  leg1_suite_gone=0; await_suite_exit && leg1_suite_gone=1
  check "leg1: the aborted suite exits" '[ "$leg1_suite_gone" = 1 ]'
  leg1_reaped=0; wrapper_gone_within "$GRACE" && leg1_reaped=1
  [ "$leg1_reaped" = 1 ] || diagnose_wrapper leg1
  check "leg1: a terminated suite reaps the reviewer wrapper it started" '[ "$leg1_reaped" = 1 ]'
fi
cleanup; PROBE_TMP=""; PROBE_TMP_REAL=""; suite_pgid=""
fi

# ---- leg 2: an untrappable abort — only the fixture's own bound can end the wrapper --
if [ "$ABORT_LEAK_PROBE_LEG" = 2 ] || [ "$ABORT_LEAK_PROBE_LEG" = all ]; then
leg2_orphaned=0
orphan_target_wrapper "$LEG2_HANG_BOUND" && leg2_orphaned=1
check "leg2: the controller was removed and the wrapper reparented to init" '[ "$leg2_orphaned" = 1 ]'
if [ "$leg2_orphaned" = 1 ]; then
  signal_suite KILL
  leg2_suite_gone=0; await_suite_exit && leg2_suite_gone=1
  check "leg2: the killed suite exits without running any cleanup" '[ "$leg2_suite_gone" = 1 ]'
  # Precondition: with no trap able to run, the wrapper must still be here. If it is
  # already gone, something else reaped it and the bound was never exercised.
  # `kill -0` succeeds for a zombie, and the verdict below excludes zombies — so a wrapper
  # that had already died would satisfy "still alive" here and "gone" there, passing the
  # leg without the bound ever being exercised. Require a live, non-zombie process.
  leg2_survived_abort=0
  if kill -0 "$wrapper_pid" 2>/dev/null; then
    case "$(ps -o stat= -p "$wrapper_pid" 2>/dev/null || true)" in
      ''|*Z*) : ;;
      *) leg2_survived_abort=1 ;;
    esac
  fi
  check "leg2: no reaper ran, so the wrapper is still alive right after the kill" \
    '[ "$leg2_survived_abort" = 1 ]'
  leg2_self_exit=0; wrapper_gone_within "$(( LEG2_HANG_BOUND + GRACE ))" && leg2_self_exit=1
  [ "$leg2_self_exit" = 1 ] || diagnose_wrapper leg2
  check "leg2: an unreaped wrapper still exits on the fixture's own lifetime bound" \
    '[ "$leg2_self_exit" = 1 ]'
fi

fi

if [ "$fails" -eq 0 ]; then
  echo "review_gate_abort_leak_ok leg=$ABORT_LEAK_PROBE_LEG client=$ABORT_LEAK_PROBE_CLIENT"
  exit 0
fi
echo "review_gate_abort_leak_failed=$fails" >&2
exit 1
