# Async, Lifecycle, and Performance

Use this reference when a change touches request concurrency, cancellation, streams, CPU work, background jobs, shutdown, or a performance claim.

## Classify the work first

| Work | Default execution | Main risk |
|---|---|---|
| Network and async file/database I/O | Native async API on the event loop | unbounded concurrency, missing timeout/cancellation, retained buffers |
| Short JavaScript transformation | Event-loop callback | input-dependent long task, excessive allocation |
| CPU-intensive JavaScript | Bounded `worker_threads` pool or external worker | worker creation/serialization overhead, queue growth, memory sharing |
| Blocking/native task using libuv pool | Async API, with measured pool pressure | worker-pool starvation across unrelated requests |
| Large or unbounded payload | Stream/pipeline with backpressure | full buffering, missing cleanup, partial output |

Node.js uses a small number of threads to serve many clients. A long callback reduces event-loop throughput; a long libuv task can starve the worker pool. Both can become denial-of-service paths when complexity or input size is attacker-controlled.

## Cancellation and deadlines

- Accept an owning cancellation/deadline signal at service boundaries and pass it through every supported downstream API.
- Prefer an existing `AbortSignal`; combine caller cancellation and timeout without losing the original reason when the supported runtime provides the needed API.
- A raced timeout that rejects while the database call, fetch, stream, worker, or child process continues is not cancellation. Close/destroy/abort the underlying resource or document why it cannot be stopped and bound the orphaned work.
- Remove listeners and timers during cleanup. Use `unref()` only when it matches lifecycle ownership; it is not a substitute for cancelling work.
- Retries must fit inside one overall deadline, use the connectivity owner's policy, and remain bounded. Never retry non-idempotent effects without an idempotency contract.

## Request context propagation

- Carry per-request context — correlation/trace ids, tenant, deadline, auth subject — in `AsyncLocalStorage` rather than threading it through every signature or parking it on a process-wide mutable. Prefer the built-in store over hand-rolled `async_hooks` context machinery: the custom form has to re-implement propagation across every async boundary and is where context silently vanishes.
- Establish the store once at the owning boundary (request/job/consumer entry) and read it inward. Outside an established context the read returns `undefined` — or the instance's configured default value, where the deployed runtime supports declaring one, which is a version-gated option to verify rather than assume. Either way, code that must also run without a request (startup, a shutdown drain, a background loop) needs an explicit branch or fallback, never a bare dereference of an absent context. Choose which by what the value authorizes: a correlation id may safely default, but a tenant, subject, or permission scope must make the operation fail closed when the context is missing. Declaring a default for those turns an absent context into work silently executed under the wrong identity — the store is a propagation mechanism, never the authorization decision.
- Propagation is not automatic across every boundary. The store stays coherent through asynchronous operations started inside the context, which is not the same as crossing an isolate or process edge: before relying on context inside a `worker_threads` worker or a child process, verify propagation there rather than assuming it, and pass the needed values explicitly across any edge you have not verified.
- What goes in the store is an implementation mechanic; which fields must exist and propagate is owned by `platform-observability`. Do not invent a field set here.

## Bounded concurrency

- Replace unbounded `Promise.all(items.map(...))` on variable-size input with a repository-standard limiter, queue, or batch window.
- Bound queue length as well as worker count. Define overload behavior: reject, shed, defer durably, or backpressure the producer.
- Track in-flight ownership so shutdown can await or abort it. A detached promise must have an explicit supervisor and error sink.
- Avoid per-request child processes or workers. If CPU offload is justified, measure task duration and transfer cost, then reuse a bounded pool.

## Outbound HTTP clients

