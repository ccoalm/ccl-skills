#!/usr/bin/env bash
# install-gates: one-click vendoring of the repo-local gate backstops into a PRODUCT repo.
#
# It installs the gate MECHANICS, warn-only. Turning a gate from warn to BLOCK is always a
# deliberate, separately-reviewed step you do by hand (flip enabled:true / remove allow_failure)
# once the repo is actually clean — the installer never one-clicks enforcement, because enabling
# a gate on a not-yet-ready repo just produces spurious CI failures or false confidence.
#
# WHAT IT INSTALLS
#   - agents-file-coverage-gate : vendors check-agent-contract-coverage.sh, scaffolds missing
#                           AGENTS.md stubs (additive — you still FILL the contracts).
#   - owner-dispatch      : vendors owner-dispatch.sh and writes a default
#                           .owner-dispatch.json (enabled:false — a complete no-op until you
#                           deliberately flip it on).
#   - control-plane       : vendors control-plane.sh (deterministic control-plane change
#                           detector; defaults built in, no config needed — optional
#                           .control-plane.json tunes it per repo).
#   - CI fragment         : ci/agent-gates.gitlab-ci.yml, warn-only (allow_failure / --check)
#                           so a fresh repo never breaks.
#
# WHAT IT CANNOT ONE-CLICK (substance, not scaffolding):
#   - real AGENTS.md content (the directory contracts a human/agent must write),
#   - the owner-dispatch map artifact a gated change owes,
#   - the warn→block flip (enabled:true / --enforce in CI / remove allow_failure).
#
# USAGE
#   bash scripts/install-gates.sh <target-repo> [options]
#   make install-gates TARGET=/path/to/repo
#
# OPTIONS
#   --gates LIST       comma list: agents,owner-dispatch,control-plane (default: all)
#   --no-scaffold      vendor scripts + write CI fragment only; do not create AGENTS stubs
#                      or a default config.
#   --ci-platform P    gitlab (default) | none. 'none' skips the CI fragment.
#   --gitlab-runner-tag TAG
#                      tag for generated GitLab jobs (default: shared; env:
#                      INSTALL_GATES_GITLAB_RUNNER_TAG). Use e.g. docker for local/self-hosted runners.
#   -h | --help        this help.
#
# SAFETY: additive + warn-only. Writes are confined to the target repo and refuse to follow
# symlinks/hardlinks. The vendored ENGINE scripts (tools/check-agent-contract-coverage.sh,
# scripts/owner-dispatch/owner-dispatch.sh, scripts/control-plane/control-plane.sh) are refreshed to the current plugin version on
# rerun — that is their purpose (kills drift); they are install-gates-owned paths. An existing
# .owner-dispatch.json, a user-authored AGENTS.md, and a user-edited CI fragment (marker removed)
# are NEVER overwritten. The CI fragment is a DEDICATED file; it is never spliced into your
# .gitlab-ci.yml — you add one `include:` line yourself.
#
# THREAT MODEL (explicit scope): the vendored SOURCES are trusted because they ship next to this
# script in a legitimately-installed ccl-skills. Relocating the installer itself (symlink,
# hardlink, or copy) into an attacker tree with fake sibling sources is OUT OF SCOPE — at that
# point the attacker already controls the code the user runs, and no in-script check converges
# (a copy defeats any link/inode check). We resolve $0 through symlinks as a convenience, and
# assert_trusted_src keeps sources within the resolved install dir; we do NOT attempt to detect a
# relocated/copied installer. The defended boundary is the TARGET repo's filesystem, not the
# provenance of an installer the user chose to execute.

set -u

