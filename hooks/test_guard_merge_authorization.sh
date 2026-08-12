#!/usr/bin/env bash
# Deterministic behavior suite for hooks/guard-merge-authorization.sh.
# Self-contained: builds a throwaway repo (default-branch checkout `main` +
# a linked feature worktree) under mktemp, feeds constructed PreToolUse JSON
# to the guard, and asserts the deny set denies and the allow set passes.
# Registered in the Makefile `test` target; requires jq + git (the guard's
# own dependencies — when they are missing the guard degrades to allow, so
# this suite requires them and fails loudly instead of false-greening).
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
GUARD="${GUARD:-$SCRIPT_DIR/guard-merge-authorization.sh}"
[ -f "$GUARD" ] || { echo "FAIL: guard not found: $GUARD" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq required for this suite" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "FAIL: git required for this suite" >&2; exit 1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/guard-merge-authz-test.XXXXXX")" || exit 1
trap 'rm -rf "$tmp"' EXIT

git -C "$tmp" init -qb main repo-main
GITC=(git -C "$tmp/repo-main" -c user.email=test@example.invalid -c user.name=test)
"${GITC[@]}" commit -q --allow-empty -m init
"${GITC[@]}" branch -q feature
"${GITC[@]}" worktree add -q "$tmp/wt-feature" feature

MAIN_CWD="$tmp/repo-main"
FEAT_CWD="$tmp/wt-feature"

# Second repo whose default branch is NOT main/master: trunk, with
# origin/HEAD resolvable (exercises the detected-default path, not the
# hardcoded main|master fallback).
git -C "$tmp" init -qb trunk repo-trunk
GITT=(git -C "$tmp/repo-trunk" -c user.email=test@example.invalid -c user.name=test)
"${GITT[@]}" commit -q --allow-empty -m init
"${GITT[@]}" branch -q feature
"${GITT[@]}" remote add origin "$tmp/repo-trunk"   # any URL; never contacted
trunk_sha=$("${GITT[@]}" rev-parse trunk)
"${GITT[@]}" update-ref refs/remotes/origin/trunk "$trunk_sha"
"${GITT[@]}" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk
"${GITT[@]}" worktree add -q "$tmp/wt-trunk-feature" feature
TRUNK_CWD="$tmp/repo-trunk"
TRUNK_FEAT_CWD="$tmp/wt-trunk-feature"

# Third repo: origin remote EXISTS but origin/HEAD and init.defaultBranch are
# both unresolvable → the gate narrows to main|master and must WARN visibly.
git -C "$tmp" init -qb trunk repo-nohead
GITN=(git -C "$tmp/repo-nohead" -c user.email=test@example.invalid -c user.name=test)
"${GITN[@]}" commit -q --allow-empty -m init
"${GITN[@]}" remote add origin "$tmp/repo-nohead"
"${GITN[@]}" branch -q feature
"${GITN[@]}" worktree add -q "$tmp/wt-nohead-feature" feature
NOHEAD_FEAT_CWD="$tmp/wt-nohead-feature"

# Fourth repo: non-simple push.default configs that make a refspec-less
# push advance the default branch even from a feature branch.
git -C "$tmp" init -qb main repo-pd
GITP=(git -C "$tmp/repo-pd" -c user.email=test@example.invalid -c user.name=test)
"${GITP[@]}" commit -q --allow-empty -m init
"${GITP[@]}" branch -q feature
"${GITP[@]}" branch -q feature2
"${GITP[@]}" worktree add -q "$tmp/wt-pd-feature" feature
"${GITP[@]}" worktree add -q "$tmp/wt-pd-feature2" feature2
"${GITP[@]}" config branch.feature.merge refs/heads/main   # misconfigured upstream
"${GITP[@]}" config branch.feature2.merge refs/heads/feature2
PD_FEAT_CWD="$tmp/wt-pd-feature"
PD_FEAT2_CWD="$tmp/wt-pd-feature2"

pass=0; fail=0

probe() { # probe <expect deny|allow> <cwd> <command>
  local expect="$1" cwd="$2" cmd="$3" out got
  out=$(jq -nc --arg c "$cmd" --arg w "$cwd" '{tool_input:{command:$c},cwd:$w}' | bash "$GUARD")
  got="allow"
  printf '%s' "$out" | grep -q '"permissionDecision":"deny"' && got="deny"
  if [ "$got" = "$expect" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1)); printf 'FAIL  [want=%s got=%s @%s]  %s\n' "$expect" "$got" "$(basename "$cwd")" "$cmd" >&2
  fi
}

# --- DENY set: merge-executing / default-branch-advancing commands ---
probe deny "$FEAT_CWD" 'glab mr merge 123 --yes'
probe deny "$FEAT_CWD" 'glab mr merge 123 --squash --remove-source-branch'
probe deny "$FEAT_CWD" 'gh pr merge 45 --merge'
probe deny "$FEAT_CWD" 'gh pr merge https://github.com/o/r/pull/45 --squash'
probe deny "$FEAT_CWD" 'glab api --method PUT "projects/:id/merge_requests/123/merge" -f sha=abc'
probe deny "$FEAT_CWD" 'git push origin main'
probe deny "$FEAT_CWD" 'git push -u origin main'
probe deny "$FEAT_CWD" 'git push --force origin main'
probe deny "$FEAT_CWD" 'git push origin HEAD:main'
probe deny "$FEAT_CWD" 'git push origin feature:main'
probe deny "$FEAT_CWD" 'git push origin HEAD:refs/heads/main'
probe deny "$FEAT_CWD" 'git push origin refs/heads/main'
probe deny "$FEAT_CWD" 'git push origin +main'
probe deny "$FEAT_CWD" 'git push origin +HEAD:main'
probe deny "$FEAT_CWD" 'git push origin master'
probe deny "$MAIN_CWD" 'git push'
probe deny "$MAIN_CWD" 'git push origin HEAD'
probe deny "$MAIN_CWD" 'git merge feature'
probe deny "$MAIN_CWD" 'git merge --no-ff feature'
probe deny "$MAIN_CWD" 'git pull origin feature'
probe deny "$MAIN_CWD" 'git pull . feature'
probe deny "$MAIN_CWD" 'git pull --rebase origin feature'
probe deny "$FEAT_CWD" 'git commit -m "done" && git push origin main'
probe deny "$FEAT_CWD" 'cd somewhere; glab mr merge 7'
probe deny "$FEAT_CWD" 'env FOO=1 glab mr merge 9'
probe deny "$FEAT_CWD" 'timeout 30 glab mr merge 9'
probe deny "$FEAT_CWD" 'timeout -k 5 30 git push origin main'
probe deny "$FEAT_CWD" 'nice -n 10 gh pr merge 45 --merge'
probe deny "$FEAT_CWD" 'sudo -u deployer git push origin main'
probe deny "$FEAT_CWD" 'env -u PAGER FOO=1 glab mr merge 9'
probe deny "$FEAT_CWD" 'git push --all origin'
probe deny "$FEAT_CWD" 'git push --mirror origin'
probe deny "$FEAT_CWD" 'git push origin --all'

# --- detected-default path (default branch = trunk via origin/HEAD) ---
probe deny "$TRUNK_FEAT_CWD" 'git push origin trunk'
probe deny "$TRUNK_FEAT_CWD" 'git push origin HEAD:trunk'
probe deny "$TRUNK_FEAT_CWD" 'git push origin refs/heads/trunk'
probe deny "$TRUNK_CWD" 'git merge feature'
probe deny "$TRUNK_CWD" 'git push'
probe allow "$TRUNK_CWD" 'git merge --ff-only origin/trunk'
probe allow "$TRUNK_FEAT_CWD" 'git merge origin/trunk'
probe allow "$TRUNK_FEAT_CWD" 'git push origin feature'
# resolved default = trunk → a NON-default branch literally named main is
# ordinary delivery there, not the protected branch (no main|master union).
probe allow "$TRUNK_FEAT_CWD" 'git push origin main'

