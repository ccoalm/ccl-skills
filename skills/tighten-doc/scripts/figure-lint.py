#!/usr/bin/env python3
"""figure-lint — SVG 图的起草期确定性检查。

判据只取两类：
  1) 有外部权威依据的（WCAG 对比度、C4 记法、SVG 文本不换行的几何后果）
  2) 纯事实性的一致性检查（跨图比例/字号阶梯是否统一）

不含任何"可读性阈值"类的拍脑袋数字。

用法:  figure-lint.py <dir-or-file>...  [--json]
退出码: 0 全过 / 1 有 ERROR / 2 只有 WARN
"""
import sys, re, os, glob, json, math, collections
import xml.etree.ElementTree as ET

SVG = "{http://www.w3.org/2000/svg}"

# ---------- 颜色与对比度（WCAG 2.2 SC 1.4.3） ----------

def _lum(hexcolor):
    h = hexcolor.lstrip('#')
    if len(h) == 3:
        h = ''.join(c * 2 for c in h)
    r, g, b = [int(h[i:i+2], 16) / 255 for i in (0, 2, 4)]
    f = lambda c: c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    return .2126 * f(r) + .7152 * f(g) + .0722 * f(b)

def contrast(fg, bg):
    l1, l2 = sorted([_lum(fg), _lum(bg)], reverse=True)
    return (l1 + .05) / (l2 + .05)

# ---------- 文本宽度估算 ----------
# CJK 全角 ≈ 1.0em，拉丁与数字 ≈ 0.55em，空格 ≈ 0.28em。
# 这是保守估算，不是精确排版；用于判「明显装不下」，不用于判「刚好放得下」。

def est_width(text, font_size):
    w = 0.0
    for ch in text:
        o = ord(ch)
        if 0x4E00 <= o <= 0x9FFF or 0x3000 <= o <= 0x303F or 0xFF00 <= o <= 0xFFEF:
            w += 1.0
        elif ch == ' ':
            w += 0.28
        else:
            w += 0.55
    return w * font_size

# ---------- CSS 解析 ----------

def parse_css(svg_text):
    """返回 {class_name: {prop: value}}"""
    out = {}
    for block in re.findall(r'<style[^>]*>(.*?)</style>', svg_text, re.S):
        for m in re.finditer(r'([^{}]+)\{([^}]*)\}', block):
            sels, body = m.group(1), m.group(2)
            props = {}
            for decl in body.split(';'):
                if ':' in decl:
                    k, v = decl.split(':', 1)
                    props[k.strip()] = v.strip()
            for sel in sels.split(','):
                sel = sel.strip()
                if sel.startswith('.'):
                    out.setdefault(sel[1:], {}).update(props)
                elif sel:
                    out.setdefault('%' + sel, {}).update(props)  # 元素选择器
    return out

def resolve(el, css, inherited=None):
    """合并元素选择器、class、行内 style 与 presentation attribute。"""
    props = dict(inherited or {})
    tag = el.tag.replace(SVG, '')
    props.update(css.get('%' + tag, {}))
    for c in (el.get('class') or '').split():
        props.update(css.get(c, {}))
    for k in ('fill', 'font-size', 'font-weight', 'stroke'):
        if el.get(k):
            props[k] = el.get(k)
    if el.get('style'):
        for decl in el.get('style').split(';'):
            if ':' in decl:
                k, v = decl.split(':', 1)
                props[k.strip()] = v.strip()
    return props

UNIT_TO_PX = {'px': 1.0, 'pt': 96.0 / 72.0, 'pc': 16.0, 'in': 96.0,
              'cm': 96.0 / 2.54, 'mm': 9.6 / 2.54, '': 1.0}

def px(v, default=None, base=16.0, unsupported=None):
    """把长度换算成用户单位。

    早先只取数字前缀：`1em` 当 1px、`12pt` 当 12px，
    会压掉 SVG-OVERFLOW、也会用错 WCAG 大字阈值。
    """
    if not v:
        return default
    m = re.match(r'^\s*(-?[\d.]+)\s*([a-z%]*)\s*$', str(v).strip(), re.I)
    if not m:
        if unsupported is not None:
            unsupported.add(str(v))
        return default
    num, unit = float(m.group(1)), m.group(2).lower()
    if unit in ('em', 'rem'):
        return num * base
    if unit in UNIT_TO_PX:
        return num * UNIT_TO_PX[unit]
    if unsupported is not None:
        unsupported.add(str(v))
    return default

