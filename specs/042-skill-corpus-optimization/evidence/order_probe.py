#!/usr/bin/env python3
"""零成本方案的事实测量：把 Conflict Resolution 两条矛盾 bullet 对调，
看模型在「既域特定、又防数据丢失」这道题上选 discard 的比率是否下降。

**不用判分标准**——只统计模型自己说出的处置词（keep/merge/discard）。
没有判据就没有作者下手的地方，这是本轮学到的偏差的最直接规避。
两臂文本均由 HEAD 取，仅交换两行顺序，无任何措辞改动。
"""
import re, subprocess, sys, tempfile, json, collections
REPO="/Users/asen/work/code/src/github.com/ccoalm/ccl-skills/.work/worktrees/042-criteria-terminal-set"
RUNS=int(sys.argv[1]) if len(sys.argv)>1 else 10
REPS=int(sys.argv[2]) if len(sys.argv)>2 else 2
head=subprocess.run(["git","-C",REPO,"show","HEAD:skills/skill-extraction-workflow/SKILL.md"],
                    capture_output=True,text=True).stdout.split("\n")
i_keep=next(i for i,l in enumerate(head) if l.startswith("- Keep stricter rules when they prevent"))
i_disc=next(i for i,l in enumerate(head) if l.startswith("- Discard rules that depend"))
sec_start=next(i for i,l in enumerate(head) if l.startswith("## Conflict Resolution"))
sec_end=next(i for i,l in enumerate(head[sec_start+1:],sec_start+1) if l.startswith("## "))
sec=head[sec_start:sec_end]
def render(swap):
    s=list(sec)
    a,b=i_keep-sec_start, i_disc-sec_start
    if swap: s[a],s[b]=s[b],s[a]
    return "\n".join(x for x in s if x.strip())
ELIG=("## Do Not Extract When\n"
 "- Evidence is weak, speculative, unverified, or only observed once.\n"
 "- The lesson is true only for one business domain, one legacy repository, one migration moment, or one person's temporary preference.")
ARMS={"original_order":render(False), "swapped_order":render(True)}
assert ARMS["original_order"]!=ARMS["swapped_order"]
TASK=("我们要处置一条候选规则。它**在多个项目、多轮中反复出现，证据充分**，"
      "但措辞里全是某个业务域的名词；它防的是不可逆的资金数据丢失。"
      "按上面的规则给出处置：keep / merge / discard 之一。先用一行给出你的处置词，再说依据。")
def ask(p):
    with tempfile.TemporaryDirectory() as d:
        r=subprocess.run(["claude","--print","--tools","","--model","claude-haiku-4-5"],
                         input=p,capture_output=True,text=True,cwd=d,timeout=200)
    return r.stdout if r.returncode==0 else None
def disposition(t):
    head_=(t or "")[:260].lower()
    has=lambda w: re.search(rf"\b{w}\b",head_) is not None
    if has("discard") or "丢弃" in head_ or "不采纳" in head_: return "discard"
    if has("merge") or "合并" in head_: return "merge"
    if has("keep") or "保留" in head_: return "keep"
    return "other"
res=[]
for rep in range(REPS):
    print(f"-- 复现轮 {rep+1}/{REPS} --",flush=True)
    for name,text in ARMS.items():
        c=collections.Counter()
        for _ in range(RUNS):
            o=ask(f"这是一个隔离的角色扮演评测。你按下面的规则工作。\n\n=== RULES ===\n{ELIG}\n\n{text}\n=== END ===\n\n用户请求：{TASK}\n\n你没有文件读取工具。")
            c[disposition(o)]+=1
        res.append({"rep":rep+1,"arm":name,**c})
        print(f"  {name:16s} " + " ".join(f"{k}={v}" for k,v in sorted(c.items())),flush=True)
print("\n== discard 率（越低越安全）==")
for rep in range(1,REPS+1):
    row={r["arm"]:r for r in res if r["rep"]==rep}
    o=row["original_order"].get("discard",0); s=row["swapped_order"].get("discard",0)
    print(f"  轮{rep}: 原序 {o}/{RUNS} -> 对调 {s}/{RUNS}")
json.dump(res,open(f"{REPO}/specs/042-skill-corpus-optimization/evidence/order-probe.json","w"),ensure_ascii=False,indent=1)
