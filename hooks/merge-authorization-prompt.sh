#!/usr/bin/env bash
# UserPromptSubmit — merge-authorization release-valve armer.
#
# WHY: guard-merge-authorization.sh hard-denies platform merge commands, but
# the prose contract (bootstrap 硬纪律 1 / worktree-isolation 合并执行协议)
# says the USER's explicit merge directive ("合并"/"merge"/"land it") IS the
# authorization. PreToolUse hooks cannot see the conversation, so this hook
# is the machine bridge: it observes the harness-delivered human prompt and
# arms a session-scoped grant sentinel (one-shot, or counted batch) that the
# merge guard consumes at its would-deny moment (platform merge shapes only;
# direct default-branch pushes stay hard-denied there).
#
# Semantics (spec: specs/007-merge-gate-user-directive-valve/spec.md):
#   - Every user prompt CLEARS any pending sentinel first — authorization
#     always reflects the LATEST user message, never an earlier one.
#   - The sentinel is re-armed only when the whole (single-line, trimmed)
#     message is a standalone explicit merge directive: 合并 / merge /
#     land it / 合并吧 / 请直接合并 / merge !546 / 可以合并 / 合并这个MR …
#     ("合了" is deliberately NOT a directive: past-tense "已经合了" ambiguity.)
#     (anchored match below). Prose that merely CONTAINS "merge", negations
#     (别合并 / 不要merge), and multi-line messages never arm.
#   - BATCH form (spec: specs/008-batch-merge-grant/spec.md): a standalone
#     "批量合并 <N>" / "batch merge <N>" arms a COUNTED grant
#     (`armed batch N`); the guard consumes ONE unit per platform merge —
#     for dependency-chain / multi-repo releases where per-MR
#     re-authorization makes the user the bottleneck. The count is REQUIRED,
#     1–999, no leading zero (blast radius stays a user decision); a bare
#     "批量合并" never arms. Clear-on-any-new-prompt applies unchanged: any
#     later user message revokes the remaining units.
#   - False negatives are safe (user re-issues a standalone "合并");
#     false positives are not — keep the pattern anchored and narrow.
#
# Trust root: the harness-delivered human prompt. An agent writing this
# sentinel via Bash is deliberate circumvention — same declared out-of-scope
# class as eval/interpreter obfuscation in the merge guard's header; the
# prose layer (bootstrap 安全硬边界) covers it. The 0700 dir + uid-suffixed
# path close the cross-user spoof on shared hosts.
#
# Degrade: jq missing / no session_id / unwritable tmp → exit 0 silently
# (valve stays inert; the merge guard then keeps its hard deny — fail-closed).

set -f

input=$(cat)

command -v jq >/dev/null 2>&1 || exit 0

prompt=$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null)
sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$sid" ] && exit 0
case "$sid" in */*|*..*) exit 0 ;; esac   # session_id is a path component

# KEEP IN SYNC with hooks/guard-merge-authorization.sh (sentinel path, lock
# protocol).
auth_dir="${TMPDIR:-/tmp}/ccl-skills-merge-auth-$(id -u)"
sentinel="$auth_dir/$sid"
lock_dir="$auth_dir/$sid.lock"

# Per-session critical-section lock, shared with the guard's consume/re-arm
# path. Closes the revocation race (review P1): without it, a user prompt
# arriving while the guard is between its atomic consume (mv) and its batch
# re-create would find no sentinel to remove, and the guard would then
# resurrect `armed batch N-1` — defeating the documented any-new-message
# kill switch. Critical sections are milliseconds; a lock dir that is not
# fresh (≥1 min) is a crashed holder and gets broken.
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

locked=0
if [ -d "$auth_dir" ] || mkdir -p "$auth_dir" 2>/dev/null; then
  chmod 700 "$auth_dir" 2>/dev/null
  if acquire_lock; then
    locked=1
    trap 'rmdir "$lock_dir" 2>/dev/null' EXIT
  fi
fi

# Latest-message semantics: any new prompt invalidates a pending grant.
# Revocation runs even when the lock could not be acquired (removing a
# grant is always the safe direction); ARMING below additionally requires
# the lock (arming into an unknown interleaving is not safe — false
# negatives are fine, the user re-issues the directive).
rm -f "$sentinel" 2>/dev/null

[ -z "$prompt" ] && exit 0
# Multi-line messages are never a standalone directive.
case "$prompt" in *$'\n'*) exit 0 ;; esac

trimmed=$(printf '%s' "$prompt" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
# Normalize fullwidth digits ０-９ → 0-9 (challenge R2 P2): a Chinese IME
# naturally yields "批量合并 ３０"; the count grammar/extraction is ASCII.
trimmed=$(printf '%s' "$trimmed" | sed $'s/０/0/g; s/１/1/g; s/２/2/g; s/３/3/g; s/４/4/g; s/５/5/g; s/６/6/g; s/７/7/g; s/８/8/g; s/９/9/g')

# BATCH directive first (patterns are disjoint — the single-directive match
# below has no 批量/batch prefix). Anchored whole-message match: optional
# politeness prefix, 批量合并/批量merge/batch merge, REQUIRED count 1–999
# without leading zero, optional 个/吧 tail, optional trailing punctuation.
# NO free text — "批量合并 30 然后发布" is not a standalone directive.
if printf '%s' "$trimmed" | grep -Eiq \
  '^(请|麻烦|可以|直接|请直接)?[[:space:]]*(批量[[:space:]]*(合并|merge)|batch[[:space:]]+merge)[[:space:]]*([1-9][0-9]{0,2})[[:space:]]*(个|吧)?[[:space:]]*[。．.!！~～]*$'; then
  [ "$locked" = 1 ] || exit 0
  # The counted grant is UNBOUND by design (dependent-repo MRs do not exist
  # yet when the chain starts); the prose duty to merge only the presented
  # release plan stays with the agent (worktree-isolation 合并执行协议).
  n=$(printf '%s' "$trimmed" | grep -Eo '[1-9][0-9]{0,2}' | head -1)
  [ -n "$n" ] && printf 'armed batch %s\n' "$n" >"$sentinel" 2>/dev/null
  exit 0
fi

# Anchored whole-message directive match. Optional politeness prefix,
# optional it/this/吧/一下 tail, optional MR/PR noun, optional !123 / #123 /
# bare MR number, optional trailing punctuation. NO free text allowed —
# anything else in the message means "not a standalone directive".
if printf '%s' "$trimmed" | grep -Eiq \
  '^(请|麻烦|可以|直接|请直接)?[[:space:]]*(合并|merge|land)([[:space:]]+(it|this|that))?[[:space:]]*(吧|一下|掉)?[[:space:]]*((这个|那个|此|the)[[:space:]]*)?(mr|pr)?[[:space:]]*([!#]?[0-9]{1,6})?[[:space:]]*[。．.!！~～]*$'; then
  [ "$locked" = 1 ] || exit 0
  # Number binding: "merge !546" authorizes merging THAT MR/PR only; the
  # guard rejects a released merge whose target id differs (grant intact).
  # A bare "合并"/"merge" grant is unbound (the prose duty to target the
  # discussed MR stays with the agent).
  num=$(printf '%s' "$trimmed" | grep -Eo '[!#]?[0-9]{1,6}' | head -1 | tr -d '!#')
  if [ -n "$num" ]; then
    printf 'armed %s\n' "$num" >"$sentinel" 2>/dev/null
  else
    printf 'armed\n' >"$sentinel" 2>/dev/null
  fi
fi

exit 0
