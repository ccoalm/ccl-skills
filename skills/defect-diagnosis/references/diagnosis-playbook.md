# Diagnosis Playbook

Use this when choosing how to isolate a defect.

## Diagnosis Lenses

- Contract: request/response fields, protobuf/API compatibility, enum defaults, error envelope, HTTP/RPC mapping.
- State: database rows, transactions, cache entries, lock state, idempotency records, durable workflow status.
- Time: deadlines, retries, async delivery, job lease, clock/time zone, race conditions, eventual consistency.
- Dependency: RPC/HTTP status, domain status, timeout, malformed response, credential/config mismatch.
- Runtime: environment, feature flag, dynamic config, deployment version, generated file drift.
- Test: invalid fixture, over-mocked dependency, missing cleanup, order dependency, live-infra assumption.
- Human/agent workflow: unclear acceptance, skipped failing path, unverified assumption, missing handoff.

## Evidence Template

```markdown
## Defect Diagnosis Evidence

- Symptom:
- Reproduction:
- Failing command/test:
- Environment/config:
- Narrowed layer:
- Hypotheses tried:
- Proven cause:
- Complexity verdict (simple | complex; `simple` must name the complexity triggers checked and found absent; `complex` must name which trigger fired + contributing factors by playbook lens):
- Fix:
- Verification:
- Regression test:
- Prevention update:
```

## Profiler / Tracer Tool Routing By Symptom

When the failure is a performance / resource / runtime-behavior symptom rather than a logic bug, pick the tool by symptom shape, not by team familiarity:

| Symptom | Default tooling | Routing |
|---|---|---|
| CPU-heavy / hot loop / unexpected slowness with one process saturating a core | flame graph + sampling profiler — pprof (Go), `py-spy` / `scalene` (Python), `perf` + FlameGraph (Linux native), Chrome DevTools Performance panel (web) | stack dev skill owns config (build with profiler symbols, enable runtime profiling endpoint) |
| I/O-blocked / process appears stuck but CPU is low | system trace — `strace` (Linux syscall trace; overhead varies widely with syscall load and can be large on syscall-heavy workloads, so use briefly and on representative samples), `dtrace` (macOS / BSD; broader dynamic tracing, not just I/O), `bpftrace` (eBPF, typically low overhead BUT a badly-scoped probe still hurts; verify the probe before attaching to a production process) | platform-observability owns eBPF-based pre-installed observers (Beyla / Pixie / Tetragon); stack dev skill owns app-level instrumentation |
| Memory leak / heap growth | heap profiler — pprof heap mode (Go), `tracemalloc` (Python), Chrome DevTools Memory panel (web), Instruments / Allocations (macOS), Valgrind massif (Linux native) | stack dev skill owns "how to enable heap profiling endpoint" |
| Concurrency / race / deadlock | race detector + lock-graph capture — Go `go test -race`, Java `ThreadMXBean.findDeadlockedThreads()`, Helgrind (Linux native pthreads), Python `faulthandler.dump_traceback_later()` + thread dump | stack dev skill owns runtime config; this skill owns "look at all threads, not just the one that hit the breakpoint" discipline |
| UI lag / dropped frames | Chrome DevTools Performance for frame-level profiling + Lighthouse for audit-style triage (web); Android Studio CPU Profiler + GPU Inspector (Android); Xcode Instruments Time Profiler + Hitches (iOS) | product-ui-ux-design owns user-facing perception; stack dev skill owns tool config |
| Network latency / packet loss / TLS handshake | `tcpdump` + Wireshark for capture; `curl -v` / `httpstat` for HTTP-level; `mtr` / `traceroute` for path | platform-service-connectivity owns mesh / proxy debug; this skill owns "capture both sides of the wire" discipline |
| Distributed-system request-path mystery | OTel trace + exemplar walk per the SKILL.md Phase A observability-driven rule; do NOT default to single-service profiler when the symptom crosses service boundaries | platform-observability owns the trace UI; this skill owns the trace-first workflow |

The recurring failure shape: reach for the team's most-familiar profiler regardless of symptom (a Java-shop reaches for `jstack` on a Python service; a web team reaches for Chrome DevTools on a server-side latency issue). Pick the tool whose data model matches what's broken; pull in the stack dev skill for "how to enable it" once the tool is chosen.

## When Stack-Specific Skills Take Over

- Use Go/Python backend development skills for concrete commands, package layout, DB/Redis/MQ/protobuf/schema tests, generated files, and code patterns.
- Use the relevant architecture skill when the prevention changes service boundary, source of truth, contract compatibility, auth, release runtime, or data ownership.
- Return here to finish root-cause evidence and prevention routing.
