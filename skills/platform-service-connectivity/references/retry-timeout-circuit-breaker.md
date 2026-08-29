# Retry, Timeout, Circuit Breaker

Where each policy lives, how they compose, and how to keep them from killing each other.

## Layered policy

For a single call A → B, four policies can fire:

```
App business deadline             ← ctx.Deadline; "this user can wait at most 800ms"
   ⊇
Framework client per-call budget   ← SDK option; "give this call 500ms"
   ⊇
Mesh transport timeout (ceiling)   ← DestinationRule; "any call to B caps at 2s"
   ⊇
TCP/HTTP2 connect + idle timeouts  ← Envoy defaults; rarely tuned
```

Each outer policy must be ≥ the next inner one. Inversions cause "request succeeded internally but caller already returned timeout" — a hard-to-debug class.

## Timeout budget rule

For a chain A → B → C:

```
A.ctx.deadline = D
A's client-to-B budget    ≤ D - margin                   (margin: 50-100ms for serialization)
B's internal work         ≤ (B-budget - C-budget)
B's client-to-C budget    ≤ B-budget - margin
```

A framework helper should compute "remaining ctx deadline" and pass `min(ctx.Deadline, my-budget)` to outbound calls.

## Retry placement

| Layer | Retries WHAT | When |
|---|---|---|
| Mesh (DestinationRule) | network errors, gRPC `UNAVAILABLE`, certain 5xx | Always-safe-to-retry transports |
| Framework client | idempotent business RPCs | Per-method opt-in |
| App handler | nothing | App level retry usually wrong |
| App business logic | high-level workflows | Saga / orchestration patterns, not "I'll retry the call once" |

Double retry = real bad. If mesh retries 2x and framework retries 2x, you get 4x amplification on every flapping backend.

**Rule**: when enabling framework-level retry, disable mesh retry for that callee (DestinationRule `retries.attempts: 0`).

Mesh retries back off automatically (Istio/Envoy: jittered exponential backoff with a default 25ms *base* interval — fully jittered, so an actual delay can be shorter than the base; it is not a guaranteed minimum gap); framework-level retry gets no such freebie — it must implement its own jittered backoff that fits inside the caller's remaining deadline.

## Retry budget (load-proportional guard, per proxy)

Per-call retry counts bound retries *per request*; they do not bound a caller's total retry share during a partial outage — at high QPS, "2 retries each" is up to a 3× load multiplier at the exact moment the upstream is sickest. Envoy's cluster circuit breakers cap this per proxy:

- `max_retries` — max **concurrent** retries to the cluster, per priority. Retries beyond it overflow (fail fast, counted in `upstream_rq_retry_overflow`). The raw Envoy default is 3, but the control plane above Envoy may override it: Istio's `connectionPool.http.maxRetries` defaults to **2^32-1 — effectively unlimited** — so in an Istio mesh "leave it unset and rely on the default cap" is a trap. Set the limit explicitly and verify the *generated* Envoy cluster config, not the assumption.
- `retry_budget` — replaces the fixed cap with a load-proportional one: concurrent retries ≤ `budget_percent` (default 20%) of active + pending requests, with a `min_retry_concurrency` floor so low-traffic clusters can still retry. When set, it overrides `max_retries`. Reachability caveat: Istio's DestinationRule API exposes only `connectionPool.http.maxRetries`, NOT `retry_budget` — on plain Istio, set a finite `maxRetries` first; adopting `retry_budget` there means an EnvoyFilter, acceptable only with the *generated* cluster config verified.
- Know exactly what the budget bounds — and what it doesn't. It bounds **Envoy-originated, concurrent** retries, per proxy. It does NOT bound: retry attempt *rate*; **framework-level retries** (each framework attempt arrives at Envoy as a fresh request and bypasses `max_retries`/`retry_budget` entirely — a platform running framework retries needs a framework-side budget or strict per-call caps); or the **fleet aggregate** (circuit breaking is distributed, not coordinated — each sidecar enforces its own budget and floor, so aggregate retry load still scales with caller replica count). A true service-wide load bound requires callee-side protection (admission control / load shedding, owned by the service-architecture skills) on top.
- When tuning for a flaky dependency, set a retry budget rather than raising per-call retry counts — but pick `budget_percent` AND `min_retry_concurrency` deliberately against the callee's capacity: on a very high-QPS caller, an unexamined 20% of active requests is far looser than `max_retries: 3`, and with many low-traffic sidecars the aggregate floor (≈ replicas × `min_retry_concurrency`) dominates instead. Alert on the overflow counter: a growing overflow stat means callers are shedding retries, which is the budget doing its job; do not "fix" it by raising the cap.

