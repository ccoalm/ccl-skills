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
# Twin of the 429 row for the status the envelope classifier now maps to `auth`.
# The ordering between this parser and that classifier is what decides whether a
# transport-flagged envelope can still be read as a completed verdict, and until
# now only 429 pinned it. Pinned here rather than left to prose: an envelope
# carrying ANY api_error_status is not a clean verdict, so adding an auth arm
# downstream cannot turn one into a verdict-dropping regression unnoticed.
run_fail challenge '{"type":"result","subtype":"success","is_error":false,"api_error_status":401,"terminal_reason":"completed","structured_output":{"mode":"challenge","findings":[]}}'
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
  # One flag per line with its description, because the wrapper reads more than
  # the flag NAMES out of this text: it also has to prove from --safe-mode's own
  # description that safe mode disables inherited skills. A flat space-separated
  # list carries every name and no description, so the wrapper can never clear
  # that gate and every case below dies on a capability_missing exit before its
  # own assertion runs.
  printf '%s\n' \
    '  --print' \
    '  --allowedTools <tools...>' \
    '  --tools <tools...>' \
    '  --add-dir <dirs...>' \
    '  --permission-mode <mode>' \
    '  --safe-mode  Start with all customizations' \
    '               (CLAUDE.md, skills, plugins, hooks, MCP servers,' \
    '               custom commands and agents) disabled' \
    '  --strict-mcp-config' \
    '  --mcp-config <config>' \
    '  --setting-sources <sources>' \
    '  --no-session-persistence' \
    '  --output-format <format>' \
    '  --json-schema <schema>' \
    '  --verbose' \
    '  --disable-slash-commands' \
    '  --effort <level>'
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
  # Same flag set as the no-tools fake, and the same reason for the per-line
  # shape: this fake must be rejected for advertising a Bash tool in its init,
  # not for a help text the wrapper cannot read a description out of.
  printf '%s\n' \
    '  --print' \
    '  --allowedTools <tools...>' \
    '  --tools <tools...>' \
    '  --add-dir <dirs...>' \
    '  --permission-mode <mode>' \
    '  --safe-mode  Start with all customizations' \
    '               (CLAUDE.md, skills, plugins, hooks, MCP servers,' \
    '               custom commands and agents) disabled' \
    '  --strict-mcp-config' \
    '  --mcp-config <config>' \
    '  --setting-sources <sources>' \
    '  --no-session-persistence' \
    '  --output-format <format>' \
    '  --json-schema <schema>' \
    '  --verbose' \
    '  --disable-slash-commands' \
    '  --effort <level>'
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
  # Deliberately advertises NO --tools / --allowedTools: this fake exists to be
  # rejected for having no no-tool review mode. Everything else, --safe-mode's
  # description included, is present so that rejection stays attributable to the
  # missing allowlist flag and cannot be satisfied by an earlier gate instead.
  printf '%s\n' \
    '  --print' \
    '  --add-dir <dirs...>' \
    '  --permission-mode <mode>' \
    '  --safe-mode  Start with all customizations' \
    '               (CLAUDE.md, skills, plugins, hooks, MCP servers,' \
    '               custom commands and agents) disabled' \
    '  --strict-mcp-config' \
    '  --mcp-config <config>' \
    '  --setting-sources <sources>' \
    '  --disable-slash-commands' \
    '  --no-session-persistence' \
    '  --output-format <format>' \
    '  --json-schema <schema>' \
    '  --verbose'
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
  # WHICH inconclusive. `inconclusive` alone is reached by every capability gate
  # ahead of the tool boundary, so this case passed for years without ever
  # exercising what it is named for: a stale fake help text stopped the wrapper
  # at safe-mode capability detection, and the assertion could not tell that
  # apart from the tool-boundary rejection it exists to prove. Pin the reason.
  # Explicit checks rather than bare greps under `set -e`: a failing grep here
  # kills the suite with no output at all, which is exactly the silent-exit-2
  # failure mode that let this file rot in the first place.
  if ! printf '%s\n' "$tool_enabled_out" | grep -F '"reason_code": "tool_boundary_violation"' >/dev/null; then
    printf 'expected tool-enabled fake to be rejected by the TOOL BOUNDARY; got: %s\n' \
      "$tool_enabled_out" >&2
    return 1
  fi
  if ! printf '%s\n' "$tool_enabled_out" | grep -F 'declared_tools=bash,structuredoutput' >/dev/null; then
    printf 'expected the tool-boundary rejection to name the declared tool set; got: %s\n' \
      "$tool_enabled_out" >&2
    return 1
  fi
  if printf '%s\n' "$tool_enabled_out" | grep -F 'capability_missing' >/dev/null; then
    printf 'tool-enabled fake was rejected by a capability gate, not the tool boundary: %s\n' \
      "$tool_enabled_out" >&2
    return 1
  fi
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
  # Same discipline on this one: it must be the MISSING ALLOWLIST FLAG that
  # rejects it, so its help text carries everything the later gates need and a
  # regression there cannot masquerade as this case still passing.
  if ! printf '%s\n' "$no_flag_out" | grep -F '"reason_code": "capability_missing"' >/dev/null; then
    printf 'expected no-allowlist fake to report capability_missing; got: %s\n' "$no_flag_out" >&2
    return 1
  fi
  if printf '%s\n' "$no_flag_out" | grep -F 'safe mode' >/dev/null; then
    printf 'no-allowlist fake was rejected by the safe-mode gate, not the missing --tools flag: %s\n' \
      "$no_flag_out" >&2
    return 1
  fi
  rm -rf "$tmp_dir"
}

run_wrapper_identity_tests

printf 'parse_review_json_tests_ok\n'
