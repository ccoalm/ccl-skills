# UI/UX Delivery Contract

Use this contract for every runtime-visible UI/UX slice. It is the canonical handoff between `product-ui-ux-design`, `testing-strategy`, every changed or claim-bearing producer owner, and every affected client implementation owner. Each skill keeps its own technical rules; this file defines the shared record, stage order, evidence semantics, and completion states.

Runtime-visible work includes layout, copy rendered by a client, state, interaction, navigation, tokens/themes, component semantics, accessibility, user-facing loading/empty/error/permission/progress/recovery feedback, and API/event/schema/default changes that alter what a client shows or which action or decision path it offers. A backend-owned value or contract is outside this contract only after an authoritative manifest, contract, package/repo inventory, or release target list establishes the complete consumer universe and every member is checked or proves it cannot render or react to the change. A zero-result search over an author-chosen repo or directory is not absence proof. If the universe or any member is inaccessible or incomplete, record `unknown-consumers`; do not silently classify the change as backend-only.

Only a value or contract change proven not to render on or alter any client may leave this contract. Route its backend behavior to the backend owner, its product meaning to the product owner, and its verification to `testing-strategy`, using API/log/output evidence plus the recorded consumer-universe proof. The inventory is routing evidence, not behavior verification. Do not use backend evidence to close an unknown or affected client surface.

Classify a consumer as `out-of-scope` only when evidence shows that stack cannot ship the value, or when the user accepts that same specifically named consumer as a current-thread handoff gap. The latter remains `pending + blocked`; scope acceptance neither proves absence nor permits `complete`.

The record may live in a plan, evidence file, task/MR description, or another reviewable artifact. A single-turn throwaway edit may use the visible progress record only if no changed file remains at handoff. Persist the record whenever the diff remains, is committed, or is handed to another owner.

This record is normalized evidence, not a required response layout. Store each
fact once and reference it across roles and phases. A handoff leads with the
decision, changed behavior, observable criteria, evidence level, blocker or
next action, and a pointer to the record; it does not paste every matrix, repeat
one evidence boundary under several headings, or substitute process labels for
task-specific behavior.

The execution order is `Design brief → Test Phase 0 → Producer/client execution → Test Phase 1/sufficiency → Design verdict`. Phase 0 chooses the proof before implementation; producer records capture the changed service/config/content/inference candidate and its observations, client records capture platform facts and the producer member/version actually exercised, and Phase 1 cites both sets to decide test sufficiency without copying them; only then does the design owner issue a verdict.

## 1. Design brief

Before editing a design artifact, UI copy, visual rule, design-system guidance, or code-facing acceptance criterion—or approving such a change—the design owner records enough analysis and planning to make it reviewable. A simple low-risk copy or spacing check may use a short inline record. New/reshaped screens, multi-platform surfaces, user-visible behavior, accessibility-sensitive flows, high-risk actions, branch/MR work, unclear risk, and implementation-driving design require the full Design brief, state/adaptation matrices, observable visual/interaction criteria, rendered/device evidence plan, and named producer/test/client handoff before edit or approval.

For runtime work, this draft exists before the first implementation edit. Testing, changed producer, and affected client owners consume it; they do not wait for a supposedly final design checkpoint.

Record these fields:

