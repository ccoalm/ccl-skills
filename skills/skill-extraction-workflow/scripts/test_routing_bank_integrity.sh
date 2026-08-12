#!/usr/bin/env bash
# Structural contract test for the routing task bank (eval/routing-tasks.jsonl).
#
# SCOPE — read this before citing the lane as evidence. This test proves the
# bank is well-formed and that every skill it names actually exists. It does
# NOT route anything and therefore does NOT prove any fixture's expectation is
# delivered: the behavioural grader (`eval-routing-bank.rb`) shells out to a
# live `claude` CLI, so it is advisory Tier-2 and cannot be a deterministic CI
# gate. A source-register row may cite THIS lane for "the fixture exists, is
# well-formed, and its targets resolve" — never for "the fixture passes".
#
# What it catches (the gap it was written for): a fixture silently deleted,
# an id collision, a typo'd or renamed target skill, a required provenance
# field dropped, or a self-contradictory row. Before this lane existed, all of
# those stayed green because the only registered routing lane checks literal
# phrases in SKILL.md files and never opens the bank at all.
set -u
ROOT="${BANK_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
[ -n "${BANK_ROOT:-}" ] && echo "NOTICE: BANK_ROOT set — testing tree: $ROOT" >&2
BANK="$ROOT/eval/routing-tasks.jsonl"

if [ ! -f "$BANK" ]; then
  echo "FAIL: task bank missing ($BANK)" >&2
  exit 1
fi

python3 - "$ROOT" "$BANK" <<'PY'
import json, os, sys

root, bank = sys.argv[1], sys.argv[2]
skills_dir = os.path.join(root, "skills")
installed = {
    name for name in os.listdir(skills_dir)
    if os.path.isfile(os.path.join(skills_dir, name, "SKILL.md"))
}

# Universal fields, measured against the bank rather than assumed: all 113 rows
# carry these five. `source` is present on only 37/113 and `added_by_change_sha`
# on none, although docs/f4-skill-effectiveness-harness.md lists both as required
# provenance — that doc-vs-bank drift is reported below, not failed, because
# failing it would red-line ~76 pre-existing rows this change never touched.
REQUIRED = ("id", "utterance", "expected_skill", "why_expected", "frozen_at_sha")
fail = 0
seen = {}
rows = 0

def bad(msg):
    global fail
    print(f"FAIL: {msg}", file=sys.stderr)
    fail = 1

with open(bank, encoding="utf-8") as fh:
    for lineno, raw in enumerate(fh, 1):
        raw = raw.strip()
        if not raw:
            continue
        rows += 1
        try:
            row = json.loads(raw)
        except json.JSONDecodeError as exc:
            bad(f"line {lineno}: not valid JSON ({exc})")
            continue

        rid = row.get("id")
        for field in REQUIRED:
            if not row.get(field):
                bad(f"line {lineno} ({rid}): missing/empty required field '{field}'")

        if rid in seen:
            bad(f"line {lineno}: duplicate id '{rid}' (first seen line {seen[rid]})")
        elif rid:
            seen[rid] = lineno

        expected = row.get("expected_skill")
        if expected and expected not in installed:
            bad(f"line {lineno} ({rid}): expected_skill '{expected}' is not a skill in skills/")

        must_not = row.get("must_not_route_to") or []
        if not isinstance(must_not, list):
            bad(f"line {lineno} ({rid}): must_not_route_to must be a list")
            must_not = []
        for target in must_not:
            if target not in installed:
                bad(f"line {lineno} ({rid}): must_not_route_to names '{target}', not a skill in skills/")
            if target == expected:
                bad(f"line {lineno} ({rid}): '{target}' is both expected_skill and must_not_route_to")

# A truncated or emptied bank must fail rather than vacuously pass.
MIN_ROWS = 100
if rows < MIN_ROWS:
    bad(f"bank has {rows} rows, expected at least {MIN_ROWS} (truncation guard)")

# Row-count guards are too coarse to notice ONE deleted fixture (deleting one of
# 113 still clears MIN_ROWS). Any fixture a source-register row cites as its
# evidence is pinned by id here, so removing it turns this lane red instead of
# silently invalidating the row that points at it. Add an id when a new register
# row cites a new fixture, in the same diff.
CITED_BY_REGISTER_ROWS = (
    "miss-refactor-python-unqualified",
    "miss-refactor-miniapp",
    "route-python-cli-not-terminal",
    "route-go-cli-not-terminal",
    "route-cli-contract-design-not-stack",
)
for rid in CITED_BY_REGISTER_ROWS:
    if rid not in seen:
        bad(f"fixture '{rid}' is cited by a source-register row but is absent from the bank")

