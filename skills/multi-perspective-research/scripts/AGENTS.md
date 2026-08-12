# skills/multi-perspective-research/scripts Agent Contract

This directory contains deterministic regression checks for executable recipes
embedded in the multi-perspective research references. The repository-wide
contract remains authoritative: [root `AGENTS.md`](../../../AGENTS.md). This
file only narrows that contract; it does not relax its safety, authority,
owner-routing, worktree-isolation, or validation gates.

Rules:

- Execute snippets extracted from the owning reference instead of maintaining a
  second implementation that can drift from the published recipe.
- Keep the inline `MANIFEST` in
  `test-public-data-acquisition-recipes.sh` exhaustive: every runnable code
  block must be marked as executed or explicitly exempt with a concrete
  environment or integration reason, and an unregistered block must fail the
  check.
- Use synthetic fixtures and local stubs. Do not require live network access,
  production data, credentials, or private endpoints.
- Preserve fail-closed assertions for acquisition, parsing, completeness, and
  cleanup behavior. A failed check must return non-zero.
- Keep shell checks portable across supported macOS and Linux environments.
  Use trap-based cleanup on normal, failed, and catchable interrupted exits.

Validation, run from the repository root:

- `bash skills/multi-perspective-research/scripts/test-public-data-acquisition-recipes.sh`
- `shellcheck -S warning skills/multi-perspective-research/scripts/test-public-data-acquisition-recipes.sh`
- `bash skills/product-rd-workflow/scripts/check-agent-contract-coverage.sh --repo . --enforce`

If `shellcheck` is unavailable, report that validation as inconclusive rather
than passing.