| Field | Required content |
| --- | --- |
| `slice_id` | Stable identifier for this surface/change. |
| `candidate_ref` | Mutable planning reference such as worktree/branch plus its current base. It locates work in progress but never binds executed evidence or a verdict. |
| `surface` | Runtime, framework, platform/host, surface type, and density mode. |
| `consumer_inventory` | Authoritative source used to establish the complete consumer universe; every member classified as affected, unchanged, out of scope, inaccessible, or unknown. |
| `trigger_class` | One delivery depth—`copy-only`, `narrow-visible`, `new-or-reshaped-screen`, or `systemic-redesign`—for runtime work, plus zero or more orthogonal work modes: `shared-system`, `source-code-evidence`, `design-to-code`, `audit/review`, `naming-version-sync`, `same-stack-multi-project`, and `multi-stack`. Record each observed basis and the union of references loaded. A source-only audit may omit delivery depth. |
| `user_and_task` | Target users, representative task, goal, prior knowledge, and use environment relevant to the decision. |
| `intent_and_risk` | Primary workflow/action, human intent, expected friction, consequence, and trust/safety boundary. |
| `structure` | Information groups regrouped by user intent and consequence, hierarchy, layout regions, navigation, progressive disclosure, return context, and component semantics. Separate routine context/data from security, recovery, and destructive/danger areas when their consequences differ; do not merely repaint the existing grouping. |
| `state_matrix` | Applicable initial, empty, loading/pending, success, failure, retry, disabled, permission, offline/degraded, partial, long-content, and interrupted/recovery states. Mark true non-applicable states with a reason. |
| `adaptation_matrix` | Primary and stress sizes, container/window constraints, text scaling/localization, input modes, collapse rules, safe area/keyboard/orientation where relevant. |
| `behavior_contract` | Routes, API/write effects, session/auth cleanup, destructive semantics, optimistic reconciliation, duplicate protection, return values, and preserved behavior. |
| `difference_class` | Each source-to-target difference is `defect-fix`, `design-freedom`, or `behavior-change`; split mixed changes and use the strictest class for an inseparable point. |
| `criteria` | Observable acceptance conditions, each with an ID, user/task outcome or invariant, and consequence if it fails. When applicable, name separate behavioral logic, aesthetic/visual hierarchy and craft, interaction, and component-semantics criteria; avoid adjectives without an observable consequence. The design brief does not select verifier type, assertion layer, rendered-evidence layer, command, or oracle; Phase 0 owns those choices. |
| `design_source` | Current product source, approved draft, design system, user-provided target, or source-light hypothesis; name specified states separately from design freedom. Record the source revision/version/content basis and any replacement or review artifact that can change the criteria. Mutable locators remain planning references until covered by an immutable design member below. |
| `design_record` | Resolvable location for the brief, criteria, source/replacement revisions, and review artifact. It may be mutable during planning; before evidence or a verdict relies on it, every changed or claim-bearing design item must have a keyed immutable member in `candidate_binding_set`. |
| `reference_surface` | Chosen current or accepted surface used to carry direction plus why it fits this slice; when no redesigned surface exists, say so and name the design reference/spec used instead. |
| `owners` | Design owner, test owner, a `producer_owner_set` keyed by every changed or claim-bearing backend/config/content/inference member, and a `client_owner_set` keyed by every affected rendered layer/runtime/target/repo, plus unresolved owner gaps. |
| `evidence_plan` | Planned automated, rendered/device, accessibility, task/user, and production evidence; list known unavailable layers. |

The initial record deliberately leaves `assertion_layer`, `rendered_evidence_layer`, verifier type, oracle, exact commands, producer returns, and client entry rules pending. Stage 2 and Stage 3 fill them. Criteria are complete when their observable condition and consequence are known; missing test-owned fields cannot make the brief incomplete. This ordering prevents the old circular wait in which testing required a completed checkpoint while the checkpoint required testing's layer choice.

### Trigger depth

`new-or-reshaped-screen` and `systemic-redesign` apply when any of these are true:

- the request declares redesign, restyle, modernization, or alignment with a new visual direction;
- layout structure, information grouping, navigation, component semantics, or visual system changes materially;
- a continuation uses a redesigned surface as the quality reference;
- multiple surfaces or shared tokens/components change with design-system consequences.

Shared token/component sweeps without information-architecture or behavior change may use `shared-system`. A copy or spacing change uses a lighter class only when it changes no structure, state, interaction, navigation, component choice, hierarchy, or behavior and is not presented as a redesign. Record the classification; uncertainty takes the deeper path.

For a systemic redesign or a sequence that uses one redesigned screen as the direction for later screens, every screen remains its own full design slice. Re-derive that screen's information architecture by grouping content and actions by user intent and consequence—for example, routine context/data apart from security, recovery, and destructive/danger areas—rather than repainting the existing layout. Re-derive behavior, states, adaptation, criteria, and runtime evidence at the same depth as the first/reference screen; an umbrella brief may share sources, tokens, and cross-surface invariants but cannot replace the per-screen records. Only a pure token/component sweep with no per-screen information-architecture or behavior change may batch implementation, and it still inventories every affected consumer.

