#!/usr/bin/env bash
# worktree-sweep — remove local git worktrees whose branch is already integrated
# (its tip is an ancestor of an integration ref). Safe by construction:
#   - DRY-RUN by default; only --apply actually removes anything.
#   - Removes ONLY a worktree whose branch tip is fully merged into one of the integration
#     refs (`git merge-base --is-ancestor`). Squash-merged branches are NOT ancestors -> kept.
#   - The integration target is NOT assumed to be main: when origin/HEAD confirms the
#     default branch, default-branch targets are kept for manual/platform-MR verification.
#     Non-default development targets may be passed explicitly (merged into ANY -> sweepable).
#   - NEVER the main worktree, the repo default branch, a target branch, a bare/detached
#     worktree, or a worktree with ANY uncommitted/untracked/IGNORED local file (ignored
#     files block too, because `git worktree remove` without --force still deletes them).
#     A worktree whose own `git status` FAILS is also kept: empty output from a failed
#     scan is never read as "clean" (fail closed, same rule as the manual pre-scan).
#     `git worktree remove` without --force is a second net for tracked/untracked dirt.
#   - Deletes the local branch with `git branch -d` (never -D). NEVER touches any remote
#     (remote-branch deletion is a separate, explicit step in the worktree-isolation 收尾 doc).
#   - `git worktree prune` runs ONLY under --apply (dry-run mutates nothing).
#
# Usage:  worktree-sweep.sh [<integration-ref> ...] [--apply] [--include-ignored]
#   <integration-ref> ...  default: origin/HEAD's branch, else main, else master.
#                          e.g. `worktree-sweep.sh release/v2 --apply`
#   --include-ignored      allow removing a worktree whose ONLY local content is ignored
#                          (regenerable, e.g. node_modules); real dirty/untracked still blocks.
#                          DESTRUCTIVE: it also deletes gitignored DATA products, so read the
#                          KEEP reasons before reaching for it. Regenerable output (deps,
#                          build/test artifacts, caches, logs) is fine to drop; keep anything
#                          expensive to recompute (long-running intermediates, collected data).
#
# Exit: 0 on success (incl. "nothing to do"); 2 on usage/setup error. Per-worktree failures
# are reported and skipped; they never abort the whole sweep.

set -uo pipefail

APPLY=0
INCLUDE_IGNORED=0
TARGETS=()
EXPLICIT_TARGETS=0
for a in "$@"; do
  case "$a" in
    --apply)           APPLY=1 ;;
    --include-ignored) INCLUDE_IGNORED=1 ;;
    -h|--help)         sed -n '2,30p' "$0"; exit 0 ;;
    --*)               echo "worktree-sweep: unknown flag '$a'" >&2; exit 2 ;;
    *)                 TARGETS+=("$a"); EXPLICIT_TARGETS=1 ;;
  esac
done

git rev-parse --git-dir >/dev/null 2>&1 || { echo "worktree-sweep: not inside a git repo" >&2; exit 2; }

# Confirm repo default branch from origin/HEAD only. If the local symref is absent,
# try the remote symref; if both fail, default-target safety cannot be proven.
DEFAULT_CONFIRMED=0
DEFAULT_BRANCH="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
if [ -n "$DEFAULT_BRANCH" ]; then
  DEFAULT_CONFIRMED=1
elif git remote get-url origin >/dev/null 2>&1; then
  DEFAULT_BRANCH="$(git ls-remote --symref origin HEAD 2>/dev/null | sed -n 's#^ref: refs/heads/\([^[:space:]]*\)[[:space:]]*HEAD$#\1#p' | head -n 1)"
  [ -n "$DEFAULT_BRANCH" ] && DEFAULT_CONFIRMED=1
fi

# Default integration ref if none given: repo default branch via confirmed origin/HEAD.
# Default-branch sweeping is intentionally manual-only, so no-arg invocation exits with a
# clear message after default detection instead of silently doing nothing.
if [ "${#TARGETS[@]}" -eq 0 ]; then
  d="$DEFAULT_BRANCH"
  [ -n "$d" ] && TARGETS=("$d")
fi
[ "${#TARGETS[@]}" -gt 0 ] || { echo "worktree-sweep: cannot determine integration ref; pass one explicitly" >&2; exit 2; }
for t in "${TARGETS[@]}"; do
  git rev-parse --verify --quiet "${t}^{commit}" >/dev/null 2>&1 \
    || { echo "worktree-sweep: integration ref '$t' not found" >&2; exit 2; }
done
TARGETS_STR="$(IFS=', '; echo "${TARGETS[*]}")"

DEFAULT_NAMES=()
[ -n "$DEFAULT_BRANCH" ] && DEFAULT_NAMES+=("$DEFAULT_BRANCH")
DEFAULT_COMMIT=""
[ "$DEFAULT_CONFIRMED" = 1 ] && DEFAULT_COMMIT="$(git rev-parse --verify --quiet "refs/remotes/origin/$DEFAULT_BRANCH^{commit}" 2>/dev/null || git rev-parse --verify --quiet "refs/heads/$DEFAULT_BRANCH^{commit}" 2>/dev/null || true)"

