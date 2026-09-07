# MR/PR Merge Authorization Gate

Authorization is scoped to the user's stated goal. "Complete and merge" or
"publish this release" already covers the necessary in-scope platform merges,
including PRs created later to deliver that goal. Present the concrete refs,
scope and sequence as they become known; this is execution evidence, not a
new permission request. It does not authorize unrelated releases, protection
changes or destructive data operations. Preparation-only and stop instructions
prevail. A single "merge" covers the one MR/PR under discussion; an explicit
"批量合并 N" remains limited to N merges in the presented plan.
Execution and host-grant limits are canonical in `worktree-isolation`
「合并执行协议」.

Before asking for or acting on authorization, read back the current MR/PR
(single form), or present the concrete delivery sequence (goal/batch form):

- URL / number.
- Source and target refs.
- Current head SHA.
- CI / pipeline status and URL.
- Mergeability / conflict state.
- Discussion / approval state when the platform exposes it.
- Auto-merge / merge-when-pipeline-succeeds flag.

Rules:

- For goal/batch authorization, in-scope repairs or newly created PRs require renewed validation and review, not renewed permission. For single-object authorization, a changed head requires confirmation. Third-party or out-of-scope changes require a scope decision.
- Re-read changed CI, mergeability, target head or auto-merge state and resolve failed gates before merging; ordinary checks finishing do not revoke goal authorization.
- Do not enable auto-merge, merge queue, or merge-when-pipeline-succeeds unless the user explicitly authorizes that behavior for the current object.
- Prefer platform/CLI/API options that guard the expected source head SHA. If unavailable, fetch and verify immediately before action, then report the residual race.

After merge, read back merged state, merge commit or equivalent result, and target branch head.
