#!/usr/bin/env python3
"""Generate / verify skills/software-architecture/references from the two old trees at a base ref.

usage: migrate_refs.py <worktree> <base-ref> generate|verify
Reads old content from git (base ref), so it works after the old trees are deleted.
"""
import hashlib
import re
import subprocess
import sys
from pathlib import Path

WT, BASE, MODE = sys.argv[1], sys.argv[2], sys.argv[3]
GO, PY, NEW = "go-microservice-architecture", "python-service-architecture", "software-architecture"
MERGED = ["event-driven-architecture.md", "multi-tenant-isolation.md", "data-platform-architecture.md"]
START = "## When this applies / does not apply"
GATE_H3 = "### Mirrored-section grep gate"
BACKLOG = "## Topic-extension backlog"


def git(*a):
    return subprocess.run(["git", "-C", WT, *a], check=True, capture_output=True, text=True).stdout


def ls(skill):
    out = git("ls-tree", "--name-only", f"{BASE}:skills/{skill}/references/")
    return sorted(x for x in out.split("\n") if x)


def show(skill, name):
    return git("show", f"{BASE}:skills/{skill}/references/{name}")


go_files, py_files = ls(GO), ls(PY)
PAIRED = sorted((set(go_files) & set(py_files)) - set(MERGED))


def newname(stack, name):
    if name in PAIRED:
        return ("go-" if stack == GO else "python-") + name
    return name


TOKEN = re.compile(r"(?P<pre>(?:\.\./)?(?:[A-Za-z0-9_.-]+/)*)(?P<name>[a-z0-9-]+\.md)")


def rewrite(text, stack):
    """Deterministic link rewrite for content that originated in <stack>'s tree."""
    own = {GO: set(go_files), PY: set(py_files)}

    def sub(m):
        pre, name = m.group("pre"), m.group("name")
        for other in (GO, PY):
            if pre in (f"{other}/references/", f"../{other}/references/", f"skills/{other}/references/"):
                if name in own[other]:
                    return newname(other, name)
                return m.group(0)
        if pre in ("", "references/") and name in own[stack]:
            return pre + newname(stack, name)
        return m.group(0)

    return TOKEN.sub(sub, text)


SHARED_EDITS = {
    # exact old -> new fragments inside the shared regions (two-tree inline routing)
    "event-driven-architecture.md": [
        ("(use `api-contract-and-schema.md` on the Python tree / `protobuf-contract-architecture.md` on the Go tree instead)",
         "(use `api-contract-and-schema.md` for Python / `protobuf-contract-architecture.md` for Go instead)"),
        ("(use `background-jobs-and-scheduling.md` or `batch-and-pipeline-architecture.md` on the Python tree / `notification-architecture.md` or `bulk-workflow-architecture.md` on the Go tree)",
         "(use `background-jobs-and-scheduling.md` or `batch-and-pipeline-architecture.md` for Python / `go-notification-architecture.md` or `bulk-workflow-architecture.md` for Go)"),
    ],
    "multi-tenant-isolation.md": [
        ("route to `web-framework-boundaries.md` or `api-contract-and-schema.md` on the Python tree / `api-security-boundaries.md` on the Go tree,",
         "route to `web-framework-boundaries.md` or `api-contract-and-schema.md` for Python / `go-api-security-boundaries.md` for Go,"),
    ],
    "data-platform-architecture.md": [
        ("route to `data-modeling-and-migrations.md`",
         "route to `go-data-modeling-and-migrations.md` for Go / `python-data-modeling-and-migrations.md` for Python"),
    ],
}

LAYOUT = (
    "> **Layout.** One file carries the stack-agnostic core once (everything from `## When this applies / does not apply` "
    "up to the first stack section) followed by one implementation section per stack. This is the single-file form of "
    "`skill-extraction-workflow/references/parallel-stack-references-pattern.md`: with one copy of the core there is no "
    "sibling to keep in sync. The core stays free of three categories of stack-specific token — DB-engine-specific syntax, "
    "runtime/concurrency-mechanic names, and library/framework API names; the concrete token list and grep command live in "
    "`## Shared-region grep gate` at the end of this file. Before commit, run that grep against the core; zero hits required. "
    "Routing text that differs per stack is written inline for both stacks (`x.md` for Python / `y.md` for Go)."
)

