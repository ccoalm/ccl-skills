#!/usr/bin/env bash
# Wrapper-level tests for opencode_review.sh's bounded format-repair retry,
# using a deterministic stub `opencode` binary. No live opencode needed.
#
# Covers:
#   - the wrapper performs structural debug-agent validation without a second
#     model invocation
#   - first reply unparseable prose -> ONE strict retry -> conforming reply passes
#   - retry also unparseable -> inconclusive/unparseable_findings, exactly 2 runs
#   - conforming first reply -> no retry (1 run)
#   - an exposed forbidden tool stops before inference
#   - eligibility gate: a first reply carrying findings-like content (severity
#     token, dotted path, root-file, or dot-prefixed locator) is NEVER retried
#     and stays inconclusive/unparseable_findings (laundering is structurally
#     impossible: nothing findings-like is ever replaced)
#   - findings produced by the retry are surfaced (status findings, exit 0)
#   - export failure (empty export args) still yields a structured verdict
#   - retry timeout still yields a structured inconclusive verdict
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
WRAPPER="$DIR/opencode_review.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/oc-retry-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
fails=0

command -v jq >/dev/null 2>&1 || { echo "FAIL - jq is required for opencode_review.sh and its tests"; exit 1; }
REAL_PYTHON_BIN="$(command -v python3)"
export REAL_PYTHON_BIN
REAL_TIMEOUT_BIN="$(command -v timeout)"
export REAL_TIMEOUT_BIN

mkdir -p "$WORK/bin" "$WORK/state" "$WORK/tmp" "$WORK/source-data/opencode"
printf '%s\n' '{"deepseek":{"type":"api","key":"test-only"}}' >"$WORK/source-data/opencode/auth.json"

cat >"$WORK/bin/timeout" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_STATE_DIR/timeout_args"
exec "$REAL_TIMEOUT_BIN" "$@"
STUB
chmod +x "$WORK/bin/timeout"

cat >"$WORK/bin/opencode" <<'STUB'
#!/usr/bin/env bash
# Deterministic opencode stub. Behavior is driven by $STUB_STATE_DIR:
#   review_mode: pass_first | pass_on_retry | never_pass | tool_exposed |
#                completed_session_timeout | completed_malformed_timeout |
#                idless_export_timeout | invalid_export_timeout |
#                native_stream_timeout | native_large_log_timeout |
#                native_slow_copy_timeout | legacy_stream_timeout |
#                pre_stream_timeout | provider_balance_exhausted |
#                provider_balance_then_server_error | provider_auth_then_server_error
set -u
STATE="$STUB_STATE_DIR"
MODE="$(cat "$STATE/review_mode")"
[ -z "${OPENCODE_PURE:-}" ] || touch "$STATE/pure_mode_forced"
if [ "$1" = "debug" ] && [ "${2:-}" = "agent" ]; then
  sleep "${STUB_BOUNDARY_DELAY_S:-0}"
  grep -q '^model:' .opencode/agent/ccl-review.md 2>/dev/null && touch "$STATE/agent_model_override"
  grep -q '^  "\*": deny$' .opencode/agent/ccl-review.md 2>/dev/null \
    && touch "$STATE/packet_only_permissions"
  grep -q '^    "testing-strategy": allow$' .opencode/agent/ccl-review.md 2>/dev/null \
    && touch "$STATE/selected_skill_only"
  model_full="$(cat "$STATE/resolved_model" 2>/dev/null || printf '%s' deepseek/deepseek-chat)"
  provider="${model_full%%/*}"
  model="${model_full#*/}"
  bash_enabled=false
  skill_enabled=false
  [ "$MODE" = "tool_exposed" ] && bash_enabled=true
  [ -e "$STATE/selected_skill_only" ] && skill_enabled=true
  printf '{"name":"ccl-review","mode":"primary","model":{"providerID":"%s","modelID":"%s"},"tools":{"invalid":true,"question":false,"bash":%s,"read":false,"glob":false,"grep":false,"edit":false,"write":false,"task":false,"webfetch":false,"todowrite":false,"skill":%s,"ccl_context":false}}\n' \
    "$provider" "$model" "$bash_enabled" "$skill_enabled"
  exit 0
fi
if [ "$1" = "run" ]; then
  review_dir=""
  prompt_file=""
  previous=""
  after_separator=no
  for arg in "$@"; do
    [ "$arg" = "--model" ] && touch "$STATE/cli_model_override"
    [ "$previous" = "--dir" ] && review_dir="$arg"
    [ "$previous" = "--file" ] && prompt_file="$arg"
    if [ "$after_separator" = consumed ]; then
      touch "$STATE/extra_positional_prompt"
    elif [ "$after_separator" = yes ]; then
      printf '%s' "$arg" >"$STATE/positional_prompt"
      after_separator=consumed
    elif [ "$arg" = "--" ]; then
      after_separator=yes
      touch "$STATE/option_separator"
    fi
    previous="$arg"
  done
  if [ -n "$prompt_file" ]; then
    prompt="$(cat "$prompt_file")"
    touch "$STATE/prompt_file_transport"
  else
    # Compatibility branch for detecting an accidental return to argv transport.
    for prompt in "$@"; do :; done
  fi
  [ ! -f "$review_dir/opencode.json" ] || cp "$review_dir/opencode.json" "$STATE/native-opencode.json"
  if compgen -G "$review_dir/agent-boundary.*" >/dev/null \
    || compgen -G "$review_dir/review-events.*" >/dev/null \
    || compgen -G "$review_dir/review-export.*" >/dev/null; then
    touch "$STATE/audit_files_visible"
  fi
  n=$(( $(cat "$STATE/review_runs" 2>/dev/null || echo 0) + 1 ))
  printf '%s' "$n" >"$STATE/review_runs"
  printf '%s\n' "$prompt" >"$STATE/review_prompt_$n"
  if [ "$MODE" = "interrupt_wait" ]; then
    touch "$STATE/interrupt_waiting"
    sleep 3
  fi
  if [ "$MODE" = "signal_exit" ]; then
    exit 143
  fi
  if [ "$MODE" = "provider_balance_exhausted" ]; then
    printf '%s\n' '{"type":"error","sessionID":"sid-review-billing","error":{"name":"APIError","data":{"message":"Insufficient Balance","statusCode":402,"isRetryable":false}}}'
    exit 1
  fi
  if [ "$MODE" = "provider_balance_then_server_error" ]; then
    printf '%s\n' \
      '{"type":"error","sessionID":"sid-review-billing","error":{"name":"APIError","data":{"message":"Insufficient Balance","statusCode":402,"isRetryable":false}}}' \
      '{"type":"error","sessionID":"sid-review-billing","error":{"name":"APIError","data":{"message":"upstream failed","statusCode":500,"isRetryable":true}}}'
    exit 1
  fi
  if [ "$MODE" = "provider_auth_then_server_error" ]; then
    printf '%s\n' \
      '{"type":"error","sessionID":"sid-review-auth","error":{"name":"APIError","data":{"message":"Unauthorized","statusCode":401,"isRetryable":false}}}' \
      '{"type":"error","sessionID":"sid-review-auth","error":{"name":"APIError","data":{"message":"upstream failed","statusCode":500,"isRetryable":true}}}'
    exit 1
  fi
  if [ "$MODE" = "retry_timeout" ] && [ "$n" -ge 2 ]; then
    sleep 8
  fi
  if [ "$MODE" = "pre_stream_timeout" ]; then
    sleep 8
  fi
  if [ "$MODE" = "invalid_stream_timeout" ]; then
    printf '%s\n' 'partial non-json transport output'
    sleep 8
  fi
  if [ "$MODE" = "session_only_timeout" ]; then
    printf '%s\n' "{\"type\":\"session_created\",\"sessionID\":\"sid-review-$n\"}"
    sleep 8
  fi
  if [ "$MODE" = "completed_session_timeout" ] \
    || [ "$MODE" = "completed_malformed_timeout" ] \
    || [ "$MODE" = "idless_export_timeout" ] \
    || [ "$MODE" = "invalid_export_timeout" ]; then
    printf '%s\n' "{\"type\":\"step_start\",\"sessionID\":\"sid-review-$n\",\"part\":{\"type\":\"step-start\"}}"
    printf '%s\n' "{\"type\":\"step_finish\",\"sessionID\":\"sid-review-$n\",\"part\":{\"type\":\"step-finish\",\"reason\":\"stop\"}}"
    sleep 8
  fi
  if [ "$MODE" = "legacy_stream_timeout" ]; then
    printf '%s\n' "{\"type\":\"step_start\",\"sessionID\":\"sid-review-$n\",\"part\":{\"type\":\"step-start\"}}"
    sleep 8
  fi
  if [ "$MODE" = "native_stream_timeout" ]; then
    mkdir -p "$XDG_DATA_HOME/opencode/log"
    printf '%s\n' 'native owner skill loaded; second model stream pending' \
      >"$XDG_DATA_HOME/opencode/log/reviewer.log"
    printf '%s\n' "{\"type\":\"step_start\",\"sessionID\":\"sid-review-$n\",\"part\":{\"type\":\"step-start\"}}"
    sleep 8
  fi
  if [ "$MODE" = "native_large_log_timeout" ]; then
    mkdir -p "$XDG_DATA_HOME/opencode/log"
    head -c 6000000 /dev/zero >"$XDG_DATA_HOME/opencode/log/oversized.log"
    printf '%s\n' "{\"type\":\"step_start\",\"sessionID\":\"sid-review-$n\",\"part\":{\"type\":\"step-start\"}}"
    sleep 8
  fi
  if [ "$MODE" = "native_slow_copy_timeout" ]; then
    mkdir -p "$XDG_DATA_HOME/opencode/log"
    printf '%s\n' 'copy interrupted sentinel' \
      >"$XDG_DATA_HOME/opencode/log/slow-copy.log"
    printf '%s\n' "{\"type\":\"step_start\",\"sessionID\":\"sid-review-$n\",\"part\":{\"type\":\"step-start\"}}"
    sleep 8
  fi
  if [ "$MODE" = "auth_refresh" ]; then
    printf '%s\n' '{"openai":{"type":"oauth","refresh":"rotated","access":"fresh","expires":9999999999999}}' \
      >"$XDG_DATA_HOME/opencode/auth.json"
  fi
  if [ "$MODE" = "no_session" ]; then
    printf '%s\n' '{"type":"step_start","part":{"type":"step-start"}}'
  else
    printf '%s\n' "{\"type\":\"step_start\",\"sessionID\":\"sid-review-$n\",\"part\":{\"type\":\"step-start\"}}"
  fi
  exit 0
