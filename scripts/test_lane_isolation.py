#!/usr/bin/env python3
"""Mechanical enforcement of the parallel lanes' isolation precondition.

`scripts/run-parallel-suites.sh` makes a lane's suites overlap in time. That is
sound only while no two suites in one lane share mutable out-of-repo state, and
round 037 established that by a manual audit. A manual audit protects the tree
it was run against and nothing else: the next suite added to a lane can quietly
reintroduce a fixed temp path, a global git write, or a listening port, and the
lanes would race with no gate objecting.

So the audit lives here as an executable check. It derives the ACTUAL lane
membership (Makefile shard targets plus the regression runner's own arrays --
never a hand-copied list that could drift), follows the local helpers those
members source or execute, scans for hazard patterns, and fails on any hit that
is not an explicitly reviewed exception.

Stale exceptions fail too: an allowlist that may only grow is a rubber stamp.

WHAT THIS IS NOT. It is a regression tripwire over the enumerated hazard classes
below, not a proof of isolation. A suite can always reach shared state by a route
static text cannot see (a tool it invokes, a path it computes at runtime), so
successive review rounds will always be able to name one more shape. Chasing them
one at a time buys less than being honest about the boundary: the standing
assurance is the reviewed audit of current membership plus CI itself, where a real
race surfaces as flakiness. This gate exists so the COMMON shapes cannot regress
silently between audits, and so adding a suite that obviously shares state is
caught at the moment it is added.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
RUNNER = REPO / "skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh"

# Hazards are judged PER OCCURRENCE, never per line. Skipping a whole line
# because it happens to mention a workspace variable is how a real hazard hides:
# `printf '%s' "$TMP" > /tmp/shared` and `git config --global x "$TMP"` both carry
# a safe-looking token and still mutate state shared across concurrent suites.
#
# A `/tmp/` occurrence is workspace-scoped only when it is part of a mktemp
# template or a `${TMPDIR:-/tmp}` default — decided from the text immediately
# around that occurrence, not from anywhere on the line. A path already rooted at
# a variable (`"$WORK/tmp/x"`) never matches in the first place, because the
# pattern's lookbehind rejects a preceding word character.
# The exemption must end EXACTLY at the occurrence. A looser "mktemp appears
# somewhere earlier on the line" window is what lets `WORK="$(mktemp -d)"; cp x
# /tmp/shared` pass — the masking shape this gate exists to catch.
TMP_OCCURRENCE_SAFE = re.compile(r"(?:TMPDIR:-|mktemp(?:\s+-[A-Za-z]+)*\s+)$")

HAZARDS = [
    # Shared temp roots, however spelled.
    ("fixed-tmp", re.compile(r"(?<![\w$}])/(?:var/)?tmp/"), True),
    # Any global git mutation, not just `config`.
    ("git-global", re.compile(r"git\s+(?:config\s+--global|--global\s+config)"), False),
    # $HOME as a write target in any form: redirect, or a mutating command's
    # argument. `touch "$HOME/x"` was invisible to a redirect-only pattern.
    ("home-write", re.compile(
        r">>?\s*\"?\$\{?HOME"
        r"|(?:touch|cp|mv|rm|mkdir|tee|install|ln)\s[^\n]*\$\{?HOME"
        r"|\$\{?HOME\}?/[^\s\"']*\s*<<"), False),
    # Shared XDG/config roots outside the suite's own workspace.
    ("shared-config-root", re.compile(r"\$\{?XDG_(?:CONFIG|CACHE|DATA)_HOME"), False),
    # Anything that occupies a fixed port: URL form, or a server/bind invocation.
    ("listen-port", re.compile(
        r"(?:localhost|127\.0\.0\.1|0\.0\.0\.0):\d+"
        r"|http\.server\s+\d+"
        r"|--(?:port|bind)[= ]\d+"
        r"|\bnc\s+-l\b"), False),
]

# Reviewed exceptions, keyed by (file, hazard, exact stripped line). Content-keyed
# on purpose: moving a line is fine, changing what it does is not.
#
#   test_cli_review_wrappers.sh -- the /tmp/forbidden* paths are CANARIES. They are
#     payloads inside untrusted hook/MCP fixtures that the wrapper must refuse to
#     execute; nothing writes them on a passing run, and their absence is the
#     assertion. Only this one suite uses them.
#   test_review_gate.sh, test_parse_probe_result.sh -- argv fixture strings compared
#     as text against what a stub received. No file is opened.
ALLOWED = {
    ("test_cli_review_wrappers.sh", "fixed-tmp", 'command = "touch /tmp/forbidden-mcp"'),
    ("test_cli_review_wrappers.sh", "fixed-tmp",
     'hooks = [{ event = "PreToolUse", matcher = "Read", command = "touch /tmp/forbidden" }]'),
    ("test_cli_review_wrappers.sh", "fixed-tmp", 'command = "touch /tmp/forbidden"'),
    ("test_review_gate.sh", "fixed-tmp", '"--review-plan-file", "/tmp/plan.json",'),
    ("test_review_gate.sh", "fixed-tmp", '"--diff-file", "/tmp/diff.patch",'),
    # Same canary class: the /tmp path is a payload inside an untrusted MCP
    # fixture the wrapper must refuse to execute; the redirect target is $WORK.
    ("test_cli_review_wrappers.sh", "fixed-tmp",
     'printf \'%s\\n\' \'{"mcpServers":{"untrusted":{"command":"touch","args":["/tmp/forbidden-mcp-json"]}}}\' >"$WORK/kimi-source/mcp.json"'),
}
# Whole (file, hazard) exemptions, for a case where every occurrence in a file
# shares one verified reason and listing them individually would be noise.
#
#   test_opencode_review_retry.sh / test_opencode_review_concurrency.sh --
#     shared-config-root. Verified rather than assumed: the reading lines sit
#     inside stub scripts the suite GENERATES into its own $WORK (e.g. the
#     `cat >"$WORK/bin/opencode" <<'STUB'` heredoc), and every XDG_DATA_HOME
#     assignment in each file -- all 14 in the retry suite, none excepted --
#     points at "$WORK/...". The stubs therefore only ever see a workspace-scoped
#     root at runtime. A text scanner cannot resolve that, which is precisely the
#     boundary this gate declares; it is recorded here as a reviewed exception
#     instead of being hidden by a rule loose enough to mask real hazards.
ALLOWED_FILE_HAZARD = {
    ("test_opencode_review_retry.sh", "shared-config-root"),
    ("test_opencode_review_concurrency.sh", "shared-config-root"),
}

# Long fixture lines are matched by prefix so an unrelated edit elsewhere on the
# line does not silently re-arm the gate against reviewed content.
ALLOWED_PREFIX = {
    ("test_parse_probe_result.sh", "fixed-tmp",
     'run_ok 0 $\'{"type":"system","subtype":"init"'),
}


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def lane_members() -> list[Path]:
    """Derive lane membership from the real dispatch points."""
    members: list[str] = []
    for target in ("test-code-review-1", "test-code-review-2"):
        out = subprocess.run(
            ["make", "-n", target], cwd=REPO, capture_output=True, text=True
        )
        if out.returncode != 0:
            fail(f"could not read lane membership for {target}: {out.stderr.strip()}")
        members += re.findall(r"skills/\S+\.(?:sh|py)", out.stdout)

    source = RUNNER.read_text(encoding="utf-8")
    for name in ("fast_tests", "heavy_tests"):
        block = re.search(rf"^{name}=\((.*?)^\)", source, re.S | re.M)
        if not block:
            fail(f"could not read the {name} array from {RUNNER.name}")
        for line in block.group(1).splitlines():
            entry = line.strip()
            if entry and not entry.startswith("#"):
                members.append(os.path.normpath(f"skills/skill-extraction-workflow/scripts/{entry}"))

    resolved = sorted({REPO / m for m in members})
    missing = [p for p in resolved if not p.exists()]
    if missing:
        fail("lane membership names files that do not exist: "
             + ", ".join(p.name for p in missing))
    return resolved


# A suite can put the hazard in a helper it sources or runs, leaving its own text
# clean. Follow local repo-relative helpers so the scan covers what a lane member
# actually executes, bounded by a visited set (helpers form cycles) and a depth
# cap (a full call graph is not what this tripwire promises).
HELPER_REF = re.compile(
    r"""(?:^|\s)(?:\.|source|bash|sh|python3?)\s+"?\$?\{?(?:SCRIPT_DIR|REPO_ROOT|REPO)?\}?/?"""
    r"""([A-Za-z0-9_./-]+\.(?:sh|py|bash))"""
)


