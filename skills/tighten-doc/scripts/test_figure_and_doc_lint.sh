#!/usr/bin/env bash
# 逐谓词差分自测：每个 fixture 只应触发它自己的那一条，控制组必须干净。
#
# 这是 references/figure-and-table-craft.md §8 第 1、2 条的机械化：
#   1) 先证明检查器能报失败再信它的绿；
#   2) 改判据必须同步改 fixture——本测试就是"fixture 失效但仍通过"的防线。
#
# 已踩过的坑，改本文件前先读：
#   - CJK 标点紧跟 $var 会被 bash 吞进变量名（踩过两次）——插值一律用 ${var}。
#   - 改函数签名必须同步改调用点：曾把 ext 参数加进签名却漏改调用点，
#     第一条期望（控制组）被当成 ext 吃掉，control.svg 变脏仍全绿。
#     现在参数不足会直接判红，且期望表是**全量对应**：报告里多一个或少一个文件都判红，
#     所以意外文件（如通配到 figure-contract.json）不会再被无声忽略。
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
fail=0

note() { printf '%s\n' "$*"; }
bad()  { printf 'FAIL %s\n' "$*"; fail=1; }

# run_expect <linter> <fixture-dir> <ext> <expectation>...
#   expectation 形如 "file=CODE[,CODE]"；等号后为空表示该 fixture 必须干净。
run_expect() {
  if [ "$#" -lt 4 ]; then
    bad "run_expect 参数不足（需 linter dir ext expectation...），实得 $# 个"; return
  fi
  local linter="$1" dir="$2" ext="$3"; shift 3
  local json
  # 两个 linter 在有发现时都返回非 0（json 模式亦然），所以不能用退出码判执行失败；
  # 判据是"输出能否解析成 JSON"。
  json="$(python3 "${here}/${linter}" "${dir}"/*."${ext}" --json 2>/dev/null)"
  printf '%s' "${json}" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null || {
    bad "${linter} 未产出可解析 JSON（${dir}）"; return; }

  local result
  result="$(printf '%s' "${json}" | LINT_EXPECT="$*" python3 -c '
import json, sys, os
d = json.load(sys.stdin)
files = d.get("files", d)
actual = {os.path.basename(k): sorted({x["code"] for x in v["findings"]}) for k, v in files.items()}
want = {}
for spec in os.environ["LINT_EXPECT"].split():
    name, _, codes = spec.partition("=")
    want[name] = sorted(c for c in codes.split(",") if c)
problems = []
for name in sorted(set(want) - set(actual)):
    problems.append("期望表列了但报告里没有: " + name)
for name in sorted(set(actual) - set(want)):
    problems.append("报告里出现但期望表未列（发现=%s）: %s" % (actual[name] or [], name))
for name in sorted(set(want) & set(actual)):
    if want[name] != actual[name]:
        problems.append("%s 期望 %s 实得 %s" % (name, want[name] or [], actual[name] or []))
print("\n".join(problems))
')" || { bad "${linter} 结果比对失败"; return; }
  if [ -n "${result}" ]; then
    while IFS= read -r line; do
      [ -n "${line}" ] && bad "${linter}: ${line}"
    done <<<"${result}"
  fi
}

note "== figure-lint 逐谓词差分 =="
run_expect figure-lint.py "${here}/tests/svg" svg \
  'control.svg=' \
  'no-title.svg=C4-TITLE' \
  'no-legend.svg=C4-LEGEND' \
  'low-contrast.svg=WCAG-143' \
  'overflow.svg=SVG-OVERFLOW' \
  'no-group.svg=GROUPING' \
  'ungrouped-card.svg=GROUPING' \
  'unlabeled-edge.svg=C4-EDGE-LABEL' \
  'offcontract-shape.svg=CONTRACT-COLOR-TOKEN' \
  'malformed.svg=PARSE' \
  'bad-viewbox.svg=GEOMETRY' \
  'no-viewbox.svg=C4-VIEWBOX' \
  'edge-no-arrow.svg=C4-EDGE-DIRECTION' \
  'edge-vague.svg=C4-EDGE-VAGUE' \
  'transformed.svg=CONTRAST-UNSUPPORTED' \
  'crossings.svg=GRAPH-CROSSINGS' \
  'figure-is-a-list.svg=FIGURE-IS-A-LIST,GROUPING' \
  'flow-mixed.svg=FLOW-DIRECTION-MIXED' \
  'no-aria.svg=FIGURE-A11Y-STRUCTURE' \
  'cvd-confusable.svg=' \
  'decorative-line.svg=' \
  'blackmarker.svg=CONTRACT-COLOR-TOKEN'