fi
if [ "$1" = "export" ]; then
  sid="$2"
  MODE="$(cat "$STATE/review_mode")"
  [ "$MODE" = "export_fail" ] && exit 1
  [ "$MODE" = "export_timeout" ] && sleep 8
  if [ "$MODE" = "invalid_export_timeout" ]; then
    printf '%s\n' 'not-json'
    exit 0
  fi
  n="${sid#sid-review-}"
  MODEL_INFO='"info":{"role":"assistant","modelID":"deepseek-chat","providerID":"deepseek"}'
  [ "$MODE" = "missing_attribution" ] && MODEL_INFO='"info":{"role":"assistant"}'
  conforming='{"type":"text","text":"CHECK correctness | Independently checked correctness against the frozen candidate.\nNO_BLOCKING_FINDINGS"}'
  empty_text='{"type":"text","text":""}'
  prose='{"type":"text","text":"No issues found."}'
  prose_with_finding='{"type":"text","text":"I am worried this could be a serious problem around auth handling, roughly a P1: the null check near handlers/auth.code line 3 seems missing."}'
  finding_line='{"type":"text","text":"P1 handlers/auth.code:3 missing null check | add a guard before dereference"}'
  prose_with_high='{"type":"text","text":"The auth handling worries me and the exposure feels HIGH but I cannot phrase it in your format."}'
  prose_with_rootfile='{"type":"text","text":"I am uneasy about the build wiring change around Makefile:12 but cannot articulate it formally."}'
  prose_with_dotfile='{"type":"text","text":"Something in the pipeline change at .github/workflows/ci.yml:12 seems off but I cannot phrase it formally."}'
  prose_concern_only='{"type":"text","text":"This can silently discard the original reviewer concern and approve a broken change."}'
  prose_mixed='{"type":"text","text":"Overall this looks good, but it can silently discard the original reviewer concern."}'
  # A clean no-findings assertion padded with punctuation: the retry gate's
  # whole-reply anchor allows unlimited surrounding [[:space:][:punct:]], so a
  # reply of any size passes the gate and lands in the retry verdict.
  prose_padded="{\"type\":\"text\",\"text\":\"No issues found.$(awk 'BEGIN { for (i = 0; i < 2000; i++) printf "." }')\"}"
  # Long malformed prose carrying a locator: findings-like, so it is never
  # retried and lands on the terminal concern-evidence path with its full text.
  prose_long_concern="{\"type\":\"text\",\"text\":\"I cannot phrase this formally but handlers/auth.code:3 looks wrong. ZZPROSESENTINELZZ $(awk 'BEGIN { for (i = 0; i < 400; i++) printf "padding word " }')\"}"
  MODE="$(cat "$STATE/review_mode")"
  body="$prose"
  case "$MODE" in
    pass_first) body="$conforming";;
    completed_session_timeout) body="$conforming";;
    completed_malformed_timeout) body="$prose_with_finding";;
    auth_refresh) body="$conforming";;
    missing_attribution) body="$conforming";;
    missing_final) body="$empty_text";;
    unfinished_concern) body="$finding_line";;
    pass_on_retry|retry_timeout|export_fail) [ "$n" -ge 2 ] && body="$conforming";;
    never_pass) body="$prose";;
    launder) if [ "$n" -ge 2 ]; then body="$conforming"; else body="$prose_with_finding"; fi;;
    launder_high) if [ "$n" -ge 2 ]; then body="$conforming"; else body="$prose_with_high"; fi;;
    launder_rootfile) if [ "$n" -ge 2 ]; then body="$conforming"; else body="$prose_with_rootfile"; fi;;
    launder_dotfile) if [ "$n" -ge 2 ]; then body="$conforming"; else body="$prose_with_dotfile"; fi;;
    launder_semantic) if [ "$n" -ge 2 ]; then body="$conforming"; else body="$prose_concern_only"; fi;;
    launder_mixed) if [ "$n" -ge 2 ]; then body="$conforming"; else body="$prose_mixed"; fi;;
    findings_on_retry) [ "$n" -ge 2 ] && body="$finding_line";;
    padded_first) if [ "$n" -ge 2 ]; then body="$conforming"; else body="$prose_padded"; fi;;
    long_concern) body="$prose_long_concern";;
  esac
  finish_reason=stop
  [ "$MODE" = "unfinished_concern" ] && finish_reason=length
  case "$MODE" in
    retry_timeout)
      [ "$n" -lt 2 ] || finish_reason=tool-calls
      ;;
    session_only_timeout|legacy_stream_timeout|native_stream_timeout|native_large_log_timeout|native_slow_copy_timeout)
      finish_reason=tool-calls
      ;;
  esac
  if [ "$MODE" = "idless_export_timeout" ]; then
    printf '{"messages":[{%s,"parts":[%s,{"type":"step-finish","reason":"%s"}]}]}\n' "$MODEL_INFO" "$body" "$finish_reason"
  else
    printf '{"id":"%s","messages":[{%s,"parts":[%s,{"type":"step-finish","reason":"%s"}]}]}\n' "$sid" "$MODEL_INFO" "$body" "$finish_reason"
  fi
  exit 0
fi
exit 1
STUB
chmod +x "$WORK/bin/opencode"

cat >"$WORK/bin/cat" <<'STUB'
#!/usr/bin/env bash
[ "${FAIL_CAT_KIND:-}" = profile ] && [ "${1:-}" = "${TEST_PROFILE_PATH:-}" ] && exit 42
case "${FAIL_CAT_KIND:-}:${1:-}" in diff:"${TMPDIR:-/tmp}"/oc-diff.*) exit 42;; esac
exec /bin/cat "$@"
STUB
chmod +x "$WORK/bin/cat"

cat >"$WORK/bin/python3" <<'STUB'
#!/usr/bin/env bash
if [ "${FAIL_TIMEOUT_ENRICHMENT:-}" = 1 ] && [ "${1:-}" = - ]; then
  source_file="$(mktemp "${TMPDIR:-/tmp}/python-source.XXXXXX")" || exit 1
  /bin/cat >"$source_file"
  if grep -q 'payload\["timeout_diagnostic"\]' "$source_file"; then
    rm -f "$source_file"
    exit 42
  fi
  "$REAL_PYTHON_BIN" "$@" <"$source_file"
  rc=$?
  rm -f "$source_file"
  exit "$rc"
fi
exec "$REAL_PYTHON_BIN" "$@"
STUB
chmod +x "$WORK/bin/python3"

