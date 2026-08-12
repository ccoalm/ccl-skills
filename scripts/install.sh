#!/usr/bin/env bash
# 一键安装 ccl-skills 多端入口（Claude Code + Codex plugin + OpenCode 原生 skills/plugin），并默认开启自动更新。
#
# 用法：
#   bash scripts/install.sh                      # 装 Claude/Codex plugin + OpenCode 原生 skills（不动 ~/.agents/skills）
#   bash scripts/install.sh --codex-cron         # 额外给 Codex 装每日 cron 伪自动更新
#   bash scripts/install.sh --with-agent-skills  # 额外同步已停更的 ~/.agents/skills 兼容路径（仅 Tabnine/Pi 等工具需要）
#
# 默认不再同步 ~/.agents/skills：该兼容路径已停更且不随 `make update` 刷新，
# 默认装上只会留下会长期变旧、还可能盖过 ~/.config/opencode/skills 最新版的副本
# （OpenCode 两个目录都扫，同名 skill 谁先解析用谁）。见 README「自动更新」。
#
# 各端自动更新能力不同：
#   - Claude Code：原生支持。脚本把 marketplace 的 autoUpdate 设为 true，启动时自动刷新+重装。
#   - Codex：无原生 auto-update。手动刷新用 `codex plugin marketplace upgrade && codex plugin add`
#     （upgrade 刷快照、plugin add 装入拷贝）；传 --codex-cron 则装每日 cron 跑这两步（伪自动，改 crontab，自行决定）。
#   - Agent Skills（--with-agent-skills 时）：Tabnine/Pi 等读取 ~/.agents/skills；用
#     `npx skills add <repo> --skill '*' -g -y` 安装/刷新，通常再重启对应工具或开新会话。

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"

HTTP_URL="https://github.com/ccoalm/ccl-skills.git"   # Claude marketplace 只认 http(s)
SSH_URL="https://github.com/ccoalm/ccl-skills.git"  # Codex marketplace 用 ssh
MP="ccl-skills"
PLUGIN="ccl-skills@ccl-skills"
CODEX_CRON=0
WITH_AGENT_SKILLS=0
for arg in "$@"; do
  case "$arg" in
    --codex-cron) CODEX_CRON=1 ;;
    --with-agent-skills) WITH_AGENT_SKILLS=1 ;;
    *) echo "Unknown option: ${arg}（可用：--codex-cron --with-agent-skills）"; exit 2 ;;
  esac
done

note() { printf '\n\033[1m%s\033[0m\n' "$*"; }

# ── Claude Code ────────────────────────────────────────────────────────────
if command -v claude >/dev/null 2>&1; then
  note "[Claude] 注册 marketplace + 安装 + 开自动更新"
  claude plugin marketplace add "$HTTP_URL" 2>&1 | tail -1 || true
  settings="$HOME/.claude/settings.json"
  if command -v jq >/dev/null 2>&1 && [ -f "$settings" ]; then
    # 写完整 extraKnownMarketplaces 条目（source + autoUpdate），开 Claude 原生自动更新。
    # 必须含 source：`plugin marketplace add` 只写 ~/.claude/plugins/known_marketplaces.json，
    # 不写 settings.json，所以这里只设 autoUpdate 会造出无 source 的非法条目，Claude 会
    # 整个 settings.json 跳过（连 env/token 一起失效）。整条赋值（merge）自愈已坏的条目。
    # 原子写：jq 输出到同目录临时文件，非空校验后再 mv 覆盖；jq 出错/输出为空都不动原 settings
    # （避免 `> $settings` 先截断后失败把含 token 的 settings 写没）。
    stmp="$(mktemp "${settings}.XXXXXX")"
    # `if type=="object"` 守：settings 不是 JSON 对象（null/数组/标量/坏 JSON）就 error→不写，原文件不动。
    if jq --arg mp "$MP" --arg url "$HTTP_URL" \
         'if type=="object" then (.extraKnownMarketplaces[$mp] = ((.extraKnownMarketplaces[$mp] // {}) + {source:{source:"git",url:$url}, autoUpdate:true})) else error("settings not an object") end' \
         "$settings" > "$stmp" 2>/dev/null && [ -s "$stmp" ]; then
      mv "$stmp" "$settings" \
        && echo "  ✔ settings.json: $MP marketplace(source+autoUpdate) 已写入"
    else
      rm -f "$stmp"
      echo "  ⚠ settings.json 未自动写入（jq 出错或 settings 非 JSON 对象），原文件未动；手动补：extraKnownMarketplaces.$MP = {\"source\":{\"source\":\"git\",\"url\":\"$HTTP_URL\"},\"autoUpdate\":true}。"
    fi
  else
    echo "  ⚠ 未自动写（缺 jq 或无 settings.json）；手动加完整条目：extraKnownMarketplaces.$MP = {\"source\":{\"source\":\"git\",\"url\":\"$HTTP_URL\"},\"autoUpdate\":true}。只填 autoUpdate 会让整个 settings.json 失效（见 README 的 \"Install and update\" 段）。"
  fi
  claude plugin install "$PLUGIN" 2>&1 | tail -1 || true