# ---------- 几何：找文本压着的底色 ----------

def rects_of(root, css):
    """收集矩形类底色形状，按文档序（后画的在上）。"""
    out = []
    def walk(node, inh):
        for el in node:
            p = resolve(el, css, inh)
            tag = el.tag.replace(SVG, '')
            if tag == 'rect':
                try:
                    x = float(el.get('x', 0)); y = float(el.get('y', 0))
                    w = float(el.get('width', 0)); h = float(el.get('height', 0))
                except ValueError:
                    x = y = w = h = 0
                fill = p.get('fill')
                if w > 0 and h > 0 and fill and fill.startswith('#'):
                    out.append((x, y, w, h, fill.upper()))
            walk(el, p)
    walk(root, {})
    return out

def referenced_defs_colors(root, css):
    """被 marker-*/use/fill=url() 引用到的 defs 定义确实会渲染，其颜色受契约约束。

    整体跳过 defs 是过度修正：箭头 marker 用契约外的颜色就查不出来，
    与「连线与箭头同样受配色契约约束」的声明矛盾。
    """
    used = set()
    for el in root.iter():
        p = resolve(el, css, {})
        for key in ('marker-start', 'marker-end', 'marker-mid', 'fill', 'stroke'):
            v = (p.get(key) or el.get(key) or '').strip()
            m = re.match(r'url\(#([^)]+)\)', v)
            if m:
                used.add(m.group(1))
        if el.tag == f'{SVG}use':
            href = el.get('href') or el.get('{http://www.w3.org/1999/xlink}href') or ''
            if href.startswith('#'):
                used.add(href[1:])
    seen = set()
    for defs in root.iter(f'{SVG}defs'):
        for node in defs:
            if node.get('id') not in used:
                continue
            for el in [node] + list(node.iter()):
                p = resolve(el, css, {})
                for key in ('fill', 'stroke'):
                    v = (p.get(key) or '').strip()
                    if v.startswith('#'):
                        seen.add(v.upper())
                tag = el.tag.replace(SVG, '')
                # 同 all_paint_colors：fill 初始值是 black。被引用的 marker
                # 若省略 fill，实际渲染成黑色——不算进来就能靠省略绕过契约。
                if tag in ('path', 'rect', 'circle', 'ellipse', 'polygon', 'polyline'):
                    if not (p.get('fill') or '').strip():
                        seen.add('#000000')
    return seen

def all_paint_colors(root, css):
    """全部渲染元素解析后的 fill 与 stroke 颜色。

    只收文本色会放过形状底色、连线与箭头——而 C4 要求的配色一致性
    正是针对这些承载语义的元素。
    """
    seen = set()
    def walk(node, inh):
        for el in node:
            p = resolve(el, css, inh)
            tag = el.tag.replace(SVG, '')
            if tag not in ('defs', 'style', 'title', 'desc'):
                for key in ('fill', 'stroke'):
                    v = (p.get(key) or '').strip()
                    if v.startswith('#'):
                        seen.add(v.upper())
                # SVG 的 fill 初始值是 black：未声明 fill 的形状确实渲染成黑色。
                # 不算进来，就能靠「省略 fill」绕过配色契约。
                if tag in ('path', 'rect', 'circle', 'ellipse', 'polygon', 'polyline', 'text'):
                    if not (p.get('fill') or '').strip():
                        seen.add('#000000')
            if tag != 'defs':
                walk(el, p)
    walk(root, {})
    return seen

def group_path_map(root):
    """元素 -> 其祖先 <g> 链（用 id() 标识），用于判定「同一卡片是否同组」。"""
    m = {}
    def walk(node, chain):
        for el in node:
            c = chain + [id(el)] if el.tag == f'{SVG}g' else chain
            m[id(el)] = c
            walk(el, c)
    walk(root, [])
    return m

def bg_under(x, y, rects, page_bg='#FFFFFF'):
    """返回包含点 (x,y) 的最内层（最后绘制的最小）矩形填充色。

    找不到任何包含矩形时返回 page_bg 只在「确实没有底板」时正确。
    调用方必须先用 unresolvable_paint() 判断本图是否含无法解析的呈现
    （transform、圆/多边形/路径底、渐变、rgb()/CSS 变量），
    否则会把无法解析当成白底，产生假绿或假红。
    """
    best = None; best_area = None
    for (rx, ry, rw, rh, fill) in rects:
        if rx <= x <= rx + rw and ry <= y <= ry + rh:
            area = rw * rh
            # 后画的优先；同为包含时取更小的（更内层）
            if best is None or area <= best_area:
                best, best_area = fill, area
    return best or page_bg

