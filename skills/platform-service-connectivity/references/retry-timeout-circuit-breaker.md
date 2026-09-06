# Retry, Timeout, Circuit Breaker

Where each policy lives, how timeouts compose, and how to bound retry amplification. Istio field names below apply to Istio HTTP/gRPC paths; other transports keep their platform-owned equivalents.

## Layered policy

For a single call A → B, several independent timers can end the call:

| Timer | Owner | Example |
|---|---|---|
| Caller deadline | App context | 800ms remaining |
| Total client-call budget | Framework client | 500ms, including retries and backoff |
| Mesh request timeout | VirtualService HTTP route `timeout` | 2s platform cap |
| Per-attempt timeout | VirtualService HTTP route `retries.perTryTimeout`, or the retry-owning SDK | Must fit the remaining call budget |
| Connection / idle timeout | DestinationRule connection pool / transport | Bounds connection setup or inactivity, not total business work |

The earliest applicable expiry wins. With the example values measured from call start, the client ends the call at 500ms; the 2s mesh cap can remain a platform backstop. These are not nested durations that must decrease from client to mesh. Propagate cancellation so downstream work stops when the caller's budget expires; a longer transport cap does not extend the caller's deadline.

Istio's [HTTPRoute and HTTPRetry fields](https://istio.io/latest/docs/reference/config/networking/virtual-service/) own request/attempt timeout and request retries. [DestinationRule connection-pool settings](https://istio.io/latest/docs/reference/config/networking/destination-rule/) own connection timeouts and concurrent-retry limits; its traffic policy owns outlier detection.

## Timeout budget rule

For a chain A → B → C:

```
A's remaining duration = A.ctx.deadline - now
A's client-to-B budget  ≤ remaining duration - margin   (e.g. 50-100ms for serialization)
B's client-to-C budget  ≤ B's remaining duration - margin
All sequential work, attempts, and backoff fit within that remaining budget
```

A framework helper computes `min(remaining_duration - margin, configured_call_budget, applicable_platform_cap)`. If no usable duration remains, fail without dispatching another attempt. Pass the resulting deadline downstream and recompute the remainder after work or backoff; do not compare an absolute deadline with a duration or restart the full budget at each hop.

## Retry placement

| Layer | Retries WHAT | When |
|---|---|---|
| Mesh (VirtualService HTTP route) | Explicitly selected network errors or response statuses | Declared idempotent calls, or failures proven to precede server receipt |
| Framework client | idempotent business RPCs | Per-method opt-in |
| App handler | nothing | App level retry usually wrong |
| App business logic | high-level workflows | Saga / orchestration patterns, not "I'll retry the call once" |

Retry layers multiply total attempts. If mesh and framework each make at most two total attempts, one logical call can reach the backend four times. Istio `retries.attempts` counts retries after the initial request: a value of 2 permits up to 3 total attempts, subject to time and retry budgets.

**Rule**: when enabling framework-level retry, set `retries.attempts: 0` on every matching VirtualService HTTP route used by that call and verify the effective generated route configuration. Keep DestinationRule connection limits and outlier detection; they do not replace the route-level retry switch.

Mesh retries back off automatically (Istio/Envoy: jittered exponential backoff with a default 25ms *base* interval — fully jittered, so an actual delay can be shorter than the base; it is not a guaranteed minimum gap); framework-level retry gets no such freebie — it must implement its own jittered backoff that fits inside the caller's remaining deadline.

## Retry budget (load-proportional guard, per proxy)

Per-call retry counts bound retries *per request*; they do not bound a caller's total retry share during a partial outage — at high QPS, "2 retries each" is up to a 3× load multiplier at the exact moment the upstream is sickest. Envoy's cluster circuit breakers cap this per proxy:

- `max_retries` — max **concurrent** retries to the cluster, per priority. Retries beyond it overflow (fail fast, counted in `upstream_rq_retry_overflow`). The raw Envoy default is 3, but the control plane above Envoy may override it: Istio's `connectionPool.http.maxRetries` defaults to **2^32-1 — effectively unlimited** — so in an Istio mesh "leave it unset and rely on the default cap" is a trap. Set the limit explicitly and verify the *generated* Envoy cluster config, not the assumption.
- `retry_budget` — replaces the fixed cap with a load-proportional one: in the default instantaneous mode, concurrent retries ≤ `budget_percent` (default 20%) of active + pending requests, with a `min_retry_concurrency` floor so low-traffic clusters can still retry. Versions exposing a non-zero `budget_interval` can count requests over that interval instead; verify the configured version and mode. When set, the budget overrides `max_retries`. Reachability caveat: Istio's DestinationRule API exposes only `connectionPool.http.maxRetries`, NOT `retry_budget` — on plain Istio, set a finite `maxRetries` first; adopting `retry_budget` there means an EnvoyFilter, acceptable only with the *generated* cluster config verified.
- Know exactly what the budget bounds — and what it doesn't. It bounds **Envoy-originated, concurrent** retries, per proxy. It does NOT bound: retry attempt *rate*; **framework-level retries** (each framework attempt arrives at Envoy as a fresh request and bypasses `max_retries`/`retry_budget` entirely — a platform running framework retries needs a framework-side budget or strict per-call caps); or the **fleet aggregate** (circuit breaking is distributed, not coordinated — each sidecar enforces its own budget and floor, so aggregate retry load still scales with caller replica count). A true service-wide load bound requires callee-side protection (admission control / load shedding, owned by the service-architecture skills) on top.
- When tuning for a flaky dependency, set a retry budget rather than raising per-call retry counts — but pick `budget_percent` AND `min_retry_concurrency` deliberately against the callee's capacity: on a very high-QPS caller, an unexamined 20% of active requests is far looser than `max_retries: 3`, and with many low-traffic sidecars the aggregate floor (≈ replicas × `min_retry_concurrency`) dominates instead. Alert on the overflow counter: a growing overflow stat means callers are shedding retries, which is the budget doing its job; do not "fix" it by raising the cap.

## Idempotency awareness

Both mesh and framework client retries MUST consider idempotency:

```
RPC method declares "idempotent: true" in IDL or annotation
   ↓
The retry-owning layer applies a policy only to methods covered by that declaration
   ↓
Non-idempotent retry happens only if the network error proves the request didn't reach the server
(connect refused, TLS handshake failure — yes; "request sent, no response" — no)
```

Don't trust HTTP method (POST can be idempotent; GET can have side effects). Trust the declaration. A 5xx, gRPC `UNAVAILABLE`, timeout, or missing response alone does not prove that a write was not applied. If the mesh cannot distinguish safe methods, keep its request retries disabled and let the method-aware SDK own the policy.

## Circuit breaker / outlier detection

Mesh outlier-detection (Envoy):

```yaml
trafficPolicy:
  outlierDetection:
    consecutive5xxErrors: 5         # 5 consecutive 5xx → eject this pod
    interval: 10s                   # periodic ejection analysis / recovery sweep
    baseEjectionTime: 30s           # eject for 30s minimum
    maxEjectionPercent: 50          # never eject more than 50% of pool
```

