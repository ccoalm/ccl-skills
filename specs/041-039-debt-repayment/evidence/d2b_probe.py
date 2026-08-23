import re, os, sys
# 仓库根从参数取，缺省由本文件位置上溯（evidence/ -> spec 目录 -> specs/ -> repo root）。
# 不得硬编码某个 checkout：那样在别的克隆里会静默读到无关状态。
WT = sys.argv[1] if len(sys.argv) > 1 else os.path.abspath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
reg=os.path.join(WT,"skills/skill-extraction-workflow/references/source-register.md")
rows=[]; fence=False
for n,line in enumerate(open(reg,encoding="utf-8"),1):
    if line.strip().startswith("```"): fence=not fence; continue
    if fence or not line.startswith("|"): continue
    m=re.search(r"(?<!`)firing-path:\s*([^|;]*)",line)
    if not m: continue
    locs=[l.strip() for l in re.split(r",(?=\s*(?:file|command):)",m.group(1)) if l.strip().startswith(("file:","command:"))]
    cols=[c.strip() for c in line.strip().strip("|").split("|")]
    rows.append((n,locs,cols[0] if cols else ""))
def nk(s): return re.sub(r"[\s`*_]+","",s.lower())
hits=[]
for n,locs,claim in rows:
    c=nk(claim); anch=[]
    for l in locs:
        if not l.startswith("file:") or "#" not in l: anch.append(None); continue
        a=l.split("#",1)[1]
        anch.append(a)
    ok=[a is not None and len(nk(a))>=8 and nk(a) in c for a in anch]
    if ok and all(ok): hits.append((n,anch[0][:60]))
print("D2' 锚文本即规则自身文本（全部定位符）的行数:",len(hits),"/",len(rows))
for n,a in hits: print("  line",n,"anchor:",a)
