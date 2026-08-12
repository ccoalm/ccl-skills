# Existing Project Assessment Report

Use this template for broad prompts such as "analyze this project", "review this codebase", "what is good or bad here", or "look at architecture, implementation, bugs, tests, and design". The goal is a code-evidence report, not a generic architecture essay.

## When To Use

- The user asks for repository or product-codebase quality across more than one dimension.
- The answer needs positives, negatives, likely bugs, missing tests, or next actions.
- The project may include backend, web, app, mini-program, LLM, release, observability, or design surfaces.

Do not use this when the task is only a narrow diff review, a single bug reproduction, or a stack-specific implementation question.

## Report Contract

Every report must separate:

- Evidence read: files, commands, configs, docs, local rules, generated areas excluded.
- Evidence not verified: missing dependencies, unavailable devices, missing credentials, failed commands, live services not run.
- Assessment launch checklist: product/user paths, architecture/implementation owners, test-layer matrix owner, UI/UX surfaces, runtime/host evidence surface, unavailable/live/manual boundaries, and extraction/learning trigger. If this checklist is absent, label the work as interim exploration, not a complete assessment.
- Test-case register before fixes/tests: scenario, layer, assertion, data/dependency, command, expected current result (`fail`, `pass-existing`, `blocked`, or `gap`), and owner. If implementation already started before the register existed, say so and do not call the slice TDD.
- Understanding: structure, entry points, dependencies, runtime flow.
- Judgment: positives, problems, likely bugs, test gaps, design/product gaps, operational risks.
- Next actions: quick fixes, structural refactors, test debt, design/product follow-ups, release/ops follow-ups.
- Closeout outputs when the assessment continues into fixes/tests: project findings or fixes, verification evidence by layer, issue/risk registration, and reusable-process disposition (`skill-extraction-workflow` landed/routed, or `unchanged`/`routed`/`discarded` with evidence).

Do not promote documentation claims to implementation facts unless code or command evidence supports them.

## Skill Route Checklist

Before writing conclusions, build a compact matrix:

| Dimension | Owning skill | Evidence to inspect | Output |
| --- | --- | --- | --- |
| Orientation | `codebase-analysis` or direct repository exploration | tree, README, package/build files, entry points, local rules | structure and flow boundary |
| Assessment launch | `product-rd-workflow` | product/user paths, architecture/implementation owners, test-layer owner, UI/UX surfaces, runtime/host evidence, unavailable/live/manual boundaries, extraction trigger | complete-vs-interim boundary before conclusions or fixes |
| Product/workflow | `product-rd-workflow` | user flows, acceptance docs, feature scope, release status | report framing and next-action split |
| Architecture | backend/client/platform architecture skills | module boundaries, contracts, storage truth, async flows, dependency direction | architectural positives and risks |
| Implementation | stack dev skill (`go`, `python`, `web`, `app`, `miniapp`) | core files, adapters, state ownership, API clients, generated boundaries | implementation quality and maintainability |
| Tests | `testing-strategy` | test configs, test commands, CI, fixtures, manual checklists, written test cases before implementation | test topology, test-case register, RED/pass-existing/blocked/gap status, and missing layers |
| UI/UX | `product-ui-ux-design` plus client skill | visible screens, states, navigation, accessibility, rendered evidence | design quality boundary and gaps |
| Bugs/risks | `defect-diagnosis` when reproducible, otherwise code-backed risk analysis | failure-prone code paths, edge cases, error handling, concurrency | verified bugs vs likely risks |
| Release/ops | `platform-release-engineering`, `platform-observability`, `platform-service-connectivity` | rollout/config/rollback, logs/metrics/traces/alerts, service-to-service transport/mesh/discovery | launch and operability risks |
| Closeout/learning | `product-rd-workflow` plus `skill-extraction-workflow` when reusable | findings/fixes, verification by layer, issue/risk register, reusable-process disposition | completion label and durable landing/no-change evidence |

If a dimension does not apply, say why. If a dimension applies but cannot be verified, mark it as missing evidence.

For high-consequence authentication, account, permission, payment, or similar entry flows, the scenario matrix must separate automated, manually/runtime-verified, blocked, product-gap, live-only, and not-applicable rows. Missing recovery/reset, identity validation, logout cleanup, permission denial, or UI/UX acceptance cannot be collapsed into “E2E passed”.

## Recommended Report Shape

### Scope And Evidence

