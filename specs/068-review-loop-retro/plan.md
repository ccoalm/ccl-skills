# 068 — Review-loop retrospective timeout correction

## Classification and scope

- Artifact: incremental shared-gate correction inside the existing 068
  retrospective candidate. This plan scopes only the final timeout correction;
  it does not replace or narrow the earlier 068 review-loop and Git-metadata
  work already present in the worktree.
- Status: implemented on `worktree-068-review-loop-retro` and opened as PR
  #79 after explicit commit, push, and PR authorization. Merge, release, and
  cleanup remain unauthorized.
- Change: raise the existing generic `--timeout` ceiling from 600 to 1200
  seconds in the review controller and every direct client wrapper.
- Preserve: the 600-second default, client order, fallback rules,
  model/provider selection, `--total-timeout` range and allocation, verdict
  semantics, timeout cleanup, and Kimi inline mode's separate 120-second cap.

## Acceptance matrix

| Input | Controller verdict / effective timeout |
| --- | --- |
| `--timeout` omitted | Accepted; each client keeps the 600-second default. |
| `--timeout 1200` with enough total budget | Accepted; the controller forwards 1200 seconds to the selected wrapper. Existing wrapper-internal sub-mode caps remain unchanged. |
| `--timeout 1201` | Rejected before client execution as `invalid_input`. |
| Direct wrapper receives `1201` or an arbitrarily long decimal | Accepted by the generic input normalizer and clamped to 1200 before shell arithmetic. |
| Total budget cannot fund the requested timeout | Accepted only at the smaller existing per-invocation allocation; the cumulative deadline remains authoritative. |
| Client availability or ordering changes | Out of scope; existing routing decides the selected client. |

## Test and status coverage

- Add a RED-first controller regression for 1200 acceptance, 1201 rejection,
  unchanged default, and cumulative-budget capping.
- Pin every wrapper's direct-invocation default and generic upper bound; run
  the affected wrapper tests plus the full code-review lane.
- Synchronize `skills/code-review/SKILL.md`, `client-routing.md`,
  `staged-review-contract.md`, `timeout-auth-and-capabilities.md`, and the
  extraction source register with the executable behavior.
- Run focused tests, `make test`, the heavy lane, public sanitization, and
  `git diff --check` on the final candidate.

## Review gate

Risk tag: `shared-gate`. Before completion, walk the asserted properties and
their killing mutations, then run one independent review and up to two
adversarial challenges through the extraction-owned wrapper against the exact
final candidate. A timeout or malformed reviewer result remains inconclusive,
not approval.
