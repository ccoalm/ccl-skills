# Multi-Agent Delegation Playbook

Use this when deciding how to split and supervise agent work.

## Good Agent Tasks

- One clear goal.
- One bounded subsystem, file set, or investigation question.
- Explicit constraints: what not to touch, what must be preserved. Slices of any delegated execution input (plan, spec, task list, requirement, implementation direction, or resumed task/status artifact) additionally carry that input's binding global constraints verbatim plus neighbor interface contracts (consumes/produces) — see SKILL.md Core Rules (dispatch payload).
- Model tier field: `model_tier: <tier>` or `model_tier: host-default (<reason>)` in every substantive brief — see SKILL.md Core Rules (model tier per dispatch).
- Clear expected output: changed file paths, root cause, test result, risk, or recommendation.
- Verification command or evidence requirement.
- Capability scope: grant only the tools the bounded task needs; deny by default further delegation, user interaction, shared/persistent-memory writes, cross-system side effects, local-machine mutation beyond the task's grant — filesystem/git writes outside the owned scope, and package installs / process-service control / env-config changes (these need explicit separate grants, not an in-scope default) — and secret-bearing reads (see SKILL.md Core Rules — capability-scoping).
- Interruption/durability: dispatch only in-turn work; for work that must outlive the turn use a durable mechanism with ownership + cancellation/cleanup, not an in-turn subagent. After an interrupted dispatch, verify the child terminated (kill/fence any live worker) and reconcile its owned write scope — its side effects may have persisted (see SKILL.md Core Rules — ephemeral/durable).

## Parallelism Gate

Parallelize only when all are true:

- Tasks can be understood independently.
- Write scopes are disjoint, or tasks are read-only.
- Shared setup is stable.
- One task's result is not needed by another.
- Verification can be integrated afterward.

Do not parallelize when failures likely share one root cause, migrations/contracts overlap, or agents would edit the same files.

### Is multi-agent worth the cost?

Parallel multi-agent dispatch carries a real token premium — on the order of 15× a single chat (a single agent ~4×), as rough order-of-magnitude heuristics rather than a fixed cutoff (actual cost depends on model, context size, retries, and tool-output volume) — plus coordination and result-integration overhead. Add a value/shape check on top of the independence gate above:

- **Value**: the task is high-value enough to pay for the extra tokens and orchestration. Low-value or quick tasks do not justify the premium — run them locally or with one agent.
- **Breadth, not depth**: the win comes from genuinely breadth-first work — many independent subtasks, source/information volume that exceeds one context window, or many complex tools/surfaces to cover at once. Subagents pay off largely by exploring in their own context windows and condensing results back, keeping the orchestrator's context clean.
- **Execution-vs-research caveat**: software-execution tasks usually have fewer truly parallelizable subtasks than open-ended research. If the "parallel" tasks actually share state, contracts, or sequencing, the apparent breadth is false and sequential delegation (or local work) is cheaper and safer.

If independence, value, or breadth is unclear, start with one focused agent or sequential delegation; use parallel dispatch when those checks are explicitly satisfied.

## Review Sequence

1. Spec compliance review.
   - Compare output to original requirement or plan.
   - Check omitted requirements, changed semantics, and unsupported assumptions.
   - Delegating this verdict to a reviewer? The packet must include the spec/brief text itself (not only the diff), and a free-form reviewer's return must carry the `verdict_scope` and `cannot_verify` slots (absent = incomplete) — see SKILL.md Core Rules (delegated-review verdict integrity).

2. Code quality review.
   - Check correctness, security, data integrity, tests, maintainability, and integration risks.

3. Evidence review.
   - Inspect diff.
   - Run focused tests or checks.
   - Confirm claimed generated files, migrations, or docs actually changed.

## Handoff-Style Delivery Recipe

Controller-authored, non-shared edits stay in the owning local workflow. Use this recipe only when a delegated worker produced the diff, or when the diff touches a named externally consumed surface such as shared/generated artifacts, lockfiles, contracts, or migrations. A separate worktree or branch is the isolation mechanism, not by itself a trigger for this recipe. Controller-authored changes being landed to a shared branch or MR route here only when `feature-risk-router` classifies the actual diff as high-risk or delegated-like; ordinary low/medium controller-authored MRs stay in the owning workflow. If risk is unclear, route the tier decision through `feature-risk-router` rather than self-classifying. This is a sequential controller/reviewer pattern unless the controller has a pre-dispatch ownership manifest with non-overlapping path globs, generated artifacts, and independent verification per slice; default to sequential if overlap is possible.

