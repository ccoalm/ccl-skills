#!/usr/bin/env bash
# Unit tests for parse_opencode_review.py using deterministic synthetic fixtures
# that mirror real opencode 1.16.0 event/export shapes. No live opencode needed.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PARSER="$DIR/parse_opencode_review.py"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/oc-parse-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
fails=0
SESSION_OK="fixture-session-ok"
SESSION_OTHER="fixture-session-other"
SESSION_MISMATCH="fixture-session-mismatch"

field() { printf '%s' "$2" | python3 -c "import sys,json;print(json.load(sys.stdin).get('$1',''))" 2>/dev/null; }
check() { # $1=label $2=expected-status $3=json   (status only)
  local got; got="$(field status "$3")"
  if [ "$got" = "$2" ]; then echo "ok   - $1 ($got)"; else echo "FAIL - $1: want $2 got '$got' :: $3"; fails=$((fails+1)); fi
}
check_reason() { # $1=label $2=expected-status $3=expected-reason $4=json
  if ! printf '%s' "$4" | python3 -c 'import json,sys; value=json.load(sys.stdin); raise SystemExit(0 if isinstance(value, dict) else 1)' >/dev/null 2>&1; then
    echo "FAIL - $1: parser emitted no valid JSON :: $4"
    fails=$((fails+1))
    return
  fi
  local s r; s="$(field status "$4")"; r="$(field reason "$4")"
  if [ "$s" = "$2" ] && [ "$r" = "$3" ]; then echo "ok   - $1 ($s/$r)"
  else echo "FAIL - $1: want $2/$3 got '$s/$r' :: $4"; fails=$((fails+1)); fi
}
check_finding_fields() { # $1=label $2=json
  if JSON_PAYLOAD="$2" python3 - <<'PY' 2>/dev/null
import json
import os

finding = json.loads(os.environ["JSON_PAYLOAD"])["findings"][0]
expected = {
    "severity": "P1",
    "file": "auth.py",
    "line": 3,
    "failure_path": "None.get crash",
    "smallest_fix": "use rec and rec.get",
}
if finding != expected:
    raise SystemExit(1)
PY
  then echo "ok   - $1"
  else echo "FAIL - $1 :: $2"; fails=$((fails+1))
  fi
}

