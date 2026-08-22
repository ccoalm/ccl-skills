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
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import yaml


TICK = chr(96)


def cite(path: str) -> str:
    """A backticked spec citation, built so it never appears literally here."""
    return TICK + path + TICK


def workflow_entry_violation(workflow: str) -> str | None:
    """Return why CI entry can skip the mandatory gate, if it can."""
    try:
        document = yaml.load(workflow, Loader=yaml.BaseLoader)
    except yaml.YAMLError as exc:
        return f"CI workflow YAML is invalid: {exc}"
    if not isinstance(document, dict) or "on" not in document:
        return "CI workflow has no top-level on trigger"
    triggers = document["on"]
    if isinstance(triggers, list):
        trigger_map = {str(event): {} for event in triggers}
    elif isinstance(triggers, dict):
        trigger_map = triggers
    else:
        return "CI workflow on trigger must be a list or mapping"

    def values(raw) -> set[str]:
        if isinstance(raw, list):
            return {str(item) for item in raw}
        return {str(raw)}

    for event in ("pull_request", "push"):
        if event not in trigger_map:
            return f"CI workflow is missing the {event} trigger"
        raw_config = trigger_map[event]
        if raw_config in (None, "", "null", "Null", "NULL", "~"):
            config = {}
        elif isinstance(raw_config, dict):
            config = raw_config
        else:
            return f"CI workflow {event} trigger has unsupported configuration"
        for path_key in ("paths", "paths-ignore"):
            if path_key in config:
                return f"CI workflow {event} trigger may not use {path_key}"
        if "branches" in config and "main" not in values(config["branches"]):
            return f"CI workflow {event} branches must include main"
        if "branches-ignore" in config and "main" in values(
            config["branches-ignore"]
        ):
            return f"CI workflow {event} branches-ignore may not exclude main"
        if event == "pull_request" and "types" in config:
            required_types = {"opened", "synchronize"}
            if not required_types.issubset(values(config["types"])):
                return "CI workflow pull_request types must include opened and synchronize"
    return None


def step_runs_exact_command(step: dict, command: str) -> bool:
    """True only when the whole run step is the required command."""
    run = step.get("run")
    return isinstance(run, str) and run.strip() == command


def dependency_wiring_violation(
    workflow: str,
    command: str,
    job_names: tuple[str, ...] = ("repository-gates", "regression-heavy"),
) -> str | None:
    """Return why a required CI job may not execute the dependency command."""
    try:
        document = yaml.load(workflow, Loader=yaml.BaseLoader)
    except yaml.YAMLError as exc:
        return f"CI workflow YAML is invalid: {exc}"
    if not isinstance(document, dict):
        return "CI workflow must be a mapping"

    root_defaults = document.get("defaults") or {}
    if not isinstance(root_defaults, dict):
        return "CI workflow defaults must be a mapping"
    root_run_defaults = root_defaults.get("run") or {}
    if not isinstance(root_run_defaults, dict):
        return "CI workflow run defaults must be a mapping"
    if "working-directory" in root_run_defaults:
        return "CI workflow defaults may not set a run working-directory"

    jobs = document.get("jobs")
    if not isinstance(jobs, dict):
        return "CI workflow has no jobs mapping"
    for job_name in job_names:
        job = jobs.get(job_name)
        if not isinstance(job, dict):
            return f"CI workflow has no {job_name} job"
        for key in ("if", "continue-on-error", "needs"):
            if key in job:
                return f"{job_name} may not set job-level {key}"
        job_defaults = job.get("defaults") or {}
        if not isinstance(job_defaults, dict):
            return f"{job_name} defaults must be a mapping"
        job_run_defaults = job_defaults.get("run") or {}
        if not isinstance(job_run_defaults, dict):
            return f"{job_name} run defaults must be a mapping"
        if "working-directory" in job_run_defaults:
            return f"{job_name} defaults may not set a run working-directory"

        steps = job.get("steps")
        if not isinstance(steps, list):
            return f"{job_name} has no steps list"
        checkout_matches = [
            (index, step)
            for index, step in enumerate(steps)
            if isinstance(step, dict)
            and str(step.get("uses", "")).startswith("actions/checkout@")
        ]
        if len(checkout_matches) != 1:
            return f"{job_name} must have exactly one actions/checkout step"
        checkout_index, checkout_step = checkout_matches[0]
        for key in ("if", "continue-on-error"):
            if key in checkout_step:
                return f"{job_name} checkout may not set {key}"
        checkout_options = checkout_step.get("with") or {}
        if not isinstance(checkout_options, dict):
            return f"{job_name} checkout options must be a mapping"
        for key in ("path", "sparse-checkout"):
            if key in checkout_options:
                return f"{job_name} checkout may not set {key}"

        install_matches = [
            (index, step)
            for index, step in enumerate(steps)
            if isinstance(step, dict) and step_runs_exact_command(step, command)
        ]
        if len(install_matches) != 1:
            return f"{job_name} must execute exactly one {command} step"
        install_index, install_step = install_matches[0]
        if checkout_index >= install_index:
            return f"{job_name} must checkout before installing test dependencies"
        for key in ("working-directory", "if", "continue-on-error"):
            if key in install_step:
                return f"{job_name} dependency install may not set {key}"
    return None


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