- Sanitized repository label or relative path by default. Include exact local/private paths only in local working notes or when the user explicitly asks.
- Detected stack and shipped targets.
- Files and docs read.
- Commands run and results.
- Blocked verification and residual risk.
- Assessment launch checklist status and any row marked unavailable, live-only, manual-only, or not applicable.

### Executive Summary

Three to six bullets:

- What is solid.
- What is risky.
- What is likely to break first.
- What should be fixed first.

### What Works Well

Group by concrete mechanisms, not praise:

- Architecture and ownership.
- Runtime and state handling.
- API/client contracts.
- UX/state completeness.
- Test/release discipline.

Each point should cite files or commands.

### Findings

Order by severity and confidence.

Use this row format:

| Severity | Confidence | Area | Evidence | Impact | Recommended fix |
| --- | --- | --- | --- | --- | --- |
| P1/P2/P3 | verified/likely/speculative | architecture/implementation/test/design/release | file:line or command | user/system impact | smallest useful correction |

Severity guidance:

- P1: crash, data/security exposure, broken critical workflow, irreversible side effect, or release blocker.
- P2: likely user-visible failure, serious maintainability risk, missing contract/test around critical behavior.
- P3: cleanup, docs drift, lower-risk maintainability, weak but non-blocking evidence.

Confidence guidance:

- Verified: reproduced by command/test/runtime evidence or direct deterministic code path.
- Likely: code path strongly suggests failure but was not executed in the current environment.
- Speculative: plausible risk from pattern or missing evidence; keep it out of the main bug list unless useful.

### Architecture Assessment

Cover only what evidence supports:

- Boundaries and ownership.
- Entry points and routing.
- Data/state source of truth.
- Async, streaming, jobs, subscriptions, or background behavior.
- Cross-service/client contracts.
- Security and permission boundaries.

### Implementation Assessment

Cover stack-specific implementation:

- State ownership and lifecycle.
- API/request/client wrappers.
- Error handling and recovery.
- Concurrency, cancellation, idempotency, and finality.
- Generated code and platform-specific branches.
- File size and module cohesion.

### Test And Verification Assessment

Include:

- Test commands discovered.
- Test frameworks/configs discovered or absent.
- Test-layer matrix owner and per-layer status: unit, integration/contract, E2E/host smoke, manual/exploratory, build/static.
- Test-case register status before implementation: written cases, target layer, assertion, expected current result, RED evidence or blocker/gap reason.
- Manual checklist status.
- Build/type/lint command results.
- Missing assertion layers.
- Device/browser/platform evidence available or absent.

Do not treat build-only or manual-only evidence as assertion-based coverage.

### UI/UX Assessment

When the project has visible surfaces, include:

- Primary workflows and navigation.
- Loading, empty, error, disabled, permission, retry, and recovery states.
- Visual hierarchy and density.
- Accessibility and text overflow risk.
- Rendered evidence, or why rendered evidence was not available.

If no visible surface changed or no rendered surface was inspected, state the limitation.

### Recommended Next Actions

Split actions into:

- Quick fixes: small, low-risk changes that remove real bugs or sharp edges.
- Structural work: refactors or ownership changes that reduce repeated risk.
- Test work: missing unit, contract, integration, E2E, device, or release checks.
- Product/design work: state, copy, workflow, trust, or accessibility follow-ups.
- Release/ops work: flags, observability, rollback, review readiness.

Each action should name the owning skill or team discipline.

Close every assessment-to-fix/test loop with:

- Project findings or fixes completed.
- Verification evidence by layer, including unavailable/live/manual boundaries.
- Issue/risk registration, or the reason no register entry is needed.
- Reusable-process disposition: `skill-extraction-workflow` landed/routed, or `unchanged`, `routed`, or `discarded` with evidence.

When the user asks to continue from assessment into fixes, add an execution-plan checkpoint before code changes:

- Existing spec/plan review: name any repo-local spec, implementation plan, assessment report, issue/MR description, or prior task doc that was checked; if none exists, say so.
- Plan-shape decision: decide whether the follow-up needs a formal external spec-plan workflow or a lightweight workflow plan, with the reason.
- Branch/worktree boundary and landing rule.
- Selected findings for this batch and findings explicitly deferred.
- Test-case register before implementation, including RED/pass-existing/blocked/gap status and why any scenario is not automated.
- Task split with files to touch.
- Root-cause evidence required before each fix.
- Failing-test-first target, or why the current repository cannot support it yet.
- Design checkpoint for any visible behavior, state, copy, navigation, loading, or error change.
- Verification commands and unavailable layers.
- Stop conditions that require user confirmation.

