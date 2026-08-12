#!/usr/bin/env bash
# 回归测试：把 references/public-data-acquisition.md 里的可运行片段**原样抽出来**跑。
#
# 为什么按原样抽而不是照着意思重写：这份 reference 的价值在于读者会照抄它。
# 如果测试跑的是另一份等价实现，文档退化了测试也不会红。
#
# 不联网：curl 被替换成本地 stub，所以可以在 CI 里跑。
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
DOC="$HERE/../references/public-data-acquisition.md"
[ -r "$DOC" ] || { echo "找不到 $DOC" >&2; exit 1; }

WORK=$(mktemp -d) || { echo "无法创建测试临时目录" >&2; exit 1; }
trap 'rm -rf -- "$WORK"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
pass=0; fail=0
ok()   { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  FAIL %s — %s\n' "$1" "${2:-}"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "期望 $3，实得 $2"; fi; }

# ---- 块清单：每个可运行片段必须**显式**声明是被执行还是被豁免 ----
# 硬编码 sh[0]/py[0] 的老做法会让新加的可运行块悄悄不被覆盖（评审 P2）。
# 这里按内容指纹认块；出现未登记的块就红，逼作者要么覆盖它、要么写明为何不可执行。
cat > "$WORK/check-block-manifest.py" <<'PY'
import re,sys
doc,work=sys.argv[1],sys.argv[2]
t=open(doc,encoding='utf-8').read()
# 枚举所有 fence，而不是只枚举认识的语言；新标签/无标签块也必须进入处置。
blocks=[(m.group(1).strip(),m.group(2))
        for m in re.finditer(r'^```([^\n]*)\n(.*?)^```[ \t]*$',t,re.S|re.M)]

# 每项：(标识, 判据, 处置)。exec=本测试真的执行它；exempt=写明为何不执行。
MANIFEST=[
 ("fetch/accept",  lambda l,b: l=='bash'   and 'fetch()' in b,                 "exec"),
 ("curl-size-log", lambda l,b: l=='' and 'Exceeded the maximum allowed file size' in b, "exempt: 实测命令输出，不是可执行片段"),
 ("curl-fail-log", lambda l,b: l=='' and '<当时返回 504 的接口>' in b,          "exempt: 实测命令输出，不是可执行片段"),
 ("cdx",           lambda l,b: l=='bash'   and 'cdx/search/cdx' in b,          "exempt: 需要真实归档站，属联网集成"),
 ("catalog",       lambda l,b: l=='bash'   and 'api/catalog/v1' in b and 'while' not in b, "exempt: 需要真实目录接口，属联网集成"),
 ("paging",        lambda l,b: l=='bash'   and 'OFF=' in b and 'while' in b,   "exec"),
 ("pdf-probe",     lambda l,b: l=='bash'   and 'pdftotext' in b,               "exempt: 依赖 poppler，非本机保证"),
 ("pdf-render",    lambda l,b: l=='bash'   and 'pdftoppm' in b,                "exempt: 依赖 poppler，非本机保证"),
 ("alias-parse",   lambda l,b: l=='python' and 'ALIAS' in b,                   "exec"),
 ("col-attrib",    lambda l,b: l=='python' and 'totA' in b,                    "exempt: 三行示意式恒等式，无控制流"),
 ("ocr",           lambda l,b: l=='swift' and 'VNRecognizeTextRequest' in b,    "exempt: 需 macOS Vision + swiftc，另行手测"),
 ("tag-fallback",  lambda l,b: l=='javascript' and 'concept(t)' in b,           "exempt: 需真实结构化接口"),
]
unmatched=[]
for lang,body in blocks:
    if not any(pred(lang,body) for _,pred,_ in MANIFEST):
        unmatched.append((lang,body.strip().split('\n')[0][:70]))
if unmatched:
    print("未登记的可运行块（要么覆盖它，要么在 MANIFEST 里写明豁免理由）：")
    for lang,head in unmatched: print(f"   [{lang}] {head}")
    sys.exit(1)
# 抽出要执行的块
for name,pred,how in MANIFEST:
    if how!="exec": continue
    hit=[b for l,b in blocks if pred(l,b)]
    if len(hit)!=1:
        print(f"块 {name} 命中 {len(hit)} 个，判据需更新"); sys.exit(1)
    ext="py" if name=="alias-parse" else "sh"
    open(f"{work}/{name.replace('/','_')}.{ext}","w").write(hit[0])
print(f"块清单：共 {len(blocks)} 个，执行 {sum(1 for _,_,h in MANIFEST if h=='exec')} 类，其余已登记豁免")
PY
python3 "$WORK/check-block-manifest.py" "$DOC" "$WORK"
[ $? -eq 0 ] || { echo "块清单校验失败" >&2; exit 1; }
mkdir -p "$WORK/negative-extract"
cat > "$WORK/unregistered-block.md" <<'BAD'
```bash
echo "unregistered"
```
BAD
if python3 "$WORK/check-block-manifest.py" "$WORK/unregistered-block.md" "$WORK/negative-extract" >/dev/null 2>&1; then
  bad "块清单能报未登记代码块" "坏输入被放行"
else
  ok "块清单能报未登记代码块"
fi
cat > "$WORK/unknown-fence.md" <<'BAD'
```sh
echo "unknown language tag"
```
BAD
if python3 "$WORK/check-block-manifest.py" "$WORK/unknown-fence.md" "$WORK/negative-extract" >/dev/null 2>&1; then
  bad "块清单能报未知 fence 标签" "未知标签被忽略"
else
  ok "块清单能报未知 fence 标签"
fi
cp "$WORK/fetch_accept.sh" "$WORK/fetch.sh" 2>/dev/null || { echo "抽取 fetch 块失败" >&2; exit 1; }
cp "$WORK/alias-parse.py" "$WORK/parse.py" 2>/dev/null || { echo "抽取 ALIAS 块失败" >&2; exit 1; }
cp "$WORK/paging.sh" "$WORK/page.sh" 2>/dev/null || { echo "抽取分页块失败" >&2; exit 1; }

echo "== 语法 =="
if bash -n "$WORK/fetch.sh"; then ok "bash -n"; else bad "bash -n"; fi

# 变量名紧跟全角标点会被 shell 吃进名字（set -u 下 unbound variable）。
# 这类错误几乎只出现在错误分支的提示语里，手测极难碰到 → 全文静态扫。
cat > "$WORK/check-fullwidth-var.py" <<'PY'
import re,sys
t=open(sys.argv[1],encoding='utf-8').read()
hits=[]
for blk in re.findall(r'```bash\n(.*?)```',t,re.S):
    for line in blk.split('\n'):
        # Bash 的 ${v#prefix} 自带 #，不能用 split('#') 粗暴截断，否则会吞掉
        # 同一行后面的真问题。只略过整行注释；行内误报宁可要求显式 ${var}。
        if line.lstrip().startswith('#'):
            continue
        if re.search(r'\$[A-Za-z_][A-Za-z0-9_]*(?![A-Za-z0-9_])[^\x00-\x7f]',line):
            hits.append(f"bash: {line.strip()}")
for h in hits: print("   "+h)
sys.exit(1 if hits else 0)
PY
if python3 "$WORK/check-fullwidth-var.py" "$DOC"
then ok "代码块里没有 \$var 紧跟全角标点"; else bad "代码块里有 \$var 紧跟全角标点（改用 \${var}）"; fi
cat > "$WORK/fullwidth-var-bad.md" <<'BAD'
```bash
echo "${name#prefix}" "$mime，"
```
BAD
if python3 "$WORK/check-fullwidth-var.py" "$WORK/fullwidth-var-bad.md" >/dev/null 2>&1; then
  bad "全角标点检查器能报坏输入" "坏输入被放行"
else
  ok "全角标点检查器能报坏输入"
fi

# ---- curl stub：按 URL 决定行为，不出网 ----
mkdir -p "$WORK/bin"
cat > "$WORK/bin/curl" <<'STUB'
#!/usr/bin/env bash
# 只实现测试需要的部分：--version、-o <file>、URL 里的关键字决定产物
if [ "${1:-}" = "--version" ]; then
  echo "curl ${CURL_STUB_VERSION:-8.7.1} (test-stub)"
  exit 0
fi
out=""; url=""; max_bytes=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out=$2; shift 2 ;;
    --max-filesize) max_bytes=$2; shift 2 ;;
    http*|https*) url=$1; shift ;;
    *) shift ;;
  esac