REAL_HEAD_BIN="$(command -v head)"
export REAL_HEAD_BIN
cat >"$WORK/bin/head" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do
  if [ "${SLOW_ARTIFACT_COPY:-}" = 1 ] && [[ "$arg" = */slow-copy.log ]]; then
    touch "$STUB_STATE_DIR/slow_artifact_copy_started"
    sleep 3
  fi
  if [ "${FAIL_LOG_COPY:-}" = 1 ] && [[ "$arg" = */reviewer.log ]]; then
    exit 42
  fi
done
exec "$REAL_HEAD_BIN" "$@"
STUB
chmod +x "$WORK/bin/head"

REAL_STAT_BIN="$(command -v stat)"
export REAL_STAT_BIN
cat >"$WORK/bin/stat" <<'STUB'
#!/usr/bin/env bash
if [ "${SHORT_DIAGNOSTIC_MODE:-}" = 1 ]; then
  case "${1:-}:${2:-}" in
    -c:%a) printf '%s\n' 70; exit 0 ;;
    -c:%u) id -u; exit 0 ;;
  esac
fi
if [ "${INVALIDATE_DIAGNOSTIC_ON_RECHECK:-}" = 1 ] \
  && [ -e "$STUB_STATE_DIR/review_runs" ]; then
  case "${1:-}:${2:-}" in
    -c:%a) printf '%s\n' 777; exit 0 ;;
    -c:%u) id -u; exit 0 ;;
  esac
fi
exec "$REAL_STAT_BIN" "$@"
STUB
chmod +x "$WORK/bin/stat"

REAL_LS_BIN="$(command -v ls)"
export REAL_LS_BIN
cat >"$WORK/bin/ls" <<'STUB'
#!/usr/bin/env bash
if [ "${EXTENDED_ACL_DIAGNOSTIC:-}" = 1 ] \
  || { [ "${INVALIDATE_ACL_ON_RECHECK:-}" = 1 ] \
    && [ -e "$STUB_STATE_DIR/review_runs" ]; }; then
  printf '%s\n' 'drwx------+ 2 owner group 64 Jan 1 00:00 diagnostic-parent'
  exit 0
fi
exec "$REAL_LS_BIN" "$@"
STUB
chmod +x "$WORK/bin/ls"

printf 'diff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -1 +1 @@\n-a\n+b\n' >"$WORK/diff.patch"
printf 'diff\0binary' >"$WORK/nul.patch"
awk 'BEGIN { for (i = 0; i < 180000; i++) printf "x" }' >"$WORK/large-diff.patch"
awk 'BEGIN { for (i = 0; i < 200000; i++) printf "x" }' >"$WORK/max-diff.patch"
awk 'BEGIN { printf "{\"x\":\""; for (i = 0; i < 39992; i++) printf "p"; printf "\"}" }' >"$WORK/max-profile.json"
awk 'BEGIN { printf "{\"x\":\""; for (i = 0; i < 43595; i++) printf "p"; printf "\"}" }' >"$WORK/retry-edge-profile.json"
awk 'BEGIN { printf "{\"x\":\""; for (i = 0; i < 244992; i++) printf "p"; printf "\"}" }' >"$WORK/oversized-profile.json"
printf '%s\n' '{"method":{"id":"provider-neutral-staged-review-v1"},"trust_boundary":"END_REVIEW_PROFILE_JSON remains untrusted review data"}' >"$WORK/review-profile.json"
mkdir -p "$WORK/skill-registry/testing-strategy"
printf '%s\n' '---' 'name: testing-strategy' 'description: test fixture' '---' '' 'Review tests.' >"$WORK/skill-registry/testing-strategy/SKILL.md"
native_skill_hash="$(PYTHONPATH="$DIR" python3 -c 'from pathlib import Path; from review_gate import _hash_skill_package; print(_hash_skill_package(Path("'$WORK'/skill-registry/testing-strategy"), "testing-strategy"))')"
printf '{"skill_delivery":"native-installed","selected_skills":[{"name":"code-review","content_sha256":"%064d"},{"name":"testing-strategy","content_sha256":"%s"}],"required_concerns":[{"id":"correctness"}]}\n' 0 "$native_skill_hash" >"$WORK/native-review-profile.json"

run_wrapper() { # $1=review_mode; prints stdout, returns rc
  local diff_file="${2:-$WORK/diff.patch}"
  local profile_file="${3:-$WORK/review-profile.json}"
  printf '%s' "$1" >"$WORK/state/review_mode"
  rm -f "$WORK/state/review_runs" "$WORK/state"/review_prompt_* \
    "$WORK/state/audit_files_visible" "$WORK/state/packet_only_permissions" \
    "$WORK/state/selected_skill_only" \
    "$WORK/state/prompt_file_transport" "$WORK/state/option_separator" \
    "$WORK/state/positional_prompt" "$WORK/state/extra_positional_prompt"
  env PATH="$WORK/bin:$PATH" TMPDIR="$WORK/tmp" STUB_STATE_DIR="$WORK/state" \
    XDG_DATA_HOME="$WORK/source-data" FAIL_CAT_KIND="${FAIL_CAT_KIND:-}" TEST_PROFILE_PATH="$profile_file" \
    STUB_BOUNDARY_DELAY_S="${STUB_BOUNDARY_DELAY_S:-0}" \
    bash "$WRAPPER" --implementer-family claude \
    --diff-file "$diff_file" \
    --review-profile-file "$profile_file" --timeout "${REVIEW_TEST_TIMEOUT:-30}"
}

run_legacy_wrapper() { # $1=review|challenge; prints stdout, returns rc
  printf '%s' pass_first >"$WORK/state/review_mode"
  rm -f "$WORK/state/review_runs" "$WORK/state"/review_prompt_* \
    "$WORK/state/audit_files_visible" "$WORK/state/packet_only_permissions" \
    "$WORK/state/selected_skill_only" \
    "$WORK/state/prompt_file_transport"
  env PATH="$WORK/bin:$PATH" TMPDIR="$WORK/tmp" STUB_STATE_DIR="$WORK/state" \
    XDG_DATA_HOME="$WORK/source-data" \
    bash "$WRAPPER" --implementer-family claude \
    --diff-file "$WORK/diff.patch" --mode "$1" --timeout 30
}

run_native_wrapper() {
  printf '%s' pass_first >"$WORK/state/review_mode"
  rm -f "$WORK/state/review_runs" "$WORK/state"/review_prompt_* \
    "$WORK/state/native-opencode.json" "$WORK/state/prompt_file_transport" \
    "$WORK/state/selected_skill_only"
  env PATH="$WORK/bin:$PATH" TMPDIR="$WORK/tmp" STUB_STATE_DIR="$WORK/state" \
    XDG_DATA_HOME="$WORK/source-data" \
    bash "$WRAPPER" --implementer-family claude \
    --diff-file "$WORK/diff.patch" \
    --review-profile-file "$WORK/native-review-profile.json" \
    --skill-registry-root "$WORK/skill-registry" --review-skill testing-strategy \
    --timeout 30
}

run_native_timeout_wrapper() { # $1=review_mode $2=diagnostic-dir-or-empty $3=timeout-or-default
  local diagnostic_dir="${2:-}"
  local timeout_seconds="${3:-5}"
  printf '%s' "$1" >"$WORK/state/review_mode"
  rm -f "$WORK/state/review_runs" "$WORK/state"/review_prompt_* \
    "$WORK/state/native-opencode.json" "$WORK/state/prompt_file_transport"
  if [ -n "$diagnostic_dir" ]; then
    env PATH="$WORK/bin:$PATH" TMPDIR="$WORK/tmp" STUB_STATE_DIR="$WORK/state" \
      XDG_DATA_HOME="$WORK/source-data" \
      bash "$WRAPPER" --implementer-family claude \
      --diff-file "$WORK/diff.patch" \
      --review-profile-file "$WORK/native-review-profile.json" \
      --skill-registry-root "$WORK/skill-registry" --review-skill testing-strategy \
      --timeout "$timeout_seconds" --diagnostic-dir "$diagnostic_dir"
  else
    env PATH="$WORK/bin:$PATH" TMPDIR="$WORK/tmp" STUB_STATE_DIR="$WORK/state" \
      XDG_DATA_HOME="$WORK/source-data" \
      bash "$WRAPPER" --implementer-family claude \
      --diff-file "$WORK/diff.patch" \
      --review-profile-file "$WORK/native-review-profile.json" \
      --skill-registry-root "$WORK/skill-registry" --review-skill testing-strategy \
      --timeout "$timeout_seconds"
  fi
}

run_native_profile_without_args() {
  printf '%s' pass_first >"$WORK/state/review_mode"
  rm -f "$WORK/state/review_runs" "$WORK/state"/review_prompt_*
  rm -f "$WORK/state/prompt_file_transport"
  env PATH="$WORK/bin:$PATH" TMPDIR="$WORK/tmp" STUB_STATE_DIR="$WORK/state" \
    XDG_DATA_HOME="$WORK/source-data" \
    bash "$WRAPPER" --implementer-family claude \
    --diff-file "$WORK/diff.patch" \
    --review-profile-file "$WORK/native-review-profile.json" \
    --timeout 30
}

