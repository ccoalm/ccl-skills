#!/usr/bin/env bash
# owner-dispatch: mechanical firing for the product-rd "owner-dispatch firing gate".
#
# WHY THIS EXISTS
#   The owner-invoke rule (invoke the owning stack/design skill at each product-R&D
#   phase transition before producing substance) lived only as prose in SKILL.md +
#   bootstrap salience, and recurringly did not fire — the failing action is
#   agent-initiated and intent-dependent, so a stronger prompt cannot enforce it.
#   Industry practice (Anthropic "gate intermediate steps" / poka-yoke; Claude Code
#   hooks deny/ask/block enforced at the interpreter level; OpenAI Agents-SDK
#   guardrail tripwires; structured-required) is unanimous: encode a must-happen
#   step as a CODE gate that blocks, run as a separate check — never as prose.
#   This engine is that gate. Built on the decision model in
#   skills/llm-inference-integration/references/agent-lifecycle-hooks.md.
#
# SAFETY POSTURE (every default is the non-annoying / non-destructive one)
#   - OPT-IN: a repo with no committed `.owner-dispatch.json` (or enabled:false) is a
#     complete no-op. A cheap parent-walk for that file runs BEFORE any git/jq work,
#     so a non-opted repo pays ~nothing and never waits on git discovery.
#   - FAIL-OPEN: any internal error (missing jq/git, parse failure, unwritable/unsafe
#     state dir, missing session id) ALLOWS the action. A broken gate must never brick
#     editing, and no error path may fail-CLOSED.
#   - DEFAULT `ask`, NOT `deny`: hard `deny` is the explicit `strict:true` opt-in, is
#     Claude-Code-only (Codex ignores the decision), applies ONLY to precise
#     Edit/Write/MultiEdit/NotebookEdit file paths (never the heuristic Bash match),
#     and is downgraded to `ask` when the boundary state dir is not safely writable
#     (so strict can never brick a repo whose state dir is unavailable).
#   - Bash write-gating is BEST-EFFORT / ADVISORY only (a shell hook cannot reliably
#     detect every write form — `python -c`, `ed`, `make generate`, rsync, etc. slip
#     through). The host-agnostic un-bypassable gate is the `ci` subcommand.
#   - STATE WRITES are symlink-safe (refuse/replace symlinked state paths; atomic
#     temp+rename) so a crafted repo cannot redirect a write outside the state dir.
#   - STOP enforcement is per-session (keyed by a real session id; fail-open without
#     one), blocks at most once per actor per session, and fails open if the cap stamp
#     cannot be persisted — so it can never trap the user. The SAME engine handles
#     SubagentStop: when stdin carries agent_id (a dispatched subagent) the activity
#     marker, block-once cap, and waiver are scoped to that subagent, so a read-only
#     sibling / the main thread's dirty gated work never blocks an unrelated subagent.
#
# SUBCOMMANDS: pretool | stop | record --owners "a,b" | ci [--base REF] | status
#              | verify-invocations --owners "a,b" --transcript PATH

set -u

# Absolute path to this engine, so remediation messages name a command that works
# from any product repo's cwd (a product repo only holds `.owner-dispatch.json`).
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/$(basename "${BASH_SOURCE[0]}")"
SID="nosession"   # set per-invocation from the hook's session_id (pretool/stop)
AID=""            # agent_id (raw) — non-empty only inside a dispatched subagent (PreToolUse
                  # fires in subagents carrying agent_id; SubagentStop carries it too).
AIDKEY=""         # filename-safe, INJECTIVE key for agent_id, computed by jq @base64 from
                  # the RAW JSON (NOT a bash var — command substitution would drop NUL /
                  # strip trailing newline / mangle non-ASCII and let distinct agent_ids
                  # collide on the same marker). Empty iff no agent_id. Scopes the activity
                  # marker / block-cap / waiver to ONE subagent.

# ----- fail-open helpers ------------------------------------------------------
allow_pretool() { exit 0; }   # no output => allow
allow_stop()    { exit 0; }   # no output => allow stop
emit_pretool_deny() { # $1 reason  $2 decision(deny|ask)
  jq -nc --arg r "$1" --arg d "$2" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
  exit 0
}
emit_stop_block() { jq -nc --arg r "$1" '{decision:"block",reason:$r}'; exit 0; }
have() { command -v "$1" >/dev/null 2>&1; }
# ----- cheap opt-in discovery (NO git; runs before any expensive call) ---------
# Walk up from a start dir looking for `.owner-dispatch.json`. Pure bash, no git/jq,
# so a NON-opted repo pays only a few stat()s and never waits on git discovery.
# (The match here is a CANDIDATE; opt_in_root verifies it is a tracked top-level
# config before the gate activates.)
find_config_dir() { # $1 start dir -> echo candidate root dir, or fail
  local d="$1"
  [ -d "$d" ] || d=$(dirname -- "$d")
  while [ -n "$d" ] && [ "$d" != "/" ] && [ "$d" != "." ]; do
    [ -f "$d/.owner-dispatch.json" ] && { printf '%s' "$d"; return 0; }
    d=$(dirname -- "$d")
  done
  [ -f "/.owner-dispatch.json" ] && { printf '%s' "/"; return 0; }
  return 1
}
# Verified opt-in: the candidate config must sit at the git TOP-LEVEL of the target
# AND be TRACKED in the repo (a stray untracked file or a parent-directory config
# must never gate an unrelated/nested repo). Runs git ONLY when a candidate exists.
opt_in_root() { # $1 start dir -> echo verified root, or fail
  local cand top; cand=$(find_config_dir "$1") || return 1
  cand=$(realpath "$cand" 2>/dev/null) || return 1   # physical, to match git's toplevel
  top=$(git -C "$cand" rev-parse --show-toplevel 2>/dev/null) || return 1
  [ "$top" = "$cand" ] || return 1
  git -C "$cand" ls-files --error-unmatch .owner-dispatch.json >/dev/null 2>&1 || return 1
  printf '%s' "$cand"
}

# ----- config + classification ------------------------------------------------
config_path() { printf '%s/.owner-dispatch.json' "$1"; }
# Echo "enabled" iff opted in AND parseable AND enabled; malformed => empty (fail-open).
cfg_enabled() { # $1 root
  local c; c=$(config_path "$1"); [ -r "$c" ] || return 0
  jq -er 'if (.enabled // false) then "enabled" else empty end' "$c" 2>/dev/null
}
cfg_get() { # $1 root  $2 jq-filter  $3 default
  local c; c=$(config_path "$1"); [ -r "$c" ] || { printf '%s' "$3"; return; }
  jq -r "$2 // \"$3\"" "$c" 2>/dev/null || printf '%s' "$3"
}
path_matches_any() { # $1 rel  $2.. globs
  local rel="$1"; shift
  shopt -s extglob 2>/dev/null
  local g
  for g in "$@"; do
    [ -z "$g" ] && continue
    # $g INTENTIONALLY unquoted: match as a glob, not a literal.
    # shellcheck disable=SC2254
    case "$rel" in $g) return 0 ;; esac
    # A leading **/ means "zero or more directories" (gitignore/globstar intent).
    # bash `case` is NOT globstar-aware (* already crosses /, so **/PAT collapses
    # to */PAT and only matches paths WITH a slash). Also test the slash-stripped
    # PAT so a top-level (repo-root) file is gated too — otherwise a repo whose
    # product code is top-level + a ["**/*.go"]-style config silently gates nothing.
    case "$g" in
      '**/'*)
        # shellcheck disable=SC2254
        case "$rel" in ${g#'**/'}) return 0 ;; esac
        ;;
    esac
  done
  return 1
}
load_globs() { # $1 root  -> PRODUCT_GLOBS / EXCLUDE_GLOBS
  local c; c=$(config_path "$1"); PRODUCT_GLOBS=(); EXCLUDE_GLOBS=()
  [ -r "$c" ] || return 0
  local line
  while IFS= read -r line; do [ -n "$line" ] && PRODUCT_GLOBS+=("$line"); done < <(jq -r '(.product_globs // [])[]' "$c" 2>/dev/null)
  while IFS= read -r line; do [ -n "$line" ] && EXCLUDE_GLOBS+=("$line"); done < <(jq -r '(.exclude_globs // [])[]' "$c" 2>/dev/null)
  EXCLUDE_GLOBS+=("**/*.md" ".owner-dispatch.json" ".git/**")
}
is_gated_path() { # $1 root  $2 rel
  load_globs "$1"
  [ "${#PRODUCT_GLOBS[@]}" -gt 0 ] || return 1
  path_matches_any "$2" "${EXCLUDE_GLOBS[@]}" && return 1
  path_matches_any "$2" "${PRODUCT_GLOBS[@]}" && return 0
  return 1
}