# Resolve the script's OWN real path first (not just $0's dir): if install-gates is invoked via a
# symlink in an attacker-controlled tree, an unresolved SELF_DIR would point AGENTS_SRC/OD_SRC at
# attacker siblings. realpath is required (also re-checked below for the rest of the run).
command -v realpath >/dev/null 2>&1 || { echo "install-gates: realpath required" >&2; exit 1; }
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}" 2>/dev/null)" || { echo "install-gates: cannot resolve installer script path" >&2; exit 1; }
SELF_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd -P)"
AGENTS_SRC="$SELF_DIR/../skills/product-rd-workflow/scripts/check-agent-contract-coverage.sh"
OD_SRC="$SELF_DIR/owner-dispatch/owner-dispatch.sh"
CP_SRC="$SELF_DIR/control-plane/control-plane.sh"

die() { printf 'install-gates: %s\n' "$*" >&2; exit 1; }
note() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
info() { printf '  \033[36mⓘ\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m⚠\033[0m %s\n' "$*" >&2; }

usage() { sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

# Track every temp file we create so a die() mid-write never leaves an .ig.* turd behind
# (a stale temp would otherwise look like a "user file" to the machinery-ownership scan).
IG_TMPS=()
cleanup_tmps() { local t; for t in "${IG_TMPS[@]:-}"; do [ -n "$t" ] && rm -f "$t" 2>/dev/null; done; }
trap cleanup_tmps EXIT

# All writes are confined to $TARGET and refuse to follow symlinks (a symlinked output path or
# parent dir could otherwise clobber/escape outside the repo). assert_in_target verifies the
# path resolves inside $TARGET, rejects '.'/'..'/empty segments, and that no component is a symlink.
assert_in_target() { # $1 abs path under TARGET
  local p="$1" probe seg
  [ "$p" = "$TARGET" ] && return 0   # the repo root itself (already validated, always a dir)
  case "$p" in "$TARGET"/*) ;; *) die "refusing to write outside target: $p" ;; esac
  # Split on '/' via read -a (no pathname expansion of glob chars, unlike `for seg in $rest`).
  local rest="${p#"$TARGET"/}"; local -a segs=()
  IFS=/ read -r -a segs <<< "$rest"
  probe="$TARGET"
  for seg in "${segs[@]}"; do
    case "$seg" in ""|"."|"..") die "refusing unsafe path segment ('$seg') in: $p" ;; esac
    probe="$probe/$seg"
    [ -L "$probe" ] && die "refusing: '$probe' is a symlink (will not follow)"
    [ "$probe" != "$p" ] && [ -e "$probe" ] && [ ! -d "$probe" ] && die "refusing: '$probe' exists and is not a directory"
  done
}
safe_mkdir() { assert_in_target "$1"; mkdir -p "$1" || die "cannot create $1"; }
# Atomic copy that breaks hardlinks (mktemp+rename, so a hardlinked dest can't write through to
# an outside file) and refuses a dest that exists as a symlink, directory, or other non-regular.
safe_copy() { # $1 src  $2 dest
  assert_in_target "$2"
  if [ -e "$2" ] && { [ -L "$2" ] || [ ! -f "$2" ]; }; then
    die "refusing: destination exists and is not a regular file: $2"
  fi
  local dir t; dir="$(dirname "$2")"; safe_mkdir "$dir"
  t="$(mktemp "$dir/.ig.XXXXXX")" || die "mktemp failed in $dir"; IG_TMPS+=("$t")
  cp "$1" "$t" || die "copy failed: $2"
  chmod +x "$t" 2>/dev/null || true
  mv -f "$t" "$2" || die "rename failed: $2"
}
# Atomic, symlink-refusing write of $2 to file $1.
safe_write() { # $1 dest file  $2 content
  assert_in_target "$1"
  if [ -e "$1" ] && { [ -L "$1" ] || [ ! -f "$1" ]; }; then
    die "refusing: destination exists and is not a regular file: $1"
  fi
  local dir t; dir="$(dirname "$1")"; safe_mkdir "$dir"
  t="$(mktemp "$dir/.ig.XXXXXX")" || die "mktemp failed in $dir"; IG_TMPS+=("$t")
  printf '%s' "$2" > "$t" || die "write failed: $1"
  mv -f "$t" "$1" || die "rename failed: $1"
}
# Has $1 a line containing marker $2? (used to tell installer-owned files from user-owned)
has_marker() { [ -f "$1" ] && grep -qF "$2" "$1" 2>/dev/null; }
# The delegated coverage scaffolder (check-agent-contract-coverage.sh --fix) writes stubs with
# plain redirection, so a DIRECTORY symlink that escapes the repo would let it write outside
# $TARGET — bypassing our own safe-write boundary. Refuse before scaffolding if one exists.
assert_no_escaping_dir_symlinks() {
  local l r found=""
  while IFS= read -r l; do
    [ -d "$l" ] || continue                      # only directory symlinks can host a write
    git -C "$TARGET" check-ignore -q "$l" 2>/dev/null && continue   # scanner respects .gitignore; so do we (no node_modules false-abort)
    r="$(realpath "$l" 2>/dev/null)" || continue
    case "$r/" in "$TARGET"/*) ;; *) found="$l"; break ;; esac
  done < <(find "$TARGET" -path "$TARGET/.git" -prune -o -type l -print 2>/dev/null)
  [ -z "$found" ] || die "refusing: '$found' is a directory symlink escaping the repo (the coverage scaffolder would write outside the target). Remove/relocate it, or run with --no-scaffold."
}
# Trusted vendored SOURCE: a regular file (not a symlink) physically inside the installer repo.
assert_trusted_src() { # $1 source path
  [ -f "$1" ] && [ ! -L "$1" ] || die "vendored source missing or is a symlink: $1"
  local r; r="$(realpath "$1" 2>/dev/null)" || die "cannot resolve source: $1"
  case "$r" in "$SELF_DIR"/*|"$(realpath "$SELF_DIR/..")"/*) ;; *) die "vendored source escapes installer repo: $r" ;; esac
}

# ----- args -------------------------------------------------------------------
TARGET=""; GATES="agents,owner-dispatch,control-plane"; SCAFFOLD=1; CI_PLATFORM="gitlab"; GITLAB_RUNNER_TAG="${INSTALL_GATES_GITLAB_RUNNER_TAG:-shared}"
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --gates) [ $# -ge 2 ] || die "--gates requires a value"; GATES="$2"; shift 2 ;;
    --no-scaffold) SCAFFOLD=0; shift ;;
    --ci-platform) [ $# -ge 2 ] || die "--ci-platform requires a value"; CI_PLATFORM="$2"; shift 2 ;;
    --gitlab-runner-tag) [ $# -ge 2 ] || die "--gitlab-runner-tag requires a value"; GITLAB_RUNNER_TAG="$2"; shift 2 ;;
    --*) die "unknown option: $1 (see --help)" ;;
    *) [ -z "$TARGET" ] || die "unexpected extra argument: $1"; TARGET="$1"; shift ;;
  esac
done
[ -n "$TARGET" ] || usage 1

# Validate ALL enum/list options up front, before any target write (a bad value must never
# leave the repo half-mutated). Every --gates token must be known; empty tokens are rejected.
_gates_arr=(); IFS=, read -r -a _gates_arr <<< "$GATES"
for _g in "${_gates_arr[@]}"; do
  case "$_g" in agents|owner-dispatch|control-plane) ;; *) die "unknown gate '$_g' in --gates (valid: agents, owner-dispatch, control-plane)" ;; esac
done
case "$CI_PLATFORM" in gitlab|none) ;; *) die "--ci-platform must be 'gitlab' or 'none' (got '$CI_PLATFORM')" ;; esac
case "$GITLAB_RUNNER_TAG" in ""|*[!A-Za-z0-9._-]*) die "--gitlab-runner-tag must be one non-empty GitLab tag using only A-Z a-z 0-9 . _ - (got '$GITLAB_RUNNER_TAG')" ;; esac
want() { case ",$GATES," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }
want agents || want owner-dispatch || want control-plane || die "--gates must include at least one of 'agents', 'owner-dispatch', 'control-plane'"

# ----- validate sources + target ---------------------------------------------
command -v git >/dev/null 2>&1 || die "git required"
command -v realpath >/dev/null 2>&1 || die "realpath required"
want agents && assert_trusted_src "$AGENTS_SRC"
want owner-dispatch && assert_trusted_src "$OD_SRC"
want control-plane && assert_trusted_src "$CP_SRC"

[ -d "$TARGET" ] || die "target is not a directory: $TARGET"
TARGET="$(cd "$TARGET" && pwd -P)" || die "cannot resolve target: $TARGET"
# A non-repo, bare repo, or GitLab-group / parent-of-repos checkout fails --show-toplevel
# (the group parent is not itself a repo) and is rejected here; run per member repo for a group.
TOP="$(git -C "$TARGET" rev-parse --show-toplevel 2>/dev/null)" \
  || die "target is not a (non-bare) git repository root: $TARGET — run per member repo for a group checkout"
[ "$TOP" = "$TARGET" ] \
  || die "target is not the repo ROOT (toplevel is $TOP). Run against the repo root, once per repo."

note "install-gates → $TARGET  (gates: $GATES; warn-only)"
# Best run on a clean, dedicated branch (worktree-isolation): warn (don't block) if dirty, so
# the installer's new files aren't tangled into unrelated uncommitted work.
if [ -n "$(git -C "$TARGET" status --porcelain 2>/dev/null)" ]; then
  warn "target has uncommitted changes — install-gates adds files; review/commit them on their own. Prefer a clean dedicated branch."
fi

# ----- scaffold FIRST (before vendoring) -------------------------------------
# Order matters: scaffold AGENTS.md from the PLUGIN's source script BEFORE vendoring, so the
# coverage scan does not see (and demand contracts for) the tools/ and scripts/owner-dispatch/
# dirs this installer is about to create. The repo's own source dirs are still scaffolded.
if [ "$SCAFFOLD" = 1 ]; then
  if want agents; then
    assert_no_escaping_dir_symlinks   # the delegated --fix writes via redirection; keep it in-repo
    sc_out="$(bash "$AGENTS_SRC" --repo "$TARGET" --fix 2>&1)"; sc_rc=$?
    if [ "$sc_rc" = 0 ]; then
      ok "scaffolded missing AGENTS.md stubs (additive — fill each with the real contract)"
    else
      warn "AGENTS.md scaffold did NOT complete (exit $sc_rc) — coverage not scaffolded; run 'tools/check-agent-contract-coverage.sh --check' manually. Detail: $(printf '%s' "$sc_out" | tail -1)"
    fi
  fi
  if want owner-dispatch; then
    if [ -e "$TARGET/.owner-dispatch.json" ]; then
      info ".owner-dispatch.json already present — left untouched"
    else
      safe_write "$TARGET/.owner-dispatch.json" "$(cat <<'JSON'
{
  "_comment": "owner-dispatch firing gate config. enabled:false => complete no-op; enabled:true => gate active. Tune product_globs / exclude_globs to this repo's source layout and confirm a real gated file matches before relying on it (generic globs can silently gate nothing). To go from off to on, flip enabled:true in a SEPARATE config-only change. See scripts/owner-dispatch/README.md. Installed by ccl-skills install-gates.",
  "enabled": false,
  "strict": false,
  "gate_bash": true,
  "product_globs": ["src/**", "internal/**", "app/**", "pkg/**", "cmd/**"],
  "exclude_globs": ["**/*_test.*", "**/*.test.*", "test/**", "tests/**", "docs/**", "**/testdata/**", "**/*.gen.*"],
  "ci_artifact": "design/owner-dispatch-map.md",
  "owner_hint": "product-rd-workflow, then the touched stack owner (*-dev / *-architecture / testing-strategy / product-ui-ux-design)"
}
JSON
)"
      ok ".owner-dispatch.json written (enabled:false) — EDIT product_globs to this repo's layout, then flip enabled:true in a separate change"
    fi
  fi
