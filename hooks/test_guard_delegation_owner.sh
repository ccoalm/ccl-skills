#!/usr/bin/env bash
# Deterministic behavior suite for hooks/guard-delegation-owner.sh.
#
# Mutation-resistant by construction: an earlier version of this suite passed
# 13/13 against five separately broken hooks, so every probe now pins the full
# observable contract, not just "did the word ask appear":
#   - exit status is always 0 (a PreToolUse hook must never fail the tool call)
#   - stdout is either empty or a single valid JSON object of the exact shape
#   - quiet means ZERO bytes on stdout, so a "deny" mutant cannot read as quiet
#   - stderr is always empty (the transcript may hold prompt payloads or secrets)
#   - each probe runs in its own TMPDIR, so one probe cannot satisfy another
#   - only the VERIFIED-loaded state is cached; the ask is stateless by design
# Registered in the Makefile `test` target and GitHub Actions; requires jq.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
HOOK="$SCRIPT_DIR/guard-delegation-owner.sh"
[ -f "$HOOK" ] || { echo "FAIL: hook not found: $HOOK" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq required for this suite" >&2; exit 1; }

ROOT=$(mktemp -d) || exit 1
trap 'rm -rf "$ROOT"' EXIT
pass=0; fail=0
note() { fail=$((fail+1)); printf 'FAIL  %s\n' "$1" >&2; }
ok()   { pass=$((pass+1)); }

# Event shapes copied from a real host transcript, not invented: a completed
# Skill load is an assistant tool_use carrying an id PLUS a user tool_result
# whose tool_use_id matches. `warm` is that pair; `requested` is the request
# alone, which must NOT count as a load.
mk_transcript() { # mk_transcript <path> <warm|cold|requested>
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_other","name":"Skill","input":{"skill":"ccl-skills:product-rd-workflow"}}]}}' > "$1"
  printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_other","content":"Launching skill: ccl-skills:product-rd-workflow"}]}}' >> "$1"
  case "$2" in
    warm|requested)
      printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_ae","name":"Skill","input":{"skill":"ccl-skills:multi-agent-delegation"}}]}}' >> "$1" ;;
  esac
  [ "$2" = warm ] && printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_ae","content":"Launching skill: ccl-skills:multi-agent-delegation"}]}}' >> "$1"
  return 0
}

# run <case-tmpdir> <tool> <transcript> <session> -> sets OUT ERR RC OUTBYTES
# stdout goes to a FILE, never through command substitution: $( ) strips trailing
# newlines, so a newline-only stdout would otherwise read as "no output".
markers_in() { ls "$1" 2>/dev/null | grep -c '^delegation-owner-loaded-'; }

run() {
  local td="$1" tool="$2" tr="$3" sess="$4"
  local eo="$td/.stderr" so="$td/.stdout"
  RUN_TD="$td"
  MARKERS_BEFORE=$(markers_in "$td")
  jq -nc --arg t "$tool" --arg p "$tr" --arg s "$sess" \
        '{tool_name:$t,transcript_path:$p,session_id:$s,cwd:"/tmp"}' \
        | TMPDIR="$td" bash "$HOOK" >"$so" 2>"$eo"
  RC=$?
  OUT=$(cat "$so" 2>/dev/null)
  ERR=$(cat "$eo" 2>/dev/null)
  OUTBYTES=$(wc -c < "$so" 2>/dev/null | tr -d ' ')
  ERRBYTES=$(wc -c < "$eo" 2>/dev/null | tr -d ' ')
}

# Every invocation, whatever the case, must satisfy these.
assert_universal() { # assert_universal <label>
  local label="$1"
  [ "$RC" -eq 0 ] || note "$label: exit status $RC, must be 0"
  # bytes, not "$ERR is empty": a newline-only write survives command
  # substitution and would otherwise read as silence (found by mutation M9)
  [ "${ERRBYTES:-0}" -eq 0 ] || note "$label: wrote $ERRBYTES bytes to stderr (possible transcript leak)"
  if [ "${OUTBYTES:-0}" -gt 0 ]; then
    # -s slurps the whole stream: enforces EXACTLY one JSON value, so trailing
    # garbage or a second object cannot pass the way bare `jq -e .` allows.
    printf '%s' "$OUT" | jq -es 'length==1 and (.[0]|type=="object")' >/dev/null 2>&1 \
      || note "$label: stdout is not exactly one JSON object"
  fi
}

