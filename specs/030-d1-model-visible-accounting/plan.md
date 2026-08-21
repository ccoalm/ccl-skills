# D1 — Model-Visible Accounting Invariant (design round)

Status: design approved — the named security owner (the repository maintainer) approved all five decision points by default on 2026-08-20, in-session, after being offered per-point amendment; the verdicts are recorded in the decision table below. The landing slice now runs on this same branch under the shared-skill non-wording gates (ledger `RED-baseline` row, deterministic pins, dual-track review, adversarial challenge bound to the landing diff). Merge authorization stays with the maintainer.

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

> **Amended by review rounds 1–7** (dispositions below); the blockquote above stands as the draft the security owner originally approved, and the landed text in the reference is authoritative. The semantic deltas against the approved draft are: (A1) the by-reference criterion is availability + authorization — resolvable for the log's whole retention horizon, access no broader than the log's policy, the authorized replay principal keeps access — not "policy at least as strict"; (A2) a leaked secret classifies non-reconstructable with an explicit no-digest note, raw and by-reference prohibited, the typed exposure event as that marker's metadata; (A3) raw means byte-equivalent content in the session log itself — a redacted item never classifies raw, and an out-of-line payload classifies by reference; (A4) a content-derived reference identifier counts as a digest — a by-reference record uses an opaque pinned id or version or a keyed derivation, never a plain content hash, and its digest is mandatory. Because the original approval bound the original wording, the amended wording's security approval is recorded in its own row of the decision table below and the verification record stays `pending` until that row is filled by the owner, never by the agent.

Design decisions and rejected alternatives:

- **Record-property, not content-property.** The invariant quantifies over classifications, not payloads. Rejected: any form of "persist everything model-visible" (r4's failure).
- **Availability + authorization as the reconstructability criterion.** A reference qualifies only if resolution is pinned (content-addressed or versioned), the item stays resolvable for the session log's whole retention horizon, access is no broader than the log's policy, and the authorized replay principal keeps access — the round-1 amendment; the original "policy at least as strict" proxy accepted stores that purge earlier than the log or deny the replay principal. Rejected: "access-controlled reference" without immutability (r5's failure — the target drifts and replay lies).
- **Unconditional digest rule keyed by record shape, not by a sensitivity taxonomy.** The trigger is objective — is the raw content beside the digest or not — so no enumerated list of protected value classes exists to fall out of date (round-029 lesson: an enumeration is permanently one unlisted class away from letting a real value out). Rejected: "keyed digests for low-entropy/sensitive classes" with a class list.
- **Reuse of the §4 keyed-digest discipline.** Key-id, algorithm-id, retained keyring, and `migration-required` rotation semantics are cited, not restated — one digest discipline per reference, two consumers.
- **Typed exposure event for the defect path.** When a secret does become model-visible, the honest record is an event about the exposure, not any transform of the value. Rejected: recording a keyed digest of the leaked secret "for correlation" — it invites offline verification against candidate values and adds nothing the event's class/source/span does not.

## Security-owner decision points

Each row needs the security owner's recorded verdict; defaults are the design above.

| # | Decision | Default offered | Owner verdict |
| --- | --- | --- | --- |
| D-1 | Classification taxonomy: exactly three classes (raw / by-immutable-reference / non-reconstructable), no fourth "partially reconstructable" class. | Three classes; partial forms classify as non-reconstructable with reason. | approved as offered — maintainer, 2026-08-20, in-session |
| D-2 | Digest discipline: plain digest only beside raw content; keyed digest (key-id + algorithm-id + retained keyring) wherever the digest is the only residue; no sensitivity class list. | As stated. | approved as offered — maintainer, 2026-08-20, in-session |
| D-3 | Secrets: never model-visible raw (reference-resolution boundary); defect path records a typed exposure event, never the value or any digest of it. | As stated. | approved as offered — maintainer, 2026-08-20, in-session |
| D-4 | Assertions audit completeness/validity only; no assertion may require raw persistence. | As stated. | approved as offered — maintainer, 2026-08-20, in-session |
| D-5 | Landing surface: reference §3 block + one Non-negotiables bullet; entrypoint (`skills/llm-inference-integration/SKILL.md`) untouched unless the landing round's size gate shows the theme word fits without growth. | Reference-only landing. | approved as offered — maintainer, 2026-08-20, in-session |
| D-6 | Re-approval of the final landed wording after review-round amendments A1–A4 (listed under the proposed-design blockquote). | The amended wording as landed at the final candidate. | approved — maintainer, 2026-08-21, in-session, all four amendments |

## Review round 4 (codex, chain r4), one P1, accepted — and the autonomous budget checkpoint

Packet `9228cf7c…`, `codex`, same profile.

- **P1, accepted — round 3's own fix re-opened the availability hole through raw's out-of-line parenthetical.** "Full payload exists content-addressed out-of-line" satisfied the raw class while the out-of-line store could purge before the log expires or deny the replay principal — the raw class required neither criterion. Fixed by removing the overlap between classes: raw now means byte-equivalent content living **in the session log itself**; an out-of-line payload classifies **by reference, never raw**, which puts it under the availability and authorization criteria that class already carries. Pinned; the applied deletion mutation reds the new pin. The full twenty-one-mutation set was re-applied to this candidate, control green before and after.
- Worth naming across rounds 1–4: every finding has been an instance of one shape — **a qualifying clause that lets an item satisfy the letter of a class while the promise the class makes is false** (strictness proxy, unclassified leak, redacted "raw", out-of-line "raw"). Each fix removed the qualifying path rather than adding an exception, which is the same convergence-by-deletion this repository's dual-track gate prefers.

**Autonomous budget checkpoint.** Four external rounds are consumed, all in review mode — each remediation produced a new candidate, and the review-chain state machine correctly demands a fresh chain (whose first round is a review) per candidate. The mandatory adversarial challenge has therefore not yet run against any candidate, and running it against the final candidate needs at least one more chain (review, then challenge). Per this repository's budget rule the round stops here as an `interim` checkpoint: whether to authorize further external rounds is the maintainer's decision, and the recommendation is to authorize a fresh review plus a full-scope challenge on the exact landing candidate rather than waive either lane.

## Review round 5 (codex, chain r5, user-authorized), one P2, accepted

The maintainer authorized continued external rounds to convergence at the budget checkpoint above. Packet `af7ec623…`, `codex`. No P1. The P2: the no-broader-access clause was the one criterion of the by-reference class left unpinned — droppable while the horizon and principal pins stayed green. Pinned; the applied weakening mutation reds the new pin while both sibling pins stay green, and the complete twenty-two-mutation set was re-run against the final fixture, control green before and after.

## Review round 6 (codex, chain r6, user-authorized), one P1, accepted

Packet `b0697382…`, `codex`. **A content-addressed id is itself a plain content hash**: a low-entropy value stored out-of-line under a conventional CAS id was enumerable from the log — the rule keyed the companion digest and overlooked the identifier, so both digest pins stayed green while the disclosure channel sat in the reference id. Fixed on the same unconditional axis as the digest rule: a content-derived reference identifier **is** a digest under this rule; a by-reference record identifies its target by an opaque pinned id or version, or a keyed derivation — never a plain content hash of the referenced content — and the class bullet's identifier parenthetical now routes to that rule instead of naming content-addressing as acceptable. Both teeth pinned; the full twenty-four-mutation set re-run against this candidate, control green before and after.

## Review round 7 (codex, chain r7, user-authorized), one P2, accepted

Packet `3deb47bc…`, `codex`. No P1. The P2: "plus a digest" — the by-reference class's mandatory-integrity wording — was droppable while every pin stayed green (the reference pin does not require a digest; the keyed-residue pins constrain a digest only when one exists). Pinned; the applied deletion mutation reds the new pin with the control green before and after.

## Review round 8 (codex, chain r8, user-authorized), one P1, accepted

Packet `c830dabd…`, `codex`. No reference or fixture finding. The P1 is a governance defect in this record: the release status declared all five decisions approved while the approved blockquote's semantics had been replaced across rounds 1–7, and the only bridge was an agent-authored "the maintainer re-checks at merge" — a self-authored approval assertion, exactly what the D1 lineage forbids. Fixed by separating the claims: the original approval stands for the original wording; the amended wording's approval is its own decision point (D-6, deltas A1–A4 enumerated), `pending` until the owner fills it; the verification row now says so.

## Review round 9 (codex, chain r9, user-authorized), one P1 accepted, one P2 split

Packet `77990f03…`, `codex`.

- **P1, accepted — the completeness claim was only as real as whatever reached the log.** A crash between model dispatch and the append leaves items no log-only audit can see, and a retry can double-classify. Fixed at the rule's altitude with §2's own discipline extended to accounting: stable per-item ids assigned at context assembly, the item manifest (ids plus classifications) durably committed **before model dispatch**, failing closed if that commit fails, retries reusing the ids so replays deduplicate. Three teeth, three pins, three applied mutations.
- **P2, split — accepted: the applied-mutation transcript is now persisted** in the ignored review-evidence store (`.work/review-evidence/`, outside the candidate, the same placement round 027 used), so a reviewer can inspect the actual RED outputs rather than prose claims. **Declined: embedding candidate-hash-bound command outputs inside the candidate itself** — round 029's finding of the same shape already ruled on it: a candidate that certifies itself is the same failure one indirection deeper; the authoritative fixture and full-suite execution is the protected CI run on the pushed branch, and the mutation evidence stays implementer-run-plus-reviewable, stated as such. The full twenty-eight-mutation set was re-applied to this candidate, control green before and after, transcript persisted.

## Review round 10 (codex, chain r10, user-authorized), one P1, accepted

Packet `0b207516…`, `codex`. The round-9 fix one level deeper: a manifest of ids plus classifications commits durably, dispatch begins, the process crashes before the raw payload appends — recovery finds exactly one valid-looking classification whose content never landed, and the completeness audit passes. Fixed: the pre-dispatch durable commit carries each item's **complete accounting record** — the id, the classification, and that classification's **evidence** (the raw content itself, the validated pinned reference plus digest, or the full non-reconstructable marker) — so nothing about an item remains to append after dispatch that an audit would need. Both new teeth pinned; the full twenty-nine-mutation set re-applied, control green before and after, transcript refreshed in the evidence store.

## Review round 11 (codex, chain r11, user-authorized), one P1, accepted

Packet `e2dc25d9…`, `codex`. The completeness family's last level: with no authoritative denominator, an under-enumeration defect commits records for a subset of the dispatched items and the audit verifies the log against that same subset — a dropped item, injected instructions included, is invisible. Fixed at the family's fixed point: one atomic, invocation-scoped manifest is derived **from the finalized dispatch payload itself** (ordered item ids and boundaries) and committed with the records, so the audit's denominator is the invocation's own manifest, never whatever subset happened to land. This closes the recursion by construction — the denominator now comes from the object the model actually consumed, which the raw class already binds by byte-equivalence. Both teeth pinned; the full thirty-one-mutation set re-applied, control green before and after, transcript refreshed.

## Review round 12 (codex, chain r12, user-authorized), one P1, accepted

Packet `d8fad0c2…`, `codex`. The check-then-act window: manifest and records derive from a mutable payload, middleware mutates or appends an item after the commit and before transport, the model sees the changed payload while the audit passes against the unchanged manifest. Fixed with the same closure the reference's §4 config lock already uses for exactly this window: freeze the dispatch payload into an immutable sealed envelope, derive the manifest and records from that envelope, and let transport and retries send only it. Both teeth pinned; the full thirty-three-mutation set re-applied, control green before and after, transcript refreshed.

## Review round 13 (codex, chain r13, user-authorized), two P1s, both accepted

Packet `a662a96c…`, `codex`.

- **P1 (a), accepted — the accounting could not distinguish one invocation from two.** After a transport failure or a lost acknowledgement the log looked like a consumed invocation, and an id-reusing retry could invoke the model again while deduplicated item accounting reported one. Fixed: durable attempt states around the sealed envelope (prepared, dispatch-attempted, then accepted or delivery-uncertain) plus the provider request/idempotency key — a possible double invocation shows as two attempts even while item accounting deduplicates. This is the write-finality rule (verify the postcondition, never the call's ok) applied to the accounting's own claims.
- **P1 (b), accepted — fail-closed auditing would brick every pre-accounting session, and back-filling records would fabricate evidence.** Fixed with §4's own no-lock precedent: the accounting schema is versioned and applies prospectively; an invocation recorded before the accounting existed carries a typed legacy marker in the non-reconstructable family with pre-accounting as the reason — never synthesized classifications.
- Four new teeth pinned; the full thirty-seven-mutation set re-applied, control green before and after, transcript refreshed.

## Review round 14 (codex, chain r14, user-authorized), one P1, accepted

Packet `e00c9e52…`, `codex`. A provider that injects, truncates, or compacts server-side makes the model's effective context differ from the sealed envelope while every local record passes — the accounting was implying fidelity it cannot observe. Fixed by scoping the guarantee honestly: it claims the client-dispatched sealed envelope; where authoritative provider evidence of the effective context exists it is recorded, and where it does not the invocation carries a typed model-context-unverifiable marker. Both teeth pinned; full mutation set re-applied (one mutation's first regex was a no-op, corrected and re-applied to RED — recorded in the transcript rather than discarded), control green before and after.

## Review round 15 (codex, chain r15, user-authorized), one P1, accepted

Packet `35c8e27c…`, `codex`. The attempt-state discipline had the same append-after-act ordering hole the item records had already closed: appending `dispatch-attempted` after calling the provider loses the attempt when the process crashes between send and append, so recovery retries and the log shows one call where the provider may have processed two. Fixed by giving the attempt record the same flush-before-finality order as everything else in this discipline: each attempt record (unique attempt id plus the provider request/idempotency key) commits durably before transport is invoked, failing closed, with the state updated afterward. Pinned; the full forty-mutation set re-applied, control green before and after, transcript refreshed.

## Review round 16 (codex, chain r16, user-authorized), one P1 and one P2, both accepted

Packet `5bd468fe…`, `codex`. The round-15 fix left the same window one refinement deeper: "commit each attempt record before transport" was satisfiable by committing `prepared` pre-transport and recording `dispatch-attempted` after the send — the crash between send and update again makes a retry look like the first call. Fixed by naming the state: the durable **`dispatch-attempted`** state itself (unique attempt id plus the provider idempotency key) commits before transport is invoked, and after transport the state moves only to `accepted` or `delivery-uncertain`. The P2 asked for exactly the mutation that distinguishes the weak form — committing `prepared` before and `dispatch-attempted` after — which is now an applied RED case, alongside the post-transport-only deletion. Full forty-one-mutation set re-applied, control green before and after, transcript refreshed.

## Review round 17 (codex, chain r17, user-authorized), one P1 accepted, one P1 re-declined with re-verification

Packet `39ec804f…`, `codex`.

- **P1 (a), accepted — recovery could not read a stale `dispatch-attempted` record.** A crash just after the pre-transport commit and a crash after provider acceptance leave the same record, so recovery could either drop a delivered invocation (treating it as done) or blind-retry into a double one. Fixed: recovery resolves stale `dispatch-attempted` to `delivery-uncertain`, reconciles by provider request id where the provider supports it, and auto-retries only under provider-guaranteed idempotency — otherwise the uncertainty is surfaced, never retried through. Both teeth pinned; full forty-three-mutation set re-applied, control green before and after, transcript refreshed.
- **P1 (b), re-declined after candidate-relative re-verification — the same class as round 9's P2** (controller-verifiable evidence inside the bounded packet). Nothing has changed that would alter the round-9 disposition: embedding implementer-generated outputs in the candidate is self-attestation one indirection deeper (round 029's precedent); the authoritative fixture and full-suite execution is the protected CI run on the pushed branch; the mutation transcript and every per-round review result JSON live in the ignored evidence store outside the candidate; the security owner's approvals are session-recorded decisions restated in the merge request, which also carries packet hashes and per-round dispositions. The review row stays honestly `pending` until the final convergence record exists — that is the gate working, not a gap in it.

## Review round 18 (codex, chain r18, user-authorized), one P1, accepted

Packet `1832d372…`, `codex`. A consistency defect between the round-14 honest scoping and the rule's own headline: the invariant and the Non-negotiables bullet still promised "every model-visible item" while a provider-injected item — outside the sealed client-dispatched envelope — can never be assigned an id or classification, so the headline promised what the scoping had already disclaimed. Fixed by scoping the invariant, the completeness parenthetical, and the Non-negotiables bullet explicitly to the client-dispatched envelope, with the provider-effective context named as the separate conditional surface. The ledger row's firing-path anchor and prose were updated in the same re-press (this round's own unpushed row — corrected by re-pressing the commit, never by editing a landed row). Full mutation set re-applied under the reworded anchors, control green before and after.

## Review round 19 (codex, chain r19, user-authorized), one P1, accepted

Packet `e9d8fd0f…`, `codex`. The sharpest behavioral finding since round 1: a secret **detected** in the sealed envelope during pre-dispatch accounting was classified, marked, evented — and then sent anyway, because the discipline only failed closed on a commit failure. Accounting a known exposure must never license shipping it. Fixed: detection before dispatch aborts the transport and records a rejected-exposure event; the leaked-secret non-reconstructable classification is reserved for a secret discovered only after it reached model context. Both teeth pinned; the full mutation set (forty-five applied mutations) re-run against this candidate, control green before and after, transcript refreshed.

## Review round 20 and the adversarial challenge (codex, chain r20, user-authorized)

Review packet `41e41dd0…`: the only finding was the **third** occurrence of the packet-self-attestation class (provide exact-candidate CI evidence inside the packet), already dispositioned in rounds 9 and 17 — the demanded evidence is the protected CI run on the pushed branch, which by construction cannot exist inside the tip it certifies; no reference, fixture, or ledger finding remained, which is the review lane's fixed point on substance.

**Challenge lane** (same chain, `codex`, full-scope with the nineteen prior fixes named as already-covered ground): one P1, accepted — **the late-discovery path relabeled a persisted secret without touching the persisted bytes.** An unrecognized secret classified raw has its value durably in the append-only log; discovering it later and reclassifying non-reconstructable left the value readable. Fixed: late discovery is a transition, not a label — supersede the classification in place, contain read access to the affected records at once, purge or cryptographically erase the persisted value and its replicas where the store supports it (a supersession event plus erasure, never a silent rewrite of the log), and record any unerasable residue as part of the exposure event. Four teeth, four pins, four applied mutations; the full forty-nine-mutation set re-run, control green before and after. One attribution repair is recorded rather than discarded: the availability-horizon mutation had begun redding on the earlier mandatory-digest pin after that pin's line grew to share text with it, and was narrowed to touch only the horizon fragment, restoring differential attribution.

## Review round 21 (codex, chain r21, user-authorized), two P1s accepted, P2 split

Packet `0b7b4ae3…`, `codex`.

- **P1 (a), accepted — a retry could mint a fresh idempotency key**, which a provider treats as a distinct request: the model runs twice while the accounting shows a retry. Fixed: one provider idempotency key binds to the sealed logical invocation; an automatic retry reuses that original key and the identical sealed envelope — a fresh-key retry counts as a second invocation, never a retry.
- **P1 (b), accepted — evidence could commit before the pre-transport secret scan rejected the envelope**, leaving the raw value in the log while the erasure transition was scoped to post-model discovery. Fixed: the scan runs before accounting evidence is derived or committed, and where any persistence preceded detection, the late-discovery erasure transition applies to the aborted dispatch as well.
- **P2, split**: pins for both fixes added (the pin-refresh itself exposed and repaired a pin gap — the uncertainty-surfaced clause had lost its owner in the pin rewrite; its NOT-RED probe, the pin repair, and the re-applied RED are all recorded in the transcript rather than discarded); the controller-verifiable-output half is the same self-attestation class dispositioned in rounds 9, 17, and 20 — unchanged.

## Review round 22 (codex, chain r22, user-authorized), one P1 accepted, P2 re-declined

Packet `9dd284ce…`, `codex`. The P1 is a self-consistency defect between two of this round's own fixes: raw's "byte-equivalent to what the model saw" contradicted the provider-effective scoping, which admits consumption is unverifiable — after a provider-side transform, the log would keep claiming raw fidelity to something nobody can check. Fixed: raw binds to **the item in the sealed client-dispatched envelope** — the only bytes the client can guarantee — with the provider-effective surface handling everything after dispatch. Pin updated and mutation-tested. The P2 is the fourth repetition of the packet-self-attestation class; disposition unchanged (rounds 9, 17, 20, 21).

## Review round 23 and the second adversarial challenge (codex, chain r23, user-authorized)

Review packet `8b65ed04…`: the only finding was the fifth repetition of the process-evidence class (pending exact-candidate review row + packet self-attestation); the substantive surfaces drew no finding for the second consecutive candidate. **Challenge lane** (same chain, full-scope): one P1, accepted — a record committed but never `dispatch-attempted` had no recovery path, so an invocation could stay `prepared` indefinitely, surfacing no failure and stranding committed evidence with no invocation to explain it. Fixed with an explicit cancel-or-resume: cancel into a typed terminal state (committed evidence following the normal retention or erasure policy), or resume by committing `dispatch-attempted` and sending the identical sealed envelope under the original key. Both teeth pinned and mutation-tested, control green before and after, transcript refreshed.

## Review round 24 (codex, chain r24, user-authorized), one P1, accepted

Packet `6e119e65…`, `codex`. The scan-before-evidence rule never required the scan itself to succeed, so a scanner timeout, error, or absence read as "no detection" and the envelope shipped unscanned. Fixed: the scan fails closed itself — error, timeout, or absence never reads as no detection; the dispatch waits or aborts. Pinned and mutation-tested, control green before and after.

## Review round 25 (codex, chain r25, user-authorized), one P1 accepted, P2 folded into it, one P1 re-declined

Packet `a5b4eda1…`, `codex`. The accepted P1: the late-discovery erasure named the value and its replicas but not the **plain integrity digest legitimately stored beside a raw record** — once the value is erased, that digest is exactly the enumerable low-entropy residue the digest rule exists to prevent. Fixed: the erasure list covers the value, its replicas, and any plain digest stored beside it, with the rationale stated inline (the digest was permissible only while the content sat next to it). The P2 was the pin for this fix — added and mutation-tested. The remaining P1 is the sixth repetition of the packet-self-attestation class; disposition unchanged.

## Review round 26 (codex, chain r26, user-authorized), one P1, accepted

Packet `9f19cd44…`, `codex`. The closed post-transport enumeration (accepted / delivery-uncertain) had no place for a definitive provider rejection before model execution — an invalid request or authentication failure was forced into `delivery-uncertain`, manufacturing uncertainty where the provider attests there was none and polluting retry semantics. Fixed: `rejected` joins the closed enumeration as a provider-attested terminal state that records no invocation occurred. Both pins refreshed and mutation-tested, control green before and after.

## Review round 27 (codex, chain r27, user-authorized), one P1, accepted

Packet `74d9a84c…`, `codex`. Pin-coverage: weakening "exactly one" to "one or more" kept the invariant's lead pin green, permitting overlapping classifications. The uniqueness quantifier now carries its own pin, mutation-tested (weakening reds it, control green).

## Post-round-27 implementer self-audit (maintainer-directed), two holes found and fixed

At the maintainer's correction — twenty-seven external rounds is a process failure, not diligence — the external loop stopped and the implementer walked the full dispatch lifecycle (states × failure points × orderings × residues × cross-references) in one enumeration instead of letting the reviewer surface one hole per round. The walk found two remaining holes, both fixed in one batch:

- **H1 — `rejected` had no resend semantics.** A corrected resend is a **new sealed invocation with its own envelope and key**: an idempotency key may only ever cover one identical payload, so reusing the rejected invocation's key under a fixed payload would break the provider's dedup contract.
- **H2 — the rejected-exposure event had no content constraint.** It now carries the same discipline as every exposure record: never the value, never a plain digest.

Both pinned and mutation-tested, plus re-applied mutations proving the neighboring abort and never-licenses pins still own their clauses; control green before and after. **Process defect recorded for extraction** (pending its own round, not self-authorized here): remediation text added during review rounds re-owes the draft-time pre-cover axes — concurrency & lifecycle above all — before going back to the reviewer; the same-class recurrence signal at round three should have triggered this full-lifecycle self-enumeration instead of twenty more single-finding patches.

## Final dual-track pair (codex, chain r28) and the stop decision

Review packet `0e06cac8…`: the only finding is the seventh repetition of the packet-self-attestation class — no substantive finding, the review lane's fixed point. **Challenge lane** (same chain, full-scope): one P1, accepted — the late-discovery transition covered only content persisted **raw**; a secret inside a **by-reference** item's target had no containment, erasure, or residue path (the implementer's lifecycle self-audit had walked the dispatch axis but not the class × late-discovery matrix — one axis short, recorded as such). Fixed by generalizing the transition to every class that persisted content: raw in the log or reachable through a by-reference target, with containment reaching the referenced target and erasure covering the content, replicas, and any digest or content-derived identifier stored for it. Three pins refreshed plus one new, all mutation-tested, control green before and after.

**Stop decision, per the maintainer's correction and the repository's budget rule**: this fix produced a new candidate, and the round does NOT self-authorize another external chain. The review lane has been substantively clean for three consecutive candidates; the challenge lane's last finding is fixed and pinned but has not itself been re-challenged. The honest review state at handoff: dual-track **converged on the review axis; the final challenge's own fix awaits one fresh challenge pass**, which is the maintainer's call to authorize — or to accept as residual risk with this record as the disposition trail.

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

## Landing record (the slice that edits `skills/**`, run after the recorded approval)

Target-output map for the landing:

| Target | Direction | Status | File or reason |
| --- | --- | --- | --- |
| Accounting invariant rule | owner implementation | updated | `skills/llm-inference-integration/references/agent-session-persistence.md` — the approved §3 block (two bullets: the classification invariant with its three classes, and the audits-never-forces bullet carrying the secrets and digest rules) plus one Non-negotiables bullet. |
| Entrypoint | routing surface | unchanged | `skills/llm-inference-integration/SKILL.md` untouched, per approved decision point D-5. |
| Deterministic pins | validation carrier | updated | `skills/skill-extraction-workflow/scripts/test_ai_coding_implementation_gates.sh` — pin family 7, one section-bound assertion per obligation, same stated limits as the claim-liveness family. |
| Append-only ledger | provenance | updated | `skills/skill-extraction-workflow/references/source-register.md` — two rows (rule owner, fixture owner), each with `RED-baseline`, `observed-failure: yes`, and a firing path. |
| Credential boundary, observability sinks | routed | unchanged | Owned by `agent-credentials-auth.md` and `platform-observability` routing already present in the reference; cited, not restated. |

RED-baseline record — every mutation was **applied** (never reasoned about) in a throwaway copy of `skills/` outside the repository; the copy's unmutated run is green before and after, which also proves the harness read the copy. Each mutant reds on its **owning** assertion; the fixture exits at first failure, so every assertion ordered before the owning one passed under the mutant:

| Mutation applied | Owning assertion | Observed result |
| --- | --- | --- |
| Reword the invariant's first line (`entered model context must carry exactly one` → `XX`) | invariant: exactly one classification | RED: text missing from the persistence-policy section |
| Delete the mutable-target sentence | obligation: immutable reference targets only | RED |
| Reword `it must never force raw persistence` to `it encourages good record keeping` | obligation: audits records, never forces persistence | RED |
| Reword the typed-exposure-event clause | obligation: leaked secret becomes a typed exposure event | RED |
| Delete `never the value, and never a plain digest of it` | obligation: no value and no plain digest of a leaked secret | RED |
| Weaken the keyed-digest clause to `hash` | obligation: residue digests are keyed | RED |
| Delete the plain-digest-only-beside-raw clause | obligation: plain digest only beside raw content | RED |
| Drop the keyed clause from the Non-negotiables bullet | non-negotiable bullet present | RED |
| Relocate the Non-negotiables bullet into the Routing section prefixed "For background only" | non-negotiable bullet present (section-bound) | RED — a whole-file grep would have stayed green |
| Revert the availability criterion to the old "at least as strict" policy proxy | obligation: by-reference availability spans the retention horizon | RED (added after review round 1) |
| Delete the purges-earlier / denies-the-replay-principal sentence | obligation: the replay principal keeps access | RED (added after review round 1) |
| Drop the leaked secret's class assignment, keeping the exposure-event sentence | obligation: a leaked secret classifies non-reconstructable, no digest | RED, while the exposure-event pin stays green — the differential the round-1 P2 asked for (added after review round 1) |

| Delete the retained-keyring / rotation clause, keeping the keyed-digest sentence | obligation: keyring is retained across rotation | RED while the keyed-digest pin stays green (added after review round 2) |
| Reword raw's byte-equivalence lead; delete the redacted-not-raw clause; weaken the by-reference lead; drop the non-reconstructable reason; drop the keyed-or-no-digest option; drop the completeness parenthetical; reword the secrets boundary | one owning pin each (seven pins added after review round 3's full-enumeration sweep) | RED, one owning assertion per mutation, control green before and after |
| Delete the out-of-line-classifies-by-reference sentence | class: out-of-line payloads classify by reference, never raw | RED (added after review round 4) |
| Weaken "with access no broader than the log's policy" to "with access controls" | obligation: reference-store access is no broader than the log policy | RED while the horizon and principal pins stay green (added after review round 5) |
| Delete the identifier-is-a-digest sentence; separately, weaken the plain-hash prohibition | obligation: reference identifiers fall under the digest rule / no plain content hash as the log-visible identifier | RED, one owning pin each (added after review round 6) |
| Drop "plus a digest" from the by-reference class | class: a by-reference record carries a mandatory digest | RED (added after review round 7) |
| Reword the accounting-record commit phrase; delete the evidence enumeration; delete the fail-closed clause; delete the retry-dedupe clause; reword the manifest's dispatch-payload source; delete the audit-denominator clause; reword the sealed-envelope derivation; delete the transport-only-sealed clause | one owning pin each (pins added after review rounds 9–12) | RED, one owning assertion per mutation |
| Delete the attempt-state enumeration; delete the two-attempts visibility clause; reword the prospective-schema sentence; delete the never-synthesized clause | one owning pin each (four pins added after review round 13) | RED, one owning assertion per mutation |
| Reword the client-dispatched scope clause; delete the unverifiable-marker clause | one owning pin each (two pins added after review round 14) | RED, one owning assertion per mutation (the second's first regex was a NO-OP and was corrected and re-applied — recorded in the transcript, not discarded) |
| Weaken to prepared-before-transport with dispatch-attempted recorded afterward; separately delete the post-transport-states-only clause | obligation: dispatch-attempted itself commits before transport / post-transport states are accepted or delivery-uncertain only | RED, one owning pin each (pins refined after review rounds 15 and 16) |
| Reword the stale-attempt recovery rule; separately delete the idempotency-gated auto-retry clause | obligation: recovery resolves stale attempts to delivery-uncertain / auto-retry only under provider-guaranteed idempotency | RED, one owning pin each (pins added after review round 17) |
| Delete the abort-on-detection sentence; separately weaken the never-licenses clause | obligation: a detected secret aborts the dispatch / accounting never licenses sending a known exposure | RED, one owning pin each (pins added after review round 19) |
| Reword the supersession clause; delete the containment clause; delete the erasure clause; reword the residue clause | one owning pin each (four pins added after the chain-r20 challenge) | RED, one owning assertion per mutation |
| (Attribution repair) the availability-horizon mutation originally also destroyed the mandatory-digest line and redded on that earlier pin; narrowed to touch only the horizon fragment and re-applied | obligation: by-reference availability spans the retention horizon | RED on its owning pin after narrowing — recorded in the transcript rather than discarded |

The whole set was re-applied against the corrected candidate (not only the three new mutations), with the unmutated control green before and after: a fix round re-owes the full enumeration, not a confirm-my-fix subset.

## Review round 1 (codex), two P1 and one P2, all accepted

Lane: `review_gate.py --mode review`, stage `release`, risk tags `security-review` + `shared-gate`, chain `d1-model-visible-accounting`, packet `84ac4c56…`; `claude` skipped at preflight (`same_family_as_implementer`), acting reviewer `codex` (OpenAI family), `native_skill_binding=established`.

- **P1 (a), accepted — "policy at least as strict" was wrong on both axes.** A store purging *earlier* than the log reads as stricter yet makes replay fail inside the log's retention window, and a stricter access policy can deny the very principal replay runs as — both produce a falsely `reconstructable` record, which is the r5 failure class re-entering through this round's own wording. Fixed by replacing the strictness proxy with the real criterion: resolvable for the session log's whole retention horizon, access no broader than the log's policy, and the authorized replay principal keeps access; failing any of these classifies the item non-reconstructable.
- **P1 (b), accepted — a leaked secret had no accounting class.** The invariant demands exactly one classification for every model-visible item, but the leak path replaced the value with a typed exposure event without assigning a class, forcing a consumer to leave the item unclassified or invent a class that could retain forbidden material. Fixed: a leaked secret classifies **non-reconstructable with an explicit no-digest note** — raw and by-reference are prohibited for it — and the typed exposure event is that marker's metadata.
- **P2, accepted — the pins did not exercise either corrected semantic.** Three section-bound pins added (availability horizon, replay-principal access, leaked-secret class assignment), each shown RED under its own applied mutation in the refreshed copy; the leaked-secret mutation reds its pin while the exposure-event pin stays green, which is the requested differential.

## Review round 2 (codex, fresh chain on the remediated candidate), one P1, accepted

Lane: same profile, chain `d1-model-visible-accounting-r2`, packet `c1f341e4…` (a changed candidate takes a fresh chain — the state machine correctly refused to reuse round 1's result against different controller/owner bindings, and reuses review mode only for a chain's first round).

- **P1, accepted — the retained-keyring / rotation clause was droppable while every digest pin stayed green.** Without it, an implementation may discard old keys on rotation, leaving retained by-reference records unverifiable before the session log expires. Fixed with a separate section-bound pin on the clause; the applied deletion mutation reds that pin while the keyed-digest pin stays green — the same one-pin-per-obligation discipline the earlier rounds converged on.

## Review round 3 (codex, chain r3), two P1 and one P2, all accepted — plus a method fix

Packet `830886cd…`, `codex`, same profile.

- **P1 (a), accepted — persistence-time redaction contradicted "reconstructable (raw)".** The raw class read "persisted under the policy's redaction rules", so a redacted item could classify raw while replay cannot reconstruct what the model saw — completeness checks pass, the promise is false. Fixed: raw now means **byte-equivalent to the model-visible payload** (consistent with §3's truncation rule: same truncated form consumed, or full payload out-of-line); a redaction-transformed item classifies non-reconstructable, with the redacted derivative recorded as the marker's metadata rather than as the item.
- **P1 (b), accepted — this plan's design-decision bullet still stated the refuted "at least as strict" proxy in the present tense.** The same claim-outlived-state shape this program keeps meeting; the bullet now states the landed availability + authorization criterion and names the amendment.
- **P2, accepted — the three class definitions themselves were unpinned.** Fixed, and the recurrence is treated as a method signal, not another patch: three consecutive rounds each found one more unpinned obligation, so this round walked **every normative statement in the added clause** and pinned the full enumeration — seven new pins (raw byte-equivalence, redacted-not-raw, the by-reference lead, the non-reconstructable reason, the keyed-or-no-digest option, the completeness parenthetical, the secrets reference-resolution boundary) — instead of pinning only what the reviewer named. The complete applied-mutation set (twenty mutations) was re-run against this candidate with the unmutated control green before and after; each reds its owning assertion.

## Implementer self-review for the landing (persisted before the landing's independent review)

| Field | Result |
| --- | --- |
| Acceptance criteria rechecked | The approved design's five decision points each map to landed text: D-1 three classes (the §3 invariant bullet), D-2 digest discipline (the digest sentences + their pins), D-3 secrets/exposure event (the credentials sentences + pins), D-4 audit-only assertions (the audits-never-forces bullet + pin), D-5 reference-only surface (entrypoint untouched). Outstanding: the landing's dual-track review + adversarial challenge, and `make test` on the committed candidate — recorded in the verification section. |
| Changed files matched to the active artifact | Exactly four paths: the owner reference (rule), the fixture (pins), the ledger (two rows), and this plan. No entrypoint, Makefile, or other skill file. |
| Edge/failure paths considered | Each historical failure (r4/r5/r6) maps to a pinned sentence; the enumeration failure mode maps to the unconditional digest trigger, itself stated in the ledger row; relocation-out-of-section is covered by an applied relocation mutation; the round-1 findings added the availability-horizon, replay-principal, and leaked-secret-class paths, each now pinned and mutation-tested. This row was refreshed after the round-1 remediation, before any rerun of the independent lanes. |
| Regression test | The pin family is the regression test; each assertion shown RED under its own applied mutation and green on the unmutated candidate (table above). |
| Deterministic gates run | `test_ai_coding_implementation_gates.sh` → ok on the candidate; `check-ccl-skills.sh` (base `dev`) → `ccl_skill_check_ok` then `ccl_skill_check_clean_ok` (`r0_status=private-ok`) on the working tree — the impact-chain gate scopes to the committed diff, so its authoritative pass is re-run after commit and recorded in the verification section. |
| Known residual risks | (a) The pins catch deletion, rewording-away, and relocation, not a weakening sentence added beside them — the dual-track review owns that, as stated in the fixture and the ledger row. (b) The clause is prose guidance; nothing in this repository audits a consumer's session log. (c) The fixture now pins a second skill's reference; a future rename of `agent-session-persistence.md` reds the pins and must update them in the same landing. |

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
| `make test` (design round, full deterministic suite) | Implementer-run: exit 0, no `FAIL`/`ERROR` line, on the design-only candidate. |
| Security-owner approval | Original design: recorded — all five decision points approved by default by the maintainer on 2026-08-20, in-session, after being offered per-point amendment. Final amended wording (A1–A4): recorded — the maintainer approved all four amendments on 2026-08-21, in-session, as the D-6 row (review round 8 correctly rejected treating the original approval, or an agent-authored "re-checked at merge" note, as approval of wording that evolved after it). The agent records verdicts; the approval act itself is the maintainer's. |
| `check-ccl-skills.sh` (base `dev`, committed landing candidate) | Implementer-run: exit 0, `ccl_skill_check_ok` then `ccl_skill_check_clean_ok` with the private R0 audit passing — structural validation, markdown-reference resolution, leakage scan, entrypoint budgets, and the impact-chain gate over the committed diff, which validates both new ledger rows' declarations and firing paths. |
| Fixture on the landing candidate | Implementer-run: `test_ai_coding_implementation_gates.sh` → ok; the RED-baseline table above carries the applied-mutation evidence. |
| `make test` (landing candidate, full deterministic suite) | Implementer-run: exit 0 on the final tree; the suite was re-run green after every review-round remediation. One earlier run on the byte-identical final tree printed `1 FAILURES` with the failing test's identity lost to a truncated capture; the immediate full rerun on the same tree is green with a complete captured log (zero FAIL lines) — recorded as an unattributed flake rather than discarded. The authoritative execution is the protected CI run on the pushed branch, recorded in the merge request. |
| Landing dual-track review + adversarial challenge | Reviewer identity, packet hash, and per-round finding disposition are recorded in the merge-request description and the chain evidence rows, not here, so that recording an outcome does not change the candidate it describes. Until those records exist for the exact landing candidate, this row reads `pending`. |
