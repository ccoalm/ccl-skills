#!/usr/bin/env bash
# Deterministic behavior suite for hooks/guard-edit-isolation.sh.
#
# The guard is the repo's ONLY edit-time hard-deny gate and previously had no
# suite at all — every regression (deny-text typo, live-worktree awk count,
# symlink branch) would only surface when a user hit it. Every probe pins the
# full observable contract, not just "did output appear":
#   - exit status is always 0 (a PreToolUse hook must never fail the tool call)
#   - stdout is either ZERO bytes (quiet allow) or exactly one JSON object
#   - stderr is always empty (payloads may carry file contents/secrets)
#   - each probe builds its own synthetic repo under a private TMPDIR
# Fixtures are synthetic repos created by this suite; run it from anywhere:
#   bash hooks/test_guard_edit_isolation.sh
# HOOK env var overrides the hook under test, so mutation RED proofs can point the suite at a broken copy; the recorded mutations (M1 deny-check removal, M2 stderr leak, M3/M5 static degrade, M9 marker/worktree precedence inversion, M10 path-name linked-worktree match, M11 git-dir-vs-common-dir compare without the worktree admin-dir walk) are run manually on every suite change and pinned in the commit log.
# Registered in the Makefile `test` target and GitHub Actions; requires jq+git.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
HOOK="${HOOK:-$SCRIPT_DIR/guard-edit-isolation.sh}"
[ -f "$HOOK" ] || { echo "FAIL: hook not found: $HOOK" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq required for this suite" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "FAIL: git required for this suite" >&2; exit 1; }

# Clear ambient git state BEFORE any repo probe (incl. the containment check).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_CEILING_DIRECTORIES
if [ -n "${SUITE_TMPDIR:-}" ]; then
  git -C "$SUITE_TMPDIR" rev-parse --show-toplevel >/dev/null 2>&1 \
    && { echo "FAIL: SUITE_TMPDIR resolves inside a git checkout (p8 fixture would be invalid): $SUITE_TMPDIR" >&2; exit 1; }
fi
ROOT=$(mktemp -d "${SUITE_TMPDIR:-/tmp}/guard-edit-isolation-test.XXXXXX") || exit 1
# darwin: /tmp -> /private/tmp. Normalize so payload paths and the guard's
# realpath-resolved view refer to the same strings.
ROOT=$(cd "$ROOT" && pwd -P)
trap 'rm -rf "$ROOT"' EXIT
# Hermetic fixtures: the invoking user's global/system git config (commit.gpgsign,
# core.hooksPath, init.templateDir) must not leak into fixture repos or the
# guard's own git probes — a stray signing/hook config would flake the suite
# for reasons unrelated to the guard.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
# Version floor: GIT_CONFIG_* env overrides need git >= 2.32. Nothing else is
# version-gated — p5 detects the porcelain prunable behaviour instead of
# assuming a floor for it (see P5).
git_ver=$(git version | grep -oE '[0-9]+\.[0-9]+' | head -1)
git_major=${git_ver%%.*}; git_minor=${git_ver##*.}
if ! { [ "$git_major" -gt 2 ] || { [ "$git_major" -eq 2 ] && [ "$git_minor" -ge 32 ]; }; }; then
  echo "FAIL: git >= 2.32 required for hermetic fixture config (found $git_ver)" >&2; exit 1
fi
pass=0; fail=0
note() { fail=$((fail+1)); printf 'FAIL  %s\n' "$1" >&2; }
ok()   { pass=$((pass+1)); }

# mk_repo <dir> — synthetic primary checkout with one commit (branch pinned:
# init.defaultBranch varies by global config, and probes assert on the name).
mk_repo() {
  git init -q -b main "$1" || return 1
  git -C "$1" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
}

# run <case-tmpdir> <json-stdin> [env-assignment...] -> OUT ERR RC OUTBYTES ERRBYTES
run() {
  local td="$1" payload="$2"
  shift 2
  local eo="$td/.stderr" so="$td/.stdout"
  ( cd "$td" && printf '%s' "$payload" | env "$@" bash "$HOOK" ) >"$so" 2>"$eo"
  RC=$?
  PAYLOAD_FP=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // empty' 2>/dev/null)
  OUT=$(cat "$so" 2>/dev/null)
  ERR=$(cat "$eo" 2>/dev/null)
  OUTBYTES=$(wc -c < "$so" 2>/dev/null | tr -d ' ')
  ERRBYTES=$(wc -c < "$eo" 2>/dev/null | tr -d ' ')
}

# Every invocation, whatever the case, must satisfy these.
assert_universal() { # assert_universal <label> — returns non-zero on violation
  local label="$1" bad=0
  [ "$RC" -eq 0 ] || { note "$label: exit status $RC, must be 0 (hook must never fail the tool call)"; bad=1; }
  [ "${ERRBYTES:-0}" -eq 0 ] || { note "$label: wrote $ERRBYTES bytes to stderr (possible payload leak)"; bad=1; }
  if [ "${OUTBYTES:-0}" -gt 0 ]; then
    printf '%s' "$OUT" | jq -es 'length==1 and (.[0]|type=="object")' >/dev/null 2>&1 \
      || { note "$label: stdout is not exactly one JSON object"; bad=1; }
  fi
  [ "$bad" -eq 0 ]
}

assert_quiet() { # assert_quiet <label> — allow means ZERO bytes on stdout
  local label="$1"
  assert_universal "$label" || return
  [ "${OUTBYTES:-0}" -eq 0 ] || note "$label: expected quiet allow, got $OUTBYTES bytes: $OUT"
  ok "$label"
}

assert_deny() { # assert_deny <label> <reason-substring> [branch]
  local label="$1" want="$2" branch="${3:-}"
  assert_universal "$label" || return
  [ -n "$OUT" ] || { note "$label: expected deny JSON, got quiet"; return; }
  printf '%s' "$OUT" | jq -e '
    .hookSpecificOutput.hookEventName == "PreToolUse" and
    .hookSpecificOutput.permissionDecision == "deny" and
    (.hookSpecificOutput.permissionDecisionReason | type == "string" and length > 0)
  ' >/dev/null 2>&1 || { note "$label: deny JSON contract broken: $OUT"; return; }
  printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason' \
    | grep -q -- "$want" || { note "$label: reason missing '$want': $OUT"; return; }
  # anti-static: a single canned reason carrying BOTH deny categories must fail
  case "$want" in
    *共享仓库*) other_cat="并发隔离闸" ;;
    *并发隔离闸*) other_cat="共享仓库" ;;
    *) other_cat="" ;;
  esac
  if [ -n "$other_cat" ]; then
    printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason' \
      | grep -q -- "$other_cat" && { note "$label: static reason carries both deny categories: $OUT"; return; }
  fi
  if [ -n "$PAYLOAD_FP" ]; then
    case "$OUT" in
      *"$PAYLOAD_FP"*) note "$label: deny output echoes payload file path (leak): $OUT"; return ;;
    esac
  fi
  if [ -n "$branch" ]; then
    printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason' \
      | grep -q -- "$branch" || { note "$label: reason missing branch '$branch': $OUT"; return; }
  fi
  ok "$label"
}

