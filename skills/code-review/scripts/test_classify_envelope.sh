#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
classifier="$script_dir/classify_envelope.py"

# expect_token PAYLOAD EXPECTED_PREFIX: classifier exits 0 and prints a token
# starting with EXPECTED_PREFIX.
expect_token() {
  local payload="$1" expected="$2" out
  if ! out="$(printf '%s' "$payload" | python3 "$classifier")"; then
    printf 'expected classification (exit 0) for: %s\n' "$payload" >&2
    return 1
  fi
  case "$out" in
    "$expected"*) ;;
    *)
      printf 'expected token prefix %q but got %q for: %s\n' "$expected" "$out" "$payload" >&2
      return 1 ;;
  esac
}

# expect_clean PAYLOAD: classifier exits 3 because JSON was present but no
# error was classified. The caller must not raw-text grep this payload.
expect_clean() {
  local payload="$1"
  set +e
  printf '%s' "$payload" | python3 "$classifier" >/dev/null 2>&1
  local rc=$?
  set -e
  if [ "$rc" -ne 3 ]; then
    printf 'expected clean-envelope exit 3 for: %s\n' "$payload" >&2
    return 1
  fi
}

# expect_no_envelope PAYLOAD: classifier exits 1, so the caller may use its
# startup stderr/text fallback.
expect_no_envelope() {
  local payload="$1"
  set +e
  printf '%s' "$payload" | python3 "$classifier" >/dev/null 2>&1
  local rc=$?
  set -e
  if [ "$rc" -ne 1 ]; then
    printf 'expected no-envelope exit 1 for: %s\n' "$payload" >&2
    return 1
  fi
}

expect_token '{"type":"result","subtype":"error","is_error":true,"result":"Not logged in. Please run /login"}' auth
expect_token '{"type":"result","subtype":"error","is_error":true,"result":"API Error: rate limit exceeded"}' quota:
expect_token '{"type":"result","subtype":"success","is_error":false,"api_error_status":429,"result":"slow down"}' quota:
expect_token '{"type":"result","subtype":"success","is_error":false,"permission_denials":["Read"],"result":""}' permission_denied
expect_token $'{"type":"system","subtype":"init","permissionMode":"default","tools":[]}\n{"type":"result","subtype":"success","is_error":false,"permission_denials":["Read"],"result":""}' permission_denied
expect_token '{"type":"result","subtype":"error_during_execution","is_error":false,"result":"boom"}' error:error_during_execution
expect_token '{"type":"result","subtype":"error_max_turns","is_error":false,"result":""}' error:error_max_turns

# A clean success envelope is not an error -> passthrough (handled by parser).
expect_clean '{"type":"result","subtype":"success","is_error":false,"permission_denials":[],"structured_output":{"mode":"challenge","findings":[]}}'
expect_clean '{"type":"result","subtype":"success","is_error":false,"result":"The reviewed code mentions rate limit exceeded and not logged in."}'
# Bare review JSON (no envelope) -> passthrough.
expect_clean '{"mode":"challenge","findings":[]}'
# Non-JSON prose -> passthrough (caller does the stderr text fallback).
expect_no_envelope 'Not logged in'
expect_no_envelope ''

printf 'classify_envelope_tests_ok\n'
