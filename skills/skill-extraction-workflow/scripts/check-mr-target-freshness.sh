#!/usr/bin/env bash
# MR target-branch freshness gate.
#
# Failure class this blocks: a delivery branched off — and an MR targeted at — an
# integration branch that is no longer live. The observed instance: `dev` sat at
# 0 commits ahead of `main` and 279 behind, still carried the pre-slimming
# entrypoints, and ran an ADVISORY copy of the size gate that `main` runs as
# BLOCKING. An MR merged there is invisible on the real integration branch and
# silently bypasses whatever gates the default branch has since tightened.
#
# Predicate (decidable from git alone — no repo-policy knowledge, no API):
#   target is NOT the default branch
#   AND target is 0 commits AHEAD of the default branch   (carries nothing of its own)
#   AND target is >= STALE_BEHIND_MIN commits BEHIND it   (meaningfully abandoned)
#
# Both conjuncts matter. "Behind the default branch" alone would flag every
# legitimate long-lived target; the 0-ahead conjunct is what makes it precise:
#   - release/x.y while it carries cherry-picks or version bumps the default
#     lacks => ahead > 0 => never fires. A maintained release branch whose
#     patches have ALL been merged forward is legitimately 0-ahead and topology
#     cannot distinguish it from an abandoned mirror — that case is what
#     MR_TARGET_FRESHNESS_ALLOW exists for — a declared exemption, not an
#     authority check (see the enforcement boundary below).
#   - promote/* cut off the default — ahead-or-equal by construction, not behind
#     => never fires.
#   - a stacked MR targeting another feature branch — that branch has its own
#     commits => never fires.
#   - a dead mirror like `dev` — 0 ahead, far behind => fires.
# Scored against every remote branch in this repo when the gate was written:
# only the genuinely dead ones matched.
#
# Not an MR pipeline => no-op. Refs unresolvable, default branch undetermined,
# fork MR, or STALE_BEHIND_MIN malformed => fail CLOSED (exit 1): a gate that
# paints the job green while printing "not a pass" is the false-green this whole
# gate exists to prevent.
#
# ENFORCEMENT BOUNDARY — read before trusting this as a control.
# A merge-request pipeline runs the `.gitlab-ci.yml` of the SOURCE branch, and
# the merge request owns that file. Two consequences, both verified:
#   1. A branch cut from a stale base carries that base's CI config. `dev` has no
#      `check-mr-target-freshness` job at all, so an MR sourced from a dev-based
#      branch never creates this job — which is exactly the shape that motivated
#      the gate (MR !510). This script CANNOT catch that case.
#   2. EVERY input it reads can be overridden from candidate-owned YAML —
#      `CI_DEFAULT_BRANCH`, `MR_TARGET_FRESHNESS_ALLOW`, `STALE_BEHIND_MIN`,
#      `CI_MERGE_REQUEST_TARGET_BRANCH_NAME`, and both project-ID variables the
#      fork check reads. So the target and fork predicates are candidate-
#      influenced too, not just the allowlist and the threshold. No shell script
#      can establish that a variable came from a maintainer.
# So this is DEFENCE IN DEPTH, not an enforceable gate. What it does buy: a
# branch cut from a current base that is then mis-targeted at a dead branch gets
# caught, and the failure class becomes visible in CI output instead of being
# noticed only in review. Actually closing the class needs enforcement the merge
# request cannot replace — a project- or group-level required/compliance
# pipeline, or a server-side merge rule — which is a maintainer setting outside
# this repository's files. Do not describe this script as closing the class.
set -euo pipefail

root="${1:-$(pwd)}"
cd "$root"

target="${CI_MERGE_REQUEST_TARGET_BRANCH_NAME:-}"
if [ -z "$target" ]; then
  echo "mr_target_freshness_skipped: not a merge-request pipeline"
  exit 0
fi

default="${CI_DEFAULT_BRANCH:-}"
if [ -z "$default" ]; then
  default="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)"
fi
if [ -z "$default" ]; then
  # Guessing "main" here would compare against a branch that may not be the
  # default at all. An undetermined default branch is an unevaluated gate.
  echo "mr_target_freshness_unevaluated: default branch is undetermined (CI_DEFAULT_BRANCH unset and origin/HEAD unresolvable) — this is NOT a pass" >&2
  exit 1
fi

# A fork MR's `origin` is the fork; the target branch lives in the upstream
# project, so same-named refs here would measure an unrelated branch.
src_pid="${CI_MERGE_REQUEST_SOURCE_PROJECT_ID:-}"
tgt_pid="${CI_MERGE_REQUEST_PROJECT_ID:-}"
if [ -n "$src_pid" ] || [ -n "$tgt_pid" ]; then
  if [ -z "$src_pid" ] || [ -z "$tgt_pid" ]; then
    # One present and one missing means the fork question cannot be answered;
    # treating that as same-project would be fail-open.
    echo "mr_target_freshness_unevaluated: incomplete merge-request project metadata (source='$src_pid' target='$tgt_pid') — cannot determine whether this is a fork; this is NOT a pass" >&2
    exit 1
  fi
  if [ "$src_pid" != "$tgt_pid" ]; then
    echo "mr_target_freshness_unevaluated: fork merge request (source project $src_pid != target project $tgt_pid) — origin is the fork, so its branches are not the target project's; this is NOT a pass" >&2
    exit 1
  fi
