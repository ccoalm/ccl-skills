# Pre-final continuation gate

Use this reference for finalization and continuation checks after a delivery slice lands.

Status-document freshness and live tracker shape remain owned by `status-tracker-sync.md`. This reference governs the landing-state proof, deferred runtime evidence, and continuation-stop classification.

## Landing-state proof (gate step 1 mechanics)

Confirm the landing state from real evidence — local branch, remote sync, MR/review artifact, CI/pipeline status when applicable, independent review/challenge status when required, product/status doc sync when the slice changes shared roadmap or readiness, and dirty worktree state — using this sequence:

- **For behavior-changing product delivery, refuse implementation completion without both closure tables.** Reconcile the active acceptance IDs against the acceptance-to-evidence table, review the concept-delta table against the final diff, and keep `gap` / `blocked` / `unknown` rows blocking. A reviewed documentation-only diff may mark both axes `not-applicable`; a reviewed pure-refactor or mechanical-maintenance diff with no contract/behavior delta exempts only the functional axis and still carries its concept-delta table (or `none` row); the classification comes from the reviewed diff, never from the implementer's label alone. Record the closeout artifact and reviewed diff identity.
- **Discover the status surfaces.** After any delivery slice lands or reaches pending-MR handoff, discover agent-consumed status/tracker/next-step documents from this bounded checklist: agent contract, README, repo-local handoff/status files, status-source validators, explicit user/context pointers, external issue/tracker/status sources used in step 2, and any recorded deferred-item path/ref. Report each class with its ref/result or concrete negative evidence — the checked path/glob, an absent contract field, an external tracker still unavailable after remediation, or an inspected scope showing no such surface; an undocumented or unverifiable absence/applicability claim is a blocking gap. Other plausible surfaces may be noted as best-effort context, but once found they reconcile and can block like any other agent-consumed status source.
- **Prove the landing before reading any document**, by where the slice lives. In every path, content/tree/patch equivalence may corroborate scope but never by itself proves the slice landed.
  - *Remote-backed* (the default unless local-only is proven by no remote tracking ref and no MR/PR/platform review): fetch/update the target ref from its remote immediately before classifying the slice landed or pending. If the fetch fails, retry once and check one alternate platform ref only as diagnostic evidence, then report `inconclusive — remote unavailable` and stop — do not fall back to a local ref. Treat the slice as landed only when the freshly fetched target ref contains the slice commit, or platform merged evidence is paired with a reachable merge/squash (or equivalent platform-produced) commit reachable from that fetched target. Read the document from that target ref; an unfetched local ref, pre-merge branch copy, or MR description alone is not enough.
  - *Local-only*: name the authoritative local target ref and verify it contains the slice by commit ancestry or an actual merge commit before reading the document there. If that verification fails, report `inconclusive — landing unverified` and stop.
  - *Pending MR / unmerged branch*: reconcile the document against both the MR head/branch ref and the freshly fetched target ref. "Not yet on the target ref" is not stale; a next-step pointer to work already landed on the target ref is stale.
