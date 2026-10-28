#!/usr/bin/env bash
# PreToolUse reminder — the last code review must cover what the pull request
# carries (Bash tool only).
#
# WHY: code-review's completion walk (references/development-completion.md,
# "Before a pull request or a ready report") requires every implementation change
# made after the last conclusive pass to be covered — by the challenge that
# follows the review, by one delta pass on the post-challenge fixes, or by
# the agent's own disposition with test evidence — never left to a human reviewer. The rule was stated, and an agent still committed a post-review test
# and opened the merge request with the delta unreviewed. What was missing is a
# firing point AT the transition, not more text: this hook fires on the command
# that opens, readies or merges a pull/merge request and compares HEAD with the
# local receipt review_gate.py writes after each conclusive review.
#
# Coverage is not disposition: a review that returned findings covers HEAD as
# well as one that passed. The reminder stays quiet only for a passed receipt
# covering HEAD; a completion checkpoint (`--mode complete`) that disposes the
# findings records a passed receipt. Every reminder names the receipt path it
# read, so results saved elsewhere are not mistaken for that receipt.
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

# True when HEAD differs from the reviewed commit only by integrating the
# target (Gerrit's TRIVIAL_REBASE and MERGE_FIRST_PARENT_UPDATE change kinds,
# narrowed to the path-disjoint case). With the reviewed paths being the files
# the reviewed commit changed since it met the target: the target changed none
# of them since then, HEAD holds exactly the reviewed version of each, and
# every other path in HEAD is exactly the target's. That is what a clean merge
# of the target or a conflict-free rebase onto it produces; a resolved
# conflict, an edit in a merge, an extra commit, another merged branch or a
# relocated edit is not. Only tree entries are compared with plumbing, so no
# file content is read, no index is written and no diff configuration or
# repository program applies. The target is the remote default branch; without
# one, with a promisor remote (a missing tree would be fetched), or on any git
# error nothing is exempt. Whether the integrated result works is CI's
# question, not this review's.
integration_only() {
  local target fork base path
  local -a paths=() others=()
  [ -z "$(g config --get-regexp '^(extensions\.partialclone|remote\..*\.promisor)$' 2>/dev/null)" ] || return 1
  target=$(g symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null) || return 1
  fork=$(g merge-base "$reviewed" "$target" 2>/dev/null) || return 1
  base=$(g merge-base "$head" "$target" 2>/dev/null) || return 1
  while IFS= read -r -d '' path; do
    paths+=(":(top,literal)$path")
    others+=(":(top,literal,exclude)$path")
  done < <(g diff-tree -r -z --name-only --no-renames "$fork" "$reviewed" 2>/dev/null)
  g diff-tree -r --quiet "$fork" "$base" -- "${paths[@]}" 2>/dev/null || return 1
  g diff-tree -r --quiet "$reviewed" "$head" -- "${paths[@]}" 2>/dev/null || return 1
  g diff-tree -r --quiet "$base" "$head" -- ':(top)' "${others[@]}" 2>/dev/null
}

git_dir=$(g rev-parse --absolute-git-dir 2>/dev/null) || exit 0
head=$(g rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null) || exit 0
receipt="$git_dir/ccl-code-review/last-review.json"

walk='code-review development-completion「Before a pull request or a ready report」'
if [ ! -f "$receipt" ] || [ -L "$receipt" ]; then
  note="⚠️ 已注入 code-review 覆盖检查：这个 worktree 没有结论性评审记录。"
  message="⚠️ code-review 覆盖检查（自动）：这个 worktree 没有记录到任何结论性的 code-review 结果（检查的收据：${receipt}），就要开 / 就绪 / 合并 PR。别处保存的评审结果文件不算收据，也不说明链已处置——打开它看 status 与 next_action。若本次改了代码或可执行测试，先按 ${walk} 由你自己跑评审，不交给人工 review；确实不需要评审（纯文档且不属共享技能改动等）就在报告里写明理由。"