# --- global flags before subcommand / quoted single-word branch ---
probe deny "$FEAT_CWD" 'gh -R owner/repo pr merge 45 --squash'
probe deny "$FEAT_CWD" 'gh --repo owner/repo pr merge 45 --merge'
probe deny "$FEAT_CWD" 'glab --host gitlab.example.invalid mr merge 7'
probe deny "$FEAT_CWD" 'git push origin "main"'
probe deny "$FEAT_CWD" "git push origin 'main'"
probe deny "$FEAT_CWD" 'git push origin HEAD:"main"'
probe allow "$FEAT_CWD" 'gh -R owner/repo pr view 45'

# --- API merge spellings (both platforms) vs. legit API use ---
probe deny "$FEAT_CWD" 'gh api repos/owner/repo/pulls/123/merge --method PUT'
probe deny "$FEAT_CWD" 'gh api "repos/owner/repo/pulls/123/merge" -X PUT'
probe allow "$FEAT_CWD" 'gh api repos/owner/repo/pulls/123/comments'
probe allow "$FEAT_CWD" 'glab api "projects/:id/merge_requests/123/notes" -f body="see merge_requests/9/merge"'
probe allow "$FEAT_CWD" 'glab api projects/:id/merge_requests/9/notes -f note=see-merge_requests/9/merge'

# --- Raw HTTP merge REST calls share the platform authorization gate ---
probe deny "$FEAT_CWD" 'curl -X PUT https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
probe deny "$FEAT_CWD" 'wget --method=PUT https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
probe deny "$FEAT_CWD" 'curl --request PUT https://git.example.invalid/api/v3/repos/o/r/pulls/42/merge'
probe deny "$FEAT_CWD" 'curl -XPUT http://git.example.invalid/api/v4/projects/group%2Frepo/merge_requests/546/merge?sha=abc#result'
probe deny "$FEAT_CWD" 'curl --request=PUT HTTPS://GIT.EXAMPLE.INVALID/repos/o/r/pulls/42/merge/'
probe deny "$FEAT_CWD" 'curl -X PUT "https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge?sha=abc&should_remove_source_branch=true"'
probe deny "$FEAT_CWD" "curl --request PUT 'https://git.example.invalid/repos/o/r/pulls/42/merge?mode=fast&confirm=1'"
probe deny "$FEAT_CWD" 'curl -T payload.bin https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
probe deny "$FEAT_CWD" 'curl --upload-file payload.bin https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
probe deny "$FEAT_CWD" 'curl --upload-file=payload.bin https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
probe deny "$FEAT_CWD" 'wget --method PUT https://git.example.invalid/repos/o/r/pulls/42/merge'
probe deny "$FEAT_CWD" 'wget --method PUT -H https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
probe deny "$FEAT_CWD" 'wget --method PUT -d https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
probe deny "$FEAT_CWD" 'wget --method PUT -x https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'

# Method, endpoint, and operand negative controls.
probe allow "$FEAT_CWD" 'curl https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
probe allow "$FEAT_CWD" 'curl --request POST https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
probe allow "$FEAT_CWD" 'curl --data x=1 https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
probe allow "$FEAT_CWD" 'curl -X POST -T payload.bin https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
probe allow "$FEAT_CWD" 'curl -T payload.bin -X POST https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
probe allow "$FEAT_CWD" 'curl -X PUT https://git.example.invalid/api/v4/projects/1/merge_requests/546/notes'
probe allow "$FEAT_CWD" 'curl -X PUT https://git.example.invalid/prefix/api/v4/projects/1/merge_requests/546/merge'
probe allow "$FEAT_CWD" 'curl -X PUT https://git.example.invalid/api/v4/projects/1/Merge_requests/546/merge'
probe allow "$FEAT_CWD" 'curl -X PUT https://git.example.invalid/api/v4/projects//merge_requests/546/merge'
probe allow "$FEAT_CWD" 'curl -X PUT https://git.example.invalid/api/v4/projects/1/merge_requests/0/merge'
probe allow "$FEAT_CWD" 'curl -X PUT https://git.example.invalid/api/v4/projects/1/merge_requests/546/%6derge'
probe allow "$FEAT_CWD" 'curl -X PUT https://:443/api/v4/projects/1/merge_requests/546/merge'
probe allow "$FEAT_CWD" 'curl -X PUT https://git.example.invalid/ordinary -H https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
probe allow "$FEAT_CWD" 'curl -X PUT https://git.example.invalid/ordinary -H "https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge?x=1&y=2"'
probe allow "$FEAT_CWD" 'curl -X PUT https://git.example.invalid/ordinary --data https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
probe allow "$FEAT_CWD" 'curl -X PUT https://git.example.invalid/ordinary -o https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
probe allow "$FEAT_CWD" 'curl -X PUT --referer https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge https://git.example.invalid/ordinary'
probe allow "$FEAT_CWD" 'curl -X PUT --doh-url https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge https://git.example.invalid/ordinary'
probe allow "$FEAT_CWD" 'curl -X PUT --proxy https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge https://git.example.invalid/ordinary'
probe allow "$FEAT_CWD" 'curl -X PUT --user-agent https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge https://git.example.invalid/ordinary'
probe allow "$FEAT_CWD" 'wget --method PUT https://git.example.invalid/ordinary --header https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
probe allow "$FEAT_CWD" 'wget --method PUT https://git.example.invalid/ordinary --body-data https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
probe allow "$FEAT_CWD" 'wget --method PUT https://git.example.invalid/ordinary -O https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
probe allow "$FEAT_CWD" 'curl --method PUT https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
probe allow "$FEAT_CWD" 'wget -X PUT https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
probe allow "$FEAT_CWD" 'wget -T 30 https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
probe allow "$FEAT_CWD" 'echo curl -X PUT https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
probe allow "$FEAT_CWD" "printf '%s' 'curl -X PUT https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'"
probe allow "$FEAT_CWD" 'true # curl -X PUT https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'

# Existing segment normalization, wrappers, and redirection handling apply to
# raw HTTP clients without creating a parallel tokenizer.
probe deny "$FEAT_CWD" 'env FOO=1 curl -X PUT https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
probe deny "$FEAT_CWD" 'timeout 30 wget --method=PUT https://git.example.invalid/repos/o/r/pulls/42/merge'
probe deny "$FEAT_CWD" '/usr/bin/curl --request PUT https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
probe deny "$FEAT_CWD" 'curl -X PUT https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge 2>/dev/null | jq .'
probe deny "$FEAT_CWD" 'echo before && curl -X PUT https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge && echo after'

# Multiple URL operands share one transfer method; repeated curl request options
# use the last value, while ambiguous transfer boundaries still deny.
probe deny "$FEAT_CWD" 'curl -X PUT https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge https://git.example.invalid/ordinary'
probe deny "$FEAT_CWD" 'curl -X PUT --url https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
probe deny "$FEAT_CWD" 'curl -X PUT --url=https://git.example.invalid/repos/o/r/pulls/42/merge'
probe allow "$FEAT_CWD" 'curl -X PUT -X POST https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
probe deny "$FEAT_CWD" 'curl -X POST --request PUT https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
probe deny "$FEAT_CWD" 'curl -X PUT https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge --next https://git.example.invalid/ordinary'

# Deliberate-circumvention boundaries stay visible and allowed; the detector
# handles routine direct argv spellings, not a shell interpreter or curl config.
# shellcheck disable=SC2016 # literal $U is the behavior under test
probe allow "$FEAT_CWD" 'U=https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge; curl -X PUT "$U"'
probe allow "$FEAT_CWD" 'curl --config merge-request.conf'
probe allow "$FEAT_CWD" 'wget --config=merge-request.conf'
probe allow "$FEAT_CWD" "eval 'curl -X PUT https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'"
probe allow "$FEAT_CWD" "bash -c 'curl -X PUT https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'"
probe allow "$FEAT_CWD" "printf '%s' https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge | xargs curl -X PUT"

