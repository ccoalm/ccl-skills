#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
parser="$script_dir/parse_review_json.py"

if printf '%s\n' '{"mode":"review","findings":[]}' | python3 "$parser" >/dev/null 2>&1; then
  printf 'expected missing parser mode to fail cleanly\n' >&2
  exit 1
fi
if printf '%s\n' '{"mode":"typo","findings":[]}' | python3 "$parser" typo >/dev/null 2>&1; then
  printf 'expected unknown parser mode to fail cleanly\n' >&2
  exit 1
fi

run_parser() {
  local mode="$1"
  python3 "$parser" "$mode"
}

run_ok() {
  local mode="$1"
  local payload="$2"
  printf '%s\n' "$payload" | run_parser "$mode" >/dev/null
}

run_fail() {
  local mode="$1"
  local payload="$2"
  if printf '%s\n' "$payload" | run_parser "$mode" >/dev/null 2>&1; then
    printf 'expected parser failure for payload: %s\n' "$payload" >&2
    return 1
  fi
}

run_output_not_contains() {
  local mode="$1"
  local payload="$2"
  local needle="$3"
  local output
  if ! output="$(printf '%s\n' "$payload" | run_parser "$mode")" || [ -z "$output" ]; then
    printf 'expected parser success with non-empty output for %s\n' "$mode" >&2
    return 1
  fi
  if printf '%s\n' "$output" | grep -F "$needle" >/dev/null; then
    printf 'expected parser output for %s to omit: %s\n' "$mode" "$needle" >&2
    return 1
  fi
}

run_ok challenge '{"type":"result","subtype":"success","is_error":false,"terminal_reason":"completed","structured_output":{"mode":"challenge","findings":[]}}'
run_ok challenge '{"type":"result","subtype":"success","is_error":false,"terminal_reason":"completed","result":"{\"mode\":\"challenge\",\"findings\":[]}"}'
run_ok challenge '{"mode":"challenge","findings":[]}'
run_ok review '{"mode":"review","findings":[]}'
coverage_out="$(printf '%s\n' '{"mode":"review","concern_results":[{"concern":"correctness","conclusion":"Checked the frozen candidate independently."}],"findings":[]}' | run_parser review)"
printf '%s\n' "$coverage_out" | grep -F '"concern": "correctness"' >/dev/null
run_fail review '{"mode":"review","concern_results":[{"concern":"correctness","conclusion":"first"},{"concern":"correctness","conclusion":"duplicate"}],"findings":[]}'
run_ok review '{"type":"result","subtype":"success","is_error":false,"terminal_reason":"completed","structured_output":{"mode":"review","findings":[]}}'
run_ok review $'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[]}\n{"type":"result","subtype":"success","is_error":false,"terminal_reason":"completed","structured_output":{"mode":"review","findings":[]}}'
run_output_not_contains review '{"mode":"review","findings":[]}' '"lens_id"'
run_output_not_contains challenge '{"mode":"challenge","findings":[]}' '"tool_identity"'
run_output_not_contains challenge '{"mode":"challenge","findings":[],"confidence":"high"}' '"confidence"'
run_output_not_contains challenge '{"mode":"challenge","findings":[{"severity":"P2","file":"x","line":1,"failure_path":"fails","smallest_fix":"fix","confidence":"low"}]}' '"confidence"'
run_ok consult '{"mode":"consult","answer":"ok","evidence_sufficient":true,"findings":[]}'
run_output_not_contains consult '{"mode":"consult","answer":"ok","evidence_sufficient":true,"findings":[],"model":"future"}' '"model"'
# A successful result envelope without a terminal_reason field must still pass:
# its absence is tolerated symmetrically with subtype, so a CLI that stops
# emitting the field cannot silently turn every direct run inconclusive.
run_ok challenge '{"type":"result","subtype":"success","is_error":false,"structured_output":{"mode":"challenge","findings":[]}}'

