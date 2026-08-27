#!/usr/bin/env bash
# PreToolUse advisory — read the local CLI's own help before passing it a long
# flag (Bash tool only).
#
# WHY: distilled from 399 recorded agent failures across 122 sessions (round
# 059). "Flag guessed instead of read" accounts for ~20 of them, and the SAME
# flag — `glab mr list --state` — failed in EIGHT independent sessions spread
# over months. Every one of those eight was "fixed" the same way (read help, use
# the supported flag) and every fix only repaired that one instance, so the class
# came straight back. Same shape for `--jq` (3x), `--output`, `--pipeline-id`,
# `--branch`, `--old-text`, `--allow-scripts`.
#
# The rule already existed in prose, but only at two NARROW firing points:
# `worktree-isolation` (merge-authorization execution) and
# `skill-extraction-workflow` (verifying CLI examples written INTO a reference).
# Neither fires where the corpus actually fails: an agent about to run an
# ordinary inspection command. This hook is that missing firing point.
#
# DELIBERATELY DOES NOT PARSE THE COMMAND. An earlier version segmented on shell
# separators and handled heredocs, line continuations, the `--` terminator,
# launcher words, global options and hierarchical subcommands. Independent review
# found a new legal shell form it mishandled in essentially every round — fifteen
# of them — because the set of legal shell spellings is open-ended and a regex
# parser can only enumerate a prefix of it. This advisory does not need to know
# where the subcommand is or when a heredoc ends. It needs to know that a risky
# tool is being invoked with a long flag. So the predicate is: the tool name
# appears as a WORD, and some long flag appears. Nothing else is inspected.
#
# PREDICATE CHOICE (unchanged, and why TOOLS is a list of TOOLS): flag
# vocabularies are owned upstream and rot at every release, so the hook keys on
# the small, slow-moving set of tool NAMES. The same reasoning retired the
# parser: predicate on an invariant you own, never on someone else's vocabulary
# or grammar.
#
# NON-BLOCKING by design; NOT a security boundary (obfuscated invocations are out
# of scope, same declared class as the sibling hooks).
#
# ONE FIRE PER (session, tool): the first advisory for a tool in a session is
# enough of a nudge; the agent can check the whole command line from there. And
# within one Bash call only the FIRST listed tool is named — `glab ... && gh ...`
# yields one advisory, about glab. The reminder says to check the flags in this
# command, not just the named subcommand, so a second one would add nothing but
# noise; naming every tool would also mean deciding where each invocation begins,
# which is the parsing this hook exists without.
#
# ACCEPTED residuals — do NOT chase these with more string heuristics; chasing
# them is precisely what produced the fifteen-round parser:
#   - FALSE FIRE: a command that merely MENTIONS a listed tool alongside a long
#     flag (a heredoc body, a commit message whose metacharacters defeat the
#     quote mask, a grep pattern) draws one advisory for that session. One extra
#     line of context; the text says to ignore it if the flag is already known.
#   - FALSE FIRE: a help invocation that is not the command's first word
#     (`cd /x && glab mr list --help`) still draws the advisory.
#   - NON-FIRE: a payload hidden inside a whitespace-bearing quoted string
#     (`sh -c 'glab mr list --state opened'`). The quote mask exists to stop
#     commit messages and grep patterns from firing, and it cannot tell those
#     from a launcher payload without parsing the command — which is the thing
#     this hook does not do. Accepted in the QUIET direction: a missed nudge, not
#     a wrong one.
#   - DUPLICATE FIRE: two Bash calls using the same tool that start concurrently
#     can both pass the marker check before either append lands, so both advise.
#     The dedup is best-effort by construction and a lock is not worth buying for
#     a duplicated one-line nudge.
#   - NON-FIRE: short flags, and any tool outside TOOLS. Extend the list only
#     when a tool accumulates recorded flag failures.
#   - NON-FIRE: payloads over the 1 MiB read cap are ignored entirely.
#
# Degrade semantics (per hooks/AGENTS.md): jq missing → emit nothing (exit 0);
# any internal issue → stay silent rather than disrupt the session.

set -f

# Bound the READ, not just the parse: this hook sits in front of every Bash call,
# so its cost must not scale with command size. Past the cap jq sees truncated
# JSON, yields nothing, and the hook exits silently.
input=$(head -c 1048576)

command -v jq >/dev/null 2>&1 || exit 0

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

