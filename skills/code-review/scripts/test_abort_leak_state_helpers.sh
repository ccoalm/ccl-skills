#!/usr/bin/env bash
# Pins the abort-leak probe's process-state vocabulary and the one helper that consumes
# it, against real processes in each state.
#
# The probe exists because three spellings of "is it there?" disagreed about one pid.
# The fix was to give the whole probe a single vocabulary — so the vocabulary itself is
# now load-bearing, and every consumer must agree with it. That is not free: adding
# `stopped` as a third state silently changed the meaning of every consumer that had been
# written when there were two, and `await_suite_exit` went on treating "not live" as
# "gone" — which would have called a STOPPED suite exited and let leg 2 pass while the
# suite it was supposed to have killed was still sitting there.
#
#   bash skills/code-review/scripts/test_abort_leak_state_helpers.sh
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROBE="$DIR/test_review_gate_abort_leak.sh"
[ -f "$PROBE" ] || { echo "FAIL: probe not found: $PROBE" >&2; exit 1; }

pass=0; fail=0
note() { fail=$((fail+1)); printf 'FAIL  %s\n' "$1" >&2; }
ok()   { pass=$((pass+1)); }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/abort-leak-helpers.XXXXXX") || exit 1
cleanup_all() {
  local p
  for p in ${KIDS:-}; do kill -CONT "$p" 2>/dev/null; kill -KILL "$p" 2>/dev/null; done
  rm -rf "$TMP"
}
KIDS=""
# Own it only while it is outstanding. A pid that has been reaped is a number the OS is
# free to hand to somebody else, so leaving it in KIDS turns the EXIT trap into a signal
# aimed at a stranger — and this repo runs suites eight-way parallel, so the stranger is
# plausibly another lane. Same rule the probe under test applies before it signals
# anything: prove current ownership, never trust a cached pid.
drop_kid() {
  local keep="" k
  for k in ${KIDS:-}; do [ "$k" = "$1" ] || keep="$keep $k"; done
  KIDS="$keep"
}
reap_kid() { # reap_kid <pid> — stop owning it the moment it is reaped
  kill -CONT "$1" 2>/dev/null
  kill -KILL "$1" 2>/dev/null
  wait "$1" 2>/dev/null
  drop_kid "$1"
}
trap cleanup_all EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

# Lift the helpers out rather than sourcing the probe, which would run both legs.
helpers=$TMP/helpers.sh
{
  echo '#!/usr/bin/env bash'
  echo 'set -uo pipefail'
  awk '/^wrapper_state\(\) \{/{p=1} p; p && /^\}$/{exit}' "$PROBE"
  awk '/^await_suite_exit\(\) \{/{p=1} p; p && /^\}$/{exit}' "$PROBE"
  awk '/^orphan_reaper_pid\(\) \{/{p=1} p; p && /^\}$/{exit}' "$PROBE"
  awk '/^wrapper_is_reparented\(\) \{/{p=1} p; p && /^\}$/{exit}' "$PROBE"
} > "$helpers"
grep -q 'wrapper_state()' "$helpers" || { echo "FAIL: could not lift wrapper_state (moved?)" >&2; exit 1; }
grep -q 'await_suite_exit()' "$helpers" || { echo "FAIL: could not lift await_suite_exit (moved?)" >&2; exit 1; }
grep -q 'orphan_reaper_pid()' "$helpers" || { echo "FAIL: could not lift orphan_reaper_pid (moved?)" >&2; exit 1; }
grep -q 'wrapper_is_reparented()' "$helpers" || { echo "FAIL: could not lift wrapper_is_reparented (moved?)" >&2; exit 1; }
# shellcheck disable=SC1090
. "$helpers"
ORPHAN_REAPER_PID="$(orphan_reaper_pid)"

# --- states -----------------------------------------------------------------
sleep 300 & live_pid=$!; KIDS="$KIDS $live_pid"
[ "$(wrapper_state "$live_pid")" = live ] && ok || note "a running child must read live, got $(wrapper_state "$live_pid")"

kill -STOP "$live_pid" 2>/dev/null
stopped_seen=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  stopped_seen="$(wrapper_state "$live_pid")"
  [ "$stopped_seen" = stopped ] && break
  sleep 0.2
done
[ "$stopped_seen" = stopped ] && ok || note "a stopped child must read stopped, got $stopped_seen"

# THE regression: a stopped process is still present. Treating "not live" as gone is how
# a suite that was never killed reads as exited.
GRACE=2
suite_pid="$live_pid"
if await_suite_exit; then
  note "await_suite_exit reported a STOPPED child as exited — 'not live' is not 'gone'"
else
  ok
fi

reap_kid "$live_pid"
suite_pid="$live_pid"
if await_suite_exit; then ok; else note "await_suite_exit must report a reaped child as gone"; fi

# A never-existing pid, and a non-numeric one, are both absent rather than an error.
[ "$(wrapper_state 999999999)" = absent ] && ok || note "an unused pid must read absent"
[ "$(wrapper_state "")" = absent ] && ok || note "an empty pid must read absent"
[ "$(wrapper_state notanumber)" = absent ] && ok || note "a non-numeric pid must read absent"

# A zombie: exited, not yet reaped. It answers kill -0 and reports a ppid, which is the
# whole reason this vocabulary exists.
python3 -c '
import os, sys, time
pid = os.fork()
if pid == 0:
    os._exit(0)
sys.stdout.write(str(pid) + "\n")
sys.stdout.flush()
time.sleep(6)
' >"$TMP/zombie.out" 2>/dev/null &
zparent=$!; KIDS="$KIDS $zparent"
zpid=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  zpid="$(head -1 "$TMP/zombie.out" 2>/dev/null || true)"
  [ -n "$zpid" ] && break
  sleep 0.3