# --- git -C redirection: the acted-on repo decides, not the hook cwd ---
probe deny "$FEAT_CWD" "git -C $MAIN_CWD merge feature"
probe deny "$FEAT_CWD" "git -C $MAIN_CWD push"
probe allow "$MAIN_CWD" "git -C $FEAT_CWD push"
probe allow "$MAIN_CWD" "git -C $FEAT_CWD merge origin/main"

# --- path-prefixed / backslash-escaped command words ---
probe deny "$FEAT_CWD" '/usr/bin/git push origin main'
probe deny "$FEAT_CWD" '\git push origin main'
probe deny "$FEAT_CWD" '/opt/homebrew/bin/glab mr merge 3'
probe allow "$FEAT_CWD" '/usr/bin/git push origin feature'

# --- GraphQL merge mutations via api subcommand ---
probe deny "$FEAT_CWD" "gh api graphql -f query='mutation { mergePullRequest(input: {pullRequestId: \"x\"}) { pullRequest { merged } } }'"
probe deny "$FEAT_CWD" "gh api graphql -f query='mutation { enablePullRequestAutoMerge(input: {pullRequestId: \"x\"}) { pullRequest { id } } }'"
probe deny "$FEAT_CWD" "glab api graphql -f query='mutation { mergeRequestAccept(input: {projectPath: \"a/b\", iid: \"1\"}) { mergeRequest { mergedAt } } }'"
probe allow "$FEAT_CWD" "gh api graphql -f query='query { repository(owner: \"o\", name: \"r\") { pullRequest(number: 1) { title } } }'"
probe allow "$FEAT_CWD" "git commit -m 'add mergePullRequest helper' && gh api graphql -f query='query { viewer { login } }'"

# --- no-origin local repo: narrow fallback (dev/trunk are pushable) ---
probe allow "$FEAT_CWD" 'git push origin develop'
probe allow "$FEAT_CWD" 'git push origin trunk'

# --- cd / checkout / switch tracked across segments ---
probe deny "$FEAT_CWD" "cd $MAIN_CWD && git push"
probe deny "$FEAT_CWD" "cd ../repo-main && git merge feature"
probe deny "$FEAT_CWD" 'git checkout main && git merge feature'
probe deny "$FEAT_CWD" 'git switch main && git push origin HEAD'
probe deny "$MAIN_CWD" 'git checkout -b hotfix main && git checkout main && git merge hotfix'
probe allow "$MAIN_CWD" "cd $FEAT_CWD && git push"
probe allow "$MAIN_CWD" 'git checkout feature && git push origin HEAD'
probe allow "$FEAT_CWD" 'git checkout -b new-feature && git push -u origin new-feature'
probe allow "$FEAT_CWD" 'git checkout -- README.md && git push origin feature'
probe deny "$FEAT_CWD" "pushd $MAIN_CWD && git push"
probe deny "$MAIN_CWD" "pushd $FEAT_CWD && popd && git push"
probe allow "$MAIN_CWD" "pushd $FEAT_CWD && git push"
probe deny "$MAIN_CWD" "cd $FEAT_CWD && cd - && git push"
probe allow "$FEAT_CWD" "cd $MAIN_CWD && cd - && git push"

# --- non-simple push.default: refspec-less push from a feature branch ---
git -C "$PD_FEAT_CWD" config push.default matching
probe deny "$PD_FEAT_CWD" 'git push'
probe allow "$PD_FEAT_CWD" 'git push origin feature'
git -C "$PD_FEAT_CWD" config push.default upstream
probe deny "$PD_FEAT_CWD" 'git push'          # upstream -> refs/heads/main
probe allow "$PD_FEAT2_CWD" 'git push'        # upstream -> its own branch
git -C "$PD_FEAT_CWD" config push.default simple
probe allow "$PD_FEAT_CWD" 'git push'

# --- ALLOW set: routine delivery actions that must not false-positive ---
probe allow "$FEAT_CWD" 'git push origin fix/merge-authorization-gate'
probe allow "$FEAT_CWD" 'git push -u origin feature'
probe allow "$FEAT_CWD" 'git push'
probe allow "$FEAT_CWD" 'git push origin HEAD'
probe allow "$FEAT_CWD" 'git merge origin/main'
probe allow "$FEAT_CWD" 'git merge main'
probe allow "$FEAT_CWD" 'git rebase origin/main'
probe allow "$MAIN_CWD" 'git merge --ff-only origin/main'
probe allow "$MAIN_CWD" 'git pull'
probe allow "$MAIN_CWD" 'git pull origin main'
probe allow "$MAIN_CWD" 'git pull --ff-only origin main'
probe allow "$FEAT_CWD" 'git pull origin main'
probe allow "$MAIN_CWD" 'git status && git log --oneline -5'