## Idempotency awareness

Framework client retries MUST consider idempotency:

```
RPC method declares "idempotent: true" in IDL or annotation
   ↓
SDK retry middleware reads this; only retries idempotent methods
   ↓
Non-idempotent retry happens only if the network error proves the request didn't reach the server
(connect refused, TLS handshake failure — yes; "request sent, no response" — no)
```

Don't trust HTTP method (POST can be idempotent; GET can have side effects). Trust the declaration.

## Circuit breaker / outlier detection

Mesh outlier-detection (Envoy):

```yaml
trafficPolicy:
  outlierDetection:
    consecutive5xxErrors: 5         # 5 consecutive 5xx → eject this pod
    interval: 10s                   # check every 10s
    baseEjectionTime: 30s           # eject for 30s minimum
    maxEjectionPercent: 50          # never eject more than 50% of pool
```

This is the right place for circuit breaking. Per-host, automatic, observable via Envoy stats.

Framework SDK circuit breakers (e.g. hystrix-style) are a fallback for environments without mesh, or for business-logic-driven breaking (e.g. "this dependency's error rate hit 10%, switch to degraded mode").

Don't run mesh outlier-detection AND SDK circuit breaker simultaneously without understanding the interaction.

## Cascading cancel

When a caller's ctx is cancelled (deadline, client disconnect, user back-button), the cancel MUST propagate to in-flight downstream calls. Frameworks should support this natively; verify by spawning a long-running downstream call and cancelling the parent — both should terminate.

If a service swallows ctx cancel, downstream load amplifies during user disconnects (every abandoned tab continues hammering the DB).

## Hedging

Hedging = send a second request after a timeout T, return whichever responds first. Useful for latency-sensitive read APIs.

Risks:
- Doubles load if T is too short.
- Not safe for non-idempotent calls.
- Mesh-level hedging is preferred (e.g. Envoy `retry_priority` patterns); SDK hedging is workable but harder to tune.

Default: off. Enable per-method after measuring p99 latency distribution.

## Common mistakes

- Setting framework client timeout > mesh timeout → client never sees mesh-side errors, retries the same call, mesh times out anyway. Align them.
- Retrying on 4xx → client errors don't fix themselves; you just amplify load.
- Retrying with exponential backoff while caller deadline is 200ms → backoff exceeds deadline, retry never fires, you wasted code.
- Mesh retry + SDK retry both on, both default 3 → 9 actual attempts per logical call.
- Circuit breaker tripped but no metric → debugging blind.

## Tuning starting points

| Policy | Default |
|---|---|
| Mesh request timeout | 5s (HTTP), 10s (RPC); per-callee override |
| Mesh retry attempts | 2 |
| Mesh retry per-try timeout | 1s |
| Mesh outlier detection | 5 consecutive 5xx, 30s eject |
| Framework client per-call budget | 500ms or shrunk from ctx deadline |
| Framework client retry | OFF by default; opt-in per idempotent method |

Tune from observed p99 + error rate, not vibes.

## Verification

- Trigger downstream 5xx storm → mesh outlier-detection metrics show ejection events; client-side error rate spikes then recovers.
- Force a connect refusal → mesh retry attempts visible in mesh metric; final caller sees one error.
- Set per-call timeout below mesh ceiling → confirm caller sees its own deadline, not mesh's.
- Cancel a request mid-flight → confirm downstream stops within one network round-trip.