done
if [ -n "$zpid" ]; then
  zstate=""
  for _ in 1 2 3 4 5; do
    zstate="$(wrapper_state "$zpid")"
    [ "$zstate" = zombie ] && break
    sleep 0.3
  done
  [ "$zstate" = zombie ] && ok || note "an unreaped corpse must read zombie, got $zstate"
  # And it must NOT read live, which is the exact confusion that red CI three times.
  [ "$zstate" != live ] && ok || note "a corpse must never read live"
else
  note "could not construct a zombie to test against"
fi
reap_kid "$zparent"

# A `ps` that cannot run is not a process that is gone. Shadow ps with a stub that
# exits 127 and prove the state reads unknown, and that await_suite_exit does NOT then
# report the suite exited — the expensive direction of this error.
psdir="$TMP/fakebin"; mkdir -p "$psdir"
printf '#!/bin/sh\nexit 127\n' > "$psdir/ps"; chmod +x "$psdir/ps"
sleep 300 & unknown_pid=$!; KIDS="$KIDS $unknown_pid"
unknown_state="$(PATH="$psdir:$PATH" wrapper_state "$unknown_pid")"
[ "$unknown_state" = unknown ] && ok || note "a failing ps must read unknown, got $unknown_state"
GRACE=2
suite_pid="$unknown_pid"
if PATH="$psdir:$PATH" await_suite_exit; then
  note "await_suite_exit reported exited while ps was broken — a tool failure is not an exit"
else
  ok
fi
reap_kid "$unknown_pid"

# Orphan reparenting: on bare init hosts orphans reparent to PID 1, while under a
# Linux PR_SET_CHILD_SUBREAPER supervisor (such as `systemd --user`) they reparent to
# that subreaper instead. Probing the actual adopter keeps both environments accurate.
case "$ORPHAN_REAPER_PID" in
  ''|*[!0-9]*|0) note "orphan_reaper_pid must be a positive integer, got '$ORPHAN_REAPER_PID'" ;;
  *) ok ;;
esac
sleep 300 & direct_pid=$!; KIDS="$KIDS $direct_pid"
if wrapper_is_reparented "$direct_pid"; then
  note "a direct child with live parent must not report reparented"
else
  ok
fi
reap_kid "$direct_pid"

orphan_pid="$(python3 -c '
import os, subprocess
gr, gw = os.pipe()
pr, pw = os.pipe()
pid = os.fork()
if pid == 0:
    os.close(gw)
    os.close(pr)
    p = subprocess.Popen(
        ["sleep", "300"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    os.write(pw, f"{p.pid}\n".encode())
    os.close(pw)
    os.read(gr, 1)
    os._exit(0)
os.close(gr)
os.close(pw)
child_pid = os.read(pr, 64).decode().strip()
os.close(pr)
os.close(gw)
os.waitpid(pid, 0)
print(child_pid)
')"
if [ -n "$orphan_pid" ]; then
  KIDS="$KIDS $orphan_pid"
  reparented_ok=0
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if wrapper_is_reparented "$orphan_pid"; then reparented_ok=1; break; fi
    sleep 0.1
  done
  [ "$reparented_ok" = 1 ] && ok || note "an orphaned live session leader must satisfy wrapper_is_reparented (reaper=$ORPHAN_REAPER_PID, ppid=$(ps -o ppid= -p "$orphan_pid" 2>/dev/null | tr -d ' '))"
  reap_kid "$orphan_pid"
else
  note "could not construct an orphan process"
fi

# On Linux, force a synthetic PR_SET_CHILD_SUBREAPER (>1) so CI hosts whose ambient
# adopter is PID 1 still exercise and pin the non-1 subreaper branch.
if [ "$(uname -s)" = "Linux" ]; then
  cat > "$TMP/subreaper_probe.py" <<'PY'
import ctypes, os, signal, subprocess, sys

libc = ctypes.CDLL(None)
if libc.prctl(36, 1, 0, 0, 0) != 0:
    sys.exit(1)

r, w = os.pipe()
mid = os.fork()
if mid == 0:
    os.close(r)
    p = subprocess.Popen(
        ["sleep", "300"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    os.write(w, f"{p.pid}\n".encode())
    os.close(w)
    os._exit(0)
os.close(w)
orphan_pid = int(os.read(r, 64).decode().strip())
os.close(r)
os.waitpid(mid, 0)

try:
    cmd = """
set -uo pipefail
. "$HELPERS_PATH"
ORPHAN_REAPER_PID="$(orphan_reaper_pid)"
[ "$ORPHAN_REAPER_PID" = "$EXPECTED_REAPER" ] || exit 11
[ "$ORPHAN_REAPER_PID" -gt 1 ] || exit 12
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if wrapper_is_reparented "$ORPHAN_PID"; then exit 0; fi
  sleep 0.1
done
exit 13
"""
    env = dict(
        os.environ,
        EXPECTED_REAPER=str(os.getpid()),
        ORPHAN_PID=str(orphan_pid),
    )
    rc = subprocess.call(["bash", "-c", cmd], env=env)
finally:
    try:
        os.kill(orphan_pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    while True:
        try:
            wpid, _ = os.waitpid(-1, os.WNOHANG)
            if wpid == 0:
                break
        except ChildProcessError:
            break
sys.exit(rc)
PY
  if HELPERS_PATH="$helpers" python3 "$TMP/subreaper_probe.py"; then
    ok
  else
    note "synthetic Linux PR_SET_CHILD_SUBREAPER probe failed (rc=$?)"
  fi
fi

printf 'abort_leak_state_helpers: pass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
echo "abort_leak_state_helpers_ok"