# --- fixtures (real opencode shapes: flat info.modelID/providerID; export id) ---
printf '{"type":"step_start","sessionID":"%s","part":{"type":"step-start"}}\n' "$SESSION_OK" >"$WORK/ev_ok.json"
cp "$WORK/ev_ok.json" "$WORK/ev_complete.json"
printf '{"type":"step_finish","sessionID":"%s","part":{"type":"step-finish","reason":"stop"}}\n' "$SESSION_OK" >>"$WORK/ev_complete.json"
cp "$WORK/ev_complete.json" "$WORK/ev_trailing_sessionless.json"
printf '%s\n' '{"type":"error","error":{"message":"tail still active"}}' >>"$WORK/ev_trailing_sessionless.json"
printf '{"type":"step_start","sessionID":"%s","part":{"type":"step-start"}}\n' "$SESSION_OTHER" >"$WORK/ev_other.json"
printf '%s\n' 'not-json' >"$WORK/ev_corrupt.json"
printf '{"type":"step_start","sessionID":"%s","part":{"type":"step-start"}}\n' "$SESSION_OK" >>"$WORK/ev_corrupt.json"
# Public debug-agent fixtures: only invalid and a controller-selected skill may
# be enabled unless a case explicitly exercises an extra plugin-tool refusal.
cat >"$WORK/agent_deepseek.json" <<'EOF'
{"name":"ccl-review","mode":"primary","model":{"providerID":"deepseek","modelID":"deepseek-chat"},"tools":{"invalid":true,"question":false,"bash":false,"read":false,"glob":false,"grep":false,"edit":false,"write":false,"task":false,"webfetch":false,"todowrite":false,"skill":true,"ccl_context":false}}
EOF
cat >"$WORK/agent_default.json" <<'EOF'
{"name":"ccl-review","mode":"primary","model":null,"tools":{"invalid":true,"question":false,"bash":false,"read":false,"glob":false,"grep":false,"edit":false,"write":false,"task":false,"webfetch":false,"todowrite":false,"skill":true,"ccl_context":false}}
EOF
cat >"$WORK/agent_deepseek_v4.json" <<'EOF'
{"name":"ccl-review","mode":"primary","model":{"providerID":"deepseek","modelID":"deepseek-v4-pro"},"tools":{"invalid":true,"question":false,"bash":false,"read":false,"glob":false,"grep":false,"edit":false,"write":false,"task":false,"webfetch":false,"todowrite":false,"skill":true,"ccl_context":false}}
EOF
cat >"$WORK/agent_kimi.json" <<'EOF'
{"name":"ccl-review","mode":"primary","model":{"providerID":"kimi","modelID":"kimi-k3"},"tools":{"invalid":true,"question":false,"bash":false,"read":false,"glob":false,"grep":false,"edit":false,"write":false,"task":false,"webfetch":false,"todowrite":false,"skill":true,"ccl_context":false}}
EOF
cat >"$WORK/agent_exposed.json" <<'EOF'
{"name":"ccl-review","mode":"primary","model":{"providerID":"deepseek","modelID":"deepseek-chat"},"tools":{"invalid":true,"bash":true,"read":false,"glob":false,"grep":false,"skill":true,"ccl_context":false}}
EOF
cat >"$WORK/agent_missing.json" <<'EOF'
{"name":"ccl-review","mode":"primary","model":{"providerID":"deepseek","modelID":"deepseek-chat"},"tools":{"invalid":true,"question":false,"bash":false,"read":false,"glob":false,"grep":false,"edit":false,"write":false,"task":false,"webfetch":false,"todowrite":false,"skill":false,"ccl_context":false}}
EOF
cat >"$WORK/agent_extra_plugin_tool_enabled.json" <<'EOF'
{"name":"ccl-review","mode":"primary","model":{"providerID":"deepseek","modelID":"deepseek-chat"},"tools":{"invalid":true,"question":false,"bash":false,"read":false,"glob":false,"grep":false,"edit":false,"write":false,"task":false,"webfetch":false,"todowrite":false,"skill":true,"ccl_context":true}}
EOF
cat >"$WORK/agent_sparse.json" <<'EOF'
{"name":"ccl-review","mode":"primary","model":{"providerID":"deepseek","modelID":"deepseek-chat"},"tools":{"invalid":true,"bash":false,"read":false,"glob":false,"skill":true,"ccl_context":false}}
EOF
cat >"$WORK/agent_claude.json" <<'EOF'
{"name":"ccl-review","mode":"primary","model":{"providerID":"anthropic","modelID":"claude-x"},"tools":{"invalid":true,"question":false,"bash":false,"read":false,"glob":false,"grep":false,"edit":false,"write":false,"task":false,"webfetch":false,"todowrite":false,"skill":true,"ccl_context":false}}
EOF
cat >"$WORK/agent_unmapped.json" <<'EOF'
{"name":"ccl-review","mode":"primary","model":{"providerID":"some-new-vendor","modelID":"m"},"tools":{"invalid":true,"question":false,"bash":false,"read":false,"glob":false,"grep":false,"edit":false,"write":false,"task":false,"webfetch":false,"todowrite":false,"skill":true,"ccl_context":false}}
EOF

