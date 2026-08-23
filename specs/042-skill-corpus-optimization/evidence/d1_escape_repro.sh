#!/usr/bin/env bash
# 042 阶段 A 步骤 2：缺陷 #4（`休眠` = 无任何机械入口到达 → 不可判定）的当前-baseline 复现。
#
# 041 末轮把这条作为 P1 接受、并据此把 d1_widened_scan.sh 的地位降级，但**没有施加**
# 那些绕过形态——它是被论证的，不是被实测的。本脚本施加它们。
#
# 三条腿（全部在仓外 git-tracked 副本上；绝不写工作树）：
#   对照腿  字面基名形态（扫描确实枚举）      -> 必须红(1)，证明扫描有鉴别力
#   实腿 A  pathlib.rglob 枚举               -> 若绿(0) 则形态未闭合（041 r3 finding #11）
#   实腿 B  运行时分段拼路径后 ruby "$p"      -> 若绿(0) 则形态未闭合（041 r3 finding #13）
# 退出：0 = 三条腿都按预期（即缺陷 #4 复现）；非 0 = 与预期不符，停下查因。
set -uo pipefail
SRC=${1:?usage: d1_escape_repro.sh <repo-root>}
SRC=$(cd "$SRC" && pwd -P)
SCAN=specs/041-039-debt-repayment/evidence/d1_widened_scan.sh
[ -f "$SRC/$SCAN" ] || { echo "refuse: 找不到 $SCAN" >&2; exit 2; }
TMP=$(mktemp -d) || exit 2
trap 'rm -rf "$TMP"' EXIT INT TERM
( cd "$SRC" && git ls-files -z | tar --null -cf - -T - ) | ( cd "$TMP" && tar xf - ) || exit 2
run() { bash "$TMP/$SCAN" "$TMP" >/dev/null 2>&1; echo $?; }
rc=0
chk() { if [ "$2" = "$3" ]; then printf '  PASS  %-42s exit=%s\n' "$1" "$2"
        else printf '  FAIL  %-42s exit=%s want=%s\n' "$1" "$2" "$3"; rc=1; fi; }
chk "baseline（无新增 runner）" "$(run)" 0
cat > "$TMP/scripts/ctl_literal.sh" <<'EOF'
#!/usr/bin/env bash
ruby specs/023-agent-native-repo-borrowing/evidence/test_red_baseline_023_c3_regrade.rb
EOF
chk "对照腿：字面基名（应被抓到）" "$(run)" 1
rm -f "$TMP/scripts/ctl_literal.sh"
cat > "$TMP/scripts/esc_rglob.py" <<'EOF'
#!/usr/bin/env python3
import pathlib, subprocess
for p in pathlib.Path("specs").rglob("*.rb"):
    subprocess.run(["ruby", str(p)])
EOF
chk "实腿 A：pathlib.rglob（应逃掉）" "$(run)" 0
rm -f "$TMP/scripts/esc_rglob.py"
cat > "$TMP/scripts/esc_split.sh" <<'EOF'
#!/usr/bin/env bash
a="specs/023-agent-native-repo-borrowing"; b="evidence"
c="test_red_baseline_023"; d="_c3_regrade.rb"
ruby "$a/$b/$c$d"
EOF
chk "实腿 B：运行时分段拼路径（应逃掉）" "$(run)" 0
rm -f "$TMP/scripts/esc_split.sh"
chk "复原核验（回到 baseline）" "$(run)" 0
[ $rc -eq 0 ] && echo "d1_escape_reproduced: 缺陷 #4 未闭合" || echo "d1_escape_repro_FAILED"
exit $rc