PREAMBLE = {
    "event-driven-architecture.md": [
        "# Event-Driven Architecture",
        "",
        "Use when designing event-driven systems, async message contracts, producer/consumer ownership, transactional outbox/inbox, sagas, schema evolution, dead-letter and replay strategy, or end-to-end delivery guarantees for a service that publishes or consumes messages.",
        "",
        "This file owns the **architecture of durable, cross-service event-driven boundaries** — delivery semantics taxonomy, producer-side patterns, transactional outbox, idempotency design, schema evolution, saga/choreography, fanout, replay, and end-to-end \"exactly-once\" illusion. Scope split per stack:",
        "",
        "- Go: `mq-consumer-architecture.md` covers consumer-side processing semantics, topic/group ownership, and consumer operations. Load both when designing a new event-driven boundary.",
        "- Python: this complements `async-execution-model.md` (concurrency model choice), `background-jobs-and-scheduling.md` (in-tenant scheduled jobs), `reliability-and-error-contract.md` (error contract), and `observability-and-ops.md` (OpenTelemetry / startup wiring / propagation).",
        "",
        LAYOUT + " Either this file or `multi-tenant-isolation.md` may be used as a template; multi-tenant additionally demonstrates the `## Topic-extension backlog` H2 for topic-wider-than-loop cases.",
        "",
    ],
    "multi-tenant-isolation.md": [
        "# Multi-Tenant Isolation",
        "",
        None,  # use-when paragraph copied verbatim from the old file (line 3)
        "",
        LAYOUT,
        "",
    ],
    "data-platform-architecture.md": [
        "# Data Platform Architecture",
        "",
        None,  # line 3 verbatim
        "",
        "This complements `go-data-modeling-and-migrations.md` / `python-data-modeling-and-migrations.md` (which own schema, index, transaction, outbox, and per-service migration concerns): this file owns the **substrate** that schema and queries sit on. Load both when designing a new data-bound service or auditing an existing one.",
        "",
        LAYOUT,
        "",
    ],
}

GATE_SUBS = [
    ("The sibling-sync header forbids three categories of stack-specific token in mirrored sections (",
     "The layout header forbids three categories of stack-specific token in the shared region (", 1),
    ("everything *before* the `## Go-specific implementation patterns` H2)",
     "everything *before* the first stack section, `## Go-specific implementation patterns`)", 1),
    ("against the mirrored region", "against the shared region", 1),
    ("which mirrored sections do not use", "which the shared region does not use", None),
    ("Forbidden tokens for this Go file's mirrored sections:", "Forbidden tokens for the shared region:", 1),
    ("the *Sibling sync* header itself", "the *Layout* header itself", 1),
    ("Vendor names in mirrored sections", "Vendor names in the shared region", None),
]
SIBLING_SENTENCE = re.compile(
    r"The sibling Python file maintains the matching gate for Python-side tokens(?: \([^)]*\))?, so a token forbidden here "
    r"may legitimately appear in the \*Python-specific implementation patterns\* section of the sibling, and vice versa\.")
SIBLING_NEW = ("The stack sections sit below the shared region and outside the scan, so a token forbidden here may "
               "legitimately appear in either stack section.")


def split(text, stack_label):
    """-> (preamble, shared, stack_body, gate, backlog) as lists of lines"""
    lines = text.split("\n")
    stop = f"## {stack_label}-specific implementation patterns"
    i_start = lines.index(START)
    i_stop = lines.index(stop)
    i_gate = lines.index(GATE_H3)
    i_back = lines.index(BACKLOG) if BACKLOG in lines else len(lines)
    assert i_start < i_stop < i_gate <= i_back
    return lines[:i_start], lines[i_start:i_stop], lines[i_stop:i_gate], lines[i_gate:i_back], lines[i_back:]


def sanitization_block(pre):
    idx = next(i for i, l in enumerate(pre) if l.startswith("> **Sanitization boundary.**"))
    blk = pre[idx:]
    while blk and blk[-1] == "":
        blk.pop()
    return blk


