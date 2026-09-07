# Resume paused delivery — premature-stop recovery binding rules

Companion to the **auto-trigger durable learning** Core Rule in `SKILL.md` (under *Retrospectives, corrections & auto-triggered learning*). The Core Rule carries the gate: for a premature-stop correction after affirmative continuation, immediate recovery first reruns the active owner's current continuation/blocking gate in full (for product R&D, Pre-Final Continuation Gate steps 1–6) against current state, and recovery proceeds only when a literal binding exists. This file carries the relocated binding detail: what counts as a binding, the `continuing:`-line form, and what makes a `blocked:` recovery invalid.

## The two binding paths

Bind recovery when either:

- **(a)** one concrete original proposal, its scope, and the assent are preserved verbatim in the visible conversation or read back verbatim from trusted host-owned session state; a `proposed-next:` marker is not required; or
- **(b)** the current user's premature-stop correction itself literally names the paused action and scope — on path (b), quote those exact user words in the visible `continuing:` line before proceeding.

A semantic compaction paraphrase supplies neither binding path; recover the original proposal and assent before deciding path (a) is unavailable. A bare "why did you stop" complaint does not itself name path (b)'s action and scope. Never copy real conversation text into a shared repository record, reconstruct, broaden, or substitute it. The user's challenge reactivates that exact slice. Restate and proceed when either path binds; ask only when the action, scope, or required authority remains unresolved. A new user message or a changed gate requires reassessment, not automatic reconfirmation.

## Invalid `blocked:` recovery

A `blocked:` recovery without applicable state evidence and a specific remaining blocker is invalid: recover intent and rerun the owning gate. If a decision or permission remains unresolved, ask in the same turn and block that dependent action. Continue available authorized diagnosis, bounded remediation, or independent work; do not let stale assent bypass a newly pending or inconclusive gate. Do not let correction RCA or extraction delay recovery of a still-authorized delivery.