run_bash3_wrapper() {
  printf '%s' pass_first >"$WORK/state/review_mode"
  rm -f "$WORK/state/review_runs" "$WORK/state"/review_prompt_*
  rm -f "$WORK/state/prompt_file_transport"
  env PATH="$WORK/bin:$PATH" TMPDIR="$WORK/tmp" STUB_STATE_DIR="$WORK/state" \
    XDG_DATA_HOME="$WORK/source-data" \
    /bin/bash "$WRAPPER" --implementer-family claude \
    --diff-file "$WORK/diff.patch" \
    --review-profile-file "$WORK/review-profile.json" \
    --timeout 30
}

field() { printf '%s' "$2" | python3 -c "import sys,json;print(json.load(sys.stdin).get('$1',''))" 2>/dev/null; }
runs() { cat "$WORK/state/review_runs" 2>/dev/null || echo 0; }
check() { # $1=label $2=cond
  if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fails=$((fails+1)); fi
}

out="$(run_wrapper pass_on_retry)"; rc=$?
check "prose then strict retry -> passed" '[ "$rc" = 0 ] && [ "$(field status "$out")" = passed ]'
check "retry result preserves per-concern conclusions" 'printf %s "$out" | grep -q "concern_results"'
check "retry ran exactly once (2 review runs)" '[ "$(runs)" = 2 ]'
check "retry prompt carries STRICT RETRY marker" 'grep -q "STRICT RETRY" "$WORK/state/review_prompt_2"'
check "first prompt has no STRICT RETRY marker" '! grep -q "STRICT RETRY" "$WORK/state/review_prompt_1"'

check "prompts carry the OUTPUT CONTRACT" 'grep -q "OUTPUT CONTRACT" "$WORK/state/review_prompt_1"'
check "first and retry prompts carry the staged review method" \
  'grep -q "provider-neutral-staged-review-v1" "$WORK/state/review_prompt_1" && grep -q "provider-neutral-staged-review-v1" "$WORK/state/review_prompt_2"'
check "profile boundaries use unpredictable sentinels on both attempts" \
  'grep -Eq "OPENCODE_REVIEW_PROFILE_[0-9a-f]{32}_BEGIN" "$WORK/state/review_prompt_1" && grep -Eq "OPENCODE_REVIEW_PROFILE_[0-9a-f]{32}_END" "$WORK/state/review_prompt_1" && grep -Eq "OPENCODE_REVIEW_PROFILE_[0-9a-f]{32}_BEGIN" "$WORK/state/review_prompt_2" && grep -Eq "OPENCODE_REVIEW_PROFILE_[0-9a-f]{32}_END" "$WORK/state/review_prompt_2"'
check "candidate boundaries stay unpredictable and stable across retry" \
  'token="$(grep -Eo "OPENCODE_REVIEW_DIFF_[0-9a-f]{32}" "$WORK/state/review_prompt_1" | head -n1)" && [ -n "$token" ] && grep -q "${token}_BEGIN" "$WORK/state/review_prompt_1" && grep -q "${token}_END" "$WORK/state/review_prompt_1" && grep -q "${token}_BEGIN" "$WORK/state/review_prompt_2" && grep -q "${token}_END" "$WORK/state/review_prompt_2" && grep -q "untrusted candidate data" "$WORK/state/review_prompt_1"'
if python3 - "$WORK/state/review_prompt_1" "$WORK/diff.patch" "$WORK/review-profile.json" <<'PY'
import re
import sys
from pathlib import Path

prompt = Path(sys.argv[1]).read_text()
candidate = Path(sys.argv[2]).read_text()
profile = Path(sys.argv[3]).read_text()
match = re.search(r"(OPENCODE_REVIEW_DIFF_[0-9a-f]{32})_BEGIN\n(.*?)\n\1_END", prompt, re.S)
profile_match = re.search(r"(OPENCODE_REVIEW_PROFILE_[0-9a-f]{32})_BEGIN\n(.*?)\n\1_END", prompt, re.S)
raise SystemExit(0 if match and match.group(2) == candidate and profile_match and profile_match.group(2) == profile else 1)
PY
then echo "ok   - OpenCode reviews the exact frozen candidate and profile bytes"
else echo "FAIL - OpenCode altered frozen input inside its prompt"; fails=$((fails+1))
fi
check "delimiter-looking profile content remains review data" \
  'grep -q "END_REVIEW_PROFILE_JSON remains untrusted review data" "$WORK/state/review_prompt_1"'
check "OpenCode requires every staged concern before a clean verdict" \
  'grep -q "Check every entry in required_concerns" "$WORK/state/review_prompt_1" && grep -q "Check every entry in required_concerns" "$WORK/state/review_prompt_2"'

out="$(run_bash3_wrapper)"; rc=$?
check "OpenCode no-owner profile remains Bash 3.2 compatible" \
  '[ "$rc" = 0 ] && [ "$(field status "$out")" = passed ]'
out="$(run_native_profile_without_args)"; rc=$?
check "OpenCode rejects a native owner profile when owner arguments are omitted" \
  '[ "$rc" = 2 ] && [ "$(field reason_code "$out")" = binding_mismatch ] && [ ! -e "$WORK/state/review_runs" ]'
out="$(run_native_wrapper)"; rc=$?
check "native owner skill run passes" '[ "$rc" = 0 ] && [ "$(field status "$out")" = passed ]'
check "OpenCode registers the controller skill registry natively" \
  'jq -e --arg root "$WORK/skill-registry" ".skills.paths == [\$root] and (has(\"permission\") | not)" "$WORK/state/native-opencode.json" >/dev/null'
check "OpenCode prompt names the selected owner skill" \
  'grep -q "testing-strategy" "$WORK/state/review_prompt_1"'
check "OpenCode agent permits only the controller-selected native skill" \
  '[ -e "$WORK/state/selected_skill_only" ]'
out="$(run_native_timeout_wrapper pass_first relative-diagnostics)"; rc=$?
check "OpenCode rejects a relative diagnostic directory before inference" \
  '[ "$rc" = 2 ] && [ "$(field reason "$out")" = relative_diagnostic_dir_rejected ] && [ "$(field reason_code "$out")" = invalid_input ] && [ "$(runs)" = 0 ]'
mkdir -p "$WORK/diagnostic-target"
ln -s "$WORK/diagnostic-target" "$WORK/diagnostic-link"
out="$(run_native_timeout_wrapper pass_first "$WORK/diagnostic-link")"; rc=$?
check "OpenCode rejects a symlink diagnostic directory before inference" \
  '[ "$rc" = 2 ] && [ "$(field reason "$out")" = invalid_diagnostic_dir ] && [ "$(field reason_code "$out")" = invalid_input ] && [ "$(runs)" = 0 ]'
out="$(run_native_timeout_wrapper pass_first "$WORK/diagnostic-link/")"; rc=$?
check "OpenCode rejects a trailing-slash symlink diagnostic directory before inference" \
  '[ "$rc" = 2 ] && [ "$(field reason "$out")" = invalid_diagnostic_dir ] && [ "$(runs)" = 0 ]'
mkdir -p "$WORK/shared-diagnostics"
chmod 0777 "$WORK/shared-diagnostics"
out="$(run_native_timeout_wrapper pass_first "$WORK/shared-diagnostics")"; rc=$?
check "OpenCode rejects a group/world-writable diagnostic directory before inference" \
  '[ "$rc" = 2 ] && [ "$(field reason "$out")" = non_private_diagnostic_dir ] && [ "$(field reason_code "$out")" = invalid_input ] && [ "$(runs)" = 0 ]'
mkdir -p "$WORK/short-mode-diagnostics"
chmod 0700 "$WORK/short-mode-diagnostics"
export SHORT_DIAGNOSTIC_MODE=1
out="$(run_native_timeout_wrapper pass_first "$WORK/short-mode-diagnostics")"; rc=$?
unset SHORT_DIAGNOSTIC_MODE
check "OpenCode rejects short-form group-writable mode output before inference" \
  '[ "$rc" = 2 ] && [ "$(field reason "$out")" = non_private_diagnostic_dir ] && [ "$(runs)" = 0 ]'