assert_ask() { # assert_ask <label> <case-tmpdir>
  local label="$1" td="$2" d
  assert_universal "$label"
  [ -n "$OUT" ] || { note "$label: expected an ask, got no output"; return; }
  d=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  [ "$d" = ask ] || { note "$label: permissionDecision=$d, expected ask"; return; }
  [ "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.hookEventName // empty')" = PreToolUse ] \
    || note "$label: wrong or missing hookEventName"
  [ -n "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty')" ] \
    || note "$label: empty permissionDecisionReason"
  # exact key set at both levels: an extra or renamed key is a contract change
  [ "$(printf '%s' "$OUT" | jq -r 'keys|join(",")')" = "hookSpecificOutput" ] \
    || note "$label: unexpected top-level keys"
  [ "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput|keys|sort|join(",")')" \
    = "hookEventName,permissionDecision,permissionDecisionReason" ] \
    || note "$label: unexpected hookSpecificOutput keys"
  # The ask is intentionally STATELESS: this ask must add NO new marker, or a
  # fan-out's siblings slip through and a denial silences the rest of the session.
  # Counted as a delta, not an existence check — an unrelated warm session in the
  # same TMPDIR may legitimately have left one already.
  [ "$(markers_in "$td")" -eq "${MARKERS_BEFORE:-0}" ] \
    || note "$label: asking created a verified marker (would suppress later asks)"
  ok
}

assert_quiet() { # assert_quiet <label>
  local label="$1"
  assert_universal "$label"
  # measured in BYTES, not "$OUT is empty": catches a deny/allow mutant and also
  # a whitespace-only emission that command substitution would have hidden.
  [ "${OUTBYTES:-0}" -eq 0 ] || { note "$label: expected 0 bytes on stdout, got $OUTBYTES"; return; }
  ok
}

case_dir() { local d="$ROOT/$1"; mkdir -p "$d"; printf '%s' "$d"; }

# --- RED baseline: dispatch with the delegation owner never invoked -> ask ----
for tool in Task Agent; do
  td=$(case_dir "cold-$tool"); mk_transcript "$td/t.jsonl" cold
  run "$td" "$tool" "$td/t.jsonl" "s-$tool"
  assert_ask "cold dispatch via $tool" "$td"
done

# --- GREEN: owner already invoked this session -> silent -------------------
td=$(case_dir warm); mk_transcript "$td/t.jsonl" warm
run "$td" Task "$td/t.jsonl" s-warm
assert_quiet "owner already invoked"

# --- a cold session keeps asking: nothing about the ASK is cached ----------
# Caching "already asked" inverted the gate twice (fan-out siblings sailed
# through; a denial silenced the rest of the session), so every cold dispatch
# must ask. Loading the owner is the only thing that stops the prompting.
td=$(case_dir repeat); mk_transcript "$td/t.jsonl" cold
for n in 1 2 3; do
  run "$td" Task "$td/t.jsonl" s-rep
  assert_ask "cold dispatch #$n in the same session" "$td"
done

# --- fan-out: every concurrent sibling is gated, not just the first --------
# Each sibling captures into its OWN directory. Sharing one .stdout across the
# five subprocesses made the observation itself racy: a regression that cached
# the ask would let one process ask and four exit quietly, yet all five reads
# could pick up the single ask and report a false 5/5.
td=$(case_dir fanout); mk_transcript "$td/t.jsonl" cold
for i in 1 2 3 4 5; do
  mkdir -p "$td/w$i"
  # ONE shared transcript path and one session id, as in a real fan-out: the
  # cache key includes transcript_path, so giving each worker its own copy would
  # hand them five different keys and a cached-ask regression would still show
  # 5/5. Only the capture files are per-worker.
  ( jq -nc --arg p "$td/t.jsonl" '{tool_name:"Task",transcript_path:$p,session_id:"s-fan",cwd:"/tmp"}' \
      | TMPDIR="$td" bash "$HOOK" > "$td/w$i/out" 2>"$td/w$i/err" ) &
done
wait
asked=0
for i in 1 2 3 4 5; do
  [ "$(jq -r '.hookSpecificOutput.permissionDecision // empty' < "$td/w$i/out" 2>/dev/null)" = ask ] \
    && asked=$((asked+1))
  [ -s "$td/w$i/err" ] && note "fan-out worker $i wrote to stderr"
done
[ "$asked" -eq 5 ] || note "fan-out: only $asked/5 concurrent dispatches were gated"
[ "$asked" -eq 5 ] && ok

# --- the verified-loaded state IS cached, and only that state --------------
td=$(case_dir verified); mk_transcript "$td/t.jsonl" warm
run "$td" Task "$td/t.jsonl" s-ver
assert_quiet "warm dispatch stays quiet"
ls "$td" 2>/dev/null | grep -q '^delegation-owner-loaded-' \
  && ok || note "warm dispatch did not record the verified marker"
# with the marker present the transcript is not needed at all
run "$td" Task "$td/gone.jsonl" s-ver
assert_quiet "verified session skips the transcript scan"

