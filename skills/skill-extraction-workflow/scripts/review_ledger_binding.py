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

The candidate's Git identity and the reviewer's input are two different sizes.
A landing candidate is base..HEAD and has no natural byte limit; a review packet
is what one reviewer can read whole, and the controller caps it at
`MAX_PACKET_BYTES`. Binding the landing candidate to ONE packet hash therefore
made the reviewer's ceiling the pull request's ceiling: a candidate larger than
one packet could not be frozen, no ledger could ever bind it, and authors split
the pull request instead of the review -- eight merges for one release. The
review side already allowed splitting a large candidate by path into partitions
(the `code-review` skill's packet rule); what was missing was the merge side
consuming them. A committed landing partition manifest closes that: it names
path partitions whose changed files together equal the candidate's changed files
exactly once, and each partition's `candidate_sha256`, which is what
`--print-candidate --paths <partition>` already answers. This gate recomputes
every partition with the same `freeze_packet`, requires a validator-accepted
ledger per partition, and refuses any manifest whose parts do not add up to the
whole: an uncovered file, an overlapping file, a partition that no longer
reproduces, a base other than the fork point, or an aggregate hash that does not
reproduce its own partitions. The manifest carries a top-level 64-hex
`candidate_sha256` -- the aggregate identity -- so it satisfies the existing
receipt predicate and committing it moves no partition; that is the load-bearing
reason for the field, and the exclusion predicate itself is unchanged. What the
manifest proves is the same narrow thing the single ledger proves, taken per
part: every byte that lands is a byte some external round froze and inspected.
Merge-queue aggregation of several pull requests into one HEAD is a different
aggregate and remains unsolved here.

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
# A landing partition manifest splits one candidate by path into packets a
# reviewer can read whole. Its shape is closed: exactly these keys, this kind,
# and a bounded partition count, so a manifest cannot double as a ledger or
# smuggle fields the gate does not read.
MANIFEST_KIND = "landing_partition_manifest"
MANIFEST_SCHEMA_VERSION = 1
MANIFEST_KEYS = {"schema_version", "kind", "base", "partitions", "candidate_sha256"}
PARTITION_KEYS = {"paths", "candidate_sha256"}
MAX_PARTITIONS = 64
HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")


class ManifestError(Exception):
    """A manifest that does not describe this candidate; the message is the reason."""


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


def canonical_digest(value: object) -> str:
    canonical = json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=False
    ).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()


def manifest_aggregate(base: str, partitions: list[dict]) -> str:
    """The aggregate identity a manifest carries as its own `candidate_sha256`.

    Computed here and nowhere else: the renderer writes it and the gate rechecks
    it, so two implementations of one hash cannot drift into a forged manifest.
    """
    return canonical_digest(
        {
            "schema_version": MANIFEST_SCHEMA_VERSION,
            "kind": MANIFEST_KIND,
            "base": base,
            "partitions": partitions,
        }
    )


def validate_partition_path(value: object) -> str:
    """A partition path is a plain relative path, never a pathspec.

    The gate appends its own exclusions; a manifest that could name `:(exclude)`
    or a glob would choose what its partition does not cover, and a leading `-`
    would reach git as an option. Reject the shape here rather than trust git to
    interpret it the way the manifest author hoped.
    """
    if not isinstance(value, str) or not value:
        raise ManifestError("partition path must be a non-empty string")
    if value.startswith((":", "-", "/")) or any(ord(ch) < 32 for ch in value):
        raise ManifestError(f"partition path is not a plain relative path: {value!r}")
    if ".." in value.split("/"):
        raise ManifestError(f"partition path escapes the repository: {value!r}")
    return value


def parse_manifest(payload: dict, fork: str) -> tuple[list[list[str]], list[str]]:
    """Return (partition path lists, partition hashes) or raise ManifestError.

    Order of checks is cheapest first and each failure names one reason, so an
    author reads which part failed to add up rather than a generic refusal.
    """
    if set(payload) != MANIFEST_KEYS:
        raise ManifestError("manifest does not carry exactly the manifest keys")
    if payload["schema_version"] != MANIFEST_SCHEMA_VERSION or type(payload["schema_version"]) is not int:
        raise ManifestError(f"manifest schema_version must be {MANIFEST_SCHEMA_VERSION}")
    base = payload["base"]
    if not isinstance(base, str) or not HEX40.match(base):
        raise ManifestError("manifest base must be a 40-hex commit id")
    if base != fork:
        raise ManifestError(
            f"manifest base {base[:12]} is not this candidate's fork point {fork[:12]}"
        )
    partitions = payload["partitions"]
    if not isinstance(partitions, list) or not 1 <= len(partitions) <= MAX_PARTITIONS:
        raise ManifestError(f"manifest must list between 1 and {MAX_PARTITIONS} partitions")
    path_lists: list[list[str]] = []
    digests: list[str] = []
    seen: set[str] = set()
    for index, partition in enumerate(partitions, start=1):
        if not isinstance(partition, dict) or set(partition) != PARTITION_KEYS:
            raise ManifestError(f"partition {index} does not carry exactly paths and candidate_sha256")
        paths = partition["paths"]
        if not isinstance(paths, list) or not paths:
            raise ManifestError(f"partition {index} names no paths")
        validated = [validate_partition_path(value) for value in paths]
        for value in validated:
            if value in seen:
                raise ManifestError(f"partition path is listed twice: {value}")
            seen.add(value)
        digest = partition["candidate_sha256"]
        if not isinstance(digest, str) or not HEX64.match(digest):
            raise ManifestError(f"partition {index} candidate_sha256 must be 64-hex")
        path_lists.append(validated)
        digests.append(digest)
    aggregate = payload["candidate_sha256"]
    if aggregate != manifest_aggregate(base, partitions):
        raise ManifestError("manifest aggregate candidate_sha256 does not reproduce its partitions")
    return path_lists, digests


