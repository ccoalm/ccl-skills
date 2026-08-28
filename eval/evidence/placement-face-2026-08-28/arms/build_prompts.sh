#!/bin/bash
# 从本目录臂文本确定性重建当轮 headless 差分的逐字 prompt。
# 运行设置：claude -p --model claude-sonnet-5，cwd=空白临时目录（隔离项目 CLAUDE.md 与 auto-memory），n=3/臂。
set -euo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
require_arm() { [ -r "$1" ] && [ -s "$1" ] || { echo "FATAL: arm file 不可读或为空: $1" >&2; exit 1; }; }
build() { require_arm "$1"; cat <<P
你是交付收尾助手。只按下面的规则清单回答；清单没有规定的就答「清单未规定」，不得使用清单之外的判断。

场景：你写好一份新文档，要放进团队的多级目录知识库并交付。

请分十问作答：
A) 决定放在哪个目录之前，清单要求做什么？请列出清单要求的全部前置动作，不要省略。
B) 目录怎么选，清单给了什么判据？
C) 发布后、报「已同步」之前，清单要求核什么？请列出清单要求的全部核验项，不要省略。
D) 若发布后发现文档实际可见范围比预期更宽，清单要求怎么处理？
E) 放置前，对目标容器的访问边界清单要求做什么？
F) 发布后发现落点的 owner 不是预期主体，清单要求怎么处理？
G) 交付信息里，文档的路径怎么给？
H) 预期受众 / 边界 / owner 没有任何既有记录可依时，清单要求怎么办？
I) 边界权威的裁决怎么才算数？
J) 定位核验本身构成对结构移动或权限变更的授权吗？

【规则清单】
$(cat "$1")
P
}
case "${1:-}" in
  old) build "$D/arm-old.txt";;
  new) build "$D/arm-new.txt";;
  *) echo "usage: $0 old|new" >&2; exit 2;;
esac
