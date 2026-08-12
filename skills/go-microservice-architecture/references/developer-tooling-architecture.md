# Developer Tooling Architecture

Use this when designing CLIs, code generators, scaffolding commands, or generated-file ownership for a Go service stack.

## Tool Boundaries

- Treat generators as build/development tools with explicit inputs, outputs, versions, and ownership.
- Prefer non-interactive command flags for CI and agent use; interactive prompts can be a convenience wrapper only.
- Generation inputs should be source-controlled where possible: DDL, IDL, templates, config, and command docs.
- Generated outputs should be clearly marked and should not require hand edits.
- Tools should be runnable from the repo root or document their required working directory.

## Reproducibility

- Pin generator versions or verify them in preflight checks.
- Fail fast when required inputs, modules, config files, or external binaries are missing.
- Use temporary files safely and remove them after command completion.
- Avoid developer-local absolute paths in generated commands.
- Format generated Go files and keep generated diffs deterministic.

## Safety

- Do not overwrite hand-written files unless the command explicitly opts in.
- Prefer generated file suffixes or directories that make ownership obvious.
- Tools that touch deploy config, database schemas, or remote systems need dry-run output and confirmation gates.
- Generated code should include tests or compile checks in the owning repo's verification workflow.

## Codegen Entrypoint Ownership

- For multi-service portfolios, architecture mandates one canonical command per codegen kind (`make wire` for DI, `make gen_db` for DAL from DDL, `make idl` / `make_service` for IDL → server/client stubs, `make doc` for API docs) and a top-level fan-out target (`make codegen`) that runs all of them. New service onboarding and post-IDL-bump refreshes use the top-level target.
- The Makefile is the source of truth for both developers and CI; CI does not invoke generator binaries directly. Tool versions are pinned at the Makefile or container layer, not at the developer's local environment.
- Generated output directories are committed and reviewed; reformatters and linters skip them. Architecture review treats hand-edits to generated files as a finding unless the generator explicitly supports custom hooks.

## Breaking-Change Governance

- Any IDL surface consumed by more than one team, more than one binary, or external clients requires a CI breaking-change gate (`buf breaking`, `kitex check`, or equivalent). Pre-commit syntax/format checks alone are not breaking-change checks.
- The gate compares the proposed IDL against the previous merged revision; intentional breaks route through an explicit approval path (PR label, separate branch, marker file the gate recognizes). Architecture review owns the approval list and the rationale per break.
- Multi-language consumers inherit the contract; if the canonical language has integration tests but other languages do not, architecture documents that asymmetry so consumers can decide whether to add their own coverage.
