# Shared gate artifact classification

Use this reference before implementing product/spec normalization, standards-to-health-gate work, or changes to shared deterministic gates and coordination surfaces.

## Trigger

This gate applies to any change that edits a shared deterministic gate/verifier, including:

- Workspace verifier.
- Conformance script.
- Contract-coverage gate.
- Status-source validator.
- CI harness.
- Continuation-state checker.
- Cross-repo contract/status/version/release/compatibility coordination surface.

It also applies when shared or cross-repo contract/status/version/release/compatibility semantics change, whether the change is made in a named gate/status surface or in runtime code, generated artifacts, config, or scripts.

## Artifact classification

Before implementation, classify the artifact as one of:

- `spec/plan`
- `gate design`
- `gate implementation`
- `status sync`
- `runtime/code`

Do not delegate the spec-vs-plan-vs-code decision to `feature-risk-router`. After artifact classification, route every shared-gate change through `feature-risk-router` and apply its `shared-gate` decision before shared branch push or MR merge.

## Persistent artifact requirement

When a `gate implementation`, `gate design`, or `status sync` change — or any change to shared or cross-repo contract/status/version/release/compatibility semantics, whether made in a named gate/status surface or in runtime code, generated artifacts, config, or scripts — alters the affected rule, scope, failure, or completion semantics, create or cite the persistent implementation-plan artifact before editing.

Accepted artifact forms:

- Implementation plan.
- ADR.
- Status doc.
- Issue/MR description mirrored into a repo-local file.

The plan must be a concrete repo-local path on the next executing agent's read path. Chat-only plans and platform-only issue/MR text are not enough.

The plan must contain:

- Artifact classification.
- Scope.
- Acceptance matrix. For a verifier/gate/status surface that emits a verdict or completion status (`ready`/`not_ready`/`pass`/`fail`/`pending` or equivalent), this matrix must be a decision table mapping its named inputs to one verdict — at least a planned input row per verdict, with executed traces by closeout — not a prose list that only names the fields.
- Test/register coverage.
- Status-sync target.
- Review/challenge gate.

A simple low-risk single-file gate edit that preserves existing semantics may use an inline plan, but the inline plan must state why no rule, scope, failure, or completion semantics changed.

## Verifier discovery

For a `gate implementation`, also discover the plan/status verifier from:

- Repo agent contract.
- README.
- Scripts.
- Makefile/package scripts.
- CI config.
- Explicit status-source validator.

An explicit status-source validator takes precedence. Otherwise run every authoritative non-alias plan/status verifier declared by the agent contract, status source, or CI. One canonical command may cover equivalent wrappers with evidence. Run each authoritative verifier, or record why it is not applicable, before implementation and before claiming the plan active.

If the slice's own purpose is to create the first such verifier, record the absence search and require the newly created verifier to run before claiming the plan active or the slice complete.

If no verifier is discoverable and the slice does not create one, record the search evidence and named artifact path as an open verifier gap. Use `interim` / pending-verification status until a verifier runs or an explicit human waiver is recorded.

## Review and closeout

Local mutation tests and passing verifier output prove script behavior. They do not replace review of whether the gate's rule, scope, and failure semantics are correct when the risk route requires review/challenge.

If the required review/challenge is unavailable after remediation and any approved fallback reviewer also fails to produce valid evidence, stop at `interim` / pending-review status instead of claiming the slice complete.
