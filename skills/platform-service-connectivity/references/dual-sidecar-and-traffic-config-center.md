# Dual Sidecar + Traffic Config Center

Two mature patterns observed in production platforms that complement the canonical mesh model.

## Dual sidecar (mesh + platform)

A pod may run two sidecars besides the app container:

```
Pod
├─ app                    business code, ports 8888 (server) / 8889 (grpc reflection)
├─ <platform-sidecar>     framework helper, port 18888
│                         responsibilities: service discovery client cache,
│                                            local SDK companion, log-shipping
│                                            adapter, framework-only metrics
└─ <mesh-sidecar>         Envoy / Linkerd / etc, mTLS + traffic policy
                          (optional per protocol — see below)
```

The platform sidecar is **not** a replacement for the mesh sidecar. It owns concerns the mesh cannot see:

| Concern | Owner |
|---|---|
| mTLS, retries, transport timeouts | Mesh sidecar (Envoy) |
| Service discovery client cache | Platform sidecar |
| Framework-only metrics emission | Platform sidecar |
| Per-application config/secret companion | Platform sidecar |
| Stress/shadow traffic tag handling at app layer | Platform sidecar |

If you do not need a platform sidecar (no shared SD cache, no framework companion), do not deploy one. A single mesh sidecar plus a thick SDK in the app is the cheaper baseline.

## Mesh injection by protocol

Mesh injection is not all-or-nothing. Real platforms apply per-protocol policy:

| App protocol | Inject Istio sidecar? | Reason |
|---|---|---|
| HTTP (REST) | YES | Envoy handles HTTP/1.1, HTTP/2; full feature support |
| gRPC | YES | HTTP/2 + per-call routing; needs `:authority` quirk handling |
| TCP (raw) | NO (often) | Envoy TCP proxy is feature-poor; routing/auth less useful at L4 |
| Thrift (TTHeader) | NO (often) | Same — L4-ish; tooling limited |

Express via pod annotations:

```yaml
annotations:
  sidecar.istio.io/inject: "{{ if has protocol "http" "grpc" }}true{{ else }}false{{ end }}"
```

For services with mixed protocols (rare), default to inject and design the bypass at the listener.

## Traffic config center (separate from mesh routing)

A platform may want **per-caller-callee** traffic policy (timeouts, retry, circuit-breaker thresholds, hedging windows) that mesh DestinationRule cannot express (DR is per-callee, not per-pair).

The pattern:

```
Operator
   │ updates pair policy via control-plane API
   ▼
Control plane
   │ writes to config center (dcc / Apollo / Consul KV / etcd KV)
   │ keyed by (caller_psm, callee_psm)
   ▼
Config center
   │ pushes updates to subscribers
   ▼
Framework client SDK in every caller service
   │ subscribes to its own outbound pairs
   │ applies new policy at next call (no restart)
```

Payload shape per pair:

```yaml
ServiceTrafficConfig:
  caller_psm: <psm>
  callee_psm: <psm>
  content:
    timeout_ms: <int>
    retry_attempts: <int>
    retry_backoff_ms: <int>
    circuit_breaker:
      consecutive_5xx: <int>
      eject_seconds: <int>
    hedging:
      enabled: <bool>
      delay_ms: <int>
```

Why per-pair, not per-callee:
- Different callers may have different criticality. The user-facing service might accept 200ms timeout calling the search service; the batch job calling the same search service may accept 5s.
- Retry budgets are per-caller — uniform per-callee retry can amplify load from a single misbehaving caller.

Write concurrency control:
- Per-pair Redis lock (lease longer than the maximum write duration; renew via heartbeat if needed).
- **Lock lease MUST exceed worst-case fanout time.** A 10s lease with a 2-min fanout window means lock A can expire mid-flight, operator B acquires the lock and writes, then A's late write overwrites B silently. Either: (a) make the lease longer than the fanout timeout, OR (b) renew the lease via heartbeat during the operation, OR (c) use fencing tokens — every write to the config center includes the lock's fencing token; the config center rejects writes with a stale token. Option (c) is the only one that's correct under all timing edge cases; (a) and (b) are pragmatic for shorter operations.
- **Prefer config-center-native CAS over external locks** where the backend supports it. etcd's `mod_revision` precondition on `Put` (transaction with `Compare(mod_revision)`) is the cleanest fencing primitive — the write fails if anyone else wrote since the read.
- Updates fan out via WaitGroup with concurrency limit (e.g. 20) and total timeout (e.g. 2 min).

## Layering with mesh

The two systems answer different questions:

| Question | Owner |
|---|---|
| Which pod gets this request? (lane routing, load balance) | Mesh VirtualService |
| Is this peer authorized? (mTLS, AuthorizationPolicy) | Mesh |
| Connection-level retry on TCP error | Mesh |
| Should this caller retry on 5xx from this callee? | Framework client SDK (reads pair config from config center) |
| What timeout for this caller→callee call? | Framework client SDK |
| Circuit-breaker per-pair | Framework client SDK |

A platform may run only mesh (simpler), only app-level traffic config (no mesh), or both. The dual approach is more work but gives both network-level and app-level levers.

## Anti-pattern to avoid

- Running both mesh DR policy AND app-level traffic config without an ownership boundary. Two layers retrying the same call amplifies load 9× (3×3). Document which layer owns retry; disable the other.
- Letting per-pair config become per-call config — the cardinality explodes. Per-pair is workable (services × services); per-call is not.
- Config center as a routing replacement. Routing belongs in mesh (or in SDK resolver). Config center is for policy values, not topology.

## Verification

- Update a pair policy via the control-plane API → log into a caller pod → SDK shows new value applied within the subscription propagation window (typically 1-10s).
- Inject a synthetic 5xx storm from a callee → mesh outlier detection ejects pods (mesh-level), and the framework client SDK respects the per-pair retry budget without amplifying.
- Disable mesh inject for a TCP service → verify connectivity still works (registry + direct TCP); verify mTLS is intentionally absent (or applied via app-level TLS if required).
