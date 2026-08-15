# AGENTS.md

`test/` contains deterministic unit, transaction, fault-injection, packed-artifact, and host-boundary tests for the unified npm CLI.

## Directory contract

- Tests must be self-contained from a clean checkout and must not depend on artifacts or state left by another npm script.
- Use isolated temporary HOME, CODEX_HOME, binaries, and managed roots; never read or mutate the user's real Codex installation.
- Keep fake-host tests for deterministic state-machine and fault coverage, and retain real-host smoke for public Codex CLI contract evidence.
- Do not weaken failure assertions to make a suite pass; interruption and fault tests must prove rollback, commit-point, or unknown-finality behavior explicitly.
- Treat generated artifacts and temporary fixtures as disposable test output, never as committed source.

## Validation

- Run `npm test` from `packages/ccl-skills-npm/` after changing tests or runtime behavior.
- Run `npm run test:pack` for packed-artifact coverage and `npm run smoke:host` for real-host lifecycle coverage.
