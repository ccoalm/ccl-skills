# gRPC Authority Compatibility

## Separate the names and constraints

HTTP/2 `:authority` conveys the target URI's authority, as defined by [RFC 9113 §8.3.1](https://www.rfc-editor.org/rfc/rfc9113.html#section-8.3.1). [RFC 3986 §3.2.2](https://www.rfc-editor.org/rfc/rfc3986.html#section-3.2.2) permits a registered name containing unreserved characters, including `_`. This syntax does not guarantee DNS resolution, certificate identity matching, or acceptance by every SDK and proxy version.

Keep these values distinct when diagnosing a request:

- Service-registry identifier and resolved network endpoint.
- HTTP/2 authority used for virtual-host routing.
- TLS server name and the certificate identity expected on each TLS hop.
- Platform naming, routing, and authorization policies.

A platform can require DNS-compatible service names and enforce that choice at registration and CI. Existing identifiers do not require migration merely because they contain an underscore; first establish which constraint the actual path violates.

## Locate the rejection before choosing a fix

Record the runtime/SDK, proxy versions and relevant configuration, exact authority, and the failing run's error or trace. Use a synthetic payload and redact credentials from captured evidence.

| Observed boundary | Next action |
|---|---|
| Authority syntax is malformed | Validate URI authority syntax, including brackets around an IPv6 literal, before changing service registration or routing. |
| Client rejects before transmitting HTTP/2 headers | Check that client's authority validation and supported configuration. Fix the client-side mapping or naming contract; a downstream proxy cannot rewrite a request it never receives. |
| DNS resolution fails | Check the resolved hostname and resolver's naming rules. Changing a later HTTP header does not repair failed resolution. |
| TLS handshake or certificate identity check fails | Check that hop's endpoint, server name, trust chain, and certificate identities. Retain verification; changing authority is not evidence that TLS is fixed. |
| Proxy/parser rejects before the HTTP filter runs | Fix the supported parser/input contract or an earlier owned mapping. A Lua filter after the rejection cannot intervene. |
| Request reaches HTTP filters, then the intended virtual-host route does not match | Compare the received authority with the generated route configuration. A supported authority mapping may be appropriate after proving the mismatch. |
| Existing path accepts the name and reaches the intended service | Preserve it unless a separate platform naming-policy migration is required. |

`RST_STREAM` or `INTERNAL_ERROR` alone does not identify an underscore problem. Confirm the first rejecting layer rather than treating every transport failure as the same naming defect.

## Choose a bounded compatibility change

**Naming policy or client mapping.** Where a DNS-compatible name is required, define the allowed form and the mapping from registry identity to endpoint/authority. Check uniqueness before migration: replacing `_` with `-` can collapse two distinct names. Migrate registrations, routes, and callers together with a compatibility window and rollback path. Use supported client options; do not bypass certificate or authorization checks to make a name work.

**Proxy mapping.** Use only if the request reaches the chosen filter and the mapping addresses a reproduced failure. Prefer the platform's supported routing mechanism. If an EnvoyFilter is necessary, verify the installed Istio/Envoy API and generated configuration, and scope it to the affected workloads, listener/direction, route, and explicit old-to-new authority mapping. Do not install an all-workload, all-direction underscore replacement. The mapping must preserve the intended destination, tenant/lane routing, authorization, and TLS identity on each hop; rewriting a header does not itself update those contracts.

## Verification

Retain the original failing case and expected rejecting layer. After the change, verify:

1. The same request succeeds through the intended path and reaches the intended service; observe authority before/after any mapping and the selected route.
2. Unrelated authorities and non-target traffic retain their behavior. Include potentially colliding names and unknown authorities as negative controls.
3. Certificate identity and authorization failures still reject requests; the compatibility change has not disabled those checks.
4. Registration/client/route changes can be rolled back together without sending traffic to another service.

Static configuration validation proves only configuration properties. Claims about a deployed SDK/proxy path require execution evidence from that path.