# --- redirection tokens: the arg walk must not miscount a redirection ---
# The real defect: 'git pull --ff-only origin main 2>&1 | tail -1' denied,
# because the '&' segment split left '2>' as a bogus third refspec arg.
# allow (fixed): routine stderr/stdout plumbing around the designed sync forms
probe allow "$MAIN_CWD" 'git pull --ff-only origin main 2>&1 | tail -1'
probe allow "$MAIN_CWD" 'git pull origin main 2>/dev/null'
probe allow "$MAIN_CWD" 'git pull --ff-only origin main >/tmp/pull.log 2>&1'
probe allow "$MAIN_CWD" 'git merge --ff-only origin/main 2>&1'
probe allow "$TRUNK_CWD" 'git pull --ff-only origin trunk 2>&1'
probe allow "$FEAT_CWD" 'git pull origin feature 2>&1'
probe allow "$MAIN_CWD" 'git pull --ff-only origin main >|/tmp/log'
probe allow "$FEAT_CWD" 'git push origin feature 2>&1'
# '>|' clobber contains a '|' that the segment split would tear; normalized to
# '>' first, so the sync flags are not stranded and a real advancement is not lost
probe allow "$MAIN_CWD" 'git merge>|/tmp/gx --ff-only origin/main'
probe allow "$MAIN_CWD" 'git merge --ff-only origin/main >|/tmp/gx'
probe deny  "$FEAT_CWD" 'git push origin main >|/tmp/gx'
probe deny  "$FEAT_CWD" 'git push origin main>|/tmp/gx'
# deny preserved: redirection plumbing never launders a real advancement
probe deny "$MAIN_CWD" 'git pull origin feature 2>&1'
probe deny "$MAIN_CWD" 'git pull --rebase origin feature 2>/dev/null'
probe deny "$MAIN_CWD" 'git merge feature 2>&1'
probe deny "$FEAT_CWD" 'git push origin main 2>&1 | tail -1'
probe deny "$FEAT_CWD" 'glab mr merge 123 --yes 2>&1'
# deny preserved: an OPERATOR-led redirection PREFIX (no fd digit) still exposes
# the command word — such tokens are unambiguous redirections, dropped anywhere
probe deny "$MAIN_CWD" '>/tmp/log git push origin main'
probe deny "$FEAT_CWD" '>/tmp/log git push origin main'
probe deny "$MAIN_CWD" '>>/tmp/log git merge feature'
# deny preserved: a QUOTED branch name that merely looks like a redirection
# is an argument, not shell plumbing — masking keeps it as a counted arg
probe deny "$MAIN_CWD" "git pull origin '2>evil'"
probe deny "$MAIN_CWD" 'git merge "2>evil"'
# deny preserved: an escaped/attached redirection keeps 'main' a visible arg,
# so a real advancement is not laundered
probe deny "$MAIN_CWD" 'git push origin feature\> main'
probe deny "$FEAT_CWD" 'git push origin main >/tmp/foo\ bar'
probe deny "$MAIN_CWD" 'git merge feature>/tmp/log'
# deny (fixed): a redirection glued directly onto the default refspec must keep
# 'main'/'HEAD:main' visible — 'main>/log' splits to 'main', not a phantom
# non-default refspec. This also un-false-denies the attached SYNC form.
probe deny "$FEAT_CWD" 'git push origin main>/tmp/log'
probe deny "$FEAT_CWD" 'git push origin main>>/tmp/log'
probe deny "$FEAT_CWD" 'git push origin HEAD:main>/tmp/log'
probe allow "$MAIN_CWD" 'git pull --ff-only origin main>/tmp/log'
# no under-block regression: a quoted single/multi-digit wrapper operand is NOT
# an fd — a digit-led redirect before the tool word is kept so the wrapper walk
# still consumes the duration and reaches git
probe deny "$FEAT_CWD" "timeout '5'>/dev/null git push origin main"
probe deny "$FEAT_CWD" "timeout '30'>/dev/null git push origin main"
probe deny "$FEAT_CWD" "nice -n '5'>/dev/null git push origin main"
probe deny "$FEAT_CWD" 'timeout 5 git push origin main'
# allow preserved: digit-led fd plumbing AFTER the tool word is still stripped,
# incl. multi-digit fds
probe allow "$MAIN_CWD" 'git pull origin main 2>/dev/null'
probe allow "$MAIN_CWD" 'git pull --ff-only origin main 10>/tmp/log'
# deny preserved: an INPUT redirect (`<in`) never launders a real advancement —
# ground-truth: bash still runs `git push origin main`, stdin is unrelated
probe deny "$FEAT_CWD" 'git push origin main <in'
probe deny "$FEAT_CWD" 'git push origin main <in 2>&1'
# no false-deny: a digit-suffixed branch is NOT an fd; the redirect attaches
# to 'main2'/'release10' (not the default branch), so the push is allowed
probe allow "$FEAT_CWD" 'git push origin main2>/tmp/log'
probe allow "$FEAT_CWD" 'git push origin main2>/dev/null'
probe allow "$FEAT_CWD" 'git push origin release10>/tmp/log'
probe allow "$FEAT_CWD" 'git push origin feature>/tmp/log'
# KNOWN best-effort gaps (documented; footgun reminder, not an adversarial
# boundary — see the guard header). Pinned so a future change that DOES start
# catching them is a visible, intentional upgrade rather than a surprise.
probe allow "$FEAT_CWD" '2>&1 git push origin main'         # fd-dup before refspec (&-split)
probe allow "$FEAT_CWD" 'git push 2>&1 origin main'         # fd-dup before refspec (&-split)
probe allow "$FEAT_CWD" 'git push 1>&2 origin main'         # fd-dup before refspec (&-split)
probe allow "$FEAT_CWD" '2>/dev/null git merge feature'     # digit-led prefix
probe allow "$FEAT_CWD" '10>/tmp/log git push origin main'  # multi-digit fd prefix
probe allow "$MAIN_CWD" '>/tmp/foo\ bar git push origin main' # escaped-space prefix
# and the counterpart that IS caught: fd-dup AFTER the complete refspec
probe deny  "$FEAT_CWD" 'git push origin main 2>&1'         # refspec intact before &-split
probe allow "$FEAT_CWD" 'glab mr create --title "x" --description "y"'
probe allow "$FEAT_CWD" 'glab mr view 123'
probe allow "$FEAT_CWD" 'glab api "projects/:id/merge_requests/123/notes" -f body=hi'
probe allow "$FEAT_CWD" 'gh pr create --fill'
probe allow "$FEAT_CWD" 'gh pr view 45'
probe allow "$FEAT_CWD" 'git commit -m "revert glab mr merge guard"'
probe allow "$FEAT_CWD" 'echo "git push origin main"'
probe allow "$FEAT_CWD" 'git push origin --delete old-feature'
probe allow "$FEAT_CWD" 'git push origin main-backup'
probe allow "$FEAT_CWD" 'git fetch origin main'

# --- unresolvable default branch: allow stands, but degrade must be VISIBLE ---
out=$(jq -nc --arg c 'git push origin release-x' --arg w "$NOHEAD_FEAT_CWD" '{tool_input:{command:$c},cwd:$w}' | bash "$GUARD")
if printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then
  fail=$((fail+1)); echo "FAIL  nohead: push release-x unexpectedly denied (documented narrowing should allow)" >&2
elif printf '%s' "$out" | grep -q 'merge-authorization guard'; then
  pass=$((pass+1))
else
  fail=$((fail+1)); echo "FAIL  nohead: expected visible degrade warning, got: $out" >&2
fi
# fallback union gates the COMMON default names when unresolved
probe deny "$NOHEAD_FEAT_CWD" 'git push origin main'
probe deny "$NOHEAD_FEAT_CWD" 'git push origin trunk'
probe deny "$NOHEAD_FEAT_CWD" 'git push origin develop'
probe deny "$NOHEAD_FEAT_CWD" 'git push origin dev'
# non-push/merge commands must stay quiet (no warning noise)
out=$(jq -nc --arg c 'git status' --arg w "$NOHEAD_FEAT_CWD" '{tool_input:{command:$c},cwd:$w}' | bash "$GUARD")
if [ -z "$out" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL  nohead: git status should be silent, got: $out" >&2; fi

# --- DECLARED OUT-OF-SCOPE (documentation probes, not coverage claims) ---
# The guard does not evaluate shell expansion/substitution or heredoc
# bodies (see the guard header). These probes PIN the current allow
# behavior so a future refactor that starts denying them (over-block) or a
# doc change that silently promises coverage gets a failing, reviewable
# signal here. The prose layer (bootstrap + worktree-isolation) is the
# covering control for these spellings.
probe allow "$FEAT_CWD" 'D=main; git push origin $D'
probe allow "$FEAT_CWD" 'git push origin $(get-target-branch)'

# --- Release valve: user-directive one-shot sentinel (spec 007) ---
# The UserPromptSubmit hook arms a session-scoped sentinel; the guard
# consumes it (one-shot) and allows PLATFORM merge shapes only. These
# probes pin: consume-on-allow, no release for DENY_GIT shapes, compound
# poisoning, session scoping, staleness, and missing-session fail-closed.
VSID="sess-valve-test"
VAUTH_DIR="$tmp/ccl-skills-merge-auth-$(id -u)"
varm() { # varm [sid] [bound-mr-number]
  mkdir -p "$VAUTH_DIR"; chmod 700 "$VAUTH_DIR"
  printf "armed${2:+ $2}\n" >"$VAUTH_DIR/${1-$VSID}"
}

probe_sid() { # probe_sid <expect deny|allow> <cwd> <sid> <command>
  local expect="$1" cwd="$2" sid="$3" cmd="$4" out got
  out=$(jq -nc --arg c "$cmd" --arg w "$cwd" --arg s "$sid" \
    '{tool_input:{command:$c},cwd:$w,session_id:$s}' | TMPDIR="$tmp" bash "$GUARD")
  got="allow"
  printf '%s' "$out" | grep -q '"permissionDecision":"deny"' && got="deny"
  if [ "$got" = "$expect" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1)); printf 'FAIL  [valve want=%s got=%s]  %s\n' "$expect" "$got" "$cmd" >&2
  fi
}

sentinel_state() { # sentinel_state <present|absent> <label>
  local want="$1" label="$2"
  if { [ "$want" = present ] && [ -f "$VAUTH_DIR/$VSID" ]; } \
     || { [ "$want" = absent ] && [ ! -f "$VAUTH_DIR/$VSID" ]; }; then
    pass=$((pass+1))
  else
    fail=$((fail+1)); printf 'FAIL  [sentinel want=%s]  %s\n' "$want" "$label" >&2
  fi
}

http_release_consumes() { # http_release_consumes <label> <command>
  local label="$1" cmd="$2"
  varm
  probe_sid allow "$FEAT_CWD" "$VSID" "$cmd"
  sentinel_state absent "$label"
}

# armed -> platform merge (immediate spelling) allowed, sentinel consumed,
# second attempt denied
varm
probe_sid allow "$FEAT_CWD" "$VSID" 'glab mr merge 546 --auto-merge=false --yes'
sentinel_state absent 'consumed after allow'
probe_sid deny  "$FEAT_CWD" "$VSID" 'glab mr merge 546 --auto-merge=false --yes'

