#!/usr/bin/env bash
# PreToolUse reminder — the last code review must cover what the pull request
# carries (Bash tool only).
#
# WHY: code-review's completion walk (references/development-completion.md,
# "Before a pull request or a ready report") requires a renewed review of every
# change made after the last conclusive review — a finding fix of any severity,
# an added test, a changelog line — run by the agent, never left to a human
# reviewer. The rule was stated, and an agent still committed a post-review test
# and opened the merge request with the delta unreviewed. What was missing is a
# firing point AT the transition, not more text: this hook fires on the command
# that opens, readies or merges a pull/merge request and compares HEAD with the
# local receipt review_gate.py writes after each conclusive review.
#
# NON-BLOCKING by design: the receipt cannot tell an evidence-only commit from a
# code change, and a deny or ask would hand the decision to a human, which the
# walk forbids. The reminder names the unreviewed commits so the agent can run
# the renewed review; it never fails the command.
#
# NOT a security boundary: obfuscated spellings (eval, subshells, raw REST or
# GraphQL calls) are out of scope, the same declared class as the other
# pull-request hooks here. A push to a branch that already has an open pull
# request is not detected either: nothing in the command says one exists.
#
# Degrade semantics (hooks/AGENTS.md): jq or git missing, cwd not a repository,
# unreadable receipt → stay silent, never break Bash.

set -f
input=$(cat)

command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

# Same unwrap-then-mask as remind-post-merge-cleanup.sh, so a mention inside a
# commit message or a title cannot trigger the reminder.
masked=$(printf '%s' "$cmd" | sed -E \
  -e 's/"([^"[:space:];|&<>()]*)"/\1/g' \
  -e "s/'([^'[:space:];|&<>()]*)'/\\1/g" \
  -e 's/"[^"]*"/QUOTED/g' \
  -e "s/'[^']*'/QUOTED/g")

# Judged per command segment: `gh pr create --help; gh pr create --fill` still
# opens a pull request in its second segment.
pr_op='gh[[:space:]]([^&|;]*[[:space:]])?pr[[:space:]]+(create|ready|merge)([[:space:]]|$)|glab[[:space:]]([^&|;]*[[:space:]])?mr[[:space:]]+(create|new|merge|accept)([[:space:]]|$)|glab[[:space:]]([^&|;]*[[:space:]])?mr[[:space:]]+update([^&|;]*[[:space:]])--ready([[:space:]]|$)'
segments=$(printf '%s\n' "$masked" | tr ';&|' '\n\n\n')
printf '%s\n' "$segments" | grep -E "$pr_op" \
  | grep -Ev -- '(^|[[:space:]])(-h|--help)([[:space:]]|$)' | grep -q . || exit 0

# A segment that moves HEAD before any pull-request operation in the same
# command (commit, rebase, reset...) makes the HEAD this hook sees stale by the
# time that operation runs; a move after the last one does not.
moves_head=$(printf '%s\n' "$segments" | awk \
  -v op="$pr_op" \
  -v mv='git[[:space:]]([^&|;]*[[:space:]])?(commit|merge|rebase|reset|cherry-pick|am|pull|revert|checkout|switch)([[:space:]]|$)' \
  -v help='(^|[[:space:]])(-h|--help)([[:space:]]|$)' \
  '$0 ~ mv { moved = 1 } $0 ~ op && $0 !~ help && moved { m = 1 } END { print m + 0 }')

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] && [ -d "$cwd" ] || cwd=$(pwd)
# A leading `cd <dir> &&` names the worktree the command runs in. A quoted
# directory is read from the original command, since masking replaced it; the
# text is matched, never evaluated.
lead_dir=$(printf '%s' "$cmd" | sed -nE \
  -e 's/^[[:space:]]*cd[[:space:]]+"([^"$`\\]+)"[[:space:]]*&&.*/\1/p' \
  -e "s/^[[:space:]]*cd[[:space:]]+'([^']+)'[[:space:]]*&&.*/\\1/p" | head -n 1)
