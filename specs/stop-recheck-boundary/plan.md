# Bound delivery Stop rechecks to the user turn

The delivery Stop hook can repeatedly challenge a resource-blocked final when
the host retry flag is reset. Preserve the first continuation check and let a
second final in the same user turn stop. This improves interruption handling
and avoids repeated work after the agent has reported a concrete blocker.

## Charter and implementation boundary

| Field | Decision |
| --- | --- |
| Purpose | Prevent repeated advisory Stop blocks from keeping a blocked task running. |
| Scope | Delivery Stop normalization, its existing marker helper, synthetic regression coverage, matching documentation and npm patch release. Safety gates and application changes remain outside this repair. No iterative-program watermark applies. |
| Depth | Generator/tooling change. |
| Result classification | Failure/correction: repeated identical false-flag Stop inputs produce repeated blocks; the true retry flag is quiet. A reported blocked final demonstrates the interruption, but does not by itself prove an infinite loop. |
| Matching analysis | Diagnose the missing owned retry bound, host resets, incomplete long-history evidence and the single-call testing gap; verify each with paired controls. |
| Failure boundary | Do not grant authority, infer task completion, suppress future user turns permanently, or replace a safety gate with an advisory marker. |
| Lifecycle impact | Hook implementation, debugging, regression testing, package publication, host acceptance, maintenance and source-free usage. No product application or production workload changes. |
| Evidence plan | Current runtime and tests; native user-event metadata; documented Stop inputs; repeat/reset, fresh-turn, concurrency, compaction, unavailable-state and oversized-history controls. Private report details are excluded. |
| Completion standard | RED before implementation, GREEN regressions, required repository lanes, deep self-review, independent review and adversarial challenge. Installation and real interrupted-session recovery are separate evidence. |

Artifact classification: `gate implementation`; risk route: `shared-gate`.
The active baseline is `origin/main`, with this plan on the isolated
`fix-stop-recheck-boundary` branch. The current default-branch repair flow uses
main as its PR target; the development ref lacks later hook changes.

Implementation owner: `skill-extraction-workflow` for shared hook behavior;
`defect-diagnosis` owns RCA and regression evidence; `testing-strategy` owns
coverage. All three were loaded before implementation. Product workflow and
feature risk routing supply the shared-gate classification. Stack-specific
implementation loading is not applicable to this shared-skill runtime repair.

Delegation: not applicable; the parser, state claim and their tests form one
dependent slice. Visible surface: no application layout or interaction change;
the existing reminder is bounded at its runtime delivery boundary. Formal
external spec planning is unnecessary for this bounded repair. Independent
review and challenge remain required before shared push.

Plan verifier discovery: root contract, README and Makefile declare
`scripts/check-spec-references.py` and `scripts/check-markdown-links.py`.
Run both on the plan before implementation; the full lane remains required.
Status-sync target: this plan and its evidence directory.

## Design

Use a validated host turn identifier when available. Otherwise derive a stable
turn identifier from the latest non-meta, non-sidechain native user record in
a bounded regular-file transcript tail. Tool results, hook feedback and compact
summaries must not start a new user turn. Use metadata identifiers, never prompt
text, in marker state.

Reuse the owned-directory, no-follow, atomic claim primitive in
`hooks/skill-loading.py`. The delivery reminder and document closeout share one
claim for the user turn. The host retry flag remains an earlier quiet guard.
Eligibility is checked before claiming: a quiet status must not consume the
turn's first reminder. A duplicate claim permits stopping even if the final
wording, tool activity or transcript size changed. A new user turn can receive
one reminder. Missing identity, unsupported metadata or unavailable/unsafe
state produces nonblocking information, never a repeating block.

The marker records an attempt only. It proves neither authorization, completion,
skill loading nor delivery quality. Existing owner, isolation and merge guards
are unaffected.

Security four questions: caller-controlled fields are the Stop payload and
transcript metadata; tampering can affect advisory delivery only, never access
or authority. No identity, billing, tenant or permission decision is made.
Actor identity comes from host metadata and remains separate from authority.
Negative cases must keep different actors and turns independent and reject
unsafe marker state without writing through it.

## Acceptance decision table and test cases

IDs are generated for this repair's acceptance inventory.

