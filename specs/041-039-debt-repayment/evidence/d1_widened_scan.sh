#!/usr/bin/env bash
# D1 加宽 runner 扫描：目标文件是否被任何机械入口到达。fail-closed。
#
# 存在理由：`register-firing-path-resolution.rb` 的 unrunnable-target advisory
# 语料**排除 specs/**，且它自己打印的边界写明不覆盖 Rakefile、无扩展名 bin 脚本、
# `find <dir> -name` 形态。041 的两轮独立评审各指出一个逃逸口——specs/ 内的 runner，
# 以及**不点名基名的通用 glob 发现**。本脚本把两者连同其余形态做成可复跑判定。
#
# 判据（机械，不靠眼力）：
#   候选 = 出现在可执行类型文件里、且「其发现范围能覆盖目标路径」的表达式。
#          glob 形态用 fnmatch 把模式与目标路径实际比一次，比不上的不算候选。
#   合格调用者 = 候选中未被 adjudications.tsv 逐条裁定排除的那些。
# 未裁定的候选一律使脚本红——将来新增一个真能跑到它的 runner 会当场翻红，
# 而不是靠这一轮的眼力。
#
# 【地位已降级 —— 041 末轮评审后】本脚本**不是终态认定器**。它证不了「不存在任何
# 机械入口」：调用形态的集合不封闭（rglob/os.walk/Find.find 等枚举器可以再多、路径
# 可以运行时分段拼出来再 `ruby "$target"`、还可以经间接层），任何静态扫描只能证
# 「在我枚举的这些形态下没有」。041 连续三轮各被找出一种新的绕过方式，按本仓
# 「同类跨轮复现是设计信号不是补丁信号」的规则，**停止加宽枚举面**，把结论降回
# 「已枚举形态下的否定证据」——真实，但不足以支撑 `休眠` 这个终态。
# 别再为了让它变绿而放宽范围；也别拿它的绿去判任何槽位休眠。
#
# 用法：d1_widened_scan.sh [repo-root] [target-repo-relative-path]
# 退出：0 = 已枚举形态下无未裁定候选；1 = 有；2 = 用法/环境错误。
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd -P)"
ROOT="${1:-$(cd "$HERE/../../.." && pwd -P)}"
TARGET="${2:-specs/023-agent-native-repo-borrowing/evidence/test_red_baseline_023_c3_regrade.rb}"
ADJ="$HERE/adjudications.tsv"
BASE="$(basename "$TARGET")"
DIR="$(dirname "$TARGET")"
cd "$ROOT" || exit 2

echo "root=$ROOT"
echo "target=$TARGET"
echo "target_exists=$([ -f "$TARGET" ] && echo yes || echo no)"
echo "revision=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
echo "adjudications=$(if [ -f "$ADJ" ]; then grep -cvE '^\s*(#|$)' "$ADJ"; else echo 0; fi) 条"
echo

INC=(--include='*.sh' --include='*.py' --include='*.rb' --include='*.yml' --include='*.yaml'
     --include='Makefile' --include='makefile' --include='Rakefile' --include='rakefile')
# 生成物镜像不是入口：dist/ 是 npm 打包出来的 skills 副本。
EXCL='^(packages/ccl-skills-npm/dist/|\.git/)'

cand_file="$(mktemp)"; trap 'rm -f "$cand_file"' EXIT

emit() { # scope, path:line:text
  printf '%s\t%s\n' "$1" "$2" >> "$cand_file"
}

scan_literal() { # scope, pattern, roots...
  local scope="$1" pat="$2"; shift 2
  grep -rnE "${INC[@]}" -- "$pat" "$@" 2>/dev/null | sed 's|^\./||' \
    | grep -vE "$EXCL" | grep -v "^${TARGET}:" | grep -v "^specs/041-039-debt-repayment/evidence/" \
    | while IFS= read -r line; do emit "$scope" "$line"; done
}

echo "## 扫描范围（逐项枚举，非概括）"
echo "  A 基名字面引用 —— specs/ 之外（advisory 的语料）"
echo "  B 基名字面引用 —— specs/ 之内（advisory 盲区）"
echo "  C 目标所在目录的字面引用（目录 sweep 形态）"
echo "  D find … -name 动态发现"
echo "  E 通用 glob/清单发现，模式经 fnmatch 与目标路径实测比对"
echo "  F Rakefile 入口"
echo "  G 无扩展名可执行入口（depth<=3）"
echo "  排除：本 evidence 目录自身、目标文件自身、npm dist 生成物镜像"
echo

scan_literal A "$BASE" .
scan_literal C "$DIR" .
scan_literal D "find[^|]*-name[^|]*\.rb" .

