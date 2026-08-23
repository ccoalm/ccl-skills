#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
parser="$script_dir/parse_probe_result.py"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
redacted_path=$'\x3cpath\x3e'

run_ok() {
  local rc="$1" stdout="$2" stderr="${3:-}"
  printf '%s' "$stdout" > "$tmp_dir/stdout"
  printf '%s' "$stderr" > "$tmp_dir/stderr"
  python3 "$parser" "$rc" "$tmp_dir/stdout" "$tmp_dir/stderr" >/dev/null
}

run_reason() {
  local rc="$1" stdout="$2" expected="$3" stderr="${4:-}" out
  printf '%s' "$stdout" > "$tmp_dir/stdout"
  printf '%s' "$stderr" > "$tmp_dir/stderr"
  if out="$(python3 "$parser" "$rc" "$tmp_dir/stdout" "$tmp_dir/stderr")"; then
    printf 'expected probe parser failure for stdout: %s\n' "$stdout" >&2
    return 1
  fi
  if ! printf '%s' "$out" | grep -F "$expected" >/dev/null; then
    printf 'expected reason containing %q but got %s\n' "$expected" "$out" >&2
    return 1
  fi
}

run_reason_excludes() {
  local rc="$1" stdout="$2" forbidden="$3" stderr="${4:-}" out
  printf '%s' "$stdout" > "$tmp_dir/stdout"
  printf '%s' "$stderr" > "$tmp_dir/stderr"
  if out="$(python3 "$parser" "$rc" "$tmp_dir/stdout" "$tmp_dir/stderr")"; then
    printf 'expected probe parser failure for stdout: %s\n' "$stdout" >&2
    return 1
  fi
  if printf '%s' "$out" | grep -F "$forbidden" >/dev/null; then
    printf 'reason must not contain %q but got %s\n' "$forbidden" "$out" >&2
    return 1
  fi
}

run_reason_strict() {
  local rc="$1" stdout="$2" expected="$3" stderr="${4:-}" out
  printf '%s' "$stdout" > "$tmp_dir/stdout"
  printf '%s' "$stderr" > "$tmp_dir/stderr"
  if out="$(python3 "$parser" "$rc" "$tmp_dir/stdout" "$tmp_dir/stderr" --require-empty-init)"; then
    printf 'expected strict probe parser failure for stdout: %s\n' "$stdout" >&2
    return 1
  fi
  if ! printf '%s' "$out" | grep -F "$expected" >/dev/null; then
    printf 'expected strict reason containing %q but got %s\n' "$expected" "$out" >&2
    return 1
  fi
}

run_ok_strict() {
  local rc="$1" stdout="$2" stderr="${3:-}"
  printf '%s' "$stdout" > "$tmp_dir/stdout"
  printf '%s' "$stderr" > "$tmp_dir/stderr"
  python3 "$parser" "$rc" "$tmp_dir/stdout" "$tmp_dir/stderr" --require-empty-init >/dev/null
}

run_ok_expected_tools() {
  local expected_tools="$1" rc="$2" stdout="$3" stderr="${4:-}"
  printf '%s' "$stdout" > "$tmp_dir/stdout"
  printf '%s' "$stderr" > "$tmp_dir/stderr"
  python3 "$parser" "$rc" "$tmp_dir/stdout" "$tmp_dir/stderr" \
    --require-empty-init --expected-tools "$expected_tools" >/dev/null
}

run_ok_expected_tool_use() {
  local expected_tools="$1" rc="$2" stdout="$3" stderr="${4:-}"
  printf '%s' "$stdout" > "$tmp_dir/stdout"
  printf '%s' "$stderr" > "$tmp_dir/stderr"
  python3 "$parser" "$rc" "$tmp_dir/stdout" "$tmp_dir/stderr" \
    --require-empty-init --expected-tools "$expected_tools" --allow-expected-tool-use >/dev/null
}

run_reason_expected_tools_implicit_strict() {
  local expected_tools="$1" rc="$2" stdout="$3" expected="$4" out
  printf '%s' "$stdout" > "$tmp_dir/stdout"
  : > "$tmp_dir/stderr"
  if out="$(python3 "$parser" "$rc" "$tmp_dir/stdout" "$tmp_dir/stderr" \
    --expected-tools "$expected_tools")"; then
    printf 'expected implicit-strict expected-tools parser failure\n' >&2
    return 1
  fi
  printf '%s' "$out" | grep -F "$expected" >/dev/null
}

run_reason_runtime_surface() {
  local expected_tools="$1" rc="$2" stdout="$3" expected="$4" stderr="${5:-}" out
  printf '%s' "$stdout" > "$tmp_dir/stdout"
  printf '%s' "$stderr" > "$tmp_dir/stderr"
  if out="$(python3 "$parser" "$rc" "$tmp_dir/stdout" "$tmp_dir/stderr" \
    --require-empty-init --expected-tools "$expected_tools" --allow-expected-tool-use --runtime-surface-only)"; then
    printf 'expected runtime-surface parser failure\n' >&2
    return 1
  fi
  printf '%s' "$out" | grep -F "$expected" >/dev/null
}

run_ok_runtime_surface() {
  local expected_tools="$1" rc="$2" stdout="$3" stderr="${4:-}"
  printf '%s' "$stdout" > "$tmp_dir/stdout"
  printf '%s' "$stderr" > "$tmp_dir/stderr"
  python3 "$parser" "$rc" "$tmp_dir/stdout" "$tmp_dir/stderr" \
    --require-empty-init --expected-tools "$expected_tools" --allow-expected-tool-use --runtime-surface-only >/dev/null
}

run_ok_expected_native_skills() {
  local expected_native_skills="$1" required_native_skills="$2" rc="$3" stdout="$4"
  local stderr="${5:-}"
  printf '%s' "$stdout" > "$tmp_dir/stdout"
  printf '%s' "$stderr" > "$tmp_dir/stderr"
  python3 "$parser" "$rc" "$tmp_dir/stdout" "$tmp_dir/stderr" \
    --require-empty-init \
    --expected-native-skills "$expected_native_skills" \
    --required-native-skills "$required_native_skills" >/dev/null
}

