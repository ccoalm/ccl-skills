#!/usr/bin/env bash
# PreToolUse guard — enforce edit isolation by CONCURRENCY signal (Option 2).
# Host aliases retain raw tool names; normalize patch targets before policy.
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

HELPER="$(cd "$(dirname "$0")" && pwd)/host-input.py"
legacy_paths() {
  # Claude's single-path input remains enforceable with the original jq/git
  # dependencies. Resolve relative input against the host cwd without Python.
  # NUL is tested on code points: jq 1.6 `contains("\u0000")` is true for every
  # string, which would drop every path and leave the edit unguarded.
  printf '%s' "$input" | jq -c --arg cwd "$PWD" '
    . as $event | {malformed_patch:false, paths:[
      (.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // empty)
      | select(type == "string" and length > 0 and (explode | any(. == 0) | not))
      | if startswith("/") then . else
          (($event.cwd | select(type == "string" and length > 0)) // $cwd) + "/" + .
        end]}' 2>/dev/null
}
if ! command -v python3 >/dev/null 2>&1 || [ ! -r "$HELPER" ]; then
  if [ "$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)" = apply_patch ]; then
    jq -nc '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"Edit-isolation guard cannot inspect apply_patch: Python input normalizer unavailable."}}'
    exit 0
  fi
  normalized=$(legacy_paths) || exit 0
else
  normalized=$(printf '%s' "$input" | python3 "$HELPER" paths 2>/dev/null) || {
    if [ "$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)" = apply_patch ]; then
      jq -nc '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"Edit-isolation guard cannot inspect apply_patch input."}}'
      exit 0
    fi
    normalized=$(legacy_paths) || exit 0
  }
fi
# One jq call yields the malformed-patch flag, then each target path, as
# NUL-terminated records on fd 3. The flag record always comes first, so a
# malformed patch with no targets is still flagged, and paths are then checked
# as they arrive. The jq-only normalizer emits one object per input document,
# and `$(jq -r .malformed_patch)` printed one line per document, so it read
# `true` only for a single document flagged true. Paths keep their exact bytes,
# trailing newlines included.
exec 3< <(printf '%s' "$normalized" | jq -sj '
  (if length == 1 then .[0].malformed_patch | tostring else "" end) + "\u0000",
  (.[] | .paths[] | . + "\u0000")')
malformed=""
IFS= read -r -d '' malformed <&3
if [ "$malformed" = true ]; then
  jq -nc '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"Edit-isolation guard cannot inspect malformed apply_patch targets. Supply a complete patch before editing."}}'
  exit 0
fi

deny() {
  local dir="$1" msg="$2" branch
  branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
  jq -nc --arg r "$msg" --arg b "$branch" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:($r + " 当前分支:" + $b)}}'
  exit 0
}

check_one_path() {
  local p="$1" allow_dangling_walk="${2:-1}"
  local dir toplevel absgitdir commondir isolated d hops live
  dir=$(dirname -- "$p")
  while [ ! -d "$dir" ] && [ "$dir" != "/" ] && [ "$dir" != "." ]; do
    if [ "$allow_dangling_walk" -eq 1 ] && [ -L "$dir" ]; then
      check_symlink_targets "$dir"
    fi
    dir=$(dirname -- "$dir")
  done
  [ -d "$dir" ] || return 0

  toplevel=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || return 0
  [ -z "$toplevel" ] && return 0

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
  [ "$isolated" -eq 1 ] && return 0

  # (a) declared shared repo → require a dedicated worktree, any branch.
  if [ -e "$toplevel/.worktree-only" ]; then
    deny "$dir" "隔离闸：[$toplevel] 标记为共享仓库（.worktree-only），禁止直接改主检出，与分支无关。先建独立 worktree 再改：git worktree add -b <new-branch> <path>，在 worktree 里编辑、提交、走 MR。（确需直接改请 /hooks 关闭）"
  fi

  # (b) parallel work in progress: count LIVE (non-prunable) worktrees. >1 ⇒ another
  # live checkout exists besides the primary. Stale/deleted worktrees are excluded.
  live=$(git -C "$dir" worktree list --porcelain 2>/dev/null | awk '
    /^worktree /{p=1; pr=0}
    /^prunable/{pr=1}
    /^$/{ if(p && !pr) n++; p=0 }
    END{ if(p && !pr) n++; print n+0 }')
  if [ "${live:-1}" -gt 1 ]; then
    deny "$dir" "并发隔离闸：[$toplevel] 存在 $live 个活动 worktree（有并行开发），别直接改主检出——在对应 worktree 里改，或新建：git worktree add -b <new-branch> <path>。（确需直接改请 /hooks 关闭）"
  fi

  return 0
}

# Resolve a symlinked target so both the symlink's own parent checkout and its
# resolved destination (including dangling targets into uncreated repo subdirs)
# are checked, bounded to 16 hops on symlink loops.
check_symlink_targets() {
  local cur="$1" rp link_target link_dir sym_hops=0
  if rp=$(realpath "$cur" 2>/dev/null) && [ -n "$rp" ]; then
    [ "$rp" != "$cur" ] && check_one_path "$rp" 0
    return 0
  fi
  while [ -L "$cur" ] && [ "$sym_hops" -lt 16 ]; do
    link_target=$(readlink "$cur" 2>/dev/null) || break
    [ -n "$link_target" ] || break
    case "$link_target" in
      /*) cur="$link_target" ;;
      *)  link_dir=$(dirname -- "$cur")
          cur="$link_dir/$link_target" ;;
    esac
    check_one_path "$cur" 0
    sym_hops=$((sym_hops + 1))
  done
}

check_target() {
  local fp="$1"
  check_one_path "$fp" 1
  if [ -L "$fp" ]; then
    check_symlink_targets "$fp"
  fi
}
while IFS= read -r -d '' fp <&3; do
  check_target "$fp"
done
exit 0