done
[ -z "${CURL_ARGS_LOG:-}" ] || printf '%s\n' "$max_bytes" > "$CURL_ARGS_LOG"
case "$url" in
  *slowA*|*slowB*)
    if [ -n "${CURL_BARRIER_DIR:-}" ]; then
      : > "$CURL_BARRIER_DIR/ready.$$"
      tries=0
      while [ "$(find "$CURL_BARRIER_DIR" -name 'ready.*' -type f | wc -l | tr -d ' ')" -lt 2 ]; do
        tries=$((tries+1))
        [ "$tries" -lt 1000 ] || exit 70
        sleep 0.01
      done
    fi
    ;;
esac
case "$url" in
  *fail500*)  echo 'curl: (22) HTTP response code said error' >&2; exit 22 ;;
  *html*)     printf '<html><body>blocked</body></html>' > "$out" ;;
  *empty*)    : > "$out" ;;
  *oversize*) printf '%s\n' '[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]' > "$out" ;;
  *slowA*)    sleep 1; printf '{"who":"A"}' > "$out" ;;
  *slowB*)    sleep 1; printf '{"who":"B"}' > "$out" ;;
  *)          printf '{"ok":true}' > "$out" ;;
esac
exit 0
STUB
chmod +x "$WORK/bin/curl"

