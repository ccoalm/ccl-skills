# UI/UX Evidence And Theory Ledger

Use this ledger when a design judgment cites theory, a standard, a benchmark, or a platform convention. It prevents a useful source from being promoted beyond what its original text supports.

Last verified: 2026-08-29. Recheck sources whose version, status, platform behavior, or recommendation can change before relying on them for a new release or compliance claim.

## Evidence classes

| Class | Meaning | How it may be used |
| --- | --- | --- |
| Standard | Normative standard or success criterion for its stated scope | May block a scoped conformance claim when applicable and tested correctly |
| Specification or draft | Technical mechanism defined by a standards body, with its published maturity retained | May justify mechanism-level implementation checks; recheck status/support and never infer design quality from feature existence |
| Community Group report | Final report published by a W3C Community Group; not a W3C Standard or Standards Track deliverable | May support mechanism-level interoperability checks at its published status; never use it as a conformance standard or infer design quality from feature existence |
| Stable mechanism | Repeatedly useful explanatory mechanism with a bounded domain | Generates a design hypothesis; does not set a universal UI recipe or numeric threshold |
| Contextual empirical | Study result tied to its method, sample, task, and environment | Informs risk and test design; must retain the study boundary |
| Conceptual framing | Named distinction or expert argument that sharpens observation | Generates a hypothesis and vocabulary; is not empirical proof or a numeric acceptance rule |
| Informative guidance | Non-normative method or practice from an authoritative body | Starting method or checklist; verify against the target context |
| Vendor convention | First-party platform guidance | Acceptance input for that platform only; preserve the source's requirement/recommendation strength |
| Local heuristic | Team or product pattern supported by local evidence | Starting hypothesis until target evidence verifies it; never present as external theory |

Write a claim as:

`observation → mechanism/risk → design hypothesis → observable check → boundary`

Do not write “Hick says,” “Fitts says,” “Miller says,” or “Doherty says” as the complete rationale. Name the actual decision variable: option search, target acquisition, hidden-context recall, feedback/state uncertainty, or another observable burden.

## Claim ledger

### Human-centred design and usability