cat >"$WORK/exp_pass.json"   <<EOF
{"id":"${SESSION_OK}","messages":[{"info":{"role":"assistant","id":"${SESSION_OK}","version":"1.16.0","modelID":"deepseek-chat","providerID":"deepseek"},"parts":[{"type":"text","text":"NO_BLOCKING_FINDINGS"},{"type":"step-finish","reason":"stop"}]}]}
EOF
cat >"$WORK/exp_pass_coverage.json" <<EOF
{"id":"${SESSION_OK}","messages":[{"info":{"role":"assistant","id":"${SESSION_OK}","version":"1.16.0","modelID":"deepseek-chat","providerID":"deepseek"},"parts":[{"type":"text","text":"CHECK correctness | Independently checked correctness against the frozen candidate.\nNO_BLOCKING_FINDINGS"},{"type":"step-finish","reason":"stop"}]}]}
EOF
cat >"$WORK/exp_pass_blank_separator.json" <<EOF
{"id":"${SESSION_OK}","messages":[{"info":{"role":"assistant","id":"${SESSION_OK}","version":"1.16.0","modelID":"deepseek-chat","providerID":"deepseek"},"parts":[{"type":"text","text":"CHECK correctness | Independently checked correctness against the frozen candidate.\n\nNO_BLOCKING_FINDINGS"},{"type":"step-finish","reason":"stop"}]}]}
EOF
cat >"$WORK/exp_find.json"   <<EOF
{"id":"${SESSION_OK}","messages":[{"info":{"role":"assistant","modelID":"deepseek-chat","providerID":"deepseek"},"parts":[{"type":"text","text":"P1 auth.py:3 None.get crash | use rec and rec.get"},{"type":"step-finish","reason":"stop"}]}]}
EOF
cat >"$WORK/exp_lgtm.json"   <<EOF
{"id":"${SESSION_OK}","messages":[{"info":{"role":"assistant","modelID":"deepseek-chat","providerID":"deepseek"},"parts":[{"type":"text","text":"Looks good to me, no problems."},{"type":"step-finish","reason":"stop"}]}]}
EOF
cat >"$WORK/exp_claude.json" <<EOF
{"id":"${SESSION_OK}","messages":[{"info":{"role":"assistant","modelID":"claude-x","providerID":"anthropic"},"parts":[{"type":"text","text":"NO_BLOCKING_FINDINGS"},{"type":"step-finish","reason":"stop"}]}]}
EOF
cat >"$WORK/exp_unmapped.json" <<EOF
{"id":"${SESSION_OK}","messages":[{"info":{"role":"assistant","modelID":"m","providerID":"some-new-vendor"},"parts":[{"type":"text","text":"NO_BLOCKING_FINDINGS"},{"type":"step-finish","reason":"stop"}]}]}
EOF
# kimi providerID (user-configured opencode provider name) must resolve to moonshot family.
cat >"$WORK/ev_kimi.json" <<'EOF'
{"type":"step_start","sessionID":"fixture-session-kimi","part":{"type":"step-start"}}
EOF
cat >"$WORK/exp_kimi.json" <<'EOF'
{"id":"fixture-session-kimi","messages":[{"info":{"role":"assistant","modelID":"kimi-k3","providerID":"kimi"},"parts":[{"type":"text","text":"NO_BLOCKING_FINDINGS"},{"type":"step-finish","reason":"stop"}]}]}
EOF
cat >"$WORK/exp_unfinished.json" <<EOF
{"id":"${SESSION_OK}","messages":[{"info":{"role":"assistant","modelID":"deepseek-chat","providerID":"deepseek"},"parts":[{"type":"step-finish","reason":"tool-calls"}]}]}
EOF
cat >"$WORK/exp_unfinished_concern.json" <<EOF
{"id":"${SESSION_OK}","messages":[{"info":{"role":"assistant","modelID":"deepseek-chat","providerID":"deepseek"},"parts":[{"type":"text","text":"P1 auth.py:3 possible null dereference | guard the lookup"},{"type":"step-finish","reason":"length"}]}]}
EOF
cat >"$WORK/exp_mismatch.json" <<EOF
{"id":"${SESSION_MISMATCH}","messages":[{"info":{"role":"assistant","modelID":"deepseek-chat","providerID":"deepseek"},"parts":[{"type":"text","text":"NO_BLOCKING_FINDINGS"},{"type":"step-finish","reason":"stop"}]}]}
EOF
# cross-message forgery: early NO_BLOCKING_FINDINGS text, later empty stop step
cat >"$WORK/exp_forge.json" <<EOF
{"id":"${SESSION_OK}","messages":[{"info":{"role":"assistant","modelID":"deepseek-chat","providerID":"deepseek"},"parts":[{"type":"text","text":"NO_BLOCKING_FINDINGS"}]},{"info":{"role":"assistant","modelID":"deepseek-chat","providerID":"deepseek"},"parts":[{"type":"step-finish","reason":"stop"}]}]}
EOF
# refusal that merely quotes a diff line (file:line present, but no severity prefix)
cat >"$WORK/exp_refusal.json" <<EOF
{"id":"${SESSION_OK}","messages":[{"info":{"role":"assistant","modelID":"deepseek-chat","providerID":"deepseek"},"parts":[{"type":"text","text":"I cannot review this. The change is at src/auth.py:3 but I lack context."},{"type":"step-finish","reason":"stop"}]}]}
EOF
# export with no session id anywhere
cat >"$WORK/exp_noid.json" <<'EOF'
{"messages":[{"info":{"role":"assistant","modelID":"deepseek-chat","providerID":"deepseek"},"parts":[{"type":"text","text":"NO_BLOCKING_FINDINGS"},{"type":"step-finish","reason":"stop"}]}]}
EOF

