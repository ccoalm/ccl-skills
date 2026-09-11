#!/usr/bin/env python3
"""Refuse a pull request that changes shared skill behavior with no recorded review.

The extraction review lane owes one review and one challenge per non-wording
change (references/dual-track-review-gate.md). The merge-side candidate binding
that used to sit here was retired: it tied every pass to one tree hash, so every
fix voided the passes and restarted the sequence. What it also did — refuse a
landing with no review at all — is the half worth keeping, and it needs no hash.

This gate asks one question: does a pull request that changes `skills/` or
`hooks/` carry at least one conclusive review result added or modified under a
specs/<round>/evidence/ directory?

It deliberately does not require a challenge result. An earlier version did,
with a waiver for wording-only changes; independent review broke that waiver in
four successive forms (a global waiver, a second skill, a later edit to the same
file, a rewritten frontmatter delimiter), because deciding "still wording-only"
means re-parsing diffs this gate does not own. Same-class recurrence is the cue
to delete the capability, so the challenge obligation stays in the review-lane
rule and this gate only catches a round that recorded no external pass at all.

A result is conclusive when it is a schema-3 controller envelope whose status is
`passed` or `findings` and which names the client that ran it. It does not check
which candidate a result reviewed, and it cannot tell a genuine result from a
hand-written one: like the repository's other author-declared gates it catches a
pass that was never recorded, not a forged one.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

SUBJECT_PREFIXES = ("skills/", "hooks/")
CONCLUSIVE = ("passed", "findings")


def changed_paths(root: Path, base: str) -> list[str]:
    result = subprocess.run(
        # No --diff-filter: every change class counts, including a type change
        # (a regular file replaced by a symlink), which a filter list omits.
        ["git", "-C", str(root), "diff", "--name-only", "--no-renames", base, "HEAD"],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "git diff failed")
    return [line for line in result.stdout.splitlines() if line]


def is_evidence_json(path: str) -> bool:
    parts = path.split("/")
    return (
        len(parts) >= 4
        and parts[0] == "specs"
        and "evidence" in parts[2:-1]
        and parts[-1].endswith(".json")
    )


def load_result(root: Path, path: str) -> dict | None:
    target = root / path
    if not target.is_file():
        return None
    try:
        value = json.loads(target.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        return None
    if not isinstance(value, dict) or value.get("schema_version") != 3:
        return None
    if value.get("mode") not in ("review", "challenge"):
        return None
    if value.get("status") not in CONCLUSIVE or not value.get("selected_client"):
        return None
    return value


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--base", required=True)
    args = parser.parse_args(argv)
    root = Path(args.repo_root).resolve()

    try:
        paths = changed_paths(root, args.base)
    except RuntimeError as exc:
        print(f"review_evidence_unevaluated: {exc}")
        return 2

    subjects = [p for p in paths if p.startswith(SUBJECT_PREFIXES)]
    if not subjects:
        print("review_evidence_not_required: no change under skills/ or hooks/")
        return 0

    reviews: list[str] = []
    challenges: list[str] = []
    for path in paths:
        if not is_evidence_json(path):
            continue
        result = load_result(root, path)
        if result is None:
            continue
        (reviews if result["mode"] == "review" else challenges).append(path)

    if not reviews:
        print(
            "review_evidence_missing: this pull request changes "
            f"{len(subjects)} path(s) under skills/ or hooks/ but carries no conclusive "
            "review result under specs/<round>/evidence/"
        )
        print("  fix: commit the controller result JSON of each owed pass "
              "(references/dual-track-review-gate.md, Recording the passes)")
        return 1
    print(f"review_evidence_present_ok: {len(reviews)} review, {len(challenges)} challenge")
    return 0


if __name__ == "__main__":
    sys.exit(main())
