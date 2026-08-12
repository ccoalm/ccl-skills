#!/usr/bin/env bash
# Regression test for eval-routing-bank grader failure diagnostics. Uses a fake
# claude earlier in PATH so this never invokes a real Claude CLI or account.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
EVAL_SCRIPT="$SCRIPT_DIR/eval-routing-bank.rb"
[ -f "$EVAL_SCRIPT" ] || { echo "FAIL: eval script not found: $EVAL_SCRIPT" >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/eval-routing-bank-diagnostics.XXXXXX")"
GRADER_PID_FILE="$TMP/grader.pid"
export GRADER_PID_FILE
cleanup() {
  stray="$(cat "$GRADER_PID_FILE" 2>/dev/null || true)"
  [ -z "$stray" ] || kill -KILL "$stray" 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_contains() { case "$2" in *"$1"*) : ;; *) fail "expected output to contain: $1${3:+ ($3)}";; esac; }

REPO="$TMP/repo"
FAKE_BIN="$TMP/bin"
mkdir -p "$REPO/skills/testing-strategy" "$REPO/eval" "$FAKE_BIN"

git -C "$TMP" init -q repo
git -C "$REPO" config user.email test@example.invalid
git -C "$REPO" config user.name "Test User"

cat > "$REPO/skills/testing-strategy/SKILL.md" <<'EOF'
---
description: Use when choosing test layers and regression evidence.
---
# Testing Strategy
EOF

cat > "$REPO/eval/routing-tasks.jsonl" <<'EOF'
{"id":"fake-claude-auth","utterance":"补一个回归测试","expected_skill":"testing-strategy","frozen_at_sha":""}
EOF

git -C "$REPO" add -A
git -C "$REPO" commit -qm "fixture"

cat > "$FAKE_BIN/claude" <<'EOF'
#!/usr/bin/env bash
printf 'Not logged in · Please run /login\n'
exit 1
EOF
chmod +x "$FAKE_BIN/claude"

json_path="$TMP/report.json"
# Deliberately generous timeout: this case exercises the grader-EXIT diagnostic,
# not the timeout guard. A tight bound here only buys a load-sensitive red — the
# fake grader exits immediately, so the guard has nothing to bound.
set +e
out="$(PATH="$FAKE_BIN:$PATH" ruby "$EVAL_SCRIPT" "$REPO" --json "$json_path" --timeout 60 2>&1)"
rc=$?
set -e

[ "$rc" = 3 ] || fail "expected all-grader-errors rc=3, got rc=$rc; output: $out"
assert_contains "Not logged in" "$out" "stdout diagnostic should appear in human output"
[ -f "$json_path" ] || fail "expected JSON report to be written"
json="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).dig("results", 0, "error")' "$json_path")"
assert_contains "Not logged in" "$json" "stdout diagnostic should appear in JSON error field"

# A grader that outlives the hard timeout must be reported as a grader error, not
# crash the eval. The guard closes the reader pipes to unblock them; a reader that
# dies of that close gets re-raised by join and aborts the run (exit 1, no report).
# The guard also has to BOUND the run and terminate the grader: a run that merely
# reports the timeout after waiting out the grader would satisfy the diagnostics
# below while the hang the guard exists to prevent still happened. The fake sleeps
# far longer than the assertions allow, so "waited it out" cannot read as green.
timeout_json="$TMP/report-timeout.json"
timeout_log="$TMP/report-timeout.log"
cat > "$FAKE_BIN/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$$" >"$GRADER_PID_FILE"
exec sleep 300
EOF
chmod +x "$FAKE_BIN/claude"

timeout_started_at="$(date +%s)"
set +e
PATH="$FAKE_BIN:$PATH" ruby "$EVAL_SCRIPT" "$REPO" --json "$timeout_json" --timeout 1 >"$timeout_log" 2>&1 &
eval_pid=$!
# Independent watchdog: without it an unbounded guard would park this test for the
# grader's whole lifetime instead of failing.
eval_deadline="$(( timeout_started_at + 60 ))"
eval_watchdog_fired=0
while kill -0 "$eval_pid" 2>/dev/null; do
  if [ "$(date +%s)" -ge "$eval_deadline" ]; then
    eval_watchdog_fired=1
    kill -KILL "$eval_pid" 2>/dev/null || true
    break
  fi
  sleep 1
done
wait "$eval_pid"
timeout_rc=$?
set -e
timeout_out="$(cat "$timeout_log" 2>/dev/null || true)"
timeout_elapsed="$(( $(date +%s) - timeout_started_at ))"

[ "$eval_watchdog_fired" = 0 ] || fail "a 1s grader timeout must bound the run; it was still going after ${timeout_elapsed}s (grader sleeps 300s); output: $timeout_out"
[ "$timeout_rc" = 3 ] || fail "expected timed-out grader to report rc=3, got rc=$timeout_rc; output: $timeout_out"