run_reason_expected_native_skills() {
  local expected_native_skills="$1" required_native_skills="$2" rc="$3" stdout="$4"
  local expected="$5" stderr="${6:-}" out
  printf '%s' "$stdout" > "$tmp_dir/stdout"
  printf '%s' "$stderr" > "$tmp_dir/stderr"
  if out="$(python3 "$parser" "$rc" "$tmp_dir/stdout" "$tmp_dir/stderr" \
    --require-empty-init \
    --expected-native-skills "$expected_native_skills" \
    --required-native-skills "$required_native_skills")"; then
    printf 'expected native-skill probe parser failure\n' >&2
    return 1
  fi
  printf '%s' "$out" | grep -F "$expected" >/dev/null
}

# Runtime-surface variants used to pin the main-invocation drift guard. The
# first omits --allow-expected-tool-use (the wrapper always passes it, so this
# is the guard's defence-in-depth leg); the second exercises the owner-aware
# path, where a permitted-looking customization list can still carry an
# unexpected identifier.
run_reason_runtime_surface_no_tool_use_allowance() {
  local expected_tools="$1" rc="$2" stdout="$3" expected="$4" stderr="${5:-}" out
  printf '%s' "$stdout" > "$tmp_dir/stdout"
  printf '%s' "$stderr" > "$tmp_dir/stderr"
  if out="$(python3 "$parser" "$rc" "$tmp_dir/stdout" "$tmp_dir/stderr" \
    --require-empty-init --expected-tools "$expected_tools" --runtime-surface-only)"; then
    printf 'expected runtime-surface parser failure (no tool-use allowance)\n' >&2
    return 1
  fi
  if printf '%s' "$out" | grep -F 'unrecognized surface-shaped init field' >/dev/null; then
    printf 'drift reason must not launder an unallowed tool_use: %s\n' "$out" >&2
    return 1
  fi
  printf '%s' "$out" | grep -F "$expected" >/dev/null
}

run_reason_runtime_surface_native() {
  local expected_native_skills="$1" rc="$2" stdout="$3" expected="$4" stderr="${5:-}" out
  printf '%s' "$stdout" > "$tmp_dir/stdout"
  printf '%s' "$stderr" > "$tmp_dir/stderr"
  if out="$(python3 "$parser" "$rc" "$tmp_dir/stdout" "$tmp_dir/stderr" \
    --require-empty-init --expected-tools "" --allow-expected-tool-use --runtime-surface-only \
    --expected-native-skills "$expected_native_skills" \
    --required-native-skills "$expected_native_skills")"; then
    printf 'expected owner-aware runtime-surface parser failure\n' >&2
    return 1
  fi
  if printf '%s' "$out" | grep -F 'unrecognized surface-shaped init field' >/dev/null; then
    printf 'drift reason must not launder an unexpected identifier: %s\n' "$out" >&2
    return 1
  fi
  printf '%s' "$out" | grep -F "$expected" >/dev/null
}

run_reason_runtime_surface_implicit_strict() {
  local stdout="$1" expected="$2" out
  printf '%s' "$stdout" > "$tmp_dir/stdout"
  : > "$tmp_dir/stderr"
  if out="$(python3 "$parser" 0 "$tmp_dir/stdout" "$tmp_dir/stderr" --runtime-surface-only)"; then
    printf 'expected implicit-strict runtime-surface parser failure\n' >&2
    return 1
  fi
  printf '%s' "$out" | grep -F "$expected" >/dev/null
}

