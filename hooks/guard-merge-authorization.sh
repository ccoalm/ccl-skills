#!/usr/bin/env bash
# PreToolUse guard — merge-authorization hard gate (Bash tool only).
#
# WHY: merge authorization used to be prose-only (bootstrap 硬纪律 1 /
# worktree-isolation 合并执行协议). In a continuous commit→push→MR flow an
# agent can slide past the prose and auto-merge to main. This guard is the
# mechanical control at the firing moment: it DENIES merge-executing commands
# so the agent must stop at the pending-review MR. It complements
# guard-edit-isolation.sh (which guards edits; this guards landings).
#
# DENY set (best-effort string heuristic over the Bash tool's command):
#   - `glab mr merge ...`
#   - `gh pr merge ...`
#   - `glab api ... merge_requests/<id>/merge` (platform merge API)
#   - `git push` whose refspec targets the default branch (main/master,
#     incl. `HEAD:main`, `feat:main`, `:main`), or a bare `git push`/`push
#     origin`/`push origin HEAD` while the current branch IS the default
#   - `git merge ...` executed while the current branch IS the default
#     branch (merging INTO main locally). Carve-out: `git merge --ff-only
#     origin/<default>` on the default branch stays allowed (post-merge local
#     sync is sanctioned by product-rd-workflow).
# ALLOW (must not false-positive): push to non-default branches; local
# merge/rebase between dev branches; merging main INTO a feature branch;
# glab/gh view/create/list; quoted mentions (commit messages) are masked.
#
# RELEASE VALVE (user-directive — specs:
# specs/007-merge-gate-user-directive-valve/spec.md +
# specs/008-batch-merge-grant/spec.md): the prose contract says the USER's
# explicit merge directive ("合并"/"merge") IS the authorization.
# hooks/merge-authorization-prompt.sh (UserPromptSubmit) observes the
# harness-delivered human prompt and arms a session-scoped sentinel; at the
# would-deny moment this guard consumes it and ALLOWS platform merge shapes
# only (glab mr merge / gh pr merge / merge API / merge GraphQL). Two grant
# kinds:
#   `armed` / `armed <id>`  — ONE-SHOT (≤60 min), optionally bound to an
#                             MR/PR number ("merge !546").
#   `armed batch <N>`       — COUNTED batch (≤240 min from arming), armed by
#                             "批量合并 <N>": each platform merge consumes ONE
#                             unit; unbound by design (dependent-repo MRs do
#                             not exist yet when a dependency chain starts) —
#                             the duty to merge only the presented release
#                             plan stays prose (worktree-isolation 合并执行
#                             协议). Any new user prompt revokes the rest.
# Direct default-branch advancement (git push main, git merge on main, …)
# is NEVER released by the valve — the sanctioned landing path is the MR.
# The sentinel is legitimately written only by the prompt hook; an agent
# forging it via Bash is deliberate circumvention, same declared
# out-of-scope class as the obfuscation exclusions below.
#
# Degrade semantics (per hooks/AGENTS.md):
#   - jq or git missing → visible warning, NOT enforced (do not brick Bash).
#   - Internal parse errors → fail-open (allow), same as the edit guard.
#   - The deny itself is fail-closed for the matched command shapes: an agent
#     cannot self-clear this gate. Release paths: the user's explicit merge
#     directive (valve above) or a human disabling the hook via /hooks.
#   - Valve failure modes (no session_id, unreadable/stale/foreign sentinel,
#     malformed grant/count, session lock unavailable) fall back to deny —
#     fail-closed.
# Enforcement is Claude-Code-hard only; hosts that ignore PreToolUse deny
# (e.g. Codex) get advisory coverage via bootstrap + worktree-isolation.
# NOT a security boundary: obfuscation (eval, subshell, interpreter -e,
# xargs) is out of scope — this catches the ROUTINE direct spellings.
# Also out of scope by the same declaration: branch names reaching push/merge
# through variable expansion or command substitution (`git push origin
# $BRANCH`, `$(echo main)`) — the guard cannot evaluate shell expansion and
# refusing every `$` token would over-block routine scripted feature pushes.
# `cd`/`git checkout`/`git switch` in EARLIER segments of the same command
# ARE tracked (they are routine spellings, not obfuscation).
# Redirections are stripped so routine plumbing (`… 2>&1 | tail`, `… >log`,
# `… main>/log` attached, `… origin main 2>&1` trailing) does not misparse (see
# the token-strip block below). Declared best-effort gaps in the SAME
# non-adversarial spirit — a cooperating developer never types these, each
# pinned by an allow-probe so a future tightening is a visible upgrade, and all
# PRE-EXISTING (the pre-redirection-fix guard allowed them too):
#   1. An `&`-bearing fd-dup redirect (`2>&1`, `1>&2`, `&>`) placed BEFORE the
#      complete refspec: the `tr … '&' …` segment split (unchanged by this fix)
#      tears the refspec off the command — `2>&1 git push main`,
#      `git push 2>&1 origin main`. (`git push origin main 2>&1`, redirect AFTER
#      the full refspec, is handled correctly.)
#   2. A digit-led redirect used as a command PREFIX that hides the command word
#      (`10>/log git push main`, `2>/dev/null git push main`).
#   3. Heredoc bodies (`<<EOF`… whose data lines are walked as commands).
# Raw HTTP merge REST coverage reuses the SAME normalized segment and release
# valve as glab/gh; it is not a second shell tokenizer or grant state machine.
# Routine direct `curl` PUT spellings (`-X`/`--request`, upload-file implicit
# PUT) and `wget --method PUT` are classified for exact GitLab v4 and GitHub
# REST merge paths on any non-empty HTTP(S) host. Query/fragment are removed;
# path case is preserved and percent escapes are not decoded. Header, body,
# output, referer, DoH, proxy, and user-agent values are not URL operands.
# An unrecognized option adjacent to a merge-shaped value is ambiguous and
# cannot consume a grant. Repeated curl request options follow curl's
# last-option-wins rule; conflicting wget methods, curl `--next` with a changed
# method, and multiple merge URLs deny without consuming a grant.
# Deliberate command construction remains out of scope with the general
# non-security-boundary declaration above: dynamic/eval/interpreter/xargs URLs,
# external curl/wget config, and encoded path or command obfuscation. The raw
# HTTP allow/deny probes in test_guard_merge_authorization.sh pin each boundary.

# Tokenization below uses unquoted word-splitting on purpose; disable
# pathname expansion so a `*` in the command cannot glob the filesystem.
set -f

input=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  printf '{"systemMessage":"⚠️ merge-authorization guard degraded: jq not found; merge gate NOT enforced this session"}\n'
  exit 0
fi
if ! command -v git >/dev/null 2>&1; then
  printf '{"systemMessage":"⚠️ merge-authorization guard degraded: git not found; merge gate NOT enforced this session"}\n'
  exit 0
fi

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] && [ -d "$cwd" ] || cwd=$(pwd)

