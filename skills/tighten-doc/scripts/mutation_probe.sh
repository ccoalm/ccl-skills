#!/usr/bin/env bash
# 差分敏感度实测：逐谓词把其 code 字面量替换掉使其在结果中消失，
# 确认自测套件转红。绿的谓词 = 该谓词没有覆盖。
#
# 为什么必须"施加"而不是"断言"：本目录实测踩过两种无效突变——
#   ① 改的是 add() 的 severity 参数，而断言比较 code 集合，
#      改了 oracle 不观测的维度，全绿是假通过；
#   ② 脚本崩溃时也没有 FAIL 行，只看 FAIL 行会把崩溃读成绿。
# 所以判据同时看退出码与 FAIL 行。
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
work="$(mktemp -d)"; trap 'rm -rf "${work}"' EXIT
cp -R "${here}" "${work}/scripts"
cd "${work}/scripts" || exit 1

bash test_figure_and_doc_lint.sh >/dev/null 2>&1 || {
  echo "BASELINE-RED: 未突变时套件就是红的，实验无效"; exit 1; }
echo "baseline: GREEN"

# 谓词清单从**源码派生**，不手写：手写清单会漏掉新增谓词，
# 而漏掉的那条就没有任何覆盖。独立评审实测抓到过——手写的 24 条里
# 漏了 PARSE / C4-VIEWBOX / C4-EDGE-VAGUE 三条。
extract_codes() {  # <linter-file>
  # 必须覆盖**所有发射路径**。早先只认 add(...) 与错误元组，
  # 漏掉了走 findings.append({'code': ...}) 的 CONTRACT-MISSING / CONTRACT-INVALID——
  # 分母因此偏小，"全部谓词均有覆盖"是未经验证的声明。
  python3 - "$1" <<'PYEOF'
import re, sys
src = open(sys.argv[1], encoding="utf8").read()
pats = [
    r"""add\(\s*['"](?:ERROR|WARN)['"]\s*,\s*['"]([A-Z0-9][A-Z0-9-]*)['"]""",   # add('ERROR', 'CODE'
    r"""\(\s*['"](?:ERROR|WARN)['"]\s*,\s*['"]([A-Z0-9][A-Z0-9-]*)['"]""",      # ('ERROR', 'CODE'
    r"""['"]code['"]\s*:\s*['"]([A-Z0-9][A-Z0-9-]*)['"]""",                    # {'code': 'CODE'
]
codes = set()
for pat in pats:
    codes |= set(re.findall(pat, src))
codes.discard("MUTANT-GONE")
for c in sorted(codes):
    print(c)
PYEOF
}
codes_fig="$(extract_codes figure-lint.py)"
codes_doc="$(extract_codes doc-lint.py)"
echo "codes_from_source: figure=$(echo "${codes_fig}" | wc -w | tr -d ' ') doc=$(echo "${codes_doc}" | wc -w | tr -d ' ')"

pass=0; total=0; missed=""
probe() {
  local file="$1" code="$2"
  total=$((total + 1))
  cp "${file}" "${file}.bak"
  MUT_FILE="${file}" MUT_CODE="${code}" python3 -c '
import os
p = os.environ["MUT_FILE"]
s = open(p, encoding="utf8").read()
open(p, "w").write(s.replace("'"'"'" + os.environ["MUT_CODE"] + "'"'"'", "'"'"'MUTANT-GONE'"'"'"))
'
  local out rc
  out="$(bash test_figure_and_doc_lint.sh 2>&1)"; rc=$?
  mv "${file}.bak" "${file}"
  if [ "${rc}" -ne 0 ] && printf '%s' "${out}" | grep -q FAIL; then
    pass=$((pass + 1)); printf '  %-28s RED  ok\n' "${code}"
  else
    missed="${missed} ${code}"; printf '  %-28s GREEN  NO-COVERAGE\n' "${code}"
  fi
}
for c in ${codes_fig}; do probe figure-lint.py "${c}"; done
for c in ${codes_doc}; do probe doc-lint.py "${c}"; done
# 派生集合必须覆盖 linter 在自测语料上实际输出过的每一个 code。
# 不断言的话，一条新增谓词只要用了未被派生正则识别的发射路径，就会静默无覆盖。
emitted="$(
  { python3 figure-lint.py tests/svg/*.svg --json 2>/dev/null || true
    python3 doc-lint.py tests/doc/*.md --json 2>/dev/null || true
  } | python3 -c '
import json, sys
codes = set()
for chunk in sys.stdin.read().split("\n{"):
    text = chunk if chunk.startswith("{") else "{" + chunk
    try:
        d = json.loads(text)
    except Exception:
        continue
    for v in d.get("files", d).values():   # doc-lint 的 JSON 顶层就是文件映射，没有 files 键
        codes |= {x["code"] for x in v["findings"]}
print(" ".join(sorted(codes)))
')"
# codes_* 是换行分隔的，必须先规范成单空格分隔再做包含匹配，
# 否则 case 模式永远匹配不上、把每一条都误报成缺口（本脚本实测踩过）。
derived=" $(printf '%s %s' "${codes_fig}" "${codes_doc}" | tr '\n' ' ' | tr -s ' ') "
for c in ${emitted}; do
  case "${derived}" in
    *" ${c} "*) ;;
    *) echo "DERIVATION-GAP: ${c} 实际会被输出，却不在派生清单里——该谓词无突变覆盖"; missed="${missed} ${c}";;
  esac
done
echo "differential_sensitivity=${pass}/${total}"
[ -n "${missed}" ] && { echo "uncovered:${missed}"; exit 1; }
echo "mutation_probe_ok"
