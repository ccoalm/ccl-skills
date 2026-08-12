# AGENTS.md

`src/` contains the TypeScript implementation of the `ccl-skills-codex` management CLI.

## Directory contract

- Treat the Codex CLI as the only interface allowed to mutate marketplace or plugin registration; never edit Codex config, cache, or hook-trust state directly.
- Decode and validate release and install manifests before using their paths, hashes, versions, or ownership records.
- Preserve transaction finality: journal every external mutation, verify public state before cleanup, and retain evidence when rollback or cleanup is uncertain.
- Keep filesystem operations contained beneath the canonical managed root; reject symlinks, hard links, path traversal, and ownership drift instead of guessing.
- Keep runtime dependencies at zero unless the package design and supply-chain review are explicitly updated.

## Validation

- Run `npm test` from `packages/codex-npm/` after changing runtime behavior.
- Run `npm run test:pack` and `npm run smoke:host` when distribution or Codex-host behavior changes.
