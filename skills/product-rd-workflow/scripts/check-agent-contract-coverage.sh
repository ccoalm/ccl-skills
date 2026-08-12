#!/usr/bin/env bash
set -euo pipefail

# Agent-contract coverage gate (per source/code directory).
#
# Team norm: the repo root and every source-code directory carry an AGENTS.md (or
# the configured contract filename). Each code directory is a unit/package with its
# own role — and a manifest does NOT mark one: in Go a single module has one go.mod
# at the root while dal/service/handler/logic/utils are each distinct packages with
# distinct contracts. So scope is "a directory that directly contains source code",
# not "a directory with a build manifest".
#
# This aligns with the agents.md convention — agents read the NEAREST AGENTS.md in
# the directory tree (closest wins), placed "inside each package". There is no root
# index of children to maintain; this gate only checks COVERAGE and never rewrites a
# human-authored file.
#
# Legacy repos rarely satisfy the norm yet, so the default mode REPORTS gaps and
# prints guidance WITHOUT failing — adoption is incremental and automated, not
# dependent on humans remembering.
#
# Modes (default = check):
#   --check    report missing/empty/symlinked contracts; exit 0 (guide; legacy-safe)
#   --enforce  same checks, exit 1 on any gap (wire into CI once the repo has adopted the norm)
#   --fix      scaffold a stub contract in each code dir that lacks one (additive only — never
#              edits or overwrites an existing file)

repo="."
contract_name="AGENTS.md"
mode="check"
exclude_segments="node_modules vendor third_party dist build out target bin obj .git .venv venv env .tox .mypy_cache .pytest_cache __pycache__ .next .nuxt .svelte-kit .output coverage .gradle generated gen .idea .vscode testdata fixtures"
source_exts=".go .py .ts .tsx .js .jsx .mjs .cjs .java .kt .kts .scala .rs .rb .php .swift .c .cc .cpp .cxx .h .hh .hpp .cs .m .mm .vue .svelte .dart .ex .exs .clj .cljs .erl .hs .ml .lua .sh .bash .sql .proto"

usage() {
  cat <<'EOF'
usage: check-agent-contract-coverage.sh [--repo DIR] [--name FILENAME]
                                        [--check | --enforce | --fix]
                                        [--source-ext ".ext1 .ext2 ..."] [--exclude "seg1 seg2 ..."]

Checks that the repo root and every source-code directory carry an agent-contract
file (default AGENTS.md). A directory is in scope when it directly contains a tracked
source file (by extension). Default mode reports gaps and exits 0 (legacy-safe
guidance); --enforce blocks; --fix scaffolds missing contracts (additive).

  --check         report only, exit 0 (default)
  --enforce       exit 1 on any missing/empty/symlinked contract
  --fix           create a stub contract in each in-scope dir that lacks one
  --source-ext S  space-separated extra source extensions (e.g. ".tf .razor")
  --exclude S     space-separated extra path segments to skip
  --repo DIR      repository root to scan (default .)
  --name FILE     contract filename to require (default AGENTS.md)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="${2:?missing value for --repo}"; shift 2 ;;
    --name) contract_name="${2:?missing value for --name}"; shift 2 ;;
    --source-ext) source_exts="$source_exts ${2:?missing value for --source-ext}"; shift 2 ;;
    --exclude) exclude_segments="$exclude_segments ${2:?missing value for --exclude}"; shift 2 ;;
    --check) mode="check"; shift ;;
    --enforce) mode="enforce"; shift ;;
    --fix) mode="fix"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ ! "$contract_name" =~ ^[A-Za-z0-9_.-]+$ ]]; then
  echo "unsupported contract filename: $contract_name" >&2
  exit 2
fi

cd "$repo"

# Group / parent-of-repos guard. This gate checks ONE repository. If the target is
# NOT inside any git work tree yet contains nested git repos, it is a GitLab-group /
# parent-of-repos checkout (sibling repos cloned side by side), not a single repo —
# scanning it as one repo conflates siblings and reports a spurious missing-root
# contract (there is no repo root to own one). A subdirectory *inside* a repo, or a
# repo with submodules, is inside a work tree, so the guard does not fire there.
# (Known limitation: symlinked repo dirs are not followed.) Refuse, in every mode.
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  # -prune stops descent into each found repo (fast; handles arbitrary group nesting).
  nested_repos="$(find . -name .git \
      -not -path '*/node_modules/*' -not -path '*/vendor/*' -not -path '*/third_party/*' \
      -not -path '*/testdata/*' -not -path '*/fixtures/*' -not -path '*/examples/*' \
      -not -path '*/samples/*' -not -path '*/.cache/*' \
      -prune -print 2>/dev/null | sed -e 's#/\.git$##' -e 's#^\./##' | sort -u)"
  if [[ -n "$nested_repos" ]]; then
    count="$(printf '%s\n' "$nested_repos" | grep -c .)"
    {
      echo "error: '$repo' is not a git repository but contains $count nested repo(s) —"
      echo "this looks like a group / parent-of-repos checkout. Run the gate PER REPO:"
      printf '%s\n' "$nested_repos" | sed 's#^#  - #'
      mode_flag=""; [[ "$mode" != "check" ]] && mode_flag=" --$mode"
      echo "  e.g.  (cd \"$repo\" && for d in <each repo above>; do \"$0\" --repo \"\$d\"$mode_flag; done)"
    } >&2
    exit 2
  fi
