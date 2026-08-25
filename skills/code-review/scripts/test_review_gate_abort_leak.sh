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
# Every verdict below is a fact the run leaves behind — the work dir the EXIT trap would
# have deleted, the marker the fixture writes only past its countdown — never an
# observation of what was true at the instant the probe looked. Liveness questions all go
# through wrapper_state() so they cannot answer the same process differently, and a
# scenario the probe fails to BUILD is retried rather than reported as a failed assertion.
# All three of those rules are here because the earlier spellings red this gate on CI
# while the suite was behaving correctly.
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
  claude) PROBE_BEHAVIOR_FILE=claude_behavior; PROBE_WRAPPER=claude_review.sh
          PROBE_BOUND_MARKER=claude_hang_bound_reached ;;
  fallback) PROBE_BEHAVIOR_FILE=kimi_behavior; PROBE_WRAPPER=kimi_review.sh
            PROBE_BOUND_MARKER=kimi_hang_bound_reached ;;
  *) echo "ABORT_LEAK_PROBE_CLIENT must be claude or fallback" >&2; exit 2 ;;
esac
# How many times a leg may rebuild its scenario before giving up. Only the SETUP is
# retried: constructing "an orphaned wrapper with no reaper left" depends on the probe
# winning races against the controller and the host, and losing one says nothing about
# the suite. An assertion ABOUT the suite is never retried, so a fixture whose bound was
# reverted fails on every attempt and cannot be retried into green.
SETUP_ATTEMPTS="${ABORT_LEAK_PROBE_SETUP_ATTEMPTS:-3}"

# ONE process-state vocabulary for the whole probe. Three separate spellings of "is it
# there?" used to disagree about the same pid: `kill -0` succeeds for a zombie, reading
# ppid succeeds for a zombie, and the two verdict scans exclude zombies. An already-dead
# wrapper awaiting reaping therefore satisfied "reparented to init", failed "still alive",
# and satisfied "gone" — one process state, three answers, and a red that named the suite
# for something the suite had not done. Every liveness question below goes through here.
wrapper_state() {
  local st rc
  case "${1:-}" in ''|*[!0-9]*) printf 'absent\n'; return 0 ;; esac
  st="$(ps -o stat= -p "$1" 2>/dev/null)"; rc=$?
  # `ps` exits 1 for "no such process", which is a real answer. Anything above that is
  # the TOOL failing, not the process being gone — and swallowing that into `absent`
  # would report a suite exited because `ps` could not run. Unknown is reported as its
  # own state and every consumer treats it as still present, because the expensive
  # direction of this error is declaring something gone that is not.
  if [ "$rc" -gt 1 ]; then printf 'unknown\n'; return 0; fi
  case "$st" in
    '') printf 'absent\n' ;;
    *Z*) printf 'zombie\n' ;;
    # A stopped process is neither running nor gone, and leg 2 deliberately puts the
    # wrapper in this state while it arms. Folding it into `live` would let the arming
    # step report success without SIGSTOP having actually landed.
    # `T` (job-control stop) or `t` (tracing stop), anywhere in the field: neither letter
    # appears among the flag characters either ps appends, so this cannot catch a
    # running process by accident.
    *[Tt]*) printf 'stopped\n' ;;
    *) printf 'live\n' ;;
  esac
}

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
# The fixture writes this file only after its bounded countdown runs to completion, so
# its presence says the fixture's OWN lifetime bound ended the wrapper and its absence
# says something else did. That is the fact leg 2 needs, and it is a fact about which
# code path ran — not about what was true at the instant the probe happened to look.
bound_marker_path() {
  local work
  work="$(suite_work_dir)" || return 1
  printf '%s\n' "$work/state/$PROBE_BOUND_MARKER"
}
bound_marker_state() {
  local path
  path="$(bound_marker_path)" || { printf 'no-work-dir\n'; return 0; }
  if [ -e "$path" ]; then printf 'present\n'; else printf 'absent\n'; fi
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
  # Both, not just the pid: a retry that left the previous attempt's group id in place
  # would have the verdict scan looking for members of a group this attempt never built.
  wrapper_pid=""
  wrapper_pgid=""

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
    # Third site of the same class: a suite that has exited but whose corpse this shell
    # has not reaped still answers `kill -0`, so the bare existence test would keep this
    # loop polling for a dead suite until the whole reach budget elapsed and then report
    # the wrong one of the two failures below.
    [ "$(wrapper_state "$suite_pid")" = live ] || { suite_died=1; break; }
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
  # Its own deadline: this loop used to reuse the one the controller wait had already
  # been counting down, so a controller that took nine of those ten seconds to die left
  # the reparent check one second to succeed in.
  deadline=$(( $(date +%s) + 10 ))
  while :; do
    # A corpse is not an orphan. The old spelling of this check read ppid, which a zombie
    # answers, so a wrapper some reaper had already killed passed for a live orphan and
    # the leg went on to make assertions about a scenario it had never built.
    if [ "$(ps -o ppid= -p "$wrapper_pid" 2>/dev/null | tr -d ' ')" = "1" ] &&
       [ "$(wrapper_state "$wrapper_pid")" = live ]; then
      return 0
    fi
    case "$(wrapper_state "$wrapper_pid")" in
      live) : ;;
      *)
        printf 'abort_leak_setup_lost: wrapper %s was already %s before the abort — a reaper reached it first (bound marker: %s)\n' \
          "$wrapper_pid" "$(wrapper_state "$wrapper_pid")" "$(bound_marker_state)" >&2
        return 1
        ;;
    esac
    if [ "$(date +%s)" -ge "$deadline" ]; then
      echo "abort_leak_setup_lost: wrapper $wrapper_pid was never reparented" >&2
      return 1
    fi
    sleep 0.5
  done
}