run_ok 0 'ok'
run_ok 0 'OK'
run_ok 0 $'ok\n'
run_ok 0 'ok' 'benign warning'
run_reason 0 $'banner\nok' 'Claude no-tool probe failed'
run_reason 0 $'Not logged in · Please run /login\nok' 'auth-path false negative'
run_reason 0 $'ok\nfooter' 'Claude no-tool probe failed'
run_reason 0 'ok' 'auth-path false negative' 'Not logged in · Please run /login'
run_ok 0 '{"type":"result","subtype":"success","is_error":false,"terminal_reason":"completed","result":"ok"}'
run_ok 0 '{"type":"result","subtype":"success","is_error":false,"api_error_status":0,"result":"ok"}'
run_ok 0 '{"type":"result","subtype":"completed","is_error":false,"api_error_status":"200","result":"ok"}'
run_reason 0 '{"type":"result","subtype":"success","is_error":false,"api_error_status":"too_many_requests","result":"ok"}' 'quota/rate limit'
run_reason 0 '{"subtype":"success","is_error":false,"result":"ok"}' 'Claude no-tool probe failed'
run_ok 0 '{"type":"result","subtype":"success","is_error":false,"result":"ok"}'
run_ok 0 '{"type":"result","is_error":false,"result":"ok"}'
run_ok 0 '{"type":"result","subtype":"success","is_error":false,"terminal_reason":"stop","result":"ok"}'
run_ok 0 '{"type":"result","subtype":"success","is_error":false,"terminal_reason":"completed","result":"OK"}'
run_ok 0 '{"type":"result","subtype":"success","is_error":false,"structured_output":"ok"}'
run_ok 0 '{"type":"result","subtype":"success","is_error":false,"structured_output":"ok","result":"OK"}'
run_ok 0 '{"type":"result","subtype":"success","is_error":false,"terminal_reason":"completed","result":"The Bash tool is not available to me in this environment, so I cannot run that command.\n\nok","permission_denials":[]}'
run_ok 0 '{"type":"result","subtype":"success","is_error":false,"terminal_reason":"completed","structured_output":"The Bash tool is not available to me in this environment, so I cannot run that command.\n\nok","permission_denials":[]}'
run_ok 0 '{"type":"result","subtype":"success","is_error":false,"terminal_reason":"completed","result":"I'\''ll comply with the user'\''s explicit instructions here.\n\nThe Bash tool is not available to me in this environment, so I cannot run that command.\n\nok","permission_denials":[]}'
run_ok 0 '{"type":"result","subtype":"success","is_error":false,"terminal_reason":"completed","result":"Available tools: none. Bash is not available.\n\nok","permission_denials":[]}'
run_reason 0 '{"type":"result","subtype":"success","is_error":false,"result":"I cannot use the Bash tool here."}' 'Claude no-tool probe failed'
run_reason 0 '{"type":"result","subtype":"success","is_error":false,"result":"TOOL_ENABLED"}' 'Claude no-tool probe failed'
run_reason 0 '{"type":"result","subtype":"success","is_error":false,"result":"The Bash tool is not available here.\nTOOL_ENABLED\nok","permission_denials":[]}' 'Claude no-tool probe failed'
run_reason 0 '{"type":"result","subtype":"success","is_error":false,"result":"I cannot be certain, but available tools: bash\nok","permission_denials":[]}' 'Claude no-tool probe failed'
run_reason 0 '{"type":"result","subtype":"success","is_error":false,"result":"I cannot be certain, but available tools: no idea -- bash, python are available\nok","permission_denials":[]}' 'Claude no-tool probe failed'
run_reason 0 '{"type":"result","subtype":"success","is_error":false,"result":"Available tools: none. Bash is available.\nok","permission_denials":[]}' 'Claude no-tool probe failed'
run_reason 0 '{"type":"result","subtype":"success","is_error":false,"result":"Bash is available, but the Bash tool is not available right now.\nok","permission_denials":[]}' 'Claude no-tool probe failed'
run_reason 0 '{"type":"result","subtype":"success","is_error":false,"result":"The Bash tool is available, but I cannot guarantee output.\nok","permission_denials":[]}' 'Claude no-tool probe failed'
run_reason 0 '{"type":"result","subtype":"success","is_error":false,"result":"The Bash tool is available, but Bash is not available right now.\nok","permission_denials":[]}' 'Claude no-tool probe failed'
run_reason 0 '{"type":"result","subtype":"success","is_error":false,"result":"The Bash tool is not available, but I can use the Bash tool anyway.\nok","permission_denials":[]}' 'Claude no-tool probe failed'
run_reason 0 '{"type":"result","subtype":"success","is_error":false,"result":"The Bash tool is not available, so I used the Bash tool via subprocess.\nok","permission_denials":[]}' 'Claude no-tool probe failed'
run_reason 0 '{"type":"result","subtype":"success","is_error":false,"result":"Bash is not available, but I will use bash anyway.\nok","permission_denials":[]}' 'Claude no-tool probe failed'
run_reason 0 '{"type":"result","subtype":"success","is_error":false,"result":"Bash is not available so I use bash to comply.\nok","permission_denials":[]}' 'Claude no-tool probe failed'
run_reason 0 '{"type":"result","subtype":"success","is_error":false,"result":"Available tools:\n- bash\nok","permission_denials":[]}' 'Claude no-tool probe failed'
run_reason 0 '{"type":"result","subtype":"success","is_error":false,"result":"I am not certain whether I have any tools.\nok","permission_denials":[]}' 'Claude no-tool probe failed'
run_reason 0 '{"type":"result","subtype":"success","is_error":false,"result":"The Bash tool is not available, so here is the listing: README.md scripts main.py\nok","permission_denials":[]}' 'Claude no-tool probe failed'
run_reason 0 '{"type":"result","subtype":"success","is_error":false,"result":"README.md\nscripts\nok","permission_denials":[]}' 'Claude no-tool probe failed'
run_reason 0 '{"type":"result","subtype":"success","is_error":false,"result":"The Bash tool is not available.\nREADME.md\nscripts\nok","permission_denials":[]}' 'Claude no-tool probe failed'
run_reason 0 '{"type":"result","subtype":"success","is_error":false,"result":"I will use the Bash tool now."}' 'Claude no-tool probe failed'
run_reason 0 '{"type":"result","subtype":"success","is_error":false,"payload":{"answer":"ok"}}' 'Claude no-tool probe failed'
run_reason 0 '{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'auth-path false negative' 'Not logged in · Please run /login'
run_ok 0 $'banner\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}'
run_reason 0 $'Not logged in · Please run /login\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'auth-path false negative'
run_ok 0 $'banner\n{\n  "type": "result",\n  "subtype": "success",\n  "is_error": false,\n  "result": "ok"\n}'
run_ok 0 $'banner\n  {"type":"result","subtype":"stop_turn","is_error":false,"errors":[],"result":"ok"}'
run_ok 0 $'{"type":"result","subtype":"success","is_error":false,"result":"ok"}\nusage footer'
run_ok 0 $'{"type":"result","subtype":"success","is_error":false,"result":"ok"}\n{"type":"telemetry","message":"footer"}'
run_reason 0 $'{"type":"result","subtype":"success","is_error":false,"result":"ok"}\n{"type":"telemetry","message":"rate limit exceeded"}' 'quota/rate limit'
run_reason 0 $'{"type":"result","subtype":"error","is_error":true,"result":"boom"}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'error envelope'
run_reason 0 '{"type":"result","subtype":"success","is_error":{"code":5},"result":"ok"}' 'error envelope'
run_reason 0 '{"type":"result","subtype":"success","is_error":["failed"],"result":"ok"}' 'error envelope'
run_reason 0 $'{"type":"result","subtype":"success","is_error":false,"result":"not ok","error":{"message":"Not logged in · Please run /login"}}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'auth-path false negative'
run_reason 0 $'probe failed but echoed {"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'Claude no-tool probe failed'

