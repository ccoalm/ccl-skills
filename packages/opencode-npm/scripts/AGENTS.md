# AGENTS.md

`scripts/` contains deterministic build and verification helpers for the `@ccoalm/ccl-skills-opencode` package.

## Directory contract

- Scripts must be deterministic, non-interactive, and safe for CI.
- Do not print secrets, registry credentials, npm auth values, or machine-local paths beyond temporary test directories.
- Verification should prefer isolated temporary HOME/prefix directories and must not mutate the user's real OpenCode config.
- Keep generated outputs (`dist/`, `*.tgz`, `node_modules/`) out of git.

## Validation

- Run `make npm-verify` from the repository root after changing scripts.
- If pack/publish behavior changes, also run `npm publish --dry-run --provenance=false` from `packages/opencode-npm/`.