# Same one vocabulary as the wrapper: a killed suite whose corpse the probe's own shell
# has not reaped yet still answers `kill -0`, so spelling this as `kill -0` made a bookkeeping
# lag inside the probe look like a suite that refused to die.
await_suite_exit() {
  local deadline
  deadline=$(( $(date +%s) + GRACE ))
  # GONE is `absent` or `zombie` — a corpse cannot run cleanup — and everything else,
  # `stopped` included, is still present. Testing `!= live` instead would call a STOPPED
  # suite exited: the work dir would still be there, the wrapper would still reach its
  # bound, and every leg-2 assertion could pass while the suite was never killed at all.
  # Introducing a third process state without revisiting the checks that had two is the
  # same defect this round is about, one file over.
  while :; do
    case "$(wrapper_state "$suite_pid")" in absent|zombie) return 0 ;; esac
    [ "$(date +%s)" -ge "$deadline" ] && break
    sleep 0.5
  done
  case "$(wrapper_state "$suite_pid")" in absent|zombie) return 0 ;; esac
  return 1
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
  printf 'abort leak diagnostic (%s): wrapper=%s state=%s bound_marker=%s ps=[%s]\n' \
    "$1" "$wrapper_pid" "$(wrapper_state "$wrapper_pid")" "$(bound_marker_state)" \
    "$(ps -o pid=,ppid=,etime=,stat= -p "$wrapper_pid" 2>/dev/null | tr -s ' ')" >&2
}

# Build the scenario, retrying only the CONSTRUCTION of it. Losing a race to some reaper
# leaves the probe with nothing to assert about, and reporting that as a failed assertion
# is what made this gate red at random on three separate assertions — each of them a
# statement about the probe's environment wearing the wording of a statement about the
# suite. A lost setup is retried from a fresh suite run; only running out of attempts is
# a failure, and it says so in those words.
# $3, when given, is a function run after a successful orphan that must also succeed for
# the attempt to count — the place for any arming step whose failure means the scenario
# was lost rather than the suite misbehaved.
orphan_with_retry() {
  local hang_bound="$1" leg="$2" arm="${3:-}" attempt=1
  while [ "$attempt" -le "$SETUP_ATTEMPTS" ]; do
    if orphan_target_wrapper "$hang_bound" && { [ -z "$arm" ] || "$arm"; }; then return 0; fi
    printf '%s: setup attempt %s/%s did not build the scenario; rebuilding\n' \
      "$leg" "$attempt" "$SETUP_ATTEMPTS" >&2
    cleanup; PROBE_TMP=""; PROBE_TMP_REAL=""; suite_pgid=""; suite_pid=""; suite_start=""
    attempt=$((attempt+1))
  done
  printf '%s: could not build the scenario in %s attempts\n' "$leg" "$SETUP_ATTEMPTS" >&2
  return 1
}

