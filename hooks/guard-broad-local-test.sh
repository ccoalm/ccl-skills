#!/usr/bin/env bash
# PreToolUse guard: stop a local test run that selects nothing, before it runs.
#
# WHY A DENY. `testing-strategy` Local Evidence Selection already says to run the
# narrowest check that would fail, and the delivery gates repeat it. It still did
# not fire at the moment that matters: an agent writing a verification command.
# Host documentation says context from a PreToolUse hook arrives next to the tool
# result, so an advisory reaches the agent after the run. Only a deny costs less
# than the run it prevents.
#
# ONE ROUND TRIP, NOT A BAN. The rule has real exceptions, so the deny names them
# and the agent states which one applies by prefixing the command:
#   CCL_BROAD_TEST_REASON=user-request|ci-failure|repo-wide|repo-required
# The first three are the cases Local Evidence Selection allows. `repo-required`
# covers a lane the repository's contract requires locally. A repository's own
# `FULL=1` opt-in counts too, so a Makefile gate and this hook read as one rule.
# The reason is the agent's own claim and stays visible in the transcript; this is
# a decision point, not an authority boundary.
#
# PREDICATE. A runner word in command position, plus nothing that selects tests.
# Deliberately no shell parser: `remind-unverified-cli-flag.sh` records why one
# does not converge. Every unhandled spelling falls on the quiet side.
#   - Repository lanes such as `make check` and `npm run verify` never match. The
#     repository chose them as its local gate, and their names say nothing about
#     their scope.
#   - `test:unit` and other named subsets never match. Only the bare entry and
#     names carrying a slow-lane word do. Lane names belong to each repository, so
#     the list holds the small, slow-moving words seen across stacks.
#
# ACCEPTED residuals, not to be chased with more string rules:
#   - NON-FIRE: a payload inside a launcher (`sh -c 'npm test'`), an unlisted
#     prefix, or a compound command where any segment carries a selector.
#   - NON-FIRE: an option's value read as a Playwright name filter
#     (`playwright test --reporter line`). Telling them apart needs each runner's
#     option table, the vocabulary this hook does not own. pytest and node take
#     paths, so a bare word after an option does not clear them.
#   - FALSE FIRE: a target that mentions a slow-lane word but is narrow. It costs
#     one round trip and the reason prefix clears it.
#
# Degrade semantics (per hooks/AGENTS.md): jq missing or any internal issue allows
# the command. Blocking tests because this hook broke is worse than one long run.

set -f

# Every tool this hook leans on must be present; otherwise allow.
for t in jq sed awk grep tr head; do command -v "$t" >/dev/null 2>&1 || exit 0; done

input=$(head -c 1048576) || exit 0

tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)
case "$tool" in ''|Bash) ;; *) exit 0 ;; esac

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

# Same mask as the sibling hooks, after dropping escaped characters so `\"`
# cannot close a quote early: quoted prose cannot fire, single-word quoted
# values keep their content. The awk stops at the first heredoc: its body is
# text, often a commit message naming the very targets this hook matches.
# Commands after the heredoc go unchecked, on the quiet side. Last, redirection
# targets go: an output file under tests/ is not a test selection.
# Newlines become a placeholder for the mask so a quote can span lines.
masked=$(printf '%s' "$cmd" | tr '\n' '\036' | sed -E \
  -e 's/\\.//g' \
  -e $'s/"([^"[:space:];|&<>()\036]*)"/\\1/g' \
  -e $'s/\'([^\'[:space:];|&<>()\036]*)\'/\\1/g' \
  -e 's/"[^"]*"/QUOTED/g' \
  -e "s/'[^']*'/QUOTED/g" \
  | tr '\036' '\n' \
  | awk '{ print } /<</ { exit }' \
  | sed -E 's/[0-9]*(>>?|<)&?[[:space:]]*[^;&|()[:space:]]+/ /g') || exit 0

# A cheap exit for the common case, since this runs before every Bash call.
printf '%s' "$masked" | grep -Eq 'make|npm|pnpm|yarn|bun|pytest|go|playwright|node' || exit 0

