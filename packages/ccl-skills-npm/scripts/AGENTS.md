# AGENTS.md

`scripts/` contains deterministic build, pack-verification, and isolated host-smoke helpers.

## Directory contract

- Build the runtime closure only from tracked files selected by the explicit allowlist; never recursively copy the working tree.
- Produce and verify one exact tgz artifact before CI publishes that same artifact; keep source commit, file hashes, and registry integrity bound together.
- Keep scripts non-interactive and fail closed on malformed metadata, unexpected file types, path escapes, or missing host capabilities.
- Use temporary HOME and CODEX_HOME directories for host smoke; never mutate the user's real Codex state.
- Never print registry credentials, auth configuration, secrets, or machine-local private data.

## Validation

- Run `npm run test:pack` from `packages/ccl-skills-npm/` after changing build or pack scripts.
- Run `npm run smoke:host` after changing host lifecycle behavior.