def unresolvable_paint(root, css):
    """本图是否含本检查器解析不了的底色呈现。返回原因列表。"""
    reasons = set()
    def _walk(node):
        for el in node:
            tag = el.tag.replace(SVG, '')
            # 整个 defs 子树都不参与渲染（marker/gradient 定义在里面），
            # 扁平遍历会把箭头 marker 的填充误当成"非矩形底色"。
            if tag in ('defs', 'style', 'title', 'desc'):
                continue
            _inspect(el)
            _walk(el)
    def _inspect(el):
        tag = el.tag.replace(SVG, '')
        if el.get('transform'):
            reasons.add('transform')
        p = resolve(el, css, {})
        for key in ('fill', 'stroke'):
            v = (p.get(key) or '').strip().lower()
            if not v or v in ('none', 'inherit'):
                continue
            if v.startswith('url('):
                reasons.add('gradient/pattern')
            elif v.startswith('var('):
                reasons.add('css-variable')
            elif v.startswith('rgb') or v.startswith('hsl'):
                reasons.add('rgb()/hsl()')
            elif not v.startswith('#'):
                reasons.add('named-colour')
        if tag in ('circle', 'ellipse', 'polygon') and (p.get('fill') or '').startswith('#'):
            reasons.add('non-rect background')
        if tag == 'path':
            fillv = (p.get('fill') or '').strip().lower()
            if fillv and fillv != 'none':
                reasons.add('non-rect background')
    _walk(root)
    return sorted(reasons)

def container_width(x, y, rects, page_w):
    """文本锚点所在的最小容器宽度；找不到则用画布宽。"""
    best = None
    for (rx, ry, rw, rh, _f) in rects:
        if rx <= x <= rx + rw and ry <= y <= ry + rh:
            if best is None or rw < best[0]:
                best = (rw, rx)
    return best if best else (page_w, 0.0)

# ---------- 路径中点（用于连线标签检测） ----------

def path_points(d):
    """粗采样：取 d 里所有坐标对。"""
    nums = [float(n) for n in re.findall(r'-?\d+\.?\d*', d)]
    return [(nums[i], nums[i+1]) for i in range(0, len(nums) - 1, 2)]

def path_mid(d):
    """按弧长取真中点。

    早先取 pts[len//2]，对「M x1 y1 L x2 y2」这种单段路径等于取到终点，
    于是终点节点自己的文字被当成连线标签，未标注的连线普遍误判为通过。
    """
    pts = path_points(d)
    if len(pts) < 2:
        return pts[0] if pts else None
    seg = []
    total = 0.0
    for a, b in zip(pts, pts[1:]):
        L = math.hypot(b[0] - a[0], b[1] - a[1])
        seg.append((a, b, L))
        total += L
    if total <= 0:
        return pts[0]
    half = total / 2
    run = 0.0
    for a, b, L in seg:
        if run + L >= half:
            t = (half - run) / L if L else 0.0
            return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
        run += L
    return pts[-1]

# ---------- 版式契约 ----------

CONTRACT_NAME = 'figure-contract.json'

_CONTRACT_CACHE: dict = {}

def load_contract(start_dir):
    """向上找 figure-contract.json。返回 (contract|None, path|None)。

    按目录缓存：多目录输入时每个文件各自解析最近的契约，
    不能用第一个文件那棵树的契约去套第二棵。
    """
    key = os.path.abspath(start_dir)
    if key in _CONTRACT_CACHE:
        return _CONTRACT_CACHE[key]
    d = key
    result = (None, None)
    for _ in range(6):
        p = os.path.join(d, CONTRACT_NAME)
        if os.path.isfile(p):
            try:
                result = (validate_contract(json.load(open(p, encoding='utf8'))), p)
            except Exception as e:
                result = ({'__error__': str(e)}, p)
            break
        nd = os.path.dirname(d)
        if nd == d:
            break
        d = nd
    _CONTRACT_CACHE[key] = result
    return result

REQUIRED_CONTRACT_FIELDS = ('canvas_ratios', 'font_scale', 'color_tokens')

