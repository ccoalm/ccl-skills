#!/usr/bin/env bash
# Synthetic tests for worktree-status.sh. Uses only local temporary git repos.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
STATUS_SCRIPT="$SCRIPT_DIR/worktree-status.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/worktree-status-test.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_contains() { case "$1" in *"$2"*) : ;; *) fail "expected output to contain: $2\n--- output ---\n$1" ;; esac; }
assert_rc() { [ "$1" = "$2" ] || fail "expected rc=$2 got rc=$1"; }

git_init_repo() {
  local repo="$1" bare="$2"
  git init --bare "$bare" >/dev/null
  git init -b main "$repo" >/dev/null
  git -C "$repo" config user.email test@example.invalid
  git -C "$repo" config user.name "Test User"
  printf 'base\n' > "$repo/file.txt"
  git -C "$repo" add file.txt
  git -C "$repo" commit -m base >/dev/null
  git -C "$repo" remote add origin "$bare"
  git -C "$repo" push -u origin main >/dev/null 2>&1
  git -C "$bare" symbolic-ref HEAD refs/heads/main
  git -C "$repo" remote set-head origin -a >/dev/null 2>&1
}

run_status() {
  local dir="$1"; shift
  set +e
  out="$(cd "$dir" && bash "$STATUS_SCRIPT" "$@" 2>&1)"
  rc=$?
  set -e
}

REPO="$TMP/repo"
BARE="$TMP/origin.git"
git_init_repo "$REPO" "$BARE"

run_status "$TMP" --slug demo
assert_rc "$rc" 2
assert_contains "$out" "not inside a git repo"

run_status "$REPO" --slug
assert_rc "$rc" 2
assert_contains "$out" "--slug requires a value"

run_status "$REPO" --slug demo
assert_rc "$rc" 1
assert_contains "$out" "worktree-status: UNSAFE"
assert_contains "$out" "suggested command: git worktree add -b 'worktree-demo' '$REPO/.work/worktrees/demo' 'origin/main'"
assert_contains "$out" "lane metadata path: $REPO/.work/lanes/demo.json"

run_status "$REPO" --slug demo --branch feature/demo
assert_rc "$rc" 1
assert_contains "$out" "suggested command: git worktree add -b 'feature/demo' '$REPO/.work/worktrees/demo' 'origin/main'"

run_status "$REPO" --slug demo --base missing/ref --json
assert_rc "$rc" 1
assert_contains "$out" '"status": "unsafe"'
assert_contains "$out" '"base_found": false'
assert_contains "$out" '"base ref not found; pass --base"'

NOHEAD_REPO="$TMP/no-origin-head"
NOHEAD_BARE="$TMP/no-origin-head.git"
git_init_repo "$NOHEAD_REPO" "$NOHEAD_BARE"
git -C "$NOHEAD_REPO" symbolic-ref --delete refs/remotes/origin/HEAD >/dev/null 2>&1 || true
git -C "$NOHEAD_REPO" branch develop origin/main
DEVELOP_WT="$TMP/no-origin-head-develop"
git -C "$NOHEAD_REPO" worktree add "$DEVELOP_WT" develop >/dev/null 2>&1
run_status "$DEVELOP_WT" --slug develop
assert_rc "$rc" 1
assert_contains "$out" "default/base branch not confirmed; pass --base"
run_status "$DEVELOP_WT" --slug develop --json
assert_rc "$rc" 1
assert_contains "$out" '"base_confirmed": false'
printf '%s' "$out" | python3 -m json.tool >/dev/null

FEATURE_WT="$TMP/repo-demo"
git -C "$REPO" worktree add -b feature/demo "$FEATURE_WT" origin/main >/dev/null 2>&1
run_status "$FEATURE_WT" --slug demo
assert_rc "$rc" 0
assert_contains "$out" "worktree-status: SAFE"
assert_contains "$out" "independent-worktree: 1"
assert_contains "$out" "primary root: $REPO"
assert_contains "$out" "lane metadata path: $REPO/.work/lanes/demo.json"
# Independent feature worktree outside .work/worktrees stays SAFE but reports
# in-.work: 0 and emits the non-blocking out-of-convention warning.
assert_contains "$out" "in-.work: 0"
assert_contains "$out" "warning: safe worktree is outside .work/worktrees; use .work/worktrees for new lanes"

run_status "$FEATURE_WT" --slug nested --branch feature/nested
assert_rc "$rc" 0
assert_contains "$out" "primary root: $REPO"
assert_contains "$out" "lane metadata path: $REPO/.work/lanes/nested.json"
case "$out" in *"$FEATURE_WT/.work/worktrees/nested"*) fail "suggested path must not be nested under current feature worktree" ;; esac

DETACHED_WT="$TMP/repo-detached"
git -C "$REPO" worktree add --detach "$DETACHED_WT" origin/main >/dev/null 2>&1
run_status "$DETACHED_WT" --slug detached
assert_rc "$rc" 1
assert_contains "$out" "detached HEAD"

printf 'dirty\n' >> "$FEATURE_WT/file.txt"
run_status "$FEATURE_WT" --slug demo
assert_rc "$rc" 1
assert_contains "$out" "dirty or untracked files present"
git -C "$FEATURE_WT" checkout -- file.txt
printf 'new\n' > "$FEATURE_WT/new.txt"
run_status "$FEATURE_WT" --slug demo
assert_rc "$rc" 1
assert_contains "$out" "dirty or untracked files present"
rm "$FEATURE_WT/new.txt"

