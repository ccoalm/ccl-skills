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
} > "$helpers"
grep -q 'wrapper_state()' "$helpers" || { echo "FAIL: could not lift wrapper_state (moved?)" >&2; exit 1; }
grep -q 'await_suite_exit()' "$helpers" || { echo "FAIL: could not lift await_suite_exit (moved?)" >&2; exit 1; }
# shellcheck disable=SC1090
. "$helpers"

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

kill -CONT "$live_pid" 2>/dev/null
kill -KILL "$live_pid" 2>/dev/null
wait "$live_pid" 2>/dev/null
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
kill -KILL "$unknown_pid" 2>/dev/null; wait "$unknown_pid" 2>/dev/null

printf 'abort_leak_state_helpers: pass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
echo "abort_leak_state_helpers_ok"