run_fail challenge '{"mode":"challenge","lens_id":"code-review:challenge:no-tools-adversarial","findings":[]}'
run_fail challenge '{"mode":"challenge","tool_identity":"code-review:no-tools","findings":[]}'
run_fail challenge '{"mode":"challenge","lens_id":"code-review:review:no-tools","tool_identity":"code-review:no-tools","findings":[]}'
run_fail challenge '{"mode":"challenge","lens_id":"code-review:challenge:no-tools-adversarial","tool_identity":"code-review:no-tools","findings":[]}'
run_fail review '{"type":"result","subtype":"success","is_error":false,"terminal_reason":"completed","structured_output":{"mode":"review","tool_identity":"code-review:no-tools","findings":[]}}'
run_fail review '{"type":"result","subtype":"success","is_error":false,"terminal_reason":"completed","structured_output":{"mode":"review","lens_id":"code-review:review:no-tools","findings":[]}}'
run_fail review '{"type":"result","subtype":"success","is_error":false,"terminal_reason":"completed","result":"{\"mode\":\"review\",\"lens_id\":\"code-review:review:no-tools\",\"tool_identity\":\"code-review:no-tools\",\"findings\":[]}"}'
run_fail review '{"type":"result","subtype":"error","is_error":true,"structured_output":{"mode":"review","findings":[]}}'
run_fail review '{"type":"result","subtype":"success","is_error":false,"terminal_reason":"max_turns","structured_output":{"mode":"review","findings":[]}}'
run_fail review '{"mode":"review","lens_id":"code-review:review:no-tools","findings":[]}'
run_fail review '{"mode":"review","tool_identity":"code-review:no-tools","findings":[]}'
run_fail review '{"mode":"review","lens_id":"code-review:challenge:no-tools-adversarial","tool_identity":"code-review:no-tools","findings":[]}'
run_fail review '{"mode":"review","lens_id":"code-review:review:no-tools","tool_identity":"code-review:no-tools","findings":[]}'
run_fail consult '{"mode":"consult","findings":[]}'
run_fail consult '{"type":"result","subtype":"error","is_error":true,"structured_output":{"mode":"consult","answer":"ok","evidence_sufficient":true,"findings":[]}}'
run_fail consult '{"type":"result","subtype":"success","is_error":false,"terminal_reason":"max_turns","structured_output":{"mode":"consult","answer":"ok","evidence_sufficient":true,"findings":[]}}'
run_fail consult '{"mode":"consult","answer":"ok","findings":[]}'
run_fail consult '{"mode":"consult","answer":"missing","evidence_sufficient":false,"findings":[]}'
run_fail consult '{"mode":"consult","answer":"ok","evidence_sufficient":"true","findings":[]}'
run_fail consult '{"mode":"consult","answer":"ok","lens_id":"code-review:review:no-tools","tool_identity":"code-review:no-tools","evidence_sufficient":true,"findings":[]}'
run_fail consult '{"mode":"consult","answer":"ok","lens_id":"code-review:review:no-tools","evidence_sufficient":true,"findings":[]}'
run_fail consult '{"mode":"consult","answer":"ok","tool_identity":"code-review:no-tools","evidence_sufficient":true,"findings":[]}'
run_fail consult '{"mode":"consult","answer":"ok","consult_scope":"prompt-only","evidence_sufficient":true,"findings":[]}'
run_fail consult '{"mode":"consult","answer":"ok","gate_eligible":false,"evidence_sufficient":true,"findings":[]}'
run_fail consult '{"mode":"consult","answer":"ok","advisory":true,"evidence_sufficient":true,"findings":[]}'
run_fail consult '{"mode":"consult","answer":"ok","consult_scope":"repository","tool_identity":"code-review:read-only-repository","evidence_sufficient":true,"findings":[]}'
run_fail consult '{"mode":"consult","answer":"ok","evidence_sufficient":true,"findings":[{"severity":"P2","file":"x","line":1,"failure_path":"fails","smallest_fix":"fix","source":"prompt-only-advisory"}]}'
run_fail consult '{"type":"result","subtype":"success","is_error":false,"terminal_reason":"completed","structured_output":{"mode":"consult","answer":"ok","lens_id":"code-review:review:no-tools","tool_identity":"code-review:no-tools","evidence_sufficient":true,"findings":[]}}'
run_fail consult '{"type":"result","subtype":"success","is_error":false,"terminal_reason":"completed","structured_output":{"mode":"consult","answer":"ok","consult_scope":"prompt-only","tool_identity":"code-review:no-tools","evidence_sufficient":true,"findings":[]}}'