def partition_coverage(
    repo_root: Path,
    base: str,
    path_lists: list[list[str]],
    excludes: tuple[str, ...],
    changed_all: list[str],
) -> list[list[str]]:
    """Each partition's changed files; refuse unless they tile the candidate.

    Name-only diffs are cheap, so every way the parts can fail to add up is found
    before any packet is frozen: an empty partition, a changed file in no
    partition, or a changed file in two. Overlap is refused rather than tolerated
    because two verdicts over one file leave undefined which one covers it.
    """
    per_partition: list[list[str]] = []
    owner: dict[str, int] = {}
    overlaps: list[str] = []
    for index, paths in enumerate(path_lists, start=1):
        changed = changed_skill_paths(repo_root, base, tuple(paths) + excludes)
        if not changed:
            raise ManifestError(f"partition {index} ({' '.join(paths)}) covers no changed path")
        for value in changed:
            if value in owner:
                overlaps.append(value)
            owner[value] = index
        per_partition.append(changed)
    if overlaps:
        raise ManifestError(
            "partitions overlap on changed paths: " + ", ".join(sorted(set(overlaps))[:5])
        )
    uncovered = sorted(set(changed_all) - set(owner))
    if uncovered:
        raise ManifestError(
            "changed paths uncovered by every partition: " + ", ".join(uncovered[:5])
        )
    return per_partition


def render_manifest(
    module: types.ModuleType,
    repo_root: Path,
    base: str,
    path_lists: list[list[str]],
    excludes: tuple[str, ...],
    changed_all: list[str],
) -> dict:
    """Build the manifest an author commits, with every hash computed by this gate."""
    validated = [[validate_partition_path(value) for value in paths] for paths in path_lists]
    seen: set[str] = set()
    for paths in validated:
        for value in paths:
            if value in seen:
                raise ManifestError(f"partition path is listed twice: {value}")
            seen.add(value)
    partition_coverage(repo_root, base, validated, excludes, changed_all)
    partitions = [
        {
            "paths": paths,
            "candidate_sha256": candidate_hash(module, repo_root, base, tuple(paths) + excludes),
        }
        for paths in validated
    ]
    return {
        "schema_version": MANIFEST_SCHEMA_VERSION,
        "kind": MANIFEST_KIND,
        "base": base,
        "partitions": partitions,
        "candidate_sha256": manifest_aggregate(base, partitions),
    }


def accepted_ledger_for(
    evidence: list[tuple[Path, dict]],
    repo_root: Path,
    validator: Path,
    digest: str,
    rejected: list[str],
) -> str | None:
    """The first validator-accepted closeout ledger bound to `digest`, if any.

    The same criterion the single-candidate path uses: a receipt-shaped file is
    not evidence, only a ledger the validator accepts, because this gate cannot
    authenticate that a controller minted what it reads.
    """
    for path, payload in evidence:
        if payload.get("candidate_sha256") != digest:
            continue
        if "closeout_state" not in payload or "controller_receipts" not in payload:
            continue
        relative = str(path.relative_to(repo_root))
        accepted, output = validator_accepts(validator, path)
        if accepted:
            return f"{relative} -- {output}"
        rejected.append(f"{relative}: {output}")
    return None


