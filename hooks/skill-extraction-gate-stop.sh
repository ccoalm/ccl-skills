#!/usr/bin/env bash
# Stop hook — extraction-gate backstop for shared-skill edits.
# Blocks the stop ONCE PER SESSION when this session edited files under a
# ccl-skills checkout's skills/<slug>/ tree (canonical repo or any worktree)
# but the transcript shows no visible skill-extraction-workflow invocation.
# Mechanizes the skill's closeout rule: a skill-change with no visible
# extraction invocation is interim.
#
# Safety posture:
# - HARD FAIL-OPEN: any parse error, missing tool, or missing transcript => allow.
# - Once-per-session via a session marker file (NOT stop_hook_active alone, which
#   another Stop hook's block would set and mask this gate entirely).
# - Scope guard: only fires when the edited tree is a ccl-skills checkout,
#   identified by the sibling marker skills/skill-extraction-workflow/SKILL.md;
#   vendored/unrelated skills/ trees in product repos and installed plugin copies
#   (Claude/Codex caches, Antigravity's ~/.gemini/config/plugins) are exempt.
# - Read-only on repo state; writes only its own /tmp marker.
# Known accepted fail-open gaps (advisory backstop, CI is the hard gate):
# Bash-driven edits, NotebookEdit, exotic transcript schemas, spoofed invocation text,
# and non-hooks/scripts plugin surfaces (bin/, .mcp.json, monitors/) — rare, CI-gated.
set -u
IN=$(cat 2>/dev/null) || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# One jq call reads the four Stop payload fields when bounded; otherwise each
# field falls back to its original per-field read.
unset fields fields_read hf_session hf_active hf_transcript hf_cwd
fields=$(printf '%s' "$IN" 2>/dev/null | jq -rs '
  def trim_nl($n): if endswith("\n") then (if $n == 0 then null else .[:-1] | trim_nl($n - 1) end) else . end;
  def bool_or_str($v): if ($v | type) == "boolean" then ($v | tostring) else $v end;
  select(length == 1) | .[0] | select(type == "object")
  | [(.session_id // ""), bool_or_str(.stop_hook_active // false), (.transcript_path // ""), (.cwd // "")]
  | select(all(.[]; type == "string" and length <= 65536
      and (split("\u0000") | length) < 2))
  | map(trim_nl(16)) | select(all(.[]; type == "string"))
  | "hf_session=\(.[0] | @sh) hf_active=\(.[1] | @sh) hf_transcript=\(.[2] | @sh) hf_cwd=\(.[3] | @sh) fields_read=1"' 2>/dev/null)
fields_read=""
case "$fields" in *' fields_read=1') eval "$fields" ;; esac

# session_id feeds a file path: strip to a safe charset and cap length so a
# hostile/garbled value (e.g. containing ../ or /) cannot traverse out of TMPDIR.
if [ -n "$fields_read" ]; then
  SESSION=$(printf '%s' "$hf_session" | tr -cd 'A-Za-z0-9._-' | cut -c1-64)
else
  SESSION=$(printf '%s' "$IN" | jq -r '.session_id // empty' 2>/dev/null | tr -cd 'A-Za-z0-9._-' | cut -c1-64)
fi
MARKER="${TMPDIR:-/tmp}/skill-extraction-gate-${SESSION:-nosession}.blocked"
if [ -n "$SESSION" ]; then
  # once per session: if we already blocked, allow.
  [ -e "$MARKER" ] && exit 0
else
  # no session id: fall back to the global re-stop flag to avoid loops.
  if [ -n "$fields_read" ]; then
    [ "$hf_active" = "true" ] && exit 0
  else
    [ "$(printf '%s' "$IN" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "true" ] && exit 0
  fi
fi

if [ -n "$fields_read" ]; then TRANSCRIPT=$hf_transcript; else
  TRANSCRIPT=$(printf '%s' "$IN" | jq -r '.transcript_path // empty' 2>/dev/null)
fi
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ] || exit 0

# 1) Candidate shared-skill/plugin-behavior edits this session (Edit/Write/MultiEdit on
#    skills/<slug>/... OR the plugin behavior surfaces hooks/ and repo-root scripts/).
HELPER="$(cd "$(dirname "$0")" && pwd)/host-input.py"
command -v python3 >/dev/null 2>&1 && [ -r "$HELPER" ] || {
  jq -nc '{systemMessage:"Skill workflow check skipped: its local helper is unavailable. This does not block your task."}'
  exit 0
}
if [ -n "$fields_read" ]; then CWD=$hf_cwd; else
  CWD=$(printf '%s' "$IN" | jq -r '.cwd // empty' 2>/dev/null)
fi
SUMMARY=$(python3 "$HELPER" transcript "$TRANSCRIPT" "${CWD:-$PWD}" 2>/dev/null) || {
  # A failed helper may print nothing, and jq 1.6 `-e` exits 0 on empty input.
  if [ -n "$SUMMARY" ] && printf '%s' "$SUMMARY" | jq -e '.truncated == true' >/dev/null 2>&1; then
    # A complete recent context may prove invocation despite the old prefix.
    # Otherwise the helper emits this advisory at most once per actor/file.
    printf '%s' "$IN" | python3 "$HELPER" extraction-overflow 2>/dev/null ||
      jq -nc '{systemMessage:"Conversation history is too large for the skill workflow check. The check is incomplete; this does not block your task."}'
  else
    jq -nc '{systemMessage:"Skill workflow check incomplete: conversation history could not be read. This does not block your task."}'
  fi
  exit 0
}
unset summary_fields summary_read hf_invoked hf_candidates
summary_fields=$(printf '%s' "$SUMMARY" 2>/dev/null | jq -rs '
  def trim_nl($n): if endswith("\n") then (if $n == 0 then null else .[:-1] | trim_nl($n - 1) end) else . end;
  select(length == 1) | .[0] | select(type == "object")
  | [((.requested_skills | any(. == "ccl-skills:skill-extraction-workflow" or . == "skill-extraction-workflow")) | if . then "1" else "0" end),
     ([.edit_paths[:40][] | select(type == "string")] | join("\n"))]
  | select(all(.[]; type == "string" and length <= 65536
      and (split("\u0000") | length) < 2))
  | map(trim_nl(16)) | select(all(.[]; type == "string"))
  | "hf_invoked=\(.[0] | @sh) hf_candidates=\(.[1] | @sh) summary_read=1"' 2>/dev/null)
summary_read=""
case "$summary_fields" in *' summary_read=1') eval "$summary_fields" ;; esac
if [ -n "$summary_read" ]; then CANDIDATES=$hf_candidates; else
  CANDIDATES=$(printf '%s' "$SUMMARY" | jq -r '.edit_paths[:40][]' 2>/dev/null)
fi
[ -n "$CANDIDATES" ] || exit 0

# 2) Scope guard: at least one edited path must live under a ccl-skills checkout
#    (root containing skills/skill-extraction-workflow/SKILL.md), excluding plugin caches.
IN_SCOPE=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in */plugins/cache/*|*/.codex/*|*/.gemini/config/plugins/*) continue ;; esac
  # Every skills/, hooks/ or scripts/ component, not only the first: a checkout
  # may sit under an ancestor that carries one of those names.
  case "$f" in /*) prefix="" ;; *) prefix="." ;; esac
  IFS=/ read -r -a parts <<PARTS
$f
PARTS
  for part in "${parts[@]}"; do
    [ -n "$part" ] || continue
    case "$part" in
      skills|hooks|scripts)
        if [ -n "$prefix" ] && [ "$prefix" != "." ] && [ -f "$prefix/skills/skill-extraction-workflow/SKILL.md" ]; then IN_SCOPE=1; break 2; fi ;;
    esac
    prefix="$prefix/$part"
  done
done <<EOF
$CANDIDATES
EOF
[ -n "$IN_SCOPE" ] || exit 0

# 3) Was skill-extraction-workflow visibly invoked this session?
if [ -n "$summary_read" ]; then
  [ "$hf_invoked" = "1" ] && exit 0
elif printf '%s' "$SUMMARY" | jq -e '.requested_skills | any(. == "ccl-skills:skill-extraction-workflow" or . == "skill-extraction-workflow")' >/dev/null 2>&1; then
  exit 0
fi

# Edits in scope, gate absent -> record the marker, then block once with the reason.
[ -n "$SESSION" ] && : > "$MARKER" 2>/dev/null
cat <<'JSON'
{"decision":"block","reason":"Extraction-gate backstop: this session edited ccl-skills shared-skill or plugin-behavior files (skills/<name>/..., hooks/, or repo-root scripts/) but skill-extraction-workflow was never visibly invoked. Per the closeout gate such commits are interim. Before stopping: invoke ccl-skills:skill-extraction-workflow and run the round's gate (charter/RCA/dual-track), OR explicitly report the work as interim/uncommitted with the reason, OR state why the edits are out of the gate's scope."}
JSON
exit 0
