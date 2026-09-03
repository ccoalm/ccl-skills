# Incident / Postmortem → Skill Extraction

Layer on top of the main extraction flow when the source is an incident, outage, regression, security event, data corruption, deploy failure, or a postmortem document. The goal is to turn a single bad event into a **durable failure-class guardrail** owned by the right skill — not a procedural patch about that one incident.

## When this layer applies

Apply when at least one of:
- A production incident happened (user-visible outage, error budget burn, data loss/corruption, security event, perf regression, deploy/rollback).
- A near-miss was caught only because a human noticed (would have been an incident without that human).
- A postmortem doc / RCA write-up exists or is being written.
- A regression keeps recurring across services or repos.

Do NOT apply when:
- The fix is a code change with no systemic lesson — commit + move on, no skill edit.
- The "incident" is just a user mis-using the product correctly. Route to product / UX skills if there is a UX gap; otherwise discard.
- The lesson is fully owned by code/tests/CI/monitoring config and does not change how future agents decide — land it there, not as agent behavior.

## Incident as a source class

This pattern **extends** the standard source-register row defined in `source-register.md` (`source_id | source_type | class | path/file_key | status | min_depth | actual_depth | extracted_mechanisms | discarded_business_details | target_skill | evidence_link`). The columns below are the additions and conventions specific to incident sources; do not omit the required columns from the standard row.

This pattern **specializes the standard singular `target_skill` field into plural `target_skills`** (see below), with an additional `coordination_owner` to hold the multi-owner invariant. The shared register schema remains singular until a parent rewrite lands plural ownership across all extraction classes; treat the plural variant as a documented per-pattern specialization, not a contradiction.

| Column added or specialized | Convention |
| --- | --- |
| `source_id` | sanitized event handle (no real ticket id, no customer name, no date with year tied to a known event) |
| `source_type` | `incident` |
| `class` | `outage` / `data` / `security` / `perf` / `deploy` / `near-miss` / `recurring-regression` / `external-dependency` |
| `severity` | placeholder severity tag — use generic tokens like `<severity-high>` / `<severity-medium>` / `<near-miss>` in the shared register; real severity labels live in the private alias map |
| `evidence` | what is actually inspectable: timeline excerpts (sanitized), alert rule, dashboard panel, code diff that introduced it, code diff that fixed it, runbook snippet |
| `min_depth` / `actual_depth` | per the standard rules — `summary-only` / `timeline-only` / `fix-diff-only` / `full-postmortem-read` |
| `discarded_sensitive_details` | enumerate the PII / customer detail / dashboard URLs / auth material that was inspected and discarded; protects against the same detail leaking via a later mining pass |
| `target_skills` | **plural — list every affected skill.** An incident commonly updates a stack/dev skill + a platform/ops skill + the extraction workflow itself + `testing-strategy`; never collapse to one target. Each owner gets its own target-output row downstream. |
| `coordination_owner` | the single skill that holds the canonical cross-skill invariant for this incident. Other `target_skills` rows reference their slice of that invariant. Without this, a multi-owner landing fragments — each owner passes review while no skill owns the end-to-end guardrail. |
| `canonical_guardrail` | one-sentence statement of the invariant the coordination owner holds (e.g. "stateful writes are idempotent at every entry point"). Each per-owner row implements a slice. |
| `completion_evidence` | the counterfactual replay outcome + which gate the new rule installs |
| `status` | `pending` / `mined` / `routed` / `excluded` |

If the only evidence is a summary or chat scrollback, mark `actual_depth: summary-only` and downgrade extraction confidence accordingly. Do not promote a summary-only incident into a strong cross-skill rule.

## The transform method (incident → durable rule)

Five steps. Each must produce a recorded line; missing any line means the extraction is shallow.

