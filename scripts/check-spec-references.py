#!/usr/bin/env python3
"""Fail when a backticked `specs/<slug>/...` citation names a path this repo lacks.

`check-markdown-links.py` resolves only Markdown inline-link destinations in
tracked `*.md`, so a backticked path in prose is invisible to it even inside
Markdown, and a citation in a shell script or any other non-Markdown file is
invisible twice over. That is how a reference to a `specs/` artifact which never
existed here survived being named as a defect in a landed spec.

Scope is deliberately `specs/` and nothing wider: a general "every backticked
path must resolve" check was measured against this repo and produced 139
non-resolving occurrences whose dominant class is correct content — a
product-agnostic skill naming a path in the *consuming* product repo. `specs/`
is a directory only this repo has, so a citation into it is always resolvable.

Design decisions and the acceptance matrix live in
specs/014-spec-reference-existence-gate/plan.md.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

# Anchored on the separator so `specsheet.md` and `specs-old/x.md` are not
# spec citations. The token is whatever sits between backticks on one line.
CITATION_RE = re.compile(r"`(specs/[^`\n]+)`")

# A trailing `:63` / `:63-70` is a line locator, not part of the path.
LOCATOR_RE = re.compile(r":\d+(?:-\d+)?$")

# `plan.md#acceptance-matrix` is ordinary path-plus-anchor syntax. The fragment
# names a section, not a file, so it is stripped before resolution -- the base
# path still has to exist. A first version omitted this and would have rejected
# normal documentation syntax; because this gate is mandatory and fail-closed, a
# false positive of that shape blocks every landing.
FRAGMENT_RE = re.compile(r"#.*$")

# `specs/<NNN>-<slug>/plan.md` is a path SHAPE, not a citation — the angle
# brackets say so on their face, and backticking a template that way is the
# clearest way to write one. Found by dogfooding the gate against this repo,
# which is also why the discriminator is structural rather than a list of the
# templates that happen to exist today. An abbreviation (`specs/<n>-…/x.md`) is
# deliberately NOT exempt: it still points a reader somewhere, so it is a
# citation and must resolve.
PLACEHOLDER_RE = re.compile(r"[<>]")

# There is deliberately NO test-file exemption. A first version skipped every
# test-named file so this gate's own fixtures would not trip it; independent
# review killed that: one of the two dead pointers that motivated this gate
# lived in `skills/code-review/scripts/test_init_policy_matrix.sh`, so the
# exemption would have blinded the gate to its own motivating case. The suite
# builds its fixture citations from fragments instead, which costs one helper
# and keeps the corpus whole.


def tracked_files(root: Path) -> list[str]:
    # Split on NUL as BYTES, then decode each entry -- the idiom the sibling
    # checkers in this directory already use. `text=True` would decode the whole
    # stream first, so one tracked filename with locale-invalid bytes would
    # crash this mandatory gate before the split. A filename that is itself not
    # valid UTF-8 still raises here, exactly as it does in the siblings; that
    # residual is shared and is routed as a follow-up rather than fixed only in
    # the newest gate.
    result = subprocess.run(
        ["git", "-C", str(root), "ls-files", "-z"],
        check=True,
        capture_output=True,
    )
    return [item.decode("utf-8") for item in result.stdout.split(b"\0") if item]


def resolve_target(raw: str) -> str:
    """Strip the line locator and any trailing separator from a citation."""
    without_fragment = FRAGMENT_RE.sub("", raw.strip())
    return LOCATOR_RE.sub("", without_fragment).rstrip("/")


def escapes_root(root: Path, target: str) -> bool:
    """True when the citation resolves outside the repository.

    A citation like specs/../../etc/passwd starts with the prefix but leaves the
    repo, and
    plain `.exists()` would happily confirm whatever the runner's filesystem
    has there. Containment is checked on the RESOLVED path so a symlink out of
    the tree is caught too.
    """
    try:
        resolved = (root / target).resolve()
        resolved.relative_to(root.resolve())
    except (ValueError, OSError):
        return True
    return False


def broken_spec_references(root: Path, unreadable: list[tuple[str, str]] | None = None) -> list[tuple[str, int, str]]:
    findings: list[tuple[str, int, str]] = []
    unreadable = [] if unreadable is None else unreadable
    for name in tracked_files(root):
        path = root / name
        # lstat, not is_file(): `git ls-files` returns tracked symlinks, and
        # is_file() FOLLOWS them, so read_bytes() would read the target. For a
        # mandatory CI gate that means scanning data outside the checkout, or
        # hanging/exhausting memory on a link to a device or a huge file. A
        # symlink's own content is a path string, never prose carrying a
        # citation, so it is skipped rather than followed.
        if path.is_symlink() or not path.is_file():
            continue
        # Lossless decode rather than a try/except that skips: a tracked file
        # carrying one invalid byte plus a dead citation would otherwise be
        # silently unscanned and CI would report success. surrogateescape never
        # raises, so every tracked file is scanned. An OSError is a real read
        # failure and fails the run instead of being skipped -- an unscannable
        # file means the verdict does not cover the corpus it claims to.
        try:
            text = path.read_bytes().decode("utf-8", errors="surrogateescape")
        except OSError as error:
            unreadable.append((name, str(error)))
            continue
        for number, line in enumerate(text.splitlines(), start=1):
            for raw in CITATION_RE.findall(line):
                if PLACEHOLDER_RE.search(raw):
                    continue
                target = resolve_target(raw)
                if not target:
                    continue
                if escapes_root(root, target) or not (root / target).exists():
                    findings.append((name, number, raw.strip()))
    return findings


def main(argv: list[str]) -> int:
    root = Path(argv[0] if argv else ".").resolve()
    unreadable: list[tuple[str, str]] = []
    findings = broken_spec_references(root, unreadable)
    for name, error in unreadable:
        print(f"{name}: tracked file could not be read: {error}", file=sys.stderr)
    for name, number, target in findings:
        print(f"{name}:{number}: spec citation does not resolve: {target}", file=sys.stderr)
    if findings or unreadable:
        print(
            "spec_reference_check_failed: a backticked `specs/<slug>/...` citation must "
            "name a path in this repo; describe a dead path instead of citing it",
            file=sys.stderr,
        )
        return 1
    print("spec_reference_check_ok: backticked specs/ citations resolve")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
