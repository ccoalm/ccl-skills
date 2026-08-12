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
OPENCODE_MANIFEST_NAME="install-manifest.json"
PROJECT_MODE=0
SKIP_AGENT_SKILLS=0

for arg in "$@"; do
  case "$arg" in
    --project) PROJECT_MODE=1 ;;
    --no-agent) SKIP_AGENT_SKILLS=1 ;;
    -h|--help)
      cat <<'EOF'
Usage: bash scripts/install-opencode.sh [--project] [--no-agent]

Default:
  - sync skills to ~/.agents/skills for cross-tool compatibility
  - sync skills to ~/.config/opencode/skills for OpenCode native global discovery
  - install ~/.config/opencode/plugins/ccl-skills.ts
  - install ~/.config/opencode/ccl-skills/bootstrap.md
  - install ~/.config/opencode/commands/ccl-*.md

--project:
  sync skills, plugin, bootstrap, and commands only to .opencode/ in the current repository

--no-agent:
  skip the cross-tool ~/.agents/skills compat sync; install skills only to the
  OpenCode native config (~/.config/opencode/skills). No effect with --project
  (that mode never touches ~/.agents/skills).
EOF
      exit 0
      ;;
    *) echo "Unknown option: $arg"; exit 2 ;;
  esac
done

note() { printf '\n\033[1m%s\033[0m\n' "$*"; }

# One-step undo instead of destructive delete: replaced skill dirs are moved
# (not rm -rf'd) into a per-run backup dir OUTSIDE the skill scan root (so
# host tools never discover the backed-up SKILL.md copies); only the current
# run's backup is kept so growth stays bounded.
BACKUP_STAMP="$(date -u +%Y%m%dT%H%M%SZ)"

copy_dir_replace() {
  local src="$1"
  local dst="$2"
  local backup_dir="$3"

  if [ -e "$dst" ]; then
    mkdir -p "$backup_dir"
    mv "$dst" "$backup_dir/$(basename "$dst")"
  fi
  mkdir -p "$(dirname "$dst")"
  cp -R "$src" "$dst"
}

migrate_legacy_review_skill() {
  local dst_root="$1"
  local legacy_dir="$dst_root/claude-code-review"
  local backup_root backup_dir

  [ -d "$legacy_dir" ] || return 1
  if [ -f "$legacy_dir/SKILL.md" ] \
    && grep -qE '^name:[[:space:]]*claude-code-review[[:space:]]*$' "$legacy_dir/SKILL.md" \
    && [ -f "$legacy_dir/scripts/claude_review.sh" ]; then
    backup_root="$(dirname "$dst_root")/.ccl-skills-backup/$(basename "$dst_root")"
    backup_dir="$backup_root/$BACKUP_STAMP"
    mkdir -p "$backup_dir" || return 2
    mv "$legacy_dir" "$backup_dir/claude-code-review" || return 2
    echo "  ⓘ 旧 claude-code-review 已迁出 skill 扫描目录；现由 code-review 替代"
    return 0
  fi
  echo "  ⚠ 保留未识别的同名目录：${legacy_dir}（未按 CCL 旧 skill 结构自动迁移）"
  return 1
}