# Message with two text parts: a finding-like fragment followed by the sentinel.
# Joined text must not pass as the bare sentinel; it remains unparseable.
cat >"$WORK/exp_multitext.json" <<EOF
{"id":"${SESSION_OK}","messages":[{"info":{"role":"assistant","modelID":"deepseek-chat","providerID":"deepseek"},"parts":[{"type":"text","text":"P1 auth.py:5 real bug | add a guard"},{"type":"text","text":"NO_BLOCKING_FINDINGS"},{"type":"step-finish","reason":"stop"}]}]}
EOF
cat >"$WORK/exp_model_switch.json" <<'EOF'
{"id":"modelhistory1","messages":[{"info":{"role":"assistant","modelID":"other-model","providerID":"other-provider"},"parts":[{"type":"text","text":"hidden analysis"}]},{"info":{"role":"assistant","modelID":"deepseek-chat","providerID":"deepseek"},"parts":[{"type":"text","text":"NO_BLOCKING_FINDINGS"},{"type":"step-finish","reason":"stop"}]}]}
EOF
printf '%s\n' '{"type":"step_start","sessionID":"modelhistory1","part":{"type":"step-start"}}' >"$WORK/ev_model_switch.json"

P() { python3 "$PARSER" "$@"; }
OKARGS=(--events "$WORK/ev_ok.json" --agent-boundary "$WORK/agent_deepseek.json" --implementer-family claude --require-skill-tool)
# kimi-lane args: dedicated events file whose session id matches exp_kimi.json (non-ses_ shape)
KP() { python3 "$PARSER" --events "$WORK/ev_kimi.json" --agent-boundary "$WORK/agent_kimi.json" --implementer-family "$1" --require-skill-tool --export "$WORK/exp_kimi.json"; }

legacy_out="$(P "${OKARGS[@]}" --export "$WORK/exp_pass.json")"
check "clean sentinel -> passed" passed "$legacy_out"
if [ "$(field concern_results "$legacy_out")" = "" ]; then
  echo "ok   - OpenCode legacy result omits staged concern fields"
else
  echo "FAIL - OpenCode legacy result added staged concern fields :: $legacy_out"
  fails=$((fails+1))
fi
coverage_out="$(P "${OKARGS[@]}" --export "$WORK/exp_pass_coverage.json")"
check "concern conclusions plus clean sentinel -> passed" passed "$coverage_out"
check "blank separator before sentinel -> passed" passed "$(P "${OKARGS[@]}" --export "$WORK/exp_pass_blank_separator.json")"
if [ "$(printf '%s' "$coverage_out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["concern_results"][0]["concern"])')" = correctness ]; then
  echo "ok   - OpenCode preserves per-concern conclusions"
else
  echo "FAIL - OpenCode discarded per-concern conclusions :: $coverage_out"
  fails=$((fails+1))
fi
check_reason "configured agent model mismatch -> blocked" inconclusive agent_model_mismatch "$(P --events "$WORK/ev_ok.json" --agent-boundary "$WORK/agent_deepseek_v4.json" --implementer-family claude --require-skill-tool --export "$WORK/exp_pass.json")"
out="$(P "${OKARGS[@]}" --export "$WORK/exp_find.json")"
check "schema findings -> findings" findings "$out"
check_finding_fields "OpenCode findings use the shared structured schema" "$out"
check_reason "praise/LGTM -> unparseable_findings" inconclusive unparseable_findings "$(P "${OKARGS[@]}" --export "$WORK/exp_lgtm.json")"
unbound_timeout_out="$(P --events "$WORK/ev_complete.json" --agent-boundary "$WORK/agent_deepseek.json" --implementer-family claude --require-skill-tool --export "$WORK/exp_pass.json" --exit-code 124)"
check_reason "stop-finished legacy export without a frozen concern contract stays timeout" inconclusive reviewer_timeout "$unbound_timeout_out"
timeout_complete_out="$(P --events "$WORK/ev_complete.json" --agent-boundary "$WORK/agent_deepseek.json" --implementer-family claude --require-skill-tool --required-concern correctness --export "$WORK/exp_pass_coverage.json" --exit-code 124)"
check "complete profile-bound export survives a timed-out run tail" passed "$timeout_complete_out"
if [ "$(field transport_tail_timeout "$timeout_complete_out")" = True ]; then
  echo "ok   - recovered OpenCode verdict records the timed-out run tail"
