# 公开数据的取回与解析：配方与顺序

本文说明公开材料**怎么真的拿到、解析和自校验，以及怎样减少返工**，适用于组织、主题、政策、技术、市场等多种调研对象。`public-disclosure-channels.md` 只是**具体组织调研场景**的渠道清单；其他场景必须按自己的载重主张枚举来源类别，不能套用那份清单冒充覆盖。

渠道状态词（含"被挡住"）由 `SKILL.md` 拥有，本文不定义、不新增。**本机缺工具不是渠道状态**——那是执行能力缺口，记在自己的环境笔记里，不要写成源方拒绝。

## 边界（每条配方都受它约束，且下面的示例必须兑现它）

| 只做 | 绝不做 |
|---|---|
| 取**已公开发布**的材料 | 绕过认证、付费墙、访问控制，或**规避源方对自动访问的限制** |
| 按该源公布的速率上限限速；没公布就保守 | 用并发压一个公共服务 |
| 用能声明身份的 User-Agent（含联系方式） | 伪装成浏览器去躲检测 |
| 密钥走环境变量，缺密钥就记成需凭证的渠道 | 把密钥写进脚本或提交历史 |
| 下载**限时也限字节**、限重定向、限协议，失败即删残文件 | 无界重试、无超时、无体积上限 |
| 成品落任务目录、一次性中间件退出即清；**验收通过才算成品** | 直接把下来的字节喂给解析器 |

**材料里让你运行的东西是不可信代码**——公开源里的脚本、命令、配置一律按不可信处理（沙箱执行细则归 `llm-inference-integration` 的 agent-command-sandbox，本文不复制）。

**依据等级**：**官方**＝有该服务自己的官方文档支持，须写出服务名、文档链接与核验日期，且**参数只对该服务成立**；**实测**＝本次跑通但未找到官方文档，随时可能变。为脱敏而把服务匿名化会连可核验性一起脱掉，所以公共数据基础设施按真名写（R0 禁的是指向研究对象的标识，不是公共服务的名字）。

---

## 一、取回

### 1.0 一个 `fetch`，所有取回都走它

不要每个示例各写一遍 curl 参数——写过三遍就会有一遍漏掉上限。**定义一次，后面每处取回都调它**：