run_fail challenge '{"type":"result","subtype":"error","is_error":true,"structured_output":{"mode":"challenge","findings":[]}}'
run_fail challenge '{"type":"result","subtype":"error_max_turns","is_error":false,"terminal_reason":"completed","structured_output":{"mode":"challenge","findings":[]}}'
run_fail challenge '{"subtype":"error_max_turns","structured_output":{"mode":"challenge","findings":[]}}'
run_fail challenge '{"subtype":"success","is_error":false,"structured_output":{"mode":"challenge","findings":[]}}'
run_fail challenge '{"type":"result","structured_output":{"mode":"challenge","findings":[]}}'
run_fail challenge '{"structured_output":{"mode":"challenge","findings":[]}}'
run_fail challenge '{"type":"result","subtype":"success","is_error":false,"api_error_status":429,"terminal_reason":"completed","structured_output":{"mode":"challenge","findings":[]}}'
run_fail challenge '{"type":"result","subtype":"success","is_error":false,"terminal_reason":"max_turns","structured_output":{"mode":"challenge","findings":[]}}'
run_fail challenge '{"type":"result","subtype":"success","is_error":false,"permission_denials":["Read"],"structured_output":{"mode":"challenge","findings":[]}}'
run_fail challenge '{"type":"assistant","is_error":true,"structured_output":{"mode":"challenge","findings":[]}}'
run_fail challenge '{"type":"assistant","structured_output":{"mode":"challenge","findings":[]}}'
run_fail challenge '{"type":"result","subtype":"success","is_error":false,"terminal_reason":"completed","structured_output":{"mode":"challenge","lens_id":"code-review:challenge:no-tools-adversarial","tool_identity":"code-review:no-tools","findings":[]}}'

run_wrapper_identity_tests() {
  local tmp_dir repo_dir fake_bin tool_enabled_bin no_flag_bin review_out challenge_out tool_enabled_out no_flag_out tool_enabled_rc no_flag_rc
  tmp_dir="$(mktemp -d)"
  repo_dir="$tmp_dir/repo"
  fake_bin="$tmp_dir/bin"
  tool_enabled_bin="$tmp_dir/tool-enabled-bin"
  no_flag_bin="$tmp_dir/no-flag-bin"
  mkdir -p "$repo_dir" "$fake_bin" "$tool_enabled_bin" "$no_flag_bin"
  cat > "$fake_bin/claude" <<'FAKE_CLAUDE'
#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "-p" ] && [ "${2:-}" = "--help" ]; then
  printf '%s\n' '--print --allowedTools --tools --add-dir --permission-mode --safe-mode --strict-mcp-config --mcp-config --setting-sources --no-session-persistence --output-format --json-schema --verbose --disable-slash-commands --effort'
  exit 0
fi

prompt="$(cat)"
if printf '%s' "$prompt" | grep -F 'Bash tool' >/dev/null; then
  tools_seen=0
  tools_value=__missing__
  mcp_value=__missing__
  settings_value=__missing__
  output_value=__missing__
  safe_mode=0
  strict_mcp=0
  commands_disabled=0
  verbose=0
  pending=""
  for arg in "$@"; do
    if [ -n "$pending" ]; then
      case "$pending" in
        tools) tools_seen=1; tools_value="$arg" ;;
        mcp) mcp_value="$arg" ;;
        settings) settings_value="$arg" ;;
        output) output_value="$arg" ;;
      esac
      pending=""
      continue
    fi
    case "$arg" in
      --tools) pending=tools ;;
      --mcp-config) pending=mcp ;;
      --setting-sources) pending=settings ;;
      --output-format) pending=output ;;
      --safe-mode) safe_mode=1 ;;
      --strict-mcp-config) strict_mcp=1 ;;
      --disable-slash-commands) commands_disabled=1 ;;
      --verbose) verbose=1 ;;
    esac
  done
  if [ "$tools_seen" = "1" ] && [ -z "$tools_value" ] \
    && [ "$mcp_value" = '{"mcpServers":{}}' ] && [ -z "$settings_value" ] \
    && [ "$output_value" = "stream-json" ] && [ "$safe_mode" = "1" ] \
    && [ "$strict_mcp" = "1" ] && [ "$commands_disabled" = "1" ] && [ "$verbose" = "1" ]; then
    printf '%s\n' '{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[]}'
  else
    printf '%s\n' '{"type":"system","subtype":"init","permissionMode":"default","tools":["Bash"],"mcp_servers":[{"name":"inherited"}],"slash_commands":["review"],"skills":["review"],"plugins":["inherited"]}'
  fi
  printf '%s\n' '{"type":"result","subtype":"success","is_error":false,"result":"ok"}'
elif [ "${CLAUDE_REVIEW_WRAPPER_MODE:-}" = "review" ]; then
  printf '%s\n' '{"type":"system","subtype":"init","permissionMode":"default","tools":["StructuredOutput"],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[]}'
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"StructuredOutput","input":{}}]}}'
  printf '%s\n' '{"type":"result","subtype":"success","is_error":false,"terminal_reason":"completed","structured_output":{"mode":"review","findings":[]}}'
