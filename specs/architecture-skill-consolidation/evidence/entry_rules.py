#!/usr/bin/env python3
"""Rebuild or verify skills/software-architecture/references/service-design-rules.md from the two old entries.

usage: entry_rules.py <worktree> <base-ref> build|verify

Every block of the old entries (a paragraph, a table, or a top-level bullet with its children)
outside Skill Routing and Reference Loading must appear in the rules file: verbatim after the link
rewrites in LINKS, or as one of the hand-merged blocks in HAND. The three platform-owner bullets of
Skill Routing are carried too. verify also requires the file on disk to equal what build produces.
"""
import re
import subprocess
import sys
from pathlib import Path

WT, BASE, MODE = sys.argv[1], sys.argv[2], sys.argv[3]
GO, PY = "go-microservice-architecture", "python-service-architecture"
OUT = Path(WT) / "skills/software-architecture/references/service-design-rules.md"


def show(skill):
    return subprocess.run(["git", "-C", WT, "show", f"{BASE}:skills/{skill}/SKILL.md"],
                          check=True, capture_output=True, text=True).stdout


def sections(text):
    """-> {h2 title: [lines]} for the body"""
    out, cur = {}, None
    for line in text.split("\n"):
        if line.startswith("## "):
            cur = line[3:].strip()
            out[cur] = []
        elif cur:
            out[cur].append(line)
    return out


def blocks(lines):
    """Group lines into blocks: a paragraph / table / top-level bullet with its nested children."""
    out, cur = [], []

    def flush():
        nonlocal cur
        while cur and not cur[-1].strip():
            cur.pop()
        if cur:
            out.append("\n".join(cur))
        cur = []

    base_indent = None
    for line in lines:
        if not line.strip():
            if cur and cur[0].lstrip().startswith("|"):
                flush()
            elif cur and not cur[0].lstrip().startswith(("-", "|")) and not re.match(r"\s*\d+\. ", cur[0]):
                flush()
            continue
        indent = len(line) - len(line.lstrip())
        is_bullet = line.lstrip().startswith("- ") or re.match(r"\s*\d+\. ", line)
        if is_bullet and (base_indent is None or indent <= base_indent):
            flush()
            base_indent = indent
            cur = [line]
        elif line.lstrip().startswith("|") and cur and cur[0].lstrip().startswith("|"):
            cur.append(line)
        elif cur and is_bullet:
            cur.append(line)
        elif cur and cur[0].lstrip().startswith("- ") and indent > base_indent:
            cur.append(line)
        else:
            flush()
            base_indent = None if not is_bullet else indent
            cur = [line]
    flush()
    return out


def dedent(block):
    ls = block.split("\n")
    n = min(len(l) - len(l.lstrip()) for l in ls if l.strip())
    return "\n".join(l[n:] for l in ls)


def workflow(lines):
    """Core Workflow -> (preface blocks, [(step title, [blocks])])"""
    pre, steps, cur = [], [], None
    for line in lines:
        m = re.match(r"^(\d)\. (.+)$", line)
        if m:
            cur = (m.group(2), [])
            steps.append(cur)
        elif cur is None:
            pre.append(line)
        else:
            cur[1].append(line)
    return blocks(pre), [(t, [dedent(b) for b in blocks(ls)]) for t, ls in steps]


# Every H2 of an old entry is either migrated here or excluded with a reason.
HANDLED = {"Platform Boundary", "Generalization Discipline", "Core Workflow", "Architecture Defaults"}
EXCLUDED = {
    "Skill Routing": "routing is rewritten in the new entry's Routing section and compared bullet by bullet in the zero-loss map; its three platform-owner bullets are carried verbatim below",
    "Reference Loading": "the pointer list is replaced by the reference index, checked by script against the references directory",
}


