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

write_receipt() { # <head> <worktree_clean true|false> [status | none to omit; default passed]
  mkdir -p "$repo/.git/ccl-code-review"
  jq -nc --arg h "$1" --argjson c "$2" --arg s "${3:-passed}" \
    '{schema_version:1,head:$h,worktree_clean:$c,mode:"review",status:$s,recorded_at:"2026-01-01T00:00:00Z"}
     | if .status == "none" then del(.status) else . end' \
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
probe "no receipt names the path it checked" remind 'glab mr create --title x' "$repo" 'ccl-code-review/last-review.json'
head1=$(git -C "$repo" rev-parse HEAD)
write_receipt "$head1" true
probe "covered head" quiet 'glab mr create --title x'
probe "covered head, gh" quiet 'gh pr create --fill'
probe "commit in the same command" remind 'git add -A && git commit -m fix && gh pr create --fill' "$repo" '会先改动 HEAD'
probe "HEAD moves only after the PR opens" quiet 'gh pr create --fill && git checkout main'
probe "draft, commit, then ready" remind 'gh pr create --draft --fill && git add -A && git commit -m fix && git push && gh pr ready' "$repo" '会先改动 HEAD'

# Coverage is not disposition: findings on the covered HEAD still remind.
write_receipt "$head1" true findings
probe "findings on the covered head" remind 'glab mr merge 8 --yes' "$repo" '结论是 findings，不是 passed'
probe "findings reminder names the receipt it read" remind 'gh pr ready 12' "$repo" 'ccl-code-review/last-review.json'
write_receipt "$head1" true none
[ "$(jq -r 'has("status")' "$repo/.git/ccl-code-review/last-review.json")" = false ] \
  || { echo "FAIL: fixture still carries a status" >&2; exit 1; }
probe "a receipt without a status is not a pass" remind 'glab mr create --title x' "$repo" '不是 passed'
probe "a missing status is not reported as findings" remind 'glab mr create --title x' "$repo" '没有记录可识别的结论'
write_receipt "$head1" true
probe "passed on the covered head" quiet 'glab mr merge 8 --yes'

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
write_receipt "$head2" true findings
probe "message-only amend keeps the findings too" remind 'glab mr create --title x' "$repo" '结论是 findings，不是 passed'

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

# Target-only integration keeps coverage (Gerrit TRIVIAL_REBASE /
# MERGE_FIRST_PARENT_UPDATE); any author change in it does not. The target is
# the remote default branch, so the fixture publishes main as origin/main.
ir="$WORK/integrate"
mkdir -p "$ir"
git -C "$ir" init -q -b main
git -C "$ir" config user.email test@example.invalid
git -C "$ir" config user.name 'Test User'
ic() { printf '%s\n' "$2" >"$ir/$1"; git -C "$ir" add -A; git -C "$ir" commit -q -m "$3"; }
must() { "$@" >/dev/null 2>&1 || { echo "FAIL: fixture step failed: $*" >&2; exit 1; }; }
publish() { must git -C "$ir" update-ref refs/remotes/origin/main main; }
ireceipt() { # <head> [status]
  mkdir -p "$ir/.git/ccl-code-review"
  jq -nc --arg h "$1" --arg s "${2:-passed}" \
    '{schema_version:1,head:$h,worktree_clean:true,mode:"review",status:$s,recorded_at:"2026-01-01T00:00:00Z"}' \
    >"$ir/.git/ccl-code-review/last-review.json"
}
fresh() { must git -C "$ir" checkout -q feature; must git -C "$ir" reset -q --hard "$reviewed"; }
ic base.txt base "base"
publish
must git -C "$ir" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
must git -C "$ir" checkout -q -b feature
ic feature.txt feature "feature change"
reviewed=$(git -C "$ir" rev-parse HEAD)
must git -C "$ir" checkout -q main
ic target.txt target "target moves on"
publish

fresh; must git -C "$ir" merge --no-edit main
ireceipt "$reviewed"
probe "A1 clean merge of the target" quiet 'gh pr merge 3 --merge' "$ir"
ireceipt "$reviewed" findings
probe "A6 clean merge-in keeps findings" remind 'gh pr merge 3 --merge' "$ir" '结论是 findings'
ireceipt "$reviewed"

# Programs configured for the repository (merge driver, external diff,
# textconv) must never run from the hook.
printf '* merge=probe diff=probe\n' >"$ir/.git/info/attributes"
git -C "$ir" config merge.probe.driver "touch '$WORK/driver-ran'"
git -C "$ir" config diff.probe.textconv "sh -c 'touch \"$WORK/textconv-ran\"; cat \"\$1\"' -"
git -C "$ir" config diff.external "sh -c 'touch \"$WORK/external-ran\"'"
mkdir -p "$ir/.git/hooks"
printf '#!/bin/sh\ntouch "%s/hook-ran"\n' "$WORK" >"$ir/.git/hooks/post-index-change"
chmod +x "$ir/.git/hooks/post-index-change"
probe "A15 coverage check runs no configured program" quiet 'gh pr merge 3 --merge' "$ir"
for ran in driver-ran textconv-ran external-ran hook-ran; do
  [ ! -e "$WORK/$ran" ] || { fail=$((fail+1)); echo "FAIL  [A15 $ran]" >&2; }
done
rm -f "$ir/.git/info/attributes"
git -C "$ir" config --unset merge.probe.driver
git -C "$ir" config --unset diff.probe.textconv
git -C "$ir" config --unset diff.external
rm -f "$ir/.git/hooks/post-index-change"

# Without a known target nothing is exempt.
must git -C "$ir" symbolic-ref --delete refs/remotes/origin/HEAD
probe "A14 no remote default branch" remind 'gh pr merge 3 --merge' "$ir" '评审之后又有这些提交'
must git -C "$ir" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main

fresh; must git -C "$ir" merge --no-commit main
printf 'sneaked\n' >"$ir/feature.txt"; must git -C "$ir" commit -qam "merge with an edit"
probe "A2 merge commit carrying an edit" remind 'gh pr merge 3 --merge' "$ir" '评审之后又有这些提交'
# The reminder carries the daily two-pass budget, not the retired five-rerun rule.
probe "A2 reminder names the challenge budget" remind 'gh pr merge 3 --merge' "$ir" 'review + challenge 两次用完后，不再调评审器'
probe "A2 reminder exempts high-risk and extraction work" remind 'gh pr merge 3 --merge' "$ir" '高风险改动和技能提炼线按各自的闸走'
probe "A2 reminder sends new scope back to review" remind 'gh pr merge 3 --merge' "$ir" '新增的行为或范围算新改动'
probe "A2 reminder excludes loosened assertions" remind 'gh pr merge 3 --merge' "$ir" '删除、跳过或放宽断言不在此列'
out_retired=$(jq -nc --arg d "$ir" '{tool_input:{command:"gh pr merge 3 --merge"},cwd:$d}' | bash "$HOOK")
if printf '%s' "$out_retired" | grep -qF '重审最多 5 次'; then
  fail=$((fail+1)); printf 'FAIL  [A2 reminder restores the five-rerun rule]\n' >&2
else
  pass=$((pass+1))
fi

must git -C "$ir" checkout -q -b other "$reviewed~1"
ic other.txt other "another author branch"
fresh; must git -C "$ir" merge --no-edit main; must git -C "$ir" merge --no-edit other
probe "A12 another branch merged in" remind 'gh pr merge 3 --merge' "$ir" '评审之后又有这些提交'

fresh; must git -C "$ir" rebase main
probe "A3 rebase with the same patch" quiet 'gh pr create --fill' "$ir"
ic extra.txt extra "extra commit after rebase"
probe "A5 rebase plus an extra commit" remind 'gh pr create --fill' "$ir"

# An unreviewed commit placed between the target and the replayed patch.
must git -C "$ir" checkout -q feature; must git -C "$ir" reset -q --hard main
ic between.txt between "unreviewed commit below the replay"
must git -C "$ir" cherry-pick "$reviewed"
probe "A11 unreviewed commit below the replay" remind 'gh pr create --fill' "$ir" '已不在当前 HEAD 的历史里'

fresh; must git -C "$ir" rebase main
printf 'amended\n' >"$ir/feature.txt"; must git -C "$ir" commit -qa --amend --no-edit
probe "A4 rebase with an amended patch" remind 'gh pr create --fill' "$ir" '已不在当前 HEAD 的历史里'

# Whitespace is code in some languages: a whitespace-only amend is a change.
fresh; must git -C "$ir" rebase main
printf 'feature \n' >"$ir/feature.txt"; must git -C "$ir" commit -qa --amend --no-edit
probe "A7 rebase with a whitespace-only amend" remind 'gh pr create --fill' "$ir" '已不在当前 HEAD 的历史里'

# A submodule pointer added in the replay stays visible even when the user's
# configuration hides submodule changes.
fresh; must git -C "$ir" rebase main
must git -C "$ir" update-index --add --cacheinfo "160000,$reviewed,vendored"
must git -C "$ir" commit -q --amend --no-edit
git -C "$ir" config diff.ignoreSubmodules all
probe "A13 gitlink hidden by diff.ignoreSubmodules" remind 'gh pr create --fill' "$ir" '已不在当前 HEAD 的历史里'
git -C "$ir" config --unset diff.ignoreSubmodules

# Run from a subdirectory with diff.relative set, a change outside it must
# still count.
fresh; must git -C "$ir" rebase main
mkdir -p "$ir/sub"; printf 'x\n' >"$ir/sub/keep.txt"; printf 'y\n' >"$ir/outside.txt"
must git -C "$ir" add -A; must git -C "$ir" commit -q --amend --no-edit
must git -C "$ir" checkout -q -b relbase "$reviewed"
mkdir -p "$ir/sub"; printf 'x\n' >"$ir/sub/keep.txt"
must git -C "$ir" add -A; must git -C "$ir" commit -q --amend --no-edit
relreviewed=$(git -C "$ir" rev-parse HEAD)
must git -C "$ir" checkout -q feature
ireceipt "$relreviewed"
git -C "$ir" config diff.relative true
probe "A16 change outside a relative diff view" remind 'gh pr create --fill' "$ir/sub" '已不在当前 HEAD 的历史里'
git -C "$ir" config --unset diff.relative
ireceipt "$reviewed"

# A partial clone could fetch a missing object through a configured
# transport while diffing; nothing is exempt there.
fresh; must git -C "$ir" rebase main
git -C "$ir" config extensions.partialClone origin
probe "A19 partial clone is never exempt" remind 'gh pr create --fill' "$ir" '已不在当前 HEAD 的历史里'
git -C "$ir" config --unset extensions.partialClone
git -C "$ir" config remote.origin.promisor true
probe "A22 promisor remote is never exempt" remind 'gh pr create --fill' "$ir" '已不在当前 HEAD 的历史里'
git -C "$ir" config --unset remote.origin.promisor

# The same patch on an unrelated root is not an update of the reviewed branch.
must git -C "$ir" checkout -q --orphan elsewhere
must git -C "$ir" rm -rq --cached .
rm -f "$ir"/*.txt
ic base.txt unrelated "unrelated root"
must git -C "$ir" cherry-pick "$reviewed"
[ "$(cat "$ir/feature.txt")" = feature ] || { echo "FAIL: A9 fixture did not replay the patch" >&2; exit 1; }
probe "A9 same patch on an unrelated base" remind 'gh pr create --fill' "$ir" '已不在当前 HEAD 的历史里'

# Conflicts: the target edits the same line the feature changed.
must git -C "$ir" checkout -q main
ic feature.txt target-side "target edits the same line"
publish
fresh; git -C "$ir" merge --no-edit main >/dev/null 2>&1
printf 'resolved\n' >"$ir/feature.txt"; must git -C "$ir" commit -qam "resolve conflict"
probe "A8 merge with a resolved conflict" remind 'gh pr merge 3 --merge' "$ir" '评审之后又有这些提交'
fresh; git -C "$ir" merge --no-edit main >/dev/null 2>&1
grep -q '^<<<<<<<' "$ir/feature.txt" || { echo "FAIL: fixture lost its conflict markers" >&2; exit 1; }
must git -C "$ir" commit -qam "commit conflict markers"
probe "A10 merge committed with conflict markers" remind 'gh pr merge 3 --merge' "$ir" '评审之后又有这些提交'

# An edit moved to a look-alike block has the same hunk text at another line;
# only replaying the reviewed patch tells them apart, also when the user's
# config renders diffs without context.
dr="$WORK/duplicate"
mkdir -p "$dr"
dg() { git -C "$dr" "$@" >/dev/null 2>&1 || { echo "FAIL: fixture step failed: git $*" >&2; exit 1; }; }
dg init -q -b main
dg config user.email test@example.invalid
dg config user.name 'Test User'
block='c1\nc2\nc3\nvalue\nc4\nc5\nc6\n'
# Header and footer lines keep both blocks away from the file boundaries,
# where git apply would refuse to move a hunk anyway.
printf "h1\nh2\nh3\nh4\n$block${block}f1\nf2\nf3\nf4\n" >"$dr/block.txt"
mkdir -p "$dr/sub"; printf 'keep\n' >"$dr/sub/keep.txt"; dg add -A; dg commit -q -m base
dg update-ref refs/remotes/origin/main main
dg symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
dg checkout -q -b feature
sed -i.bak '8s/value/changed/' "$dr/block.txt"; rm -f "$dr/block.txt.bak"; dg commit -qam "edit the first block"
dreviewed=$(git -C "$dr" rev-parse HEAD)
dg checkout -q main
printf 'moved\n' >"$dr/target.txt"; dg add -A; dg commit -q -m "target moves on"
dg update-ref refs/remotes/origin/main main
dg checkout -q feature; dg reset -q --hard main
sed -i.bak '15s/value/changed/' "$dr/block.txt"; rm -f "$dr/block.txt.bak"; dg commit -qam "edit the second block"
mkdir -p "$dr/.git/ccl-code-review"
jq -nc --arg h "$dreviewed" \
  '{schema_version:1,head:$h,worktree_clean:true,mode:"review",status:"passed",recorded_at:"2026-01-01T00:00:00Z"}' \
  >"$dr/.git/ccl-code-review/last-review.json"
probe "A17 edit moved to a look-alike block" remind 'gh pr create --fill' "$dr" '已不在当前 HEAD 的历史里'
dg config diff.context 0
probe "A18 look-alike block under diff.context=0" remind 'gh pr create --fill' "$dr" '已不在当前 HEAD 的历史里'
dg config --unset diff.context
# Control: the same reviewed edit replayed in place stays covered.
dg reset -q --hard main; dg cherry-pick "$dreviewed"
probe "A17 control: the reviewed block replayed" quiet 'gh pr create --fill' "$dr"
probe "A26 control from a subdirectory" quiet 'gh pr create --fill' "$dr/sub"

# The target rewrote the reviewed block, so the reviewed hunk would fit only
# the look-alike block HEAD edited instead.
dg checkout -q main; dg reset -q --hard "$dreviewed~1"
sed -i.bak '8s/value/target-value/' "$dr/block.txt"; rm -f "$dr/block.txt.bak"; dg commit -qam "target rewrites the first block"
dg update-ref refs/remotes/origin/main main
dg checkout -q feature; dg reset -q --hard main
sed -i.bak '15s/value/changed/' "$dr/block.txt"; rm -f "$dr/block.txt.bak"; dg commit -qam "edit the second block"
probe "A21 target rewrote the reviewed block" remind 'gh pr create --fill' "$dr" '已不在当前 HEAD 的历史里'
dg config diff.relative true
probe "A25 A21 from a subdirectory with diff.relative" remind 'gh pr create --fill' "$dr/sub" '已不在当前 HEAD 的历史里'
dg config --unset diff.relative
# Stricter than Gerrit by design: any target change to a file the branch
# changes owes a review, even far from the branch's edit.
dg checkout -q main; dg reset -q --hard "$dreviewed~1"
printf 'appended\n' >>"$dr/block.txt"; dg commit -qam "target appends to the same file"
dg update-ref refs/remotes/origin/main main
dg checkout -q feature; dg reset -q --hard main; dg cherry-pick "$dreviewed"
probe "A23 target changed the same file elsewhere" remind 'gh pr create --fill' "$dr" '已不在当前 HEAD 的历史里'
dg checkout -q main; dg reset -q --hard "$dreviewed~1"
printf 'moved\n' >"$dr/target.txt"; dg add -A; dg commit -q -m "target moves on"
dg update-ref refs/remotes/origin/main main
dg checkout -q feature

# A reviewed patch with trailing whitespace still replays exactly, even when
# the user's config rejects whitespace errors on apply.
dg checkout -q -b spaced "$dreviewed~1"
printf 'trailing   \n' >"$dr/spaced.txt"; dg add -A; dg commit -q -m "line with trailing spaces"
sreviewed=$(git -C "$dr" rev-parse HEAD)
dg rebase main
jq -nc --arg h "$sreviewed" \
  '{schema_version:1,head:$h,worktree_clean:true,mode:"review",status:"passed",recorded_at:"2026-01-01T00:00:00Z"}' \
  >"$dr/.git/ccl-code-review/last-review.json"
dg config apply.whitespace error
probe "A20 trailing whitespace replays exactly" quiet 'gh pr create --fill' "$dr"
dg config --unset apply.whitespace

# With diff.noprefix the first path component of an unprefixed patch would be
# stripped on apply, moving a nested edit onto a same-named root file.
pr="$WORK/prefix"
mkdir -p "$pr/nested"
pg() { git -C "$pr" "$@" >/dev/null 2>&1 || { echo "FAIL: fixture step failed: git $*" >&2; exit 1; }; }
pg init -q -b main
pg config user.email test@example.invalid
pg config user.name 'Test User'
printf 'same\n' >"$pr/file.txt"; printf 'same\n' >"$pr/nested/file.txt"; pg add -A; pg commit -q -m base
pg update-ref refs/remotes/origin/main main
pg symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
pg checkout -q -b feature
printf 'changed\n' >"$pr/nested/file.txt"; pg commit -qam "edit the nested file"
previewed=$(git -C "$pr" rev-parse HEAD)
pg checkout -q main
printf 'moved\n' >"$pr/target.txt"; pg add -A; pg commit -q -m "target moves on"
pg update-ref refs/remotes/origin/main main
pg checkout -q feature; pg reset -q --hard main
printf 'changed\n' >"$pr/file.txt"; pg commit -qam "edit the root file instead"
mkdir -p "$pr/.git/ccl-code-review"
jq -nc --arg h "$previewed" \
  '{schema_version:1,head:$h,worktree_clean:true,mode:"review",status:"passed",recorded_at:"2026-01-01T00:00:00Z"}' \
  >"$pr/.git/ccl-code-review/last-review.json"
pg config diff.noprefix true
probe "A24 nested edit moved to the root under diff.noprefix" remind 'gh pr create --fill' "$pr" '已不在当前 HEAD 的历史里'

# The target changed a reviewed file and the merge kept the reviewed version,
# silently dropping the target's change: an author decision nobody reviewed.
must git -C "$pr" checkout -q main
printf 'target edit\n' >"$pr/nested/file.txt"; must git -C "$pr" commit -qam "target edits the reviewed file"
must git -C "$pr" update-ref refs/remotes/origin/main main
must git -C "$pr" checkout -q feature; must git -C "$pr" reset -q --hard "$previewed"
git -C "$pr" merge --no-commit main >/dev/null 2>&1
must git -C "$pr" checkout "$previewed" -- nested/file.txt
must git -C "$pr" commit -q --no-edit
git -C "$pr" config --unset diff.noprefix
probe "A27 merge drops the target's change to a reviewed file" remind 'gh pr merge 3 --merge' "$pr" '评审之后又有这些提交'

# A reviewed file whose name looks like a glob must not exclude other files
# from the comparison.
gr="$WORK/glob"
mkdir -p "$gr"
gg() { git -C "$gr" "$@" >/dev/null 2>&1 || { echo "FAIL: fixture step failed: git $*" >&2; exit 1; }; }
gg init -q -b main
gg config user.email test@example.invalid
gg config user.name 'Test User'
printf 'base\n' >"$gr/notes"; gg add -A; gg commit -q -m base
gg update-ref refs/remotes/origin/main main
gg symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
gg checkout -q -b feature
printf 'reviewed\n' >"$gr/n*"; gg add -A; gg commit -q -m "add a glob-named file"
greviewed=$(git -C "$gr" rev-parse HEAD)
gg checkout -q main
printf 'moved\n' >"$gr/target.txt"; gg add -A; gg commit -q -m "target moves on"
gg update-ref refs/remotes/origin/main main
gg checkout -q feature; gg rebase main
printf 'unreviewed\n' >"$gr/notes"; gg add -A; gg commit -q --amend --no-edit
mkdir -p "$gr/.git/ccl-code-review"
jq -nc --arg h "$greviewed" \
  '{schema_version:1,head:$h,worktree_clean:true,mode:"review",status:"passed",recorded_at:"2026-01-01T00:00:00Z"}' \
  >"$gr/.git/ccl-code-review/last-review.json"
probe "A28 glob-like reviewed name excludes nothing else" remind 'gh pr create --fill' "$gr" '已不在当前 HEAD 的历史里'

# A bracketed name is a glob that does not match itself: without literal
# pathspecs the reviewed file would drop out of the comparison, so dropping
# its reviewed change in an amend would go unnoticed.
br="$WORK/bracket"
mkdir -p "$br"
bg() { git -C "$br" "$@" >/dev/null 2>&1 || { echo "FAIL: fixture step failed: git $*" >&2; exit 1; }; }
bg init -q -b main
bg config user.email test@example.invalid
bg config user.name 'Test User'
printf 'base\n' >"$br/check[1].sh"; printf 'base\n' >"$br/feature.txt"; bg add -A; bg commit -q -m base
bg update-ref refs/remotes/origin/main main
bg symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
bg checkout -q -b feature
printf 'reviewed\n' >"$br/check[1].sh"; printf 'reviewed\n' >"$br/feature.txt"; bg add -A; bg commit -q -m "reviewed change"
breviewed=$(git -C "$br" rev-parse HEAD)
bg checkout -q main
printf 'moved\n' >"$br/target.txt"; bg add -A; bg commit -q -m "target moves on"
bg update-ref refs/remotes/origin/main main
bg checkout -q feature; bg rebase main
printf 'base\n' >"$br/check[1].sh"; bg add -A; bg commit -q --amend --no-edit
mkdir -p "$br/.git/ccl-code-review"
jq -nc --arg h "$breviewed" \
  '{schema_version:1,head:$h,worktree_clean:true,mode:"review",status:"passed",recorded_at:"2026-01-01T00:00:00Z"}' \
  >"$br/.git/ccl-code-review/last-review.json"
probe "A29 bracketed reviewed name stays compared" remind 'gh pr create --fill' "$br" '已不在当前 HEAD 的历史里'

printf 'test_remind_review_covers_head: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
echo test_remind_review_covers_head_ok