note "== doc-lint 逐谓词差分 =="
run_expect doc-lint.py "${here}/tests/doc" md \
  'control.md=' \
  'tables-only-clean.md=' \
  'fake-header.md=WCAG-131-FAKE-HEADING' \
  'no-unit.md=TABLE-NO-UNIT' \
  'should-be-chart.md=ICD203-9-SHOULD-BE-CHART' \
  'imbalance.md=CARRIER-IMBALANCE,ICD203-9-SHOULD-BE-CHART' \
  'fig-dangling.md=FIG-REF-DANGLING' \
  'fig-orphan.md=FIG-ORPHAN' \
  'fig-orphan-captioned.md=FIG-ORPHAN' \
  'empty-header.md=WCAG-131-TABLE' \
  'wide-table.md=TABLE-WIDE' \
  'unfilled.md=TABLE-UNFILLED' \
  'fenced-noise.md='

# 无契约时应提示「重复出现的值该成为 token」——独立目录，避免污染契约测试
t3="$(mktemp -d)"
# 需要一张「多种颜色各重复多次」的图才触发；就地合成，不入仓
python3 - "${t3}/multi.svg" <<'SVGEOF'
import sys
cols = ["#0072B2", "#D55E00", "#009E73", "#CC79A7", "#E69F00"]
parts = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 200" role="img" aria-label="many repeated colours"><title>many repeated colours</title><g>']
y = 5
for c in cols:
    for _ in range(3):
        parts.append(f'<rect x="10" y="{y}" width="12" height="8" fill="{c}"/>')
        y += 10
parts.append("</g></svg>")
open(sys.argv[1], "w").write("".join(parts))
SVGEOF
out2="$(python3 "${here}/figure-lint.py" "${t3}"/*.svg 2>/dev/null)"; rc2=$?
case "${out2}" in *VALUE-SHOULD-BE-TOKEN*) ;; *) bad "无契约且多色重复时未报 VALUE-SHOULD-BE-TOKEN";; esac
[ "${rc2}" = 1 ] || bad "多色重复用例退出码应为 1(CONTRACT-MISSING 是 ERROR)，实得 ${rc2}"
# 规则写的是「>2 次即应成 token」——单一颜色重复 3 次同样要报，否则规则与实现不一致
python3 - "${t3}/one.svg" <<'SVGEOF2'
import sys
parts = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 200" role="img" aria-label="one repeated colour"><title>one repeated colour</title><g>']
y = 5
for _ in range(3):
    parts.append(f'<rect x="10" y="{y}" width="12" height="8" fill="#0072B2"/>')
    y += 10
parts.append("</g></svg>")
open(sys.argv[1], "w").write("".join(parts))
SVGEOF2
out2b="$(python3 "${here}/figure-lint.py" "${t3}/one.svg" 2>/dev/null)"; rc2b=$?
case "${out2b}" in *VALUE-SHOULD-BE-TOKEN*) ;; *) bad "单色重复 3 次未报 VALUE-SHOULD-BE-TOKEN（规则与实现不一致）";; esac
[ "${rc2b}" = 1 ] || bad "单色重复用例退出码应为 1(CONTRACT-MISSING 是 ERROR)，实得 ${rc2b}"
rm -rf "${t3}"

# CVD 距离只在契约**显式声明语义色**时测量，且只报数不下判定
t3b="$(mktemp -d)"
cp "${here}/tests/svg/cvd-confusable.svg" "${t3b}/"
cat >"${t3b}/figure-contract.json" <<'JSON'
{ "canvas_ratios": [2.0], "font_scale": [14],
  "color_tokens": {"ink":"#111827","warn":"#B54708","crit":"#B42318","ok":"#009E73","surface":"#FFFFFF"},
  "semantic_colors": {"warning":"#B54708","critical":"#B42318","ok":"#009E73"} }
