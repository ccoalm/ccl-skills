# Async Execution Model

Use this when deciding sync vs async, concurrency, event loops, CPU/GPU work, and blocking dependency boundaries.

## Decisions

- Use async when the dominant work is non-blocking I/O and the dependency libraries are async-native.
- Keep synchronous stacks synchronous when async would only wrap blocking SDKs.
- Do not call blocking DB, HTTP, file, CPU, or GPU work directly inside async endpoints.
- Isolate blocking work with workers, process pools, thread pools, or `asyncio.to_thread` where appropriate.
- Bound concurrency with semaphores, queue limits, worker pool settings, and dependency-specific connection limits.

## Python-Specific Risks

- The GIL makes CPU-heavy concurrency different from lightweight I/O concurrency. Use process or native-extension strategies for CPU-bound work.
- `asyncio.gather` without limits can overload downstream systems.
- Cancellation and timeouts must be designed; a cancelled request should not leave orphaned jobs, leaked clients, or half-written state.
- Event-loop lifecycle and client cleanup belong to app lifespan/bootstrap, not module import.

## Structured Concurrency Principle

- **`asyncio.TaskGroup` (Python 3.11+) is the architecture default for fan-out concurrency** — supersedes `asyncio.gather` as the recommended primitive for any concurrent work where partial failure should cancel siblings. The architectural shift from `gather` to `TaskGroup` is the same shift Trio popularized as "structured concurrency": every concurrent task has a lexically-scoped lifetime, failures propagate as a unit (via `ExceptionGroup` + `except*` per PEP 654), and cancellation flows in a deterministic order. Reserve `gather(return_exceptions=True)` for the narrow case where partial success with independent siblings is the intended contract — every other use is technical debt waiting to leak.
- **Free-threading (PEP 703) changes the GIL assumption for new architecture decisions starting at Python 3.14**, where free-threading reached officially-supported Phase II status (per PEP 779) with the single-threaded penalty narrowed to ~5-10%. For services where parallel CPU work matters (in-process inference fan-out, parallel parsing, image/document processing) this is the first version where the "use a process pool to escape the GIL" decision becomes "use threads in a free-threaded build" — a meaningfully different architecture. The catch: C extensions must opt in (PEP 803 `abi3t`), and ecosystem maturity at 2025-2026 is uneven. Treat free-threading as an architecture option to consider deliberately, not the default; for pure I/O-bound services, the stock-GIL build remains correct.
- **`anyio` is the architecture choice for async code that should support both asyncio and Trio backends** — relevant when the service ships as a library consumed by both ecosystems or when the team values Trio's stronger structured-concurrency semantics. Pure-application services usually stay on asyncio directly (TaskGroup + timeout + ExceptionGroup); reach for anyio when the dual-backend requirement is real, not as a hedge.
