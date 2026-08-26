#!/usr/bin/env bash
# Contract tests for configurable reviewer-client routing. Every CLI wrapper is
# replaced by one deterministic fake; no live model or repository command runs.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/review-client-order-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
fails=0

mkdir -p "$WORK/harness/scripts" "$WORK/state" "$WORK/repo"
cp "$DIR/review_gate.sh" "$DIR/review_gate.py" "$WORK/harness/scripts/"
cp "$DIR/../SKILL.md" "$WORK/harness/SKILL.md"

cat >"$WORK/harness/scripts/client_stub.sh" <<'CLIENT_STUB'
#!/usr/bin/env bash
set -u
state="$REVIEW_GATE_TEST_STATE"
client="$(basename "$0" _review.sh)"
mode="review"
diff_file=""
if [ "${1:-}" = "review" ] || [ "${1:-}" = "challenge" ]; then
  mode="$1"
  shift
fi
while [ "$#" -gt 0 ]; do
  case "$1" in
    --mode) mode="$2"; shift 2 ;;
    --diff-file) diff_file="$2"; shift 2 ;;
    *) shift ;;
  esac
done

n=$(( $(cat "$state/${client}_runs" 2>/dev/null || echo 0) + 1 ))
printf '%s' "$n" >"$state/${client}_runs"
printf '%s\n' "$client" >>"$state/client_sequence"
printf '%s\n' "$mode" >"$state/${client}_mode"
if [ -n "$diff_file" ] && [ -f "$diff_file" ]; then
  shasum -a 256 "$diff_file" | awk '{print $1}' >"$state/${client}_hash"
fi

behavior="$(cat "$state/${client}_behavior" 2>/dev/null || printf unavailable)"
case "$client" in
  claude) family=claude; provider=anthropic; model=claude-local-default ;;
  kimi) family=moonshot; provider=kimi-cli; model=kimi-local-default ;;
  opencode) family=deepseek; provider=deepseek; model=local-ccl-review ;;
  codex) family=openai; provider=openai; model=codex-local-default ;;
  *) exit 2 ;;
esac
concern_results='[{"concern":"correctness","conclusion":"Checked routing correctness."},{"concern":"safety","conclusion":"Checked fail-closed safety."},{"concern":"failure_paths","conclusion":"Checked fallback failure paths."},{"concern":"tests_evidence","conclusion":"Checked deterministic test evidence."},{"concern":"compatibility","conclusion":"Checked client-order compatibility."}]'

if [ "$client" = "claude" ]; then
  case "$behavior" in
    passed) printf '{"mode":"%s","concern_results":%s,"findings":[],"lens_id":"code-review:%s:no-tools","tool_identity":"code-review:no-tools"}\n' "$mode" "$concern_results" "$mode"; exit 0 ;;
    quota) printf '{"mode":"%s","status":"inconclusive","reason":"quota","reason_code":"quota","fallback_eligible":true,"next_action":"fallback"}\n' "$mode"; exit 2 ;;
    unavailable) printf '{"mode":"%s","status":"inconclusive","reason":"claude missing","reason_code":"client_unavailable","fallback_eligible":true,"next_action":"fallback"}\n' "$mode"; exit 2 ;;
    boundary) printf '{"mode":"%s","status":"inconclusive","reason":"unsafe tools","reason_code":"tool_boundary_violation","fallback_eligible":false,"next_action":"stop_reviewer_lane"}\n' "$mode"; exit 2 ;;
  esac
fi

