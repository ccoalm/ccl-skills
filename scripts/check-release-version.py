#!/usr/bin/env python3
"""Fail when the npm package's version pointer sits below an already-released one.

A published registry version is immutable — npm's unpublish policy states
"Registry data is immutable, meaning once published, a package cannot change" —
but nothing about that immutability protects the version *pointer in this tree*.
It moved backwards once: a rebase conflict resolution inside an unrelated
extraction commit rewrote 0.9.0 to 0.8.0 across all three sites while 0.9.0 was
already on the registry, and every check stayed green because CI never read the
version and the tag/version agreement check only runs on a release tag push.

So this gate checks the pointer against the release record the repository owns:

1. All three version sites agree (`package.json`, and both places the lockfile
   records it). The regression moved all three together, so agreement alone is
   not the invariant — but a split between them is its own release defect.
2. The version is stable MAJOR.MINOR.PATCH, matching what the publish workflow
   demands of a release tag.
3. The version is not BELOW the release floor, which is the higher of two
   independent records. The primary one is the highest `ccl-skills-v*` tag: the
   repository's own record of what has been published, which is what the
   invariant is actually about ("the tree never points below something already
   published and therefore unchangeable") rather than the weaker base-relative
   question "did this branch lower it". The second is the version the merge
   target already declares, and it exists because the tag record is deletable —
   remove `ccl-skills-v0.10.0` from the remote and no depth of fetch brings it
   back, after which a tree declaring 0.9.0 would look clean. A branch's target
   still declares 0.10.0, so lowering the pointer means corrupting both records.
   Residual, not closed: if a version is published without a tag, or if both
   records are lost, the floor drops with them. Closing that would mean querying
   the registry from a merge-time gate, which puts the network inside the
   critical path; the two-record floor is the bound that stays offline.

External-contract record (see `external-practice-controls.md`, inherited-reading
section). This gate depends on the release tags being present in the checkout:
- claim: `actions/checkout` with `fetch-depth: 0` fetches all history AND tags.
- source: actions/checkout README, "Checkout v4" section — "Set `fetch-depth: 0`
  to fetch all history for all branches and tags".
- verified: 2026-09-01, reading that README at its then-current revision, against
  `actions/checkout@v4` as pinned in ci.yml (the README documents v4 through v7
  in separate sections, so the sentence must be re-read in the section matching
  whatever major this repository pins, not in whichever one is newest).
- invalidated by: bumping the pinned major, or any workflow dropping
  `fetch-depth: 0` from a job that runs this gate. Both change whether tags
  exist at run time, and a tagless run is reported unevaluated, never clean.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

PACKAGE_JSON = "packages/ccl-skills-npm/package.json"
PACKAGE_LOCK = "packages/ccl-skills-npm/package-lock.json"
TAG_GLOB = "ccl-skills-v*"
TAG_RE = re.compile(r"^ccl-skills-v(\d+\.\d+\.\d+)$")
STABLE_SEMVER_RE = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")
DEFAULT_BASE_REF = "origin/dev"
BASE_LABEL = "the merge target"


def order(version: str) -> tuple[int, int, int]:
    major, minor, patch = version.split(".")
    return int(major), int(minor), int(patch)


def version_sites(root: Path) -> tuple[dict[str, str], list[str]]:
    """Return {site label: version} plus problems for unreadable/absent sites."""
    sites: dict[str, str] = {}
    problems: list[str] = []
    for relative, paths in (
        (PACKAGE_JSON, (("version",),)),
        (PACKAGE_LOCK, (("version",), ("packages", "", "version"))),
    ):
        path = root / relative
        if not path.is_file():
            problems.append(f"{relative}: missing")
            continue
        try:
            document = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as error:
            problems.append(f"{relative}: invalid JSON ({error})")
            continue
        except (OSError, UnicodeError) as error:
            problems.append(f"{relative}: unreadable ({error})")
            continue
        for keys in paths:
            cursor = document
            for key in keys:
                cursor = cursor.get(key) if isinstance(cursor, dict) else None
                if cursor is None:
                    break
            label = f"{relative}:{'.'.join(key or '<root>' for key in keys)}"
            if isinstance(cursor, str):
                sites[label] = cursor
            else:
                problems.append(f"{label}: no version string at this key")
    return sites, problems


def base_declared_version(root: Path) -> str | None:
    """The version the merge target already declares, or None when no base resolves.

    Second floor, and the reason the gate does not rest on tags alone: a tag can be
    deleted from the remote, and no depth of fetch recovers what is gone. The target
    branch's own committed version is a separate record that a tag deletion does not
    touch, so lowering the pointer now requires corrupting both. Absent (a fresh
    clone with no remote, a detached probe), this floor simply does not apply -- it
    strengthens the tag floor and never replaces it.
    """
    base = os.environ.get("CCL_SKILL_BASE_REF") or DEFAULT_BASE_REF
    try:
        completed = subprocess.run(
            ["git", "-C", str(root), "show", f"{base}:{PACKAGE_JSON}"],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return None
    if completed.returncode != 0:
        return None
    try:
        version = json.loads(completed.stdout).get("version")
    except json.JSONDecodeError:
        return None
    return version if isinstance(version, str) and STABLE_SEMVER_RE.match(version) else None


def highest_release_tag(root: Path) -> tuple[str | None, str | None]:
    """Return (version, error). Absent tags are an error, never a pass."""
    try:
        completed = subprocess.run(
            ["git", "-C", str(root), "tag", "--list", TAG_GLOB],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError as error:
        return None, f"git is not runnable here ({error})"
    if completed.returncode != 0:
        return None, f"git tag --list failed: {completed.stderr.strip()}"
    versions = [
        match.group(1)
        for line in completed.stdout.splitlines()
        if (match := TAG_RE.match(line.strip()))
    ]
    if not versions:
        return None, (
            f"no {TAG_GLOB} tag resolves in this checkout, so the published "
            "release record is unknown. Run `git fetch --tags` (CI gets them "
            "from actions/checkout's fetch-depth: 0)"
        )
    return max(versions, key=order), None


def findings(root: Path) -> tuple[list[str], str | None, str | None]:
    """Return (problems, declared version, released floor).

    The floor is resolved exactly once and carried out, so the success line reports
    the same snapshot the comparison used rather than a second, unchecked read.
    """
    sites, problems = version_sites(root)
    if problems:
        return problems, None, None

    distinct = sorted(set(sites.values()))
    if len(distinct) > 1:
        detail = "; ".join(f"{label} = {value}" for label, value in sorted(sites.items()))
        problems.append(
            f"version sites disagree: {detail}. All three must carry one version"
        )
        return problems, None, None

    declared = distinct[0]
    if not STABLE_SEMVER_RE.match(declared):
        problems.append(
            f"{PACKAGE_JSON}: version {declared!r} is not stable MAJOR.MINOR.PATCH. "
            "The publish workflow rejects anything else at tag time"
        )
        return problems, declared, None

    highest, tag_error = highest_release_tag(root)
    if tag_error is not None:
        problems.append(f"release_version_unevaluated: {tag_error}")
        return problems, declared, None

    floor, source = highest, f"tag ccl-skills-v{highest}"
    base_version = base_declared_version(root)
    if base_version is not None and order(base_version) > order(floor):
        floor, source = base_version, f"already declared by {BASE_LABEL}"
    if order(declared) < order(floor):
        problems.append(
            f"version {declared} is BELOW the released {floor} "
            f"({source}). A published version is immutable, so "
            f"the tree may never point under it. Sites to repair: "
            + ", ".join(sorted(sites))
        )
    return problems, declared, floor


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    problems, declared, floor = findings(root)
    if problems:
        for problem in problems:
            print(problem, file=sys.stderr)
        return 1
    print(f"release_version_ok: {declared} at or above released {floor}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
