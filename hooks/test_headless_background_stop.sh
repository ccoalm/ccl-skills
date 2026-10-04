#!/usr/bin/env bash
# Deterministic behavior suite for hooks/headless-background-stop.sh.
# Registered in the Makefile `test` target; requires jq to build hook inputs.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
HOOK="${HEADLESS_BG_HOOK:-$SCRIPT_DIR/headless-background-stop.sh}"
[ -f "$HOOK" ] || { echo "FAIL: hook not found: $HOOK" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq required for this suite" >&2; exit 1; }
bash -n "$HOOK" || { echo "FAIL: hook is not syntactically valid" >&2; exit 1; }

pass=0; fail=0
WORK="$(mktemp -d "${TMPDIR:-/tmp}/headless-bg-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
STATE="$WORK/state"; mkdir -p "$STATE"
ERR="$WORK/err"

# payload <session> <stop_hook_active> <tasks-json>
payload() {
  jq -nc --arg s "$1" --argjson a "$2" --argjson t "$3" \
    '{session_id:$s,hook_event_name:"Stop",stop_hook_active:$a,background_tasks:$t}'
}
task() {  # task <id> <status> [description]
  jq -nc --arg i "$1" --arg st "$2" --arg d "${3:-Run the review gate}" \
    '{id:$i,type:"shell",status:$st,description:$d,command:"sleep 60"}'
}

# run <entrypoint> <tmpdir> <stdin> -> sets OUT; fails the case unless exit 0 with silent stderr
run() {
  local rc errbytes
  OUT=$(printf '%s' "$3" | CLAUDE_CODE_ENTRYPOINT="$1" TMPDIR="$2" bash "$HOOK" 2>"$ERR"); rc=$?
  errbytes=$(wc -c <"$ERR" | tr -d ' ')
  [ "$rc" = 0 ] && [ "$errbytes" = 0 ] && return 0
  echo "FAIL: hook must exit 0 with silent stderr (rc=$rc, stderr=${errbytes}B)"; fail=$((fail + 1)); return 1
}

# expect <block|quiet|notice> <label> <entrypoint> <tmpdir> <stdin> [needle...]
expect() {
  local want="$1" label="$2" got needle
  run "$3" "$4" "$5" || return
  if [ -z "$OUT" ]; then
    got=quiet
  elif printf '%s' "$OUT" | jq -e '.decision == "block" and (.reason | type == "string")' >/dev/null 2>&1; then
    got=block
  elif printf '%s' "$OUT" | jq -e '.systemMessage | startswith("Background task check unavailable")' >/dev/null 2>&1; then
    got=notice
  else
    echo "FAIL [$label]: unexpected output: $OUT"; fail=$((fail + 1)); return
  fi
  if [ "$got" != "$want" ]; then
    echo "FAIL [$label]: expected $want, got $got: $OUT"; fail=$((fail + 1)); return
  fi
  shift 5
  for needle in "$@"; do
    if ! printf '%s' "$OUT" | jq -e --arg n "$needle" '.reason | contains($n)' >/dev/null 2>&1; then
      echo "FAIL [$label]: reason lacks '$needle': $OUT"; fail=$((fail + 1)); return
    fi
  done
  pass=$((pass + 1))
}

one="[$(task t1 running 'Run the external review on the diff')]"
expect block "headless stop with a running task" sdk-cli "$STATE" "$(payload s1 false "$one")" \
  "headless session" "Run the external review on the diff (t1)" "foreground" "TaskStop" "once per task"
expect quiet "the same task at the next stop" sdk-cli "$STATE" "$(payload s1 true "$one")"
expect quiet "the same task without the host retry flag" sdk-cli "$STATE" "$(payload s1 false "$one")"
both="[$(task t1 running),$(task t2 running 'Wait for the lane')]"
expect block "a new task in the same session" sdk-cli "$STATE" "$(payload s1 true "$both")" "Wait for the lane (t2)"
if printf '%s' "$OUT" | jq -e '.reason | contains("(t1)")' >/dev/null 2>&1; then
  echo "FAIL [a new task in the same session]: an already reported task was listed again"; fail=$((fail + 1))
fi
expect block "another session with the same task id" sdk-cli "$STATE" "$(payload s2 false "$one")" "(t1)"
expect block "an SDK entrypoint" sdk-py "$STATE" "$(payload s3 false "$one")" "(t1)"

expect quiet "an interactive session" cli "$STATE" "$(payload s4 false "$one")"
expect quiet "no entrypoint" "" "$STATE" "$(payload s4 false "$one")"
expect quiet "a lookalike entrypoint" sdkx "$STATE" "$(payload s4 false "$one")"
done_task="[$(task t9 completed)]"
expect quiet "no task still running" sdk-cli "$STATE" "$(payload s5 false "$done_task")"
expect quiet "no background tasks field" sdk-cli "$STATE" '{"session_id":"s5","hook_event_name":"Stop","stop_hook_active":false}'
expect quiet "another hook event" sdk-cli "$STATE" "$(jq -nc --argjson t "$one" '{session_id:"s5",hook_event_name:"SubagentStop",stop_hook_active:false,background_tasks:$t}')"
expect notice "input that is not JSON" sdk-cli "$STATE" 'not json'

# Without usable state a repeat cannot be recognized, so the host retry flag bounds it.
expect block "no state, first stop" sdk-cli "$WORK/missing/dir" "$(payload s6 false "$one")" "(t1)"
expect quiet "no state, host retry" sdk-cli "$WORK/missing/dir" "$(payload s6 true "$one")"

# The helper repeats the entrypoint check, so it holds even when called without the wrapper.
HELPER="$(dirname "$HOOK")/host-input.py"
helper_quiet() {  # helper_quiet <label> <entrypoint>
  local out
  out=$(printf '%s' "$(payload s9 false "$one")" | CLAUDE_CODE_ENTRYPOINT="$2" TMPDIR="$STATE" python3 "$HELPER" headless-background 2>"$ERR")
  if [ -z "$out" ] && [ ! -s "$ERR" ]; then pass=$((pass + 1)); else echo "FAIL [$1]: helper spoke: $out"; fail=$((fail + 1)); fi
}
helper_quiet "the helper alone in an interactive session" cli
helper_quiet "the helper alone with a lookalike entrypoint" sdkx

# The wrapper leaves interactive sessions before the helper: no Python start, no notice about it.
BASH_BIN="$(command -v bash)"; mkdir -p "$WORK/no-python"; ln -s "$(command -v dirname)" "$WORK/no-python/dirname"
no_python() {  # no_python <label> <entrypoint> <expected output or empty>
  local out
  out=$(printf '%s' "$(payload s10 false "$one")" | CLAUDE_CODE_ENTRYPOINT="$2" PATH="$WORK/no-python" "$BASH_BIN" "$HOOK" 2>"$ERR")
  if [ "$out" = "$3" ] && [ ! -s "$ERR" ]; then pass=$((pass + 1)); else echo "FAIL [$1]: got '$out'"; fail=$((fail + 1)); fi
}
no_python "an interactive session without Python" cli ""
no_python "a headless session without Python" sdk-cli \
  '{"systemMessage":"Background task check unavailable: Python input normalizer missing."}'

many="[$(for i in 1 2 3 4 5 6 7; do task "m$i" running; printf ','; done | sed 's/,$//')]"
expect block "a long task list" sdk-cli "$STATE" "$(payload s7 false "$many")" "(m5)" "and 2 more"
multiline="[$(task n1 running "$(printf 'line one\nline two')")]"
expect block "a description with a line break" sdk-cli "$STATE" "$(payload s8 false "$multiline")" "line one line two (n1)"

echo "pass=$pass fail=$fail"
[ "$fail" = 0 ] || exit 1
echo "test_headless_background_stop_ok"
