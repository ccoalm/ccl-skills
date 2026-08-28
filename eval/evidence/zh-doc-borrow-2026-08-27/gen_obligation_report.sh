#!/bin/bash
# 义务检查器 + base→head 报告生成器（zh-doc-borrow 交付面收缩的零损核对）。
# 覆盖全部已声明义务（移出→reference 的 8 条 + 留在入口的摘要锚 + 双载体设计项 + 节头限定 + 新增规则锚），
# 逐条数**出现次数**（grep -oF|wc -l，非行数），任一与期望不符即 exit 1。
# 用法：在仓根跑
#   bash eval/evidence/zh-doc-borrow-2026-08-27/gen_obligation_report.sh <base-ref>            # 报告+检查
#   bash eval/evidence/zh-doc-borrow-2026-08-27/gen_obligation_report.sh <base-ref> --self-test # 另证明失败路径可触发
# 复核：diff <(bash .../gen_obligation_report.sh <base-ref>) .../obligation-report.txt
set -uo pipefail
BASE="${1:?usage: gen_obligation_report.sh <base-ref> [--self-test]}"
MODE="${2:-}"
REF=skills/tighten-doc/references/delivery-face-closeout.md
SK=skills/tighten-doc/SKILL.md
FAIL=0

count_in() { # file phrase -> occurrence count
  grep -oF -- "$2" "$1" 2>/dev/null | wc -l | tr -d ' '
}
count_pkg() { # phrase -> occurrence count across the whole package
  grep -roF -- "$1" skills/tighten-doc/ 2>/dev/null | wc -l | tr -d ' '
}
check() { # scope(SK|REF|PKG) expected phrase label
  local scope="$1" exp="$2" phrase="$3" label="$4" got
  case "$scope" in
    SK)  got="$(count_in "$SK" "$phrase")";;
    REF) got="$(count_in "$REF" "$phrase")";;
    PKG) got="$(count_pkg "$phrase")";;
  esac
  if [ "$got" = "$exp" ]; then
    printf 'PASS [%s expect=%s got=%s] %s\n' "$scope" "$exp" "$got" "$label"
  else
    printf 'FAIL [%s expect=%s got=%s] %s :: %s\n' "$scope" "$exp" "$got" "$label" "$phrase"
    FAIL=1
  fi
}

echo "== base 交付面 bullet（${BASE}） =="
BASE_SHA="$(git rev-parse --verify "${BASE}^{commit}" 2>/dev/null)" || { echo "FAIL: 无法把 ${BASE} 解析为提交——base 不可用"; echo 'obligation_check_failed'; exit 1; }
BASE_CONTENT="$(git show "$BASE_SHA:$SK" 2>/dev/null)" || { echo "FAIL: git show ${BASE_SHA}:$SK 失败——base 不可读，未做任何 base→head 核对"; echo 'obligation_check_failed'; exit 1; }
BASE_BULLET="$(printf '%s\n' "$BASE_CONTENT" | grep -n '交付面：改完' || true)"
BASE_BULLET_N="$(printf '%s' "$BASE_BULLET" | grep -c . || true)"
if [ "$BASE_BULLET_N" != 1 ]; then echo "FAIL: base 交付面 bullet 行数=${BASE_BULLET_N}（期望 1）——base 形态不符，拒绝继续"; echo 'obligation_check_failed'; exit 1; fi
printf '%s\n' "$BASE_BULLET"
echo "base 解析为不可变提交：${BASE_SHA}（全部 base 读取均经此 SHA，无 TOCTOU 窗口）"
BASE_BULLET_TEXT="${BASE_BULLET#*:}"
count_base_bullet() { printf '%s' "$BASE_BULLET_TEXT" | grep -oF -- "$1" | wc -l | tr -d ' '; }
echo
echo "== base 侧断言：每条「被移」义务必须确实存在于 base bullet（否则『移出』主张不成立） =="
while IFS= read -r bp; do
  [ -n "$bp" ] || continue
  got="$(count_base_bullet "$bp")"
  if [ "$got" -ge 1 ]; then
    printf 'PASS [BASE>=1 got=%s] %s\n' "$got" "$bp"
  else
    printf 'FAIL [BASE>=1 got=%s] %s\n' "$got" "$bp"
    FAIL=1
  fi