JSON
out3b="$(python3 "${here}/figure-lint.py" "${t3b}/cvd-confusable.svg" 2>/dev/null)"; rc3b=$?
case "${out3b}" in *CVD-DISTANCE*) ;; *) bad "契约声明语义色后未测量 CVD-DISTANCE";; esac
case "${out3b}" in *"测量值不是判定"*) ;; *) bad "CVD-DISTANCE 文案未声明这是测量值";; esac
# 「只报数不设阈」若让退出码变成非零，这句声明就被退出码当场推翻——必须是 INFO 档、退出码 0
[ "${rc3b}" = 0 ] || bad "只有 CVD-DISTANCE 测量时退出码应为 0(INFO 不阻断)，实得 ${rc3b}"
case "${out3b}" in *INFO*) ;; *) bad "CVD-DISTANCE 未标为 INFO 档";; esac
# semantic_colors 非法必须报 CONTRACT-INVALID，不得崩溃、也不得静默丢成空集
for bad_sc in '["#B54708","#B42318"]' '"#B54708"' '{"a":"red","b":"#B42318"}' '{"a":"#123456","b":"#B42318"}'; do
  cat >"${t3b}/figure-contract.json" <<JSON
{ "canvas_ratios": [2.0], "font_scale": [14],
  "color_tokens": {"ink":"#111827","warn":"#B54708","crit":"#B42318","ok":"#009E73","surface":"#FFFFFF"},
  "semantic_colors": ${bad_sc} }
JSON
  o="$(python3 "${here}/figure-lint.py" "${t3b}/cvd-confusable.svg" 2>&1)"; r=$?
  case "${o}" in *CONTRACT-INVALID*) ;; *) bad "非法 semantic_colors ${bad_sc} 未报 CONTRACT-INVALID";; esac
  case "${o}" in *Traceback*) bad "非法 semantic_colors ${bad_sc} 让检查器崩溃";; esac
  [ "${r}" = 1 ] || bad "非法 semantic_colors ${bad_sc} 应为 ERROR(退出码 1)，实得 ${r}"
done
# 未声明语义色时不得凭渲染色臆断语义
out3c="$(python3 "${here}/figure-lint.py" "${here}/tests/svg/cvd-confusable.svg" 2>/dev/null || true)"
case "${out3c}" in *CVD-*) bad "契约未声明语义色却报了 CVD-*（把装饰色当语义色）";; esac
rm -rf "${t3b}"

# 主题维度：同一套写死的色在另一主题底上会失效；纯黑底另有提示。
t4="$(mktemp -d)"
cp "${here}/tests/svg/control.svg" "${t4}/"
cat >"${t4}/figure-contract.json" <<'JSON'
{ "canvas_ratios": [2.0], "font_scale": [13,14],
  "color_tokens": {"ink":"#111827","primary":"#0072B2","critical":"#D55E00","ok":"#009E73","surface":"#FFFFFF"},
  "themes": { "light": {"surface":"#FFFFFF"}, "dark": {"surface":"#000000"} } }
JSON
out4="$(python3 "${here}/figure-lint.py" "${t4}"/control.svg 2>/dev/null)"; rc4=$?
[ "${rc4}" = 2 ] || bad "主题用例退出码应为 2(仅 WARN)，实得 ${rc4}"
case "${out4}" in *THEME-CONTRAST*) ;; *) bad "深色主题下未报 THEME-CONTRAST";; esac
case "${out4}" in *THEME-PURE-BLACK*) ;; *) bad "纯黑主题底未报 THEME-PURE-BLACK";; esac
# 主题底色不是合法 #RRGGBB 时必须报契约非法——否则该主题被静默跳过 = 假绿
cat >"${t4}/figure-contract.json" <<'JSON'
{ "canvas_ratios": [2.0], "font_scale": [13,14],
  "color_tokens": {"ink":"#111827","primary":"#0072B2","critical":"#D55E00","ok":"#009E73","surface":"#FFFFFF"},
  "themes": { "light": {"surface":"#FFFFFF"}, "dark": {"surface":"black"} } }
JSON
out4b="$(python3 "${here}/figure-lint.py" "${t4}"/control.svg 2>/dev/null)"; rc4b=$?
case "${out4b}" in *CONTRACT-INVALID*) ;; *) bad "themes.dark.surface 非十六进制未报 CONTRACT-INVALID（静默跳过=假绿）";; esac
[ "${rc4b}" = 1 ] || bad "契约非法应为 ERROR(退出码 1)，实得 ${rc4b}"
cat >"${t4}/figure-contract.json" <<'JSON'
{ "canvas_ratios": [2.0], "font_scale": [13,14],
  "color_tokens": {"ink":"#111827","primary":"#0072B2","critical":"#D55E00","ok":"#009E73","surface":"#FFFFFF"},
  "themes": { "light": {"surface":"#FFFFFF"}, "dark": {"surface":[255]} } }