else
  printf '%s\n' '{"type":"system","subtype":"init","permissionMode":"default","tools":["StructuredOutput"],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[]}'
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"StructuredOutput","input":{}}]}}'
  printf '%s\n' '{"type":"result","subtype":"success","is_error":false,"terminal_reason":"completed","structured_output":{"mode":"challenge","findings":[]}}'
fi
FAKE_CLAUDE
  chmod +x "$fake_bin/claude"
  cat > "$tool_enabled_bin/claude" <<'FAKE_CLAUDE_TOOL_ENABLED'
#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "-p" ] && [ "${2:-}" = "--help" ]; then
  printf '%s\n' '--print --allowedTools --tools --add-dir --permission-mode --safe-mode --strict-mcp-config --mcp-config --setting-sources --no-session-persistence --output-format --json-schema --verbose --disable-slash-commands --effort'
  exit 0
fi

cat >/dev/null
printf '%s\n' '{"type":"system","subtype":"init","permissionMode":"default","tools":["StructuredOutput","Bash"],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[]}'
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"true"}}]}}'
printf '%s\n' '{"type":"result","subtype":"success","is_error":false,"terminal_reason":"completed","structured_output":{"mode":"review","findings":[]}}'
FAKE_CLAUDE_TOOL_ENABLED
  chmod +x "$tool_enabled_bin/claude"
  cat > "$no_flag_bin/claude" <<'FAKE_CLAUDE_NO_FLAGS'
#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "-p" ] && [ "${2:-}" = "--help" ]; then
  printf '%s\n' '--print --add-dir --permission-mode --safe-mode --strict-mcp-config --mcp-config --setting-sources --disable-slash-commands --no-session-persistence --output-format --json-schema --verbose'
  exit 0
fi

cat >/dev/null
printf '%s\n' '{"type":"result","subtype":"success","is_error":false,"terminal_reason":"completed","structured_output":{"mode":"review","findings":[]}}'
FAKE_CLAUDE_NO_FLAGS
  chmod +x "$no_flag_bin/claude"

  git -C "$repo_dir" init -q
  printf 'before\n' > "$repo_dir/file.txt"
  git -C "$repo_dir" add file.txt
  git -C "$repo_dir" -c user.name='Test User' -c user.email='test@example.invalid' commit -q -m init
  printf 'after\n' > "$repo_dir/file.txt"

  review_out="$(PATH="$fake_bin:$PATH" "$script_dir/claude_review.sh" review --cwd "$repo_dir" --base HEAD --timeout 30 --direct)"
  challenge_out="$(PATH="$fake_bin:$PATH" "$script_dir/claude_review.sh" challenge --cwd "$repo_dir" --base HEAD --timeout 30 --direct)"

  printf '%s\n' "$review_out" | grep -F '"lens_id": "code-review:review:no-tools"' >/dev/null
  printf '%s\n' "$review_out" | grep -F '"tool_identity": "code-review:no-tools"' >/dev/null
  printf '%s\n' "$challenge_out" | grep -F '"lens_id": "code-review:challenge:no-tools-adversarial"' >/dev/null
  printf '%s\n' "$challenge_out" | grep -F '"tool_identity": "code-review:no-tools"' >/dev/null
  set +e
  tool_enabled_out="$(PATH="$tool_enabled_bin:$PATH" "$script_dir/claude_review.sh" review --cwd "$repo_dir" --base HEAD --timeout 30 --direct)"
  tool_enabled_rc=$?
  set -e
  if [ "$tool_enabled_rc" -ne 2 ]; then
    printf 'expected tool-enabled fake review to exit 2, got %s\n' "$tool_enabled_rc" >&2
    return 1
  fi
  printf '%s\n' "$tool_enabled_out" | grep -F '"status"' >/dev/null
  printf '%s\n' "$tool_enabled_out" | grep -F 'inconclusive' >/dev/null
  set +e
  no_flag_out="$(PATH="$no_flag_bin:$PATH" "$script_dir/claude_review.sh" review --cwd "$repo_dir" --base HEAD --timeout 30 --direct)"
  no_flag_rc=$?
  set -e
  if [ "$no_flag_rc" -ne 2 ]; then
    printf 'expected no-allowlist fake review to exit 2, got %s\n' "$no_flag_rc" >&2
    return 1
  fi
  printf '%s\n' "$no_flag_out" | grep -F '"status"' >/dev/null
  printf '%s\n' "$no_flag_out" | grep -F 'inconclusive' >/dev/null
  printf '%s\n' "$no_flag_out" | grep -F 'no no-tool review mode' >/dev/null
  rm -rf "$tmp_dir"
}

run_wrapper_identity_tests

printf 'parse_review_json_tests_ok\n'
