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
