# Dormant Code Activation

Use this reference when a delivery slice activates previously-unused, disabled, orphaned, or never-shipped code.

## Trigger

Treat these as behavior-changing delivery slices by default:

- Flipping a feature flag on.
- Uncommenting an old module.
- Wiring an orphaned helper into a real caller.
- Enabling a disabled branch.

They are not harmless config flips just because the code already exists.

## First Check

Before activating the path, read why it was dormant. Common causes include:

- Stale or renamed imports.
- Signature or contract drift.
- Code abandoned as buggy.
- Intentional product, security, or kill-switch removal.

If the code was deliberately removed or disabled, especially for product, security, or kill-switch reasons, clear that original rationale before resurrecting it.

If activation touches security, permission, or data paths, route the slice through `feature-risk-router` before implementation.

## Verification Ladder

A passing mock-backed unit test or green config check does not prove a dormant path works.

Verify the real end-to-end resolution chain with actual imports and wiring, but keep execution in an isolated sandbox or staging environment with synthetic or scrubbed fixtures and no production credentials by default. Running never-shipped, possibly side-effecting code against live services or production data is a release gate with owner, rollback, observability, and permission requirements.

Import or resolution reachability is a prerequisite, not acceptance. Use the owning stack skill for per-stack mechanics, such as Python import checks, Go `go list`, web dependency graph checks, or Flutter `dart analyze` plus targeted source checks. Acceptance still needs behavior assertions, negative and edge cases, and risk-matched review.

Scale runtime proof to risk:

- Pure, side-effect-free, contract-local helpers may mark E2E or host smoke as `not applicable` with reason in the test-layer table.
- Routing, permission, data, or IO paths require runtime or integration evidence matched to the risk.
- Feature flags define the rollout boundary and evidence sequence; they do not waive real-chain verification. Use the same evidence ladder: sandbox chain proof → disabled/internal-flag proof → staged/canary enablement → rollout evidence.

## Routing

- `testing-strategy` owns real-chain-vs-mocks test mechanics and the test-layer table.
- `feature-risk-router` owns security, permission, data-touching, write-finality, and unclear verification scope escalation.
- `platform-release-engineering`, `platform-observability`, and the owning stack skill apply when activation reaches live or pre-ramp environments.