run_fetch() {  # 在受控 PATH 下 source 文档片段并调用 fetch
  local log=${FETCH_LOG:-/dev/null}
  ( export PATH="$WORK/bin:$PATH" UA="regression-test test@example.invalid"
    [ -z "${CURL_BARRIER_DIR:-}" ] || export CURL_BARRIER_DIR
    cd "$WORK/run" || exit 9
    # shellcheck disable=SC1090
    . "$WORK/fetch.sh"
    OUT=$PWD; export OUT
    fetch "$@"
  ) >"$log" 2>&1
  rc=$?
  echo "$rc"
}

echo "== fetch 行为 =="
rm -rf "$WORK/run"; mkdir -p "$WORK/run"
check "正常下载返回 0"        "$(run_fetch "$WORK/run/a.json" 'https://x/data')"     0
check "已存在则 SKIP 返回 0"  "$(run_fetch "$WORK/run/a.json" 'https://x/data')"     0
check "curl 失败返回 1"       "$(FETCH_LOG="$WORK/curl-fail.log" run_fetch "$WORK/run/b.json" 'https://x/fail500')" 1
check "curl 失败原因匹配"     "$(grep -Fq 'curl: (22)' "$WORK/curl-fail.log" && echo matched || echo missing)" matched
check "curl 失败不留成品"     "$([ -e "$WORK/run/b.json" ] && echo present || echo absent)" absent
check "curl < 8.4.0 被拒绝"   "$(FETCH_LOG="$WORK/oldcurl.log" CURL_STUB_VERSION=8.3.0 run_fetch "$WORK/run/oldcurl.json" 'https://x/data')" 1
check "旧 curl 失败原因匹配"  "$(grep -Fq '< 8.4.0' "$WORK/oldcurl.log" && echo matched || echo missing)" matched
check "旧 curl 不留成品"      "$([ -e "$WORK/run/oldcurl.json" ] && echo present || echo absent)" absent
check "类型不符返回 1"        "$(FETCH_LOG="$WORK/type.log" run_fetch "$WORK/run/c.json" 'https://x/html')" 1
check "类型不符原因匹配"      "$(grep -Fq '类型不符' "$WORK/type.log" && echo matched || echo missing)" matched
check "类型不符不留成品"      "$([ -e "$WORK/run/c.json" ] && echo present || echo absent)" absent
check "空响应返回 1"          "$(FETCH_LOG="$WORK/empty.log" run_fetch "$WORK/run/d.json" 'https://x/empty')" 1
check "空响应原因匹配"        "$(grep -Fq '空响应' "$WORK/empty.log" && echo matched || echo missing)" matched
mkdir -p "$WORK/run/adir" && : > "$WORK/run/adir/keep"
check "目标是目录返回 2"      "$(run_fetch "$WORK/run/adir" 'https://x/data')"       2
check "目录内容未被动"        "$([ -e "$WORK/run/adir/keep" ] && echo kept || echo GONE)" kept
check "无 .part 残留"         "$(find "$WORK/run" -name '*.part.*' | wc -l | tr -d ' ')" 0