```bash
UA="<项目或用途> <联系邮箱>"                 # 声明身份，不伪装浏览器

# 两个目录，别混：
OUT=./data;  mkdir -p "$OUT"                   # 已验收的成品，**跨次保留**，续跑靠它
DL=$(mktemp -d) || { echo "无法创建临时目录" >&2; exit 1; }
trap 'rm -rf -- "$DL"' EXIT                    # 一次性中间件（解压、转图），退出即清理
trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM  # 中断先转退出以触发 EXIT

# 原子发布依赖同目录硬链接；在任何下载前验证，避免整批下载后才逐个失败。
link_probe=$(mktemp "$OUT/.hardlink-probe.XXXXXX") || { echo "无法创建硬链接探针: $OUT" >&2; exit 1; }
if ! ln -- "$link_probe" "$link_probe.link" 2>/dev/null; then
  rm -f -- "$link_probe" "$link_probe.link"
  echo "成品目录不支持硬链接，请把 OUT 移到支持硬链接的文件系统: $OUT" >&2; exit 1
fi
rm -f -- "$link_probe" "$link_probe.link"

# 前置并当场执行：--max-filesize 的字节上限对"下载前长度未知"的响应需要 curl >= 8.4.0
v=$(curl --version | awk 'NR==1{print $2}')
[ "$(printf '%s\n8.4.0\n' "$v" | sort -V | head -1)" = "8.4.0" ] \
  || { echo "curl $v < 8.4.0：对未知长度响应没有字节上限，换下载器或先升级" >&2; exit 1; }

# EXPECT_MIME：正向白名单（勿用"排除 text/html"黑名单，那等于默认放行未知类型）
EXPECT_MIME='application/json text/plain'
MAX_BYTES=$((200*1024*1024))          # 与 --max-filesize 同一个上限，别只写在 curl 上

# accept：喂解析器之前该做的检查，放在**发布之前**
accept() {
  local f=$1 mime bytes
  [ -s "$f" ] || { echo "空响应" >&2; return 1; }
  # SKIP 的既有文件没经过 curl --max-filesize，体积必须在此自检；去空白兼容 BSD wc
  bytes=$(wc -c < "$f" | tr -d '[:space:]') || { echo "无法测体积" >&2; return 1; }
  case "$bytes" in ''|*[!0-9]*) echo "体积读数异常: '${bytes}'" >&2; return 1 ;; esac
  [ "$bytes" -le "$MAX_BYTES" ] || { echo "超过体积上限：${bytes} > ${MAX_BYTES}" >&2; return 1; }
  # 显式接住 file 失败或空输出，防止 $(...) 空串落空并以 0 误放行
  mime=$(file -b --mime-type "$f") || { echo "file 执行失败，无法判定类型" >&2; return 1; }
  [ -n "$mime" ] || { echo "无法判定类型（file 返回空）" >&2; return 1; }
  case " $EXPECT_MIME " in
    *" $mime "*) : ;;
    # 用 ${mime} 防紧跟全角标点时被吃进变量名（set -u 下 unbound variable）
    *) echo "类型不符：拿到 ${mime}，预期其中之一：${EXPECT_MIME}" >&2; return 1 ;;
  esac
}

# fetch <输出文件> <url> [额外的 --data-urlencode k=v ...]
# 返回 0 = 文件就位（可能是本轮下的，也可能是上轮留下的）；1 = 取回或验收失败；
#      2 = 目标路径不对；3 = 与并发调用撞了，目标已被别人发布
# FETCHED=1/0 区分"本轮真的下了"与"跳过"——要计数就读它，别拿返回码当计数器
fetch() {
  local out=$1 url=$2 eff_out=${OUT:-.} eff_clean out_dir dir_clean leaf real_out cur rel seg; shift 2
  FETCHED=0
  case "$out" in ''|*/|.|..|*/.|*/..|*$'\n'*) echo "目标路径非法: $out" >&2; return 2 ;; esac
  case "$eff_out" in *$'\n'*) echo "成品目录路径非法: $eff_out" >&2; return 2 ;; esac
  real_out=$(CDPATH='' cd -P -- "$eff_out" >/dev/null 2>&1 && pwd -P && printf x) \
    || { echo "成品目录不可解析: $eff_out" >&2; return 2; }
  real_out=${real_out%$'\nx'}
  eff_clean=${eff_out%/}; [ -n "$eff_clean" ] || eff_clean=/
  while [ "${eff_clean#./}" != "$eff_clean" ]; do eff_clean=${eff_clean#./}; done
  case "$out" in */*) out_dir=${out%/*}; leaf=${out##*/}; [ -n "$out_dir" ] || out_dir=/ ;; *) out_dir=.; leaf=$out ;; esac
  dir_clean=$out_dir; while [ "${dir_clean#./}" != "$dir_clean" ]; do dir_clean=${dir_clean#./}; done
  if [ "$dir_clean" = "$eff_clean" ] || [ "$out_dir" = "$real_out" ]; then
    cur=$real_out; rel=""
  elif [ "$eff_clean" != "." ] && [ "$eff_clean" != "/" ] && [ "${dir_clean#"$eff_clean/"}" != "$dir_clean" ]; then
    cur=$real_out; rel=${dir_clean#"$eff_clean/"}
  elif [ "$real_out" != "/" ] && [ "${out_dir#"$real_out/"}" != "$out_dir" ]; then
    cur=$real_out; rel=${out_dir#"$real_out/"}
  elif [ "$real_out" = "/" ] && [ "${out_dir#/}" != "$out_dir" ]; then
    cur=/; rel=${out_dir#/}
  elif [ "${dir_clean#/}" = "$dir_clean" ]; then
    cur=$(pwd -P && printf x) || return 2; cur=${cur%$'\nx'}
    case "$cur/" in "$real_out/"*) rel=$dir_clean ;; *) echo "当前目录越出受控成品目录 ($eff_out): $out" >&2; return 2 ;; esac
  else
    echo "目标父目录越出受控成品目录 ($eff_out): $out" >&2; return 2
  fi
  while [ -n "$rel" ]; do
    case "$rel" in */*) seg=${rel%%/*}; rel=${rel#*/} ;; *) seg=$rel; rel="" ;; esac
    case "$seg" in ''|.) continue ;; ..)
      case "$cur/" in "$real_out/"?*) cur=${cur%/*}; [ -n "$cur" ] || cur=/ ;; *) echo "目标父目录越出受控成品目录 ($eff_out): $out" >&2; return 2 ;; esac ;;
    *)
      [ ! -L "$cur/$seg" ] && [ -d "$cur/$seg" ] || { echo "目标父目录不存在或是符号链接: $out" >&2; return 2; }
      cur="$cur/$seg" ;;
    esac
  done
  out="$cur/$leaf"
  [ ! -L "$out" ] || { echo "目标路径不得是符号链接: $out" >&2; return 2; }
  if [ -e "$out" ]; then
    [ -f "$out" ] && [ -s "$out" ] \
      || { echo "目标已存在但不是非空普通文件（目录或空文件？）: $out" >&2; return 2; }
    # 已存在的文件也须过验收，防止手工拷入或旧版残留绕过白名单
    accept "$out" || { echo "已存在的文件未通过验收: $out" >&2; return 1; }
    echo "SKIP $out" >&2; return 0
  fi
  local part
  part=$(mktemp "$out.part.XXXXXX") || { echo "无法创建同目录临时文件（父目录是否存在？）: $out" >&2; return 1; }
  curl --fail --show-error --location --get --proto '=https' --proto-redir '=https' --max-redirs 3 \
       --max-filesize "$MAX_BYTES" --max-time 900 -H "User-Agent: $UA" \
       -o "$part" "$url" "$@" || { rm -f -- "$part"; return 1; }
  accept "$part" || { rm -f -- "$part"; return 1; }   # 没验收就当这次没取到
  # 用 os.link 直调 link(2) 而不用 mv -f 或裸 ln：目标已存在（文件/目录/符号链接）时原子报 EEXIST，绝不覆盖或链入目录
  if python3 -c 'import os,sys; os.link(sys.argv[1], sys.argv[2])' "$part" "$out" 2>/dev/null; then rm -f -- "$part"; FETCHED=1; return 0; fi
  rm -f -- "$part"
  if [ -L "$out" ] || [ -d "$out" ]; then echo "目标路径冲突（目录或符号链接）: $out" >&2; return 2; fi
  [ -f "$out" ] && { echo "并发冲突：$out 已被另一个调用发布，本次丢弃" >&2; return 3; }
  echo "发布失败（目录需支持同目录硬链接；若已支持，再查权限与配额）：$out" >&2; return 1
}
```