run_reason 1 'Not logged in · Please run /login' 'auth-path false negative'
run_reason 1 $'Not logged in · Please run /login\n{"type":"telemetry"}' 'auth-path false negative'
run_reason 0 'Not logged in · Please run /login' 'auth-path false negative'
run_reason 0 '{"type":"result","subtype":"success","is_error":false,"result":"Not logged in · Please run /login"}' 'auth-path false negative'
run_reason 0 '{"type":"result","subtype":"success","is_error":false,"result":"Invalid API key"}' 'auth-path false negative'
run_reason 0 '{"type":"result","subtype":"success","is_error":false,"result":"OAuth token expired"}' 'auth-path false negative'
run_reason 1 '401 Unauthorized' 'auth-path false negative'
run_reason 1 'session has ended' 'auth-path false negative'
run_reason 0 '{"type":"result","subtype":"success","is_error":false,"result":"session expired; hit your limit"}' 'auth-path false negative'
run_reason 0 '{"type":"result","subtype":"success","is_error":false,"debug":"Not logged in · Please run /login","result":"not ok"}' 'auth-path false negative'
run_reason 0 '{"type":"result","subtype":"success","is_error":false,"debug":"rate limit exceeded","result":"not ok"}' 'quota/rate limit'
run_reason 1 '{"type":"result","subtype":"error","is_error":true,"result":null,"error":{"message":"Not logged in · Please run /login"}}' 'auth-path false negative'
run_reason 0 '{"type":"result","subtype":"success","is_error":false,"result":"ok","error":{"message":"rate limit exceeded"}}' 'quota/rate limit'
run_reason 1 '{"type":"result","subtype":"success","is_error":false,"api_error_status":429,"result":"Please run /login; rate limit exceeded"}' 'quota/rate limit'
run_reason 1 '{"type":"result","subtype":"success","is_error":false,"api_error_status":"429","result":"Please run /login"}' 'quota/rate limit'
run_reason 1 '{"type":"result","subtype":"success","is_error":false,"api_error_status":401,"result":"unauthorized"}' 'auth-path false negative'
run_reason 1 '{"type":"result","subtype":"success","is_error":false,"api_error_status":401,"result":"rate limit exceeded"}' 'auth-path false negative'
run_reason 1 '{"type":"result","subtype":"success","is_error":false,"api_error_status":403,"result":"forbidden"}' 'permission/API access status 403'
run_reason 1 '{"type":"result","subtype":"success","is_error":false,"result":"credit balance too low"}' 'quota/rate limit'
run_reason 1 '{"type":"result","subtype":"success","is_error":false,"result":"usage limit reached"}' 'quota/rate limit'
run_reason 1 '{"type":"result","subtype":"success","is_error":false,"result":"rate limit exceeded: 50/min"}' '50/min'
run_reason 1 '{"type":"result","subtype":"success","is_error":false,"result":"rate limit exceeded for key=abcdefghijklmnopqrst"}' '<secret>'
run_reason 1 '{"type":"result","subtype":"success","is_error":false,"result":"service unavailable 503"}' 'Claude no-tool probe failed'
run_reason 1 '' '<secret>' 'failed token=abcdefghijklmnopqrst'
run_reason 1 '{"type":"result","subtype":"success","is_error":false,"oauth_token":"abcdefghijklmnopqrst","result":"not ok"}' '<secret>'
run_reason 0 '{"type":"result","subtype":"success","is_error":false,"structured_output":"ok","result":"rate limit exceeded"}' 'quota/rate limit'
run_reason 1 '{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'Claude no-tool probe failed'
run_reason 1 '' 'Claude no-tool probe failed: <path>' '/workspace/project/script failed'
run_reason 1 '' 'inspect local probe stderr' '/workspace/project/script'
run_reason 1 '' 'Claude no-tool probe failed: <path>' '/Applications/Tool/app failed'
run_reason 1 '' 'Claude no-tool probe failed: open:<path>' 'open:/workspace/project/script failed'
run_reason 1 '' 'Claude no-tool probe failed: open <path>' 'open /root failed'
run_reason 1 '' 'Claude no-tool probe failed: open <path>' 'open home/user/.claude/file failed'
run_reason 0 '{"type":"assistant","subtype":"success","is_error":false,"terminal_reason":"completed","result":"ok"}' 'missing the init event'
run_reason 0 '{"type":"result","subtype":"success","is_error":false,"permission_denials":["Read"],"result":"ok"}' 'permission denials'
run_reason 0 '{"type":"result","subtype":"error","is_error":true,"result":"boom"}' 'error envelope'
run_reason 0 '{"type":"result","subtype":"error","is_error":true,"result":"failed at /workspace/example/project/file"}' "error envelope: failed at $redacted_path"
run_reason 0 '{"type":"result","subtype":"success","is_error":"true","result":"ok"}' 'error envelope'
run_reason 0 '{"type":"result","subtype":"success","is_error":false,"api_error_status":500,"result":"ok"}' 'API error status 500'
run_reason 1 '' 'stderr failure text' 'stderr failure text'

# --- stream-json ground-truth path (declared/invoked tools, not the reply token) ---
empty_init='{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[]}'
run_reason_strict 0 'ok' 'missing the required stream-json init evidence'
run_ok_strict 0 "$empty_init"$'\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}'
read_init='{"type":"system","subtype":"init","permissionMode":"default","tools":["Read","Grep","Glob"],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[]}'
run_ok_expected_tools 'Read,Grep,Glob' 0 "$read_init"$'\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}'
run_ok_expected_tool_use 'Read,Grep,Glob' 0 "$read_init"$'\n{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{}}]}}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}'
# Claude Code 2.1.218 exposes these exact host built-ins whenever an explicit
# plugin enables the command registry. They are not plugin-owned commands or
# model tools, so a selected native skill remains valid.
run_ok_expected_native_skills 'testing-strategy' 'testing-strategy' 0 \
  $'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":["ccl-skills:testing-strategy","workflow-launch-exec","ultrareview"],"skills":["testing-strategy"],"plugins":["ccl-skills"]}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}'
# The same owner-aware path remains value-exact: an arbitrary command cannot
# hide beside the two registered host built-ins.
run_reason_expected_native_skills 'testing-strategy' 'testing-strategy' 0 \
  $'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":["ccl-skills:testing-strategy","workflow-launch-exec","ultrareview","unrelated:danger"],"skills":["testing-strategy"],"plugins":["ccl-skills"]}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' \
  'runtime capability surface is not empty'
# A dict-shaped entry is never whole, however allowed its `name` reads. The
# entry hides a sibling key the identifier helper discards, so clearing it on
# the truncated name would accept a customization whose proof was in the part
# that was thrown away. host_entry_is_whole must reject the shape BEFORE the
# allowlist reads it; flipping its non-string branch to True makes this case
# pass, which is exactly the regression this asserts.
run_reason_expected_native_skills 'testing-strategy' 'testing-strategy' 0 \
  $'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":["ccl-skills:testing-strategy","workflow-launch-exec",{"name":"ultrareview","path":"hidden-sibling-value"}],"skills":["testing-strategy"],"plugins":["ccl-skills"]}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' \
  'runtime capability surface is not empty'

