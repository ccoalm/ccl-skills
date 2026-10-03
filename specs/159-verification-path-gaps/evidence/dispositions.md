# 159 review dispositions

Every pass ran through `extraction_review_gate.sh`. The round's register rows
land in the last content commit, so the delta pass after the challenge holds a
file the extraction lane owns.

## Pass 1 — review (codex), base `origin/main`, reviewed commit `8dd869a`: 4 × P2

Record: `pass1-review.json`.

| # | Sev | Finding | Disposition | Where |
| --- | --- | --- | --- | --- |
| 1 | P2 | The packet does not show that a changed carrier makes re-rendering fail, so the fix hint's safety is unverified | fixed: a guard renders after carrier mutations and expects the audit to keep failing with each mutation's own code; with the mutation replaced by a no-op the guard fails on `audit_ok`, so it can catch what it claims | `test_obligation_ledger.sh`, `42d74ad` |
| 2 | P2 | The generic delta call's chain semantics are unshown, and "nothing else reads" the chain id is unsupported | fixed: the unsupported claim is gone. The step now says the controller requires the chain for a high-risk review and that its suggested challenge is not owed. The existing high-risk chain case in `test_review_gate.sh` pins the call's admission: rc 0, tracked chain, `next_action=run_challenge` | `dual-track-review-gate.md`, `42d74ad` |
| 3 | P2 | Array membership alone does not show the drift failing `make test` and CI | packet boundary: the same one-line shift passes main's fast lane and fails the candidate's on exactly the repo audit, through the real entrypoint (validation record); CI's fast job runs that entrypoint with full history | validation record |
| 4 | P2 | The `AGENTS.md` command's parity with the pull-request check is unshown | packet boundary: CI runs the same script with the PR base. The checker diffs base to HEAD and needs one conclusive review result among the changed evidence files; a stale local base only adds subjects, so a local run can be stricter, never looser | `check_review_evidence_present.py`, `ci.yml` |

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
| 2 | P2 | Stopping a generic chain after its review is not shown to leave readiness unblocked | no change: nothing consumes the chain's remaining challenge. The pull-request check counts conclusive results only, and round 158's pull request passed CI with two delta passes recorded exactly this way | `check_review_evidence_present.py`; round 158 evidence |
| 3 | P2 | Shallow checkouts, other lanes, registration and timing are unverified | accepted with evidence: the registration audit and both lanes run in `make test` and the heavy lane on the final commit (below). A shallow clone now fails the fast lane closed with "needs full history (fetch-depth: 0)" instead of only the heavy lane; every CI job already fetches full history | lane results below |
| 4 | P2 | The local command leaves HEAD implicit and may not match CI's merge revision | no change: as for pass 1 finding 4, a local run on the commit being pushed can only be stricter than CI's check of the same change | `AGENTS.md` |