| ID | Class and source | Supported use | Boundary | Observable check |
| --- | --- | --- | --- | --- |
| HCD-01 | Standard — [ISO 9241-210:2019, Human-centred design for interactive systems](https://www.iso.org/standard/77520.html) | Consider users, tasks and use context throughout the interactive-system lifecycle; iterate design and evaluation | The ISO abstract says it gives requirements/recommendations and an activity overview, not detailed coverage of methods and techniques | Context brief names target users, representative task, use environment, constraints, and iteration evidence |
| HCD-02 | Standard — [ISO 9241-11:2018, Usability: Definitions and concepts](https://www.iso.org/standard/63500.html) | Treat usability as an outcome of use in a specified context rather than an intrinsic visual property | The standard does not prescribe a specific design/evaluation process | Acceptance names user, goal/task, environment, effectiveness/efficiency/satisfaction outcome, and limits |
| HCD-03 | Informative guidance — [GOV.UK, Learning about users and their needs](https://www.gov.uk/service-manual/user-research/start-by-learning-user-needs) | Base user needs on evidence from actual/likely users and keep validating across delivery stages | Government-service practice, not a universal regulatory standard; stakeholder opinions remain assumptions until researched | Source of each user need is named; solution wording is not substituted for the underlying need |

Design implication: start with a context brief and phrase the first design as a testable hypothesis. “Best design” without users, task, environment, and evidence is overclaimed.

### Heuristic review

| ID | Class and source | Supported use | Boundary | Observable check |
| --- | --- | --- | --- | --- |
| HEU-01 | Contextual empirical — [Nielsen & Molich 1990, Heuristic evaluation of user interfaces](https://doi.org/10.1145/97243.97281) | Broad heuristics can identify candidate usability problems early and multiple evaluators improve coverage | An evaluator's findings are not a complete problem inventory or user-task acceptance evidence | Findings state observed surface, violated heuristic, user consequence, severity basis, and evidence needed to confirm |
| HEU-02 | Informative guidance — [Nielsen Norman Group, 10 Usability Heuristics](https://www.nngroup.com/articles/ten-usability-heuristics/) | Review status visibility, real-world match, control, consistency, prevention, recognition, flexibility, restraint, recovery and help | The source calls them broad rules of thumb; they are not detailed interface standards | Use them to create risk hypotheses, then close important findings with runtime/task evidence |

Heuristic review is risk discovery, not acceptance proof. One Agent review cannot prove usability, accessibility, or launch readiness.

### Cognition, signifiers, and choice

| ID | Class and source | Supported use | Boundary | Observable check |
| --- | --- | --- | --- | --- |
| COG-01 | Contextual empirical — [Sweller 1988, Cognitive Load During Problem Solving](https://doi.org/10.1207/s15516709cog1202_4) | Means–ends search can consume processing capacity that would otherwise support learning/schema acquisition | The study concerns learning and problem solving. It does not prove a universal “chunk every UI” rule or a fixed item count | Identify the exact hidden-context recall, cross-step search, task switching, or means–ends burden; compare task errors/time/hesitation after the change |
| COG-02 | Conceptual framing — [Norman 2008, Signifiers, not affordances](https://jnd.org/signifiers-not-affordances/) | Provide perceivable cues for what an element/state means, what action is possible, and what is happening | This is a conceptual distinction, not a controlled UI-effect estimate. A signifier can be conventional or unreliable; recognition does not justify displaying every option | Check signifier → action → feedback mapping with new and experienced users; remove ambiguous or misleading cues |

Design implication: reduce a named burden. Examples include keeping current object/state visible, preserving return context, narrowing active choices for the current decision, and exposing advanced controls when relevant. Do not use “lower cognitive load” as an acceptance criterion without an observable task effect.

### Accessibility and inclusive evaluation

| ID | Class and source | Supported use | Boundary | Observable check |
| --- | --- | --- | --- | --- |
| A11Y-01 | Standard — [WCAG 2.2](https://www.w3.org/TR/WCAG22/) | Apply testable web-content success criteria for perceivable, operable, understandable and robust content | WCAG does not address every disability need; a conformance claim must follow its scope and complete-process rules | Map applicable criteria to automated and manual checks, target pages/processes, technologies, versions and known gaps |
| A11Y-02 | Informative guidance — [W3C, Involving Users in Evaluating Web Accessibility](https://www.w3.org/WAI/test-evaluate/involving-users/) | Combine standards evaluation with disabled-user evaluation to find issues either method can miss | One participant does not represent all users; user evaluation alone cannot determine accessibility conformance | Record participant characteristics, task/protocol, assistive technology, scope, findings, limits and standards checks |
| A11Y-03 | Informative guidance — [ARIA Authoring Practices Guide introduction](https://www.w3.org/WAI/ARIA/apg/about/introduction/) | Use common role/state/keyboard patterns as implementation references for rich web widgets | APG explicitly is not a complete design system or production-ready code; examples may omit localization and platform robustness | Verify normative ARIA/HTML requirements, browser/AT behavior, keyboard/focus, localization and production constraints |
| A11Y-04 | Standard — [WCAG 2.2 SC 2.5.8, Target Size Minimum](https://www.w3.org/TR/WCAG22/#target-size-minimum); informative explanation — [Understanding SC 2.5.8](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum) | For Web Level AA, pointer targets are at least 24×24 CSS px or meet a named exception such as spacing/equivalent/inline/user-agent/essential | The Understanding document is informative; the criterion is Web-scoped and allows explicit exceptions. It is not the Apple/Android platform target | Measure target geometry/spacing at relevant zoom and pointer modes; record the exception when used |
| A11Y-05 | Vendor convention — [Android, Make apps more accessible](https://developer.android.com/guide/topics/ui/accessibility/apps) | Android recommends at least 48×48dp focusable/touch targets for touch interfaces and tests semantics with manual/automated tools | Precise mouse/trackpad input may use smaller targets; this is Android guidance, not a cross-platform constant | Measure the actual touch/focusable region, not only the icon; test touch, accessibility service output and custom components |
| A11Y-06 | Vendor convention — [Apple Human Interface Guidelines, Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons) | Apple states as a general rule that a button needs a hit region of at least 44×44pt; visionOS uses 60×60pt | This is first-party Apple-platform guidance for button hit regions, not a universal touch-target constant or evidence that every control is usable | Measure the actual hit region separately from the glyph on each target Apple platform; retain the platform/input context and verify selection with the intended input modes |
| A11Y-07 | Standard — [WCAG 2.2 SC 4.1.2, Name, Role, Value](https://www.w3.org/TR/WCAG22/#name-role-value) and [SC 2.5.3, Label in Name](https://www.w3.org/TR/WCAG22/#label-in-name) | For Web, every user-interface component covered by SC 4.1.2 exposes a programmatically determinable name and role; when a visible text label exists, SC 2.5.3 requires the accessible name to contain that text | A visible label is not sufficient unless the target technology exposes it through the accessible-name computation. These criteria do not require a visible label for every control or define native-platform semantics | Inspect the accessibility tree/name computation and role/state/value; test visible-label speech input and browser/assistive-technology output |
| A11Y-08 | Standard — [WCAG 2.2 SC 1.4.3, Contrast Minimum](https://www.w3.org/TR/WCAG22/#contrast-minimum) and [SC 1.4.11, Non-text Contrast](https://www.w3.org/TR/WCAG22/#non-text-contrast) | For scoped Web Level AA, text and images of text meet 4.5:1; large-scale text (at least 18pt regular or 14pt bold, or an equivalent relative size) meets 3:1, while visual information required to identify UI components/states and graphical objects meets 3:1 | SC 1.4.3 retains incidental-text and logotype exceptions. SC 1.4.11 retains inactive/user-agent component and essential-graphic exceptions; neither criterion makes every pixel or decorative graphic subject to 3:1 | Measure rendered foreground/background or adjacent colors in the applicable states and retain the criterion, large-text basis and any named exception in the result |
| A11Y-09 | Vendor convention — [Apple Human Interface Guidelines, Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) | Apple says that, in general, about 12pt of padding around elements with a bezel and about 24pt around the visible edges of bezel-less elements works well to reduce accidental selection | This is approximate Apple-platform spacing guidance, not a minimum target size, a universal inter-control distance, or an unconditional acceptance threshold | Measure the rendered target and surrounding spacing separately on each target Apple platform, then exercise adjacent controls with the intended input modes and record exceptions or mis-selections |

Do not collapse accessibility into color contrast. Include semantics/name-role-value, keyboard/focus, pointer/touch, reflow/text scale, error identification and suggestion, status messages, motion, authentication, and complete task processes as applicable.

### Responsive and adaptive layout

| ID | Class and source | Supported use | Boundary | Observable check |
| --- | --- | --- | --- | --- |
| RESP-01 | Specification or draft — [Media Queries Level 5](https://www.w3.org/TR/mediaqueries-5/) | Adapt to observable environment features such as viewport, input, display and user preferences; re-evaluate when environment changes | Retain the source's publication status and check target-browser support. Media queries test environment/device aspects, not component content; device categories alone are insufficient | Resize/orient/change preferences at runtime; test intermediate values, input changes and text zoom, not only named devices |
| RESP-02 | Specification or draft — [CSS Containment Level 3, Container Queries](https://www.w3.org/TR/css-contain-3/#container-queries) | Adapt a component to its query container when local available space differs from viewport space | Retain the source's publication status and check target-browser support. The spec defines mechanisms, not which breakpoints or visual composition are good | Test component instances in narrow/wide containers, nested contexts, long content and dynamic resize |
| RESP-03 | Vendor convention — [Android, Window size classes](https://developer.android.com/develop/adaptive-apps/guides/use-window-size-classes) | Use actual app-window space to select adaptive layouts | Android describes its thresholds as opinionated platform guidance; a window class is not a physical-device identity | Test resizable windows, split screen, orientation and posture transitions; choose layout changes from content/task constraints |

Breakpoints are implementation decisions derived from content, available space, input and state transitions. “Desktop/tablet/mobile” screenshots alone do not prove adaptation.

### Motion and feedback

| ID | Class and source | Supported use | Boundary | Observable check |
| --- | --- | --- | --- | --- |
| MOT-01 | Contextual empirical — [Tversky, Morrison & Bétrancourt 2002, Animation: can it facilitate?](https://doi.org/10.1006/ijhc.2002.1017) | Match graphic form to the concept and use interaction to help users apprehend change over time | Comparable animations were not generally superior to static graphics; complexity and speed can make them harder to perceive | State the animation's information job, compare an equivalent static/reduced-motion form, and test comprehension/control |
| MOT-02 | Specification or draft — [Media Queries Level 5, `prefers-reduced-motion`](https://www.w3.org/TR/mediaqueries-5/#prefers-reduced-motion) | Detect a user's request to minimize non-essential motion | Retain the source's publication status and check target-browser support. The preference does not mean remove state feedback or all animation | For each motion, name purpose and essential/decorative status; verify reduced-motion output retains state/causal information |
| MOT-03 | Standard — [WCAG 2.2 SC 2.3.3, Animation from Interactions](https://www.w3.org/TR/WCAG22/#animation-from-interactions); informative explanation — [Understanding SC 2.3.3](https://www.w3.org/WAI/WCAG22/Understanding/animation-from-interactions) | For Web Level AAA, provide a way to disable non-essential motion animation triggered by interaction | The Understanding page is informative. This Web Level AAA criterion is not a universal duration/SLO or cross-platform rule | Exercise triggering interactions with the preference/setting and verify equivalent non-motion feedback |

Model feedback as `event → acknowledged/pending → success/failure/partial/unknown → recovery`. A remembered “0.1/1/10 second” heuristic is not a service SLO or universal acceptance threshold.

### Error prevention and recovery

| ID | Class and source | Supported use | Boundary | Observable check |
| --- | --- | --- | --- | --- |
| ERR-01 | Standard — [WCAG 2.2 SC 3.3.4](https://www.w3.org/TR/WCAG22/#error-prevention-legal-financial-data); informative explanation — [Understanding SC 3.3.4](https://www.w3.org/WAI/WCAG22/Understanding/error-prevention-legal-financial-data) | For covered high-consequence submissions, make changes reversible, checked/correctable, or reviewable/confirmable | The Understanding page is informative. The criterion does not require confirmation for every save or routine edit | Classify consequence; verify the selected reversible/check/review mechanism and recovery path |
| ERR-02 | Standard — [WCAG 2.2 SC 3.3.3](https://www.w3.org/TR/WCAG22/#error-suggestion) and [SC 4.1.3](https://www.w3.org/TR/WCAG22/#status-messages); informative explanations — [Error Suggestion](https://www.w3.org/WAI/WCAG22/Understanding/error-suggestion.html) and [Status Messages](https://www.w3.org/WAI/WCAG22/Understanding/status-messages.html) | Identify errors and suggestions when known; expose status without unnecessary focus movement | The Understanding pages are informative. Suggestions can be inappropriate when they would compromise purpose/security; status semantics do not prescribe one visual carrier | Test local error association, repair guidance, retained input, assistive announcement, focus and retry/restore outcome |

Select constraint, inline validation, preview, undo, confirmation, retry or restore from consequence and reversibility. Confirmation everywhere creates friction and habituation; transient toasts are insufficient for errors users must act on.

### Design systems and executable claims

| ID | Class and source | Supported use | Boundary | Observable check |
| --- | --- | --- | --- | --- |
| DS-01 | Community Group report — [Design Tokens Format Module 2025.10](https://www.w3.org/community/reports/design-tokens/CG-FINAL-format-20251028/) | Exchange typed token values, groups, aliases, deprecation metadata and extensions across tools | The report explicitly is not a W3C Standard or Standards Track deliverable and does not define visual quality, semantic naming, governance or runtime correctness | Validate format/alias resolution, then render representative components across themes/platforms and inspect contrast/state drift |
| DS-02 | Informative guidance — [GOV.UK Design System contribution criteria](https://design-system.service.gov.uk/community/contribution-criteria/) | Reusable patterns need an evidenced user need, broad usefulness, quality, documentation and maintenance | A mature component still needs target-service validation; contribution rules are not universal regulation | Record purpose, states, accessibility/research evidence, implementation mapping, version/owner and current-context test |

A token file is not a design system. A story is not an executed test. A component-library dependency is not accessibility proof. Encode stable invariants in semantic APIs/types/tests and verify representative rendered states.

### Usability and acceptance evidence

| ID | Class and source | Supported use | Boundary | Observable check |
| --- | --- | --- | --- | --- |
| EVAL-01 | Informative guidance — [GOV.UK, Moderated usability testing](https://www.gov.uk/service-manual/user-research/using-moderated-usability-testing) | Observe actual/likely users attempting credible, goal-based tasks; agree questions, users and target areas first | Think-aloud and moderated protocols can affect behavior; findings depend on participants/tasks/prototype fidelity | Record research question, participant criteria, neutral task, expected outcome, observations, errors, help, completion and limits |
| EVAL-02 | Contextual empirical — [Faulkner 2003, Beyond the five-user assumption](https://doi.org/10.3758/BF03195514) | Choose sample size from study risk and problem variability instead of a fixed folklore number | In this 60-person study, random groups of five found 55%–99% of known issues; the exact range does not transfer to every product | Predeclare purpose and stopping rule; report sample, task coverage, issue yield/severity and what the study cannot generalize |
| EVAL-03 | Informative guidance — [WCAG-EM](https://www.w3.org/WAI/test-evaluate/conformance/wcag-em/) | Structure a scoped website accessibility conformance evaluation | Sampling/method execution must match the claim; it does not establish general usability | Identify scope, complete processes, representative pages/states, technologies, evaluation methods and result limitations |

Evidence types answer different claims: source/intent, static implementation, automated acceptance, rendered/device runtime, representative task/user, and production outcome. Select every dimension required by the claim; there is no globally highest rung. Later field evidence may strengthen its own outcome claim, but it cannot discharge independent standards-conformance, automated-oracle, runtime-state, or user-task obligations. Do not let a heuristic review, linter, screenshot, or single user opinion stand in for a claim it does not establish.

## Platform convention use

Platform guidance is an adapter, not shared theory:

- Web uses WCAG and web-platform specifications for conformance claims, plus target browser/assistive-technology evidence.
- Apple-platform work uses the current Apple Human Interface Guidelines and platform APIs; preserve whether a statement is a requirement, general rule, or recommendation.
- Android work uses current Android/Material guidance and runtime APIs.
- Mini-programs use the target host's current conventions and capability/permission model.
- Terminal/TUI work uses terminal geometry, input, color/fallback, selection/copy, scrollback and real-PTY evidence.
- Windows/Linux native desktop, Electron, TV, and any other rendered client use their current first-party platform guidance plus the installed client owner; when no owner is installed, use the fail-closed project-convention lookup in `delivery-contract.md`. An embedded renderer and its shell remain separate owner/evidence members.

When two platforms give different numbers or behavior, keep both platform-scoped. Do not average them into a “universal” rule.

For cross-platform criteria, use one row per target for native units and target
geometry/spacing, text scale, size/orientation extremes, input and
assistive-technology traversal, motion, and contrast/state cues. Mark `not
applicable` with a reason; one platform never proves another.

## Maintenance rules

1. Add or change a blocking claim only with an exact named source, direct URL, scope, authority class, observable check, and verification date.
2. Preserve normative strength. Recommendation/“consider” language cannot become an unconditional failure without an independently owned product rule.
3. If a source is unreachable, follow blocked-source remediation; do not reconstruct precise wording or numbers from memory.
4. Mark local observations and aesthetic preferences as local heuristics. Promote them only after target evidence and independent review.
5. Recheck version-sensitive platform and performance claims at use time. Stable theory still retains its original population/task boundary.
