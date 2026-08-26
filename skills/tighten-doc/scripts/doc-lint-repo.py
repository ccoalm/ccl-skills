#!/usr/bin/env python3
"""Fail when a tracked Markdown doc in a repository carries an ERROR-class defect.

`doc-lint.py` (this script's sibling) decides every predicate for ONE document.
This is the repository-wide enumerator: it lists the tracked Markdown of a repo
you point it at, runs the linter over all of it in one pass, and turns the ERROR
tier into a landing gate. Nothing here judges a document; it decides only WHICH
files are in scope and WHICH tier blocks.

    python3 doc-lint-repo.py /path/to/your/repo

It is written to run against ANY repository, not only the one that ships it. That
is the point: a repo-local scanner would have made this skill's own documents the
only ones ever checked. Both paths it depends on are derived, not assumed — the
linter is the sibling file next to this script, and the fixture exclusion is that
linter's own `tests/` directory, resolved against whatever repo you scanned.

WHY ERROR ONLY. Measured over the shipping repository's 481 tracked non-fixture
Markdown files: 0 ERROR, 75 WARN. Blocking on the WARN tier would fail that repo
on its own docs the day the gate lands, and the right conclusion is not a waiver
list — the WARN predicates are labelled `[工]` engineering proxies in
`../references/figure-and-table-craft.md` (§9b), and that file's own rule is that
a proxy which cannot separate a defect from a judgement call must not gate. So
the WARN count is printed for visibility and does not block. The ERROR tier is
the objective half: an empty or absent table header, a dangling figure reference,
an unreadable file.

WHY A FIXTURE DIRECTORY IS EXCLUDED, and why that is not convenience. The
linter's own corpus under its `tests/` directory contains documents built to
violate each predicate; measured, it reports 2 ERROR by construction. Scanning it
would make this gate permanently red for the exact inputs that prove the linter
works. The exclusion is ONE derived prefix and applies only when that directory
actually sits inside the scanned repo — in a consuming repo the skill is
installed elsewhere, so nothing is excluded and nothing needs to be. It is
asserted in both directions: a real doc must not be dropped by it, and a fixture
must not be scanned. A wider exclusion is the failure mode to guard against — it
hides real documents while still printing a pass.

Scope is TRACKED files only: an untracked scratch file is not part of the
delivered repo, and including it would make the verdict depend on the working
tree rather than on what lands.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
# The linter that owns every predicate — the sibling file, NOT a path guessed
# inside the scanned repo. Deriving it is what lets this run against a repo that
# has never heard of this skill.
LINTER = HERE / "doc-lint.py"
# Documents built to violate the predicates so the linter can prove it detects
# them. Derived from the linter's own location, and applied only if that location
# is inside the repo being scanned.
FIXTURE_DIR = HERE / "tests"

TOTAL_RE = re.compile(r"^合计: (\d+) ERROR, (\d+) WARN", re.M)
ERROR_ROW_RE = re.compile(r"^  ERROR +([A-Z][A-Z0-9-]+)", re.M)


def fixture_prefix(root: Path) -> str | None:
    """The fixture directory as a repo-relative prefix, or None if outside it."""
    try:
        rel = FIXTURE_DIR.resolve().relative_to(root)
    except ValueError:
        return None
    return f"{rel.as_posix()}/"


def tracked_markdown(root: Path) -> list[str]:
    """Tracked Markdown paths, fixtures removed. Fails closed on a git error.

    Enumerate EVERYTHING and filter on a case-folded suffix rather than asking
    git for `*.md`. That pathspec is case-sensitive on a case-sensitive
    filesystem, so a tracked `NOTES.MD` is silently outside a gate that reports
    repository-wide Markdown coverage — a hole in exactly the property this
    script exists to provide.
    """
    proc = subprocess.run(
        ["git", "-C", str(root), "ls-files", "-z"],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"git ls-files exited {proc.returncode}: {proc.stderr.strip()}")
    paths = [p for p in proc.stdout.split("\0") if p]
    md = [p for p in paths if Path(p).suffix.casefold() == ".md"]
    prefix = fixture_prefix(root)
    if prefix is None:
        return md
    return [p for p in md if not p.startswith(prefix)]


def main(argv: list[str]) -> int:
    root = Path(argv[0] if argv else ".").resolve()
    linter = LINTER
    if not linter.is_file():
        # Fail closed: a missing linter must not read as "nothing to report".
        print(
            f"doc_structure_check_failed: linter not found at {linter}; "
            "the gate cannot certify a corpus it never scanned",
            file=sys.stderr,
        )
        return 1

    try:
        files = tracked_markdown(root)
    except RuntimeError as exc:
        print(f"doc_structure_check_failed: {exc}", file=sys.stderr)
        return 1

    if not files:
        # An empty scope is a scoping bug, not a clean corpus. A repository worth
        # gating has tracked Markdown; zero means the enumeration broke or the
        # path is not the repo you meant.
        print(
            "doc_structure_check_failed: no tracked Markdown in scope — the "
            "enumeration is broken, not the corpus clean",
            file=sys.stderr,
        )
        return 1

    proc = subprocess.run(
        [sys.executable, str(linter), *files],
        capture_output=True,
        text=True,
        cwd=str(root),
    )
    # doc-lint's contract: 0 clean / 2 WARN-only / 1 has ERROR. Anything else is
    # the linter itself failing, which this gate must not read as a clean corpus.
    if proc.returncode not in (0, 1, 2):
        print(
            f"doc_structure_check_failed: linter exited {proc.returncode} "
            f"(expected 0/1/2); its output cannot be trusted as a verdict\n"
            f"{proc.stderr.strip()[:2000]}",
            file=sys.stderr,
        )
        return 1

    total = TOTAL_RE.search(proc.stdout)
    if not total:
        print(
            "doc_structure_check_failed: linter produced no 合计 line, so the "
            "count it reports cannot be read; treat as unscanned",
            file=sys.stderr,
        )
        return 1
    n_err, n_warn = int(total.group(1)), int(total.group(2))

    # CROSS-CHECK the exit code against the counts. Accepting the code as merely
    # "in range" and then trusting the totals alone leaves the contradictory case
    # open: a linter that exits 1 — its own signal for "there are ERRORs" — while
    # printing `合计: 0 ERROR` is read here as a clean corpus and returns 0. That
    # is the shape a partial failure after summary emission takes, and it is the
    # one combination where every other guard in this file is satisfied. Both
    # review lanes found it independently; the crash and unparseable-output tests
    # do not reach it, because this output is perfectly parseable and merely lying.
    expected_rc = 1 if n_err else (2 if n_warn else 0)
    if proc.returncode != expected_rc:
        print(
            f"doc_structure_check_failed: linter exit code {proc.returncode} "
            f"contradicts its own summary ({n_err} ERROR, {n_warn} WARN, which "
            f"its contract maps to {expected_rc}). One of the two is wrong, so "
            f"neither can be trusted as a verdict; treat as unscanned.",
            file=sys.stderr,
        )
        return 1

    if n_err:
        # Print the ERROR rows only. The WARN tier is visibility, and dumping 75
        # advisory lines into a failure message buries the blocking ones.
        for line in proc.stdout.splitlines():
            if line.startswith("  ERROR") or (
                line.strip() and not line.startswith("  ") and "ERROR" in line
            ):
                print(line, file=sys.stderr)
        codes = sorted(set(ERROR_ROW_RE.findall(proc.stdout)))
        print(
            f"doc_structure_check_failed: {n_err} ERROR-class structure defect(s) "
            f"across {len(files)} tracked doc(s): {', '.join(codes)}. "
            f"Fix the document; these are objective defects (a table with no real "
            f"header, a figure reference with no such figure, an unreadable file), "
            f"not style preferences. Run "
            f"`python3 {linter} <file>` for the per-file detail.",
            file=sys.stderr,
        )
        return 1

    print(
        f"doc_structure_check_ok: {len(files)} tracked doc(s), 0 ERROR, "
        f"{n_warn} WARN (advisory, non-blocking — the WARN predicates are `[工]` "
        f"proxies and do not gate)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
