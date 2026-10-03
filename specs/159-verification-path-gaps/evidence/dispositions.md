# 159 review dispositions

Passes 1–3 ran through `extraction_review_gate.sh`. The round's register rows
land in the last content commit, so the delta pass after the challenge held a
file the extraction lane owns. Later deltas changed only `AGENTS.md`, so they
ran through the generic controller, as the delta-pass step now describes.

## Pass 1 — review (codex), base `origin/main`, reviewed commit `8dd869a`: 4 × P2

Record: `pass1-review.json`.

| # | Sev | Finding | Disposition | Where |
| --- | --- | --- | --- | --- |
| 1 | P2 | The packet does not show that a changed carrier makes re-rendering fail, so the fix hint's safety is unverified | fixed: a guard renders after carrier mutations and expects the audit to keep failing with each mutation's own code; with the mutation replaced by a no-op the guard fails on `audit_ok`, so it can catch what it claims | `test_obligation_ledger.sh`, `42d74ad` |
| 2 | P2 | The generic delta call's chain semantics are unshown, and "nothing else reads" the chain id is unsupported | fixed: the unsupported claim is gone. The step now says the controller requires the chain for a high-risk review and that its suggested challenge is not owed. The existing high-risk chain case in `test_review_gate.sh` pins the call's admission: rc 0, tracked chain, `next_action=run_challenge` | `dual-track-review-gate.md`, `42d74ad` |
| 3 | P2 | Array membership alone does not show the drift failing `make test` and CI | packet boundary: the same one-line shift passes main's fast lane and fails the candidate's on exactly the repo audit, through the real entrypoint (validation record); CI's fast job runs that entrypoint with full history | validation record |
| 4 | P2 | The `AGENTS.md` command's parity with the pull-request check is unshown | first disposed as "a local run can only be stricter"; pass 3 refuted that and the command changed (pass 3, finding 4) | `AGENTS.md` |

## Pass 2 — challenge (codex), base `origin/main`, reviewed commit `bf57f27`: 4 × P2

Focus: whether the printed command can clear a lost or weakened obligation or
be built wrong from caller arguments; whether the lane move breaks shallow
checkouts, other lanes, registration or CI timing; whether the documented
delta call is correct and consistent with the dual-track rules; parity of the
`AGENTS.md` command; any loosened gate or unneeded switch, judged against the
requester's words. Record: `pass2-challenge.json`.

- Gate-fireability applicability: yes — the round moves a gate between lanes
  and changes what two failures tell the agent to do.
- Item 9 exercised: yes — the focus asks whether the hint can clear a dropped
  obligation (a bypass of the audit by regeneration).

| # | Sev | Finding | Disposition | Where |
| --- | --- | --- | --- | --- |
| 1 | P2 | The guard covers parent and fence mutations but not a weakened obligation; replay with `--head`, refs or relative paths is unshown | fixed in part: the guard adds the qualifier-weakening mutation, which keeps failing with `QUALIFIER_WEAKENED` after a render. The hint echoes the caller's own arguments, `--head` included when given; the real-repository run with `--head` cleared the stale ledger as printed (validation record) | `test_obligation_ledger.sh` |
| 2 | P2 | Stopping a generic chain after its review is not shown to leave readiness unblocked | no change: outside the controller, only the pull-request reminder hook reads a result's `next_action`, and it never blocks. CI's check counts conclusive results only; round 158's pull request passed CI with two delta passes recorded this way | `hooks/remind-review-covers-head.sh`, `check_review_evidence_present.py` |
| 3 | P2 | Shallow checkouts, other lanes, registration and timing are unverified | accepted with evidence: the registration audit and both lanes run in `make test` and the heavy lane on the final commit (below). A shallow clone now fails the fast lane closed with "needs full history (fetch-depth: 0)" instead of only the heavy lane; every CI job already fetches full history | lane results below |
| 4 | P2 | The local command leaves HEAD implicit and may not match CI's merge revision | fixed after pass 3, finding 4 | `AGENTS.md` |

## Pass 3 — delta review (codex), base `bf57f27`, reviewed commit `69f9ec0`: 4 × P2

Run through `extraction_review_gate.sh`: the delta holds the register rows, a
file the extraction lane owns. The packet quoted the four challenge findings
verbatim as open items. Record: `pass3-delta.json`.

| # | Sev | Finding | Disposition | Where |
| --- | --- | --- | --- | --- |
| 1 | P2 | The guard's body and the tool's paths are outside the packet, so a guard that checks only the pre-render failure cannot be ruled out | packet boundary: the guard body landed before `bf57f27` and was in the challenge's packet; it runs the audit after the render, and the no-op control fails it on `audit_ok` | `test_obligation_ledger.sh` |
| 2 | P2 | "Nothing consumes the chain's remaining challenge" is an absence claim | fixed in the record: a repository search finds one reader of `next_action` outside the controller, the non-blocking reminder hook (pass 2, finding 2) | this file |
| 3 | P2 | The register row's lane claim lacks wiring evidence, and "lane results below" pointed at nothing | fixed: the lane results are recorded below on the final commit; a shallow clone was probed and the audit fails closed with "needs full history (fetch-depth: 0)" | this file |
| 4 | P2 | A stale local base can include an already-landed review result, so the local check can pass where CI fails; "never looser" does not follow | confirmed and fixed: against a base three merges old, a branch with no evidence of its own passed with 8 reviews from landed rounds; with the merge-base of the current target it failed as CI would. `AGENTS.md` now says to fetch the target and use the merge-base | `AGENTS.md` |