1. **Failure class** — generalize the specific event to a class. "Service X dropped writes during deploy Y on date Z" → class: *write loss during rolling restart of a stateful component*. The class is what future agents must recognize; the incident is just one instance.
2. **Causal chain (earliest practical prevention point)** — this is the *deepening* branch within the Deep RCA five moves (see `source-to-skill-extraction.md`, Deep RCA For Extraction): you still **widen** to the multiple contributing factors first, split **active vs latent** conditions, and use **local rationality** (why it made sense at the time) rather than one linear chain — then deepen each material branch here. Record why each prior layer did not catch it. Do **not** stop at the first controllable layer; a test or a review is often controllable but only catches the symptom while the actual durable fix is upstream (contract definition, schema ownership, capability model, MR readiness, release process). Continue the chain until you identify the **earliest practical prevention point in the delivery chain**, then list each later layer that could *also* have caught it as a **secondary control** (defense in depth). "Engineer was tired" is not controllable; "the contract had no idempotency key requirement and the contract review skill did not enforce it" is the earliest practical prevention point, with "the integration test suite did not exercise duplicate delivery" as a secondary control. **"Earliest practical" is bounded by executable enforceability:** the earliest gate that has all four of (a) a named artifact (skill rule / contract field / test / review checklist item / launch gate item), (b) an owning skill or team that can change it today, (c) an observable check an agent or reviewer can run, and (d) a **reachable surface** (bootstrap / description / closeout / hook / CI) that makes the next agent actually hit it in time — a rule landed only in a deep reference nothing routes them to read does not fire (per the Core Rule firing-path proof). If a candidate upstream gate lacks any of the four, it is a context principle — record it, but the first executable downstream gate becomes primary, not the principle.
3. **Missing gate** — name the specific gate at the earliest practical prevention point and any secondary gates. Pick from: design checkpoint / arch review / contract definition / schema ownership / capability model / unit test / integration/contract test / E2E / load/perf test / chaos test / security review / code review / launch checklist / canary / monitoring & reconciliation / runbook / on-call rotation / postmortem follow-through. If the gate already exists but did not fire, the bug is in the *gate's executable wording*, not in "we should add a gate."
4. **Owning skill(s)** — map each gate to the skill(s) that own it (see routing table). Usually more than one skill; the `coordination_owner` field of the source-register row records which skill holds the canonical cross-skill invariant. Sibling-generalization mini-map still applies. Default owner resolver when no exact sibling exists: route by lifecycle, **stack-implementation last** — product-risk gates → architecture contract → testing strategy → release/rollout → observability → security → extraction workflow → stack-implementation. **Stack-first override:** when the prevention depends on language / framework / runtime / package-manager / build-tool semantics (e.g. Go `http.Response.Body` lifecycle, Python asyncio cancellation semantics, JVM classloader behavior, Rust borrow-checker pattern, Node event-loop starvation, Flutter rendering pipeline), route first to the affected stack `*-dev` or `*-architecture` skill — lifecycle owners (release/rollout, tests, observability) become secondary controls. Use lifecycle-first as the default, stack-first as the override; record which path was chosen and why.
5. **Counterfactual replay** — write the new rule, then record in the provenance-to-target diff: incident class, the specific source signal the rule keys off, target file/line, gate name, the observable check an agent will run, and whether the new rule would have blocked the incident at that gate before the consequence. If any field is generic, the rule is not yet executable; tighten or downgrade to `working hypothesis` until a second incident or independent evidence confirms it.

## Routing table — incident class → likely owning skills

Owners are exact skill names. An incident with hybrid causes maps to a **coordinated owner set** (one extraction touches every owner in the row), not to multiple independent table rows.

