#!/usr/bin/env bash
# Integration test for generic-r0-leak-scan.sh: proves the public R0 fallback
# blocks on a diff-added leak and passes on clean added lines, WITHOUT any
# private ALIAS_AUDIT_CMD. Builds a throwaway git repo so the scan has a real
# diff to read (added lines only).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
SCAN_SCRIPT="$SCRIPT_DIR/generic-r0-leak-scan.sh"
[ -f "$SCAN_SCRIPT" ] || { echo "FAIL: scan script not found: $SCAN_SCRIPT" >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/genr0.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_rc() { [ "$1" = "$2" ] || fail "expected rc=$2 got rc=$1${3:+ ($3)}"; }
assert_contains() { case "$2" in *"$1"*) : ;; *) fail "expected to contain: $1${3:+ ($3)}";; esac; }
assert_not_contains() { case "$2" in *"$1"*) fail "expected NOT to contain: $1${3:+ ($3)}";; *) : ;; esac; }

# Run the scan with a guaranteed-unset ALIAS_AUDIT_CMD; capture stdout+stderr+rc.
# Optional $2 = a resolvable diff base (CCL_SKILL_BASE_REF). Supplying a base
# is the realistic CI shape and exercises the covered `_ok`/`_failed` path; omit it
# to exercise the base-unavailable `degraded` path (no origin/main, no upstream).
run_scan() {
  local target="$1" base="${2:-}"
  set +e
  if [ -n "$base" ]; then
    out="$(env -u ALIAS_AUDIT_CMD CCL_SKILL_BASE_REF="$base" bash "$SCAN_SCRIPT" "$target" 2>&1)"
  else
    out="$(env -u ALIAS_AUDIT_CMD -u CCL_SKILL_BASE_REF bash "$SCAN_SCRIPT" "$target" 2>&1)"
  fi
  rc=$?
  set -e
}

REPO="$TMP/repo"
mkdir -p "$REPO/skills/demo-skill"
git init -q -b main "$REPO"
git -C "$REPO" config user.email test@example.invalid
git -C "$REPO" config user.name "Test User"

SKILL_MD="$REPO/skills/demo-skill/SKILL.md"
cat > "$SKILL_MD" <<'EOF'
---
name: demo-skill
description: baseline skill body for the leak-scan integration test.
---

Baseline content line that is perfectly clean.
EOF
git -C "$REPO" add -A
git -C "$REPO" commit -qm "baseline demo skill"
# Resolvable base for the covered path (the realistic CI shape); the repo has no
# origin/main or upstream, so pass this explicitly. Committed diff = base..HEAD.
BASE0="$(git -C "$REPO" rev-parse HEAD)"

# Case 1: clean added line (tracked, uncommitted) => PASS.
printf 'This added line stays clean and generic.\n' >> "$SKILL_MD"
run_scan "$REPO" "$BASE0"
assert_rc "$rc" 0 "clean added line should pass"
assert_contains "generic_r0_leak_scan_ok" "$out" "clean run marker"
assert_not_contains "generic_r0_leak_scan_failed" "$out" "clean run must not fail"
git -C "$REPO" checkout -- "skills/demo-skill/SKILL.md"

# Case 2: diff-added absolute local path (tracked, uncommitted) => FAIL.
printf 'See the file at /Users/example/private/secret-notes.md for context.\n' >> "$SKILL_MD"
run_scan "$REPO" "$BASE0"
assert_rc "$rc" 1 "added /Users path should fail"
assert_contains "generic_r0_leak_scan_failed" "$out" "fail marker"
assert_contains "skills/demo-skill/SKILL.md" "$out" "offender path reported"
assert_contains "/Users/example/private" "$out" "offending content reported"
git -C "$REPO" checkout -- "skills/demo-skill/SKILL.md"

# Case 3: pre-existing leak NOT in the diff must NOT be re-policed.
# Commit a line containing a private IP, then make an unrelated clean edit; with a
# base AT the legacy commit, base..HEAD holds only the clean added line, so it
# passes (diff-scoped, not whole-file).
private_ip='10.''1.2.3'
printf 'Legacy note mentions %s from before this change.\n' "$private_ip" >> "$SKILL_MD"
git -C "$REPO" commit -qam "legacy line (pre-existing debt)"
BASE_LEGACY="$(git -C "$REPO" rev-parse HEAD)"
printf 'A fresh and clean follow-up line.\n' >> "$SKILL_MD"
run_scan "$REPO" "$BASE_LEGACY"
assert_rc "$rc" 0 "pre-existing leak outside the added diff must not block"
assert_contains "generic_r0_leak_scan_ok" "$out" "diff-scoped clean marker"
git -C "$REPO" checkout -- "skills/demo-skill/SKILL.md"

