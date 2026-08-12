# Resume paused delivery — premature-stop recovery binding rules

Companion to the **auto-trigger durable learning** Core Rule in `SKILL.md` (under *Retrospectives, corrections & auto-triggered learning*). The Core Rule carries the gate: for a premature-stop correction after affirmative continuation, immediate recovery first reruns the active owner's current continuation/blocking gate in full (for product R&D, Pre-Final Continuation Gate steps 1–6) against current state, and recovery proceeds only when a literal binding exists. This file carries the relocated binding detail: what counts as a binding, the `continuing:`-line form, and what makes a `blocked:` recovery invalid.

## The two binding paths

Bind recovery when either:

- **(a)** the literal original `proposed-next:` action/scope (or literal explicit proposal for a pre-marker incident) and literal assent are preserved in the visible conversation or quoted exactly in trusted host-owned session/compaction state; or
- **(b)** the current user's premature-stop correction itself literally names the paused action and scope — on path (b), quote those exact user words in the visible `continuing:` line before proceeding.

A semantic compaction paraphrase or a bare "why did you stop" complaint is not path-(b) authority. Never copy real conversation text into a shared repository record, reconstruct, broaden, or substitute it. The user's challenge is a current reactivation signal for that exact slice, not a demand for redundant reconfirmation; restate and proceed only when path (a) or (b) binds, and ask again when neither path binds the slice, the user intervened, or current scope/gates changed.

## Invalid `blocked:` recovery

A `blocked:` recovery without the step-1 evidence and a specific missing authority/ambiguity is invalid: rerun the gate and emit a well-formed outcome before any action; if ambiguity remains, ask the blocker question in the same turn and stay blocked. Do not let correction RCA or extraction extend a still-authorized delivery, and do not let stale assent bypass a newly pending or inconclusive gate.