| Incident class | First-pass owners (coordinated set) | Common second owners |
| --- | --- | --- |
| Production outage from deploy | `platform-release-engineering` + `platform-observability` (detection lag) | the affected stack skill (`go-microservice-architecture` / `python-service-architecture` / `web-react-dev` / `app-cross-platform-dev`) only for service-internal architecture rules |
| Data corruption / write loss | the affected `*-architecture` skill (contract / idempotency / ordering / schema ownership) + `testing-strategy` (contract & duplicate-delivery tests) | `platform-release-engineering` (migration & runbook); `platform-observability` (reconciliation) |
| Security event | installed security owner (`cso` if present; no dedicated security skill exists in this repo — otherwise `feature-risk-router` security-review gate) + the affected `*-dev` skill (input validation / auth / capability model) + the affected `*-architecture` skill (trust boundary) | `platform-release-engineering` (secrets handling) |
| Perf regression in prod — pure runtime/capacity | `platform-observability` (SLI/SLO) + the affected `*-architecture` skill (capacity / quota) | `testing-strategy` (load) |
| Perf regression caused by deploy / config / build / asset change | `platform-release-engineering` + `web-react-dev` / `app-cross-platform-dev` (build & runtime assets) | `platform-observability` (detection); `testing-strategy` (deploy-bound perf checks) |
| Schema / data migration or version-skew caused by deploy or config rollout | `platform-release-engineering` (rollout ordering & rollback) + the affected `*-architecture` skill (schema compatibility) + `testing-strategy` (migration & version-skew tests) | `platform-observability` (reconciliation & skew detection); the affected stack `*-dev` skill (implementation mechanics) |
| Feature-flag default change / config rollout causing segmented failure | `platform-release-engineering` (flag rollout & default-change discipline) + the affected `*-architecture` skill (flag-gated invariant) | `platform-observability` (per-segment detection); `testing-strategy` (flag-state tests) |
| Deploy / rollback failure | `platform-release-engineering` + `platform-service-connectivity` (traffic) | `platform-observability` (deploy markers); the affected stack skill if the failure was stack-specific |
| External dependency / async callback / probabilistic failure | `platform-observability` + `platform-service-connectivity` (reconciliation & repair) | the affected `*-architecture` skill (boundary contract) |
| Recurring regression across services | `skill-extraction-workflow` (the extraction or routing rule that allowed it) + the shared `*-architecture` skill that owns the contract | per-stack `*-dev` skill only if the rule is genuinely stack-specific |
| Near-miss caught by human | the gate that should have been automatic at the earliest practical prevention point (route per the table above) | `platform-observability` if detection was the gap |
| User error producing real harm | `product-ui-ux-design` (state design / confirmation / undo) + `web-react-dev` / `app-cross-platform-dev` (implementation) | `testing-strategy` (interaction & dangerous-action tests) |

### No-owner decision rule

If no owner in the table fits the candidate rule, apply this single decision rule (replacing earlier conflicting guidance):

- The prevention is **runtime-enforceable only** (code / config / test / monitor / runbook with no agent-decision content) → land it there, not as a skill edit.
- The prevention is an **extraction, review, routing, or agent-decision guardrail** (a future agent must remember to check or decide something) → route to `skill-extraction-workflow`.
- Otherwise → **block landing until an owner is named.** Do not orphan the rule in a stack skill it does not belong to.

## Anti-patterns

Block these before landing:

- **Overfit to the incident** — "always check column `foo` before deploy of service `bar`" is procedural; the rule should be "stateful components require an idempotency contract verified by a contract test before launch."
- **Procedural patch as rule** — what the on-call did during the incident is not the durable rule. The durable rule is what the next agent must do BEFORE the incident can happen again.
- **Single-incident threshold inflation** — one outage caused by a 99th-percentile event does not justify a guardrail that blocks the common path. Calibrate the rule's strictness to the failure class's likely recurrence and blast radius. **Carve-out (evidentiary, not categorical):** irreversible data loss, security boundary bypass, money movement, public or destructive admin action, or compliance exposure can override recurrence calibration — but only when the extraction records all of: (a) the specific category, (b) evidence that repair is impossible or hard (no clean rollback, no idempotent retry, no compensating action, regulator notification required), (c) blast radius (population affected, blast scope), (d) the **narrowest workflow** that triggers the gate (the strict rule applies only to that workflow, not to all admin/security/money paths), and (e) the gate scope (what action it actually blocks). Without that row, fall back to recurrence × blast-radius calibration. The carve-out is not a category badge; it is a contract.
- **Missing-gate misattribution** — saying "we needed a code review" when the diff was reviewed; the real miss was that the reviewer did not have a checklist item for the failure class. Fix the checklist, not the abstract gate.
- **Sibling miss** — landing the rule only in the stack/service where the incident happened, when the failure class clearly applies to siblings. Run the sibling-generalization mini-map and the default owner resolver (lifecycle first, stack last).
- **Lessons-learned dump** — copying the postmortem's "lessons learned" section verbatim into a skill. Postmortem lessons are often advisory; skill rules must be executable. Translate each lesson into an observable checkpoint, decision rule, or acceptance criterion.
- **Passive alerting as the only rule** — adding a dashboard or alert as the sole rule when a preventive gate is available. For incidents where preventive gates exist (contract / test / review / canary), monitoring is secondary. (See exception in the next bullet.)
- **Skipping the counterfactual replay** — if the provenance-to-target diff cannot name a specific observable signal the rule keys off, do not land it.
- **Naming the incident in the rule body** — rule text must not contain the customer name, real ticket id, real date, real service name, real on-call name. These go in provenance only.