mkdir -p "$WORK/acl-diagnostics"
chmod 0700 "$WORK/acl-diagnostics"
export EXTENDED_ACL_DIAGNOSTIC=1
out="$(run_native_timeout_wrapper pass_first "$WORK/acl-diagnostics")"; rc=$?
unset EXTENDED_ACL_DIAGNOSTIC
check "OpenCode rejects an extended-ACL diagnostic directory before inference" \
  '[ "$rc" = 2 ] && [ "$(field reason "$out")" = non_private_diagnostic_dir ] && [ "$(runs)" = 0 ]'

out="$(run_legacy_wrapper review)"; rc=$?
check "OpenCode legacy review keeps the pre-staged instruction" \
  '[ "$rc" = 0 ] && grep -q "Review only this diff." "$WORK/state/review_prompt_1" && ! grep -q "controller-frozen staged review profile" "$WORK/state/review_prompt_1"'
out="$(run_legacy_wrapper challenge)"; rc=$?
check "OpenCode legacy challenge keeps its explicit adversarial scope" \
  '[ "$rc" = 0 ] && grep -q "Adversarially CHALLENGE this diff. Hunt specifically for: race conditions" "$WORK/state/review_prompt_1" && ! grep -q "controller-frozen staged review profile" "$WORK/state/review_prompt_1"'

out="$(run_wrapper never_pass)"; rc=$?
check "retry also prose -> inconclusive/unparseable_findings" '[ "$rc" = 2 ] && [ "$(field reason "$out")" = unparseable_findings ]'
check "no third attempt (bounded retry)" '[ "$(runs)" = 2 ]'

out="$(run_wrapper pass_first)"; rc=$?
check "conforming first reply -> passed with no retry" '[ "$rc" = 0 ] && [ "$(field status "$out")" = passed ] && [ "$(runs)" = 1 ]'
check "one conforming review uses exactly one model invocation" '[ "$(runs)" = 1 ]'
rm -f "$WORK/state/timeout_args"
out="$(REVIEW_TEST_TIMEOUT=180 run_wrapper pass_first)"; rc=$?
check "OpenCode caps the pre-inference boundary probe and preserves the unspent formal budget" \
  '[ "$rc" = 0 ] && grep -q -- "60s opencode debug agent ccl-review" "$WORK/state/timeout_args" && grep -q -- "170s opencode run" "$WORK/state/timeout_args"'
rm -f "$WORK/state/timeout_args"
out="$(STUB_BOUNDARY_DELAY_S=2 REVIEW_TEST_TIMEOUT=10 run_wrapper pass_first)"; rc=$?
formal_timeout="$(awk '/ opencode run / { value=$1; sub(/s$/, "", value); print value; exit }' "$WORK/state/timeout_args")"
check "OpenCode charges the boundary probe against run and retry time" \
  '[ "$rc" = 0 ] && [ "$formal_timeout" -ge 1 ] && [ "$formal_timeout" -lt 10 ]'
check "OpenCode receives the prompt after an explicit option terminator" \
  '[ -e "$WORK/state/option_separator" ] && [ "$(cat "$WORK/state/positional_prompt")" = "Review the attached bounded instruction and candidate packet." ] && [ ! -e "$WORK/state/extra_positional_prompt" ]'
check "wrapper leaves model selection to user OpenCode config" \
  '[ ! -e "$WORK/state/cli_model_override" ] && [ ! -e "$WORK/state/agent_model_override" ]'
check "reviewer project cannot read wrapper audit artifacts" \
  '[ ! -e "$WORK/state/audit_files_visible" ]'
check "generated agent denies packet-external tools" \
  '[ -e "$WORK/state/packet_only_permissions" ]'

out="$(FAIL_CAT_KIND=profile run_wrapper pass_first)"; rc=$?
check "profile read failure stops before inference" \
  '[ "$rc" = 2 ] && [ "$(field reason "$out")" = review_profile_read_failed ] && [ "$(field reason_code "$out")" = local_tool_failure ] && [ "$(runs)" = 0 ]'

out="$(FAIL_CAT_KIND=diff run_wrapper pass_first)"; rc=$?
check "diff read failure stops before inference" \
  '[ "$rc" = 2 ] && [ "$(field reason "$out")" = diff_read_failed ] && [ "$(field reason_code "$out")" = local_tool_failure ] && [ "$(runs)" = 0 ]'

out="$(run_wrapper pass_first "$WORK/nul.patch")"; rc=$?
check "NUL-bearing diff stops before OpenCode inference" \
  '[ "$rc" = 2 ] && [ "$(field reason "$out")" = diff_contains_nul ] && [ "$(field reason_code "$out")" = invalid_input ] && [ "$(field cascade_eligible "$out")" = False ] && [ "$(runs)" = 0 ]'

out="$(run_wrapper pass_first "$WORK/large-diff.patch")"; rc=$?
check "OpenCode accepts a bounded 180 KB frozen candidate" \
  '[ "$rc" = 0 ] && [ "$(field status "$out")" = passed ] && [ "$(runs)" = 1 ] && [ -e "$WORK/state/prompt_file_transport" ]'

out="$(run_wrapper pass_first "$WORK/max-diff.patch" "$WORK/max-profile.json")"; rc=$?
check "OpenCode accepts the maximum candidate plus maximum rendered profile" \
  '[ "$rc" = 0 ] && [ "$(field status "$out")" = passed ] && [ "$(runs)" = 1 ]'

out="$(run_wrapper pass_on_retry "$WORK/max-diff.patch" "$WORK/retry-edge-profile.json")"; rc=$?
check "OpenCode reserves strict-retry headroom before first inference" \
  '[ "$rc" = 2 ] && [ "$(field reason "$out")" = prompt_too_large ] && [ "$(runs)" = 0 ]'

out="$(run_wrapper pass_first "$WORK/diff.patch" "$WORK/oversized-profile.json")"; rc=$?
check "OpenCode rejects a composed prompt above 245 KB before model inference" \
  '[ "$rc" = 2 ] && [ "$(field reason "$out")" = prompt_too_large ] && [ "$(runs)" = 0 ]'

out="$(run_wrapper auth_refresh)"; rc=$?
check "OpenCode OAuth refresh persists through the private runtime binding" \
  '[ "$rc" = 0 ] && grep -q "rotated" "$WORK/source-data/opencode/auth.json" && [ "$(field credential_binding "$out")" = present_shared_auth_link ]'

out="$(run_wrapper tool_exposed)"; rc=$?
check "resolved forbidden tool stops before model inference" \
  '[ "$rc" = 2 ] && [ "$(field reason "$out")" = agent_boundary_invalid ] && [ "$(field reason_code "$out")" = tool_boundary_violation ] && [ "$(runs)" = 0 ]'

out="$(run_wrapper launder)"; rc=$?
check "findings-like prose (P1 + dotted path) is never retried" '[ "$rc" = 2 ] && [ "$(field reason "$out")" = unparseable_findings ] && [ "$(runs)" = 1 ]'
# The prose itself no longer rides out (see the concern-evidence egress in
# opencode_review.sh); what must survive is the operator's ability to locate the
# concern, which the excerpt carries as the severity and locator it matched.
check "ineligible verdict still identifies the concern" \
  'printf %s "$(field concern_excerpt "$out")" | grep -q "severities: P1" && printf %s "$(field concern_excerpt "$out")" | grep -q "text withheld"'
check "ineligible verdict no longer relays the model prose" \
  '! printf %s "$out" | grep -q "auth handling"'

out="$(run_wrapper launder_high)"; rc=$?
check "judge-vocabulary severity word (HIGH) blocks the retry" '[ "$rc" = 2 ] && [ "$(field reason "$out")" = unparseable_findings ] && [ "$(runs)" = 1 ]'

out="$(run_wrapper launder_rootfile)"; rc=$?
check "root-file locator (Makefile:12) blocks the retry" '[ "$rc" = 2 ] && [ "$(field reason "$out")" = unparseable_findings ] && [ "$(runs)" = 1 ]'

out="$(run_wrapper launder_dotfile)"; rc=$?
check "dot-prefixed locator (.github/workflows/ci.yml:12) blocks the retry" '[ "$rc" = 2 ] && [ "$(field reason "$out")" = unparseable_findings ] && [ "$(runs)" = 1 ]'

out="$(run_wrapper launder_semantic)"; rc=$?
check "semantic concern prose without a clean assertion is terminal" \
  '[ "$rc" = 2 ] && [ "$(field reason "$out")" = unparseable_findings ] && [ "$(field cascade_eligible "$out")" = False ] && [ "$(runs)" = 1 ]'

out="$(run_wrapper launder_mixed)"; rc=$?
check "clean phrase mixed with a concern is never retried" '[ "$rc" = 2 ] && [ "$(field reason "$out")" = unparseable_findings ] && [ "$(runs)" = 1 ]'