# Case 3b: a leak COMMITTED on the branch IS caught when the base predates it —
# base..HEAD includes the legacy commit. This is the anti-false-green guarantee:
# a branch-committed leak must not slip past just because the worktree is clean.
run_scan "$REPO" "$BASE0"
assert_rc "$rc" 1 "committed branch leak in base..HEAD must block"
assert_contains "generic_r0_leak_scan_failed" "$out" "committed-leak fail marker"
assert_contains "$private_ip" "$out" "committed offending content reported"

# Case 4: untracked markdown file with a secret token literal => FAIL.
fixture_label='api_key'
fixture_value='abcdef0123456789ABCDEF'
printf '%s = "%s"\n' "$fixture_label" "$fixture_value" \
  > "$REPO/skills/demo-skill/references-note.md"
mkdir -p "$REPO/skills/demo-skill/references"
mv "$REPO/skills/demo-skill/references-note.md" "$REPO/skills/demo-skill/references/note.md"
run_scan "$REPO" "$BASE_LEGACY"
assert_rc "$rc" 1 "untracked md with secret literal should fail"
assert_contains "generic_r0_leak_scan_failed" "$out" "fail marker (untracked)"
assert_contains "references/note.md" "$out" "untracked offender path reported"
rm -f "$REPO/skills/demo-skill/references/note.md"

# Case 5: angle-placeholder path must NOT be flagged (low false positives).
printf 'Place new lanes under /home/<user>/scratch as a convention.\n' >> "$SKILL_MD"
run_scan "$REPO" "$BASE_LEGACY"
assert_rc "$rc" 0 "angle placeholder path must not be flagged"
assert_contains "generic_r0_leak_scan_ok" "$out" "placeholder clean marker"
git -C "$REPO" checkout -- "skills/demo-skill/SKILL.md"

# Case 6: NO resolvable base (no origin/main, no upstream, unset base) with a HEAD
# present => coverage is DEGRADED, not a reassuring _ok, because branch commits are
# not scanned. This is the exact shallow/detached-HEAD CI shape that must not be a
# silent false-green. Degraded is warning-pass (exit 0) by default; strict blocks.
run_scan "$REPO"   # no base arg -> CCL_SKILL_BASE_REF unset -> base unresolvable
assert_rc "$rc" 0 "degraded (no base) is warning-pass by default"
assert_contains "generic_r0_leak_scan_degraded" "$out" "degraded marker when no base resolves"
assert_not_contains "generic_r0_leak_scan_ok" "$out" "degraded must not print a reassuring _ok"
set +e
strict_out="$(env -u ALIAS_AUDIT_CMD -u CCL_SKILL_BASE_REF CCL_SKILL_R0_STRICT_BASE=1 bash "$SCAN_SCRIPT" "$REPO" 2>&1)"
strict_rc=$?
set -e
assert_rc "$strict_rc" 1 "strict mode blocks degraded coverage"
assert_contains "generic_r0_leak_scan_degraded_blocking" "$strict_out" "strict block marker"

# Case 7: --self-test-cached contract (cold stamp write, warm 0-rg hit,
# CCL_SKILL_NO_SELFTEST_CACHE=1 bypass, 1-byte edit invalidation, broken mutant
# non-caching, symlink/0777 cache-dir rejection, <=64 pruning, check-ccl-skills.sh
# --self-test-cached wiring, and Makefile uncached --self-test wiring).
CACHE_DIR="$TMP/selftest-cache"
RG_SHIM_DIR="$TMP/rg-shim"
RG_LOG="$TMP/rg.log"
REAL_RG="$(command -v rg)"
mkdir -p "$RG_SHIM_DIR"
cat > "$RG_SHIM_DIR/rg" <<EOF
#!/usr/bin/env bash
echo x >> "$RG_LOG"
exec "$REAL_RG" "\$@"
EOF
chmod +x "$RG_SHIM_DIR/rg"

