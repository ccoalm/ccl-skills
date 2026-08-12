# Developer Tooling Patterns

Use this when implementing developer CLIs, code generators, scaffolding commands, or generated-file workflows.

## CLI Shape

- Provide non-interactive flags for every input needed by CI or agents.
- Interactive prompts may wrap the same execution path, but should not be the only supported mode.
- Validate required flags before doing file or remote work.
- Print planned inputs and output paths before generation when the command changes files.
- Return errors instead of only logging so callers can fail CI.

## Project Dev Command Surface

- Prefer a small documented project command surface for common agent/developer actions: status, setup, start, stop, restart, format, lint, check, test, focused test, codegen, and review.
- A wrapper script or Make target should call the same underlying commands used by CI; do not create a second untested path.
- Commands should print the working directory, selected config, important environment source, and the exact subcommands they run when useful for debugging.
- Long-running service commands should expose readiness checks and logs instead of requiring manual observation.
- Test commands should distinguish fast deterministic tests from integration, live dependency, browser, replay, or long-running suites.
- Wrappers may load local env files for development, but CI and agents need non-interactive flags or documented environment variables.
- Repo-local agent contracts (`AGENTS.md`): when the repo adopts root + per-source-directory contracts, wire the coverage gate into the normal lint/check path so contracts do not drift from the code. `check-agent-contract-coverage.sh` (from `product-rd-workflow/scripts/`) provides it — `--check` (guidance, non-blocking), `--fix` (scaffold missing, additive), `--enforce` (CI block once adopted). Contracts are nearest-file-wins (no root index); scope is every source-code directory, detected by source file rather than manifest — Go packages such as `dal`/`service`/`handler`/`logic` carry no manifest yet each owns distinct layering rules. Policy/ownership lives in `product-rd-workflow`'s spec / repo-contract sync gate; do not rely on review memory or a generic passing build to prove the contract is current.

## Generator Shape

- Parse structured inputs with real parsers, not ad hoc string splitting.
- Keep templates in files or embedded assets with tests for rendered output.
- Build a typed intermediate model before rendering generated files.
- Use deterministic ordering for columns, fields, imports, indexes, routes, and generated methods.
- Run formatting tools on generated Go files.
- Mark generated files and document whether they are safe to edit.

## File Safety

- Refuse to overwrite hand-written files by default.
- Overwrite only generated files or when an explicit force flag is provided.
- Write to a temporary file and rename when partial writes would leave broken output.
- Use repo-relative paths in docs and generated references.
- Clean up temporary layout/config files.
- When regenerating directories, move old generated output to a guarded backup path and delete that backup only after the full generation succeeds.
- Guard any cleanup command with repo-root/path validation so a bad environment variable cannot remove an arbitrary directory.

## DDL And Data Model Generation

- Parse DDL with a SQL parser and preserve table name, column names, comments, indexes, unique constraints, nullable fields, and soft-delete fields.
- Map database types to Go types through one tested table.
- Generate model constants, query helpers, update helpers, and optional repository wrappers from the same intermediate model.
- Sharded table suffix handling must be explicit and tested; do not infer it silently unless the convention is documented.

## Tests

- Test missing input, bad input parse, existing output file, force overwrite, deterministic output, formatting failure, template failure, type mapping, index generation, module path detection, and command exit status.

## Build Script And Makefile Convention

- Keep a per-service `build.sh` whose only job is reproducibly produce a deployable artifact: create the output directory, copy the conf files needed at runtime, mark scripts executable, and run `go build` with explicit output path. Avoid embedding codegen inside `build.sh` — codegen runs separately and its output is committed.
- For cross-platform builds, detect OS/ARCH from `uname` and select the matching binary suffix; do not embed personal absolute paths or developer-specific Go toolchain pinning in the script.
- Centralize all codegen and DI entrypoints in the Makefile so callers do not need to remember tool names: `make wire` (DI), `make gen_db` (DAL from DDL), `make idl` or `make_service` (IDL → server/client stubs), `make doc` (API docs). Each target is the canonical command — CI and developers use the same path.
- Provide a top-level one-command codegen target (e.g., `make codegen` that fans out to `make wire`, `make gen_db`, `make idl`) for new-service onboarding and post-IDL-bump refreshes. Leaving each business repo with its own ad-hoc targets and no portfolio-level entrypoint is a recurring onboarding pain.
- The Makefile should expose `make test` (fast tests) and `make test-integration` (live-dep tests). Builds that skip tests are intentional, not an oversight.

## Breaking-Change Gate

- For any IDL surface consumed by another team, another binary, or external clients, add a breaking-change check to CI: `buf breaking` for proto, `kitex check` for Kitex, or a custom script that compares the generated descriptor against the previous merged revision.
- Pre-commit syntax/format checks (protoc compile + clang-format) are not breaking-change checks. They catch typos, not contract regressions.
- When a breaking change is intentional, route it through an explicit approval path: a marker file, a PR label, or a separate "breaking" branch the gate recognizes. Do not let "the gate is annoying" be a reason to disable the check.

## Static Analysis And Vulnerability Scan

- **`golangci-lint` is the current default-recommendation meta-linter** for Go services — wraps `staticcheck`, `govet`, `errcheck`, `ineffassign`, `gosec`, and 100+ other linters behind one config + one binary, with parallel execution and caching. v2 reorganized the config format and made the enabled-linter list explicit rather than implicit; verify the exact stability tiering against `golangci-lint.run/usage/linters` for the version you pin. Pin a specific version in CI so the rule set doesn't drift under a contributor's local `golangci-lint` upgrade. Service-specific tuning lives in `.golangci.yml` at the repo root — do NOT enable every available linter (the noise drowns real findings); start from a curated set (`govet, errcheck, ineffassign, staticcheck, gosec, gocritic` plus team-specific picks) and add linters individually as the team agrees on them. Reserve `staticcheck` standalone only when a sibling Go service hasn't yet adopted golangci-lint and migration would block the current change.
- **`govulncheck` (`golang.org/x/vuln/cmd/govulncheck`) is the Go team's official vulnerability scanner** — symbol/call-graph aware (significantly reduces false positives versus naive go.sum CVE scanners by skipping CVEs whose vulnerable symbols the binary's call graph does not reach; reflection / `init` side effects / build-tag-conditional code can still expose CVEs that static call-graph analysis misses, so govulncheck is a strong baseline, not absolute proof of safety). Run as a CI gate: `govulncheck ./...`. Integrate into the same Make target as other quality gates (`make vuln` or fold into `make lint`); fail the build on findings unless the project explicitly waives a CVE via an issue-tracker reference and a justification comment in the waive-list. Re-run on schedule (weekly cron) in addition to per-PR — new CVEs land continuously and a passing PR last month may be vulnerable today.
