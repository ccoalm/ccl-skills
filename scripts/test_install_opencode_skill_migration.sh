#!/usr/bin/env bash
# Verifies the recoverable claude-code-review -> code-review install migration.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/ccl-skills-install-migration.XXXXXX")"
NO_AGENT_HOME="$(mktemp -d "${TMPDIR:-/tmp}/ccl-skills-install-no-agent.XXXXXX")"
trap 'rm -rf "$TEST_HOME" "$NO_AGENT_HOME"' EXIT

native_legacy="$TEST_HOME/.config/opencode/skills/claude-code-review"
compat_legacy="$TEST_HOME/.agents/skills/claude-code-review"
mkdir -p "$native_legacy/scripts" "$compat_legacy"
printf '%s\n' '---' 'name: claude-code-review' '---' >"$native_legacy/SKILL.md"
: >"$native_legacy/scripts/claude_review.sh"
printf '%s\n' 'personal directory with the same name' >"$compat_legacy/KEEP"

HOME="$TEST_HOME" bash "$REPO_ROOT/scripts/install-opencode.sh" \
  >"$TEST_HOME/install.out"

test ! -e "$native_legacy"
test -f "$TEST_HOME/.config/opencode/skills/code-review/SKILL.md"
test -f "$compat_legacy/KEEP"
find "$TEST_HOME/.config/opencode/.ccl-skills-backup/skills" \
  -path '*/claude-code-review/SKILL.md' -type f | grep -q .
grep -q '保留未识别的同名目录' "$TEST_HOME/install.out"

no_agent_legacy="$NO_AGENT_HOME/.agents/skills/claude-code-review"
mkdir -p "$no_agent_legacy/scripts"
printf '%s\n' '---' 'name: claude-code-review' '---' >"$no_agent_legacy/SKILL.md"
: >"$no_agent_legacy/scripts/claude_review.sh"
HOME="$NO_AGENT_HOME" bash "$REPO_ROOT/scripts/install-opencode.sh" --no-agent \
  >"$NO_AGENT_HOME/install.out"
test ! -e "$no_agent_legacy"
find "$NO_AGENT_HOME/.agents/.ccl-skills-backup/skills" \
  -path '*/claude-code-review/SKILL.md' -type f | grep -q .
test ! -e "$NO_AGENT_HOME/.agents/skills/code-review"

printf '%s\n' install_opencode_skill_migration_tests_ok
