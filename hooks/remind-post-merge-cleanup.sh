#!/usr/bin/env bash
# PostToolUse reminder — post-merge worktree/branch cleanup (Bash tool only).
#
# WHY: worktree-isolation 收尾 requires cleaning the source worktree + local
# branch + remote branch immediately after an AUTHORIZED merge. That rule was
# prose-only and recurrently skipped — stale worktrees/branches pile up locally
# and someone has to sweep them later. The content already exists in the skill;
# what was missing is a FIRING mechanism at the moment cleanup becomes due. This
# hook is that mechanism: right after a platform merge command it injects an
# advisory reminder + the current worktree list + the exact cleanup commands.
#
# NON-BLOCKING by design: PostToolUse runs AFTER the tool (the merge already
# happened, so there is nothing to deny), and a hard block would wrongly trip on
# a permanent/integration source branch (a dev→main promotion source must NOT be
# deleted). So this only reminds; it never fails the command.
#
# NOT a security boundary: obfuscated merges (eval/subshell/interpreter -e) are
# out of scope, the same declared class as guard-merge-authorization.sh. This
# catches the ROUTINE direct spellings — which is all an advisory needs.
#
# ACCEPTED best-effort residuals (risk-owner accepted; do NOT chase these with
# more string heuristics — inferring "a real, completed merge" from an open-ended
# command + freeform tool output is structurally non-convergent). The reminder's
# own TEXT is the real safety net: it leads with "confirm 已集成判据 first; a
# merge that was only authorized/queued/failed does NOT count", so a stray fire
# is a no-op for a correctly-behaving agent, not a destructive action.
#   - MISS: raw REST / GraphQL / curl merges are not detected (only the CLI
#     subcommands are). The CLI is the near-universal agent merge path.
#   - MISS: squash-merge cleanup is surfaced by the reminder text's 已集成判据,
#     not auto-detected (consistent with the skill's squash-conservative stance).
#   - FALSE FIRE (rare): a non-merge command that literally spells an unquoted
#     `glab mr merge` / `gh pr merge` (e.g. `echo glab mr merge`, `true # gh pr
#     merge`) — a command-word parser would be needed to kill these and that is
#     the non-convergent path we are avoiding.
#   - FALSE FIRE (rare): a failed CLI merge whose result carries no recognized
#     failure signal (no nonzero exit code / is_error, and unrecognized error
#     text) — mitigated by the verify-first reminder text.
#
# Degrade semantics (per hooks/AGENTS.md): jq missing → emit nothing (exit 0);
# any internal issue → stay silent rather than disrupt the session. The reminder
# is a helpful nudge, never load-bearing enforcement, so silent degrade is safe.

set -f
input=$(cat)

# jq absent: cannot safely parse/emit — degrade to no reminder (never break Bash).
command -v jq >/dev/null 2>&1 || exit 0

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

# Mask quoted prose spans (commit messages / MR titles) so a mere MENTION like
# `git commit -m "revert glab mr merge"` cannot trigger the reminder. Same
# two-step unwrap-then-mask as guard-merge-authorization.sh (single-word quoted
# values keep their content; whitespace-bearing prose becomes QUOTED).
masked=$(printf '%s' "$cmd" | sed -E \
  -e 's/"([^"[:space:];|&<>()]*)"/\1/g' \
  -e "s/'([^'[:space:];|&<>()]*)'/\\1/g" \
  -e 's/"[^"]*"/QUOTED/g' \
  -e "s/'[^']*'/QUOTED/g")

# Detect ONLY the high-confidence CLI merge subcommands: `glab mr merge/accept`
# and `gh pr merge`, matched on the MASKED command (quoted prose is QUOTED, so a
# commit-message mention like `git commit -m "revert glab mr merge"` can't trip;
# global flags between tool and subcommand — `gh -R owner/repo pr merge`,
# `glab --hostname h mr accept` — are tolerated via the [^&|;]* intra-segment
# span). We deliberately DO NOT match raw REST paths (merge_requests|pulls/<n>/
# merge), GraphQL mutation names, or curl: matching those tokens anywhere in an
# open-ended command recurrently false-fired on non-merge commands (issue-body
# `-f body=` values, echoed docs, `git log --grep`), and an advisory that cries
# wolf gets ignored. Raw-API / GraphQL / curl merges are an ACCEPTED best-effort
# NON-fire — `glab mr merge` / `gh pr merge` is the near-universal agent merge
# path, and the human-readable cleanup rule in worktree-isolation SKILL.md +
# bootstrap covers EVERY merge path regardless of this reminder.
printf '%s' "$masked" | grep -Eq \
  'glab[[:space:]]([^&|;]*[[:space:]])?mr[[:space:]]+(merge|accept)([[:space:]]|$)|gh[[:space:]]([^&|;]*[[:space:]])?pr[[:space:]]+merge([[:space:]]|$)' \
  || exit 0