out="$(run_wrapper findings_on_retry)"; rc=$?
check "retry findings are surfaced" '[ "$rc" = 0 ] && [ "$(field status "$out")" = findings ]'
check "retry finding text preserved" 'printf %s "$out" | grep -q "handlers/auth.code:3"'
check "retry verdict carries the replaced first reply" '[ -n "$(field retry_first_reply_text "$out")" ]'

# The replaced reply is untrusted model text relayed into a durable evidence
# row. The retry gate bounds its SHAPE (no findings-like content, whole-reply
# assertion) but not its SIZE, so without an explicit cap an arbitrarily long
# reply rides out verbatim — the class this repo already closed for the other
# lanes with bounded_reason_detail.
out="$(run_wrapper padded_first)"; rc=$?
check "an over-long first reply is bounded before it reaches the verdict" \
  '[ "$rc" = 0 ] && [ "$(field retry_first_reply_text "$out" | wc -c | tr -d " ")" -lt 400 ]'
check "bounding keeps the reply identifiable" \
  'printf %s "$(field retry_first_reply_text "$out")" | grep -q "No issues found"'

# The terminal concern-evidence path relays the parser's full `.text`. That text
# is arbitrary NON-conforming model prose, not a structured verdict, so it is the
# unbounded-relay class the other lanes closed with a capped concern excerpt.
# `.text` stays whole inside the wrapper (the retry gate and this audit both read
# it); only what leaves on stdout is bounded.
out="$(run_wrapper long_concern)"; rc=$?
check "long malformed concern prose stays terminal" \
  '[ "$rc" = 2 ] && [ "$(field concern_evidence "$out")" = True ] && [ "$(field cascade_eligible "$out")" = False ]'
# Measured against the WHOLE serialized verdict, not the `text` field: the egress
# drops one key and re-emits the rest of the payload, so a per-field assertion
# passes while any other parser-retained key still carries the prose.
check "terminal concern verdict does not relay the prose in ANY field" \
  '! printf %s "$out" | grep -q ZZPROSESENTINELZZ'
check "terminal concern verdict does not relay the full reply text" \
  '[ "$(field text "$out" | wc -c | tr -d " ")" -lt 400 ]'
check "terminal concern verdict carries a bounded excerpt instead" \
  '[ -n "$(field concern_excerpt "$out")" ]'
# The verdict is built from an allowlist, so its key set is the contract. Pinning
# it catches BOTH failure directions without needing a mutated parser: a new
# parser field that nobody classified changes the set (and would otherwise ride
# out unexamined), and a routing field the allowlist forgot changes it too.
verdict_keys() { printf '%s' "$1" | python3 -c 'import sys,json;print(",".join(sorted(json.load(sys.stdin))))'; }
check "terminal concern verdict emits exactly the allowlisted key set" \
  '[ "$(verdict_keys "$out")" = "cascade_eligible,concern_evidence,concern_excerpt,concern_excerpt_truncated,credential_binding,mode,model,provider,reason,reason_code,reviewer,reviewer_family,runtime_isolation,session_id,status,version" ]'

out="$(run_wrapper no_session)"; rc=$?
check "sessionless run is not automatically re-run" '[ "$rc" = 2 ] && [ "$(field reason "$out")" = review_session_missing ] && [ "$(runs)" = 1 ]'

out="$(run_wrapper missing_final)"; rc=$?
check "missing final text is candidate-local malformed model output" \
  '[ "$rc" = 2 ] && [ "$(field reason "$out")" = missing_final_text ] && [ "$(field reason_code "$out")" = invalid_model_output ] && [ "$(field cascade_eligible "$out")" = True ]'

out="$(run_wrapper unfinished_concern)"; rc=$?
check "unfinished OpenCode concern is terminal" \
  '[ "$rc" = 2 ] && [ "$(field reason "$out")" = missing_final_text ] && [ "$(field cascade_eligible "$out")" = False ] && [ "$(field concern_evidence "$out")" = True ] && [ "$(runs)" = 1 ]'

out="$(run_wrapper missing_attribution)"; rc=$?
check "missing model attribution is a terminal binding failure" \
  '[ "$rc" = 2 ] && [ "$(field reason "$out")" = missing_model_attribution ] && [ "$(field reason_code "$out")" = binding_mismatch ] && [ "$(field cascade_eligible "$out")" = False ]'

out="$(run_wrapper export_fail)"; rc=$?
check "export failure is stage-specific and not retried" '[ "$rc" = 2 ] && [ "$(field reason "$out")" = review_export_failed ] && [ "$(runs)" = 1 ]'

out="$(printf '%s' export_timeout >"$WORK/state/review_mode"; rm -f "$WORK/state/review_runs" "$WORK/state"/review_prompt_*; env PATH="$WORK/bin:$PATH" TMPDIR="$WORK/tmp" STUB_STATE_DIR="$WORK/state" XDG_DATA_HOME="$WORK/source-data" bash "$WRAPPER" --implementer-family claude --diff-file "$WORK/diff.patch" --timeout 5)"; rc=$?
check "export timeout remains bounded and candidate-local" \
  '[ "$rc" = 2 ] && [ "$(field reason "$out")" = review_export_timeout ] && [ "$(field reason_code "$out")" = timeout ] && [ "$(field cascade_eligible "$out")" = True ] && [ "$(runs)" = 1 ]'

TIMEOUT_OVERRIDE=5
out="$(printf '%s' retry_timeout >"$WORK/state/review_mode"; rm -f "$WORK/state/review_runs" "$WORK/state"/review_prompt_*; env PATH="$WORK/bin:$PATH" TMPDIR="$WORK/tmp" STUB_STATE_DIR="$WORK/state" XDG_DATA_HOME="$WORK/source-data" bash "$WRAPPER" --implementer-family claude --diff-file "$WORK/diff.patch" --timeout $TIMEOUT_OVERRIDE)"; rc=$?
check "retry timeout still yields structured inconclusive" '[ "$rc" = 2 ] && [ "$(field status "$out")" = inconclusive ] && [ -n "$(field reason "$out")" ]'
check "review timeout remains eligible for the next review client" \
  '[ "$(field reason_code "$out")" = timeout ] && [ "$(field cascade_eligible "$out")" = True ]'

mkdir -p "$WORK/timeout-diagnostics"
out="$(run_native_timeout_wrapper completed_session_timeout)"; rc=$?
check "a stop-finished exported OpenCode session survives a timed-out run tail" \
  '[ "$rc" = 0 ] && [ "$(field status "$out")" = passed ] && [ "$(field native_skill_binding "$out")" = established ] && [ "$(field transport_tail_timeout "$out")" = True ]'

out="$(run_native_timeout_wrapper completed_malformed_timeout)"; rc=$?
check "a stop-finished malformed concern remains terminal despite a timed-out run tail" \
  '[ "$rc" = 2 ] && [ "$(field reason "$out")" = unparseable_findings ] && [ "$(field reason_code "$out")" = invalid_model_output ] && [ "$(field cascade_eligible "$out")" = False ] && [ "$(field concern_evidence "$out")" = True ] && [ "$(field transport_tail_timeout "$out")" = True ]'

out="$(run_native_timeout_wrapper idless_export_timeout)"; rc=$?
check "a timed-out run with an idless export remains fallback-eligible timeout" \
  '[ "$rc" = 2 ] && [ "$(field reason_code "$out")" = timeout ] && [ "$(field cascade_eligible "$out")" = True ]'

out="$(run_native_timeout_wrapper invalid_export_timeout)"; rc=$?
check "a timed-out run with an invalid export remains fallback-eligible timeout" \
  '[ "$rc" = 2 ] && [ "$(field reason_code "$out")" = timeout ] && [ "$(field cascade_eligible "$out")" = True ]'

out="$(run_native_timeout_wrapper native_stream_timeout "$WORK/timeout-diagnostics")"; rc=$?
check "native owner-skill stream timeout is classified precisely but remains inconclusive" \
  '[ "$rc" = 2 ] && [ "$(field status "$out")" = inconclusive ] && [ "$(field reason "$out")" = review_native_skill_stream_timeout ] && [ "$(field reason_code "$out")" = timeout ] && [ "$(field cascade_eligible "$out")" = True ]'
check "native owner-skill stream timeout emits bounded progress evidence" \
  'printf %s "$out" | jq -e '\''
    .timeout_diagnostic.native_owner_skills_requested == true
    and .timeout_diagnostic.selected_skill_count == 1
    and .timeout_diagnostic.event_count == 1
    and .timeout_diagnostic.session_id_observed == true
    and (.timeout_diagnostic.runtime_log_file_count >= 1)
  '\'' >/dev/null'