sp='[[:space:]]'
tok='[^;&|()[:space:]]'
end="($sp|[;&|)]|\$)"
pos="(^|[;&|(])$sp*(([A-Za-z_][A-Za-z0-9_]*=$tok*|time|env|nice|command|exec|npx|bunx|timeout$sp+$tok+|(uv|poetry)$sp+run|python3?$sp+-m)$sp+)*"
slow="[A-Za-z0-9_:.-]*(integration|scenario|e2e|chaos|acceptance)[A-Za-z0-9_:.-]*"
entry="(tests?|test[-_:](all|full)|$slow)"
# Before the entry, a package runner takes only options and `run`; a directory
# or file option to make is not a target.
jsopt="($sp+-$tok+($sp+[^-;&|()[:space:]]$tok*)?)*"
jsrun="(npm|pnpm|yarn|bun)$jsopt($sp+(run|run-script)$jsopt)?"
scan=$(printf '%s' "$masked" | sed -E "s/(^|$sp)(-C|-f|--directory|--file|--makefile)$sp+$tok+/ /g") || exit 0

broad="$pos(make($sp+$tok+)*$sp+$entry"
broad="$broad|$jsrun$sp+(t|$entry)"
broad="$broad|pytest|playwright$sp+test"
broad="$broad|node$sp+--test($sp+$tok*\\*$tok*)*"
broad="$broad|go$sp+test($sp+$tok+)*$sp+(\\./\\.\\.\\.|\\./$tok*(integration|scenario|e2e)$tok*))$end"

printf '%s' "$scan" | grep -Eq -- "$broad" || exit 0

# Anything that names tests, reads instead of runs, or states a reason. A grep
# error (status 2) allows, like a match.
selects="(^|$sp)(-run|-bench|-k|-g|-t|--grep|--test-name-pattern|--testNamePattern|--testPathPattern|--filter|--project|--lf|--last-failed|--failed)([=[:space:]]|\$)"
selects="$selects|(^|$sp)[A-Z_]*RUN=[^[:space:]]|(^|$sp)FULL=1($sp|\$)"
selects="$selects|(^|$sp)(-h|--help|--version|--collect-only|--co|--list|-list|--dry-run|--just-print)($sp|=|\$)"
selects="$selects|(^|$sp)make$sp+-n($sp|\$)"
# Positional selections after the entry. Jest, Vitest, Bun and Playwright filter
# by any word. pytest and node take paths, so only a path-like word counts there,
# which keeps an option's value (`pytest --tb short`) from reading as one. A glob
# is not a selection.
arg="[^-;&|<>()[:space:]*][^;&|<>()[:space:]*]*$end"
patharg="[^-;&|<>()[:space:]*][^;&|<>()[:space:]*]*(/|\\.[A-Za-z]+|::)[^;&|<>()[:space:]*]*$end"
selects="$selects|$jsrun$sp+(t|$entry)$sp+(--$sp+)?$arg"
selects="$selects|playwright$sp+test($sp+-$tok+)*$sp+$arg"
selects="$selects|(pytest|node$sp+--test)($sp+$tok+)*$sp+$patharg"
selects="$selects|(^|$sp)CCL_BROAD_TEST_REASON=(user-request|ci-failure|repo-wide|repo-required)($sp|\$)"
printf '%s' "$scan" | grep -Eq -- "$selects"
[ $? -eq 1 ] || exit 0

# A named file or directory selects, unless it is a glob or a Go package tree.
# Only "the last grep found nothing, and the filter before it ran cleanly" means
# no selector. A match, a grep error at either stage, or SIGPIPE after an early
# match allows.
words=$(printf '%s' "$scan" | tr -s '[:space:]' '\n') || exit 0
printf '%s\n' "$words" | grep -Ev '[*]|\.\.\.$' \
  | grep -Eq '(\.test\.|\.spec\.|_test\.(go|py)|(^|/)test_[^/]*\.py|::|(^|/)tests?/[^/]|(^|/)__tests__/)'
st=("${PIPESTATUS[@]}")
[ "${st[2]}" -eq 1 ] && [ "${st[1]}" -le 1 ] || exit 0

reason="这条命令会跑一整组测试，已拦下，命令没有执行。全量通常由 CI 跑，本地按改动选用例：Go 用 -run，pytest 用 -k 或文件路径，Node 与前端用文件路径或 --test-name-pattern。仓库有 RUN= 这类入口时用它。
确实要跑这一组时，在命令前写明原因再执行：CCL_BROAD_TEST_REASON=user-request（用户要求）、ci-failure（排查 CI 失败）、repo-wide（改动波及全仓）、repo-required（仓库约定本地必跑）。"

jq -nc --arg r "$reason" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