# armed -> merge REST API + gh pr merge also released (consumed each time)
varm
probe_sid allow "$FEAT_CWD" "$VSID" 'glab api projects/:id/merge_requests/546/merge -X PUT -f should_remove_source_branch=false'
sentinel_state absent 'consumed after api allow'
varm
probe_sid allow "$FEAT_CWD" "$VSID" 'gh pr merge 42 --squash'
sentinel_state absent 'consumed after gh allow'

# Every supported raw-HTTP PUT spelling is releasable by the same one-shot
# valve and consumes exactly one grant.
http_release_consumes 'curl -X PUT consumed' 'curl -X PUT https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
http_release_consumes 'curl -XPUT consumed' 'curl -XPUT https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
http_release_consumes 'curl --request PUT consumed' 'curl --request PUT https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
http_release_consumes 'curl --request=PUT consumed' 'curl --request=PUT http://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
http_release_consumes 'curl --silent consumed' 'curl -X PUT --silent https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
http_release_consumes 'curl -T consumed' 'curl -T payload.bin https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
http_release_consumes 'curl --upload-file consumed' 'curl --upload-file payload.bin https://git.example.invalid/repos/o/r/pulls/42/merge'
http_release_consumes 'curl --upload-file= consumed' 'curl --upload-file=payload.bin https://git.example.invalid/api/v3/repos/o/r/pulls/42/merge'
http_release_consumes 'wget --method PUT consumed' 'wget --method PUT https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
http_release_consumes 'wget --method=PUT consumed' 'wget --method=PUT https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
http_release_consumes 'wget -H consumed' 'wget --method PUT -H https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
http_release_consumes 'wget -d consumed' 'wget --method PUT -d https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
http_release_consumes 'wget -x consumed' 'wget --method PUT -x https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
http_release_consumes 'one merge among multiple URL operands consumes once' 'curl -X PUT https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge https://git.example.invalid/ordinary'

# Non-merge HTTP traffic must not consume a grant.
varm
probe_sid allow "$FEAT_CWD" "$VSID" 'curl https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
sentinel_state present 'HTTP GET merge path must not consume'
probe_sid allow "$FEAT_CWD" "$VSID" 'curl -X PUT https://git.example.invalid/ordinary'
sentinel_state present 'unrelated HTTP PUT must not consume'
probe_sid allow "$FEAT_CWD" "$VSID" 'curl --request POST https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
sentinel_state present 'HTTP POST merge path must not consume'
probe_sid allow "$FEAT_CWD" "$VSID" 'curl -X PUT https://git.example.invalid/ordinary -H https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
sentinel_state present 'HTTP header URL must not consume'
probe_sid allow "$FEAT_CWD" "$VSID" 'curl -X PUT --doh-url https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge https://git.example.invalid/ordinary'
sentinel_state present 'curl DoH URL must not consume'
varm
probe_sid allow "$FEAT_CWD" "$VSID" 'curl -X PUT --proxy https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge https://git.example.invalid/ordinary'
sentinel_state present 'curl proxy URL must not consume'
varm
probe_sid allow "$FEAT_CWD" "$VSID" 'curl -X PUT --user-agent https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge https://git.example.invalid/ordinary'
sentinel_state present 'curl user-agent text must not consume'
rm -f "$VAUTH_DIR/$VSID"

# Ambiguous/multiple raw-HTTP shapes and a compound hard deny are never
# released and leave the grant intact.
varm
probe_sid deny "$FEAT_CWD" "$VSID" 'curl -X PUT --cacert https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge https://git.example.invalid/ordinary'
sentinel_state present 'unknown option association must not consume'
varm
probe_sid allow "$FEAT_CWD" "$VSID" 'curl -X PUT -X POST https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
sentinel_state present 'last curl method POST must not consume'
probe_sid allow "$FEAT_CWD" "$VSID" 'curl -X POST --request PUT https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
sentinel_state absent 'last curl method PUT consumed'
varm
probe_sid deny "$FEAT_CWD" "$VSID" 'curl -X PUT https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge --next https://git.example.invalid/ordinary'
sentinel_state present 'curl --next ambiguity must not consume'
probe_sid deny "$FEAT_CWD" "$VSID" 'curl -X PUT https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge https://git.example.invalid/api/v4/projects/1/merge_requests/547/merge'
sentinel_state present 'multiple HTTP merge URLs must not consume'
probe_sid deny "$FEAT_CWD" "$VSID" 'curl -X PUT https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge && git push origin main'
sentinel_state present 'HTTP merge plus DENY_GIT must not consume'
rm -f "$VAUTH_DIR/$VSID"

# Number-bound grants use the id extracted from raw HTTP URLs.
varm "$VSID" 546
probe_sid deny "$FEAT_CWD" "$VSID" 'curl -X PUT https://git.example.invalid/api/v4/projects/1/merge_requests/999/merge'
sentinel_state present 'HTTP target mismatch must not consume'
probe_sid allow "$FEAT_CWD" "$VSID" 'curl -X PUT https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
sentinel_state absent 'matching HTTP target consumed'

# armed -> DENY_GIT shapes are NEVER released and do not consume the grant
varm
probe_sid deny "$FEAT_CWD" "$VSID" 'git push origin main'
sentinel_state present 'git-push deny must not consume'
probe_sid deny "$FEAT_CWD" "$VSID" 'glab mr merge 546 && git push origin main'
sentinel_state present 'compound with DENY_GIT must not consume'
rm -f "$VAUTH_DIR/$VSID"

# no sentinel / other-session sentinel / stale sentinel -> deny (fail-closed)
probe_sid deny "$FEAT_CWD" "$VSID" 'glab mr merge 546'
varm other-session
probe_sid deny "$FEAT_CWD" "$VSID" 'glab mr merge 546'
probe_sid deny "$FEAT_CWD" "$VSID" 'curl -X PUT https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
if [ -f "$VAUTH_DIR/other-session" ]; then
  pass=$((pass+1))
else
  fail=$((fail+1)); echo 'FAIL  wrong-session HTTP deny consumed another session grant' >&2
fi
rm -f "$VAUTH_DIR/other-session"
varm
old_ts=$(date -v-2H +%Y%m%d%H%M 2>/dev/null || date -d '-2 hours' +%Y%m%d%H%M)
touch -m -t "$old_ts" "$VAUTH_DIR/$VSID"
probe_sid deny "$FEAT_CWD" "$VSID" 'glab mr merge 546'
probe_sid deny "$FEAT_CWD" "$VSID" 'wget --method=PUT https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
rm -f "$VAUTH_DIR/$VSID"

# review round-1 findings: exactly-one-merge per grant; auto-merge/queued
# spellings are NEVER released (immediate-merge protocol), grant intact
varm
probe_sid deny "$FEAT_CWD" "$VSID" 'glab mr merge 1 && glab mr merge 2'
sentinel_state present 'multi-merge compound must not consume'
probe_sid deny "$FEAT_CWD" "$VSID" 'glab mr merge 546 --auto-merge'
sentinel_state present 'glab auto-merge must not be released nor consume'
probe_sid deny "$FEAT_CWD" "$VSID" 'gh pr merge 42 --auto --squash'
sentinel_state present 'gh --auto must not be released nor consume'
probe_sid deny "$FEAT_CWD" "$VSID" 'glab api projects/:id/merge_requests/546/merge -X PUT -f merge_when_pipeline_succeeds=true'
sentinel_state present 'REST merge_when_pipeline_succeeds must not be released'
probe_sid deny "$FEAT_CWD" "$VSID" "gh api graphql -f query='mutation { enablePullRequestAutoMerge(input:{pullRequestId:\"x\"}) }'"
sentinel_state present 'GraphQL auto-merge mutation must not be released'
# protocol-recommended immediate-merge spelling IS released
probe_sid allow "$FEAT_CWD" "$VSID" 'glab mr merge 546 --auto-merge=false --yes'
sentinel_state absent 'consumed after protocol spelling allow'
# a single GraphQL merge emits ONE verdict (REST+span double-count fixed)
varm
probe_sid allow "$FEAT_CWD" "$VSID" "glab api graphql -f query='mutation { mergeRequestAccept(input:{projectPath:\"g/p\",iid:\"546\"}) }'"
sentinel_state absent 'consumed after single graphql merge'

