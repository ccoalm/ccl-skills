#!/usr/bin/env python3
"""042 的 RED 基线：用**整份 SKILL.md** 做两臂，测「撤回那句假陈述」是否改变行为。

先前的切片探针（只喂那一条 bullet）报无差异；按本轮落地的纪律，**不合格仪器的
零结果不是效果不存在的证据**。这里改用完整语料，判据由只见场景、不见技能文本的
独立通道产出并先行冻结，判分方看不到臂来源。
"""
import json,re,subprocess,sys,tempfile,collections
S="/private/tmp/claude-501/-Users-asen-work-code-src-github-com-ccoalm-ccl-skills/ef5e68f3-9528-4473-963e-528bd9b8024f/scratchpad"
RUNS=int(sys.argv[1]) if len(sys.argv)>1 else 10
REPS=int(sys.argv[2]) if len(sys.argv)>2 else 2
ARMS={"old":open(f"{S}/arm_old_full.md",encoding='utf-8').read(),
      "new":open(f"{S}/arm_new_full.md",encoding='utf-8').read()}
RUBRIC=open(f"{S}/rubric3-frozen.txt",encoding='utf-8').read()
TASK=("这一节已经有 8 条 bullet。一次真实纠正暴露出其中一条的适用条件写得不清楚，"
      "补一句限定能避免下次再误用。同事反对：这一节已经够长，再加只会稀释其它规则、"
      "把它们挤下去，整体合规反而更差。到底该不该补这句限定？给出你的结论与依据。")
def ask(prompt,model="claude-haiku-4-5",timeout=400):
    with tempfile.TemporaryDirectory() as d:
        r=subprocess.run(["claude","--print","--tools","","--model",model],
                         input=prompt,capture_output=True,text=True,cwd=d,timeout=timeout)
    return r.stdout if r.returncode==0 else None
def judge(items):
    body="\n\n".join(f"[{i}]\n{t[:1200]}" for i,(k,t) in enumerate(items))
    p=(f"你是判分方。判定标准如下（只判处置立场，不看用词）：\n\n{RUBRIC}\n\n"
       f"=== 回答 ===\n{body}\n=== 结束 ===\n\n"
       f'只输出 JSON 数组，元素 {{"i":<编号>,"ok":true|false}}，覆盖全部 {len(items)} 条，无其它文字。')
    out=ask(p,timeout=400); m=re.search(r"\[.*\]",out or "",re.S)
    if not m: return None
    try: return {items[int(x["i"])][0]: bool(x["ok"]) for x in json.loads(m.group(0)) if int(x["i"])<len(items)}
    except Exception: return None
allrows=[]
for rep in range(REPS):
    print(f"-- 复现轮 {rep+1}/{REPS} --",flush=True)
    answers=[]
    for arm,body in ARMS.items():
        for k in range(RUNS):
            o=ask(f"这是一个隔离的角色扮演评测。你按下面这份技能的规则工作。\n\n=== SKILL BODY ===\n{body}\n=== END ===\n\n用户请求：{TASK}\n\n你没有文件读取工具。")
            answers.append(((arm,rep,k),o or ""))
    verd={}
    for i in range(0,len(answers),5):
        g=judge(answers[i:i+5])
        if g: verd.update(g)
        else: print(f"  judge batch {i} FAILED",file=sys.stderr)
    c=collections.Counter()
    for (arm,_,_),ok in verd.items(): c[(arm,ok)]+=1
    o_ok=c[("old",True)]; n_ok=c[("new",True)]
    o_tot=c[("old",True)]+c[("old",False)]; n_tot=c[("new",True)]+c[("new",False)]
    print(f"  old 恰当处置 {o_ok}/{o_tot}   new 恰当处置 {n_ok}/{n_tot}",flush=True)
    allrows.append({"rep":rep+1,"old_ok":o_ok,"old_n":o_tot,"new_ok":n_ok,"new_n":n_tot,
                    "answers":{f"{k[0]}|{k[1]}|{k[2]}":v[:900] for k,v in answers}})
print("\n== 承重读数（全文两臂）==")
for r in allrows: print(f"  轮{r['rep']}: old {r['old_ok']}/{r['old_n']} -> new {r['new_ok']}/{r['new_n']}")
json.dump(allrows,open(f"{S}/full-arms-result.json","w"),ensure_ascii=False,indent=1)
