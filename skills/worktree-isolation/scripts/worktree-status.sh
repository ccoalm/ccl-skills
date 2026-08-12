#!/usr/bin/env bash
# worktree-status — read-only preflight for repository worktree isolation.

set -u

SLUG=""
WANTED_BRANCH=""
BASE_REF=""
JSON=0
BASE_EXPLICIT=0

usage() {
  cat <<'USAGE'
Usage: worktree-status.sh [--slug <slug>] [--branch <branch>] [--base <ref>] [--json]

Read-only worktree isolation preflight. It prints the current repo state, a
worktree inventory, and a copyable `git worktree add` command when editing is
unsafe. It never creates, removes, checks out, or modifies git state.

Exit codes: safe=0, unsafe=1, usage/setup error=2.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --slug)
      [ "$#" -ge 2 ] || { echo "worktree-status: --slug requires a value" >&2; exit 2; }
      SLUG="$2"; shift 2 ;;
    --branch)
      [ "$#" -ge 2 ] || { echo "worktree-status: --branch requires a value" >&2; exit 2; }
      WANTED_BRANCH="$2"; shift 2 ;;
    --base)
      [ "$#" -ge 2 ] || { echo "worktree-status: --base requires a value" >&2; exit 2; }
      BASE_REF="$2"; BASE_EXPLICIT=1; shift 2 ;;
    --json) JSON=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --*) echo "worktree-status: unknown flag '$1'" >&2; usage >&2; exit 2 ;;
    *) echo "worktree-status: unexpected argument '$1'" >&2; usage >&2; exit 2 ;;
  esac
done

git rev-parse --git-dir >/dev/null 2>&1 || { echo "worktree-status: not inside a git repo" >&2; exit 2; }
if [ "$JSON" = 1 ] && ! command -v python3 >/dev/null 2>&1; then
  echo "worktree-status: --json requires python3 for JSON escaping" >&2
  exit 2
fi