## Pass 4 — delta review (codex), base `69f9ec0`, reviewed commit `3f0c70b`: 2 × P2

The delta held no file the extraction lane owns, so it ran through the generic
controller with the round's plan and risk tag, `--review-chain-id
pr-159-delta2` and `--autonomous-review-index 1`, as the delta-pass step now
describes. The controller admitted it and a reviewer returned findings. Record:
`pass4-delta.json`.

| # | Sev | Finding | Disposition | Where |
| --- | --- | --- | --- | --- |
| 1 | P2 | A branch reused after a squash merge keeps a merge-base older than the landed review, so the local check can still pass where CI fails; parity with CI's diff is not established | wording fixed: the line no longer claims parity and keeps only the fetch warning. The squash-reuse false green stays open as a residual: the local command can pass where CI fails for a branch reused after its review landed by squash. 35 of the last 40 first-parent commits on main are merge commits, which keep a branch's commits in main's history; this is observed practice, not an enforced rule | `AGENTS.md` |
| 2 | P2 | "Lane results below" still points at nothing | fixed: the lane results follow | this file |

## Pass 5 — delta review (codex), base `3f0c70b`, reviewed commit `cbc2ab4`: 2 × P2

Generic controller with `--review-chain-id pr-159-delta3`; the delta deleted
one clause from `AGENTS.md`. Record: `pass5-delta.json`. Both findings concern
this record, which owes no further pass.

| # | Sev | Finding | Disposition | Where |
| --- | --- | --- | --- | --- |
| 1 | P2 | Pass 4 finding 1 was marked fixed although only its wording was corrected, and the merge-practice remark was unsupported | fixed in this record: pass 4 finding 1 now reads "wording fixed", with the squash-reuse false green left open as a residual and the merge-commit count as observed practice | this file |
| 2 | P2 | The lane results are still missing | fixed: they follow | this file |

## Pass 6 — delta review (codex) after the rebase onto round 158, base `8e312ee`, reviewed commit `c11cf43`: 3 × P2

Round 158's pull request merges first, so this branch was rebased onto its
head `8e312ee`. Two files conflicted because both rounds inserted at the same
place: `test_review_gate.sh` (round 158's three focus and egress cases, then
this round's refusal case) and `source-register.md` (round 158's three rows,
then this round's two). Both sides were kept. The last commit bumps the npm
package to 0.18.10 for the release that follows both merges. The delta pass
ran through `extraction_review_gate.sh` on the two resolved files and the two
package files. Record: `pass6-delta.json`.

| # | Sev | Finding | Disposition | Where |
| --- | --- | --- | --- | --- |
| 1 | P2 | The packet shows one resolved case and part of another, so exact-once preservation and a passing suite are not shown | evidence supplied: each of the four case names occurs exactly once; both resolved blocks are byte-identical to their source commits (`8e312ee` and `1bf9e54`); the file parses with `bash -n`; the suite result is in the lanes below | `test_review_gate.sh` |
| 2 | P2 | The register rows' preservation and anchors are not shown against `8e312ee` | evidence supplied: round 158's three rows and this round's two rows are byte-identical to their source commits; `check-ccl-skills.sh` with base `8e312ee` ends `ccl_skill_check_clean_ok`, impact-chain gate included | `source-register.md` |
| 3 | P2 | `packages/AGENTS.md` requires `npm-test`, `npm-pack-verify` and `npm-publish-dry` for a package change | run: `make npm-publish-dry` covers all three (`npm ci`, `npm test`, `test:pack`, `pack --dry-run`); result in the lanes below | `packages/ccl-skills-npm` |

The sorted added and removed lines of this round's change are identical before
and after the rebase (16 files, 353 insertions, 8 deletions), and the
controller diff between `8e312ee` and the rebased head is only this round's
refusal message.

## Verification lanes

On `69f9ec0`, in a detached checkout with `CCL_SKILL_BASE_REF=origin/main` and
`GITHUB_HEAD_REF` set as CI sets them:

- `make -k test`: exit 0. `ccl_skill_check_clean_ok` and
  `shared_git_surface_gate_ok` in the repo gates; `regression_fast_lane_ok:
  45 suites`, one more than before because the repo ledger audit now runs
  there; `code_review_shard_1_ok`, `code_review_shard_2_ok` and
  `review_gate_abort_leak_ok` for both legs.
- `test_check_ccl_regressions.sh --heavy-only`: `regression_heavy_lane_ok:
  9 suites`, one fewer for the same reason.

The commits after `69f9ec0` change one `AGENTS.md` line and these records; the
repository gates ran again on the final commit before the pull request.

After the rebase onto `8e312ee` and the version bump (`c11cf43`):

- `check-ccl-skills.sh` with base `8e312ee`: `ccl_skill_check_clean_ok`.
- `test_review_gate.sh`: `review_gate_tests_ok`.
- `make npm-publish-dry`: exit 0. `npm test` 432 of 432 pass, `test:pack` 11
  of 11, and `npm pack --dry-run` lists 709 files for `@ccoalm/ccl-skills`
  0.18.10.