# ----- symlink-safe per-REPOSITORY state --------------------------------------
# Keyed on the COMMON git dir, not `--absolute-git-dir`. Under a linked worktree the
# latter is `.git/worktrees/<name>`, so state written while working in a worktree is
# invisible to a read from the main checkout — and that split is guaranteed by this
# org's own rules, not an edge case: `worktree-isolation` mandates developing in a
# worktree, while `cmd_stop` resolves its repo from $PWD, which the harness routinely
# resets back to the main checkout. The gate then reports "never recorded" on the
# standard workflow, and a gate that cries wolf every delivery stops being read at all.
# Worktree cleanup would also delete the record. State is session-scoped and the actor
# is already isolated by session/agent id inside this dir, so sharing it per repository
# is the correct scope — one repo, one boundary namespace.
#
# `--git-common-dir` is asked for ABSOLUTELY on purpose: plain `--git-common-dir`
# answers a bare relative `.git` when the caller is the main checkout (absolute only
# from a linked worktree), which would make the state dir depend on the caller's cwd —
# the same defect class, re-introduced. `--path-format` needs git >= 2.31; the fallback
# resolves the relative answer against the root git was pointed at, not against $PWD.
boundary_dir() { # $1 root (echo <common-git-dir>/owner-dispatch)
  local gd
  gd=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || gd=""
  if [ -z "$gd" ]; then
    gd=$(git -C "$1" rev-parse --git-common-dir 2>/dev/null) || return 1
    [ -n "$gd" ] || return 1
    case "$gd" in /*) ;; *) gd="$1/$gd" ;; esac
  fi
  # Canonicalise. The two branches above disagree on symlinked roots: git answers the
  # PHYSICAL path, while the fallback's `$1/<relative>` keeps whatever logical path the
  # caller passed (macOS /var -> /private/var is the everyday case). Left alone, a host on
  # git < 2.31 would get a different key from the main checkout than from a worktree and
  # this whole bug would come back on exactly the machines that cannot use the fast path.
  # `opt_in_root` already realpath's "to match git's toplevel"; match it here.
  local rp; rp=$(realpath "$gd" 2>/dev/null) && [ -n "$rp" ] && gd="$rp"
  printf '%s/owner-dispatch' "$gd"
}
# Resolve + create the state dir, refusing a symlinked dir (a crafted repo could
# point it elsewhere). Echo the dir on success; fail (=> caller fails open).
state_dir() { # $1 root
  local d; d=$(boundary_dir "$1") || return 1
  [ -L "$d" ] && return 1
  [ -e "$d" ] && [ ! -d "$d" ] && return 1
  mkdir -p "$d" 2>/dev/null || return 1
  printf '%s' "$d"
}
# Symlink-safe writes: a symlink in our own namespace is illegitimate -> drop it,
# then write via mktemp (O_EXCL, unpredictable name => no predictable-temp race) +
# atomic rename so the redirect never follows a link. NOTE: the state dir lives
# inside `<git-dir>/owner-dispatch`; an attacker who can race writes there already
# has write access to your `.git` (hooks, objects, config) and owns the repo — so
# residual TOCTOU here is bounded by a trust boundary you have already lost.
safe_put() { # $1 file  $2 content
  [ -L "$1" ] && rm -f "$1" 2>/dev/null
  local dir t; dir=$(dirname -- "$1")
  t=$(mktemp "$dir/.od.XXXXXX" 2>/dev/null) || return 1
  printf '%s' "$2" > "$t" 2>/dev/null && mv -f "$t" "$1" 2>/dev/null || { rm -f "$t" 2>/dev/null; return 1; }
}
safe_append() { # $1 file  $2 line  (atomic read-modify-rewrite via safe_put)
  [ -L "$1" ] && rm -f "$1" 2>/dev/null
  local cur=""; [ -f "$1" ] && cur=$(cat "$1" 2>/dev/null)
  safe_put "$1" "$cur$2"$'\n'
}
# Append $2 + a NUL terminator using O_APPEND (`>>`), which is CONCURRENCY-SAFE: each
# write is positioned at EOF atomically, so two parallel same-agent PreToolUse hooks (the
# model can emit parallel Edits in one turn) never lose an entry — unlike a read-copy-
# rename, where both read the same old file and the last rename clobbers the other's add.
# A single path is far under PIPE_BUF so the write is atomic. NUL-delimited so entries
# with newlines/spaces are read back by exact byte-equality. Symlink-dropped first (same
# .git-trust bound as the other state writers; whole-file atomicity isn't needed for an
# append-only log).
safe_append_z() { # $1 file  $2 value
  [ -L "$1" ] && rm -f "$1" 2>/dev/null
  printf '%s\0' "$2" >> "$1" 2>/dev/null || return 1
}
# Atomic, symlink-safe, BINARY/NUL-safe write from stdin (bash vars can't hold NUL,
# so NUL-delimited path lists must stream straight to the temp file via cat).
safe_put_stdin() { # $1 file  (content on stdin)
  [ -L "$1" ] && rm -f "$1" 2>/dev/null
  local dir t; dir=$(dirname -- "$1")
  t=$(mktemp "$dir/.od.XXXXXX" 2>/dev/null) || return 1
  cat > "$t" 2>/dev/null && mv -f "$t" "$1" 2>/dev/null || { rm -f "$t" 2>/dev/null; return 1; }
}
sid_safe() { printf '%s' "${1:-}" | tr -c 'A-Za-z0-9._-' '_'; }
# Compute the INJECTIVE, filename-safe agent_id key directly from the hook's raw JSON on
# stdin via jq @base64 — operating on the JSON value, NOT a bash var, so NUL / trailing
# newline / non-ASCII in agent_id cannot be dropped or mangled into a collision. base64's
# '+' and '/' are remapped to '-' '_' (base64url) so the key is a safe filename component;
# '=' padding is filename-safe as-is. Empty agent_id => empty key (base64 of "" is "").
aid_key_from() { # stdin: raw hook JSON -> echo injective key (empty if no agent_id)
  jq -r '.agent_id // "" | @base64' 2>/dev/null | tr '+/' '-_'
}
# In an UNBORN repo `git rev-parse HEAD` prints the literal "HEAD" on stdout AND exits
# non-zero, so the old `cmd 2>/dev/null || printf NO_HEAD` emitted BOTH — a two-line value
# that equalled nothing and made every NO_HEAD comparison downstream dead code. Use
# --verify so the failure path produces no stdout, and the sentinel is the only output.
current_head() { git -C "$1" rev-parse --verify --quiet HEAD 2>/dev/null || printf 'NO_HEAD'; }

# Validity is (repo, TTL, HEAD-continuity): the recorded head must remain an ANCESTOR of the
# current HEAD, not equal to it.
#
# Why equality was wrong: the gate requires recording BEFORE the first gated edit, and a
# delivery's own commit necessarily lands AFTER that edit — so a HEAD-equality condition
# invalidated the boundary of every delivery that commits, and Stop then reported it as
# "never recorded". Worse than the false block: the only strategy that satisfied a
# HEAD-pinned boundary was re-recording at session end, which turns "record before editing"
# into post-hoc attestation — the record-field forgery surface the invocation-evidence
# check exists to close.
#
# Why dropping HEAD entirely was ALSO wrong: equality was incidentally catching history
# discontinuities — `git switch` to an unrelated branch, a reset onto a divergent commit —
# which genuinely do mean "a different piece of work". A TTL-only rule let the same actor
# record once, finish that delivery, jump to an unrelated branch inside the TTL, and edit
# gated code with no gate at either end. Ancestry keeps the commit-forward case working
# (the actual defect) while re-firing on the discontinuity case.
#
# HEAD was ALSO standing in for actor identity ("this boundary is THIS work unit's"), and
# nothing here replaces that: there is no actor binding. `owners_not_invoked` at Stop
# verifies only that the recorded owner NAMES appear as invoked skills in the current
# actor's transcript. That blocks an actor which invoked nothing, or a different owner set
# — but it clears an actor that invoked the same names, whoever recorded the boundary. So
# it detects SOME cross-actor reuse as a side effect; it does not bind a boundary to an
# actor. Do not restate it as identity binding (see the residual note below).
#
# Residual (accepted by the risk owner): within TTL, on the same descendant line of work, in
# the same worktree, a DIFFERENT actor inherits this boundary. PreToolUse never reads the
# transcript, and Stop clears that actor too whenever it invoked the same owner NAMES
# (`missing` empty => allow) — the normal case for a repo with a stable owner set, not an
# edge case. So "record before first edit" is not enforced per-actor. Do not restate this as
# "Stop still catches it": it does not. Also unenforced: whether the recorded owner set
# matches the concerns actually touched (needs a glob->owner map; deferred).
# Parse all gate-critical fields from ONE jq invocation, i.e. one opened version of the file.
# Sets b_repo / b_exp / b_head in the caller's scope (they are declared `local` there).
# @tsv escapes any literal tab inside a value, so splitting on real tabs is unambiguous.
boundary_read() { # $1 boundary.json  -> sets b_repo b_exp b_head b_gitdir; fails if unparseable
  local snap rest
  snap=$(jq -r '[(.repo_root // ""), (.expires_at // 0), (.head // ""), (.repo_git_dir // "")] | @tsv' "$1" 2>/dev/null) || return 1
  [ -n "$snap" ] || return 1
  b_repo=${snap%%$'\t'*}; rest=${snap#*$'\t'}
  b_exp=${rest%%$'\t'*};  rest=${rest#*$'\t'}
  # `@tsv` always emits all four fields, so a missing tab here means a malformed
  # snapshot rather than an absent value — treat the git dir as unknown and let the
  # caller fall back, instead of silently aliasing it to the head.
  case "$rest" in
    *$'\t'*) b_head=${rest%%$'\t'*}; b_gitdir=${rest#*$'\t'} ;;
    *)       b_head=$rest;           b_gitdir="" ;;
  esac
}

boundary_valid() { # $1 root  -> echo "valid" iff a non-expired boundary exists
  local d f now b_repo b_exp b_head b_gitdir cur
  d=$(boundary_dir "$1") || return 1
  f="$d/boundary.json"; [ -r "$f" ] && [ ! -L "$f" ] || return 1
  now=$(date +%s)
  # ONE snapshot, one jq. Reading the fields through separate jq processes was a torn-read
  # fail-open: `record` replaces this file by atomic rename, so a concurrent record between
  # two reads let the check combine an unexpired expiry from one record with the head from
  # another and return valid though neither record was. A single invocation sees exactly one
  # version of the file.
  boundary_read "$f" || return 1     # sets b_repo / b_exp / b_head / b_gitdir
  # REPOSITORY identity, not working-tree path. `repo_root` is a per-worktree path, so
  # comparing it literally rejected a boundary recorded in a linked worktree and read
  # from the main checkout — i.e. every delivery that follows `worktree-isolation`.
  # The common git dir is the same for every worktree of one repo AND survives the
  # worktree being removed at cleanup, which the recording path never does. This is a
  # replacement, not a removal: it still refuses a boundary belonging to a different
  # repository (what the path equality was really there for). A legacy record with no
  # repo_git_dir keeps the old path equality — conservative, since that record was
  # written by the pre-fix code and can only have come from this same root anyway.
  if [ -n "$b_gitdir" ]; then
    [ "$b_gitdir" = "$(boundary_dir "$1")" ] || return 1
  else
    [ "$b_repo" = "$1" ] || return 1
  fi
  [ "$now" -lt "$b_exp" ] 2>/dev/null || return 1
  # CONTINUITY, not equality: the recorded head must still be an ancestor of the current
  # HEAD. Committing forward on the same line of work keeps the boundary (that is the whole
  # point of dropping equality), while `git switch` to an unrelated branch, a reset onto a
  # divergent commit, or any other history discontinuity re-fires the gate — those really do
  # mean "a different piece of work", which equality was incidentally catching and a
  # TTL-only rule would silently let through.
  cur=$(current_head "$1")
  # Unborn repo on either side: there is no history, so continuity cannot be established —
  # fail closed. This IS a deliberate behaviour change, not a no-op: the previous equality
  # rule ALLOWED here. `current_head` used to emit the two-line value "HEAD\nNO_HEAD" (the
  # unborn `rev-parse` prints "HEAD" on stdout *and* fails), and since both `record` and the
  # check used the same helper, both sides produced that identical string and compared equal
  # — verified against the old code, which returns allow in an unborn repo where this returns
  # ask. Failing closed is the intended outcome: an unborn repo has no line of work to be
  # continuous with, and switching between orphan branches must not satisfy the gate.
  { [ "$b_head" = "NO_HEAD" ] || [ "$cur" = "NO_HEAD" ]; } && return 1
  [ -n "$b_head" ] || return 1
  # Both env vars are load-bearing and neither substitutes for the other (verified on
  # git 2.50): GIT_NO_REPLACE_OBJECTS disables `git replace` refs, GIT_GRAFT_FILE disables
  # the legacy `.git/info/grafts` file — with only the former, a grafts file still makes
  # merge-base report an unrelated commit as an ancestor. Not a serious adversary story
  # (anyone deliberately evading can `touch <waiver>`, which is documented), but a repo
  # legitimately carrying grafts or replace refs would otherwise get a silently wrong
  # verdict. True-object ancestry only.
  GIT_NO_REPLACE_OBJECTS=1 GIT_GRAFT_FILE=/dev/null \
    git -C "$1" merge-base --is-ancestor "$b_head" "$cur" 2>/dev/null || return 1
  printf 'valid'
}

# Classify WHY a boundary is unusable. Wording only — never a gate input; every enforcement
# path keeps calling boundary_valid.
#
# Each invalidating reason gets its OWN label, because collapsing them is the exact defect
# this file was changed to fix: telling an actor it "never recorded" a boundary when a
# record exists sends diagnosis hunting for a missing file. `expired` and `discontinuous`
# are both "you recorded, but it no longer applies" — very different from "there is nothing
# here". An unparseable record stays `absent` (conservative: never imply a usable record was
# found when the field could not be read).
boundary_state() { # $1 root  -> echo valid|expired|discontinuous|absent
  local d f now b_repo b_exp b_head b_gitdir cur
  boundary_valid "$1" >/dev/null && { printf 'valid'; return 0; }
  d=$(boundary_dir "$1") || { printf 'absent'; return 0; }
  f="$d/boundary.json"; { [ -r "$f" ] && [ ! -L "$f" ]; } || { printf 'absent'; return 0; }
  boundary_read "$f" || { printf 'absent'; return 0; }        # one snapshot, same as the gate
  # Same repository-identity rule as the gate. Keeping literal path equality HERE while the
  # gate compares git dirs would rebuild the exact contradiction `cmd_status` already warns
  # about: the diagnostic saying "absent" for a boundary the gate accepts.
  if [ -n "$b_gitdir" ]; then
    [ "$b_gitdir" = "$(boundary_dir "$1")" ] || { printf 'absent'; return 0; }
  else
    [ "$b_repo" = "$1" ] || { printf 'absent'; return 0; }
  fi
  case "$b_exp" in (''|0|*[!0-9]*) printf 'absent'; return 0 ;; esac   # non-integer => absent
  now=$(date +%s)
  [ "$now" -lt "$b_exp" ] 2>/dev/null || { printf 'expired'; return 0; }
  # Present, repo-matching, unexpired, yet boundary_valid rejected it. Before calling that a
  # history discontinuity, prove the recorded head IS a real commit here: a well-formed but
  # nonexistent sha (an all-zero value, a gc'd or shallow-clone-missing object) is an
  # unusable record, not evidence of a branch switch — saying "a reset moved HEAD off it"
  # there would be the same false diagnosis this whole change set exists to remove.
  cur=$(current_head "$1")
  case "$b_head" in (''|*[!0-9a-fA-F]*) printf 'absent'; return 0 ;; esac  # not sha-shaped
  GIT_NO_REPLACE_OBJECTS=1 GIT_GRAFT_FILE=/dev/null \
    git -C "$1" cat-file -e "$b_head^{commit}" 2>/dev/null || { printf 'absent'; return 0; }
  [ "$b_head" = "$cur" ] && { printf 'absent'; return 0; }   # equal yet invalid => not continuity
  printf 'discontinuous'
}

# ----- invocation evidence (name != invoke) -----------------------------------
# The record only stores owner NAMES; this cross-checks them against the skills
# ACTUALLY invoked (loaded) this session, read from the Claude Code session
# transcript (a JSONL of message events). A Skill invocation appears as a
# `tool_use` content block with name=="Skill" and input.skill=="<plugin>:<name>".
# Empirically verified on the current transcript format; missing/unreadable or
# malformed or shape-drifted evidence stays FAIL-OPEN. A subagent transcript with a
# verifiable tool-event shape but zero Skill calls proves the worker never loaded one.
#
# Emit the base skill names invoked in a transcript, ONE PER LINE (strip any "prefix:").
invoked_skills() { # $1 transcript-path
  [ -n "$1" ] && [ -r "$1" ] || return 0
  # Per-line jq (JSONL); tolerate malformed lines. A line's message.content[] may
  # carry tool_use blocks. input.skill is "ccl-skills:foo" or bare "foo".
  jq -rR '
    fromjson?
    | select(.type=="assistant")   # real invocations live in assistant events only
    | (.message.content // empty)
    | if type=="array" then .[] else empty end
    | select(type=="object" and .type=="tool_use" and .name=="Skill")
    | (.input.skill)
    | strings                       # drop non-string skill values (no sub() abort)
    | select(length>0)
    | ascii_downcase
    | if startswith("ccl-skills:") then ltrimstr("ccl-skills:") else . end
  ' "$1" 2>/dev/null
}

# True iff the transcript contains at least one recognized assistant tool_use block and
# every visible Skill block has the invocation shape parsed by invoked_skills. This lets
# strict worker verification distinguish "the worker invoked no skills" from "the host
# transcript or Skill-event shape drifted" without turning valid-JSON drift into a trap.
transcript_has_verifiable_invocation_shape() { # $1 transcript-path
  [ -n "$1" ] && [ -r "$1" ] || return 1
  jq -seR '
    [ split("\n")[]
      | try fromjson catch empty
      | select(.type=="assistant")
      | (.message.content // empty)
      | if type=="array" then .[] else empty end
      | select(type=="object" and .type=="tool_use")
    ] as $tools
    | ($tools | length) > 0
      and ([ $tools[] | select((.name | type) != "string") ] | length) == 0
      and ([ $tools[]
             | select(.name=="Skill"
                      and (((.input | type) != "object")
                           or ((.input.skill | type) != "string")
                           or (.input.skill | length) == 0))
           ] | length) == 0
  ' "$1" >/dev/null 2>&1
}

# Echo (comma-joined) the recorded owners that (a) look like a skill name
# (kebab token, no spaces) and (b) were NEVER invoked in the transcript. Free-text
# owner labels ("then the touched owner") are skill-name-shaped-filtered out, so
# they never false-flag. Empty output => nothing to report (all invoked, or
# unverifiable => fail-open). $3=true makes a shape-verifiable zero-invocation transcript
# report every skill-shaped owner; this is used for a worker's own transcript only.
owners_not_invoked() { # $1 boundary.json  $2 transcript-path  $3 empty-is-missing(true|false)
  local bf="$1" tp="$2" empty_is_missing="${3:-false}"
  [ -r "$bf" ] && [ -n "$tp" ] && [ -r "$tp" ] || return 0
  # newline-separated invoked base-name set for grep -Fxq membership
  local invoked; invoked=$(invoked_skills "$tp")
  # Main sessions preserve the historical fail-open behavior for an empty set. A worker
  # uses its dedicated transcript and strict mode: if that file contains a verifiable
  # tool-event shape but zero Skill calls, the empty set is evidence of a cold worker.
  # Missing, malformed, or Skill-shape-drifted evidence remains unverifiable/fail-open.
  if [ -z "$invoked" ]; then
    [ "$empty_is_missing" = "true" ] && transcript_has_verifiable_invocation_shape "$tp" || return 0
  fi
  local out="" o norm
  while IFS= read -r o; do
    [ -n "$o" ] || continue
    # Normalize the owner token the SAME way invoked skills are: lowercase and strip a
    # leading "ccl-skills:" so a recorded full id (ccl-skills:foo) matches the
    # invoked base name "foo". Other-plugin prefixes are NOT stripped (they keep the ':'
    # and fail the kebab-shape check below), so a same-named skill from an untrusted
    # plugin cannot silently satisfy a CCL owner.
    norm=$(printf '%s' "$o" | tr '[:upper:]' '[:lower:]')
    case "$norm" in ccl-skills:*) norm=${norm#ccl-skills:} ;; esac
    # skill-name shape only: a single kebab token; excludes phrases with spaces/commas
    # and any remaining "plugin:" colon.
    case "$norm" in *[!a-z0-9-]*|"") continue ;; esac
    printf '%s\n' "$invoked" | grep -Fxq "$norm" && continue
    out="${out:+$out,}$o"
  done < <(jq -r '(.touched_owners // [])[]? | gsub("^\\s+|\\s+$";"")' "$bf" 2>/dev/null)
  printf '%s' "$out"
}

# ----- per-session activity markers + baseline --------------------------------
# Two activity markers record THAT this session did owner-dispatch-relevant work:
#   .touched   — an Edit/Write tool touched a gated path.
#   .bashwrite — the best-effort Bash write-verb heuristic matched (over-matches
#                read-only commands, so it is only an activity hint, never proof).
# Neither marker's CONTENT is parsed (safe_append concatenates without a reliable
# separator) — they are existence-only triggers. What a session actually CHANGED is
# decided at Stop by diffing the current tree against a baseline snapshot (HEAD +
# product/exclude globs + content-hashed pre-session dirty paths) captured at the FIRST
# touch (PreToolUse fires before the edit applies, so the baseline is the pre-edit
# state). That distinguishes real new gated work (committed OR dirty) from a read-only/
# rejected/reverted session and from untouched pre-existing dirt — without trapping —
# and resists config mutation (product-shrink / exclude-widen) via baseline∪current
# classification, with `ci` as the reliable backstop.
note_touched() { # $1 root  $2 rel  (per-session, symlink-safe; + per-agent in a subagent)
  local sd; sd=$(state_dir "$1") || return 0
  capture_baseline "$1"
  safe_append "$sd/s.$(sid_safe "$SID").touched" "$2"
  # In a subagent, ALSO record a per-agent marker so SubagentStop can tell THIS subagent
  # did gated work (vs. a read-only sibling or the main thread). NUL-delimited so the path
  # is read back by exact byte-equality (the session marker above is existence-only).
  [ -n "$AID" ] && safe_append_z "$sd/s.$(sid_safe "$SID").a.$AIDKEY.touched" "$2"
}
note_bashwrite() { # $1 root  (per-session heuristic sentinel, symlink-safe; + per-agent in a subagent)
  local sd; sd=$(state_dir "$1") || return 0
  capture_baseline "$1"
  safe_put "$sd/s.$(sid_safe "$SID").bashwrite" "1"
  [ -n "$AID" ] && safe_put "$sd/s.$(sid_safe "$SID").a.$AIDKEY.bashwrite" "1"
}

# Baseline globs captured at first touch (the authoritative classification at the time
# the work happened), kept separate from the current globs so config mutation can't
# dodge. Always SET (even empty) so `"${BASE_*[@]}"` is safe under bash 3.2 `set -u`.
BASE_PRODUCT=(); BASE_EXCLUDE=()

# Echo the working-tree content hash of <rel> (or ABSENT if missing/unreadable).
# Filters are applied identically at capture and at Stop, so the comparison is stable.
path_hash() { # $1 root  $2 rel
  git -C "$1" hash-object -- "$2" 2>/dev/null || printf 'ABSENT'
}

# Snapshot, ONCE per session+repo (first touch = PreToolUse, before the edit applies),
# the pre-session state so Stop can tell what THIS session changed. Writes: .basehead
# (HEAD SHA, or UNBORN); .baseglobs / .baseexcl (product/exclude globs at capture time,
# the authoritative classification — used at Stop alongside the current globs so a
# later product-shrink OR exclude-widen can't hide a gated path); .basepaths (NUL pairs
# rel\0hash\0 of gated paths ALREADY changed-vs-HEAD before the session, WITH their
# content hash — so a pre-existing dirty file is excused only while its content is
# unchanged; editing it further changes the hash and is caught). .basehead is written
# LAST and is the idempotency guard.
capture_baseline() { # $1 root
  local sd sidf; sd=$(state_dir "$1") || return 0; sidf=$(sid_safe "$SID")
  [ -e "$sd/s.$sidf.basehead" ] && return 0
  local head; head=$(git -C "$1" rev-parse HEAD 2>/dev/null || printf 'UNBORN')
  load_globs "$1"; BASE_PRODUCT=(); BASE_EXCLUDE=()   # baseline classification == current here
  # Write the data files FIRST; .basehead is the success-guard written LAST, so a
  # partial write (disk full, RO fs) leaves no .basehead => the next touch re-captures
  # and meanwhile session_gated_changed falls back to gated_dirty (never a stale baseline).
  { local g; for g in ${PRODUCT_GLOBS[@]+"${PRODUCT_GLOBS[@]}"}; do [ -n "$g" ] && printf '%s\0' "$g"; done; } \
    | safe_put_stdin "$sd/s.$sidf.baseglobs" || return 0
  { local x; for x in ${EXCLUDE_GLOBS[@]+"${EXCLUDE_GLOBS[@]}"}; do [ -n "$x" ] && printf '%s\0' "$x"; done; } \
    | safe_put_stdin "$sd/s.$sidf.baseexcl" || return 0
  { local rel; while IFS= read -r -d '' rel; do
      [ -n "$rel" ] && printf '%s\0%s\0' "$rel" "$(path_hash "$1" "$rel")"
    done < <(emit_changed_z "$1" "$head"); } | safe_put_stdin "$sd/s.$sidf.basepaths" || return 0
  safe_put "$sd/s.$sidf.basehead" "$head"
}

# Load BASE_PRODUCT / BASE_EXCLUDE from the captured baseline glob files.
load_base_globs() { # $1 baseglobs-file  $2 baseexcl-file
  BASE_PRODUCT=(); BASE_EXCLUDE=(); local g
  [ -r "$1" ] && while IFS= read -r -d '' g; do [ -n "$g" ] && BASE_PRODUCT+=("$g"); done < "$1"
  [ -r "$2" ] && while IFS= read -r -d '' g; do [ -n "$g" ] && BASE_EXCLUDE+=("$g"); done < "$2"
}

# True (0) iff <rel> is gated under the CURRENT config OR the BASELINE config (gated ==
# matches product AND not matches exclude, evaluated per-config) — so neither a
# product-shrink nor an exclude-widen after the first touch can de-classify it.
gated_either() { # $1 rel  (empty-array-safe expansions for bash 3.2 `set -u`)
  local rel="$1"
  path_matches_any "$rel" ${EXCLUDE_GLOBS[@]+"${EXCLUDE_GLOBS[@]}"} \
    || { path_matches_any "$rel" ${PRODUCT_GLOBS[@]+"${PRODUCT_GLOBS[@]}"} && return 0; }
  path_matches_any "$rel" ${BASE_EXCLUDE[@]+"${BASE_EXCLUDE[@]}"} \
    || { path_matches_any "$rel" ${BASE_PRODUCT[@]+"${BASE_PRODUCT[@]}"} && return 0; }
  return 1
}

# Emit (NUL) every path that differs from <head> in the current tree (committed-since-
# head OR staged OR unstaged — `git diff <head>` compares head to the WORKING TREE, so
# a committed change still shows) plus untracked files, filtered to gated_either. Caller
# must have loaded current + baseline globs. head=UNBORN => diff the empty tree. Inner
# `| while` only printfs (no `return`), so the subshell is harmless.
emit_changed_z() { # $1 root  $2 head
  local root="$1" head="$2" rel diffref="$2"
  [ "$head" = "UNBORN" ] && diffref=$(git -C "$root" hash-object -t tree /dev/null 2>/dev/null)
  { [ -n "$diffref" ] && git -C "$root" diff --name-only --no-renames -z "$diffref" 2>/dev/null
    git -C "$root" ls-files --others --exclude-standard -z 2>/dev/null; } \
  | while IFS= read -r -d '' rel; do
      [ -n "$rel" ] && gated_either "$rel" && printf '%s\0' "$rel"
    done
}

# True (0) iff <rel> is recorded in baseline-paths AND its current content hash matches
# the recorded one (i.e. a pre-existing change untouched this session). A re-edit changes
# the hash => not unchanged => the caller blocks. Not recorded => not unchanged.
baseline_unchanged() { # $1 basepaths-file  $2 root  $3 rel
  [ -r "$1" ] || return 1
  local p h cur; cur=$(path_hash "$2" "$3")
  while IFS= read -r -d '' p && IFS= read -r -d '' h; do
    [ "$p" = "$3" ] && { [ "$h" = "$cur" ] && return 0; return 1; }
  done < "$1"
  return 1
}

# True (0) iff this session changed a gated path that was NOT already changed (same
# content) at the baseline — i.e. real new gated work, committed or in the worktree.
# Read-only, rejected, reverted/stashed-to-baseline, and untouched-pre-existing-dirty
# sessions yield no such path => return 1 (allow). No baseline (state write failed) =>
# conservative fallback to gated_dirty. `< <(...)` keeps the loop in this shell so
# `return` exits the function.
session_gated_changed() { # $1 root  $2 state-dir  $3 sidf
  local root="$1" sd="$2" sidf="$3" head rel
  [ -r "$sd/s.$sidf.basehead" ] || { gated_dirty "$root"; return; }
  head=$(cat "$sd/s.$sidf.basehead" 2>/dev/null)
  load_globs "$root"
  load_base_globs "$sd/s.$sidf.baseglobs" "$sd/s.$sidf.baseexcl"
  while IFS= read -r -d '' rel; do
    [ -n "$rel" ] || continue
    baseline_unchanged "$sd/s.$sidf.basepaths" "$root" "$rel" && continue
    return 0
  done < <(emit_changed_z "$root" "$head")
  return 1
}

# ACTOR-PRECISE variant for SubagentStop: true (0) iff a gated path THIS subagent
# actually touched (its per-agent .touched list of Edit/Write paths) is among the
# session's newly-changed gated paths. This is the real isolation — session_gated_changed
# alone would blame a subagent that merely ATTEMPTED a gated edit for a SIBLING's change.
# A subagent whose only activity was a Bash write (no .touched paths, sentinel only) is
# NOT path-attributable, so it is NOT blocked here (the Bash heuristic is advisory by
# design; the session Stop + `ci` remain the backstop for those). No per-agent touched
# file => nothing to attribute => allow. No baseline (state write failed) => CANNOT
# attribute precisely, so ALLOW (return 1) rather than falling back to the session-wide
# check, which would re-introduce the sibling-blame this function exists to prevent.
# The touched list is NUL-delimited (paths may contain newlines/spaces) and membership is
# tested by exact byte-equality, so no substring/line-fragment can cross-attribute.
agent_touched_has() { # $1 touched-file(NUL-delimited)  $2 rel  -> 0 iff exact member
  local p
  [ -r "$1" ] || return 1
  while IFS= read -r -d '' p; do [ "$p" = "$2" ] && return 0; done < "$1"
  return 1
}
agent_gated_changed() { # $1 root  $2 state-dir  $3 sidf  $4 per-agent-touched-file
  local root="$1" sd="$2" sidf="$3" tf="$4" head rel
  [ -r "$sd/s.$sidf.basehead" ] || return 1   # no baseline => not attributable => allow
  [ -r "$tf" ] || return 1   # only a .bashwrite sentinel (or nothing) => not attributable
  head=$(cat "$sd/s.$sidf.basehead" 2>/dev/null)
  load_globs "$root"
  load_base_globs "$sd/s.$sidf.baseglobs" "$sd/s.$sidf.baseexcl"
  while IFS= read -r -d '' rel; do
    [ -n "$rel" ] || continue
    baseline_unchanged "$sd/s.$sidf.basepaths" "$root" "$rel" && continue
    # rel is a newly-changed gated path this session — attribute it only if THIS
    # subagent touched that EXACT path (NUL-safe byte-equality, not line/substring match).
    agent_touched_has "$tf" "$rel" && return 0
  done < <(emit_changed_z "$root" "$head")
  return 1
}

# Fallback only (used when no baseline was captured): block iff a gated path is dirty
# in the current tree, using current globs.
gated_dirty() { # $1 root
  local root="$1" rel
  load_globs "$root"
  [ "${#PRODUCT_GLOBS[@]}" -gt 0 ] || return 1
  while IFS= read -r -d '' rel; do
    [ -n "$rel" ] || continue
    path_matches_any "$rel" "${EXCLUDE_GLOBS[@]}" && continue
    path_matches_any "$rel" "${PRODUCT_GLOBS[@]}" && return 0
  done < <(git -C "$root" diff  --name-only --no-renames -z HEAD     2>/dev/null; \
           git -C "$root" diff  --name-only --no-renames -z --cached 2>/dev/null; \
           git -C "$root" ls-files --others --exclude-standard -z    2>/dev/null)
  return 1
}

# =============================================================================
cmd_pretool() {
  have jq || allow_pretool   # can't parse stdin / determine opt-in => silent fail-open
  local input tool fp cmd repo rel
  input=$(cat)
  SID=$(printf '%s' "$input" | jq -r '.session_id // "nosession"' 2>/dev/null)
  AID=$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null)   # subagent => per-agent markers
  AIDKEY=$(printf '%s' "$input" | aid_key_from)                          # injective key (jq, raw JSON)
  tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)

  case "$tool" in
    Edit|Write|MultiEdit|NotebookEdit)
      fp=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // empty' 2>/dev/null)
      [ -n "$fp" ] || allow_pretool
      if [ -e "$fp" ]; then
        local _r; _r=$(realpath "$fp" 2>/dev/null) && [ -n "$_r" ] && fp="$_r"
      else
        local _d; _d=$(realpath "$(dirname -- "$fp")" 2>/dev/null) && [ -n "$_d" ] && fp="$_d/$(basename -- "$fp")"
      fi
      repo=$(opt_in_root "$(dirname -- "$fp")") || allow_pretool   # cheap walk, git only if candidate
      [ "$(cfg_enabled "$repo")" = "enabled" ] || allow_pretool
      rel=${fp#"$repo"/}
      is_gated_path "$repo" "$rel" || allow_pretool
      local strict decision hint sidf sdv
      sidf=$(sid_safe "$SID"); sdv=$(state_dir "$repo" 2>/dev/null)
      # Capture the activity marker + baseline for EVERY gated edit — even under a valid
      # boundary — so the Stop invocation-evidence check can run on the proactive-record
      # path (record owners BEFORE any edit). Without this, a boundary short-circuit here
      # left no marker and Stop silently allowed, fully bypassing the name!=invoke check.
      note_touched "$repo" "$rel"
      # A valid boundary satisfies the PRETOOL gate (allow the edit through); Stop still
      # verifies actual-gated-change + invocation evidence from the marker just captured.
      boundary_valid "$repo" >/dev/null && allow_pretool
      # Explicit per-session exemption (the escape hatch, esp. under strict): if the
      # agent recorded a waiver for a genuinely narrow exempt edit, allow.
      [ -n "$sdv" ] && [ -e "$sdv/s.$sidf.waiver" ] && allow_pretool
      strict=$(cfg_get "$repo" '.strict' 'false')
      hint=$(cfg_get "$repo" '.owner_hint' 'the owning product-rd / stack skill')
      decision="ask"
      # strict hard-deny ONLY if we can actually persist state (else the agent could
      # never unblock => brick); otherwise downgrade to ask.
      [ "$strict" = "true" ] && [ -n "$sdv" ] && decision="deny"
      if [ "$decision" = "deny" ]; then
        emit_pretool_deny "owner-dispatch (strict): blocked edit of gated product code ($rel) in [$repo] — no owner-dispatch boundary this session. INVOKE (load) ${hint} for each touched concern, build the owner-dispatch map, then: bash $SELF record --owners \"<owner1,owner2>\". If this is a genuinely narrow exempt edit (single bug/test/doc/config), record an exemption to proceed: touch \"$sdv/s.$sidf.waiver\" (only after classifying this as a genuinely narrow exempt edit; otherwise invoke + record). (naming an owner is not invoking it.) Clearing THIS owner-dispatch boundary is yours, agent — invoke the owners then run record; don't punt it to the user as an approval. It unblocks only this gate: merge/push/destructive/scope/product decisions still require user authorization." "deny"
      else
        emit_pretool_deny "owner-dispatch: about to edit gated product code ($rel) in [$repo] with no owner-dispatch boundary this session. Per the product-rd owner-dispatch firing gate, INVOKE (load) ${hint} for each touched concern and build the owner-dispatch map BEFORE producing substance — naming an owner is not invoking it. Then record it: bash $SELF record --owners \"<owner1,owner2>\". (Narrow self-contained bug/test/doc/config edits are exempt — proceed if so.) Agent: clearing this is yours — invoke the owners + record; don't punt it to the user as an approval. It clears only this owner-dispatch gate; merge/push/destructive/scope/product decisions still require user authorization." "ask"
      fi
      ;;
    Bash)
      cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
      [ -n "$cmd" ] || allow_pretool
      repo=$(opt_in_root "$PWD") || allow_pretool   # cheap walk, git only if candidate
      [ "$(cfg_enabled "$repo")" = "enabled" ] || allow_pretool
      [ "$(cfg_get "$repo" '.gate_bash' 'true')" = "true" ] || allow_pretool
      # Best-effort write-verb detection (advisory only — many forms slip through).
      printf '%s' "$cmd" | grep -Eq '(>>?|>\||[[:space:]]tee[[:space:]]|sed -i|perl -i|[[:space:]]ed[[:space:]]|[[:space:]]dd[[:space:]]|[[:space:]]cp[[:space:]]|[[:space:]]mv[[:space:]]|[[:space:]]install[[:space:]]|[[:space:]]rsync[[:space:]]|git (apply|restore|checkout)|[[:space:]]patch[[:space:]]|python[0-9.]* -c|<<)' || allow_pretool
      load_globs "$repo"
      [ "${#PRODUCT_GLOBS[@]}" -gt 0 ] || allow_pretool   # empty/malformed globs => clean fail-open
      local matched="" g stem
      for g in "${PRODUCT_GLOBS[@]}"; do
        stem="${g%%/\**}"; stem="${stem%%\**}"
        [ -n "$stem" ] && printf '%s' "$cmd" | grep -Fq "$stem" && { matched=1; break; }
      done
      [ -n "$matched" ] || allow_pretool
      boundary_valid "$repo" >/dev/null && allow_pretool
      # RECORD-ONLY: the Bash write-verb heuristic over-matches read-only commands
      # (`python -c`, heredocs, `>/dev/null`) and can never hard-deny anyway, so raising
      # a user `ask` popup here is pure false-positive noise that trains users to disable
      # the gate. Drop the activity marker for the Stop backstop and ALLOW SILENTLY (emit
      # nothing). Real gated work is caught by the evidence-based Stop hook + `ci`; a real
      # Edit/Write to a gated file still prompts the agent via the Edit branch above.
      note_bashwrite "$repo"
      allow_pretool
      ;;
    *) allow_pretool ;;
  esac
}

# =============================================================================
cmd_stop() {
  have jq || allow_stop   # silent fail-open
  # Handles BOTH the main Stop and SubagentStop (same wrapper; agent_id present only for
  # the latter). NOTE: only inspects the repo under the current PWD; a gated edit made in
  # a DIFFERENT repo during the same session is not re-checked here (documented limit).
  local input repo sd sidf aidf mpfx capkey actor
  input=$(cat)
  SID=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
  # No reliable session id => cannot scope per-session => fail open (never risk a trap).
  [ -n "$SID" ] && [ "$SID" != "nosession" ] || allow_stop
  # agent_id is populated only on SubagentStop. When present, scope the activity marker,
  # block-once cap, and waiver to THIS subagent so (a) a read-only sibling/main thread's
  # dirty gated work never blocks an unrelated subagent, and (b) the subagent's once-cap
  # is independent of the main Stop's. The session-level baseline (capture_baseline keys
  # on SID) is shared and correct for everyone — only the per-actor markers differ.
  AID=$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null)
  AIDKEY=$(printf '%s' "$input" | aid_key_from)   # injective key (jq, raw JSON) — see globals
  local transcript agent_transcript empty_is_missing="false"
  if [ -n "$AID" ]; then
    # Claude's SubagentStop carries BOTH paths: transcript_path is the controller/main
    # session; agent_transcript_path is this worker. Only the latter can prove that the
    # worker loaded its required skills. Older hosts may omit it; their main-transcript
    # fallback retains legacy empty-set fail-open because it is not worker evidence.
    agent_transcript=$(printf '%s' "$input" | jq -r '.agent_transcript_path // empty' 2>/dev/null)
    if [ -n "$agent_transcript" ]; then
      transcript="$agent_transcript"
      empty_is_missing="true"
    else
      transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
    fi
  else
    transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
  fi
  repo=$(opt_in_root "$PWD") || allow_stop
  [ "$(cfg_enabled "$repo")" = "enabled" ] || allow_stop
  sd=$(state_dir "$repo") || allow_stop
  sidf=$(sid_safe "$SID")
  if [ -n "$AID" ]; then mpfx="s.$sidf.a.$AIDKEY"; else mpfx="s.$sidf"; fi
  capkey="$mpfx.blocked"
  [ -r "$sd/$mpfx.touched" ] || [ -r "$sd/$mpfx.bashwrite" ] || allow_stop  # no activity by this actor
  # Invocation-evidence check (name != invoke): a valid boundary normally satisfies the
  # gate — BUT if it recorded owners that were never actually invoked (loaded) this
  # session (per the transcript), the "record" was a bare name, not a real dispatch.
  # Block ONCE (same cap/waiver safety) to surface it. Fail-open: no transcript / no
  # un-invoked owner / parse gap => the boundary satisfies as before.
  if boundary_valid "$repo" >/dev/null; then
    local bdir bf missing
    bdir=$(boundary_dir "$repo" 2>/dev/null); bf="$bdir/boundary.json"
    missing=$(owners_not_invoked "$bf" "$transcript" "$empty_is_missing" 2>/dev/null)
    if [ -z "$missing" ]; then allow_stop; fi                       # all recorded owners were invoked (or unverifiable)
    # Same no-trap safety as the boundary-missing block: only block a session/actor that
    # ACTUALLY changed gated code this session (not a reverted edit or a Bash-heuristic
    # over-match). This preserves the prior invariant that a no-change session is never
    # blocked, even though a valid boundary exists.
    if [ -n "$AID" ]; then
      agent_gated_changed "$repo" "$sd" "$sidf" "$sd/$mpfx.touched" || allow_stop
    else
      session_gated_changed "$repo" "$sd" "$sidf" || allow_stop
    fi
    [ -e "$sd/s.$sidf.waiver" ] && allow_stop
    [ -n "$AID" ] && [ -e "$sd/$mpfx.waiver" ] && allow_stop
    [ -e "$sd/$capkey" ] && allow_stop
    safe_put "$sd/$capkey" "1" || allow_stop
    [ -r "$sd/$capkey" ] || allow_stop
    emit_stop_block "owner-dispatch: recorded owner(s) [$missing] in [$repo] but this actor's transcript shows they were never invoked (loaded) — naming an owner is not invoking it. Continue the same actor now: invoke each named owner skill, re-check the work against its rules, repair any miss, and re-record with: bash $SELF record --owners \"<owners-you-actually-invoked>\". If [$missing] is a non-skill reference (not an invocable skill), correct the record and proceed. (Fires at most once per actor per session.) This recovery is the agent's job; do not ask the user to perform it."
  fi
  [ -e "$sd/s.$sidf.waiver" ] && allow_stop          # session-level waiver suppresses both
  [ -n "$AID" ] && [ -e "$sd/$mpfx.waiver" ] && allow_stop  # per-subagent waiver
  [ -e "$sd/$capkey" ] && allow_stop                 # already blocked once for this actor
  # Evidence gate: block only if this session actually changed a gated path, judged by
  # diffing the current WORKING TREE against the baseline snapshot taken at the first
  # touch. This blocks real new gated work whether it ended up committed or dirty (the
  # worktree reflects committed content too), while a read-only, rejected, reverted/
  # stashed-to-baseline, or untouched-pre-existing-dirty session produces no NEW gated
  # path and is allowed (no false trap). Design boundary: Stop inspects the WORKTREE, so
  # gated work that lives ONLY in the index/HEAD with a worktree deliberately restored to
  # baseline (`git add` + `git restore --worktree`, or commit + `git checkout <base> --`),
  # or a write the Bash heuristic never recorded (`node -e …`), is out of this nudge's
  # reach — the reliable `ci` subcommand (diffs base..HEAD at commit/merge) is the gate
  # for those. Stop is a fast in-session nudge, not the enforcement boundary.
  # Evidence gate — actor-precise: a subagent blocks only for a gated path IT touched
  # (not a sibling's); the main session uses the session-wide check.
  if [ -n "$AID" ]; then
    agent_gated_changed "$repo" "$sd" "$sidf" "$sd/$mpfx.touched" || allow_stop
  else
    session_gated_changed "$repo" "$sd" "$sidf" || allow_stop
  fi
  # Persist the cap FIRST; if we can't, fail open (never block forever on a RO FS).
  safe_put "$sd/$capkey" "1" || allow_stop
  [ -r "$sd/$capkey" ] || allow_stop
  local hint; hint=$(cfg_get "$repo" '.owner_hint' 'the owning product-rd / stack skill')
  [ -n "$AID" ] && actor="this subagent" || actor="this session"
  # Distinguish "never recorded" from "recorded, then expired": reporting an expired record
  # as absent sends diagnosis after a record that was in fact written.
  local why lead; why=$(boundary_state "$repo")
  case "$why" in
    expired)
      lead="edited gated product code in [$repo], where an owner-dispatch boundary exists but expired before this actor finished (it may have been recorded by an earlier actor; boundaries are time-bounded — re-record to extend)" ;;
    discontinuous)
      lead="edited gated product code in [$repo], where an owner-dispatch boundary exists but was recorded on a different line of history (a branch switch, reset, amend, or rebase moved HEAD off it) — that record covers different work, so re-record for this one" ;;
    *)
      lead="edited gated product code in [$repo] but never recorded an owner-dispatch boundary" ;;
  esac
  emit_stop_block "owner-dispatch: $actor $lead. Before finishing: confirm you invoked ${hint} for each touched concern (not just named it). If you did the work, record it — bash $SELF record --owners \"<owners>\"; if this delivery is genuinely exempt (narrow bug/test/doc), waive — touch \"$sd/$mpfx.waiver\". (Fires at most once per actor per session.) Clearing this is yours, agent — invoke + record; don't punt it to the user as an approval (it clears only this gate, not merge/push/destructive actions)."
}

# =============================================================================
# Standalone invocation-evidence check (also the Stop hook's mechanism, exposed for
# testing/CI). Given a comma owner list and a transcript, report which skill-shaped
# owners were never invoked. Exit 0 = all invoked / unverifiable (fail-open); exit 3
# = at least one skill-shaped owner was recorded but never invoked.
cmd_verify_invocations() {
  have jq || { echo "verify-invocations: jq required" >&2; return 0; }   # fail-open
  local owners="" transcript="" empty_is_missing="false"
  while [ $# -gt 0 ]; do
    case "$1" in
      --owners) owners="${2:-}"; shift 2 ;;
      --transcript) transcript="${2:-}"; shift 2 ;;
      --empty-is-missing) empty_is_missing="true"; shift ;;
      *) shift ;;
    esac
  done
  [ -n "$owners" ] || { echo "verify-invocations: --owners required" >&2; return 2; }
  [ -n "$transcript" ] && [ -r "$transcript" ] || { echo "verify-invocations: transcript unreadable => unverifiable (fail-open)"; return 0; }
  # Reuse owners_not_invoked by synthesizing a minimal boundary json.
  local tmp; tmp=$(mktemp "${TMPDIR:-/tmp}/od-vi.XXXXXX") || return 0
  jq -nc --arg o "$owners" '{touched_owners:($o|split(",")|map(gsub("^\\s+|\\s+$";"")))}' > "$tmp" 2>/dev/null
  local missing; missing=$(owners_not_invoked "$tmp" "$transcript" "$empty_is_missing" 2>/dev/null)
  rm -f "$tmp"
  if [ -n "$missing" ]; then
    echo "verify-invocations: recorded but NEVER invoked: $missing"
    return 3
  fi
  echo "verify-invocations: all skill-shaped owners were invoked (or unverifiable)"
  return 0
}

cmd_record() {
  have jq && have git || { echo "owner-dispatch record: jq+git required" >&2; return 1; }
  local owners="" artifact="" ttl=28800
  while [ $# -gt 0 ]; do
    case "$1" in
      --owners) owners="${2:-}"; shift 2 ;;
      --artifact) artifact="${2:-}"; shift 2 ;;
      --ttl) ttl="${2:-28800}"; shift 2 ;;
      *) shift ;;
    esac
  done
  [ -n "$owners" ] || { echo "owner-dispatch record: --owners \"a,b\" required (the owner skills you actually invoked)" >&2; return 2; }
  local repo; repo=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "owner-dispatch record: not in a git repo" >&2; return 2; }
  local sd; sd=$(state_dir "$repo") || { echo "owner-dispatch record: state dir unavailable/unsafe" >&2; return 1; }
  local now exp head json gdir
  now=$(date +%s); exp=$((now + ttl)); head=$(current_head "$repo")
  # Repository identity for validation. `repo_root` stays for diagnostics (it says WHICH
  # worktree recorded), but it must not be the key: it differs per worktree and vanishes
  # when that worktree is cleaned up after merge.
  gdir=$(boundary_dir "$repo") || { echo "owner-dispatch record: cannot resolve git dir" >&2; return 1; }
  json=$(jq -nc --arg repo "$repo" --arg head "$head" --arg owners "$owners" \
        --arg artifact "$artifact" --argjson created "$now" --argjson expires "$exp" \
        --arg gdir "$gdir" \
        --arg sid "${CLAUDE_SESSION_ID:-${OWNER_DISPATCH_SESSION:-unknown}}" \
        '{repo_root:$repo,repo_git_dir:$gdir,head:$head,touched_owners:($owners|split(",")|map(gsub("^\\s+|\\s+$";""))),artifact:$artifact,created_at:$created,expires_at:$expires,session_id:$sid}' 2>/dev/null) \
    || { echo "owner-dispatch record: encode failed" >&2; return 1; }
  safe_put "$sd/boundary.json" "$json" || { echo "owner-dispatch record: write failed" >&2; return 1; }
  # No cleanup of s.*.touched/blocked: a valid boundary supersedes them (boundary_valid
  # short-circuits before those markers are consulted), so stale per-session markers are
  # inert — and NOT globbing-deleting avoids any raced-symlink delete risk.
  echo "owner-dispatch: boundary recorded for [$repo] @ ${head:0:8} (owners: $owners; expires in $((ttl/3600))h)"
}

# Load product/exclude globs from a config CONTENT string (used for the BASE config).
load_globs_from() { # $1 json-string -> sets ARG_PRODUCT_GLOBS / ARG_EXCLUDE_GLOBS
  ARG_PRODUCT_GLOBS=(); ARG_EXCLUDE_GLOBS=()
  local line
  while IFS= read -r line; do [ -n "$line" ] && ARG_PRODUCT_GLOBS+=("$line"); done < <(printf '%s' "$1" | jq -r '(.product_globs // [])[]' 2>/dev/null)
  while IFS= read -r line; do [ -n "$line" ] && ARG_EXCLUDE_GLOBS+=("$line"); done < <(printf '%s' "$1" | jq -r '(.exclude_globs // [])[]' 2>/dev/null)
  ARG_EXCLUDE_GLOBS+=("**/*.md" ".owner-dispatch.json" ".git/**")
}
# Fail-closed schema check for an ENABLED config: an enabled-but-unusable config
# (product_globs missing / empty / not a string array) would silently gate nothing.
cfg_schema_ok() { # $1 config-json -> 0 if a valid enabled config
  printf '%s' "$1" | jq -e '
    (.enabled==true)
    and ((.product_globs|type)=="array") and ((.product_globs|length)>0)
    and (all(.product_globs[]; (type=="string") and (length>0)))
    and (((.exclude_globs)//[])|type=="array")
    and (((.ci_artifact)//"x")|type=="string")
    and (((.strict)//false)|type=="boolean")
    and (((.gate_bash)//true)|type=="boolean")
  ' >/dev/null 2>&1
}

cmd_ci_python() {
  python3 - "$@" <<'PY'
import fnmatch
import json
import os
import subprocess
import sys


def fail(message, code=2):
    print(message, file=sys.stderr)
    return code


def run_git(args, cwd=None, text=True, check=False):
    result = subprocess.run(
        ["git", *args],
        cwd=cwd,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=text,
    )
    if check and result.returncode != 0:
        raise RuntimeError(args)
    return result


def load_json_text(text):
    if not text:
        return None
    return json.loads(text)


def load_json_file(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def enabled(cfg):
    return bool(isinstance(cfg, dict) and cfg.get("enabled") is True)


def glob_list(cfg, key):
    if not isinstance(cfg, dict):
        return []
    value = cfg.get(key) or []
    return value if isinstance(value, list) else []


def path_matches_any(rel, globs):
    for glob in globs:
        if not glob:
            continue
        # fnmatch's '*' crosses '/', matching bash `case` semantics used above.
        if fnmatch.fnmatchcase(rel, glob):
            return True
        if glob.startswith("**/") and fnmatch.fnmatchcase(rel, glob[3:]):
            return True
    return False


def load_globs(cfg):
    product = [g for g in glob_list(cfg, "product_globs") if isinstance(g, str) and g]
    exclude = [g for g in glob_list(cfg, "exclude_globs") if isinstance(g, str) and g]
    exclude.extend(["**/*.md", ".owner-dispatch.json", ".git/**"])
    return product, exclude


def is_gated_path(rel, cfg):
    product, exclude = load_globs(cfg)
    if not product:
        return False
    if path_matches_any(rel, exclude):
        return False
    return path_matches_any(rel, product)


def schema_ok(cfg):
    if not isinstance(cfg, dict) or cfg.get("enabled") is not True:
        return False
    product = cfg.get("product_globs")
    exclude = cfg.get("exclude_globs", [])
    ci_artifact = cfg.get("ci_artifact", "x")
    return (
        isinstance(product, list)
        and len(product) > 0
        and all(isinstance(x, str) and len(x) > 0 for x in product)
        and isinstance(exclude, list)
        and (ci_artifact is None or isinstance(ci_artifact, str))
        and isinstance(cfg.get("strict", False), bool)
        and isinstance(cfg.get("gate_bash", True), bool)
    )


def main(argv):
    base = ""
    if len(argv) >= 2 and argv[0] == "--base":
        base = argv[1]

    top = run_git(["rev-parse", "--show-toplevel"], check=False)
    if top.returncode != 0:
        return fail("owner-dispatch ci: not a git repo — FAIL-CLOSED (2)")
    repo = top.stdout.strip()

    if not base:
        default_branch = os.environ.get("CI_DEFAULT_BRANCH") or "origin/main"
        mb = run_git(["merge-base", "HEAD", default_branch], cwd=repo, check=False)
        base = mb.stdout.strip()
    if not base:
        return fail("owner-dispatch ci: could not determine a diff base — pass --base <sha>. FAIL-CLOSED (2).")
    if run_git(["rev-parse", "--verify", f"{base}^{{commit}}"], cwd=repo).returncode != 0:
        return fail(f"owner-dispatch ci: invalid base '{base}' — FAIL-CLOSED (2)")

    head_cfg = None
    head_cfg_path = os.path.join(repo, ".owner-dispatch.json")
    if os.path.exists(head_cfg_path):
        try:
            head_cfg = load_json_file(head_cfg_path)
        except (OSError, json.JSONDecodeError):
            head_cfg = None

    base_show = run_git(["show", f"{base}:.owner-dispatch.json"], cwd=repo)
    base_cfg_text = base_show.stdout if base_show.returncode == 0 else ""
    try:
        base_cfg = load_json_text(base_cfg_text)
    except json.JSONDecodeError:
        base_cfg = None

    head_enabled = enabled(head_cfg)
    base_enabled = enabled(base_cfg)

    diff = run_git(["diff", "-z", "--name-only", base, "HEAD"], cwd=repo, text=False)
    if diff.returncode != 0:
        return fail("owner-dispatch ci: diff failed — FAIL-CLOSED (2)")
    changed = [p.decode("utf-8", "surrogateescape") for p in diff.stdout.split(b"\0") if p]

    base_product, base_exclude = load_globs(base_cfg)
    gated = []
    for rel in changed:
        if is_gated_path(rel, head_cfg):
            gated.append(rel)
            continue
        if base_product and not path_matches_any(rel, base_exclude) and path_matches_any(rel, base_product):
            gated.append(rel)

    gated_disp = "".join(f" {p}" for p in gated)

    tracked = run_git(["ls-files", "--error-unmatch", ".owner-dispatch.json"], cwd=repo).returncode == 0
    if tracked and not isinstance(head_cfg, dict):
        return fail("owner-dispatch ci: FAIL-CLOSED (2) — tracked .owner-dispatch.json is malformed or non-object JSON.")

    if base_enabled and not head_enabled:
        if gated:
            print(
                f"owner-dispatch ci: FAIL (1) — this change disables/removes the gate AND touches gated product code:{gated_disp}",
                file=sys.stderr,
            )
            print("  Decommission the gate in a separate config-only change, or keep it enabled.", file=sys.stderr)
            return 1
        print("owner-dispatch ci: gate disabled/removed in a config-only change — allowed (clean decommit)")
        return 0

    if not head_enabled:
        print("owner-dispatch ci: not opted in — skip")
        return 0

    if not schema_ok(head_cfg):
        return fail(
            "owner-dispatch ci: FAIL-CLOSED (2) — enabled .owner-dispatch.json is schema-invalid "
            "(product_globs must be a non-empty array of non-empty strings; strict/gate_bash boolean; ci_artifact a string)."
        )

    if not gated:
        print("owner-dispatch ci: no gated product files changed — ok")
        return 0

    artifact_value = head_cfg.get("ci_artifact", "design/owner-dispatch-map.md")
    if artifact_value is None:
        artifact_value = "design/owner-dispatch-map.md"
    artifact = str(artifact_value)
    if artifact.startswith("./"):
        artifact = artifact[2:]
    if artifact.startswith("/") or ".." in artifact.split("/") or artifact == "":
        print(
            f"owner-dispatch ci: FAIL (1) — unsafe ci_artifact path '{artifact}' (must be repo-relative, no '..' path component).",
            file=sys.stderr,
        )
        return 1
    if artifact == ".owner-dispatch.json":
        print("owner-dispatch ci: FAIL (1) — ci_artifact must not be the config file.", file=sys.stderr)
        return 1

    head_product, _ = load_globs(head_cfg)
    if head_product and path_matches_any(artifact, head_product):
        print(
            f"owner-dispatch ci: FAIL (1) — ci_artifact '{artifact}' matches product_globs; the map must be a dedicated non-product file.",
            file=sys.stderr,
        )
        return 1
    if artifact in gated:
        print(
            f"owner-dispatch ci: FAIL (1) — ci_artifact '{artifact}' is itself a gated changed file; use a dedicated map.",
            file=sys.stderr,
        )
        return 1

    artifact_path = os.path.join(repo, artifact)
    if not os.path.exists(artifact_path) or os.path.getsize(artifact_path) <= 0:
        print(
            f"owner-dispatch ci: FAIL (1) — gated product files changed:{gated_disp} but no owner-dispatch map at '{artifact}'.",
            file=sys.stderr,
        )
        return 1
    if artifact not in changed:
        print(
            f"owner-dispatch ci: FAIL (1) — '{artifact}' exists but was not updated in this change (stale) for gated files:{gated_disp}",
            file=sys.stderr,
        )
        return 1

    print(f"owner-dispatch ci: gated files changed and '{artifact}' updated in this change — ok")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
PY
}