fi

if [ "$target" = "$default" ]; then
  echo "mr_target_freshness_ok: target=$target is the default branch"
  exit 0
fi

# A live integration target that is legitimately 0-ahead — e.g. a maintained
# release branch whose hotfixes have all been merged forward — cannot be told
# apart from an abandoned mirror by topology alone, so it needs a declared
# exemption. Intended to be set as a project CI variable; note that nothing
# here can enforce that, because candidate-owned YAML can set it too (see the
# enforcement boundary above). It is a declaration, not an authority check.
# `set -f` so a branch name is compared literally: an unquoted expansion would
# glob against the working tree and silently change allowlist membership.
set -f
for allowed in ${MR_TARGET_FRESHNESS_ALLOW:-}; do
  if [ "$target" = "$allowed" ]; then
    set +f
    echo "mr_target_freshness_ok: target=$target is in MR_TARGET_FRESHNESS_ALLOW (maintainer-declared live integration branch)"
    exit 0
  fi
done
set +f

stale_behind_min="${STALE_BEHIND_MIN:-50}"
case "$stale_behind_min" in
  '' | *[!0-9]*)
    echo "mr_target_freshness_misconfigured: STALE_BEHIND_MIN='$stale_behind_min' is not a non-negative integer — refusing to run rather than silently passing" >&2
    exit 1
    ;;
esac
# Digits alone are not enough: a value wider than a machine integer makes the
# `-ge` test abort with "integer expected", and because that abort happens in an
# `if` condition it is exempt from `set -e` and falls through to the ok path.
if [ "${#stale_behind_min}" -gt 9 ]; then
  echo "mr_target_freshness_misconfigured: STALE_BEHIND_MIN='$stale_behind_min' exceeds 9 digits — refusing rather than risking the numeric comparison aborting into a pass (not every such value overflows; 9 digits is a conservative bound, well above any real commit count)" >&2
  exit 1
fi

# ALWAYS force-fetch both refs. A reused runner checkout can carry a stale
# origin/<branch>, and measuring against historical topology is how a
# now-dead target would score as healthy.
# One fetch for both refspecs: two sequential fetches can observe two different
# moments. This narrows the window; it does not close it — a push to either
# branch after measurement can still leave a stale verdict, which is why this
# gate is a check on the MR as opened, not a merge-time invariant.
fetch_ok=1
git fetch --quiet --no-tags --force origin \
  "+refs/heads/$target:refs/remotes/origin/$target" \
  "+refs/heads/$default:refs/remotes/origin/$default" 2>/dev/null || fetch_ok=0

if [ "$fetch_ok" -eq 0 ] \
  || ! git rev-parse --verify --quiet "refs/remotes/origin/$target" >/dev/null \
  || ! git rev-parse --verify --quiet "refs/remotes/origin/$default" >/dev/null; then
  # Fail CLOSED. Exiting 0 here would paint the job green while the log says
  # "not a pass", which is the false-green this gate exists to prevent. This
  # repo clones with GIT_DEPTH: "0", so both refs are reachable in a healthy
  # pipeline; an unresolvable ref is a real problem, not routine noise.
  echo "mr_target_freshness_unevaluated: could not resolve origin/$target or origin/$default — this is NOT a pass, and the gate fails closed" >&2
  echo "  if the target genuinely lives in another project (fork MR), fetch it explicitly or declare it in MR_TARGET_FRESHNESS_ALLOW" >&2
  exit 1
fi

ahead="$(git rev-list --count "origin/$default..origin/$target")"
behind="$(git rev-list --count "origin/$target..origin/$default")"

echo "mr_target_freshness: target=$target default=$default ahead=$ahead behind=$behind threshold=$stale_behind_min"

if [ "$ahead" -eq 0 ] && [ "$behind" -ge "$stale_behind_min" ]; then
  {
    echo "mr_target_freshness_stale: target branch '$target' carries nothing the default branch '$default' lacks (ahead=0) and is $behind commits behind it"
    echo "  why this blocks: merging here does not reach '$default', and '$target' may still run older/weaker versions of the repo's gates than '$default' does"
    echo "  fix: retarget this MR to '$default', and rebase or re-cut the source branch off '$default'"
    echo "  if '$target' really is a live integration branch that is legitimately 0-ahead (all its patches merged forward), a maintainer declares it in MR_TARGET_FRESHNESS_ALLOW"
  } >&2
  exit 1
fi

echo "mr_target_freshness_ok"