class LedgerCitationWaiverTest(unittest.TestCase):
    """Row 025 — a citation frozen in an append-only ledger line.

    Every case here exists to show the waiver is bound by IDENTITY, not by
    shape. The token below is a glob on purpose: if any of these started
    passing because the token looks like a template, the deleted exemption
    would be back.
    """

    LEDGER = "ledger/register.md"
    FROZEN = "specs/090-absent/evidence/AGENTS.md"
    OTHER_DEAD = "specs/091-absent/plan.md"

    def make_repo(self, files: dict[str, str]) -> Path:
        sandbox = Path(self.enterContext(tempfile.TemporaryDirectory()))
        root = sandbox / "repo"
        root.mkdir()
        subprocess.run(["git", "init", "-q", "-b", "main", str(root)], check=True)
        for name, content in files.items():
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")
        subprocess.run(["git", "-C", str(root), "add", "."], check=True)
        return root

    def waivers(
        self,
        line: str,
        token: str | None = None,
        path: str | None = None,
        number: int = 1,
        terminator: str = "\n",
    ) -> dict:
        """A pin is (line number, digest of the line AS STORED).

        `line` is passed without its terminator for readability; the digest is
        taken over `line + terminator`, which is what the checker hashes.
        """
        return {
            (path or self.LEDGER, token or self.FROZEN): (
                "frozen in an append-only row",
                ((number, MODULE.line_digest(line + terminator)),),
            )
        }

    def run_scan(self, root: Path, waivers: dict):
        waived: list[tuple[str, int, str, str]] = []
        stale: list[tuple[str, str, str]] = []
        findings = MODULE.broken_spec_references(root, None, waived, stale, waivers)
        return findings, waived, stale

    # Row 2 — the pinned line, the pinned token, the pinned file.
    def test_pinned_citation_is_waived_and_reported(self) -> None:
        line = "row: not a frozen measurement under " + cite(self.FROZEN) + " here"
        root = self.make_repo({self.LEDGER: line + "\n"})
        findings, waived, stale = self.run_scan(root, self.waivers(line))
        self.assertEqual(findings, [])
        self.assertEqual(stale, [])
        self.assertEqual(len(waived), 1, waived)
        self.assertEqual(waived[0][0], self.LEDGER)
        self.assertEqual(waived[0][1], 1)
        self.assertEqual(waived[0][2], self.FROZEN)

    # Row 3 — the same token in the same file, one line whose bytes differ.
    def test_waiver_does_not_bleed_to_another_line(self) -> None:
        pinned = "row one: " + cite(self.FROZEN) + " frozen"
        other = "row two: " + cite(self.FROZEN) + " appended later"
        root = self.make_repo({self.LEDGER: pinned + "\n" + other + "\n"})
        findings, waived, _ = self.run_scan(root, self.waivers(pinned))
        self.assertEqual(len(waived), 1, waived)
        self.assertEqual(len(findings), 1, findings)
        self.assertEqual(findings[0][1], 2)
        self.assertEqual(findings[0][2], self.FROZEN)

    # An identical COPY of the pinned row is a row nobody reviewed. Content
    # alone identifies a line shape, not an occurrence, so the pin carries the
    # line number too and only that occurrence is waived. Independent review
    # found this by copying the frozen row; without the number both copies were
    # waived and the duplicate rode in under a green gate.
    def test_verbatim_duplicate_of_the_pinned_line_still_fails(self) -> None:
        line = "row: " + cite(self.FROZEN) + " frozen"
        root = self.make_repo({self.LEDGER: line + "\n" + line + "\n"})
        findings, waived, stale = self.run_scan(root, self.waivers(line, number=1))
        self.assertEqual(stale, [])
        self.assertEqual(len(waived), 1, waived)
        self.assertEqual(waived[0][1], 1)
        self.assertEqual(len(findings), 1, findings)
        self.assertEqual(findings[0][1], 2)

    # One waiver is spent by ONE citation. The predicate runs per regex match,
    # so a line carrying the same dead token twice used to get both suppressed
    # by the single reviewed waiver -- a second unresolved citation riding in on
    # the first one's approval. Independent review found this after the line
    # number and terminator were already pinned.
    def test_waiver_is_spent_by_one_citation_on_the_pinned_line(self) -> None:
        line = "row: " + cite(self.FROZEN) + " and again " + cite(self.FROZEN)
        root = self.make_repo({self.LEDGER: line + "\n"})
        findings, waived, stale = self.run_scan(root, self.waivers(line, number=1))
        self.assertEqual(stale, [])
        self.assertEqual(len(waived), 1, waived)
        self.assertEqual(len(findings), 1, findings)
        self.assertEqual(findings[0][2], self.FROZEN)

    # A waiver whose TOKEN is mistyped or obsolete covers nothing. The digest
    # proves the line, so the pin still matches and staleness would never fire;
    # only requiring the token proves the entry still has a subject. The
    # adversarial lane found this hiding behind the line-and-digest pin.
    def test_waiver_naming_a_token_absent_from_the_pinned_line_is_stale(self) -> None:
        line = "row: " + cite(self.FROZEN) + " frozen"
        root = self.make_repo({self.LEDGER: line + "\n"})
        typo = self.waivers(line, token="specs/090-absent/evidence/AGENT.md", number=1)
        findings, waived, stale = self.run_scan(root, typo)
        self.assertEqual(waived, [])
        self.assertEqual(len(stale), 1, stale)
        self.assertEqual(len(findings), 1, findings)
        self.assertEqual(findings[0][2], self.FROZEN)

    # Sharper than the typo case: the waiver's token IS present in the line's
    # raw text, but only as part of a longer citation. A substring test would
    # mark the pin seen and the entry would sit there covering nothing; the
    # tokens are compared as parsed citations instead.
    def test_waiver_token_that_is_only_a_substring_of_another_citation_is_stale(self) -> None:
        longer = self.FROZEN + ".bak"
        line = "row: " + cite(longer) + " frozen"
        root = self.make_repo({self.LEDGER: line + "\n"})
        findings, waived, stale = self.run_scan(root, self.waivers(line, number=1))
        self.assertEqual(waived, [])
        self.assertEqual(len(stale), 1, stale)
        self.assertEqual(len(findings), 1, findings)
        self.assertEqual(findings[0][2], longer)

    # Same hole from the prose side: the token appears on the pinned line but
    # not inside backticks, so it is not a citation and cannot be the subject.
    def test_waiver_token_only_in_unbackticked_prose_is_stale(self) -> None:
        line = "row: we deliberately do not cite " + self.FROZEN + " here"
        root = self.make_repo({self.LEDGER: line + "\n"})
        findings, waived, stale = self.run_scan(root, self.waivers(line, number=1))
        self.assertEqual(waived, [])
        self.assertEqual(findings, [])
        self.assertEqual(len(stale), 1, stale)

    # The pinned row at a DIFFERENT number is not the pinned occurrence: it is
    # not waived, and the pin that now matches nothing goes stale.
    def test_pinned_row_moved_to_another_line_is_not_waived(self) -> None:
        line = "row: " + cite(self.FROZEN) + " frozen"
        root = self.make_repo({self.LEDGER: "a preceding note\n" + line + "\n"})
        findings, waived, stale = self.run_scan(root, self.waivers(line, number=1))
        self.assertEqual(waived, [])
        self.assertEqual(len(findings), 1, findings)
        self.assertEqual(len(stale), 1, stale)

    # splitlines() discards the terminator, so hashing the STRIPPED line let an
    # LF-to-CRLF rewrite change the stored bytes while the pin kept matching.
    # The digest is taken over the line as stored.
    def test_crlf_terminator_change_breaks_the_waiver(self) -> None:
        line = "row: " + cite(self.FROZEN) + " frozen"
        root = self.make_repo({self.LEDGER: line + "\r\n"})
        findings, waived, stale = self.run_scan(
            root, self.waivers(line, number=1, terminator="\n")
        )
        self.assertEqual(waived, [])
        self.assertEqual(len(findings), 1, findings)
        self.assertEqual(len(stale), 1, stale)

    # Same defect from the other side: dropping the file's final newline also
    # changes the stored bytes of the pinned row.
    def test_missing_final_newline_breaks_the_waiver(self) -> None:
        line = "row: " + cite(self.FROZEN) + " frozen"
        root = self.make_repo({self.LEDGER: line})
        findings, waived, stale = self.run_scan(
            root, self.waivers(line, number=1, terminator="\n")
        )
        self.assertEqual(waived, [])
        self.assertEqual(len(findings), 1, findings)
        self.assertEqual(len(stale), 1, stale)

    # Row 3 again, at one byte of distance: a reflow is not the pinned row.
    def test_one_byte_change_to_the_pinned_line_stops_the_waiver(self) -> None:
        pinned = "row: " + cite(self.FROZEN) + " frozen"
        root = self.make_repo({self.LEDGER: pinned + " \n"})
        findings, waived, stale = self.run_scan(root, self.waivers(pinned))
        self.assertEqual(waived, [])
        self.assertEqual(len(findings), 1, findings)
        self.assertEqual(len(stale), 1, stale)

    # Row 4 — the identical line, in a file the waiver does not name.
    def test_waiver_does_not_bleed_to_another_file(self) -> None:
        line = "row: " + cite(self.FROZEN) + " frozen"
        root = self.make_repo({self.LEDGER: line + "\n", "docs/copy.md": line + "\n"})
        findings, waived, _ = self.run_scan(root, self.waivers(line))
        self.assertEqual(len(waived), 1, waived)
        self.assertEqual(len(findings), 1, findings)
        self.assertEqual(findings[0][0], "docs/copy.md")

    # Row 5 — the waiver is token-bound, so it cannot cover a second dead
    # citation that happens to sit on the very line it waives.
    def test_waiver_is_token_bound_on_the_pinned_line(self) -> None:
        line = "row: " + cite(self.FROZEN) + " and also " + cite(self.OTHER_DEAD)
        root = self.make_repo({self.LEDGER: line + "\n"})
        findings, waived, _ = self.run_scan(root, self.waivers(line))
        self.assertEqual(len(waived), 1, waived)
        self.assertEqual(waived[0][2], self.FROZEN)
        self.assertEqual(len(findings), 1, findings)
        self.assertEqual(findings[0][2], self.OTHER_DEAD)

    # Row 6 — a neighbouring glob spelling has no standing at all.
    def test_other_template_spellings_still_fail(self) -> None:
        line = "row: " + cite(self.FROZEN) + " frozen"
        neighbours = "a " + cite("specs/*/plan.md") + " b " + cite("specs/*/evidence/x.md")
        root = self.make_repo({self.LEDGER: line + "\n" + neighbours + "\n"})
        findings, _, _ = self.run_scan(root, self.waivers(line))
        self.assertEqual(
            sorted(target for _, _, target in findings),
            ["specs/*/evidence/x.md", "specs/*/plan.md"],
            findings,
        )

    # Row 7 — a locator makes a different token, so it inherits nothing. The
    # pin is of THIS line, so only the key mismatch can be doing the work.
    def test_waived_token_with_locator_still_fails(self) -> None:
        line = "row: " + cite(self.FROZEN + ":12") + " frozen"
        root = self.make_repo({self.LEDGER: line + "\n"})
        findings, waived, stale = self.run_scan(root, self.waivers(line))
        self.assertEqual(waived, [])
        self.assertEqual(len(findings), 1, findings)
        self.assertEqual(findings[0][2], self.FROZEN + ":12")
        # And the waiver is STALE, not merely inert: the token it names is not a
        # citation on that line, so the entry covers nothing and has to be
        # re-reviewed rather than sit there looking healthy.
        self.assertEqual(len(stale), 1, stale)

    # A waiver covers non-existence, never a citation that leaves the checkout.
    def test_waiver_never_covers_a_containment_escape(self) -> None:
        escaping = "specs/../../outside/AGENTS.md"
        line = "row: " + cite(escaping) + " frozen"
        root = self.make_repo({self.LEDGER: line + "\n"})
        findings, waived, stale = self.run_scan(
            root, self.waivers(line, token=escaping)
        )
        self.assertEqual(waived, [])
        self.assertEqual(len(findings), 1, findings)
        self.assertEqual(findings[0][2], escaping)
        self.assertEqual(len(stale), 1, stale)

    # Application and liveness call this same predicate. Pin the empty domain
    # directly rather than inventing a second citation grammar in the test.
    def test_empty_resolved_target_is_not_waivable(self) -> None:
        self.assertEqual(MODULE.resolve_target("/"), "")
        self.assertFalse(MODULE.waiver_can_apply_to_target("", escaped=False))
        self.assertFalse(
            MODULE.waiver_can_apply_to_target(self.FROZEN, escaped=True)
        )
        self.assertTrue(
            MODULE.waiver_can_apply_to_target(self.FROZEN, escaped=False)
        )

    # Row 8 — the waived file is present and the pinned row is gone. On an
    # append-only ledger that means it was edited or deleted; a waiver is never
    # left silently covering nothing.
    def test_stale_pinned_digest_fails_closed(self) -> None:
        pinned = "the row as it was reviewed"
        root = self.make_repo({self.LEDGER: "the row after somebody edited it\n"})
        findings, waived, stale = self.run_scan(root, self.waivers(pinned))
        self.assertEqual(findings, [])
        self.assertEqual(waived, [])
        self.assertEqual(len(stale), 1, stale)
        self.assertEqual(stale[0][0], self.LEDGER)

    # Row 9 — the same waiver against a corpus that has no such file is inert.
    # Without this the table would red every unrelated repository the checker
    # is pointed at, including this suite's own fixtures.
    def test_waiver_for_absent_file_is_inert(self) -> None:
        root = self.make_repo({"docs/guide.md": "nothing to see\n"})
        findings, waived, stale = self.run_scan(root, self.waivers("some pinned row"))
        self.assertEqual(findings, [])
        self.assertEqual(waived, [])
        self.assertEqual(stale, [])

    # A stale pin exits non-zero through the CLI, with its own reason code, so
    # it can never be mistaken for the passing run it would otherwise resemble.
    def test_stale_pin_is_a_cli_failure(self) -> None:
        root = self.make_repo({"a.md": "x\n"})
        probe = root / "probe.py"
        probe.write_text(
            "import importlib.util, sys\n"
            "spec = importlib.util.spec_from_file_location('c', %r)\n"
            "m = importlib.util.module_from_spec(spec)\n"
            "spec.loader.exec_module(m)\n"
            "m.LEDGER_CITATION_WAIVERS = {('a.md', 'specs/x/y.md'): ('r', ((1, 'deadbeef'),))}\n"
            "sys.exit(m.main([%r]))\n" % (str(SCRIPT), str(root)),
            encoding="utf-8",
        )
        result = subprocess.run(
            [sys.executable, str(probe)], capture_output=True, text=True
        )
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("spec_reference_waiver_stale", result.stderr)
        self.assertNotIn("spec_reference_check_ok", result.stdout)