case "$behavior" in
  passed)
    printf '{"reviewer":"%s","mode":"%s","status":"passed","reviewer_family":"%s","provider":"%s","model":"%s","concern_results":%s,"findings":[]}\n' "$client" "$mode" "$family" "$provider" "$model" "$concern_results"
    exit 0
    ;;
  passed_grok)
    printf '{"reviewer":"%s","mode":"%s","status":"passed","reviewer_family":"grok","provider":"xai","model":"grok-local","concern_results":%s,"findings":[]}\n' "$client" "$mode" "$concern_results"
    exit 0
    ;;
  findings)
    printf '{"reviewer":"%s","mode":"%s","status":"findings","reviewer_family":"%s","provider":"%s","model":"%s","concern_results":%s,"findings":[{"severity":"P1","file":"x","line":1,"failure_path":"breaks","smallest_fix":"fix"}]}\n' "$client" "$mode" "$family" "$provider" "$model" "$concern_results"
    exit 0
    ;;
  unavailable)
    printf '{"reviewer":"%s","mode":"%s","status":"inconclusive","reason":"client missing","reason_code":"client_unavailable","cascade_eligible":true}\n' "$client" "$mode"
    exit 2
    ;;
  quota)
    printf '{"reviewer":"%s","mode":"%s","status":"inconclusive","reason":"quota","reason_code":"quota","cascade_eligible":true}\n' "$client" "$mode"
    exit 2
    ;;
  passed_openai)
    printf '{"reviewer":"%s","mode":"%s","status":"passed","reviewer_family":"openai","provider":"openai","model":"local-default","concern_results":%s,"findings":[]}\n' "$client" "$mode" "$concern_results"
    exit 0
    ;;
  boundary)
    printf '{"reviewer":"%s","mode":"%s","status":"inconclusive","reason":"unsafe tools","reason_code":"tool_boundary_violation","cascade_eligible":false}\n' "$client" "$mode"
    exit 2
    ;;
  auth_path)
    printf '{"reviewer":"%s","mode":"%s","status":"inconclusive","reason":"unsupported host retry","reason_code":"auth_path_unavailable","cascade_eligible":true}\n' "$client" "$mode"
    exit 2
    ;;
esac
exit 2
CLIENT_STUB
chmod +x "$WORK/harness/scripts/client_stub.sh"
for client in claude kimi opencode codex; do
  cp "$WORK/harness/scripts/client_stub.sh" "$WORK/harness/scripts/${client}_review.sh"
done

printf 'diff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -1 +1 @@\n-a\n+b\n' >"$WORK/diff.patch"
printf 'diff --git a/c b/c\n--- a/c\n+++ b/c\n@@ -1 +1 @@\n-x\n+aws_key = "AKIAIOSFODNN7EXAMPLE"\n' >"$WORK/secret-diff.patch"
cat >"$WORK/review-plan.json" <<'JSON'
{
  "intent": "Preserve attributable reviewer routing while adding staged review.",
  "acceptance": ["Client ordering and model-family attribution remain deterministic, and same-family reviewers are eligible."],
  "self_review": [
    {"concern": "correctness", "conclusion": "Routing preserves the first eligible independent result.", "evidence_refs": ["e1"]},
    {"concern": "safety", "conclusion": "Terminal boundaries remain fail closed across clients.", "evidence_refs": ["e1"]},
    {"concern": "failure_paths", "conclusion": "Candidate-local failures alone enter the fallback chain.", "evidence_refs": ["e1"]},
    {"concern": "tests_evidence", "conclusion": "Deterministic stubs cover client order and attribution.", "evidence_refs": ["e1"]},
    {"concern": "compatibility", "conclusion": "Existing client-order customization remains supported.", "evidence_refs": ["e1"]}
  ],
  "evidence": [{"id": "e1", "result": "Deterministic client routing contract fixture."}]
}
JSON

