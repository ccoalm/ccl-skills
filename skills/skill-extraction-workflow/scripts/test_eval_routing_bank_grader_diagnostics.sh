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

# A second skill keeps the outcome space larger than {expected, none}, so
# acceptable[] fixtures below stay non-vacuous under the anti-gaming rule.
mkdir -p "$REPO/skills/tighten-doc"
cat > "$REPO/skills/tighten-doc/SKILL.md" <<'EOF'
---
description: Use when polishing document wording.
---
# Tighten Doc
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

# --- negative-control sentinel + failure-mode labels -------------------------
# expected_skill "none" is an outcome, not a catalog entry: a grader that picks a
# real skill for such a row must FAIL the task and label it "absorbed", and its
# clarify flag must be counted as a first-class metric.
none_bank="$TMP/bank-none.jsonl"
cat > "$none_bank" <<'EOF'
{"id":"neg-probe","utterance":"帮我写封邮件","expected_skill":"none","frozen_at_sha":""}
EOF
none_json="$TMP/report-none.json"
cat > "$FAKE_BIN/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"selected_skill": "testing-strategy", "clarify": true, "confidence": 0.4, "rationale_short": "nearest neighbor"}'
EOF
chmod +x "$FAKE_BIN/claude"
set +e
none_out="$(PATH="$FAKE_BIN:$PATH" ruby "$EVAL_SCRIPT" "$REPO" --bank "$none_bank" --json "$none_json" --timeout 60 2>&1)"
none_rc=$?
set -e
[ "$none_rc" = 0 ] || fail "sentinel run should complete advisory rc=0, got rc=$none_rc; out=$none_out"
none_status="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).dig("results", 0, "status")' "$none_json")"
[ "$none_status" = "FAIL" ] || fail "a skill claiming an expected-none row must FAIL, got: $none_status"
none_labels="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).dig("results", 0, "labels").join(",")' "$none_json")"
assert_contains "absorbed" "$none_labels" "expected-none row claimed by a skill must carry the absorbed label"
none_clarify="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0]))["clarify_count"]' "$none_json")"
[ "$none_clarify" = 1 ] || fail "clarify flag must be counted (expected clarify_count=1, got $none_clarify)"
none_lowconf="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0]))["low_confidence_count"]' "$none_json")"
[ "$none_lowconf" = 1 ] || fail "confidence 0.4 must count as low-confidence (<0.5), got $none_lowconf"
# And the honest direction: a grader answering "none" on the same row must PASS.
cat > "$FAKE_BIN/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"selected_skill": "none", "clarify": false, "confidence": 0.9, "rationale_short": "out of catalog"}'
EOF
chmod +x "$FAKE_BIN/claude"
set +e
none2_out="$(PATH="$FAKE_BIN:$PATH" ruby "$EVAL_SCRIPT" "$REPO" --bank "$none_bank" --json "$none_json" --timeout 60 2>&1)"
set -e
none2_status="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).dig("results", 0, "status")' "$none_json")"
[ "$none2_status" = "PASS" ] || fail "a none verdict on an expected-none row must PASS, got: $none2_status; out=$none2_out"

# --- replicas: conservative consensus, ownership_split, agreement metric ------
split_bank="$TMP/bank-split.jsonl"
cat > "$split_bank" <<'EOF'
{"id":"split-probe","utterance":"补一个回归测试","expected_skill":"testing-strategy","frozen_at_sha":""}
EOF
split_json="$TMP/report-split.json"
rm -f "$GRADER_PID_FILE.calls"
cat > "$FAKE_BIN/claude" <<'EOF'
#!/usr/bin/env bash
if [ -f "$GRADER_PID_FILE.calls" ]; then
  printf '%s\n' '{"selected_skill": "none", "clarify": false, "confidence": 0.6, "rationale_short": "second replica disagrees"}'
else
  : > "$GRADER_PID_FILE.calls"
  printf '%s\n' '{"selected_skill": "testing-strategy", "clarify": false, "confidence": 0.9, "rationale_short": "first replica"}'
fi
EOF
chmod +x "$FAKE_BIN/claude"
set +e
split_out="$(PATH="$FAKE_BIN:$PATH" ruby "$EVAL_SCRIPT" "$REPO" --bank "$split_bank" --replicas 2 --json "$split_json" --timeout 60 2>&1)"
split_rc=$?
set -e
[ "$split_rc" = 0 ] || fail "replica run should complete advisory rc=0, got rc=$split_rc; out=$split_out"
split_status="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).dig("results", 0, "status")' "$split_json")"
[ "$split_status" = "FAIL" ] || fail "one failing replica must fail the task (conservative consensus), got: $split_status"
split_labels="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).dig("results", 0, "labels").join(",")' "$split_json")"
assert_contains "ownership_split" "$split_labels" "disagreeing replicas must carry the ownership_split label"
split_agree="$(ruby -rjson -e 'r=JSON.parse(File.read(ARGV[0]))["replica_agreement"]; print "#{r["agree"]}/#{r["measured"]}"' "$split_json")"
[ "$split_agree" = "0/1" ] || fail "expected replica_agreement 0/1, got: $split_agree"
split_verdicts="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).dig("results", 0, "verdicts").length' "$split_json")"
[ "$split_verdicts" = 2 ] || fail "expected 2 recorded verdicts, got: $split_verdicts"