# ---- leg 1: a trappable abort — the suite's own cleanup must reap the wrapper --------
if [ "$ABORT_LEAK_PROBE_LEG" = 1 ] || [ "$ABORT_LEAK_PROBE_LEG" = all ]; then
leg1_orphaned=0
orphan_with_retry "" leg1 && leg1_orphaned=1
check "leg1: the scenario was built — controller removed, live wrapper reparented to init" \
  '[ "$leg1_orphaned" = 1 ]'
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
leg2_work=""
# Arm the leg, in this order: prove the wrapper is live, freeze its group, then read the
# marker. Freezing first is what makes the read meaningful — while the group is stopped
# nothing can write that file, so "absent" is a stable fact rather than a sample taken
# between two racing events. Absent means the bound has not fired, which is exactly the
# precondition leg 2 needs; present means it already fired and the scenario is rebuilt.
# The ordering this establishes — controller gone, bound not yet fired, abort next — is
# ENFORCED rather than observed, and needs no clock and no timestamp comparison, which
# second-granularity stamps could not have given honestly anyway.
leg2_arm() {
  leg2_work="$(suite_work_dir || true)"
  [ -n "$leg2_work" ] && [ -d "$leg2_work/state" ] || {
    echo "abort_leak_setup_lost: leg2 found no suite work dir to arm against" >&2
    return 1
  }
  [ "$(wrapper_state "$wrapper_pid")" = live ] || {
    printf 'abort_leak_setup_lost: wrapper %s was %s before arming\n' \
      "$wrapper_pid" "$(wrapper_state "$wrapper_pid")" >&2
    return 1
  }
  # STOP the wrapper for the length of the abort. Checking "is it still live" and then
  # killing the suite is a race no shell can close: between the two the countdown can
  # finish, write the marker, and exit, after which every assertion passes while the
  # untrappable-abort path never ran. A stopped process cannot reach the write at all,
  # so the ordering stops being something to observe and becomes something enforced —
  # which is the whole point of this round. The group, not the leader: the claude stub
  # runs its countdown in a backgrounded child that shares the wrapper's group, and
  # stopping only the leader would leave that child counting.
  # Ownership before signalling, proved the way `probe_processes` proves it: re-match the
  # pid against the live table by this run's private path, then require it to LEAD the
  # group being signalled. Those two together mean the group is the validated wrapper's
  # own, which is what makes a group signal safe here.
  # (`probe_group_is_ours` is not used for this: measured on macOS it answers no for a
  # group whose leader `probe_processes` matches by the same private path in the same
  # instant. That is pre-existing and only makes `cleanup` fall back to per-pid kills —
  # which still reap, since every member carries the path — so it is reported rather
  # than changed under this round's scope.)
  probe_processes | grep -qx "$wrapper_pid" || {
    echo "abort_leak_setup_lost: wrapper $wrapper_pid no longer matches this run's private path" >&2
    return 1
  }
  [ "$wrapper_pgid" = "$wrapper_pid" ] || {
    printf 'abort_leak_setup_lost: wrapper %s does not lead group %s; refusing to stop the group\n' \
      "$wrapper_pid" "$wrapper_pgid" >&2
    return 1
  }
  kill -STOP -"$wrapper_pgid" 2>/dev/null || true
  [ "$(wrapper_state "$wrapper_pid")" = stopped ] || {
    printf 'abort_leak_setup_lost: wrapper %s did not stop (state %s)\n' \
      "$wrapper_pid" "$(wrapper_state "$wrapper_pid")" >&2
    kill -CONT -"$wrapper_pgid" 2>/dev/null || true
    return 1
  }
  # Observe the barrier; never manufacture it. Deleting the marker here destroyed the one
  # piece of evidence that distinguishes the two cases: for the claude stub the countdown
  # runs in a child, so the child can finish and write the marker while the wrapper is
  # still unwinding and therefore still reads live. Removing it then made a scenario that
  # was already lost — the bound fired BEFORE the abort — look like a clean run whose
  # marker never came back, i.e. a false RED against a suite that behaved correctly.
  # Read after the freeze, when nothing can be writing that file: absent means the bound
  # has not fired yet, which is the precondition. Present means it already has, so the
  # scenario is lost and gets rebuilt. The suite wipes state files at each case start, so
  # a marker here belongs to this case, and every retry gets a fresh private tmp anyway.
  [ "$(bound_marker_state)" = absent ] || {
    printf 'abort_leak_setup_lost: %s already present — the bound fired before the abort\n' \
      "$PROBE_BOUND_MARKER" >&2
    kill -CONT -"$wrapper_pgid" 2>/dev/null || true
    return 1
  }
  return 0
}
# Resume the wrapper once the suite is gone. From here its countdown runs with no
# controller, no suite, and no trap anywhere — exactly the state leg 2 is about.
leg2_resume_wrapper() {
  [ -n "${wrapper_pgid:-}" ] && [ "$wrapper_pgid" = "${wrapper_pid:-}" ] &&
    { kill -CONT -"$wrapper_pgid" 2>/dev/null || true; }
  return 0
}
leg2_orphaned=0
orphan_with_retry "$LEG2_HANG_BOUND" leg2 leg2_arm && leg2_orphaned=1
check "leg2: the scenario was built — controller removed, live wrapper reparented to init" \
  '[ "$leg2_orphaned" = 1 ]'
