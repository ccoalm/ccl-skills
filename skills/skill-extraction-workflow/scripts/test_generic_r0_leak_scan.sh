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

echo "test_generic_r0_leak_scan: ok"
