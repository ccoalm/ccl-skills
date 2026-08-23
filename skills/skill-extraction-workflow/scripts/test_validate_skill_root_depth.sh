#!/usr/bin/env bash
# Regression: validate-skill.sh must discover skills laid out as
# <root>/skills/<name>/SKILL.md (depth 3) when invoked on the repo root.
#
# The discovery find used -maxdepth 2, matching <root>/<name>/SKILL.md only, so
# the documented default invocation `validate-skill.sh .` from a ccl-skills
# checkout exited 2 with no_skill_roots_found. The failure was loud (non-zero),
# but the default-vs-layout mismatch made "run the validator on the repo" fail
# spuriously. This test pins depth-3 discovery AND that a directory with no
# SKILL.md anywhere still fails loudly.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
VALIDATE="$SCRIPT_DIR/validate-skill.sh"
[ -f "$VALIDATE" ] || { echo "FAIL: validate script not found: $VALIDATE" >&2; exit 1; }

fail() { echo "FAIL: $*" >&2; exit 1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/vsrd.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

# (1) repo-root layout: skills/<name>/SKILL.md is found at depth 3.
mkdir -p "$tmp/repo/skills/sample-skill"
cat > "$tmp/repo/skills/sample-skill/SKILL.md" <<'EOF'
---
name: sample-skill
description: Use when validating sample fixtures end to end.
---

# Sample skill

Body text.
EOF
# Excluded fixtures are deliberately INVALID (broken frontmatter): if a buggy
# discovery picks one up — even instead of the real root — validation fails
# loudly rather than false-greening on "1 root".
mkdir -p "$tmp/repo/skills/sample-skill/fixtures"
printf 'not-frontmatter\n' > "$tmp/repo/skills/sample-skill/fixtures/SKILL.md"
mkdir -p "$tmp/repo/vendor/thing"
printf 'not-frontmatter\n' > "$tmp/repo/vendor/thing/SKILL.md"
out="$(bash "$VALIDATE" "$tmp/repo" 2>&1)" || fail "repo-root run exited non-zero: $out"
# Pure-bash substring match, not `printf | grep -q`: grep -q exits on its first
# hit, the producer takes SIGPIPE, and under `set -o pipefail` the SUCCESS path
# then reports failure. Timing-dependent, so it stayed latent until this lane
# ran concurrently (specs/037-ci-intra-job-parallel/plan.md).
[[ "$out" == *"validating 1 skill root(s)"* ]] \
  || fail "expected exactly 1 root (nested fixture must be excluded): $out"

# (2) a tree with no SKILL.md still fails loudly (exit 2, no silent green).
mkdir -p "$tmp/empty/sub/deeper"
if out="$(bash "$VALIDATE" "$tmp/empty" 2>&1)"; then
  fail "empty tree unexpectedly passed: $out"
fi
[[ "$out" == *no_skill_roots_found* ]] \
  || fail "empty tree missing loud no_skill_roots_found: $out"

echo "PASS: validate-skill discovers skills/<name>/SKILL.md and stays loud on empty trees"