# Protected branch names = default branch + each target normalized to a local short name
# (so `origin/release`, `refs/heads/release`, `release` all protect a worktree on `release`).
PROTECTED=()
[ -n "$DEFAULT_BRANCH" ] && PROTECTED+=("$DEFAULT_BRANCH")
HAS_DEFAULT_TARGET=0
SWEEP_TARGETS=()
is_default_name() {
  [ "${#DEFAULT_NAMES[@]}" -gt 0 ] || return 1
  local x="$1" d
  for d in "${DEFAULT_NAMES[@]}"; do [ "$x" = "$d" ] && return 0; done
  return 1
}
for t in "${TARGETS[@]}"; do
  n="${t#refs/heads/}"; n="${n#refs/remotes/}"; n="${n#origin/}"
  tt="$(git rev-parse --verify --quiet "${t}^{commit}" 2>/dev/null || true)"
  if is_default_name "$n" || { [ -n "$DEFAULT_COMMIT" ] && [ -n "$tt" ] && [ "$tt" = "$DEFAULT_COMMIT" ]; }; then
    HAS_DEFAULT_TARGET=1
  else
    SWEEP_TARGETS+=("$t")
  fi
  PROTECTED+=("$t" "$n")
done

if [ "$EXPLICIT_TARGETS" = 0 ] && [ "$HAS_DEFAULT_TARGET" = 1 ]; then
  echo "worktree-sweep: default target requires platform MR evidence; pass a non-default development target explicitly" >&2
  exit 2
fi
if [ "$DEFAULT_CONFIRMED" = 0 ]; then
  echo "worktree-sweep: cannot confirm origin/HEAD; refusing ancestor-based sweep" >&2
  exit 2
fi

# Main worktree root = parent of the common git dir.
COMMON="$(git rev-parse --git-common-dir)"
MAIN_ROOT="$(cd "$COMMON/.." 2>/dev/null && pwd -P)"

# Local state that must block removal. Default: any uncommitted/untracked/IGNORED file
# (git worktree remove without --force still deletes ignored-only worktrees -> data loss).
# --include-ignored relaxes this to real dirty/untracked only (ignored files = regenerable).
# --untracked-files=all forces untracked enumeration regardless of a repo's
# status.showUntrackedFiles=no config (which would otherwise hide untracked work).
# FAIL CLOSED on a non-zero `git status`: an unscannable worktree (corrupt index,
# broken gitdir, unreadable tree) yields EMPTY output, and treating that emptiness
# as "clean" is exactly the false-negative the manual pre-scan rule forbids
# ("必须 exit 0；失败按没扫处理"). Unscannable -> local state present -> KEEP.
# HAS_LOCAL_STATE_REASON carries which of the two it was, for the KEEP line.
# HAS_LOCAL_STATE_SAMPLE carries a bounded sample of the actual entries, because the
# cleanup rule asks the operator to grade what is there by RECOMPUTE COST before
# deciding — a generic "ignored files present" gives them nothing to grade, and they
# would have to re-run status by hand to find out.
HAS_LOCAL_STATE_REASON=""
HAS_LOCAL_STATE_SAMPLE=""
STATE_SAMPLE_LINES=8
has_local_state() {
  local out rc
  if [ "$INCLUDE_IGNORED" = 1 ]; then
    out="$(git -C "$1" status --porcelain --untracked-files=all 2>/dev/null)"; rc=$?
  else
    out="$(git -C "$1" status --porcelain --untracked-files=all --ignored 2>/dev/null)"; rc=$?
  fi
  HAS_LOCAL_STATE_SAMPLE=""
  if [ "$rc" -ne 0 ]; then
    HAS_LOCAL_STATE_REASON="unscannable: git status exit $rc — treat as unscanned, inspect manually"
    return 0
  fi
  [ -n "$out" ] || return 1
  HAS_LOCAL_STATE_REASON="local changes / untracked$([ "$INCLUDE_IGNORED" = 0 ] && printf ' / ignored') files present"
  local total; total="$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
  HAS_LOCAL_STATE_SAMPLE="$(printf '%s\n' "$out" | head -n "$STATE_SAMPLE_LINES")"
  if [ "$total" -gt "$STATE_SAMPLE_LINES" ]; then
    HAS_LOCAL_STATE_SAMPLE="$HAS_LOCAL_STATE_SAMPLE
   … $((total - STATE_SAMPLE_LINES)) more"
  fi
  return 0
}

echo "worktree-sweep: integration ref(s) = [$TARGETS_STR]  mode = $([ "$APPLY" = 1 ] && echo APPLY || echo 'DRY-RUN (pass --apply to act)')"
echo