# A matching name in either executable surface is still terminal. Built-in UI
# registration never authorizes a tool declaration or invocation.
run_reason_expected_native_skills 'testing-strategy' 'testing-strategy' 0 \
  $'{"type":"system","subtype":"init","permissionMode":"default","tools":["workflow-launch-exec"],"mcp_servers":[],"slash_commands":["ccl-skills:testing-strategy","workflow-launch-exec","ultrareview"],"skills":["testing-strategy"],"plugins":["ccl-skills"]}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' \
  'runtime capability surface is not empty'
run_reason_expected_native_skills 'testing-strategy' 'testing-strategy' 0 \
  $'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":["ccl-skills:testing-strategy","workflow-launch-exec","ultrareview"],"skills":["testing-strategy"],"plugins":["ccl-skills"]}\n{"type":"assistant","message":{"content":[{"type":"tool_use","name":"workflow-launch-exec","input":{}}]}}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' \
  'runtime capability surface is not empty'
run_reason_expected_tools_implicit_strict 'Read,Grep,Glob' 0 'ok' \
  'missing the required stream-json init evidence'
run_reason_runtime_surface '' 0 "$empty_init"$'\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'auth-path false negative' 'Not logged in · Please run /login'
run_reason_runtime_surface '' 0 "$empty_init"$'\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'quota/rate limit' 'rate limit exceeded'
run_reason_runtime_surface '' 0 "$empty_init"$'\n{"type":"result","subtype":"success","is_error":false,"api_error_status":401,"result":"schema unavailable"}' 'auth-path false negative'
run_reason_runtime_surface '' 0 "$empty_init"$'\n{"type":"result","subtype":"success","is_error":false,"api_error_status":429,"result":"schema unavailable"}' 'quota/rate limit'
run_reason_runtime_surface '' 0 $'Not logged in · Please run /login\n'"$empty_init"$'\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'runtime isolation surface is invalid'
run_reason_runtime_surface '' 0 $'rate limit exceeded\n'"$empty_init"$'\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'runtime isolation surface is invalid'
run_reason_runtime_surface '' 0 "$empty_init"$'\n{"type":"result","subtype":"error","is_error":true,"result":"boom"}' 'runtime isolation surface is invalid'
run_reason_runtime_surface '' 0 "$empty_init"$'\n{"type":"result","subtype":"success","is_error":false,"permission_denials":["Read"],"result":"ok"}' 'permission denials'
run_reason_runtime_surface '' 0 $'{\n  "type":"result",\n  "subtype":"success",\n  "is_error":false,\n  "result":"Not logged in; quoted model prose"\n}' 'missing the required stream-json init evidence'
run_reason_runtime_surface_implicit_strict \
  '{"type":"result","subtype":"success","is_error":false,"result":"ok"}' \
  'missing the required stream-json init evidence'