A bare ownership declaration does not authorize a behavior change. If IA regrouping silently changes routes, writes, semantics, permissions, return behavior, or another preserved contract, that is an implementation defect rather than a design refinement; classify and route the behavior change explicitly.

### RED baseline

Every `new-or-reshaped-screen`, `systemic-redesign`, and behavior-changing slice records a falsifiable current-state baseline before implementation:

- a failing focused assertion when an executable harness fits; or
- a resolvable before artifact plus a target criterion for visual/layout work; or
- reproducible construction steps for a synthetic state.

The baseline proves the starting condition, not that the proposed design is good. Do not create a fake failing unit test for a visual judgment.

### Missed pre-edit record

If implementation starts before the required full or lightweight record exists, treat that as a process defect, not permission to write a brief around the result:

1. stop further implementation edits and record when/how the omission was discovered;
2. reconstruct the required record from the request, pre-change source/runtime, and product evidence rather than from the already-written implementation;
3. obtain Phase 0 and the client entry rule, then audit the whole existing diff against every criterion, preserved behavior, consumer, and evidence obligation;
4. record deviations and revise or reject the implementation before continuing.

Complete this remediation before further implementation, a completion/final claim, commit, push, or an MR-ready claim. A retroactive brief without the diff audit cannot bless the existing implementation.

## 2. Test Phase 0 — layer selection

`testing-strategy` responds to the design brief with the pre-implementation layer-selection pass below, then owns the separate Phase 1 closeout after producer/client execution.

Return a compact record before implementation:

| Field | Required content |
| --- | --- |
| `assertion_layer` | Unit/component/integration/browser/device/contract/manual-task layer for each criterion. |
| `rendered_evidence_layer` | Browser, simulator/emulator, real device, host preview, desktop runner, or PTY/terminal capture, including required sizes/themes/input modes. |
| `cases` | Criterion IDs mapped to happy, boundary, failure, recovery, and accessibility cases. |
| `command_and_target` | Planned command or interaction, candidate target, fixture/data needs, and expected current result. |
| `oracle` | What observation makes the case pass or fail; DOM existence alone is not a visual or interaction oracle. |
| `test_definition_set` | Resolvable Phase 0 mapping plus every harness, assertion/oracle, fixture, config, script, external test artifact, or manual protocol that can change the result. Before execution, each changed or claim-bearing item gets its own immutable test member in `candidate_binding_set`. |
| `evidence_gap` | Missing harness, environment, data, device, or human judgment with owner and next action. |

This Phase 0 response completes the draft's testing fields. Absence of a previously finalized checkpoint does not block Phase 0; absence of the design brief's user/task, states, risks, and criteria does.

For a valid `copy-only` slice, Phase 0 uses the lightweight record defined below rather than demanding the full state/adaptation/behavior matrices. It still selects semantic, accessible-name, localization, rendered-extent, and target-render or preview oracles as applicable.

## 3. Producer/client execution

When the slice changes or relies on a backend, event producer, remote config/CMS, schema/default, prompt/model, or generated-content path, every changed or claim-bearing producer first adds one member to `producer_record_set`. Each member records its owner/repository/runtime target, immutable candidate-binding member, build/schema/config/prompt/model/artifact identity, exact verification command and environment/endpoint version, API/event/log/output observations mapped to criteria, consumer-inventory pointer, coverage boundary, and gaps. Each client execution must name which producer member/version it actually exercised. A render against an old, unknown, or mismatched service/config/model cannot verify the changed producer candidate.

Build an owner set from every affected rendered layer, including content embedded in another container:

| Rendered layer | Client owner | Required local return beyond the shared record |
| --- | --- | --- |
| React web or React content inside Electron/WebView | `web-react-dev` | Browser/server route, viewport/container sizes, themes, input modes, console/network checks, overflow/focus/keyboard evidence. |
| Flutter, React Native, native Android/iOS, or native host shell | `app-cross-platform-dev` | Build target, simulator/emulator/device, safe area, keyboard, orientation, text scale, touch, lifecycle, and host/content bridge evidence. |
| WeChat/Alipay/Douyin or another mini-program host/page layer | `miniapp-product-dev` | Host/runtime version, developer-tool or device target, host capability/permission behavior, web-view bridge, package/platform constraints. |
| Full-screen terminal/TUI or terminal-rendered interface | `terminal-cli-dev` | Real PTY/terminal, dimensions, color depth/fallback, keyboard-only flow, resize, scrollback, selection/copy, long output, streaming/background progress, focus/modal state, and jump/new-output affordance evidence. |
| Electron/desktop shell or any rendered layer without an installed client owner | Project client conventions | Named surface/runtime plus the exact local convention consulted; otherwise use the fail-closed lookup below. |