def build_merged(name):
    g_pre, g_sh, g_body, g_gate, g_back = split(show(GO, name), "Go")
    p_pre, p_sh, p_body, p_gate, p_back = split(show(PY, name), "Python")
    assert g_sh == p_sh, f"shared region differs at base: {name}"
    assert g_back == p_back, f"backlog differs at base: {name}"
    assert sanitization_block(g_pre) == sanitization_block(p_pre), f"sanitization block differs: {name}"

    shared = "\n".join(g_sh)
    for old, new in SHARED_EDITS[name]:
        assert shared.count(old) == 1, (name, old)
        shared = shared.replace(old, new)

    pre = []
    for item in PREAMBLE[name]:
        if item is None:
            assert g_pre[2] == p_pre[2], name
            item = g_pre[2]
        pre.append(item)
    sani = "\n".join(sanitization_block(g_pre))
    sani = sani.replace(
        "The mirrored-section grep gate at the end of this file's stack-glue forbids *stack-specific implementation syntax* in mirrored content",
        "The shared-region grep gate at the end of this file forbids *stack-specific implementation syntax* in the shared region",
    ).replace("are *intentionally* in mirrored content", "are *intentionally* in the shared region")
    pre.extend(sani.split("\n"))
    pre.append("")

    gate = "\n".join(g_gate)
    gate = gate.replace(GATE_H3, "## Shared-region grep gate")
    for old, new, n in GATE_SUBS:
        assert (gate.count(old) == n) if n else gate.count(old) <= 1, (name, old)
        gate = gate.replace(old, new)
    assert len(SIBLING_SENTENCE.findall(gate)) <= 1
    gate = SIBLING_SENTENCE.sub(SIBLING_NEW, gate)
    assert "sibling" not in gate.lower() and "mirrored" not in gate.lower(), (name, gate)

    # The Python gate must say the same thing as the Go gate apart from naming its
    # own stack and its sibling; otherwise a Python-only token would be dropped.
    def gate_core(lines, own, other):
        out = []
        for line in lines:
            if line.startswith("Allowed exception:"):
                continue
            out.append(line.replace(f"{own}-specific", "STACK-specific").replace(f"this {own} file", "this STACK file"))
        return out
    assert gate_core(g_gate, "Go", "Python") == gate_core(p_gate, "Python", "Go"), f"Go and Python gates differ: {name}"

    # The scan starts at the shared region, not at the top of the file, so a
    # stack-specific scope note in the preamble is not reported as contamination.
    # A renamed or missing boundary heading must not read as a clean scan, so the
    # command checks that each boundary occurs exactly once before it greps.
    old_awk = f"awk '/^## Go-specific implementation patterns/{{exit}} 1' {name}"
    # Extraction and scan are separate steps so the three outcomes have three
    # exit statuses: 2 when a boundary is missing, duplicated or out of order
    # (the scan did not run), 0 when grep finds a forbidden token, 1 when the
    # shared region is clean.
    new_awk = (
        "region=\"$(awk '$0 == \"## When this applies / does not apply\" { s++; if (e) bad = 1; f = 1 }\n"
        "     $0 == \"## Go-specific implementation patterns\" { e++; f = 0 }\n"
        "     f { print }\n"
        "     END { if (s != 1 || e != 1 || bad) { print \"shared-region boundary missing, duplicated or out of order: the scan did not run\" > \"/dev/stderr\"; exit 2 } }' "
        f"{name})\" \\\n"
        "  && printf '%s\\n' \"$region\""
    )
    assert gate.count(old_awk) == 1, (name, "awk")
    gate = gate.replace(old_awk, new_awk)
    gate = gate.replace(
        "Run this grep against the shared region before every commit; zero hits required",
        "Run this command before every commit. Exit status 1 with no output means the shared region is clean; 0 means a forbidden token was found; 2 means a boundary heading is missing, duplicated or out of order and the scan did not run",
    )
    # Pre-existing drift between the multi-tenant token list and its regex.
    if name == "multi-tenant-isolation.md":
        for old, new in (("|Hertz|Kitex|SQLAlchemy|", "|Hertz|Kitex|golang\\.org/x/time/rate|SQLAlchemy|"),
                         ("`aiokafka`, `pika`, `aio-pika`", "`aiokafka`, `\\bpika\\b`, `aio-pika`")):
            assert gate.count(old) == 1, (name, old)
            gate = gate.replace(old, new)

    go_body = rewrite("\n".join(g_body), GO)
    py_body = rewrite("\n".join(p_body), PY)

    def block(s):
        return s.strip("\n") + "\n"

    out = "\n".join(block(p) for p in ["\n".join(pre), shared, go_body, py_body, gate])
    if g_back:
        out += "\n" + block("\n".join(g_back))
    return out, {"shared_lines": len(g_sh), "go_lines": len(g_body), "py_lines": len(p_body)}