# 7a: cold --self-test-cached runs self-test (batched <= 2 rg calls) and writes a 0700 dir + stamp.
: > "$RG_LOG"
set +e
cold_out="$(PATH="$RG_SHIM_DIR:$PATH" CCL_SKILL_SELFTEST_CACHE_DIR="$CACHE_DIR" env -u CCL_SKILL_NO_SELFTEST_CACHE bash "$SCAN_SCRIPT" --self-test-cached 2>&1)"
cold_rc=$?
set -e
assert_rc "$cold_rc" 0 "cold --self-test-cached should pass"
assert_contains "generic_r0_leak_scan_self_test_ok" "$cold_out" "cold self-test ok token"
cold_rg="$(wc -l < "$RG_LOG" | tr -d ' ')"
[ "$cold_rg" -ge 1 ] && [ "$cold_rg" -le 2 ] || fail "expected batched cold self-test to spawn 1-2 rg calls, got $cold_rg"
stamp_count="$(find "$CACHE_DIR" -maxdepth 1 -type f -name '*.ok' | wc -l | tr -d ' ')"
[ "$stamp_count" -eq 1 ] || fail "expected 1 stamp file after cold run, got $stamp_count"

# 7b: warm --self-test-cached reuses stamp with 0 rg spawns.
: > "$RG_LOG"
warm_out="$(PATH="$RG_SHIM_DIR:$PATH" CCL_SKILL_SELFTEST_CACHE_DIR="$CACHE_DIR" env -u CCL_SKILL_NO_SELFTEST_CACHE bash "$SCAN_SCRIPT" --self-test-cached 2>&1)"
assert_contains "generic_r0_leak_scan_self_test_ok" "$warm_out" "warm self-test ok token"
warm_rg="$(wc -l < "$RG_LOG" | tr -d ' ')"
[ "$warm_rg" -eq 0 ] || fail "expected 0 rg calls on warm --self-test-cached hit, got $warm_rg"

# 7c: CCL_SKILL_NO_SELFTEST_CACHE=1 bypasses stamp and runs self-test.
: > "$RG_LOG"
nocache_out="$(PATH="$RG_SHIM_DIR:$PATH" CCL_SKILL_SELFTEST_CACHE_DIR="$CACHE_DIR" CCL_SKILL_NO_SELFTEST_CACHE=1 bash "$SCAN_SCRIPT" --self-test-cached 2>&1)"
assert_contains "generic_r0_leak_scan_self_test_ok" "$nocache_out" "no-cache self-test ok token"
nocache_rg="$(wc -l < "$RG_LOG" | tr -d ' ')"
[ "$nocache_rg" -ge 1 ] || fail "expected CCL_SKILL_NO_SELFTEST_CACHE=1 to run rg, got 0"

# 7d: 1-byte script change invalidates stamp and writes a second stamp.
COPY_SCRIPT="$TMP/generic-r0-copy.sh"
cp "$SCAN_SCRIPT" "$COPY_SCRIPT"
printf '\n# 1-byte-ish comment invalidation\n' >> "$COPY_SCRIPT"
: > "$RG_LOG"
PATH="$RG_SHIM_DIR:$PATH" CCL_SKILL_SELFTEST_CACHE_DIR="$CACHE_DIR" env -u CCL_SKILL_NO_SELFTEST_CACHE bash "$COPY_SCRIPT" --self-test-cached >/dev/null
edit_rg="$(wc -l < "$RG_LOG" | tr -d ' ')"
[ "$edit_rg" -ge 1 ] || fail "expected edited copy to miss prior stamp and run rg"

# 7d2: swapping rg on PATH (different binary/shim) invalidates prior stamp and fails closed on a broken rg.
BROKEN_RG_DIR="$TMP/rg-shim-broken"
mkdir -p "$BROKEN_RG_DIR"
cat > "$BROKEN_RG_DIR/rg" <<EOF
#!/usr/bin/env bash
echo x >> "$RG_LOG"
exit 1
EOF
chmod +x "$BROKEN_RG_DIR/rg"
: > "$RG_LOG"
set +e
PATH="$BROKEN_RG_DIR:$PATH" CCL_SKILL_SELFTEST_CACHE_DIR="$CACHE_DIR" env -u CCL_SKILL_NO_SELFTEST_CACHE bash "$SCAN_SCRIPT" --self-test-cached >/dev/null 2>&1
swap_rc=$?
set -e
swap_rg="$(wc -l < "$RG_LOG" | tr -d ' ')"
[ "$swap_rg" -ge 1 ] || fail "expected swapped rg binary on PATH to miss prior stamp and invoke rg, got $swap_rg"
[ "$swap_rc" -ne 0 ] || fail "expected broken swapped rg on PATH to fail --self-test-cached, got rc=0"