# --- only a real Skill tool-use event counts (spoof resistance) ------------
# Each spoof carries the skill NAME in a non-invocation position. The last two
# also carry the literal "skill": key, so they fail a match that checks only the
# skill value and not the enclosing Skill tool-use event.
spoof_line() {
  case "$1" in
    prose)  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"Launching skill: ccl-skills:multi-agent-delegation"}]}}' ;;
    quoted) printf '%s\n' '{"type":"user","message":{"content":[{"type":"text","text":"run {\"skill\":\"ccl-skills:multi-agent-delegation\"} for me"}]}}' ;;
    other)  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"skill":"ccl-skills:multi-agent-delegation"}}]}}' ;;
    # a user-authored event shaped exactly like an invocation: matches any
    # fragment regex, but the agent never invoked anything
    userside) printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"ccl-skills:multi-agent-delegation"}}]}}' ;;
    # a real invocation of a DIFFERENT tool carrying a nested look-alike node
    nested) printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"example":{"name":"Skill","input":{"skill":"ccl-skills:multi-agent-delegation"}}}}]}}' ;;
  esac
}
# A Skill REQUEST with no matching result is not a load: one turn can emit the
# Skill call and several dispatches together, and the call may still be pending,
# denied, or failed when the hook runs.
td=$(case_dir requested); mk_transcript "$td/t.jsonl" requested
run "$td" Task "$td/t.jsonl" s-req
assert_ask "Skill requested but never completed" "$td"

# A result belonging to a DIFFERENT call must not vouch for this one.
td=$(case_dir mismatch); mk_transcript "$td/t.jsonl" requested
printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_unrelated","content":"Launching skill: ccl-skills:multi-agent-delegation"}]}}' >> "$td/t.jsonl"
run "$td" Task "$td/t.jsonl" s-mis
assert_ask "unrelated tool_result does not complete the load" "$td"

# The canonical ccl-scoped id is required; a bare basename could be another
# locally installed skill.
td=$(case_dir bare)
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_b","name":"Skill","input":{"skill":"multi-agent-delegation"}}]}}' > "$td/t.jsonl"
printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_b","content":"Launching skill: multi-agent-delegation"}]}}' >> "$td/t.jsonl"
run "$td" Task "$td/t.jsonl" s-bare
assert_ask "bare skill basename is not the CCL owner" "$td"

for s in prose quoted other userside nested; do
  td=$(case_dir "spoof-$s"); mk_transcript "$td/t.jsonl" cold
  spoof_line "$s" >> "$td/t.jsonl"
  run "$td" Task "$td/t.jsonl" "s-spoof-$s"
  assert_ask "spoof/$s is not a Skill invocation" "$td"
done

# --- one session must never vouch for another via a colliding cache key ----
# `team/a` and `teama` sanitize to the same string, so a key built from the
# sanitized id alone would let the warm session silence the cold one.
td=$(case_dir collide)
mk_transcript "$td/warm.jsonl" warm
mk_transcript "$td/cold.jsonl" cold
run "$td" Task "$td/warm.jsonl" 'teama'
assert_quiet "colliding-key: warm session is quiet"
run "$td" Task "$td/cold.jsonl" 'team/a'
assert_ask "colliding-key: cold session still asks" "$td"

# --- a session with no usable id gets no shared cache bucket ---------------
td=$(case_dir nosession); mk_transcript "$td/t.jsonl" warm
run "$td" Task "$td/t.jsonl" ''
assert_quiet "warm dispatch without session_id"
ls "$td" 2>/dev/null | grep -q '^delegation-owner-loaded-' \
  && note "an id-less session wrote a shared cache marker" || ok

# --- non-dispatch tools never fire -----------------------------------------
for tool in Edit Bash Read; do
  td=$(case_dir "tool-$tool"); mk_transcript "$td/t.jsonl" cold
  run "$td" "$tool" "$td/t.jsonl" "s-$tool"
  assert_quiet "non-dispatch tool $tool"
done

# --- fail-open: absent, unreadable, or non-regular transcript --------------
td=$(case_dir missing); mk_transcript "$td/t.jsonl" cold
run "$td" Task "$td/nope.jsonl" s-miss
assert_quiet "missing transcript"
run "$td" Task "" s-empty
assert_quiet "empty transcript path"

