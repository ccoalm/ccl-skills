#!/usr/bin/env python3
"""Fail when a backticked specs/ citation names a path this repo lacks.

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

import os
import re
import subprocess
import sys
from pathlib import Path

# Anchored on the separator so `specsheet.md` and `specs-old/x.md` are not
# spec citations. The token is whatever sits between backticks on one line.
#
# A single-backtick pattern is sufficient for EVERY delimiter run: a path
# contains no backtick, so in a multi-backtick span the innermost pair always
# matches. A review round reported multi-backtick spans as an evasion; measured
# against the pattern they are not, and a run-matching version was reverted after
# its own mutation flipped nothing. The double-backtick cases below stay as pins.
CITATION_RE = re.compile(r"`(?P<path>specs/[^`\n]+)`")

# A trailing `:63` / `:63-70` is a line locator, not part of the path.
LOCATOR_RE = re.compile(r":\d+(?:-\d+)?$")

# `plan.md#acceptance-matrix` is ordinary path-plus-anchor syntax. The fragment
# names a section, not a file, so it is stripped before resolution -- the base
# path still has to exist. A first version omitted this and would have rejected
# normal documentation syntax; because this gate is mandatory and fail-closed, a
# false positive of that shape blocks every landing.
FRAGMENT_RE = re.compile(r"#.*$")

# THERE IS NO TEMPLATE EXEMPTION, and its removal is the point.
#
# An earlier version exempted a token containing angle brackets, on the reasoning
# that a path SHAPE is not a citation. That exemption was the gate's entire
# attack surface: two review rounds found five separate ways through it — the
# test ran on the raw token before the fragment and locator were resolved; one
# valid placeholder segment licensed a malformed sibling; a zero-width character
# passed as a placeholder body; the marker suppressed the containment check as
# well as the existence check; and `..` cancelled the placeholder segment so a
# contained dead path still read as a shape. Each fix was correct and each was
# followed by another shape, which is the signal to remove the capability rather
# than adjudicate it again.
#
# The ambiguity was never really about paths: BACKTICKS were overloaded, marking
# both "a real path you can open" and "a shape you cannot". A gate cannot tell
# those apart from syntax, so the overload is gone instead. A backticked token
# beginning specs/ is a citation and must resolve — no exemption to evade.
#
# A template is written so it is not one such token: name the shape without the
# prefix and put the prefix in prose ("a `<NNN>-<slug>/plan.md` file under
# specs/"). Backticks are kept there on purpose, because an unbackticked angle
# bracket is swallowed as an HTML tag when Markdown renders.
#
# DECLARED SCOPE, and the residual that comes with it. The unit is the canonical
# token, not everything a renderer might display as a path. Exotic spellings that
# RENDER as one path while not being one token — the prefix split across a code
# span, a padded span CommonMark trims — are not detected. A round of review
# chased them and the honest conclusion was that completing it means writing an
# inline-Markdown parser inside a repo gate. This gate's declared trust model is
# an honest author citing a path that does not exist, which is how the defect
# that motivated it arose; it is not an adversary crafting an evasion, and it
# never was. Detecting those spellings was reverted rather than half-built, and
# the corpus uses none of them. An unbackticked prose mention was already out of
# scope (014 row 7); this residual is its neighbour and is accepted the same way.

# There is deliberately NO test-file exemption. A first version skipped every
# test-named file so this gate's own fixtures would not trip it; independent
# review killed that: one of the two dead pointers that motivated this gate
# lived in `skills/code-review/scripts/test_init_policy_matrix.sh`, so the
# exemption would have blinded the gate to its own motivating case. The suite
# builds its fixture citations from fragments instead, which costs one helper
# and keeps the corpus whole.



def display(text: str) -> str:
    """Render untrusted repo text safe to print on one physical line.

    A tracked filename may legally contain a newline, an ANSI escape, or (after
    os.fsdecode) a surrogate for a byte that is not valid UTF-8. Interpolated
    raw, one filename splits a finding across two physical lines, so anything
    reading this output line by line — a human, a CI annotation parser — sees a
    forged line. Escaping is display-only; the value used for resolution is
    untouched. Printable non-ASCII (an ordinary CJK filename) is preserved.
    """
    # Backslash FIRST, then every non-printable character including tab:
    # otherwise the encoding is not reversible — a real newline and a filename
    # containing a literal backslash-n both render as the same two characters,
    # so two distinct tracked paths produce an identical diagnostic. Printable
    # non-ASCII (an ordinary CJK filename) is preserved.
    escaped = text.replace("\\", "\\\\")
    return "".join(ch if ch.isprintable() else repr(ch)[1:-1] for ch in escaped)

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
    # os.fsdecode, not a strict decode: git tracks raw bytes and Linux allows a
    # filename that is not valid UTF-8, which made every one of these three
    # checkers crash with a traceback before scanning anything. macOS rejects
    # such names outright, so it is unreachable on this team's own machines and
    # reachable on the ubuntu CI runner. surrogateescape round-trips back to the
    # original bytes when the path is opened, so the file is still scanned.
    return [os.fsdecode(item) for item in result.stdout.split(b"\0") if item]


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
    except (ValueError, OSError, RuntimeError):
        # RuntimeError covers the symlink-loop shape older Pythons raise from
        # resolve(); an unresolvable target is treated as escaping, never as
        # contained, so a hostile link cannot crash a mandatory gate.
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
            for match in CITATION_RE.finditer(line):
                raw = match.group("path")
                target = resolve_target(raw)
                if not target:
                    continue
                # Containment is reported separately from non-existence so a
                # citation that leaves the checkout is never silently confirmed
                # by whatever the runner's filesystem happens to have there.
                # `exists()` is a syscall and CAN raise on a hostile target — a
                # citation long enough to exceed the filesystem's name limit
                # raised ENAMETOOLONG and crashed this mandatory gate mid-run.
                # Fail CLOSED: a target that cannot even be interrogated has not
                # been shown to resolve.
                try:
                    resolves = (root / target).exists()
                except OSError:
                    resolves = False
                if escapes_root(root, target) or not resolves:
                    findings.append((name, number, raw.strip()))
    return findings


def main(argv: list[str]) -> int:
    root = Path(argv[0] if argv else ".").resolve()
    unreadable: list[tuple[str, str]] = []
    findings = broken_spec_references(root, unreadable)
    for name, error in unreadable:
        print(
            f"{display(name)}: tracked file could not be read: {display(error)}",
            file=sys.stderr,
        )
    for name, number, target in findings:
        print(
            f"{display(name)}:{number}: spec citation does not resolve: {display(target)}",
            file=sys.stderr,
        )
    if findings or unreadable:
        print(
            "spec_reference_check_failed: a backticked specs/ citation must name a "
            "path in this repo. Describe a dead path instead of citing it; write a "
            "path TEMPLATE without the specs/ prefix inside the backticks, or in a "
            "fenced block, so it is not read as a citation.",
            file=sys.stderr,
        )
        return 1
    print("spec_reference_check_ok: backticked specs/ citations resolve")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