JSON
out4c="$(python3 "${here}/figure-lint.py" "${t4}"/control.svg 2>/dev/null || true)"
case "${out4c}" in *CONTRACT-INVALID*) ;; *) bad "themes.dark.surface 非字符串未报 CONTRACT-INVALID";; esac

# 底色解析不可信时，主题对比度不得凭全局底色判——必须显式报未判定
t4u="$(mktemp -d)"
cp "${here}/tests/svg/transformed.svg" "${t4u}/"
cat >"${t4u}/figure-contract.json" <<'JSON'
{ "canvas_ratios": [2.0], "font_scale": [13,14],
  "color_tokens": {"ink":"#111827","primary":"#0072B2","surface":"#FFFFFF"},
  "themes": { "light": {"surface":"#FFFFFF"}, "dark": {"surface":"#0B0F19"} } }
JSON
out4u="$(python3 "${here}/figure-lint.py" "${t4u}/transformed.svg" 2>/dev/null || true)"
case "${out4u}" in *THEME-UNASSESSED*) ;; *) bad "几何不可信时未报 THEME-UNASSESSED";; esac
case "${out4u}" in *THEME-CONTRAST*) bad "几何不可信时仍判 THEME-CONTRAST（拿不可信底色判出的假红）";; esac
rm -rf "${t4u}"

# fill="none" 的描边框不是底板：包住低对比文字的边框不得豁免 THEME-CONTRAST
t4s="$(mktemp -d)"
cat >"${t4s}/stroked.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 200" role="img" aria-label="stroked box"><title>stroked box</title><g>
<rect x="0" y="0" width="400" height="200" fill="#FFFFFF"/>
<rect x="20" y="20" width="200" height="60" fill="none" stroke="#0072B2"/>
<text x="30" y="55" font-size="14" fill="#111827">深色小字</text>
</g></svg>
SVG
cat >"${t4s}/figure-contract.json" <<'JSON'
{ "canvas_ratios": [2.0], "font_scale": [14],
  "color_tokens": {"ink":"#111827","primary":"#0072B2","surface":"#FFFFFF"},
  "themes": { "light": {"surface":"#FFFFFF"}, "dark": {"surface":"#0B0F19"} } }
JSON
out4s="$(python3 "${here}/figure-lint.py" "${t4s}/stroked.svg" 2>/dev/null || true)"
case "${out4s}" in *THEME-CONTRAST*) ;; *) bad "fill=none 的描边框被当成底板，豁免了 THEME-CONTRAST";; esac
rm -rf "${t4s}"

# 两端都没箭头的无向连接不得按 d 的书写顺序造出方向
t5="$(mktemp -d)"
cat >"${t5}/undirected.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 200" role="img" aria-label="undirected"><title>undirected</title>
<defs><marker id="a" refX="10" refY="6"><path d="M1 1L11 6L1 11Z" fill="#0072B2"/></marker></defs><g>
<rect x="0" y="0" width="400" height="200" fill="#FFFFFF"/>
<path d="M10 20L200 20" fill="none" stroke="#0072B2"/>
<path d="M200 60L10 60" fill="none" stroke="#0072B2"/>
<path d="M10 100L200 100" fill="none" stroke="#0072B2"/>
<path d="M200 140L10 140" fill="none" stroke="#0072B2"/>
</g></svg>
SVG
out5="$(python3 "${here}/figure-lint.py" "${t5}/undirected.svg" 2>/dev/null || true)"
case "${out5}" in *FLOW-DIRECTION-MIXED*) bad "无箭头的连接被按 d 书写顺序判成混合流向";; esac
rm -rf "${t5}"

# 主题相符时不得误报
cat >"${t4}/figure-contract.json" <<'JSON'
{ "canvas_ratios": [2.0], "font_scale": [13,14],
  "color_tokens": {"ink":"#111827","primary":"#0072B2","critical":"#D55E00","ok":"#009E73","surface":"#FFFFFF"},
  "themes": { "light": {"surface":"#FFFFFF"} } }
JSON
out5="$(python3 "${here}/figure-lint.py" "${t4}"/control.svg 2>/dev/null || true)"
case "${out5}" in *THEME-CONTRAST*) bad "单一浅色主题下误报 THEME-CONTRAST";; esac
rm -rf "${t4}"