assert_degrade() { # assert_degrade <label> <tool-name> <other-tool> — visible per-tool degrade
  local label="$1" tool="$2" other="$3"
  assert_universal "$label" || return
  [ -n "$OUT" ] || { note "$label: expected degrade systemMessage, got quiet"; return; }
  printf '%s' "$OUT" | jq -e '.systemMessage | type == "string" and length > 0' >/dev/null 2>&1 \
    || { note "$label: degrade is not a visible systemMessage: $OUT"; return; }
  # attribution contract (locale-flexible): the message attributes absence to
  # the missing tool ("<tool> not found/未安装/缺失/..."), and does NOT attribute
  # absence to the present one. A static both-names text attributes nothing and
  # fails the positive arm; a legit "jq 未安装，跳过 git 仓库检测" passes.
  printf '%s' "$OUT" | jq -r '.systemMessage' | grep -qw "$tool" \
    || { note "$label: degrade message does not name missing tool '$tool': $OUT"; return; }
  printf '%s' "$OUT" | jq -r '.systemMessage' | grep -qE "not found|not installed|missing|is required|未安装|缺失" \
    || { note "$label: degrade message carries no absence marker for '$tool': $OUT"; return; }
  printf '%s' "$OUT" | jq -r '.systemMessage' | grep -qE "$other (not found|not installed|is required|未安装|缺失)|(未安装|缺失)[^，。；,;]{0,6}$other" \
    && { note "$label: degrade message also blames present tool '$other' (static text, not per-tool detection): $OUT"; return; }
  ok "$label"
}

