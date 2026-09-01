#!/usr/bin/env python3
"""Regression tests for check-release-version.py.

The gate's own oracle table. A gate is only evidence once it has been pointed at
something known to be broken and reported it FOR THE RIGHT REASON, so each
mutant below pins the message fragment it must produce, and each benign
neighbour pins that the gate stays silent on a tree that is merely unusual.

Mutants that MUST fire (and on which predicate):
  M1  the historical regression replayed: every version site rewritten to 0.8.0
      while ccl-skills-v0.9.0 is already tagged        -> "is BELOW the released"
  M2  package.json and the lockfile disagree                -> "sites disagree"
  M3  only the lockfile's packages[""] site regressed       -> "sites disagree"
  M4  a prerelease version                    -> "not stable MAJOR.MINOR.PATCH"
  M5  a checkout carrying no release tag        -> "release_version_unevaluated"
  M6  package.json absent                                          -> "missing"
  M7  0.9.0 declared while ccl-skills-v0.10.0 is tagged -> "is BELOW the released"
      (M7 is the ordering mutant: a lexicographic max picks "0.9.0" over
      "0.10.0" and the gate would pass this tree.)
  M8  a version file that is not valid UTF-8                       -> "unreadable"
  M9  the release tag deleted, so only the merge target still carries the higher
      version                            -> "is BELOW the released" via the base floor
  M10 a release tag on a commit unreachable from HEAD is still part of the
      record                                           -> "is BELOW the released"

Benign neighbours that MUST NOT fire:
  B1  version exactly equal to the highest release tag (the steady state)
  B2  version above every release tag (an ordinary pending bump)
  B3  tags this repository does not own (`v1.0.0`, `other-v9.9.9`) present
  B4  a release tag pointing at an unrelated commit
  B5  no base ref resolves, so the base floor simply does not apply
"""

from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import tempfile
import unittest
import unittest.mock
from pathlib import Path

