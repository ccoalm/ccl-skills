#!/usr/bin/env bash
# 安装/刷新 OpenCode 使用的 skills、commands 和本地 plugin。
# 默认安装全局 OpenCode 原生路径，同时保留 ~/.agents/skills 兼容路径；传 --project 同步到当前项目 .opencode/。

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
OPENCODE_PLUGIN_DIR="$HOME/.config/opencode/plugins"
OPENCODE_DATA_DIR="$HOME/.config/opencode/ccl-skills"
OPENCODE_SKILLS_DIR="$HOME/.config/opencode/skills"
OPENCODE_COMMANDS_DIR="$HOME/.config/opencode/commands"
AGENT_SKILLS_DIR="$HOME/.agents/skills"
OPENCODE_PLUGIN_SRC="$REPO_ROOT/packages/opencode-plugin/ccl-skills.ts"
OPENCODE_PLUGIN_DST="$OPENCODE_PLUGIN_DIR/ccl-skills.ts"
# Source path is the repo's agent-context asset; the installed artifact name
# stays bootstrap.md (uninstall manifests and the plugin runtime key on it).
OPENCODE_BOOTSTRAP_SRC="$REPO_ROOT/agent-context/session-start.md"
OPENCODE_BOOTSTRAP_DST="$OPENCODE_DATA_DIR/bootstrap.md"
OPENCODE_RUNTIME_DIR="$OPENCODE_DATA_DIR/runtime"
OPENCODE_MANIFEST_NAME="install-manifest.json"
PROJECT_MODE=0
SKIP_AGENT_SKILLS=0
ONLY_AGENT_SKILLS=0

for arg in "$@"; do
  case "$arg" in
    --project) PROJECT_MODE=1 ;;
    --no-agent) SKIP_AGENT_SKILLS=1 ;;
    --only-agent) ONLY_AGENT_SKILLS=1 ;;
    -h|--help)
      cat <<'EOF'
Usage: bash scripts/install-opencode.sh [--project] [--no-agent] | --only-agent

Default:
  - sync skills to ~/.agents/skills for cross-tool compatibility
  - sync skills to ~/.config/opencode/skills for OpenCode native global discovery
  - install ~/.config/opencode/plugins/ccl-skills.ts
  - install ~/.config/opencode/ccl-skills/bootstrap.md
  - install ~/.config/opencode/ccl-skills/runtime (host hook runtime)
  - install ~/.config/opencode/commands/ccl-*.md

--project:
  sync skills, plugin, bootstrap, hook runtime, and commands only to .opencode/ in the current repository

--no-agent:
  skip the cross-tool ~/.agents/skills compat sync; install skills only to the
  OpenCode native config (~/.config/opencode/skills). No effect with --project
  (that mode never touches ~/.agents/skills).

--only-agent:
  sync only ~/.agents/skills for cross-tool compatibility, without OpenCode assets.
  Cannot be combined with --project or --no-agent.
EOF
      exit 0
      ;;
    *) echo "Unknown option: $arg"; exit 2 ;;
  esac
done

if [ "$ONLY_AGENT_SKILLS" = 1 ] && { [ "$PROJECT_MODE" = 1 ] || [ "$SKIP_AGENT_SKILLS" = 1 ]; }; then
  echo "--only-agent cannot be combined with --project or --no-agent" >&2
  exit 2
fi

note() { printf '\n\033[1m%s\033[0m\n' "$*"; }

# Keep the first replaced directory outside the skill scan root while an
# installation is pending. Retries retain it; only complete installs rotate
# the pending set into the latest directory-level recovery copy.
BACKUP_STAMP="$(date -u +%Y%m%dT%H%M%SZ)-$$" || exit "$?"
BACKUP_ROOTS=()

preserve_replaced_dir() {
  local dst="$1" backup_dir="$2" saved retry
  saved="$backup_dir/$(basename "$dst")"

  [ ! -L "$backup_dir" ] || return 1
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    mkdir -p "$backup_dir" || return "$?"
    if [ -e "$saved" ] || [ -L "$saved" ]; then
      retry="$saved.retry.$BACKUP_STAMP"
      [ ! -e "$retry" ] && [ ! -L "$retry" ] || return 1
      mv "$dst" "$retry" || return "$?"
    else
      mv "$dst" "$saved" || return "$?"
    fi
  fi
}

copy_dir_replace() {
  local src="$1" dst="$2" backup_dir="$3"

  preserve_replaced_dir "$dst" "$backup_dir" || return "$?"
  mkdir -p "$(dirname "$dst")" || return "$?"
  cp -R "$src" "$dst"
}

finish_backups() {
  local root pending previous
  for root in "${BACKUP_ROOTS[@]}"; do
    pending="$root/.pending"
    [ ! -L "$pending" ] || return 1
    [ -d "$pending" ] || continue
    [ ! -e "$root/$BACKUP_STAMP" ] && [ ! -L "$root/$BACKUP_STAMP" ] || return 1
    mv "$pending" "$root/$BACKUP_STAMP" || return 1
    for previous in "$root"/*; do
      [ "$previous" != "$root/$BACKUP_STAMP" ] || continue
      [[ "${previous##*/}" =~ ^[0-9]{8}T[0-9]{6}Z(-[0-9]+)?$ ]] || continue
      [ -d "$previous" ] && [ ! -L "$previous" ] || continue
      rm -rf -- "$previous" || return 1
    done
    echo "  ⓘ 恢复副本保留于 $root/$BACKUP_STAMP"
  done
}

