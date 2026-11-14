#!/usr/bin/env python3
"""Paired before/after plugin-tree driver for eval/behavior-fixtures.jsonl.

Reuses skill-behavior-eval.py (stream parsing, fail-closed terminal check, sig, report) and
replaces only the arm command: each arm loads the whole ccl-skills plugin from an exported git
tree via --plugin-dir, with the installed ccl-skills/context-mode plugins disabled, and every
run starts in the same empty directory. File naming follows the tool (`current` = before tree,
`candidate` = after tree), so the tool's own --report-only can build its delta report.

Per sample it also writes <id>.<arm>.s<n>.meta.json: every tool_use (name + input), cost,
duration, turns, token usage and the init event's plugin list (contamination audit).
"""
import argparse, importlib.util, json, os, subprocess, threading, time
from concurrent.futures import ThreadPoolExecutor

_tl = threading.local()


# A child `claude` that inherits the parent session's ids/socket also inherits that session's
# scratch directory as an allowed path, which can hold the other arm's tree and answers.
_PARENT_SESSION_VARS = ("CLAUDECODE", "CLAUDE_CODE_SESSION_ID", "CLAUDE_CODE_CHILD_SESSION",
                        "CLAUDE_CODE_SESSION_ATTENDED", "CLAUDE_CODE_MESSAGING_SOCKET",
                        "CLAUDE_CODE_MESSAGING_TOKEN", "CLAUDE_PID", "AI_AGENT", "CLAUDE_EFFORT",
                        "CLAUDE_CODE_ENTRYPOINT")
CLEAN_ENV = {k: v for k, v in os.environ.items() if k not in _PARENT_SESSION_VARS}


class RecordingPopen(subprocess.Popen):
    """Runs with the parent-session vars removed and keeps this thread's raw stream."""
    def __init__(self, *a, **k):
        k["env"] = CLEAN_ENV
        super().__init__(*a, **k)

    def communicate(self, *a, **k):
        out, err = super().communicate(*a, **k)
        _tl.raw = out
        return out, err