def with_helpers(paths: list[Path], max_depth: int = 2, root: Path | None = None) -> list[Path]:
    # `root` bounds traversal to one tree. It is a parameter so the self-check can
    # run wholly inside a temporary directory: writing probe files into the source
    # tree would clobber whatever sits at those paths, break a read-only checkout,
    # and let two concurrent runs corrupt each other.
    allowed = (root or REPO).resolve()
    seen: set[Path] = set()
    frontier = list(paths)
    depth = 0
    while frontier and depth <= max_depth:
        nxt: list[Path] = []
        for path in frontier:
            if path in seen or not path.exists():
                continue
            seen.add(path)
            text = path.read_text(encoding="utf-8", errors="replace")
            for ref in HELPER_REF.findall(text):
                for base in (path.parent, allowed):
                    candidate = (base / ref).resolve()
                    if candidate.exists() and allowed in candidate.parents and candidate not in seen:
                        nxt.append(candidate)
                        break
        frontier = nxt
        depth += 1
    return sorted(seen)


# A file that ASSIGNS an environment root to its own workspace has scoped that
# root for everything it then invokes, so later uses of the variable are not
# shared state. This is a per-VARIABLE, per-FILE judgement backed by the
# assignment -- not the discredited "any safe-looking token anywhere on the line"
# skip, which hid independent hazards sitting on the same line.
# Only a STANDALONE or exported assignment scopes the variable for the rest of
# the file, and the assignment must be the WHOLE statement: `HOME=... some_cmd`
# is a command prefix that scopes just that one command, and a mention inside a
# comment scopes nothing. Counting either would let a real hazard elsewhere in
# the file be suppressed.
ASSIGNMENT_LINE = re.compile(
    r"""^\s*(?:export\s+)?(HOME|XDG_[A-Z]+_HOME)=("[^"]*"|'[^']*'|\S+)\s*(?:#.*)?$"""
)
WORKSPACE_VALUE = re.compile(r"\$\{?WORK|\$\{?TMP|\$\(mktemp")
VAR_SCOPED_HAZARDS = {"home-write": "HOME", "shared-config-root": "XDG"}