reset_case() {
  rm -f "$WORK/state"/*
  printf '%s' "$1" >"$WORK/state/claude_behavior"
  printf '%s' "$2" >"$WORK/state/kimi_behavior"
  printf '%s' "$3" >"$WORK/state/opencode_behavior"
  printf '%s' "$4" >"$WORK/state/codex_behavior"
}

run_gate() {
  local implementer="$1"
  shift
  REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
    --mode review --cwd "$WORK/repo" --diff-file "$WORK/diff.patch" \
    --implementer-family "$implementer" --review-plan-file "$WORK/review-plan.json" \
    --allow-fallback-egress "$@"
}

run_gate_no_egress() {
  local implementer="$1"
  shift
  REVIEW_GATE_TEST_STATE="$WORK/state" "$WORK/harness/scripts/review_gate.sh" \
    --mode review --cwd "$WORK/repo" --diff-file "$WORK/diff.patch" \
    --implementer-family "$implementer" --review-plan-file "$WORK/review-plan.json" "$@"
}

check() {
  if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fails=$((fails+1)); fi
}

json_fields() {
  local payload="$1"
  shift
  JSON_PAYLOAD="$payload" python3 - "$@" <<'PY' 2>/dev/null
import json
import os
import sys

payload = json.loads(os.environ["JSON_PAYLOAD"])
for expected in sys.argv[1:]:
    path, wanted = expected.split("=", 1)
    value = payload
    for part in path.split("."):
        value = value[int(part)] if isinstance(value, list) else value[part]
    assert str(value).lower() == wanted.lower(), (path, value, wanted)
PY
}

reset_case quota passed unavailable unavailable
out="$(run_gate openai)"; rc=$?
check "default order selects Kimi CLI before OpenCode" \
  '[ "$rc" = 0 ] && [ "$(tr "\n" " " < "$WORK/state/client_sequence")" = "claude codex kimi " ] && json_fields "$out" selected_client=kimi client_order.0=claude client_order.1=codex client_order.2=kimi client_order.3=opencode'

reset_case unavailable unavailable passed unavailable
out="$(CODE_REVIEW_CLIENT_ORDER=opencode,claude,kimi,codex run_gate moonshot)"; rc=$?
check "environment order may put OpenCode first" \
  '[ "$rc" = 0 ] && [ "$(cat "$WORK/state/client_sequence")" = opencode ] && json_fields "$out" selected_client=opencode client_order.0=opencode'

reset_case unavailable unavailable passed_grok unavailable
out="$(CODE_REVIEW_CLIENT_ORDER=opencode run_gate claude)"; rc=$?
check "OpenCode reviewer families accepted by its parser are accepted by the gate" \
  '[ "$rc" = 0 ] && json_fields "$out" selected_client=opencode attempts.0.reviewer_family=grok'

reset_case passed passed unavailable unavailable
out="$(CODE_REVIEW_CLIENT_ORDER=kimi,claude run_gate_no_egress deepseek --diff-file "$WORK/secret-diff.patch")"; rc=$?
check "a secret-bearing egress-denied client is skipped without blocking a later Claude review" \
  '[ "$rc" = 0 ] && [ "$(cat "$WORK/state/client_sequence")" = claude ] && json_fields "$out" skipped_clients.0.client=kimi skipped_clients.0.reason_code=egress_denied skipped_clients.0.stage=preflight selected_client=claude'

reset_case unavailable passed unavailable passed_openai
out="$(CODE_REVIEW_CLIENT_ORDER=codex,kimi run_gate openai)"; rc=$?
check "Codex OpenAI family is eligible for an OpenAI implementer" \
  '[ "$rc" = 0 ] && [ -e "$WORK/state/codex_runs" ] && [ "$(cat "$WORK/state/client_sequence")" = codex ] && json_fields "$out" selected_client=codex attempts.0.reviewer_family=openai'

reset_case passed unavailable passed passed
out="$(run_gate claude)"; rc=$?
check "Claude implementer may use Claude as the first available reviewer" \
  '[ "$rc" = 0 ] && [ -e "$WORK/state/claude_runs" ] && [ "$(cat "$WORK/state/client_sequence")" = claude ] && json_fields "$out" selected_client=claude'

reset_case unavailable passed passed unavailable
out="$(CODE_REVIEW_CLIENT_ORDER=kimi,opencode run_gate moonshot)"; rc=$?
check "Kimi Moonshot family is eligible for a Moonshot implementer" \
  '[ "$rc" = 0 ] && [ -e "$WORK/state/kimi_runs" ] && [ "$(cat "$WORK/state/client_sequence")" = kimi ] && json_fields "$out" selected_client=kimi attempts.0.reviewer_family=moonshot'

reset_case unavailable unavailable passed unavailable
out="$(CODE_REVIEW_CLIENT_ORDER=kimi,opencode run_gate claude)"; rc=$?
check "missing client is recorded and the next client runs" \
  '[ "$rc" = 0 ] && [ "$(tr "\n" " " < "$WORK/state/client_sequence")" = "kimi opencode " ] && json_fields "$out" skipped_clients.0.client=kimi skipped_clients.0.reason_code=client_unavailable selected_client=opencode'

reset_case unavailable auth_path unavailable unavailable
out="$(CODE_REVIEW_CLIENT_ORDER=kimi run_gate claude)"; rc=$?
check "Kimi auth-path code requests one bounded host retry" \
  '[ "$rc" = 2 ] && json_fields "$out" reason_code=auth_path_unavailable next_action=host_retry'

reset_case unavailable auth_path unavailable unavailable
out="$(CODE_REVIEW_CLIENT_ORDER=kimi run_gate claude --host-remediation-attempted)"; rc=$?
check "Kimi auth-path retry is bounded to one host attempt" \
  '[ "$rc" = 2 ] && json_fields "$out" reason_code=auth_path_unavailable next_action=stop_reviewer_lane'

reset_case unavailable unavailable unavailable auth_path
out="$(CODE_REVIEW_CLIENT_ORDER=codex run_gate claude)"; rc=$?
check "Codex auth-path code cannot request a host retry" \
  '[ "$rc" = 2 ] && json_fields "$out" reason_code=auth_path_unavailable next_action=stop_reviewer_lane'

reset_case unavailable unavailable passed passed
out="$(CODE_REVIEW_CLIENT_ORDER=opencode,codex run_gate deepseek)"; rc=$?
check "same-family OpenCode result is accepted after attribution" \
  '[ "$rc" = 0 ] && [ "$(cat "$WORK/state/client_sequence")" = opencode ] && json_fields "$out" selected_client=opencode attempts.0.reviewer_family=deepseek'

reset_case unavailable unavailable passed_openai passed
out="$(CODE_REVIEW_CLIENT_ORDER=opencode,codex run_gate openai)"; rc=$?
check "successful same-family result remains gate-eligible" \
  '[ "$rc" = 0 ] && [ "$(cat "$WORK/state/client_sequence")" = opencode ] && json_fields "$out" selected_client=opencode attempts.0.status=passed attempts.0.reviewer_family=openai'

for bad_order in 'claude,,kimi' 'claude,claude' 'claude,unknown'; do
  reset_case passed passed passed passed
  out="$(CODE_REVIEW_CLIENT_ORDER="$bad_order" run_gate deepseek)"; rc=$?
  check "invalid order '$bad_order' fails before wrappers" \
    '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=invalid_input'
done

reset_case passed passed passed passed
out="$(run_gate unknown-family)"; rc=$?
check "unmapped implementer family fails before wrappers" \
  '[ "$rc" = 2 ] && [ ! -e "$WORK/state/client_sequence" ] && json_fields "$out" reason_code=unmapped_implementer_family'

reset_case quota boundary passed unavailable
out="$(run_gate deepseek)"; rc=$?
check "tool-boundary failure is terminal" \
  '[ "$rc" = 2 ] && [ "$(tr "\n" " " < "$WORK/state/client_sequence")" = "claude codex kimi " ] && [ ! -e "$WORK/state/opencode_runs" ] && json_fields "$out" reason_code=tool_boundary_violation'

reset_case quota quota passed unavailable
out="$(run_gate gemini)"; rc=$?
claude_hash="$(cat "$WORK/state/claude_hash")"
check "every attempted client receives the same frozen packet" \
  '[ "$rc" = 0 ] && [ "$claude_hash" = "$(cat "$WORK/state/kimi_hash")" ] && [ "$claude_hash" = "$(cat "$WORK/state/opencode_hash")" ] && json_fields "$out" packet_sha256="$claude_hash"'

printf '%s\n' '----'
if [ "$fails" -eq 0 ]; then
  echo review_client_order_tests_ok
else
  echo "$fails FAILURES"
  exit 1
fi