[ -n "$lead_dir" ] || lead_dir=$(printf '%s' "$masked" | sed -nE 's/^[[:space:]]*cd[[:space:]]+([^;&|[:space:]]+)[[:space:]]*&&.*/\1/p')
if [ -n "$lead_dir" ]; then
  case "$lead_dir" in
    /*) [ -d "$lead_dir" ] && cwd="$lead_dir" ;;
    *) [ -d "$cwd/$lead_dir" ] && cwd="$cwd/$lead_dir" ;;
  esac
fi

# No repository-supplied executable (fsmonitor, pager) runs from this hook.
g() { git -c core.fsmonitor=false --no-pager -C "$cwd" "$@"; }

git_dir=$(g rev-parse --absolute-git-dir 2>/dev/null) || exit 0
head=$(g rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null) || exit 0
receipt="$git_dir/ccl-code-review/last-review.json"

walk='code-review development-completion「Before a pull request or a ready report」'
if [ ! -f "$receipt" ] || [ -L "$receipt" ]; then
  note="⚠️ 已注入 code-review 覆盖检查：这个 worktree 没有结论性评审记录。"
  message="⚠️ code-review 覆盖检查（自动）：这个 worktree 没有记录到任何结论性的 code-review 结果，就要开 / 就绪 / 合并 PR。若本次改了代码或可执行测试，先按 ${walk} 由你自己跑评审，不交给人工 review；确实不需要评审（纯文档且不属共享技能改动等）就在报告里写明理由。"
else
  reviewed=$(jq -r '.head // empty' "$receipt" 2>/dev/null)
  clean=$(jq -r '.worktree_clean // empty' "$receipt" 2>/dev/null)
  mode=$(jq -r '.mode // "?"' "$receipt" 2>/dev/null)
  status=$(jq -r '.status // "?"' "$receipt" 2>/dev/null)
  at=$(jq -r '.recorded_at // "?"' "$receipt" 2>/dev/null)
  printf '%s' "$reviewed" | grep -Eq '^[0-9a-f]{40,64}$' || exit 0
  if [ "$moves_head" = 0 ] && [ "$reviewed" = "$head" ] && [ "$clean" = "true" ]; then
    exit 0
  fi
  reviewed_tree=$(g rev-parse -q --verify "${reviewed}^{tree}" 2>/dev/null || true)
  head_tree=$(g rev-parse -q --verify "${head}^{tree}" 2>/dev/null || true)
  if [ "$moves_head" = 0 ] && [ "$clean" = "true" ] && [ -n "$reviewed_tree" ] && [ "$reviewed_tree" = "$head_tree" ]; then
    exit 0
  fi
  short_reviewed=$(printf '%.12s' "$reviewed")
  short_head=$(printf '%.12s' "$head")
  if [ "$moves_head" = 1 ]; then
    detail="这条命令会先改动 HEAD（commit / rebase / reset 等）再开 / 就绪 / 合并 PR，本 hook 看不到新产生的提交，无法确认它们被评审过；拆开执行，先提交，再让评审覆盖新 HEAD。"
  elif [ "$reviewed" = "$head" ]; then
    detail="评审时工作区有未提交改动，之后 HEAD 没动；确认那批改动就是现在要提交的内容。"
  elif g merge-base --is-ancestor "$reviewed" "$head" 2>/dev/null; then
    commits=$(g log --oneline --no-decorate -n 20 "${reviewed}..${head}" 2>/dev/null)
    stat=$(g diff --stat "$reviewed" "$head" 2>/dev/null | tail -n 1)
    detail="评审之后又有这些提交（最多列 20 条）：
${commits}
${stat}"
    [ "$clean" = "true" ] || detail="${detail}
（评审时工作区还有未提交改动：若这些提交正是那批改动，内容可能已被评审过，逐条核对。）"
  else
    detail="评审过的提交 ${short_reviewed} 已不在当前 HEAD 的历史里（rebase / amend / 换了分支），无法证明现在的内容被评审过。"
  fi
  note="⚠️ 已注入 code-review 覆盖检查：当前 HEAD 没有被最后一次评审覆盖。"
  message="⚠️ code-review 覆盖检查（自动）：最后一次结论性评审（${mode}, ${status}, ${at}）覆盖的是 ${short_reviewed}，当前 HEAD 是 ${short_head}。
${detail}
按 ${walk}：评审后的任何改动（含测试、文档、changelog）都要先由你按所属闸重审，重审最多 5 次，不交给人工 review，也不能说 HEAD 已评审。只多了评审记录文件（结果 JSON、处置说明）时可忽略本提醒。"
fi

jq -nc --arg r "$message" --arg n "$note" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$r},systemMessage:$n}'
exit 0