diagnostic_name="$(printf '%s' "$out" | jq -r '.diagnostic_artifacts.directory_name // empty')"
diagnostic_path="$WORK/timeout-diagnostics/$diagnostic_name"
check "explicit timeout diagnostics retain curated artifacts with restrictive permissions" \
  '[ -n "$diagnostic_name" ] && [ -d "$diagnostic_path" ] && [ "$(stat -c %a "$diagnostic_path" 2>/dev/null || stat -f %Lp "$diagnostic_path")" = 700 ] && [ -f "$diagnostic_path/review-events.jsonl" ] && [ "$(stat -c %a "$diagnostic_path/review-events.jsonl" 2>/dev/null || stat -f %Lp "$diagnostic_path/review-events.jsonl")" = 600 ] && [ -f "$diagnostic_path/opencode-logs/reviewer.log" ] && [ "$(jq -r .credential_files_copied "$diagnostic_path/manifest.json")" = false ]'
check "result and manifest agree that complete timeout artifacts were not truncated" \
  '[ ! -e "$diagnostic_path/.truncation-flags" ] && printf %s "$out" | jq -e '\''
    .diagnostic_artifacts.artifacts_truncated == false
    and .diagnostic_artifacts.logs_truncated == false
  '\'' >/dev/null && jq -e '\''
    .artifacts_truncated == false
    and .logs_truncated == false
  '\'' "$diagnostic_path/manifest.json" >/dev/null'
check "timeout diagnostics never copy the credential binding" \
  '[ -n "$diagnostic_name" ] && [ -z "$(find "$diagnostic_path" -name auth.json -print -quit)" ] && ! grep -rqa "test-only" "$diagnostic_path" && ! find "$diagnostic_path" -type l -print | grep -q .'

mkdir -p "$WORK/revalidated-diagnostics"
export INVALIDATE_DIAGNOSTIC_ON_RECHECK=1
out="$(run_native_timeout_wrapper native_stream_timeout "$WORK/revalidated-diagnostics")"; rc=$?
unset INVALIDATE_DIAGNOSTIC_ON_RECHECK
check "diagnostic parent is revalidated immediately before timeout retention" \
  '[ "$rc" = 2 ] && printf %s "$out" | jq -e '\''
    .diagnostic_artifacts.requested == true
    and .diagnostic_artifacts.retained == false
    and .diagnostic_artifacts.error == "retention_failed"
  '\'' >/dev/null && [ -z "$(find "$WORK/revalidated-diagnostics" -mindepth 1 -print -quit)" ]'
mkdir -p "$WORK/revalidated-acl-diagnostics"
export INVALIDATE_ACL_ON_RECHECK=1
out="$(run_native_timeout_wrapper native_stream_timeout "$WORK/revalidated-acl-diagnostics")"; rc=$?
unset INVALIDATE_ACL_ON_RECHECK
check "diagnostic parent ACL is revalidated immediately before timeout retention" \
  '[ "$rc" = 2 ] && printf %s "$out" | jq -e '\''
    .diagnostic_artifacts.requested == true
    and .diagnostic_artifacts.retained == false
    and .diagnostic_artifacts.error == "retention_failed"
  '\'' >/dev/null && [ -z "$(find "$WORK/revalidated-acl-diagnostics" -mindepth 1 -print -quit)" ]'
mkdir -p "$WORK/enrichment-failure-diagnostics"
export FAIL_TIMEOUT_ENRICHMENT=1
out="$(run_native_timeout_wrapper native_stream_timeout "$WORK/enrichment-failure-diagnostics")"; rc=$?
unset FAIL_TIMEOUT_ENRICHMENT
check "failed timeout-result enrichment removes the unreported sensitive child" \
  '[ "$rc" = 2 ] && [ "$(field reason "$out")" = review_native_skill_stream_timeout ] && [ -z "$(find "$WORK/enrichment-failure-diagnostics" -mindepth 1 -print -quit)" ] && printf %s "$out" | jq -e '\''
    .diagnostic_artifacts.requested == true
    and .diagnostic_artifacts.retained == false
    and .diagnostic_artifacts.error == "retention_failed"
  '\'' >/dev/null'
export FAIL_TIMEOUT_ENRICHMENT=1
out="$(run_native_timeout_wrapper pre_stream_timeout)"; rc=$?
unset FAIL_TIMEOUT_ENRICHMENT
check "failed timeout enrichment without a diagnostic request keeps requested false" \
  '[ "$rc" = 2 ] && [ "$(field reason "$out")" = review_timeout ] && printf %s "$out" | jq -e '\''
    .diagnostic_artifacts.requested == false
    and .diagnostic_artifacts.retained == false
    and (.diagnostic_artifacts | has("error") | not)
  '\'' >/dev/null'

mkdir -p "$WORK/large-log-diagnostics"
out="$(run_native_timeout_wrapper native_large_log_timeout "$WORK/large-log-diagnostics" 8)"; rc=$?
large_log_diagnostic_name="$(printf '%s' "$out" | jq -r '.diagnostic_artifacts.directory_name // empty')"
large_log_diagnostic_path="$WORK/large-log-diagnostics/$large_log_diagnostic_name"
check "oversized runtime logs are omitted and reported as truncated" \
  '[ "$rc" = 2 ] && [ "$(field reason "$out")" = review_native_skill_stream_timeout ] && [ -n "$large_log_diagnostic_name" ] && [ ! -e "$large_log_diagnostic_path/opencode-logs/oversized.log" ] && printf %s "$out" | jq -e '\''
    .diagnostic_artifacts.artifacts_truncated == true
    and .diagnostic_artifacts.logs_truncated == true
  '\'' >/dev/null && jq -e '\''
    .artifacts_truncated == true
    and .logs_truncated == true
    and .limits.max_file_bytes == 5242880
    and .limits.max_total_bytes == 20971520
    and .limits.max_log_files == 1000
    and .limits.max_log_entries == 5000
  '\'' "$large_log_diagnostic_path/manifest.json" >/dev/null'

mkdir -p "$WORK/rotating-log-diagnostics"
export FAIL_LOG_COPY=1
out="$(run_native_timeout_wrapper native_stream_timeout "$WORK/rotating-log-diagnostics")"; rc=$?
unset FAIL_LOG_COPY
rotating_log_diagnostic_name="$(printf '%s' "$out" | jq -r '.diagnostic_artifacts.directory_name // empty')"
rotating_log_diagnostic_path="$WORK/rotating-log-diagnostics/$rotating_log_diagnostic_name"
check "one unreadable runtime log does not discard the remaining timeout evidence" \
  '[ "$rc" = 2 ] && [ -n "$rotating_log_diagnostic_name" ] && [ -f "$rotating_log_diagnostic_path/review-events.jsonl" ] && [ ! -e "$rotating_log_diagnostic_path/opencode-logs/reviewer.log" ] && printf %s "$out" | jq -e '\''
    .diagnostic_artifacts.artifacts_truncated == true
    and .diagnostic_artifacts.logs_truncated == true
  '\'' >/dev/null'

mkdir -p "$WORK/interrupted-copy-diagnostics"
printf '%s' native_slow_copy_timeout >"$WORK/state/review_mode"
rm -f "$WORK/state/slow_artifact_copy_started" "$WORK/interrupted-copy.out"
env PATH="$WORK/bin:$PATH" TMPDIR="$WORK/tmp" STUB_STATE_DIR="$WORK/state" \
  XDG_DATA_HOME="$WORK/source-data" SLOW_ARTIFACT_COPY=1 \
  bash "$WRAPPER" --implementer-family claude --diff-file "$WORK/diff.patch" \
  --review-profile-file "$WORK/native-review-profile.json" \
  --skill-registry-root "$WORK/skill-registry" --review-skill testing-strategy \
  --timeout 5 --diagnostic-dir "$WORK/interrupted-copy-diagnostics" \
  >"$WORK/interrupted-copy.out" &
interrupted_copy_pid=$!
for _ in {1..100}; do
  [ -e "$WORK/state/slow_artifact_copy_started" ] && break
  sleep 0.1
done
kill -TERM "$interrupted_copy_pid"
wait "$interrupted_copy_pid"; interrupted_copy_rc=$?
interrupted_copy_out="$(cat "$WORK/interrupted-copy.out")"
check "operator interrupt during diagnostic copy removes the unreported sensitive child" \
  '[ "$interrupted_copy_rc" = 2 ] && [ "$(field reason_code "$interrupted_copy_out")" = operator_interrupt ] && [ -z "$(find "$WORK/interrupted-copy-diagnostics" -mindepth 1 -print -quit)" ]'