# frozen_at_sha ancestry. docs/f4-skill-effectiveness-harness.md says the runner
# validates this, but the runner needs a live model and no committed-time lane
# checked it — so a fixture carrying a sha from an unrelated history (the "drift"
# the field exists to catch) reached main unchallenged. Verified here instead.
#
# SEMANTICS, because two readers already read this field two different ways:
# frozen_at_sha is an ANCESTRY/BATCH marker, not a claim that the expectation was
# already deliverable at that commit. Fixtures that land together share the sha
# of the branch point, so a fixture added ALONGSIDE the routing surface it
# describes is correctly frozen at a commit where that surface does not yet
# exist. Do not "fix" such a row by pointing it at a post-landing commit: branch
# shas do not survive a squash merge, and a dangling sha reads as drift and
# silently drops the fixture from regression judgement.
import subprocess

def git(*args):
    return subprocess.run(("git", "-C", root) + args,
                          capture_output=True, text=True)


if git("rev-parse", "--git-dir").returncode != 0:
    print("routing_bank_ancestry_info: not a git checkout — ancestry not verified")
else:
    # An unresolvable sha is tolerated ONLY where it is genuinely explainable:
    # a shallow or partial clone that simply does not carry the object. In a
    # COMPLETE checkout an unresolvable sha means the row points at a mistyped,
    # dangling, or unrelated history — which is precisely the drift this check
    # exists to catch, and the row would be silently dropped from regression
    # judgement. Tolerating it unconditionally made the lane pass in exactly the
    # case it was written for.
    # Shallow detection: ONE signal, the `shallow` marker file. It is the ground
    # truth `--is-shallow-repository` itself derives from, so pairing the two as
    # "primary + fallback" is not redundancy — whichever is second is provably
    # unreachable, and shipping an unreachable branch is how you get code that
    # has never been observed to work. Verified both ways: deleting the marker
    # makes the porcelain report false too.
    #
    # --git-COMMON-dir, not --git-dir: in a linked worktree --git-dir returns
    # .git/worktrees/<name>, while `shallow` lives in the shared .git — probing
    # the per-worktree dir silently finds nothing and reports every shallow
    # worktree as a complete checkout.
    common_dir = git("rev-parse", "--git-common-dir").stdout.strip()
    shallow = False
    if common_dir:
        cd_abs = common_dir if os.path.isabs(common_dir) else os.path.join(root, common_dir)
        shallow = os.path.isfile(os.path.join(cd_abs, "shallow"))
    # Partial clone: git marks the PROMISOR REMOTE, whose name is not necessarily
    # "origin" (`git clone -o upstream --filter=...`). Scan every remote, or a
    # partial clone under any other remote name gets red-lined on every row.
    # `extensions.partialClone` is the repository-level marker (it names the
    # promisor remote) and survives a remote rename; the per-remote keys are the
    # corroborating signal. Check both, under any remote name.
    partial = bool(git("config", "--get", "extensions.partialClone").stdout.strip()) or \
        bool(git("config", "--get-regexp",
                 r"^remote\..*\.(promisor|partialclonefilter)$").stdout.strip())
    # ONE decision point, deliberately hoisted out of the per-sha loop.
    #
    # This used to be consulted twice INSIDE the loop — once for an unresolvable
    # object, once for a failed ancestry query — and both times I added a new
    # failure mode while guarding only one of the two exits. A degraded clone
    # cannot answer either question, so the honest structure is to decide once,
    # up front, whether ancestry is answerable at all. Adding a third git query
    # later cannot reintroduce the bug: there is no per-query tolerance to forget.
    degraded = shallow or partial
    if degraded:
        kind = "shallow" if shallow else "partial"
        print(f"routing_bank_ancestry_info: {kind} clone — ancestry NOT verified for any row "
              f"(a complete checkout verifies every row and fails on drift)")
    else:
        for rid, sha in sorted({r.get("id"): r.get("frozen_at_sha") for r in
                                [json.loads(l) for l in open(bank, encoding="utf-8") if l.strip()]}.items()):
            if not sha:
                continue  # empty/missing is already a required-field failure above
            if sha == "root":
                sha = git("rev-list", "--max-parents=0", "HEAD").stdout.splitlines()[0]
            if git("cat-file", "-e", f"{sha}^{{commit}}").returncode != 0:
                bad(f"({rid}): frozen_at_sha {sha[:12]} does not resolve to a commit in this "
                    f"complete checkout (mistyped or from an unrelated history — the row would "
                    f"be silently excluded from regression judgement)")
                continue
            if git("merge-base", "--is-ancestor", sha, "HEAD").returncode != 0:
                bad(f"({rid}): frozen_at_sha {sha[:12]} is not an ancestor of HEAD (drift — the "
                    f"row would be silently excluded from regression judgement)")
        print(f"routing_bank_ancestry_ok: {rows} row(s) verified against HEAD")

if fail:
    sys.exit(1)

# Informational: provenance coverage the harness doc asks for but the bank does
# not yet carry. Reported so the drift stays visible without blocking.
with open(bank, encoding="utf-8") as fh:
    parsed = [json.loads(l) for l in fh if l.strip()]
with_source = sum(1 for r in parsed if r.get("source"))
print(f"routing_bank_provenance_info: source present on {with_source}/{rows} rows "
      f"(docs/f4-skill-effectiveness-harness.md lists it as required; not enforced here)")
print(f"routing_bank_integrity_ok rows={rows} (structure only — routing NOT evaluated)")
PY