# --- replicas: a PASS+ERROR pair is PARTIALLY measured, never a clean PASS ----
# Task-level consensus sees only observed verdicts, so without replica-level
# error accounting a failed replica would vanish (zero grader-errors reported).
partial_bank="$TMP/bank-partial.jsonl"
cat > "$partial_bank" <<'EOF'
{"id":"partial-probe","utterance":"补一个回归测试","expected_skill":"testing-strategy","frozen_at_sha":""}
EOF
partial_json="$TMP/report-partial.json"
rm -f "$GRADER_PID_FILE.partial"
cat > "$FAKE_BIN/claude" <<'EOF'
#!/usr/bin/env bash
if [ -f "$GRADER_PID_FILE.partial" ]; then
  printf 'grader exploded\n' >&2
  exit 1
fi
: > "$GRADER_PID_FILE.partial"
printf '%s\n' '{"selected_skill": "testing-strategy", "clarify": false, "confidence": 0.9, "rationale_short": "first replica ok"}'
EOF
chmod +x "$FAKE_BIN/claude"
set +e
partial_out="$(PATH="$FAKE_BIN:$PATH" ruby "$EVAL_SCRIPT" "$REPO" --bank "$partial_bank" --replicas 2 --json "$partial_json" --timeout 60 2>&1)"
partial_rc=$?
set -e
[ "$partial_rc" = 0 ] || fail "partial-error run should complete advisory rc=0, got rc=$partial_rc; out=$partial_out"
partial_status="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).dig("results", 0, "status")' "$partial_json")"
[ "$partial_status" = "PASS" ] || fail "consensus over observed verdicts should stay PASS, got: $partial_status"
partial_labels="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).dig("results", 0, "labels").join(",")' "$partial_json")"
assert_contains "partial_error" "$partial_labels" "a PASS+ERROR pair must carry the partial_error label"
partial_ev="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0]))["error_verdicts"]' "$partial_json")"
[ "$partial_ev" = 1 ] || fail "replica-level errors must be counted (expected error_verdicts=1, got $partial_ev)"
assert_contains "grader-error verdicts: 1" "$partial_out" "partial errors must be surfaced in human output"

# --- acceptable[]: a defensible alternate outcome passes, and is marked -------
acc_bank="$TMP/bank-acc.jsonl"
cat > "$acc_bank" <<'EOF'
{"id":"acc-probe","utterance":"用 COBOL 写个批处理","expected_skill":"testing-strategy","acceptable":["none"],"frozen_at_sha":""}
EOF
acc_json="$TMP/report-acc.json"
cat > "$FAKE_BIN/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"selected_skill": "none", "clarify": false, "confidence": 0.8, "rationale_short": "alternate outcome"}'
EOF
chmod +x "$FAKE_BIN/claude"
set +e
acc_out="$(PATH="$FAKE_BIN:$PATH" ruby "$EVAL_SCRIPT" "$REPO" --bank "$acc_bank" --json "$acc_json" --timeout 60 2>&1)"
acc_rc=$?
set -e
[ "$acc_rc" = 0 ] || fail "acceptable run should complete advisory rc=0, got rc=$acc_rc; out=$acc_out"
acc_status="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).dig("results", 0, "status")' "$acc_json")"
[ "$acc_status" = "PASS" ] || fail "a selection inside acceptable[] must PASS, got: $acc_status"
acc_hit="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).dig("results", 0, "acceptable_hit")' "$acc_json")"
[ "$acc_hit" = "true" ] || fail "acceptable_hit must be recorded, got: $acc_hit"