# E：先抓出所有 glob/清单表达式，再把模式拿去和目标路径实际 fnmatch。
python3 - "$ROOT" "$TARGET" "$cand_file" <<'PY'
import os, re, sys, fnmatch, subprocess
root, target, out = sys.argv[1], sys.argv[2], sys.argv[3]
pat_expr = re.compile(r'(Dir\.glob|Dir\[|glob\.glob|iglob|FileList|git ls-files)')
lit_all = re.compile(r'["\']([^"\']+)["\']')
exts = (".sh", ".py", ".rb", ".yml", ".yaml")
def brace_expand(p):
    m = re.search(r'\{([^{}]*)\}', p)
    if not m: return [p]
    return [q for alt in m.group(1).split(",")
              for q in brace_expand(p[:m.start()] + alt + p[m.end():])]
rows = subprocess.run(["git", "-C", root, "ls-files"], capture_output=True, text=True).stdout.split()
for rel in rows:
    if rel.startswith("packages/ccl-skills-npm/dist/"): continue
    if rel.startswith("specs/041-039-debt-repayment/evidence/"): continue
    if rel == target: continue
    if not (rel.endswith(exts) or os.path.basename(rel) in ("Makefile","makefile","Rakefile","rakefile")): continue
    try: body = open(os.path.join(root, rel), encoding="utf-8", errors="replace").read()
    except OSError: continue
    for n, line in enumerate(body.splitlines(), 1):
        if not pat_expr.search(line): continue
        frags = lit_all.findall(line)
        # File.join("skills", "*", "SKILL.md") 会被拆成三个片段，其中裸 "*" 单独看
        # 匹配一切——那是 041 第一版扫描器 20 条全红的原因。按 join 语义拼回整条
        # 模式，再单独考虑本身就带路径/扩展名的片段；裸通配片段不单独成模式。
        joined = "/".join(frags) if len(frags) > 1 else ""
        pats = [q for q in ([joined] + frags)
                if q and any(c in q for c in "*?") and q.strip("*/?") not in ("", ".")]
        if not any(c in line for c in '"\''):
            with open(out, "a") as f: f.write(f"E?\t{rel}:{n}:{line.strip()[:160]}\n")
            continue
        if not pats:
            with open(out, "a") as f: f.write(f"E?\t{rel}:{n}:{line.strip()[:160]}\n")
            continue
        hit = False
        for q0 in pats:
            for q in brace_expand(q0):
                q = q.replace("**/", "*/").lstrip("./")
                if fnmatch.fnmatch(target, q) or fnmatch.fnmatch(target, "*/" + q):
                    hit = True; break
            if hit: break
        if hit:
            with open(out, "a") as f: f.write(f"E\t{rel}:{n}:{line.strip()[:160]}\n")
PY

for f in $(find . -name 'Rakefile' -o -name 'rakefile' 2>/dev/null | grep -v '/\.git/' | sed 's|^\./||'); do emit F "$f:0:Rakefile 入口"; done
for f in $(find . -maxdepth 3 -type f -perm -u+x ! -name '*.*' ! -path './.git/*' ! -path './node_modules/*' 2>/dev/null | sed 's|^\./||'); do
  grep -qE "ruby|specs/" "$f" 2>/dev/null && emit G "$f:0:无扩展名可执行入口，提及 ruby/specs"
done

sort -u -o "$cand_file" "$cand_file"
total=$(wc -l < "$cand_file" | tr -d ' ')
echo "## 候选（发现范围能覆盖目标的表达式）：$total 条"
[ "$total" -eq 0 ] && echo "(无)"
cut -f1,2 "$cand_file" | sed 's/^/  /'
echo

unadj=0
echo "## 逐条对照 adjudications.tsv"
while IFS=$'\t' read -r scope loc; do
  [ -z "${loc:-}" ] && continue
  key="${loc%%:*}"; rest="${loc#*:}"; lineno="${rest%%:*}"
  if [ -f "$ADJ" ] && grep -qE "^${key}	${lineno}	" "$ADJ"; then
    reason=$(grep -E "^${key}	${lineno}	" "$ADJ" | head -1 | cut -f3)
    echo "  [已裁定] $key:$lineno — $reason"
  else
    echo "  [未裁定] $key:$lineno  ← 合格调用者，除非逐条裁定排除"
    unadj=$((unadj+1))
  fi
done < "$cand_file"
echo

echo "candidates=$total unadjudicated=$unadj"
if [ "$unadj" -eq 0 ]; then
  echo "d1_widened_scan_ok: 无未裁定的合格调用者 —— 目标不可被任何机械入口到达"
  exit 0
fi
echo "d1_widened_scan_found_callers: D1 休眠 结论不成立，先裁定上列候选"
exit 1