def bind_manifest(
    module: types.ModuleType,
    repo_root: Path,
    base: str,
    payload: dict,
    excludes: tuple[str, ...],
    changed_all: list[str],
    evidence: list[tuple[Path, dict]],
    validator: Path,
    rejected_ledgers: list[str],
) -> list[str]:
    """Bind the candidate through one manifest; return per-partition proof lines.

    Raises ManifestError naming the first part that does not add up.
    """
    path_lists, digests = parse_manifest(payload, base)
    partition_coverage(repo_root, base, path_lists, excludes, changed_all)
    proofs: list[str] = []
    for index, (paths, recorded) in enumerate(zip(path_lists, digests), start=1):
        label = f"partition {index} ({' '.join(paths)})"
        actual = candidate_hash(module, repo_root, base, tuple(paths) + excludes)
        if actual != recorded:
            raise ManifestError(
                f"{label} recorded {recorded[:12]}... but does not reproduce: the candidate now hashes to {actual[:12]}..."
            )
        proof = accepted_ledger_for(evidence, repo_root, validator, actual, rejected_ledgers)
        if proof is None:
            raise ManifestError(f"no accepted ledger binds {label} {actual}")
        proofs.append(f"  {label} {actual[:12]}... <- {proof}")
    return proofs


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
    parser.add_argument(
        "--print-manifest",
        action="store_true",
        help=(
            "render a landing partition manifest for the --partition groups given, "
            "with every hash computed by this gate, then exit"
        ),
    )
    parser.add_argument(
        "--partition",
        action="append",
        nargs="+",
        metavar="PATH",
        default=[],
        help="one partition's paths; repeat per partition (only with --print-manifest)",
    )
    args = parser.parse_args()
    if args.print_manifest and not args.partition:
        parser.error("--print-manifest needs at least one --partition")
    if args.partition and not args.print_manifest:
        parser.error("--partition is only meaningful with --print-manifest")

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
    excludes = tuple(
        f":(exclude,literal){path}" for path in added_evidence_paths(repo_root, base)
    )
    paths = tuple(args.paths) + excludes
    require_committed_tree(repo_root, paths)
    changed = changed_skill_paths(repo_root, base, paths)
    if not changed:
        # No reviewed path moved, so there is no candidate to freeze and nothing to
        # bind. Say which it is rather than letting an empty packet surface as a
        # freeze error, which reads like a broken gate.
        if args.print_candidate or args.print_manifest:
            emit(f"review_ledger_binding_no_change: no reviewed-path change against {base}")
        else:
            print(f"review_ledger_binding_ok: no reviewed-path change against {base}")
        return 0

    module = load_controller(repo_root)

    if args.print_manifest:
        try:
            manifest = render_manifest(module, repo_root, base, args.partition, excludes, changed)
        except ManifestError as exc:
            emit(f"review_ledger_binding_error: cannot render a landing partition manifest: {exc}")
            return 1
        except Exception as exc:  # noqa: BLE001 - surface the controller's own message
            emit(f"review_ledger_binding_error: cannot freeze a partition packet: {exc}")
            return 1
        print(json.dumps(manifest, indent=2, ensure_ascii=False))
        return 0

    # The whole candidate may be larger than one packet. That is no longer a
    # terminal error: record why the single freeze failed and let a committed
    # partition manifest bind the candidate part by part.
    expected: str | None = None
    whole_error: str | None = None
    try:
        expected = candidate_hash(module, repo_root, base, paths)
    except Exception as exc:  # noqa: BLE001 - surface the controller's own message
        whole_error = str(exc)

    if args.print_candidate:
        if expected is None:
            emit(f"review_ledger_binding_error: cannot freeze the candidate packet: {whole_error}")
            return 1
        print(expected)
        return 0

    validator = repo_root / "skills" / "skill-extraction-workflow" / "scripts" / VALIDATOR
    evidence = scan(repo_root, args.evidence_root)
    ledgers: list[str] = []
    if expected is not None:
        # Only a validator-accepted ledger counts. A receipt-shaped file proves
        # nothing on its own: this gate cannot authenticate that a controller
        # minted it, so any branch keyed on a self-declared field is a bypass a
        # contributor can hand-write.
        proof = accepted_ledger_for(evidence, repo_root, validator, expected, ledgers)
        if proof is not None:
            print(
                f"review_ledger_binding_ok: {proof.split(' -- ', 1)[0]} binds the landing "
                f"candidate ({expected[:12]}...) -- {proof.split(' -- ', 1)[1]}"
            )
            return 0

    manifests: list[str] = []
    for path, payload in evidence:
        if payload.get("kind") != MANIFEST_KIND:
            continue
        relative = str(path.relative_to(repo_root))
        try:
            proofs = bind_manifest(
                module, repo_root, base, payload, excludes, changed, evidence, validator, ledgers
            )
        except ManifestError as exc:
            manifests.append(f"{relative}: {exc}")
            continue
        except Exception as exc:  # noqa: BLE001 - surface the controller's own message
            manifests.append(f"{relative}: cannot freeze a partition packet: {exc}")
            continue
        print(
            f"review_ledger_binding_ok: {relative} binds the landing candidate as "
            f"{len(proofs)} partitions (aggregate {payload['candidate_sha256'][:12]}...)"
        )
        for line in proofs:
            print(line)
        return 0

    if expected is None:
        emit(
            "review_ledger_binding_failed: the whole candidate cannot be frozen as one "
            f"packet ({whole_error}) and no committed landing partition manifest binds it"
        )
        emit(
            "  split the candidate by path: --print-manifest --partition <paths> "
            "[--partition <paths> ...] renders the manifest; commit it with one "
            "validated ledger per partition"
        )
    else:
        emit(
            "review_ledger_binding_failed: no accepted review evidence binds the landing "
            f"candidate {expected}"
        )
    emit(f"  reviewed paths: {' '.join(paths)} against {base}")
    emit(f"  changed files: {len(changed)}")
    for row in ledgers:
        emit(f"  rejected ledger -> {row}")
    for row in manifests:
        emit(f"  rejected manifest -> {row}")
    if not ledgers and not manifests:
        emit(
            "  no committed ledger records this candidate; run the extraction review "
            "lane against the final, committed tree"
        )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
