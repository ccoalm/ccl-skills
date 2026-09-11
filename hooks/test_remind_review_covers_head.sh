#!/usr/bin/env bash
# Deterministic behavior suite for hooks/remind-review-covers-head.sh.
# Builds throwaway repositories, writes the local review receipt the way
# review_gate.py does, and asserts which pull-request commands get the reminder.
# Registered in the Makefile `test` target; requires jq and git (without jq the
# hook degrades to silence, so this suite fails loudly instead of false-greening).
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
HOOK="$SCRIPT_DIR/remind-review-covers-head.sh"
[ -f "$HOOK" ] || { echo "FAIL: hook not found: $HOOK" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq required for this suite" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "FAIL: git required for this suite" >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/review-covers-head.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
pass=0; fail=0

repo="$WORK/repo"
mkdir -p "$repo" "$WORK/elsewhere"
git -C "$repo" init -q
git -C "$repo" config user.email test@example.invalid
git -C "$repo" config user.name 'Test User'
commit() { printf '%s\n' "$2" >"$repo/$1"; git -C "$repo" add -A; git -C "$repo" commit -q -m "$3"; }
commit code.txt one "first change"

write_receipt() { # <head> <worktree_clean true|false>
  mkdir -p "$repo/.git/ccl-code-review"
  jq -nc --arg h "$1" --argjson c "$2" \
    '{schema_version:1,head:$h,worktree_clean:$c,mode:"review",status:"findings",recorded_at:"2026-01-01T00:00:00Z"}' \
    >"$repo/.git/ccl-code-review/last-review.json"
}

# probe <label> <expect remind|quiet> <command> [cwd] [expected substring]
probe() {
  local label="$1" expect="$2" cmd="$3" dir="${4:-$repo}" needle="${5:-}" out got
  out=$(jq -nc --arg c "$cmd" --arg d "$dir" '{tool_input:{command:$c},cwd:$d}' | bash "$HOOK")
  got="quiet"
  printf '%s' "$out" | grep -q '"additionalContext"' && got="remind"
  if [ "$got" = "$expect" ] && { [ -z "$needle" ] || printf '%s' "$out" | grep -qF -- "$needle"; }; then
    pass=$((pass+1))
  else
    fail=$((fail+1)); printf 'FAIL  [%s want=%s got=%s]  %s\n' "$label" "$expect" "$got" "$cmd" >&2
  fi
}

probe "no receipt" remind 'glab mr create --title x' "$repo" '没有记录到任何结论性的 code-review 结果'
head1=$(git -C "$repo" rev-parse HEAD)
write_receipt "$head1" true
probe "covered head" quiet 'glab mr create --title x'
probe "covered head, gh" quiet 'gh pr create --fill'
probe "commit in the same command" remind 'git add -A && git commit -m fix && gh pr create --fill' "$repo" '会先改动 HEAD'
probe "HEAD moves only after the PR opens" quiet 'gh pr create --fill && git checkout main'
probe "draft, commit, then ready" remind 'gh pr create --draft --fill && git add -A && git commit -m fix && git push && gh pr ready' "$repo" '会先改动 HEAD'

commit test.txt added "add regression test after review"
probe "commit after review" remind 'glab mr create --title x' "$repo" 'add regression test after review'
probe "gh pr ready" remind 'gh pr ready 12'
probe "help then action" remind 'gh pr create --help ; gh pr create --fill'
probe "gh pr merge" remind 'gh -R o/r pr merge 12 --squash'
probe "glab mr update --ready" remind 'glab mr update 8 --ready'
probe "glab mr merge" remind 'glab mr merge 8 --yes'
probe "leading cd names the worktree" remind "cd $repo && glab mr create --title x" "$WORK/elsewhere" 'add regression test after review'

# A quoted leading cd with a space: masking must not hide the directory.
spaced="$WORK/space repo"
mkdir -p "$spaced"
git -C "$spaced" init -q
git -C "$spaced" -c user.email=t@example.invalid -c user.name=t commit -q --allow-empty -m init
probe "double-quoted cd with a space" remind "cd \"$spaced\" && gh pr create --fill" "$WORK/elsewhere" '没有记录到任何结论性的 code-review 结果'
probe "single-quoted cd with a space" remind "cd '$spaced' && gh pr create --fill" "$WORK/elsewhere" '没有记录到任何结论性的 code-review 结果'

probe "unrelated glab" quiet 'glab mr list'
probe "plain push" quiet 'git push -u origin fix'
probe "update without ready" quiet 'glab mr update 8 --title y'
probe "quoted mention" quiet 'git commit -m "then glab mr create later"'
probe "help" quiet 'glab mr create --help'
probe "not a repository" quiet 'glab mr create --title x' "$WORK/elsewhere"

# Same content, new commit id (message-only amend): the tree matches, so quiet.
head2=$(git -C "$repo" rev-parse HEAD)
write_receipt "$head2" true
git -C "$repo" commit -q --amend -m "reworded message only"
probe "message-only amend keeps the reviewed tree" quiet 'glab mr create --title x'

# Rewritten history with different content: the reviewed commit is gone.
git -C "$repo" reset -q --hard "$head1"
commit other.txt diverged "diverged content"
probe "rewritten history" remind 'glab mr create --title x' "$repo" '已不在当前 HEAD 的历史里'

# The review saw uncommitted changes and HEAD has not moved since.
head3=$(git -C "$repo" rev-parse HEAD)
write_receipt "$head3" false
probe "review covered a dirty worktree" remind 'glab mr create --title x' "$repo" '评审时工作区有未提交改动'

# A linked receipt is not trusted.
write_receipt "$head3" true
mv "$repo/.git/ccl-code-review/last-review.json" "$WORK/receipt.json"
ln -s "$WORK/receipt.json" "$repo/.git/ccl-code-review/last-review.json"
probe "linked receipt counts as missing" remind 'glab mr create --title x' "$repo" '没有记录到任何结论性的 code-review 结果'

printf 'test_remind_review_covers_head: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
echo test_remind_review_covers_head_ok
