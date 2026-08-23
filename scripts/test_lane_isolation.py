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
never a hand-copied list that could drift), scans each member for hazard
patterns, and fails on any hit that is not an explicitly reviewed exception.

Stale exceptions fail too: an allowlist that may only grow is a rubber stamp.
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
    ("fixed-tmp", re.compile(r"(?<![\w$}])/tmp/"), True),
    ("git-global", re.compile(r"git config --global"), False),
    ("home-write", re.compile(r">>?\s*\"?\$\{?HOME"), False),
    ("listen-port", re.compile(r"(?:localhost|127\.0\.0\.1):\d+"), False),
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


def scan(paths: list[Path]) -> set[tuple[str, str, str]]:
    findings: set[tuple[str, str, str]] = set()
    for path in paths:
        for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
            line = raw.strip()
            if line.startswith("#"):
                continue
            for hazard, pattern, occurrence_exempt in HAZARDS:
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
    with tempfile.TemporaryDirectory() as tmp:
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


def main() -> None:
    self_check()

    members = lane_members()
    # A derivation that silently returns nothing would make every assertion below
    # vacuously true, which is the failure mode this floor exists to prevent.
    if len(members) < 20:
        fail(f"lane derivation produced only {len(members)} members; it is broken, not clean")

    findings = scan(members)
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

    stale = sorted(
        entry for entry in ALLOWED if entry not in findings
    )
    if stale:
        print(
            "FAIL: reviewed exceptions no longer match anything. An allowlist that only "
            "grows stops being a review; drop these entries.",
            file=sys.stderr,
        )
        for name, hazard, line in stale:
            print(f"  {name}: {hazard}: {line[:120]}", file=sys.stderr)
        raise SystemExit(1)

    print(f"lane_isolation_ok: {len(members)} lane members, "
          f"{len(findings)} reviewed exception(s), 0 unreviewed")


if __name__ == "__main__":
    main()
