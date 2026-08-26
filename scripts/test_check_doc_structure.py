#!/usr/bin/env python3
"""Assertions for `check-doc-structure.py`.

Every leg states what it pins. The two that matter most are the exclusion pair:
an exclusion is the only part of a scanner that can make it print a pass while
covering less than it claims, so it is asserted in BOTH directions — a fixture
must be dropped, and a real document under a similar path must not be.

The fail-closed legs matter for the same reason: a scanner that returns 0 when
it could not scan is worse than no scanner, because it certifies a corpus it
never read.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
SCRIPT = HERE / "check-doc-structure.py"
LINTER_REL = "skills/tighten-doc/scripts/doc-lint.py"
FIXTURE_PREFIX = "skills/tighten-doc/scripts/tests/"

CLEAN_DOC = """# Title

A paragraph with nothing structurally wrong.

| Name | Count (n) |
| --- | --- |
| alpha | 1 |
| beta | 2 |
"""

# A table whose header row is empty. This is WCAG 2.2 SC 1.3.1 territory and the
# linter's ERROR tier, not a style opinion.
HEADERLESS_DOC = """# Title

|  |  |
| --- | --- |
| alpha | 1 |
| beta | 2 |
"""


def run(args, cwd=None):
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        text=True,
        cwd=cwd,
    )


def make_repo(tmp: Path, docs: dict[str, str], *, with_linter=True) -> Path:
    """A git repo carrying the real linter plus the given docs."""
    root = tmp / "repo"
    root.mkdir()
    subprocess.run(["git", "init", "-q", "-b", "trunk", str(root)], check=True)
    subprocess.run(["git", "-C", str(root), "config", "user.email", "t@example.invalid"], check=True)
    subprocess.run(["git", "-C", str(root), "config", "user.name", "T"], check=True)
    subprocess.run(["git", "-C", str(root), "config", "commit.gpgsign", "false"], check=True)
    if with_linter:
        dest = root / LINTER_REL
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text((REPO / LINTER_REL).read_text(encoding="utf8"), encoding="utf8")
    for rel, body in docs.items():
        p = root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(body, encoding="utf8")
    subprocess.run(["git", "-C", str(root), "add", "-A"], check=True)
    subprocess.run(["git", "-C", str(root), "commit", "-qm", "seed"], check=True)
    return root


class RealRepo(unittest.TestCase):
    def test_gate_is_green_and_states_its_coverage(self):
        """The gate is green on the current checkout, and says how many docs it read.

        A pass with no count is unfalsifiable: it reads identically whether the
        scanner covered 481 documents or zero.
        """
        proc = run([str(REPO)], cwd=str(REPO))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("doc_structure_check_ok:", proc.stdout)
        count = int(proc.stdout.split("doc_structure_check_ok:")[1].split()[0])
        self.assertGreater(count, 100, "scope collapsed; the pass covers almost nothing")


class Exclusion(unittest.TestCase):
    def test_fixture_corpus_is_excluded(self):
        """Without the exclusion this gate is permanently red on its own fixtures."""
        with tempfile.TemporaryDirectory() as tmp:
            root = make_repo(
                Path(tmp),
                {
                    "docs/real.md": CLEAN_DOC,
                    FIXTURE_PREFIX + "doc/broken.md": HEADERLESS_DOC,
                },
            )
            proc = run([str(root)], cwd=str(root))
            self.assertEqual(proc.returncode, 0, proc.stderr + proc.stdout)
            self.assertIn("1 tracked doc(s)", proc.stdout)

    def test_exclusion_does_not_swallow_a_real_doc(self):
        """The other direction: a path that merely LOOKS fixture-ish stays in scope.

        This is the leg that catches an exclusion widened into a pattern. A
        one-directional exclusion test passes just as well when the exclusion
        has quietly grown to cover half the repo.

        THE DEFECT MUST SIT ON THE AT-RISK PATH, and that is not a detail. The
        first version of this leg put the headerless table on a path with no
        `tests/` segment and a clean doc on `docs/tests/guide.md`; a mutation
        that widened the prefix to a `"tests/" in p` substring then dropped only
        the CLEAN document, the verdict did not move, and the leg stayed green
        while its own docstring claimed it tested both directions. Applying that
        mutation is what found it. Keep the ERROR on the path the widened
        exclusion would swallow, or this leg proves nothing again.
        """
        with tempfile.TemporaryDirectory() as tmp:
            root = make_repo(
                Path(tmp),
                {
                    # Contains `tests/`, is NOT under the fixture prefix, and is
                    # the doc carrying the defect.
                    "docs/tests/guide.md": HEADERLESS_DOC,
                    "skills/tighten-doc/scripts/testing-notes.md": CLEAN_DOC,
                },
            )
            proc = run([str(root)], cwd=str(root))
            self.assertEqual(
                proc.returncode,
                1,
                "a real doc on a fixture-looking path was dropped by the exclusion",
            )
            self.assertIn("doc_structure_check_failed:", proc.stderr)
            self.assertIn("WCAG-131-TABLE", proc.stderr)


class Blocking(unittest.TestCase):
    def test_error_blocks_and_names_the_predicate(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = make_repo(Path(tmp), {"docs/bad.md": HEADERLESS_DOC})
            proc = run([str(root)], cwd=str(root))
            self.assertEqual(proc.returncode, 1)
            self.assertIn("doc_structure_check_failed:", proc.stderr)
            # rc alone is a weak oracle: name WHICH defect, or an unrelated
            # failure reads as the gate working.
            self.assertIn("WCAG-131-TABLE", proc.stderr)

    def test_warn_only_corpus_does_not_block(self):
        """The WARN tier is advisory by decision, not by accident.

        `figure-and-table-craft.md` §9b: a proxy that cannot separate a defect
        from a judgement call must not gate. If this leg ever flips, that
        decision was reversed silently.

        ASSERT ON THE COUNTS, NOT ON THE WORDS. The first version searched the
        success line for the literal strings "WARN" and "non-blocking" — both of
        which that line always contains, whatever the counts are. The leg would
        have stayed green if the parser started reporting 0 WARN, or if this
        fixture stopped producing any WARN at all. The challenge lane found it.
        So: parse the numbers, and independently confirm the fixture really is a
        WARN-only document by checking the linter's own exit code is 2.
        """
        # A numeric column with no unit, over enough rows to trip TABLE-NO-UNIT.
        # The single-row version used first produced ZERO findings — which is how
        # the old string-matching assertion passed on a fixture that tested nothing.
        warn_doc = (
            "# Title\n\n| 指标 | 值 |\n| --- | --- |\n"
            "| 延迟 | 120 |\n| 吞吐 | 4500 |\n| 错误率 | 3 |\n| 并发 | 64 |\n"
        )
        with tempfile.TemporaryDirectory() as tmp:
            root = make_repo(Path(tmp), {"docs/warny.md": warn_doc})

            # Precondition: the fixture is WARN-only per the linter itself. If
            # this ever stops holding, the leg below is testing nothing.
            direct = subprocess.run(
                [sys.executable, str(root / LINTER_REL), str(root / "docs/warny.md")],
                capture_output=True,
                text=True,
            )
            self.assertEqual(
                direct.returncode, 2, "fixture is no longer WARN-only: " + direct.stdout
            )

            proc = run([str(root)], cwd=str(root))
            self.assertEqual(proc.returncode, 0, proc.stderr)
            m = re.search(r"(\d+) tracked doc\(s\), (\d+) ERROR, (\d+) WARN", proc.stdout)
            self.assertIsNotNone(m, proc.stdout)
            n_docs, n_err, n_warn = (int(g) for g in m.groups())
            self.assertEqual(n_docs, 1)
            self.assertEqual(n_err, 0)
            self.assertGreater(n_warn, 0, "WARN tier reported nothing; leg proves nothing")
            self.assertIn("non-blocking", proc.stdout)


class Coverage(unittest.TestCase):
    def test_uppercase_extension_is_in_scope(self):
        """A tracked `.MD` is Markdown, and a coverage gate that misses it lies.

        `git ls-files '*.md'` is case-sensitive on a case-sensitive filesystem,
        so a document named `NOTES.MD` sat outside a gate whose whole claim is
        repository-wide tracked-Markdown coverage. The review lane found it. The
        defect must sit on the uppercase file, or the leg passes on the lowercase
        one and proves nothing.
        """
        with tempfile.TemporaryDirectory() as tmp:
            root = make_repo(
                Path(tmp),
                {"docs/CLEAN.md": CLEAN_DOC, "docs/BYPASS.MD": HEADERLESS_DOC},
            )
            proc = run([str(root)], cwd=str(root))
            self.assertEqual(proc.returncode, 1, "an uppercase-extension doc was skipped")
            self.assertIn("WCAG-131-TABLE", proc.stderr)


class ContradictoryLinter(unittest.TestCase):
    """The exit code and the summary must agree, or neither is a verdict.

    Both review lanes found this independently: accepting the code as merely
    "in range" and then trusting the totals leaves open the one combination
    where every other guard here is satisfied — a linter that exits 1 (its
    signal for "there are ERRORs") while printing `合计: 0 ERROR`. The crash and
    unparseable-output legs do not reach it: this output parses perfectly and is
    simply lying.
    """

    def _stub(self, code: str, rc: int):
        with tempfile.TemporaryDirectory() as tmp:
            root = make_repo(Path(tmp), {"docs/real.md": CLEAN_DOC})
            (root / LINTER_REL).write_text(
                f"import sys\nprint({code!r})\nsys.exit({rc})\n", encoding="utf8"
            )
            proc = run([str(root)], cwd=str(root))
            return proc

    def test_exit_1_with_zero_errors_is_not_read_as_clean(self):
        proc = self._stub("合计: 0 ERROR, 0 WARN", 1)
        self.assertEqual(proc.returncode, 1)
        self.assertIn("contradicts its own summary", proc.stderr)

    def test_exit_0_with_errors_reported_is_not_read_as_clean(self):
        proc = self._stub("合计: 3 ERROR, 0 WARN", 0)
        self.assertEqual(proc.returncode, 1)
        self.assertIn("contradicts its own summary", proc.stderr)

    def test_exit_2_with_zero_findings_is_not_read_as_clean(self):
        proc = self._stub("合计: 0 ERROR, 0 WARN", 2)
        self.assertEqual(proc.returncode, 1)
        self.assertIn("contradicts its own summary", proc.stderr)

    def test_consistent_warn_only_stub_is_accepted(self):
        """The control: a stub that AGREES with itself must pass.

        Without it, a cross-check that rejected everything would look identical
        to one that works.
        """
        proc = self._stub("合计: 0 ERROR, 4 WARN", 2)
        self.assertEqual(proc.returncode, 0, proc.stderr)


class FailsClosed(unittest.TestCase):
    def test_missing_linter_blocks(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = make_repo(Path(tmp), {"docs/real.md": CLEAN_DOC}, with_linter=False)
            proc = run([str(root)], cwd=str(root))
            self.assertEqual(proc.returncode, 1)
            self.assertIn("linter not found", proc.stderr)

    def test_empty_scope_blocks(self):
        """No tracked Markdown is a broken enumeration, never a clean corpus."""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "empty"
            root.mkdir()
            subprocess.run(["git", "init", "-q", "-b", "trunk", str(root)], check=True)
            (root / LINTER_REL).parent.mkdir(parents=True, exist_ok=True)
            (root / LINTER_REL).write_text(
                (REPO / LINTER_REL).read_text(encoding="utf8"), encoding="utf8"
            )
            proc = run([str(root)], cwd=str(root))
            self.assertEqual(proc.returncode, 1)
            self.assertIn("enumeration is broken", proc.stderr)

    def test_non_git_directory_blocks(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "plain"
            (root / LINTER_REL).parent.mkdir(parents=True, exist_ok=True)
            (root / LINTER_REL).write_text(
                (REPO / LINTER_REL).read_text(encoding="utf8"), encoding="utf8"
            )
            proc = run([str(root)], cwd=str(root))
            self.assertEqual(proc.returncode, 1)
            # Name WHICH refusal. Asserting only the generic token cannot tell a
            # git failure apart from the empty-scope guard catching the empty
            # list a swallowed git error would return — a mutation that replaced
            # the raise with a fall-through stayed green here for that reason.
            self.assertIn("git ls-files exited", proc.stderr)

    def test_linter_crash_is_not_read_as_clean(self):
        """A linter that dies must block, not certify.

        Substituting a stub that exits 3 pins the exit-code contract check: 0/1/2
        are verdicts, anything else is the linter failing.
        """
        with tempfile.TemporaryDirectory() as tmp:
            root = make_repo(Path(tmp), {"docs/real.md": CLEAN_DOC})
            (root / LINTER_REL).write_text(
                "import sys\nsys.exit(3)\n", encoding="utf8"
            )
            proc = run([str(root)], cwd=str(root))
            self.assertEqual(proc.returncode, 1)
            self.assertIn("expected 0/1/2", proc.stderr)

    def test_missing_total_line_is_not_read_as_clean(self):
        """A linter that prints nothing parseable must block.

        Exit 0 plus unreadable output is the exact shape that makes a scanner
        certify a corpus it never counted.
        """
        with tempfile.TemporaryDirectory() as tmp:
            root = make_repo(Path(tmp), {"docs/real.md": CLEAN_DOC})
            (root / LINTER_REL).write_text(
                "print('nothing parseable here')\n", encoding="utf8"
            )
            proc = run([str(root)], cwd=str(root))
            self.assertEqual(proc.returncode, 1)
            self.assertIn("treat as unscanned", proc.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