# challenge round-2: ambiguous spellings are NOT released (glab bare merge
# defaults to auto-merge while a pipeline runs; gh without an explicit
# strategy goes interactive/queue-dependent); --admin bypass never released;
# grant stays intact so the agent can rewrite and retry
varm
probe_sid deny "$FEAT_CWD" "$VSID" 'glab mr merge 546 --yes'
sentinel_state present 'bare glab merge (no --auto-merge=false) must not consume'
probe_sid deny "$FEAT_CWD" "$VSID" 'gh pr merge 42'
sentinel_state present 'gh merge without explicit strategy must not consume'
probe_sid deny "$FEAT_CWD" "$VSID" 'gh pr merge 42 --admin --merge'
sentinel_state present 'gh --admin bypass must not be released nor consume'
rm -f "$VAUTH_DIR/$VSID"

# challenge round-2: number-bound grant ("merge !546") releases ONLY that id
varm "$VSID" 546
probe_sid deny "$FEAT_CWD" "$VSID" 'glab mr merge 999 --auto-merge=false --yes'
sentinel_state present 'bound grant must not release a different MR'
probe_sid deny "$FEAT_CWD" "$VSID" "glab api graphql -f query='mutation { mergeRequestAccept(input:{projectPath:\"g/p\",iid:\"546\"}) }'"
sentinel_state present 'bound grant must not release an id-unresolvable merge'
probe_sid allow "$FEAT_CWD" "$VSID" 'glab mr merge 546 --auto-merge=false --yes'
sentinel_state absent 'bound grant consumed by the matching id'
varm "$VSID" 546
probe_sid allow "$FEAT_CWD" "$VSID" 'glab api projects/:id/merge_requests/546/merge -X PUT'
sentinel_state absent 'bound grant consumed by matching REST merge'

# challenge round-2: a GraphQL mutation string inside a NON-graphql REST body
# is not a merge — segment must not classify, grant must survive
varm
probe_sid allow "$FEAT_CWD" "$VSID" "gh api repos/o/r/issues -f body='mutation { mergePullRequest(input:{pullRequestId:\"x\"}) { pullRequest { merged } } }'"
sentinel_state present 'mutation text in non-graphql REST body must not consume'
rm -f "$VAUTH_DIR/$VSID"

# mktemp degrade path: unwritable TMPDIR -> visible degrade warning, no deny
out=$(jq -nc --arg c 'glab mr merge 546' --arg w "$FEAT_CWD" \
  '{tool_input:{command:$c},cwd:$w}' | TMPDIR="$tmp/nonexistent-tmpdir" bash "$GUARD")
if printf '%s' "$out" | grep -q 'degraded: mktemp failed' \
   && ! printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then
  pass=$((pass+1))
else
  fail=$((fail+1)); echo "FAIL  mktemp degrade must warn visibly and fail open, got: $out" >&2
fi

# final-review P2: a method-less (default GET) call to a merge REST endpoint
# must not burn the grant — deny without consuming until -X PUT is explicit
varm
probe_sid deny "$FEAT_CWD" "$VSID" 'glab api projects/:id/merge_requests/546/merge'
sentinel_state present 'GET-default REST merge call must not consume'
rm -f "$VAUTH_DIR/$VSID"

# host-compat: Claude Code (CLAUDECODE=1) gets permissionDecision:"allow"
# (no popup); other hosts (codex bridge rejects "allow") get advisory
# systemMessage ONLY — no permissionDecision at all. Both consume the grant.
varm
out=$(jq -nc --arg c 'glab mr merge 546 --auto-merge=false --yes' --arg w "$FEAT_CWD" --arg s "$VSID" --arg t "$HOME/.claude/projects/x/transcript.jsonl" \
  '{tool_input:{command:$c},cwd:$w,session_id:$s,transcript_path:$t}' \
  | TMPDIR="$tmp" CLAUDECODE=1 CODEX_THREAD_ID= CODEX_SANDBOX= CODEX_CI= CODEX_MANAGED_BY_NPM= CODEX_HOME= bash "$GUARD")
if printf '%s' "$out" | grep -q '"permissionDecision":"allow"'; then pass=$((pass+1)); else
  fail=$((fail+1)); echo "FAIL  full claude signals must emit permissionDecision allow, got: $out" >&2
fi
sentinel_state absent 'claude-host allow consumed'
# CLAUDECODE=1 + clean env but NO .claude transcript_path (a stripped-env
# codex-like bridge) -> advisory only: the positive input signal is required
varm
out=$(jq -nc --arg c 'glab mr merge 546 --auto-merge=false --yes' --arg w "$FEAT_CWD" --arg s "$VSID" \
  '{tool_input:{command:$c},cwd:$w,session_id:$s}' \
  | TMPDIR="$tmp" CLAUDECODE=1 CODEX_THREAD_ID= CODEX_SANDBOX= CODEX_CI= CODEX_MANAGED_BY_NPM= CODEX_HOME= bash "$GUARD")
if printf '%s' "$out" | grep -q 'systemMessage' && ! printf '%s' "$out" | grep -q 'permissionDecision'; then
  pass=$((pass+1))
else
  fail=$((fail+1)); echo "FAIL  missing .claude transcript_path must emit advisory only, got: $out" >&2
fi
sentinel_state absent 'no-transcript advisory release still consumed'
# nested host: codex spawned from Claude inherits CLAUDECODE=1 but carries
# codex-positive signals -> advisory only (never the rejected allow field)
varm
out=$(jq -nc --arg c 'glab mr merge 546 --auto-merge=false --yes' --arg w "$FEAT_CWD" --arg s "$VSID" \
  '{tool_input:{command:$c},cwd:$w,session_id:$s}' \
  | TMPDIR="$tmp" CLAUDECODE=1 CODEX_THREAD_ID=t1 bash "$GUARD")
if printf '%s' "$out" | grep -q 'systemMessage' && ! printf '%s' "$out" | grep -q 'permissionDecision'; then
  pass=$((pass+1))
else
  fail=$((fail+1)); echo "FAIL  nested codex host must emit advisory only, got: $out" >&2
fi
sentinel_state absent 'nested-host advisory release still consumed'
varm
out=$(jq -nc --arg c 'glab mr merge 546 --auto-merge=false --yes' --arg w "$FEAT_CWD" --arg s "$VSID" \
  '{tool_input:{command:$c},cwd:$w,session_id:$s}' | TMPDIR="$tmp" CLAUDECODE= bash "$GUARD")
if printf '%s' "$out" | grep -q 'systemMessage' && ! printf '%s' "$out" | grep -q 'permissionDecision'; then
  pass=$((pass+1))
else
  fail=$((fail+1)); echo "FAIL  non-claude host must emit systemMessage only, got: $out" >&2
fi
sentinel_state absent 'non-claude-host advisory release still consumed'

# challenge round-3: `glab mr accept` is the documented merge alias — same
# gate, same valve, same multi-merge accounting
probe deny "$FEAT_CWD" 'glab mr accept 546'
varm
probe_sid allow "$FEAT_CWD" "$VSID" 'glab mr accept 546 --auto-merge=false --yes'
sentinel_state absent 'accept alias consumed like merge'
varm
probe_sid deny "$FEAT_CWD" "$VSID" 'glab mr accept 1 --auto-merge=false --yes && glab mr merge 2 --auto-merge=false --yes'
sentinel_state present 'accept+merge compound counts as two merges'
rm -f "$VAUTH_DIR/$VSID"