run_status "$FEATURE_WT" --slug demo --json
assert_rc "$rc" 0
assert_contains "$out" '"status": "safe"'
assert_contains "$out" '"is_independent_worktree": true'
assert_contains "$out" '"primary_root":'
assert_contains "$out" '"suggested_worktree_path":'
assert_contains "$out" '"in_work_dir": false'
assert_contains "$out" '"outside_work_dir_warning": true'
assert_contains "$out" '"worktrees": ['
printf '%s' "$out" | python3 -m json.tool >/dev/null

# git status failure must fail CLOSED: undetermined cleanliness => UNSAFE, never a
# false clean/SAFE. Corrupt the otherwise-SAFE worktree's index so `git status`
# errors, and assert the verdict flips to UNSAFE with the cleanliness reason.
# (FEATURE_WT is not reused after this point.)
FEATURE_GITDIR="$(git -C "$FEATURE_WT" rev-parse --absolute-git-dir)"
printf 'GARBAGEGARBAGE' > "$FEATURE_GITDIR/index"
run_status "$FEATURE_WT" --slug demo
assert_rc "$rc" 1
assert_contains "$out" "worktree-status: UNSAFE"
assert_contains "$out" "could not determine worktree cleanliness (git status failed)"

SPACE_REPO="$TMP/repo with space"
SPACE_BARE="$TMP/origin space.git"
git_init_repo "$SPACE_REPO" "$SPACE_BARE"
run_status "$SPACE_REPO" --slug space-demo
assert_rc "$rc" 1
assert_contains "$out" "suggested command: git worktree add -b 'worktree-space-demo' '$SPACE_REPO/.work/worktrees/space-demo' 'origin/main'"

# Independent worktree checked out on main is UNSAFE — directly assert the
# never-develop-on-main red line.
MAINWT_REPO="$TMP/mainwt"
MAINWT_BARE="$TMP/mainwt.git"
git_init_repo "$MAINWT_REPO" "$MAINWT_BARE"
# Park the primary checkout on another branch so main is free to link.
git -C "$MAINWT_REPO" checkout -b parking >/dev/null 2>&1
MAIN_ON_MAIN="$TMP/mainwt-on-main"
git -C "$MAINWT_REPO" worktree add "$MAIN_ON_MAIN" main >/dev/null 2>&1
run_status "$MAIN_ON_MAIN" --slug onmain
assert_rc "$rc" 1
assert_contains "$out" "worktree-status: UNSAFE"
assert_contains "$out" "independent-worktree: 1"
assert_contains "$out" "current branch is empty/default/base"

# Submodule checkout is UNSAFE and names the submodule reason.
SUBSRC="$TMP/subsrc"
git init -b main "$SUBSRC" >/dev/null
git -C "$SUBSRC" config user.email test@example.invalid
git -C "$SUBSRC" config user.name "Test User"
printf 'sub\n' > "$SUBSRC/s.txt"
git -C "$SUBSRC" add s.txt
git -C "$SUBSRC" commit -m sub >/dev/null
SUPER="$TMP/super"
git init -b main "$SUPER" >/dev/null
git -C "$SUPER" config user.email test@example.invalid
git -C "$SUPER" config user.name "Test User"
printf 'base\n' > "$SUPER/f.txt"
git -C "$SUPER" add f.txt
git -C "$SUPER" commit -m base >/dev/null
git -C "$SUPER" -c protocol.file.allow=always submodule add "$SUBSRC" sub >/dev/null 2>&1
git -C "$SUPER" commit -m "add sub" >/dev/null 2>&1
run_status "$SUPER/sub" --slug sub
assert_rc "$rc" 1
assert_contains "$out" "worktree-status: UNSAFE"
assert_contains "$out" "inside a submodule"

# python3-less JSON fallback escaping: build a PATH that excludes python3 and
# confirm the lane metadata snippet is still valid JSON with tricky characters.
NOPY="$TMP/nopy-bin"
mkdir -p "$NOPY"
for tool in bash sh git awk sed tr grep wc basename dirname cat env; do
  tp="$(command -v "$tool" 2>/dev/null || true)"
  [ -n "$tp" ] && ln -sf "$tp" "$NOPY/$tool"
done
if PATH="$NOPY" command -v python3 >/dev/null 2>&1; then
  echo "WARN: python3 still resolvable in sandbox PATH; skipping fallback escaping test" >&2
else
  TRICKY='weird"ref\back	tab'
  set +e
  fb_out="$(cd "$REPO" && PATH="$NOPY" bash "$STATUS_SCRIPT" --slug demo --base "$TRICKY" 2>&1)"
  set -e
  fb_snip="$(printf '%s\n' "$fb_out" | sed -n 's/^lane metadata snippet: //p')"
  [ -n "$fb_snip" ] || fail "fallback snippet not found in output\n--- output ---\n$fb_out"
  # Validate with the real python3 (available in the test environment).
  printf '%s' "$fb_snip" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["base"]=="weird\"ref\\back\ttab", repr(d["base"])' \
    || fail "fallback snippet is not valid/escaped JSON: $fb_snip"
fi

echo "test_worktree_status: ok"
