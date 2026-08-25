#!/usr/bin/env python3
"""doc-lint — 交付文档的表格与结构的起草期确定性检查（Markdown）。

判据来源：
  [外] WCAG 2.2 SC 1.3.1 (Level A) — 通过视觉呈现传达的信息与关系必须可被程序确定。
       对表格即：真表头，不能用加粗行冒充表头。
  [外] ICD 203 §9 — tables 属于 visual information；且「图形式比文字更能传达
       空间/时间关系时应当出图」。据此判「该出图却压成表」。
  [外] ICD 203 §1/§3 — 承载判断的内容要能追到来源，并区分信息与假设。
  [工] 其余为工程判断（列数过多、占位符未填、数值列无单位、图文引用一致）。

  已删除的谓词（勿再加回）：标题过长、单元格塞整段、段落内并列枚举、列表项多句。
  它们都拿宽度或计数当「表达好不好」的代理，而这类阈值经查证无可靠来源；
  全仓 392 份文档试跑时它们产生 318 条 ERROR，抽样中无一条是其声称的缺陷。

用法: doc-lint.py <file.md>... [--json]
"""
import sys, re, os, json, collections

CJK = re.compile(r'[\u4e00-\u9fff]')

def width(s):
    """近似显示宽度：汉字 2，其余 1。"""
    return sum(2 if CJK.match(c) else 1 for c in s)

def parse_tables(lines):
    """返回 [(start_line, header_cells, sep_ok, rows)]"""
    tables = []
    i = 0
    while i < len(lines):
        if lines[i].lstrip().startswith('|') and i + 1 < len(lines):
            sep = lines[i + 1].strip()
            sep_ok = bool(re.match(r'^\|?[\s:\-\|]+\|[\s:\-\|]*$', sep)) and '-' in sep
            if sep_ok:
                header = [c.strip() for c in lines[i].strip().strip('|').split('|')]
                rows = []
                j = i + 2
                while j < len(lines) and lines[j].lstrip().startswith('|'):
                    rows.append([c.strip() for c in lines[j].strip().strip('|').split('|')])
                    j += 1
                tables.append((i + 1, header, sep_ok, rows))
                i = j
                continue
        i += 1
    return tables

PLACEHOLDER = {'-', '—', '–', 'N/A', 'n/a', 'TBD', 'TODO', '待定', '待补', '?', '待填'}
NUMRE = re.compile(r'^[¥$€]?\s*-?[\d,]+(\.\d+)?\s*[%‰]?$')
UNIT_HINT = re.compile(r'[%‰]|元|美元|万|亿|GB|TB|MB|ms|s\b|次|人|天|月|年|条|个|倍|Ki?B|/')

FENCE = re.compile(r'^\s*(```|~~~)')

def strip_fences(lines):
    """把围栏代码块内的行替换成空行（保留行号）。

    代码块里的内容不是文档结构：ASCII 分隔线、缩进的示例标题、
    示例表格都会被结构谓词误判。全仓试跑时 `── Report ──` 这类
    分隔线被当成标题，就是漏了这一层。
    """
    out = []
    in_fence = False
    for ln in lines:
        if FENCE.match(ln):
            in_fence = not in_fence
            out.append('')
            continue
        out.append('' if in_fence else ln)
    return out

