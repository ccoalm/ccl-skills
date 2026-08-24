#!/usr/bin/env python3
"""按**义务**判分的删除探针（取代 deletion_arms.rb 的正则版）。

deletion_arms.rb 的缺陷已实证：它的 marker 必须「组内唯一承载」，这等于逼着
选同义反复的词——删掉唯一提到某词的行，模型自然不再说那个词，测的是删词
不是变差。本版改为：把三臂的原始回答交独立判分方，只问**义务是否仍被要求**，
不看用词；候选 marker 不再要求唯一承载（别处也承载正是冗余的证据）。

三臂：full / minus_candidate / minus_control。
对照臂必须掉——它证明本探针测得出删除；否则候选的零结果无意义。
"""
import json, re, subprocess, sys, tempfile

REPO = "/Users/asen/work/code/src/github.com/ccoalm/ccl-skills/.work/worktrees/042-criteria-terminal-set"
SK = f"{REPO}/skills/skill-extraction-workflow/SKILL.md"
GROUP = range(101, 123)
CAND, CTRL = 106, 107
RUNS = int(sys.argv[1]) if len(sys.argv) > 1 else 10
REPS = int(sys.argv[2]) if len(sys.argv) > 2 else 2

L = open(SK, encoding="utf-8").read().split("\n")
body = lambda drop: "\n".join(L[i-1] for i in GROUP if i != drop)
ARMS = {"full": body(None), "minus_candidate": body(CAND), "minus_control": body(CTRL)}
assert len(set(ARMS.values())) == 3

TASK = ("我刚在 Go 服务技能里改了一条上游契约规则（它同时是别的技能要执行的决策面），"
        "过程中还发现自己漏掉了一个 owner 维度。按上面的规则，closeout 我必须产出什么？逐项列全。")

OBL_CAND = ("回答是否要求把**上下游两个方向都**映射到位——即：改了上游决策面就必须点名"
            "下游要执行它的 owner（实现/测试/评审/发布），反过来也一样？只看是否要求了这件事，"
            "不看用词、不要求出现任何特定术语。")
OBL_CTRL = ("回答是否要求做**兄弟栈**的决定——即：这条规则是否也属于同类的其它语言/服务技能，"
            "并对每个兄弟给出 update / unchanged / 上移到共享 owner 之一的处置？"
            "只看是否要求了这件事，不看用词。")

def ask(prompt, model="claude-haiku-4-5", timeout=200):
    with tempfile.TemporaryDirectory() as d:
        r = subprocess.run(["claude","--print","--tools","","--model",model],
                           input=prompt, capture_output=True, text=True, cwd=d, timeout=timeout)
    return r.stdout if r.returncode == 0 else None

def judge(obl, items):
    numbered = "\n\n".join(f"[{i}]\n{t[:800]}" for i, t in items)
    p = (f"你是判分方。下面是同一道题的多个回答。判定标准：\n{obl}\n\n"
         f"=== 回答 ===\n{numbered}\n=== 结束 ===\n\n"
         f"只输出 JSON 数组，元素 {{\"i\":<编号>,\"ok\":true|false}}，覆盖全部 {len(items)} 条，无其它文字。")
    out = ask(p, timeout=300)
    m = re.search(r"\[.*\]", out or "", re.S)
    if not m: return None
    try: return {int(x["i"]): bool(x["ok"]) for x in json.loads(m.group(0))}
    except Exception: return None

allres = []
for rep in range(REPS):
    print(f"-- 复现轮 {rep+1}/{REPS} --", flush=True)
    outs = {}
    for name, text in ARMS.items():
        outs[name] = []
        for _ in range(RUNS):
            o = ask(f"这是一个隔离的角色扮演评测。你按下面的规则工作。\n\n=== RULES ===\n{text}\n=== END ===\n\n用户请求：{TASK}\n\n你没有文件读取工具。直接列出必须产出的东西。")
            outs[name].append(o or "")
    tally = {}
    for name in ARMS:
        items = [(i, t) for i, t in enumerate(outs[name])]
        jc = judge(OBL_CAND, items) or {}
        jt = judge(OBL_CTRL, items) or {}
        tally[name] = {"cand": sum(1 for v in jc.values() if v), "ctrl": sum(1 for v in jt.values() if v),
                       "n_c": len(jc), "n_t": len(jt)}
        print(f"  {name:16s} 双向义务={tally[name]['cand']}/{tally[name]['n_c']}  兄弟栈义务={tally[name]['ctrl']}/{tally[name]['n_t']}", flush=True)
    allres.append({"tally": tally, "outs": {k: [x[:800] for x in v] for k, v in outs.items()}})

need = max(1, round(RUNS * 0.3))
print("\n== 判定 ==")
verds = []
for r in allres:
    t = r["tally"]
    ctrl_drop = t["full"]["ctrl"] - t["minus_control"]["ctrl"]
    cand_drop = t["full"]["cand"] - t["minus_candidate"]["cand"]
    if ctrl_drop < need: v = f"INVALID_APPARATUS (对照只掉 {ctrl_drop})"
    elif cand_drop >= need: v = f"LOAD_BEARING (候选掉 {cand_drop})"
    else: v = f"REMOVABLE_ON_PROBED_POINTS (对照掉 {ctrl_drop}，候选掉 {cand_drop})"
    verds.append(v); print("  " + v)
kinds = {v.split(" ")[0] for v in verds}
final = verds[0].split(" ")[0] if len(kinds) == 1 else f"NOT_REPLICATED ({','.join(sorted(kinds))})"
print(f"final: {final}")
json.dump({"runs": RUNS, "reps": REPS, "candidate": CAND, "control": CTRL,
           "results": allres, "verdicts": verds, "final": final},
          open(f"{REPO}/specs/042-skill-corpus-optimization/evidence/deletion-obligation-L106.json","w"),
          ensure_ascii=False, indent=1)
