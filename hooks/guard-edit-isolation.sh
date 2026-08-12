#!/usr/bin/env bash
# PreToolUse guard — enforce edit isolation by CONCURRENCY signal (Option 2).
# Enforcement is Claude-Code-only: Codex DOES run this hook but ignores the
# permissionDecision:"deny" (verified), so Codex edits are not hard-blocked —
# on Codex, isolation is advisory via the worktree-isolation skill + bootstrap.
#
# Allows edits from a linked worktree. Denies PRIMARY-checkout edits only when:
#   (a) the repo declares itself shared via a committed `.worktree-only` marker; or
#   (b) the repo has another LIVE (non-prunable) worktree → parallel work in
#       progress, so editing the primary checkout risks clobbering it.
# Background/secondary agent sessions are isolated natively by Claude Code's
# `worktree.bgIsolation` default and are not re-handled here. Solo, clean,
# single-worktree primary editing (normal product dev) proceeds freely.
# Override: a human can disable this guard via /hooks.

input=$(cat)

# Dependency degrade: a global guard must NOT silently allow on a missing tool,
# but also must NOT brick all editing. Emit a visible warning and defer.
if ! command -v jq >/dev/null 2>&1; then
  printf '{"systemMessage":"⚠️ edit-isolation guard degraded: jq not found; isolation NOT enforced this session"}\n'
  exit 0
fi
if ! command -v git >/dev/null 2>&1; then
  printf '{"systemMessage":"⚠️ edit-isolation guard degraded: git not found; isolation NOT enforced this session"}\n'
  exit 0
fi

fp=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // empty' 2>/dev/null)
[ -z "$fp" ] && exit 0

# Resolve a symlinked target so a symlink pointing into a protected repo is caught.
if [ -L "$fp" ]; then
  rp=$(realpath "$fp" 2>/dev/null) && [ -n "$rp" ] && fp="$rp"
fi

dir=$(dirname -- "$fp")
while [ ! -d "$dir" ] && [ "$dir" != "/" ] && [ "$dir" != "." ]; do
  dir=$(dirname -- "$dir")
done
[ -d "$dir" ] || exit 0

toplevel=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -z "$toplevel" ] && exit 0

# Linked worktree → already isolated. Discriminate STRUCTURALLY: a linked
# worktree's git-dir (<common>/worktrees/<id>) differs from the repo's common
# dir; a primary checkout's does not. Matching the path name `*/worktrees/*`
# instead would silently disable this guard for any primary checkout that
# merely lives under a directory called `worktrees/` (e.g. ~/work/worktrees/repo).
absgitdir=$(git -C "$dir" rev-parse --absolute-git-dir 2>/dev/null)
commondir=$(git -C "$dir" rev-parse --git-common-dir 2>/dev/null)
case "$commondir" in
  ""  ) ;;                                                       # unknown → treat as primary (fail-closed)
  /*  ) commondir=$(cd "$commondir" 2>/dev/null && pwd -P) ;;
  *   ) commondir=$(cd "$dir" && cd "$commondir" 2>/dev/null && pwd -P) ;;  # relative to git -C dir
esac
absgitdir=$(cd "$absgitdir" 2>/dev/null && pwd -P) || :
isolated=0
if [ -n "$absgitdir" ] && [ -n "$commondir" ] && [ "$absgitdir" != "$commondir" ]; then
  isolated=1
fi
# A submodule initialized inside a linked worktree keeps its git-dir under that
# worktree's admin dir (<common>/worktrees/<id>/modules/<name>) and reports the
# SAME path as its common dir, so the comparison above reads "primary" — yet the
# checkout is isolated from the superproject's main checkout. Detect the
# enclosing admin dir by the marker files git writes there (commondir+gitdir),
# never by a directory merely NAMED worktrees.
if [ "$isolated" -eq 0 ] && [ -n "$absgitdir" ]; then
  d="$absgitdir"; hops=0
  while [ "$d" != "/" ] && [ "$d" != "." ] && [ "$hops" -lt 40 ]; do
    if [ -f "$d/commondir" ] && [ -f "$d/gitdir" ]; then isolated=1; break; fi
    d=$(dirname -- "$d"); hops=$((hops+1))
  done
fi
[ "$isolated" -eq 1 ] && exit 0

deny() {
  local branch
  branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
  jq -nc --arg r "$1" --arg b "$branch" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:($r + " 当前分支:" + $b)}}'
  exit 0
}

# (a) declared shared repo → require a dedicated worktree, any branch.
if [ -e "$toplevel/.worktree-only" ]; then
  deny "隔离闸：[$toplevel] 标记为共享仓库（.worktree-only），禁止直接改主检出，与分支无关。先建独立 worktree 再改：git worktree add -b <new-branch> <path>，在 worktree 里编辑、提交、走 MR。（确需直接改请 /hooks 关闭）"
fi

# (b) parallel work in progress: count LIVE (non-prunable) worktrees. >1 ⇒ another
# live checkout exists besides the primary. Stale/deleted worktrees are excluded.
live=$(git -C "$dir" worktree list --porcelain 2>/dev/null | awk '
  /^worktree /{p=1; pr=0}
  /^prunable/{pr=1}
  /^$/{ if(p && !pr) n++; p=0 }
  END{ if(p && !pr) n++; print n+0 }')
if [ "${live:-1}" -gt 1 ]; then
  deny "并发隔离闸：[$toplevel] 存在 $live 个活动 worktree（有并行开发），别直接改主检出——在对应 worktree 里改，或新建：git worktree add -b <new-branch> <path>。（确需直接改请 /hooks 关闭）"
fi

exit 0
