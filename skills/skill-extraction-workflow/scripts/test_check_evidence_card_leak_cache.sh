#!/usr/bin/env bash
# Deterministic regression suite for check-evidence-card-leak.sh self-test caching
# and ambient CCL_SKILL_BASE_REF isolation (B2-1).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
DETECTOR="$SCRIPT_DIR/check-evidence-card-leak.sh"
CHECKER="$SCRIPT_DIR/check-ccl-skills.sh"

[ -f "$DETECTOR" ] || { echo "FAIL: missing detector: $DETECTOR" >&2; exit 1; }
[ -f "$CHECKER" ] || { echo "FAIL: missing checker: $CHECKER" >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/evcard-cache-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT INT TERM

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1" >&2; }

REAL_GIT="$(command -v git)"
SPY_BIN="$WORK/spy-bin"
mkdir -p "$SPY_BIN"
GIT_INIT_LOG="$WORK/git-init.log"
cat > "$SPY_BIN/git" <<EOF
#!/usr/bin/env bash
for arg in "\$@"; do
  if [ "\$arg" = "init" ]; then
    printf 'init\n' >> "$GIT_INIT_LOG"
    break
  fi
done
exec "$REAL_GIT" "\$@"
EOF
chmod 0755 "$SPY_BIN/git"

# 1. Ambient CCL_SKILL_BASE_REF=HEAD must not break --self-test case (v)
set +e
amb_out="$(CCL_SKILL_BASE_REF=HEAD bash "$DETECTOR" --self-test 2>&1)"
amb_rc=$?
set -e
if [ "$amb_rc" -eq 0 ] && grep -q 'evidence_card_leak_self_test_ok' <<<"$amb_out"; then
  ok "ambient CCL_SKILL_BASE_REF=HEAD does not pollute --self-test"
else
  bad "ambient CCL_SKILL_BASE_REF=HEAD broke --self-test (rc=$amb_rc): $amb_out"
fi

# 2. Cold cache runs self-test and writes 0700 stamp; warm cache hits with 0 git init forks
CACHE_A="$WORK/cache-a"
: > "$GIT_INIT_LOG"
set +e
cold_out="$(PATH="$SPY_BIN:$PATH" CCL_SKILL_SELFTEST_CACHE_DIR="$CACHE_A" bash "$DETECTOR" --self-test-cached 2>&1)"
cold_rc=$?
set -e
cold_inits="$(wc -l < "$GIT_INIT_LOG" | tr -d ' ')"
stamp_count_cold="$(find "$CACHE_A" -maxdepth 1 -type f -name '*.ok' 2>/dev/null | wc -l | tr -d ' ')"
if [ "$cold_rc" -eq 0 ] && grep -q 'evidence_card_leak_self_test_ok' <<<"$cold_out" \
   && [ "$cold_inits" -ge 1 ] && [ "$stamp_count_cold" -eq 1 ]; then
  ok "cold --self-test-cached runs fixture repo and writes 1 stamp"
else
  bad "cold --self-test-cached unexpected: rc=$cold_rc inits=$cold_inits stamps=$stamp_count_cold out=$cold_out"
fi

: > "$GIT_INIT_LOG"
set +e
warm_out="$(PATH="$SPY_BIN:$PATH" CCL_SKILL_SELFTEST_CACHE_DIR="$CACHE_A" bash "$DETECTOR" --self-test-cached 2>&1)"
warm_rc=$?
set -e
warm_inits="$(wc -l < "$GIT_INIT_LOG" | tr -d ' ')"
if [ "$warm_rc" -eq 0 ] && grep -q 'evidence_card_leak_self_test_ok' <<<"$warm_out" && [ "$warm_inits" -eq 0 ]; then
  ok "warm --self-test-cached hits stamp with 0 git init forks"
else
  bad "warm --self-test-cached missed or failed: rc=$warm_rc inits=$warm_inits out=$warm_out"
fi

# 3. Strict or explicit no-cache env bypasses warm stamp and runs fixture self-test
: > "$GIT_INIT_LOG"
set +e
strict_out="$(PATH="$SPY_BIN:$PATH" CCL_SKILL_SELFTEST_CACHE_DIR="$CACHE_A" CCL_SKILL_EVIDENCE_CARD_STRICT_SELFTEST=1 bash "$DETECTOR" --self-test-cached 2>&1)"
strict_rc=$?
set -e
strict_inits="$(wc -l < "$GIT_INIT_LOG" | tr -d ' ')"
if [ "$strict_rc" -eq 0 ] && [ "$strict_inits" -ge 1 ]; then
  ok "CCL_SKILL_EVIDENCE_CARD_STRICT_SELFTEST=1 bypasses warm stamp"
else
  bad "strict mode did not bypass warm stamp: rc=$strict_rc inits=$strict_inits out=$strict_out"
fi

: > "$GIT_INIT_LOG"
set +e
nocache_out="$(PATH="$SPY_BIN:$PATH" CCL_SKILL_SELFTEST_CACHE_DIR="$CACHE_A" CCL_SKILL_NO_SELFTEST_CACHE=1 bash "$DETECTOR" --self-test-cached 2>&1)"
nocache_rc=$?
set -e
nocache_inits="$(wc -l < "$GIT_INIT_LOG" | tr -d ' ')"
if [ "$nocache_rc" -eq 0 ] && [ "$nocache_inits" -ge 1 ]; then
  ok "CCL_SKILL_NO_SELFTEST_CACHE=1 bypasses warm stamp"
else
  bad "CCL_SKILL_NO_SELFTEST_CACHE=1 did not bypass warm stamp: rc=$nocache_rc inits=$nocache_inits out=$nocache_out"
fi

# 4. Any 1-byte edit to check-evidence-card-leak.sh invalidates stamp and re-runs self-test
COPY_DETECTOR="$WORK/check-evidence-card-leak-copy.sh"
cp "$DETECTOR" "$COPY_DETECTOR"
printf '\n# cache-invalidation-comment\n' >> "$COPY_DETECTOR"
chmod 0755 "$COPY_DETECTOR"
: > "$GIT_INIT_LOG"
set +e
edit_out="$(PATH="$SPY_BIN:$PATH" CCL_SKILL_SELFTEST_CACHE_DIR="$CACHE_A" bash "$COPY_DETECTOR" --self-test-cached 2>&1)"
edit_rc=$?
set -e
edit_inits="$(wc -l < "$GIT_INIT_LOG" | tr -d ' ')"
stamp_count_after_edit="$(find "$CACHE_A" -maxdepth 1 -type f -name '*.ok' 2>/dev/null | wc -l | tr -d ' ')"
if [ "$edit_rc" -eq 0 ] && [ "$edit_inits" -ge 1 ] && [ "$stamp_count_after_edit" -eq 2 ]; then
  ok "1-byte detector edit invalidates cache and writes distinct stamp"
else
  bad "1-byte edit did not invalidate cache: rc=$edit_rc inits=$edit_inits stamps=$stamp_count_after_edit"
fi

# 5. Broken detector mutant fails rc!=0 and never writes .ok stamp
BROKEN_DETECTOR="$WORK/check-evidence-card-leak-broken.sh"
python3 - "$DETECTOR" "$BROKEN_DETECTOR" <<'PY'
import pathlib, sys
src = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
mut = src.replace('report 0', 'report 1', 1)
assert mut != src, "failed to construct broken mutant"
pathlib.Path(sys.argv[2]).write_text(mut, encoding="utf-8")
PY
chmod 0755 "$BROKEN_DETECTOR"
CACHE_B="$WORK/cache-broken"
set +e
brk_out="$(CCL_SKILL_SELFTEST_CACHE_DIR="$CACHE_B" bash "$BROKEN_DETECTOR" --self-test-cached 2>&1)"
brk_rc=$?
set -e
brk_stamps="$(find "$CACHE_B" -maxdepth 1 -type f -name '*.ok' 2>/dev/null | wc -l | tr -d ' ')"
if [ "$brk_rc" -ne 0 ] && [ "$brk_stamps" -eq 0 ]; then
  ok "broken detector mutant fails closed and writes 0 stamps"
else
  bad "broken detector mutant wrote stamp or passed: rc=$brk_rc stamps=$brk_stamps"
fi

# 6. Skipped git-fixture self-test (git unavailable) exits 0 with warning but writes 0 stamps
NOGIT_BIN="$WORK/nogit-bin"
mkdir -p "$NOGIT_BIN"
cat > "$NOGIT_BIN/git" <<'EOF'
#!/usr/bin/env bash
exit 127
EOF
chmod 0755 "$NOGIT_BIN/git"
CACHE_SKIP="$WORK/cache-skip"
set +e
skip_out="$(PATH="$NOGIT_BIN:$PATH" CCL_SKILL_SELFTEST_CACHE_DIR="$CACHE_SKIP" bash "$DETECTOR" --self-test-cached 2>&1)"
skip_rc=$?
set -e
skip_stamps="$(find "$CACHE_SKIP" -maxdepth 1 -type f -name '*.ok' 2>/dev/null | wc -l | tr -d ' ')"
if [ "$skip_rc" -eq 0 ] && grep -q 'evidence_card_leak_self_test_skipped' <<<"$skip_out" && [ "$skip_stamps" -eq 0 ]; then
  ok "degraded git-skip self-test never writes a clean cache stamp"
else
  bad "degraded git-skip cached or failed unexpectedly: rc=$skip_rc stamps=$skip_stamps out=$skip_out"
fi

# 7. Unsafe cache directory (symlink or world-writable 0777) is rejected without writing through it
VICTIM_DIR="$WORK/victim"
mkdir -p -m 0700 "$VICTIM_DIR"
SYM_CACHE="$WORK/cache-symlink"
ln -s "$VICTIM_DIR" "$SYM_CACHE"
: > "$GIT_INIT_LOG"
set +e
sym_out="$(PATH="$SPY_BIN:$PATH" CCL_SKILL_SELFTEST_CACHE_DIR="$SYM_CACHE" bash "$DETECTOR" --self-test-cached 2>&1)"
sym_rc=$?
set -e
victim_files="$(find "$VICTIM_DIR" -maxdepth 1 -type f | wc -l | tr -d ' ')"
if [ "$sym_rc" -eq 0 ] && [ "$victim_files" -eq 0 ] && [ "$(wc -l < "$GIT_INIT_LOG" | tr -d ' ')" -ge 1 ]; then
  ok "symlinked cache dir is rejected without writing through symlink"
else
  bad "symlinked cache dir was followed or failed: rc=$sym_rc victim_files=$victim_files"
fi

WW_CACHE="$WORK/cache-world-writable"
mkdir -p "$WW_CACHE"
chmod 0777 "$WW_CACHE"
: > "$GIT_INIT_LOG"
set +e
ww_out="$(PATH="$SPY_BIN:$PATH" CCL_SKILL_SELFTEST_CACHE_DIR="$WW_CACHE" bash "$DETECTOR" --self-test-cached 2>&1)"
ww_rc=$?
set -e
ww_files="$(find "$WW_CACHE" -maxdepth 1 -type f | wc -l | tr -d ' ')"
if [ "$ww_rc" -eq 0 ] && [ "$ww_files" -eq 0 ] && [ "$(wc -l < "$GIT_INIT_LOG" | tr -d ' ')" -ge 1 ]; then
  ok "world-writable (0777) cache dir is rejected without writing stamps"
else
  bad "world-writable cache dir wrote stamps or failed: rc=$ww_rc ww_files=$ww_files"
fi

# 8. Stamp pruning bounds directory growth when >64 historical stamps exist
PRUNE_CACHE="$WORK/cache-prune"
mkdir -p -m 0700 "$PRUNE_CACHE"
for i in $(seq 1 70); do
  printf 'ok\n' > "$PRUNE_CACHE/old-stamp-$i.ok"
done
set +e
prune_out="$(CCL_SKILL_SELFTEST_CACHE_DIR="$PRUNE_CACHE" bash "$DETECTOR" --self-test-cached 2>&1)"
prune_rc=$?
set -e
prune_count="$(find "$PRUNE_CACHE" -maxdepth 1 -type f -name '*.ok' | wc -l | tr -d ' ')"
if [ "$prune_rc" -eq 0 ] && [ "$prune_count" -le 64 ]; then
  ok "cache stamp count is bounded to <= 64 entries ($prune_count)"
else
  bad "cache stamp count was not bounded: rc=$prune_rc count=$prune_count"
fi

# 9. check-ccl-skills.sh invokes --self-test-cached
if grep -q -- '--self-test-cached' "$CHECKER"; then
  ok "check-ccl-skills.sh invokes check-evidence-card-leak.sh --self-test-cached"
else
  bad "check-ccl-skills.sh still invokes uncached --self-test"
fi

echo "----"
echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
