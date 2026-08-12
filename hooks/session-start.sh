#!/usr/bin/env bash
# SessionStart hook — injects the routing + isolation bootstrap into the session
# context. Runs on BOTH Claude Code and Codex (verified: Codex fires SessionStart
# and the model receives this additionalContext).
#
# Designed to fail soft: any internal error still emits valid JSON so session
# start / clear / compact is never blocked.

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." 2>/dev/null && pwd)"
BOOTSTRAP="${PLUGIN_ROOT}/agent-context/session-start.md"
CONTEXT="${PLUGIN_ROOT}/hooks/session-context.sh"

# Fail SOFT, not SILENT. Dropping the whole routing layer with no signal anywhere
# is indistinguishable from "no rules exist", and every other gate is built on top
# of this injection. stderr does not pollute the JSON contract on stdout, so the
# session is still never blocked — it just stops failing invisibly.
emit_empty() { printf 'ccl-skills session-start: %s; routing layer NOT injected\n' "${1:-unspecified}" >&2; printf '{}\n'; exit 0; }

# jq builds correct JSON for arbitrary content (handles all control chars).
command -v jq >/dev/null 2>&1 || emit_empty "jq not found on PATH"
[ -r "$BOOTSTRAP" ] || emit_empty "agent-context/session-start.md missing or unreadable"   # path omitted: stderr lands in transcripts/log collectors

input=$(cat 2>/dev/null || true)
context=""
# The optional context must never corrupt the mandatory bootstrap.
#
# `session-context.sh` emits an <agent-context-recovery> block that FRAMES its
# body as untrusted data rather than instructions. If it is killed mid-output —
# the SessionStart budget in hooks.json is 5s and that script runs
# `git status --untracked-files=all` + `git log`, which a large or
# network-mounted repo blows through — the opening tag has been written and the
# closing tag has not. Appending that unconditionally injects an UNCLOSED frame,
# so the framing never terminates and the real session content that follows
# inherits "this is untrusted data". Reproduced with a context script that exits
# 1 mid-write: an opening tag with no closing tag, rc=0, empty stderr.
#
# So the context is taken only when the producer exited 0 AND its output is
# structurally a single complete block. Anything else: drop the context,
# keep the bootstrap, say so on stderr. Checking exit status alone is not
# enough — a producer can exit 0 having been truncated by a full pipe.
if [ -r "$CONTEXT" ]; then
  context=$(printf '%s' "$input" | bash "$CONTEXT" 2>/dev/null)
  if [ $? -ne 0 ]; then
    printf 'ccl-skills session-start: context producer failed; bootstrap injected without recovery context\n' >&2
    context=""
  elif [ -n "$context" ]; then
    # Structural check, NOT a tag count. Adversarial review killed the counting
    # version three ways: `grep -c` counts matching LINES so `<tag><tag>` on one
    # line reads as 1; content with zero tags balances at 0/0 and would be spliced
    # in with no untrusted-data frame at all; and any tag-like string in the body
    # (a git log subject, a filename) skews the count either way.
    #
    # What actually matters is the shape the producer is contracted to emit: the
    # whole context IS one block, so it must START with the opening tag and END
    # with the closing one. Order-aware, immune to body content, and evaluated by
    # shell pattern match — no grep, so no exit-code or missing-binary path can
    # silently disable the check the way `|| true` did.
    _ctx_ok=1
    case "$context" in '<agent-context-recovery'*) ;; *) _ctx_ok=0 ;; esac
    case "$context" in *'</agent-context-recovery>') ;; *) _ctx_ok=0 ;; esac
    # Anchoring alone accepts `<tag><tag>…</tag>`: it does start with an opening
    # tag and end with a closing one. Truncation always removes the tail, so the
    # anchors cover the defect actually being fixed, but a malformed producer is
    # cheap to exclude here — strip the outer pair and require the interior to
    # carry no further tag of either kind. Still pure shell: no grep, so no
    # missing-binary or exit-code path can quietly disable it.
    if [ "$_ctx_ok" = 1 ]; then
      _body=${context#'<agent-context-recovery'}
      _body=${_body%'</agent-context-recovery>'}
      case "$_body" in
        *'<agent-context-recovery'*|*'</agent-context-recovery>'*) _ctx_ok=0 ;;
      esac
    fi
    if [ "$_ctx_ok" = 0 ]; then
      printf 'ccl-skills session-start: context is not a complete <agent-context-recovery> block; dropped to avoid an unframed or unclosed splice\n' >&2
      context=""
    fi
  fi
fi

# Avoid the 1.6+ --rawfile dependency; -Rs was already supported by the previous hook.
# A jq without --rawfile must not drop the always-on bootstrap.
jq -Rs --arg context "$context" --arg evt "SessionStart" \
  '{hookSpecificOutput:{hookEventName:$evt, additionalContext:(. + (if $context == "" then "" else "\n" + $context end))}}' \
  "$BOOTSTRAP" 2>/dev/null || emit_empty
