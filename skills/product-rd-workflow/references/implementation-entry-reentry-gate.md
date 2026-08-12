# Implementation Entry / Re-entry Gate

Use this reference when a product R&D delivery is about to move from analysis, planning, or continuation into implementation. The entrypoint keeps the trigger and routing decisions; this reference carries the detailed mechanics.

## Baseline Selection

Use existing specs, implementation plans, assessment reports, issue or MR descriptions, or repo-local task docs only after either:

- Reading them back.
- Pointing to artifacts just produced in the current active session.

Then check freshness, scope, owner skills, acceptance checks, tests, stop conditions, and landing state using the shared labels: `local status`, `MR-ready`, `landed`, `release-ready`, or `shared-status-ready`. Record the result as entry/re-entry and fill gaps before editing.

An unmerged plan/spec that is already part of the current active delivery branch may remain the working baseline while that branch continues, under whichever landing label its actual evidence supports. Being pushed or attached to a draft/MR does not demote the current branch's own plan.

A plan/spec belonging to a different line of work — a different branch, a prior superseded slice, or another delivery's pushed/draft/MR-ready artifact — is durable storage, not active baseline authority. It may orient the next action, but it cannot by itself select implementation work.

For those external/unlanded artifacts from a different line of work, the default next slice is to make the review, merge, or status path explicit. Implementation may proceed from them only after the user explicitly selects that artifact as the working baseline and the response records that status.

Explicit selection does not waive the freshness/reality check. Before a selected external/unlanded artifact drives implementation, reconcile it against landing evidence on the real target, repair or supersede stale status, and derive work only from named still-unlanded deltas. An artifact whose items are already landed or satisfied yields no implementation work, not a re-run.

If no usable artifact exists, create the proportionate plan/spec before implementation. Only a simple low-risk single-file change may use a short inline plan.

On a restart/redo of an in-flight delivery, if a prior design/spec/plan exists, recover it for context if available — read it back, including from git history if previously committed — then either reconcile with it or explicitly supersede it with a new/current spec. Discarding the design/spec itself needs an explicit user opt-out after clarification; record deviations in the restored/current spec, or in a restart note if the original artifact cannot be restored. Silently destroying the spec or developing plan-less on a restart without that opt-out is a delivery defect.

## Bare Continuation Scan

A bare "continue", "resume", or "go implement" is not a waiver when no active artifact has already been established and cited in the current session. A record that survives only in a context summary, compacted memory, or previous response residue is not establishment.

When continuation may be resuming product-rd-scoped work, first verify a concrete signal on the real target:

- A named, read-back spec, plan, assessment, or gate artifact.
- A same-scope still-unlanded plan/spec/task doc visible on the current repo/worktree/branch.

Record at least one low-cost scan as evidence, such as `git status --short --branch` plus `rg -n "(plan|spec|assessment|task|需求|方案|计划|规范)"`, hit or no-hit.

Exclude only the off-tree artifact store that the request, branch/repo docs, or MR/issue explicitly names, such as Feishu, Bitable, or a linked repo. This is a bounded set, not a global search.

An unambiguous narrow-owner continuation skips this scan. A context-summary-only or bare-continuation hint that cannot be tied to a concrete artifact pauses for confirmation or persistent-artifact recovery rather than coding.

## Implementation Boundary Record

Invoking or routing a slice to a stack/execution skill (`*-dev`, `*-architecture`, `multi-agent-delegation`, and similar) selects the executor. It is not establishment and is not permission to start implementing.

Reading code to analyze is fine. The transition from analysis to the first implementation edit is the gate.

Before that edit, record:

- Active baseline.
- Scope.
- Implementation-mechanics owner for the slice.
- Implementation-mechanics owner invoked/loaded in-session before the first implementation edit for hands-on product/stack code.
- Which owner mechanical rules were triggered, or `triggered: none` with a one-line reason. Do not enumerate non-triggered rules.
- `multi-agent-delegation` decision when delegation is plausible: `local`, `sequential delegation`, or `parallel delegation`. `local` needs a recorded reason when 2+ slices look independent. A delegating value additionally needs the in-session load, per the invoke bar below.
- Visible-UI checkpoint when the surface is visible UI.
- Short risk inventory routed to `feature-risk-router` when the slice touches money/quota, permission/access, data-isolation, write-finality, shared-gate, or unknown scope.
- Test-case-first status.
- Gate disposition: every pre-code gate above marked `triggered` or `not-applicable` with a reason — a complete accounting, not only the triggered gates.
- Output form: a reviewable plan plus per-point acceptance-coverage matrix.

### The invoke bar applies to every field that names an owner

A boundary-record field that names an owner is filled only from that owner's in-session load, never from the decision alone. Writing the value is the act that feels like discharging the gate, so a field without this bar silently converts its owner gate into self-attestation — the record then reads complete while none of that owner's mechanical rules ever fired.

The bar fires on the field's **triggered** values only, so a slice that legitimately needs none of these owners is not dragged through three loads:

| Field | Invoke required when | No load needed when |
|---|---|---|
| Implementation-mechanics owner | hands-on product/stack code | `not-applicable`, or a recorded `owner-load: not-required` |
| `multi-agent-delegation` decision | delegation is plausible at all — 2+ slices look independent — **including when the recorded value is `local`** | a genuinely single-slice task where nothing was delegable |
| Visible-UI checkpoint | the surface is visible UI | non-visible surface |
| `feature-risk-router` inventory | any listed risk class is present | `not-applicable` with the reason |

