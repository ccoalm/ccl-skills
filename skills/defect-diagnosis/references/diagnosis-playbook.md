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
- Localization move used (commit bisection | input reduction | suite bisection | boundary walk | difference diff | upstream trace | telemetry walk):
- Hypothesis log (hypothesis | falsifier | probe cost/risk | result):
- Active-test changes made and reverted:
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

## Localization Playbook

Locating the defect is usually the most expensive phase — harder than reproducing or fixing it (arXiv 2103.12447, a 2021 survey of 102 programmers' recently fixed bugs) — so choose the localization move by the failure's shape before forming hypotheses:

| Failure shape | Move | Recipe |
|---|---|---|
| Regression with a known-good and a known-bad commit | commit bisection | `git bisect` per SKILL.md Phase A.2; narrow with `-- <paths>` and every known-good commit; `--first-parent` for merge-introduced regressions; `git bisect log` / `replay` to hand off a half-finished search; alternate terms (`--term-old fast --term-new slow`) when the "bad" state is a slowdown or a fix rather than a bug |
| Failing input / config / dataset, no commit axis | input reduction (delta debugging) | halve the failing input; if neither half fails, keep cutting smaller chunks (quarters, eighths) until every remaining piece is needed; the minimal failing input is both the reproduction and a localization clue |
| Passes alone, fails in the suite | suite bisection | halve the set of tests that run before the failing one, keep the half that still fails, repeat until one polluting test (or the shared fixture/state it leaves behind) remains; fix the isolation, not the victim test |
| Multi-component chain | boundary walk | in ONE run log entry/exit data and the env/config actually received at each boundary; the first boundary whose output is wrong owns the search |
| A passing analog exists (sibling test, other endpoint, last-good build) | difference diff | enumerate every difference between working and broken; include executed-path differences — coverage, trace spans, or request attributes that only the failing population carries — not only inputs and config |
| Wrong value observed downstream | upstream trace | follow the value backward to the first point where a correct input produced a wrong output; that transition is the defect, the observation point is only where it surfaced |
| Production symptom that cannot be re-triggered | telemetry walk | alert → exemplar trace → span tree → logs by trace-id (SKILL.md Phase A.4); group the failing population by attribute and compare it against the baseline to find what is different about failing requests |

## Probe Ordering And The Hypothesis Log

Order probes; do not merely list hypotheses. For each candidate cause record what would falsify it, what the probe costs, and what it risks, then run the probe that is cheapest and safest AND whose outcome eliminates the most alternatives. Test likely-and-cheap before exotic. Watch for confounders (a probe run from the wrong host, credential, or network position fails for its own reasons), side effects of active probes (more CPU changes race timing; verbose logging worsens latency — revert before the next probe), and probes that are only suggestive (races, deadlocks): record the evidence grade next to the result.

Running log, kept while diagnosing and pasted into the evidence template at closeout:

| # | Hypothesis | Falsifier (observation only THIS cause predicts) | Probe (cost / risk / side effects) | Result | Conclusion |
|---|---|---|---|---|---|
| 1 | ... | ... | ... | rejected / confirmed / suggestive | ... |

Check each new hypothesis against the rows above before spending a probe; a rejected class re-entered under a new name counts toward the three-strike reassessment in SKILL.md.

## Sources

Verified against the primary page when this playbook was written; for audit, not required reading.

- Google SRE Book, ch. 12 *Effective Troubleshooting* (`sre.google/sre-book/effective-troubleshooting/`): the hypothetico-deductive model; common pitfalls (irrelevant symptoms, unsafe tests, latching on to past causes, spurious correlation); simplify and reduce, bisection over components; "what touched it last"; test design — mutually exclusive alternatives, decreasing likelihood weighed against risk, confounders, side effects of active tests, suggestive tests; take clear notes; negative results.
- The Debugging Book (`debuggingbook.org`): *Introduction to Debugging* — the scientific-method loop, a fix requires a diagnosis showing both causality and incorrectness, keep a log; *Reducing Failure-Inducing Inputs* — delta debugging; *Statistical Debugging* — suspiciousness ranking of executed lines.
- `git-scm.com/docs/git-bisect`: run exit codes, skip, pathspec and multiple good commits, log/replay, alternate terms, `--first-parent`.
- *What we can learn from how programmers debug their code* (2021, arXiv 2103.12447): locating a bug is harder than reproducing or fixing it; memory and concurrency bugs consume disproportionate time.
- Agentless (Xia et al., 2024, arXiv 2407.01489): localization → repair → validation with reproduction and regression tests as a strong, simple baseline.
- Microsoft Research, *debug-gym* (2025): coding agents typically rewrite code conditioned on the error message; access to interactive debugging tools (breakpoints, value printing) improves repair, and current agents still under-use them.

## When Stack-Specific Skills Take Over

- Use Go/Python backend development skills for concrete commands, package layout, DB/Redis/MQ/protobuf/schema tests, generated files, and code patterns.
- Use the relevant architecture skill when the prevention changes service boundary, source of truth, contract compatibility, auth, release runtime, or data ownership.
- Return here to finish root-cause evidence and prevention routing.