def model(skill):
    text = show(skill)
    s = sections(text)
    unaccounted = set(s) - HANDLED - set(EXCLUDED)
    assert not unaccounted, f"{skill}: H2 sections neither migrated nor excluded: {sorted(unaccounted)}"
    assert HANDLED <= set(s), f"{skill}: expected sections missing: {sorted(HANDLED - set(s))}"
    # The text before the first H2 (frontmatter, title, one intro paragraph) is
    # replaced by the new entry's opening paragraph; check it is only that.
    before = text.split("\n## ", 1)[0].split("\n---\n", 1)[-1].strip().split("\n\n")
    assert len(before) == 2 and before[0].startswith("# "), f"{skill}: unexpected text before the first H2"
    pre, steps = workflow(s["Core Workflow"])
    assert len(steps) == 5, f"{skill}: expected 5 workflow steps, found {len(steps)}"
    # The three platform-owner routing bullets carry the service-side half of each
    # platform contract; they move with the contract table.
    platform_routes = [dedent(b) for b in blocks(s["Skill Routing"]) if b.startswith("- Use `platform-")]
    assert len(platform_routes) == 3, skill
    m = {
        "Platform boundary contract": [dedent(b) for b in blocks(s["Platform Boundary"])] + platform_routes,
        "Generalization discipline": [dedent(b) for b in blocks(s["Generalization Discipline"])],
        "Planning depth": pre,
        "Architecture defaults": [dedent(b) for b in blocks(s["Architecture Defaults"])],
    }
    return m, steps


go_m, go_steps = model(GO)
py_m, py_steps = model(PY)

STEP_TITLES = [
    ("Step 1 — Boundary", 0, 0),
    ("Step 2 — Contracts", 1, 1),
    ("Step 3 — Data ownership", 2, 2),
    ("Step 4 — Runtime and dependency contracts", 3, 3),
    ("Step 5 — Code generation, quality, and release readiness", 4, 4),
]


def groups():
    order = ["Platform boundary contract", "Generalization discipline", "Planning depth"]
    g = [(k, go_m[k], py_m[k]) for k in order]
    for title, gi, pi in STEP_TITLES:
        g.append((title, go_steps[gi][1], py_steps[pi][1]))
    g.append(("Architecture defaults", go_m["Architecture defaults"], py_m["Architecture defaults"]))
    return g


LINKS = [
    ("`references/protobuf-contract-architecture.md`", "`protobuf-contract-architecture.md`"),
    ("`../go-microservice-architecture/references/protobuf-contract-architecture.md`", "`protobuf-contract-architecture.md`"),
    ("`../platform-service-connectivity/references/", "`platform-service-connectivity/references/"),
    (" Mirror any change to this rule in `../python-service-architecture/SKILL.md`.", ""),
    (" Mirror any change to this rule in `../go-microservice-architecture/SKILL.md`.", ""),
]


def norm(b):
    for old, new in LINKS:
        b = b.replace(old, new)
    return b


def sub(*pairs):
    def f(t):
        for old, new in pairs:
            assert t.count(old) == 1, (old, t[:60])
            t = t.replace(old, new)
        return t
    return f


# (go block prefix, python block prefix, transform applied to the normalized Go block)
HAND = [
    ("- Do not copy product nouns,", "- Do not copy product nouns,", sub()),
    ("- API contracts must define request messages,", "- API contracts must define request schemas,",
     sub(("request messages,", "request messages/schemas,"))),
    ("- Internal service data models need", "- Internal service data models need",
     sub(("convert at transport/application boundaries", "convert at transport (route)/application boundaries"))),
    ("- **Inventory the service's exposed surfaces", "- **Inventory the service's exposed surfaces", sub(
        ("HTTP routes, RPC services and methods, and async subscriptions (MQ / event / webhook consumers)",
         "HTTP routes (in Python: FastAPI / Flask / Django), RPC services and methods, and async subscriptions (MQ / Celery / queue / event / webhook consumers)"),
        ("or a generated manifest plus a checked-in snapshot", "or a generated OpenAPI/manifest plus a checked-in snapshot"),
        ("(`buf breaking` / `kitex check`, which guards *changes to existing* surfaces)",
         "(`buf breaking` / `kitex check` in Go, schema / contract diff in Python — both guard *changes to existing* surfaces)"))),
    ("- Dependency clients: DB, Redis, MQ,", "- Dependency clients for DB, Redis, MQ,",
     sub(("secret provider, and external HTTP clients must", "secret provider, external HTTP, and inference clients must"))),
    ("- When comparing a new product backend against a mature internal reference", "- When comparing a new product backend against a mature internal reference", sub(
        ("MQ producer/consumer lifecycle", "MQ/queue producer/consumer lifecycle"),
        ("across HTTP/RPC/MQ,", "across HTTP/RPC/MQ (queue),"))),
    ("- Mature reference code is useful only", "- Mature reference code is useful only",
     sub(("config schemas, transaction helpers, MQ lifecycle helpers,", "config schemas, unit-of-work or transaction helpers, MQ/queue lifecycle helpers,"))),
]