def lint(path):
    # 非 UTF-8 文本（图片等）不是本检查器的对象：跳过而不是崩——
    # 调用方按目录通配传入时，目录里混着图片是常态。
    # 与 figure-lint 对齐：坏文件报 READ 并继续整批，不能静默判干净——
    # 早先返回空发现集 + skipped=true，等于让损坏的 .md「干净通过」。
    try:
        src = open(path, encoding='utf8').read()
    except (UnicodeDecodeError, OSError) as e:
        return ([{'level': 'ERROR', 'code': 'READ',
                  'msg': f'无法读取: {type(e).__name__}: {e}', 'line': None}],
                {'tables': 0, 'figures': 0, 'lines': 0})
    raw_lines = src.split('\n')
    # mermaid 图是**图**不是代码：必须在剥离围栏前数，否则恒为 0，
    # 既会制造 CARRIER-IMBALANCE 假报，又让图文引用检查漏检。
    n_mermaid = sum(1 for ln in raw_lines if re.match(r'^\s*(```|~~~)\s*mermaid\b', ln))
    lines = strip_fences(raw_lines)
    src = '\n'.join(lines)   # 后续按剥离围栏后的正文分析
    F = []
    def add(level, code, msg, line=None):
        F.append({'level': level, 'code': code, 'msg': msg, 'line': line})

    # ---- 表格 ----
    tables = parse_tables(lines)
    fake_header_rows = 0
    for (ln, header, sep_ok, rows) in tables:
        ncol = len(header)

        # [外] WCAG 1.3.1：表头必须是真表头
        if all((not h) or h in PLACEHOLDER for h in header):
            add('ERROR', 'WCAG-131-TABLE', f'表格表头为空——表头必须可被程序确定，不能靠视觉暗示', ln)

        # [工] 列数过多
        if ncol > 8:
            add('WARN', 'TABLE-WIDE', f'{ncol} 列——超出一屏可读范围，考虑拆表或转置', ln)

        # [工] 占位符未填
        cells = [c for row in rows for c in row]
        if cells:
            ph = sum(1 for c in cells if c in PLACEHOLDER or not c)
            if ph / len(cells) > 0.25:
                add('WARN', 'TABLE-UNFILLED',
                    f'{ph}/{len(cells)} 个单元格为空或占位符（{ph/len(cells)*100:.0f}%）——表未填完', ln)

        # [工] 数值列缺单位/口径
        for c_i in range(ncol):
            col = [row[c_i] for row in rows if c_i < len(row)]
            nums = [c for c in col if NUMRE.match(c)]
            if len(nums) >= 3 and len(nums) / max(len(col), 1) > 0.6:
                head = header[c_i] if c_i < len(header) else ''
                if not UNIT_HINT.search(head) and not any(UNIT_HINT.search(c) for c in nums):
                    add('WARN', 'TABLE-NO-UNIT',
                        f'数值列「{head or f"第{c_i+1}列"}」表头与单元格均无单位/口径', ln)

        # 载体选择原则是 [外]（ICD 203 §9：图形式更能传达空间/时间关系时应出图），
        # 但「≥6 行、数值占比 >0.8、≤3 列」这三个识别阈值是 [工]——本检查器自定的
        # 保守下界，无外部依据。两者档位不同，不能一起挂在 [外] 名下。
        if len(rows) >= 6:
            numcols = 0
            for c_i in range(ncol):
                col = [row[c_i] for row in rows if c_i < len(row)]
                if col and sum(1 for c in col if NUMRE.match(c)) / len(col) > 0.8:
                    numcols += 1
            if numcols == 1 and ncol <= 3:
                add('WARN', 'ICD203-9-SHOULD-BE-CHART',
                    f'{len(rows)} 行 × {ncol} 列且仅一列数值——量级对比用图形式更能传达。'
                    f'[外] 载体选择原则来自 ICD 203 §9；[工] 触发阈值（≥6 行 / 数值占比 >0.8 / ≤3 列）'
                    f'为本检查器自定的保守下界，无外部依据', ln)

    # ---- 文档级：表图配比 ----
    n_fig = len(re.findall(r'!\[', src)) + n_mermaid + len(re.findall(r'<img', src))
    n_tab = len(tables)
    # [工] 计数阈值是工程启发式，不是 ICD 203 的内容。ICD 203 §9 的判据是
    # 「图形式是否比文字更能传达」——那取决于内容，不取决于表的个数。
    # 八张查询表 / 模式表 / 证据表本来就不需要图，所以这条只报 WARN 不阻断，
    # 且只在存在「量级对比型」表格（已由 ICD203-9-SHOULD-BE-CHART 认定）时才提示。
    chart_worthy = any(x['code'] == 'ICD203-9-SHOULD-BE-CHART' for x in F)
    if n_tab >= 8 and n_fig == 0 and chart_worthy:
        add('WARN', 'CARRIER-IMBALANCE',
            f'{n_tab} 个表、0 张图，且其中有适合出图的量级对比表——'
            f'信息可能整体压给了表格（计数阈值为工程启发式，非外部标准）')
    elif n_tab >= 10 and n_fig and n_tab / n_fig > 8 and chart_worthy:
        add('WARN', 'CARRIER-IMBALANCE',
            f'{n_tab} 表 / {n_fig} 图，比值 {n_tab/n_fig:.1f}——偏表（工程启发式）')


    # ---- 图文一致 ----
    # 正文引用的图号 vs 实际图数；以及有图从不被正文引用（孤图）
    # 采集「正文引用」时必须排除图注行本身，否则图注会把自己算成引用（假阴性）
    CAPTION_LINE = re.compile(r'^\s*[*_]*图\s*\d{1,2}\s*[：:]')
    fig_refs = set()
    for _ln in lines:
        if CAPTION_LINE.match(_ln):
            continue
        for m in re.finditer(r'图\s*(\d{1,2})', _ln):
            fig_refs.add(int(m.group(1)))
    # 图注锚（![...] 的 alt、或「图 N：」形式的说明行）
    caption_nums = set()
    for m in re.finditer(r'^\s*\*?图\s*(\d{1,2})\s*[：:]', src, re.M):
        caption_nums.add(int(m.group(1)))
    n_fig_local = n_fig
    # 采用编号图注约定时按**实际编号**比对；早先按数量比（n > max(图数, 图注数)）
    # 两个方向都会错：引用图 2 而图注只有 1 和 3 不报，唯一图注是图 10 却误报。
    if fig_refs and caption_nums and not n_fig_local:
        # 有编号图注、却没有任何真实图实例：图注在描述不存在的图。
        add('ERROR', 'FIG-REF-DANGLING',
            f'文档有编号图注 {sorted(caption_nums)} 但没有任何图片或 mermaid 图——图注指向的图不存在')
    elif fig_refs and caption_nums:
        missing = sorted(fig_refs - caption_nums)
        if missing:
            add('ERROR', 'FIG-REF-DANGLING',
                f'正文引用了「图 {missing}」但文档没有对应编号的图注'
                f'（现有图注编号 {sorted(caption_nums)}）——引用悬空')
    elif fig_refs and not caption_nums and n_fig_local:
        # 「引用悬空」的前提是文档确实在用图系统。一张图都没有的文档里出现「图 N」，
        # 那是在**谈论**图（举例、引用规范条文），不是在引用本文档的图——
        # 本检查器自己的判据文档就因此被误判过一次。
        missing = sorted(n for n in fig_refs if n > n_fig_local)
        if missing:
            add('ERROR', 'FIG-REF-DANGLING',
                f'正文引用了「图 {missing}」但文档只有 {n_fig_local} 张图且无编号图注——引用悬空')
    # 只有当文档已采用编号图注约定，或图多到需要索引（>=3）时，才要求正文引用。
    # 单张随文插图不强制编号——否则控制组会被误报。
    if n_fig_local and not fig_refs and (caption_nums or n_fig_local >= 3):
        add('WARN', 'FIG-ORPHAN',
            f'{n_fig_local} 张图，正文一次也没引用「图 N」——图与正文各说各的，读者不知道该在哪一步看图')
    if caption_nums and fig_refs:
        never_ref = sorted(caption_nums - fig_refs)
        if never_ref:
            add('WARN', 'FIG-ORPHAN', f'图注存在但正文未引用：图 {never_ref}')

    # ---- 加粗行冒充小节标题 ----
    for idx, ln in enumerate(lines, 1):
        s = ln.strip()
        if re.match(r'^\*\*[^*]{2,40}\*\*[:：]?$', s):
            fake_header_rows += 1
    if fake_header_rows >= 5:
        add('WARN', 'WCAG-131-FAKE-HEADING',
            f'{fake_header_rows} 处「独占一行的加粗短语」——若充当小节标题，结构无法被程序确定（WCAG 1.3.1），且目录不可用')

    return F, {'tables': n_tab, 'figures': n_fig, 'lines': len(lines)}


