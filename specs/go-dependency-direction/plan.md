# Make the Go dependency-direction diagram show import direction

The Dependency Direction diagram in the Go architecture playbook draws
`domain -> infrastructure adapters`. The sentence above it says adapters sit
behind interfaces the inner layers own, and a later section of the same file
says adapters import the core and never the reverse. Read as an import
diagram, the arrow tells an agent to make the domain package import a database
adapter. This round redraws the diagram so import direction and run-time call
order are shown separately. The task result it improves: Go service designs
and scaffolds that keep the domain free of infrastructure imports.

## Charter

| Field | Decision |
| --- | --- |
| Purpose | Stop the diagram from recommending an inward-to-outward import that the surrounding text forbids. |
| Scope | In: the Dependency Direction diagram and one explanatory paragraph in `skills/go-microservice-architecture/references/architecture-playbook.md`. Out: the rules list under it, the Python sibling, the entrypoint, and the separately planned merge of the two stack architecture skills. Not an iterative program; no watermark. |
| Depth | Targeted check: one diagram against the text of its own file. |
| Result classification | Failure/correction. Observation: the diagram and the prose of the same section disagree, and a forced-choice probe on the base text answers that the domain imports the adapter (see `evidence/validation.md`). |
| Matching analysis | Contributing factors: (1) one arrow notation used for run-time flow in a section titled for dependency direction; (2) no check compares a diagram with its section's rules; (3) the Python sibling states the same idea in prose only, so the parity review between the two files had nothing to compare the Go diagram against. Counterfactual: with the arrow reversed or labeled, the probe answer changes; that is tested. Prevention is the corrected text plus a pinned assertion that the misleading arrow does not return. A general diagram-versus-prose checker is not built: one instance does not justify it. |
| Failure mode or success boundary | A weak fix would reverse the arrow and lose the run-time picture, or forbid the application layer from importing a simple adapter, which the second rule in that list allows. |
| Lifecycle impact | Architecture design and Go implementation scaffolding. Testing, release, onboarding: unchanged. Use without source access: the playbook is the source. |
| Evidence plan | The playbook section and the adapter-family section of the same file; the Python sibling's Layering Depth section; `go-microservice-dev` references that state the import rule. External grounding: none added; the section already links its ports-and-adapters source and this round changes no attribution. |
| Completion standard | Probe red on the base text and green on the candidate; a regression assertion in the repository suite; `make test`, the heavy regression lane and the public-text check; one independent review and one adversarial challenge. |

## Target-output map

| Owner | Direction | Status | Changed file or reason |
| --- | --- | --- | --- |
| `go-microservice-architecture` | self | updated | `references/architecture-playbook.md`, Dependency Direction diagram and paragraph |
| `python-service-architecture` | sibling | unchanged | Its Layering Depth section has no diagram and already says infrastructure modules are the adapters hidden behind the application-service layer |
| `go-microservice-dev` | downstream | unchanged | `engineering-patterns.md` already says the core domain must never import infrastructure |
| `nodejs-service-dev`, `python-service-dev` | sibling stacks | not-applicable | No copy of this diagram |
| `testing-strategy`, `product-rd-workflow`, `code-review` | lifecycle | unchanged | No rule about layer import direction lives there |
| `skill-extraction-workflow` | process | updated | A regression assertion for the diagram; the source-register row if the repository check asks for one |

Sibling mini-map: source stack Go; sibling Python `unchanged` (prose only, already correct); shared owner none today (the consolidation plan would give the rule one home).

Result of this round, provenance to target: the diagram defect → `architecture-playbook.md` section "Dependency Direction" → the `imports` and `calls` lines and the paragraph under them → acceptance by the probe and the regression assertion → `landed` once the checks in `evidence/validation.md` pass.
