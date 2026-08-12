# Security-Review Gate

Conduct rules for the **security-review gate label** in `feature-risk-router`. This is a router label, not a skill route; this repo does not define a CCL skill named security-review. This file owns the gate's **status** and **safety boundary** only; it does NOT define a security-audit method (no checklist, phase catalog, or report schema lives here — that is the method layer, owned by a dedicated security skill or a professional firm).

## Gate statuses (exactly one)

The security-review gate is in exactly one state. This router can never set `passed`.

- **not-applicable** — **change-triggered arm only**: `security posture unchanged` is recorded with every posture-change blocker ruled out (see "Co-applies" below). An explicit audit / threat-model / pentest request is never **not-applicable** — it is at least **pending-dedicated-review**.
- **pending-dedicated-review** — the gate applies and no accountable security owner has completed it. **The inline first-pass triage and any external-recipe run (e.g. `gstack-cso`) land HERE — this is the ceiling for anything this router can produce.**
- **passed** — set ONLY by a named accountable security owner or a professional review. Never set by the inline pass, by an external recipe's output, by model judgment, or by a risk acceptance.

Absence of a dedicated owner or recipe does not block *unrelated* work, but it leaves the security-review gate at **pending-dedicated-review**, never satisfied. A risk owner may accept the residual risk and ship past a **pending-dedicated-review** gate, but that is a separate recorded ship / accept-risk exception (per Stop Rules) and **leaves the gate at pending-dedicated-review — it does not make it `passed`**. Proceeding past a pending gate is a risk-owner / user decision, never something the inline pass or an external recipe can grant.

## Method ownership

There is no ccl-owned security-audit *method*. The router owns only the gate's status and how the review is conducted safely.

- If an external security-review recipe is available in the current session (for example `gstack-cso` — **external / reference-only, not a CCL owner and not a pass authority**), use it as the supplemental operational method. Its output is method *evidence* that informs the gate; it does not by itself move the gate to `passed`, and its absence does not lower the bar.
- With no such recipe, the most you may run is a bounded read-only **first-pass triage** — OWASP-Top-10 / STRIDE used only as a lens to surface obvious questions and findings, not as a comprehensive method or coverage claim.

## The inline first-pass is triage-only, never a completed review

- For any case where the tag applies, the inline pass status is **pending-dedicated-review** (with `stop reason: dedicated security owner / professional review required` for an explicit audit / pentest / threat-model request, a sensitive or production system, a new trust boundary, or secret handling). It never satisfies the gate.
- Never emit "secure", "audit passed", or a standalone "no findings" as audit completeness from the inline pass. "No findings in a bounded first pass" is not "the system is secure."

## Read-only conduct — this router never runs exploit tests

Verify by code-tracing and guardrail inspection only. Never use a live exploit, real or production-like credentials, a destructive / privileged / irreversible action, or production mutation as verification — the same boundary as `testing-strategy`'s runtime auth-boundary rule. Production or production-like credentials and any production mutation are **always invalid** here, not merely "stop and confirm".

This router never conducts an exploit test itself. A genuine exploit test is a separate, dedicated exercise — generic "audit / pentest this" wording is **not** authorization for one. It may proceed only when routed to a dedicated security / `testing-strategy` owner AND with explicit current-turn authorization naming: target environment, synthetic tenant / account / credentials, allowed actions, a non-production / sandbox boundary, no real external side effects, rollback / stop conditions, and the responsible owner. Any missing field, or any production / production-like target, → stop.

## Subordinate to Stop Rules; co-applies with other tags

- The security-review gate **never de-escalates** another risk tag or a Stop Rule. If security / privacy assumptions, the identity model, external permissions, or local-verification authority are unclear, STOP and ask (per the router's Stop Rules) before treating any review gate as passed. The inline pass may only collect questions and evidence; it must not self-resolve the assumption.
- It **co-applies** with `permission-access`, `external-integration`, `release-ops`, and `ai-action`; those tags do not suppress it. The omit (`not-applicable`) path is for the **change-triggered arm only** — an explicit audit / threat-model / pentest request is never omitted. Mark the change-triggered arm `not-applicable` only after explicitly recording `security posture unchanged` and ruling out a new / altered trust boundary, untrusted-input surface, sensitive sink, auth / authorization semantics, data visibility, secret handling, hardening, or vulnerability-fix intent. It is the security-posture lens, not a duplicate of the per-surface tags.

## Finding shape and sub-routing

- Normalize every finding per the shared review-finding standard (`skill-extraction-workflow/references/review-finding-standards.md`): failure_path + impact + evidence + smallest_fix; reject speculation and noise.
- Sub-route depth to existing owners: test / proof evidence → `testing-strategy`; LLM / agent security → `llm-inference-integration`; release / rollout security → the platform owners; classifying a specific change's risk stays in `feature-risk-router`'s other tags.