run_fetch_smallcap() {  # 把 MAX_BYTES 压到很小，用来触发体积上限分支
  local log=${FETCH_LOG:-/dev/null}
  ( export PATH="$WORK/bin:$PATH" UA="regression-test test@example.invalid"
    [ -z "${CURL_ARGS_LOG:-}" ] || export CURL_ARGS_LOG
    cd "$WORK/run" || exit 9
    # shellcheck disable=SC1090
    . "$WORK/fetch.sh" >/dev/null 2>&1
    # MAX_BYTES 被文档里的 accept() 读取，shellcheck 看不到跨 source 的使用
    # shellcheck disable=SC2034
    MAX_BYTES=${MAXOVERRIDE:-32}; OUT=$PWD; export OUT
    fetch "$@"
  ) >"$log" 2>&1
  rc=$?
  echo "$rc"
}

echo "== 已存在的文件也要过验收，不能因 SKIP 绕过（评审 P1）=="
rm -rf "$WORK/run"; mkdir -p "$WORK/run"
printf '<html>上一轮/别的工具留下的非空垃圾</html>' > "$WORK/run/stale.json"
check "残留 HTML 被拒收(1)" "$(run_fetch "$WORK/run/stale.json" 'https://x/data')" 1
printf '{"ok":true}' > "$WORK/run/good.json"
check "残留合法 JSON 走 SKIP(0)" "$(run_fetch "$WORK/run/good.json" 'https://x/data')" 0
# 已存在文件从没经过 curl --max-filesize，所以体积必须由 accept 自己查（评审 P1）
python3 -c "open('$WORK/run/huge.json','w').write('['+'0,'*60+'0]')"
check "超上限的残留文件被拒收(1)" "$(FETCH_LOG="$WORK/stale-size.log" MAXOVERRIDE=32 run_fetch_smallcap "$WORK/run/huge.json" 'https://x/data')" 1
check "残留超限原因匹配" "$(grep -Fq '超过体积上限' "$WORK/stale-size.log" && echo matched || echo missing)" matched
check "超上限的新下载被拒收(1)" "$(FETCH_LOG="$WORK/new-size.log" MAXOVERRIDE=32 run_fetch_smallcap "$WORK/run/oversize.json" 'https://x/oversize')" 1
check "新下载超限原因匹配" "$(grep -Fq '超过体积上限' "$WORK/new-size.log" && echo matched || echo missing)" matched
check "小上限下载返回 0" "$(CURL_ARGS_LOG="$WORK/max-bytes.log" MAXOVERRIDE=32 run_fetch_smallcap "$WORK/run/capped.json" 'https://x/data')" 0
check "curl 与 accept 使用同一上限" "$(cat "$WORK/max-bytes.log")" 32

cat > "$WORK/bin/ln" <<'S'
#!/usr/bin/env bash
exit 1
S
chmod +x "$WORK/bin/ln"
check "硬链接不受支持时下载前失败" "$(FETCH_LOG="$WORK/no-hardlink.log" run_fetch "$WORK/run/no-hardlink.json" 'https://x/data')" 1
check "硬链接探针失败原因匹配" "$(grep -Fq '成品目录不支持硬链接' "$WORK/no-hardlink.log" && echo matched || echo missing)" matched
rm -f "$WORK/bin/ln"

