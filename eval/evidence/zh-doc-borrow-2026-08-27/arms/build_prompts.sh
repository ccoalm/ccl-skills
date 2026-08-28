#!/bin/bash
# 从本目录臂文本确定性重建当轮 headless 差分的逐字 prompt。
# 运行设置：claude -p --model claude-sonnet-5，cwd=空白临时目录（隔离项目 CLAUDE.md 与 auto-memory），n=3/臂。
set -euo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
require_arm() { [ -r "$1" ] && [ -s "$1" ] || { echo "FATAL: arm file 不可读或为空: $1" >&2; exit 1; }; }
promptA() { require_arm "$1"; cat <<P
你是文档审查助手。只按下面的规则清单审查待审文本，逐条列出规则命中的问题（引用原文+指出所依规则）；不得使用清单之外的判断。

【规则清单】
$(cat "$1")

【待审文本】
1. 系统会对返回结果进行校验，并对超时情况加以处理。
2. 服务启动时会加载插件并重建索引。这会拖慢启动速度。
3. 本次升级全面提升了系统性能。
4. 构建产物写入 dist 目录。
P
}
promptB2() { require_arm "$1"; cat <<P
你是交付收尾助手。只按下面的规则清单回答；清单没有规定的就答「清单未规定」，不得使用清单之外的判断。

场景：你刚把一份含结论与风险标注的文档发布到某协作文档平台；已调用平台回读接口，确认本轮新增的结论段落与修订时间已出现在远端；团队的结构校验脚本也已对回读内容跑过且通过。

问题：交付收尾还需要人工通读（人读 sweep）这份文档吗？请回答「需要 / 不需要 / 清单未规定」之一，并引用所依规则原文。

【规则清单】
$(cat "$1")
P
}
promptA2() { require_arm "$1"; cat <<P
你是文档审查助手。只按下面的规则清单审查待审文本，逐条列出规则命中的问题（引用原文+指出所依规则）；不得使用清单之外的判断。

【规则清单】
$(cat "$1")

【待审文本】
1. 打包器维护一份依赖清单。缓存目录在每次构建前被清空。它随后被写入锁文件。
2. 本次升级全面提升了系统性能。
3. 构建产物写入 dist 目录。
P
}
case "${1:-}" in
  A-old) promptA "$D/armA-old.txt";;
  A-new) promptA "$D/armA-new.txt";;
  A2-old) promptA2 "$D/armA-old.txt";;
  A2-new) promptA2 "$D/armA-new.txt";;
  B2-old) promptB2 "$D/armB-old.txt";;
  B2-new) promptB2 "$D/armB-new.txt";;
  *) echo "usage: $0 A-old|A-new|A2-old|A2-new|B2-old|B2-new" >&2; exit 2;;
esac