### When monitoring / reconciliation **is** the primary rule

For failure classes where prevention is genuinely not available at gate time — external dependencies (vendor APIs, third-party webhooks), async / eventually-consistent callbacks, fraud and anomaly detection, data reconciliation against an external source of truth, probabilistic failures, failures only observable after the fact — monitoring or reconciliation may be the **primary** rule. "External dependency" alone is not the justification — many external failures (duplicate webhook delivery, payload-shape changes, vendor 5xx storms) can still be prevented at the **local boundary**.

**Prevention-disqualification checklist (required before monitoring may be primary).** For each applicable local preventive gate, mark whether it is available; monitoring becomes primary only when every applicable gate is `unavailable` with evidence:

- Boundary contract — can we constrain the request/response schema at our edge?
- Idempotency / deduplication — can we dedupe inbound or outbound requests?
- Timeout / retry / backoff policy — can we bound vendor latency and retries?
- Capability / auth validation — can we verify the caller's authority before acting?
- Contract / replay test — can we exercise the failure shape in CI?
- Canary / staged rollout — can we ship the change to a slice first?

If any gate is **available**, it is the primary rule; monitoring is a secondary control. When monitoring is primary:

- Name the specific signal and the threshold (not "watch for errors").
- Pair it with an **executable repair or escalation path** (compensating action, retry policy, rollback trigger, on-call runbook step). Detection without action is not a primary rule.
- Record the disqualification checklist outcomes inline, so a future reviewer does not mistake this for a procedural patch.

## Counterfactual verification (recorded in provenance-to-target diff)

Before landing the rule, record in the provenance-to-target diff a row with these required fields:

- `incident_class` — one phrase, sanitized.
- `source_signal` — the specific observable feature an agent will look for (a code shape, a contract field, a test name, a release-gate item).
- `target_file_line` — where the new rule lands.
- `gate_name` — the gate from step 3 above.
- `observable_check` — the executable check an agent following the skill will run.
- `would_have_blocked` — `yes` / `no` / `partial`, with a one-line justification tracing source_signal → gate → consequence.

These additional fields are **required when applicable** (omit only if the incident genuinely had no such dimension; under-specifying a real dimension makes the rule look executable while hiding where the signal must be checked):

- `affected_surface` — the specific page, endpoint, queue, table, or interface the rule applies to.
- `change_vector` — what introduced the bad state (code change, deploy, config flip, schema migration, data import, vendor change).
- `scope_segment` — which population, tenant, locale, or device class is affected (when the failure is segmented).
- `rollout_phase` — canary / partial / fully rolled out / post-release (when the failure depends on rollout stage).
- `control_plane` — the surface where the rule actually gates (feature-flag system, IaC pipeline, deploy gate, contract schema, CI step).
- `secondary_control_gap` — which secondary controls also failed to catch this (defense-in-depth audit).

If any required field is generic, the rule is not executable; downgrade to `working hypothesis` and do not promote until confirmed.

## Sanitization additions for incident sources

Incident sources carry PII and sensitive operational detail beyond the standard sanitization set. These categories **extend** the main R0 audit categories defined in `SKILL.md`; they do not replace them. The shared file carries only the category list — the per-project scan patterns and allow-lists live in the project's private alias map (`audit_cmd`) per the parent R0 rule.

