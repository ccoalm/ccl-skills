#!/usr/bin/env bash
# Deterministic behavior suite for hooks/merge-authorization-prompt.sh
# (the merge-authorization release-valve armer). Self-contained: feeds
# constructed UserPromptSubmit JSON with TMPDIR pointed into a throwaway
# dir and asserts sentinel arming/clearing semantics. Registered in the
# Makefile `test` target and the ccl-skills-hooks-tests CI job.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
HOOK="$SCRIPT_DIR/merge-authorization-prompt.sh"
[ -f "$HOOK" ] || { echo "FAIL: hook not found: $HOOK" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq required for this suite" >&2; exit 1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/merge-auth-prompt-test.XXXXXX")" || exit 1
trap 'rm -rf "$tmp"' EXIT

SID="sess-prompt-test"
AUTH_DIR="$tmp/ccl-skills-merge-auth-$(id -u)"
SENT="$AUTH_DIR/$SID"

pass=0; fail=0

send() { # send <prompt> [sid]
  local p="$1" s="${2-$SID}"
  jq -nc --arg p "$p" --arg s "$s" '{prompt:$p,session_id:$s}' | TMPDIR="$tmp" bash "$HOOK"
}

expect_armed() { # expect_armed <prompt> [expected sentinel content]
  rm -f "$SENT"
  send "$1"
  if [ -f "$SENT" ] && { [ $# -lt 2 ] || [ "$(cat "$SENT")" = "$2" ]; }; then
    pass=$((pass+1))
  else
    fail=$((fail+1)); printf 'FAIL  [want=armed%s got=%s]  %q\n' \
      "${2:+ ($2)}" "$(cat "$SENT" 2>/dev/null || echo not-armed)" "$1" >&2
  fi
  rm -f "$SENT"
}

expect_not_armed() { # expect_not_armed <prompt>
  rm -f "$SENT"
  send "$1"
  if [ ! -f "$SENT" ]; then pass=$((pass+1)); else
    fail=$((fail+1)); printf 'FAIL  [want=not-armed got=armed]  %q\n' "$1" >&2
  fi
  rm -f "$SENT"
}

# --- standalone explicit merge directives ARM the sentinel ---
expect_armed '合并' 'armed'
expect_armed 'merge' 'armed'
expect_armed 'Merge'
expect_armed 'MERGE'
expect_armed '合并吧'
expect_armed '请直接合并'
expect_armed '直接合并'
expect_armed '可以合并'
expect_armed 'land it'
expect_armed 'merge it'
expect_armed 'merge !546' 'armed 546'
expect_armed 'merge 546' 'armed 546'
expect_armed '合并这个MR'
expect_armed '合并 MR' 'armed'
expect_armed '合并 546' 'armed 546'
expect_armed 'merge the pr'

# --- negations / prose / anything with free text must NOT arm ---
expect_not_armed '合了'   # past-tense ambiguity: deliberately not a directive
expect_not_armed '别合并'
expect_not_armed '不要merge'
expect_not_armed '先不合并'
expect_not_armed '先别合并'
expect_not_armed 'merge conflicts 怎么解决'
expect_not_armed 'merge完成后清理worktree'
expect_not_armed '帮我看看这个 merge 请求'
expect_not_armed 'merged'
expect_not_armed 'merging'
expect_not_armed 'landing page 怎么写'
expect_not_armed '把这个功能做完然后合并到主干再发布'
expect_not_armed ''
expect_not_armed '合并
再清理 worktree'   # multi-line is never a standalone directive

# --- whitespace / punctuation tolerance ---
expect_armed '  合并  '
expect_armed '合并。'
expect_armed 'merge!'

# --- batch directive (spec 008): counted grant `armed batch N` ---
expect_armed '批量合并 30' 'armed batch 30'
expect_armed '批量合并30' 'armed batch 30'
expect_armed '批量合并 30 个' 'armed batch 30'
expect_armed 'batch merge 12' 'armed batch 12'
expect_armed '批量合并 ３０' 'armed batch 30'   # fullwidth digits (challenge R2 P2)
expect_armed '批量合并３０' 'armed batch 30'
expect_armed '批量merge 5' 'armed batch 5'
expect_armed '请批量合并 999' 'armed batch 999'
expect_armed '批量合并 1。' 'armed batch 1'
# count is REQUIRED and well-formed: bare/zero/leading-zero/overflow never arm
expect_not_armed '批量合并'
expect_not_armed 'batch merge'
expect_not_armed '批量合并 0'
expect_not_armed '批量合并 007'
expect_not_armed '批量合并 1000'
# negation / free text must NOT arm
expect_not_armed '别批量合并 30'
expect_not_armed '不要批量合并 30'
expect_not_armed '批量合并 30 然后打 tag'
expect_not_armed '批量合并这30个MR怎么样'
expect_not_armed '批量合并
30'   # multi-line never arms

# --- number binding: a named MR/PR number is recorded in the grant ---
rm -f "$SENT"
send 'merge !546'
if [ "$(cat "$SENT" 2>/dev/null)" = "armed 546" ]; then pass=$((pass+1)); else
  fail=$((fail+1)); echo "FAIL  'merge !546' must arm bound to 546, got: $(cat "$SENT" 2>/dev/null)" >&2
fi
rm -f "$SENT"
send '合并'
if [ "$(cat "$SENT" 2>/dev/null)" = "armed" ]; then pass=$((pass+1)); else
  fail=$((fail+1)); echo "FAIL  bare 合并 must arm unbound, got: $(cat "$SENT" 2>/dev/null)" >&2
fi
rm -f "$SENT"

# --- latest-message semantics: a new non-directive prompt CLEARS the grant ---
rm -f "$SENT"
send '合并'
if [ -f "$SENT" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo 'FAIL  arm-before-clear' >&2; fi
send '改一下 README 再说'
if [ ! -f "$SENT" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo 'FAIL  new prompt must clear pending grant' >&2; fi
rm -f "$SENT"

# --- session lock (review P1): arming requires the lock; revocation never
# blocked. A FRESH lock held by a peer suppresses arming (false negative =
# safe); a STALE (≥1 min) lock is a crashed holder and gets broken. ---
LOCK="$AUTH_DIR/$SID.lock"
mkdir -p "$AUTH_DIR"; chmod 700 "$AUTH_DIR"
mkdir "$LOCK"
send '合并'
if [ ! -f "$SENT" ]; then pass=$((pass+1)); else
  fail=$((fail+1)); echo 'FAIL  held fresh lock must suppress arming' >&2
fi
printf 'armed batch 5\n' >"$SENT"
send '停一下'
if [ ! -f "$SENT" ]; then pass=$((pass+1)); else
  fail=$((fail+1)); echo 'FAIL  revocation must run even under a held lock' >&2
fi
rmdir "$LOCK" 2>/dev/null
mkdir "$LOCK"
old_ts=$(date -v-5M +%Y%m%d%H%M 2>/dev/null || date -d '-5 minutes' +%Y%m%d%H%M)
touch -t "$old_ts" "$LOCK"
send '合并'
if [ -f "$SENT" ]; then pass=$((pass+1)); else
  fail=$((fail+1)); echo 'FAIL  stale lock must be broken and arming proceed' >&2
fi
if [ ! -d "$LOCK" ]; then pass=$((pass+1)); else
  fail=$((fail+1)); echo 'FAIL  hook must release the lock on exit' >&2
fi
rm -f "$SENT"

# --- degrade / hostile inputs: no session_id, path-traversal session_id ---
jq -nc '{prompt:"合并"}' | TMPDIR="$tmp" bash "$HOOK"
if [ ! -d "$AUTH_DIR" ] || [ -z "$(ls -A "$AUTH_DIR" 2>/dev/null)" ]; then pass=$((pass+1)); else
  fail=$((fail+1)); echo 'FAIL  missing session_id must be a no-op' >&2
fi
send '合并' '../evil'
if [ ! -f "$tmp/evil" ] && [ ! -f "$AUTH_DIR/../evil" ]; then pass=$((pass+1)); else
  fail=$((fail+1)); echo 'FAIL  path-traversal session_id must be rejected' >&2
fi
out=$(printf 'not-json' | TMPDIR="$tmp" bash "$HOOK")
if [ -z "$out" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL  bad json -> $out" >&2; fi

if [ "$fail" -ne 0 ]; then
  echo "test_merge_authorization_prompt: FAIL pass=$pass fail=$fail" >&2
  exit 1
fi
echo "test_merge_authorization_prompt_ok pass=$pass"
