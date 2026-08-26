#!/usr/bin/env python3
"""Fail when a README states a skill count that no longer matches skills/.

Both READMEs are reader-facing product pages, and the npm one is frozen into
each published tarball, so a stale count is visible on the package page until
the next release. The claim is cheap to state and cheap to check, so check it.

A README that states no count is fine; this gate never requires the sentence.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

README_PATHS = ("README.md", "packages/ccl-skills-npm/README.md")
COUNT_RE = re.compile(r"\b(\d+) skills\b")


def actual_skill_count(root: Path) -> int:
    skills = root / "skills"
    return sum(1 for child in sorted(skills.iterdir()) if (child / "SKILL.md").is_file())


def findings(root: Path) -> list[str]:
    expected = actual_skill_count(root)
    problems: list[str] = []
    for relative in README_PATHS:
        path = root / relative
        if not path.is_file():
            problems.append(f"{relative}: missing")
            continue
        for line_number, line in enumerate(
            path.read_text(encoding="utf-8").splitlines(), 1
        ):
            for match in COUNT_RE.finditer(line):
                stated = int(match.group(1))
                if stated != expected:
                    problems.append(
                        f"{relative}:{line_number}: states {stated} skills, "
                        f"skills/ holds {expected}"
                    )
    return problems


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    problems = findings(root)
    if problems:
        for problem in problems:
            print(problem, file=sys.stderr)
        return 1
    print(f"skill_count_ok: READMEs agree with skills/ ({actual_skill_count(root)})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
