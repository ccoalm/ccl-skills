# AGENTS.md

`src/` contains the TypeScript source for the `@ccoalm/ccl-skills-opencode` distribution package.

## Directory contract

- Keep runtime code dependency-light: do not add production dependencies unless the package design is updated explicitly.
- Do not hard-code registry hosts, credentials, user names, private repo paths, or local machine paths in source.
- File-system writes must be conservative and reversible: prefer dry-run previews, content/ownership checks, and explicit `--yes` for destructive actions.
- User OpenCode config updates must preserve existing entries and avoid destructive rewrites; if a config cannot be safely patched, warn and provide manual instructions instead of guessing.
- TUI plugin exports must match OpenCode's loader shape: default export an object with `{ id, tui }`.

## Validation

- Run `make npm-verify` from the repository root after changing package behavior.
- Run `npm publish --dry-run --provenance=false` from `packages/opencode-npm/` before publishing package changes.