External planning, debugging, TDD, or QA skills may be used to enforce these steps, but the report must still name the owning CCL skill for each task.

For any non-trivial follow-up task, even outside assessment-to-fix flow, require enough analysis and planning before edits:

- Check existing specs/plans before writing a new one or editing code.
- Upgrade to a formal external spec plan when the follow-up needs the extra artifact because it is multi-skill, branch/worktree-scoped, delegated/subagent-executed, high-risk, intended as a durable process sample, or likely to expand without a reviewed task split. Ordinary multi-step assessment-to-fix-to-test work still needs a reviewed plan, but not automatically an external spec plan.
- Simple, low-risk, single-file tasks: short inline plan with target file and verification command.
- Multi-file, user-visible, bug-fix, release, branch/MR, test, design, or unclear-risk tasks: explicit task split with acceptance checks and stop conditions.
- High-risk tasks: root cause, risk matrix, rollback path, test matrix, and owner handoff before implementation.

## Anti-Patterns

- A report that only summarizes the repository tree.
- A report that lists "good/bad" without file or command evidence.
- Calling a third-party understanding skill's output the final analysis.
- Treating manual checklists as automated regression coverage.
- Saying "tests pass" when dependencies were not installed or commands were not run.
- Mixing verified bugs with guesses without confidence labels.
- Reporting design quality without rendered evidence or a stated static-review limitation.
- Ignoring skill-route misses discovered during the analysis.
- Omitting the assessment launch checklist or four closeout outputs while calling the analysis complete.
- Running test commands before writing the test-case register, then calling the result complete.
- Starting fixes from a broad assessment before producing and accepting a task plan.
- Treating "low risk" as a reason to skip analysis entirely instead of scaling the plan down.

## Grounding the evidence boundary

Before running any per-repo gate or concluding that a file/config/tooling is absent, ground against the authoritative state on **both** axes, every time:

- **Repo topology.** Determine whether the target is a single repo, a **parent-of-repos / VCS group** (sibling repos cloned side by side under a parent that is not itself a repo — e.g. a GitLab group checkout), or a **monorepo**. A per-repo gate (contract/coverage/lint) run against a group parent conflates siblings and falsely reports a missing root — run it **per member-repo boundary** (each group child repo, and in a monorepo each submodule / nested-repo root), not once over the parent. Quick check: the parent itself is not a work tree (`git -C <dir> rev-parse --is-inside-work-tree` prints `true` only for a work tree — a nonzero exit means not a repo, `false` with exit 0 means a bare repo) yet the child dirs each are work trees (verify each with `git -C <child> rev-parse --is-inside-work-tree`, not by scanning for a `.git` *directory* — a member repo's or linked worktree's `.git` may be a file). (`check-agent-contract-coverage.sh` now self-refuses on a group parent, but topology must be established for every assessment, not only that gate.)
- **Committed vs working-tree state.** Verify file/config/tooling presence-or-absence against committed `HEAD`, not a bare filesystem check — a tracked file deleted only in the working tree (or an untracked local addition) makes a plain `[ -f … ]` lie. First `git rev-parse --verify HEAD` to confirm a commit exists (unborn `HEAD` → record "no committed baseline", not "absent"), then read the path out of `HEAD` from the repo root with a repo-root-relative `<path>` (`git cat-file -e HEAD:<path>` / `git ls-tree -r --name-only HEAD`) — not `git ls-files` / `git status`, which report the **index/working tree** (staged or unstaged adds/deletes mislead). Also record dirty-working-tree state: uncommitted local deletions/edits may be another session's WIP (do not treat them as the repo's real state, and isolate before editing).

## Standardization / conformance maturity calibration

For repo/family standardization or contract-conformance maturity assessment:

- A verified same-org peer exemplar is calibration input, not authority. If it is absent, stale, or unverified, record `peer_exemplar: unavailable` and fall back to standards-to-health-gate conformance plus authoritative standards.
- Split structural and semantic conformance into separate yes/no rows: structural presence does not prove semantic parity, and only a cross-consumer conformance check closes the maturity gap.
- Detailed structural marker examples and candidate-until-verified rules live in `cross-repo-coordination.md`.