# ---- 契约符合性：缺失 / 相符 / 不符 / 损坏 / 多目录 ----
note "== figure-lint 契约符合性 =="
tmp="$(mktemp -d)"; t2="$(mktemp -d)"
trap 'rm -rf "${tmp}" "${t2}"' EXIT
cp "${here}/tests/svg/control.svg" "${tmp}/"

out="$(python3 "${here}/figure-lint.py" "${tmp}" 2>/dev/null || true)"
case "${out}" in *CONTRACT-MISSING*) ;; *) bad "契约缺失时未报 CONTRACT-MISSING";; esac


# 相符：取 control.svg 的真实取值，必须干净（写负例前先核对 fixture 真值，
# 否则会写出一份"其实相符"的契约让断言永远绿——本轮实际踩过）。
cat >"${tmp}/figure-contract.json" <<'JSON'
{ "canvas_ratios": [2.0], "font_scale": [13, 14],
  "color_tokens": { "ink": "#111827", "primary": "#0072B2", "critical": "#D55E00",
                    "ok": "#009E73", "surface": "#FFFFFF" } }
JSON
out="$(python3 "${here}/figure-lint.py" "${tmp}" 2>/dev/null || true)"
case "${out}" in *CONTRACT-MISSING*) bad "契约存在时仍报 CONTRACT-MISSING";; esac
case "${out}" in
  *CONTRACT-RATIO*|*CONTRACT-FONT-SCALE*|*CONTRACT-COLOR-TOKEN*)
    bad "契约与 fixture 相符却报了偏离（假阳性）";;
esac

# 不符：三维各自断言。写成 OR（三选一命中即过）会让其余两维永久失去覆盖——
# 突变实测过：删掉 CONTRACT-RATIO 后套件仍绿，因为 FONT-SCALE 顶上了。
cat >"${tmp}/figure-contract.json" <<'JSON'
{ "canvas_ratios": [1.778], "font_scale": [99], "color_tokens": { "ink": "#000000" } }
JSON
out="$(python3 "${here}/figure-lint.py" "${tmp}" 2>/dev/null || true)"
for want in CONTRACT-RATIO CONTRACT-FONT-SCALE CONTRACT-COLOR-TOKEN; do
  case "${out}" in
    *"${want}"*) ;;
    *) bad "契约不符时未报 ${want}——该维度的契约检查形同虚设";;
  esac
done

# 损坏：语法错与类型非法都必须报 CONTRACT-INVALID 且不得崩溃。
printf '{ "canvas_ratios": [1.778,, }' >"${tmp}/figure-contract.json"
out="$(python3 "${here}/figure-lint.py" "${tmp}" 2>/dev/null || true)"
case "${out}" in *CONTRACT-INVALID*) ;; *) bad "契约语法损坏时未报 CONTRACT-INVALID";; esac

cat >"${tmp}/figure-contract.json" <<'JSON'
{ "canvas_ratios": "not-a-list", "font_scale": [ {"x": 1} ], "color_tokens": 42 }
JSON
out="$(python3 "${here}/figure-lint.py" "${tmp}" 2>/dev/null || true)"
case "${out}" in *CONTRACT-INVALID*) ;; *) bad "契约类型非法时未报 CONTRACT-INVALID（或已崩溃）";; esac

# 多目录：两棵树各有自己的契约，必须各按各的最近契约判，不能用第一棵的套第二棵。
mkdir -p "${t2}/a" "${t2}/b"
cp "${here}/tests/svg/control.svg" "${t2}/a/"
cp "${here}/tests/svg/control.svg" "${t2}/b/"
cat >"${t2}/a/figure-contract.json" <<'JSON'
{ "canvas_ratios": [2.0], "font_scale": [13, 14],
  "color_tokens": { "ink": "#111827", "primary": "#0072B2", "critical": "#D55E00",
                    "ok": "#009E73", "surface": "#FFFFFF" } }
JSON
cat >"${t2}/b/figure-contract.json" <<'JSON'
{ "canvas_ratios": [1.5], "font_scale": [13, 14],
  "color_tokens": { "ink": "#111827", "primary": "#0072B2", "critical": "#D55E00",
                    "ok": "#009E73", "surface": "#FFFFFF" } }
JSON
out="$(python3 "${here}/figure-lint.py" "${t2}/a/control.svg" "${t2}/b/control.svg" --json 2>/dev/null || true)"
printf '%s' "${out}" | python3 -c '
import json, sys, os
d = json.load(sys.stdin)
per = {os.path.basename(os.path.dirname(k)): sorted({x["code"] for x in v["findings"]})
       for k, v in d["files"].items()}
