# Artifact-Egress Confidentiality Gate

A pre-egress confidentiality pass for delivery artifacts. This gate owns **only the semantic confidentiality axis** that secret/PII scanners miss; it is not a general redaction framework and not a scan-every-internal-doc ritual.

## When it fires (and when it does not)

Fires when a delivery artifact, **or any text generated from it**, crosses the local trusted boundary. Run the pass **before** the write / create / push / send API call, not after:

- shared/collaborative stores: Feishu/Bitable writeback, an external tracker, a shared or public doc, a wiki;
- request bodies: an MR/issue body, a PR/MR review comment or review packet;
- **durable VCS / release metadata**: a commit message, a branch or tag name, a release note / changelog, CI or release metadata, or any platform-generated body derived from the artifact (these leak into remote history even when the MR body is clean);
- model/worker handoffs: an external assistant/model call, or a delegated worker/agent prompt.

Scope of in-scope artifacts: product specs, plans, requirements, status/writeback docs, launch/task cards, and product-delivery retrospectives.

- **Does NOT fire** for work kept on the local machine, an internal need-to-know transient with no cross-boundary handoff, or an artifact that never leaves the box. Egress is the trigger — not "every document".

## The gate's own output is also egress (do not leak via the finding)

The block reason, gate finding, review packet, audit note, and any "categories considered" record are **themselves egress artifacts**. When the destination of that record crosses the boundary, it must **not quote the raw sensitive span or the real name** — that re-leaks exactly what the gate stopped. Use **category + a sanitized placeholder + a local-only locator** (e.g. "named-person+negative-judgment at spec §3, line 12"); the raw context stays local/private unless the owner explicitly approves that exact span for that exact destination.

## What this gate owns vs routes out

Route these to their existing owners — do **not** re-implement secret scanning here:

- secrets / credentials / tokens / keys, raw logs → `platform-observability` redaction + the `feature-risk-router` security-review gate label.
- diagnosis evidence pasted to an external assistant / public web → `defect-diagnosis` evidence sanitization.
- PII / customer data fields → the owner above; this gate does not duplicate field-level PII regex.

This gate owns the **semantic confidentiality axis** — sensitive even when no credential or PII field is present:

| Category | Action |
|---|---|
| A named person tied to a negative judgment ("underperforming / missed / fired / ignored") | rephrase to a role/function ("the owning team"), do not name the individual |
| A customer / vendor tied to a negative event | anonymize ("Customer A" / "a vendor") |
| Unannounced strategy / roadmap / not-yet-public plans, internal staging language, internal KPI targets | remove or generalize, OR confirm the destination is explicitly approved (see below) |
| NDA-bound material (partner deck, named vendor under NDA) | **block** until the owner explicitly approves — the agent never self-approves |
| Internal codename not used publicly | replace with a generic/public label |

## Severity and block behavior

- **Hard-category block** (NDA-bound; clear confidential strategy headed to a broad/public destination): do **not** write the raw artifact across the egress boundary — not to the destination, tracker, worker prompt, or review packet.
- **Confirm category** (named-individual / customer-tied / codename / internal KPI to a need-to-know internal destination): surface it (sanitized, per the output rule above) and let the user/owner decide rephrase / anonymize / proceed-with-acknowledgement; on a broad/public destination, "proceed silently" is not offered — rephrase or stop.
- **Block stops the egress, never the work.** Do not persist the raw artifact *across the boundary* on block; **preserve it locally** — keep the draft in its normal working location or a local user-controlled scratch path, and if it exists only in model context, save it locally before blocking. Never delete or overwrite the user's draft to "resolve" a finding. The remedy is rephrase-then-resend or an owner decision, not data loss.

## Authority stays with the user/owner

- This gate flags and proposes; it does not unilaterally approve an NDA exception, decide a roadmap is publishable, or push past the user. Cross-model or self-judgment that "it's probably fine" is a recommendation, not a clearance.
- **"Explicitly approved" = the user/owner approving this exact sensitive content/span for this exact destination** — never a broad "content class" the agent can later sort new raw NDA/roadmap material into. ACL membership, "it's an internal channel", a whole-organization wiki/Feishu/MR being "internal", or agent/cross-model inference is **not** approval. Treat broad-internal, broadly-shared, and unknown destinations as the public/strict tier unless the user/owner confirms need-to-know for that exact content.
- A confidentiality **proceed-acknowledgement authorizes only that one content-egress decision.** It never authorizes merge, auto-merge, default-branch push, force-push, deletion, or cleanup — those keep their own separate authorization gates.

## Not a "passed" badge (avoid false precision)

A clean pass is not a certification that the artifact is confidential-safe. Record only the categories considered and the action taken (or that none fired), sanitized per the output rule — never emit "semantic safety passed / no confidential content" as a guarantee. The pass is a best-effort LLM-judgment triage, the same posture as any review finding under `skill-extraction-workflow/references/review-finding-standards.md`.

## Delegated-worker firing point: multi-agent-delegation

`multi-agent-delegation` enforces this gate at the delegated-worker firing point: before a worker prompt includes a delivery spec/plan/requirement/status/retro/task card, it runs this pass and sanitizes the prompt (a controller can dispatch from an multi-agent-delegation path without reloading `product-rd-workflow`, so the rule must also live at that dispatch site).