# Mask whitespace-bearing quoted spans so an ordinary commit message or grep
# pattern mentioning a tool does not fire. Single-word quoted values keep their
# content. This is the only text transform the hook performs.
masked=$(printf '%s' "$cmd" | sed -E \
  -e 's/"([^"[:space:];|&<>()]*)"/\1/g' \
  -e "s/'([^'[:space:];|&<>()]*)'/\\1/g" \
  -e 's/"[^"]*"/QUOTED/g' \
  -e "s/'[^']*'/QUOTED/g")

TOOLS='glab|gh|lark-cli|uv'

# EVERY listed tool in the command, not just the first. Taking only the first
# meant a tool that always trails another — `glab ... && gh ...` — could never
# reach its own advisory once the leader was deduped, so it stayed silent for the
# whole session. The dedup step below picks the first of these not yet advised.
# Still no parsing: this is the set of tool words present, not their positions.
tools_present=$(printf '%s' "$masked" | grep -Eow "(${TOOLS})" | awk '!seen[$0]++')
[ -z "$tools_present" ] && exit 0
tool=$(printf '%s' "$tools_present" | head -1)

printf '%s' "$masked" | grep -Eq -- '(^|[[:space:]])--[a-zA-Z][a-zA-Z0-9-]+' || exit 0

# Suppress only the unambiguous case: the command's FIRST WORD is the tool and it
# is asking for help. Taking one token is not parsing the command; it keeps the
# hook from telling someone to run the help they are already running, without a
# whole-string help check. Suppression is additionally limited to commands with
# NO shell separator: in `glab mr list --state opened && git --help` the first
# word is still the tool, so a whole-command help grep swallowed the advisory for
# a genuine invocation. Testing for a separator is one character class, not a
# parse — a compound command simply never qualifies for suppression.
first=$(printf '%s' "$masked" | awk '{print $1; exit}')
# A NEWLINE separates commands just as `;` does, and grep is line-oriented so a
# character class can never see one — a two-line command read as "simple" and its
# second line's `--help` suppressed the advisory for the first line's invocation.
# A standalone `--` hands the rest of the line to another program, so a `--help`
# after it belongs to that program, not to this tool: `uv run --python 3.12 --
# python --help` still needs the advisory for `--python`.
sep_lines=$(printf '%s' "$masked" | grep -c '')
if [ "$first" = "$tool" ] \
   && [ "$sep_lines" -le 1 ] \
   && ! printf '%s' "$masked" | grep -Eq -- '(^|[[:space:]])--([[:space:]]|$)' \
   && ! printf '%s' "$masked" | grep -q '[;|&]'; then
  # `-h` / `--help` anywhere in this simple command, or a bare `help` only in the
  # SUBCOMMAND slot. Accepting a bare `help` anywhere matched positional
  # arguments — `gh api help --paginate` asks for an endpoint named `help`, not
  # for help — and swallowed the advisory for a genuine flag.
  second=$(printf '%s' "$masked" | awk '{print $2; exit}')
  { printf '%s' "$masked" | grep -Eq -- '(^|[[:space:]])(-h|--help)([[:space:]]|$)' \
    || [ "$second" = "help" ]; } && exit 0
fi

