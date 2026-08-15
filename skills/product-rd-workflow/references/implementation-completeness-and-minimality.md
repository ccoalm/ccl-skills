# Implementation Completeness And Minimality

Use this gate for behavior-changing product delivery.

- **Functional completeness and structural minimality are independent gates. For behavior-changing delivery, map every in-scope acceptance point to implementation plus fresh evidence, and every retained new concept to a current acceptance point or hard constraint. Gaps block `complete`; speculative future need and omitted required behavior both fail.**

It answers two separate questions:

1. Did the change deliver every behavior currently in scope?
2. Did the change introduce only the structure needed by those behaviors or a hard current constraint?

Passing one question never compensates for failing the other. Minimality does not permit omitted behavior; completeness does not justify speculative machinery. Objective Closure below fixes the scope that question 1 is measured against: the objective's whole authorized population and all of its outcome classes, not the slice that happened to be convenient.

## Objective Closure

Two records are required for every behavior-changing delivery, written into the acceptance inventory at implementation entry. A `complete` claim without them is invalid.

Every record below is read against one fixed pair — the objective and its member unit. Fix that pair first, because every laundering route in this section works by moving it.

**Every boundary here is an implementer claim the reviewer accepts or rejects** — the objective, the member unit, the system of record, the enumerator and its filters, the component edge, and each continuation assumption. Record them together so they can be checked as a set. This section cannot make a boundary self-proving: no wording stops an implementer who is willing to draw the line somewhere convenient, and each boundary it pins down simply moves the next one outward. What it does guarantee is that every boundary is **visible, attributed, and rejectable**. Discharge it with one line — `boundary acceptance: <reviewer identity> accepted <objective | member unit | system of record | enumerator+filters | component edge | assumptions>, <locator>` — where the *component edge* is the set of systems this delivery treats as in-scope for producing or consuming the members. A boundary with no such line is unreviewed, and an unreviewed or rejected boundary reverts the delivery to incomplete under Firing And Closeout, where the implementer rebuilds the rows.

### Objective and member identity

- **The objective is the enclosing product outcome the requesting authority asked for**, cited by its own locator. Choosing an authority-authored *sub*-objective is legitimate and closes **only that sub-objective**: the enclosing objective's classes stay `in` until every sub-objective under it closes. "The request also asked for a batch endpoint" makes the endpoint a sub-objective, never a replacement for "migrate every account".
- **The member is the unit the objective counts.** If the objective says every account, the member is an account — never the request, batch, job, page, or call that happens to touch accounts. A member identity finer than the objective's unit invalidates the preflight verdict and every bound row that rests on it.
- **The population is enumerated from the objective's system of record, not from whichever query or endpoint is convenient.** Name the enumerator and every filter it applies. A filter the authority did not state — archived, locked, soft-deleted, tenant-scoped, or simply absent from a new endpoint's result set — does not shrink the population: those members stay `in` and unprocessed, which is a `gap`. Fixing the member unit while letting a convenient query define the set is the same laundering one level down.
- Both are recorded once, with locators, and every row below refers to them. Changing either mid-flight re-runs this section and records the old pair, the reason, and whether the new pair narrows the old; a narrowing move needs the same independent authority as an `out` class, so a silent replacement is not a re-run.

### Population preflight

Record `population: fires` or `population: does-not-fire`, with the instance-count or arrival basis behind the verdict.

- It **fires** whenever satisfaction depends on more than one work item, event, record, or user, or on repeated arrivals — regardless of whether the goal is phrased as a quantity, a capability, a reliability claim, or a continuous behavior. Repeated-arrival and open-ended populations fire even when a point-in-time query enumerates them today. Classification, sampling, or batching in the implementation also forces `fires`.
- `does-not-fire` must quote an authoritative source establishing both the finite member set and a boundary after which no new member can arrive, and must resolve that source's exact locator at closeout. That source must exist **independently of this delivery** — a snapshot, ID list, or "no arrivals after T0" claim authored inside this delivery is the implementer enumerating their own convenient set, not authority. An unquoted, unresolvable, or same-delivery citation counts as `fires`.
- Low-cost single-instance exception: a verbatim user statement or a lifecycle-issued Ready PRD section naming exactly one static instance and establishing that the objective carries no collection, sampling, or repeated-arrival semantics; record and resolve its exact locator. An implementer-authored characterization, a plan artifact, a self-asserted single instance, or any assertion authored inside this same delivery is never sufficient.
- **When the preflight fires, reconcile enumerated against covered before closing.** Record the enumerator's revision, its resolved output and count, the member set that actually reached a terminal outcome, and the difference between them. Naming the right query and writing "all members" in the class rows is not the proof — the reconciliation is; every enumerated member missing from the terminal set is a `gap`.
- The verdict governs member-population proof only. It never removes the outcome-class row below.

