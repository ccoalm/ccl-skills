# D1 — Model-Visible Accounting Invariant (design round)

Status: design-for-approval — this round produces the design and stops; it edits no `skills/**` file. Completion condition, fixed by the round-023 deferral: the named security owner (the repository maintainer) participates in the design and records approval. Until that approval is recorded, the round is `interim`; the landing round that edits the owner reference runs afterwards under the shared-skill non-wording gates (ledger `RED-baseline` row, dual-track review, adversarial challenge).

## Authorization and lineage

- Source: `specs/023-agent-native-repo-borrowing/plan.md` Batch V — D1 was moved out of Batch I after three same-class review P1s (r4 credential persistence, r5 mutable-reference false promise, r6 enumerable digest of low-entropy values plus an unnamed security owner), with the pre-registered disposition "no more in-place patching; a dedicated spec with a named security owner".
- The maintainer authorized opening this round on 2026-08-20, choosing D1 before E5, and is the named security owner; their recorded approval of the design is this round's completion condition, and prior rounds' authorization explicitly did not cover D1.
- E5 stays out of this round entirely: no privilege-escalation design, no maintainer disposition requested.

## Charter

| Field | Decision |
| --- | --- |
| Purpose | Give agent-session persistence an honest accounting invariant: everything that entered model context is *explainable afterwards* — reconstructable, reconstructable by immutable reference, or explicitly not — without the rule ever mandating that raw content (least of all credentials) be persisted. |
| Scope | In: the proposed clause text for `skills/llm-inference-integration/references/agent-session-persistence.md` (a §3 addition plus one Non-negotiables bullet), the security-owner decision points, the operability check, and the landing round's test design. Out: any `skills/**` edit (landing round), E5, entrypoint (`skills/llm-inference-integration/SKILL.md`) wording (deferred to the landing round's size-gate check), retention-policy or observability-sink changes (existing owners keep them). |
| Depth | Targeted design. Sources are this repository's own committed rule text and the round-023 record, all read first-hand this round; no new source class is mined. |
| Root cause of the three failed drafts | Each draft stated the invariant as a property of *content* ("persist / summarize / reference everything") and inherited a persistence obligation: r4 forced credentials into logs; r5 replaced raw content with references whose targets were mutable, so "reconstructable" promised replay content that resolution would no longer return; r6 replaced content with plain digests, which for enumerable value spaces are reversible by dictionary. The honest form states the invariant as a property of the *record*: classification must be complete and valid; content persistence is never forced. |
| Failure mode if designed weakly | Each weak form re-creates its numbered failure above: content-completeness → r4, missing immutability → r5, plain-digest residue → r6. One weak form is new: stated as an enumerated list of protected value classes, the rule repeats the round-029 lesson — an enumeration is permanently one unlisted class away from leaking a real value — so the digest rule below is unconditional, keyed by *what the record persists*, not by a sensitivity taxonomy. |
| Lifecycle impact | Design/review of agent-runtime persistence layers (the reference's consumers), and this repository's landing gates for the follow-up round. Product intent, UI, launch acceptance unaffected; no-source-access use unaffected — the clause is generic guidance with no repository-specific noun. |
| Evidence plan | Primary sources read first-hand this round: `skills/llm-inference-integration/references/agent-session-persistence.md` (whole file — §3 persistence policy, §4 config-lock keyed-digest discipline, Non-negotiables), `specs/023-agent-native-repo-borrowing/plan.md` (Batch V row, D1 intent row, r4/r5/r6 chain dispositions), `skills/product-rd-workflow/references/design-review-gate-mechanics.md`, `skills/product-rd-workflow/references/dispatch-owner-skills.md`. External sources not applicable — no industry-practice claim is made. |
| Completion standard | This design recorded; owner-dispatch map applied; mechanism-operability check recorded; security-owner decision points each carrying the owner's recorded verdict (approve / amend / reject). The strongest label this round can carry before that verdict is `interim`. Landing (separate slice, may follow in the same delivery once approval is recorded): clause lands in the reference, ledger row with `RED-baseline`, fixture pins, dual-track review + adversarial challenge, `make test` green. Merge authorization stays with the user throughout. |

## Owner-dispatch map (built before the design substance below was drafted)

| Concern | Owner | Status | Applied evidence |
| --- | --- | --- | --- |
| Agent session persistence design substance | `llm-inference-integration` | applied | Skill loaded in-session before drafting; the design reuses its existing keyed-digest discipline (config lock, §4 of the target reference: non-secret key-id + algorithm-id, retained keyring, `migration-required` on missing keys) instead of inventing a second digest scheme, and slots the invariant into §3, whose "persist what the model actually saw" rule it generalizes. |
| Security classification and gate structure | `feature-risk-router` | applied | Invoked this round: `security-review` tag (secret/credential handling and data-visibility semantics); the gate's pass condition is the named security owner's recorded approval; agent-side work is at most read-only triage (`security-first-pass-only`), never a passed audit. |
| Credential handling boundary | `llm-inference-integration` (`references/agent-credentials-auth.md`) | routed | The design keeps credentials out of model-visible content by reference-resolution at the boundary and cites that reference rather than restating it. |
| Log retention / access-policy and sink redaction | `platform-observability` | routed | The target reference already routes sink policy there; the design inherits the session log's retention/access policy and changes nothing in that routing. |
| Landing-round validation mechanics (ledger row, fixture pins, dual-track) | `skill-extraction-workflow` | named — fires at landing | No shared-skill file changes this round; the landing obligations are listed in the test design below. |
| Test-layer policy | `testing-strategy` | not-applicable this round | Design-only docs slice; the landing round adds assertions inside the existing deterministic fixture layer, no policy change. |
| Visible UI | `product-ui-ux-design` | not-applicable | `visible surface: no` — documentation rule, no rendered surface. |
| Delegation | `multi-agent-delegation` | local | Single-writer design document; no independent parallelizable slices. |

## Proposed design (the clause offered for approval)

Target: `skills/llm-inference-integration/references/agent-session-persistence.md`, as a new block at the end of §3 ("A persistence policy decides what is durable, ephemeral, or truncated") plus one Non-negotiables bullet. Draft text, in the reference's house style:

> **Model-visible ⟹ accounted-for.** The policy above decides what is durable; this invariant decides
> what must be *explainable afterwards*: every item that entered model context (user/assistant
> messages, tool outputs, injected context, resolved instruction surfaces) carries exactly one durable
> accounting classification —
>
> - **reconstructable (raw)** — the content itself is persisted in the log under the policy's
>   redaction rules;
> - **reconstructable (by reference)** — the log carries an immutable, versioned reference
>   (content-addressed id or pinned version) plus a digest, and the referenced store's retention and
>   access policy is at least as strict as the session log's. A mutable reference target does not
>   qualify: replay would resolve different or missing content, turning "reconstructable" into a
>   false promise — classify such an item non-reconstructable instead.
> - **non-reconstructable** — an explicit marker carrying the reason (policy forbids persistence, the
>   payload was ephemeral, the source lives behind stricter access control) plus either a keyed
>   digest or an explicit no-digest note.
>
> Three rules keep the invariant honest rather than dangerous:
>
> - **It audits records, never forces persistence.** Assertions over a session log check completeness
>   (no model-visible item without a classification) and validity (by-reference targets immutable and
>   policy-aligned) — never "everything model-visible is persisted raw". That inversion is how an
>   accounting rule becomes a credential-persistence bug.
> - **Credentials and secrets never reach this accounting as content**, because they are never
>   model-visible raw: resolve them by reference at the boundary (`agent-credentials-auth.md`). If a
>   secret does leak into model context, the accounting records a typed exposure event (class,
>   source, span) — never the value, and never a plain digest of it.
> - **A digest is itself a disclosure channel; key it unless the content sits beside it.** A plain
>   content hash of an enumerable value (short identifiers, phone numbers, PINs) is reversible by
>   dictionary. Plain digests are allowed only where the same record already persists the content raw
>   (pure integrity use). Where the digest is the only residue — the by-reference and
>   non-reconstructable classes — use a keyed digest with a non-secret key-id and algorithm-id,
>   verified against a retained keyring, with rotation handled as `migration-required`: the same
>   discipline the §4 config lock already specifies for sensitive-but-behavior-affecting fields.

Proposed Non-negotiables bullet:

> - Every model-visible item is accounted for as reconstructable-raw, reconstructable by immutable
>   reference (digest + policy-aligned store), or explicitly non-reconstructable with reason;
>   accounting assertions check completeness and classification, never force raw persistence; secrets
>   stay reference-resolved and appear only as typed exposure events; a digest that is the only
>   residue of an item is keyed, never plain.

Design decisions and rejected alternatives:

- **Record-property, not content-property.** The invariant quantifies over classifications, not payloads. Rejected: any form of "persist everything model-visible" (r4's failure).
- **Immutability as the reconstructability criterion.** A reference qualifies only if resolution is pinned (content-addressed or versioned) and the store's policy is at least as strict. Rejected: "access-controlled reference" without immutability (r5's failure — the target drifts and replay lies).
- **Unconditional digest rule keyed by record shape, not by a sensitivity taxonomy.** The trigger is objective — is the raw content beside the digest or not — so no enumerated list of protected value classes exists to fall out of date (round-029 lesson: an enumeration is permanently one unlisted class away from letting a real value out). Rejected: "keyed digests for low-entropy/sensitive classes" with a class list.
- **Reuse of the §4 keyed-digest discipline.** Key-id, algorithm-id, retained keyring, and `migration-required` rotation semantics are cited, not restated — one digest discipline per reference, two consumers.
- **Typed exposure event for the defect path.** When a secret does become model-visible, the honest record is an event about the exposure, not any transform of the value. Rejected: recording a keyed digest of the leaked secret "for correlation" — it invites offline verification against candidate values and adds nothing the event's class/source/span does not.

## Security-owner decision points

Each row needs the security owner's recorded verdict; defaults are the design above.

| # | Decision | Default offered | Owner verdict |
| --- | --- | --- | --- |
| D-1 | Classification taxonomy: exactly three classes (raw / by-immutable-reference / non-reconstructable), no fourth "partially reconstructable" class. | Three classes; partial forms classify as non-reconstructable with reason. | pending |
| D-2 | Digest discipline: plain digest only beside raw content; keyed digest (key-id + algorithm-id + retained keyring) wherever the digest is the only residue; no sensitivity class list. | As stated. | pending |
| D-3 | Secrets: never model-visible raw (reference-resolution boundary); defect path records a typed exposure event, never the value or any digest of it. | As stated. | pending |
| D-4 | Assertions audit completeness/validity only; no assertion may require raw persistence. | As stated. | pending |
| D-5 | Landing surface: reference §3 block + one Non-negotiables bullet; entrypoint (`skills/llm-inference-integration/SKILL.md`) untouched unless the landing round's size gate shows the theme word fits without growth. | Reference-only landing. | pending |

## Mechanism-operability check (recorded)

The design proposes no new enforcement machinery in this repository: the clause is prose guidance for products building agent runtimes; the "assertions" it describes are the *consumers'* runtime/test checks, specified by the rule, not a gate here. The landing round extends the existing deterministic fixture with pins for the new clause — the same pin family every non-wording shared-skill landing carries — so: author dogfood = the standard fixture run; marginal cost = one more pinned-anchor set on an already-pinned file; trust-model fit = unchanged (pins defend against accidental drift; deliberate weakening is caught by dual-track review of a visible diff, the same protection every normative rule here has). No leg fails; no lightening needed. The claim-liveness firing point does not apply — this round withdraws no claim.

## Test design (for the landing round)

| Layer | Decision | Command or evidence | Reason |
| --- | --- | --- | --- |
| unit | not applicable | — | Prose rule; no unit-testable code in this repository changes. |
| integration/contract | run at landing | `make test` | Deterministic gate suite must stay green with the reference edited. |
| deterministic fixture pins | add at landing | extend the existing gate fixture with one anchor per obligation the clause imposes (classification completeness wording, the never-forces-persistence rule, the secrets exposure-event rule, the keyed-digest residue rule), each RED under its own applied mutation per the ledger contract | The clause is non-wording for its owner package; the ledger row requires `RED-baseline` behavioral evidence. Anchors follow the one-per-obligation discipline (a sentence-level anchor survives sub-obligation deletion). |
| independent review | run at landing | dual-track review + adversarial challenge on the landing diff, reviewer identity + finding disposition recorded | `security-review` + shared-skill non-wording change. |
| security review | this round + landing | this design's owner verdicts recorded per decision point; landing diff re-checked against them | The named owner's approval is the gate; agent-side work stays `security-first-pass-only`. |
| manual/exploratory | not applicable | — | No runtime surface in this repository. |

## Implementer self-review (persisted before any independent review of this design)

| Field | Result |
| --- | --- |
| Acceptance criteria rechecked | Charter completion standard walked: design recorded (this file), owner-dispatch map applied before drafting, operability check recorded, decision points enumerated with defaults. Outstanding: every `Owner verdict` cell is `pending` — the round's completion condition by construction. |
| Changed files matched to the active artifact | Exactly one path: this plan. No `skills/**`, ledger, fixture, or Makefile change; target-output for the landing round is listed above, not staged. |
| Edge/failure paths considered | The three historical failure modes (r4/r5/r6) each map to a named design rule; the enumeration failure mode (029) maps to the unconditional digest trigger; the defect path (secret actually leaked) has an explicit non-digest disposition. |
| Regression test | Not applicable this round (no behavior changes); the landing round's RED-baseline plan is specified in the test design. |
| Deterministic gates run | `make test` on this candidate — result recorded in the verification section. |
| Known residual risks | (a) The clause is prose: nothing here mechanically audits a consumer's session log — the assertions are the consumer's to build; the fixture only pins that the rule stays present and intact. (b) A keyed digest still permits offline correlation by a party holding the keyring; the design accepts this for the residue classes and forbids it entirely for leaked secrets (typed event, no digest). (c) The reference grows by one block; if its owner package ever gains a size budget, the landing round pays it there. |

## Verification record

| Check | Result |
| --- | --- |
| `make test` (full deterministic suite) | Implementer-run: exit 0, no `FAIL`/`ERROR` line, on the candidate tree whose only later edit is this row's own text (a result row inside the tip it describes cannot cite a run of that exact tip). The authoritative execution is the protected CI run on the pushed branch, recorded in the merge request. |
| Security-owner approval | pending — the round's completion condition. |