# `... merge --help` / `-h` shows help, it does not merge.
printf '%s' "$masked" | grep -Eq -- '(^|[[:space:]])(-h|--help)([[:space:]]|$)' && exit 0

# Suppress unless the merge actually COMPLETED now — the reminder recommends a
# destructive `git push origin --delete` (NOT refused for an un-integrated
# branch), so a premature fire (scheduled auto-merge, or a failed merge) must not
# nudge cleanup of un-merged work. Best-effort defense-in-depth; the reminder
# TEXT is the primary safety (it leads with "confirm 已集成判据 first; a merge
# that was only authorized/queued/failed does NOT count").

# (1) Structured failure signal from the tool result, when the host provides one
#     (exit code / is_error / interrupted). Harmless no-op when absent.
fail_struct=$(printf '%s' "$input" | jq -r '
  (.tool_response // {}) as $r
  | if ($r|type)=="object"
    then ( (($r.exit_code // $r.returncode // $r.exitCode // 0)|tostring) as $ec
           | if (($ec|test("^-?[0-9]+$")) and $ec!="0") or ($r.is_error==true) or ($r.interrupted==true)
             then "fail" else "" end )
    else "" end' 2>/dev/null)
[ "$fail_struct" = "fail" ] && exit 0

resp=$(printf '%s' "$input" | jq -r '(.tool_response // "") | tostring' 2>/dev/null)

# (2) Scheduled / queued auto-merge (flags or response phrasing). Explicit
#     immediate override (--auto-merge=false) does NOT match the flag branch.
printf '%s' "$masked" | grep -Eq -- \
  '(--auto([[:space:]]|=true|$)|--auto-merge([[:space:]]|=true|$)|--when-pipeline-succeeds|--merge-when-pipeline-succeeds)' \
  && exit 0
printf '%s' "$resp" | grep -Eqi \
  'will be automatically merged|set to (be )?(auto-?)?merge|to be merged when|when the pipeline succeeds|when pipeline succeeds|scheduled to (be )?merge|auto-merge (is )?enabled|enabled auto-merge' \
  && exit 0

# (3) Failure phrases in freeform text (secondary; the structured signal above is
#     preferred and more reliable).
printf '%s' "$resp" | grep -Eqi \
  'CONFLICT|is not mergeable|cannot be merged|merge failed|not authorized|unauthorized|forbidden|permission denied|[^a-z]denied|not accessible|could not resolve|no such|not found|does not exist|HTTP [45][0-9][0-9]|exit (status|code) [1-9]|operation canceled|rate limit' \
  && exit 0

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] && [ -d "$cwd" ] || cwd=$(pwd)

# Best-effort worktree inventory so the reminder is actionable (agent sees the
# candidate paths/branches). Never fail if git is missing or cwd is not a repo.
wt=""
if command -v git >/dev/null 2>&1 && git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
  wt=$(git -C "$cwd" worktree list 2>/dev/null)
fi

reminder="🧹 worktree-isolation 收尾提醒（自动）：检测到 MR/PR 合并命令。先按本节「已集成判据」确认这次合并**已真正完成**（平台 MR/PR 已在当前 head SHA 上 merged；仅授权、仅排队 auto-merge、或合并失败都不算已集成）；确认后，若源分支是临时 feature 分支就立即清理三侧，别攒：
  git worktree remove <path>        # 不加 --force（脏树/未合并被拒=安全网）
  git branch -d <branch>            # 不加 -D（未合并被拒=安全网）
  git push origin --delete <branch> # 远端源分支——破坏性，务必先确认已集成再删
  git worktree prune && git worktree list && git branch   # 验证三侧都没了
唯一例外：源分支本身是永久/集成分支（如 dev→main promotion，源是 dev）——绝不删。squash 合并测不到祖先则保守保留、先确认已集成。"
if [ -n "$wt" ]; then
  reminder="${reminder}
当前 worktrees（挑出刚合并的那个源 worktree 清理）：
${wt}"
fi

# PostToolUse output contract: additionalContext feeds the reminder into the
# model's context (so the agent acts on it); systemMessage surfaces a short note
# to the user. Mirrors the plugin's existing hookSpecificOutput usage.
jq -nc --arg r "$reminder" \
  '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$r},systemMessage:"🧹 合并后清理提醒已注入（worktree-isolation 收尾）。"}'
exit 0