done <<'BASEPHRASES'
超时后半成、权限被拒、覆盖到错误的页面、缓存仍吐旧版
「不投放」只能是经授权的排除
已过期 → 指向新版
可折叠节点、悬浮标签、可滚动区、分页表
比不出交互 → 静态这一次性的丢失
不构成处置
本地改完、远端还是旧版是最常见的静默残缺
旧版退役只用归档或原位标
判定与执行都不归本技能
BASEPHRASES
echo
echo "== head 交付面 bullet =="
grep -n '交付面：改完' "$SK"
echo
echo "== 目的地文件现行全文（${REF}） =="
nl -ba "$REF"
echo
echo "== 义务检查（出现次数计，任一不符 exit 1） =="
# —— 移出入口、载体应唯一在 reference：PKG=1（全包唯一）且 REF=1（定位在目的地）双查 ——
for spec in   '超时后半成、权限被拒、覆盖到错误的页面、缓存仍吐旧版|①投放失败形态枚举'   '「不投放」只能是经授权的排除|①不投放仅限授权排除'   '已过期 → 指向新版|②两种可逆退役之原位标'   '归档到明确的历史目录|②两种可逆退役之归档'   '不构成处置|②可逆做法不构成被要求删除的处置'   '可折叠节点、悬浮标签、可滚动区、分页表|③交互源形态枚举'   '比不出交互 → 静态这一次性的丢失|③oracle 区分句'
do
  phrase="${spec%%|*}"; label="${spec##*|}"
  check PKG 1 "$phrase" "${label}（全包唯一）"
  check REF 1 "$phrase" "${label}（定位于目的地）"
done
check REF 1 '处置**不归本技能**' '②处置判定与执行不归本技能（rephrased 载体）'
check REF 1 '本地看着已发、远端还是旧的' '①静默残缺 rationale（rephrased 载体）'
check REF 1 '旧版退役只用**可逆的两种**' '②退役排他限定「只用…两种」（目的地）'
# —— 留在入口的摘要义务锚（SKILL 内计数=1）——
check SK 1 '核到本轮的可识别标志才算已投放' '①回读核标志（入口保留）'
check SK 1 '推不上去是 blocked 不是「不投放」' '①blocked≠不投放（入口保留）'
check SK 1 '旧版退役只用可逆做法，本条不授权删除' '②入口摘要（含不授权删除）'
check SK 1 '单标 `待安全处置` 转出给安全 / 法务 / 内容 owner' '②被要求删除→转出（入口保留）'
check SK 1 '交互源导成静态图前全部展开再导' '③全部展开再导（入口保留）'
check SK 1 '导出后对照交互源清点承载性实体' '③导出清点（入口保留）'
check SK 1 '三态定义、投放失败形态与绕过路径、退役的两种可逆做法、转出规则与静态导出的 oracle 见' '尾指针句点名被移内容'
check SK 1 '当前版给稳定入口' '②稳定入口（入口保留）'
check SK 1 '与投放类 blocked 分开列，其结案前不得报已同步' '②待安全处置分开列+结案前禁报同步（入口保留）'
check SK 1 '人读 sweep 照跑' '机器校验不豁免人读（入口保留）'
check REF 1 '本条不绑定单一平台' '载体无关（reference）'
check SK 1 '交付面：改完 ≠ 交出去' 'head 交付面 bullet 存在且唯一'
# —— 双载体设计项（入口摘要+reference 展开，各 1）——
check SK 1 '校验绿只是人读性的代理' '机器校验代理定界（入口）'
check REF 1 '校验绿只是人读性的代理，不是替代' '机器校验代理定界（reference 展开）'
# —— 句子层 nesting-closure 判据 + 新增规则锚 ——
check SK 1 '仅取适合中文交付文档的；英文语法/标点规则不适用，已剔除' '句子层节头限定短语逐字保留'
check SK 1 '歧义代词消歧：它 / 它们 / 其 必须先有名词、后有代词' '新增代词规则锚（台账 firing-path）'

if [ "$MODE" = "--self-test" ]; then
  echo
  echo "== self-test：失败路径必须可触发 =="
  if bash "$0" 'no-such-ref-canary' >/dev/null 2>&1; then
    echo 'self-test BROKEN: 非法 base 未返回非零'
    FAIL=1
  else
    echo 'self-test OK: 非法 base 返回非零'
  fi
  PRE_FAIL=$FAIL
  check SK 1 '这句话不存在于包内任何文件中——canary' 'canary（期望 FAIL）'
  if [ "$FAIL" = 1 ] && [ "$PRE_FAIL" = 0 ]; then
    echo 'self-test OK: canary 触发 FAIL，检查器可失败'
    FAIL=0
  else
    echo 'self-test BROKEN: canary 未触发 FAIL 或此前已有 FAIL 干扰'
    FAIL=1
  fi
fi

echo
if [ "$FAIL" = 0 ]; then echo 'obligation_check_ok'; else echo 'obligation_check_failed'; fi
exit "$FAIL"
