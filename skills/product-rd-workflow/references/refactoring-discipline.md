# Refactoring Discipline

Use this when improving code structure, splitting responsibilities, reducing duplication, changing data shapes, or cleaning technical debt without intending to change product behavior.

## Rules

- Keep behavior-preserving refactors separate from feature changes and bug fixes unless the user explicitly accepts the combined risk.
- Establish a green baseline first: run the smallest relevant tests or record why the current baseline is already failing.
- Refactor in small steps. Each step should be reviewable and, when practical, independently testable.
- Search all call sites before changing public functions, DTOs, generated contracts, config keys, storage fields, events, or exported helpers.
- Preserve external behavior, response shape, errors, telemetry, permissions, and side effects unless the change is intentional and documented.
- Do not broaden a refactor while debugging an unknown defect; use `defect-diagnosis` first.

## Impact Analysis

Before changing a shared shape or function, identify:

- direct callers and generated callers.
- tests, fixtures, mocks, and fakes.
- API/RPC/protobuf/OpenAPI/Pydantic/DDL/config/event contracts.
- persisted historical data, cached values, queued messages, and replay/backfill inputs.
- observability and dashboards that depend on names, status, or error codes.

## Data Shape Changes

- Prefer additive, compatible changes first.
- Keep old readers/writers working until migrated.
- Treat shipped or externally consumed API/RPC/event/config/response contracts as compatible-by-default. Do not remove, rename, repurpose, or stop accepting existing fields/codes/semantics unless a human explicitly approves a breaking change after seeing a risk assessment.
- A breaking-change risk assessment must name consumers, rollout order, compatibility window, migration or dual-read/dual-write plan, monitoring, rollback path, user/customer impact, and the tests or replay evidence that prove the cutover is safe.
- If the user asks to remove compatibility for a contract that may already be live, first clarify or verify launch status. If launch status is unknown, assume live for compatibility planning and present the breaking-change risk before implementing.
- Decide which fields are immutable, preserved, recalculated, or backfilled.
- Include rollback behavior for schema, generated code, dynamic config, and data migration.

## Verification

- Run focused tests before and after when feasible.
- Add characterization tests before risky legacy refactors.
- When the behavior to lock is unreachable by the current test harness (library-private, or entangled with native / platform / UI machinery), the "characterization tests before risky legacy refactors" rule needs a narrow, explicit exception: introduce the smallest behavior-preserving testability boundary first — extract the pure logic, pass an existing dependency / clock / client in as an argument, or wrap the native/UI boundary behind an interface, then write the characterization test before the risky refactor continues. That pre-test boundary change is not free protection: keep it reviewably mechanical and guard it with the strongest *practical* before/after evidence available (existing tests, compiler/static checks, golden output, or a recorded before/after trace); if no meaningful check exists, say so and do not call the result test-protected. Do not expose secrets, auth/permission decisions, privileged internals, or unsafe native/platform handles just to test them — prefer same-package/in-module tests, a narrow adapter, or an interface; widen a visible boundary only when it is independently a defensible product/code boundary.
- For shared contracts, run contract/codegen checks and affected integration tests.
- Prove a "zero behavior change" claim with a deterministic anchor, not a verbal assertion: a conformance digest, golden output, or differential test whose result stays identical across the whole refactor. For multi-step refactors, run the anchor and the relevant suite green at every step, not only at the end — a step that cannot be proven green is where the drift hides.
- When retiring an old path in stages, keep a thin compatibility shim until every caller is migrated, so deleting the old symbol fails at compile/build time for any missed call site instead of changing behavior silently.
- Review diffs for behavior drift, not just formatting or decomposition.

## Module Depth & Tactical-vs-Strategic（Ousterhout *A Philosophy of Software Design* 2018）

判断"是否值得 refactor"的设计原则：

- **Deep module** = 简单 interface 包覆较深功能（high benefit / low cost — abstraction 是负担抵不过省的心智）。**Shallow module** = interface 与 implementation 几乎同体量（abstraction 几乎无收益，只是包了一层）。指标：interface 字段 / 方法数 vs internal 行数；前者远小于后者 = deep；接近 = shallow
- **Refactor 优先吃 shallow module**：合并到调用方或重设计 interface 让它变 deep；不要为复用而抽 shallow module
- **Tactical 编程**（快速 patch + 局部最优 + 持续 hack）vs **Strategic 编程**（每改动留代码比改动前更好 — investing-in-design）：tactical debt 累计后只能 strategic 还。Refactor 是 strategic 模式的工具
- **Red flags**（Ousterhout-aligned design 反信号；命中 → 是 refactor 候选 — 本 ref 选用 5 个常见 + 本地补充 generic name 例）：information leakage（多模块知同一秘密）、temporal decomposition（按时间步拆模块而非按概念）、overexposure（接口暴露过多 implementation 细节）、pass-through method（只转手调用无实质，应消除中间层）、vague / generic name（本地补充：`Util` / `Helper` / `Manager` 模糊责任）
- **不仅因"代码看着不爽" refactor**：每次 refactor 必指出对应的具体动因 — 团队 convention 对齐 / cognitive load 降低 / 命中 red flag / shallow module / 测试可达性等可表述的影响；纯主观"不优雅"不接受作单独理由