1. Controller sets the lifecycle gate first.
   - Name the lifecycle owner, implementation owner skill, test owner, review owner, and branch/worktree boundary before dispatch.
   - Create or update a handoff manifest before dispatch. The sink can be a repo-local task handoff file, extraction source-register row, MR description, or commit body, but it must be durable enough for the landing reviewer to inspect. Record fields as `tier_artifact`, `review_pass_record`, `challenge_pass_record`, `verified_candidate`, and `cleanup_proof`; a missing required field blocks landing.
   - Record the review tier before dispatch: deterministic checks only, single independent review, or dual-track review + challenge. Use the lifecycle/risk owner and the owning review gate for this decision; record the concrete authorizing artifact in `tier_artifact`, such as a specific review-table row id or an owner-skill decision reference, not a free-text assertion. If no owning review table applies to a code/config/doc handoff, `feature-risk-router` is the fallback owner for the tier artifact; if that route cannot produce an artifact, keep the strictest tier and report the handoff as interim rather than landing. For shared-skill changes, follow `skill-extraction-workflow`'s dual-track table instead of downgrading here.
   - Do not restate the high-risk or dual-track trigger table in this recipe. Record the authorizing table row or owner-skill decision artifact used in the handoff manifest, then apply that tier; routine local git/worktree cleanup follows `worktree-isolation` unless the lifecycle/risk owner escalates it.
   - Single independent review is allowed only when the owning review table row or lifecycle/risk owner decision artifact explicitly authorizes it for the actual diff after deterministic checks pass. Use that artifact's own classification criteria for labels such as operational or architectural; the controller cannot locally downgrade by relabeling the slice as routine, low-risk, or reversible. Shared-skill tier decisions stay entirely with `skill-extraction-workflow`; this recipe does not add a local shared-skill downgrade path.
   - Define the worker stop line: for example, local commit plus report only, or pushed branch plus MR. Do not let workers infer push/merge authority.
   - For parallel write workers, define the owned-path manifest before dispatch; if shared generated files, lockfiles, indexes, migrations, or contract artifacts are in scope, keep that part sequential.

2. Workers operate in isolated scopes.
   - Give each write worker its own worktree or clone and a named branch.
   - Tell the worker exactly which files or repo surface it owns, which contracts are read-only, and which commands prove its slice.
   - Require a compact report: commit or diff ref, changed files, tests run, skipped checks, and invoked owner skills.
   - For parallel write workers, verify each returned diff touches only its manifest-owned set before integration; any undeclared shared/generated artifact forces sequential integration and review.

3. Review is independent and bounded.
   - The implementation worker's self-report is not review evidence.
   - Run deterministic gates before LLM review: clean diff/status, expected file scope, generated-artifact checks, tests, current target freshness, and pipeline presence/status.
   - Prefer a repeatable review script or structured tool wrapper over a broad repo review; the controller should be able to rerun the same review after fixes. Before running the reviewer, define how the controller will assemble the conclusive pass record: for committed candidates, current candidate head SHA from `git rev-parse HEAD`; for uncommitted candidates, a diff content hash such as `git diff <base> | git hash-object --stdin`; changed files from the pinned candidate delta such as `git diff --name-only <base>..HEAD` or the exact uncommitted diff command; exact review command; and parseable verdict/findings from the bounded wrapper output. If no bounded wrapper is available, the review is inconclusive. Free-form prompt output may be useful advisory feedback, but it is not conclusive review evidence for landing.
   - Batch LLM review by landing candidate, not by every tiny fix. Apply all findings in a batch; when both review and challenge are required, rerun both lenses on the updated candidate before landing.
   - Empty, timed-out, partial, malformed, free-form, or continuation-like reviewer output is `inconclusive`, not approval. Treat review as passed only when the controller's pass record proves all of: command success; the recorded candidate SHA equals the current committed head being landed, or the recorded uncommitted diff hash equals the current uncommitted diff hash; the wrapper output matches its pre-documented clean-pass token (for `code-review`, JSON-decodable wrapper output with the expected `mode`, harness-injected `lens_id` and `tool_identity`, and `findings: []`); blocking findings are empty; and the recorded changed-file set from `git diff --name-only <pinned-base>..<reviewed-sha>` or the exact uncommitted diff command matches the candidate and is re-verified before landing. A bounded wrapper without a pre-documented clean-pass token is inconclusive. Any stale SHA, stale diff hash, non-approval verdict, blocking finding, missing file, changed diff after review, or unparseable wrapper output is not a pass. Exit code alone is not enough. When the review carries a spec-compliance verdict, the pass record additionally names the authoritative requirement inputs supplied to the reviewer (spec/brief locator — a wrapper run given only the diff cannot record a spec verdict as conclusive) and the out-of-packet obligations the controller verified itself (may be `none`), per SKILL.md Core Rules (delegated-review verdict integrity).