# =============================================================================
# Host-agnostic BACKSTOP for product repos. Unlike the in-session hooks (which fail
# OPEN so a bug never bricks editing), CI fails CLOSED: any inability to verify is a
# failure, because this is the gate of last resort. Exit: 0 ok / not-opted / clean
# decommit; 1 violation; 2 could-not-verify (a gating job must treat 2 as failure).
cmd_ci() {
  have git || { echo "owner-dispatch ci: git required to verify — FAIL-CLOSED (2)" >&2; return 2; }
  if ! have jq; then
    have python3 || { echo "owner-dispatch ci: jq missing and python3 fallback unavailable — FAIL-CLOSED (2)" >&2; return 2; }
    cmd_ci_python "$@"; return $?
  fi
  local base=""; [ "${1:-}" = "--base" ] && base="${2:-}"
  local repo; repo=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "owner-dispatch ci: not a git repo — FAIL-CLOSED (2)" >&2; return 2; }
  [ -n "$base" ] || base=$(git merge-base HEAD "${CI_DEFAULT_BRANCH:-origin/main}" 2>/dev/null)
  [ -n "$base" ] || { echo "owner-dispatch ci: could not determine a diff base — pass --base <sha>. FAIL-CLOSED (2)." >&2; return 2; }
  git rev-parse --verify "$base^{commit}" >/dev/null 2>&1 || { echo "owner-dispatch ci: invalid base '$base' — FAIL-CLOSED (2)" >&2; return 2; }

  local head_enabled base_cfg base_enabled
  head_enabled=$([ "$(cfg_enabled "$repo")" = "enabled" ] && echo 1 || echo 0)
  base_cfg=$(git show "$base:.owner-dispatch.json" 2>/dev/null)
  base_enabled=$(printf '%s' "$base_cfg" | jq -er 'if (.enabled // false) then 1 else 0 end' 2>/dev/null || echo 0)
  # Direct two-tree diff against the EXPLICIT base (NOT three-dot, which recomputes a
  # merge-base and breaks on shallow/disconnected CI clones). NUL-delimited via a temp
  # file (NUL can't survive a shell var) so paths with spaces/newlines classify exactly.
  local CHANGED=() difftmp rel
  difftmp=$(mktemp 2>/dev/null) || { echo "owner-dispatch ci: mktemp failed — FAIL-CLOSED (2)" >&2; return 2; }
  git diff -z --name-only "$base" HEAD > "$difftmp" 2>/dev/null || { rm -f "$difftmp"; echo "owner-dispatch ci: diff failed — FAIL-CLOSED (2)" >&2; return 2; }
  while IFS= read -r -d '' rel; do CHANGED+=("$rel"); done < "$difftmp"
  rm -f "$difftmp"

  # Classify changed files against the UNION of base-config and head-config product
  # globs (base = the contract in force before this change), so an MR cannot dodge the
  # gate by shrinking product_globs / widening excludes in the same change.
  load_globs_from "$base_cfg"
  # bash-3.2-safe array copies (expanding an empty array under `set -u` errors on 3.2).
  local base_product=() base_exclude=() GATED=()
  [ "${#ARG_PRODUCT_GLOBS[@]}" -gt 0 ] && base_product=("${ARG_PRODUCT_GLOBS[@]}")
  [ "${#ARG_EXCLUDE_GLOBS[@]}" -gt 0 ] && base_exclude=("${ARG_EXCLUDE_GLOBS[@]}")
  if [ "${#CHANGED[@]}" -gt 0 ]; then
    for rel in "${CHANGED[@]}"; do
      if is_gated_path "$repo" "$rel"; then GATED+=("$rel"); continue; fi
      if [ "${#base_product[@]}" -gt 0 ] && ! path_matches_any "$rel" "${base_exclude[@]}" && path_matches_any "$rel" "${base_product[@]}"; then
        GATED+=("$rel")
      fi
    done
  fi
  local n_gated=${#GATED[@]} gated_disp=""
  [ "$n_gated" -gt 0 ] && gated_disp=$(printf ' %s' "${GATED[@]}")

  # A TRACKED-but-unparseable config is "cannot verify" (fail-closed), NOT "not opted
  # in" and NOT a clean decommit: cfg_enabled returns empty for malformed JSON. This MUST
  # run BEFORE the decommit branch, else malforming an enabled config in a config-only
  # change (n_gated=0) would be mistaken for a clean removal and pass.
  if git -C "$repo" ls-files --error-unmatch .owner-dispatch.json >/dev/null 2>&1; then
    jq -e 'type=="object"' "$repo/.owner-dispatch.json" >/dev/null 2>&1 || {
      echo "owner-dispatch ci: FAIL-CLOSED (2) — tracked .owner-dispatch.json is malformed or non-object JSON." >&2; return 2; }
  fi
  # Anti-bypass: turning the gate OFF (disable/REMOVE) is allowed ONLY in a change that
  # touches NO gated product code — a clean, separately-reviewed decommit. (A malformed
  # config was already rejected above, so only a genuine disable/removal reaches here.)
  if [ "$base_enabled" = "1" ] && [ "$head_enabled" != "1" ]; then
    if [ "$n_gated" -gt 0 ]; then
      echo "owner-dispatch ci: FAIL (1) — this change disables/removes the gate AND touches gated product code:$gated_disp" >&2
      echo "  Decommission the gate in a separate config-only change, or keep it enabled." >&2
      return 1
    fi
    echo "owner-dispatch ci: gate disabled/removed in a config-only change — allowed (clean decommit)"
    return 0
  fi
  [ "$head_enabled" = "1" ] || { echo "owner-dispatch ci: not opted in — skip"; return 0; }
  # Fail-closed: an enabled config must be schema-valid, else it gates nothing silently.
  cfg_schema_ok "$(cat "$repo/.owner-dispatch.json" 2>/dev/null)" || {
    echo "owner-dispatch ci: FAIL-CLOSED (2) — enabled .owner-dispatch.json is schema-invalid (product_globs must be a non-empty array of non-empty strings; strict/gate_bash boolean; ci_artifact a string)." >&2; return 2; }
  [ "$n_gated" -gt 0 ] || { echo "owner-dispatch ci: no gated product files changed — ok"; return 0; }

  local artifact; artifact=$(cfg_get "$repo" '.ci_artifact' 'design/owner-dispatch-map.md')
  artifact=${artifact#./}   # normalize to git's path form (git reports 'design/x', not './design/x')
  case "$artifact" in
    /*|"") echo "owner-dispatch ci: FAIL (1) — unsafe ci_artifact path '$artifact' (must be repo-relative, no '..' path component)." >&2; return 1 ;;
  esac
  case "/$artifact/" in
    */../*) echo "owner-dispatch ci: FAIL (1) — unsafe ci_artifact path '$artifact' (must be repo-relative, no '..' path component)." >&2; return 1 ;;
  esac
  # The map must be a DEDICATED artifact — not the config and not product code, or a
  # change to that very file would falsely satisfy the gate.
  [ "$artifact" = ".owner-dispatch.json" ] && { echo "owner-dispatch ci: FAIL (1) — ci_artifact must not be the config file." >&2; return 1; }
  load_globs "$repo"
  if [ "${#PRODUCT_GLOBS[@]}" -gt 0 ] && path_matches_any "$artifact" "${PRODUCT_GLOBS[@]}"; then
    echo "owner-dispatch ci: FAIL (1) — ci_artifact '$artifact' matches product_globs; the map must be a dedicated non-product file." >&2; return 1
  fi
  for rel in "${GATED[@]}"; do
    [ "$rel" = "$artifact" ] && { echo "owner-dispatch ci: FAIL (1) — ci_artifact '$artifact' is itself a gated changed file; use a dedicated map." >&2; return 1; }
  done
  if [ ! -s "$repo/$artifact" ]; then
    echo "owner-dispatch ci: FAIL (1) — gated product files changed:$gated_disp but no owner-dispatch map at '$artifact'." >&2
    return 1
  fi
  # Anti-stale: the artifact must be one of the files actually changed in this diff.
  local art_updated=0
  for rel in "${CHANGED[@]}"; do [ "$rel" = "$artifact" ] && { art_updated=1; break; }; done
  if [ "$art_updated" != "1" ]; then
    echo "owner-dispatch ci: FAIL (1) — '$artifact' exists but was not updated in this change (stale) for gated files:$gated_disp" >&2
    return 1
  fi
  # RESIDUAL (documented): CI checks the map EXISTS, is updated in-change, and sits on
  # a safe repo-relative path. It does NOT validate the map's semantic content (that the
  # listed owners actually cover the gated files) — that stays reviewer/owner judgment.
  echo "owner-dispatch ci: gated files changed and '$artifact' updated in this change — ok"
}

cmd_status() {
  # Resolve exactly like the enforcement paths do (opt_in_root realpath's to the physical
  # path, "to match git's toplevel"). Using the raw logical path here made `status` compare
  # a logical path against the physical repo_root stored by `record`. Whenever the checkout
  # is reached through a symlink so `$PWD` stays logical (macOS /tmp among them; entering by
  # the physical path is unaffected), it reported absent/stale for a perfectly valid
  # boundary while pretool allowed the edit — the diagnostic surface contradicting the gate
  # it exists to explain. Fall back to the older resolution only when not opted in, so the
  # "opted-in: no" output still works outside a gated repo.
  local repo; repo=$(opt_in_root "$PWD") || repo=$(find_config_dir "$PWD") || repo=$(git rev-parse --show-toplevel 2>/dev/null)
  [ -n "${repo:-}" ] || { echo "not in a git repo / no opt-in found"; return 0; }
  echo "repo:     $repo"
  echo "opted-in: $([ "$(cfg_enabled "$repo")" = enabled ] && echo yes || echo 'no (no/disabled/malformed .owner-dispatch.json)')"
  echo "strict:   $(cfg_get "$repo" '.strict' 'false')"
  echo "HEAD:     $(current_head "$repo")"
  # Report the actual state, not a valid/not-valid collapse: `status` is the command an
  # agent runs to diagnose a Stop block, so it must distinguish "never recorded" from
  # "recorded, then expired" for the same reason the Stop message does.
  echo "boundary: $(boundary_state "$repo")"
}

main() {
  local sub="${1:-}"; shift || true
  case "$sub" in
    pretool) cmd_pretool "$@" ;;
    stop)    cmd_stop "$@" ;;
    record)  cmd_record "$@" ;;
    verify-invocations) cmd_verify_invocations "$@" ;;
    ci)      cmd_ci "$@" ;;
    status)  cmd_status "$@" ;;
    # Introspection: where boundary state for a root actually lands. Exists so the
    # read/write path can be ASSERTED across the worktree boundary rather than
    # inferred, and so a human debugging a Stop block can compare two roots directly.
    boundary-path) boundary_dir "${1:-$PWD}" ;;
    *) echo "usage: owner-dispatch.sh {pretool|stop|record --owners \"a,b\"|ci [--base REF]|status|boundary-path [root]}" >&2; return 2 ;;
  esac
}
main "$@"