A composite host has multiple owner-set members: React inside a native WebView uses `web-react-dev` for content and `app-cross-platform-dev` for the native container/bridge. A mini-program `web-view` uses the actual web-content owner plus `miniapp-product-dev`; Electron uses the actual web-content owner plus the installed desktop-shell owner or project client convention. For either host, React content routes to `web-react-dev`; Vue, Svelte, static, vendor, or another renderer routes to its installed owner or the fail-closed project-convention lookup below, never to React by container name alone. A single owner may fill two members only when an explicit project contract assigns both responsibilities and its evidence covers both layers. An unchanged host member still records the integration contract and proof that the change cannot affect it; omitting the member because the code diff sits in another repo is invalid.

Before the first implementation edit, every affected member of the client owner set adds a compact `client_entry` acknowledgement to the shared record: a short quote from, or exact identifier for, that owner's visible-UI, page-slice, design-checkpoint, or rendered-evidence rule plus the decision it produced; target surface/runtime; planned run/capture command; and behavior that must remain unchanged. Arbitrary skill text, a file path, runtime name, or vague anchor alone is not evidence of the applied convention. A project-convention owner must quote the specific surface/interaction/evidence convention applied. This is an entry decision, not fabricated execution evidence. Merely listing or naming an owner, including on the copy-only path, does not satisfy this step.

For a shared package, first establish the authoritative consumer universe from build/release targets, manifests, contracts, packages/repos, locale/config sources, and import evidence; then inspect every member. Record each as affected, unchanged, out of scope, inaccessible, or unknown with the basis. An incomplete universe or inaccessible member remains `unknown-consumers` and blocks a complete claim. The user may accept a specifically scoped handoff in the current thread, but its terminal state remains `pending + blocked`; acceptance of the handoff is not design acceptance or completion.

Before writing `no-installed-owner`, name the runtime/framework and why the installed client owners do not apply, then inspect the current repository's README/CONTRIBUTING, nearest AGENTS/CLAUDE contract, and client/style/design docs for a local convention. Record the locations checked. An incomplete or inaccessible lookup is `owner-lookup-unavailable`, never `no-installed-owner`.

Each affected client owner returns one member of a shared `client_record_set`:

- the same resolvable quote or exact section/rule identifier plus the implementation decision it shaped;
- affected files/components and preserved behavior contracts;
- exact run/capture command plus its keyed immutable candidate-binding member and target surface;
- review-accessible `artifact_ids` or paths;
- tested dimensions, states, themes, sizes, input modes, and assistive-technology checks;
- raw observations mapped to criterion IDs where the client owner can verify them mechanically;
- coverage boundary: what the gate detects, paths/states scanned, known false negatives, and remaining manual/runtime checks;
- unresolved product, design, test, platform, environment, or evidence gaps.

Prefer an existing route, state catalog, story/preview, fixture, smoke harness, or integration test. Batch planned captures and permission requests so evidence collection does not repeatedly interrupt the operator or create a noisy throwaway workflow that blocks normal work. If a temporary helper script or page is unavoidable, create or edit it once for the batch, reuse it, and remove it before commit and before completion unless the repository intentionally owns that harness. A state catalog or story counts as proof only when its execution is demonstrated; file presence and item counts are source evidence, not test execution.

### Candidate binding set

The design record/source artifacts, test definitions and executions, producer/client record sets, Test Phase 1, and design verdict use one `candidate_binding_set`, keyed by role owner, layer/runtime target, and repository/artifact. A truly single-member slice may use `candidate_binding` as shorthand. Every changed or claim-bearing design, test, producer, and required client member must resolve to the same logical candidate; a later change to any member invalidates the affected evidence and aggregate verdict.