# A valid init without any terminal result event is never sufficient runtime
# evidence, even when every declared capability surface is clean.
run_reason_runtime_surface '' 0 "$empty_init"$'\n{"type":"assistant","message":{"content":[{"type":"text","text":"ok"}]}}' 'runtime isolation surface is invalid'
# Runtime isolation ignores model reply prose, but never structural error fields
# or stderr auth/quota evidence; result parsing owns the reply payload afterward.
run_ok_runtime_surface '' 0 "$empty_init"$'\n{"type":"result","subtype":"success","is_error":false,"result":"Not logged in · Please run /login"}'
# Unknown init field, surface-shaped (non-empty list/dict): could enumerate a
# new invocable surface -> fails closed.
run_reason 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[],"future_capabilities":["x"]}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'unrecognized surface-shaped init field'
run_reason 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[],"future_capabilities":{"enabled":true}}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'unrecognized surface-shaped init field'
# The reason names the offending field so the follow-up is a one-line review.
run_reason 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[],"future_capabilities":["x"]}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'future_capabilities'
# Unknown init field carrying a scalar (or an empty container) is metadata: it
# cannot enumerate a surface, so a routine CLI release does not fail the lane.
run_ok 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[],"future_capability":"enabled"}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}'
run_ok 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[],"future_capability":false}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}'
run_ok 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[],"future_capability":0}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}'
run_ok 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[],"future_capability":null}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}'
run_ok 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[],"future_capabilities":[]}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}'
run_ok 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[],"future_capabilities":{}}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}'
run_ok 0 $'{"type":"system","subtype":"init","tools":[],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[],"permissionMode":"default"}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}'
run_ok_expected_tools 'Read,Grep,Glob' 0 $'{"type":"system","subtype":"init","tools":["Read","Grep","Glob"],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[],"permissionMode":"plan"}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}'
# permissionMode stays value-pinned: it changes what the runtime may do without
# any tool being added. It must report as a BREACHED boundary, not as schema
# drift — the drift class is fallback-eligible in claude_review.sh, so routing a
# real privilege escalation through it would downgrade "stop the lane" to "try
# another client".
# Authority must be STATED, not merely benign. An init that stops reporting it
# is unverifiable, not permissive — otherwise a CLI that renames the knob makes
# the old name vanish and the drift policy waves the new scalar through.
# Unverifiable, though, is NOT a proven breach: it reports in the
# fallback-eligible class, because terminalizing a rename would reproduce the
# very outage this landing removes. Only a KNOWN field with a KNOWN-unsafe value
# is terminal.
run_reason 0 $'{"type":"system","subtype":"init","tools":[],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[]}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'authority is no longer verifiable'
# A renamed knob loses the required field AND trips the authority-name guard;
# both land in the same unverifiable-authority class.
run_reason 0 $'{"type":"system","subtype":"init","tools":[],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[],"permission_mode":"bypassPermissions"}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'authority is no longer verifiable'
# An ADDED authority knob keeps the required field, so it is the name guard that
# has to catch it — scalar shape and all.
run_reason 0 $'{"type":"system","subtype":"init","tools":[],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[],"permissionMode":"default","dangerously_skip_permissions":true}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'authority: dangerously_skip_permissions'
# ...but a neutral unknown scalar is still tolerated: the guard must not have
# quietly re-pinned the schema it was added to keep open.
run_ok 0 $'{"type":"system","subtype":"init","tools":[],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[],"permissionMode":"default","future_render_mode":"compact"}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}'
bypass_init=$'{"type":"system","subtype":"init","tools":[],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[],"permissionMode":"bypassPermissions"}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}'
run_reason 0 "$bypass_init" 'unsafe runtime capability value on permissionMode'
# ...and it must NOT carry the drift phrase, which routes to fallback.
run_reason_excludes 0 "$bypass_init" 'unrecognized surface-shaped init field'
# `agents` is shape-checked only: an agent is unreachable without the Agent tool,
# which the `tools` allowlist already pins, so a new built-in agent name in a CLI
# release must not take the lane down.
run_ok 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[],"agents":["Explore"]}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}'
run_ok 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[],"agents":["FutureAgent"]}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}'
# ...but a non-string member or non-list shape is an unverifiable descriptor
# schema and still fails closed.
run_reason 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[],"agents":[{"name":"FutureAgent"}]}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'unrecognized surface-shaped init field'
run_reason 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[],"agents":"Explore"}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'unrecognized surface-shaped init field'
# A known scalar metadata field that turns container-shaped is still suspicious.
run_reason 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[],"cwd":{"path":"workspace"}}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'unrecognized surface-shaped init field'
# `capabilities` (CLI 2.1.207+) announces host stream-protocol features, not
# model-invocable surfaces, so it is shape-checked without a value vocabulary:
# any list of strings passes; a non-string element or non-list shape fails.
run_ok 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[],"capabilities":["interrupt_receipt_v1","msg_lifecycle_v1"]}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}'
run_ok 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[],"capabilities":["interrupt_receipt_v1"]}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}'
run_ok 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[],"capabilities":[]}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}'
# THE regression: CLI 2.1.220 added the `interrupt_cancel_queued_v1` capability
# token and the `fast_mode_disabled_reason` field. Under the old value-exact
# whitelist both made every Claude lane inconclusive on a fully isolated run.
run_ok 0 $'{"type":"system","subtype":"init","tools":[],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[],"agents":["claude","Explore","general-purpose","Plan"],"capabilities":["interrupt_receipt_v1","interrupt_cancel_queued_v1","msg_lifecycle_v1"],"claude_code_version":"2.1.220","fast_mode_state":"off","fast_mode_disabled_reason":"sdk_opt_in_required","permissionMode":"default","output_style":"default","apiKeySource":"none","analytics_disabled":false,"product_feedback_disabled":false,"model":"claude-opus-5[1m]","cwd":"/tmp/x","session_id":"s","uuid":"u"}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}'
# A future protocol token passes on shape alone. Deliberately a neutral name:
# the fixture must not read as blessing a capability that claims tool execution
# — if such a token ever appears, the `tools` allowlist and tool_use scan are
# what refuse it, and the token itself would warrant its own review.
run_ok 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[],"capabilities":["future_protocol_v1"]}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}'
run_reason 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[],"capabilities":[{"name":"interrupt_receipt_v1"}]}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'unrecognized surface-shaped init field'
run_reason 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[],"capabilities":{"interrupt_receipt_v1":true}}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'unrecognized surface-shaped init field'
run_reason 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[],"capabilities":"interrupt_receipt_v1"}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'unrecognized surface-shaped init field'
# duplicate JSON keys must not launder a value behind a clean last occurrence:
# a duplicate-key record is malformed stream evidence regardless of vocabulary.
run_reason 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[],"capabilities":["tool_exec_v1"],"capabilities":[]}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'malformed stream-json record'
# strict mode keeps the same verdicts for the drift-tolerant fields.
run_ok_strict 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[],"capabilities":["interrupt_receipt_v1","interrupt_cancel_queued_v1"],"fast_mode_disabled_reason":"sdk_opt_in_required"}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}'
run_reason_strict 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[],"capabilities":[{"name":"tool_exec_v1"}]}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'unrecognized surface-shaped init field'
# The load-bearing proof is untouched: a declared tool or an invoked tool still
# fails even when every drift-tolerant field looks routine.
run_reason 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":["Bash"],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[],"capabilities":["interrupt_cancel_queued_v1"],"fast_mode_disabled_reason":"sdk_opt_in_required"}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'the no-tool sandbox is not enforced'
run_reason 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":["Write"],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[],"capabilities":["interrupt_cancel_queued_v1"],"fast_mode_disabled_reason":"sdk_opt_in_required"}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'runtime capability surface is not empty'
run_reason 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[],"fast_mode_disabled_reason":"sdk_opt_in_required"}\n{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{}}]}}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'runtime capability surface is not empty'
# Drift + a real breach in the same init must report as the BREACH. Review round
# 4 suspected `unexpected_customization_identifiers` was missing from the
# main-path `runtime_drift_only` guard; it stays out because every identifier it
# reports lands in a set that IS in the guard, and these fixtures pin that so the
# soft drift reason can never launder a combined case. Note which set: an
# identifier that is provably a customization marks its field non-empty, while a
# bare host-vocabulary name lands in the unclassifiable set instead — so the
# fixtures below use a NAMESPACED foreign identifier, which is the one that is
# still a proven breach.
run_reason_runtime_surface '' 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":[],"skills":["some-skill"],"plugins":[],"future_surface":["x"]}\n{"type":"result","subtype":"success","is_error":false,"terminal_reason":"completed","structured_output":{"mode":"challenge","findings":[]}}' 'runtime isolation surface is invalid'
run_reason_runtime_surface '' 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":[],"skills":["some-skill"],"plugins":[],"future_surface":["x"]}\n{"type":"result","subtype":"success","is_error":false,"terminal_reason":"completed","structured_output":{"mode":"challenge","findings":[]}}' 'unexpected_customizations=skills'
# ...and the main-path guard must match the probe path's breach set exactly.
# A tool_use with no allowance, and an unexpected identifier under an owner-aware
# run, are the two legs where the two guards could silently diverge again.
run_reason_runtime_surface_no_tool_use_allowance 'Write' 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":["Write"],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[],"future_surface":["x"]}\n{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{}}]}}\n{"type":"result","subtype":"success","is_error":false,"terminal_reason":"completed","structured_output":{"mode":"challenge","findings":[]}}' 'runtime isolation surface is invalid'
run_reason_runtime_surface_native 'testing-strategy' 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":["ccl-skills:testing-strategy"],"skills":["testing-strategy","other-plugin:unrelated-skill"],"plugins":["ccl-skills"],"future_surface":["x"]}\n{"type":"result","subtype":"success","is_error":false,"terminal_reason":"completed","structured_output":{"mode":"challenge","findings":[]}}' 'unexpected_customization_identifiers=skills:other-plugin:unrelated-skill'
# The same fixture with a BARE unknown skill is deliberately the other verdict:
# it reports the soft class, because a bare name outside the built-in snapshot is
# not proof of a customization. Pinned explicitly so the split above is asserted
# rather than merely allowed by the fixture's choice of identifier. `future_surface`
# is dropped here on purpose — with schema drift also present the reason is the
# broader drift phrase, which this helper forbids by design; that combined case is
# pinned in the policy matrix instead.
run_reason_runtime_surface_native 'testing-strategy' 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":["ccl-skills:testing-strategy"],"skills":["testing-strategy","unrelated-skill"],"plugins":["ccl-skills"]}\n{"type":"result","subtype":"success","is_error":false,"terminal_reason":"completed","structured_output":{"mode":"challenge","findings":[]}}' 'unclassifiable_host_vocabulary=skills:unrelated-skill'
# Same rule on the probe path: drift alongside a declared surface, an unexpected
# tool, or a tool_use must report the BREACH. The drift phrase routes to
# fallback, so reaching it first would launder a real breach.
combo_drift_breach=$'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":[],"skills":["some-skill"],"plugins":[],"future_surface":["x"]}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}'
run_reason 0 "$combo_drift_breach" 'runtime capability surface is not empty'
run_reason_excludes 0 "$combo_drift_breach" 'unrecognized surface-shaped init field'
combo_drift_tool=$'{"type":"system","subtype":"init","permissionMode":"default","tools":["Write"],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[],"future_surface":["x"]}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}'
run_reason_excludes 0 "$combo_drift_tool" 'unrecognized surface-shaped init field'
combo_drift_use=$'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[],"future_surface":["x"]}\n{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{}}]}}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}'
run_reason_excludes 0 "$combo_drift_use" 'unrecognized surface-shaped init field'
# A declared CCL skill/plugin surface is still rejected under drift tolerance.
run_reason 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":[],"skills":["some-skill"],"plugins":[],"fast_mode_disabled_reason":"sdk_opt_in_required"}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'runtime capability surface is not empty'
# THE flakiness fix: model hallucinates TOOL_ENABLED but every runtime surface is empty -> pass.
run_ok 0 "$empty_init"$'\n{"type":"result","subtype":"success","is_error":false,"num_turns":1,"permission_denials":[],"result":"TOOL_ENABLED"}'
# clean ok via stream -> pass.
run_ok 0 "$empty_init"$'\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}'
# Missing runtime-surface fields are unverifiable, not equivalent to empty.
run_reason 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":[]}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'missing required isolation fields'
# Any declared tool or inherited customization surface fails closed.
run_reason 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":["Read"],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[]}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'runtime capability surface is not empty'
# A changed tool-descriptor shape must not be silently dropped into an empty
# declared set; unknown/non-string elements make init ground truth invalid.
run_reason 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":[{"name":"Bash"}],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[]}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'missing required isolation fields'
run_reason 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[{"name":"x"}],"slash_commands":[],"skills":[],"plugins":[]}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'runtime capability surface is not empty'
run_reason 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":["review"],"skills":[],"plugins":[]}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'runtime capability surface is not empty'
run_reason 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":[],"skills":["review"],"plugins":[]}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'runtime capability surface is not empty'
run_reason 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":[],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":["x"]}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'runtime capability surface is not empty'
# closes the latent false-negative: Bash DECLARED in init.tools, reply says ok -> fail.
run_reason 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":["Bash","Read"],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[]}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'Bash tool is available'
# Bash actually INVOKED via tool_use block -> fail (sandbox not enforced).
run_reason 0 "$empty_init"$'\n{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{}}]}}\n{"type":"result","subtype":"success","is_error":false,"num_turns":2,"result":"TOOL_ENABLED"}' 'Bash tool is available'
# Any non-Bash tool_use is also a hard fail.
run_reason 0 "$empty_init"$'\n{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Read","input":{}}]}}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'runtime capability surface is not empty'
# A malformed tool_use name is still evidence that a tool invocation occurred;
# missing/non-string names must fail closed instead of disappearing.
run_reason 0 "$empty_init"$'\n{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","input":{}}]}}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'runtime capability surface is not empty'
run_reason 0 "$empty_init"$'\n{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":{"value":"Bash"},"input":{}}]}}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'runtime capability surface is not empty'
# ground-truth does not override auth/quota: 401 in a stream envelope still classifies auth.
run_reason 0 "$empty_init"$'\n{"type":"result","subtype":"success","is_error":false,"api_error_status":401,"result":"ok"}' 'auth-path false negative'
# ground-truth does not override permission denials.
run_reason 0 "$empty_init"$'\n{"type":"result","subtype":"success","is_error":false,"permission_denials":["Read"],"result":"ok"}' 'permission denials'
# A non-Bash MCP-like tool name is still a forbidden declared tool.
run_reason 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":["mcp__bashful__run"],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[]}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'runtime capability surface is not empty'
# false-negative hardening (codex review):
# P1a: Bash tool_use with NO init event + clean ok reply must still fail.
run_reason 0 $'{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{}}]}}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'Bash tool is available'
# P1b: malformed stream record after an init must fail closed, not pass on the ok reply.
run_reason 0 "$empty_init"$'\n{"type":"assistant", BROKEN_RECORD\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'ground-truth is unverifiable'
# confirmed stream (valid init) with a Bash tool_use line that lost its leading
# '{' must fail closed: in a real stream every line is JSON, so a non-JSON line
# is a dropped/corrupt record that may have hidden the Bash call.
run_reason 0 "$empty_init"$'\n"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{}}]}}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'ground-truth is unverifiable'
# stream-json with NO init event (e.g. dropped) must fail closed, not pass on ok.
run_reason 0 $'{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"ok"}]}}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'missing the init event'
# a plain single envelope with a trailing telemetry object is NOT stream-json -> still passes.
run_ok 0 $'{"type":"result","subtype":"success","is_error":false,"result":"ok"}\n{"type":"telemetry","message":"footer"}'
# P1b': the init record ITSELF malformed must fail closed (don't fall to text fallback).
run_reason 0 $'{"type":"system","subtype":"init","permissionMode":"default","tools":["Bash"] BROKEN\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'ground-truth is unverifiable'
# P2: a later init declaring Bash must not be masked by an earlier empty init.
run_reason 0 "$empty_init"$'\n{"type":"system","subtype":"init","permissionMode":"default","tools":["Bash"],"mcp_servers":[],"slash_commands":[],"skills":[],"plugins":[]}\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}' 'Bash tool is available'
# pretty-printed single envelope (bare-brace lines) must still pass via the text fallback.
run_ok 0 $'{\n  "type": "result",\n  "subtype": "success",\n  "is_error": false,\n  "result": "ok"\n}'