| ID | Inputs and scenario | Verdict/assertion | Expected baseline | Coverage |
| --- | --- | --- | --- | --- |
| S1 | Eligible final, valid actor/turn, first claim | One block with the existing reason | pass-existing | Native wrapper plus real temporary state |
| S2 | Same turn, false retry flag again; unchanged or restated blocker | Allow stop; no second decision/reason | fail | Multi-call native wrapper regression |
| S3 | Tool result, hook feedback, compact summary, transcript growth or rewrite between stops | No new claim for the same user turn | fail | Claude metadata and file lifecycle fixtures |
| S4 | New real user record or validated host turn ID | A fresh single block, followed by quiet stop | pass-existing without an owned bound | Claude/Codex wrapper controls |
| S5 | True retry flag, malformed event, quiet status or unrelated final | Quiet; a quiet status consumes no reminder | pass-existing | Existing tests plus quiet-then-eligible control |
| S6 | Missing helper, invalid identity, unsafe/unwritable state or no usable user record | Nonblocking information with no verdict claim | fail | Fail-open advisory controls |
| S7 | Concurrent duplicate Stop calls for one turn | Exactly one block | fail | Real atomic-state process race |
| S8 | Oversized/partial history, FIFO or malformed tail | Bounded processing; no invented turn or repeating block | gap | Regular-file and byte-bound controls |

| Test layer | Decision and command | Purpose |
| --- | --- | --- |
| Unit | Extend `python3 hooks/test_proposed_next.py` | Classification, identity selection, quiet and unavailable paths |
| Integration/contract | Run the same wrapper against real disposable marker state | Repeat/reset, independent turns and atomic concurrency |
| E2E/host smoke | Run native Stop JSON through the shipped shell entry | Proves hook output and state integration; does not prove model compliance |
| Manual/exploratory | Inspect native event metadata and reported output | Confirms fixture shape; interrupted-session recovery remains separate |
| Repository | `make test` | Required local lanes; explicit shared Git checks use `origin/main` |
| Supplemental | Public sanitization; heavy lane if shared skill text changes | Scope-driven checks beyond the local lane |

## Completeness and minimality

Objective: prevent the delivery reminder from repeatedly blocking one user
turn. Member: an eligible delivery Stop event. System of record: native Stop
input plus transcript turn metadata. Population: fires, because arrivals repeat.
Enumerator: all eligible finals in the acceptance decision table, with no
business/source filters. Component edge: shipped shell entry, normalizer and
owned marker state. No member is queued or deferred by the bounded tail: an
unverifiable event terminates as nonblocking information.

| Outcome class | Variants | Scope and acceptance points |
| --- | --- | --- |
| Positive | First eligible attempt; new user turn | in: S1, S4 |
| Negative | Malformed identity, unsafe state, unreadable/nonregular history | in: S5, S6, S8 |
| Corrected/recovered | Restated blocker, flag reset, tool activity, compaction | in: S2, S3 |
| Ambiguous/superficially successful | Unknown turn, concurrent claims, incomplete history | in: S6, S7, S8 |

| Concept delta | Current need | Simpler alternative | Decision |
| --- | --- | --- | --- |
| Turn-scoped advisory attempt | S2-S4, S7: independent bound despite host flag resets | Retry flag alone reproduces duplicate blocks; session-only marker suppresses later tasks | Keep using the existing atomic primitive |
| Bounded metadata turn lookup | S3, S4, S8: Claude Stop lacks a documented turn field | Full transcript scans are already incomplete on large histories | Keep; unknown stays nonblocking |

## Owner and source map

| Owner/surface | Direction | Disposition |
| --- | --- | --- |
| Delivery normalizer and wrapper | downstream | updated: owned advisory bound and regression fixtures |
| Existing state helper | sibling | unchanged API and protection model; reuse atomic claim |
| Product workflow | upstream | unchanged policy: one recheck supplies no authority; this plan records the shared-gate implementation |
| Testing strategy | verification | unchanged principles; multi-call, negative and precision cases apply here |
| Extraction workflow | governance | unchanged gate; hooks are already classified as non-wording shared behavior |
| Code review | verification | required independent review and adversarial challenge of actual diff |
| Reader documentation | downstream | updated to describe the runtime bound and fallback accurately |
| External/system process skills | reference-only | no editable target; no duplicated process recipe |
| Release coordination | lifecycle | patch preparation, protected-branch merge, tag-driven publication and published-artifact verification |
| Application/client, observability and case-document owners | lifecycle | no change to application behavior, telemetry or external testcase records |

## Execution and closeout

1. Verify this plan and write the S2/S3/S6/S7/S8 regression assertions.
2. Run them against the unchanged runtime and retain the assertion failures.
3. Implement the smallest turn lookup and atomic claim wiring.
4. Run focused tests, named-property mutation controls and the required lanes.
5. Persist deep self-review before separate independent review and challenge.
6. Dispose of findings, recheck later changes, commit neutral shared Git text and
   open a feature PR. Merge after required CI and exact-candidate review.
7. Publish npm 0.18.13 through the tag-driven workflow. Verify tag/SHA, registry
   integrity, provenance and the published package's three-host lifecycle smoke.

Release owner: `release-coordination`, loaded before release preparation.
The declared and published version is 0.18.12; prepare the next patch, 0.18.13,
after verifying its registry and remote tag absence. The release scope includes
the reviewed Stop repair and the version synchronization.

Implementation and focused regressions passed. Execution results, review
dispositions and publication verification are recorded under `evidence/`.