### Outcome-class row

Always walk the positive, negative, corrected/recovered, and ambiguous-or-superficially-successful outcome classes within the already-authorized source population. This row maps existing scope; it never invents new sources or mechanisms. One row per class, all four always present:

| Outcome class | Scope | Member scope it holds over | Implementation surface | Fresh evidence | Status |
| --- | --- | --- | --- | --- | --- |
| positive / negative / corrected-recovered / ambiguous-or-superficially-successful | `in` / `out` / `deferred` / `absent`, each with its locator or mechanism per the rules below | which members this class's handling actually covers — "all members of the population" or the named subset | the code path that handles it, or `none` | command and result, trace, or query — over the recorded member scope | satisfied / gap / blocked / unknown |

- **Each class enumerates its independently-failable variants** and links them to the Functional Completeness rows that cover them. `negative` is not one behavior: timeout, authorization denial, validation rejection, conflict, and dead-letter are separate variants, and `satisfied` requires every in-scope variant closed. One passing validation test does not close the negative class.
- A class whose scope is `in` and whose implementation surface is `none` is a `gap`, and a `gap` blocks `complete` exactly as it does in the Functional Completeness table. Four classes recorded `in` with only the happy path implemented is the failure this table exists to make visible — the row cannot be satisfied by listing the classes.
- **Member scope is a claim about coverage, not about fixtures.** A class exercised on a hand-picked fixture, while its handling is not on the path every member takes, records that narrower member scope and stays a `gap` for the rest — it is never `satisfied` for the population.
- Every class implied by the stated objective defaults to `in`. Universal authority language ("all real work") places every walked class in scope unless that same authority already records an exception; quote the exception and resolve its locator, or the class stays `in`.
- A class the behavior cannot produce is marked `absent`. Because `absent` needs no product authority, it carries an evidence bar instead: cite the **mechanism** that makes the class impossible — the state machine, API contract, or schema constraint, with its locator — never the implementer's model of the behavior. `absent` is rejected when any retry, replay, manual repair, or upstream redelivery path can produce the class **outside the edited component** (an ambiguous-success class is not `absent` merely because the API returns a typed result: stale, partial, duplicated, and asynchronously-rejected successes still count). A class that can occur and is merely unhandled is `in`, never `absent`.
- `out` or `deferred` requires a verbatim user statement or a lifecycle-issued Ready PRD section traceable to an explicit product-authority decision, the exact source locator (user turn or PRD section heading), and the rationale. The authority must exist **independently of this delivery**: a section authored or amended within this delivery by the implementer is not authority for narrowing that delivery, whatever lifecycle state it later reaches. Text authored to clear this gate, an unresolvable locator, and an implementer's reading are not authority: the class stays `in` and blocks any slice that contradicts it. This deliberately narrows the per-point `out`/`deferred` rule under Functional Completeness: dropping a whole outcome class is a scope decision, so those two forms are the only accepted shapes of the explicit product/human authority that rule requires — where they conflict, this section governs outcome classes and that rule governs individual points.
- Never reopen a class, goal layer, or outcome axis that authority already set. Absence of an exception under an explicit universal objective is decisive, not a question to send back to the user — do not offer or solicit a hypothetical carve-out, and do not ask the user to choose arbitrary scheduling numbers when no product outcome is undecided.
- The acceptance artifact marks every walked class and must not append optional exclusion, sampling, expiry, or scope-reconfirmation questions.
- A deferred class makes the current slice `interim` for the objective. Report it as `slice complete; objective interim`, naming the deferred class — a bare `complete` is invalid while any class under the cited objective is unprocessed, whatever the slice achieved. This is the scoped-partial result required under Firing And Closeout, stated for outcome classes.

### Per-operation bounds and no-starvation

List every per-operation sample, batch, context, time, or resource bound separately from the total obligation.

