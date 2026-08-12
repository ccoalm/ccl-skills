# Framework Middleware (Client and Server)

The middleware chain that propagates app-level context across hops, layered above mesh transport.

## RPC server suite — default chain

In platform RPC server bootstrap (Kitex `server.Suite`, gRPC interceptor chain, or equivalent):

```
incoming RPC
   │
   ▼
 ctx_inject (server)
   │ extracts log-id, lane, caller-identity from RPC base struct or metadata
   │ generates log-id if absent (server side fallback)
   │ injects into context.Context
   ▼
 tracing (OTel contrib)
   │ extracts traceparent; starts a kind=server span
   ▼
 metrics
   │ counts QPS + latency histogram, labels = baseline + caller + callee + method
   ▼
 request_info_log (gated by env flag)
   │ INFO line on entry and exit with method, code, duration
   ▼
 err_handler
   │ catches kerrors.ErrPanic / ErrACL / ErrRPCTimeout / ErrBiz
   │ maps to a stable error-code enum (server_panic, forbidden, timeout, biz)
   ▼
 handler
```

`server.WithMetaHandler` typically wires the transport-level metadata propagation (TTHeader for Thrift, HTTP/2 metadata for gRPC). Set at server suite construction; don't re-set per service.

## RPC client suite — default chain

```
outgoing RPC (from app code)
   │
   ▼
 client_base_inject
   │ reads log-id, lane, idc, cluster from context.Context
   │ populates the canonical RPC base struct on the outbound request
   ▼
 ctx_inject (client)
   │ adds log-id to metadata for transports that don't use base struct
   │ logs caller-side observation
   ▼
 metrics
   │ counts QPS + latency, labels = baseline + caller + callee + method
   ▼
 request_info_log (gated)
   ▼
 tracing (OTel client suite)
   │ starts kind=client span; injects traceparent into outbound metadata
   ▼
 err_handler
   │ classifies framework errors so callers see a stable error-code
   ▼
 transport (mesh sidecar then network)
```

## Canonical RPC base struct

For RPC platforms with a "base request" concept (Kitex, Thrift):

```thrift
struct Base {
  1: i64 UnixTime              // ms since epoch, caller's clock
  2: string LogId              // platform log-id
  3: string Caller             // PSM-style caller identity
  4: map<string,string> Tags { // standard tag names below
       "idc":     <region>
       "cluster": <k8s cluster name>
       "lane":    <env/lane label>
       // optional below
       "stress_tag": "true" | absent      // load-test traffic flag
       "shadow":     "true" | absent      // shadow-traffic flag
  }
}
```

Whether request metadata rides an in-message `Base` field or the transport metadata/header channel is a scenario decision, not a universal mandate — see the Carrier decision in `rpc-framework-recipe.md` (transport metadata + interceptors is the industry-standard default for ordinary unary and streaming gRPC). **On a platform that has standardized the in-message `Base` carrier**, each RPC method's request type embeds `Base`, the IDL generator auto-includes it, and it is not optional per-method within that platform. **On a metadata-carrier platform**, the request type does NOT embed `Base`; the same metadata set rides the R7 owner-recorded header set and the middleware injects/extracts it there. The middleware obligation (inject on the client, extract on the server) holds on either carrier.

The client middleware fills the chosen carrier (in-message `Base` or the metadata/header set) from ctx; the server middleware extracts it. App code uses `appctx.GetLogId(ctx)`, `appctx.GetLane(ctx)` etc., never touches the carrier directly.

## HTTP equivalent (Hertz / Gin / FastAPI)

For HTTP, replace base struct with header set:

```
<log-id-header>     log-id, generated if missing
<lane-header>       lane / env
X-Caller-PSM        PSM-style identity of upstream caller (if any)
X-Caller-IDC        region
X-Caller-Cluster    cluster
traceparent         OTel trace context
tracestate          OTel trace context
```

Header names are a platform constant. The literal value does not matter; consistency does. Both client and server middleware MUST use the same names.

## Local dev mode

The middleware chain must work locally:
- No registry → resolve via `LOCAL_HOST` config or direct address.
- No mesh → app talks plaintext.
- No otel collector → tracing exporter no-ops.
- Log-id, lane, ctx propagation must still work end-to-end.

If a developer can't reproduce a multi-hop context propagation bug locally, the local mode is broken.

## What MUST NOT be in the default chain

- **Auth/authz at framework layer**. Authz belongs in handler or in mesh AuthorizationPolicy. Embedding in middleware creates a hidden coupling.
- **Rate limiting**. Use mesh / API gateway / RLS.
- **Circuit breaking**. Use mesh outlier-detection or SDK-native circuit breaker; not a middleware.
- **Cache layer**. Cache is a handler concern.

Each item above can be added as opt-in middleware for specific services, but is NOT in the default chain.

## Verification

```bash
# Server side
grep -E "ctx_inject|tracing|metrics|request_info_log|err_handler|base_inject" \
  <platform-framework-default-server-options.go>
# expect ≥ 5 hits

# Client side
grep -E "ctx_inject|client_base_inject|tracing|metrics|err_handler" \
  <platform-framework-default-client-options.go>
# expect ≥ 5 hits

# Service code does not re-add the same middleware
grep -rE "WithMiddleware\(.*(CtxInject|Metrics|Tracing|ErrorHandler)" <service-dir>
# expect zero hits

# Live: cross-service call carries log-id and lane
# Make a synthetic call from A → B; inspect B's INFO log on entry.
# Expect to see same log-id as A wrote; same lane.
```