def main(argv):
    as_json = '--json' in argv
    files = [a for a in argv[1:] if not a.startswith('--')]
    if not files:
        print('用法: doc-lint.py <file.md>... [--json]', file=sys.stderr)
        return 2
    out = {}
    n_err = n_warn = 0
    for f in files:
        F, st = lint(f)
        out[f] = {'findings': F, 'stats': st}
        n_err += sum(1 for x in F if x['level'] == 'ERROR')
        n_warn += sum(1 for x in F if x['level'] == 'WARN')
    if as_json:
        print(json.dumps(out, ensure_ascii=False, indent=1))
    else:
        for f, r in out.items():
            st = r['stats']
            print(f"\n{os.path.basename(f)}  [{st['lines']} 行 / {st['tables']} 表 / {st['figures']} 图]")
            seen = collections.Counter()
            for x in r['findings']:
                seen[x['code']] += 1
                if seen[x['code']] <= 3:
                    loc = f"L{x['line']}" if x['line'] else '--'
                    print(f"  {x['level']:5} {x['code']:26} {loc:>6}  {x['msg']}")
            for c, n in seen.items():
                if n > 3:
                    print(f"  ...   {c:26}         另有 {n-3} 处")
            if not r['findings']:
                print('  ✓ 无发现')
        print(f'\n合计: {n_err} ERROR, {n_warn} WARN')
    return 1 if n_err else (2 if n_warn else 0)

if __name__ == '__main__':
    sys.exit(main(sys.argv))
