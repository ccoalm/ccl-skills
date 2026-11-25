# Verify Enforcement Mechanisms

Mechanics and full rules for the enforcement-mechanism verification obligation referenced from `SKILL.md` (Core Rules).

- Require a behavioral matrix before a completion claim — blocked case per deny-condition, allowed/no-collateral cases, the fail-open/swallowed-exception bypass set, and the canonicalization/symlink/worktree edge cases. Run the matrix only against scratch/synthetic targets (a throwaway checkout/worktree, fixture repo, or dry-run mode) — never a live workspace, real user data, or live credentials. Parity claimed from code reading alone is hypothesis-grade, not evidence.

## Behavioral Matrix Cells

- **Blocked set**: one blocked case per externally observable deny condition (not only the easiest violation).
- **Allowed set**: allowed cases proving legitimate operations are not collateral damage.
- **Bypass set**: the paths environment variance opens — every swallowed-exception path (a catch that falls through to "allow" is fail-open; make it deny, degrade visibly, or prove the swallowed case is genuinely outside enforcement scope).
- **Canonicalization/read edge cases**, derived from what the guard canonicalizes or reads: target path and cwd (not-yet-existing directories; at least one case where the raw path and the canonicalized path differ, e.g. under a symlinked root), and VCS metadata/state when the guard reads it (linked worktrees, detached/edge ref states).

A case that cannot be exercised safely is recorded as a safe-unavailable gap with its residual risk, not silently skipped.

## Port/Mirror Parity

When the mechanism ports or mirrors an existing guard, the documented enforcement contract is the spec and the original's behavior is parity input: diff condition-by-condition, record each divergence as intentional-divergence or legacy-bug-closed — never silently inherit a bypass — and run the same matrix on both.

For the sibling obligation when the *test* (not the guard) is ported to a sibling stack — input-fixture fidelity of the adversarial inputs themselves — see `test-code-authoring-patterns.md` §9.