- Design members cover the brief, criteria/behavior contract, and every design-source revision, replacement source, or review artifact that the verdict relies on.
- Test members cover the Phase 0 criterion mapping, harness/assertion/oracle, fixture/config/script/manual protocol, external test artifact, and each test-owned execution/result. An additional run identifies both its bound definition member and execution member.
- Producer and client members cover the candidate and runtime facts defined above. A client member also names the bound producer member/version it exercised.

Each binding value has a non-empty, exact payload from this closed set:

| Binding kind | Exact payload |
| --- | --- |
| `commit` | `commit:<full-40-or-64-hex>` |
| `tree` | `tree:<full-40-or-64-hex>` |
| `artifact-sha256` | `artifact-sha256:<64-hex>` |
| `dirty-bundle-v1` | `dirty-bundle-v1:<full-base-commit-hex>:<64-hex-bundle-digest>` |

Branches, tags, abbreviated SHAs, empty suffixes, mutable external version labels or artifact paths, and prose such as “current working tree” are locators, not immutable bindings. An external design, review, test, or runtime artifact without a content-addressed immutable ID is covered by an `artifact-sha256` member over the exact reviewed bytes plus its locator. Adding another binding kind changes this contract and requires its parser/oracle, collision and empty-value tests, and all consumer skills to change together.

A `commit` or `tree` binding is valid for an executed member only when the command ran from that exact materialized commit/tree and no tracked, untracked, ignored helper, generated file, symlink target, external harness/config, or other candidate input changed the result. For a Git worktree, the relevant checkout must be clean and its full HEAD/tree must equal the binding; `commit:HEAD` written after a run from dirty bytes is invalid. A result-affecting byte inside the checkout but outside/different from that commit/tree must be included in `dirty-bundle-v1`; a result-affecting input outside the checkout must have its own `artifact-sha256` member over the exact bytes. Do not relabel a dirty execution as a clean commit after the fact.

A dirty-bundle record also points to a reviewable manifest and the exact command/script used to derive it. The versioned manifest includes the base commit, the byte-exact binary tracked diff, every untracked member, and every result-affecting ignored member, all in sorted path order with path, file mode/type, and raw content or symlink target. Ignored generated files, helpers, fixtures, configs, and caches are not exempt merely because Git omits them; either include their exact bytes in the dirty bundle or bind each as a separate `artifact-sha256` member. Result-affecting external inputs always use a separate content-addressed member and locator. The manifest may exclude only a named non-deliverable proven unable to affect the candidate or result. If the record containing the digest is itself in the bundle, store the binding outside that bundle or define one canonical placeholder for only that field; do not omit the rest of the record or arbitrary files to escape self-reference. In a multi-repo or multi-target slice, preserve one keyed member per design/test/producer/client repository or artifact rather than hashing an unspecified ambient directory.

## 4. Test Phase 1 — execution result and sufficiency

After producer/client execution, `testing-strategy` consumes the complete design/test/producer/client member and record sets and returns one test-owned closeout:

| Field | Required content |
| --- | --- |
| `candidate_binding_set` | The same complete keyed design/test/producer/client binding set; `candidate_binding` is only the one-member shorthand. A branch name alone is never exact. |
| `design_record_ids` | Resolvable pointer per changed or claim-bearing brief/criteria/behavior/source/replacement/review member, with its immutable binding. |
| `test_record_ids` | Resolvable pointer per Phase 0 mapping, harness/oracle/fixture/config/protocol, external test artifact, and test-owned execution/result member, with immutable bindings. |
| `producer_record_ids` | Resolvable pointer per changed or claim-bearing producer member, including artifact/version identity, command/environment, API/event/log/output observation, coverage boundary, and gaps. |
| `client_record_ids` | Resolvable pointer per affected client execution member. Cite its commands, targets, artifacts, tested dimensions, and raw observations instead of copying them. |
| `additional_test_runs` | Bound definition/execution IDs for any test-owned commands/results/artifacts not already in a producer/client record, or `none` with reason. |
| `criterion_results` | Result and verifier per criterion, including which producer observation, client observation, or test artifact supports it. |
| `sufficiency` | `sufficient`, `insufficient`, or `blocked` for the required evidence plan, with the reason. |
| `coverage_boundary` | Combined detected paths/states/dimensions, known false negatives, and remaining manual/runtime checks. |
| `gaps` | Unresolved evidence, environment, data, or oracle gap with owner and next action. |