# --- host vocabulary is unverifiable, not a proven breach -------------------
# The review-skill invocation is the only shape whose customization lists are
# populated by the host's own built-ins, so a name this repo's snapshot does not
# know cannot be shown to be a user customization. It must refuse WITHOUT
# terminating the lane; anything that IS provably a customization must not
# inherit that softer class. `product-rd-workflow` is used as the selected skill
# because a name that is also a built-in skill trips the ambiguous-owner guard
# and would mask the verdict under test.
native_vocab_result=$'\n{"type":"result","subtype":"success","is_error":false,"result":"ok"}'
native_vocab_init() {
  printf '{"type":"system","subtype":"init","permissionMode":"default","tools":%s,"mcp_servers":[],"slash_commands":%s,"skills":%s,"plugins":[{"name":"ccl-skills"}]}' \
    "${1:-[]}" "${2:-[\"init\",\"agents\"]}" "${3:-[\"ccl-skills:product-rd-workflow\",\"dataviz\"]}"
}
run_reason_native_excludes() {
  local stdout="$1" forbidden="$2" expected="$3" out
  printf '%s' "$stdout" > "$tmp_dir/stdout"
  : > "$tmp_dir/stderr"
  if out="$(python3 "$parser" 0 "$tmp_dir/stdout" "$tmp_dir/stderr" \
    --require-empty-init \
    --expected-native-skills product-rd-workflow \
    --required-native-skills product-rd-workflow)"; then
    printf 'expected native-skill parser failure for stdout: %s\n' "$stdout" >&2
    return 1
  fi
  if printf '%s' "$out" | grep -F "$forbidden" >/dev/null; then
    printf 'a proven customization must not report as %q: %s\n' "$forbidden" "$out" >&2
    return 1
  fi
  printf '%s' "$out" | grep -F "$expected" >/dev/null
}
# the base itself is accepted, or none of the rows below prove anything
run_ok_expected_native_skills product-rd-workflow product-rd-workflow 0 \
  "$(native_vocab_init)$native_vocab_result"