`local` is the value that most looks like an exemption and is not one. Serial-versus-parallel is the delegation owner's own decision, taken after checking true independence, write-scope isolation, and the parent verification plan — so choosing `local` while 2+ slices look independent is exactly the owner-bearing judgment this bar exists for, and it is the one path the dispatch hook can never catch, because nothing is ever dispatched. A single-slice task with nothing delegable needs no load.

Test-case-first status is deliberately **not** in that table: it names no owner, it is a status value, and recording it triggers no load. It is listed here only to close the set-diff explicitly, so a later reader does not mistake its absence for an oversight. When a slice needs an actual test-LAYER decision — which layer, what coverage, what fixtures — that judgment routes to `testing-strategy` under its own rules, not under this field's bar.

Naming the owner, quoting its rules from memory, or having invoked it in an earlier unrelated session is not the load. The same reload triggers below apply per owner.

The owner load is rule application, not ceremony. The stack/execution owner is the relevant `*-dev` skill, `not-applicable` with the reason, or `owner-load: not-required` for a simple low-risk single-file product/stack edit whose boundary record names why no owner mechanical-rule class can plausibly trigger. This exception must be surfaced at closeout, not silently skipped.

Shared-skill and process-rule edits are out of this owner-load clause only — they follow `skill-extraction-workflow`'s gates instead of loading a stack `*-dev` owner — but they remain subject to the rest of the boundary record and to the shared-gate persistent-artifact requirement below.

Two failure shapes this field closes:

1. Silently inferring ownership from the repo's stack context.
2. Naming or knowing the owner but coding from memory without loading it, so the owner's current mechanical rules never fire — directory `AGENTS.md` sync, generated-artifact handling, format/gen-before-attestation, idempotency mechanics — even when higher-level gates already passed.

Loading an architecture/design owner is not loading the implementation-mechanics owner. Reload triggers in a long loop are narrow: a new owner/stack, a context resume/compaction with no visible owner-load evidence, or the owner skill file changed. Otherwise one in-session load covers later same-owner slices, cited in the next boundary record.

This is a recognition-dependent firing-point sharpening, not a true mechanical gate. The backstops remain the completion-time check and user-signal escalation.

## Design Gate and Risk Routing

A visible-UI slice must invoke/load `product-ui-ux-design` in-session before the first edit, using the same name-to-invoke bar as the implementation-mechanics owner. Recording or naming the checkpoint from memory is not invoking it.

Loading the implementation-mechanics owner, or any stack `*-dev`, is not loading the design-gate owner. This is the reverse of the architecture-vs-implementation note above.

The record's depth follows the proportionality and persistence rules in the main workflow. A simple low-risk single-file change may mark gates satisfied or `not-applicable` in its short inline plan. Shared-gate, cross-repo, or high-risk changes that trigger the persistent-artifact rule need the concrete persistent artifact.

A stack-skill invocation, worktree, or code-reading is not the boundary record. Reaching the first implementation edit without the boundary record is a process defect: pause, record the boundary, and report current state. This is the same firing point as a stale rule that exists but did not trigger.

## Closeout Backstop

A hands-on implementation slice reported done or merged with no visible in-session load of its implementation-mechanics owner is not process-complete. It owes a post-hoc owner-rule audit:

- Load/read the owner.
- Compare its mechanical-rule classes against the slice's actually touched surfaces.
- Record applied, missed, or `not-applicable` per class.
- Record follow-up before claiming the slice clean.

A slice whose boundary record carries a valid `owner-load: not-required` exception is exempt from this post-hoc load, but closeout must still surface that recorded reason. A bare `missed: none` without touched-surface comparison is not a valid audit.

The same completion-time audit applies to every owner whose boundary field was triggered, not only the implementation-mechanics owner. It governs slices whose boundary record is written under this rule — it does not reopen work already closed out under the narrower earlier bar. A slice completed before this extension is not retroactively process-incomplete; apply the wider audit from its next boundary record onward. A visible-UI slice reported done with no in-session `product-ui-ux-design` load owes a post-hoc design-gate audit; a slice that recorded a delegating `multi-agent-delegation` decision with no in-session load of that owner owes the same audit against its dispatch-blocking rules, and so does a triggered `feature-risk-router` inventory. Each stays process-incomplete until recorded. Test-case-first is excluded here for the same reason it is excluded from the table above.

The git landing state, such as merged or MR-ready, is a separate fact that is not relabelled. A late token load does not clear the audit.

Shared-skill changes follow `skill-extraction-workflow`'s stricter "no in-session extraction invocation ⇒ interim" closeout.

An explicit, acknowledged gate opt-out follows the precedence order in the main workflow and must be recorded as such.

Shared deterministic gate/verifier and cross-repo coordination-surface changes carry a stricter persistent-artifact requirement when they alter that surface's rule, scope, failure, or completion semantics. For those, a chat-only plan is not active and a concrete repo-local artifact path must be cited before implementation edits, as defined under the main workflow's *Enforce quality gates* bullet beginning "For product/spec normalization".
