#!/usr/bin/env bash
# Reference-access census: which of a skill package's files were actually
# touched by real agent sessions on THIS host, over a lookback window.
#
# Why this exists: a rule set must not grow monotonically, but "retire what is
# not pulling its weight" needs a signal that is not the author's opinion. The
# closest observable proxy on a local host is the per-file access record in the
# agent's own session transcripts (Claude Code `~/.claude/projects/**/*.jsonl`,
# Codex `~/.codex/sessions/**/*.jsonl`): a reference that no session mentioned
# in N days is a relocation/retirement candidate; one mentioned in most sessions
# that loaded the skill is a candidate for promotion into the entrypoint. This
# is the local instantiation of the usage counters that context-evolution
# methods keep per bullet (helpful/harmful counts) and of the "ignored content
# is unnecessary or poorly signaled" observation in the official skill-authoring
# guidance — advisory only, never a gate (Goodhart: a count that becomes a
# target gets gamed by mentioning files).
#
# Privacy contract: the transcripts are private per-host data. This script
# prints ONLY repo-relative skill file paths, per-file session counts, and
# last-touched dates. It never prints transcript text, prompts, absolute paths
# outside the skill tree, or session ids. Its output is safe to paste into a
# private charter; it is still not shared-tree content by itself.
#
# Counting unit: a SESSION (one transcript file) counts once per skill file it
# mentions, whatever the tool (Read, sed, grep, Skill load). "Mentioned" is a
# superset of "read to depth" — treat a count as an upper bound on real use.
#
# Usage:
#   reference-access-census.sh [--skill <name>] [--days <n>] [--repo-root <dir>]
#                              [--logs <dir>[,<dir>...]]
# Defaults: skill=skill-extraction-workflow, days=60, repo-root=cwd-derived,
#           logs=$HOME/.claude/projects,$HOME/.codex/sessions
# Exit 0 on a completed census or an honest unevaluated result (no transcripts);
# exit 2 on usage errors and on input errors (unreadable/vanished/unexecutable
# inputs) — counts are withheld rather than printed as zeros.
set -euo pipefail

skill="skill-extraction-workflow"
days=60
repo_root=""
logs="${HOME}/.claude/projects,${HOME}/.codex/sessions"
while [ $# -gt 0 ]; do
  case "$1" in
    --skill|--days|--repo-root|--logs)
      if [ $# -lt 2 ]; then echo "reference_access_census_usage_error: $1 needs a value" >&2; exit 2; fi ;;
  esac
  case "$1" in
    --skill) skill="$2"; shift 2 ;;
    --days) days="$2"; shift 2 ;;
    --repo-root) repo_root="$2"; shift 2 ;;
    --logs) logs="$2"; shift 2 ;;
    -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
    *) echo "reference_access_census_usage_error: unknown argument $1" >&2; exit 2 ;;
  esac
done
if [ -z "$repo_root" ]; then
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
skill_dir="$repo_root/skills/$skill"
if [ ! -d "$skill_dir" ]; then
  echo "reference_access_census_usage_error: no skill package named skills/$skill under the repo root" >&2; exit 2
fi
case "$days" in ''|*[!0-9]*) echo "reference_access_census_usage_error: --days must be an integer" >&2; exit 2 ;; esac

# Inventory: every tracked markdown file in the package (entrypoint + references).
files=()
while IFS= read -r f; do files+=("$f"); done < <(cd "$repo_root" && git ls-files "skills/$skill/SKILL.md" "skills/$skill/references/*.md" 2>/dev/null | sort)
if [ "${#files[@]}" -eq 0 ]; then
  echo "reference_access_census_usage_error: no tracked SKILL.md/references under skills/$skill" >&2; exit 2
fi

# Candidate transcripts: any .jsonl under the log roots modified within the window.
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
IFS=',' read -r -a roots <<<"$logs"
: > "$tmp/candidates"; : > "$tmp/errors"
# Input errors are never zeros: every scan phase collects stderr, and a non-empty
# error log withholds the table (exit 2) instead of printing counts that would
# read as evidence. grep's no-match status writes nothing to stderr, so it never
# trips this; unreadable, vanished, or unexecutable inputs do. The error log is
# summarized as a count only — file names would be private paths.
withhold_if_errors() {
  if [ -s "$tmp/errors" ]; then
    n="$(wc -l < "$tmp/errors" | tr -d ' ')"
    echo "reference_access_census_unevaluated: $n input error(s) while scanning transcripts (unreadable, vanished, or unexecutable inputs); counts withheld"
    exit 2
  fi
}
for r in "${roots[@]}"; do
  [ -n "$r" ] || continue
  [ -d "$r" ] || continue
  find "$r" -type f -name '*.jsonl' -mtime "-$days" >> "$tmp/candidates" 2>> "$tmp/errors" || true
done
withhold_if_errors
total_sessions="$(wc -l < "$tmp/candidates" | tr -d ' ')"
if [ "$total_sessions" -eq 0 ]; then
  echo "reference_access_census_unevaluated: no transcripts within ${days}d under ${#roots[@]} log root(s); counts withheld"
  exit 0
fi

# Sessions that mention the package at all (fixed-string prefilter keeps this fast).
# xargs batches keep this under ARG_MAX; grep exit 1 (no match in a batch) is not an error.
tr '\n' '\0' < "$tmp/candidates" | xargs -0 -n 200 grep -lF "skills/$skill/" > "$tmp/touching" 2>> "$tmp/errors" || true
withhold_if_errors
touching="$(wc -l < "$tmp/touching" | tr -d ' ')"

# Per-file session count + last-touched date (mtime of the newest touching transcript).
: > "$tmp/rows"
for f in "${files[@]}"; do
  rel="${f#skills/$skill/}"
  if [ "$touching" -eq 0 ]; then n=0; last="-"; else
    tr '\n' '\0' < "$tmp/touching" | xargs -0 -n 200 grep -lF "$f" > "$tmp/hits" 2>> "$tmp/errors" || true
    withhold_if_errors
    n="$(wc -l < "$tmp/hits" | tr -d ' ')"
    if [ "$n" -gt 0 ]; then
      # BSD stat first, GNU stat as the fallback; only the fallback's failure is an error.
      last="$(tr '\n' '\0' < "$tmp/hits" | xargs -0 stat -f '%Sm' -t '%Y-%m-%d' 2>/dev/null | sort | tail -1 || true)"
      [ -n "$last" ] || last="$(tr '\n' '\0' < "$tmp/hits" | xargs -0 stat -c '%y' 2>> "$tmp/errors" | cut -c1-10 | sort | tail -1)"
      [ -n "$last" ] || withhold_if_errors
    else last="-"; fi
  fi
  if [ "$touching" -gt 0 ]; then share="$(( n * 100 / touching ))%"; else share="-"; fi
  printf '%s | %s | %s | %s\n' "$rel" "$n" "$last" "$share" >> "$tmp/rows"
done
printf '%s\n' "reference_access_census: skill=$skill window=${days}d transcripts=$total_sessions sessions_touching_package=$touching"
printf '%s\n' "file | sessions | last_touched | share_of_touching"
sort -t'|' -k2,2nr "$tmp/rows"
echo "reference_access_census_ok"
