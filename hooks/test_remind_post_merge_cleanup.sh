#!/usr/bin/env bash
# Deterministic behavior suite for hooks/remind-post-merge-cleanup.sh.
# Self-contained: feeds constructed PostToolUse JSON to the reminder hook and
# asserts the REMIND set emits additionalContext and the QUIET set emits none.
# Registered in the Makefile `test` target; requires jq (the hook's dependency —
# without jq the hook degrades to silence, so this suite requires it and fails
# loudly instead of false-greening).
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
HOOK="$SCRIPT_DIR/remind-post-merge-cleanup.sh"
[ -f "$HOOK" ] || { echo "FAIL: hook not found: $HOOK" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq required for this suite" >&2; exit 1; }

pass=0; fail=0

# probe <expect remind|quiet> <command> [tool_response]
probe() {
  local expect="$1" cmd="$2" resp="${3:-merged}" out got
  out=$(jq -nc --arg c "$cmd" --arg r "$resp" \
        '{tool_input:{command:$c},tool_response:$r,cwd:"/tmp"}' | bash "$HOOK")
  got="quiet"
  printf '%s' "$out" | grep -q '"additionalContext"' && got="remind"
  if [ "$got" = "$expect" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1)); printf 'FAIL  [want=%s got=%s]  %s\n' "$expect" "$got" "$cmd" >&2
  fi
}

# probe_json <expect remind|quiet> <command> <raw-json tool_response>
# For structured tool results (exit_code / is_error / interrupted).
probe_json() {
  local expect="$1" cmd="$2" rj="$3" out got
  out=$(jq -nc --arg c "$cmd" --argjson r "$rj" \
        '{tool_input:{command:$c},tool_response:$r,cwd:"/tmp"}' | bash "$HOOK")
  got="quiet"
  printf '%s' "$out" | grep -q '"additionalContext"' && got="remind"
  if [ "$got" = "$expect" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1)); printf 'FAIL  [want=%s got=%s]  %s (json resp)\n' "$expect" "$got" "$cmd" >&2
  fi
}

# --- REMIND set: real CLI platform merge command shapes (the covered path) ---
probe remind 'glab mr merge 123 --yes'
probe remind 'glab mr merge !546 --auto-merge=false --yes'
probe remind 'glab mr accept 123'
probe remind 'gh pr merge 45 --merge'
probe remind 'gh pr merge https://github.com/o/r/pull/45 --squash'
probe remind 'cd /some/path && glab mr merge 7 --auto-merge=false --yes'

# --- ACCEPTED best-effort NON-fire: raw REST / GraphQL / curl merges are NOT
#     detected (matching those tokens anywhere false-fired on non-merge cmds;
#     the CLI is the covered path, prose covers every path). Documented, quiet. ---
probe quiet 'glab api --method PUT "projects/:id/merge_requests/123/merge" -f sha=abc'
probe quiet 'gh api --method PUT "repos/o/r/pulls/45/merge"'
probe quiet 'glab api graphql -f query="mutation { mergeRequestAccept(input:{}) { errors } }"'
probe quiet 'curl --request PUT https://gitlab.example/api/v4/projects/1/merge_requests/123/merge'

# --- QUIET set: must NOT emit a reminder ---
probe quiet 'git status'
probe quiet 'git worktree list'
probe quiet 'git push origin feature-branch'
probe quiet 'glab mr view 123'
probe quiet 'glab mr create --title x'
# prose mention inside a quoted commit message must be masked (no false remind)
probe quiet 'git commit -m "revert an earlier glab mr merge"'
probe quiet 'git log --grep="gh pr merge"'
# token/path/mutation-name mentions on non-merge commands (Track-A/B false-pos)
probe quiet "git commit -m 'add mergeRequestAccept helper'"
probe quiet "gh api repos/o/r/issues -f title=graphql -f body=mergePullRequest"
probe quiet 'echo curl -X PUT /repos/o/r/pulls/45/merge'
probe quiet 'gh api repos/o/r/pulls/45/merge'
probe quiet 'glab api projects/1/merge_requests/7/merge'

# --- Global-flag forms (Track-B P2): must still REMIND ---
probe remind 'gh -R owner/repo pr merge 45 --merge'
probe remind 'gh --repo owner/repo pr merge 45 --squash'
probe remind 'glab --repo group/project mr merge 123 --auto-merge=false --yes'
probe remind 'glab --hostname gitlab.example.com mr accept 123'

# --- Scheduled / queued auto-merge (Track-B P1): NOT yet merged → quiet ---
probe quiet 'gh pr merge 45 --auto'
probe quiet 'glab mr merge 123 --auto-merge'
probe quiet 'glab mr merge 123 --when-pipeline-succeeds'
probe quiet 'glab mr merge 123' 'Merge request is set to be merged when pipeline succeeds'
probe quiet 'gh pr merge 45 --auto' 'Pull request will be automatically merged when all requirements are met'
# explicit immediate override is a real merge → remind
probe remind 'glab mr merge 123 --auto-merge=false --yes'

# scheduled via "set to auto-merge" phrasing (Track-B round-2)
probe quiet 'glab mr merge 123 --yes' 'Merge request !123 was set to auto-merge'

# --- Failed-merge responses (Track-B P1): quiet on failure markers ---
probe quiet 'glab mr merge 123 --yes' 'error: MR is not mergeable'
probe quiet 'gh pr merge 45 --merge' 'merge failed: CONFLICT'
probe quiet 'glab mr merge 123 --yes' '合并授权闸：该命令会合并 MR/PR ... denied'
probe quiet 'gh pr merge 45 --merge' 'HTTP 403: Resource not accessible by integration'
probe quiet 'glab mr merge 123 --auto-merge=false --yes' 'error: 401 Unauthorized'
probe quiet 'gh pr merge 45 --merge' 'error: could not resolve to a PullRequest'

# --- Structured tool_response failure signal (Track-B round-2): exit_code / is_error ---
probe_json quiet  'gh pr merge 45 --merge'   '{"exit_code":1,"stderr":"exit status 1"}'
probe_json quiet  'gh pr merge 45 --merge'   '{"exit_code":"1","stderr":"boom"}'
probe_json quiet  'gh pr merge 45 --merge'   '{"is_error":true}'
probe_json quiet  'glab mr merge 123 --yes'  '{"interrupted":true}'
probe_json remind 'gh pr merge 45 --merge'   '{"exit_code":0,"stdout":"Merged"}'
probe_json remind 'gh pr merge 45 --merge'   '{"exit_code":"0","stdout":"Merged"}'
probe_json remind 'glab mr merge 123 --yes'  '{"stdout":"Merged !123"}'

# --- --help / -h is not a merge → quiet ---
probe quiet 'gh pr merge --help'
probe quiet 'glab mr merge -h'
# a successful-looking string response still reminds
probe remind 'glab mr merge 123 --yes' 'Merged! https://.../merge_requests/123'

printf 'remind-post-merge-cleanup tests: pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
echo "test_remind_post_merge_cleanup_ok"