else
  echo "[Claude] 未检测到 claude CLI，跳过"
fi

# ── Codex ──────────────────────────────────────────────────────────────────
if command -v codex >/dev/null 2>&1; then
  note "[Codex] 注册 marketplace + 安装"
  codex plugin marketplace add "$SSH_URL" 2>&1 | tail -1 || true
  codex plugin add "$PLUGIN" 2>&1 | tail -1 || true
  if [ "$CODEX_CRON" = 1 ]; then
    line="0 9 * * * codex plugin marketplace upgrade >/dev/null 2>&1; codex plugin add $PLUGIN >/dev/null 2>&1"
    if crontab -l 2>/dev/null | grep -Fq "codex plugin marketplace upgrade"; then
      echo "  ✔ Codex cron 已存在，跳过"
    else
      ( crontab -l 2>/dev/null; echo "$line" ) | crontab - \
        && echo "  ✔ 已装每日 9:00 cron 刷新 Codex plugin"
    fi
  else
    echo "  ⓘ Codex 无原生自动更新。手动刷新：codex plugin marketplace upgrade && codex plugin add $PLUGIN"
    echo "    想要伪自动：重跑本脚本加 --codex-cron（装每日 cron）。"
  fi
else
  echo "[Codex] 未检测到 codex CLI，跳过"
fi

# ── OpenCode 原生 skills/plugin（默认 --no-agent；--with-agent-skills 时才同步已停更的 ~/.agents/skills）
if [ "$WITH_AGENT_SKILLS" = 1 ]; then
  bash "$SCRIPT_DIR/install-opencode.sh"
else
  bash "$SCRIPT_DIR/install-opencode.sh" --no-agent
fi

# ── 旧 symlink 提醒（plugin 与 symlink 二选一，避免重复加载）────────────────
note "检查旧 symlink"
found=0
for base in "$HOME/.claude/skills" "${CODEX_HOME:-$HOME/.codex}/skills"; do
  [ -d "$base" ] || continue
  for l in "$base"/*; do
    [ -L "$l" ] || continue
    case "$(readlink "$l")" in *ccoalm/ccl-skills*) echo "  ⚠ 残留 symlink：$l"; found=1;; esac
  done
done
[ "$found" = 1 ] && echo "  → Claude/Codex plugin 已接管，建议删掉上述 symlink（plugin 与 symlink 同装会重复加载）；不要删 OpenCode 自动读取的 ~/.agents/skills，也不要删 ~/.tabnine/agent/skills、~/.pi/agent/skills 这类指向 ~/.agents/skills 的工具消费 symlink。" || echo "  ✔ 无指向本仓库的旧 Claude/Codex symlink"

note "完成。重启 Claude Code / Codex / OpenCode / Tabnine / Pi 等对应客户端使新技能生效。"