def expected():
    files, rows = {}, []
    for name in MERGED:
        out, meta = build_merged(name)
        files[name] = out
        rows.append((f"{GO}/{name} + {PY}/{name}", name, "merged", meta))
    for stack, names in ((GO, go_files), (PY, py_files)):
        for name in names:
            if name in MERGED:
                continue
            old = show(stack, name)
            new = rewrite(old, stack)
            nn = newname(stack, name)
            assert nn not in files, nn
            files[nn] = new
            changed = sum(1 for a, b in zip(old.split("\n"), new.split("\n")) if a != b)
            assert len(old.split("\n")) == len(new.split("\n"))
            rows.append((f"{stack}/{name}", nn, "identical" if old == new else f"links-rewritten:{changed}",
                         {"old_sha": hashlib.sha256(old.encode()).hexdigest()[:12],
                          "new_sha": hashlib.sha256(new.encode()).hexdigest()[:12]}))
    return files, rows


HAND_EDITS = {
    "go-source-evidence-map.md": [(
        "- `python-service-architecture` — cross-language counterpart? mirror at architecture level.",
        "- this skill's Python stack defaults and `python-*` references — cross-language counterpart? mirror at architecture level.")],
    "python-source-evidence-map.md": [(
        "- `go-microservice-architecture` — cross-language counterpart? mirror at architecture level.",
        "- this skill's Go stack defaults and `go-*` references — cross-language counterpart? mirror at architecture level.")],
}
for _n in ("python-workflow-state-architecture.md", "python-notification-architecture.md",
           "python-replay-comparison-architecture.md", "python-audit-history-architecture.md"):
    HAND_EDITS[_n] = [("(not under the parallel-stack parity gate)", "(a separate per-stack file, not a single-file shared core)")]
for _n in MERGED:
    HAND_EDITS[_n] = [
        ("the sibling Python file localizes the same patterns differently.", "the Python section below localizes the same patterns differently."),
        ("the sibling Go file localizes the same patterns differently.", "the Go section above localizes the same patterns differently."),
    ]


def apply_hand_edits(files, rows):
    for n, edits in HAND_EDITS.items():
        for old, new in edits:
            assert files[n].count(old) == 1, (n, old)
            files[n] = files[n].replace(old, new)
    out = []
    for r in rows:
        if r[1] in HAND_EDITS and r[2] != "merged":
            r = (r[0], r[1], (r[2] + "+" if r[2] != "identical" else "") + f"reworded:{len(HAND_EDITS[r[1]])}",
                 {"old_sha": r[3]["old_sha"], "new_sha": hashlib.sha256(files[r[1]].encode()).hexdigest()[:12]})
        out.append(r)
    return out


files, rows = expected()
rows = apply_hand_edits(files, rows)
dest = Path(WT) / "skills" / NEW / "references"
if MODE == "generate":
    dest.mkdir(parents=True, exist_ok=True)
    for n, c in files.items():
        (dest / n).write_text(c)
    print(f"generated {len(files)} files")
elif MODE == "verify":
    bad = 0
    NEW_FILES = {"service-design-rules.md", "method-grounding.md"}  # authored for the merged skill
    present = sorted(p.name for p in dest.glob("*.md") if p.name not in NEW_FILES)
    if present != sorted(files):
        print("FILESET_MISMATCH", sorted(set(present) ^ set(files)))
        bad = 1
    for n, c in files.items():
        p = dest / n
        # A symlink, a directory or a missing path is not a migrated document,
        # even when its name is in the listing.
        if p.is_symlink() or not p.is_file():
            print("NOT_A_REGULAR_FILE", n)
            bad = 1
        elif p.read_text() != c:
            print("CONTENT_MISMATCH", n)
            bad = 1
    for r in rows:
        print(" | ".join([r[0], r[1], r[2], ", ".join(f"{k}={v}" for k, v in r[3].items())]))
    print("VERIFY_FAIL" if bad else f"VERIFY_OK files={len(files)}")
    sys.exit(bad)