# Release-valve sentinel (armed by hooks/merge-authorization-prompt.sh on an
# explicit user merge directive; consumed below on platform merge shapes —
# one-shot grants whole, batch grants one unit at a time). KEEP IN SYNC with
# that script's path derivation and lock protocol.
sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
tpath=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
case "$sid" in */*|*..*) sid="" ;; esac   # session_id is a path component
sentinel=""; lock_dir=""
if [ -n "$sid" ]; then
  sentinel="${TMPDIR:-/tmp}/ccl-skills-merge-auth-$(id -u)/$sid"
  lock_dir="${TMPDIR:-/tmp}/ccl-skills-merge-auth-$(id -u)/$sid.lock"
fi

# Per-session critical-section lock shared with the prompt hook (review P1):
# the guard's parse→consume→batch-re-arm sequence must not interleave with
# the prompt hook's revoke/arm, or a user's kill-switch message could be
# lost between the atomic consume (mv) and the batch re-create. Stale locks
# (≥1 min — critical sections are milliseconds) are broken.
acquire_lock() {
  i=0
  while ! mkdir "$lock_dir" 2>/dev/null; do
    i=$((i+1))
    if [ "$i" -ge 20 ]; then
      if [ -z "$(find "$lock_dir" -mmin -1 2>/dev/null)" ]; then
        rm -rf "$lock_dir" 2>/dev/null
        mkdir "$lock_dir" 2>/dev/null && return 0
      fi
      return 1
    fi
    sleep 0.05
  done
  return 0
}

deny() {
  jq -nc --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

DENY_TEXT_MR="合并授权闸：该命令会合并 MR/PR。合并需要用户明确下达合并指令——用户在下一条消息中单独回复\"合并\"或\"merge\"即可一次性放行本类命令；链式/多仓发布可单独回复\"批量合并 <N>\"（如：批量合并 30）一次授权 N 个平台合并（武装后 4 小时内有效，用户发送任何新消息即取消剩余额度）。均由 UserPromptSubmit 哨兵机器核验，agent 不能代替用户回复；在此之前把 MR 链接、分支、head SHA、CI 状态（批量场景为发布计划）展示给用户并停在待审状态。"
DENY_TEXT_GIT="合并授权闸：该命令会直接推进 main/默认分支（push/merge/pull 到默认分支）。该形态不适用用户回复\"合并\"的放行阀——落地必须走 MR 流程（push 功能分支 → MR → 用户授权后平台合并）；人工确需直推可经 /hooks 关闭本闸。"
# Same deny, accurate reason. This闸 reads the command TEXT, so a `-C`/--git-dir/
# --work-tree target written as a shell variable cannot be expanded here; the branch
# context then falls back to the cwd (fail-closed, because that unknown path may be
# the default checkout). Tell the caller how to make it decidable instead of letting
# them read it as "the gate is broken" — merging main INTO a feature worktree is
# explicitly allowed, it just has to be legible.
DENY_TEXT_GIT_UNRESOLVED="合并授权闸：命令用 -C/--git-dir/--work-tree 指向了另一个仓库，但目标路径写成了 shell 变量，本闸读的是命令文本、展开不了，因此无法确认它不是默认分支检出——按闭式失败处理。若这是「把 main 合进功能分支/worktree」（允许的形态），把目标写成**字面绝对路径**（git -C /abs/path/to/worktree merge origin/main），或直接 cd 进该 worktree 再执行；若确实要推进 main/默认分支，仍按 MR 流程走。"
DENY_TEXT_AUTO="合并授权闸：该命令会开启 auto-merge / merge-when-pipeline-succeeds / 排队合并，或用 --admin 绕过平台检查。即便用户已授权合并，执行也必须一次性立即合并且不绕过检查（如 glab mr merge <iid> --auto-merge=false --yes），不得转 auto-merge/排队/--admin（见 worktree-isolation 合并执行协议）；该形态不适用放行阀。"
DENY_TEXT_SPELL="合并授权闸：授权有效但命令拼写不满足一次性立即合并要求——glab 需显式 --auto-merge=false（pipeline 运行中裸 merge 会默认转 auto-merge），gh 需显式 --merge/--squash/--rebase 策略，merge REST API 需显式 -X PUT。授权未消费，按上述拼写改写命令直接重试即可（无需用户重新授权）。"
DENY_TEXT_TARGET="合并授权闸：用户授权指向了特定 MR/PR 编号，但该命令的合并对象与之不符或无法识别。授权未消费——请显式点名该编号（如 glab mr merge <授权编号> --auto-merge=false --yes）后重试；确需合并其他 MR 请让用户重新授权。"
DENY_TEXT_MULTI="合并授权闸：同一条命令内检测到多个平台合并调用。每条命令只放行一个合并——把命令拆开逐条执行（单个授权下每个合并由用户分别授权；批量授权下每条命令消费 1 个额度，无需用户再次回复）。"
DENY_TEXT_AMBIGUOUS="合并授权闸：检测到原始 HTTP 客户端、变更 method 的选项和 merge endpoint，但 method、transfer 边界、目标或动作数无法可靠关联。授权未消费——请改写成单个 curl/wget、单个明确 PUT method 和单个 merge URL 后重试。"

# Does any single quoted span of the raw command look like a GraphQL merge
# MUTATION? Per-span check (must contain `mutation` AND a merge-mutation
# name) so a compound command that merely MENTIONS the identifier in an
# unrelated quoted value (commit message, note body) cannot trip it.
graphql_merge_mutation() { # $1 = ERE of mutation names
  printf '%s\n' "$cmd" | grep -Eo '"[^"]*"|'"'[^']*'" | grep -E 'mutation' | grep -Eq "$1"
}

# Print the numeric MR/PR id when a raw HTTP URL is exactly one supported
# platform merge endpoint. The detector deliberately accepts any non-empty
# host (internal and public installations share authorization semantics),
# strips query/fragment without percent-decoding, and rejects path prefixes.
http_merge_id() { # $1 = normalized URL operand
  hurl="$1"
  case "$hurl" in
    [Hh][Tt][Tt][Pp]://*|[Hh][Tt][Tt][Pp][Ss]://*) ;;
    *) return 1 ;;
  esac
  authority_path="${hurl#*://}"
  authority="${authority_path%%/*}"
  [ -n "$authority" ] && [ "$authority_path" != "$authority" ] || return 1
  hostport="${authority##*@}"
  case "$hostport" in
    \[*\]*) host="${hostport#\[}"; host="${host%%\]*}" ;;
    *) host="${hostport%%:*}" ;;
  esac
  [ -n "$host" ] || return 1
  hpath="/${authority_path#*/}"
  hpath="${hpath%%\#*}"
  hpath="${hpath%%\?*}"
  mid=$(printf '%s\n' "$hpath" | sed -nE 's#^/api/v4/projects/[^/]+/merge_requests/([1-9][0-9]*)/merge/?$#\1#p')
  if [ -z "$mid" ]; then
    mid=$(printf '%s\n' "$hpath" | sed -nE 's#^/api/v3/repos/[^/]+/[^/]+/pulls/([1-9][0-9]*)/merge/?$#\1#p')
  fi
  if [ -z "$mid" ]; then
    mid=$(printf '%s\n' "$hpath" | sed -nE 's#^/repos/[^/]+/[^/]+/pulls/([1-9][0-9]*)/merge/?$#\1#p')
  fi
  [ -n "$mid" ] || return 1
  printf '%s\n' "$mid"
}

# Default branch of the repo at cwd; empty when cwd is not a git repo.
# origin/HEAD is the only per-repo authoritative signal, and it is frequently
# unset on cloned/CI repos (needs an explicit `git remote set-head`).
# Deliberately NO init.defaultBranch fallback: that is a new-repo template
# knob (often set globally on the host) and does not describe THIS repo's
# default — using it would silently mask the unresolved state. When the repo
# has an origin remote but origin/HEAD is unresolvable, the gate narrows to
# main|master and that degradation is made VISIBLE (warning below), not
# silent, or a develop/trunk-default repo bypasses the gate unnoticed.
default_branch=""
origin_exists=0
if git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$cwd" config --get remote.origin.url >/dev/null 2>&1 && origin_exists=1
  default_branch=$(git -C "$cwd" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
fi
current_branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)
# Hook-cwd baselines; git segments reset from these (a `git -C` overrides).
base_default_branch="$default_branch"
base_current_branch="$current_branch"
base_origin_exists="$origin_exists"
origin_flag="$origin_exists"