migrate_legacy_review_skill() {
  local dst_root="$1"
  local legacy_dir="$dst_root/claude-code-review"
  local backup_root backup_dir

  backup_root="$(dirname "$dst_root")/.ccl-skills-backup/$(basename "$dst_root")"
  BACKUP_ROOTS+=("$backup_root")
  [ -d "$legacy_dir" ] || return 1
  if [ -f "$legacy_dir/SKILL.md" ] \
    && grep -qE '^name:[[:space:]]*claude-code-review[[:space:]]*$' "$legacy_dir/SKILL.md" \
    && [ -f "$legacy_dir/scripts/claude_review.sh" ]; then
    backup_dir="$backup_root/.pending"
    preserve_replaced_dir "$legacy_dir" "$backup_dir" || return 2
    echo "  ⓘ 旧 claude-code-review 已迁出 skill 扫描目录；现由 code-review 替代"
    return 0
  fi
  echo "  ⚠ 保留未识别的同名目录：${legacy_dir}（未按 CCL 旧 skill 结构自动迁移）"
  return 1
}

sync_skill_set() {
  local dst_root="$1"
  local backup_root backup_dir migration_rc replaced_any=0

  mkdir -p "$dst_root" || return "$?"
  # e.g. ~/.config/opencode/skills -> ~/.config/opencode/.ccl-skills-backup/skills
  backup_root="$(dirname "$dst_root")/.ccl-skills-backup/$(basename "$dst_root")"
  backup_dir="$backup_root/.pending"
  BACKUP_ROOTS+=("$backup_root")
  if migrate_legacy_review_skill "$dst_root"; then
    replaced_any=1
  else
    migration_rc=$?
    [ "$migration_rc" -eq 1 ] || return "$migration_rc"
  fi
  for src in "$REPO_ROOT"/skills/*; do
    [ -d "$src" ] || continue
    [ -e "$dst_root/$(basename "$src")" ] && replaced_any=1
    copy_dir_replace "$src" "$dst_root/$(basename "$src")" "$backup_dir" || return "$?"
  done
  if [ "$replaced_any" = 1 ]; then
    echo "  ⓘ 安装完成前保留原目录副本：${backup_dir}"
  fi
}

sync_commands() {
  local dst_root="$1"

  mkdir -p "$dst_root" || return "$?"
  cp "$REPO_ROOT"/packages/opencode-plugin/commands/ccl-*.md "$dst_root"/
}

sync_runtime() {
  local data_dir="$1"
  local runtime="$data_dir/runtime"
  local backup="$data_dir/.runtime-backup/.pending"
  local stage src

  BACKUP_ROOTS+=("$data_dir/.runtime-backup")
  mkdir -p "$data_dir" || return 1
  stage=$(mktemp -d "$data_dir/.runtime-stage.XXXXXX") || return 1
  case "$stage" in "$data_dir"/.runtime-stage.*) ;; *) return 1 ;; esac
  mkdir -p "$stage/hooks" "$stage/scripts/owner-dispatch" "$stage/agent-context" || { rm -rf -- "$stage"; return 1; }
  cp "$REPO_ROOT/hooks/hooks.json" "$stage/hooks/" || { rm -rf -- "$stage"; return 1; }
  for src in "$REPO_ROOT"/hooks/*.sh; do
    case "$(basename "$src")" in test_*) continue ;; esac
    cp "$src" "$stage/hooks/" || { rm -rf -- "$stage"; return 1; }
  done
  cp "$REPO_ROOT/scripts/owner-dispatch/owner-dispatch.sh" "$stage/scripts/owner-dispatch/" || { rm -rf -- "$stage"; return 1; }
  cp "$REPO_ROOT/agent-context/session-start.md" "$REPO_ROOT/agent-context/subagent-start.md" "$stage/agent-context/" || { rm -rf -- "$stage"; return 1; }

  mkdir -p "$runtime" || { rm -rf -- "$stage"; return 1; }
  copy_dir_replace "$stage/hooks" "$runtime/hooks" "$backup" || { rm -rf -- "$stage"; return 1; }
  mkdir -p "$runtime/scripts" || { rm -rf -- "$stage"; return 1; }
  copy_dir_replace "$stage/scripts/owner-dispatch" "$runtime/scripts/owner-dispatch" "$backup" || { rm -rf -- "$stage"; return 1; }
  copy_dir_replace "$stage/agent-context" "$runtime/agent-context" "$backup" || { rm -rf -- "$stage"; return 1; }
  rm -rf -- "$stage" || return 1
}

source_commit() {
  git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || printf 'unknown'
}

write_manifest() {
  local data_dir="$1"
  local mode="$2"
  local manifest="$data_dir/$OPENCODE_MANIFEST_NAME"
  local temporary installed_at

  mkdir -p "$data_dir" || return "$?"
  installed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" || return "$?"
  temporary="$(mktemp "$manifest.XXXXXX")" || return "$?"
  if ! cat > "$temporary" <<EOF
{
  "installed_at": "$installed_at",
  "source_commit": "$(source_commit)",
  "install_mode": "$mode",
  "installer": "scripts/install-opencode.sh"
}
EOF
  then
    rm -f "$temporary"
    return 1
  fi
  mv "$temporary" "$manifest" || { rm -f "$temporary"; return 1; }
}

install_opencode_assets() {
  local base="$1"
  local data_dir="$2"

  sync_skill_set "$base/skills" || return "$?"
  sync_commands "$base/commands" || return "$?"
  mkdir -p "$base/plugins" "$data_dir" || return "$?"
  cp "$OPENCODE_PLUGIN_SRC" "$base/plugins/ccl-skills.ts" || return "$?"
  cp "$OPENCODE_BOOTSTRAP_SRC" "$data_dir/bootstrap.md" || return "$?"
  sync_runtime "$data_dir" || return 1
  write_manifest "$data_dir" "project"
}

if [ "$ONLY_AGENT_SKILLS" = 1 ]; then
  note "[Agent Skills] 安装/刷新兼容路径"
  sync_skill_set "$AGENT_SKILLS_DIR" || exit "$?"
  finish_backups || { echo "安装内容已更新，备份整理失败；请保留恢复副本" >&2; exit 1; }
  echo "  ✔ 通用 Agent Skills 兼容路径已同步：$AGENT_SKILLS_DIR"
  exit 0
fi

if [ "$PROJECT_MODE" = 0 ]; then
  note "[OpenCode] 安装/刷新全局 skills"

  sync_skill_set "$OPENCODE_SKILLS_DIR" || exit "$?"
  echo "  ✔ OpenCode 原生全局 skills 已同步：$OPENCODE_SKILLS_DIR"

  if [ "$SKIP_AGENT_SKILLS" = 0 ]; then
    sync_skill_set "$AGENT_SKILLS_DIR" || exit "$?"
    echo "  ✔ 通用 Agent Skills 兼容路径已同步：$AGENT_SKILLS_DIR"
  else
    if migrate_legacy_review_skill "$AGENT_SKILLS_DIR"; then
      echo "  ⓘ --no-agent 仅完成旧 reviewer skill 迁移，未同步其他兼容 skills"
    else
      migration_rc=$?
      [ "$migration_rc" -eq 1 ] || exit "$migration_rc"
    fi
    echo "  ⓘ --no-agent：跳过 ~/.agents/skills 兼容同步（${AGENT_SKILLS_DIR}）"
  fi
fi

if [ "$PROJECT_MODE" = 0 ]; then
  if [ -f "$OPENCODE_PLUGIN_SRC" ]; then
    mkdir -p "$OPENCODE_PLUGIN_DIR" "$OPENCODE_DATA_DIR" || exit "$?"
    sync_commands "$OPENCODE_COMMANDS_DIR" || exit "$?"
    cp "$OPENCODE_PLUGIN_SRC" "$OPENCODE_PLUGIN_DST" || exit "$?"
    cp "$OPENCODE_BOOTSTRAP_SRC" "$OPENCODE_BOOTSTRAP_DST" || exit "$?"
    sync_runtime "$OPENCODE_DATA_DIR" || exit 1
    write_manifest "$OPENCODE_DATA_DIR" "global" || exit "$?"
    echo "  ✔ OpenCode plugin 已安装：$OPENCODE_PLUGIN_DST"
    echo "  ✔ OpenCode bootstrap 已安装：$OPENCODE_BOOTSTRAP_DST"
    echo "  ✔ OpenCode hooks runtime 已安装：$OPENCODE_RUNTIME_DIR"
    echo "  ✔ OpenCode install manifest 已写入：$OPENCODE_DATA_DIR/$OPENCODE_MANIFEST_NAME"
    echo "  ✔ OpenCode commands 已安装：$OPENCODE_COMMANDS_DIR/ccl-*.md"
    echo "    - 注入本仓 agent-context/session-start.md"
    echo "    - 拦截主检出 edit/write/apply_patch（.worktree-only 标记仓不分分支；有并行活动 worktree 时也拦截）"
  else
    echo "  ⚠ 未找到 OpenCode plugin 源文件：$OPENCODE_PLUGIN_SRC" >&2
    exit 1
  fi
fi

if [ "$PROJECT_MODE" = 1 ]; then
  note "[OpenCode] 同步项目级 .opencode/"
  install_opencode_assets "$REPO_ROOT/.opencode" "$REPO_ROOT/.opencode/ccl-skills" || exit "$?"
  echo "  ✔ 项目级 skills/commands/plugin 已同步到：$REPO_ROOT/.opencode"
fi

finish_backups || { echo "安装内容已更新，备份整理失败；请保留恢复副本" >&2; exit 1; }
echo "  ⓘ 重启 OpenCode 或开新会话后生效"