echo "== accept 的外部命令失败必须 fail-closed（评审 P1）=="
rm -rf "$WORK/run"; mkdir -p "$WORK/run" "$WORK/nofile"
cat > "$WORK/nofile/file" <<'S'
#!/usr/bin/env bash
exit 127          # 冒充 file 不可用/执行失败
S
chmod +x "$WORK/nofile/file"; cp "$WORK/bin/curl" "$WORK/nofile/curl"
rc=$( export PATH="$WORK/nofile:/usr/bin:/bin" UA="t t@example.invalid"
      cd "$WORK/run" || exit 9; . "$WORK/fetch.sh" >/dev/null 2>&1; OUT=$PWD; export OUT
      fetch "$WORK/run/e.json" 'https://x/data' >/dev/null 2>&1; echo $? )
check "file 失败时返回非 0" "$([ "$rc" != 0 ] && echo nonzero || echo zero)" nonzero
check "file 失败时不发布"   "$([ -e "$WORK/run/e.json" ] && echo present || echo absent)" absent

echo "== 并发写同一目标、内容不同，不得静默覆盖（评审 P1）=="
rm -rf "$WORK/run" "$WORK/barrier"; mkdir -p "$WORK/run" "$WORK/barrier"
( CURL_BARRIER_DIR="$WORK/barrier" run_fetch "$WORK/run/race.json" 'https://x/slowA' > "$WORK/rcA" ) &
( CURL_BARRIER_DIR="$WORK/barrier" run_fetch "$WORK/run/race.json" 'https://x/slowB' > "$WORK/rcB" ) &
wait
rcA=$(cat "$WORK/rcA"); rcB=$(cat "$WORK/rcB")
winners=0; [ "$rcA" = 0 ] && winners=$((winners+1)); [ "$rcB" = 0 ] && winners=$((winners+1))
check "恰好一个调用发布成功" "$winners" 1
losers=0; for r in "$rcA" "$rcB"; do [ "$r" = 3 ] && losers=$((losers+1)); done
check "另一个报并发冲突(3)"  "$losers" 1
check "成品是完整的单方内容" "$(python3 -c "
import json,sys
d=json.load(open('$WORK/run/race.json'))
print('single' if d.get('who') in ('A','B') and len(d)==1 else 'MIXED')" 2>/dev/null || echo BROKEN)" single
check "并发后无 .part 残留"  "$(find "$WORK/run" -name '*.part.*' | wc -l | tr -d ' ')" 0

echo "== 分页循环：解析失败必须非零终止，不得空转（评审 P1/P2）=="
# 只跑 sh[0] 会漏掉这一块——分页块里 N=$(...) 失败时 OFF 不前进，会反复读同一页。
cat > "$WORK/pagerun.sh" <<'SH'
set -euo pipefail
UA="t t@example.invalid"; OUT=$PWD; export UA OUT
DOMAIN=example.invalid; ID=ds; PAGE=2
# shellcheck disable=SC1090
. "$WORKDIR/fetch.sh" >/dev/null 2>&1
fetch() {
  case "$1" in
    *-p0.json) printf '%s' "$BADBODY" > "$1" ;;
    *) printf '%s' "${NEXTBODY:-$BADBODY}" > "$1" ;;
  esac
  FETCHED=1
  if [ "${CONFLICT_ONCE:-0}" = 1 ] && [ ! -e "$WORKDIR/conflict-returned" ]; then
    : > "$WORKDIR/conflict-returned"
    return 3
  fi
  return 0
}   # 绕开网络，直接给受控分页内容
# shellcheck disable=SC1090
. "$WORKDIR/page.sh"
SH
run_pager() {
  python3 - "$WORK/pagerun.sh" <<'PY'
import subprocess,sys
try:
    p=subprocess.run(["bash",sys.argv[1]],stdout=subprocess.DEVNULL,
                     stderr=subprocess.STDOUT,timeout=20)
    print(p.returncode)
except subprocess.TimeoutExpired:
    print(124)
PY
}
rm -rf "$WORK/pg"; mkdir -p "$WORK/pg"
rc=$( cd "$WORK/pg" || exit 9
      export WORKDIR="$WORK" BADBODY='{ this is not json'
      run_pager )
