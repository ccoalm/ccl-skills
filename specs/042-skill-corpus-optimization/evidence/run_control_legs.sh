#!/usr/bin/env bash
# 042 阶段 A 步骤 1：台账自指探针的复验 + 对照腿。
# 只读仓库；全部突变施加在仓外临时副本上，绝不写工作树（041 finding #3 的教训：
# 无条件 `git checkout --` 会连带丢弃目标文件上的无关未提交改动）。
# 退出码：0 = 全部腿按预期；非 0 = 某条腿的读数与预期不符，停下查因，不得当作已验证。
set -uo pipefail
REPO=${1:?usage: run_control_legs.sh <repo-root>}
REPO=$(cd "$REPO" && pwd -P)
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
case "$HERE" in "$REPO"*) : ;; *) echo "refuse: 脚本须随仓库一起分发" >&2; exit 2;; esac
REG=skills/skill-extraction-workflow/references/source-register.md
[ -f "$REPO/$REG" ] || { echo "refuse: 找不到台账 $REG" >&2; exit 2; }
TMP=$(mktemp -d) || exit 2
trap 'rm -rf "$TMP"' EXIT INT TERM
mk() { mkdir -p "$TMP/$1/$(dirname "$REG")"; cp "$REPO/$REG" "$TMP/$1/$REG"; }
mut() { python3 - "$TMP/$1/$REG" "$2" "$3" "$4" <<'PY'
import io,sys
p,idx,old,new=sys.argv[1],int(sys.argv[2]),sys.argv[3],sys.argv[4]
L=io.open(p,encoding='utf-8').read().split("\n")
assert old in L[idx-1], "突变靶点未命中第 %d 行：前置条件已变，停" % idx
L[idx-1]=L[idx-1].replace(old,new)
io.open(p,'w',encoding='utf-8').write("\n".join(L))
PY
}
wide()  { python3 "$REPO/specs/041-039-debt-repayment/evidence/d2_strict.py" "$1" | sed -n '2p' | grep -oE '[0-9]+' | head -1; }
corr()  { python3 "$HERE/selfref_probe.py" "$1" | grep -oE '[0-9]+' | head -1; }
A53_OLD='file:skills/multi-agent-delegation/SKILL.md#Before a worker prompt includes a delivery spec'
A53_EXE='file:hooks/test_guard_delegation_owner.sh#Before a worker prompt includes a delivery spec'
A53_GONE='file:skills/zzz-not-in-evidence/nowhere.md#Before a worker prompt includes a delivery spec'
B140_OLD='file:skills/product-rd-workflow/references/delivery-lifecycle.md'
B140_SELF='file:skills/product-rd-workflow/SKILL.md'
# 突变的前置条件断言失败 = 台账行号已漂移，后续腿会拿未突变副本比出假结果。
# 因此这里 fail-closed 中止，绝不带着坏副本往下跑。
die() { echo "abort: 突变前置条件不成立（台账行号已漂移？）——停下重定靶点，不得当作已验证" >&2; exit 3; }
mk null
mk m1; mut m1 53  "$A53_OLD"  "$A53_EXE"   || die
mk m2; mut m2 140 "$B140_OLD" "$B140_SELF" || die
mk m3; mut m3 53  "$A53_OLD"  "$A53_GONE"  || die
rc=0
chk() { # 名称 实测 预期
  if [ "$2" = "$3" ]; then printf '  PASS  %-46s %s\n' "$1" "$2"
  else printf '  FAIL  %-46s got=%s want=%s\n' "$1" "$2" "$3"; rc=1; fi
}
echo "== 实腿（当前工作树，只读） =="
chk "d2_strict(041) live"            "$(wide "$REPO")"      51
chk "selfref_probe(042) live"        "$(corr "$REPO")"      51
echo "== 零腿（未突变副本；证明复制机制本身不改数） =="
chk "d2_strict null-copy"            "$(wide "$TMP/null")"  51
chk "selfref_probe null-copy"        "$(corr "$TMP/null")"  51
echo "== 对照腿 m2：非自指行(:140)改成自指 -> 两版都应 +1 =="
chk "d2_strict m2"                   "$(wide "$TMP/m2")"    52
chk "selfref_probe m2"               "$(corr "$TMP/m2")"    52
echo "== 对照腿 m3：自指行(:53)改指 Evidence 里没有的路径 -> 两版都应 -1 =="
chk "d2_strict m3"                   "$(wide "$TMP/m3")"    50
chk "selfref_probe m3"               "$(corr "$TMP/m3")"    50
echo "== 对照腿 m1：自指行(:53)改指其 Evidence 已列的可执行体 =="
echo "   这正是 13 行的修复动作。两版在此分岔——这条腿是本次复验的实质发现。"
chk "d2_strict m1  (不响应修复=不适格)" "$(wide "$TMP/m1")"  51
chk "selfref_probe m1 (正确 -1)"        "$(corr "$TMP/m1")"  50
[ $rc -eq 0 ] && echo "control_legs_ok" || echo "control_legs_FAILED"
exit $rc