4. Land only reviewed refs.
   - An inconclusive review is not a reviewed ref; do not push or merge until the required review returns a conclusive approval. If the lifecycle plan does not require review, record that before dispatch instead of using this reviewed-ref path.
   - Before pushing or merging, verify the branch is based on the current target or run the worktree freshness gate.
   - After the final conclusive review round, record the reviewed head SHA of that exact candidate. Land that immutable reviewed commit, or for any mutable/platform merge record both the source-SHA / expected-old-oid guard used and concrete post-merge patch equivalence (`git range-diff` or scoped `git diff` with no unexpected delta) showing the landed tree contains only the reviewed changes. Source-SHA guards and parent/head equality alone are not proof because merge conflict resolution can change content. Without reviewed-ref plus landed-content proof, a mutable source-branch merge is not provably reviewed and must remain interim.
   - Check CI definition separately from run status. If a pipeline definition or required platform check exists, it must reach a conclusive pass before landing. A no-CI acceptance requires a captured platform artifact for this exact ref, such as API JSON or check-result output showing zero required checks or no pipeline/check definition; agent-side interpretation of path or branch filters is not proof. Pending, failed, no-runner, unexplained skipped, or human-explained-only skipped states do not qualify as no-CI. The acceptance must name the lifecycle/test owner plus compensating verification commands and results before merge; local file absence is not enough.

5. Clean up after integration.
   - After the reviewed ref is non-interim landed, sync the target checkout. If landing used a mutable source-branch merge without an atomic reviewed-ref guard, do not clean up yet; keep the branch as evidence.
   - For local-commit-only handoff, prefer fast-forward or merge that preserves the exact reviewed SHA. First sync or fetch the target checkout, verify its current `HEAD` contains the reviewed SHA, and prove the landed content matches the reviewed delta with `git range-diff` or a scoped `git diff` showing no unexpected delta. Only after that content-equivalence proof and `git merge-base --is-ancestor <reviewed-sha> HEAD` both pass in the synced target checkout may the controller remove the isolated worktree and delete the local branch with `git branch -d` (not `-D`) from the same checkout. There is no remote source branch to prune.
   - For pushed-branch/MR handoff, check the platform merge mode first. If it is squash, rebase, cherry-pick, or another rewrite mode, use the non-ancestor path below. If the reviewed branch tip equals the recorded reviewed SHA and is a target ancestor, sync the target checkout, verify it contains the reviewed SHA, re-fetch and verify the local source branch tip still equals the reviewed SHA, remove the isolated worktree, delete the local branch with `git branch -d` from that synced target checkout, confirm the remote source branch was removed by the platform or delete it explicitly, run `git fetch --prune`, run `git worktree prune`, and verify `git worktree list` no longer shows the path and the remote source branch is absent. If the branch has post-review commits, review those commits before cleanup or keep the branch.
   - For squash, rebase, cherry-pick, or platform rewrites where ancestry does not prove integration, require a concrete non-ancestor proof before partial cleanup: platform merge state tied to the reviewed SHA, or an explicit patch-equivalence check such as `git range-diff` / scoped `git diff` showing the reviewed hunks are present on target with no unexpected differences. Under the default no-force-delete policy, remove only the clean worktree, keep the local branch, and report `branch retained: non-ancestor integration`; do not claim full cleanup unless `worktree-isolation` explicitly permits that merge-mode cleanup.
   - Treat a `git branch -d` failure as an unsafe-cleanup blocker; do not force-delete to make cleanup appear complete.
   - If cleanup cannot be proven safe, leave the worktree in place and report the exact blocker.

## Completion Gate

Before claiming completion:

- Run fresh verification appropriate to the claim.
- Read the full output and exit code.
- Check VCS diff for unexpected changes.
- State what was verified and what remains unverified.