def validate_contract(c):
    """类型与完备性校验。

    字段全可选是个绕过口：放一个空的 figure-contract.json 就能让比例、字号、
    配色三项检查全部跳过，而闸仍报"有契约"。所以三项受检字段必须存在且非空。
    """
    if not isinstance(c, dict):
        return {'__error__': 'contract root must be an object'}
    errs = []
    missing = [k for k in REQUIRED_CONTRACT_FIELDS if not c.get(k)]
    if missing:
        errs.append('missing or empty required field(s): ' + ', '.join(missing))
    r = c.get('canvas_ratios')
    if r is not None:
        if not isinstance(r, list) or not r or not all(isinstance(x, (int, float)) for x in r):
            errs.append('canvas_ratios must be a non-empty list of numbers')
    f = c.get('font_scale')
    if f is not None:
        if not isinstance(f, list) or not f or not all(isinstance(x, (int, float)) for x in f):
            errs.append('font_scale must be a non-empty list of numbers')
    t = c.get('color_tokens')
    if t is not None:
        vals = t.values() if isinstance(t, dict) else (t if isinstance(t, list) else None)
        if vals is None or not all(isinstance(x, str) for x in vals):
            errs.append('color_tokens must be an object or list of colour strings')
    tol = c.get('ratio_tolerance')
    if tol is not None and not isinstance(tol, (int, float)):
        errs.append('ratio_tolerance must be a number')
    if errs:
        return {'__error__': '; '.join(errs)}
    return c

def check_contract(stats, contract):
    """把一张图的实测统计与契约比对。返回 findings 列表。

    契约不规定「几档」，只规定「哪几档」——一致性是外部要求（C4：
    colour coding consistent within and across diagrams），
    具体取值是团队自选。偏离契约才是缺陷。
    """
    out = []
    if not contract:
        return out
    ratios = contract.get('canvas_ratios')
    if ratios and stats.get('ratio') is not None:
        # 容差由契约声明，不由检查器内置。内置 0.02 是魔数，且会让
        # 契约里没有的比例照样通过——与「一致性即契约符合性」矛盾。
        tol = float(contract.get('ratio_tolerance', 0.0))
        if not any(abs(stats['ratio'] - float(r)) <= tol for r in ratios):
            suffix = '' if tol else '（契约未声明 ratio_tolerance，按精确匹配）'
            out.append(('ERROR', 'CONTRACT-RATIO',
                        f"画布比例 {stats['ratio']:.6g} 不在契约允许集 {ratios}{suffix}"))
    scale = contract.get('font_scale')
    if scale:
        allowed = {float(x) for x in scale}
        stray = sorted(set(stats.get('sizes', [])) - allowed)
        if stray:
            out.append(('ERROR', 'CONTRACT-FONT-SCALE',
                        f"字号 {[f'{s:g}' for s in stray]} 不在契约阶梯 {sorted(allowed)} 内"))
    tokens = contract.get('color_tokens')
    if tokens:
        allowed = {str(v).upper() for v in (tokens.values() if isinstance(tokens, dict) else tokens)}
        # 取全部渲染元素的 fill 与 stroke，不只文本色：形状底色、连线与箭头
        # 同样承载语义，只查文本色等于放过了大部分跨图配色不一致。
        stray = sorted(set(stats.get('tokens', [])) - allowed)
        if stray:
            out.append(('ERROR', 'CONTRACT-COLOR-TOKEN',
                        f"颜色 {stray} 不在契约 token 表内"))
    return out

# ---------- 主检查 ----------