sync_skill_set() {
  local dst_root="$1"
  local backup_root backup_dir migration_rc replaced_any=0

  mkdir -p "$dst_root"
  # e.g. ~/.config/opencode/skills -> ~/.config/opencode/.ccl-skills-backup/skills
  backup_root="$(dirname "$dst_root")/.ccl-skills-backup/$(basename "$dst_root")"
  backup_dir="$backup_root/$BACKUP_STAMP"
  # Keep only this run's backup: clear older stamps before the first move.
  if [ -d "$backup_root" ]; then
    find "$backup_root" -mindepth 1 -maxdepth 1 ! -name "$BACKUP_STAMP" -exec rm -rf {} +
  fi
  if migrate_legacy_review_skill "$dst_root"; then
    replaced_any=1
  else
    migration_rc=$?
    [ "$migration_rc" -eq 1 ] || return "$migration_rc"
  fi
  for src in "$REPO_ROOT"/skills/*; do
    [ -d "$src" ] || continue
    [ -e "$dst_root/$(basename "$src")" ] && replaced_any=1
    copy_dir_replace "$src" "$dst_root/$(basename "$src")" "$backup_dir"
  done
  if [ "$replaced_any" = 1 ]; then
    echo "  ⓘ 被替换的旧版本已移入 ${backup_dir}（仅保留最近一次，可整目录 mv 回去回滚）"
  fi
}

sync_commands() {
  local dst_root="$1"

  mkdir -p "$dst_root"
  rm -f "$dst_root"/ccl-*.md
  cp "$REPO_ROOT"/packages/opencode-plugin/commands/ccl-*.md "$dst_root"/
}

source_commit() {
  git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || printf 'unknown'
}

write_manifest() {
  local data_dir="$1"
  local mode="$2"
  local manifest="$data_dir/$OPENCODE_MANIFEST_NAME"

  mkdir -p "$data_dir"
cat > "$manifest" <<EOF
{
  "installed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "source_commit": "$(source_commit)",
  "install_mode": "$mode",
  "installer": "scripts/install-opencode.sh"
}
EOF
}

install_opencode_assets() {
  local base="$1"
  local data_dir="$2"

  sync_skill_set "$base/skills"
  sync_commands "$base/commands"
  mkdir -p "$base/plugins" "$data_dir"
  cp "$OPENCODE_PLUGIN_SRC" "$base/plugins/ccl-skills.ts"
  cp "$OPENCODE_BOOTSTRAP_SRC" "$data_dir/bootstrap.md"
  write_manifest "$data_dir" "project"
}

if [ "$PROJECT_MODE" = 0 ]; then
  note "[OpenCode] 安装/刷新全局 skills"

  sync_skill_set "$OPENCODE_SKILLS_DIR"
  echo "  ✔ OpenCode 原生全局 skills 已同步：$OPENCODE_SKILLS_DIR"

  if [ "$SKIP_AGENT_SKILLS" = 0 ]; then
    sync_skill_set "$AGENT_SKILLS_DIR"
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
    mkdir -p "$OPENCODE_PLUGIN_DIR" "$OPENCODE_DATA_DIR"
    sync_commands "$OPENCODE_COMMANDS_DIR"
    cp "$OPENCODE_PLUGIN_SRC" "$OPENCODE_PLUGIN_DST"
    cp "$OPENCODE_BOOTSTRAP_SRC" "$OPENCODE_BOOTSTRAP_DST"
    write_manifest "$OPENCODE_DATA_DIR" "global"
    echo "  ✔ OpenCode plugin 已安装：$OPENCODE_PLUGIN_DST"
    echo "  ✔ OpenCode bootstrap 已安装：$OPENCODE_BOOTSTRAP_DST"
    echo "  ✔ OpenCode install manifest 已写入：$OPENCODE_DATA_DIR/$OPENCODE_MANIFEST_NAME"
    echo "  ✔ OpenCode commands 已安装：$OPENCODE_COMMANDS_DIR/ccl-*.md"
    echo "    - 注入本仓 agent-context/session-start.md"
    echo "    - 拦截主检出 edit/write（.worktree-only 标记仓不分分支；有并行活动 worktree 时也拦截）"
  else
    echo "  ⚠ 未找到 OpenCode plugin 源文件：$OPENCODE_PLUGIN_SRC"
  fi
fi

if [ "$PROJECT_MODE" = 1 ]; then
  note "[OpenCode] 同步项目级 .opencode/"
  install_opencode_assets "$REPO_ROOT/.opencode" "$REPO_ROOT/.opencode/ccl-skills"
  echo "  ✔ 项目级 skills/commands/plugin 已同步到：$REPO_ROOT/.opencode"
fi

echo "  ⓘ 重启 OpenCode 或开新会话后生效"