**验收必须在发布之前，不能留给"解析之前再检查"**：否则一个返回 200 的 soft-block 页（`--fail` 抓不到）第一次被存成最终名，之后每次跑都走 SKIP，那道检查再也不会执行。上面的 MIME 与体积检查只是通用下限，**不能单独识别 MIME 也合法的 soft-block**：尤其 `EXPECT_MIME` 允许 `text/plain` 时，纯文本拦截页会通过类型检查。调用方必须按目标把内容锚点并入 `accept`（例如 JSON 能解析且含必需字段、CSV 含必需表头、文本含稳定的结构锚点），锚点不符就返回非零；不确定锚点时不得把文件发布成已验收成品。放在发布前，"最终名存在"才等于"下完且通过本次完整验收"。发布（`os.link` 硬链接）是原子的，所以进程中途被杀只会留下 `.part`，不会留下半个成品。

**为什么发布用 `os.link` 硬链接而不用 `mv -f` 或裸 `ln`。** `mv -f` 无条件覆盖：两个调用同时发现目标不存在、各自下了**不同**的 URL 或参数、都通过验收，然后依次 `mv`——后完成的静默换掉先发布的成品，而**两边都返回成功**，最终内容取决于竞态；裸 `ln` 在目标并发变成目录或指向目录的符号链接时会把临时件链进该目录内部并返回成功。`python3` `os.link` 直调内核 `link(2)`，目标路径已存在（普通文件、目录或符号链接）时原子报错（`FileExistsError`，目标内容不变），撞上的调用删掉自己的临时件并按冲突类型返回 2 或 3。**前提是 `$OUT` 所在文件系统支持硬链接**；临时件与目标在同一目录，已经排除跨设备，但 FAT/exFAT 或部分网络挂载仍可能不支持。此时会明确报“发布失败”并丢弃本轮临时件，应把 `$OUT` 移到支持硬链接的文件系统，或另做带排他锁的发布实现；**不要退回 `mv -f`**。

⚠ 我自己第一次测并发时用了**同一个 URL** 跑两遍，两边内容相同，这个覆盖问题就被掩盖过去了——**测并发要让两个调用产生不同的内容**，否则测不出覆盖。

**这是"整文件级的批次续跑"，不是字节级断点续传**（没用 Range）。失败的传输整份丢弃、下次重下；已完成的文件跨次保留。这仍然值得做：跨年批量取数常要跑几十分钟，中途一次超时如果让你从头再来，你就会去掉上限——**没有续跑能力的脚本会逼作者拆掉安全阀**。

**SKIP 能保证什么、不能保证什么。** 能：当前路径上的非空普通文件通过了**本次** `accept`；如果它确由这个 `fetch` 发布，则发布前也完成了下载与验收。不能：

- **不能**仅凭 SKIP 证明文件由这个 `fetch` 产生；手工拷入或其他工具留下的文件也可能通过同一组验收
- **不能**保证它对应你**这次**的 URL 与参数。改了年份、改了查询、源方发了修订版，文件名没变，SKIP 就会给你旧的那份 → 换了取数参数就换输出文件名（把关键参数编进文件名），或直接清目录
- 别的来源留下的文件**会过一遍 `accept`**（类型不符、超体积上限都会被挡下），但通用验收下限**只看类型与体积**；即使调用方另加内容锚点，也不能自动证明 URL、参数、版本与取得方式 → 换了下载方式就先清掉 `$OUT`

⚠ 三个易错点：

- `$OUT`（及子目录）要**先 `mkdir -p`**。`fetch` 不建目录，父目录不存在、含符号链接或解析到 `$OUT` 之外时会在下载前直接返回 `2`，避免把本地路径错误误诊成网络问题或越界读写
- **`$OUT` 必须是调用方独占的受控目录**（勿使用多方共写的公共临时目录）：`[ -L "$out" ]` 与父目录 `pwd -P` 校验拦住的是既有的末端或中间目录符号链接；路径检查与 `accept "$out"` / `ln` 之间假设没有不可信并发写者替换目录项
- **要续跑的东西不能放 `$DL`**。`$DL` 在退出时被 `trap` 删掉，成品放进去等于每次都从头下。成品进 `$OUT`，只有解压产物、转出来的图这类一次性中间件进 `$DL`

| 参数 | 它到底管什么 |
|---|---|
| `--fail` | 让 HTTP ≥400 变成非零退出。**不带它，错误页会被存成"数据文件"且退出码是 0**。管不到返回 200 的 WAF/soft-404 页——那只能靠下面的类型与锚点检查 |
| `--show-error` | 配 `-s`/静默使用时仍打出错误原因 |
| `--proto '=https' --proto-redir '=https'` | 限定初始与重定向后的协议，防降级到明文 |
| `--max-redirs 3` | 默认是 **50** 跳（不是无限），这里是把它收紧到任务需要的量级 |
| `--max-filesize` | 字节上限。**下载前长度已知**→超限不启动（退出 63）；**长度未知（chunked）**→curl ≥8.4.0 在达阈值时中止（退出 56），**8.4.0 以前对这类响应完全无效** |
| `--max-time` | 只限时间不限字节，所以和上一条**都要** |
| `--get --data-urlencode` | 查询参数交给 curl 编码，别自己拼（见 §1.3） |
| `trap … EXIT` | 临时目录会被清理；不可信文件不落工作区 |

