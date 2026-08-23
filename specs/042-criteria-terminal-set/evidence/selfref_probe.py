import re,sys
rows=[];fence=False
for n,line in enumerate(open(sys.argv[1]+"/"+"skills/skill-extraction-workflow/references/source-register.md",encoding='utf-8'),1):
    if line.strip().startswith("```"): fence=not fence; continue
    if fence or not line.startswith("|"): continue
    m=re.search(r"(?<!`)firing-path:\s*([^|;]*)",line)
    if not m: continue
    locs=[l.strip() for l in re.split(r",(?=\s*(?:file|command):)",m.group(1)) if l.strip().startswith(("file:","command:"))]
    cols=[c.strip() for c in line.strip().strip("|").split("|")]
    rows.append((n,locs,cols[4] if len(cols)>4 else ""))
EXEC=(".sh",".py",".rb")
def ext(t):
    t=t.split("#",1)[0]; b=t.rsplit("/",1)[-1]
    return "."+b.rsplit(".",1)[-1] if "." in b else "(none)"
def tgt(l): return l.split(":",1)[1].split("#",1)[0].lstrip("./")
cand=0
for n,locs,ev in rows:
    evp=[p.lstrip("./") for p in re.findall(r"`([^`]*?\.(?:md|rb|sh|py))`",ev)]
    ks=set()
    for l in locs:
        t=tgt(l)
        if l.startswith("command:") or ext(t) in EXEC: ks.add("exec")
        elif ext(t)==".md": ks.add("selftext" if any(t==e or t.endswith("/"+e) for e in evp) else "othertext")
        else: ks.add("other")
    if ks=={"selftext"}: cand+=1
print("corrected 自指(全部定位符指向本行落地文本):",cand,"/",len(rows))
# 谓词（042 修正版）：一行的**全部** firing-path 定位符都指向该行自己的落地文本时计一次。
#   - command: 目标、或扩展名为 .sh/.py/.rb 的 file: 目标 = 可执行体，按 keep(a) 是合法 firing point，不计。
#   - .md 目标且该路径出现在本行 Evidence 列 = 指向自身落地文本，计。
#   - .md 目标但不在 Evidence 列 = 指向他处文本（可能是别的技能的 closeout 走查行），不计。
# 与 041 `d2_strict.py` 的差别见 control-legs-out.txt：那一版按「目标 ∈ Evidence 文件集合」判，
# 会把 Evidence 里顺带列出的可执行体也算成自指，因此对 13 行的改指修复不响应。
