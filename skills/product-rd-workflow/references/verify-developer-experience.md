# Verify Developer Experience

Use this reference when a delivery touches developer-facing surfaces — CLI, SDK, library, public API, or developer docs — and must prove developer experience (DX) as an acceptance dimension. The entrypoint keeps the acceptance gate and the routing decision; this file carries the journey-proof mechanics.

## Measured onboarding journey

For a new or public developer surface, or a change touching onboarding, install/setup, first-success, defaults, error surfaces, or a breaking migration, prove DX by the measured onboarding journey: run the real discover→install→first-success path as a new user and capture steps, time-to-first-success, friction, and the actual error messages. Do not infer DX from README / feature-list quality.

- A smaller change proves only its affected segment, or cites recent unchanged-journey evidence.
- An unavailable real environment after remediation uses `testing-strategy`'s proportional / lowest-sufficient-layer model and `blocked` / `pre-runtime-test-ready` handling — never a faked pass.

## Error messages are a first-class acceptance item

Every error surface a new user can hit states the problem, the likely cause, and the fix — ideally with a docs link. A green build or a 200 response is not DX evidence when the failure paths are unreadable.

## Defaults: safety stays fail-closed

- A non-safety product default needs a safe override (escape hatch) or a documented no-escape rationale.
- A safety / security default (auth, sandbox, TLS, destructive-action, privacy, compliance) stays fail-closed: widening it needs risk-owner approval, and it may legitimately have no normal escape hatch. DX never licenses an `--insecure` / `--no-sandbox` bypass.
- Breaking changes need a migration path.

## Route per-surface execution to the owning executor

The workflow owns the acceptance dimension only; route execution + evidence per surface:

- SDK / library / package → the target stack / package owner.
- React/browser-consuming surface → `web-react-dev` only.
- CLI / TUI → `terminal-cli-dev`.
- Service APIs → the API/contract + `*-architecture` owner.
- Developer-doc authoring → `tighten-doc` + the stack/API owner.
- Onboarding-journey scenario coverage → `testing-strategy`.
- Deprecation / migration → `platform-release-engineering`.

Do not build a generic DX-scorecard skill — the acceptance gate lives in the entrypoint, and the recipes stay with the executor owners.
