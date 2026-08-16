#!/usr/bin/env bash
# Fake-CLI proof that default OpenCode wrapper calls overlap without a shared
# lock and export only their review sessions.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
WRAPPER="$DIR/opencode_review.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/oc-concurrency-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
fails=0

command -v jq >/dev/null 2>&1 || { echo "FAIL - jq is required"; exit 1; }
mkdir -p "$WORK/bin" "$WORK/state" "$WORK/tmp" "$WORK/source-data/opencode" "$WORK/source-state"
printf '%s\n' '{"deepseek":{"type":"api","key":"test-only"}}' >"$WORK/source-data/opencode/auth.json"
chmod 0600 "$WORK/source-data/opencode/auth.json"

cat >"$WORK/bin/opencode" <<'STUB'
#!/usr/bin/env bash
set -u
state="$STUB_STATE_DIR"
[ -z "${OPENCODE_PURE:-}" ] || touch "$state/pure_mode_forced"
if [ "$1" = "debug" ] && [ "${2:-}" = "agent" ]; then
  model_full="deepseek/deepseek-v4-pro"
  provider="${model_full%%/*}"
  model="${model_full#*/}"
  printf '%s|%s|debug\n' "$XDG_DATA_HOME" "$XDG_STATE_HOME" >>"$state/runtime_paths"
  printf '{"name":"ccl-review","mode":"primary","model":{"providerID":"%s","modelID":"%s"},"tools":{"invalid":true,"question":false,"bash":false,"read":false,"glob":false,"grep":false,"edit":false,"write":false,"task":false,"webfetch":false,"todowrite":false,"skill":false,"ccl_context":false}}\n' \
    "$provider" "$model"
  exit 0
fi
if [ "$1" = "run" ]; then
  project_dir=""
  previous=""
  for arg in "$@"; do
    [ "$previous" = "--dir" ] && project_dir="$arg"
    previous="$arg"
  done
  for prompt in "$@"; do :; done
  auth="$XDG_DATA_HOME/opencode/auth.json"
  case "$XDG_DATA_HOME" in "$project_dir"/*) touch "$state/auth_inside_project" ;; esac
  if [ ! -L "$auth" ] || [ "$(readlink "$auth")" != "$STUB_SOURCE_AUTH" ] \
    || ! cmp -s "$auth" "$STUB_SOURCE_AUTH"; then
    touch "$state/auth_binding_bad"
  fi
  if stat -Lc '%a' "$auth" >/dev/null 2>&1; then
    auth_mode="$(stat -Lc '%a' "$auth")"
  else
    auth_mode="$(stat -Lf '%Lp' "$auth")"
  fi
  [ "$auth_mode" = 600 ] || touch "$state/auth_binding_bad"
  [ -w "$auth" ] || touch "$state/auth_binding_bad"
  printf '%s|%s|run\n' "$XDG_DATA_HOME" "$XDG_STATE_HOME" >>"$state/runtime_paths"
  owner=0
  if mkdir "$state/active" 2>/dev/null; then
    owner=1
  else
    touch "$state/overlap"
  fi
  sleep 1
  [ "$owner" = 1 ] && rmdir "$state/active" 2>/dev/null
  sid="sid-review-$$"
  printf '%s\n' "{\"type\":\"step_start\",\"sessionID\":\"$sid\",\"part\":{\"type\":\"step-start\"}}"
  printf '%s\n' "$XDG_DATA_HOME" >"$state/$sid.data_home"
  exit 0
fi
if [ "$1" = "export" ]; then
  sid="$2"
  printf '%s|%s|export\n' "$XDG_DATA_HOME" "$XDG_STATE_HOME" >>"$state/runtime_paths"
  expected_home="$(cat "$state/$sid.data_home" 2>/dev/null || true)"
  [ "$expected_home" = "$XDG_DATA_HOME" ] || touch "$state/export_runtime_mismatch"
  printf '%s\n' "$sid" >>"$state/exports"
  printf '{"id":"%s","messages":[{"info":{"role":"assistant","modelID":"deepseek-v4-pro","providerID":"deepseek"},"parts":[{"type":"text","text":"NO_BLOCKING_FINDINGS"},{"type":"step-finish","reason":"stop"}]}]}\n' "$sid"
  exit 0
fi
exit 1
STUB
chmod +x "$WORK/bin/opencode"
printf 'diff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -1 +1 @@\n-a\n+b\n' >"$WORK/diff.patch"

run_one() {
  local output="$1"
  env PATH="$WORK/bin:$PATH" TMPDIR="$WORK/tmp" STUB_STATE_DIR="$WORK/state" \
    STUB_SOURCE_AUTH="$WORK/source-data/opencode/auth.json" \
    XDG_DATA_HOME="$WORK/source-data" XDG_STATE_HOME="$WORK/source-state" \
    bash "$WRAPPER" \
    --implementer-family openai \
    --diff-file "$WORK/diff.patch" --timeout 20 >"$output"
}

check() {
  if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fails=$((fails+1)); fi
}
field() { jq -r ".${2}" "$1" 2>/dev/null; }

mkdir "$WORK/tmp/opencode-review.lock"
run_one "$WORK/out1.json" & p1=$!
run_one "$WORK/out2.json" & p2=$!
wait "$p1"; r1=$?
wait "$p2"; r2=$?
check "default calls both complete" '[ "$r1" = 0 ] && [ "$r2" = 0 ]'
check "default calls overlap in the same TMPDIR" '[ -e "$WORK/state/overlap" ]'
check "legacy lock is ignored and never deleted" '[ -d "$WORK/tmp/opencode-review.lock" ]'
check "two unique review sessions are exported once each" '[ "$(wc -l < "$WORK/state/exports" | tr -d " ")" = 2 ] && [ "$(sort -u "$WORK/state/exports" | wc -l | tr -d " ")" = 2 ]'
check "each wrapper uses a distinct private XDG data root" '[ "$(cut -d "|" -f1 "$WORK/state/runtime_paths" | sort -u | wc -l | tr -d " ")" = 2 ]'
check "each wrapper uses a distinct private XDG state root" '[ "$(cut -d "|" -f2 "$WORK/state/runtime_paths" | sort -u | wc -l | tr -d " ")" = 2 ]'
check "private roots do not reuse caller data or state roots" '! rg -q "$WORK/source-(data|state)" "$WORK/state/runtime_paths"'
check "credential runtime stays outside the reviewer project" '[ ! -e "$WORK/state/auth_inside_project" ] && ! rg -q "/oc-review\\.[^|]*/xdg-(data|state)" "$WORK/state/runtime_paths"'
check "run and export stay in the same private runtime" '[ ! -e "$WORK/state/export_runtime_mismatch" ]'
check "private runtime binds auth to the caller's refreshable credential file" '[ ! -e "$WORK/state/auth_binding_bad" ]'
check "caller auth file is unchanged" 'cmp -s "$WORK/source-data/opencode/auth.json" <(printf "%s\n" "{\"deepseek\":{\"type\":\"api\",\"key\":\"test-only\"}}")'
check "result reports private runtime and shared credential binding" '[ "$(field "$WORK/out1.json" runtime_isolation)" = per_invocation_xdg ] && [ "$(field "$WORK/out1.json" credential_binding)" = present_shared_auth_link ]'
check "user-installed plugins are not disabled with forced pure mode" '[ ! -e "$WORK/state/pure_mode_forced" ]'

echo '----'
if [ "$fails" -eq 0 ]; then
  echo opencode_review_concurrency_tests_ok
else
  echo "$fails FAILURES"
  exit 1
fi
