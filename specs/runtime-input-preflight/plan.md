# Runtime input preflight

Status: implementation; repository checks observed; independent review and challenge pending.
Artifact classification: gate design and gate implementation guidance.
Risk tags: shared-gate, ai-output. Security posture unchanged; no new authorization
or production admission. No new safety-sensitive input is introduced.

## Charter and placement

Purpose: prevent avoidable live rounds caused by hand-assembled requests with missing
retained-file bindings or prescribed routes/actions unsupported by current evidence.
Scope: input construction and its pre-dispatch firing point. Depth: targeted tooling
and guidance change. Result: failure/correction, not proven general agent improvement.
Evidence: synthetic request/transport tests and observed driver failures retained
privately. Exclude product names, credentials, private identifiers and copied schemas.
Completion: negative/control behavior, exact-candidate review/challenge, repository
checks and private leakage audit; unresolved gates remain explicit.

| Target | Decision and mechanism |
| --- | --- |
| testing-strategy | Add pre-dispatch invocation at live-test execution; recipe in existing E2E reference |
| llm-inference-integration | Distinguish generation constraints from runtime argument/state validation in tool-dispatch owner |
| skill-extraction-workflow | Place repeated driver-input prevention on the request-builder transition; route recipe to testing |
| Node/Go/Python implementation owners | route-to-shared; the rule is language-neutral, with no distinct stack mechanism |
| product-rd / feature-risk | Existing shared-gate classification suffices; no lifecycle-policy change |
| design/release/observability | unchanged; no visible, deployed or telemetry boundary |
| product-specific test repository | Own executable preflight and current schema/state adapters; never ship them here |

## Decision and evidence matrix

| Input | Decision |
| --- | --- |
| Retained source binding omitted/mismatched | Reject before request emission |
| Forced tool/action unsupported or evidence unknown | Reject that prescribed input; do not widen admission |
| Owning schema/state validation refuses | Reject before request emission |
| Validated input changes before send | Send its immutable validated snapshot only |
| Correct input and matching durable record | Dispatch once through the normal entry |
| Model generates a malformed call after valid input | Runtime refusal remains mandatory; input preflight is not semantic proof |

An initial synthetic no-op dispatcher failed seven of ten tests for binding/tool/
validator/snapshot behavior. Its gated counterpart passed all ten; the real sender
integration baseline also emitted a request that the negative test required to reject.
Record exact commands and final results in evidence/validation.md. These measurements
prove executable preflight behavior, not statistical improvement in model compliance.
Keep historical assisted failures separate from any future unassisted acceptance.

Consolidation: preserve existing fixture isolation, live-lane marking and typed tool
errors. The shared testing recipe owns input preflight; inference owns the generation
boundary; extraction owns placement. Do not restate product field enums or add a runner.
The source-register rows name changed normative anchors and these evidence limits.
The testing entrypoint exceeds its size and word budgets. Keep only the short execution
invocation there, put input details in the E2E reference, and relocate its existing
file-output cleanup paragraph verbatim to the canonical test-data reference. The
entrypoint shrinks; its new file-output pointer fires before test preparation.

| Existing obligation | Destination and preservation |
| --- | --- |
| Temporary directories and cleanup hooks for file output | Test-owned files; exact original paragraph |
| Remove/promote temporary evidence before review readiness | Same paragraph; same deadline and maintained-test alternative |
| Run output is evidence; prefer temp/dry-run over tracked mutation | Same paragraph; no new exception |
| Undo only the seeded change and recheck Git status | Same paragraph; no blanket restoration |
| Non-disposable-tree definition and unsafe cleanup prohibition | Same paragraph; all four commands and status precondition retained |
| Throwaway worktree/fresh-clone exception | Same paragraph; identical scope |
| Every other pre-existing obligation in changed guidance files | Unchanged bytes; additions introduce no replacement or deletion |

Independent challenge recomputes this obligation set across the changed files and
checks the destination and entrypoint pointer. This relocation has no new exemption.

Verifier discovery: use check-ccl-skills.sh, repository/spec/link gates, make test,
heavy regressions, public sanitization and the exact-base review-evidence gate.
Private R0 must be observed, not assumed unavailable. Independent review and challenge
inspect false-positive/false-negative behavior and the limits of behavioral evidence.
No merge, host installation or publication belongs to this change.