payload_for() { # payload_for <file_path> [tool] [field] — PreToolUse shapes the guard reads
  local fp="$1" tool="${2:-Edit}" field="${3:-file_path}"
  jq -nc --arg t "$tool" --arg p "$fp" --arg f "$field" '{tool_name:$t,tool_input:{($f):$p}}'
}

# --- probe fixtures ---------------------------------------------------------

# P1: solo primary checkout, plain repo, no marker, no extra worktrees -> allow
d1="$ROOT/p1"; mk_repo "$d1" || { note "p1 fixture: mk_repo failed"; exit 1; }
run "$d1" "$(payload_for "$d1/src/x.py")"
assert_quiet "p1 solo primary checkout allows edit"

# P2: primary checkout of a .worktree-only repo -> deny (shared-repo branch)
d2="$ROOT/p2"; mk_repo "$d2" || { note "p2 fixture: mk_repo failed"; exit 1; }; touch "$d2/.worktree-only"
run "$d2" "$(payload_for "$d2/src/x.py")"
assert_deny "p2 .worktree-only primary denies edit" "共享仓库" "main"

# P3: another LIVE worktree exists (no marker) -> deny with concurrency count
d3="$ROOT/p3"; mk_repo "$d3" || { note "p3 fixture: mk_repo failed"; exit 1; }
git -C "$d3" worktree add -q -b side "$ROOT/p3-side" || { note "p3 fixture: worktree add failed"; exit 1; }
git -C "$d3" worktree list --porcelain | grep -q "p3-side" || note "p3 fixture: sibling worktree missing"
run "$d3" "$(payload_for "$d3/src/x.py")"
assert_deny "p3 live sibling worktree denies primary edit" "并发隔离闸" "main"

# P4: edit INSIDE the linked worktree -> allow (already isolated)
d4="$ROOT/p3-side"
run "$d4" "$(payload_for "$d4/src/x.py")"
assert_quiet "p4 linked worktree checkout allows edit"

# P4b: linked worktree of a .worktree-only repo (marker COMMITTED, so it exists
# in every checkout) -> allow. This pins the ORDER of the two branches: the
# linked-worktree exit must run before the marker deny. Inverting them denies
# every edit in every worktree of a shared repo — precisely the workflow the
# marker exists to force — and p4 alone cannot see it (its fixture has no marker).
d4b="$ROOT/p4b"; mk_repo "$d4b" || { note "p4b fixture: mk_repo failed"; exit 1; }
touch "$d4b/.worktree-only"
git -C "$d4b" add .worktree-only \
  && git -C "$d4b" -c user.email=t@t -c user.name=t commit -q -m marker \
  || { note "p4b fixture: marker commit failed"; exit 1; }
git -C "$d4b" worktree add -q -b p4b-side "$ROOT/p4b-side" || { note "p4b fixture: worktree add failed"; exit 1; }
[ -e "$ROOT/p4b-side/.worktree-only" ] || note "p4b fixture: committed marker absent in the linked worktree checkout"
run "$ROOT/p4b-side" "$(payload_for "$ROOT/p4b-side/src/x.py")"
assert_quiet "p4b linked worktree of a MARKED shared repo allows edit (marker deny must not precede the worktree exit)"