fi

# ----- vendor scripts ---------------------------------------------------------
# Refreshing OUR vendored engine (these exact paths are install-gates-owned) to the current
# plugin version is intentional — it fixes drift. safe_copy keeps a symlinked/hardlinked dest
# from clobbering or escaping the repo.
vendor_script() { # $1 trusted-src  $2 dest-rel-under-target
  local dest="$TARGET/$2" verb=new
  [ -f "$dest" ] && [ ! -L "$dest" ] && verb=refreshed
  safe_copy "$1" "$dest"
  ok "vendored $2 ($verb)"
}
want agents && vendor_script "$AGENTS_SRC" "tools/check-agent-contract-coverage.sh"
want owner-dispatch && vendor_script "$OD_SRC" "scripts/owner-dispatch/owner-dispatch.sh"
want control-plane && vendor_script "$CP_SRC" "scripts/control-plane/control-plane.sh"

# The vendored dirs hold ONLY a gate engine, but the coverage scan treats any .sh dir as
# source and would flag them as missing a contract. Give each a REAL machinery contract —
# but only when the dir is installer-owned (nothing but our vendored script) and the existing
# AGENTS.md is absent / an untouched scaffolder stub / our own marker. A user-authored
# contract (no marker) or a dir holding the user's own files is never overwritten.
MACHINERY_MARKER="install-gates:machinery"
write_machinery_contract() { # $1 dir-rel  $2 vendored-basename  $3 human-name
  local dir="$TARGET/$1" f="$TARGET/$1/AGENTS.md" e bn
  for e in "$dir"/* "$dir"/.*; do
    [ -e "$e" ] || [ -L "$e" ] || continue   # skip literal-glob non-matches; keep broken symlinks
    bn="$(basename "$e")"
    case "$bn" in .|..|AGENTS.md|.ig.*|"$2") continue ;; esac   # .ig.* = a stale installer temp, not user data
    # ANY remaining entry (file, dir, symlink, fifo, …) means the user owns this dir
    warn "$1/ holds your own files — not writing a machinery contract; add $1/AGENTS.md yourself"; return 0
  done
  # Overwrite ONLY our own machinery contract (or write when absent). Anything else — a
  # user-authored file, OR a scaffolder stub the user has since filled but left the marker in —
  # is treated as user content and never clobbered.
  if [ -e "$f" ] && ! has_marker "$f" "$MACHINERY_MARKER"; then
    info "$1/AGENTS.md is user-authored — left untouched"; return 0
  fi
  safe_write "$f" "<!-- $MACHINERY_MARKER -->
# Agent Contract — vendored gate engine ($3)

This directory holds a gate engine vendored from ccl-skills by install-gates.
Do NOT edit it here — update upstream in ccl-skills and re-run install-gates to refresh.
No product code lives in this directory.
"
  ok "wrote $1/AGENTS.md (machinery contract — satisfies coverage; do not put product code here)"
}
if [ "$SCAFFOLD" = 1 ]; then
  want agents && write_machinery_contract "tools" "check-agent-contract-coverage.sh" "agents-file-coverage-gate"
  want owner-dispatch && write_machinery_contract "scripts/owner-dispatch" "owner-dispatch.sh" "owner-dispatch"
  want control-plane && write_machinery_contract "scripts/control-plane" "control-plane.sh" "control-plane"
fi

# ----- CI fragment (warn-only; you flip to blocking by hand) ------------------
CI_FRAG_MARKER="Generated by ccl-skills install-gates"
if [ "$CI_PLATFORM" = "gitlab" ]; then
  frag="$TARGET/ci/agent-gates.gitlab-ci.yml"
  # Never silently clobber a user-customized fragment: only (re)write if absent or still ours.
  if [ -e "$frag" ] && ! has_marker "$frag" "$CI_FRAG_MARKER"; then
    warn "ci/agent-gates.gitlab-ci.yml exists and was edited (no install-gates marker) — left untouched. Delete it to regenerate."
  else
    body="# $CI_FRAG_MARKER. Vendored gate backstops (warn-only — remove allow_failure / swap --check for --enforce to block).
# Add to your pipeline:   include: { local: ci/agent-gates.gitlab-ci.yml }
# Jobs need a GitLab runner tag: default is '$GITLAB_RUNNER_TAG'. Override with --gitlab-runner-tag for local/self-hosted runners.
"
    if want agents; then
      body="$body
agent-contract-coverage:
  stage: test
  tags: ['$GITLAB_RUNNER_TAG']
  before_script:
    - |
      if ! command -v bash >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
        command -v apk >/dev/null 2>&1 || { echo 'agent-gates require bash/git/python3 or an apk-based image that can install them' >&2; exit 2; }
        apk add --no-cache bash git python3 >/dev/null
      fi
  script:
    - bash tools/check-agent-contract-coverage.sh --repo . --check   # swap for --enforce to block
  allow_failure: true   # warn-only; remove once contracts are filled
"
    fi
    if want owner-dispatch; then
      body="$body
owner-dispatch:
  stage: test
  tags: ['$GITLAB_RUNNER_TAG']
  rules:
    - if: \$CI_MERGE_REQUEST_IID   # MR pipelines only: the diff base SHA exists, no shallow-clone merge-base guesswork
  before_script:
    - |
      if ! command -v bash >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
        command -v apk >/dev/null 2>&1 || { echo 'agent-gates require bash/git/python3 or an apk-based image that can install them' >&2; exit 2; }
        apk add --no-cache bash git python3 >/dev/null
      fi
  script:
    - bash scripts/owner-dispatch/owner-dispatch.sh ci --base \"\$CI_MERGE_REQUEST_DIFF_BASE_SHA\"
  allow_failure: true   # no-op while .owner-dispatch.json enabled:false; flip enabled:true (separate change) + remove this to enforce
"
    fi
    if want control-plane; then
      body="$body
control-plane:
  stage: test
  tags: ['$GITLAB_RUNNER_TAG']
  rules:
    - if: \$CI_MERGE_REQUEST_IID   # MR pipelines only: the diff base SHA exists, no shallow-clone merge-base guesswork
  before_script:
    - |
      if ! command -v bash >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
        command -v apk >/dev/null 2>&1 || { echo 'agent-gates require bash/git/python3 or an apk-based image that can install them' >&2; exit 2; }
        apk add --no-cache bash git python3 >/dev/null
      fi
  script:
    - bash scripts/control-plane/control-plane.sh ci --base \"\$CI_MERGE_REQUEST_DIFF_BASE_SHA\"   # to block: add --enforce AND remove allow_failure
  allow_failure: true   # warn-only advisory: labels the MR control-plane vs product-only
"
    fi
    safe_write "$frag" "$body"
    ok "generated ci/agent-gates.gitlab-ci.yml (warn-only)"
  fi
fi

# ----- next steps -------------------------------------------------------------
note "Installed (warn-only). Next steps (substance, not scaffolding):"
want agents && info "Fill each scaffolded AGENTS.md with the real directory contract (role / allowed+forbidden deps / build+test / link to parent)."
want owner-dispatch && info "Edit .owner-dispatch.json product_globs to this repo's source layout. 'owner-dispatch.sh status' shows opt-in/boundary state only — to prove the globs actually MATCH (a generic glob can silently gate nothing), enable+commit the config then run 'owner-dispatch.sh ci --base <sha>' on a branch that edits a real gated file."
want control-plane && info "control-plane works with built-in defaults (no config needed). Optionally add .control-plane.json (see scripts/control-plane/control-plane.example.json in ccl-skills) to extend or declassify per-repo paths; the enforcement chain itself is hard-pinned."
[ "$CI_PLATFORM" = "gitlab" ] && info "Add to .gitlab-ci.yml:   include: { local: ci/agent-gates.gitlab-ci.yml }   (jobs run warn-only)."
info "To BLOCK later (deliberate, separate, reviewed change): fill contracts / write the owner-dispatch map, flip enabled:true, swap --check→--enforce and remove allow_failure."
info "Commit the vendored scripts + config + fragment. Re-running install-gates refreshes the vendored engines and never overwrites your config / contracts / edited CI fragment."