- Such a bound only **schedules** work. Without a verbatim user statement or Ready PRD section plus exact locator explicitly narrowing the total obligation, it never narrows it; an authority-narrowed total is recorded as product scope, never relabelled as a per-operation bound.
- Whenever the population is open-ended **or a per-operation bound defers any member** — the two triggers are independent, because a finite `does-not-fire` population can still be processed under a bound — record observable progress/finality plus **executed** continuation evidence.
- **The evidence must exercise the continuation mechanism, not one lucky item.** One trace of item 513 advancing past a batch of 512 proves that item advanced; it says nothing about 514 onward, and a cursor that rescans 1–513 forever satisfies it. What closes the row is an executed test, run, or query showing the selection invariant itself: the cursor/queue/marker advances monotonically and every member is eventually selected — a repeated run that drains the population, or an assertion on the selection rule. A designed-only scenario, or evidence covering a single overflow member, keeps the objective `interim` and blocks `complete` for this delivery.
- **Continuation evidence records the assumptions it rests on** — selection ordering, arrival rate, retry, mutation, restart, and crash behavior — because no finite run proves liveness for an open population. Naming an assumption is not satisfying it: each one is either **observed** (production or staging telemetry showing it holds in the real operating envelope) or **monitored** (a named alert/invariant with an owner that fires when it stops holding). Each carries its locator — telemetry: query, window, and result; monitor: the alert identity plus a record of it having fired at least once, and the population it covers — and its owner is someone other than the implementer. An assumption that is neither, one whose monitor is self-owned or never shown to fire, or one whose monitor is currently firing or carries an unresolved incident, keeps the row `interim` — a favorable assumption asserted by the implementer over a fixture is the starvation path restated, not evidence against it. A drain over a static fixture closes a finite population only; for an open one it closes the row only when the assumptions are named and the selection rule is shown not to starve older members under them (a `ORDER BY updated_at LIMIT n` scan that retries refresh, or a cursor that resets on restart, is a starvation path, not evidence).
- **"Defers nothing" is judged against the member identity in the population row, never the operation's own unit.** A per-request timeout, context limit, or resource cap that fully completes the *member* it handles defers nothing and closes on its bound row. A request that terminates cleanly while the business record it was processing stays unprocessed **defers that member** — redefining the member as the request is how this row gets laundered.
- This is a no-starvation check, not a new latency or quota SLO unless the product outcome requires one.
- A representative success, one green slice, an omitted-count report, or a bounded call proves that slice only; none of them closes an objective whose required classes can remain indefinitely unprocessed.

## Functional Completeness

Start from the active requirement or acceptance source, not from the implementation diff. Preserve stable IDs and explicit source decisions so a never-implemented behavior remains visible. When the source has no native numbering, assign generated trace IDs, mark them `generated`, map each to the source's literal text, and record the source revision or timestamp consulted so a later source rewrite cannot silently erase in-scope points; never present generated IDs as source-native.

| Requirement / acceptance point | Source decision | Implementation surface | Verification | Fresh evidence | Status |
| --- | --- | --- | --- | --- | --- |
| one independently-failable behavior | in / out / deferred, with source authority | code, config, migration, UI, API, job, or docs surface (docs only when the point itself is documentation) | lowest sufficient assertion or real-flow check | command and result, trace, screenshot, or API result | satisfied / gap / blocked / unknown / out / deferred |

Rules:

- Every in-scope point needs an implementation surface and fresh verification evidence before the delivery is called complete.
- `gap`, `blocked`, or `unknown` blocks a complete claim. Report the exact incomplete boundary and unblock action.
- `out` and `deferred` are terminal only when the active product or human source explicitly made that decision; record the decision reference. A `deferred` point must also name a durable follow-up locator — a tracker row, issue, or status-document entry; a chat message alone is not durable — otherwise the row stays `gap`. An implementer may not silently downscope a point.
- `not-applicable` is never a per-point status: a point leaves scope only as `out` or `deferred` with source authority. The two-axis `not-applicable` exists only for the whole-delivery exemption defined under Firing And Closeout.
- Derive primary scenarios from this matrix. Code analysis may add boundary, failure, permission, compatibility, and regression risks, but cannot prove that absent behavior was never omitted.

## Structural Minimality

Record the concept delta before or during implementation, then revisit it against the final diff.

| New concept | Current acceptance point or hard constraint | Simpler alternative | Decision |
| --- | --- | --- | --- |
| abstraction, indirection, module/service, state/entity, dependency, config/flag, generalized path, or extension point — including a material expansion of an existing one (new states, new generic parameters, new dependency capabilities) | stable acceptance ID or observed current constraint | inline/local/direct option considered | keep / simplify / remove |

Rules:

- Each new concept must point to a current acceptance point or an observed hard constraint such as repeated current duplication, required isolation, testability, reliability, security, or compatibility — with a concrete locator (the duplicated call sites, the failing or unwritable test, the incident or requirement reference). A bare label like "testability" with no locator does not justify `keep`.
- “Might be useful later”, generic extensibility, and hypothetical reuse are not evidence. Prefer the direct implementation for the known problem.
- Refactoring, self-testing, and code-health work are allowed when they address an observed current constraint; minimality is not a reason to preserve harmful structure.
- When the simpler alternative is adequate, remove or collapse the new concept before closeout.
- **Before deleting or demoting an existing surface, classify its consumers by corpus, not by grep count**: *production* (shipped source, runtime config, loader/config paths, product smoke entries), *non-production* (tests, docs, decision records, snapshots, generated expected outputs, comments), and *ambiguous* (examples/scripts that may be product smoke paths — inspect before classifying). "Only tests or docs consume it, and what they pin is not load-bearing" is the strong deletion signal; a production caller turns the removal into a feature decision, and a surface an implemented decision record or hard-won defensive pattern explicitly justifies needs new evidence that beats that reason. Search the exact symbol, event/config/wire strings, and both `.name(` and `name(` call forms, then read the call sites — a dead-code tool is not a substitute for reading public interfaces, dynamic names, and loader paths.
- **A correct-but-tiny simplification is a tagged TODO, not a record**: `TODO(<stable-tag>)` naming the smell and the action, so it can be revisited; reserve a decision record for removals that change public API, durable formats, or behavior.
- An empty concept delta is recorded as one row with `none` in the concept column and `no new concept` as its decision; the structural axis becomes `not-applicable` only under the whole-delivery exemption at closeout.
- A `simplify` or `remove` decision not yet reflected in the final diff is a blocking row: closeout cannot claim `complete` while the concept it rejected is still present.

## Firing And Closeout

1. At implementation entry, record the Objective Closure population preflight and outcome-class row as part of the functional axis. When the preflight fires, expand its member set into the acceptance inventory; when the population is open-ended or any per-operation bound defers a member, add the continuation obligation. A delivery whose functional axis is exempt under the exemption rules below carries objective closure with it and records `objective closure: not-applicable — <exemption class>` on that axis line instead. The reviewer confirms that classification from the diff and the original acceptance source; a rejected exemption, a missing record, or an invalid preflight blocks `complete`.
2. At implementation entry, copy or reference the complete active per-point acceptance inventory and preserve its stable IDs and source decisions.
3. Before the first edit, identify expected new concepts and the simpler alternative; update the rows when the diff changes direction.
4. Have `testing-strategy` derive requirement coverage first and add implementation/code-risk scenarios second.
5. Self-review the final diff in both directions: acceptance point to implementation/evidence, and new concept to current necessity.
6. Give reviewers the original acceptance source, both tables, the final diff, and fresh verification results; a diff alone cannot reveal missing behavior.
7. Claim complete only when every in-scope row is satisfied and every retained concept has a current justification. Otherwise report a scoped partial or blocked result.

The reviewer-visible closeout must carry both tables, even when each has only one row; when no concept was added, record `none` instead of inventing one. Keep this proportional: a low-risk change may carry both tables inline. Exemptions are per-axis, not blanket: only a documentation-only diff may mark both axes `not-applicable` (documentation-only means internal or engineering documentation with no user-visible surface — user-visible copy and published API reference content are product behavior, never documentation-only). A pure refactor with no acceptance-point behavior change, or mechanical maintenance with no contract/behavior delta, may mark only the functional axis `not-applicable` — the structural axis stays live, because refactors are exactly where new abstractions appear; record its concept-delta table (or the `none` row). No exemption waives regression evidence: the existing suite covering the touched behavior stays green and is cited. An exempted axis records one line — `axis: not-applicable — <exemption class>, reviewed diff <identity>` — in place of its table; a live axis always records its table. In every case the reviewed diff is the evidence, and a reviewer confirms the classification from the diff, not from the implementer's label: the implementer classifies at implementation entry as a recorded claim, and the reviewer confirms or rejects that claim at closeout. Diffs touching API contracts, schemas or migrations, permissions, quotas or pricing, config defaults, or user-visible copy are behavior-changing by default and never take any exemption. Claiming an exemption does not defer the question to closeout: classify at implementation entry, and when a reviewer rejects the classification the delivery reverts to incomplete — the implementer rebuilds the required tables from the acceptance source; reviewers never reconstruct the evidence themselves.

## Practice Basis

- [Google Engineering Practices: What to look for in a code review](https://google.github.io/eng-practices/review/reviewer/looking-for.html) treats functionality, complexity, and tests as distinct review dimensions and warns against code made more generic than present needs require.
- [Martin Fowler: Yagni](https://martinfowler.com/bliki/Yagni.html) rejects presumptive future capability while distinguishing that rule from neglecting refactoring, self-testing, or continuous delivery.
- [NASA Requirements Verification Matrix](https://www.nasa.gov/reference/appendix-d-requirements-verification-matrix/) demonstrates the durable pattern of assigning requirements stable identifiers and explicit verification methods.