Categories the incident-commit audit must zero out:

- Severity / priority / response tier labels embedded as literals (sev-N, P0–P3, response-level tokens) — keep only sanitized placeholders in shared text.
- Specific calendar dates tied to a known event (ISO date, deploy week / quarter labels with year).
- Ticket / Jira / Linear / Asana / GitHub Issues incident ids; postmortem document handles or numbers.
- Vendor and observability tooling hostnames and URLs (PagerDuty, Opsgenie, Datadog, Sentry, Grafana, Kibana, Splunk, New Relic, Honeycomb, plus internal mirrors).
- Customer / tenant / org names and any customer-shaped or employee-shaped identifier (`user_id`, `employee_id`, `tenant_id`, `org_id`, `account_id`, `openid`, `unionid`).
- On-call / responder / reviewer real names; team Slack / Lark / Teams channel names that carry product or domain identity.
- Email addresses, phone numbers, IP addresses (v4 and v6), MAC addresses, postal addresses.
- Auth material: `Authorization` / `Cookie` / `Set-Cookie` / `X-Api-Key` headers and their values; bearer JWTs (`eyJ…` shape); API key shapes; OAuth `access_token`/`refresh_token` query params; session ids.
- Cloud storage locators: presigned URLs and their query parameters (`X-Amz-*`, `signature=`, `expires=`), real bucket / object names, container / blob names, GCS / S3 / OSS paths.
- Internal hostnames, dashboard URLs with real paths, alert rule names, runbook paths.
- Real error messages that embed identifiers / paths / tokens — quote only the generic shape (`"<resource> not found at <path>"`).
- Structured-log PII field values — even when the *field name* is generic, the *value* may carry PII; strip the value.
- Real CVE numbers when the rule is generic — link in provenance only, not in the rule body.
- Regulated identifiers: payment card numbers (PAN, CVV, expiry), bank account / IBAN / routing numbers, government-issued ids (passport, national id, tax id, SSN-shape), driver license, vehicle id (VIN), insurance / policy numbers.
- Health and legal content: medical record fragments, diagnosis codes (ICD/CPT), prescription / medication detail, legal case identifiers, contract-protected content.
- Unstructured user-supplied content from the incident: free-form user messages, uploaded document text or OCR extractions, support transcripts, chat logs, call transcripts.
- LLM / AI surfaces: prompts and responses captured from production, model debugging traces with user content, tool-call arguments containing user data, embedding-input dumps. Redact even when the model run is sanitized in product logs — incident artifacts often include the raw payload.

The actual grep patterns, per-category regex, and per-project allow-lists for these categories live in the project's `audit_cmd` in the private alias map. Maintainers extending this audit set must add the corresponding patterns there.

## Quickstart adaptation

When the extraction is incident-driven, the main `extraction-quickstart.md` flow gets these per-step adjustments:

- **Charter** — name the failure class and the future incident this extraction prevents (not "incident on date X"). Record blast radius and recurrence likelihood explicitly so a future reader can calibrate strictness; record carve-out applicability (irreversible / security / money / compliance) when relevant.
- **Source register** — extended standard row above; include the postmortem doc, the fix diff, and the detection evidence as separate inspectable artifacts with `min_depth`/`actual_depth` set.
- **Batch** — for multi-contributor postmortems, batch by failure class, not by section of the doc. One class can produce rules in multiple owning skills.
- **Sibling mini-map** — required even for "single service" incidents; most failure classes generalize across stacks more than the incident narrative implies. Apply the default owner resolver above.
- **Dual-track review** — the challenge pass must specifically attack the rule with: "what's the simplest variant of this incident that still slips past the new rule?" If it finds one, the rule is under-specified.
- **Counterfactual** — recorded per landed rule in the provenance-to-target diff, before commit.

## Failure modes (specific to this layer)