SCRIPT = Path(__file__).with_name("check-release-version.py")
SPEC = importlib.util.spec_from_file_location("check_release_version", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

GIT_IDENTITY = (
    "-c",
    "user.email=gate@example.invalid",
    "-c",
    "user.name=gate",
)


class ReleaseVersionCheckTest(unittest.TestCase):
    def setUp(self) -> None:
        # The base floor reads this; fixtures opt in per test rather than
        # inheriting whatever the surrounding shell exported.
        self.enterContext(unittest.mock.patch.dict(os.environ, {"CCL_SKILL_BASE_REF": "refs/none"}))

    def make_repo(
        self,
        *,
        package_version: str | None = "0.10.0",
        lock_version: str | None = None,
        lock_root_version: str | None = None,
        tags: tuple[str, ...] = ("ccl-skills-v0.10.0",),
    ) -> Path:
        sandbox = Path(self.enterContext(tempfile.TemporaryDirectory()))
        root = sandbox / "repo"
        package_dir = root / "packages" / "ccl-skills-npm"
        package_dir.mkdir(parents=True)
        if package_version is not None:
            (package_dir / "package.json").write_text(
                json.dumps({"name": "@ccoalm/ccl-skills", "version": package_version}),
                encoding="utf-8",
            )
        lock = lock_version if lock_version is not None else package_version
        lock_root = lock_root_version if lock_root_version is not None else lock
        (package_dir / "package-lock.json").write_text(
            json.dumps({"version": lock, "packages": {"": {"version": lock_root}}}),
            encoding="utf-8",
        )
        self.git(root, "init", "--quiet", init=True)
        # Track the fixture files: a branch that only exists as an empty commit
        # would delete them on checkout, which the base-floor legs need to survive.
        self.git(root, "add", "-A")
        self.git(root, "commit", "--quiet", "-m", "base")
        for tag in tags:
            self.git(root, "tag", tag)
        return root

    def git(self, root: Path, *args: str, init: bool = False) -> None:
        command = ["git"]
        if init:
            command += [*args[:1], str(root), *args[1:]]
        else:
            command += ["-C", str(root), *GIT_IDENTITY, *args]
        subprocess.run(command, check=True, capture_output=True)

    def base_branch(self, root: Path, version: str) -> None:
        """Give the fixture a merge target declaring `version`, and point the gate at it."""
        package = root / "packages" / "ccl-skills-npm" / "package.json"
        keep = package.read_text(encoding="utf-8")
        package.write_text(
            json.dumps({"name": "@ccoalm/ccl-skills", "version": version}), encoding="utf-8"
        )
        self.git(root, "checkout", "--quiet", "-b", "target")
        self.git(root, "add", "-A")
        # --allow-empty: the target may already declare this version, and the leg
        # under test is what the target's committed package.json says, not whether
        # this fixture step happened to change it.
        self.git(root, "commit", "--quiet", "--allow-empty", "-m", "target")
        self.git(root, "checkout", "--quiet", "-")
        package.write_text(keep, encoding="utf-8")
        self.enterContext(unittest.mock.patch.dict(os.environ, {"CCL_SKILL_BASE_REF": "target"}))

    def problems(self, root: Path) -> list[str]:
        return MODULE.findings(root)[0]

    def assert_fires_with(self, root: Path, fragment: str) -> None:
        problems = self.problems(root)
        self.assertTrue(problems, f"gate stayed silent; expected {fragment!r}")
        self.assertTrue(
            any(fragment in problem for problem in problems),
            f"fired for the wrong reason: {problems}",
        )

    # --- control leg: the shape every mutant is a single step away from -------

    def test_control_tree_is_clean(self) -> None:
        self.assertEqual(self.problems(self.make_repo()), [])

    # --- mutants -------------------------------------------------------------

    def test_m1_historical_regression_replay(self) -> None:
        root = self.make_repo(
            package_version="0.8.0",
            tags=("ccl-skills-v0.8.0", "ccl-skills-v0.9.0"),
        )
        self.assert_fires_with(root, "is BELOW the released")

    def test_m2_package_and_lock_disagree(self) -> None:
        root = self.make_repo(package_version="0.10.0", lock_version="0.9.0")
        self.assert_fires_with(root, "sites disagree")

    def test_m3_only_the_nested_lock_site_regressed(self) -> None:
        root = self.make_repo(package_version="0.10.0", lock_root_version="0.9.0")
        self.assert_fires_with(root, "sites disagree")

    def test_m4_prerelease_version_is_rejected(self) -> None:
        root = self.make_repo(package_version="0.11.0-rc.1")
        self.assert_fires_with(root, "not stable MAJOR.MINOR.PATCH")

    def test_m5_a_tagless_checkout_is_unevaluated_not_clean(self) -> None:
        root = self.make_repo(tags=())
        self.assert_fires_with(root, "release_version_unevaluated")

    def test_m6_missing_package_json_is_reported(self) -> None:
        root = self.make_repo(package_version=None)
        self.assert_fires_with(root, "missing")

    def test_m7_ordering_is_numeric_not_lexicographic(self) -> None:
        root = self.make_repo(
            package_version="0.9.0",
            tags=("ccl-skills-v0.9.0", "ccl-skills-v0.10.0"),
        )
        self.assert_fires_with(root, "is BELOW the released")

    # --- benign neighbours ---------------------------------------------------

    def test_b1_version_equal_to_the_highest_tag_passes(self) -> None:
        root = self.make_repo(
            package_version="0.10.0",
            tags=("ccl-skills-v0.9.0", "ccl-skills-v0.10.0"),
        )
        self.assertEqual(self.problems(root), [])

    def test_b2_a_pending_bump_passes(self) -> None:
        root = self.make_repo(
            package_version="0.11.0", tags=("ccl-skills-v0.10.0",)
        )
        self.assertEqual(self.problems(root), [])

    def test_b3_foreign_tags_are_not_release_records(self) -> None:
        root = self.make_repo(
            package_version="0.10.0",
            tags=("ccl-skills-v0.10.0", "v1.0.0", "other-v9.9.9"),
        )
        self.assertEqual(self.problems(root), [])

    def test_m10_a_tag_unreachable_from_head_is_still_part_of_the_record(self) -> None:
        root = self.make_repo(package_version="0.10.0")
        head = subprocess.run(
            ["git", "-C", str(root), "rev-parse", "HEAD"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
        self.git(root, "checkout", "--quiet", "-b", "sidetrack")
        self.git(root, "commit", "--quiet", "--allow-empty", "-m", "unmerged release")
        self.git(root, "tag", "ccl-skills-v0.11.0")
        self.git(root, "checkout", "--quiet", head)
        self.git(root, "branch", "--quiet", "-D", "sidetrack")
        # ccl-skills-v0.11.0 now sits on a commit no branch reaches; a reachability-
        # scoped discovery (git tag --merged HEAD) would drop it and pass this tree.
        self.assert_fires_with(root, "is BELOW the released")

    def test_m8_an_undecodable_version_file_is_reported_not_raised(self) -> None:
        root = self.make_repo(package_version="0.10.0")
        (root / "packages" / "ccl-skills-npm" / "package.json").write_bytes(b'{"version": "\xff\xfe"}')
        self.assert_fires_with(root, "unreadable")

    def test_m9_the_base_floor_survives_a_deleted_release_tag(self) -> None:
        root = self.make_repo(package_version="0.10.0", tags=("ccl-skills-v0.10.0",))
        self.base_branch(root, "0.10.0")
        self.git(root, "tag", "-d", "ccl-skills-v0.10.0")
        self.git(root, "tag", "ccl-skills-v0.9.0")
        package = root / "packages" / "ccl-skills-npm" / "package.json"
        package.write_text(
            json.dumps({"name": "@ccoalm/ccl-skills", "version": "0.9.0"}), encoding="utf-8"
        )
        lock = root / "packages" / "ccl-skills-npm" / "package-lock.json"
        lock.write_text(
            json.dumps({"version": "0.9.0", "packages": {"": {"version": "0.9.0"}}}),
            encoding="utf-8",
        )
        # The tag record now tops out at 0.9.0 and would clear this tree on its own.
        self.assert_fires_with(root, "is BELOW the released")

    def test_b4_a_release_tag_on_an_unrelated_commit_still_counts(self) -> None:
        root = self.make_repo(package_version="0.10.0")
        self.git(root, "commit", "--quiet", "--allow-empty", "-m", "later")
        self.assertEqual(self.problems(root), [])

    def test_b5_an_unresolvable_base_leaves_the_tag_floor_alone(self) -> None:
        root = self.make_repo(package_version="0.10.0")
        self.assertIsNone(MODULE.base_declared_version(root))
        self.assertEqual(self.problems(root), [])

    def test_the_reported_floor_is_the_one_that_was_validated(self) -> None:
        root = self.make_repo(package_version="0.11.0", tags=("ccl-skills-v0.10.0",))
        problems, declared, floor = MODULE.findings(root)
        self.assertEqual((problems, declared, floor), ([], "0.11.0", "0.10.0"))
        # A tag appearing after validation cannot change what the caller prints,
        # because findings() carries its own snapshot out.
        self.git(root, "tag", "ccl-skills-v0.12.0")
        self.assertEqual(MODULE.findings(root)[2], "0.12.0")

    # --- live leg ------------------------------------------------------------

    def test_the_gate_holds_on_this_repository(self) -> None:
        root = Path(__file__).resolve().parents[1]
        self.assertEqual(self.problems(root), [])


if __name__ == "__main__":
    unittest.main()