# Is this token the default-branch name? When the repo's default IS resolved
# (origin/HEAD), gate on that value alone — hardcoding main|master on top
# would over-block an ordinary non-default branch literally named `main`
# (common during trunk migrations). The main|master union is only the
# fallback for the unresolved case (which warns visibly below).
is_default_name() {
  if [ -n "$default_branch" ]; then
    [ "$1" = "$default_branch" ]
  elif [ "$origin_flag" = 1 ]; then
    # Origin exists but its default is unresolved: gate the COMMON
    # default-branch names, not just main|master — dev/develop/trunk are
    # integration branches in the wild and essentially never casual feature
    # branches, so the over-block risk is negligible next to the bypass
    # risk (and the visible warning below explains the narrowing).
    case "$1" in
      main|master|dev|develop|trunk) return 0 ;;
      *) return 1 ;;
    esac
  else
    # No origin remote (local-only repo): no remote MR flow to protect —
    # keep the narrow main|master set so a local branch named dev/trunk
    # is not blocked without any warning surface.
    case "$1" in
      main|master) return 0 ;;
      *) return 1 ;;
    esac
  fi
}

# Quote handling, two-step: (1) quoted spans containing whitespace or shell
# metacharacters (prose: commit messages, MR titles) become QUOTED so
# `git commit -m "revert glab mr merge"` cannot false-positive; (2) remaining
# quotes around single words are stripped so `git push origin "main"` still
# resolves to the branch name instead of hiding behind the mask.
# Heredoc bodies stay a known best-effort gap.
# Stage 0 folds a backslash-escaped redirection metachar (`\<`, `\>`, `\&`) to a
# neutral letter: the shell passes it as a LITERAL word char, not syntax, so a
# refspec like `feature\>:main` (→ `feature>:main`, which targets `main`) or a
# bare `feature\> main` must not be read as a redirection later. Scoped to only
# `<>&` so an escaped command word (`\git`, a routine alias-bypass spelling)
# keeps its backslash for the `${1#\\}` normalization below and is unaffected.
# Order matters: fold escapes; strip query/fragment from a quoted single-word
# HTTP URL before the segment splitter can mistake its literal `&` for shell
# syntax; then unwrap single-word quotes (left-to-right pair consumption); then
# mask remaining metachar spans. A "span-with-whitespace" pattern run first
# would cross-pair a closing quote with the next opening one.
masked=$(printf '%s' "$cmd" | sed -E \
  -e 's/\\([<>&])/X/g' \
  -e 's/>\|/>/g' \
  -e 's#"([Hh][Tt][Tt][Pp][Ss]?://[^"[:space:]?#]*)([?#][^"]*)"#"\1"#g' \
  -e "s#'([Hh][Tt][Tt][Pp][Ss]?://[^'[:space:]?#]*)([?#][^']*)'#'\\1'#g" \
  -e 's/"([^"[:space:];|&<>()]*)"/\1/g' \
  -e "s/'([^'[:space:];|&<>()]*)'/\\1/g" \
  -e 's/"[^"]*"/QUOTED/g' \
  -e "s/'[^']*'/QUOTED/g")
# `>|` (clobber-override) is redirection-equivalent to `>`, but its `|` would be
# torn by the `tr ';|&(){}'` segment split below and strand the command word in
# a fragment (e.g. `git merge>|/log --ff-only origin/main` → the sync's flags
# split off, leaving a bare `git merge`). Fold it to `>` before the split. The
# `&`-bearing fd-dup operators (`2>&1`, `&>`) have the same tearing property but
# stay a declared best-effort gap — see the header — because normalizing them is
# ambiguous (the digit/`&` also carry fd meaning), whereas `>|`→`>` is exact.