一手实测（本机 curl 8.7.1）：

```
$ curl -s --show-error --max-filesize 1K -o out.bin "<chunked-endpoint>"
exit=56 ; curl: (56) Exceeded the maximum allowed file size (1024) with 1024 bytes
$ wc -c < out.bin
1024                      ← 上限触发后截断文件仍在盘上，所以 fetch 里必须 rm
```

```
$ curl -s -o data.json "<当时返回 504 的接口>" ; echo $?
0                         ← 不带 --fail：504 的 HTML 被存成 data.json
$ curl -s --fail --show-error -o data.json "<同一 URL>" ; echo $?
22                        ← HTTP 错误被 --fail 转成非零；fetch 随后删除临时文件
```

`--max-filesize` 的版本条件出自 curl 官方手册原文（"before curl 8.4.0 … this option has no effect"；[curl 手册](https://curl.se/docs/manpage.html)，核验于 2026-07）。

**`accept` 是白名单，不是黑名单。** 黑名单（"排除 HTML"）等于默认接受一切你没想到的类型；白名单在类型不符时停下。每换一类目标就设一次 `EXPECT_MIME`，并按需再加——压缩包**展开后**的体积在预期量级、PDF 页数在预期量级。把一个 WAF HTML 或一个展开炸弹喂进解析器是这道验收要防的事，而它现在是 `fetch` 的一部分，不是一句"记得检查"。

**外部命令自己会失败**，而失败常表现为空输出。`$(file …)` 在 `file` 没装或执行失败时给空串，落进 `case` 没有任何分支命中，函数就以 0 返回——**未验收的字节被当成成品发布**。凡是拿命令输出做判据的地方都要显式接住非零退出与空输出，别让"判不出来"走成"通过"（同 §3.6）。

### 1.1 按源公布的上限限速

不少监管方与公共接口**明文要求**自动访问声明身份并公布速率上限。已核验的一例：美国证券交易委员会的站长 FAQ 同时给出"如何声明 user agent"与"maximum access rate is 10 requests per second"（[SEC webmaster FAQ](https://www.sec.gov/about/webmaster-frequently-asked-questions)，核验于 2026-07）。**依据：官方，仅对该服务成立。**

**别照抄那个数字**——去读你要访问的那个源自己公布的上限；没公布时用远低于常识的速率，并在循环里留 sleep。

### 1.2 归档站：只用于已下架、已替换或历史版本，且要问下架原因

**正当场景**：官方发布的文件被换掉/下架，或你要的是历史版本做时间序列。

**"它下架了"本身不是取回许可**——先问为什么下架。因**误披露个人信息、安全问题、法律争议或已确认的重大错误**而撤回的材料，不取回、不传播（除非有明确授权且做最小化处理）。把一份因错误被撤的表重新引进报告，比没有它更糟。

**明确不适用**：某个源仍在正常提供该文件、只是拒绝自动访问——那种情况下走归档就是规避源方的自动访问限制，属于本文边界表禁止的行为。此时的正确处置是获准的人工下载、官方批量接口，或按 `SKILL.md` 的状态词记「被挡住」。

### 1.3 查询参数交给 curl 编码，别自己拼

自己拼 query 会踩两类坑，一类来自 shell，一类来自目标 URL 自带的 `&`：

```bash
# 快照清单：目标 URL 与各参数都由 curl 编码
CDX_KEY="<文件名安全的目标+查询口径键，例如 targetA-exact-2015-2026>"
fetch "$OUT/cdx-$CDX_KEY.json" "https://web.archive.org/cdx/search/cdx" \
  --data-urlencode "url=$TARGET_URL" \
  --data-urlencode "matchType=exact" \
  --data-urlencode "output=json" \
  --data-urlencode "collapse=timestamp:4" \
  --data-urlencode "filter=statuscode:200" \
  --data-urlencode "from=2015" --data-urlencode "to=2026"

# 按时间戳取原始字节
fetch "$OUT/snap-$CDX_KEY-$TS.bin" "https://web.archive.org/web/${TS}id_/${TARGET_URL}"
```

- 目标 URL 自带 query（`...report?id=1&type=pdf`）时**必须编码**，否则 `&type=pdf` 会被目标接口当成它自己的参数
- `collapse=timestamp:4` 是"比较 timestamp 前 4 位（YYYY）并折叠**相邻**行"。⚠ 两处易错：`:6` 是 YYYYMM＝逐月；而 `collapse` 只作用于相邻行，所以只有 `matchType=exact` 时结果才近似"每年一条"——prefix/domain 查询下会变成"每个 URL 每年一条"，还可能撞上服务端结果上限
- `collapse` / `filter` / `matchType` 字段语义：**官方**（[Internet Archive CDX server 文档](https://github.com/internetarchive/wayback/blob/master/wayback-cdx-server/README.md)，核验于 2026-07），且是**该服务特定**行为，不是归档服务的通用契约
- 时间戳后加 `id_` 取原始字节：**实测**——帮助页与 Wayback API 文档均未找到说明，随时可能变

### 1.4 受阻时的分级处置（常见实例，非穷尽）

| 现象 | 先试什么 | 仍不行怎么记 |
|---|---|---|
| 脚本被拒、浏览器可访问 | 声明身份的 UA；查该源是否另有**官方批量下载入口或数据门户**；查是否需要注册 | 记「被挡住」+ 已试动作。**不要转走归档来规避**——见 §1.2 |
| `429` / `503` 且带 `Retry-After` | **这是源方在告诉你节奏**：按它给的秒数退避重试，并把请求速率永久降下来 | 反复 429 就记「被挡住」，写清你用的速率 |
| 需要密钥或注册 | 记为需凭证的渠道 | 写清要谁去申请 |
| 接口返回单页应用 HTML 而非数据 | 该接口很可能已下线，找现行接口或官方批量下载 | 记「被挡住」，注明疑似下线 |
| 超时 | 缩小范围（按年/按季/按分页）后重试 | 记已缩到多小仍失败 |
| 逐年/逐期文件的命名毫无规律 | **别猜模板**——从官方落地页把清单抄下来写死，并在脚本里注明清单出自哪个页面 | 记清单来源页；下次先看那一页有没有新增 |

「被挡住」不是"查过了没有"——两者对结论的含义完全不同（见 `public-disclosure-channels.md`）。

关于最后一行：同一机构逐年发布的文件名常常一年一个样（`7-1-25` 与 `7-1-2024` 混用、月日补零不一致）。猜模板会静默漏年份，而漏掉的那年在结果里看不出来。所以写死清单——**但落地页本身也可能不全**，抄清单不等于抄全了。清单要连这几项一起记：

- 页面 URL、取回日期、页面快照或 hash
- **页面是怎么呈现这批链接的**：分页？只显示最近几年？靠脚本延迟加载？（后两种最容易让人以为"就这些"）
- **你预期的期间范围与条目数**，以及实际拿到的

有了预期范围，期间出现空洞时才有东西可以触发失败；否则一份"忠实抄下来"的清单会稳定地漏掉同样几期，每次都看不出来。旧文件从页面撤下但 URL 仍可访问也很常见——这时按 §1.2 先问撤下原因。

### 1.5 目录式发现，别猜网址；分页要取完

要找"各地/各机构的同类数据集"时，逐个猜网址既慢又漏。开放数据平台通常提供目录检索接口。

```bash
# 注意单引号：URL 里的 $ 不能进双引号，否则被 shell 当变量吃掉
CATALOG_LIMIT=20
CATALOG_KEY="<文件名安全的关键词+查询口径键>"
fetch "$OUT/catalog-$CATALOG_KEY-n$CATALOG_LIMIT.json" 'https://api.us.socrata.com/api/catalog/v1' \
  --data-urlencode "q=$KEYWORD" --data-urlencode 'only=dataset' \
  --data-urlencode "limit=$CATALOG_LIMIT"
# 每条结果里：resource.id 是数据集 id，metadata.domain 是要发第二个请求的 host
```

```bash
# 取数据集本身：$limit 只是"这一页多少行"，必须自己翻页
OFF=0; PAGE=50000
while :; do
  page_file="$OUT/$DOMAIN-$ID-n$PAGE-p$OFF.json"
  if fetch "$page_file" "https://$DOMAIN/resource/$ID.json" \
      --data-urlencode '$order=:id' \
      --data-urlencode "\$limit=$PAGE" --data-urlencode "\$offset=$OFF"; then
    :
  else
    rc=$?
    [ "$rc" -eq 3 ] || exit 1
  fi
  # 显式接住失败：python3 缺失或 JSON 损坏时 N 是空串，
  # 后面的数值比较只报错不退出，OFF 不前进 → 反复读同一页的死循环
  if ! N=$(python3 -c 'import json,sys
x=json.load(open(sys.argv[1]))
if not isinstance(x,list): raise SystemExit("expected a JSON array page")
print(len(x))' "$page_file"); then
    echo "解析第 $OFF 页失败，停止" >&2; exit 1
  fi
  case "$N" in ''|*[!0-9]*) echo "页行数不是非负整数: '$N'" >&2; exit 1 ;; esac
  if [ "$N" -eq 0 ]; then break; fi
  OFF=$((OFF+N))
  if [ "$N" -lt "$PAGE" ]; then break; fi
done
echo "取到 $OFF 行"          # 与数据集自述行数比对，不一致就是没取完
```

这里的输出名也属于正确性契约：`DOMAIN`、`ID`、`PAGE`、`OFF` 都参与文件名，避免改分页大小或切换数据域后被旧文件的 SKIP 混入。`CDX_KEY` / `CATALOG_KEY` 同理，必须由调用方生成成**文件名安全且绑定目标与查询口径**的稳定键；只写一个好看的主题简称不够。

- **`$limit` / `$offset` / `$order` 前面的 `$` 是参数名的一部分**。写在双引号里会被 shell 展开成空（`?$limit=50000` → `?=50000`，本机实测），所以用单引号或 `\$`
- **不给稳定 `$order` 的分页会漏行也会重行**；没有终止断言的单页取数是最容易发生的系统性少算——数据集 12 万行、一页 5 万，静默少 58%。上面这段在真实数据集上实测取满 2368 行、按行标识去重后仍是 2368 条，无重复
- **去重要按行标识，不要按行内容**：同一实测里按整行内容去重会掉 9 行，而那 9 行是**真实存在的重复记录**（同一批次里两条各字段全同的通知）。按内容去重＝静默改了分母。行标识（如该平台的 `:id`）通常需要显式 select 才会返回
- 分页语义与单页上限：**官方**（[Socrata LIMIT](https://dev.socrata.com/docs/queries/limit.html) / [OFFSET](https://dev.socrata.com/docs/queries/offset.html)，核验于 2026-08）；Discovery API 的存在性同为官方（[开发者门户](https://dev.socrata.com/)），上面的**具体参数形状**为**实测**
- 收益很实：一次检索能命中若干同类数据集，替代几十次猜测

---

## 二、解析

**这一节所有代码遵循同一条原则：读不到、对不上、不确定，就大声失败并非零退出。**静默降级（缺列当空、失败页当零、单页当全量）产生的是"看起来可信的错数"，比崩掉难查得多。

### 2.1 超大表格：流式读，缺列即停

体量大的表格文件解压后单个工作表可达数百 MB。某些常用库在这种体量下**不报错、返回空表**——静默失败最难查。

```python
# 跨年取同一语义字段：列名会改，先过别名表，再判缺
ALIAS = {
    "<语义字段A>": ["<今名>", "<旧名>"],        # 每个语义字段一串候选
    "<语义字段B>": ["<今名>", "<更旧的名>"],
}
norm = lambda s: " ".join(str(s).split()).upper()   # 表头与候选必须走同一个规范化

wb = openpyxl.load_workbook(path, read_only=True, data_only=True)
try:
    ws = wb[SHEET_NAME]                       # 显式选表：首个 sheet 常是封面
    it = ws.iter_rows(values_only=True)
    try:
        hdr = [norm(c) if c is not None else "" for c in next(it)]
    except StopIteration:
        raise SystemExit(f"{path}: 工作表没有表头行——先排除库静默返回空表")
    dup = {h for h in hdr if h and hdr.count(h) > 1}
    if dup:
        raise SystemExit(f"{path}: 表头重复，列归属不可判定: {dup}")

    idx, hit, problems = {}, {}, []
    for want, cands in ALIAS.items():
        found = [norm(c) for c in cands if norm(c) in hdr]      # 命中的**全部**候选
        if len(found) == 0:
            problems.append(f"{want}: 候选 {cands} 一个都不在表头")
        elif len(found) > 1:
            # 新旧列同时存在＝口径很可能变了。这时"按优先级取第一个"是猜，不是读。
            problems.append(f"{want}: 候选同时命中 {found}，须先判定该期用哪个语义")
        else:
            idx[want], hit[want] = hdr.index(found[0]), found[0]
    # 两个语义字段绑到同一物理列 = 映射不是单射，必有一个是错的
    for col, wants in {c: [w for w in idx if idx[w] == c] for c in set(idx.values())}.items():
        if len(wants) > 1:
            problems.append(f"列 {hdr[col]!r} 被 {wants} 同时占用")
    if problems:
        raise SystemExit(f"{path}: 列映射不可判定\n  " + "\n  ".join(problems)
                         + f"\n  实际表头: {hdr}")
    print(f"{path}: 命中别名 {hit}")          # 落到日志/审计输出，不只留在内存
    n = 0
    for row in it:
        ...
        n += 1
    if n == 0:
        raise SystemExit("行数为 0——先排除库静默返回空表，别记成该源没数据")
finally:
    wb.close()
```

- **实测**
- **千万别写 `hdr.index(k) if k in hdr else -1`**：Python 的 `-1` 是**最后一列**，缺列会静默读到"总计"列，行数断言照样通过，错数直接进结论。本机复现：`hdr=['A','TOTAL']`、`idx={'EMPLOYEES': -1}` → `row[idx['EMPLOYEES']]` 取到 `TOTAL` 的值
- **列按名字取，不按位置取**（同一数据源不同年份的列序会变）
- **别名表要记下每年命中的是哪个名字**（上面的 `hit`）。一个字段从旧名迁到新名，常常同时意味着**口径改了**——只看数值序列是连续的，看不出这件事
- **副表可能比主表全**：同一批数据常有"一案一行"的主表和"一案多行"的明细表（全部地点、全部子项）。用主表算总量会漏掉一案多项的部分——先看这个数据源有没有配套明细表
- ⚠ **`data_only=True` 不计算公式**，它返回工作簿最后保存时缓存的值；缓存缺失时得到 `None`（[openpyxl 文档](https://openpyxl.readthedocs.io/en/stable/tutorial.html)，核验于 2026-07）。所以关键列为空时**不能直接记成渠道未命中**：先用 `data_only=False` 看该单元格是否本就是公式（本机实测：openpyxl 写出的含公式工作簿，`data_only=True` 给 `None`，`data_only=False` 给 `'=SUM(A1:A2)'`），若是，问题在缓存而不在数据源
- ⚠ `read_only` 依赖生产者写对 worksheet dimensions；行列数明显不对时用 `reset_dimensions()` / `calculate_dimension()` 复核（[openpyxl 性能文档](https://openpyxl.readthedocs.io/en/stable/optimized.html)）

### 2.2 图像版 PDF：探针只是启发式，再走系统 OCR

法定登记的账目常是图像版 PDF：没有文本层，也没有结构化版本。

**依赖**：下面的 `pdftotext` / `pdfimages` / `pdftoppm` 来自 poppler，**不是 macOS 自带**（本机三者均在 `/opt/homebrew/bin`，`/usr/bin` 无同名文件）。没有它就先装 poppler，或把这条渠道记成需要额外工具——这是执行能力缺口，不是渠道被挡。本节只有 OCR 那一步是系统自带的。

```bash
# 启发式探针：目标页能抽出多少非空白字符
pdftotext -f 1 -l 3 doc.pdf - | tr -d '[:space:]' | wc -c
pdfimages -list doc.pdf | head -3     # 嵌入图像的渲染分辨率，作为经验起点
```

- **它不是决定性判据**。一页只有矢量表格、外加一处 render mode 3（隐形）文字，探针就会返回非零而可见内容一个字都抽不出来——本机构造的最小 PDF 实测 `extracted='OK', nonspace_bytes=2`。反向的假阴性也存在（轮廓化文字）
- 所以真正要看的是**覆盖率与锚点**：目标区域的表头、关键数字是否都在抽出的文本里、位置是否对得上。抽出的文本与可见内容不一致时**两条都做**：OCR 一遍，与文本层逐项对照
- **为什么也不用 `pdffonts`**：它只做字体分析（[pdffonts 手册](https://manpages.debian.org/trixie/poppler-utils/pdffonts.1.en.html)）。带无效或隐藏 OCR 层的图像件也会有字体，轮廓化文字可能没有字体
- 分辨率不是充分条件：`pdfimages` 给的 PPI 只是嵌入图像的渲染分辨率，**300 左右是经验起点而非阈值**

**转图前先算像素预算**——页面尺寸不受你控制：

```bash
# MediaBox 可以很大：200×200 英寸的页在 300 DPI 下是 60000² ≈ 36 亿像素/页
pdfinfo doc.pdf | grep -E 'Page size|Pages'
# 用 -scale-to 钉住长边，而不是钉住 DPI；只转需要的页
pdftoppm -scale-to 3000 -png -gray -f 1 -l 14 doc.pdf "$DL/page"
du -sh "$DL"                      # 转完看一眼实际占用，超预期就停
```

页号范围不是资源上限（一页就能打爆磁盘）。上限是：**长边像素 + 页数 + 输出总字节**，三者都要有，且转完实测一次。

macOS 可用系统自带的文字识别框架，不必安装第三方 OCR。**关键是关掉语言纠正**，否则财务数字会被"修"坏；同时**输出几何信息、失败要非零退出**：

```swift
// swiftc -O -o ocr ocr.swift ；用法 ./ocr page-01.png ... > out.tsv
import Foundation; import Vision; import AppKit
var failed = 0
for path in CommandLine.arguments.dropFirst() {
    let name = (path as NSString).lastPathComponent
    guard let img = NSImage(contentsOfFile: path), let tiff = img.tiffRepresentation,
          let bmp = NSBitmapImageRep(data: tiff), let cg = bmp.cgImage else {
        FileHandle.standardError.write("OPEN-FAIL\t\(name)\n".data(using: .utf8)!)
        failed += 1; continue                      // 记下是哪一页，不静默跳过
    }
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = .accurate
    req.usesLanguageCorrection = false             // 财务数字必须关，否则会被“纠正”
    do { try VNImageRequestHandler(cgImage: cg, options: [:]).perform([req]) }
    catch {
        FileHandle.standardError.write("OCR-FAIL\t\(name)\t\(error)\n".data(using: .utf8)!)
        failed += 1; continue
    }
    let obs = req.results ?? []
    if obs.isEmpty {
        FileHandle.standardError.write("EMPTY\t\(name)\n".data(using: .utf8)!)
        failed += 1; continue
    }
    // 先按行（midY 降序）再按列（minX 升序）；几何信息必须留给下游还原版面
    for o in obs.sorted(by: { abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.01
                              ? $0.boundingBox.midY > $1.boundingBox.midY
                              : $0.boundingBox.minX < $1.boundingBox.minX }) {
        guard let c = o.topCandidates(1).first else { continue }
        let b = o.boundingBox
        print("\(name)\t\(b.minX)\t\(b.minY)\t\(b.width)\t\(b.height)\t\(c.confidence)\t\(c.string)")
    }
}
if failed > 0 { exit(1) }                          // 缺页必须让调用方看见
```

- `usesLanguageCorrection` 属于该框架的公开接口（[Apple Vision 文档](https://developer.apple.com/documentation/vision/vnrecognizetextrequest)，核验于 2026-07）。**依据：官方，仅对该平台成立**
- **其他平台**：本文不提供等价配方——装一个 OCR 引擎，或把该渠道记成需要额外工具，不要假装有跨平台路径
- 上面的两级排序只是**近似**，那个 `0.01` 不是可依赖的阈值：本机拿一张干净的 3×3 合成表实测，同一行内两个单元格的 `midY` 差就有 **0.017**（已超过阈值），只是恰好按 Y 降序排也对。版式一变、抖动方向一变，同一行就会交错。这就是为什么必须输出 bbox——**版面还原是下游一道独立工序，不是排序能解决的事**，而丢了 bbox 就再也补不回来
- OCR **会打乱表格列序**——必须配 §3 的自校验，不能裸用 OCR 出的数

### 2.3 结构化接口：标签要有回退链

同一语义字段在不同年份可能用不同标签，只认一个就会缺年份。

```javascript
const TAGS = ['<PreferredTag>', '<LegacyTag>', '<GenericTag>'];   // 按优先级回退
let series = {};
for (const t of TAGS) Object.assign(series, { ...(await concept(t)), ...series });
// 记下每个年份实际命中的是哪个标签——回退链会掩盖口径变化
```

- **实测**
- 另一半：**结构化接口未必有你要的字段**。缺的字段常只存在于正文里，需要正则抽取，且各家措辞不同——单一模式会漏，要按序试多套并记录命中的是哪一套

---

## 三、自校验（本文最该被抄走的一节）

来源真实、工具调用真实、字段取对了，**取到之后的处理仍然会错**。下面是本次实际发生过的几类，**不是完整清单**——单位、期间、范围、唯一键重复、缺失分区等完整自校验义务在 `SKILL.md`，本节只补它没有的形状。

### 3.1 行内既有分项又有行合计 → 整行求和得 2 倍值

法定报表的一行常同时给出各分项与该行合计。把整行数字全加一遍，得到的是 2 倍。

**三重核对**（三条都过才用结果）：

1. 每个类别行：分项之和 == 该行末位的行合计
2. 各类别行合计相加 == 报表自己给出的总数
3. 总数行自身：其分项之和 == 其末位数

未通过时**按诊断顺序走**：先查解析、单位、舍入、版本（有来源格式或模式证据支持的解析修正是正当的）；再查来源的修订与勘误、以及来源自身的内部矛盾；仍不能解释就**如实报告源内冲突**，不让它以确定值进入结论。**不要一律归因为"我解析错了"**——来源确实会有内部矛盾。

另外必须过一次与研究对象相称的外部边界 sanity check，例如子集数量不可能大于同口径总体；在组织调研场景里，某国人数不可能大于该组织全球人数。这类检查能当场挡住 2 倍错值，但只能否证，不能确证。

### 3.2 用加总反推列归属：提高可信度，不构成确证

OCR 或宽表解析后常搞不清"哪一列是哪一年"。可以用恒等式做假设检验：

```python
totA = sum(v[0] for v in rows.values())
totB = sum(v[1] for v in rows.values())
# 两组同时与报表自述的合计吻合 → 该列归属假设可信度显著提高
```

**但这不是确证**：数值恒等式只说明数字关系，同源的分项与合计常出自同一生成程序。最终归属仍要靠表头、脚注、字段定义或独立映射来定（与 `SKILL.md` 的"恒等式只是 sanity check、不构成语义依据"一致）。

### 3.4 名单进出比对：范围变化会伪装成事件

拿同一份名单的逐期快照做差分（谁进了、谁出了）时，有两层噪声会被误读成真实变动：

- **同人异名**：同一个人在不同期用了不同写法（全名/常用名/中间名有无）→ 差分会同时报"一个人离开、一个人加入"。必须先做归一，且归一规则要写出来
- **收录范围本身会变**：一份名单页面收谁、不收谁，发布方随时可能调整。**"从名单里消失"不等于"离开了"**——它可能只是不再被收录。差分结果只能当**线索**：每一条要用**独立于这份名单的来源**证实（同一上游数据的另一个展示面不算独立，那是循环确认），并写明该来源的截至日期。证实不了的按 `SKILL.md` 的既有处置走——进待核验清单、不得进入承重结论；**别新造一个"未确认"标签**

- **匹配方法自己会造出"消失"**：按 token 集合 / 精确串做归一时，标签**长出新词**（原名被包进一个更长的名字里）会漏配，差集于是报出一个其实还在的实体"消失了"。**凡由差集得出的缺席结论，落笔前先过一遍包含式复检**（把旧名当子串在新全集里查一遍）。**复检只能推翻缺席，不能确认缺席。** 命中且确认与原实体同一（新名把旧名包进去、指向同一对象）→ 判漏配，缺席结论作废；命中但确认是另一个恰好含该字串的实体，或根本没命中 → **只说明这条路没找到它**，不等于它真的不在：改名后的新名可能完全不含旧名，任何字面匹配都照不到。所以缺席结论的成立仍走上一条的既有处置——用独立于该名单的来源证实，证实不了就进待核验清单，不得因为「复检过了」而升格为结论。这与上一条方向相反：上一条是发布方不再收录，这一条是**我方的匹配口径**造的假缺席——两条都要过，只处理其一仍会出错。缺席结论同时要写明检索边界（查了哪些面、到什么截至日期），"未出现在任何一手材料"这类全称否定不写边界即为过强。

这三层不处理，一张"逐年进出表"会看起来非常有说服力而实际大半是噪声。

自建名称匹配与双向抽样、分页全量饱和核验、检查器自证与组合覆盖、公开数据采集基线顺序与增量管线复验、以及无产出渠道记录细则见 [evidence-controls-and-program-mode.md](evidence-controls-and-program-mode.md)。
