#!/usr/bin/env bash
# Verifies the recoverable install migrations for retired skills: claude-code-review ->
# code-review, and the two stack architecture skills -> software-architecture.
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

# A retired architecture skill is recognised by its own frontmatter name plus a
# file only the shipped skill carried. Both scan roots are covered, and a
# same-named directory that is not the shipped skill must survive untouched.
# Recognition also requires the SKILL.md to be a version this repository
# shipped, so the fixture installs the last shipped entry from history.
shipped_entry() { # <name>
  local last
  last="$(git -C "$REPO_ROOT" rev-list -n 1 HEAD -- "skills/$1/SKILL.md")"
  [ -n "$last" ] || { echo "no history for skills/$1/SKILL.md (needs full history)" >&2; return 1; }
  if git -C "$REPO_ROOT" cat-file -e "$last:skills/$1/SKILL.md" 2>/dev/null; then
    git -C "$REPO_ROOT" show "$last:skills/$1/SKILL.md"
  else
    git -C "$REPO_ROOT" show "$last^:skills/$1/SKILL.md"
  fi
}
make_retired_arch() { # <skills-root> <name>
  mkdir -p "$1/$2/references"
  shipped_entry "$2" >"$1/$2/SKILL.md"
  : >"$1/$2/references/architecture-playbook.md"
}
native_root="$TEST_HOME/.config/opencode/skills"
compat_root="$TEST_HOME/.agents/skills"
make_retired_arch "$native_root" go-microservice-architecture
make_retired_arch "$native_root" python-service-architecture
make_retired_arch "$compat_root" go-microservice-architecture
mkdir -p "$compat_root/python-service-architecture"
printf '%s\n' 'personal directory with the same name' >"$compat_root/python-service-architecture/KEEP"

HOME="$TEST_HOME" bash "$REPO_ROOT/scripts/install-opencode.sh" \
  >"$TEST_HOME/install.out"

test ! -e "$native_legacy"
test -f "$TEST_HOME/.config/opencode/skills/code-review/SKILL.md"
test -f "$compat_legacy/KEEP"
find "$TEST_HOME/.config/opencode/.ccl-skills-backup/skills" \
  -path '*/claude-code-review/SKILL.md' -type f | grep -q .
grep -q '保留未识别的同名目录' "$TEST_HOME/install.out"

test ! -e "$native_root/go-microservice-architecture"
test ! -e "$native_root/python-service-architecture"
test ! -e "$compat_root/go-microservice-architecture"
test -f "$native_root/software-architecture/SKILL.md"
test -f "$compat_root/software-architecture/SKILL.md"
test -f "$compat_root/python-service-architecture/KEEP"
for retired in go-microservice-architecture python-service-architecture; do
  find "$TEST_HOME/.config/opencode/.ccl-skills-backup/skills" \
    -path "*/$retired/SKILL.md" -type f | grep -q .
done
find "$TEST_HOME/.agents/.ccl-skills-backup/skills" \
  -path '*/go-microservice-architecture/SKILL.md' -type f | grep -q .
! find "$TEST_HOME/.agents/.ccl-skills-backup/skills" \
  -path '*/python-service-architecture/*' | grep -q .
grep -q '旧 go-microservice-architecture 已迁出 skill 扫描目录；现由 software-architecture 替代' "$TEST_HOME/install.out"

# A second install over the migrated home is a no-op for the retired names: they
# stay gone and the unrecognised directory is still left alone.
HOME="$TEST_HOME" bash "$REPO_ROOT/scripts/install-opencode.sh" >"$TEST_HOME/install-again.out"
test ! -e "$native_root/go-microservice-architecture"
test -f "$compat_root/python-service-architecture/KEEP"

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
make_retired_arch "$NO_AGENT_HOME/.agents/skills" python-service-architecture
HOME="$NO_AGENT_HOME" bash "$REPO_ROOT/scripts/install-opencode.sh" --no-agent \
  >"$NO_AGENT_HOME/install.out"
test ! -e "$no_agent_legacy"
find "$NO_AGENT_HOME/.agents/.ccl-skills-backup/skills" \
  -path '*/claude-code-review/SKILL.md' -type f | grep -q .
test ! -e "$NO_AGENT_HOME/.agents/skills/code-review"
test ! -e "$NO_AGENT_HOME/.agents/skills/python-service-architecture"
test ! -e "$NO_AGENT_HOME/.agents/skills/software-architecture"
find "$NO_AGENT_HOME/.agents/.ccl-skills-backup/skills" \
  -path '*/python-service-architecture/SKILL.md' -type f | grep -q .

# Recognition reads the frontmatter name only. A personal skill whose own
# frontmatter names something else stays put even when its body quotes the
# retired name in a frontmatter-shaped line and it carries the same marker file.
FM_HOME="$(mktemp -d "${TMPDIR:-/tmp}/ccl-skills-install-fm.XXXXXX")"
trap 'rm -rf "$TEST_HOME" "$NO_AGENT_HOME" "$FM_HOME"' EXIT
fm_dir="$FM_HOME/.config/opencode/skills/go-microservice-architecture"
mkdir -p "$fm_dir/references"
printf '%s\n' '---' 'name: my-architecture-notes' '---' '' 'Example frontmatter:' '' 'name: go-microservice-architecture' >"$fm_dir/SKILL.md"
: >"$fm_dir/references/architecture-playbook.md"
HOME="$FM_HOME" bash "$REPO_ROOT/scripts/install-opencode.sh" --no-agent >"$FM_HOME/install.out"
test -f "$fm_dir/SKILL.md"
grep -q '保留未识别的同名目录' "$FM_HOME/install.out"

# A personal skill that declares the retired name and carries the marker file,
# but whose SKILL.md is not a shipped version, is kept too.
same_dir="$FM_HOME/.config/opencode/skills/python-service-architecture"
mkdir -p "$same_dir/references"
printf '%s\n' '---' 'name: python-service-architecture' 'description: my own notes' '---' '' 'Personal content.' >"$same_dir/SKILL.md"
: >"$same_dir/references/architecture-playbook.md"
HOME="$FM_HOME" bash "$REPO_ROOT/scripts/install-opencode.sh" --no-agent >"$FM_HOME/install-same.out"
test -f "$same_dir/SKILL.md"
grep -q "保留未识别的同名目录：$same_dir" "$FM_HOME/install-same.out"

# The FIRST name field decides even when it is empty: a later name line must
# not turn an unnamed directory into a recognised one. The marker-proof row is
# the one where the name alone decides, so the case uses it.
empty_dir="$FM_HOME/.config/opencode/skills/claude-code-review"
mkdir -p "$empty_dir/scripts"
printf '%s\n' '---' 'name:   ' 'name: claude-code-review' '---' >"$empty_dir/SKILL.md"
: >"$empty_dir/scripts/claude_review.sh"
HOME="$FM_HOME" bash "$REPO_ROOT/scripts/install-opencode.sh" --no-agent >"$FM_HOME/install-empty.out"
test -f "$empty_dir/SKILL.md"

printf '%s\n' install_opencode_skill_migration_tests_ok
