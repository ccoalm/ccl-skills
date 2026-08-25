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
expect_token '{"type":"result","subtype":"success","is_error":true,"result":"Failed to authenticate. API Error: 401 OAuth access token has expired. Re-authenticate to continue."}' auth
expect_token '{"type":"result","subtype":"success","is_error":true,"result":"  \r\nFailed to authenticate. API Error: 401 OAuth access token has expired."}' auth
expect_token '{"type":"result","subtype":"success","is_error":false,"api_error_status":401,"result":"authentication rejected"}' auth
# String-serialized transport status. A bare `== 401` matches only an int, so this
# shape used to fall through BOTH arms and land on the generic `error:success`
# token — the exact false negative this change removes. Pinned per status so the
# normalization cannot be dropped for one arm while the other keeps its fixture.
expect_token '{"type":"result","subtype":"success","is_error":false,"api_error_status":"401","result":"authentication rejected"}' auth
expect_token '{"type":"result","subtype":"success","is_error":false,"api_error_status":"429","result":"slow down"}' quota:
# A non-numeric status is not a status: it must not be coerced into either arm.
expect_token '{"type":"result","subtype":"error","is_error":true,"api_error_status":"unauthorized","result":"boom"}' error:
# Nor is a bool or a float. `int(True)` is 1 and `int(401.9)` truncates to 401,
# so a permissive coercion would let a value that is not a status code select the
# auth arm — pinned in both directions rather than left to the reader.
expect_token '{"type":"result","subtype":"error","is_error":true,"api_error_status":true,"result":"boom"}' error:
expect_token '{"type":"result","subtype":"error","is_error":true,"api_error_status":401.9,"result":"boom"}' error:
# The TEXT arm deliberately still requires an errored envelope, while the
# STRUCTURED arm does not. The asymmetry is the trust boundary: `api_error_status`
# is a transport field, `result` is model-controlled, so payload prose needs a
# second signal before it can select an auth decision. A challenge argued this
# shape reproduces the observed `error:success` defect; it does not — it exits 3
# ("envelope present, nothing classifiable"), a different path the caller is
# already told not to raw-text grep. Pinned so the boundary is a decision on
# record rather than an accident, in both directions.
expect_clean '{"type":"result","subtype":"success","is_error":false,"result":"Failed to authenticate. API Error: 401 OAuth access token has expired."}'
expect_token '{"type":"result","subtype":"error","is_error":true,"result":"P1: authentication failed when the reviewed session expires"}' error:
expect_token '{"type":"result","subtype":"error","is_error":true,"result":"Failed to authenticate after a dependency timeout. API Error: 500"}' error:
expect_token '{"type":"result","subtype":"error","is_error":true,"result":"review preamble\nFailed to authenticate. API Error: 401 OAuth access token has expired."}' error:
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