# challenge round-3: inline config and repo retargeting count
probe deny "$FEAT_CWD" 'git -c push.default=matching push origin'
probe deny "$FEAT_CWD" "git --git-dir=$MAIN_CWD/.git merge feature"
probe deny "$FEAT_CWD" "git --work-tree=$MAIN_CWD --git-dir=$MAIN_CWD/.git merge feature"

# challenge round-3: a number-bound grant must not release an explicit
# cross-repo retarget (-R): 546 in another repo is a different MR
varm "$VSID" 546
probe_sid deny "$FEAT_CWD" "$VSID" 'glab mr merge 546 -R other/repo --auto-merge=false --yes'
sentinel_state present 'bound grant must not release -R retarget'
probe_sid deny "$FEAT_CWD" "$VSID" 'gh -R other/repo pr merge 546 --squash'
sentinel_state present 'bound grant must not release gh -R retarget'
# value-taking flags before the id must not corrupt id extraction
probe_sid allow "$FEAT_CWD" "$VSID" 'glab mr merge --sha abc123 546 --auto-merge=false --yes'
sentinel_state absent 'value flag before id still resolves the bound id'
varm
probe_sid allow "$FEAT_CWD" "$VSID" 'gh pr merge 42 --match-head-commit deadbeef --squash'
sentinel_state absent 'gh value flag before id still releases'
# DOCUMENTATION PROBE (residual, spec 007): an UNBOUND grant still releases
# an explicit -R retarget — the duty to target the discussed MR stays with
# the agent prose contract. Pins current behavior for reviewability.
varm
probe_sid allow "$FEAT_CWD" "$VSID" 'glab mr merge 546 -R other/repo --auto-merge=false --yes'
sentinel_state absent 'unbound grant + -R (pinned residual)'

# armed -> non-merge commands never touch the grant
varm
probe_sid allow "$FEAT_CWD" "$VSID" 'git status'
sentinel_state present 'non-merge command must not consume'
rm -f "$VAUTH_DIR/$VSID"

# no session_id in input (legacy probe path) stays hard-deny even when a
# sentinel file exists for some session
varm
probe deny "$FEAT_CWD" 'glab mr merge 546'
rm -f "$VAUTH_DIR/$VSID"

# --- Batch grant (spec 008): `armed batch N` — one unit per platform merge ---
varm_batch() { # varm_batch <count> [sid]
  mkdir -p "$VAUTH_DIR"; chmod 700 "$VAUTH_DIR"
  printf 'armed batch %s\n' "$1" >"$VAUTH_DIR/${2-$VSID}"
}
sentinel_content() { # sentinel_content <expected-first-line> <label>
  local want="$1" label="$2" got
  got=$(sed -n '1p' "$VAUTH_DIR/$VSID" 2>/dev/null || echo '<absent>')
  if [ "$got" = "$want" ]; then pass=$((pass+1)); else
    fail=$((fail+1)); printf 'FAIL  [sentinel-content want=%s got=%s]  %s\n' "$want" "$got" "$label" >&2
  fi
}

# decrement chain: 3 -> 2 -> 1 -> consumed -> deny
varm_batch 3
probe_sid allow "$FEAT_CWD" "$VSID" 'glab mr merge 101 --auto-merge=false --yes'
sentinel_content 'armed batch 2' 'batch decrements to 2'
probe_sid allow "$FEAT_CWD" "$VSID" 'gh pr merge 202 --squash'
sentinel_content 'armed batch 1' 'batch decrements to 1'
probe_sid allow "$FEAT_CWD" "$VSID" 'glab api projects/:id/merge_requests/303/merge -X PUT'
sentinel_state absent 'last batch unit fully consumed'
probe_sid deny "$FEAT_CWD" "$VSID" 'glab mr merge 404 --auto-merge=false --yes'

# Raw HTTP merges consume the same batch counter one unit at a time.
varm_batch 2
probe_sid allow "$FEAT_CWD" "$VSID" 'curl -X PUT https://git.example.invalid/api/v4/projects/1/merge_requests/546/merge'
sentinel_content 'armed batch 1' 'HTTP merge decrements batch to 1'
probe_sid allow "$FEAT_CWD" "$VSID" 'wget --method=PUT https://git.example.invalid/repos/o/r/pulls/42/merge'
sentinel_state absent 'last batch unit consumed by HTTP merge'

# batch grant is UNBOUND: different repos/ids release (units still counted)
varm_batch 2
probe_sid allow "$FEAT_CWD" "$VSID" 'glab mr merge 546 -R other/repo --auto-merge=false --yes'
sentinel_content 'armed batch 1' 'batch unbound retarget consumed one unit'
rm -f "$VAUTH_DIR/$VSID"

# batch + bad spelling: deny WITHOUT consuming (agent rewrites and retries)
varm_batch 5
probe_sid deny "$FEAT_CWD" "$VSID" 'glab mr merge 546 --yes'
sentinel_content 'armed batch 5' 'bad spelling must not burn a batch unit'
# batch + DENY_GIT / auto-merge / multi-merge compound: never released, intact
probe_sid deny "$FEAT_CWD" "$VSID" 'git push origin main'
sentinel_content 'armed batch 5' 'DENY_GIT must not touch batch grant'
probe_sid deny "$FEAT_CWD" "$VSID" 'glab mr merge 546 --auto-merge'
sentinel_content 'armed batch 5' 'auto-merge never released under batch'
probe_sid deny "$FEAT_CWD" "$VSID" 'glab mr merge 1 --auto-merge=false --yes && glab mr merge 2 --auto-merge=false --yes'
sentinel_content 'armed batch 5' 'multi-merge compound denied under batch (split = one unit each)'
probe_sid deny "$FEAT_CWD" "$VSID" 'curl -X PUT https://git.example.invalid/api/v4/projects/1/merge_requests/1/merge https://git.example.invalid/api/v4/projects/1/merge_requests/2/merge'
sentinel_content 'armed batch 5' 'multi-HTTP merge denied without batch consumption'
probe_sid allow "$FEAT_CWD" "$VSID" 'curl -X PUT --request POST https://git.example.invalid/api/v4/projects/1/merge_requests/1/merge'
sentinel_content 'armed batch 5' 'last curl method POST leaves batch intact'
# non-merge commands never touch batch units
probe_sid allow "$FEAT_CWD" "$VSID" 'git push origin feature'
sentinel_content 'armed batch 5' 'non-merge command must not consume batch unit'
rm -f "$VAUTH_DIR/$VSID"

# batch TTL is 240 min anchored to arming: 3h-old grant still fresh,
# 5h-old grant stale (one-shot stays 60 min — 2h-old one-shot already denies
# above). Decrement must PRESERVE the arming mtime, not refresh it.
varm_batch 2
old_ts=$(date -v-3H +%Y%m%d%H%M 2>/dev/null || date -d '-3 hours' +%Y%m%d%H%M)
touch -m -t "$old_ts" "$VAUTH_DIR/$VSID"
probe_sid allow "$FEAT_CWD" "$VSID" 'glab mr merge 546 --auto-merge=false --yes'
sentinel_content 'armed batch 1' '3h-old batch grant still releases'
# mtime preserved through the decrement: file must still be ~3h old
if [ -z "$(find "$VAUTH_DIR/$VSID" -mmin -170 2>/dev/null)" ]; then pass=$((pass+1)); else
  fail=$((fail+1)); echo 'FAIL  batch decrement must preserve arming mtime (found fresher than 170min)' >&2
fi
rm -f "$VAUTH_DIR/$VSID"
varm_batch 9
old_ts=$(date -v-5H +%Y%m%d%H%M 2>/dev/null || date -d '-5 hours' +%Y%m%d%H%M)
touch -m -t "$old_ts" "$VAUTH_DIR/$VSID"
probe_sid deny "$FEAT_CWD" "$VSID" 'glab mr merge 546 --auto-merge=false --yes'
rm -f "$VAUTH_DIR/$VSID"