mkdir -p "$WORK/closed-stdout-diagnostics"
printf '%s' native_stream_timeout >"$WORK/state/review_mode"
env PATH="$WORK/bin:$PATH" TMPDIR="$WORK/tmp" STUB_STATE_DIR="$WORK/state" \
  XDG_DATA_HOME="$WORK/source-data" \
  bash "$WRAPPER" --implementer-family claude --diff-file "$WORK/diff.patch" \
  --review-profile-file "$WORK/native-review-profile.json" \
  --skill-registry-root "$WORK/skill-registry" --review-skill testing-strategy \
  --timeout 5 --diagnostic-dir "$WORK/closed-stdout-diagnostics" >&-; closed_stdout_rc=$?
check "closed stdout cannot strand an unreported diagnostic child" \
  '[ "$closed_stdout_rc" = 2 ] && [ -z "$(find "$WORK/closed-stdout-diagnostics" -mindepth 1 -print -quit)" ]'

cat >"$WORK/post-write-signal-env.sh" <<'STUB'
if [ -z "${WRAPPER_TEST_PID:-}" ]; then
  WRAPPER_TEST_PID="$$"
  export WRAPPER_TEST_PID
fi
trap 'case "$BASH_COMMAND" in TIMEOUT_ARTIFACT_REPORTED=*true*) : >"$POST_WRITE_SIGNAL_MARKER"; kill -TERM "$WRAPPER_TEST_PID"; trap - DEBUG ;; esac' DEBUG
STUB
mkdir -p "$WORK/post-write-signal-diagnostics"
export BASH_ENV="$WORK/post-write-signal-env.sh"
export POST_WRITE_SIGNAL_MARKER="$WORK/state/post-write-signal-fired"
rm -f "$POST_WRITE_SIGNAL_MARKER"
out="$(run_native_timeout_wrapper native_stream_timeout "$WORK/post-write-signal-diagnostics")"; rc=$?
unset BASH_ENV POST_WRITE_SIGNAL_MARKER WRAPPER_TEST_PID
post_write_diagnostic_name="$(printf '%s' "$out" | jq -r '.diagnostic_artifacts.directory_name // empty')"
check "signal after stdout handoff preserves the reported diagnostic child without duplicate output" \
  '[ "$rc" = 2 ] && [ -e "$WORK/state/post-write-signal-fired" ] && [ -n "$post_write_diagnostic_name" ] && [ -d "$WORK/post-write-signal-diagnostics/$post_write_diagnostic_name" ] && [ "$(printf '\''%s\n'\'' "$out" | wc -l | tr -d '\''[:space:]'\'')" = 1 ]'

mkdir -p "$WORK/generic-timeout-diagnostics"
out="$(run_native_timeout_wrapper pre_stream_timeout "$WORK/generic-timeout-diagnostics")"; rc=$?
generic_diagnostic_name="$(printf '%s' "$out" | jq -r '.diagnostic_artifacts.directory_name // empty')"
check "owner-aware timeout without stream evidence keeps the generic classification" \
  '[ "$rc" = 2 ] && [ "$(field reason "$out")" = review_timeout ] && [ "$(field reason_code "$out")" = timeout ] && [ "$(field cascade_eligible "$out")" = True ] && [ -n "$generic_diagnostic_name" ] && [ -d "$WORK/generic-timeout-diagnostics/$generic_diagnostic_name" ] && printf %s "$out" | jq -e '\''
    .timeout_diagnostic.native_owner_skills_requested == true
    and .timeout_diagnostic.session_id_observed == false
    and .diagnostic_artifacts.requested == true
    and .diagnostic_artifacts.retained == true
  '\'' >/dev/null'
out="$(run_native_timeout_wrapper invalid_stream_timeout)"; rc=$?
check "non-JSON transport bytes do not prove a native owner-skill stream" \
  '[ "$rc" = 2 ] && [ "$(field reason "$out")" = review_timeout ] && [ "$(field reason_code "$out")" = timeout ] && [ "$(field cascade_eligible "$out")" = True ]'
out="$(run_native_timeout_wrapper session_only_timeout)"; rc=$?
check "session creation without a structured stream part keeps the generic timeout" \
  '[ "$rc" = 2 ] && [ "$(field reason "$out")" = review_timeout ] && [ "$(field reason_code "$out")" = timeout ] && [ "$(field cascade_eligible "$out")" = True ]'

printf '%s' legacy_stream_timeout >"$WORK/state/review_mode"
rm -f "$WORK/state/review_runs" "$WORK/state"/review_prompt_* \
  "$WORK/state/selected_skill_only"
out="$(env PATH="$WORK/bin:$PATH" TMPDIR="$WORK/tmp" STUB_STATE_DIR="$WORK/state" XDG_DATA_HOME="$WORK/source-data" bash "$WRAPPER" --implementer-family claude --diff-file "$WORK/diff.patch" --timeout 5)"; rc=$?
check "structured stream progress without owner skills keeps the generic timeout" \
  '[ "$rc" = 2 ] && [ "$(field reason "$out")" = review_timeout ] && [ "$(field reason_code "$out")" = timeout ] && [ "$(field cascade_eligible "$out")" = True ]'

mkdir -p "$WORK/success-diagnostics"
out="$(printf '%s' pass_first >"$WORK/state/review_mode"; env PATH="$WORK/bin:$PATH" TMPDIR="$WORK/tmp" STUB_STATE_DIR="$WORK/state" XDG_DATA_HOME="$WORK/source-data" bash "$WRAPPER" --implementer-family claude --diff-file "$WORK/diff.patch" --review-profile-file "$WORK/native-review-profile.json" --skill-registry-root "$WORK/skill-registry" --review-skill testing-strategy --diagnostic-dir "$WORK/success-diagnostics" --timeout 30)"; rc=$?
check "successful native owner-skill review does not retain timeout diagnostics" \
  '[ "$rc" = 0 ] && [ "$(field status "$out")" = passed ] && [ -z "$(find "$WORK/success-diagnostics" -mindepth 1 -print -quit)" ]'

out="$(run_wrapper signal_exit)"; rc=$?
check "OpenCode process signals are terminal operator interrupts" \
  '[ "$rc" = 2 ] && [ "$(field reason_code "$out")" = operator_interrupt ] && [ "$(field cascade_eligible "$out")" = False ]'

out="$(run_wrapper provider_balance_exhausted)"; rc=$?
check "OpenCode classifies structured provider billing exhaustion as fallback quota" \
  '[ "$rc" = 2 ] && [ "$(field reason "$out")" = provider_billing_exhausted ] && [ "$(field reason_code "$out")" = quota ] && [ "$(field cascade_eligible "$out")" = True ] && [ "$(field transport_exit_code "$out")" = 1 ]'

out="$(run_wrapper provider_balance_then_server_error)"; rc=$?
check "OpenCode preserves an earlier structured billing error when later events differ" \
  '[ "$rc" = 2 ] && [ "$(field reason "$out")" = provider_billing_exhausted ] && [ "$(field reason_code "$out")" = quota ] && [ "$(field cascade_eligible "$out")" = True ] && [ "$(field transport_exit_code "$out")" = 1 ]'

out="$(run_wrapper provider_auth_then_server_error)"; rc=$?
check "OpenCode preserves an earlier structured authentication error when later events differ" \
  '[ "$rc" = 2 ] && [ "$(field reason "$out")" = provider_auth_unavailable ] && [ "$(field reason_code "$out")" = provider_unavailable ] && [ "$(field cascade_eligible "$out")" = True ] && [ "$(field transport_exit_code "$out")" = 1 ]'

printf '%s' interrupt_wait >"$WORK/state/review_mode"
rm -f "$WORK/state/review_runs" "$WORK/state"/review_prompt_* "$WORK/state/interrupt_waiting"
env PATH="$WORK/bin:$PATH" TMPDIR="$WORK/tmp" STUB_STATE_DIR="$WORK/state" \
  XDG_DATA_HOME="$WORK/source-data" \
  bash "$WRAPPER" --implementer-family claude --diff-file "$WORK/diff.patch" \
  --timeout 30 >"$WORK/interrupt.out" &
interrupt_pid=$!
for _ in {1..100}; do
  [ -e "$WORK/state/interrupt_waiting" ] && break
  sleep 0.02
done
kill -TERM "$interrupt_pid"
wait "$interrupt_pid"
interrupt_rc=$?
out="$(cat "$WORK/interrupt.out")"
check "operator interrupt is terminal and cannot cascade" \
  '[ "$interrupt_rc" = 2 ] && [ "$(field reason_code "$out")" = operator_interrupt ] && [ "$(field cascade_eligible "$out")" = False ]'

echo ----
if [ "$fails" -eq 0 ]; then echo "opencode_review_retry_tests_ok"; else echo "$fails FAILURES"; exit 1; fi
