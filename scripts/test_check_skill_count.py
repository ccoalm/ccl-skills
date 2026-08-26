#!/usr/bin/env python3
"""Regression tests for check-skill-count.py."""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("check-skill-count.py")
SPEC = importlib.util.spec_from_file_location("check_skill_count", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class SkillCountCheckTest(unittest.TestCase):
    def make_repo(self, skills: int, readmes: dict[str, str]) -> Path:
        sandbox = Path(self.enterContext(tempfile.TemporaryDirectory()))
        root = sandbox / "repo"
        for index in range(skills):
            skill = root / "skills" / f"skill-{index}"
            skill.mkdir(parents=True)
            (skill / "SKILL.md").write_text("x\n", encoding="utf-8")
        for name, content in readmes.items():
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")
        return root

    def both_readmes(self, body: str) -> dict[str, str]:
        return {"README.md": body, "packages/ccl-skills-npm/README.md": body}

    def test_matching_count_passes(self) -> None:
        root = self.make_repo(3, self.both_readmes("3 skills cover the lifecycle.\n"))
        self.assertEqual(MODULE.findings(root), [])

    def test_stale_count_is_reported_per_readme(self) -> None:
        root = self.make_repo(3, self.both_readmes("32 skills cover the lifecycle.\n"))
        problems = MODULE.findings(root)
        self.assertEqual(len(problems), 2, problems)
        for problem in problems:
            self.assertIn("states 32 skills, skills/ holds 3", problem)

    def test_readme_without_a_count_is_accepted(self) -> None:
        root = self.make_repo(3, self.both_readmes("Workflows for coding agents.\n"))
        self.assertEqual(MODULE.findings(root), [])

    def test_a_directory_without_skill_md_is_not_a_skill(self) -> None:
        root = self.make_repo(3, self.both_readmes("3 skills cover the lifecycle.\n"))
        (root / "skills" / "scratch").mkdir()
        self.assertEqual(MODULE.findings(root), [])

    def test_missing_readme_is_reported(self) -> None:
        root = self.make_repo(3, {"README.md": "3 skills.\n"})
        problems = MODULE.findings(root)
        self.assertEqual(problems, ["packages/ccl-skills-npm/README.md: missing"])

    def test_the_gate_holds_on_this_repository(self) -> None:
        root = Path(__file__).resolve().parents[1]
        self.assertEqual(MODULE.findings(root), [])


if __name__ == "__main__":
    unittest.main()