# malformed batch grants are NO grant (fail-closed): zero, junk, leading zero,
# >999
for bad in 0 abc 007 1000; do
  varm_batch "$bad"
  probe_sid deny "$FEAT_CWD" "$VSID" 'glab mr merge 546 --auto-merge=false --yes'
  rm -f "$VAUTH_DIR/$VSID"
done

# challenge R2 P0: a GraphQL body with multiple aliased merge mutations must
# deny (multi) and NOT consume — one command must not execute several merges
varm_batch 5
probe_sid deny "$FEAT_CWD" "$VSID" "glab api graphql -f query='mutation { a: mergeRequestAccept(input:{projectPath:\"g/p\",iid:\"1\"}){x} b: mergeRequestAccept(input:{projectPath:\"g/p\",iid:\"2\"}){x} }'"
sentinel_content 'armed batch 5' 'multi-alias graphql merge denied, batch intact'
probe_sid deny "$FEAT_CWD" "$VSID" "gh api graphql -f query='mutation { a: mergePullRequest(input:{pullRequestId:\"x\"}){x} b: mergePullRequest(input:{pullRequestId:\"y\"}){x} }'"
sentinel_content 'armed batch 5' 'multi-alias gh graphql merge denied, batch intact'
rm -f "$VAUTH_DIR/$VSID"

# challenge R2 P0: a loop body `for … do glab mr merge …; done` splits to a
# `do glab …` segment — the leading `do` keyword must be stripped so the
# merge is still detected (denied when no grant present)
probe deny "$FEAT_CWD" 'for id in 1 2; do glab mr merge $id --auto-merge=false --yes; done'
probe deny "$FEAT_CWD" 'if true; then glab mr merge 5 --auto-merge=false --yes; fi'

# session lock (review P1): a FRESH lock held by a peer → deny WITHOUT
# consuming (fail-closed; agent retries); a STALE (≥1 min) lock is broken
# and the consume proceeds; the guard releases the lock on exit.
GLOCK="$VAUTH_DIR/$VSID.lock"
varm_batch 3
mkdir "$GLOCK"
probe_sid deny "$FEAT_CWD" "$VSID" 'glab mr merge 546 --auto-merge=false --yes'
sentinel_content 'armed batch 3' 'held fresh lock must deny without consuming'
rmdir "$GLOCK" 2>/dev/null
varm_batch 3
mkdir "$GLOCK"
old_ts=$(date -v-5M +%Y%m%d%H%M 2>/dev/null || date -d '-5 minutes' +%Y%m%d%H%M)
touch -t "$old_ts" "$GLOCK"
probe_sid allow "$FEAT_CWD" "$VSID" 'glab mr merge 546 --auto-merge=false --yes'
sentinel_content 'armed batch 2' 'stale lock broken, unit consumed'
if [ ! -d "$GLOCK" ]; then pass=$((pass+1)); else
  fail=$((fail+1)); echo 'FAIL  guard must release the lock on exit' >&2
fi
rm -f "$VAUTH_DIR/$VSID"

# batch release reports remaining units in the visible systemMessage
varm_batch 3
out=$(jq -nc --arg c 'glab mr merge 546 --auto-merge=false --yes' --arg w "$FEAT_CWD" --arg s "$VSID" \
  '{tool_input:{command:$c},cwd:$w,session_id:$s}' | TMPDIR="$tmp" CLAUDECODE= bash "$GUARD")
if printf '%s' "$out" | grep -q '剩余 2 个'; then pass=$((pass+1)); else
  fail=$((fail+1)); echo "FAIL  batch release must report remaining units, got: $out" >&2
fi
rm -f "$VAUTH_DIR/$VSID"

# --- degrade: malformed input must fail-open (allow, no output) ---
out=$(printf '{}' | bash "$GUARD")
if [ -z "$out" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL  empty input -> $out" >&2; fi
out=$(printf 'not-json' | bash "$GUARD")
if [ -z "$out" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL  bad json -> $out" >&2; fi

# --- POSIX reserved words that can prefix a simple command ---------------
# Regression for a class that silently bypassed a gate whose entire job is
# stopping an unauthorized merge. `if <merge>; then …; fi` is an ordinary
# scripted spelling, not the eval/subshell obfuscation the header excludes.
# The stripped set is closed (derived from the POSIX reserved-word list), so
# these pin the whole class, not just the instances that were reported.
probe deny "$FEAT_CWD" 'if glab mr merge 546 --yes; then echo ok; fi'
probe deny "$FEAT_CWD" 'if git push origin main; then echo ok; fi'
probe deny "$FEAT_CWD" 'while glab mr merge 546 --yes; do echo x; done'
probe deny "$FEAT_CWD" 'until glab mr merge 546 --yes; do :; done'
probe deny "$FEAT_CWD" '! git push origin main'
# The words themselves must stay inert in prose.
probe allow "$FEAT_CWD" 'echo if merge and while merge'
probe allow "$FEAT_CWD" 'git push origin feature-if'
# Transparent special builtins are the same bypass class as the reserved words
# above, and were still open after the first pass at this fix.
probe deny "$FEAT_CWD" 'exec git push origin main'
probe deny "$FEAT_CWD" 'exec glab mr merge 546 --yes'
probe deny "$FEAT_CWD" 'builtin git push origin main'
probe allow "$FEAT_CWD" 'exec git push origin feature-x'

# ---- -C target legibility ----------------------------------------------------
# Merging main INTO a feature worktree is an ALLOWED shape, and `git -C <wt> merge
# origin/main` from the main checkout is how it gets written. That works only when the
# target is legible: this guard reads command TEXT, so a variable target cannot be
# expanded and the branch context falls back to the cwd (fail-closed, since the unknown
# path may be the default checkout). Both verdicts are pinned here so neither drifts,
# plus the deny REASON — an accurate reason is the whole point, because a deny that
# blames "advances main" for an unexpandable variable reads as a broken gate and trains
# people to route around it.
probe allow "$MAIN_CWD" "git -C $FEAT_CWD merge origin/main --no-edit"
probe allow "$MAIN_CWD" "git -C $FEAT_CWD merge main"
probe deny  "$MAIN_CWD" 'git -C "$WT" merge origin/main --no-edit'
probe deny  "$MAIN_CWD" 'git -C "$WT" push origin main'
# …and the unresolved fallback must never become an ALLOW: an unknown -C target on a
# genuinely default-advancing shape stays denied even from a feature worktree.
probe deny  "$FEAT_CWD" 'git -C "$SOMEWHERE" push origin main'

reason_has() { # reason_has <want-substring|!want> <cwd> <cmd>
  local want="$1" cwd="$2" cmd="$3" out
  out=$(jq -nc --arg c "$cmd" --arg w "$cwd" '{tool_input:{command:$c},cwd:$w}' | bash "$GUARD")
  case "$want" in
    '!'*) if printf '%s' "$out" | grep -q -- "${want#!}"; then
            fail=$((fail+1)); printf 'FAIL  [reason should NOT mention %s]  %s\n' "${want#!}" "$cmd" >&2
          else pass=$((pass+1)); fi ;;
    *)    if printf '%s' "$out" | grep -q -- "$want"; then pass=$((pass+1))
          else fail=$((fail+1)); printf 'FAIL  [reason missing %s]  %s\n' "$want" "$cmd" >&2; fi ;;
  esac
}
# The unexpandable-target deny explains itself and offers the literal-path escape…
reason_has '展开不了'  "$MAIN_CWD" 'git -C "$WT" merge origin/main --no-edit'
reason_has '字面绝对路径' "$MAIN_CWD" 'git -C "$WT" merge origin/main --no-edit'
# …while a REAL default-branch advance keeps the original, more severe reason.
reason_has '!展开不了' "$MAIN_CWD" 'git merge origin/main'
reason_has '直接推进'  "$MAIN_CWD" 'git merge origin/main'

if [ "$fail" -ne 0 ]; then
  echo "test_guard_merge_authorization: FAIL pass=$pass fail=$fail" >&2
  exit 1
fi
echo "test_guard_merge_authorization_ok pass=$pass"
