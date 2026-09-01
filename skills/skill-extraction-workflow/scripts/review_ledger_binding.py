#!/usr/bin/env python3
"""Require the landing candidate to be the candidate an external round reviewed.

The dual-track ledger is caller-built and caller-run. Nothing at merge time read
it, so which candidate the rounds actually inspected was unchecked: a chain could
close out on the pre-fix candidate while a different tree merged. This gate closes
that gap from the merge side.

The reviewed identity is the packet the controller froze, so this recomputes that
packet with the controller's own `freeze_packet` rather than a second
implementation of the same bytes -- two implementations of one hash drift, and the
drift would read as a forged ledger. The bound set is every tracked path, minus
exactly what this round adds under a round's evidence directory. It is a default
of everything rather than a whitelist because a whitelist binds only the paths
some round happened to review: a pull request could carry a ledger valid for its
skill changes while also landing a root build script, a release script, or any
other executable path, and because that content does not move the candidate the
existing ledger still passed and the unreviewed content merged. Binding
everything makes the default fail-closed -- a new top-level path is bound the day
it appears rather than the day somebody remembers to add it. The cost is stated
rather than hidden: a change confined to documentation now needs a ledger too,
which is the direction this repository has already chosen for shared gates, where
a false positive is cheaper than a false negative.

The exclusion is computed per run (`added_evidence_paths`) rather than written
down as a subtree, and the difference is load-bearing. Something must be outside
the candidate or no ledger could ever be committed: a receipt inside the bound set
would move the very hash it records. But excluding all of `specs/` would exclude
far more than that -- a pull request could delete or rewrite an earlier round's
plan and receipts, the committed review history itself, and none of it would reach
the candidate, so the gate would pass while that history was corrupted. Only the
paths this round ADDS under a round's own `<round>/evidence/` directory are excluded. Every
modification and deletion under `specs/`, and every added path outside an evidence
directory, is bound like any other file. What remains outside is narrow and worth
naming: a file added under an EARLIER round's evidence directory is excluded too,
because the rule is structural rather than round-aware.

The candidate must also be committed (`require_committed_tree`). The frozen packet
is built from the working tree and includes untracked files, so a scratch file or
an unstaged edit inside the bound paths would silently produce a hash no clean
checkout recomputes -- the author records it in the ledger, and the merge-side run
then reports that nothing binds the landing candidate. Refusing out loud costs a
commit; the alternative costs a review round nobody can reproduce. The workflow
directory stays bound, as it was before: with only `skills/` bound, deleting the CI
step that runs this gate would not move the candidate the evidence has to match.

Boundaries this gate does NOT close, stated because a gate that lives inside the
candidate cannot authenticate itself: it cannot prove the caller retained every
earlier chain; it runs the candidate's own validator, so a candidate that also
rewrites that validator is outside what any in-repo check can settle; and a pull
request may edit the workflow step that runs it. The fail-closed branch is pinned
as a contract anchor so hollowing it also edits a registry another required check
verifies; the workflow step itself is NOT pinned, because that registry addresses
skill files and a cross-tree row breaks the checker against its own fixtures. The terminal authority is the platform's
required-check configuration plus human review of changes to this gate itself,
both of which live outside the candidate. What this proves is narrow and worth
stating plainly: that what merges is the candidate an external round inspected --
not that the round was honest, and not that it found nothing. Any terminal state
the validator accepts satisfies this gate, including one that carries unresolved
findings forward for a human: this binds identity, and the verdict on the findings
stays with the human who merges.
"""

from __future__ import annotations

import sys

# Importing the controller must not perturb the tree this gate hashes: a written
# __pycache__ lands as an untracked binary file inside the reviewed paths and the
# packet freeze then fails on it. Set before any import that can write bytecode.
sys.dont_write_bytecode = True

import argparse
import hashlib
import importlib.util
import json
import os
import re
import subprocess
import time
import types
from pathlib import Path

