# Product R&D Source Evidence Map

Internal provenance only. Use this when auditing or re-extracting the top-level product R&D workflow.

## Source Coverage

| Dimension | Sources inspected | Useful extraction | Decision |
| --- | --- | --- | --- |
| Design sources | Batch Figma reads across web shell, mobile app, creation, analytics, review, scan/upload, assignment, resource library, resource center, object/config management, and design systems | Product workflow must require design readiness for human-facing surfaces before implementation, including states, density, trust, and rendered acceptance | Keep routing/gate only; design details stay in design skill |
| Web/client code | Batch manifests and representative package scripts across Umi/React, Vite React, Vue, admin, H5, document/media, and operations apps | Product workflow must route web/app implementation separately and require rendered evidence, not only code/build success | Keep |
| Backend code | Go/Python service inventories, Makefiles, service manifests, tests, integration scripts, generated contracts | Product workflow must route architecture before code when contracts, runtime, source-of-truth, auth, async, or release surfaces change | Keep |
| High-risk backend review samples | Targeted local review of quota/accounting/audit/worker patterns and defect-review notes in high-risk service samples | Good patterns: durable idempotency, trace/request correlation, worker status, stale counters, admin repair states, contract tests. Bad patterns to guard against: default-context fallback on missing scope, Redis/TTL-only dedupe for durable side effects, mutation committed before audit/outbox evidence, and repair flows without visible stale/pending evidence | Merge into high-risk resilience gates and backend/testing skills; do not copy product nouns or paths into executable guidance |
| Mature service and frontend samples | Broad inventory plus representative source reads from a mature multi-service and interaction-heavy frontend workspace | Useful mechanisms: gateway/RPC/worker/service-package classification, handler/logic/service/infra layering, generated contract ownership, Wire/codegen gates, structured config, trace/log context propagation, DB/MQ lifecycle, route/layout/workbench separation, API wrappers, table/filter/bulk patterns, upload/scan/long-task state, chart/canvas lifecycle, H5 gesture/WebView constraints | Keep mechanics; route stack details to Go/Python/Web/App/testing/design skills; discard source-domain vocabulary |
| Current source-register pass | New-product skill-suite register, frontend/app subagent review, Go subagent review, local Python/AI runtime reads, and selected direct file reads | Corrected coverage and source-quality discipline: package/module inventory is not line-level completion; primary Go modules count is 78 plus one downgraded demo/test module; strong frontend/app sources are modern React workbench/H5/admin projects; Python evidence supports microservice/runtime wiring but still has broader read gaps | Keep as extraction-control evidence; route concrete rules to target skills |
| Testing topology | Go/Python/Web/App tests, markers, Playwright/Vitest, integration scripts, structure checks, CI-like commands | Product workflow must use testing strategy for layer selection and require evidence matched to risk | Keep |
| Skill extraction corrections | Repeated user corrections about shallow extraction, source-depth overstatement, and missing RCA | Product workflow should route durable learning through `skill-extraction-workflow` and not bury extraction method in product docs | Keep |

## Keep / Merge / Discard

- Keep: product R&D is the top-level router and gate owner, not the owner of stack-specific implementation details.
- Keep: human-facing surfaces need design checkpoint and rendered inspection; backend/runtime surfaces need architecture gate and risk-matched verification.
- Keep: when extracting from an old or different-domain product, require mechanism/business/source-quality separation before product planning or skills reuse.
- Merge: testing, design, web/app, Go, Python, and extraction skills through explicit routing.
- Route: all source-derived skill changes to `skill-extraction-workflow`; UI details to design; implementation to stack skills.
- Discard: business-domain structure, source repo names, old product IA, and any one-off local tool habit that is not a general lifecycle gate.

Coverage label: broad cross-source workflow extraction, not node-by-node product/code inventory.

Latest high-risk resilience pass label: targeted code-and-review extraction from local high-risk service samples, not full repository inventory.

Latest mature-workspace pass label: representative broad extraction across service, frontend, and Figma-indexed design sources; not a node-by-node inventory of every source file.