removed=0; kept=0
wt=""; br=""; det=0; bare=0
is_protected_name() { local b="$1" p; for p in "${PROTECTED[@]}"; do [ "$b" = "$p" ] && return 0; done; return 1; }
# Release-named branches are never auto-deleted, however merged they look: a release branch is
# kept after merge to tag from, to trace what shipped, and to cut patches off — yet in git
# topology it is indistinguishable from a finished feature branch, so "merged" does not imply
# "disposable" here. Name-based on purpose; substring + case-insensitive so release/v2,
# release-1.2, and hotfix-RELEASE all match. Deleting one is a user-named action, never a sweep.
# One hardcoded keyword, deliberately not extensible. Three rounds of adversarial review
# each found a new way a configurable list fails to TRAVEL: an env var protects only the
# invocation that exported it; `.git/config` is per-clone and a fresh CI clone loses it.
# Every fix chased vocabulary the script does not own. The keyword lives in this shared
# script, so it travels wherever the skill is installed — that is the property a delete
# guard needs. A repo whose release branches are named otherwise (`rc/`, `stabilization/`)
# is NOT auto-protected here, and that is the deliberate residual: the sweep prints its
# full KEEP/REMOVE plan for a human before `--apply`, and deleting anything is a
# user-named action to begin with. Do not re-add a config source without first solving
# how it reaches a fresh clone.
is_release_named() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in *release*) return 0 ;; *) return 1 ;; esac
}
# A worktree sitting exactly at an integration ref's tip is on the integration branch itself
# (not a finished feature ahead of it) -> never remove. A real merged feature (--no-ff) has a
# tip that is an ANCESTOR of, but != , the target tip, so it is not caught here.
is_at_target_tip() {
  local bt; bt="$(git rev-parse --verify --quiet "refs/heads/$1^{commit}" 2>/dev/null)" || return 1
  [ -n "$bt" ] || return 1
  local t tt; for t in "${TARGETS[@]}"; do
    tt="$(git rev-parse --verify --quiet "${t}^{commit}" 2>/dev/null)"
    [ -n "$tt" ] && [ "$bt" = "$tt" ] && return 0
  done; return 1
}
merged_into_any() {
  [ "${#SWEEP_TARGETS[@]}" -gt 0 ] || return 1
  local b="$1" t
  for t in "${SWEEP_TARGETS[@]}"; do git merge-base --is-ancestor "refs/heads/$b" "$t" 2>/dev/null && return 0; done
  return 1
}

sweep_one() {
  [ -n "$wt" ] || return 0
  local path="$wt" branch="$br" reason=""
  HAS_LOCAL_STATE_SAMPLE=""
  if [ "$bare" = 1 ]; then reason="bare";
  elif [ "$(cd "$path" 2>/dev/null && pwd -P)" = "$MAIN_ROOT" ]; then reason="main worktree";
  elif [ "$det" = 1 ] || [ -z "$branch" ]; then reason="detached / no branch";
  elif is_protected_name "$branch"; then reason="protected branch (default / integration target)";
  elif is_release_named "$branch"; then reason="release-named branch (never auto-deleted; delete only when the user names it)";
  elif is_at_target_tip "$branch"; then reason="at an integration ref tip";
  elif has_local_state "$path"; then reason="$HAS_LOCAL_STATE_REASON";
  elif [ "${#SWEEP_TARGETS[@]}" -eq 0 ]; then reason="default target requires platform MR evidence; inspect manually";
  elif ! merged_into_any "$branch"; then reason="not merged into any non-default target of [$TARGETS_STR]";
  fi
  if [ -n "$reason" ]; then
    printf '  KEEP   %-50s [%s]\n' "$path" "$reason"
    # Show WHAT is there so the recompute-cost call can be made from this output
    # alone. Without it, --include-ignored is a blind batch-wide waiver.
    [ -n "$HAS_LOCAL_STATE_SAMPLE" ] && printf '%s\n' "$HAS_LOCAL_STATE_SAMPLE" | sed 's/^/           /'
    kept=$((kept+1)); return 0
  fi
  if [ "$APPLY" = 0 ]; then
    printf '  WOULD-REMOVE %-44s (branch %s, merged)\n' "$path" "$branch"; removed=$((removed+1)); return 0
  fi
  if git worktree remove "$path" 2>/dev/null; then
    git branch -d "$branch" >/dev/null 2>&1 || true
    printf '  REMOVED %-49s (branch %s)\n' "$path" "$branch"; removed=$((removed+1))
  else
    printf '  KEEP   %-50s [remove refused: dirty/locked — inspect manually]\n' "$path"; kept=$((kept+1))
  fi
}

while IFS= read -r line; do
  case "$line" in
    "worktree "*) sweep_one; wt="${line#worktree }"; br=""; det=0; bare=0 ;;
    "branch "*)   br="${line#branch refs/heads/}" ;;
    "detached")   det=1 ;;
    "bare")       bare=1 ;;
  esac
done < <(git worktree list --porcelain)
sweep_one  # flush last block

[ "$APPLY" = 1 ] && git worktree prune  # prune only mutates under --apply (dry-run prints only)
echo
echo "worktree-sweep: $([ "$APPLY" = 1 ] && echo removed || echo would-remove)=$removed kept=$kept"
[ "$APPLY" = 0 ] && [ "$removed" -gt 0 ] && echo "worktree-sweep: re-run with --apply to remove the above."
exit 0