- **Postmortem-as-novel** — extracting every paragraph as a rule. Postmortems are mostly narrative; only the controllable causal points become rules.
- **One incident, many rules** — fine if each rule maps to a distinct failure class with its own counterfactual. Suspicious if all rules trace to the same root cause; consolidate.
- **Long-tail incidents driving common-path rules** — heavy guardrails added because of a once-in-three-years event. Calibrate to recurrence × blast radius — except for the irreversible/security/money/compliance carve-outs, where one incident is enough.
- **Detection-only fixes treated as primary when prevention exists** — adding alerts/dashboards as the rule when a real preventive gate (contract / test / review / canary) was available. Acceptable as a *secondary* rule (defense in depth). For external/async/probabilistic classes where prevention is unavailable, monitoring + repair path may be primary — see the carve-out above.
- **Cross-team rule landing without owner** — incidents often span teams; apply the no-owner decision rule (runtime → code/config; agent-decision → `skill-extraction-workflow`; otherwise block). Do not orphan the rule in a stack skill it does not belong to.
- **Stopping at the first controllable layer** — landing only the test or review rule when the contract / schema / capability owner is the real earliest practical prevention point. Continue the chain; list later layers as secondary controls.
- **Re-extracting the same incident twice** — happens when the first extraction landed only the procedural patch. Treat the second pass as a failure-class extraction, supersede the procedural rule, and record why the first pass was insufficient.

## Success reviews — the sustain half of learning

An incident is one source class; ordinary work that went right is the larger one, and the entrypoint's result-classification rule already requires a `stable success` to carry mechanism, non-luck evidence, reuse conditions, firing point, and owner. Two obligations that rule leaves implicit, each with a primary source:

- **Record the success mechanism as work-as-done, not as rule compliance.** Things go right mostly because the agent adjusted its work to the actual conditions, not because a rule was followed to the letter; a `stable success` row must name the adjustment that produced the outcome (which condition was read, what was varied, what was checked) and only then whether an existing rule fired. A row that says "the rule was applied" names compliance, not the mechanism, and cannot transfer when conditions differ. (Hollnagel & Leonhardt, *From Safety-I to Safety-II*, EUROCONTROL 2013: "the reason that things go right is not people behave as they are told to, but that people can adjust their work so that it matches the conditions"; "we cannot make sure things go right just by preventing them from going wrong".)
- **A sustained practice carries its own re-examination trigger.** Repeated success with a procedure accumulates experience with it and starves the alternative of a fair trial, so a sustain row must name the condition under which the practice is re-tried against an alternative (a changed host capability, a cheaper tool, a second consecutive workaround, a cost row that stops improving) — reuse conditions say where it still holds; the trigger says when to stop assuming it does. (Levitt & March, "Organizational Learning", *Annual Review of Sociology* 14, 1988: competency trap and superstitious learning — the disconfirming observation the classification rule already requires is the guard against the second.)
- Every retro asks the sustain question next to the improve question, but a sustain row must be written only when stable-success evidence meets the entry bar (mechanism + non-luck evidence + reuse conditions + firing point + owner); otherwise the retro records an explicit `no-new-lesson` or `unstable/insufficient evidence` disposition on the sustain side, never a fabricated success. The pairing has evidence in its own settings: reviewing successes and failures together improved subsequent performance more than reviewing failures alone in a quasi-field experiment on navigation training (Ellis & Davidi, *Journal of Applied Psychology* 90(5), 2005), and the Army's after-action review ends with two lists, sustain and improve (TC 25-20, 1993). The entrypoint's LARGE-session sustain axis and the DO-CONFIRM card's sustain row are the firing points.

## What gets committed

A successful incident extraction usually produces, in one commit or a tight series:

- 1–3 new or sharpened lines in each owning skill's executable workflow (the coordinated owner set may produce small landings in multiple skills).
- Optionally, a new entry in the `recurring-anti-patterns-checklist.md` if the failure class has now appeared in 2+ skills/services.
- A provenance-to-target diff row (with the counterfactual fields above) recorded in the maintainer's working artifacts.
- A provenance note in the private alias map linking the sanitized rule to the incident's real id/date/team and the per-category audit patterns — never in the shared skill tree.
- Zero copies of the postmortem narrative in the skill files.

If the commit contains no executable rule (only narrative or only passive alerting where prevention is available), do not land it as an extraction; route to runtime config or to a runbook instead.