check "JSON 损坏时非零终止" "$([ "$rc" != 0 ] && [ "$rc" != 124 ] && echo nonzero || echo "bad:$rc")" nonzero
rm -rf "$WORK/pg2"; mkdir -p "$WORK/pg2"
rc2=$( cd "$WORK/pg2" || exit 9
       export WORKDIR="$WORK" BADBODY='[]'
       run_pager )
check "空页正常收尾(0)" "$rc2" 0
rm -rf "$WORK/pg-full"; mkdir -p "$WORK/pg-full"
rc_full=$( cd "$WORK/pg-full" || exit 9
           export WORKDIR="$WORK" BADBODY='[1,2]' NEXTBODY='[]'
           run_pager )
check "set -e 下满页后继续到空页" "$rc_full" 0
rm -f "$WORK/conflict-returned"
rm -rf "$WORK/pg-conflict"; mkdir -p "$WORK/pg-conflict"
rc_conflict=$( cd "$WORK/pg-conflict" || exit 9
               export WORKDIR="$WORK" BADBODY='[]' CONFLICT_ONCE=1
               run_pager )
check "并发已发布返回 3 时继续处理该页" "$rc_conflict" 0
rm -rf "$WORK/pg3"; mkdir -p "$WORK/pg3"
rc3=$( cd "$WORK/pg3" || exit 9
       export WORKDIR="$WORK" BADBODY='{"error":"not an array page"}'
       run_pager )
check "JSON 对象不能冒充数组页" "$([ "$rc3" != 0 ] && [ "$rc3" != 124 ] && echo nonzero || echo "bad:$rc3")" nonzero

echo "== ALIAS 解析必须 fail-closed =="
# 直接判命令，不用 $?——间接读退出码正是本 reference §3.6 点名的坑
if python3 - "$WORK/parse.py" "$WORK" <<'PY'
import re,sys,openpyxl,os
code=open(sys.argv[1],encoding='utf-8').read()
def variant(alias_literal):
    c=re.sub(r'ALIAS = \{.*?\n\}', alias_literal, code, count=1, flags=re.S)
    assert c!=code, "ALIAS 字面量替换失败——文档结构变了，请更新本测试"
    return c.replace('SHEET_NAME','"DATA"').replace('...','pass')
two   = variant('ALIAS = {"A":["New Name","Old Name"],"B":["BEE","B_OLD"]}')
share = variant('ALIAS = {"person":["NAME"],"organization":["NAME"]}')
tmp=os.path.join(sys.argv[2],"alias-fixtures")
os.mkdir(tmp)
def wb(name,hdr,rows=((1,2),)):
    w=openpyxl.Workbook(); s=w.active; s.title="DATA"
    if hdr is not None: s.append(hdr)
    for r in rows: s.append(list(r))
    p=os.path.join(tmp,name+".xlsx"); w.save(p); return p
cases=[
 ("新名(大小写/空白不同)命中", two,   wb("c1",["New   name","BEE"]),      "ok"),
 ("旧名走别名命中",           two,   wb("c2",["Old Name","B_OLD"]),      "ok"),
 ("新旧候选同时命中",         two,   wb("c3",["New Name","Old Name","BEE"]), "closed"),
 ("候选全不在表头",           two,   wb("c4",["ZZZ","BEE"]),             "closed"),
 ("表头重复",                 two,   wb("c5",["New Name","New Name","BEE"]), "closed"),
 ("空表无表头行",             two,   wb("c6",None,rows=()),              "closed"),
 ("两语义绑同一物理列",       share, wb("c7",["NAME","OTHER"]),          "closed"),
]
bad=0
for tag,src,path,want in cases:
    ns={'openpyxl':openpyxl,'path':path}
    try:
        exec(compile(src,'<doc>','exec'),ns); got="ok"
    except SystemExit: got="closed"
    except Exception as e: got=f"UNEXPECTED {type(e).__name__}: {e}"
    if got==want: print(f"  ok   {tag}")
    else: print(f"  FAIL {tag} — 期望 {want}，实得 {got}"); bad+=1
sys.exit(1 if bad else 0)
PY
then ok "ALIAS 七种输入"; else bad "ALIAS 七种输入"; fi

printf '\n通过 %d，失败 %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
echo "public_data_acquisition_recipes_ok"