def scoped_roots(text: str) -> set[str]:
    scoped = set()
    for raw in text.splitlines():
        if raw.strip().startswith("#"):
            continue
        match = ASSIGNMENT_LINE.match(raw)
        if match and WORKSPACE_VALUE.search(match.group(2)):
            scoped.add("HOME" if match.group(1) == "HOME" else "XDG")
    return scoped


def scan(paths: list[Path]) -> set[tuple[str, str, str]]:
    findings: set[tuple[str, str, str]] = set()
    for path in paths:
        body = path.read_text(encoding="utf-8", errors="replace")
        scoped = scoped_roots(body)
        for raw in body.splitlines():
            line = raw.strip()
            if line.startswith("#"):
                continue
            for hazard, pattern, occurrence_exempt in HAZARDS:
                if VAR_SCOPED_HAZARDS.get(hazard) in scoped:
                    continue
                for match in pattern.finditer(line):
                    if occurrence_exempt and TMP_OCCURRENCE_SAFE.search(line[: match.start()]):
                        continue
                    findings.add((path.name, hazard, line))
                    break
    return findings


def allowed(finding: tuple[str, str, str]) -> bool:
    if finding in ALLOWED:
        return True
    name, hazard, line = finding
    if (name, hazard) in ALLOWED_FILE_HAZARD:
        return True
    return any(
        name == a_name and hazard == a_hazard and line.startswith(a_prefix)
        for a_name, a_hazard, a_prefix in ALLOWED_PREFIX
    )


