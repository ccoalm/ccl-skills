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

runtime="$TEST_HOME/.config/opencode/ccl-skills/runtime"
expected_hook_count=2
cmp "$REPO_ROOT/hooks/host-input.py" "$runtime/hooks/host-input.py"
cmp "$REPO_ROOT/hooks/hooks.json" "$runtime/hooks/hooks.json"
for src in "$REPO_ROOT"/hooks/*.sh; do
  case "$(basename "$src")" in test_*) continue ;; esac
  cmp "$src" "$runtime/hooks/$(basename "$src")"
  expected_hook_count=$((expected_hook_count + 1))
done
test "$(find "$runtime/hooks" -maxdepth 1 -type f | wc -l | tr -d ' ')" = "$expected_hook_count"
test "$(find "$runtime/agent-context" -maxdepth 1 -type f | wc -l | tr -d ' ')" = 3
cmp "$REPO_ROOT/agent-context/session-start.md" "$runtime/agent-context/session-start.md"
cmp "$REPO_ROOT/agent-context/session-policy.md" "$runtime/agent-context/session-policy.md"
cmp "$REPO_ROOT/agent-context/session-policy.md" "$TEST_HOME/.config/opencode/ccl-skills/session-policy.md"
cmp "$REPO_ROOT/agent-context/session-start.md" "$TEST_HOME/.config/opencode/ccl-skills/bootstrap.md"
cmp "$REPO_ROOT/agent-context/subagent-start.md" "$runtime/agent-context/subagent-start.md"
cmp "$REPO_ROOT/scripts/owner-dispatch/owner-dispatch.sh" "$runtime/scripts/owner-dispatch/owner-dispatch.sh"

# Exercise the installed canonical guard, not the repository copy. A missing
# normalizer also denies patches, so require the protected-checkout reason.
protected="$TEST_HOME/protected"
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git init -q "$protected"
touch "$protected/.worktree-only"
payload=$(jq -nc --arg cwd "$protected" '{tool_name:"apply_patch",cwd:$cwd,tool_input:{command:"*** Begin Patch\n*** Add File: blocked.py\n+x\n*** End Patch"}}')
printf '%s' "$payload" | HOME="$TEST_HOME" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null bash "$runtime/hooks/guard-edit-isolation.sh" \
  | jq -e '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains(".worktree-only"))' >/dev/null

# Project mode uses a disposable source layout so it never writes .opencode in
# the working checkout. The implementation and hook assets are the real files.
project_source="$TEST_HOME/project-source"
mkdir -p "$project_source/scripts" "$project_source/packages/opencode-plugin/commands" "$project_source/skills/fixture-owner"
cp "$REPO_ROOT/scripts/install-opencode.sh" "$project_source/scripts/"
cp "$REPO_ROOT/packages/opencode-plugin/ccl-skills.ts" "$project_source/packages/opencode-plugin/"
printf '# Fixture command\n' > "$project_source/packages/opencode-plugin/commands/ccl-fixture.md"
printf '%s\n' '---' 'name: fixture-owner' '---' > "$project_source/skills/fixture-owner/SKILL.md"
cp -R "$REPO_ROOT/hooks" "$REPO_ROOT/agent-context" "$project_source/"
mkdir -p "$project_source/scripts/owner-dispatch"
cp "$REPO_ROOT/scripts/owner-dispatch/owner-dispatch.sh" "$project_source/scripts/owner-dispatch/"
HOME="$TEST_HOME" bash "$project_source/scripts/install-opencode.sh" --project > "$TEST_HOME/project-install.out"
project_data="$project_source/.opencode/ccl-skills"
cmp "$REPO_ROOT/hooks/host-input.py" "$project_data/runtime/hooks/host-input.py"
cmp "$REPO_ROOT/agent-context/session-policy.md" "$project_data/runtime/agent-context/session-policy.md"
cmp "$REPO_ROOT/agent-context/session-policy.md" "$project_data/session-policy.md"
cmp "$REPO_ROOT/agent-context/session-start.md" "$project_data/bootstrap.md"

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