Each design, test, producer, and client owner writes its own facts once; Phase 1 owns criterion-level test interpretation, cross-member aggregation, and sufficiency. Missing, mismatched, stale, changed-after-run, or unexercised required design/test/producer/client owner or binding members make sufficiency `blocked`; one passing member cannot mask another. When the same person holds multiple roles, keep the sections in one shared record and reference the role-owned fields rather than duplicate them. A build, lint, type-check, or unit-test pass is not rendered evidence. A hand-authored or echoed transcript is fabricated evidence—the same defect class as fabricated verification output—and blocks acceptance. A screenshot proves only the captured visual state; it does not by itself prove which producer version ran, keyboard behavior, recovery semantics, accessibility, task success, or production behavior. `testing-strategy` does not issue the holistic design verdict.

## 5. Design verdict

The design owner evaluates the returned evidence against every criterion and records:

| Field | Required content |
| --- | --- |
| `criterion_results` | `pass`, `fail`, `blocked`, or `not-applicable` per criterion, with verifier and artifact/result pointer. |
| `verdict` | `candidate`, `accepted`, `rejected`, or `pending`. |
| `verdict_owner` | User, named independent design owner, or author under the bounded deterministic exception below. |
| `rejection_basis` | For `rejected`, classify `deterministic-conformance`, `design-judgment`, or `mixed`, naming the failed criterion. `mixed` follows the stricter design-judgment path. |
| `rationale` | Evidence-backed reason, named divergence, and consequence. |
| `candidate_binding_set` | Complete immutable keyed design/test/producer/client set defined above; `candidate_binding` is only the one-member shorthand. A mutable branch is only `candidate_ref`. Any covered brief, criteria, source/review artifact, harness/oracle, producer, UI/copy/state, or member mismatch invalidates earlier evidence and verdicts. |
| `next_state` | `complete`, `pre-runtime-test-ready`, `design-rejected`, or `blocked`, with owner and next action for any open item. |

Deterministic checks may close their own criterion without waiting for aesthetic judgment. An author may issue `accepted` only for a low-risk `copy-only`, `narrow-visible`, or current-source conformance slice when every blocking criterion has an independent deterministic oracle, all required runtime evidence is verified, and no criterion needs aesthetic/product judgment. A new/reshaped screen, systemic redesign, cross-surface shared-system direction, brand direction, high-risk semantics, any judgment-bearing criterion, or a prior `design-judgment`/`mixed` rejection requires a user or named independent design owner. Until that owner decides, the author records `candidate`.

This bounded deterministic exception intentionally replaces the blanket rule that an author can never accept any slice. It removes an owner wait only when independent oracles leave no design judgment to exercise; it does not turn author opinion into evidence. A prior deterministic-conformance rejection may use the exception only after its criterion-targeted fix binds a new candidate and every invalidated criterion reruns. Any rejection containing design judgment keeps the independent-owner requirement.

At a handoff, only these verdict/next-state combinations are valid:

| Verdict | Next state | Required condition |
| --- | --- | --- |
| `accepted` | `complete` | The bound Phase 1 `sufficiency` is `sufficient` and no required evidence gap remains; every blocking criterion is `pass` or justified `not-applicable`; every required design/test/producer/client owner, record, exercised-version link, and binding-set member is present and verified; the allowed verdict owner accepted. |
| `rejected` | `design-rejected` | A blocking criterion or design judgment failed; preserve the negative evidence and revise the target. |
| `pending` | `pre-runtime-test-ready` | The only missing blocking layer is named runtime/rendered execution; lower layers pass, and an executable command/target plus named runtime owner is handed off. |
| `pending` | `blocked` | A required owner, decision, permission, environment, non-runtime evidence, consumer inventory, or criterion cannot be resolved. |
| `candidate` | `blocked` | Evidence is ready for a required user/independent design verdict, but that verdict has not arrived; name that owner and review artifact. |