def lint(path, contract_hint=None):
    contract_hint = contract_hint or {}
    findings = []
    # 逐文件捕获：一个非 UTF-8 / 消失 / 不可读的文件不得中断整批，
    # 否则 --json 输出被破坏、其余文件的检查结果一起消失。
    try:
        src = open(path, encoding='utf8').read()
    except (UnicodeDecodeError, OSError) as e:
        return ([{'level': 'ERROR', 'code': 'READ',
                  'msg': f'无法读取: {type(e).__name__}: {e}'}], {})
    def add(level, code, msg):
        findings.append({'level': level, 'code': code, 'msg': msg})

    try:
        root = ET.fromstring(src)
    except ET.ParseError as e:
        add('ERROR', 'PARSE', f'SVG 解析失败: {e}')
        return findings, {}

    css = parse_css(src)
    vb = root.get('viewBox')
    if vb:
        try:
            p = [float(v) for v in vb.split()]
        except ValueError:
            p = []
        if len(p) != 4 or not all(math.isfinite(v) for v in p) or p[2] <= 0 or p[3] <= 0:
            add('ERROR', 'GEOMETRY', f'viewBox 非法（需四个有限数且宽高为正）: "{vb}"')
            p = [0.0, 0.0, 0.0, 0.0]
        page_w, page_h = p[2], p[3]
    else:
        page_w = px(root.get('width'), 0) or 0
        page_h = px(root.get('height'), 0) or 0
        add('WARN', 'C4-VIEWBOX', '缺 viewBox，缩放行为不确定')
    # 不预先舍入：先舍入再做「精确」比较等于引入未声明容差（16:9 的 1.7777… 会通过 [1.778]）
    ratio = (page_w / page_h) if page_h else None

    rects = rects_of(root, css)
    # 含 transform 等无法解析的呈现时，所有依赖几何的判据都不可信——
    # 必须在第一个几何判据之前就算出来。
    paint_gaps = unresolvable_paint(root, css)
    # 任何不可解析的呈现都让几何/底色判据不可信，不只 transform：
    # 渐变、圆/多边形底、rgb()/CSS 变量同样会让「按白底算」得出假红或假绿。
    geometry_unsafe = bool(paint_gaps)

    # --- C4: 标题 ---
    title_el = root.find(f'{SVG}title')
    title = (title_el.text or '').strip() if title_el is not None else ''
    if not title:
        add('ERROR', 'C4-TITLE', '缺 <title>：C4 要求每张图有标题，说清图的类型与范围')

    # --- 收集文本 ---
    texts = []
    def walk_text(node, inh):
        for el in node:
            p = resolve(el, css, inh)
            if el.tag == f'{SVG}text':
                content = ''.join(el.itertext()).strip()
                content = ' '.join(content.split())
                tspans = el.findall(f'{SVG}tspan')
                try:
                    tx = float(el.get('x', 0)); ty = float(el.get('y', 0))
                except ValueError:
                    tx = ty = 0.0
                texts.append({
                    'el': el,
                    'text': content, 'x': tx, 'y': ty,
                    'size': px(p.get('font-size'), 16.0),
                    'fill': (p.get('fill') or '#000000').upper(),
                    'bold': str(p.get('font-weight', '')).strip() in ('bold', '700', '800', '900'),
                    'tspans': len(tspans),
                    'anchor': el.get('text-anchor') or p.get('text-anchor') or 'start',
                    'class': el.get('class') or '',
                })
            walk_text(el, p)
    walk_text(root, {})

    # --- C4: 图例 ---
    # 判据一：显式关键字。判据二：存在 ≥3 个小色块，每个近旁有短文本。
    has_kw = bool(re.search(r'图例|legend|Legend|图示说明', src))
    swatches = [r for r in rects if 8 <= r[2] <= 40 and 8 <= r[3] <= 40]
    paired = 0
    for (rx, ry, rw, rh, _f) in swatches:
        for t in texts:
            if abs(t['y'] - (ry + rh / 2)) < rh and 0 < (t['x'] - (rx + rw)) < 160 and len(t['text']) <= 24:
                paired += 1
                break
    if not has_kw and paired < 3:
        add('WARN', 'C4-LEGEND',
            f'未检出图例（关键字未命中；配对色块={paired}/需≥3）。'
            f'C4「每张图都要有图例」是 [外]，但本检测是 [工] 代理且**两个方向都会错**：'
            f'两条目的合法图例会被拒，注释/desc/class 里出现 legend 字样又会放行——故非阻断，需人工确认')

    # --- C4: 连线标签 ---
    # 先识别全部连接线，再分别校验方向与标签。
    # 早先只收「已经带 marker-end 的」——没有箭头的连线因此完全不进检查，
    # 而「每条线单向」恰恰要求它必须有且只有一个方向箭头；双向线同样漏掉。
    flows = []
    def _markers(el, p):
        return (
            bool(p.get('marker-start') or el.get('marker-start')),
            bool(p.get('marker-end') or el.get('marker-end')),
        )
    # 连线必须**显式声明**：class 命中契约声明的连线类名（默认 flow/edge/link/connector/arrow），
    # 或自身带方向 marker。把「所有有描边的 path / 所有 line」都当连线会误挡分隔线、
    # 网格线与线性图标——那是制造误报的判据，与本轮删掉那四条同类。
    conn_classes = set(contract_hint.get('connector_classes') or
                       ('flow', 'edge', 'link', 'connector', 'arrow'))
    def _declared_connector(el, p):
        if set((el.get('class') or '').split()) & conn_classes:
            return True
        return any(_markers(el, p))
    # 样式沿祖先继承：stroke 写在父 <g> 上的真实连线，用空继承解析会被漏掉。
    def _walk_conn(node, inh):
        for el in node:
            p = resolve(el, css, inh)
            tag = el.tag.replace(SVG, '')
            if tag == 'path' and el.get('d') and _declared_connector(el, p):
                flows.append({'d': el.get('d'), 'markers': _markers(el, p)})
            elif tag == 'line' and _declared_connector(el, p):
                flows.append({'d': f"M{el.get('x1',0)} {el.get('y1',0)} L{el.get('x2',0)} {el.get('y2',0)}",
                              'markers': _markers(el, p)})
            if tag != 'defs':
                _walk_conn(el, p)
    _walk_conn(root, {})
    for fl in flows:
        ms, me = fl['markers']
        if ms and me:
            add('ERROR', 'C4-EDGE-DIRECTION',
                ' 连线同时带 marker-start 与 marker-end（双向）：C4 要求每条线单向')
        elif not ms and not me:
            add('ERROR', 'C4-EDGE-DIRECTION',
                '连线无方向箭头：C4 要求每条线单向且方向可读')

    unlabeled = 0
    RADIUS = 90.0
    for fl in flows:
        d = fl['d']
        mid = path_mid(d)
        if not mid:
            continue
        found = False
        for t in texts:
            if not t['text'] or len(t['text']) > 30:
                continue
            # 节点框内的文字是节点名不是连线标签——早先不做这层排除，
            # 于是终点节点的名字被当成了标签。
            in_node = any(rx <= t['x'] <= rx + rw and ry <= t['y'] <= ry + rh
                          and rw < page_w * 0.95
                          for (rx, ry, rw, rh, _f) in rects)
            if in_node:
                continue
            if math.hypot(t['x'] - mid[0], t['y'] - mid[1]) <= RADIUS:
                found = True
                break
        if not found:
            unlabeled += 1
    if flows and unlabeled and not geometry_unsafe:
        add('WARN', 'C4-EDGE-LABEL',
            f'{unlabeled}/{len(flows)} 条连线在中点 {RADIUS:.0f}px 内找不到标签文本。'
            f'C4「每条线带具体标签」是 [外]，但本检测是 [工] 的邻近代理、两个方向都会错：'
            f'中点附近的分区标题会掩盖未标注连线，标在别处的合法标签又会被拒——故非阻断；报出的是下界')

    # 通用连线标签词
    for t in texts:
        if t['text'] in ('Uses', 'uses', '调用', '依赖', '使用', '关联'):
            add('WARN', 'C4-EDGE-VAGUE', f'连线标签过于笼统: "{t["text"]}"')

    # --- WCAG 1.4.3 对比度（底色按几何解析） ---
    # 解析不了底色时明确报 UNSUPPORTED，不按白底判——按白底判会产生
    # 假绿（深字压深底被判通过）或假红（浅字压浅底被判失败）。
    if paint_gaps:
        add('WARN', 'CONTRAST-UNSUPPORTED',
            f'本图含本检查器无法解析底色/坐标的呈现（{", ".join(paint_gaps)}）：'
            f'{"依赖几何的 ERROR 判据（对比度/溢出/分组/连线标签）已全部跳过，" if geometry_unsafe else ""}'
            f'结果不可信，需人工核对')
    for t in texts:
        if not t['text'] or not t['fill'].startswith('#'):
            continue
        bg = bg_under(t['x'], t['y'] - t['size'] * 0.35, rects)
        large = t['size'] >= 24 or (t['size'] >= 18.66 and t['bold'])
        need = 3.0 if large else 4.5
        try:
            c = contrast(t['fill'], bg)
        except Exception:
            continue
        if c < need and not geometry_unsafe:
            add('ERROR', 'WCAG-143',
                f'对比度 {c:.2f} < {need}（{t["size"]:g}px {t["fill"]} 压在 {bg} 上）: "{t["text"][:24]}"')

    # --- SVG 文本不换行 → 几何溢出 ---
    for t in texts:
        if not t['text'] or t['tspans'] > 0:
            continue
        w = est_width(t['text'], t['size'])
        cw, cx = container_width(t['x'], t['y'] - t['size'] * 0.35, rects, page_w)
        if t['anchor'] == 'middle':
            avail = min(t['x'] - cx, cx + cw - t['x']) * 2
        elif t['anchor'] == 'end':
            avail = t['x'] - cx
        else:
            avail = cx + cw - t['x']
        avail = max(avail, 0)
        if avail > 0 and w > avail * 1.02 and not geometry_unsafe:
            add('ERROR', 'SVG-OVERFLOW',
                f'文本估算宽 {w:.0f}px > 可用 {avail:.0f}px 且未用 tspan 拆行（SVG <text> 默认不换行）: "{t["text"][:28]}"')

    # --- 分组（目标端 z 序重排防护） ---
    # 早先只查「全图是否存在任意一个 <g>」——一个无关的组就能让整图通过，
    # 而契约要求的是每张卡片（形状 + 其文字）自身成组。
    gmap = group_path_map(root)
    el_by_id = {}
    def _index(node):
        for el in node:
            el_by_id[id(el)] = el
            _index(el)
    _index(root)
    ungrouped_cards = 0
    card_total = 0
    def _is_card_rect(e):
        try:
            w = float(e.get('width', 0)); h = float(e.get('height', 0))
            x = float(e.get('x', 0)); y = float(e.get('y', 0))
        except ValueError:
            return False
        if w <= 0 or h <= 0 or w >= page_w * 0.95:
            return False
        return any(x <= t['x'] <= x + w and y <= t['y'] <= y + h for t in texts)
    card_rects = [e for e in root.iter(f'{SVG}rect') if _is_card_rect(e)]
    for el in root.iter(f'{SVG}rect'):
        try:
            rx = float(el.get('x', 0)); ry = float(el.get('y', 0))
            rw = float(el.get('width', 0)); rh = float(el.get('height', 0))
        except ValueError:
            continue
        if rw <= 0 or rh <= 0 or rw >= page_w * 0.95:
            continue          # 跳过整页底板
        inside = [t for t in texts
                  if rx <= t['x'] <= rx + rw and ry <= t['y'] <= ry + rh]
        if not inside:
            continue
        card_total += 1
        rect_chain = gmap.get(id(el), [])
        if not rect_chain:
            ungrouped_cards += 1
            continue
        # 「祖先集合有交集」不够：把整张图包进一个顶层 <g>，每张卡片各自未分组
        # 也会全部通过。判据是这张卡片有一个**专属**的最近公共组——
        # 该组不能同时容纳其它卡片的形状。
        bad_card = False
        for t in inside:
            tel = t.get('el')
            text_chain = gmap.get(id(tel), [])
            common = [g for g in rect_chain if g in text_chain]
            if not common:
                bad_card = True
                break
            nearest = common[-1]          # 链尾 = 最近公共组
            members = [r for r in card_rects
                       if nearest in gmap.get(id(r), [])]
            if len(members) > 1:
                bad_card = True           # 该组不是这张卡片专属的
                break
        if bad_card:
            ungrouped_cards += 1
    if card_total and ungrouped_cards and not geometry_unsafe:
        add('ERROR', 'GROUPING',
            f'{ungrouped_cards}/{card_total} 张卡片的形状与其文字不在同一个 <g> 内：'
            f'推送到会重排 z 序的目标端时，矩形可能盖住文字')
    elif card_total == 0 and len(list(root.iter(f'{SVG}g'))) == 0:
        add('ERROR', 'GROUPING', '全图零 <g> 分组：目标端重排 z 序时矩形可能盖住文字')

    stats = {
        'ratio': ratio,
        'sizes': sorted({t['size'] for t in texts}),
        'tokens': sorted(all_paint_colors(root, css) | referenced_defs_colors(root, css)),
        'texts': len(texts),
        'flows': len(flows),
    }
    return findings, stats