if [ "$leg2_orphaned" = 1 ]; then
  signal_suite KILL
  # The suite must really be gone, and this stays an ASSERTION rather than a warning:
  # the work-dir check below passes vacuously against a suite that is still running,
  # because a live suite has not reached its EXIT trap either. Demoting this to a
  # diagnostic would leave that check reading "no cleanup ran" whenever the kill missed.
  # What made the old version of this flaky was the zombie ambiguity inside
  # await_suite_exit, not the assertion itself — that is fixed at the helper, so the
  # obligation can be kept instead of traded away.
  leg2_suite_gone=0; await_suite_exit && leg2_suite_gone=1
  # Resume only now: the wrapper was held stopped across the abort so its countdown
  # could not have completed before it, and everything observed from here happens with
  # no reaper of any kind left alive.
  leg2_resume_wrapper
  check "leg2: the killed suite is gone" '[ "$leg2_suite_gone" = 1 ]'

  # No trap ran — structurally, not by the clock. The suite's EXIT trap ends in
  # `rm -rf "$WORK"`, so the work dir outliving a SIGKILLed suite is the trap's absence
  # made visible. The old spelling asked whether the suite exited inside a 30s window,
  # which is a fact about the host's scheduler rather than about whether cleanup ran.
  # Read together with the assertion above, the pair says: the suite is gone AND it left
  # its work dir behind — which only an untrapped death produces.
  leg2_no_cleanup=0
  [ "$leg2_suite_gone" = 1 ] && [ -n "$leg2_work" ] && [ -d "$leg2_work" ] && leg2_no_cleanup=1
  check "leg2: no cleanup ran — the killed suite's work dir survives it" \
    '[ "$leg2_no_cleanup" = 1 ]'

  leg2_self_exit=0; wrapper_gone_within "$(( LEG2_HANG_BOUND + GRACE ))" && leg2_self_exit=1
  [ "$leg2_self_exit" = 1 ] || diagnose_wrapper leg2
  check "leg2: an unreaped wrapper leaves nothing behind" '[ "$leg2_self_exit" = 1 ]'

  # WHY it ended, not WHEN it was last seen. The fixture writes this only on the far side
  # of its bounded countdown, so present means the bound ended it and absent means a
  # reaper did — the distinction the deleted "still alive right after the kill" check was
  # trying to draw by looking at the process at one instant, which a corpse answers wrong.
  # An unbounded fixture never reaches the write, so this still reds the reverted bound.
  leg2_bound_marker="$(bound_marker_state)"
  [ "$leg2_bound_marker" = present ] || diagnose_wrapper leg2-bound
  check "leg2: the fixture's own lifetime bound is what ended the wrapper" \
    '[ "$leg2_bound_marker" = present ]'
fi

fi

if [ "$fails" -eq 0 ]; then
  echo "review_gate_abort_leak_ok leg=$ABORT_LEAK_PROBE_LEG client=$ABORT_LEAK_PROBE_CLIENT"
  exit 0
fi
echo "review_gate_abort_leak_failed=$fails" >&2
exit 1