All other terminal combinations are invalid. In particular, `accepted + pre-runtime-test-ready`, `accepted + blocked`, `pending + complete`, and `candidate + complete` are contradictions. During active work, omit `next_state` rather than manufacture a terminal combination.

Status meanings:

- `candidate`: author assessment; useful for review, never final acceptance.
- `accepted`: required criteria pass on the bound candidate and the required verdict owner accepts the design.
- `rejected`: a blocking criterion or design verdict failed; the current render is negative evidence, not a baseline to polish into acceptance.
- `pending`: evidence or verdict has not arrived; silence is not acceptance.
- `pre-runtime-test-ready`: lower layers are ready and the only missing blocker is named runtime/rendered execution with a named owner and command; it is not design acceptance.
- `blocked`: an owner, decision, permission, consumer universe, non-runtime evidence, environment without an executable handoff, or required independent verdict is unavailable.

A missing or absent design verdict is `pending` and blocks `complete`, MR-ready, merge-ready, and normal MR; it cannot be treated as tacit approval.

When a surface is `rejected`, preserve the rejected evidence and its `rejection_basis`. Until a re-rendered revision is `accepted`, rejection blocks `complete`, MR-ready, merge-ready, and every normal or ordinary draft MR; the rejected render or screenshot is negative evidence and cannot be reused as acceptance evidence. A `deterministic-conformance` rejection may be repaired by a targeted change—including a qualifying lightweight copy fix—only when the change addresses the failed criterion, introduces no new design judgment, binds a new candidate, and reruns every invalidated criterion; repeated failure stays blocked and routes through `defect-diagnosis` until its cause is isolated. A `design-judgment` or `mixed` rejection requires a revised design target, fresh baseline, new runtime evidence, and user/named independent design verdict; isolated copy, spacing, or token patches cannot clear it. A clearly labelled review-only draft MR may transport only the revised bound candidate to that named independent owner; it remains `candidate + blocked`, is not a normal handoff or MR-ready claim, and cannot merge. A second design-judgment rejection on the same surface stops implementation churn and returns the direction to that owner.

## Evidence semantics

Evidence dimensions are claim-matched, not a global ladder; verify every required dimension:

1. Intent/source: a rule, design, spec, or decision exists.
2. Static implementation: relevant code/config/story/test exists.
3. Automated acceptance: an exact command ran against the candidate and its oracle passed.
4. Rendered/device runtime: the target surface and required states were inspected on the named runtime.
5. Representative task/user: target users attempted credible tasks under the recorded protocol.
6. Production outcome: version-bound field metrics or incidents support the claim.

Dimensions do not substitute: production outcomes do not prove conformance; conformance does not prove user success; screenshots do not prove durability or recovery. Multi-dimensional criteria close only when all required dimensions pass. Heuristic review is risk discovery, not acceptance proof. Automated accessibility checks and user evaluation complement standards conformance; neither substitutes for the other. A single participant, single screenshot, single viewport, or single expert review does not justify a population-wide or cross-platform claim.

`unavailable-with-owner` and `unavailable-no-owner` are valid rendered-evidence statuses only when the record includes every attempted capture command, its observed failure, the residual risk, and the next unblock action. An unavailable label without an actual attempt record is invalid. Render-layer failures can also be nondeterministic: an earlier per-screen capture may look clean while a later pass exposes the defect, including charset auto-detection that renders clean once and garbled later. An aggregate or final design review therefore re-renders the actual artifact set at review time—even when the candidate binding is unchanged—instead of trusting earlier per-screen captures or a source-level pass.

`planned` includes the exact capture command/step and must resolve before a final design verdict, MR-ready claim, or normal MR. The only unresolved-runtime handoff is `pending + pre-runtime-test-ready` with its named owner/command. An unavailable layer closes only as a handoff gap after the user is told the residual risk and explicitly accepts proceeding without that evidence for this specific change in the current thread; `unavailable-no-owner` remains `pending + blocked`.

For every deterministic gate, record its coverage boundary. A regex/path scan proves only its declared scan scope. A token reference proves use, not rendered theme correctness. A component test proves its oracle, not that CI executes it. A render proves the captured state, not production durability or recovery.

