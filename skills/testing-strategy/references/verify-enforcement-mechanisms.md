# Verify Enforcement Mechanisms

Mechanics for the entry rule's enforcement-mechanism verification obligation in `SKILL.md` (Core Rules): the behavioral matrix's cells, the fail-open bypass set, and the port/mirror parity procedure. The obligations themselves — a matrix is required before a completion claim, scratch/synthetic targets only, parity-from-reading is hypothesis-grade — live in the entry; this file owns what goes in the matrix.

## Behavioral Matrix Cells

- **Blocked set**: one blocked case per externally observable deny condition (not only the easiest violation).
- **Allowed set**: allowed cases proving legitimate operations are not collateral damage.
- **Bypass set**: the paths environment variance opens — every swallowed-exception path (a catch that falls through to "allow" is fail-open; make it deny, degrade visibly, or prove the swallowed case is genuinely outside enforcement scope).
- **Canonicalization/read edge cases**, derived from what the guard canonicalizes or reads: target path and cwd (not-yet-existing directories; at least one case where the raw path and the canonicalized path differ, e.g. under a symlinked root), and VCS metadata/state when the guard reads it (linked worktrees, detached/edge ref states).

A case that cannot be exercised safely is recorded as a safe-unavailable gap with its residual risk, not silently skipped.

## Port/Mirror Parity

When the mechanism ports or mirrors an existing guard, the documented enforcement contract is the spec and the original's behavior is parity input: diff condition-by-condition, record each divergence as intentional-divergence or legacy-bug-closed — never silently inherit a bypass — and run the same matrix on both.

For the sibling obligation when the *test* (not the guard) is ported to a sibling stack — input-fixture fidelity of the adversarial inputs themselves — see `test-code-authoring-patterns.md` §9.
