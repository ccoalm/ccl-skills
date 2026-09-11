#!/usr/bin/env bash
# PreToolUse advisory (Bash tool only): a process detached with nohup, setsid or
# disown is not tracked by the host.
#
# WHY: in one observed extraction round the agent started its test lane with
# `nohup ... &` (a workaround for background runs being terminated), ended the
# turn with "the lane is running", and armed no tracked waiter. The host never
# listed the job and never announced its completion, so the finished lane sat
# unread for 81 minutes until the user typed "continue"; across that session the
# user had to prompt progress about 25 times. A companion round waited with
# `pgrep 'make test'`, which matched another session's process and never exited.
# The rule existed only in a personal memory; this hook is its firing point.
#
# The predicate is only the detach WORD at a command position. Quoted strings are
# masked first so a commit message or grep pattern naming the word stays quiet.
# The hook does not parse shell (see remind-unverified-cli-flag.sh for why a
# parser does not converge), so these residuals are accepted:
#   - NON-FIRE: a detach word inside a quoted launcher payload (`sh -c 'nohup x'`).
#   - FALSE FIRE: a heredoc body that starts a line with the word.
# It fires on every matching call: there is no per-session marker to keep safe,
# and one line of context per detach is cheap.
#
# NON-BLOCKING by design; NOT a security boundary. Degrade: jq missing or any
# internal issue emits nothing and exits 0.

set -f

input=$(head -c 1048576)

command -v jq >/dev/null 2>&1 || exit 0

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

masked=$(printf '%s' "$cmd" | sed -E -e 's/"[^"]*"/QUOTED/g' -e "s/'[^']*'/QUOTED/g")

printf '%s' "$masked" \
  | grep -Eq '(^|[;&|({[:space:]])(nohup|setsid|disown)([;&|)}[:space:]]|$)' || exit 0

advisory="⏳ 后台任务跟踪提醒：\`nohup\` / \`setsid\` / \`disown\` 起的进程宿主不跟踪——任务列表里看不到，跑完也不会通知你。
如果它跑完后要驱动下一步：必须在同一次调用里挂上受跟踪的等待器（Bash \`run_in_background\` 跑一个 until 循环，只盯本会话自己写的日志结束标记；或用 Monitor），没挂等待器不许结束回合。不要按进程名（pgrep）等待，会匹配到别的会话的同名进程。
只是起一个不需要回收结果的服务，可忽略本提示。"

jq -nc --arg r "$advisory" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$r}}'
exit 0