For a meshed path, this provides per-host ejection observable through Envoy stats. [Envoy's ejection algorithm](https://www.envoyproxy.io/docs/envoy/latest/intro/arch_overview/upstream/outlier) checks consecutive-error thresholds inline; periodic analyses use `interval`. An ejection also depends on the configured threshold/enforcement and pool limits. Killing a pod once does not prove those conditions fired.

Framework SDK circuit breakers (e.g. hystrix-style) are a fallback for environments without mesh, or for business-logic-driven breaking (e.g. "this dependency's error rate hit 10%, switch to degraded mode").

Don't run mesh outlier-detection AND SDK circuit breaker simultaneously without understanding the interaction.

## Cascading cancel

When a caller's ctx is cancelled (deadline, client disconnect, user back-button), propagate it to in-flight downstream calls. [gRPC cancellation](https://grpc.io/docs/guides/cancellation/) requires application handlers to cooperate; outgoing-call propagation also depends on the language/runtime. Verify cancellation reaches the handler, stops its work and child calls, and releases resources within the service's documented cancellation bound. A transport cancellation signal alone does not prove application work stopped.

If a service swallows ctx cancel, downstream load amplifies during user disconnects (every abandoned tab continues hammering the DB).

## Hedging

Hedging sends an additional request while the first is still in flight and returns the first acceptable response. It can reduce tail latency for idempotent reads, at the cost of concurrent upstream work.

Risks:
- Doubles load if T is too short.
- Not safe for non-idempotent calls.
- Bound concurrent attempts, total deadline and admitted load; cancel losing attempts after choosing a response and propagate caller cancellation.
- Envoy's [HedgePolicy](https://www.envoyproxy.io/docs/envoy/latest/api-v3/config/route/v3/route_components.proto#config-route-v3-hedgepolicy) uses `hedge_policy.hedge_on_per_try_timeout` with a finite per-try timeout and a retry policy containing retry conditions and a positive retry limit. `retry_priority` selects upstream priorities; it does not enable hedging.
- Istio's HTTPRetry API does not expose a hedging field. Use an explicitly supported platform mechanism (such as an EnvoyFilter with generated-route and runtime verification), or a method-aware SDK; do not infer hedging from `perTryTimeout` alone. Keep a single retry/hedge owner.

Default: off. Enable per-method after measuring p99 latency distribution.

## Common mistakes

- Treating a shorter mesh timeout as invisible to the client → the client can receive a mesh timeout response before its own deadline. Verify error mapping and the retry-owning layer; do not turn that response into an unsafe replay.
- Retrying every 4xx → permanent client errors do not fix themselves. Only a documented transient condition, such as a rate-limit response with a bounded retry delay, may be eligible under the idempotency and remaining-budget rules.
- Retrying with exponential backoff while caller deadline is 200ms → backoff exceeds deadline, retry never fires, you wasted code.
- Mesh and SDK each allow 3 retries after the initial request → up to 16 backend attempts per logical call, before deadline/budget limits.
- Circuit breaker tripped but no metric → debugging blind.

## Tuning starting points

These are example starting points for eligible traffic, not vendor defaults or a mandate to enable retries. Apply the idempotency and single-owner rules first.

| Policy | Starting point |
|---|---|
| Mesh request timeout | 5s (HTTP), 10s (RPC); per-callee override |
| Mesh retry attempts | 0 unless mesh owns safe retries; then up to 2 retries within the call budget |
| Mesh retry per-try timeout | Fit within the remaining call budget; reserve time for backoff and any later attempt |
| Mesh outlier detection | 5 consecutive 5xx, 30s eject |
| Framework client per-call budget | 500ms or shrunk from ctx deadline |
| Framework client retry | OFF by default; opt-in per idempotent method |

Tune from observed p99 + error rate, not vibes.

## Verification

- Trigger downstream 5xx storm → mesh outlier-detection metrics show ejection events; client-side error rate spikes then recovers.
- Force a connect refusal → only the configured retry owner produces attempts, counts fit its budget, and the final caller sees one error. With SDK-owned retries, confirm effective route retries are disabled.
- Set per-call timeout below mesh ceiling → confirm caller sees its own deadline, not mesh's.
- Set mesh request timeout below the client budget → confirm the mapped mesh error is visible and does not trigger a second, unintended retry layer.
- For a non-idempotent write with a lost response, confirm neither layer blindly replays it.
- With hedging enabled, delay an eligible call past the per-try timeout → confirm bounded concurrent attempts, first acceptable response selection, loser cancellation, and no second retry/hedge owner.
- Cancel a request mid-flight → confirm handler work and downstream calls stop and resources release within the declared cancellation bound.