canon_dir() { cd "$1" 2>/dev/null && pwd -P; }
json_escape() { printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'; }
# Bash JSON string escaper used when python3 is unavailable. Emits
# the escaped inner content WITHOUT surrounding quotes; escapes backslash,
# double quote, tab, CR, and LF so interpolated values stay valid JSON.
json_string_fallback() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\t'/\\t}
  s=${s//$'\r'/\\r}
  s=${s//$'\n'/\\n}
  printf '%s' "$s"
}
# ASCII unit separator: a delimiter that cannot appear in worktree paths or
# branch names, so the worktree inventory survives literal '|' in either field.
US="$(printf '\037')"
shell_quote() {
  printf "'"
  printf '%s' "$1" | sed "s/'/'\\\\''/g"
  printf "'"
}
slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's#[^a-z0-9._-]#-#g; s#^-*##; s#-*$##; s#--*#-#g'
}
branchify() {
  printf '%s' "$1" | sed 's#[^A-Za-z0-9._/-]#-#g; s#//*#/#g; s#^[-/]*##; s#[-/]*$##; s#\.\.#-#g; s#@{#-#g; s#--*#-#g'
}

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$REPO_ROOT" ] || { echo "worktree-status: cannot resolve repo root" >&2; exit 2; }
REPO_ROOT="$(canon_dir "$REPO_ROOT")"
GIT_DIR_RAW="$(git rev-parse --git-dir 2>/dev/null || true)"
GIT_COMMON_RAW="$(git rev-parse --git-common-dir 2>/dev/null || true)"
GIT_DIR="$(canon_dir "$GIT_DIR_RAW" 2>/dev/null || printf '%s' "$GIT_DIR_RAW")"
GIT_COMMON_DIR="$(canon_dir "$GIT_COMMON_RAW" 2>/dev/null || printf '%s' "$GIT_COMMON_RAW")"
PRIMARY_ROOT="$(canon_dir "$(dirname "$GIT_COMMON_DIR")" 2>/dev/null || true)"
[ -n "$PRIMARY_ROOT" ] || { echo "worktree-status: cannot resolve primary checkout root" >&2; exit 2; }
BRANCH="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
HEAD_REV="$(git rev-parse --short HEAD 2>/dev/null || true)"
SUPERPROJECT="$(git rev-parse --show-superproject-working-tree 2>/dev/null || true)"
IS_SUBMODULE=0; [ -n "$SUPERPROJECT" ] && IS_SUBMODULE=1
IS_DETACHED=0; [ -z "$BRANCH" ] && IS_DETACHED=1
IS_INDEPENDENT=0; [ "$GIT_DIR" != "$GIT_COMMON_DIR" ] && IS_INDEPENDENT=1
WORKTREE_ONLY=0; [ -f "$REPO_ROOT/.worktree-only" ] && WORKTREE_ONLY=1
WORK_DIR_ROOT="$PRIMARY_ROOT/.work"
WORKTREE_DIR="$WORK_DIR_ROOT/worktrees"
LANE_DIR="$WORK_DIR_ROOT/lanes"
IN_WORK_DIR=0
case "$REPO_ROOT" in
  "$WORKTREE_DIR"/*) IN_WORK_DIR=1 ;;
esac

DEFAULT_BRANCH=""
DEFAULT_CONFIRMED=0
BASE_CONFIRMED=0
DEFAULT_SYMREF="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
if [ -n "$DEFAULT_SYMREF" ]; then
  DEFAULT_BRANCH="${DEFAULT_SYMREF#origin/}"
  DEFAULT_CONFIRMED=1
fi

if [ -z "$BASE_REF" ]; then
  if [ "$DEFAULT_CONFIRMED" = 1 ]; then
    BASE_REF="origin/$DEFAULT_BRANCH"
    BASE_CONFIRMED=1
  elif git rev-parse --verify --quiet "main^{commit}" >/dev/null 2>&1; then
    BASE_REF="main"
  elif git rev-parse --verify --quiet "master^{commit}" >/dev/null 2>&1; then
    BASE_REF="master"
  fi
elif [ "$BASE_EXPLICIT" = 1 ]; then
  BASE_CONFIRMED=1
fi

if [ -z "$BASE_REF" ]; then
  BASE_FOUND=0
else
  if git rev-parse --verify --quiet "${BASE_REF}^{commit}" >/dev/null 2>&1; then
    BASE_FOUND=1
  else
    BASE_FOUND=0
  fi
fi

BASE_SHORT="$BASE_REF"
case "$BASE_SHORT" in
  origin/*) BASE_SHORT="${BASE_SHORT#origin/}" ;;
  refs/heads/*) BASE_SHORT="${BASE_SHORT#refs/heads/}" ;;
  refs/remotes/origin/*) BASE_SHORT="${BASE_SHORT#refs/remotes/origin/}" ;;
esac

# Capture git status success separately: swallowing a nonzero exit into an empty
# string would read as "0 dirty lines" => a false clean => a false SAFE. For a
# clobber-prevention preflight, undetermined cleanliness must fail CLOSED (unsafe),
# so track STATUS_OK and require it for SAFE below.
if STATUS_PORCELAIN="$(git status --porcelain --untracked-files=all 2>/dev/null)"; then
  STATUS_OK=1
else
  STATUS_OK=0
  STATUS_PORCELAIN=""
fi
STATUS_WITH_IGNORED="$(git status --porcelain --untracked-files=all --ignored 2>/dev/null || true)"
DIRTY_LINES="$(printf '%s\n' "$STATUS_PORCELAIN" | sed '/^$/d' | wc -l | tr -d ' ')"
UNTRACKED_LINES="$(printf '%s\n' "$STATUS_PORCELAIN" | grep -c '^?? ' || true)"
IGNORED_LINES="$(printf '%s\n' "$STATUS_WITH_IGNORED" | grep -c '^!! ' || true)"
TRACKED_DIRTY_LINES=$((DIRTY_LINES - UNTRACKED_LINES))
[ "$TRACKED_DIRTY_LINES" -lt 0 ] && TRACKED_DIRTY_LINES=0

safe_branch=0
if [ -n "$BRANCH" ] && [ "$BRANCH" != "$BASE_SHORT" ] && [ "$BRANCH" != "main" ] && [ "$BRANCH" != "master" ]; then
  safe_branch=1
fi

SAFE=0
if [ "$IS_INDEPENDENT" = 1 ] && [ "$safe_branch" = 1 ] && [ "$IS_SUBMODULE" = 0 ] && [ "$IS_DETACHED" = 0 ] && [ "$STATUS_OK" = 1 ] && [ "$DIRTY_LINES" = 0 ] && [ "$BASE_FOUND" = 1 ] && [ "$BASE_CONFIRMED" = 1 ]; then
  SAFE=1
fi

REASONS=()
[ "$IS_INDEPENDENT" = 1 ] || REASONS+=("not an independent worktree")
[ "$IS_SUBMODULE" = 0 ] || REASONS+=("inside a submodule")
[ "$IS_DETACHED" = 0 ] || REASONS+=("detached HEAD")
[ "$safe_branch" = 1 ] || REASONS+=("current branch is empty/default/base")
[ "$STATUS_OK" = 1 ] || REASONS+=("could not determine worktree cleanliness (git status failed); treating as unsafe")
[ "$DIRTY_LINES" = 0 ] || REASONS+=("dirty or untracked files present")
[ "$BASE_FOUND" = 1 ] || REASONS+=("base ref not found; pass --base")
[ "$BASE_CONFIRMED" = 1 ] || REASONS+=("default/base branch not confirmed; pass --base")

if [ -n "$SLUG" ]; then
  SUGGEST_SLUG="$(slugify "$SLUG")"
elif [ -n "$WANTED_BRANCH" ]; then
  SUGGEST_SLUG="$(slugify "$WANTED_BRANCH")"
elif [ -n "$BRANCH" ]; then
  SUGGEST_SLUG="$(slugify "$BRANCH")"
else
  SUGGEST_SLUG="worktree-task"
fi
[ -n "$SUGGEST_SLUG" ] || SUGGEST_SLUG="worktree-task"

if [ -n "$WANTED_BRANCH" ]; then
  SUGGEST_BRANCH="$WANTED_BRANCH"
elif [ "$safe_branch" = 1 ]; then
  SUGGEST_BRANCH="$BRANCH"
else
  SUGGEST_BRANCH="worktree-${SUGGEST_SLUG}"
fi
SUGGEST_BRANCH="$(branchify "$SUGGEST_BRANCH")"
[ -n "$SUGGEST_BRANCH" ] || SUGGEST_BRANCH="worktree-${SUGGEST_SLUG}"
if ! git check-ref-format --branch "$SUGGEST_BRANCH" >/dev/null 2>&1; then
  SUGGEST_BRANCH="worktree-${SUGGEST_SLUG}"
fi
SUGGEST_PATH="$WORKTREE_DIR/${SUGGEST_SLUG}"
LANE_METADATA_PATH="$LANE_DIR/${SUGGEST_SLUG}.json"
if [ -n "$BASE_REF" ]; then
  SUGGEST_CMD="git worktree add -b $(shell_quote "$SUGGEST_BRANCH") $(shell_quote "$SUGGEST_PATH") $(shell_quote "$BASE_REF")"
else
  SUGGEST_CMD="git worktree add -b $(shell_quote "$SUGGEST_BRANCH") $(shell_quote "$SUGGEST_PATH") <base>"
fi
if command -v python3 >/dev/null 2>&1; then
  LANE_METADATA_SNIPPET="$(python3 - "$SUGGEST_SLUG" "$SUGGEST_BRANCH" "$SUGGEST_PATH" "$BASE_REF" <<'PY'
import json
import sys

slug, branch, worktree_path, base = sys.argv[1:]
print(json.dumps({
    "slug": slug,
    "branch": branch,
    "worktree_path": worktree_path,
    "base": base,
}, separators=(",", ":")))
PY
)"
else
  LANE_METADATA_SNIPPET="{\"slug\":\"$(json_string_fallback "$SUGGEST_SLUG")\",\"branch\":\"$(json_string_fallback "$SUGGEST_BRANCH")\",\"worktree_path\":\"$(json_string_fallback "$SUGGEST_PATH")\",\"base\":\"$(json_string_fallback "$BASE_REF")\"}"
fi

WT_SUMMARY="$(git worktree list --porcelain 2>/dev/null | awk '
  BEGIN { sep=sprintf("%c", 31) }
  /^worktree / { if (path != "") print path sep branch sep head sep flags; path=substr($0,10); branch=""; head=""; flags=""; next }
  /^HEAD / { head=substr($0,6); next }
  /^branch / { branch=substr($0,19); next }
  /^detached$/ { flags=flags ",detached"; next }
  /^bare$/ { flags=flags ",bare"; next }
  /^locked/ { flags=flags ",locked"; next }
  END { if (path != "") print path sep branch sep head sep flags }
')"

if [ "$JSON" = 1 ]; then
  printf '{\n'
  printf '  "status": %s,\n' "$(json_escape "$([ "$SAFE" = 1 ] && echo safe || echo unsafe)")"
  printf '  "repo_root": %s,\n' "$(json_escape "$REPO_ROOT")"
  printf '  "primary_root": %s,\n' "$(json_escape "$PRIMARY_ROOT")"
  printf '  "branch": %s,\n' "$(json_escape "$BRANCH")"
  printf '  "head": %s,\n' "$(json_escape "$HEAD_REV")"
  printf '  "base": %s,\n' "$(json_escape "$BASE_REF")"
  printf '  "base_found": %s,\n' "$([ "$BASE_FOUND" = 1 ] && echo true || echo false)"
  printf '  "base_confirmed": %s,\n' "$([ "$BASE_CONFIRMED" = 1 ] && echo true || echo false)"
  printf '  "default_branch": %s,\n' "$(json_escape "$DEFAULT_BRANCH")"
  printf '  "default_confirmed": %s,\n' "$([ "$DEFAULT_CONFIRMED" = 1 ] && echo true || echo false)"
  printf '  "git_dir": %s,\n' "$(json_escape "$GIT_DIR")"
  printf '  "git_common_dir": %s,\n' "$(json_escape "$GIT_COMMON_DIR")"
  printf '  "work_dir_root": %s,\n' "$(json_escape "$WORK_DIR_ROOT")"
  printf '  "worktree_dir": %s,\n' "$(json_escape "$WORKTREE_DIR")"
  printf '  "lane_metadata_path": %s,\n' "$(json_escape "$LANE_METADATA_PATH")"
  printf '  "lane_metadata_snippet": %s,\n' "$(json_escape "$LANE_METADATA_SNIPPET")"
  printf '  "suggested_worktree_path": %s,\n' "$(json_escape "$SUGGEST_PATH")"
  printf '  "in_work_dir": %s,\n' "$([ "$IN_WORK_DIR" = 1 ] && echo true || echo false)"
  printf '  "outside_work_dir_warning": %s,\n' "$([ "$SAFE" = 1 ] && [ "$IN_WORK_DIR" = 0 ] && echo true || echo false)"
  printf '  "is_submodule": %s,\n' "$([ "$IS_SUBMODULE" = 1 ] && echo true || echo false)"
  printf '  "is_detached": %s,\n' "$([ "$IS_DETACHED" = 1 ] && echo true || echo false)"
  printf '  "is_independent_worktree": %s,\n' "$([ "$IS_INDEPENDENT" = 1 ] && echo true || echo false)"
  printf '  "worktree_only_marker": %s,\n' "$([ "$WORKTREE_ONLY" = 1 ] && echo true || echo false)"
  printf '  "dirty_count": %s,\n' "$TRACKED_DIRTY_LINES"
  printf '  "untracked_count": %s,\n' "$UNTRACKED_LINES"
  printf '  "ignored_count": %s,\n' "$IGNORED_LINES"
  printf '  "ignored_only_warning": %s,\n' "$([ "$DIRTY_LINES" = 0 ] && [ "$IGNORED_LINES" -gt 0 ] && echo true || echo false)"
  printf '  "suggested_command": %s,\n' "$(json_escape "$SUGGEST_CMD")"
  printf '  "reasons": ['
  first=1
  set +u
  for r in "${REASONS[@]}"; do [ "$first" = 1 ] || printf ', '; first=0; printf '%s' "$(json_escape "$r")"; done
  set -u
  printf '],\n'
  printf '  "worktrees": ['
  first=1
  while IFS="$US" read -r p b h f; do
    [ -n "$p" ] || continue
    [ "$first" = 1 ] || printf ','
    first=0
    printf '\n    {"path": %s, "branch": %s, "head": %s, "flags": %s}' "$(json_escape "$p")" "$(json_escape "$b")" "$(json_escape "$h")" "$(json_escape "${f#,}")"
  done <<EOF
$WT_SUMMARY
EOF
  [ "$first" = 1 ] || printf '\n  '
  printf ']\n}\n'
else
  echo "worktree-status: $([ "$SAFE" = 1 ] && echo SAFE || echo UNSAFE)"
  echo "repo root: $REPO_ROOT"
  echo "primary root: $PRIMARY_ROOT"
  echo "branch: ${BRANCH:-<detached>}  head: ${HEAD_REV:-unknown}"
  echo "default/base: ${DEFAULT_BRANCH:-unknown} / ${BASE_REF:-<missing>} $([ "$BASE_FOUND" = 1 ] || printf '(base not found)')"
  echo "git-dir: $GIT_DIR"
  echo "git-common-dir: $GIT_COMMON_DIR"
  echo "submodule: $IS_SUBMODULE  detached: $IS_DETACHED  independent-worktree: $IS_INDEPENDENT  .worktree-only: $WORKTREE_ONLY  in-.work: $IN_WORK_DIR"
  echo ".work convention: worktrees=$WORKTREE_DIR lanes=$LANE_DIR"
  echo "dirty: tracked=$TRACKED_DIRTY_LINES untracked=$UNTRACKED_LINES ignored=$IGNORED_LINES"
  if [ "$DIRTY_LINES" = 0 ] && [ "$IGNORED_LINES" -gt 0 ]; then
    echo "warning: ignored-only files present; this is a warning, not a hard fail for edit preflight"
  fi
  if [ "$SAFE" != 1 ]; then
    echo "unsafe reasons: ${REASONS[*]}"
    echo "suggested command: $SUGGEST_CMD"
    echo "suggested worktree path: $SUGGEST_PATH"
    echo "lane metadata path: $LANE_METADATA_PATH"
    echo "lane metadata snippet: $LANE_METADATA_SNIPPET"
  else
    echo "next: safe to edit in this worktree; still run normal task validation before integration"
    if [ "$IN_WORK_DIR" = 0 ]; then
      echo "warning: safe worktree is outside .work/worktrees; use .work/worktrees for new lanes"
    fi
    echo "lane metadata path: $LANE_METADATA_PATH"
  fi
  echo
  echo "worktree inventory:"
  if [ -n "$WT_SUMMARY" ]; then
    while IFS="$US" read -r p b h f; do
      [ -n "$p" ] || continue
      printf '  - %s  branch=%s  head=%s  flags=%s\n' "$p" "${b:-<none>}" "${h:-unknown}" "${f#,}"
    done <<EOF
$WT_SUMMARY
EOF
  else
    echo "  <none>"
  fi
fi

[ "$SAFE" = 1 ] && exit 0 || exit 1