- **Report and re-classify.** If a document exists, report the ref/SHA read and its current/next-step state. Scan every present status surface plus any exact path/ref cited by previously recorded deferred merge-closeout items, and re-classify every next-step/status pointer that asserts current/landed/unstarted state against fresh ref state — not only recorded deferred items. Future/planned items are exempt only when their text and fresh-ref evidence make no current/landed/unstarted claim. A deferred item without a concrete path/ref, or a previously cited deferred path/ref that is no longer locatable, is a blocking gap until re-located or re-recorded with one. For each deferred item, refresh its MR/PR state and target ref, then apply the landing proof above before deciding it is merged.
- **Repair stale status before deriving or finalizing.** When a status surface contradicts the landing evidence for the ref being checked — it points at an already-merged/pushed/completed next step, marks landed work as pending/unstarted, or a deferred item is proven merged — run a status-source repair slice first, then mark the item resolved with the repair ref/SHA and keep the audit trail. Run the repair on a non-default branch/ref distinct from the old MR head: any push to an MR head invalidates that MR's merge authorization, which must then be re-requested (exception: under a batch merge grant — "批量合并 N" — commits the agent itself pushes while executing the presented release plan stay within the authorization; see `worktree-isolation` 合并执行协议). If the repository has no discoverable status source but a deferred item must be recorded, create or update a repo-local handoff/status artifact on a non-default branch/ref distinct from the MR head (or in an explicitly user-sanctioned external status repo) and cite its path/ref.
- **Pending-MR deferral.** Only status changes that flip solely because the merge has not happened yet may be deferred, and only when proven by a committed/pushed post-merge diff/repair artifact; if that proof is missing or unverified, treat the item as a blocking stale-status gap. Do not push these at-merge-time-only changes to the MR head — that would void its live merge authorization (single-form; a batch grant's in-plan agent pushes are the documented exception, see `worktree-isolation` 合并执行协议) — so record the deferred merge-closeout items in a discovered status artifact/ref on a non-default branch/ref distinct from the MR head, verify the committed/pushed record there, and report the turn as `pending-MR handoff, merge outstanding`, not complete. If the MR closes without merge, mark the deferred item dropped/superseded and record the closure ref instead of applying the repair. Authorization preservation never overrides a stale-status blocker: if the document affirmatively contradicts the MR head/branch or target-ref reality, either repair it (invalidating and re-requesting authorization) or stop and report the blocker — never merge it as-is.

## Deferred real evidence

`DFE-CONT` applies when real or runtime evidence is due and not closed:

- Named by an acceptance item, status source, landing-evidence row, required gate, user correction, or the behavior's only meaningful proof.
- Deferred, blocked by unavailable runtime/service/cluster/credential/release access, skipped at finalization, or replaced by local/mock verification.
- `unavailable` only after the host's normal blocked-verification remediation path has failed.

Evidence is **pending**, not deferred, when the command is runnable this turn with available access and simply has not run yet; no named requirement makes it optional.

Evidence is **optional** only when no acceptance item, status requirement, landing evidence, gate, user correction, or current-slice requirement covers it.

## Terminal deferral anchors

Report deferred real evidence as `interim` / outstanding until a valid non-agent anchor closes it.

A local/mock substitution or deferral can be terminal only when a cited **non-agent** anchor:

- Names the same evidence command/source or behavior.
- Declares the substitution/deferral terminal.

Valid anchors:

- Exact user utterance.
- User-authored status item for the active slice/ref.
- Status item carrying an explicit cited user approval ref/utterance.
- Named later gate, such as `feature-risk-router`, whose ownership is set by one of those non-agent sources.

Invalid anchors:

- Agent-authored or agent-co-edited status/router/gate/handoff text from the same engagement.
- A status item created or modified by the agent to grant itself permission.
- A gate introduced or routed by the agent and then cited as permission.

When the anchor is valid and carries the outstanding command/source forward for the active slice/ref, report `deferred-to-<gate>` / `deferred-accepted`.

If it does not carry the outstanding command/source forward, keep the status `interim`.

## Local/mock progress

A cited local/mock gate counts as separate progress only when both are true:

- It exercises a different command or harness from the deferred command.
- It proves a blocker that does not need the deferred runtime, credential, or cluster path.

If it exercises the same acceptance, the deferred item remains outstanding.

## Hardening boundary

Do not add verifier/config/test hardening solely because deferred real evidence is still missing.

Hardening requires a non-agent-authored, pre-existing input:

- Status-source acceptance path/ref.
- Named `feature-risk-router` or verification-owner gate with required evidence.
- Fresh failure from a pre-existing local gate that predates this slice, is independent of the deferred path, and covers a different acceptance.

Tests asserting this slice's own implemented behavior remain allowed under normal verification rules when they are independent of the deferred command.

Otherwise stop polishing that gate, re-enter the status source, and continue only with other in-scope work under the normal continue/stop conditions.

Never auto-continue past a pending blocking or required gate, and never claim deferred evidence is closed.

If over-polishing around deferred evidence recurs, or the user flags it as a reusable process failure, route the lesson through `skill-extraction-workflow`.

## Continuation-proposal output contract (session-wide coverage)

The entrypoint defines the contract itself (exactly one literal `proposed-next:` line per assistant message, in one of its two forms). The coverage detail:

- It binds every assistant message in a delivery session routed by or through the workflow — including "go straight to the owning skill" paths: status answers, questions, review reports, and work dispatched directly to implementation, diagnosis, or another owning skill. Neither the router nor the executor may classify its own turn out of the contract; if it is unclear whether the workflow was invoked, default to carrying it.
- It applies before any slice lands and is not conditional on entering the Pre-Final Continuation Gate.
- At the start of every subsequent user turn, read that literal line before interpreting the reply: an action marker enters the gate's continuing/blocked classification; absence/multiplicity enters `blocked:`/`interim` by default; a `none` marker that conflicts with proposal wording does the same.
- This is an observable prose contract, not a host-enforced hook; a task that never loads this workflow cannot be mechanically controlled by this text, so do not claim it prevents that host-level omission.

## Gate triggers and outcome contract

The session-wide contract creates a second, independent trigger at the start of every subsequent user turn in that delivery session when either (a) the immediately preceding assistant message carries an action-form `proposed-next:` and the user replies, (b) its marker is absent/multiple or `none` conflicts with imperative/future/next-step wording, or (c) a user reply reads as affirmative/permissive toward an explicit assistant-proposed next action — regardless of whether a slice landed or the turn is being finalized. Paths (a) and (b) are unconditional literal/fail-closed checks; marker absence enters path (b) without first asking the agent to recognize why it was omitted.

- Path (c) examples include, but are not limited to, `ok`, `okay`, `yes`, `sure`, `可以`, `好`, `行`, `按这个来`, `继续`, `proceed`, `do it`, `go ahead`, or `👍`; any plausibly affirmative reply enters unless it explicitly says stop/pause.
- Select `continuing:` only when the reply is unambiguously affirmative and the marker or immediately preceding message contains exactly one concrete action and scope.
- An explicit stop/pause selects `blocked:` with that reason; a mixed/ambiguous reply, invalid/conflicting marker, or bare emoji/interjection after status-mixed or multi-proposal prose also enters but must select `blocked:`.
- Before any further action or final response, visibly emit exactly one of `continuing: <action and scope>` or `blocked: <proposed action and scope> — <specific stop, missing authority, or ambiguity>`; emitting neither or both is invalid.

## Status-source reconciliation (gate step 2 mechanics)

Before deriving the next slice from a status source, reconcile it against the applicable current branch/MR/merge/CI/tag state (the landing evidence from step 1, not history-mining). Contradiction shapes: the source claims unstarted/old-version/stub work that is already implemented or merged, or the reverse — either way it is stale. On stale: stop, run a status-source repair slice before inferring anything (repair mechanics in *Landing-state proof* above), and do NOT derive the next slice from the stale source or from a git-log/grep scan. Needing to grep history to guess the next slice is itself a stale-status-source signal, not normal flow. If no status source exists, a touched-repository scan may identify only a candidate next step; do not auto-continue from that candidate unless the user has already given an active continuation instruction for the same product scope.

## Assent binding (gate step 2 assent rule)

- **Affirmative assent to the immediately preceding concrete next-slice proposal** is an active continuation instruction only when the immediately preceding assistant message itself explicitly states one concrete next action and its scope; the required `proposed-next:` marker makes that binding observable, and any concrete next-slice proposal you issue must itself carry the `proposed-next:` marker or a later assent cannot bind — and omitting the marker never self-clears the obligation: an assent whose referent is unmarked is ambiguous and selects `blocked:` with the step-4 form. Select the `continuing:` outcome and bind it to that proposal, not to adjacent status or response-format prose. If assent, the proposal/referent, or authority is genuinely ambiguous, step 4 takes precedence: select the `blocked:` outcome, restate the proposed action/scope plus the specific ambiguity/authority, cite the step-1 evidence, and ask one concise question in the same turn. The `continuing:` default applies only when assent is unambiguous and no step-4 condition holds; self-classifying the reply or marker away is never an exit.

Binding detail:

- Internal developer self-use through already configured model/tool accounts is an ordinary execution detail: it requires no separate quota/cost disclosure, estimate, cap, or per-run confirmation.
- Assent never replaces an owner gate's stricter authorization form and never broadens scope or implies an external purchase/financial commitment, merge, publish, destructive, production, external-message, or high-impact-decision authority.