sys.exit(0 if per.get("a") == [] and "CONTRACT-RATIO" in per.get("b", []) else 1)
' 2>/dev/null || bad "多目录时未按各自最近的契约判定（a 应干净、b 应报 CONTRACT-RATIO）"

# ---- 退出码契约回归 ----
# 两个 CLI 都声明「ERROR=1 / 仅 WARN=2 / 干净=0」，普通与 --json 模式一致。
# 此前套件全程忽略退出码（|| true），把 1 改成 0 也不会转红——契约无保护。
note "== 退出码契约（0 干净 / 2 仅 WARN / 1 有 ERROR）=="
assert_rc() {  # <期望码> <说明> <命令...>
  "${@:3}" >/dev/null 2>&1
  local rc=$?
  [ "${rc}" -eq "$1" ] || bad "退出码契约：$2 期望 $1 实得 ${rc}"
}
for mode in "" "--json"; do
  label="${mode:-plain}"
  assert_rc 0 "figure-lint 干净(${label})" python3 "${here}/figure-lint.py" "${here}/tests/svg/control.svg" ${mode}
  assert_rc 1 "figure-lint 有 ERROR(${label})" python3 "${here}/figure-lint.py" "${here}/tests/svg/no-title.svg" ${mode}
  assert_rc 2 "figure-lint 仅 WARN(${label})" python3 "${here}/figure-lint.py" "${here}/tests/svg/transformed.svg" ${mode}
  assert_rc 0 "doc-lint 干净(${label})" python3 "${here}/doc-lint.py" "${here}/tests/doc/control.md" ${mode}
  assert_rc 1 "doc-lint 有 ERROR(${label})" python3 "${here}/doc-lint.py" "${here}/tests/doc/fig-dangling.md" ${mode}
  assert_rc 2 "doc-lint 仅 WARN(${label})" python3 "${here}/doc-lint.py" "${here}/tests/doc/no-unit.md" ${mode}
done

# ---- 读取失败不得中断整批 ----
# 非 UTF-8 fixture **不入仓**：提交进去会打断全仓扫描器（R0 审计实测 sed 报
# illegal byte sequence）。临时生成即可。
note "== 读取失败隔离 =="
python3 -c "open('${tmp}/non-utf8.svg','wb').write(b'<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 10 10\"><title>\xff\xfe</title></svg>')"
cp "${here}/tests/svg/control.svg" "${tmp}/ok.svg"
cp "${here}/tests/svg/figure-contract.json" "${tmp}/"
mixed="$(python3 "${here}/figure-lint.py" "${tmp}/non-utf8.svg" "${tmp}/ok.svg" --json 2>/dev/null)"
printf '%s' "${mixed}" | python3 -c '
import json, sys, os
d = json.load(sys.stdin)
per = {os.path.basename(k): sorted({x["code"] for x in v["findings"]}) for k, v in d["files"].items()}
ok = per.get("non-utf8.svg") == ["READ"] and per.get("ok.svg") == []
sys.exit(0 if ok else 1)
' 2>/dev/null || bad "坏文件未被隔离：期望 non-utf8.svg=[READ] 且 ok.svg 干净，实得 ${mixed}"

# doc-lint 同样：坏 .md 报 READ 并继续，不得静默判干净。
python3 -c "open('${tmp}/bad.md','wb').write(b'# t\n\xff\xfe\n')"
cp "${here}/tests/doc/control.md" "${tmp}/good.md"
dmixed="$(python3 "${here}/doc-lint.py" "${tmp}/bad.md" "${tmp}/good.md" --json 2>/dev/null)"
printf '%s' "${dmixed}" | python3 -c '
import json, sys, os
d = json.load(sys.stdin)
per = {os.path.basename(k): sorted({x["code"] for x in v["findings"]}) for k, v in d.get("files", d).items()}
sys.exit(0 if per.get("bad.md") == ["READ"] and per.get("good.md") == [] else 1)
' 2>/dev/null || bad "doc-lint 坏文件未被隔离：期望 bad.md=[READ] 且 good.md 干净，实得 ${dmixed}"

if [ "${fail}" -eq 0 ]; then
  note "OK: figure-lint / doc-lint 逐谓词差分与契约五态全部符合预期"
fi
exit "${fail}"
