#!/usr/bin/env bash
# 把本仓 OpenCode command 快捷入口安装到目标项目的 opencode.json。
# 只合并 command 字段和缺失的 $schema；不写模型、MCP、权限、个人路径或密钥。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
SOURCE_CONFIG="$REPO_ROOT/opencode.json"
TARGET_DIR="${1:-.}"
FORCE=0

shift $(( $# > 0 ? 1 : 0 ))
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    -h|--help)
      cat <<'EOF'
Usage: bash scripts/install-opencode-commands.sh [project-dir] [--force]

Install ccl-skills OpenCode commands into a project's OpenCode config.

Default behavior:
  - updates <project-dir>/opencode.json when it exists
  - otherwise updates <project-dir>/.opencode/opencode.json when it exists
  - otherwise creates <project-dir>/opencode.json
  - creates a timestamped .bak backup when the file exists
  - adds missing commands from this repo's opencode.json
  - refuses to overwrite same-name commands unless --force is passed
  - never writes models, MCPs, providers, permissions, or secrets
EOF
      exit 0
      ;;
    *) echo "未知参数：$arg" >&2; exit 2 ;;
  esac
done

TARGET_DIR="$(cd "$TARGET_DIR" && pwd -P)"
if [ -f "$TARGET_DIR/opencode.json" ]; then
  TARGET_CONFIG="$TARGET_DIR/opencode.json"
elif [ -f "$TARGET_DIR/.opencode/opencode.json" ]; then
  TARGET_CONFIG="$TARGET_DIR/.opencode/opencode.json"
else
  TARGET_CONFIG="$TARGET_DIR/opencode.json"
fi

if [ ! -f "$SOURCE_CONFIG" ]; then
  echo "未找到源配置：$SOURCE_CONFIG" >&2
  exit 1
fi

SOURCE_CONFIG="$SOURCE_CONFIG" TARGET_CONFIG="$TARGET_CONFIG" FORCE="$FORCE" python3 - <<'PY'
import json
import os
import pathlib
import shutil
import sys
from datetime import datetime

source_path = pathlib.Path(os.environ["SOURCE_CONFIG"])
target_path = pathlib.Path(os.environ["TARGET_CONFIG"])
force = os.environ.get("FORCE") == "1"

with source_path.open(encoding="utf-8") as source_file:
    source = json.load(source_file)

source_commands = source.get("command")
if not isinstance(source_commands, dict) or not source_commands:
    raise SystemExit(f"source command is missing or invalid: {source_path}")

if target_path.exists():
    with target_path.open(encoding="utf-8") as target_file:
        target = json.load(target_file)
else:
    target = {}

if not isinstance(target, dict):
    raise SystemExit(f"target config must be a JSON object: {target_path}")

target_commands = target.setdefault("command", {})
if_not_dict = not isinstance(target_commands, dict)
if if_not_dict:
    raise SystemExit(f"target command must be a JSON object: {target_path}")

conflicts = sorted(name for name in source_commands if name in target_commands and not force)
if conflicts:
    print("同名 command 已存在，未覆盖：" + ", ".join(conflicts), file=sys.stderr)
    print("如确认要覆盖，请重跑并加 --force。", file=sys.stderr)
    raise SystemExit(3)

if target_path.exists():
    suffix = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_path = target_path.with_name(target_path.name + f".bak.{suffix}")
    counter = 1
    while backup_path.exists():
        backup_path = target_path.with_name(target_path.name + f".bak.{suffix}.{counter}")
        counter += 1
    shutil.copy2(target_path, backup_path)
    print(f"  ✔ 已备份：{backup_path}")

added = []
updated = []
for name, command in source_commands.items():
    if name in target_commands:
        updated.append(name)
    else:
        added.append(name)
    target_commands[name] = command

target.setdefault("$schema", "https://opencode.ai/config.json")
target_path.write_text(json.dumps(target, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

print(f"  ✔ 已写入：{target_path}")
print("  ✔ 新增 command：" + (", ".join(added) if added else "无"))
if updated:
    print("  ✔ 覆盖 command：" + ", ".join(updated))
PY

echo "  ⓘ 重启 OpenCode 或在目标项目开新会话后生效。"