# a FIFO must not hang the hook. Needs both mkfifo and a timeout command; on a
# platform lacking either, skip rather than fail on a missing tool (finding: an
# unguarded `timeout` exits 127 and would read as a hook defect).
td=$(case_dir fifo)
TIMEOUT_BIN=""
for c in timeout gtimeout; do command -v "$c" >/dev/null 2>&1 && { TIMEOUT_BIN="$c"; break; }; done
if [ -n "$TIMEOUT_BIN" ] && mkfifo "$td/pipe" 2>/dev/null; then
  jq -nc --arg p "$td/pipe" '{tool_name:"Task",transcript_path:$p,session_id:"s-fifo",cwd:"/tmp"}' \
        | TMPDIR="$td" "$TIMEOUT_BIN" 5 bash "$HOOK" >"$td/.stdout" 2>"$td/.stderr"
  RC=$?
  OUT=$(cat "$td/.stdout" 2>/dev/null); ERR=$(cat "$td/.stderr" 2>/dev/null)
  OUTBYTES=$(wc -c < "$td/.stdout" 2>/dev/null | tr -d ' ')
  ERRBYTES=$(wc -c < "$td/.stderr" 2>/dev/null | tr -d ' ')
  if [ "$RC" -eq 124 ]; then
    note "FIFO transcript hung the hook until timeout"
  else
    assert_quiet "FIFO transcript is not read"
  fi
else
  ok  # no mkfifo or no timeout command on this platform: nothing to assert
fi

# an unreadable regular file must fail open, not error
td=$(case_dir unreadable); mk_transcript "$td/t.jsonl" cold
if chmod 000 "$td/t.jsonl" 2>/dev/null && [ ! -r "$td/t.jsonl" ]; then
  run "$td" Task "$td/t.jsonl" s-unread
  assert_quiet "unreadable transcript fails open"
  chmod 644 "$td/t.jsonl" 2>/dev/null
else
  chmod 644 "$td/t.jsonl" 2>/dev/null
  ok  # running as root or on a permissionless filesystem: not assertable
fi

# Without jq the hook must degrade to silence, never to a decision or an error.
# The PATH must still carry a shell and coreutils — emptying it hides `bash` and
# `cat` too, which tests the harness rather than the hook.
td=$(case_dir nojq); mk_transcript "$td/t.jsonl" cold
jq -nc --arg p "$td/t.jsonl" '{tool_name:"Task",transcript_path:$p,session_id:"s-nojq",cwd:"/tmp"}' > "$td/in.json"
BASE_PATH="/usr/bin:/bin:/usr/sbin:/sbin"
BASH_ABS=$(command -v bash)
if [ -x "$BASH_ABS" ] && ! PATH="$BASE_PATH" command -v jq >/dev/null 2>&1 \
   && PATH="$BASE_PATH" command -v cat >/dev/null 2>&1; then
  PATH="$BASE_PATH" TMPDIR="$td" "$BASH_ABS" "$HOOK" < "$td/in.json" >"$td/.stdout" 2>"$td/.stderr"
  RC=$?
  OUT=$(cat "$td/.stdout" 2>/dev/null); ERR=$(cat "$td/.stderr" 2>/dev/null)
  OUTBYTES=$(wc -c < "$td/.stdout" 2>/dev/null | tr -d ' ')
  ERRBYTES=$(wc -c < "$td/.stderr" 2>/dev/null | tr -d ' ')
  assert_quiet "no jq on PATH degrades to silence"
else
  ok  # jq lives in a system dir here, so it cannot be hidden without hiding coreutils
fi

# --- malformed stdin must not emit a decision ------------------------------
td=$(case_dir badstdin)
printf 'not json' | TMPDIR="$td" bash "$HOOK" >"$td/.stdout" 2>"$td/.stderr"; RC=$?
OUT=$(cat "$td/.stdout" 2>/dev/null); ERR=$(cat "$td/.stderr" 2>/dev/null)
OUTBYTES=$(wc -c < "$td/.stdout" 2>/dev/null | tr -d ' ')
ERRBYTES=$(wc -c < "$td/.stderr" 2>/dev/null | tr -d ' ')
assert_quiet "malformed stdin"

# --- hostile session_id stays inside TMPDIR --------------------------------
td=$(case_dir hostile); mk_transcript "$td/t.jsonl" cold
run "$td" Task "$td/t.jsonl" '../../escape'
assert_ask "hostile session_id still asks" "$td"
if [ -e "$ROOT/escape" ] || [ -e "$td/../escape" ]; then
  note "marker escaped TMPDIR"
else
  ok
fi

# --- the reason must never carry transcript content ------------------------
td=$(case_dir leak); mk_transcript "$td/t.jsonl" cold
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"SENTINEL-SECRET-VALUE"}]}}' >> "$td/t.jsonl"
run "$td" Task "$td/t.jsonl" s-leak
assert_ask "cold dispatch with secret in transcript" "$td"
if printf '%s%s' "$OUT" "$ERR" | grep -q 'SENTINEL-SECRET-VALUE'; then
  note "transcript content leaked into hook output"
else
  ok
fi

printf 'guard_delegation_owner: pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
echo "guard_delegation_owner_ok"