# P4c: a PRIMARY checkout whose filesystem path merely contains a `worktrees/`
# component is still gated. The linked-worktree exit must be STRUCTURAL (git-dir
# vs common dir); a `*/worktrees/*` path-name match silently disables the repo's
# only hard deny gate for any checkout living at e.g. ~/work/worktrees/<repo>.
mkdir -p "$ROOT/worktrees"
d4c="$ROOT/worktrees/p4c"; mk_repo "$d4c" || { note "p4c fixture: mk_repo failed"; exit 1; }
touch "$d4c/.worktree-only"
case "$(git -C "$d4c" rev-parse --absolute-git-dir 2>/dev/null)" in
  */worktrees/*) ;;
  *) note "p4c fixture: git-dir lacks the worktrees/ path component, probe proves nothing" ;;
esac
run "$d4c" "$(payload_for "$d4c/src/x.py")"
assert_deny "p4c primary checkout under a path named worktrees/ still denies" "共享仓库" "main"

# P4d: a MARKED submodule initialized inside a linked superproject worktree is
# already isolated from the superproject's main checkout -> allow. Its git-dir
# lands at <common>/worktrees/<id>/modules/<name> and git reports the SAME path
# as its common dir, so a git-dir-vs-common-dir comparison alone reads "primary"
# and would hard-deny the mandated workflow. The guard must recognise the
# enclosing worktree admin dir structurally (commondir+gitdir marker files).
d4d="$ROOT/p4d"; mk_repo "$d4d/sub" || { note "p4d fixture: sub mk_repo failed"; exit 1; }
touch "$d4d/sub/.worktree-only"
git -C "$d4d/sub" add .worktree-only \
  && git -C "$d4d/sub" -c user.email=t@t -c user.name=t commit -q -m marker \
  || { note "p4d fixture: sub marker commit failed"; exit 1; }
mk_repo "$d4d/super" || { note "p4d fixture: super mk_repo failed"; exit 1; }
git -C "$d4d/super" -c protocol.file.allow=always -c user.email=t@t -c user.name=t submodule add -q "$d4d/sub" sub \
  && git -C "$d4d/super" -c user.email=t@t -c user.name=t commit -q -m addsub \
  || { note "p4d fixture: submodule add failed"; exit 1; }
git -C "$d4d/super" worktree add -q -b p4d-side "$d4d/superwt" || { note "p4d fixture: worktree add failed"; exit 1; }
git -C "$d4d/superwt" -c protocol.file.allow=always submodule update --init -q \
  || { note "p4d fixture: submodule update in linked worktree failed"; exit 1; }
[ -e "$d4d/superwt/sub/.worktree-only" ] || note "p4d fixture: marker absent in the worktree's submodule checkout"
sub_gd=$(git -C "$d4d/superwt/sub" rev-parse --absolute-git-dir 2>/dev/null)
sub_cd=$(git -C "$d4d/superwt/sub" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
[ -n "$sub_gd" ] && [ "$sub_gd" = "$sub_cd" ] \
  || note "p4d fixture: submodule git-dir/common-dir no longer coincide ($sub_gd vs $sub_cd) — probe no longer pins the intended branch"
run "$d4d/superwt/sub" "$(payload_for "$d4d/superwt/sub/src/x.py")"
assert_quiet "p4d marked submodule inside a linked superproject worktree allows edit"

# P5: prunable sibling (dir deleted) is excluded from the live count -> allow
d5="$ROOT/p5"; mk_repo "$d5" || { note "p5 fixture: mk_repo failed"; exit 1; }
git -C "$d5" worktree add -q -b ghost "$ROOT/p5-ghost" || { note "p5 fixture: worktree add failed"; exit 1; }
rm -rf "$ROOT/p5-ghost"
# The contract is version-independent (quiet allow), so the probe is too. What
# varies is HOW the ghost stays out of the live count: git may omit it from the
# porcelain listing, or list it with a `prunable` annotation. Both satisfy the
# contract; a git that lists it WITHOUT the annotation does not, and would make
# the guard deny — so assert that disjunction as the fixture premise and report
# it as the cause instead of leaving an unexplained deny.
# (Detect it behaviourally, not by a version floor: the 2.34 CI runner does emit
# the porcelain `prunable` line, so a >=2.36 gate mis-describes why this passes.)
p5_porcelain=$(git -C "$d5" worktree list --porcelain 2>/dev/null)
if printf '%s' "$p5_porcelain" | grep -q "p5-ghost" \
   && ! printf '%s' "$p5_porcelain" | grep -q "^prunable"; then
  note "p5 fixture: ghost listed WITHOUT a prunable annotation on git $git_ver — it would count as live, premise broken"
fi
run "$d5" "$(payload_for "$d5/src/x.py")"
assert_quiet "p5 deleted-dir worktree excluded from the live count (omitted or prunable-annotated)"

# P6: symlinked file pointing into a protected repo -> deny (target resolved)
mkdir -p "$d2/src" && touch "$d2/src/x.py"
ln -s "$d2/src/x.py" "$ROOT/p6-link"
run "$ROOT" "$(payload_for "$ROOT/p6-link")"
assert_deny "p6 symlink into .worktree-only repo denies edit" "共享仓库" ""

# P7: not-yet-existing file below an existing protected dir (walk-up) -> deny
run "$d2" "$(payload_for "$d2/newdir/newfile.py")"
assert_deny "p7 non-existent file under protected repo denies edit" "共享仓库" ""

# P7b: other edit-tool shapes hit the same deny path (Write / NotebookEdit /
# generic path field) — a regression narrowing the gated tool set turns these red
run "$d2" "$(payload_for "$d2/src/y.py" Write)"
assert_deny "p7b Write tool on protected repo denies" "共享仓库" ""
run "$d2" "$(payload_for "$d2/src/nb.ipynb" NotebookEdit notebook_path)"
assert_deny "p7c NotebookEdit notebook_path on protected repo denies" "共享仓库" ""
run "$d2" "$(payload_for "$d2/src/z.py" SomeEdit path)"
assert_deny "p7d generic path field on protected repo denies" "共享仓库" ""
# The guard is intentionally tool-agnostic (host matcher scopes it to edit
# tools): a Bash-shaped payload carries no file_path so it is a quiet no-op.
# This pins the CURRENT contract boundary as a DOCUMENTED SCOPE LIMIT — the
# shell-write path is outside this guard (merge-time writes are owned by the
# merge-authorization guard), and any future change that makes this guard read
# or gate Bash payloads must update this probe deliberately.
run "$d2" '{"tool_name":"Bash","tool_input":{"command":"echo x > '"$d2"'/src/q.py"}}'
assert_quiet "p7e Bash-shaped payload quiet (documented scope limit: matcher owns tool scope)"

# P7g: garbage input never kills the hook — malformed JSON and empty stdin
# are quiet no-ops (jq failure leaves fp empty by design)
run "$d2" "$(printf '{not json')"
assert_quiet "p7g malformed JSON input is a quiet no-op (never a spurious deny)"
run "$d2" "$(printf '')"
assert_quiet "p7h empty stdin is a quiet no-op (never a spurious deny)"

# P8: file outside any repository -> allow
d8="$ROOT/p8"; mkdir -p "$d8"
run "$d8" "$(payload_for "$d8/loose.txt")"
assert_quiet "p8 file outside any repo allows edit"

# P9: input without file_path -> quiet no-op
run "$ROOT" '{"tool_name":"Edit","tool_input":{}}'
assert_quiet "p9 missing file_path is a quiet no-op"

# P10: jq missing -> visible degrade naming jq, never silent.
# Shim carries the utilities the hook may plausibly touch so the degrade is
# attributable to the probed dependency and not to an unrelated missing tool.
shim="$ROOT/shim-git-only"; mkdir "$shim"
for t in git dirname realpath readlink cat wc awk basename bash sed grep tr uname mktemp env find head sort; do
  p=$(command -v "$t" 2>/dev/null) || { echo "suite fixture: required shim tool missing: $t" >&2; exit 1; }
  ln -s "$p" "$shim/$t"
done
run "$ROOT" "$(payload_for "$d2/src/x.py")" PATH="$shim"
assert_degrade "p10 jq missing degrades visibly" "jq" "git"
printf '%s' "$OUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1 \
  && note "p10 degrade must not carry permissionDecision deny: $OUT"

# P11: git missing -> visible degrade naming git, never silent
shim2="$ROOT/shim-jq-only"; mkdir "$shim2"
for t in jq dirname realpath readlink cat wc awk basename bash sed grep tr uname mktemp env find head sort; do
  p=$(command -v "$t" 2>/dev/null) || { echo "suite fixture: required shim tool missing: $t" >&2; exit 1; }
  ln -s "$p" "$shim2/$t"
done
run "$ROOT" "$(payload_for "$d2/src/x.py")" PATH="$shim2"
assert_degrade "p11 git missing degrades visibly" "git" "jq"
printf '%s' "$OUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1 \
  && note "p11 degrade must not carry permissionDecision deny: $OUT"

# Self-pin: a deleted/commented-out probe must fail the suite, not shrink it.
EXPECTED_PROBES=20
actual_probes=$(grep -cE '^[[:space:]]*assert_(quiet|deny|degrade) ' "$0")
[ "$actual_probes" -eq "$EXPECTED_PROBES" ] \
  || { echo "FAIL: suite self-pin: expected $EXPECTED_PROBES probe assertions, found $actual_probes" >&2; exit 1; }

echo "guard_edit_isolation: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
