#!/usr/bin/env python3
"""按**冻结判据**测删除候选。判据见 frozen-rubric.json（独立通道产出，先于本脚本任何运行提交）。

设计：双向解离——同时移除多个候选，各自充当对方的对照。
仪器有效性 = 至少一个臂在某条义务上相对 full 下降 >= 30% 运行数。
不满足则整次读数作废（探针测不出删除，任何"可删"结论无意义）。
判分方看不到臂来源。阈值与判定序已随判据冻结，事后不得只改有利那格。
"""
import json, re, subprocess, sys, tempfile, itertools
REPO="/Users/asen/work/code/src/github.com/ccoalm/ccl-skills/.work/worktrees/042-criteria-terminal-set"
EV=f"{REPO}/specs/042-skill-corpus-optimization/evidence"
L=open(f"{REPO}/skills/skill-extraction-workflow/SKILL.md",encoding="utf-8").read().split("\n")
GROUP=range(101,123)
CANDS=[int(x) for x in (sys.argv[3].split(",") if len(sys.argv)>3 else ["106","107"])]
RUNS=int(sys.argv[1]) if len(sys.argv)>1 else 10
REPS=int(sys.argv[2]) if len(sys.argv)>2 else 2
OBL=json.load(open(f"{EV}/frozen-rubric.json",encoding="utf-8"))
body=lambda drop:"\n".join(L[i-1] for i in GROUP if i!=drop)
ARMS={"full":body(None), **{f"minus_L{c}":body(c) for c in CANDS}}
assert len(set(ARMS.values()))==len(ARMS), "臂文本重复，行号可能已漂移"
TASK=("我刚在 Go 服务技能里改了一条上游契约规则（它同时是别的技能要执行的决策面），"
      "过程中还发现自己漏掉了一个 owner 维度。按上面的规则，closeout 我必须产出什么？逐项列全。")

def call(prompt,model="claude-haiku-4-5",timeout=240):
    with tempfile.TemporaryDirectory() as d:
        r=subprocess.run(["claude","--print","--tools","","--model",model],
                         input=prompt,capture_output=True,text=True,cwd=d,timeout=timeout)
    return r.stdout if r.returncode==0 else None

def grade(answers):  # answers: list[(key, text)] -> {key: set(obl ids)}
    lines="\n".join(f'- {o["id"]}: {o["obligation"]}' for o in OBL)
    body_="\n\n".join(f"[{i}]\n{t[:900]}" for i,(k,t) in enumerate(answers))
    p=(f"你是判分方。下面是同一道题的多个回答。对每个回答，判定它**要求到了**下列哪些义务。"
       f"只看是否要求了那件事，容许任何措辞，不要求出现特定词。\n\n义务：\n{lines}\n\n"
       f"=== 回答 ===\n{body_}\n=== 结束 ===\n\n"
       f'只输出 JSON 数组，元素 {{"i":<编号>,"met":["O1","O3",...]}}，覆盖全部 {len(answers)} 条，无其它文字。')
    out=call(p,timeout=400); m=re.search(r"\[.*\]",out or "",re.S)
    if not m: return None
    try:
        r=json.loads(m.group(0))
        return {answers[int(x["i"])][0]: set(x.get("met") or []) for x in r if int(x["i"])<len(answers)}
    except Exception: return None

allreps=[]
for rep in range(REPS):
    print(f"-- 复现轮 {rep+1}/{REPS} --",flush=True)
    answers=[]
    for name,text in ARMS.items():
        for k in range(RUNS):
            o=call(f"这是一个隔离的角色扮演评测。你按下面的规则工作。\n\n=== RULES ===\n{text}\n=== END ===\n\n用户请求：{TASK}\n\n你没有文件读取工具。直接列出必须产出的东西。")
            answers.append(((name,k),o or ""))
    met={}
    for i in range(0,len(answers),5):
        g=grade(answers[i:i+5])
        if g: met.update(g)
        else: print(f"  judge batch {i} FAILED",file=sys.stderr)
    tally={n:{o["id"]:0 for o in OBL} for n in ARMS}
    for (name,_),ids in met.items():
        for oid in ids:
            if oid in tally[name]: tally[name][oid]+=1
    for n in ARMS:
        print("  "+n.ljust(14)+" "+" ".join(f'{o["id"]}={tally[n][o["id"]]}' for o in OBL),flush=True)
    allreps.append({"tally":tally,"answers":{f"{k[0]}|{k[1]}":v[:800] for k,v in answers}})

need=max(1,round(RUNS*0.3))
print("\n== 判定（阈值随判据冻结）==")
verdicts=[]
for r in allreps:
    t=r["tally"]; drops={}
    for c in CANDS:
        arm=f"minus_L{c}"
        drops[c]={o["id"]: t["full"][o["id"]]-t[arm][o["id"]] for o in OBL}
    any_drop=any(d>=need for c in CANDS for d in drops[c].values())
    if not any_drop:
        v={"_apparatus":f"INVALID_APPARATUS (无任何臂在任何义务上掉 >= {need}，探针测不出删除)"}
    else:
        v={"_apparatus":"ok"}
        for c in CANDS:
            hit={k:d for k,d in drops[c].items() if d>=need}
            v[c]=f"LOAD_BEARING (掉: {hit})" if hit else f"REMOVABLE_ON_PROBED_POINTS (最大跌幅 {max(drops[c].values())} < {need})"
    verdicts.append(v); print("  "+json.dumps(v,ensure_ascii=False))
final={}
if any(v["_apparatus"]!="ok" for v in verdicts): final["all"]="APPARATUS_FAILED"
elif RUNS<10 or REPS<2: final["all"]="UNDERPOWERED_OR_UNREPLICATED"
else:
    for c in CANDS:
        kinds={verdicts[i][c].split(" ")[0] for i in range(len(verdicts))}
        final[c]=list(kinds)[0] if len(kinds)==1 else f"NOT_REPLICATED({','.join(sorted(kinds))})"
print("final: "+json.dumps(final,ensure_ascii=False))
json.dump({"runs":RUNS,"reps":REPS,"cands":CANDS,"reps_data":allreps,"verdicts":verdicts,"final":final},
          open(f"{EV}/frozen-rubric-run.json","w"),ensure_ascii=False,indent=1)