# --- baseline ruler guard: mismatched bank or replicas suppresses the diff ----
# The docs declare reports from different (bank, replicas) configurations
# non-comparable; the runner must enforce that, or a stale baseline emits false
# newly_failed/newly_passed regressions.
ruler_bank="$TMP/bank-ruler.jsonl"
cat > "$ruler_bank" <<'EOF'
{"id":"ruler-probe","utterance":"补一个回归测试","expected_skill":"testing-strategy","frozen_at_sha":""}
EOF
cat > "$FAKE_BIN/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"selected_skill": "none", "clarify": false, "confidence": 0.9, "rationale_short": "fails vs expected"}'
EOF
chmod +x "$FAKE_BIN/claude"
ruler_now="$TMP/report-ruler-now.json"
set +e
PATH="$FAKE_BIN:$PATH" ruby "$EVAL_SCRIPT" "$REPO" --bank "$ruler_bank" --json "$ruler_now" --timeout 60 >/dev/null 2>&1
set -e
[ -f "$ruler_now" ] || fail "expected current-ruler report to be written"
# Baseline A: same shape but a different bank fingerprint, task previously PASS.
ruler_base_bank="$TMP/report-ruler-base-bank.json"
ruby -rjson -e '
r = JSON.parse(File.read(ARGV[0]))
r["routing_surface"]["bank_sha256"] = "0" * 64
r["results"][0]["status"] = "PASS"
File.write(ARGV[1], JSON.generate(r))
' "$ruler_now" "$ruler_base_bank"
mismatch_json="$TMP/report-ruler-mismatch.json"
set +e
mismatch_out="$(PATH="$FAKE_BIN:$PATH" ruby "$EVAL_SCRIPT" "$REPO" --bank "$ruler_bank" --baseline "$ruler_base_bank" --json "$mismatch_json" --timeout 60 2>&1)"
set -e
assert_contains "baseline not compared" "$mismatch_out" "a bank-fingerprint mismatch must suppress the baseline diff"
mm_nf="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0]))["newly_failed"].length' "$mismatch_json")"
[ "$mm_nf" = 0 ] || fail "newly_failed must be empty under a mismatched-bank baseline, got $mm_nf entries"
mm_cmp="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0]))["baseline_comparable"].inspect' "$mismatch_json")"
[ "$mm_cmp" = "false" ] || fail "baseline_comparable must be false for a bank mismatch, got: $mm_cmp"
# Baseline B: same bank fingerprint but a different replica count.
ruler_base_rep="$TMP/report-ruler-base-rep.json"
ruby -rjson -e '
r = JSON.parse(File.read(ARGV[0]))
r["replicas"] = 2
r["results"][0]["status"] = "PASS"
File.write(ARGV[1], JSON.generate(r))
' "$ruler_now" "$ruler_base_rep"
set +e
repmm_out="$(PATH="$FAKE_BIN:$PATH" ruby "$EVAL_SCRIPT" "$REPO" --bank "$ruler_bank" --baseline "$ruler_base_rep" --json "$mismatch_json" --timeout 60 2>&1)"
set -e
assert_contains "replica count differs" "$repmm_out" "a replica-count mismatch must suppress the baseline diff"
# Control: an identical-ruler baseline still produces the diff.
ruler_base_ok="$TMP/report-ruler-base-ok.json"
ruby -rjson -e '
r = JSON.parse(File.read(ARGV[0]))
r["results"][0]["status"] = "PASS"
File.write(ARGV[1], JSON.generate(r))
' "$ruler_now" "$ruler_base_ok"
set +e
okdiff_out="$(PATH="$FAKE_BIN:$PATH" ruby "$EVAL_SCRIPT" "$REPO" --bank "$ruler_bank" --baseline "$ruler_base_ok" --json "$mismatch_json" --timeout 60 2>&1)"
set -e
assert_contains "newly_failed=ruler-probe" "$okdiff_out" "an identical-ruler baseline must still yield the regression diff"

# --- schema strictness: vacuous rows and non-list fields are usage errors ----
vac_bank="$TMP/bank-vacuous.jsonl"
cat > "$vac_bank" <<'EOF'
{"id":"vac-probe","utterance":"x","expected_skill":"testing-strategy","acceptable":["tighten-doc","none"],"frozen_at_sha":""}
EOF
set +e
vac_out="$(ruby "$EVAL_SCRIPT" "$REPO" --bank "$vac_bank" --dry-run 2>&1)"
vac_rc=$?
set -e
[ "$vac_rc" = 2 ] || fail "a row covering the whole outcome space must be a usage error (rc=2), got rc=$vac_rc; out=$vac_out"
assert_contains "vacuous row" "$vac_out" "vacuous-row rejection should name the failure"

badtype_bank="$TMP/bank-badtype.jsonl"
cat > "$badtype_bank" <<'EOF'
{"id":"badtype-probe","utterance":"x","expected_skill":"testing-strategy","must_not_route_to":1,"frozen_at_sha":""}
EOF
set +e
badtype_out="$(ruby "$EVAL_SCRIPT" "$REPO" --bank "$badtype_bank" --dry-run 2>&1)"
badtype_rc=$?
set -e
[ "$badtype_rc" = 2 ] || fail "a non-list must_not_route_to must be a usage error (rc=2), got rc=$badtype_rc; out=$badtype_out"
assert_contains "must_not_route_to must be a list" "$badtype_out" "non-list field must produce the documented diagnostic, not a stack trace"

# --- --replicas argument strictness ------------------------------------------
set +e
rep_out="$(ruby "$EVAL_SCRIPT" "$REPO" --replicas 0 2>&1)"
rep_rc=$?
set -e
[ "$rep_rc" = 2 ] || fail "--replicas 0 must be a usage error (rc=2), got rc=$rep_rc; out=$rep_out"

echo "test_eval_routing_bank_grader_diagnostics: ok"