class ProductionWaiverTableTest(unittest.TestCase):
    """Row 1 — the shipped table, against the repository it was written for.

    This is the case that keeps the ledger row honest: the pin is of the whole
    line, so an edit, a reflow, or a deletion of the waived row turns this RED
    without anyone having to notice.
    """

    REPO = SCRIPT.parent.parent

    def test_shipped_waivers_all_apply_to_this_repository(self) -> None:
        waived: list[tuple[str, int, str, str]] = []
        stale: list[tuple[str, str, str]] = []
        findings = MODULE.broken_spec_references(self.REPO, None, waived, stale)
        self.assertEqual(stale, [], "a shipped waiver pin no longer matches its row")
        self.assertEqual(findings, [], findings)
        # Every shipped entry is exercised: an entry covering nothing is a
        # waiver nobody can review the need for.
        self.assertEqual(
            sorted({(path, token) for path, _, token, _ in waived}),
            sorted(MODULE.LEDGER_CITATION_WAIVERS),
        )

    def test_shipped_waiver_is_printed_by_the_cli(self) -> None:
        result = subprocess.run(
            [sys.executable, str(SCRIPT), str(self.REPO)],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        printed = [
            line for line in result.stdout.splitlines()
            if line.startswith("spec_citation_waived:")
        ]
        self.assertEqual(len(printed), len(MODULE.LEDGER_CITATION_WAIVERS), result.stdout)


class WaivedPathPresenceTest(unittest.TestCase):
    """A shipped waiver may not be voided by REMOVING its file.

    The adversarial lane found this: `git ls-files` stops yielding a deleted or
    untracked path, so the path was never scanned, its pins were never checked,
    and the gate exited 0 with the waiver covering nothing -- the guard voided by
    omission rather than satisfied. Reproduced against the shipped table before
    the fix: deleted and untracked both gave findings=0 waived=0 stale=0, exit 0.

    The two conditions that make absence an error are checked separately below, so
    neither can be dropped without a case going RED.
    """

    def clone_candidate(self, mutate) -> Path:
        """A synthetic repo carrying a COPY of this checker, so the copy's own
        parent-of-parent is that repo and the shipped table is judged against it.

        The waived ledger and the `specs/` tree it cites are both copied, so the
        control is a faithful mini-candidate that passes cleanly. Copying only the
        ledger left its OTHER citations unresolvable, and the resulting findings
        made the mutants' non-zero exit unattributable -- caught by the control.
        """
        sandbox = Path(self.enterContext(tempfile.TemporaryDirectory()))
        root = sandbox / "repo"
        source_root = SCRIPT.parent.parent
        waived_path = next(iter(MODULE.LEDGER_CITATION_WAIVERS))[0]
        (root / "scripts").mkdir(parents=True)
        (root / "scripts" / SCRIPT.name).write_bytes(SCRIPT.read_bytes())
        target = root / waived_path
        target.parent.mkdir(parents=True, exist_ok=True)
        source_target = source_root / waived_path
        if source_target.is_symlink():
            target.symlink_to(os.readlink(source_target))
        elif source_target.is_file():
            target.write_bytes(source_target.read_bytes())
        tracked_specs = subprocess.run(
            ["git", "-C", str(source_root), "ls-files", "-z", "--", "specs"],
            check=True,
            stdout=subprocess.PIPE,
        ).stdout.split(b"\0")
        for raw_name in tracked_specs:
            if not raw_name:
                continue
            relative = Path(os.fsdecode(raw_name))
            source = source_root / relative
            # `git ls-files` also reports tracked worktree deletions. Preserve
            # that candidate state as absence in the synthetic repository so
            # the copied checker can diagnose it instead of the fixture raising
            # FileNotFoundError before the control runs.
            if not source.exists() and not source.is_symlink():
                continue
            destination = root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            if source.is_symlink():
                destination.symlink_to(os.readlink(source))
            else:
                destination.write_bytes(source.read_bytes())
        subprocess.run(["git", "init", "-q", "-b", "main", str(root)], check=True)
        mutate(root, waived_path)
        subprocess.run(["git", "-C", str(root), "add", "-A"], check=True)
        return root

    def run_cli(self, root: Path) -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, str(root / "scripts" / SCRIPT.name), str(root)],
            capture_output=True,
            text=True,
        )

    def test_control_waived_path_present_still_passes(self) -> None:
        root = self.clone_candidate(lambda root, path: None)
        result = self.run_cli(root)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("spec_citation_waived:", result.stdout)
        self.assertIn("spec_reference_check_ok", result.stdout)

    def test_deleting_the_waived_path_is_stale_and_red(self) -> None:
        root = self.clone_candidate(lambda root, path: (root / path).unlink(missing_ok=True))
        result = self.run_cli(root)
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("spec_reference_waiver_stale", result.stderr)
        self.assertIn("absent-from-tracked-corpus", result.stderr)

    def test_untracking_the_waived_path_is_stale_and_red(self) -> None:
        def untrack(root: Path, path: str) -> None:
            (root / ".gitignore").write_text(path + "\n", encoding="utf-8")

        root = self.clone_candidate(untrack)
        result = self.run_cli(root)
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("spec_reference_waiver_stale", result.stderr)
        self.assertIn("absent-from-tracked-corpus", result.stderr)

    def test_tracked_symlink_is_reported_as_present_but_unscanned(self) -> None:
        def replace_with_symlink(root: Path, path: str) -> None:
            target = root / path
            target.unlink(missing_ok=True)
            target.symlink_to("missing-ledger-target")

        root = self.clone_candidate(replace_with_symlink)
        result = self.run_cli(root)
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("spec_reference_waiver_stale", result.stderr)
        self.assertIn("present-but-unscanned", result.stderr)
        self.assertNotIn("absent-from-tracked-corpus", result.stderr)

    def test_explicit_shipped_table_still_requires_its_waived_path(self) -> None:
        root = self.clone_candidate(lambda root, path: (root / path).unlink(missing_ok=True))
        script = root / "scripts" / SCRIPT.name
        spec = importlib.util.spec_from_file_location("copied_checker", script)
        copied = importlib.util.module_from_spec(spec)
        assert spec.loader is not None
        spec.loader.exec_module(copied)

        near_copy = dict(copied.LEDGER_CITATION_WAIVERS)
        shipped_key = next(iter(near_copy))
        shipped_reason, shipped_pins = near_copy[shipped_key]
        near_copy[shipped_key] = (shipped_reason + " caller-local change", shipped_pins)
        for table in (
            copied.LEDGER_CITATION_WAIVERS,
            dict(copied.LEDGER_CITATION_WAIVERS),
            near_copy,
        ):
            waived: list[tuple[str, int, str, str]] = []
            stale: list[tuple[str, str, str]] = []
            findings = copied.broken_spec_references(
                root, None, waived, stale, table
            )
            self.assertEqual(findings, [])
            self.assertEqual(waived, [])
            self.assertTrue(
                any(pin.endswith("absent-from-tracked-corpus") for _, _, pin in stale),
                f"explicit shipped table {table!r} covered nothing without going stale",
            )

    # Compatibility positive 1: a FOREIGN corpus. This checker, running from its
    # own repository, pointed at an unrelated repository that has no such file,
    # must stay inert -- which is what every other fixture in this suite relies on.
    def test_foreign_corpus_without_the_waived_path_stays_inert(self) -> None:
        sandbox = Path(self.enterContext(tempfile.TemporaryDirectory()))
        root = sandbox / "foreign"
        root.mkdir()
        (root / "docs").mkdir()
        (root / "docs" / "guide.md").write_text("nothing to see\n", encoding="utf-8")
        subprocess.run(["git", "init", "-q", "-b", "main", str(root)], check=True)
        subprocess.run(["git", "-C", str(root), "add", "-A"], check=True)
        result = subprocess.run(
            [sys.executable, str(SCRIPT), str(root)], capture_output=True, text=True
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("spec_reference_check_ok", result.stdout)

    def test_repository_gate_invocations_scan_the_owning_root(self) -> None:
        command = "python3 scripts/check-spec-references.py ."
        repository = SCRIPT.parent.parent.resolve()
        self.assertEqual(MODULE.owning_repository_root(), repository)
        makefile = (repository / "Makefile").read_text()
        make_lines = makefile.splitlines()
        # `test:` may be a pure-prerequisite aggregate (specs/035): the gate
        # invocation then lives in a prerequisite target's recipe. The invariant
        # is reachability from `make test`, so collect the recipe of `test`
        # plus the recipes of every prerequisite target it names.
        def make_recipe(target: str) -> list[str]:
            target_index = next(
                index
                for index, line in enumerate(make_lines)
                if line.startswith(target + ":")
            )
            recipe: list[str] = []
            for line in make_lines[target_index + 1 :]:
                if not line.startswith("\t"):
                    break
                recipe.append(line)
            return recipe

        test_line = next(
            line for line in make_lines if line.startswith("test:")
        )
        prerequisites = test_line.split(":", 1)[1].split("##", 1)[0].split()
        test_recipe = make_recipe("test")
        for prerequisite in prerequisites:
            test_recipe.extend(make_recipe(prerequisite))
        self.assertIn("\t" + command, test_recipe)
        workflow = (repository / ".github/workflows/ci.yml").read_text()
        workflow_lines = workflow.splitlines()
        trigger_violation = workflow_entry_violation(workflow)
        self.assertIsNone(trigger_violation, trigger_violation)
        repository_job = workflow.split("\n  repository-gates:", 1)[1].split(
            "\n  regression-heavy:", 1
        )[0]
        spec_step = repository_job.split(
            "\n      - name: Spec reference gate", 1
        )[1].split("\n      - ", 1)[0]
        self.assertIn("\n        run: " + command, spec_step)
        for defaults_index, line in enumerate(workflow_lines):
            if not line.startswith("defaults:"):
                continue
            defaults_block = [line]
            for nested in workflow_lines[defaults_index + 1 :]:
                if nested and not nested.startswith(" "):
                    break
                defaults_block.append(nested)
            self.assertNotIn("working-directory:", "\n".join(defaults_block))
        self.assertNotIn("working-directory:", repository_job)
        self.assertNotIn("\n    needs:", repository_job)
        self.assertNotIn("\n    if:", repository_job)
        self.assertNotIn("\n    continue-on-error:", repository_job)
        self.assertNotIn("\n        if:", spec_step)
        self.assertNotIn("\n        continue-on-error:", spec_step)
        result = subprocess.run(
            ["python3", "scripts/check-spec-references.py", "."],
            cwd=repository,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("spec_reference_check_ok", result.stdout)

    def test_required_jobs_share_pinned_ripgrep_install(self) -> None:
        repository = SCRIPT.parent.parent.resolve()
        workflow = yaml.load(
            (repository / ".github/workflows/ci.yml").read_text(),
            Loader=yaml.BaseLoader,
        )
        self.assertIsInstance(workflow, dict)
        self.assertEqual(workflow["env"]["RIPGREP_VERSION"], "15.2.0")
        self.assertEqual(
            workflow["env"]["RIPGREP_SHA256"],
            "33e15bcf1624b25cdd2a55813a47a2f95dbe126268203e76aa6a585d1e7b149c",
        )

        install_runs: dict[str, str] = {}
        for job_name in ("repository-gates", "regression-heavy"):
            steps = workflow["jobs"][job_name]["steps"]
            matches = [
                step.get("run")
                for step in steps
                if isinstance(step, dict)
                and step.get("name") == "Install validation tools"
            ]
            self.assertEqual(len(matches), 1, job_name)
            self.assertIsInstance(matches[0], str)
            install_runs[job_name] = matches[0]

        self.assertEqual(
            install_runs["repository-gates"], install_runs["regression-heavy"]
        )
        install_run = install_runs["repository-gates"]
        for required in (
            "--retry-max-time 900",
            "--max-time 300",
            "sha256sum --check -",
            "sudo install --mode 0755",
            " /usr/local/bin/rg",
            'resolved_rg="$(command -v rg)"',
            'installed_version="$(rg --version | head -n 1)"',
            "failed to download pinned ripgrep",
        ):
            self.assertIn(required, install_run)
        self.assertNotIn("apt-get", install_run)

    def test_declared_test_dependencies_are_wired_after_checkout(self) -> None:
        repository = SCRIPT.parent.parent.resolve()
        requirements = {
            line.strip()
            for line in (repository / "requirements-test.txt").read_text().splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        }
        self.assertEqual(requirements, {"pytest", "pyyaml"})

        workflow = (repository / ".github/workflows/ci.yml").read_text()
        dependency_command = "python3 -m pip install -r requirements-test.txt"
        wiring_violation = dependency_wiring_violation(workflow, dependency_command)
        self.assertIsNone(wiring_violation, wiring_violation)

        contributing = (repository / "docs" / "CONTRIBUTING.md").read_text()
        self.assertIn(dependency_command, contributing)

    def test_dependency_command_recognizer_rejects_decoys(self) -> None:
        command = "python3 -m pip install -r requirements-test.txt"
        self.assertTrue(
            step_runs_exact_command({"run": "  " + command + "\n"}, command)
        )
        decoys = (
            {"run": "sudo apt-get update\n" + command},
            {"run": 'echo "' + command + '"'},
            {"run": "# " + command},
            {"run": None},
            {"run": [command]},
        )
        for step in decoys:
            with self.subTest(step=step):
                self.assertFalse(step_runs_exact_command(step, command))

    def test_dependency_wiring_rejects_disabled_or_relocated_execution(self) -> None:
        command = "python3 -m pip install -r requirements-test.txt"
        job_block = (
            "  repository-gates:\n"
            "    steps:\n"
            "      - uses: actions/checkout@v5\n"
            "      - name: Arbitrary label\n"
            "        run: " + command + "\n"
        )
        valid = "jobs:\n" + job_block
        self.assertIsNone(
            dependency_wiring_violation(valid, command, ("repository-gates",))
        )
        rejected = {
            "defaults:\n  run:\n    working-directory: subdir\n" + valid:
                "workflow defaults",
            valid.replace("    steps:\n", "    if: false\n    steps:\n"):
                "job-level if",
            valid.replace("    steps:\n", "    continue-on-error: true\n    steps:\n"):
                "job-level continue-on-error",
            valid.replace("    steps:\n", "    needs: never-runs\n    steps:\n"):
                "job-level needs",
            valid.replace(
                "    steps:\n",
                "    defaults:\n      run:\n        working-directory: subdir\n    steps:\n",
            ): "defaults may not set a run working-directory",
            valid.replace(
                "      - uses: actions/checkout@v5\n",
                "      - uses: actions/checkout@v5\n        if: false\n",
            ): "checkout may not set if",
            valid.replace(
                "      - uses: actions/checkout@v5\n",
                "      - uses: actions/checkout@v5\n        continue-on-error: true\n",
            ): "checkout may not set continue-on-error",
            valid.replace(
                "      - uses: actions/checkout@v5\n",
                "      - uses: actions/checkout@v5\n        with:\n          path: subdir\n",
            ): "checkout may not set path",
            valid.replace(
                "      - uses: actions/checkout@v5\n",
                "      - uses: actions/checkout@v5\n        with:\n          sparse-checkout: scripts\n",
            ): "checkout may not set sparse-checkout",
            valid.replace(
                "      - name: Arbitrary label\n",
                "      - name: Arbitrary label\n        if: false\n",
            ): "install may not set if",
            valid.replace(
                "      - name: Arbitrary label\n",
                "      - name: Arbitrary label\n        working-directory: subdir\n",
            ): "install may not set working-directory",
            valid.replace(
                "      - name: Arbitrary label\n",
                "      - name: Arbitrary label\n        continue-on-error: true\n",
            ): "install may not set continue-on-error",
            valid.replace(
                "      - uses: actions/checkout@v5\n"
                "      - name: Arbitrary label\n"
                "        run: " + command + "\n",
                "      - name: Arbitrary label\n"
                "        run: " + command + "\n"
                "      - uses: actions/checkout@v5\n",
            ): "must checkout before installing test dependencies",
            valid.replace("        run: " + command, "        run: echo " + command):
                "must execute exactly one",
        }
        for workflow, expected in rejected.items():
            with self.subTest(expected=expected):
                violation = dependency_wiring_violation(
                    workflow, command, ("repository-gates",)
                )
                self.assertIsNotNone(violation)
                self.assertIn(expected, violation or "")

        structural_rejected = {
            "jobs: [": "workflow YAML is invalid",
            "- jobs": "workflow must be a mapping",
            "defaults: [invalid]\n" + valid: "workflow defaults must be a mapping",
            "defaults:\n  run: [invalid]\n" + valid:
                "workflow run defaults must be a mapping",
            "jobs: []\n": "workflow has no jobs mapping",
            "jobs: {}\n": "workflow has no repository-gates job",
            "jobs:\n  repository-gates: []\n":
                "workflow has no repository-gates job",
            valid.replace("    steps:\n", "    defaults: [invalid]\n    steps:\n"):
                "defaults must be a mapping",
            valid.replace(
                "    steps:\n",
                "    defaults:\n      run: [invalid]\n    steps:\n",
            ): "run defaults must be a mapping",
            valid.replace("    steps:\n", "    steps: {}\n    ignored:\n"):
                "has no steps list",
            valid.replace("      - uses: actions/checkout@v5\n", ""):
                "exactly one actions/checkout step",
            valid.replace(
                "      - uses: actions/checkout@v5\n",
                "      - uses: actions/checkout@v5\n"
                "      - uses: actions/checkout@v6\n",
            ): "exactly one actions/checkout step",
            valid.replace(
                "      - uses: actions/checkout@v5\n",
                "      - uses: actions/checkout@v5\n        with: invalid\n",
            ): "checkout options must be a mapping",
            valid.replace(
                "      - name: Arbitrary label\n        run: " + command + "\n",
                "",
            ): "must execute exactly one",
            valid.replace(
                "      - name: Arbitrary label\n        run: " + command + "\n",
                "      - name: Arbitrary label\n        run: " + command + "\n"
                "      - name: Duplicate install\n        run: " + command + "\n",
            ): "must execute exactly one",
        }
        for workflow, expected in structural_rejected.items():
            with self.subTest(structural=expected):
                violation = dependency_wiring_violation(
                    workflow, command, ("repository-gates",)
                )
                self.assertIsNotNone(violation)
                self.assertIn(expected, violation or "")

        second_job_disabled = (
            "jobs:\n"
            + job_block
            + job_block.replace("repository-gates", "regression-heavy").replace(
                "    steps:\n", "    if: false\n    steps:\n"
            )
        )
        second_job_violation = dependency_wiring_violation(
            second_job_disabled, command
        )
        self.assertIsNotNone(second_job_violation)
        self.assertIn("regression-heavy may not set job-level if", second_job_violation or "")

    def test_workflow_entry_accepts_equivalent_nonweakening_yaml(self) -> None:
        accepted = (
            "on: [push, pull_request]\n",
            '"on": # workflow entry\n'
            "  pull_request:\n"
            "    branches: [main]\n"
            "    types: [opened, synchronize]\n"
            "  push:\n"
            "    branches:\n"
            "      - main\n",
            "'on':\n  pull_request: {}\n  push: {}\n",
            "on: {pull_request: null, push: null}\n",
        )
        for workflow in accepted:
            with self.subTest(workflow=workflow):
                self.assertIsNone(workflow_entry_violation(workflow))

    def test_workflow_entry_rejects_execution_narrowing(self) -> None:
        rejected = {
            "on:\n  pull_request:\n    paths: [docs/**]\n  push:\n": "paths",
            "on:\n  pull_request:\n  push:\n    paths-ignore: [scripts/**]\n": "paths-ignore",
            "on:\n  pull_request:\n    branches: [dev]\n  push:\n": "include main",
            "on:\n  pull_request:\n    branches-ignore: [main]\n  push:\n": "exclude main",
            "on:\n  pull_request:\n    types: [closed]\n  push:\n": "opened and synchronize",
            "on:\n  workflow_dispatch:\n": "missing the pull_request trigger",
        }
        for workflow, expected in rejected.items():
            with self.subTest(workflow=workflow):
                violation = workflow_entry_violation(workflow)
                self.assertIsNotNone(violation)
                self.assertIn(expected, violation or "")

    # Compatibility positive 2: an EXPLICIT table, including an empty one, keeps
    # the old inert-on-absence semantics even against this repository.
    def test_explicit_waiver_table_stays_inert_on_absence(self) -> None:
        source_root = SCRIPT.parent.parent
        for table in ({}, {("no/such/file.md", "specs/090-absent/plan.md"): ("r", ((1, "deadbeef"),))}):
            waived: list[tuple[str, int, str, str]] = []
            stale: list[tuple[str, str, str]] = []
            findings = MODULE.broken_spec_references(source_root, None, waived, stale, table)
            self.assertEqual(stale, [], f"explicit table {table!r} was not inert")
            self.assertEqual(waived, [])
            # With an explicit table the shipped waiver does not apply, so the
            # frozen ledger citation is an ordinary finding.
            self.assertTrue(
                any(f[2] == "specs/*/evidence/AGENTS.md" for f in findings), findings
            )


if __name__ == "__main__":
    unittest.main()
