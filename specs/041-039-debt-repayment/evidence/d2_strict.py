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
    rows.append((n,locs,cols[4] if len(cols)>4 else ""))
strict=0; kinds={}
for n,locs,ev in rows:
    evp=[p.lstrip("./") for p in re.findall(r"`([^`]*?\.(?:md|rb|sh|py))`",ev)]
    fl=[l[5:].split("#",1)[0].lstrip("./") for l in locs if l.startswith("file:")]
    if not fl or len(fl)!=len(locs): continue
    # strict: 每个 file: 目标路径都必须是某个 evidence 路径的后缀匹配（完整路径段级）
    def match(t):
        for e in evp:
            if t==e or t.endswith("/"+e): return True
        return False
    if all(match(t) for t in fl):
        strict+=1
        kinds[fl[0].split("/")[0]]=kinds.get(fl[0].split("/")[0],0)+1
print("总行数(带 firing-path):",len(rows))
print("严格路径段级自指(全部定位符):",strict)
print("按顶层目录:",kinds)
