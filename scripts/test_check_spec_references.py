#!/usr/bin/env python3
"""Regression tests for check-spec-references.py.

Row numbers refer to the acceptance matrix in
specs/014-spec-reference-existence-gate/plan.md.

Fixture citations are ASSEMBLED rather than written literally. This suite is
checked by the gate it tests -- there is no test-file exemption, because one of
the two dead pointers that motivated the gate lived in a test_*.sh file -- so a
literal backticked spec path here would make the repository gate fail on its own
test source.
"""

from __future__ import annotations

import importlib.util
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


TICK = chr(96)


def cite(path: str) -> str:
    """A backticked spec citation, built so it never appears literally here."""
    return TICK + path + TICK


SCRIPT = Path(__file__).with_name("check-spec-references.py")
SPEC = importlib.util.spec_from_file_location("check_spec_references", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class SpecReferenceCheckTest(unittest.TestCase):
    def make_repo(self, files: dict[str, str], untracked: dict[str, str] | None = None) -> Path:
        sandbox = Path(self.enterContext(tempfile.TemporaryDirectory()))
        root = sandbox / "repo"
        root.mkdir()
        subprocess.run(["git", "init", "-q", "-b", "main", str(root)], check=True)
        for name, content in files.items():
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")
        subprocess.run(["git", "-C", str(root), "add", "."], check=True)
        for name, content in (untracked or {}).items():
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")
        return root

    def findings(self, root: Path) -> list[tuple[str, int, str]]:
        return MODULE.broken_spec_references(root)

    # Row 1 — a live citation that resolves.
    def test_resolving_reference_passes(self) -> None:
        root = self.make_repo(
            {
                "specs/012-thing/plan.md": "# plan\n",
                "docs/guide.md": "See " + cite("specs/012-thing/plan.md") + " for the shape.\n",
            }
        )
        self.assertEqual(self.findings(root), [])

    # Row 2 — the shape 010 named and could not catch.
    def test_absent_reference_in_markdown_fails(self) -> None:
        root = self.make_repo(
            {"docs/guide.md": "Record it in " + cite("specs/009-absent/validation-log.md") + ".\n"}
        )
        found = self.findings(root)
        self.assertEqual(len(found), 1, found)
        path, line, target = found[0]
        self.assertEqual(path, "docs/guide.md")
        self.assertEqual(line, 1)
        self.assertEqual(target, "specs/009-absent/validation-log.md")

    # Row 3 — the copy every doc linter missed, because it is not Markdown.
    # This is also the shape that killed the first version's test-file
    # exemption: the real instance lived in a test_*.sh file.
    def test_absent_reference_in_shell_script_fails(self) -> None:
        root = self.make_repo(
            {"scripts/probe.sh": "#!/bin/sh\n# recorded in " + cite("specs/009-absent/x.md") + "\n"}
        )
        found = self.findings(root)
        self.assertEqual(len(found), 1, found)
        self.assertEqual(found[0][0], "scripts/probe.sh")
        self.assertEqual(found[0][1], 2)

    # Row 14 — a dead citation in a test-named file is checked like any other.
    def test_test_named_file_is_not_exempt(self) -> None:
        root = self.make_repo(
            {"scripts/test_probe.sh": "#!/bin/sh\n# see " + cite("specs/009-absent/x.md") + "\n"}
        )
        found = self.findings(root)
        self.assertEqual(len(found), 1, found)
        self.assertEqual(found[0][0], "scripts/test_probe.sh")

    # Rows 4-5 — line locators are stripped before resolution.
    def test_line_locator_is_stripped(self) -> None:
        root = self.make_repo(
            {
                "specs/010-thing/plan.md": "# plan\n",
                "docs/a.md": cite("specs/010-thing/plan.md:63") + " says so.\n",
                "docs/b.md": cite("specs/010-thing/plan.md:63-70") + " says so.\n",
            }
        )
        self.assertEqual(self.findings(root), [])

    # Row 6 — directory references resolve, with or without a trailing slash.
    def test_directory_reference_resolves(self) -> None:
        root = self.make_repo(
            {
                "specs/010-thing/plan.md": "# plan\n",
                "docs/a.md": "under "
                + cite("specs/010-thing/")
                + " and "
                + cite("specs/010-thing")
                + "\n",
            }
        )
        self.assertEqual(self.findings(root), [])

    # Row 7 — the unit is the citation, not every mention.
    def test_unbackticked_mention_is_ignored(self) -> None:
        root = self.make_repo({"docs/guide.md": "a validation log under specs/009-absent/ never landed\n"})
        self.assertEqual(self.findings(root), [])

    # Row 8 — corpus is tracked files, matching check-markdown-links.py.
    def test_untracked_file_is_ignored(self) -> None:
        root = self.make_repo(
            {"docs/guide.md": "clean\n"},
            untracked={"scratch.md": cite("specs/009-absent/plan.md") + "\n"},
        )
        self.assertEqual(self.findings(root), [])

    # Row 9 — the prefix is anchored on the separator.
    def test_prefix_is_anchored_on_the_separator(self) -> None:
        root = self.make_repo(
            {"docs/guide.md": cite("specsheet.md") + " and " + cite("specs-old/x.md") + " are not refs\n"}
        )
        self.assertEqual(self.findings(root), [])

    # Row 10 — every finding is reported, not just the first.
    def test_all_findings_are_reported(self) -> None:
        root = self.make_repo(
            {
                "docs/guide.md": (
                    cite("specs/009-absent/a.md")
                    + "\nclean line\n"
                    + cite("specs/009-absent/b.md")
                    + " and "
                    + cite("specs/008-absent/c.md")
                    + "\n"
                )
            }
        )
        found = self.findings(root)
        self.assertEqual(len(found), 3, found)
        self.assertEqual([entry[1] for entry in found], [1, 3, 3])

    # 014 row 12 EXEMPTED an angle-bracket template. 016 deletes that exemption:
    # backticks were overloaded (a real path vs a shape), the gate could not tell
    # them apart from syntax, and the grammar that tried produced five bypasses.
    # A backticked specs/ token is now always a citation.
    def test_angle_bracket_template_is_now_a_citation(self) -> None:
        root = self.make_repo(
            {"docs/guide.md": "record it in " + cite("specs/<NNN>-<slug>/plan.md") + "\n"}
        )
        self.assertEqual(len(self.findings(root)), 1)

    # ...and this is how a template is written instead: name the shape without
    # the prefix and leave the prefix in prose. Backticks are kept because an
    # unbackticked angle bracket is swallowed as an HTML tag when Markdown
    # renders.
    def test_template_without_the_prefix_is_not_a_citation(self) -> None:
        root = self.make_repo(
            {"docs/guide.md": "a `<NNN>-<slug>/plan.md` file under specs/\n"}
        )
        self.assertEqual(self.findings(root), [])

    # A hostile citation must not crash the gate: a target longer than the
    # filesystem's name limit raised ENAMETOOLONG from exists() mid-run.
    def test_absurdly_long_target_fails_closed_without_crashing(self) -> None:
        root = self.make_repo(
            {"docs/guide.md": "see " + cite("specs/" + "x" * 5000 + ".md") + "\n"}
        )
        self.assertEqual(len(self.findings(root)), 1)

    # CommonMark allows any backtick-run delimiter, and this repo writes
    # double-backtick spans in tables: a single-backtick-only matcher would miss
    # a perfectly canonical citation.
    def test_double_backtick_citation_is_checked(self) -> None:
        root = self.make_repo(
            {"docs/guide.md": "see " + TICK * 2 + "specs/009-absent/plan.md" + TICK * 2 + "\n"}
        )
        self.assertEqual(len(self.findings(root)), 1)

    def test_double_backtick_resolving_citation_passes(self) -> None:
        root = self.make_repo(
            {
                "specs/012-thing/plan.md": "# plan\n",
                "docs/guide.md": "see " + TICK * 2 + "specs/012-thing/plan.md" + TICK * 2 + "\n",
            }
        )
        self.assertEqual(self.findings(root), [])

    # A symlink LOOP must produce a finding, not an exception from the gate.
    def test_symlink_loop_target_fails_closed(self) -> None:
        root = self.make_repo({"docs/guide.md": "placeholder\n"})
        specs = root / "specs"
        specs.mkdir(parents=True, exist_ok=True)
        (specs / "a").symlink_to(specs / "b")
        (specs / "b").symlink_to(specs / "a")
        (root / "docs" / "guide.md").write_text(
            "see " + cite("specs/a/plan.md") + "\n", encoding="utf-8"
        )
        subprocess.run(["git", "-C", str(root), "add", "-A"], check=True)
        self.assertEqual(len(self.findings(root)), 1)

    # A citation whose target is an in-repo SYMLINK pointing at a file that
    # really exists outside must be reported: a lexical containment check would
    # confirm it from the runner's filesystem.
    def test_citation_to_symlink_escaping_the_repo_is_rejected(self) -> None:
        root = self.make_repo({"docs/guide.md": "placeholder\n"})
        outside = root.parent / "outside.md"
        outside.write_text("# real file outside the repo\n", encoding="utf-8")
        specs = root / "specs"
        specs.mkdir(parents=True, exist_ok=True)
        (specs / "linked.md").symlink_to(outside)
        (root / "docs" / "guide.md").write_text(
            "see " + cite("specs/linked.md") + "\n", encoding="utf-8"
        )
        subprocess.run(["git", "-C", str(root), "add", "-A"], check=True)
        self.assertEqual(len(self.findings(root)), 1)

    def test_template_inside_a_fenced_block_is_not_a_citation(self) -> None:
        root = self.make_repo(
            {"docs/guide.md": "```\nspecs/<NNN>-<slug>/plan.md\n```\n"}
        )
        self.assertEqual(self.findings(root), [])

    # Row 13 — an abbreviated citation is still a citation and must resolve.
    def test_abbreviated_citation_is_not_exempt(self) -> None:
        root = self.make_repo({"docs/guide.md": "see " + cite("specs/009-…/x.md") + "\n"})
        self.assertEqual(len(self.findings(root)), 1)

    # The template exemption is about a path SHAPE, so it is decided on the
    # RESOLVED path. Deciding it on the raw token let one angle bracket anywhere
    # skip the citation before its base was ever resolved, which turned this
    # mandatory gate into an opt-out: every case below passed the gate.
    def test_angle_bracket_in_fragment_does_not_exempt_a_dead_base(self) -> None:
        root = self.make_repo(
            {"docs/guide.md": "see " + cite("specs/does-not-exist/plan.md#<legacy>") + "\n"}
        )
        self.assertEqual(len(self.findings(root)), 1, "a fragment must not exempt the base")

    def test_trailing_angle_bracket_does_not_exempt(self) -> None:
        root = self.make_repo({"docs/guide.md": "see " + cite("specs/also-missing.md<") + "\n"})
        self.assertEqual(len(self.findings(root)), 1)

    def test_bracketed_note_after_a_filename_does_not_exempt(self) -> None:
        root = self.make_repo(
            {"docs/guide.md": "see " + cite("specs/missing.md<note>") + "\n"}
        )
        self.assertEqual(len(self.findings(root)), 1, "a note is not a path shape")

    def test_angle_bracket_in_line_locator_does_not_exempt(self) -> None:
        root = self.make_repo(
            {"docs/guide.md": "see " + cite("specs/gone/plan.md:<12>") + "\n"}
        )
        self.assertEqual(len(self.findings(root)), 1)

    # ...while the real template shape stays exempt, including with a fragment,
    # so the tightening does not start rejecting the syntax row 12 protects.
    # A real placeholder segment does not license a stray bracket elsewhere:
    # without this the "no bracket survives" clause has no owning case, and a
    # token could pair a valid template segment with an unmatched bracket to opt
    # out of resolution.
    def test_template_segment_plus_stray_bracket_is_not_exempt(self) -> None:
        root = self.make_repo(
            {"docs/guide.md": "see " + cite("specs/<slug>/plan.md<") + "\n"}
        )
        self.assertEqual(len(self.findings(root)), 1)

    # A valid template segment must not license a malformed one elsewhere in the
    # same path: testing "some segment qualifies" and then stripping brackets
    # globally let a sibling segment's validity carry a dead citation through.
    def test_valid_segment_does_not_license_a_malformed_sibling(self) -> None:
        root = self.make_repo(
            {"docs/guide.md": "see " + cite("specs/<slug>/missing.md<note>") + "\n"}
        )
        self.assertEqual(len(self.findings(root)), 1)

    # A placeholder body is a visible identifier: a permissive body accepts
    # zero-width characters, so a segment that reads as empty would qualify.
    def test_zero_width_placeholder_body_does_not_exempt(self) -> None:
        root = self.make_repo(
            {"docs/guide.md": "see " + cite("specs/does-not-exist/<​>/plan.md") + "\n"}
        )
        self.assertEqual(len(self.findings(root)), 1)

    # A template marker says "do not resolve this shape"; it never licenses a
    # path that leaves the repository, so containment is checked first.
    def test_template_cannot_suppress_the_containment_check(self) -> None:
        root = self.make_repo(
            {"docs/guide.md": "see " + cite("specs/<slug>/../../../outside.md") + "\n"}
        )
        self.assertEqual(len(self.findings(root)), 1)

    # `..` cancels the segment before it, so a placeholder can be present in the
    # text while contributing nothing to the effective path. The normalized
    # target stays INSIDE the repo, so containment does not catch it either.
    def test_traversal_cancelling_a_placeholder_is_not_exempt(self) -> None:
        root = self.make_repo(
            {"docs/guide.md": "see " + cite("specs/<slug>/../does-not-exist.md") + "\n"}
        )
        self.assertEqual(len(self.findings(root)), 1)

    # Row 15 — an invalid UTF-8 byte must not make the file unscanned.
    def test_invalid_utf8_file_is_still_scanned(self) -> None:
        root = self.make_repo({"docs/guide.md": "placeholder\n"})
        target = root / "docs" / "binaryish.md"
        target.write_bytes(b"\xff\xfe bad byte then " + cite("specs/009-absent/x.md").encode() + b"\n")
        subprocess.run(["git", "-C", str(root), "add", "."], check=True)
        found = self.findings(root)
        self.assertEqual(len(found), 1, found)
        self.assertEqual(found[0][0], "docs/binaryish.md")

    # Row 16 — a citation that escapes the repository is rejected.
    #
    # The escape target must EXIST outside the repo, or the row is falsely
    # green: a traversal to somewhere that happens not to exist is rejected by
    # the ordinary existence check and never reaches the containment logic.
    # The first version of this row used a specs/../../../../etc/passwd path,
    # resolves to nothing at a temp-dir depth — the mutation walk caught it by
    # dropping the containment check and flipping nothing.
    def test_traversal_outside_the_repo_is_rejected(self) -> None:
        root = self.make_repo(
            {
                "specs/012-thing/plan.md": "# plan\n",
                "docs/guide.md": "see " + cite("specs/../../outside.md") + "\n",
            }
        )
        (root.parent / "outside.md").write_text("real file, outside the repo\n", encoding="utf-8")
        self.assertTrue((root / "specs" / ".." / ".." / "outside.md").exists())
        found = self.findings(root)
        self.assertEqual(len(found), 1, found)
        self.assertEqual(found[0][2], "specs/../../outside.md")

    # Row 17 — an in-repo relative path that stays inside still resolves.
    def test_in_repo_relative_traversal_still_resolves(self) -> None:
        root = self.make_repo(
            {
                "specs/012-thing/plan.md": "# plan\n",
                "docs/a.md": "see " + cite("specs/012-thing/../012-thing/plan.md") + "\n",
            }
        )
        self.assertEqual(self.findings(root), [])

    # Row 18 — path-plus-anchor is ordinary syntax; the base must still exist.
    def test_fragment_is_stripped_when_base_exists(self) -> None:
        root = self.make_repo(
            {
                "specs/012-thing/plan.md": "# plan\n",
                "docs/a.md": "see " + cite("specs/012-thing/plan.md#acceptance-matrix") + "\n",
            }
        )
        self.assertEqual(self.findings(root), [])

    # Row 19 — a fragment does not rescue a missing base path.
    def test_fragment_does_not_rescue_a_missing_base(self) -> None:
        root = self.make_repo({"docs/a.md": "see " + cite("specs/009-absent/plan.md#x") + "\n"})
        self.assertEqual(len(self.findings(root)), 1)

    # Row 20 — stripping the fragment must not eat the filename with it.
    # Without this row, a mutation that strips `/plan.md#anchor` wholesale
    # flips nothing: rows 18-19 both still pass, because 18's parent directory
    # exists and 19's does not. The mutation walk found that gap.
    def test_fragment_stripping_does_not_eat_the_filename(self) -> None:
        root = self.make_repo(
            {
                "specs/012-thing/plan.md": "# plan\n",
                "docs/a.md": "see " + cite("specs/012-thing/absent.md#anchor") + "\n",
            }
        )
        found = self.findings(root)
        self.assertEqual(len(found), 1, found)

    # Row 21 — a tracked symlink is not followed.
    def test_tracked_symlink_is_not_followed(self) -> None:
        root = self.make_repo({"docs/guide.md": "clean\n"})
        outside = root.parent / "outside.md"
        outside.write_text("see " + cite("specs/009-absent/x.md") + "\n", encoding="utf-8")
        link = root / "docs" / "link.md"
        link.symlink_to(outside)
        subprocess.run(["git", "-C", str(root), "add", "-A"], check=True)
        self.assertTrue(link.is_symlink())
        self.assertEqual(self.findings(root), [])

    # Row 22 — a non-ASCII tracked filename must not crash the gate under a
    # non-UTF-8 locale. `text=True` decodes the whole ls-files stream with the
    # LOCALE codec, so a C-locale CI runner would raise before the NUL split;
    # splitting bytes first and decoding each entry as UTF-8 does not.
    def test_non_ascii_filename_survives_a_c_locale(self) -> None:
        root = self.make_repo({"docs/clean.md": "ok\n"})
        (root / "docs" / "\u65e5\u672c\u8a9e.md").write_text("ok\n", encoding="utf-8")
        subprocess.run(["git", "-C", str(root), "add", "-A"], check=True)
        env = dict(os.environ, LC_ALL="C", LANG="C", PYTHONUTF8="0", PYTHONCOERCECLOCALE="0")
        result = subprocess.run(
            [sys.executable, str(SCRIPT), str(root)], capture_output=True, text=True, env=env
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_main_exit_codes(self) -> None:
        clean = self.make_repo(
            {
                "specs/012-thing/plan.md": "# plan\n",
                "docs/a.md": cite("specs/012-thing/plan.md") + "\n",
            }
        )
        self.assertEqual(MODULE.main([str(clean)]), 0)
        dirty = self.make_repo({"docs/a.md": cite("specs/009-absent/plan.md") + "\n"})
        self.assertEqual(MODULE.main([str(dirty)]), 1)


class InvalidUtf8FilenameTest(unittest.TestCase):
    """git tracks raw bytes and Linux allows a filename that is not valid UTF-8.

    A strict decode made this checker raise before scanning anything, so one such
    tracked file hard-failed the whole gate on the ubuntu CI runner. The name
    cannot be created on macOS (APFS rejects it), so the enumeration is driven
    directly rather than through the filesystem.
    """

    def test_invalid_utf8_tracked_name_does_not_crash(self) -> None:
        class FakeRun:
            stdout = b"README.md\x00bad\xff-name.md\x00"
            returncode = 0

        real = MODULE.subprocess.run
        MODULE.subprocess.run = lambda *a, **k: FakeRun()
        try:
            entries = MODULE.tracked_files(Path("."))
        finally:
            MODULE.subprocess.run = real
        self.assertEqual(len(entries), 2, entries)
        # count alone would pass for a LOSSY decode; the point is that the
        # name round-trips back to the original bytes so the file can be opened.
        import os as _os
        self.assertEqual(_os.fsencode(_os.fspath(entries[1])).split(b"/")[-1], b"bad\xff-name.md")


class DisplayEscapingTest(unittest.TestCase):
    """The display encoding must be reversible and must not eat legitimate text."""

    def test_distinct_names_do_not_collide(self) -> None:
        # A real newline and a filename containing a literal backslash-n are
        # different tracked paths; if both render the same, a finding is
        # misattributable.
        self.assertNotEqual(MODULE.display("a\nb.md"), MODULE.display("a\\nb.md"))

    def test_control_characters_are_escaped(self) -> None:
        for raw in ("a\nb.md", "a\tb.md", "a\x1b[31mb.md", "a\rb.md"):
            rendered = MODULE.display(raw)
            self.assertNotIn("\n", rendered)
            self.assertNotIn("\t", rendered)
            self.assertNotIn("\x1b", rendered)
            self.assertNotIn("\r", rendered)

    def test_printable_non_ascii_is_preserved(self) -> None:
        # Escaping must not mangle an ordinary non-English filename.
        self.assertEqual(MODULE.display("\u65e5\u672c\u8a9e.md"), "\u65e5\u672c\u8a9e.md")


class UnreadableFileDiagnosticTest(unittest.TestCase):
    """The unreadable-file diagnostic interpolates the same untrusted name."""

    def test_unreadable_name_is_escaped(self) -> None:
        sandbox = Path(self.enterContext(tempfile.TemporaryDirectory()))
        root = sandbox / "repo"
        (root / "docs").mkdir(parents=True)
        subprocess.run(["git", "init", "-q", "-b", "main", str(root)], check=True)
        target = root / "docs" / "unre\nadable.md"
        target.write_text("x\n", encoding="utf-8")
        subprocess.run(["git", "-C", str(root), "add", "-A"], check=True)
        target.chmod(0o000)
        self.addCleanup(target.chmod, 0o644)
        result = subprocess.run(
            [sys.executable, str(SCRIPT), str(root)], capture_output=True, text=True
        )
        unreadable_lines = [
            line for line in result.stderr.splitlines() if "could not be read" in line
        ]
        if not unreadable_lines:
            self.skipTest("file stayed readable (running with elevated privileges)")
        self.assertEqual(len(unreadable_lines), 1, result.stderr)
        # STARTSWITH, not "in": the OSError message repr()s the path itself, so a
        # substring check passes even when the diagnostic's own name field was
        # split across lines. The escaped name must be the line's first field.
        self.assertTrue(
            unreadable_lines[0].startswith("docs/unre\\nadable.md:"),
            unreadable_lines[0],
        )


class ControlCharacterDiagnosticTest(unittest.TestCase):
    """A filename may legally contain a newline; a finding must stay one line."""

    def test_newline_in_filename_does_not_split_the_diagnostic(self) -> None:
        sandbox = Path(self.enterContext(tempfile.TemporaryDirectory()))
        root = sandbox / "repo"
        (root / "docs").mkdir(parents=True)
        subprocess.run(["git", "init", "-q", "-b", "main", str(root)], check=True)
        (root / "docs" / "inno\ncent.md").write_text(
            "see " + cite("specs/009-absent/plan.md") + "\n", encoding="utf-8"
        )
        subprocess.run(["git", "-C", str(root), "add", "-A"], check=True)
        result = subprocess.run(
            [sys.executable, str(SCRIPT), str(root)], capture_output=True, text=True
        )
        self.assertEqual(result.returncode, 1, result.stderr)
        finding_lines = [
            line for line in result.stderr.splitlines() if "does not resolve" in line
        ]
        self.assertEqual(len(finding_lines), 1, result.stderr)
        self.assertIn("inno\\ncent.md", finding_lines[0])
        self.assertNotIn("\n", finding_lines[0].replace("\\n", ""))


if __name__ == "__main__":
    unittest.main()