fi

_seg_excluded() {
  local seg="$1" e
  [[ "$seg" == .* && "$seg" != "." ]] && return 0
  for e in $exclude_segments; do [[ "$seg" == "$e" ]] && return 0; done
  return 1
}
is_excluded() {
  local rest="$1" seg
  while [[ "$rest" == */* ]]; do
    seg="${rest%%/*}"; rest="${rest#*/}"
    _seg_excluded "$seg" && return 0
  done
  _seg_excluded "$rest"
}
is_source() {
  local b="$1" e
  for e in $source_exts; do [[ "$b" == *"$e" ]] && return 0; done
  return 1
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

# 1. Enumerate tracked files (fall back to find outside a work tree).
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git ls-files -co --exclude-standard -z >"$tmp_dir/files.z"
else
  find . -type f -print0 >"$tmp_dir/files.z"
fi

# 2. Derive in-scope dirs (root + every dir with a direct source file) and existing contracts.
: >"$tmp_dir/dirs"
: >"$tmp_dir/contracts"
printf '.\n' >>"$tmp_dir/dirs"
while IFS= read -r -d '' file; do
  file="${file#./}"
  case "$file" in *$'\n'*) echo "skipping path containing a newline: $file" >&2; continue ;; esac
  base="$(basename "$file")"
  dir="$(dirname "$file")"
  if [[ "$base" == "$contract_name" ]]; then
    if [[ "$dir" == "." ]] || ! is_excluded "$dir"; then printf '%s\n' "$file" >>"$tmp_dir/contracts"; fi
    continue
  fi
  if is_source "$base"; then
    if [[ "$dir" == "." ]] || ! is_excluded "$dir"; then printf '%s\n' "$dir" >>"$tmp_dir/dirs"; fi
  fi
done <"$tmp_dir/files.z"
sort -u "$tmp_dir/dirs" -o "$tmp_dir/dirs"
sort -u "$tmp_dir/contracts" -o "$tmp_dir/contracts"

contract_path() { [[ "$1" == "." ]] && printf '%s\n' "$contract_name" || printf '%s/%s\n' "$1" "$contract_name"; }

scaffold() {
  local target="$1" dir="$2"
  cat >"$target" <<EOF
# Agent Contract — ${dir}

<!-- Scaffolded by check-agent-contract-coverage.sh. Replace this with the rules an
agent must follow when working in this directory: its role/responsibility; allowed and
forbidden dependencies and layering rules (e.g. a logic layer must not access the
database directly — go through the data-access layer); invariants; build/test commands;
and a link to the nearest parent contract. An empty contract is still reported as a gap
and blocks --enforce. -->
EOF
}

# 3a. Missing contracts in in-scope dirs (only these are scaffolded). Skip symlinks here;
#     they are reported in 3b without being followed.
missing=(); created=()
while IFS= read -r dir; do
  cpath="$(contract_path "$dir")"
  [[ -L "$cpath" ]] && continue
  if [[ ! -f "$cpath" ]]; then
    if [[ "$mode" == "fix" ]]; then scaffold "$cpath" "$dir"; created+=("$cpath"); else missing+=("$cpath"); fi
  fi
done <"$tmp_dir/dirs"

# 3b. Every existing tracked contract must be a real, non-empty file (anywhere — an empty
#     or symlinked AGENTS.md is a defect wherever it sits).
empty=(); symlinked=()
while IFS= read -r c; do
  [[ -n "$c" ]] || continue
  if [[ -L "$c" ]]; then symlinked+=("$c")
  elif [[ -f "$c" && ! -s "$c" ]]; then empty+=("$c")
  fi
done <"$tmp_dir/contracts"

# 4. Report.
status=0
report_list() { local label="$1"; shift; (($#)) || return 0; echo "$label" >&2; printf '  %s\n' "$@" >&2; }
if [[ "$mode" == "fix" ]]; then
  report_list "scaffolded contract files (now fill them in):" ${created[@]+"${created[@]}"}
elif ((${#missing[@]})); then
  echo "source directories missing a $contract_name contract:" >&2
  printf '  %s\n' "${missing[@]}" >&2
  echo "  → adopt incrementally: run with --fix to scaffold stubs, then fill them in." >&2
  status=1
fi
report_list "empty contract files (fill them in):" ${empty[@]+"${empty[@]}"}
[[ ${#empty[@]} -eq 0 ]] || status=1
report_list "symlinked contract paths (not followed; replace with a real file):" ${symlinked[@]+"${symlinked[@]}"}
[[ ${#symlinked[@]} -eq 0 ]] || status=1

if [[ "$status" -eq 0 ]]; then
  echo "agent contract coverage ok"
  exit 0
fi
# Gaps found. Block only in --enforce; guide (exit 0) otherwise so legacy CI is not broken.
if [[ "$mode" == "enforce" ]]; then exit 1; fi
echo "(guidance mode: gaps reported, not blocking — use --enforce in CI once the repo has adopted the norm)" >&2
exit 0