def self_check() -> None:
    """Prove the scanner can fail — and can stay quiet — before trusting a verdict.

    The masked cases are the point: a line may carry a workspace token AND an
    independent hazard, and an earlier version of this gate skipped such a line
    wholesale. Each must-flag case below therefore pairs a safe-looking token with
    a real hazard on the same line.
    """
    must_flag = {
        "bare fixed /tmp write": 'printf hi > /tmp/shared-fixture.txt',
        "workspace token masking a /tmp write": 'printf \'%s\' "$TMP" > /tmp/shared-fixture.txt',
        "mktemp masking a later /tmp write": 'WORK="$(mktemp -d)"; cp x /tmp/shared-fixture.txt',
        "workspace token masking a global git write": 'git config --global user.name "$TMP"',
        "workspace token masking a HOME write": 'printf "$TMP" >> "$HOME/.ccl-shared"',
        "workspace token masking a port": 'curl "$TMP" http://localhost:8080/x',
    }
    must_stay_quiet = {
        "path rooted at a workspace variable": 'printf hi > "$WORK/tmp/thing.txt"',
        "TMPDIR default inside a mktemp template": 'TMP="$(mktemp -d "${TMPDIR:-/tmp}/suite.XXXXXX")"',
    }
    # Whole-file cases: a root the file scopes to its own workspace is not shared,
    # but merely USING an inherited root is.
    multiline_must_flag = {
        "inherited XDG root used without scoping it":
            'auth="$XDG_DATA_HOME/opencode/auth.json"\nprintf hi > "$auth"',
        "inherited HOME used as a write target":
            'touch "$HOME/.ccl-shared"',
    }
    multiline_must_stay_quiet = {
        "HOME scoped by a standalone assignment":
            'WORK="$(mktemp -d)"\nHOME="$WORK/home"\ntouch "$HOME/.thing"',
        "XDG scoped by an exported assignment":
            'WORK="$(mktemp -d)"\nexport XDG_DATA_HOME="$WORK/data"\n'
            'auth="$XDG_DATA_HOME/opencode/auth.json"',
    }
    # A command-prefix assignment scopes only that command, and a comment scopes
    # nothing — neither may suppress a hazard elsewhere in the file.
    multiline_must_flag.update({
        "command-local assignment does not scope the rest of the file":
            'WORK="$(mktemp -d)"\nHOME="$WORK/home" run_thing\ntouch "$HOME/.shared"',
        "a commented assignment scopes nothing":
            '# HOME="$WORK/home"\ntouch "$HOME/.shared"',
    })
    with tempfile.TemporaryDirectory() as tmp:
        # A hazard that lives only in a sourced helper must still be found; scanning
        # the registered suite alone would report clean while the lane races. Both
        # probes live in the temp tree, and traversal is bounded to it.
        probe_root = Path(tmp) / "probe-root"
        probe_root.mkdir()
        helper = probe_root / "helper.sh"
        caller = probe_root / "caller.sh"
        helper.write_text('#!/usr/bin/env bash\nprintf hi > /tmp/helper-shared.txt\n',
                          encoding="utf-8")
        caller.write_text('#!/usr/bin/env bash\nsource "$SCRIPT_DIR/helper.sh"\n',
                          encoding="utf-8")
        if not scan(with_helpers([caller], root=probe_root)):
            fail("a hazard reachable only through a sourced helper was not found")

        for label, body in must_flag.items():
            probe = Path(tmp) / "test_probe.sh"
            probe.write_text(f"#!/usr/bin/env bash\n{body}\n", encoding="utf-8")
            if not scan([probe]):
                fail(f"the scanner missed a planted hazard ({label}); it proves nothing")
        for label, body in must_stay_quiet.items():
            probe = Path(tmp) / "test_probe.sh"
            probe.write_text(f"#!/usr/bin/env bash\n{body}\n", encoding="utf-8")
            found = scan([probe])
            if found:
                fail(f"the scanner cried wolf on a workspace-scoped line ({label}): {found}")
        for label, body in multiline_must_flag.items():
            probe = Path(tmp) / "test_probe.sh"
            probe.write_text(f"#!/usr/bin/env bash\n{body}\n", encoding="utf-8")
            if not scan([probe]):
                fail(f"the scanner missed an inherited shared root ({label})")
        for label, body in multiline_must_stay_quiet.items():
            probe = Path(tmp) / "test_probe.sh"
            probe.write_text(f"#!/usr/bin/env bash\n{body}\n", encoding="utf-8")
            found = scan([probe])
            if found:
                fail(f"the scanner cried wolf on a self-scoped root ({label}): {found}")


def main() -> None:
    self_check()

    members = lane_members()
    # A derivation that silently returns nothing would make every assertion below
    # vacuously true, which is the failure mode this floor exists to prevent.
    if len(members) < 20:
        fail(f"lane derivation produced only {len(members)} members; it is broken, not clean")

    findings = scan(with_helpers(members))
    unreviewed = sorted(f for f in findings if not allowed(f))
    if unreviewed:
        print(
            "FAIL: a suite in a PARALLEL lane touches mutable state outside its own "
            "workspace. Concurrent suites would race on it.\n"
            "Fix the suite to use its own `mktemp -d` workspace, or -- if the hit is "
            "genuinely inert (a fixture string, an absence-canary) -- review it and add "
            "it to ALLOWED in this file with the reason.",
            file=sys.stderr,
        )
        for name, hazard, line in unreviewed:
            print(f"  {name}: {hazard}: {line[:120]}", file=sys.stderr)
        raise SystemExit(1)

    covered_file_hazards = {(name, hazard) for name, hazard, _ in findings}
    stale = sorted(
        [entry for entry in ALLOWED if entry not in findings]
        + [entry for entry in ALLOWED_FILE_HAZARD if entry not in covered_file_hazards]
    )
    if stale:
        print(
            "FAIL: reviewed exceptions no longer match anything. An allowlist that only "
            "grows stops being a review; drop these entries.",
            file=sys.stderr,
        )
        for entry in stale:
            print("  " + ": ".join(str(part)[:120] for part in entry), file=sys.stderr)
        raise SystemExit(1)

    print(f"lane_isolation_ok: {len(members)} lane members, "
          f"{len(findings)} reviewed exception(s), 0 unreviewed")


if __name__ == "__main__":
    main()
