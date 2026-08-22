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
specs/014-spec-reference-existence-gate/plan.md; the deletion of the template
exemption in specs/016-spec-citation-template-exemption/plan.md; the row-bound
waiver for a citation frozen in an append-only ledger line in
specs/025-spec-reference-correction/plan.md.
"""

from __future__ import annotations

import hashlib
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

# ROW-BOUND WAIVERS, for a citation frozen inside an append-only ledger line.
#
# This is NOT the deleted exemption returning. That one asked "does this token
# LOOK like a shape", which is a grammar, and a grammar is a thing to evade --
# five ways through were found. This asks "are these exact bytes, on this exact
# line, in this exact file, the ones a reviewer waived", which is an identity.
# There is no shape to imitate: the same token one line away, one byte away, or
# one file away is a finding like any other, and CITATION_RE, resolve_target and
# the containment check are all untouched. 016 separately rejected allowlisting
# the known template STRINGS -- that predicates the gate on a vocabulary, and its
# reach is every file and every line; this reach is one line.
#
# It exists because two contracts intersect. This gate is repo-wide and scans
# every tracked file, including skills/skill-extraction-workflow/references/
# source-register.md. That ledger is append-only by contract: a landed row is
# never edited or deleted. So a citation defect frozen into a row has no legal
# repair, and would hard-red a mandatory gate forever. This repository already
# resolved that exact class twice against that exact file -- exempt_historical_
# routes in skills/skill-extraction-workflow/scripts/check-ccl-skills.sh and
# EXEMPT_ROW_DIGESTS in the register-firing-path-resolution.rb beside it -- and
# both chose a SHA-256 of the waived line over an occurrence count, because a
# count says "one row" but never WHICH row, so it silently transfers onto a new
# row when the old one moves. Same choice here, for the same reason.
#
# Keyed by (repo-relative path, the RAW token between the backticks) and pinned
# to (LINE NUMBER, SHA-256 of the stored line INCLUDING its terminator). Keying
# on the raw token rather than the resolved target is deliberate: a locator or
# fragment appended to a waived token makes a DIFFERENT token, which the waiver
# must not cover.
#
# Both halves of the pin were added after independent review defeated a weaker
# version, and both are load-bearing:
#
#   LINE NUMBER, because content alone identifies a LINE SHAPE, not an
#   occurrence. Copy the frozen row verbatim to a second line and the copy
#   matched path, token and digest too, so the waiver silently covered a row
#   nobody reviewed. An append-only ledger never renumbers a landed row, so
#   pinning the number costs an honest author nothing and any shift goes stale
#   rather than transferring.
#
#   THE TERMINATOR, because splitlines() discards it. Rewriting the pinned row
#   from LF to CRLF, or dropping the file's final newline, changed the stored
#   bytes while leaving the digest identical -- so a pin advertised as covering
#   a line's bytes did not. The digest is taken over the line as stored.
#
# Fail-closed in both directions. An applied waiver is printed, never silent. A
# pin that matches no line in a waived file that WAS scanned fails the run: on an
# append-only ledger that means the row was edited, reflowed, or deleted, and the
# waiver has to be re-reviewed rather than quietly covering nothing.
#
# AND a waived path that never reaches the corpus fails too, for the SHIPPED table
# scanning its OWN repository. That case used to be inert, which the adversarial
# lane showed was a bypass by omission: delete or untrack the waived ledger and
# `git ls-files` stops yielding it, so the path is never scanned, its pins are
# never checked, and the gate exits 0 with the waiver covering nothing -- the
# guard voided by removing the file instead of by satisfying it. Reproduced
# against this table: with the ledger deleted, and again with it untracked,
# findings=0 waived=0 stale=0 and the CLI exited 0.
#
# The inertness is kept exactly where it was written for -- a foreign corpus.
# Two conditions must BOTH hold before absence is an error: the default table is
# in use, and the scan root is the repository this checker ships in. So this
# gate's own fixtures, which point the checker at synthetic repositories, and any
# caller passing an explicit or empty table, keep the old semantics; only the
# shipped waiver against its own repository must find its file.
#
# Adding an entry is a reviewed act: the table's own diff and the printed waiver
# lines are the artifacts the mandatory independent review reads.
LEDGER_CITATION_WAIVERS: dict[tuple[str, str], tuple[str, tuple[tuple[int, str], ...]]] = {
    (
        "skills/skill-extraction-workflow/references/source-register.md",
        "specs/*/evidence/AGENTS.md",
    ): (
        "round-025 impact-chain row 153 declares that its local base/head "
        "observation is NOT a frozen measurement under the per-spec evidence "
        "contract, and writes that contract as a glob standing for the class. "
        "The referent is real -- this repository holds one instance, at "
        "specs/023-agent-native-repo-borrowing/evidence/AGENTS.md -- and the "
        "row's claim needs no file at the literal path. The register is "
        "append-only, so the token cannot be respelled. See "
        "specs/025-spec-reference-correction/plan.md. The pinned line moved from "
        "152 to 153 when a corrective rewrite of the round-023 borrowing merge "
        "inserted the impact-chain row that merge had omitted, and from 153 to "
        "168 when the round-032 Round-consolidation note landed above it in the "
        "ledger's notes block; the waived row itself is byte-identical across "
        "both moves, which is why its digest is unchanged.",
        ((168, "73d3e6f2801cefdb9807293d0b2cda8275921272197498671fa19722eaf29f5d"),),
    ),
}


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


def waiver_can_apply_to_target(target: str, escaped: bool) -> bool:
    """Use one target-domain predicate for application and liveness."""
    return bool(target) and not escaped


def owning_repository_root() -> Path:
    """The repository this checker ships in.

    It lives at `<repo>/scripts/check-spec-references.py`, so the owning root is
    two levels up. Used only to decide whether a missing waived path is an error
    (this repository) or inert (a foreign corpus a fixture pointed us at).
    """
    return Path(__file__).resolve().parent.parent


def line_digest(stored_line: str) -> str:
    """SHA-256 of one line's original bytes, terminator included.

    The corpus is decoded with surrogateescape, so re-encoding the same way
    round-trips back to the bytes git tracks -- a pin therefore covers a line
    that is not valid UTF-8 as faithfully as one that is.

    The argument is the line AS STORED, still carrying whatever terminator it
    had. Hashing the stripped line instead would let an LF-to-CRLF rewrite, or
    the removal of the file's final newline, change the stored bytes while the
    pin kept matching.
    """
    return hashlib.sha256(stored_line.encode("utf-8", errors="surrogateescape")).hexdigest()


def broken_spec_references(
    root: Path,
    unreadable: list[tuple[str, str]] | None = None,
    waived: list[tuple[str, int, str, str]] | None = None,
    stale: list[tuple[str, str, str]] | None = None,
    waivers: dict[tuple[str, str], tuple[str, tuple[tuple[int, str], ...]]] | None = None,
) -> list[tuple[str, int, str]]:
    findings: list[tuple[str, int, str]] = []
    unreadable = [] if unreadable is None else unreadable
    waived = [] if waived is None else waived
    stale = [] if stale is None else stale
    waivers = LEDGER_CITATION_WAIVERS if waivers is None else waivers
    # Presence is a property of each SHIPPED entry, not of whether the caller
    # omitted the optional table argument. Passing the shipped table explicitly
    # must not turn deletion or untracking into a way to void its guard. Custom
    # entries remain inert on absence, as do all entries against a foreign corpus.
    required_waiver_keys = (
        {
            key
            for key in waivers
            if key in LEDGER_CITATION_WAIVERS
        }
        if root.resolve() == owning_repository_root()
        else set()
    )
    # Per waived PATH, the union of every (line number, digest) pin written for
    # it. Digesting is done only for those paths: every other tracked file keeps
    # its previous cost.
    pins_by_path: dict[str, set[tuple[int, str]]] = {}
    for (path, _token), (_reason, pins) in waivers.items():
        pins_by_path.setdefault(path, set()).update(pins)
    # A pin is "seen" when its line is found at its pinned number AND that line
    # actually carries the token the waiver names. Not when a finding is waived:
    # if the citation ever started resolving on its own the waiver would become
    # unnecessary, and reporting that as staleness would red the gate on a good
    # state. But requiring the token is what stops a MISTYPED or obsolete waiver
    # key from sitting there covering nothing while its pin still matches -- the
    # digest proves the line, and only the token proves the waiver has a subject.
    # Keyed by the full waiver key, so one entry's health never masks another's.
    seen_pins: set[tuple[str, str, tuple[int, str]]] = set()
    tracked_waived_paths: set[str] = set()
    scanned_waived_paths: set[str] = set()
    # A waiver is spent by ONE citation. The predicate is evaluated per regex
    # match and a line can carry the same dead token twice, so without this the
    # single reviewed waiver silently covered every repeat on that line -- a
    # second unresolved citation riding in on the first one's approval. Keyed by
    # (path, token, pin) so a waiver written for two pinned lines still covers
    # one citation on each.
    spent: set[tuple[str, str, tuple[int, str]]] = set()
    for name in tracked_files(root):
        path = root / name
        pins_here = pins_by_path.get(name)
        if pins_here is not None:
            tracked_waived_paths.add(name)
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
        if pins_here is not None:
            scanned_waived_paths.add(name)
        # keepends: the digest has to cover the terminator, so the split must
        # keep it. `stored.splitlines()[0]` recovers exactly the line the scan
        # used before, including for the exotic separators splitlines() honours.
        for number, stored in enumerate(text.splitlines(keepends=True), start=1):
            line = stored.splitlines()[0] if stored.splitlines() else ""
            # Parse the line ONCE and use the result for both the seen-marking
            # and the scan, so the two can never disagree about what a citation
            # on this line is. Matching the waiver's token against raw text
            # instead would be a substring test: a token that is merely part of
            # a LONGER citation, or that appears in prose, would mark the pin
            # seen while the entry covered no actual citation -- the covering-
            # nothing hole this check exists to close, reopened one level down.
            matches = list(CITATION_RE.finditer(line))
            tokens_on_line = {found.group("path").strip() for found in matches}
            pin = ()
            if pins_here is not None:
                pin = (number, line_digest(stored))
                if pin in pins_here:
                    for (waived_path, waived_token), (
                        _reason,
                        entry_pins,
                    ) in waivers.items():
                        waived_target = resolve_target(waived_token)
                        if (
                            waived_path == name
                            and pin in entry_pins
                            and waived_token in tokens_on_line
                            and waiver_can_apply_to_target(
                                waived_target, escapes_root(root, waived_target)
                            )
                        ):
                            seen_pins.add((waived_path, waived_token, pin))
            for match in matches:
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
                escaped = escapes_root(root, target)
                if escaped or not resolves:
                    token = raw.strip()
                    entry = waivers.get((name, token))
                    # All three must match: this file, this exact token, and
                    # these exact line bytes. Any one of them differing leaves
                    # the finding standing.
                    #
                    # A waiver covers NON-EXISTENCE only. A citation that leaves
                    # the checkout is a different failure -- it would be
                    # confirmed by whatever the runner's filesystem happens to
                    # hold -- and no frozen ledger row needs one, so containment
                    # stays unwaivable rather than resting on nobody ever pinning
                    # such a line.
                    spend_key = (name, token, pin)
                    if (
                        waiver_can_apply_to_target(target, escaped)
                        and entry is not None
                        and pin
                        and pin in entry[1]
                        and spend_key not in spent
                    ):
                        spent.add(spend_key)
                        waived.append((name, number, token, entry[0]))
                        continue
                    findings.append((name, number, token))
    for path, token in sorted(waivers):
        if path not in scanned_waived_paths:
            # Absent from the tracked corpus. An error for the shipped table
            # against its own repository -- otherwise deleting or untracking the
            # waived file voids the guard instead of satisfying it -- and inert
            # for a foreign corpus, which is what the inertness was written for.
            if (path, token) in required_waiver_keys:
                state = (
                    "present-but-unscanned"
                    if path in tracked_waived_paths
                    else "absent-from-tracked-corpus"
                )
                for number, digest in sorted(waivers[(path, token)][1]):
                    stale.append(
                        (path, token, f"{number}:{digest} {state}")
                    )
            continue
        for number, digest in sorted(waivers[(path, token)][1]):
            if (path, token, (number, digest)) not in seen_pins:
                stale.append((path, token, f"{number}:{digest}"))
    return findings


def main(argv: list[str]) -> int:
    root = Path(argv[0] if argv else ".").resolve()
    unreadable: list[tuple[str, str]] = []
    waived: list[tuple[str, int, str, str]] = []
    stale: list[tuple[str, str, str]] = []
    findings = broken_spec_references(root, unreadable, waived, stale)
    # Printed on every run, including a passing one: a waiver that nobody sees
    # is a hole, and this is the line a reviewer reads to decide whether the
    # table still deserves its entry.
    for name, number, target, reason in waived:
        print(
            f"spec_citation_waived: {display(name)}:{number}: "
            f"{display(target)} -- {display(reason)}"
        )
    for path, token, pin in stale:
        if pin.endswith("absent-from-tracked-corpus"):
            cause = "waived path is absent from the tracked corpus"
        elif pin.endswith("present-but-unscanned"):
            cause = "waived path is tracked but was not scanned"
        else:
            cause = "waiver pin matches no line in this file"
        print(
            f"{display(path)}: {cause}: {display(token)} {pin}",
            file=sys.stderr,
        )
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
    if stale:
        print(
            "spec_reference_waiver_stale: a row-bound citation waiver no longer has "
            "the subject it was written for -- its pinned line may be absent, its "
            "file may be unscannable, or its file may not be tracked at all. The ledger it "
            "waives is append-only, so a missing row means it was edited, reflowed, "
            "or deleted; an unscanned FILE means the verdict does not cover it; and "
            "an absent FILE means the waived path was deleted or untracked. None "
            "may void this guard instead of "
            "satisfying it. Re-review the waiver and regenerate its digest, restore "
            "the path, or remove the entry. A waiver is never left covering nothing.",
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
    if findings or unreadable or stale:
        return 1
    print("spec_reference_check_ok: backticked specs/ citations resolve")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
