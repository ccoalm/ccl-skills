# Review continuation

## Outcome and scope

Necessary review after an in-scope repair continues under the existing task
authority. Five renewed runs trigger a progress check. An explicit user limit,
missing resource or host permission still constrains the next action.

Artifact classification: `gate design` for completion policy;
`gate implementation` for migration of one historical locator using the
existing row-digest exception mechanism. No gate algorithm changes.
Risk tags: `shared-gate`, `release-ops`. Visible surface: no product UI change.
Security posture: no change to credentials, provider access, sensitive data or
host permission enforcement. A review packet cannot grant authority.

The policy owner is `code-review/references/development-completion.md`.
Extraction's entrypoint, quickstart and delta-review instructions route to it.
The runtime controller's per-chain limits and per-invocation timeouts remain.
The npm patch updates only the package's version fields and ships these rules.

## Acceptance decision table

| Input | Required decision | Evidence |
| --- | --- | --- |
| Five renewed passes; a verified in-scope fix changed the candidate; no user limit | Review the changed candidate without new permission | Completion checkpoint and extraction-policy regression |
| Repeated findings; no new evidence or effective repair | Change method or evidence before another call; continue safe independent work | Checkpoint's progress record and existing finding dispositions |
| Explicit user stop, count, cost or time limit prevents the next pass | Honor the limit; ask only for the missing decision or authority | Canonical checkpoint boundary assertions |
| Host denial or unavailable resource | Follow normal recovery; do not bypass or claim pass | Canonical checkpoint and unchanged controller tests |
| Current candidate already has valid review and dispositions | Reuse evidence and finish | Existing completion reuse rule |
| Missing review, unreviewed delta or unresolved P0/P1 | Keep readiness pending | Completion and delta-review rules |
| Exact historical ledger row names the retired five-pass anchor | Resolve through its reviewed, exact-row digest exception | Register resolution and wiring suites |
| New, changed, duplicated or missing row tries to use that exception | Fail | Existing register digest and duplicate-use tests; targeted mutation probe |

## Implementation boundary

Active baseline: this plan and the current feature diff. Implementation owner:
`skill-extraction-workflow`; tests use `testing-strategy`; classification uses
`product-rd-workflow` and `feature-risk-router`. Shared-skill edits use the
extraction owner instead of a product stack owner. One dependent slice; no
delegation. Root agent contract governs the existing paths unchanged.

Baseline evidence: the new extraction regression fails against the old policy.
The existing register checker then identifies the removed historical anchor.
Keep that ledger row byte-identical, append a superseding row and bind the
retirement to its existing SHA-256. No new row may inherit the exception.

Plan verification: repository contracts, Makefile and CI expose the Markdown
link and spec-reference validators. Run both before the metadata migration;
the full repository lane checks the final candidate. No separate status-source
validator applies: this plan specifies behavior and does not assert deployment
state.

## Verification and delivery

| Layer | Work |
| --- | --- |
| Unit/contract | Extraction policy regression; register resolution and production wiring; mutation of the retired-row digest and duplicate-use boundary |
| Integration | Full local `make test`, public sanitization and private R0 audit |
| Package/host | npm test, tarball verification and three-host lifecycle smoke |
| Manual/self-review | Walk the decision table against old and new instructions; preserve explicit limits and evidence requirements |
| Independent | One review and one adversarial challenge; review later deltas under the extraction lane |

Status-sync target: evidence records beside this plan plus current PR, CI, tag
and registry state. Publish only after required checks and review are conclusive,
using the existing protected-main and tag-driven npm workflow. Failed checks
remain visible and are repaired before release. A subsequent patch is the
recovery path for a published defect; no registry version is overwritten.