# Best-effort per-session dedup. Any obstacle → skip dedup and remind again;
# reminding twice is harmless, the failure modes below are not.
#
# HOSTILE-TMPDIR HARDENING (adversarial challenge; every attack below was
# reproduced first-hand before being fixed). A predictable marker path directly
# under TMPDIR let another user on a shared /tmp pre-create it as a SYMLINK (the
# append wrote into an arbitrary file), as a FIFO (the append blocked until the
# host killed the hook at its 10s timeout — a denial of service on the agent's
# own Bash tool), or as a HARD LINK (which passes -f, -O and the symlink test
# alike). Sanitizing the session id does not help; the path is guessable either
# way. So the marker lives inside a directory this hook creates mode 0700 and
# verifies it owns, where another user cannot plant anything.
#
# The append runs inside a subshell whose stderr is already redirected, which
# closes the ENTIRE failed-open class — unwritable file, immutable flag, full
# filesystem, a state change between the checks and the open. An explicit `-w`
# check was removed once mutation showed it changed nothing the subshell did not
# already cover; keeping it would also have hidden the subshell from every probe
# by short-circuiting first. Enumerating open-failure causes is the same mistake
# as enumerating shell forms.
#
# THREAT MODEL, stated so this stops being re-litigated one finding at a time.
# The marker is a temp file holding a tool name. A successful attack on it buys
# exactly one thing: getting this user's uid to append a fixed short string
# (`glab`) to a file the attacker picks but cannot write themselves, or making
# the advisory silent. It cannot execute anything, cannot read anything, and
# carries no attacker-chosen content. The precondition walk below is therefore
# sized to that payload: resolve the physical path once, refuse the whole
# mechanism where the path is not exclusively ours or root's, and otherwise stop.
# The ancestor check was rewritten three times as review found successive holes —
# mode bits only, then bits plus sticky, then ownership, then physical
# resolution — which is the same recurrence signal the parser produced. The
# convergent form is the ownership invariant plus a physical path; further
# hardening of a fixed-string append is not worth more rounds.
#
# UNVERIFIED PROPERTIES (labelled, not counted as audited). Both need a second
# user id to construct, so no portable probe here reaches either, and a mutation
# removing each one leaves the suite fully green:
#   - the `-O` cross-uid rejection on the marker directory;
#   - the third-party-ownership rejection in the ancestor walk (a directory owned
#     by another non-root user, whose owner may rename its entries regardless of
#     the mode bits).
# The suite covers the same-uid and no-sticky directions of both. Do not read its
# green as covering these; they rest on code inspection alone.
# The suite does carry a PRESENCE check for each of them — a grep proving the
# guard is still written — so deleting one silently turns the suite red even
# though its behavior stays unverified. Presence is not behavior; the check
# exists only so an unverified guard cannot also become an unnoticed one.
session=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
if [ -n "$session" ]; then
  tmp_root="${TMPDIR:-/tmp}"
  # PRECONDITION, because the TOCTOU below cannot be closed from bash. Every
  # check on the marker directory is followed by a separate open of a path
  # underneath it, and in a directory another user may write to they can rename
  # the validated directory away and drop their own in its place between the two.
  # Closing that needs a directory handle and openat-relative operations, which
  # this language does not have. So the hook declines to dedup where dedup cannot
  # be made safe, rather than pretending the window is shut: if the temp root is
  # group- or world-writable and NOT sticky, skip the marker entirely and remind
  # again. Sticky is what makes the usual shared /tmp safe — only the owner may
  # rename or remove their entries there — and a per-user temp root is not
  # other-writable at all, so this fires in neither normal case.
  # Walk the whole ANCESTOR CHAIN, not just the temp root: a mode-0700 TMPDIR
  # sitting under a world-writable non-sticky parent is swappable wholesale, so
  # checking one level proves nothing about the path. Bounded by path depth, and
  # `/` is never other-writable so it always terminates.
  # Walk the PHYSICAL path. `dirname` on a logical path never resolves symlinks
  # or `..`, so a relative TMPDIR or one whose target sits under a hostile
  # ancestor walked a chain that does not exist on disk. Resolve once, up front.
  # `cd -- ` because a TMPDIR of `-P` or `-L` is otherwise taken as a cd OPTION,
  # leaving cd with no operand and landing in HOME — after which the ownership
  # checks pass and the marker directory gets created there.
  tmp_root=$(cd -- "$tmp_root" 2>/dev/null && pwd -P) || tmp_root=""
  probe_dir="$tmp_root"
  [ -z "$probe_dir" ] && probe_dir="/nonexistent"
  walk_n=0
  while : ; do
    dir_perm=$(ls -ld "$probe_dir" 2>/dev/null | cut -c1-10)
    if [ -z "$dir_perm" ]; then tmp_root=""; break; fi
    # TWO independent ways an ancestor lets someone move the path out from under
    # us, and the first is not about permission bits at all:
    #   (1) it is OWNED by a third party — a directory owner may rename entries
    #       in their own directory whatever the mode says, so 0755 owned by
    #       another non-root user is just as exploitable as 0777;
    #   (2) it is group/other-writable and NOT sticky — the classic shared-/tmp
    #       hole, where any writer may rename anyone's entry.
    # Earlier versions checked only the mode bits and then only bits-plus-sticky,
    # and independent review walked in through the gap each time. Ownership is
    # the invariant; the bits are the secondary case.
    dir_owner=$(ls -ld "$probe_dir" 2>/dev/null | awk '{print $3}')
    if [ ! -O "$probe_dir" ] && [ "$dir_owner" != "root" ]; then
      tmp_root=""; break
    fi
    if { [ "$(printf '%s' "$dir_perm" | cut -c6)" = "w" ] \
         || [ "$(printf '%s' "$dir_perm" | cut -c9)" = "w" ]; } \
       && [ ! -k "$probe_dir" ]; then
      tmp_root=""; break
    fi
    # Bound the walk: a legitimate path can have hundreds of components and each
    # iteration spawns several processes, in front of every Bash call. Real temp
    # roots are shallow; past the bound, refuse rather than keep paying.
    walk_n=$((walk_n + 1))
    if [ "$walk_n" -gt 40 ]; then tmp_root=""; break; fi
    # `--` for the same reason `cd` needed it: a path component that looks like
    # an option is taken as one. Not reachable from a `pwd -P` result today, but
    # the guard costs nothing and the omission is the exact shape already found
    # once in this file.
    parent_dir=$(dirname -- "$probe_dir")
    [ "$parent_dir" = "$probe_dir" ] && break
    probe_dir="$parent_dir"
  done
  marker_dir="${tmp_root}/ccl-skills-cliflag"
  # The explicit chmod is load-bearing: `mkdir -p -m 700` applies its mode only
  # when it CREATES the directory, so an already-present group/world-writable one
  # keeps its permissions and leaves the swap window open.
  if [ -n "$tmp_root" ] \
     && mkdir -p -m 700 "$marker_dir" 2>/dev/null \
     && [ -d "$marker_dir" ] && [ ! -L "$marker_dir" ] && [ -O "$marker_dir" ] \
     && chmod 700 "$marker_dir" 2>/dev/null; then
    # Bound the NAME: an over-long session id became an over-long filename, and
    # `>>file 2>/dev/null` applies redirections left to right, so the failed open
    # printed before the suppression took effect.
    safe_session=$(printf '%s' "$session" | tr -c 'A-Za-z0-9._-' '_' | cut -c1-100)
    marker="${marker_dir}/${safe_session}"
    marker_links=1
    if [ -e "$marker" ]; then
      marker_links=$(ls -ld "$marker" 2>/dev/null | awk '{print $2}')
      case "$marker_links" in ''|*[!0-9]*) marker_links=99 ;; esac
    fi
    if [ -L "$marker" ] || [ "$marker_links" -gt 1 ] \
       || { [ -e "$marker" ] && { [ ! -f "$marker" ] || [ ! -O "$marker" ]; }; }; then
      : # unexpected object — skip dedup entirely, do not open it
    else
      # SIZE-capped, and the story of why is worth keeping. This cap was added,
      # then removed on the argument that the line-count bound below already
      # prevented the append — an argument checked only against a MANY-LINE file,
      # where it happens to hold. A single enormous LINE has a line count of 1,
      # sails past that bound, gets appended to, and is re-scanned by both greps
      # on every matching call. Varying one dimension of the input and concluding
      # over all of them is the exact mistake the round's own material names.
      # Anything past a few lines of tool names is not ours: skip it, unread.
      marker_bytes=$(wc -c "$marker" 2>/dev/null | awk '{print $1; exit}')
      case "$marker_bytes" in ''|*[!0-9]*) marker_bytes=0 ;; esac
      if [ "$marker_bytes" -gt 4096 ]; then
        # Oversized: neither read nor written. Guarding only the read left the
        # append running, which is how a single enormous line kept growing.
        :
      else
          # Advise the first tool in this command not yet recorded this session; if
        # every one of them is recorded, stay quiet.
        if [ -f "$marker" ]; then
          tool=""
          for candidate in $tools_present; do
            grep -Fqx "$candidate" "$marker" 2>/dev/null || { tool="$candidate"; break; }
          done
          [ -z "$tool" ] && exit 0
        fi
        # `grep -c ''` on an EMPTY file prints 0 but EXITS 1, so trusting the
        # exit code produced "0\n0" and a stderr diagnostic from the test below.
        marker_lines=$(grep -c '' "$marker" 2>/dev/null | head -1)
        case "$marker_lines" in ''|*[!0-9]*) marker_lines=0 ;; esac
        if [ "$marker_lines" -lt 32 ]; then
          ( printf '%s\n' "$tool" >>"$marker" ) 2>/dev/null || true
        fi
      fi
    fi
  fi
fi

advisory="🔎 CLI flag 核验提醒（本会话对 \`${tool}\` 只提示一次）：\`${tool}\` 的 flag 词表**跨版本/跨平台差异很大**，凭记忆用 flag 是本仓记录中最高频的机械失败类之一——同一个 \`glab mr list --state\` 在 8 个独立会话里各踩一次，每次都只修了当次那一条。
这条命令里的 flag 若**本会话还没在本机确认过**，先读一次对应子命令的 help 再用。
已确认过就照常执行，忽略本提示。命令因无法识别的 flag 失败时，先怀疑这版不支持它，而不是先改用法之外的东西。"

jq -nc --arg r "$advisory" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$r}}'
exit 0