- The process-wide dispatcher is a real contract, not a default to ignore. The built-in `fetch` routes through the globally configured dispatcher, so pooling, keep-alive, and timeout behavior for every outbound call are decided by that one object; set it deliberately at startup and treat replacing it as a service-wide change rather than a local one.
- **The defaults are unbounded where it matters.** The per-origin pool defaults to unlimited connections, and the number of distinct origins is unbounded unless capped, so an outbound burst is bounded only by whatever bounds the calling code carries. This is the bounded-concurrency rule above applied at the socket layer: bound connections per origin, and bound origins too when destinations are influenced by input.
- **Timeouts are layered, and none of them is an overall deadline.** Connect, response-headers, and response-body timeouts are separate settings; a request can stay within every one of them and still blow the caller's budget. The overall deadline comes from the caller's `AbortSignal` — per the cancellation rule above, a deadline not attached to the request is not a deadline.
- **An unconsumed response body holds its connection.** Consume or explicitly cancel the body even when only the status or headers were wanted; leaving it unread stalls the request and leaks the pooled connection. A happy-path test that never reads a body cannot see this, so exercise the discard path directly.
- Defaults and option names drift across runtime and client versions. Read the deployed version's own documentation and the repository's actual dispatcher wiring instead of assuming a number, and verify the pool/timeout settings a change depends on rather than restating them from memory.
- Retry, backoff, circuit breaking, mTLS, and cross-service timeout *policy* stay with `platform-service-connectivity`. This section owns only the Node-side client shape that implements whatever policy that owner sets.

## Streams and backpressure

- Prefer `node:stream/promises` `pipeline()` or an established equivalent so errors and teardown propagate across the chain.
- Respect `write()` backpressure/drain semantics and configure object/buffer high-water marks from measurement, not folklore.
- Set payload/record limits even when streaming. Streaming bounds memory growth; it does not bound total work.
- Propagate abort signals and verify cleanup on source error, transform error, destination error, client disconnect, and timeout.
- Do not mix flowing-mode event handlers and async iteration on the same readable unless the lifecycle is deliberately controlled.

## Errors and process lifecycle

- Catch errors at boundaries that can make a valid decision: translate, retry under policy, compensate, or fail the operation. Otherwise preserve `cause` and propagate.
- For durable/task state written by one operation, capture the clock once per transition (all timestamps the transition itself stamps come from a single `now`; domain-provided times are recorded as received, never re-stamped), and validate external-response structure (schema parse with a typed error path) before mapping — a malformed upstream payload must become a persisted failure transition carrying the canonical error (mirroring the go/python state-machine rendering), never a crash or a silently-defaulted field.
- Treat unknown `uncaughtException` and default-throw unhandled rejection paths as fatal. A handler is for synchronous cleanup/diagnostics before termination, not resuming normal operation from an undefined state.
- On `SIGTERM`/the platform's shutdown signal:
  1. mark readiness false or otherwise stop new routing;
  2. stop accepting new work;
  3. drain bounded in-flight work;
  4. abort/stop owned background loops and consumers;
  5. close database, queue, cache, HTTP, worker, and telemetry resources;
  6. force termination only after the documented grace deadline.
- `server.close()` and force-closing connections have version-specific semantics. Verify the deployed Node line, long-lived/upgraded connections, keep-alive behavior, and orchestrator grace period.
- Prefer setting `process.exitCode` and allowing owned flushes to finish. Use immediate `process.exit()` only when the deliberate loss of pending asynchronous work is acceptable.

## Evidence-led performance

1. Reproduce with a representative payload, concurrency, runtime flags, dependency state, and warm-up period.
2. Capture an application outcome (latency distribution, throughput, timeout/error rate) and at least one causal signal (CPU profile, event-loop delay/utilization, worker-pool/queue depth, heap/GC, active resources).
3. Change one mechanism, rerun the same workload, and compare distributions rather than one fastest sample.
4. Check correctness and resource cleanup under load; faster wrong or leaking code is a regression.

Use CPU profiles/flame graphs for CPU attribution and heap/retainer evidence for memory claims. A heap snapshot stops the main thread and can approximately double heap use while being produced; do not take one from a sole production instance or expose an unauthenticated snapshot endpoint.

## Focused adversarial cases

- large but valid input;
- malformed input that exercises worst-case parsing/regex behavior;
- downstream never responds or ignores cancellation;
- client disconnects mid-stream;
- queue reaches its bound;
- shutdown arrives during startup and during in-flight work;
- worker crashes or returns an unserializable/oversized result;
- retry budget/deadline is exhausted.