# Walk simple-command segments (;, |, &&, ||, &, newlines, parens).
# Cross-segment state: `cd` moves the effective cwd for LATER segments
# (so `cd ../main-checkout && git push` is judged in the target repo), and
# `git checkout <branch>` / `git switch <branch>` moves the effective
# current branch (so `git checkout main && git merge feature` denies).
# The state lives inside the pipeline subshell — sequential by design.
eff_cwd="$cwd"
prev_cwd=""     # last dir before the most recent cd/pushd (for `cd -`)
eff_branch=""   # empty = ask the repo at eff_cwd
# Verdicts are TYPED: DENY_GIT (direct default-branch advancement — never
# released by the valve; emitting it breaks the walk, nothing can weaken it)
# vs DENY_MR (platform merge — valve-eligible; emitting it does NOT break,
# so a later DENY_GIT segment in the same compound command still registers).
# Collected via a temp file, not $(...): macOS bash 3.2 cannot parse case
# patterns inside command substitution. mktemp failure → fail-open (allow)
# with a VISIBLE degrade warning, same class as the jq/git degrades above —
# never a silent unenforced gate.
vfile=$(mktemp "${TMPDIR:-/tmp}/merge-guard-verdict.XXXXXX" 2>/dev/null) || {
  printf '{"systemMessage":"⚠️ merge-authorization guard degraded: mktemp failed; merge gate NOT enforced for this command"}\n'
  exit 0
}
printf '%s\n' "$masked" | tr ';|&(){}' '\n' | while IFS= read -r seg; do
  # Strip leading whitespace and env VAR=x / transparent wrapper prefixes.
  # Wrappers with their OWN arguments are walked properly: `timeout 30 git`,
  # `nice -n 10 git`, `sudo -u bob git`, `env -i FOO=1 git` all land on the
  # real command word instead of the wrapper's operand.
  set -- $seg
  # Reduce each token to the word the shell would hand the command, stripping
  # REDIRECTIONS so they are not miscounted as git refspec args — the real
  # defect was `git pull --ff-only origin main 2>&1 | tail -1` denying: the `&`
  # split left `… origin main 2>` and `2>` counted as a third (non-default)
  # refspec. Quote-masking already turned any quoted `>`/`<` into QUOTED, so a
  # surviving operator here is real unquoted shell syntax. For each token with
  # a `<`/`>`, split at the FIRST operator; `pre` is the word before it:
  #   • pre empty (operator-led `>file`, `<in`, bare `>`): a pure redirection →
  #     drop it; a bare operator also eats the following target word (`> file`).
  #   • pre has a non-digit (`main>/log`, `main2>/log`, `HEAD:main>/log`): a
  #     refspec/arg with an attached redirect → keep `pre`, drop the redirect.
  #     This is why `main>/log` still denies (keeps `main`) while `main2>/log`
  #     is allowed (keeps `main2`) — the shell lexes them exactly so.
  #   • pre all-digits (`2>`, `10>/dev/null`): a file descriptor ONLY after the
  #     git/glab/gh tool word (real plumbing like `2>&1`) → drop it; BEFORE the
  #     tool word an all-digit token is indistinguishable from a wrapper's
  #     numeric operand whose quotes were normalized away (`timeout '5'>/dev/null
  #     git …` → `timeout 5>/dev/null git …`), so keep it whole for the
  #     wrapper/command-word walk, or the wrapper would swallow `git`.
  # KNOWN best-effort gaps (footgun reminder, not an adversarial boundary — see
  # the header; each pinned by an allow-probe so a future tightening is visible):
  # a DIGIT-led redirection used as a command PREFIX that hides the command word
  # (`2>&1 git push…`, `10>/tmp/log git push…`), and heredoc bodies (`<<EOF`…).
  rfiltered=""; rskip=0; seen_tool=0
  for rtok in "$@"; do
    if [ "$rskip" = 1 ]; then rskip=0; continue; fi
    case "$rtok" in
      *[\<\>]*)
        pre="${rtok%%[<>]*}"; rest="${rtok#"$pre"}"
        case "$pre" in
          "")
            # operator-led: bare operator eats its target word; else drop whole
            case "$rtok" in
              \>|\>\>|\<|\<\<|\<\<\<|\<\>|\>\|) rskip=1; continue ;;
              *) continue ;;
            esac ;;
          *[!0-9]*)
            # word + attached redirect → keep the word, drop the redirect.
            # Deliberately NO rskip on a bare trailing operator (`main> file`):
            # the space-separated form already denies on the pre-existing path
            # (its target becomes a stray arg), so skipping the rskip loses
            # nothing and stays fail-closed.
            rfiltered="$rfiltered $pre"
            # the kept word may itself BE the tool (`git>/tmp/out pull …`) — mark
            # it before the `continue`, or a later `2>` stays unstripped and the
            # pull parser miscounts it (false-deny of a valid sync)
            bn="${pre##*/}"; bn="${bn#\\}"
            case "$bn" in git|glab|gh|curl|wget) seen_tool=1 ;; esac
            continue ;;
          *)
            # all-digit prefix: real fd only after the tool word
            if [ "$seen_tool" = 1 ]; then
              case "$rest" in
                \>|\>\>|\<|\<\>|\>\|) rskip=1; continue ;;
                *) continue ;;
              esac
            fi
            # before the tool word → wrapper operand; keep whole (fall through)
            ;;
        esac
        ;;
    esac
    bn="${rtok##*/}"; bn="${bn#\\}"
    case "$bn" in git|glab|gh|curl|wget) seen_tool=1 ;; esac
    rfiltered="$rfiltered $rtok"
  done
  set -- $rfiltered
  [ $# -eq 0 ] && continue
  while [ $# -gt 0 ]; do
    case "$1" in
      *=*) shift ;;
      # Transparent prefixes: they execute the following word as the command.
      # `exec`/`builtin` are POSIX special BUILTINS, not reserved words, so the
      # reserved-word completeness argument below does not reach them — an
      # earlier version of this fix claimed the class was closed while
      # `exec git push origin main` still ALLOWed. `eval` stays out of scope by
      # the header declaration (it takes a string to re-parse, not a command).
      command|nohup|time|exec|builtin) shift ;;
      # Leading shell keywords left by tokenizing on ;|&(){} — a loop/if body
      # `for id in …; do glab mr merge …; done` splits to a `do glab …`
      # segment (challenge R2 P0). Strip them so the routine loop spelling is
      # still detected. (Dynamic merge COUNT under a loop stays a declared
      # best-effort gap — see the not-a-security-boundary header.)
      #
      # This list is the COMPLETE set, derived from the POSIX reserved-word list
      # (`! { } case do done elif else esac fi for if in then until while`) by
      # asking which members can sit immediately before a simple command in a
      # segment this tokenizer produces — NOT another word added because someone
      # found one more bypass. `for`/`in`/`case` are followed by a word list, not
      # a command; `fi`/`done`/`esac` terminate; `{`/`}` are already tokenizer
      # delimiters. That leaves exactly these eight.
      #
      # An earlier version stripped only `do|then|else|elif`, so every one of
      # these was a silent bypass of a gate whose whole job is to stop an
      # unauthorized merge — `if <merge>; then …; fi` and `! <push to main>` are
      # ordinary scripted spellings, not the eval/subshell obfuscation the header
      # declares out of scope:
      #   if glab mr merge 546 --yes; then echo ok; fi   -> was ALLOW, now DENY
      #   while glab mr merge 546 --yes; do echo x; done -> was ALLOW, now DENY
      #   ! git push origin main                         -> was ALLOW, now DENY
      do|then|else|elif|if|while|until|'!') shift ;;
      env)
        shift
        while [ $# -gt 0 ]; do
          case "$1" in
            -u|--unset) if [ $# -ge 2 ]; then shift 2; else shift; fi ;;
            -*) shift ;;
            *=*) shift ;;
            *) break ;;
          esac
        done
        ;;
      sudo|doas)
        shift
        while [ $# -gt 0 ]; do
          case "$1" in
            -u|-g|-h|-p) if [ $# -ge 2 ]; then shift 2; else shift; fi ;;
            -*) shift ;;
            *) break ;;
          esac
        done
        ;;
      nice)
        shift
        while [ $# -gt 0 ]; do
          case "$1" in
            -n|--adjustment) if [ $# -ge 2 ]; then shift 2; else shift; fi ;;
            -*) shift ;;
            *) break ;;
          esac
        done
        ;;
      timeout)
        shift
        while [ $# -gt 0 ]; do
          case "$1" in
            -k|--kill-after|-s|--signal) if [ $# -ge 2 ]; then shift 2; else shift; fi ;;
            -*) shift ;;
            *) break ;;
          esac
        done
        [ $# -gt 0 ] && shift   # the DURATION operand
        ;;
      *) break ;;
    esac
  done
  [ $# -eq 0 ] && continue

  # Normalize the command word: `\git` and `/usr/bin/git` are routine
  # spellings of the same tool, not obfuscation — match on the basename.
  cmdword="${1#\\}"; cmdword="${cmdword##*/}"

  case "$cmdword" in
    cd|pushd)
      t="${2:-}"
      [ -z "$t" ] && { [ "$cmdword" = "cd" ] && { prev_cwd="$eff_cwd"; eff_cwd="$HOME"; }; eff_branch=""; continue; }
      case "$t" in
        /*) prev_cwd="$eff_cwd"; eff_cwd="$t" ;;
        -)
          # cd - : swap with the tracked previous dir (routine one-hop use);
          # without one tracked, keep the current context.
          if [ -n "$prev_cwd" ]; then
            t="$eff_cwd"; eff_cwd="$prev_cwd"; prev_cwd="$t"
          fi
          ;;
        *) prev_cwd="$eff_cwd"; eff_cwd="$eff_cwd/$t" ;;
      esac
      eff_branch=""
      continue
      ;;
    popd)
      # Single-level pushd/popd is the routine pattern; restore hook cwd.
      prev_cwd="$eff_cwd"
      eff_cwd="$cwd"
      eff_branch=""
      continue
      ;;
    curl|wget)
      tool="$cmdword"; shift
      explicit_method=""; method_conflict=0; upload_seen=0; next_seen=0
      operand_ambiguous=0; merge_count=0; first_mid=""
      while [ $# -gt 0 ]; do
        case "$1" in
          -X|--request)
            if [ "$tool" != curl ]; then
              if [ $# -ge 2 ]; then shift 2; else shift; fi
            elif [ $# -ge 2 ]; then
              next_method=$(printf '%s' "$2" | tr '[:lower:]' '[:upper:]')
              explicit_method="$next_method"; shift 2
            else method_conflict=1; shift
            fi
            ;;
          --method)
            if [ "$tool" != wget ]; then
              if [ $# -ge 2 ]; then shift 2; else shift; fi
            elif [ $# -ge 2 ]; then
              next_method=$(printf '%s' "$2" | tr '[:lower:]' '[:upper:]')
              if [ -n "$explicit_method" ] && [ "$explicit_method" != "$next_method" ]; then method_conflict=1; fi
              explicit_method="$next_method"; shift 2
            else method_conflict=1; shift
            fi
            ;;
          -X?*)
            if [ "$tool" = curl ]; then
              next_method=$(printf '%s' "${1#-X}" | tr '[:lower:]' '[:upper:]')
              explicit_method="$next_method"
            fi
            shift
            ;;
          --request=*)
            if [ "$tool" = curl ]; then
              next_method=$(printf '%s' "${1#*=}" | tr '[:lower:]' '[:upper:]')
              explicit_method="$next_method"
            fi
            shift
            ;;
          --method=*)
            if [ "$tool" = wget ]; then
              next_method=$(printf '%s' "${1#*=}" | tr '[:lower:]' '[:upper:]')
              if [ -n "$explicit_method" ] && [ "$explicit_method" != "$next_method" ]; then method_conflict=1; fi
              explicit_method="$next_method"
            fi
            shift
            ;;
          -T|--upload-file)
            [ "$tool" = curl ] && upload_seen=1
            if [ $# -ge 2 ]; then shift 2; else shift; fi
            ;;
          -T?*) [ "$tool" = curl ] && upload_seen=1; shift ;;
          --upload-file=*) [ "$tool" = curl ] && upload_seen=1; shift ;;
          -O|--output-document)
            if [ "$tool" = wget ] && [ $# -ge 2 ]; then shift 2; else shift; fi
            ;;
          --output-document=*) shift ;;
          -s|--silent)
            if [ "$tool" = curl ]; then
              shift
            else
              if [ $# -ge 2 ] && http_merge_id "$2" >/dev/null; then operand_ambiguous=1; fi
              shift
            fi
            ;;
          -x)
            if [ "$tool" = curl ] && [ $# -ge 2 ]; then shift 2; else shift; fi
            ;;
          --doh-url|--proxy|--preproxy)
            if [ "$tool" = curl ]; then
              if [ $# -ge 2 ]; then shift 2; else shift; fi
            else
              if [ $# -ge 2 ] && http_merge_id "$2" >/dev/null; then operand_ambiguous=1; fi
              shift
            fi
            ;;
          -x?*) shift ;;
          --doh-url=*|--proxy=*|--preproxy=*)
            if [ "$tool" = curl ]; then
              shift
            else
              if http_merge_id "${1#*=}" >/dev/null; then operand_ambiguous=1; fi
              shift
            fi
            ;;
          -A|--user-agent)
            if [ $# -ge 2 ]; then shift 2; else shift; fi
            ;;
          -A?*|--user-agent=*) shift ;;
          -H|-d)
            if [ "$tool" = curl ] && [ $# -ge 2 ]; then shift 2; else shift; fi
            ;;
          --header|--data|--data-ascii|--data-binary|--data-raw|--data-urlencode|--json|-o|--output|-e|--referer|--post-data|--post-file|--body-data|--body-file)
            if [ $# -ge 2 ]; then shift 2; else shift; fi
            ;;
          -H?*|-d?*|-o?*|-e?*|--header=*|--data=*|--data-ascii=*|--data-binary=*|--data-raw=*|--data-urlencode=*|--json=*|--output=*|--referer=*|--post-data=*|--post-file=*|--body-data=*|--body-file=*) shift ;;
          --next) [ "$tool" = curl ] && next_seen=1; shift ;;
          --url)
            if [ "$tool" = curl ] && [ $# -ge 2 ]; then
              if candidate_mid=$(http_merge_id "$2"); then
                merge_count=$((merge_count+1)); [ -n "$first_mid" ] || first_mid="$candidate_mid"
              fi
            fi
            if [ $# -ge 2 ]; then shift 2; else shift; fi
            ;;
          --url=*)
            if [ "$tool" = curl ] && candidate_mid=$(http_merge_id "${1#--url=}"); then
              merge_count=$((merge_count+1)); [ -n "$first_mid" ] || first_mid="$candidate_mid"
            fi
            shift
            ;;
          [Hh][Tt][Tt][Pp]://*|[Hh][Tt][Tt][Pp][Ss]://*)
            if candidate_mid=$(http_merge_id "$1"); then
              merge_count=$((merge_count+1)); [ -n "$first_mid" ] || first_mid="$candidate_mid"
            fi
            shift
            ;;
          -*)
            candidate_value=""
            case "$1" in
              *=*) candidate_value="${1#*=}" ;;
              *) [ $# -ge 2 ] && candidate_value="$2" ;;
            esac
            if [ -n "$candidate_value" ] && http_merge_id "$candidate_value" >/dev/null; then
              operand_ambiguous=1
            fi
            shift
            ;;
          *) shift ;;
        esac
      done
      method="$explicit_method"
      [ -n "$method" ] || { [ "$upload_seen" = 1 ] && method=PUT || method=GET; }
      if [ "$operand_ambiguous" = 1 ] && { [ "$method" = PUT ] || [ "$method_conflict" = 1 ]; }; then
        echo DENY_HTTP_AMBIGUOUS
      elif [ "$merge_count" -gt 0 ]; then
        if [ "$method_conflict" = 1 ] || { [ "$next_seen" = 1 ] && { [ -n "$explicit_method" ] || [ "$upload_seen" = 1 ]; }; }; then
          echo DENY_HTTP_AMBIGUOUS
        else
          if [ "$method" = PUT ]; then
            echo "DENY_MR $first_mid SPELLOK"
            [ "$merge_count" -gt 1 ] && echo "DENY_MR $first_mid SPELLOK"
          fi
        fi
      fi
      ;;
    glab|gh)
      tool="$cmdword"; shift
      # Skip global flags before the subcommand (`gh -R owner/repo pr merge`);
      # value-taking globals also skip their value. `shift 2` is guarded so a
      # trailing value-flag cannot leave $@ unchanged and spin the loop.
      # retarget: an explicit -R/--repo/--hostname redirects the platform
      # call away from the cwd repo — a number-bound grant must not release
      # it (the bound number is only meaningful in the discussed repo).
      retarget=0
      while [ $# -gt 0 ]; do
        case "$1" in
          -R|--repo|--host|--hostname) retarget=1; if [ $# -ge 2 ]; then shift 2; else shift; fi ;;
          -R=*|--repo=*|--host=*|--hostname=*) retarget=1; shift ;;
          -*) shift ;;
          *) break ;;
        esac
      done
      # Each merge-executing SEGMENT emits exactly ONE verdict (hit=1 gate
      # below): the valve's exactly-one-merge check counts DENY_MR lines,
      # so double-emitting for one call (REST regex + GraphQL span check)
      # would over-deny a legitimate single merge. Auto-merge/queued
      # spellings become DENY_AUTO — NEVER released by the valve: even an
      # authorized landing must merge immediately, not schedule (worktree-
      # isolation 合并执行协议).
      # hit: this segment executes a platform merge. auto: it schedules/
      # queues or bypasses checks (never released). spell: SPELLOK when the
      # spelling is guaranteed-immediate (glab explicit --auto-merge=false;
      # gh explicit strategy; REST/GraphQL calls are immediate by API
      # semantics). mid: the merge target id when statically extractable
      # ("?" otherwise) — matched against a number-bound grant below.
      hit=0; auto=0; spell=SPELLBAD; mid="?"; multi_seg=0
      if [ "$tool" = "glab" ]; then
        # `accept` is glab's documented alias of `mr merge` (same help text).
        if [ "${1:-}" = "mr" ] && { [ "${2:-}" = "merge" ] || [ "${2:-}" = "accept" ]; }; then
          hit=1; shift 2
          while [ $# -gt 0 ]; do
            case "$1" in
              --auto-merge=false) spell=SPELLOK ;;
              --auto-merge|--auto-merge=*|--when-pipeline-succeeds*) auto=1 ;;
              -R|--repo|--host|--hostname) retarget=1; [ $# -ge 2 ] && shift ;;
              -R=*|--repo=*|--host=*|--hostname=*) retarget=1 ;;
              # value-taking flags: consume the value so it is not mistaken
              # for the MR id positional (`glab mr merge --sha abc 546`).
              --sha|-m|--message|--squash-message) [ $# -ge 2 ] && shift ;;
              -*) : ;;
              *)
                if [ "$mid" = "?" ] && [ -z "${id_seen:-}" ]; then
                  id_seen=1
                  t="${1#!}"; t="${t##*#}"
                  case "$t" in
                    *[!0-9]*)
                      mid=$(printf '%s' "$t" | sed -n 's|.*/merge_requests/\([0-9][0-9]*\)$|\1|p')
                      [ -n "$mid" ] || mid="?"
                      ;;
                    "") ;;
                    *) mid="$t" ;;
                  esac
                fi
                ;;
            esac
            shift
          done
          unset id_seen
        elif [ "${1:-}" = "api" ]; then
          # Scan the MASKED segment: single-word quoted API paths survive the
          # mask (quotes stripped), while prose values with whitespace (e.g.
          # -f body="see merge_requests/9/merge") are already QUOTED and
          # cannot false-positive here.
          # Left boundary: path/URL starts ('/', '=', space, quote, start) —
          # not a word char or '-', so `note=see-merge_requests/9/merge`
          # (a mere reference inside a value) cannot trip it.
          if printf '%s' "$seg" | grep -Eq '(^|[^a-zA-Z0-9_.-])merge_requests/[^ /]+/merge([^a-zA-Z_-]|$)'; then
            hit=1
            # REST release needs the explicit mutating method: glab/gh api
            # default to GET, and a GET to the merge endpoint must not burn
            # the one-shot grant (final-review P2).
            printf '%s' "$seg" | grep -Eiq '(-X|--method)[= ]*(PUT|POST)' && spell=SPELLOK
            mid=$(printf '%s' "$seg" | sed -n 's|.*[^a-zA-Z0-9_.-]merge_requests/\([0-9][0-9]*\)/merge.*|\1|p')
            [ -n "$mid" ] || mid="?"
          fi
          # GraphQL merge mutation: quoted query bodies are prose-masked, so
          # check quoted spans of the raw command (per-span, mutation-scoped)
          # plus the masked segment for unquoted single-word forms. Gated on
          # the SEGMENT actually calling a graphql endpoint, so a mutation
          # string quoted inside an unrelated REST body (issue note, comment)
          # cannot classify that segment as a merge (challenge round-2 P2).
          if printf '%s' "$seg" | grep -qi 'graphql'; then
            if printf '%s' "$seg" | grep -q 'mergeRequestAccept' \
               || graphql_merge_mutation 'mergeRequestAccept'; then
              hit=1; spell=SPELLOK
              # Multi-alias undercount (challenge R2 P0): a single GraphQL body
              # can carry several aliased mergeRequestAccept fields → several
              # platform merges. If more than one merge mutation appears, mark
              # the segment multi so the exactly-one-per-command guard trips.
              [ "$(printf '%s' "$cmd" | grep -o 'mergeRequestAccept' | grep -c .)" -gt 1 ] && multi_seg=1
            fi
          fi
          if [ "$hit" = 1 ]; then
            # REST auto-merge params (merge_when_pipeline_succeeds / auto_merge)
            printf '%s' "$seg" | grep -Eq 'merge_when_pipeline_succeeds=(true|1)|auto_merge=(true|1)' && auto=1
          fi
        fi
      else
        if [ "${1:-}" = "pr" ] && [ "${2:-}" = "merge" ]; then
          hit=1; shift 2
          while [ $# -gt 0 ]; do
            case "$1" in
              --auto|--auto=true) auto=1 ;;
              --admin) auto=1 ;;    # bypasses checks/queue: never released
              --merge|--squash|--rebase) spell=SPELLOK ;;
              -R|--repo) retarget=1; [ $# -ge 2 ] && shift ;;
              -R=*|--repo=*) retarget=1 ;;
              # value-taking flags: consume the value so it is not mistaken
              # for the PR id positional.
              -b|--body|-F|--body-file|-t|--subject|--match-head-commit|-A|--author-email) [ $# -ge 2 ] && shift ;;
              -*) : ;;
              *)
                if [ "$mid" = "?" ] && [ -z "${id_seen:-}" ]; then
                  id_seen=1
                  t="${1#!}"; t="${t##*#}"
                  case "$t" in
                    *[!0-9]*)
                      mid=$(printf '%s' "$t" | sed -n 's|.*/pull/\([0-9][0-9]*\)$|\1|p')
                      [ -n "$mid" ] || mid="?"
                      ;;
                    "") ;;
                    *) mid="$t" ;;
                  esac
                fi
                ;;
            esac
            shift
          done
          unset id_seen
        elif [ "${1:-}" = "api" ]; then
          # GitHub merge-API mirror of the glab path: pulls/<n>/merge.
          if printf '%s' "$seg" | grep -Eq '(^|[^a-zA-Z0-9_.-])pulls/[^ /]+/merge([^a-zA-Z_-]|$)'; then
            hit=1
            # Same mutating-method requirement as the glab REST path.
            printf '%s' "$seg" | grep -Eiq '(-X|--method)[= ]*(PUT|POST)' && spell=SPELLOK
            mid=$(printf '%s' "$seg" | sed -n 's|.*[^a-zA-Z0-9_.-]pulls/\([0-9][0-9]*\)/merge.*|\1|p')
            [ -n "$mid" ] || mid="?"
          fi
          # GraphQL merge mutations — segment-gated like the glab side.
          if printf '%s' "$seg" | grep -qi 'graphql'; then
            if printf '%s' "$seg" | grep -q 'mergePullRequest' \
               || graphql_merge_mutation 'mergePullRequest'; then
              hit=1; spell=SPELLOK
              # Multi-alias undercount (challenge R2 P0): see the glab side.
              [ "$(printf '%s' "$cmd" | grep -o 'mergePullRequest' | grep -c .)" -gt 1 ] && multi_seg=1
            fi
            # enablePullRequestAutoMerge schedules an auto-merge: always AUTO.
            if printf '%s' "$seg" | grep -q 'enablePullRequestAutoMerge' \
               || graphql_merge_mutation 'enablePullRequestAutoMerge'; then
              hit=1; auto=1
            fi
          fi
        fi
      fi
      if [ "$hit" = 1 ]; then
        # Explicit repo retargeting makes the static id meaningless for a
        # number-bound grant (546 in ANOTHER repo is a different MR): force
        # the id unresolvable so bound grants deny (unbound grants keep the
        # agent-side duty to target the discussed MR — documented residual).
        [ "$retarget" = 1 ] && mid="?"
        if [ "$auto" = 1 ]; then echo DENY_AUTO; else
          echo "DENY_MR $mid $spell"
          # A single segment carrying multiple aliased merge mutations emits a
          # second DENY_MR so the >1 exactly-one-per-command guard denies it.
          [ "$multi_seg" = 1 ] && echo "DENY_MR $mid $spell"
        fi
      fi
      ;;
    git)
      shift
      # Walk git global options. `-C <path>` REDIRECTS the repo the command
      # acts on — capture it so current/default-branch checks below evaluate
      # THAT repo, not the effective cwd (else `git -C /path/to/main merge
      # feat` from a feature worktree slips the on-default-branch checks).
      gdir="$eff_cwd"; used_C=0; inline_pd=""; gd_path=""; wt_path=""
      while [ $# -gt 0 ]; do
        case "$1" in
          -C)
            if [ $# -ge 2 ]; then
              case "$2" in /*) gdir="$2" ;; *) gdir="$gdir/$2" ;; esac
              used_C=1
              shift 2
            else shift; fi
            ;;
          -c)
            # Inline config counts: `git -c push.default=matching push` must
            # be judged with THAT value, not only the persisted repo config.
            if [ $# -ge 2 ]; then
              case "$2" in push.default=*) inline_pd="${2#push.default=}" ;; esac
              shift 2
            else shift; fi
            ;;
          # --git-dir/--work-tree retarget the acted-on repo like -C does.
          --git-dir=*) gd_path="${1#--git-dir=}"; shift ;;
          --git-dir) if [ $# -ge 2 ]; then gd_path="$2"; shift 2; else shift; fi ;;
          --work-tree=*) wt_path="${1#--work-tree=}"; shift ;;
          --work-tree) if [ $# -ge 2 ]; then wt_path="$2"; shift 2; else shift; fi ;;
          --*|-*) shift ;;
          *) break ;;
        esac
      done
      if [ -n "$wt_path" ] || [ -n "$gd_path" ]; then
        t="${wt_path:-$gd_path}"
        [ -z "$wt_path" ] && t="${t%/.git}"   # …/.git → its checkout dir
        case "$t" in /*) gdir="$t" ;; *) gdir="$gdir/$t" ;; esac
        used_C=1
      fi
      # Per-segment branch context (reset each segment): baselines when the
      # segment acts on the hook cwd, else ask the repo at gdir; a tracked
      # `git checkout`/`git switch` overrides the current branch unless the
      # segment -C-targets a different repo.
      # When a segment REDIRECTS the repo but the target cannot be resolved, the
      # branch context below silently falls back to the hook's cwd. That fallback is
      # right (an unknown target may well BE the default checkout, so assuming
      # otherwise would open the gate), but the resulting message then blames
      # "this command advances main" for what is really "I could not tell which repo
      # this is". The overwhelmingly common cause is an unexpanded shell variable —
      # `git -C "$WT" merge origin/main` — because this guard reads the command text
      # and cannot expand it. Tag it so the deny can say that instead.
      deny_git_tag="DENY_GIT"
      if [ "$gdir" = "$cwd" ]; then
        default_branch="$base_default_branch"
        current_branch="$base_current_branch"
        origin_flag="$base_origin_exists"
      elif git -C "$gdir" rev-parse --git-dir >/dev/null 2>&1; then
        default_branch=$(git -C "$gdir" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
        current_branch=$(git -C "$gdir" rev-parse --abbrev-ref HEAD 2>/dev/null)
        origin_flag=0
        git -C "$gdir" config --get remote.origin.url >/dev/null 2>&1 && origin_flag=1
      else
        default_branch="$base_default_branch"
        current_branch="$base_current_branch"
        origin_flag="$base_origin_exists"
        [ "$used_C" = 1 ] && deny_git_tag="DENY_GIT_UNRESOLVED"
      fi
      if [ -n "$eff_branch" ] && [ "$used_C" = 0 ]; then
        current_branch="$eff_branch"
      fi
      sub="${1:-}"; [ -n "$sub" ] && shift
      case "$sub" in
        checkout|switch)
          # Track the branch move for LATER segments in this command.
          [ "$used_C" = 1 ] && continue   # affects another repo, not eff_cwd
          nb=""
          for t in "$@"; do
            [ "$t" = "--" ] && break      # `checkout -- <paths>`: no branch move
            case "$t" in
              -*) continue ;;
            esac
            nb="$t"; break
          done
          [ -n "$nb" ] && eff_branch="$nb"
          continue
          ;;
        push)
          # Positional #1 is the remote; #2+ are refspecs. argi tracks that
          # so `git push origin <feature>` counts as having a refspec while
          # `git push` / `git push origin` stay refspec-less.
          has_default_target=0; has_refspec=0; pushes_head=0; argi=0
          for t in "$@"; do
            case "$t" in
              # --all/--mirror push every branch, unavoidably incl. the default.
              --all|--mirror) has_default_target=1; continue ;;
              -*) continue ;;
            esac
            argi=$((argi+1))
            t="${t#+}"   # force-push refspec prefix (+main, +HEAD:main)
            case "$t" in
              *:*)
                has_refspec=1
                dest="${t##*:}"; dest="${dest#refs/heads/}"
                is_default_name "$dest" && has_default_target=1
                ;;
              HEAD) has_refspec=1; pushes_head=1 ;;
              *)
                t="${t#refs/heads/}"   # non-colon fully-qualified form
                is_default_name "$t" && has_default_target=1
                [ "$argi" -ge 2 ] && has_refspec=1
                ;;
            esac
          done
          [ "$has_default_target" = 1 ] && { echo "$deny_git_tag"; break; }
          # bare push / push origin / push origin HEAD while ON the default branch
          if [ -n "$current_branch" ] && is_default_name "$current_branch"; then
            { [ "$has_refspec" = 0 ] || [ "$pushes_head" = 1 ]; } && { echo "$deny_git_tag"; break; }
          fi
          # Refspec-less push from a NON-default branch can still advance the
          # default under non-simple push.default: `matching` pushes every
          # same-named branch (incl. the default), and `upstream`/`tracking`
          # pushes INTO whatever branch.<cur>.merge names.
          if [ "$has_refspec" = 0 ]; then
            pd=$(git -C "$gdir" config --get push.default 2>/dev/null)
            [ -n "$inline_pd" ] && pd="$inline_pd"
            [ "$pd" = "matching" ] && { echo "$deny_git_tag"; break; }
            if [ "$pd" = "upstream" ] || [ "$pd" = "tracking" ]; then
              up=$(git -C "$gdir" config --get "branch.$current_branch.merge" 2>/dev/null)
              up="${up#refs/heads/}"
              if [ -n "$up" ] && is_default_name "$up"; then echo "$deny_git_tag"; break; fi
            fi
          fi
          ;;
        merge)
          if [ -n "$current_branch" ] && is_default_name "$current_branch"; then
            # carve-out: fast-forward-only sync from origin/<default> is allowed
            ff_only=0; src_origin_default=0
            for t in "$@"; do
              [ "$t" = "--ff-only" ] && ff_only=1
              case "$t" in
                origin/*) is_default_name "${t#origin/}" && src_origin_default=1 ;;
              esac
            done
            { [ "$ff_only" = 1 ] && [ "$src_origin_default" = 1 ]; } || { echo "$deny_git_tag"; break; }
          fi
          ;;
        pull)
          # pull = fetch + merge INTO the current branch. On the default
          # branch: bare pull / pull <remote> / pull <remote> <default> is
          # upstream sync (allowed); an explicit NON-default branch arg
          # merges that branch into the default -> deny.
          if [ -n "$current_branch" ] && is_default_name "$current_branch"; then
            argn=0; deny_pull=0
            for t in "$@"; do
              case "$t" in
                -*) continue ;;
              esac
              argn=$((argn+1))
              if [ "$argn" -ge 2 ]; then
                t="${t#+}"; t="${t#refs/heads/}"
                src="${t%%:*}"   # refspec src decides what merges in
                is_default_name "$src" || deny_pull=1
              fi
            done
            [ "$deny_pull" = 1 ] && { echo "$deny_git_tag"; break; }
          fi
          ;;
      esac
      ;;
  esac
done >"$vfile"
verdicts=$(cat "$vfile" 2>/dev/null)
rm -f "$vfile"

# A genuine default-branch advance outranks an unresolved target: if any segment is
# unambiguously advancing the default branch, say that, not "I could not tell".
if printf '%s\n' "$verdicts" | grep -q '^DENY_GIT$'; then
  deny "$DENY_TEXT_GIT"
fi
if printf '%s\n' "$verdicts" | grep -q '^DENY_GIT_UNRESOLVED$'; then
  deny "$DENY_TEXT_GIT_UNRESOLVED"
fi
if printf '%s\n' "$verdicts" | grep -q '^DENY_AUTO'; then
  deny "$DENY_TEXT_AUTO"
fi
if printf '%s\n' "$verdicts" | grep -q '^DENY_HTTP_AMBIGUOUS'; then
  deny "$DENY_TEXT_AMBIGUOUS"
fi
# Exactly ONE platform merge per COMMAND: a compound command with several
# merge calls is denied whole (grant intact). Under a one-shot grant the
# split commands each need a fresh directive; under a batch grant each
# split command consumes one unit.
if [ "$(printf '%s\n' "$verdicts" | grep -c '^DENY_MR')" -gt 1 ]; then
  deny "$DENY_TEXT_MULTI"
fi
if printf '%s\n' "$verdicts" | grep -q '^DENY_MR'; then
  # Release valve: consume a fresh, uid-owned, session-scoped grant armed by
  # the user's explicit merge directive. Grant kinds (specs 007 + 008):
  #   `armed` / `armed <id>` — one-shot, TTL 60 min, optionally id-bound.
  #   `armed batch <N>`      — counted batch, TTL 240 min anchored to the
  #                            ARMING time (decrement preserves mtime), one
  #                            unit per platform merge, unbound.
  # Every failure mode (no session_id, missing/foreign/stale sentinel,
  # malformed grant line or count) falls through to deny — fail-closed.
  mr_line=$(printf '%s\n' "$verdicts" | sed -n 's/^DENY_MR //p' | head -1)
  mr_id="${mr_line%% *}"; mr_spell="${mr_line##* }"
  # Everything from parse to consume/re-arm runs INSIDE the session lock so
  # a concurrent prompt-hook revoke/arm cannot be lost or mis-sequenced.
  # Lock unavailable → treated as no grant (fail-closed deny; grant intact,
  # the agent simply retries). The EXIT trap releases the lock on every
  # deny/allow path below.
  # Hygiene sweep (challenge R2 P2): a SIGKILL between mv and cleanup can
  # orphan .used.*/.rearm.* temp files and .lock dirs. Best-effort remove
  # any older than the stale-lock threshold so repeated kills cannot exhaust
  # inodes and wedge arming. Cheap, bounded to this session's auth dir.
  if [ -n "$sentinel" ]; then
    _adir=$(dirname "$sentinel")
    find "$_adir" -maxdepth 1 \( -name '*.used.*' -o -name '*.rearm.*' \) -mmin +1 -exec rm -f {} + 2>/dev/null
    find "$_adir" -maxdepth 1 -name '*.lock' -type d -mmin +1 -exec rm -rf {} + 2>/dev/null
  fi
  locked=0
  if [ -n "$sentinel" ] && [ -f "$sentinel" ] && acquire_lock; then
    locked=1
    trap 'rmdir "$lock_dir" 2>/dev/null' EXIT
  fi
  grant_kind=""; grant_num=""; batch_count=0; ttl_min=60
  if [ "$locked" = 1 ] && [ -f "$sentinel" ] && [ -O "$sentinel" ]; then
    grant_line=$(sed -n '1p' "$sentinel" 2>/dev/null)
    case "$grant_line" in
      "armed batch "*)
        batch_count="${grant_line#armed batch }"
        # Count must be a well-formed 1–999 integer (matches the prompt
        # hook's grammar); anything else is treated as no grant.
        case "$batch_count" in
          [1-9]|[1-9][0-9]|[1-9][0-9][0-9]) grant_kind=batch; ttl_min=240 ;;
          *) batch_count=0 ;;
        esac
        ;;
      armed) grant_kind=oneshot ;;
      "armed "*)
        # Number-bound one-shot ("merge !546" arms `armed 546`): the
        # released command must merge THAT id.
        grant_num="${grant_line#armed }"
        case "$grant_num" in
          ""|*[!0-9]*) grant_num="" ;;   # malformed → no grant
          *) grant_kind=oneshot ;;
        esac
        ;;
    esac
  fi
  if [ -n "$grant_kind" ] \
     && [ -n "$(find "$sentinel" -mmin "-$ttl_min" 2>/dev/null)" ]; then
    # Pre-consume checks: deny WITHOUT consuming (agent fixes and retries).
    [ "$mr_spell" = "SPELLOK" ] || deny "$DENY_TEXT_SPELL"
    if [ -n "$grant_num" ] && [ "$mr_id" != "$grant_num" ]; then
      deny "$DENY_TEXT_TARGET"
    fi
  fi
  # Atomic consume: mv succeeds for exactly one contender, so two parallel
  # merge commands cannot both ride a single grant/unit.
  if [ -n "$grant_kind" ] \
     && [ -n "$(find "$sentinel" -mmin "-$ttl_min" 2>/dev/null)" ] \
     && mv "$sentinel" "$sentinel.used.$$" 2>/dev/null; then
    # Batch decrement: re-arm with count-1, PRESERVING the arming mtime so
    # the 4h TTL anchors to the user's directive, not the last merge (a
    # rolling window would extend the grant indefinitely). Publish is
    # atomic (review P2): write a temp file, stamp it from the consumed
    # grant, then mv into place — the decremented grant only ever becomes
    # visible already carrying the original arming mtime. ANY failure
    # (unwritable dir, touch -r failure) drops the remaining units —
    # fail-closed — and never publishes a fresh-mtime grant.
    remaining=0
    if [ "$grant_kind" = batch ] && [ "$batch_count" -gt 1 ]; then
      remaining=$((batch_count-1))
      rearm="$sentinel.rearm.$$"
      if printf 'armed batch %s\n' "$remaining" >"$rearm" 2>/dev/null \
         && touch -r "$sentinel.used.$$" "$rearm" 2>/dev/null \
         && mv "$rearm" "$sentinel" 2>/dev/null; then
        :
      else
        rm -f "$rearm" 2>/dev/null
        remaining=0
      fi
    fi
    rm -f "$sentinel.used.$$" 2>/dev/null
    # Host-aware emission: Claude Code supports permissionDecision "allow"
    # (skips the permission prompt). Other hosts that execute these hooks
    # (e.g. the codex plugin bridge) accept deny but REJECT "allow" — they
    # error the hook after the grant was already consumed. For them, emit
    # the advisory systemMessage only (no decision): the merge command then
    # proceeds through that host's own approval flow.
    # Nested-host guard (review P1 + challenge P1): codex spawned FROM a
    # Claude session inherits CLAUDECODE=1, and an env blocklist alone is
    # structurally best-effort — so "allow" additionally requires the
    # POSITIVE Claude-Code input signal: this hook invocation's own
    # transcript_path living under a .claude directory (Claude Code always
    # sends it; a codex bridge's input would not point into .claude).
    # Every misdetection direction degrades to advisory (a popup), never
    # to a host error that burns the consumed grant.
    claude_host=0
    if [ "${CLAUDECODE:-}" = "1" ] \
       && [ -z "${CODEX_THREAD_ID:-}${CODEX_SANDBOX:-}${CODEX_CI:-}${CODEX_MANAGED_BY_NPM:-}${CODEX_HOME:-}" ]; then
      case "$tpath" in */.claude/*) claude_host=1 ;; esac
    fi
    if [ "$grant_kind" = batch ]; then
      if [ "$remaining" -gt 0 ]; then
        used_msg="✅ 合并授权闸：批量合并授权已消费 1 个额度，剩余 ${remaining} 个（自武装起 4 小时内有效；用户发送任何新消息即清除剩余额度）。"
      else
        used_msg="✅ 合并授权闸：批量合并授权已消费最后 1 个额度；再次合并需用户重新回复\"合并/merge\"或\"批量合并 <N>\"。"
      fi
    else
      used_msg="✅ 合并授权闸：用户合并指令一次性放行已消费；再次合并需用户重新回复\"合并/merge\"。"
    fi
    if [ "$claude_host" = 1 ]; then
      jq -nc --arg m "$used_msg" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",permissionDecisionReason:"合并授权闸：检测到用户明确合并指令（授权额度已消费），放行平台合并命令。"},systemMessage:$m}'
    else
      jq -nc --arg m "$used_msg" \
        '{systemMessage:($m + "（本宿主不支持免弹窗放行，命令按宿主正常审批流继续。）")}'
    fi
    exit 0
  fi
  deny "$DENY_TEXT_MR"
fi

# Visible-degrade warning (allow still stands): the repo has an origin remote
# but its default branch could not be resolved, and this command touches
# push/merge — tell the session the gate is narrowed to main|master instead
# of silently half-enforcing. Non-push/merge commands stay quiet (no noise).
if [ "$origin_exists" = 1 ] && [ -z "$default_branch" ] && printf '%s' "$masked" | grep -Eq '(^|[^[:alnum:]_-])git([^|;&]*[[:space:]])?(push|merge)([[:space:]]|$)'; then
  printf '{"systemMessage":"⚠️ merge-authorization guard: 无法解析该仓的默认分支（origin/HEAD 未设置）；本闸按 main/master/dev/develop/trunk 兜底判定，其余名字的默认分支可能漏拦。修复：git remote set-head origin -a"}\n'
fi

exit 0