# 7e: broken mutant never writes a stamp.
BROKEN_SCRIPT="$TMP/generic-r0-broken.sh"
sed 's|/Users/\[A-Za-z0-9._-\]|/NEVER_MATCHES_USERS_PATH|' "$SCAN_SCRIPT" > "$BROKEN_SCRIPT"
FAIL_CACHE="$TMP/fail-cache"
set +e
CCL_SKILL_SELFTEST_CACHE_DIR="$FAIL_CACHE" bash "$BROKEN_SCRIPT" --self-test-cached >/dev/null 2>&1
broken_rc=$?
set -e
[ "$broken_rc" -ne 0 ] || fail "broken mutant must fail --self-test-cached"
broken_stamps="$(find "$FAIL_CACHE" -maxdepth 1 -type f -name '*.ok' 2>/dev/null | wc -l | tr -d ' ')"
[ "$broken_stamps" -eq 0 ] || fail "broken mutant must write 0 stamps, got $broken_stamps"

# 7f: symlink or 0777 cache dir is rejected (bypasses cache without trusting/writing stamp).
BAD_MODE_DIR="$TMP/bad-mode-cache"
mkdir -p "$BAD_MODE_DIR"
chmod 0777 "$BAD_MODE_DIR"
: > "$RG_LOG"
PATH="$RG_SHIM_DIR:$PATH" CCL_SKILL_SELFTEST_CACHE_DIR="$BAD_MODE_DIR" env -u CCL_SKILL_NO_SELFTEST_CACHE bash "$SCAN_SCRIPT" --self-test-cached >/dev/null
PATH="$RG_SHIM_DIR:$PATH" CCL_SKILL_SELFTEST_CACHE_DIR="$BAD_MODE_DIR" env -u CCL_SKILL_NO_SELFTEST_CACHE bash "$SCAN_SCRIPT" --self-test-cached >/dev/null
bad_rg="$(wc -l < "$RG_LOG" | tr -d ' ')"
bad_stamps="$(find "$BAD_MODE_DIR" -maxdepth 1 -type f -name '*.ok' 2>/dev/null | wc -l | tr -d ' ')"
[ "$bad_rg" -ge 4 ] || fail "0777 cache dir must bypass stamp on every call (expected >=4 rg spawns across 2 runs), got rg=$bad_rg"
[ "$bad_stamps" -eq 0 ] || fail "0777 cache dir must write 0 stamps, got $bad_stamps"

SYMLINK_DIR="$TMP/symlink-cache"
ln -s "$CACHE_DIR" "$SYMLINK_DIR"
: > "$RG_LOG"
PATH="$RG_SHIM_DIR:$PATH" CCL_SKILL_SELFTEST_CACHE_DIR="$SYMLINK_DIR" env -u CCL_SKILL_NO_SELFTEST_CACHE bash "$SCAN_SCRIPT" --self-test-cached >/dev/null
sym_rg="$(wc -l < "$RG_LOG" | tr -d ' ')"
[ "$sym_rg" -ge 1 ] || fail "symlinked cache dir must bypass stamp, got rg=$sym_rg"

# 7g: stamp pruning caps cache directory at <= 64 `.ok` files.
PRUNE_DIR="$TMP/prune-cache"
( umask 077 && mkdir -m 0700 "$PRUNE_DIR" )
for idx in $(seq 1 70); do
  printf 'seed\n' > "$(printf '%s/%064d.ok' "$PRUNE_DIR" "$idx")"
done
CCL_SKILL_SELFTEST_CACHE_DIR="$PRUNE_DIR" env -u CCL_SKILL_NO_SELFTEST_CACHE bash "$SCAN_SCRIPT" --self-test-cached >/dev/null
pruned_count="$(find "$PRUNE_DIR" -maxdepth 1 -type f -name '*.ok' | wc -l | tr -d ' ')"
[ "$pruned_count" -le 64 ] || fail "expected <=64 stamps after pruning, got $pruned_count"

# 7h: check-ccl-skills.sh uses --self-test-cached while Makefile test-repo-gates keeps uncached --self-test.
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"
grep -q 'bash "\$generic_r0_scan" --self-test-cached' "$SCRIPT_DIR/check-ccl-skills.sh" \
  || fail "check-ccl-skills.sh must invoke generic-r0-leak-scan.sh --self-test-cached"
grep -q 'generic-r0-leak-scan.sh --self-test$' "$REPO_ROOT/Makefile" \
  || fail "Makefile test-repo-gates must run uncached generic-r0-leak-scan.sh --self-test"

echo "test_generic_r0_leak_scan: ok"
