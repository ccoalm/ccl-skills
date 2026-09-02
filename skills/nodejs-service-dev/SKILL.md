---
name: nodejs-service-dev
description: Use when implementing, modifying, scaffolding, or testing Node.js backend and service code, including HTTP/RPC handlers, workers, jobs, standalone Node.js CLI/tooling, runtime configuration, TypeScript/JavaScript module setup, async cancellation, streams, graceful shutdown, and Node-specific test mechanics. Triggers include "用 Node.js 写接口", "Node 后端实现", "用 Node.js 写个命令行工具", "重构 Node 服务里的某文件/某类(局部)", "refactor a file/class within a Node.js service", "Fastify/Express/NestJS 服务", "node:test 怎么写", and "event loop / worker_threads 怎么改". Route active failures to defect-diagnosis, test-layer choices to testing-strategy, terminal contracts to terminal-cli-dev, and cross-module architecture or multi-stage delivery to product-rd-workflow.
---

# Node.js Service Development

## Skill Routing

- Use this skill for Node.js service implementation: handlers, middleware, adapters, workers, jobs, clients, runtime/toolchain mechanics, and focused tests.
- New capabilities, cross-module architecture, service redesigns, and multi-stage refactors enter `product-rd-workflow`; verified repairs return here after `defect-diagnosis`.
- `testing-strategy` chooses test layers, coverage policy, contract/E2E scope, and CI gates. This skill owns Node runner, mock, fixture, and command mechanics after that choice.
- Standalone CLI/tooling stays here; language-stack CLI implementation must not be routed back to `terminal-cli-dev`, owner of the interface contract; logs/metrics/traces to `platform-observability`; cross-service timeout/retry/mTLS to `platform-service-connectivity`; rollout/rollback to `platform-release-engineering`.
- Browser UI goes to `web-react-dev`; LLM/RAG/agent-runtime behavior to `llm-inference-integration`. Keep language-neutral rules in their existing owner.
- Architecture, service-boundary, and data-ownership decisions have no Node architecture sibling skill by decision: they run through `product-rd-workflow`'s architecture gate plus the relevant `platform-*` owners, and this skill owns the Node-side implementation contract. Do not borrow the Go or Python architecture skill for a Node.js service.
- The runtime contract here is Node.js. Bun and Deno share much of this service shape, but their runtime, package, permission, and built-in-API semantics differ and are not verified against this skill's sources: reuse the boundary and lifecycle rules, confirm every runtime-specific claim against that runtime's own documentation, and treat a deliberate migration as a `product-rd-workflow` decision rather than a drop-in swap.

## Generalization Discipline

- Implement the repository in front of you; do not lift product nouns, service names, package paths, or organization-specific habits from a prior codebase into a reusable rule.
- When adding or revising durable Node.js guidance, place it deliberately. A rule that depends on Node runtime or toolchain mechanics — module resolution, TypeScript execution, event loop, streams, `worker_threads`, package-manager state — stays here. Generic backend service practice belongs in the shared workflow, testing, or architecture owner; a lesson that also holds for a sibling stack updates `go-microservice-dev` or `python-service-dev` in the same landing instead of living only here.
- The duty runs inward too: a generic backend rule already landed in a sibling stack skill applies here unless Node runtime semantics make it wrong. Record the per-sibling decision — `update`, `unchanged`, or `route-to-shared` — rather than leaving the sibling unexamined.

## Workflow

### 1. Recover the contract

Read the nearest `AGENTS.md`, then inspect `package.json`, lockfile/package-manager metadata, runtime-version files, `tsconfig*.json`/`jsconfig.json`, build/test scripts, deployment manifests, and the smallest relevant source path. Record:

- supported and deployed Node.js line;
- package manager and authoritative lockfile;
- ESM/CommonJS and JS/TS execution plus type-check path;
- framework lifecycle, verification commands, changed external contract, and non-goals.

Preserve those choices unless migration is explicit. Read [runtime-and-project-contract.md](references/runtime-and-project-contract.md) when changing one.

### 2. Define and implement the narrow boundary

State input, output, error, cancellation, timeout, idempotency, and ownership before code. Preserve established contracts unless explicitly changed; validate untrusted data at the owning boundary.

- Keep event-loop callbacks and worker-pool tasks short; bound fan-out, queues, retries, payloads, and buffering.
- Propagate cancellation/deadlines to underlying work. A wrapper timeout that leaves work running is not cancellation.
- Use streams with backpressure for large/unbounded data. Use a bounded `worker_threads` pool only for measured CPU-intensive JavaScript, not ordinary async I/O.
- Preserve error causes and map once at the boundary. Do not swallow rejections or resume normal operation after an unknown fatal process error.
- Carry request context (correlation, tenant, deadline) in `AsyncLocalStorage` established at the owning boundary, not through every signature or a process-wide mutable. Pick the no-context behavior by what the value authorizes: a diagnostic value may declare a default, but a security-bearing one must fail the operation closed.
- Treat the outbound HTTP client as a bounded resource: its pool is unbounded by default, its timeouts are layered rather than an overall deadline, and an unconsumed response body holds its connection.

Read [async-lifecycle-and-performance.md](references/async-lifecycle-and-performance.md) when touching concurrency, request context, outbound clients, streams, CPU work, shutdown, or performance.

### 3. Make lifecycle and exposure explicit

Validate configuration before traffic and never log secrets. On shutdown, stop intake, drain bounded work, abort owned background work, close resources, and honor one documented deadline; handle upgraded connections separately. Treat readiness and liveness as different contracts.

Keep dependency changes minimal, update the lockfile, use frozen/immutable install verification, and review scripts/transitive impact. Bound input work and treat the Node.js Permission Model as optional defense in depth, never a complete sandbox. Read [verification-diagnostics-and-security.md](references/verification-diagnostics-and-security.md) for concrete test, diagnostic, dependency, and security checks.

### 4. Verify narrow to broad

Use repository commands: focused behavior and failure-path test → touched-package lint/type/check → package/service suite → build/package/start check → required repo gates. Exercise cancellation, malformed input, cleanup, and shutdown when relevant.

Performance/reliability claims require a representative workload plus outcome and causal evidence. Re-run the reproducer; inspection alone cannot prove a leak, stall, or regression fixed.

## Hard Rules

- Preserve module convention and make new package intent explicit; do not rely on ambiguous `.js` syntax detection.
- Built-in TypeScript stripping is execution support, not type checking or general transpilation. Keep a real type-check gate and verify unsupported syntax/`tsconfig` dependencies.
- Prefer explicit dependencies and startup wiring over mutable process-wide singletons so tests need not bind ports or mutate globals.
- Avoid unbounded `Promise.all`, ownerless fire-and-forget promises, synchronous hot-path APIs, per-request workers/processes, and whole-stream buffering by default.
- Do not add blanket retries, speculative caches, generic base layers, or process-level exception recovery without observed need and an owning contract.

## Output Contract

Report the runtime/package/module contract, changed behavior, preserved boundaries, exact checks, measurements, skips, version assumptions, and risks.

Technical claims and comparison limits are recorded in [source-map.md](references/source-map.md); ordinary implementation should load only the task reference whose decision surface is reached.