else
  echo "FAIL - recovered OpenCode verdict omitted timed-out run-tail evidence :: $timeout_complete_out"
  fails=$((fails+1))
fi
check_reason "timeout-tail recovery requires every bound concern conclusion" inconclusive reviewer_timeout \
  "$(P --events "$WORK/ev_complete.json" --agent-boundary "$WORK/agent_deepseek.json" --implementer-family claude --require-skill-tool --required-concern correctness --export "$WORK/exp_pass.json" --exit-code 124)"
check_reason "malformed final text after a timed-out run remains timeout" inconclusive reviewer_timeout \
  "$(P --events "$WORK/ev_complete.json" --agent-boundary "$WORK/agent_deepseek.json" --implementer-family claude --require-skill-tool --required-concern correctness --export "$WORK/exp_lgtm.json" --exit-code 124)"
check "timeout-tail recovery accepts a complete bound concern contract" passed \
  "$(P --events "$WORK/ev_complete.json" --agent-boundary "$WORK/agent_deepseek.json" --implementer-family claude --require-skill-tool --required-concern correctness --export "$WORK/exp_pass_coverage.json" --exit-code 124)"
check_reason "unfinished export after reviewer timeout stays inconclusive" inconclusive reviewer_timeout "$(P "${OKARGS[@]}" --export "$WORK/exp_unfinished.json" --exit-code 124)"
check_reason "export stop without terminal event evidence stays timeout" inconclusive reviewer_timeout "$(P "${OKARGS[@]}" --export "$WORK/exp_pass.json" --exit-code 124)"
check_reason "sessionless event after terminal stop keeps timeout active" inconclusive reviewer_timeout "$(P --events "$WORK/ev_trailing_sessionless.json" --agent-boundary "$WORK/agent_deepseek.json" --implementer-family claude --require-skill-tool --export "$WORK/exp_pass.json" --exit-code 124)"
check_reason "nonzero exit -> inconclusive" inconclusive reviewer_exit_1 "$(P "${OKARGS[@]}" --export "$WORK/exp_pass.json" --exit-code 1)"
check_reason "debug-agent forbidden tool -> blocked" inconclusive agent_forbidden_tool_available \
  "$(P --events "$WORK/ev_ok.json" --agent-boundary "$WORK/agent_exposed.json" --implementer-family claude --require-skill-tool --export "$WORK/exp_pass.json")"
check_reason "debug-agent missing skill tool -> blocked" inconclusive agent_required_tool_missing \
  "$(P --events "$WORK/ev_ok.json" --agent-boundary "$WORK/agent_missing.json" --implementer-family claude --require-skill-tool --export "$WORK/exp_pass.json")"
check "debug-agent may disable skill when no owner skill was selected" passed \
  "$(P --events "$WORK/ev_ok.json" --agent-boundary "$WORK/agent_missing.json" --implementer-family claude --export "$WORK/exp_pass.json")"
check_reason "debug-agent must disable skill when no owner skill was selected" inconclusive agent_forbidden_tool_available \
  "$(P --events "$WORK/ev_ok.json" --agent-boundary "$WORK/agent_deepseek.json" --implementer-family claude --export "$WORK/exp_pass.json")"
check_reason "debug-agent enabled plugin tool -> blocked" inconclusive agent_forbidden_tool_available \
  "$(P --events "$WORK/ev_ok.json" --agent-boundary "$WORK/agent_extra_plugin_tool_enabled.json" --implementer-family claude --require-skill-tool --export "$WORK/exp_pass.json")"
check_reason "debug-agent sparse known-tool map -> blocked" inconclusive agent_disabled_tool_missing \
  "$(P --events "$WORK/ev_ok.json" --agent-boundary "$WORK/agent_sparse.json" --implementer-family claude --require-skill-tool --export "$WORK/exp_pass.json")"
check_reason "assistant history model switch -> blocked" inconclusive session_model_history_mismatch \
  "$(P --events "$WORK/ev_model_switch.json" --agent-boundary "$WORK/agent_deepseek.json" --implementer-family claude --require-skill-tool --export "$WORK/exp_model_switch.json")"
check_reason "multi-text-part sentinel forgery -> blocked" inconclusive unparseable_findings "$(P "${OKARGS[@]}" --export "$WORK/exp_multitext.json")"
check_reason "same family -> blocked" inconclusive same_family_as_implementer \
  "$(P --events "$WORK/ev_ok.json" --agent-boundary "$WORK/agent_claude.json" --implementer-family claude --require-skill-tool --export "$WORK/exp_claude.json")"
