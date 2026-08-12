# MR/PR Merge Authorization Gate

Merge authorization is plan-scoped, never blanket: a single directive
("合并"/"merge") covers exactly the one MR/PR under discussion; a batch
directive ("批量合并 N") covers at most N platform merges **within the
release plan the agent has already presented** (wave order, per-repo MRs or
how they will be created) — anything outside that plan needs fresh
authorization. Batch is the right form for dependency-chain releases
(core package → release → dependents bump → merge → tag) where dependent
MRs do not exist yet at authorization time; semantics and the mechanical
valve are canonical in `worktree-isolation` 「合并执行协议」.

Before asking for or acting on authorization, read back the current MR/PR
(single form), or present the release plan (batch form):

- URL / number.
- Source and target refs.
- Current head SHA.
- CI / pipeline status and URL.
- Mergeability / conflict state.
- Discussion / approval state when the platform exposes it.
- Auto-merge / merge-when-pipeline-succeeds flag.

Rules:

- If head SHA changed after the last user-facing confirmation, authorization is stale. (Batch form: commits/MRs the agent itself creates while executing the presented plan are inside the authorization; third-party or out-of-plan changes still require re-presenting.)
- If CI, mergeability, target branch head, or auto-merge state changed materially, re-present the object before merging.
- Do not enable auto-merge, merge queue, or merge-when-pipeline-succeeds unless the user explicitly authorizes that behavior for the current object.
- Prefer platform/CLI/API options that guard the expected source head SHA. If unavailable, fetch and verify immediately before action, then report the residual race.

After merge, read back merged state, merge commit or equivalent result, and target branch head.