# a built-in the snapshot has not caught up with, in either host-vocabulary field
run_reason_expected_native_skills product-rd-workflow product-rd-workflow 0 \
  "$(native_vocab_init '[]' '["init","agents","brand-new-builtin"]')$native_vocab_result" \
  'unclassifiable host-vocabulary entry'
run_reason_expected_native_skills product-rd-workflow product-rd-workflow 0 \
  "$(native_vocab_init '[]' '["init"]' '["ccl-skills:product-rd-workflow","brand-new-skill"]')$native_vocab_result" \
  'unclassifiable host-vocabulary entry'
# ...and the identifier is named, so the follow-up is a one-liner
run_reason_expected_native_skills product-rd-workflow product-rd-workflow 0 \
  "$(native_vocab_init '[]' '["init","brand-new-builtin"]')$native_vocab_result" \
  'slash_commands:brand-new-builtin'
# A NAMESPACED entry proves a surface beyond the one expected plugin; a
# path-shaped or unparseable identifier proves nothing about host origin; a
# duplicate is a spoofing signal. All four stay terminal.
run_reason_native_excludes \
  "$(native_vocab_init '[]' '["init","evil-plugin:pwn"]')$native_vocab_result" \
  'unclassifiable host-vocabulary' 'runtime capability surface is not empty'
run_reason_native_excludes \
  "$(native_vocab_init '[]' '["init","dir/cmd"]')$native_vocab_result" \
  'unclassifiable host-vocabulary' 'runtime capability surface is not empty'
run_reason_native_excludes \
  "$(native_vocab_init '[]' '["init","ev!l"]')$native_vocab_result" \
  'unclassifiable host-vocabulary' 'runtime capability surface is not empty'
run_reason_native_excludes \
  "$(native_vocab_init '[]' '["init","init"]')$native_vocab_result" \
  'unclassifiable host-vocabulary' 'runtime capability surface is not empty'
# The softer class must never absorb a real breach that happens alongside it.
run_reason_native_excludes \
  "$(native_vocab_init '["Write"]' '["init","brand-new-builtin"]')$native_vocab_result" \
  'unclassifiable host-vocabulary' 'runtime capability surface is not empty'
# Same policy on the main-invocation path, with the identifier in the detail
# fields so an operator can see which name drifted.
run_reason_runtime_surface_native product-rd-workflow 0 \
  "$(native_vocab_init '[]' '["init","brand-new-builtin"]')$native_vocab_result" \
  'unclassifiable host-vocabulary entry'
run_reason_runtime_surface_native product-rd-workflow 0 \
  "$(native_vocab_init '[]' '["init","brand-new-builtin"]')$native_vocab_result" \
  'unclassifiable_host_vocabulary=slash_commands:brand-new-builtin'

printf 'parse_probe_result_tests_ok\n'
