#!/usr/bin/env bash
# The gate lane must be judged on the BRANCH, not on the synthetic merge ref.
#
# WHY THIS TEST EXISTS. `impact-chain-gate.rb` partitions history into rounds by
# walking the branch's own first-parent chain. That flag is load-bearing and
# pinned by its own fixtures (`test_check_ccl_impact_chain_refscripts.sh`, round
# scoping 8): it is what collapses a merged worktree round to a single boundary
# when the ledger append precedes the owner work. Dropping it was tried and
# turned that fixture red.
#
# But the walk assumes the first-parent chain IS the branch's history. On the
# `refs/pull/N/merge` ref that actions/checkout uses by default for a
# pull_request event, HEAD is a merge whose first parent is the TARGET, so the
# walk finds only the merge commit and every round on the branch collapses into
# one. Rows whose validity depends on their round being narrow then flip red
# with nothing about them changed — observed on PR #53, where a description-only
# round lost its locator because a sibling round had edited the same owner's
# body. The two shapes are topologically identical (both are "merge X into Y
# where Y is the base"), so the gate cannot tell them apart from git alone; the
# harness has to hand it the right history instead.
#
# Hence: every job that runs a gate lane checks out the branch head. This test
# fails closed if a job loses that binding, because the symptom otherwise shows
# up as a confusing gate refusal on an unrelated PR months later.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"
CI="$ROOT/.github/workflows/ci.yml"
[ -f "$CI" ] || { echo "FAIL: workflow not found: $CI" >&2; exit 1; }

fail() { echo "FAIL: $*" >&2; exit 1; }

# The jobs that run a lane consuming the impact-chain gate. Named explicitly
# rather than derived: a new gate-running job must be added here deliberately,
# and a job that stops running gates must be removed deliberately.
GATE_JOBS="repository-gates regression-fast regression-heavy code-review-regressions-1 code-review-regressions-2"

python3 - "$CI" $GATE_JOBS <<'PY'
import re, sys

path, jobs = sys.argv[1], sys.argv[2:]
src = open(path, encoding="utf8").read()

# Split the jobs: mapping stanza at exactly two spaces of indent.
job_starts = [(m.start(), m.group(1)) for m in re.finditer(r"^  ([A-Za-z0-9_-]+):$", src, re.M)]
if not job_starts:
    print("FAIL: no jobs parsed out of the workflow", file=sys.stderr)
    sys.exit(1)
bounds = {}
for i, (pos, name) in enumerate(job_starts):
    end = job_starts[i + 1][0] if i + 1 < len(job_starts) else len(src)
    bounds[name] = src[pos:end]

failures = []
for job in jobs:
    body = bounds.get(job)
    if body is None:
        failures.append(f"{job}: job not present in the workflow (renamed? then update GATE_JOBS)")
        continue
    if "actions/checkout" not in body:
        failures.append(f"{job}: no checkout step")
        continue
    if "github.event.pull_request.head.sha" not in body:
        failures.append(
            f"{job}: checkout does not pin the branch head — it will run on the "
            f"refs/pull/N/merge ref, where the impact-chain gate's first-parent "
            f"round walk runs through the target and collapses every round into one"
        )
        continue
    # A fallback is required too: on `push` there is no pull_request context, and
    # an empty `ref:` silently checks out the default branch instead of failing.
    if "github.sha" not in body:
        failures.append(f"{job}: head-sha pin has no non-PR fallback (`|| github.sha`)")
        continue
    if "fetch-depth: 0" not in body:
        failures.append(f"{job}: no full history, so the gate cannot resolve its base")

if failures:
    for f in failures:
        print(f"FAIL: {f}", file=sys.stderr)
    sys.exit(1)
PY

echo "test_ci_checkout_ref_binding: ok (gate lanes judge the branch head, not the merge ref)"