HEADER = """# Service Design Rules (full wording)

The entry `SKILL.md` carries the walk-list: one condensed line per obligation, at the step where it fires. This file carries the full wording of the Go and Python rules, grouped by the same steps: a `Shared` part that both former entries stated, and one part per stack. Node.js/TypeScript has no part here; for a Node.js/TypeScript service the entry's method and its Node.js/TypeScript part are the rule, and nothing under `Shared` transfers to it on its own — in particular not the RPC/gRPC transport default. Read the section for the step you are deciding before giving a conclusion that depends on it; when a condensed line and this file differ, this file is the rule and the entry line is fixed in the same change.

A rule that changes here names its downstream owner before landing: the stack's dev skill for code mechanics, `testing-strategy` for the proof layer, the `platform-*` skills for runtime contracts, and `product-rd-workflow` for cross-stage gates.
"""


def build():
    out = [HEADER]
    merged_log = []
    for title, gb, pb in groups():
        gb, pb = [norm(b) for b in gb], [norm(b) for b in pb]
        shared = [b for b in gb if b in pb]
        for gpre, ppre, tf in HAND:
            g = [b for b in gb if b.startswith(gpre) and b not in shared]
            q = [b for b in pb if b.startswith(ppre) and b not in shared]
            if len(g) == 1 and len(q) == 1:
                m = tf(g[0])
                gb = [m if b == g[0] else b for b in gb]
                pb.remove(q[0])
                shared.append(m)
                merged_log.append((title, gpre, ppre, m))
        shared = [b for b in gb if b in shared]  # keep Go order
        out.append(f"## {title}\n")
        for label, bl in (("Shared", shared), ("Go", [b for b in gb if b not in shared]),
                          ("Python", [b for b in pb if b not in shared])):
            if not bl:
                continue
            out.append(f"### {label}\n")
            prev = None
            for b in bl:
                isb = b.startswith("- ")
                if prev is not None and not (isb and prev):
                    out.append("")
                out.append(b)
                prev = isb
            out.append("")
    return "\n".join(out).rstrip("\n") + "\n", merged_log


if MODE == "build":
    text, log = build()
    assert len(log) == len(HAND), [l[1] for l in log]
    OUT.write_text(text)
    print(f"built {OUT.name}: bytes={len(text.encode())} lines={text.count(chr(10))} hand_merged={len(log)}")
elif MODE == "verify":
    expected, log = build()
    bad = 0
    if OUT.read_text() != expected:
        print("RULES_FILE_DIFFERS_FROM_GENERATOR")
        bad = 1
    text = OUT.read_text()
    verbatim = merged = 0
    for title, gb, pb in groups():
        for stack, bl in (("go", gb), ("python", pb)):
            for b in bl:
                nb = norm(b)
                if nb in text:
                    verbatim += 1
                    continue
                idx = 1 if stack == "go" else 2
                hit = [l for l in log if l[0] == title and nb.startswith(l[idx])]
                if len(hit) == 1 and hit[0][3] in text:
                    merged += 1
                    print(f"HAND_MERGED [{stack}] {title}: {nb[:70]!r}")
                    continue
                bad += 1
                print(f"LOST [{stack}] {title}: {nb[:110]!r}")
    print(f"entry_rules verbatim={verbatim} hand_merged={merged} lost={bad}")
    sys.exit(1 if bad else 0)