def main(argv):
    as_json = '--json' in argv
    args = [a for a in argv[1:] if not a.startswith('--')]
    files = []
    for a in args:
        if os.path.isdir(a):
            files += sorted(glob.glob(os.path.join(a, '*.svg')))
        else:
            files.append(a)
    if not files:
        print('用法: figure-lint.py <dir-or-file>... [--json]', file=sys.stderr)
        return 2

    report = {}
    all_ratios = collections.Counter()
    all_sizes = set()
    for f in files:
        findings, stats = lint(f, (load_contract(os.path.dirname(os.path.abspath(f)))[0] or {}))
        report[f] = {'findings': findings, 'stats': stats}
        if stats.get('ratio'):
            all_ratios[stats['ratio']] += 1
        all_sizes |= set(stats.get('sizes', []))

    # 一致性 = 契约符合性（C4: consistent within and across diagrams）
    # 逐文件解析各自最近的契约：跨两棵树检查时，不能用第一棵的契约套第二棵。
    cross = []
    per_file_contract = {f: load_contract(os.path.dirname(os.path.abspath(f))) for f in files}
    distinct = {cp for _c, cp in per_file_contract.values()}
    if len(distinct) > 1:
        for f, (c, cp) in per_file_contract.items():
            r = report[f]
            if c is None:
                r['findings'].append({'level': 'ERROR', 'code': 'CONTRACT-MISSING',
                                      'msg': f'缺 {CONTRACT_NAME}，一致性不可判定', 'line': None})
            elif '__error__' in c:
                r['findings'].append({'level': 'ERROR', 'code': 'CONTRACT-INVALID',
                                      'msg': f'{CONTRACT_NAME} 无法使用: {c["__error__"]}', 'line': None})
            else:
                for lvl, code, msg in check_contract(r['stats'], c):
                    r['findings'].append({'level': lvl, 'code': code, 'msg': msg, 'line': None})
        cross.append(f'逐文件契约: {sorted(str(x) for x in distinct)}')
        contract, cpath = None, None
        _skip_uniform = True
    else:
        _skip_uniform = False
        contract, cpath = per_file_contract[files[0]]
    if _skip_uniform:
        pass
    elif contract is None:
        cross.append(f'未找到 {CONTRACT_NAME}：一致性无法判定。'
                     f'契约缺失本身是缺陷——没有冻结的版式，每轮内容变动都要重调几何')
        for r in report.values():
            r['findings'].append({'level': 'ERROR', 'code': 'CONTRACT-MISSING',
                                  'msg': f'缺 {CONTRACT_NAME}，一致性不可判定', 'line': None})
    elif '__error__' in contract:
        cross.append(f'{cpath} 解析失败: {contract["__error__"]}')
        for r in report.values():
            r['findings'].append({'level': 'ERROR', 'code': 'CONTRACT-INVALID',
                                  'msg': f'{CONTRACT_NAME} 无法使用: {contract["__error__"]}',
                                  'line': None})
    else:
        cross.append(f'契约: {cpath}')
        for f, r in report.items():
            for lvl, code, msg in check_contract(r['stats'], contract):
                r['findings'].append({'level': lvl, 'code': code, 'msg': msg, 'line': None})

    n_err_all = sum(1 for r in report.values() for x in r['findings'] if x['level'] == 'ERROR')
    n_warn_all = sum(1 for r in report.values() for x in r['findings'] if x['level'] == 'WARN')
    if as_json:
        print(json.dumps({'files': report, 'cross': cross}, ensure_ascii=False, indent=1))
        return 1 if n_err_all else (2 if n_warn_all else 0)
    else:
        n_err = n_warn = 0
        for f, r in report.items():
            errs = [x for x in r['findings'] if x['level'] == 'ERROR']
            warns = [x for x in r['findings'] if x['level'] == 'WARN']
            n_err += len(errs); n_warn += len(warns)
            if not errs and not warns:
                print(f'✓ {os.path.basename(f)}')
                continue
            print(f'\n{os.path.basename(f)}  [{len(errs)} ERROR / {len(warns)} WARN]')
            seen = collections.Counter()
            for x in r['findings']:
                seen[x['code']] += 1
                if seen[x['code']] <= 3:
                    print(f"  {x['level']:5} {x['code']:16} {x['msg']}")
            for code, n in seen.items():
                if n > 3:
                    print(f"  ...   {code:16} 另有 {n-3} 处")
        for c in cross:
            print(f'\nWARN  CONSISTENCY-SIZES  {c}')
        print(f'\n合计: {n_err} ERROR, {n_warn} WARN, {len(files)} 个文件')
        return 1 if n_err else (2 if n_warn else 0)
    return 0

if __name__ == '__main__':
    sys.exit(main(sys.argv))