# The grader itself must be terminated, not merely abandoned mid-sleep.
grader_pid="$(cat "$GRADER_PID_FILE" 2>/dev/null || true)"
[ -n "$grader_pid" ] || fail "fixture did not record the grader pid; the termination assertion below would be vacuous"
grader_gone=0
grader_wait_deadline="$(( $(date +%s) + 10 ))"
while :; do
  if ! kill -0 "$grader_pid" 2>/dev/null; then grader_gone=1; break; fi
  case "$(ps -o stat= -p "$grader_pid" 2>/dev/null || true)" in
    *Z*) grader_gone=1; break ;;
  esac
  [ "$(date +%s)" -ge "$grader_wait_deadline" ] && break
  sleep 1
done
[ "$grader_gone" = 1 ] || fail "a timed-out grader must be terminated, not left running (pid=$grader_pid)"
case "$timeout_out" in
  *"terminated with exception"*|*"stream closed in another thread"*)
    fail "grader timeout must not surface a reader-thread crash; output: $timeout_out" ;;
esac
assert_contains "grader_timeout_1s" "$timeout_out" "timeout diagnostic should appear in human output"
[ -f "$timeout_json" ] || fail "expected JSON report to be written for a timed-out grader"
timeout_error="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).dig("results", 0, "error")' "$timeout_json")"
[ "$timeout_error" = "grader_timeout_1s" ] || fail "expected JSON error grader_timeout_1s, got: $timeout_error"

# Malformed grader output is re-asked, never interpreted. A response whose
# rationale carries an unescaped quote is invalid JSON; the parser refuses it and
# the task is retried, so a one-off formatting slip still produces a measured
# observation without anything reading a verdict out of broken text.
retry_json="$TMP/report-retry-parse.json"
cat > "$FAKE_BIN/claude" <<'EOF'
#!/usr/bin/env bash
if [ -f "$GRADER_PID_FILE.parsed" ]; then
  printf '%s\n' '{"selected_skill": "testing-strategy", "confidence": 0.9, "rationale_short": "second call"}'
  exit 0
fi
: > "$GRADER_PID_FILE.parsed"
printf '%s\n' '{"selected_skill": "testing-strategy", "confidence": 0.95, "rationale_short": "局部重构（"某文件"）"}'
EOF
chmod +x "$FAKE_BIN/claude"
rm -f "$GRADER_PID_FILE.parsed"
set +e
retry_out="$(PATH="$FAKE_BIN:$PATH" ruby "$EVAL_SCRIPT" "$REPO" --json "$retry_json" --timeout 60 2>&1)"
retry_rc=$?
set -e
[ "$retry_rc" = 0 ] || fail "one unparseable response must be retried, not recorded as unmeasured; rc=$retry_rc out=$retry_out"
retry_status="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).dig("results", 0, "status")' "$retry_json")"
[ "$retry_status" = "PASS" ] || fail "expected the retried task to be graded, got: $retry_status"

# Output that stays malformed must stay UNMEASURED. These are the shapes a repair
# path would have read as a verdict: field-shaped prose that merely ends in a
# brace, and an object cut off mid-string. Neither may ever become an observation.
for shape in prose truncated; do
  bad_json="$TMP/report-bad-$shape.json"
  case "$shape" in
    prose)     payload='grader note: "selected_skill": "testing-strategy" }' ;;
    truncated) payload='{"selected_skill": "testing-strategy", "confidence": 0.9, "rationale_short": "cut off mid' ;;
  esac
  printf '#!/usr/bin/env bash\nprintf %%s %s\n' "'$payload'" > "$FAKE_BIN/claude"
  chmod +x "$FAKE_BIN/claude"
  set +e
  bad_out="$(PATH="$FAKE_BIN:$PATH" ruby "$EVAL_SCRIPT" "$REPO" --json "$bad_json" --timeout 60 2>&1)"
  bad_rc=$?
  set -e
  [ "$bad_rc" = 3 ] || fail "$shape output must stay unmeasured, not become a verdict; rc=$bad_rc out=$bad_out"
  bad_status="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).dig("results", 0, "status")' "$bad_json")"
  [ "$bad_status" = "ERROR" ] || fail "expected $shape output to stay ERROR, got: $bad_status"
done

# A grader that hangs twice still reports the timeout rather than a verdict.
twice_json="$TMP/report-timeout-twice.json"
cat > "$FAKE_BIN/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$$" >"$GRADER_PID_FILE"
exec sleep 300
EOF
chmod +x "$FAKE_BIN/claude"
set +e
twice_out="$(PATH="$FAKE_BIN:$PATH" ruby "$EVAL_SCRIPT" "$REPO" --json "$twice_json" --timeout 1 2>&1)"
twice_rc=$?
set -e
[ "$twice_rc" = 3 ] || fail "a grader that hangs on both attempts must stay unmeasured; rc=$twice_rc"
assert_contains "grader_timeout_1s" "$twice_out" "a doubly-timed-out task should still report the timeout"

echo "test_eval_routing_bank_grader_diagnostics: ok"