## Design-system and state contracts

- Encode stable visual and accessibility invariants in semantic component APIs, tokens, types, and focused tests when the codebase supports them. Prose remains the rationale and boundary, not the only enforcement layer.
- Keep a previewable state catalog for high-cost loading, empty, failure, permission, offline, partial, recovery, and success states. Pair it with mapping/coverage checks where source inputs can be enumerated.
- Classify errors by affected scope, recovery path, durability/finality, and retry safety. Choose one primary carrier; do not stack inline, banner, toast, and modal messages without distinct jobs.
- Preserve stateful workspace cores across transient loading/error/mode changes when remounting would lose draft, focus, selection, scroll, or media state. Verify preservation at runtime.
- Apply the same token, responsive, accessibility, and state checks to examples, stories, catalogs, and docs that teams use as implementation sources.
- Before landing executable design guidance that affects multiple client stacks, name every downstream stack owner and route the reusable rule through `skill-extraction-workflow`; mirror its executable form into every affected owner, or record for each stack why its behavior remains unchanged.

## Copy-only and source-only paths

A runtime copy-only change may use a lightweight record when it stays in the same component, rendering slot, or output field and changes no conditional logic, hierarchy, layout, state, interaction, navigation, behavior, or component semantics. The lightweight record is complete with: `slice_id`, `candidate_ref`, surface and authoritative consumer inventory; before/after copy and classification evidence; semantic intent and risk class; unchanged component/slot/field and behavior proof; the design/test owners, every changed or claim-bearing producer owner, and every affected client owner; and criteria for accessible name, terminology, localization, rendered extent, and target render/preview where applicable. It intentionally omits unrelated full-record matrices.

Testing supplies a lightweight Phase 0 for those criteria; each changed producer and affected client owner may begin from that record instead of the full brief. The lightweight design record, test definitions/executions, and producer/client returns still form the complete immutable candidate-binding set and record their own source or command/target, artifacts or observations, criterion links, coverage boundary, and gaps; client returns also record tested locales/sizes and the producer member/version exercised. Phase 1 binds and cites the complete design/test/producer/client record sets. Error, auth, money, destructive-action, permission, legal/compliance, and AI-disclosure copy are not lightweight; route their risk and run the full contract.

If later evidence proves the `copy-only` classification wrong, the lightweight record is invalid from that discovery point, and you must apply **Missed pre-edit record** to the existing diff by stopping implementation edits, rebuilding the full Design brief, obtaining full Phase 0 and every affected producer/client owner entry, auditing the whole existing diff against them, then rerunning producer/client execution, Phase 1, and the design verdict. Until that remediation closes, the slice is `pending + blocked`; the old lightweight result cannot support completion.

If rendered evidence is not captured for a qualifying copy-only edit, it can close only as `pending + pre-runtime-test-ready` with the named runtime owner/command, or as the same risk-disclosed, specific-change, current-thread user-accepted handoff gap above. It is never `complete` without the required render.

Copy acceptance is semantic, not a character-count shortcut: action labels identify the action and object/consequence when context does not; errors state what happened, a safe/useful reason when available, and the next repair action; disabled controls expose a safe reason and enablement condition or are hidden when disclosure is unsafe; success feedback names the completed outcome and useful next step; terminology, tone, accessible naming, localization and rendered extent remain consistent. Platform-standard short dialog labels are valid when the consequence is already unambiguous.

Source-only guidance, design-file, or audit work stops before Stage 3 when no runtime implementation is requested. Report recommendations as hypotheses or acceptance criteria and name the missing implementation/runtime evidence. Do not fabricate a client handoff.

## Persistence and safety

Artifacts must resolve at review time through repo-relative paths, review attachments, or named artifact IDs. Do not use local absolute private paths. Record the command and target with captured output; a pass/fail summary alone is not an inspectable artifact. Use sanitized/test accounts and redact tokens, credentials, PII, private paths, and raw personal data.

Any required evidence status other than verified leaves the slice `pre-runtime-test-ready` or `blocked`. A user may accept a gap only after its residual risk is disclosed and only for the specifically named change in the current thread; blanket autonomy, a prior “continue”, or a different slice's acceptance does not convert the gap into `complete`.