def load_tool(path):
    spec = importlib.util.spec_from_file_location("sbe", path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    m.subprocess.Popen = RecordingPopen  # module attribute is shared; rebinding is process-wide
    return m


def audit_stream(raw):
    tools, init, result = [], {}, {}
    for ln in (raw or "").splitlines():
        try:
            e = json.loads(ln)
        except ValueError:
            continue
        if not isinstance(e, dict):
            continue
        if e.get("type") == "system" and e.get("subtype") == "init":
            init = {"model": e.get("model"),
                    "plugins": [p.get("path") for p in e.get("plugins") or [] if isinstance(p, dict)],
                    "ts_skill_listed": any("typescript-dev" in str(s) for s in e.get("skills") or [])}
        elif e.get("type") == "assistant":
            for c in (e.get("message") or {}).get("content") or []:
                if isinstance(c, dict) and c.get("type") == "tool_use":
                    tools.append({"name": c.get("name"), "input": c.get("input")})
        elif e.get("type") == "user":
            # tool results: kept so leakage is auditable from what the agent actually saw
            for c in (e.get("message") or {}).get("content") or []:
                if isinstance(c, dict) and c.get("type") == "tool_result":
                    body = c.get("content")
                    body = body if isinstance(body, str) else json.dumps(body, ensure_ascii=False)
                    tools.append({"name": "<result>", "is_error": c.get("is_error"),
                                  "mentions_typescript_dev": "typescript-dev" in body,
                                  "head": body[:300]})
        elif e.get("type") == "result":
            result = {k: e.get(k) for k in ("subtype", "total_cost_usd", "duration_ms", "num_turns", "usage")}
    return {"init": init, "tool_uses": tools, "result": result}


def main():
    ap = argparse.ArgumentParser()
    for k in ("tool", "fixtures", "before", "after", "cwd", "out", "model"):
        ap.add_argument("--" + k, required=True)
    ap.add_argument("--only", default="")
    ap.add_argument("--samples", type=int, default=10)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--timeout", type=int, default=900)
    ap.add_argument("--max-turns", type=int, default=12)
    ap.add_argument("--stop-util", type=float, default=0.93)
    ap.add_argument("--mask", action="append", default=[],
                    help="directory hidden behind a tmpfs in every arm (repeatable)")
    a = ap.parse_args()
    out = os.path.abspath(a.out)
    t = load_tool(a.tool)
    layer = {"current": "plugin-tree:before", "candidate": "plugin-tree:after"}
    tree = {"current": os.path.abspath(a.before), "candidate": os.path.abspath(a.after)}
    only = {x for x in a.only.split(",") if x}
    rows = [r for r in t.load_fixtures(a.fixtures) if not only or r["id"] in only]
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "layers.json"), "w") as fh:
        json.dump({"layers": layer, "trees": tree, "model": a.model, "max_turns": a.max_turns,
                   "samples": a.samples, "mask": a.mask, "cwd": a.cwd}, fh, indent=1)
    # sample-major order, arms alternate, so both arms run interleaved in the same run
    jobs = [(fx, arm, s) for s in range(1, a.samples + 1) for fx in rows for arm in ("current", "candidate")]
    state = {"util": None, "stop": False}
    lock = threading.Lock()
    logf = open(os.path.join(out, "run-log.jsonl"), "a")

    def run(job):
        fx, arm, s = job
        rpath = os.path.join(out, f"{fx['id']}.{arm}.s{s}.txt")
        sig = t.sample_sig(fx, arm, layer[arm])
        if os.path.isfile(rpath) and t._saved_sig(rpath) == sig:
            return
        with lock:
            if state["stop"]:
                return
        cmd = ["claude", "-p", "--output-format", "stream-json", "--verbose", "--model", a.model,
               "--max-turns", str(a.max_turns),
               # --allowedTools only pre-approves; --tools is what removes Bash/Write/Edit/etc.
               # dontAsk + --add-dir: reads outside cwd and this arm's own tree are denied,
               # and the tool already rejects any run with permission denials.
               "--tools", "Read", "Grep", "Glob", "Skill", "--permission-mode", "dontAsk",
               "--add-dir", tree[arm],
               "--settings", json.dumps({"enabledPlugins": {"ccl-skills@ccl-skills": False,
                                                           "context-mode@context-mode": False}}),
               "--plugin-dir", tree[arm]]
        # Read/Grep/Glob are not path-confined, so the other tree and every checkout that holds
        # the skill are hidden by mount namespace instead: tmpfs over the masked dirs, this arm's
        # tree re-mounted read-only at its usual path, a fresh empty cwd per run.
        box = ["bwrap", "--bind", "/", "/", "--dev-bind", "/dev", "/dev", "--proc", "/proc"]
        for d in a.mask:
            box += ["--tmpfs", d]
        box += ["--ro-bind", tree[arm], tree[arm], "--dir", a.cwd, "--chdir", a.cwd, "--"]
        cmd = box + cmd
        _tl.raw = None
        t0 = time.time()
        text, err, util, invoked = t._headless_claude(cmd, fx["prompt"], a.timeout)
        dt = time.time() - t0
        meta = audit_stream(_tl.raw)
        meta.update({"id": fx["id"], "arm": arm, "sample": s, "wall_s": round(dt), "error": err,
                     "skills_invoked": invoked})
        with open(rpath[:-4] + ".meta.json", "w") as fh:
            json.dump(meta, fh, ensure_ascii=False, indent=1)
        with lock:
            if util is not None:
                state["util"] = util
                state["stop"] = state["stop"] or util > a.stop_util
            logf.write(json.dumps({"id": fx["id"], "arm": arm, "sample": s, "dt": round(dt),
                                   "util": util, "error": err, "invoked": invoked}) + "\n")
            logf.flush()
        if err:
            print(f"[{fx['id']}/{arm}/s{s}] ERROR {err} ({dt:.0f}s)", flush=True)
            return
        with open(rpath, "w", encoding="utf-8") as rf:
            rf.write(f"# sig: {sig}\n")
            rf.write(f"# {fx['id']} / arm={arm} / sample={s} / {dt:.0f}s / util={util}\n")
            rf.write(f"# skills_invoked: {json.dumps(invoked, ensure_ascii=False)}\n")
            rf.write(f"# axis: {fx.get('axis','')}\n# RUBRIC (judgment-grade, do NOT keyword-match):\n# {fx.get('rubric','')}\n\n")
            rf.write(text + "\n")
        print(f"[{fx['id']}/{arm}/s{s}] saved {dt:.0f}s invoked={invoked}", flush=True)

    with ThreadPoolExecutor(a.workers) as ex:
        list(ex.map(run, jobs))
    logf.close()
    print("done; stopped_on_util=", state["stop"], "util=", state["util"], flush=True)


if __name__ == "__main__":
    main()