else
  reviewed=$(jq -r '.head // empty' "$receipt" 2>/dev/null)
  clean=$(jq -r '.worktree_clean // empty' "$receipt" 2>/dev/null)
  mode=$(jq -r '.mode // "?"' "$receipt" 2>/dev/null)
  status=$(jq -r '.status // "?"' "$receipt" 2>/dev/null)
  at=$(jq -r '.recorded_at // "?"' "$receipt" 2>/dev/null)
  printf '%s' "$reviewed" | grep -Eq '^[0-9a-f]{40,64}$' || exit 0
  covered=0
  if [ "$moves_head" = 0 ] && [ "$clean" = "true" ]; then
    if [ "$reviewed" = "$head" ]; then
      covered=1
    else
      reviewed_tree=$(g rev-parse -q --verify "${reviewed}^{tree}" 2>/dev/null || true)
      head_tree=$(g rev-parse -q --verify "${head}^{tree}" 2>/dev/null || true)
      if [ -n "$reviewed_tree" ] && [ "$reviewed_tree" = "$head_tree" ]; then covered=1; fi
      if [ "$covered" = 0 ] && integration_only; then covered=1; fi
    fi
  fi
  # Coverage is not disposition: a review that returned findings covers HEAD as
  # well as one that passed. Only a passed receipt stays quiet; a completion
  # checkpoint that disposes the findings records a passed one.
  if [ "$covered" = 1 ] && [ "$status" = "passed" ]; then
    exit 0
  fi
  short_reviewed=$(printf '%.12s' "$reviewed")
  short_head=$(printf '%.12s' "$head")
  if [ "$covered" = 1 ]; then
    note="⚠️ 已注入 code-review 覆盖检查：最后一次评审覆盖了当前 HEAD，但结论不是 passed。"
    if [ "$status" = "findings" ]; then
      situation="有发现未处置就要开 / 就绪 / 合并 PR：先逐条对照实际调用路径核验——确认的缺陷修掉（review 之后的修复由接着跑的 challenge 覆盖；challenge 之后的修复配先红后绿的测试或从源码驳回；challenge 之后又改了豁免以外内容的（会影响行为的文档也算），攒齐后再跑一次只看这些修复的增量复查；这次增量复查已经跑过的，它的发现不再送评审，只配先红后绿的测试或从源码驳回）；全部源头驳回的，按 code-review staged contract 跑 --mode complete，成功后收据记为 passed。"
    else
      situation="收据没有记录可识别的结论，无法确认这条评审链已处置：打开对应的评审结果看 status 与 next_action，必要时重跑评审。"
    fi
    message="⚠️ code-review 覆盖检查（自动）：收据 ${receipt} 记录的最后一次评审（${mode}, ${status}, ${at}）覆盖了当前 HEAD ${short_head}，但结论是 ${status}，不是 passed。
${situation}按 ${walk}，未处置的 P0/P1 不能报告就绪，也不交给人工 review。"
  elif [ "$moves_head" = 1 ]; then
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
  if [ "$covered" != 1 ]; then
    note="⚠️ 已注入 code-review 覆盖检查：当前 HEAD 没有被最后一次评审覆盖。"
    message="⚠️ code-review 覆盖检查（自动）：收据 ${receipt} 记录的最后一次结论性评审（${mode}, ${status}, ${at}）覆盖的是 ${short_reviewed}，当前 HEAD 是 ${short_head}。
${detail}
按 ${walk}（高风险改动和技能提炼线按各自的闸走，不适用下面的日常预算；没打风险标签、但属于删除/迁移数据、鉴权、计费这类高风险形态的也算高风险）：评审后改了实现代码的，若还没跑 challenge，就由你对修复后的版本跑 challenge；日常开发 review + challenge 两次用完后，不再调评审器，由你逐条处置（修复要有先红后绿的测试，或从源码驳回，或写明理由挂账）；challenge 之后又改了东西的（本提醒末尾列的可忽略情形除外，会影响行为的文档也算；不论修的是几级发现），攒齐后对这些修复跑一次增量复查（--base 指向 challenge 时的提交），那是最后一次，未处置的 P0/P1 在报告和 PR 里标为阻塞（只写理由的挂账不算处置）；challenge 之后新增的行为或范围算新改动，对该增量重走 review 和 challenge。不交给人工 review，也不能说 HEAD 已评审。只多了评审记录文件、日常开发中只改了不影响 agent 或运行行为的文档/changelog/注释（技能文本、agent 指令、prompt、runbook 不算）、或只新增/加强了测试且已跑绿时可忽略本提醒（删除、跳过或放宽断言不在此列）。"
  fi
fi

jq -nc --arg r "$message" --arg n "$note" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$r},systemMessage:$n}'
exit 0
