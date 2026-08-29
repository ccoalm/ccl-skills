#!/usr/bin/env bash
# Build slice-head.md: updated SKILL.md Workflow section + the reference surfaces
# a followed pointer would materialize (decision table + closeout checklist).
# Base slice was the same Workflow section, current tree (see AGENTS.md design note).
set -euo pipefail
cd "$(dirname "$0")"
SKILL=../../../skills/testing-strategy/SKILL.md
REF=../../../skills/testing-strategy/references/test-code-authoring-patterns.md
{
  awk '/^## Workflow$/{f=1} /^## Reference Loading$/{f=0} f' "$SKILL"
  echo
  echo "=====REFERENCE: test-code-authoring-patterns.md（决策表与自查表）====="
  awk '/^## 快速选用决策表$/{f=1} /^---$/{if(f)exit} f' "$REF"
} > slice-head.md
wc -c slice-head.md
grep -c "写完测试走查" slice-head.md >/dev/null || { echo "checklist missing from slice" >&2; exit 1; }