check_reason "unmapped family -> inconclusive" inconclusive missing_or_unmapped_reviewer_family \
  "$(P --events "$WORK/ev_ok.json" --agent-boundary "$WORK/agent_unmapped.json" --implementer-family claude --require-skill-tool --export "$WORK/exp_unmapped.json")"
check "kimi provider -> moonshot family, independent vs claude implementer" passed "$(KP claude)"
check_reason "kimi provider (moonshot) vs moonshot implementer -> same family" inconclusive same_family_as_implementer "$(KP moonshot)"
check_reason "unfinished run -> inconclusive" inconclusive missing_final_text "$(P "${OKARGS[@]}" --export "$WORK/exp_unfinished.json")"
out="$(P "${OKARGS[@]}" --export "$WORK/exp_unfinished_concern.json")"
check_reason "unfinished run preserves concern text" inconclusive missing_final_text "$out"
if [ "$(field text "$out")" = "P1 auth.py:3 possible null dereference | guard the lookup" ]; then
  echo "ok   - unfinished concern text remains available to the wrapper audit"
else
  echo "FAIL - unfinished concern text was discarded :: $out"
  fails=$((fails+1))
fi
check_reason "session mismatch -> blocked" inconclusive session_id_mismatch "$(P "${OKARGS[@]}" --export "$WORK/exp_mismatch.json")"
check_reason "cross-message forgery -> missing_final_text" inconclusive missing_final_text "$(P "${OKARGS[@]}" --export "$WORK/exp_forge.json")"
check_reason "missing events -> blocked" inconclusive missing_events "$(P --agent-boundary "$WORK/agent_deepseek.json" --implementer-family claude --require-skill-tool --export "$WORK/exp_pass.json")"
check_reason "corrupt event stream -> blocked" inconclusive event_stream_unparseable \
  "$(P --events "$WORK/ev_corrupt.json" --agent-boundary "$WORK/agent_deepseek.json" --implementer-family claude --require-skill-tool --export "$WORK/exp_pass.json")"
check_reason "missing export -> inconclusive" inconclusive missing_export "$(P "${OKARGS[@]}")"
check_reason "refusal quoting file:line -> unparseable" inconclusive unparseable_findings "$(P "${OKARGS[@]}" --export "$WORK/exp_refusal.json")"
check_reason "export without session id -> mismatch" inconclusive session_id_mismatch "$(P "${OKARGS[@]}" --export "$WORK/exp_noid.json")"
check_reason "implementer providerID anthropic vs reviewer anthropic -> same family" inconclusive same_family_as_implementer \
  "$(P --events "$WORK/ev_ok.json" --agent-boundary "$WORK/agent_claude.json" --implementer-family anthropic --require-skill-tool --export "$WORK/exp_claude.json")"
check_reason "unmapped implementer family -> blocked" inconclusive unmapped_implementer_family "$(P --events "$WORK/ev_ok.json" --agent-boundary "$WORK/agent_deepseek.json" --implementer-family bogusvendor --require-skill-tool --export "$WORK/exp_pass.json")"
check_reason "implementer family deepseek vs reviewer deepseek -> blocked" inconclusive same_family_as_implementer \
  "$(P --events "$WORK/ev_ok.json" --agent-boundary "$WORK/agent_deepseek.json" --implementer-family deepseek --require-skill-tool --export "$WORK/exp_pass.json")"
missing_boundary_rc=0
if missing_boundary_out="$(P --events "$WORK/ev_ok.json" --export "$WORK/exp_pass.json" --implementer-family claude 2>/dev/null)"; then
  missing_boundary_rc=0
else
  missing_boundary_rc=$?
fi
if [ "$missing_boundary_rc" -eq 2 ] && [ -z "$missing_boundary_out" ]; then
  echo "ok   - missing boundary arg is rejected by argparse"
else
  echo "FAIL - missing boundary arg: want exit 2 with empty stdout, got exit $missing_boundary_rc :: $missing_boundary_out"
  fails=$((fails+1))
fi
check_reason "native OpenCode default still enforces exported family independence" inconclusive same_family_as_implementer \
  "$(P --events "$WORK/ev_ok.json" --agent-boundary "$WORK/agent_default.json" --implementer-family deepseek --require-skill-tool --export "$WORK/exp_pass.json")"

echo "----"
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "$fails FAIL"; exit 1; fi
