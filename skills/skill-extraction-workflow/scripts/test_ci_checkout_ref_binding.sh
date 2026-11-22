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

# PR text is mutable without a new commit. The metadata gate must rerun when a
# title or body edit is the only event, not only when the branch SHA changes.
trigger = re.search(r"^  pull_request:\s*\n((?: {4}.*\n)*)", src, re.M)
if trigger is None or not re.search(r"\bedited\b", trigger.group(1)):
    print(
        "FAIL: pull_request trigger does not include `edited`; PR text changes "
        "would bypass the shared Git/PR metadata gate",
        file=sys.stderr,
    )
    sys.exit(1)

# The shared metadata gate is also the backstop for authorized direct landing
# pushes. Both landing branches must trigger CI; the local hook is opt-in.
push_trigger = re.search(r"^  push:\s*\n((?: {4}.*\n)*)", src, re.M)
branches = set()
if push_trigger is not None:
    branch_row = re.search(r"branches:\s*\[([^]]*)\]", push_trigger.group(1))
    if branch_row is not None:
        branches = {item.strip() for item in branch_row.group(1).split(",") if item.strip()}
missing_push_branches = {"dev", "main"} - branches
if missing_push_branches:
    print(
        "FAIL: push trigger does not cover landing branch(es): "
        + ", ".join(sorted(missing_push_branches)),
        file=sys.stderr,
    )
    sys.exit(1)

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

repository_body = bounds.get("repository-gates", "")
step_start = re.search(
    r"^      - name:\s*Repository gate suite\s*$", repository_body, re.M
)
repository_step = ""
if step_start is None:
    failures.append(
        "repository-gates: `Repository gate suite` step is missing"
    )
else:
    next_step = re.search(r"^      - ", repository_body[step_start.end() :], re.M)
    step_end = (
        step_start.end() + next_step.start()
        if next_step is not None
        else len(repository_body)
    )
    repository_step = repository_body[step_start.start() : step_end]

if repository_step:
    if not re.search(
        r"^\s+CANDIDATE_BASE_REF:\s*\$\{\{\s*"
        r"github\.event\.pull_request\.base\.sha\s*\|\|\s*"
        r"github\.event\.before\s*\}\}\s*$",
        repository_step,
        re.M,
    ):
        failures.append(
            "repository-gates: `Repository gate suite` does not bind the PR "
            "base SHA with the pre-push event fallback; the commit range could "
            "collapse to HEAD and silently scan zero candidate commits"
        )
    if not re.search(
        r'^\s+if\s+\[\[\s+-n\s+"\$CANDIDATE_BASE_REF"\s+\]\]\s+&&\s+'
        r'git\s+merge-base\s+"\$CANDIDATE_BASE_REF"\s+HEAD\s+'
        r'>/dev/null\s+2>&1;\s+then\s*$\n'
        r'^\s+export\s+CCL_SKILL_BASE_REF="\$CANDIDATE_BASE_REF"\s*$\n'
        r'^\s+fi\s*$\n'
        r"^\s+make test-repo-gates\s*$",
        repository_step,
        re.M,
    ):
        failures.append(
            "repository-gates: `Repository gate suite` must validate the "
            "candidate base, export it, then invoke `make test-repo-gates` in "
            "that order; otherwise the metadata gate can scan the wrong range"
        )

if failures:
    for f in failures:
        print(f"FAIL: {f}", file=sys.stderr)
    sys.exit(1)
PY

SETUP_ACTION="$ROOT/.github/actions/setup-validation-tools/action.yml"
[ -f "$SETUP_ACTION" ] || fail "composite action not found: $SETUP_ACTION"
python3 - "$CI" "$SETUP_ACTION" $GATE_JOBS <<'PY'
import pathlib, re, sys, yaml

ci_path = pathlib.Path(sys.argv[1])
action_path = pathlib.Path(sys.argv[2])
gate_jobs = sys.argv[3:]

ci_doc = yaml.safe_load(ci_path.read_text(encoding="utf-8"))
action_doc = yaml.safe_load(action_path.read_text(encoding="utf-8"))
if not isinstance(ci_doc, dict) or not isinstance(ci_doc.get("jobs"), dict):
    print("FAIL: ci.yml must parse to a mapping with jobs", file=sys.stderr)
    sys.exit(1)
if not isinstance(action_doc, dict) or not isinstance(action_doc.get("runs"), dict):
    print("FAIL: setup-validation-tools/action.yml must parse to a mapping with runs", file=sys.stderr)
    sys.exit(1)
if action_doc["runs"].get("using") != "composite":
    print("FAIL: setup-validation-tools/action.yml runs.using must be composite", file=sys.stderr)
    sys.exit(1)

def _has_hosted_py_action(step: object) -> bool:
    if not isinstance(step, dict):
        return False
    uses = str(step.get("uses") or "").strip()
    return uses.startswith("actions/setup-python@") or "/actions/setup-python@" in uses

