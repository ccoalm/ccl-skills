# Structured TC Input Translation

Use this reference when the input is a set of structured test cases from `test-artifact-management` or a Feishu Bitable TC list. This is a **translation guide** from structured TC fields into test strategy, layer selection, implementation routing, TC metadata, and result handoff; after translation, run the standard `testing-strategy` workflow from Step 1.

The mapping is directional — not every TC becomes one automated test, and one TC may need assertions at multiple layers.

## Pre-check before translating

| TC 状态 | 处理方式 |
|---|---|
| `未测试` | default implementation candidate; proceed with translation |
| `通过` | decide whether to automate for regression fixation or leave as manual evidence; do not assume automation is required |
| `失败` | regression candidate; add or update at least one relevant test and run it RED before implementation, unless no harness can support it after normal remediation — in that case record the evidence gap and strongest alternate check |
| `阻塞` | record as `blocked`; name the environment or product gap; do not auto-implement until unblocked. **JUnit auto-mapping**: pytest `@skip(reason="…")` with environment keywords (`requires`/`needs`/`no driver`/`no device`/`service unavailable`/`credential`/`platform`/`linux`/`windows`/`darwin`/`fixture not ready`/`environment`) maps to 阻塞. |
| `跳过` | excluded from implementation queue; keep it in the coverage register with skip reason and source decision; do not delete or overwrite the Bitable record. **JUnit auto-mapping**: any other `<skipped>` reason (manual exclusion, deferred, deprecated feature) maps to 跳过. Use precise reason strings so the automation routes correctly. |
| `废弃` | excluded from implementation queue; grep the sidecar (`test/results/tc-map.jsonl`) and test source for this TC ID; for each linked test, check whether the underlying business code is still valid using the per-stack import-graph commands documented in the relevant dev skill's "废弃级联：业务代码是否仍在用" subsection (Python `grep import` / Go `go list` / Web `madge` / 小程序 madge+app.json / Flutter+native `dart analyze` + grep) — single grep on the test file is the FIRST step only; the second step is verifying whether OTHER product code still depends on what the test imports. If business code is removed/feature is gone, delete the test in the same commit; if code is still active, take no action by default. If a test's `tc(...)` call covers this TC ID plus other active TC IDs, remove the deprecated ID from the `tc(...)` argument list instead of deleting the whole test; tests without `tc(...)` calls are handled separately and are not part of this check |
| empty / unrecognized | blocks translation until status is normalized; do not infer as `未测试` |

Additional pre-checks:

- TC 优先级 (P0/P1/P2) is a business priority signal, not a final layer or CI gate assignment. P0 requires explicit proof of behavior or an explicit `blocked` / `gap` / `manual-only` decision with named owner, evidence artifact/location, and residual risk — it does not automatically mean automated test. Use risk, cross-boundary behavior, defect history, and assertion cost to determine the actual layer and gate.
- Verify TC ID uniqueness and field completeness before writing any test code.
- **Orphan detection (split responsibility).** `python gen_report.py --detect-orphans` covers ONLY tests that DO link to a TC ID: it surfaces (a) tests whose TC ID is marked `废弃` in Bitable, and (b) tests whose TC ID does not exist in Bitable at all. For each match, check if the underlying business code is still valid using the per-stack import-graph commands documented in the relevant dev skill; if code is removed, delete the test in the same commit; if code is still active, take no action by default. Tests WITHOUT any TC link (no `tc()` / `tc.Mark` / `@pytest.mark.tc` / `tcTest`) are NOT detected by this command — they are caught when the dev intentionally deletes business code and runs the per-stack "废弃级联：业务代码是否仍在用" workflow on the affected modules; that workflow prompts the user to decide on each unlinked test.

## Field mapping

Directional, not 1:1:

| TC 字段 | 测试设计参考 |
|---|---|
| 前置条件 | test setup — fixture data, dependency state, permission context, or environment dimension; may map to multiple setup steps across layers, not a single setup call |
| 操作步骤 | test body — what to render, call, interact with, or trigger |
| 预期结果 | assertion target — visible outcome, persisted state, emitted event, contract shape, or error |
| 优先级 | risk signal only; see pre-check above — do not map directly to a layer or gate |
| 测试层级 | primary proof layer requested by the TC author. Treat it as the default landing target, then verify it still matches the cheapest sufficient proof. If the field and risk analysis disagree, record the discrepancy and route it back to `test-artifact-management` for TC definition update instead of silently drifting. |
| 测试类型 | execution form / owning implementation surface. Use it to route the scenario to the right stack skill and runtime harness (`ui-automation`, `api-automation`, `device-automation`, `contract-validation`, `llm-eval`, `manual-verification`). |
| 模块 | test file grouping or suite name (use stack-specific naming convention) |
| 用例ID | passed to the per-stack `tc()` helper / `@pytest.mark.tc` / `tcTest` / `tc.Mark` at registration time, recorded in the sidecar `test/results/tc-map.jsonl` (NOT in the test function name — function names stay clean). See `test-artifact-management/references/tc-marker-conventions.md` |
| 状态 | see pre-check table above |

## Layer assignment rules

- One TC may need assertions at multiple layers (e.g. unit + contract + one E2E smoke for a P0 cross-boundary behavior); do not assume 1:1.
- Multiple TCs in the same module may merge into one scenario gate when they share setup and differ only in data dimension; when merging, the test register or coverage map must list all covered TC IDs (mandatory for Bitable fan-out); test name or inline comment is auxiliary only. Merged scenario results must be fanned out per TC ID: only update a TC's status when that TC's own expected result and assertion dimension are covered by the merged test.
- Do not assign layer by priority alone. A P2 TC that is cheap, stable, and regression-prone belongs in the fast gate; a P0 TC that requires a live service belongs in the integration or E2E gate.
- Apply the client API-backed surface split and scenario dimension rules from the Workflow section as usual.

## Execution-type routing rules

- `测试层级=e2e` + `测试类型=ui-automation` + web/admin frontend → route implementation to `web-react-dev`; if an in-app browser/runtime check is needed, use the browser capability the environment provides.
- `测试层级=e2e` + `测试类型=device-automation` + mini-program → route to `miniapp-product-dev`.
- `测试层级=e2e` + `测试类型=device-automation` + app/mobile → route to `app-cross-platform-dev`.
- `测试类型=api-automation` + Go service → route to `go-microservice-dev`; `platform-service-connectivity` stays the contract/connectivity owner when wire behavior or shared transport policy matters.
- `测试类型=api-automation` + Python service → route to `python-service-dev`; `platform-service-connectivity` stays the contract/connectivity owner when wire behavior or shared transport policy matters.
- `测试类型=contract-validation` → keep the main layer at `contract`; route schema/proto/GraphQL contract execution to the owning backend/client stack skill after this skill chooses the exact gate.
- `测试类型=llm-eval` → route model/replay/eval harness implementation to `llm-inference-integration`; do not reroute visible product-surface assertions that still belong to web/app/miniapp/client skills.
- `测试层级=manual` or `测试类型=manual-verification` → do not fake automation. Produce the strongest executable lower-layer evidence you can, then keep the user-visible/runtime proof as manual or `blocked` with owner and residual risk.

## Specialized TC routing

**AI/LLM-triggered preconditions** ("触发研报检索", "模型决定调用工具") cannot be reliably reproduced via live model calls; use recorded fixtures or controlled data for the product surface (UI states, fallback behavior, error paths, permission states). Route only LLM/agent/RAG eval, replay, model/provider/inference stream protocol finality, and inference-specific observability to `llm-inference-integration`; UI streaming display finality, reconnect visible state, and button recovery remain product surface tests handled here. Do not route the entire TC to `llm-inference-integration`.

**Non-functional TCs** (performance, security, accessibility, visual regression, migration): determine gate placement here using the Non-Functional And Specialized Testing section in the entrypoint and `non-functional-specialized-scenarios.md`, then route implementation detail to the relevant specialized skill.

## Handoff back to test-artifact-management

When automated test results are available, update the TC's 状态 and append a 信息流转 entry in Bitable. Status-only result updates are Bitable-only (local md does not need to sync). TC content changes (steps, expected results) or new regression cases discovered during implementation must go through `test-artifact-management` update sync to keep Bitable and local md consistent.