VALIDATOR = "validate_extraction_review_state.py"
CONTROLLER = Path("skills") / "code-review" / "scripts" / "review_gate.py"
# Every tracked path. See the module docstring: the inversion is what stops an
# unreviewed path from riding along on a valid ledger. The only exclusion is
# computed per run by `added_evidence_paths` -- the receipts this round adds --
# because a written-down subtree would also hide edits to committed history.
EVIDENCE_ROOT = "specs"
EVIDENCE_MEMBER = re.compile(r"^specs/[^/]+/evidence/")
# A receipt is small; anything larger is not one, and reading it is not free.
MAX_RECEIPT_BYTES = 4_000_000
DEFAULT_PATHS = (".",)


def emit(message: str) -> None:
    print(message, file=sys.stderr)


def load_controller(repo_root: Path) -> types.ModuleType:
    controller_path = repo_root / CONTROLLER
    if not controller_path.is_file():
        raise SystemExit(
            f"review_ledger_binding_error: controller not found at {controller_path}"
        )
    spec = importlib.util.spec_from_file_location(
        "ccl_review_gate_for_binding", controller_path
    )
    if spec is None or spec.loader is None:
        raise SystemExit("review_ledger_binding_error: controller is not importable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def resolve_base(repo_root: Path, base: str) -> str:
    """Resolve the caller's base to a commit id before it reaches any git command.

    An option-shaped base (``--quiet``) is read by git as an option rather than a
    revision, and ``git diff`` with no revision compares the index to the working
    tree: in a clean checkout that reports no paths at all, so the gate would pass
    having compared nothing.
    """
    result = subprocess.run(
        [
            "git",
            "-C",
            str(repo_root),
            "rev-parse",
            "--verify",
            "--quiet",
            "--end-of-options",
            f"{base}^{{commit}}",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    resolved = result.stdout.strip()
    if result.returncode != 0 or len(resolved) != 40 or not all(
        character in "0123456789abcdef" for character in resolved
    ):
        raise SystemExit(
            f"review_ledger_binding_error: base does not resolve to a commit: {base}"
        )
    return resolved


def fork_point(repo_root: Path, base: str) -> str:
    """Compare against where this branch left the base, not the base's tip.

    A candidate measured against the tip absorbs every unrelated change the base
    branch gained meanwhile, so an advance on the target branch silently restates
    what this branch is and voids evidence that is still correct. The fork point
    is what the branch actually adds, and it does not move when someone else
    merges.
    """
    result = subprocess.run(
        ["git", "-C", str(repo_root), "merge-base", base, "HEAD"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    resolved = result.stdout.strip()
    if result.returncode != 0 or len(resolved) != 40:
        raise SystemExit(
            f"review_ledger_binding_error: no fork point between HEAD and {base}"
        )
    return resolved


def added_evidence_paths(repo_root: Path, base: str) -> list[str]:
    """Paths this round ADDS under a round's evidence directory.

    These are the only paths the candidate may exclude, and the predicate is what
    the file IS, not where it sits. Two earlier shapes of this exclusion were
    each broken by an adversarial round, and both failures were the same one: the
    rule named a location and the location stood in for "this is a receipt".
    Excluding all of `specs/` let a pull request delete or rewrite an earlier
    round's plan and receipts -- the committed review history itself -- with no
    evidence required. Narrowing that to added paths under an evidence directory
    then let an arbitrary added file there, a script included, ride through
    unreviewed for exactly the same reason.

    So the third shape stops using the path as a proxy. A file is excluded only
    when it is what the exclusion exists for: a committed JSON object carrying
    the 64-hex `candidate_sha256` that makes it a receipt about some candidate.
    Its directory still has to be a round's evidence directory, because that is
    where receipts belong, but the directory alone no longer buys exclusion.
    Anything else added there -- a script, a fixture, a data file, a JSON file
    with no candidate binding -- is bound like any other path, as is every
    modification and deletion under `specs/`.
    """
    result = subprocess.run(
        [
            "git", "-C", str(repo_root), "diff", "--name-only",
            "--diff-filter=A", base, "HEAD", "--", EVIDENCE_ROOT,
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(
            "review_ledger_binding_error: cannot enumerate added evidence: "
            f"{result.stderr.strip()}"
        )
    excluded: list[str] = []
    for line in result.stdout.splitlines():
        if not EVIDENCE_MEMBER.match(line):
            continue
        if is_candidate_receipt(repo_root, line):
            excluded.append(line)
    return excluded


def is_candidate_receipt(repo_root: Path, path_value: str) -> bool:
    """Whether the committed blob at this path is a receipt about a candidate.

    Read from the object store rather than the working tree: the exclusion has to
    describe what merges. A blob that is not JSON, is not an object, or carries no
    64-hex `candidate_sha256` is not a receipt, whatever it is named or wherever
    it sits, and it stays inside the candidate.
    """
    result = subprocess.run(
        ["git", "-C", str(repo_root), "cat-file", "blob", f"HEAD:{path_value}"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0 or len(result.stdout) > MAX_RECEIPT_BYTES:
        return False
    try:
        payload = json.loads(result.stdout.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return False
    if not isinstance(payload, dict):
        return False
    binding = payload.get("candidate_sha256")
    return (
        isinstance(binding, str)
        and len(binding) == 64
        and all(character in "0123456789abcdef" for character in binding)
    )


def require_committed_tree(repo_root: Path, paths: tuple[str, ...]) -> None:
    """Refuse a candidate the merge cannot reproduce.

    The frozen packet is built from the working tree and includes untracked
    files, so a scratch file or an unstaged edit inside the bound paths silently
    produces a hash no clean checkout will ever recompute: the author records it
    in the ledger and the merge-side run then reports that no evidence binds the
    landing candidate. Refusing out loud costs a commit; the alternative costs a
    review round nobody can reproduce. This is the same stance the evidence tree
    already takes -- what merges is the committed tree.
    """
    result = subprocess.run(
        ["git", "-C", str(repo_root), "status", "--porcelain", "--", *paths],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(
            f"review_ledger_binding_error: cannot read tree state: {result.stderr.strip()}"
        )
    dirty = [line for line in result.stdout.splitlines() if line]
    if dirty:
        raise SystemExit(
            "review_ledger_binding_error: the candidate tree carries uncommitted "
            "changes, so its hash is not the one a clean checkout recomputes; "
            "commit them first: " + ", ".join(entry[3:] for entry in dirty[:5])
        )


def changed_skill_paths(repo_root: Path, base: str, paths: tuple[str, ...]) -> list[str]:
    result = subprocess.run(
        ["git", "-C", str(repo_root), "diff", "--name-only", base, "--", *paths],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(
            f"review_ledger_binding_error: cannot diff against {base}: {result.stderr.strip()}"
        )
    return [line for line in result.stdout.splitlines() if line]


def candidate_hash(module: types.ModuleType, repo_root: Path, base: str, paths: tuple[str, ...]) -> str:
    args = argparse.Namespace(
        cwd=str(repo_root),
        diff_file=None,
        base=base,
        paths=list(paths),
        wording_only_proof_file=None,
    )
    packet_path, packet_sha256, _paths, _secrets = module.freeze_packet(
        args, time.monotonic() + 120
    )
    try:
        Path(packet_path).unlink(missing_ok=True)
    except OSError:
        pass
    return packet_sha256


def validator_accepts(validator: Path, ledger_path: Path) -> tuple[bool, str]:
    result = subprocess.run(
        [sys.executable, str(validator), str(ledger_path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=False,
        timeout=60,
    )
    return result.returncode == 0, result.stdout.strip()


def scan(repo_root: Path, evidence_root: str) -> list[tuple[Path, dict]]:
    """Enumerate committed evidence only.

    What merges is the committed tree, so evidence that is untracked or modified
    in the working tree is not evidence about the landing candidate -- and a gate
    that reads it would accept a ledger nobody can find after the merge. The
    enumeration comes from HEAD, and a dirty evidence tree is refused outright
    rather than silently read from disk.
    """
    listing = subprocess.run(
        ["git", "-C", str(repo_root), "ls-tree", "-r", "--name-only", "HEAD", "--", evidence_root],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if listing.returncode != 0:
        return []
    dirty = subprocess.run(
        ["git", "-C", str(repo_root), "status", "--porcelain", "--", evidence_root],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if dirty.returncode != 0 or dirty.stdout.strip():
        raise SystemExit(
            "review_ledger_binding_error: the evidence tree has uncommitted changes; "
            "commit the ledger and its receipts before this gate can read them"
        )
    found: list[tuple[Path, dict]] = []
    for relative in sorted(line for line in listing.stdout.splitlines() if line.endswith(".json")):
        path = repo_root / relative
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError):
            continue
        if isinstance(payload, dict):
            found.append((path, payload))
    return found


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--base", default=None)
    parser.add_argument(
        "--allow-unevaluated",
        action="store_true",
        help="permit a run with no resolvable base to exit 0, for events that have none",
    )
    parser.add_argument("--evidence-root", default="specs")
    parser.add_argument("--paths", nargs="*", default=list(DEFAULT_PATHS))
    parser.add_argument(
        "--print-candidate",
        action="store_true",
        help="print the candidate hash the evidence must bind, then exit",
    )
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    base = args.base or os.environ.get("CCL_SKILL_BASE_REF", "")
    if not base:
        # The gate is base-relative by construction, so a run with no base has
        # checked nothing. Exiting 0 there is how a base-relative gate becomes
        # decorative: a base-wiring mistake would read as a passing required
        # check. Fail closed; a caller whose event genuinely has no base must
        # say so out loud with --allow-unevaluated.
        emit(
            "review_ledger_binding_unevaluated: no base ref supplied "
            "(pass --base or set CCL_SKILL_BASE_REF); nothing was checked"
        )
        return 0 if args.allow_unevaluated else 2

    base = fork_point(repo_root, resolve_base(repo_root, base))
    # The exclusion is derived from this round's own diff, not written down as a
    # subtree, so edits to committed history stay inside the candidate.
    # These names come from the candidate's own tree and are handed back to git as
    # pathspecs, so `literal` stops git reading a filename as a pattern. A review
    # round called this a total bypass -- a receipt named `*` excluding everything
    # -- and that did not reproduce: the exclusion carries the full path, so a glob
    # in the filename expands only within that one evidence directory, whose other
    # members are receipts anyway. The claim is recorded as narrowed rather than
    # confirmed, and no test asserts a bypass this gate does not have. `literal`
    # stays because interpreting these names as patterns is a capability the gate
    # never needed, and removing it costs nothing.
    paths = tuple(args.paths) + tuple(
        f":(exclude,literal){path}" for path in added_evidence_paths(repo_root, base)
    )
    require_committed_tree(repo_root, paths)
    changed = changed_skill_paths(repo_root, base, paths)
    if not changed:
        # No reviewed path moved, so there is no candidate to freeze and nothing to
        # bind. Say which it is rather than letting an empty packet surface as a
        # freeze error, which reads like a broken gate.
        if args.print_candidate:
            emit(f"review_ledger_binding_no_change: no reviewed-path change against {base}")
        else:
            print(f"review_ledger_binding_ok: no reviewed-path change against {base}")
        return 0

    module = load_controller(repo_root)
    try:
        expected = candidate_hash(module, repo_root, base, paths)
    except Exception as exc:  # noqa: BLE001 - surface the controller's own message
        emit(f"review_ledger_binding_error: cannot freeze the candidate packet: {exc}")
        return 1

    if args.print_candidate:
        print(expected)
        return 0

    validator = repo_root / "skills" / "skill-extraction-workflow" / "scripts" / VALIDATOR
    ledgers: list[str] = []
    for path, payload in scan(repo_root, args.evidence_root):
        if payload.get("candidate_sha256") != expected:
            continue
        relative = str(path.relative_to(repo_root))
        # Only a validator-accepted ledger counts. A receipt-shaped file proves
        # nothing on its own: this gate cannot authenticate that a controller
        # minted it, so any branch keyed on a self-declared field is a bypass a
        # contributor can hand-write.
        if "closeout_state" in payload and "controller_receipts" in payload:
            accepted, output = validator_accepts(validator, path)
            if accepted:
                print(
                    f"review_ledger_binding_ok: {relative} binds the landing candidate "
                    f"({expected[:12]}...) -- {output}"
                )
                return 0
            ledgers.append(f"{relative}: {output}")

    emit(
        "review_ledger_binding_failed: no accepted review evidence binds the landing "
        f"candidate {expected}"
    )
    emit(f"  reviewed paths: {' '.join(paths)} against {base}")
    emit(f"  changed files: {len(changed)}")
    for row in ledgers:
        emit(f"  rejected ledger -> {row}")
    if not ledgers:
        emit(
            "  no committed ledger records this candidate; run the extraction review "
            "lane against the final, committed tree"
        )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