# eval/skill-effectiveness/{bridge,reviewer_calibration_protocol}.py reject any
# group- or world-writable sys.executable (`_reject_shared_write_access`).
# GitHub's actions/setup-python unpacks /opt/hostedtoolcache/Python/... with
# 0775 (group-writable) binaries, breaking repository-gates eval tests.
for job_name, job_cfg in ci_doc["jobs"].items():
    steps = (job_cfg or {}).get("steps") or []
    for step in steps:
        if _has_hosted_py_action(step):
            print(
                f"FAIL: ci.yml job {job_name} uses actions/setup-python, which switches python3 to "
                "group-writable /opt/hostedtoolcache binaries rejected by eval manifest probes",
                file=sys.stderr,
            )
            sys.exit(1)

for job_name in gate_jobs:
    steps = ((ci_doc["jobs"].get(job_name) or {}).get("steps")) or []
    if not any(
        isinstance(s, dict) and str(s.get("uses") or "").strip() == "./.github/actions/setup-validation-tools"
        for s in steps
    ):
        print(
            f"FAIL: ci.yml gate job {job_name} does not invoke ./.github/actions/setup-validation-tools",
            file=sys.stderr,
        )
        sys.exit(1)

action_steps = action_doc["runs"].get("steps") or []
if not isinstance(action_steps, list) or not action_steps:
    print("FAIL: setup-validation-tools/action.yml runs.steps must be a non-empty list", file=sys.stderr)
    sys.exit(1)

for step in action_steps:
    if _has_hosted_py_action(step):
        print(
            "FAIL: setup-validation-tools/action.yml uses actions/setup-python, which switches python3 to "
            "group-writable /opt/hostedtoolcache binaries rejected by eval manifest probes",
            file=sys.stderr,
        )
        sys.exit(1)

has_pip_cache = False
perm_check_idx = None
pip_install_idx = None
perm_line_re = re.compile(
    r"^python3\s+-c\s+.*os\.path\.realpath\(sys\.executable\).*os\.lstat\(.*S_IWGRP.*S_IWOTH"
)

for idx, step in enumerate(action_steps):
    if not isinstance(step, dict):
        continue
    uses = str(step.get("uses") or "").strip()
    with_cfg = step.get("with") if isinstance(step.get("with"), dict) else {}
    if (
        uses.startswith("actions/cache@")
        and step.get("if") is None
        and str(with_cfg.get("path") or "").strip() == "~/.cache/pip"
        and "hashFiles('requirements-test.txt')" in str(with_cfg.get("key") or "")
    ):
        has_pip_cache = True
    run_script = step.get("run")
    if isinstance(run_script, str) and str(step.get("shell") or "").strip() == "bash":
        active_lines = [
            ln.strip()
            for ln in run_script.splitlines()
            if ln.strip() and not ln.lstrip().startswith("#")
        ]
        if any(perm_line_re.search(ln) for ln in active_lines):
            perm_check_idx = idx
        if any("pip install" in ln and "requirements-test.txt" in ln for ln in active_lines):
            pip_install_idx = idx

if not has_pip_cache:
    print(
        "FAIL: setup-validation-tools/action.yml must have an unconditional actions/cache step "
        "with path ~/.cache/pip and key containing hashFiles('requirements-test.txt')",
        file=sys.stderr,
    )
    sys.exit(1)

if perm_check_idx is None or pip_install_idx is None or perm_check_idx > pip_install_idx:
    print(
        "FAIL: setup-validation-tools/action.yml must execute an active python3 sys.executable "
        "S_IWGRP/S_IWOTH lstat check before installing requirements-test.txt",
        file=sys.stderr,
    )
    sys.exit(1)
PY

default_make_dry_run="$(make --no-print-directory -n -C "$ROOT" test-repo-gates)"
override_make_dry_run="$(
  make --no-print-directory -n -C "$ROOT" \
    CCL_SKILL_DEFAULT_BASE_REF=refs/remotes/upstream/dev test-repo-gates
)"
python3 - "$default_make_dry_run" "$override_make_dry_run" <<'PY'
import shlex
import sys


def default_base(dry_run: str) -> str:
    commands = [
        line
        for line in dry_run.splitlines()
        if "shared_git_surface_gate.py" in line
    ]
    if len(commands) != 1:
        raise SystemExit(
            "FAIL: test-repo-gates must invoke the shared Git/PR metadata gate once"
        )
    tokens = shlex.split(commands[0])
    if tokens.count("--default-base-ref") != 1:
        raise SystemExit(
            "FAIL: test-repo-gates must pass exactly one --default-base-ref"
        )
    index = tokens.index("--default-base-ref")
    if index + 1 >= len(tokens):
        raise SystemExit("FAIL: --default-base-ref has no value")
    return tokens[index + 1]


default_value = default_base(sys.argv[1])
override_value = default_base(sys.argv[2])
if default_value != "origin/dev":
    raise SystemExit(
        f"FAIL: test-repo-gates compatibility default is {default_value!r}, "
        "expected 'origin/dev'"
    )
if override_value != "refs/remotes/upstream/dev":
    raise SystemExit(
        f"FAIL: caller default-base override resolved to {override_value!r}, "
        "expected 'refs/remotes/upstream/dev'"
    )
PY

echo "test_ci_checkout_ref_binding: ok (gate lanes judge the branch head, not the merge ref)"
