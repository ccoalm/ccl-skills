# RPC Framework Recipe (Concrete Defaults)

Concrete defaults for the kitex/hertz-style framework default suite. Patterns distilled from production deployments; localize names but preserve structure.

**Wire protocol**: gRPC over HTTP/2 only. Kitex's `DefaultClientOptions` / `DefaultServerOptions` set `transport.GRPC` + HTTP/2 metadata handlers. Thrift / TTHeader code paths exist in the framework for historical reasons but are **deprecated** — do not write new services against them, do not propagate Thrift patterns in this recipe.

## RPC base.Request — full schema

### Protobuf-backed base field declarations

This section describes the **in-message `base` carrier**, which is one of two carriers — whether a platform uses it at all is scenario-driven, not universal (see the Carrier decision below; transport metadata + interceptors is the industry-standard default for ordinary gRPC). On a platform that has standardized the in-message `base` carrier, the shared IDL defines the base metadata fields as fixed organization contract declarations. The field number is the owner-recorded pin from the cited shared IDL/IDLGen owner artifact or generated descriptor, not this prose line. The generated declarations below are shared-IDL owner output, not service-local proto templates (the field is required *for this carrier*, not a mandate that every platform adopt it):

```proto
message ExampleRequest {
  base.Request base = <owner-pinned-base-tag>;
  // Field number comes from the resolved shared IDL/IDLGen owner artifact; do not hand-pick it in a service-authored proto.
  // business fields must not use the owner-pinned base tag for any other field.
  // Do not reserve that tag unless item 6 records an interim migration; the tag is occupied by the required base field.
}

message ExampleResponse {
  base.Response base = <owner-pinned-base-tag>;
  // Field number comes from the resolved shared IDL/IDLGen owner artifact; do not hand-pick it in a service-authored proto.
  // business fields must not use the owner-pinned base tag for any other field.
  // Do not reserve that tag unless item 6 records an interim migration; the tag is occupied by the required base field.
}
```

### Carrier decision — in-message `base` vs transport metadata is scenario-driven, not mandatory

Whether internal RPC metadata rides an **in-message `base` field** or the **transport metadata / context channel** (gRPC HTTP/2 metadata + client/server interceptors, CloudWeGo metainfo, or an owner-recorded header set) is a platform/scenario decision — NOT a universal mandate on every gRPC method (unary or streaming):

- The **transport metadata channel is the industry-standard carrier** and a first-class default for ordinary unary *and* streaming RPC: it is how gRPC itself propagates auth/tracing/custom context across a distributed system, and how OpenTelemetry carries `traceparent`/`baggage`. Native gRPC/HTTP2 metadata makes an in-message envelope redundant for most services. A new product may propagate via the metadata channel and does **not** owe an "exception note" for declining the in-message `base` field.
- The **in-message `base` field is the Thrift/kitex-legacy carrier** (Thrift lacked a clean metadata channel, so the `Base` struct rode in the message body). It applies **only when the platform has standardized it**, or when a specific shared-IDL contract declares a `base` field. This recipe documents that carrier concretely; it does not require every platform to adopt it.
- **Mandatory regardless of carrier** is the observability + identity propagation contract (R6/R7): every hop propagates `log-id`, `lane`, caller identity, and `{idc, cluster}` tags on *some* channel, populated by middleware, asserted end-to-end. Choosing the metadata channel relaxes the message *shape*, never the *propagation obligation*.
- The **field-pinning gate below applies only when the in-message `base` field is actually used** (a platform/contract that has standardized it). A service propagating via the metadata channel uses the R7 owner-recorded header-set contract (enumerated, checked) instead of the protobuf field-number gate. The R7 contract lives in `../platform-service-connectivity/SKILL.md` (section R7); this recipe references but never restates it.
- **Security controls follow the identity carrier, not the `base` field name.** Boundary classification, external/gateway egress zeroing, opaque external `LogId` remap, and "caller-supplied identity is not authentication" apply to *whatever channel* carries identity/metadata — the in-message `base` fields OR the metadata/header channel. Moving off in-message `base` never moves off these controls.
- **Migrating an already-standardized in-message `base` contract off (or onto) the message is a wire-compatibility change** and goes through the Collision-migration record (item 6): existing binary consumers that read the `base` field are drained/retired first. Scenario-driven governs the *carrier choice for a new service/contract*, not silently dropping an established field from a live contract.

The ordered gate below governs the **in-message `base`-field carrier**. Apply it in this order when that carrier is in use:

1. **Trigger**: Apply this decision list in order.
   1. Run the gate for method-message definition edits, top-level request/response promotion or reuse, `base` edits, owner-pinned field-number edits/reservations, or a change to the directly consumed shared IDL/IDLGen pin or resolved descriptor/generated-artifact provenance hash.
   2. Run the gate when the service newly consumes a shared-IDL method message not previously consumed by that service. If the upstream message is unchanged and the diff does not touch definition, `base`, the owner-pinned field number, promotion/reuse, or the effective shared IDL/generated-artifact pin, a committed dependency manifest reference, repo-committed pin/lock/registry id, or linked owner-suite resolution for the consumed artifact is enough to discharge the trigger.
   3. For transitive, indirect, or floating dependency changes, run the gate only when the resolved descriptor/generated-artifact hash, committed dependency manifest reference, repo-committed pin/lock/registry id, or owner-suite resolution for a consumed shared contract changes. If resolution can float and no before/after resolver evidence is available, artifact drift is blocking for definition, `base`, owner-pinned field-number, promotion/reuse, or effective pin/provenance changes. For unrelated service-logic diffs, `coverage deferred to owner suite` is mergeable only when it cites a tracked owner-action id with owner, deadline, and a committed CI/registry/owner-suite gate that machine-checks the owner-action id and deadline before merge; without that enforced owner action, the drift remains an open gap.
   4. A newly consumed message reached through floating or transitive resolution is discharged by a committed dependency manifest reference, repo-committed pin/lock/registry id, or owner-suite resolution when the upstream message is unchanged and the diff does not touch definition, `base`, owner-pinned field number, promotion/reuse, or effective generated-artifact version/provenance. If none is reachable in diff-only review, `coverage deferred to owner suite` requires a tracked owner-action id with owner, deadline, and a committed CI/registry/owner-suite gate that machine-checks the owner-action id and deadline before merge; do not report pass.
   5. For generated-artifact version/provenance changes, pass only when descriptor diff, registry metadata, or owner-suite proves existing consumed method messages did not change and any newly consumed method message satisfies item 4. Changelog prose alone is not proof.
   6. Pure new consumption of an unchanged upstream method message with no definition, promotion/reuse, `base`, owner-pinned field-number, pin, manifest, or resolver change uses the gate step 4 Field assertion light path: cite the committed dependency manifest reference, repo-committed pin/lock/registry id, or owner-suite resolution for the consumed artifact plus generated descriptor evidence for the consumed message kind. It does not require a full owner-suite sweep in the service diff.
   7. Pure handler/service-logic changes are not applicable only when they do not manually construct generated request/response DTOs and do not write, mutate, or overwrite `base` or equivalent identity fields outside the middleware-filled path. Manual construction or identity mutation routes to the implementation population check below — that check is carrier-neutral and runs even when this gate is not applicable.
   8. Per-diff proof covers touched, promoted, reused, or newly consumed messages. Existing untouched internal protobuf method messages are covered by citing a resolvable shared IDL owner inventory artifact or owner-suite sweep from item 3; if no owner inventory exists, create or link the tracked owner action and keep inventory coverage open instead of re-proving the full inventory in the service diff.
2. **Surface**: On a platform that has standardized the in-message `base` carrier (per the Carrier decision above), embedded `base` applies to every organization shared-IDL protobuf method message on that platform — this item governs intra-platform consistency once that carrier is chosen, not whether a platform must adopt it. A method exposed through JSON transcoding or a gateway still keeps the in-message `base` contract resolved from the shared IDL/IDLGen owner artifact unless a platform owner record affirmatively classifies the method as JSON-only. JSON-only suppression is reachable only through a committed platform owner gate that names the exact method messages and proves no binary consumer can silently consume a no-base message. The evidence must include: owner record locator; committed shared-IDL consumer registry path; current consumer set; exact registry/descriptor scan command recorded in that owner record; pasted run output; enforced CI/registry/import gate job or config path that blocks unregistered binary consumers; and enforced IDL/IDLGen generation-boundary gate job or config path that either preserves the owner-artifact `base` declaration when binary bindings are generated or fails generation for a JSON-only message. The cited gate must expose a stable command name, input registry id/path, expected pass output, and expected blocking output; freeform command names or undocumented local scripts are candidate evidence only. Routing, gateway, HTTP-transcoding config, import-site checks, or point-in-time consumer snapshots alone cannot satisfy the no-future-binary-consumer condition. Absent the owner gate and exact evidence above, JSON-only suppression is unavailable and, on a platform that has standardized the in-message `base` carrier, the in-message platform `base` field remains required for that platform's binary-consumed messages (intra-platform consistency, not a mandate that every gRPC platform adopt in-message `base` — see the Carrier decision above). A transcoded/gateway HTTP surface must cite `protobuf-http-contract-signals.md` evidence before deciding whether that HTTP face is JSON-wire or binary-protobuf. organization-internal protobuf RPC surfaces not generated from the platform shared IDL are open onboarding gaps until they onboard to the shared IDL or carry a platform owner record/disposition. JSON-wire HTTP surfaces follow the recorded response-envelope/API contract plus metadata/header propagation. Missing HTTP classification evidence is an open gap. Externally reachable owner exceptions still require egress zeroing and opaque external `LogId` remap.
3. **Inventory locator**: Base/tag/promotion/pin-affecting diffs must cite a shared IDL/IDLGen owner artifact outside the business service repo: repo/path, document URL, registry entry, or owner-suite id. The artifact must name the exact generated-artifact version and exact method message types. If the locator is not resolvable from the service repo, the bounded fallback is: link a tracked owner-unblock issue with owner; cite a committed CI, registry, or owner-suite gate that machine-checks the unblock issue id, deadline, and no-reuse constraint; attach local no-owner-pinned-tag-conflict evidence for the touched message; and treat only base/tag/promotion/pin-affecting changes as blocked. An expired, repeatedly reused, deadline-unenforced, or gate-unenforced owner-unblock issue is an open gap. Unrelated handler/service-logic changes remain not applicable.
4. **Field assertion**: Evidence must verify the touched or newly consumed message kind: edited or newly consumed request messages carry the shared platform `base.Request base` declaration, edited or newly consumed response messages carry the shared platform `base.Response base` declaration, and the field number matches the pinned number resolved from the cited shared IDL/IDLGen owner artifact. No business field may use the owner-pinned base field number except under a gate step 6 owner-recorded interim migration. In-diff descriptors pass only when their upstream shared IDL/IDLGen artifact provenance or hash for the pinned version actually consumed, not just a version label, is confirmed by repo-committed pin/lock/registry id, owner-suite, or registry for the exact message types. Service-local snippets, copied descriptors, uncited provenance, stale versions, wrong versions, or author-only version assertions are open gaps. Business-field-only edits may use the gate step 4 Field assertion light path only with a repo-committed pin/lock/registry id or owner-suite resolution for the consumed shared IDL artifact plus generated descriptor proving unchanged shared-platform `base` for the touched message kind and no field/reservation at the owner-pinned base field number outside a gate step 6 migration. Pure new consumption of an unchanged, already-pinned upstream method message may use the gate step 4 Field assertion light path only with repo-committed pin/lock/registry id or owner-suite resolution proving the artifact actually consumed by the service, plus generated descriptor evidence proving that consumed artifact declares the required shared-platform `base` field at the owner-pinned field number and no business field/reservation at that field number outside a gate step 6 migration; otherwise use the full path or keep stale/wrong artifact as an open gap. When the registry/locator is not resolvable from the service repo, the gate step 3 Inventory locator owner-unblock fallback satisfies this light path only for business-field-only edits or pure new consumption that attach both pinned-version artifact provenance evidence and machine-checked generated descriptor evidence proving the applicable base/tag assertion, do not touch `base`, the owner-pinned field number, promotion/reuse, or the effective generated-artifact version/provenance, and remain within the owner-unblock deadline; if upstream provenance is unverifiable or the deadline has passed, the fallback is an open gap, not pass.
   - Concrete check: attach schema-level descriptor evidence for the exact touched message kind. Passing evidence may be an executed FileDescriptorSet/FileDescriptorProto dump, a language-native descriptor API dump, a committed generated-descriptor artifact path plus artifact provenance, or a linked passing owner-suite/registry run for the exact shared IDL/generated-artifact version and exact message types. The evidence must show all of: field name `base`; field number equals the owner-pinned number resolved from the cited shared IDL/IDLGen artifact; request field message type resolves by fully-qualified name and package to the shared platform `base.Request`; response field message type resolves by fully-qualified name and package to the shared platform `base.Response`; and no other field or reservation uses that owner-pinned field number outside a gate step 6 migration. `.proto` source grep, raw text grep, and message-block snippets are candidate triage only; they cannot close the gate because they do not prove descriptor resolution or tag uniqueness. For generated-only consumers, use a language-native schema descriptor dump, such as Go `protoreflect`/`FileDescriptor` output or Python `_pb2.DESCRIPTOR`/`FileDescriptorProto` output, that exposes field name, number, fully-qualified message type, and package. Text grep over generated compiled artifacts such as `.pb.go`, `.pb.py`, or encoded descriptors is inconclusive and cannot pass. When descriptor tooling, committed generated descriptor artifacts, and owner-suite/registry access are all unreachable in diff-only review, record `coverage deferred to owner suite` with the exact owner action/link; do not report pass and do not turn unrelated service-logic diffs into automatic blockers unless this diff changed `base`, the owner-pinned field number, promotion/reuse, or the effective generated-artifact version/provenance.
5. **Metadata-channel carrier (first-class, not an exception)**: Any method may carry its metadata on the transport metadata/header channel instead of an in-message `base` field — this is the industry-standard default (per the Carrier decision) and needs no waiver. It is the norm for WKT, empty, and streaming messages that cannot embed `base`, and a valid choice for ordinary unary RPC on a platform that has not standardized in-message `base`. When this carrier is used: apply the R7 owner-recorded header-set contract (enumerated header names, checked against actual propagated/exposed headers) rather than the field-number gate; the observability contract (item above) and all boundary/egress/authz security controls still apply to that channel. The no-waiver carrier freedom above is scoped to **platforms that have NOT standardized in-message `base`, and new / not-yet-binary-published contracts**. It does **not** apply inside a base-standardized platform, where intra-platform consistency (item 2, Surface) exists specifically to protect binary consumers. On a platform that HAS standardized the in-message `base` carrier:

- A specific method (new or existing) goes metadata-only ONLY through the same owner-recorded exception that item 2 requires — proving no binary consumer silently expects `base` and the generation boundary preserves-or-blocks correctly — or through a platform-level item-6 migration off the standard. A bare descriptor/carrier record is not sufficient there; without the item-2 owner gate it is an open contract gap.
- Switching an **already-published or binary-consumed** method OFF its in-message `base` field is a wire-compatibility change, not a free carrier choice: it requires the item-6 collision-migration record (consumer-registry scan, old/new wire-compatibility tests, producer/consumer drain of readers still expecting `base`) before the field is removed. A descriptor/carrier record alone never authorizes dropping an established `base` field.
6. **Collision migration**: Business use of the owner-pinned base field number, service-local reservation of that number, or interim no-base state requires a platform-owner migration record with deadline, interim state, old/new wire compatibility tests, and producer drain/retirement precondition. Missing migration record or dual tag meaning is an open contract gap.
7. **Message shape**: Top-level method request/response types must not be reused as nested business payloads or as both request and response. Split distinct request/response and nested business messages. Promoting an existing message to top-level request/response reruns this gate; skipping it is an open contract gap.

For non-protobuf RPC variants and metadata-only transports, use the platform-pinned base struct, field id, or metadata key for that transport instead of applying protobuf field numbers. Field name, type, and field number are not local service choices. Business service repos and language-specific generated packages must not rename, renumber, retype, or replace these fields; regenerate from the shared IDL/IDLGen boundary instead. The protobuf `base` field name, type, and owner-pinned field number are fixed contract invariants; do not change them locally or treat regenerated artifacts as a migration path for renaming or renumbering the pinned `base` fields. A new non-protobuf or metadata-only transport must have a concrete platform-owner record for its pinned base struct, field id, or metadata key before service implementation; without that record, contract coverage is open and cannot be reported as passing. `../testing-strategy/SKILL.md` owns the contract-test obligation for asserting the generated declarations from this shared boundary.

### Metadata-carried base struct

The struct below describes the metadata set that must propagate on every hop (the observability/identity contract). It is the shape of the in-message `base` field **when the in-message carrier is used**; when a service propagates via the transport metadata channel instead (per the Carrier decision), the same fields ride gRPC/HTTP2 metadata headers under the R7 owner-recorded header-set contract. The field set and its security handling are identical; only the carrier differs.

The canonical RPC base struct carries:

```
base.Request {
  UnixTime    int64                      # ms since epoch (caller's clock)
  LogId       string                     # platform correlation id
  Tags        map[string]string {        # platform identity
    "idc":     <region or DC>
    "cluster": <k8s cluster name>
    "lane":    <lane/env label>
  }
  From        Request_InstanceInfo {     # caller identity, populated by client middleware
    ServiceName: <caller psm>
    PodName:     <caller pod name>
    IpAddr:      <caller pod IP>
  }
  To          Request_InstanceInfo {     # resolved callee identity (post-resolver)
    ServiceName: <callee psm>
    PodName:     <callee pod name>       # from registry instance tag
    IpAddr:      <callee instance addr>  # from resolver
  }
}
```

`base.Response` mirrors the metadata fields needed for internal response-side propagation (`LogId`, `Caller`, `IDC`, `Cluster`, `Tags`, `UnixTime`) and adds result metadata (`Code`, `Message`) using the platform error enum below. Response business payload remains in the response message's business fields, not inside `base.Response`. Boundary exposure must be classified from the service deployment/exposure record plus positive network/gateway/policy evidence before release; every recorded classification must cite the dated record/version of each governing deployment, mesh, gateway, and policy source, and a missing or unresolvable baseline version forces reclassification. For greenfield services before first deploy, target deployment manifests, mesh-injection policy, IaC, gateway policy, or release topology records may serve as planned-topology evidence, but this is a deferral and must be re-verified against the actual deployment/exposure record before first release or any external exposure. Planned-only classification is not a release pass. If an external or gateway path exists, remains unknown, or internal-only classification is unverified, use the external-safe middleware path and keep unresolved classification as an open release gap. External-safe implementation evidence must cite a concrete platform middleware package, generated middleware binding, gateway policy, or platform owner record; citing this prose recipe alone is not implementation evidence. At external or gateway ingress, middleware must discard caller-supplied `base.Request` identity fields and mirrored metadata/header identity fields, reset or regenerate caller-supplied `LogId`, and drop or overwrite caller-supplied `Tags` unless positive runtime authenticated-caller evidence exists and the tag key/value is in the owner-approved allowlist. Tags/header allowlists must cite a concrete platform owner-approved allowlist record, gateway policy, or owner-suite id; an uncited or service-local allowlist is an open gap. On any surface, base/header identity is not caller authentication: using caller-supplied `From`, `Caller`, `LogId`, `Tags`, or mirrored identity headers for authz, caller attribution, or tag routing requires positive runtime authenticated-caller evidence such as mTLS identity or signed platform identity; internal-only network evidence or a static owner record alone is not enough. External/gateway ingress must reset or regenerate caller-supplied `LogId`; internal-only propagation may keep correlation-only log-id only when the deployment/exposure record and runtime mesh/platform identity prove an internal authenticated caller path, and that log-id is not used for authz, caller attribution, or tag routing. At external or gateway egress, middleware must default to zeroing all internal `base.Response` metadata fields and removing all base identity/metadata fields from mirrored metadata/header channels or request-base echo. The only allowed external values are owner-approved opaque external `LogId` values that are unique, non-reused, collision-checked independent random tokens stored in the owner remap table and resolvable external-to-internal only through that table, never the internal `LogId`, a deterministic derivation of it, or a token recomputable from service-local keys; a token previously issued for one internal `LogId` must be retained as a tombstone or exclusion entry and must not be recycled to another internal `LogId` after cleanup or expiry. Metadata-only result channels may carry mapped public `Code` and only fixed public `Message` strings keyed by that mapped `Code` when a concrete owner-approved allowlist record, gateway policy, or owner-suite locator enumerates those strings; any uncited, service-local, or non-allowlisted message string is an external leak, not a mapped message. `base.Response` is an internal-mesh contract, not an external API payload. When a service carries this identity/result metadata on the transport metadata/header channel instead of an in-message `base.Response` field (per the Carrier decision), every ingress-discard, egress-zeroing, opaque-`LogId`-remap, public-`Code`/`Message` allowlist, and caller-identity-is-not-authentication control above applies unchanged to that channel — the carrier changes, the controls do not.

`From` and `To` are richer than a typical "caller string" — both ends include service identity + pod name + IP. This makes trace analysis simpler:

- Filter logs by `From.PodName` to find every outbound call from one specific replica.
- Filter traces by `To.IpAddr` to find calls that landed on a specific callee pod.
- Build per-pod call graphs without joining external pod metadata.

Client middleware populates the struct on every outbound RPC. On a platform that uses the in-message `base` carrier, the generated request/response `base` field is the contract source; middleware may mirror log-id, lane, and related context into HTTP/2 metadata for propagation compatibility, and handlers and contract tests assert the generated message field and end-to-end propagation. When a service propagates via the transport metadata channel instead (per the Carrier decision), the metadata headers *are* the contract source: middleware populates them, and contract tests assert the R7 owner-recorded header set and end-to-end propagation rather than an in-message `base` field. Either way, service code never touches the identity fields directly.

### Boundary-exposure classification — canonical trigger set, rerun, and local-relaxation bar

Classification evidence, dispositions, and the executable probes live in the `Metadata-carried base struct` section (the `base.Response` paragraph) and the `Verification` section (2a/3a–3d) of this file; this subsection lists the canonical boundary trigger set, rerun conditions, and the local-relaxation bar so stack dev skills, testing verdicts, and review all classify on the same triggers.

Triggers — run boundary-exposure classification before release when any fires:

- ingress/egress reachability change;
- deployment/exposure/boundary metadata or external/gateway classification change that changes or invalidates classification;
- log-id response-header value path change (how the log-id value is produced or remapped, independent of exposure);
- CORS or log-id response-header exposure change;
- `base.Response` metadata-field population change on a boundary-reachable, exposure-changed, or unknown surface without current internal-only evidence;
- response header mirroring/exposure without current or planned internal-only evidence;
- egress mapping without current or planned internal-only evidence;
- first deployment/exposure records after planned topology;
- caller-supplied base/header/tag identity used for authz, caller attribution, or tag routing without positive authenticated-caller evidence.

Rerun classification on exposure-metadata changes, first release after planned topology, CORS/log-id exposure changes, egress behavior changes, or changed platform exposure records.

- Freshness bar: an unchanged internal surface with an existing classification discharges the trigger by freshness citation only, and that citation must be dated **at or after the change under review** for every governing deployment, mesh, gateway, and policy record. An older dated baseline is stale, not fresh; absent verifiable freshness, rerun classification or default to the external-safe path.

Changes that write, mutate, mirror, expose, or remap `base`, `base.Response`, `LogId`, caller, `From`, `To`, `Tags`, or equivalent identity fields are not freshness-only changes.

Do not locally relax identity-discard, metadata-zeroing, public-result mapping, authenticated-caller-evidence, or allowlist-owner-record rules.

External/vendor gRPC dependencies follow external-contract review with a recorded classification and must not be claimed as organization shared-IDL compliant.

### Implementation population check (carrier-neutral)

- Handler, route, view, adapter, or DTO diffs that manually construct generated request/response DTOs outside the middleware-filled path, or write/mutate/overwrite `base`, `LogId`, caller, `From`, `To`, `Tags`, or equivalent identity fields on generated DTOs, must provide executed-test or runtime evidence tied to the touched path proving the chosen contract source (the in-message `base` field, or — on a metadata-carrier service — the R7 owner-recorded header set) is populated from platform context and caller-supplied identity is not propagated without positive authenticated-caller evidence; static population code or a generic middleware citation is not enough. This evidence obligation is carrier-neutral: a metadata-carrier service is not exempt — it proves the header set instead of the `base` field. Missing evidence is an open implementation gap. Do not hand-create alternative metadata structs or schemas, mutate middleware-owned identity fields in app code, or skip them in manual generated DTO construction.

## Dual-channel ctx propagation

The example below shows `log-id` and `lane` only, as the minimal **compatibility mirror** — it is NOT the full metadata-carrier contract. When the transport metadata channel is the *contract source* (per the Carrier decision), the owner-recorded R7 header set must cover **the full metadata set the in-message `base` carrier would have carried** — every `base.Request` field as enumerated in the base-struct schema below (`LogId`, `lane`, caller identity, the `{idc, cluster}` tags, `UnixTime`, and the `From`/`To` peer identity) and, response-side, every `base.Response` field (the mirrored request metadata plus result `Code`/`Message`) — not just log-id/lane, with contract tests asserting each header propagates and (at a boundary) is exposed/zeroed correctly. Any intentional omission of a field the base carrier would have carried needs an owner exception, exactly as dropping a `base` sub-field would. Omitting caller identity, tags, timing, resolved-peer, or result metadata because the example only shows log-id/lane is a propagation bug.

For frameworks that support a parallel metadata transport (CloudWeGo metainfo alongside standard gRPC HTTP/2 metadata), client middleware writes log-id and lane into BOTH:

```go
// Channel 1: CloudWeGo metainfo (preferred)
ctx = metainfo.WithPersistentValue(ctx, "<log-id-key>", logId)
ctx = metainfo.WithPersistentValue(ctx, "<lane-key>", lane)

// Channel 2: standard gRPC outgoing metadata (compatibility)
ctx = metadata.AppendToOutgoingContext(ctx, "<log-id-key>", logId)
ctx = metadata.AppendToOutgoingContext(ctx, "<lane-key>", lane)
```

Server middleware tries both inbound channels, falling back as needed:

```go
1. Try incoming gRPC metadata (md.Get("<log-id-key>"))
2. If empty, try metainfo.GetPersistentValue
3. If still empty, generate a new log-id at server side
```

Why dual-channel: services may have mixed framework versions during rollout. A new client writing to channel A and an old server reading only channel B silently drops log-id. Writing to both bridges the gap until everyone is on one version.

## Standard error code enum

Match HTTP semantics where possible; pick distinct codes for framework-internal errors:

```
Code_Default       = 0     # unset / default
Code_OK            = 200   # success
Code_InvalidParams = 400   # validation
Code_Unauthorized  = 401   # auth missing/invalid
Code_Forbidden     = 403   # authz denied (incl. mesh ACL)
Code_NotFound      = 404
Code_ServerError   = 500   # generic server failure
Code_ServerPanic   = 503   # framework caught a panic
Code_Timeout       = 504   # RPC timeout (transport or business)
```

`503` is HTTP "Service Unavailable" but here serves "ServerPanic" — close enough semantically; pick a code and stick to it across all languages.

Code enum is a Go constants (or language-equivalent enum). The same numeric value across languages enables cross-service error filtering by code in metrics and logs.

## Framework error mapping (server side)

Map the underlying framework error types to your code enum:

```
kerrors.ErrBiz                  → Code_ServerError (500)  # business error, unwrap
kerrors.ErrPanic                → Code_ServerPanic (503)  # include stack in message
kerrors.ErrACL                  → Code_Forbidden  (403)
kerrors.ErrRPCTimeout           → Code_Timeout    (504)
kerrors.ErrTimeoutByBusiness    → Code_Timeout    (504)
<anything else>                 → Code_ServerError (500)
```

The error handler wraps the result as a `*Error{code, msg}` and serializes it into the transport error slot. **New services use the canonical carrier: `google.rpc.Status` with `details` (transported via the `grpc-status-details-bin` trailer or the framework's native details mechanism) — see `go-microservice-architecture/references/error-contract-architecture.md` "Cross-RPC Envelope".**

> **Legacy carrier — do not adopt for new work.** Older framework builds pack the wrapper as JSON into the freeform `status.Message()` string (`{"code": N, "message": "..."}`) and re-parse it on the client. That string is size-limited, not a structured channel, loses typed retry/security semantics, and risks leaking server-rendered text — the anti-pattern the canonical error-contract rule forbids. It reflects a pre-migration framework reality (the same JSON-in-status-message drift that shared-IDL error-contract alignment is migrating off); keep it here only to explain existing wire traffic, and migrate to `grpc-status-details-bin` details.

## Framework error mapping (client side)

Client-side handler converts the wire error back into a typed error. **Canonical**: parse `google.rpc.Status` `details` from the `grpc-status-details-bin` trailer (or framework details mechanism), reconstruct the typed error, and if the payload is not the canonical shape wrap it as a transport/unknown error without dropping the original cause.

```
# Legacy fallback for the JSON-in-status-message carrier above — do not build new services on this:
1. If wire status carries a structured error (gRPC status.Error):
     a. Try parsing status.Message() as `{"code": N, "message": M}` JSON.
     b. If parses, return that structured error.
     c. Else wrap as Code_ServerError with status.Message() as msg.
2. If local error (transport failure, etc.):
     wrap as Code = -1, message = err.Error()
```

Result: caller sees a uniform `*Error` regardless of where the failure occurred (peer panic vs. local network blip).

## Default server middleware chain (Kitex)

```
server.WithErrorHandler(ServerErrorHandler)          # error type-mapping
server.WithMiddleware(NewMetricsMW(isServer=true))   # qps + latency + err + panic counters
server.WithMiddleware(NewCtxInjectMW(isServer=true)) # extract log-id, lane from metadata
server.WithMiddleware(NewRequestInfoLogMW(true))     # request/response logging (env-gated)
# plus:
server.WithSuite(tracing.NewServerSuite())           # OTel server tracing (only in cloud)
server.WithMetaHandler(transmeta.ServerHTTP2Handler) # transport meta handling
server.WithRegistry(<nacos registry>)                # only if in-cloud or LOCAL_HOST set
```

## Default client middleware chain (Kitex)

```
client.WithClientBasicInfo(...)                       # caller identity
client.WithTransportProtocol(transport.GRPC)          # default gRPC
client.WithMetaHandler(transmeta.ClientHTTP2Handler)
client.WithResolver(<nacos resolver, or FQDN fallback, or proxy resolver>)
client.WithSuite(tracing.NewClientSuite())            # OTel client tracing

client.WithErrorHandler(ClientErrorHandler)
client.WithMiddleware(NewMetricsMW(isServer=false))
client.WithMiddleware(NewCtxInjectMW(isServer=false)) # generate/propagate log-id
client.WithMiddleware(NewClientBaseInjectMW())        # request-metadata inject: on an in-message-base platform populates base.Request{From,To,Tags,LogId,UnixTime}; on a metadata-carrier service the SAME middleware populates the R7 owner-recorded metadata/header set with the same full field set instead
client.WithMiddleware(NewRequestInfoLogMW(false))
```

The `NewClientBaseInjectMW` step above is the concrete injector for the **in-message `base` carrier**. On a metadata-carrier service (the default for ordinary gRPC — see the Carrier decision), substitute a request-metadata injector that writes the same full field set into the owner-recorded metadata/header channel, and have the server middleware extract from that channel; the chain position and obligation are identical, only the carrier target differs.

## Default server middleware chain (Hertz / HTTP)

Order differs from RPC because Hertz uses linear middleware (not endpoint wrapping):

```
1. ctx_inject     # read <log-id-header>, generate if missing, write to response header, inject into ctx
2. recovery       # panic catch (wraps subsequent middleware + handler)
3. metrics        # timer start, c.Next, then record qps + latency + error
4. tenant_info / business middleware (optional)
5. tracing middleware (if cloud)
6. handler
```

Difference from RPC order: HTTP places recovery BEFORE metrics, since recovery wraps `c.Next` and catches panics that would otherwise crash the metric recording. The recovery handler also emits a uniform 500 response with the standard error envelope `{"code": Code_ServerPanic, "message": "server panic: ..."}`.

## Metric label discipline (RPC pair)

For every RPC, emit metrics with the baseline labels plus pair-specific labels:

```
baseline: psm, lane, idc, cluster, pod_name, pod_ip, node_ip
RPC-pair: caller (name, cluster, env, method)
          callee (name, cluster, env, method)
on error: err_code (one of the enum values)
```

The full label set gives operators per-method per-pair per-env breakdowns. Cardinality is bounded by `services × methods × envs`, typically thousands — well within metric-store capacity.

Standard metric names:
- `<framework>_server_method_qps` — request count by method.
- `<framework>_server_method_latency_seconds` — histogram with platform-default buckets (see below).
- `<framework>_server_method_success_rate` — success counter.
- `<framework>_server_method_err_qps` — error counter (with `err_code` label).
- `<framework>_client_invoke_qps` / `latency_seconds` / `success_rate` / `err_qps` — same shape, caller side.
- `service_panic` — panic counter (per api path/method).
- `<framework>_server_api_qps` / `latency_seconds` / `err` / `success_rate` — HTTP-side equivalents.

## Latency histogram buckets

Platform-wide default in seconds:

```
[0, 0.05, 0.1, 0.2, 0.3, 0.5, 0.7, 1, 1.5, 2, 3, 5, 10, 15, 20, 30, 60, 120]
```

18 buckets, dense in 0-1s range (where most user-facing API latencies live), sparse from 1s-2min for long-tail and batch operations. Per-method override allowed but rare.

## Resolver strategies (when registry is the source of truth)

Three resolver implementations co-exist; clients pick based on need:

### A) Direct registry resolver
Standard: query registry for callee instances filtered by lane tag. Default for in-cluster RPC.

### B) FQDN fallback resolver
Wraps the registry resolver; if the registry returns no instances, falls back to k8s DNS FQDN:

```
callee psm "<owner>.<class>.<env>"
  → replace dots/underscores with hyphens → "<owner>-<class>-<env>"
  → FQDN: "<owner>-<class>-<env>.<owner>.svc.cluster.local:<port>"
```

Use when the platform is migrating from k8s-DNS to registry; gives a soft fallback during migration.

**Lane-safety constraint**: the FQDN fallback bypasses registry lane-tag filtering — `<callee>.svc.cluster.local` resolves to ALL backend pods regardless of lane. If a caller in `lane=canary` falls through to FQDN because the registry temporarily returns no canary instances, the request lands on default-lane pods, defeating canary isolation. Mitigations (pick at least one):
- **Fail closed for non-default lanes**: only the default lane uses FQDN fallback; lanes with non-empty headers get an explicit `no_instance` error.
- **FQDN fallback only through mesh**: the request still carries the lane header, and the mesh VirtualService routes based on header — so even a "raw" FQDN call lands on the right subset via Envoy. Requires the mesh + lane VS to be the unconditional layer, not opt-in.
- **Disable FQDN fallback after migration completes**: useful as a transitional aid; harmful as a steady-state behavior.

### C) Proxy resolver
Returns instances of a dedicated proxy service (e.g. `<infra>.proxy.rpc`) instead of the real callee. The proxy then forwards based on the request's original target.

Use when:
- Cross-cluster traffic needs central observability.
- Specific calls need traffic shaping outside mesh.
- Migration scenarios where you want to inject behavior in front of a callee without modifying its clients.

Set per-client at registration time; not switched per-call.

## CORS defaults (HTTP gateway)

For services exposed to browsers, the framework provides default CORS middleware. **Default must NOT combine `AllowAllOrigins: true` with `AllowCredentials: true`** — browsers reject `Access-Control-Allow-Origin: *` when credentials are sent, AND frameworks that reflect the request Origin grant credentialed cross-origin access to arbitrary sites. The mature default:

```
AllowOrigins:          [<explicit allowlist>]   # never wildcard with credentials
AllowOriginFunc:       <validator function>     # optional, per-domain logic
AllowCredentials:      <true only when allowlist is non-wildcard>
ExposeHeaders:         [<log-id-header>, Content-Encoding, Date, Connection]
MaxAge:                12 hours
AllowWildcard:         <only when AllowCredentials=false>
AllowBrowserExtensions: true
AllowWebSockets:       true
AllowFiles:            false
```

Two acceptable defaults:
- **Internal-only service** (no public browser exposure): `AllowOrigins: []` (CORS disabled or restricted to specific internal hostnames).
- **Public service**: explicit allowlist of allowed origins; `AllowCredentials` only if the API genuinely needs cookies/credentials.

**Critical**: CORS log-id exposure is part of the boundary-exposure gate. `ExposeHeaders` lists the log-id header name that browser code may read. Any browser-exposed log-id must be an owner-approved opaque remapped id, never the internal `LogId`; browser clients are not authenticated mesh peers even on internal-only browser surfaces. Browser/CORS-exposed responses must not expose any base identity fields, including allowlisted Tags; the Tags allowlist applies only to proven internal authenticated-caller propagation, not browser egress. Without an exposed support id, browser cross-origin code cannot report failures back to support; without the remap, the response leaks internal trace identity.

The framework MAY ship an "open" preset for local dev (`AllowAllOrigins: true, AllowCredentials: false`) but production deployment MUST flip to the explicit allowlist. A linter or admission gate that rejects production manifests with `AllowAllOrigins: true && AllowCredentials: true` is recommended.

**`AllowOriginFunc` is equally dangerous.** A permissive validator (e.g. one that does substring match on a domain or trusts any `*.example.com`) combined with `AllowCredentials: true` lets an attacker-controlled subdomain or look-alike host issue credentialed cross-origin requests. Production admission must:
- Reject `AllowOriginFunc` that doesn't exact-match against a reviewed allowlist.
- Reject any combination of `AllowCredentials: true` with `AllowOriginFunc` whose source isn't pinned in code review.
- Require security review for any change to the CORS validator function on production-public services.

Treat the effective origin policy — not just the `AllowAllOrigins` flag — as the security boundary.

## Local dev support

The framework default ON-CLOUD path:
- Connects to registry, registers self.
- Enables OTel tracing with collector endpoint.
- Reports metrics via collector OTLP exporter.

The framework default OFF-CLOUD path:
- Skips registry registration unless `LOCAL_HOST` env var is set (lets a dev choose to register from laptop for cross-machine testing).
- Detects "inner IP" via a configured CIDR (typically a /24 subnet on the dev network) for service-to-service addressing.
- Disables OTel tracing (avoid noise + no collector to reach).
- Logs still emit to stdout / file; reading via `tail` works.

The on-cloud / off-cloud branch is controlled by a single `env.InCloud()` predicate. Local dev "just works" by default; opting into cross-machine local testing requires one env var.

## Server boot sequence

```
1. Initialize logger (zap with platform field schema).
2. Initialize metrics client (OTel SDK + OTLP exporter, only if in-cloud).
3. Read env vars: SERVICE_NAME, SERVICE_PORT, LANE, IDC, CLUSTER, POD_NAME, POD_IP.
4. Construct server with DefaultServerOptions (which appends all the middleware above).
5. Register routes (handler functions).
6. Spin (start serving).
7. On termination signal:
     a. Begin graceful shutdown (stop accepting new requests).
     b. Drain in-flight requests (with grace period).
     c. Close registered closers (TracerProvider, collector exporter, etc.).
     d. Flush logs.
     e. Exit.
```

The framework provides the deferred shutdown function; service code calls it via `defer deferFunc()`.

## Verification

Per-aspect checks the framework default MUST satisfy:

```
# 1. Static — middleware chain present
grep -E "WithErrorHandler|WithMiddleware\(.*(Metrics|CtxInject|RequestInfoLog|BaseInject|Recovery)" <default-options-file>
# expect: 5+ hits for kitex, 4+ for hertz

# 2. Live — internal-only log-id round-trip
curl -i -X POST <service-ping-url> -H "<log-id-header>: my-test-id"
# require a fresh internal-only classification citation: deployment/exposure record locator, mesh policy id, gateway policy, IaC path, release topology record, or previously approved owner-suite record whose dated baselines still match the current deployment, mesh, gateway, and policy records
# hard stop: if the response echoes caller-supplied "<log-id-header>: my-test-id", raw preservation remains an open gap until probe 2a or equivalent owner-suite evidence proves authenticated internal caller identity and confirms the log-id is correlation-only
# on unrelated unchanged-internal-surface changes, this curl is a freshness smoke only; cite the fresh internal classification and do not claim raw log-id preservation behavior changed
# if the change touches exposure, CORS, log-id value path, external/gateway classification, caller identity use, or the classification baseline is missing/stale, run probe 2a and the transport-appropriate egress probe (3b/3c/3d)
# if the surface is browser/CORS-exposed, raw log-id echo is not a pass; run the opaque-remap probe and CORS log-id rule instead

# 2a. Runtime/integration — authenticated internal caller identity for raw log-id preservation
<metadata-aware-probe> --auth-path mesh-or-platform --header "<log-id-header>: my-test-id" <service-target>
# required when the diff touches exposure, CORS, log-id value path, external/gateway classification, caller identity use, or when the internal-only classification baseline is missing/stale; if it cannot pass, reset or regenerate caller-supplied log-id
# require positive runtime mesh/platform authenticated-caller identity evidence for this request, such as mTLS identity, signed platform identity, or owner-suite output that records the authenticated caller principal
# expect: the same correlation log-id is preserved only on the authenticated internal path, and the log-id is not used for authz, caller attribution, or tag routing
# negative case: when an unauthenticated or auth-stripped path is reachable, run the same probe through that path; caller-supplied "<log-id-header>: my-test-id" must be reset or regenerated. Preserving the raw caller-supplied log-id on the unauthenticated path is a failure. If no unauthenticated path exists, cite dated deployment, mesh, gateway, and policy classification evidence plus a release-time owner-suite or integration artifact, dated at or after the final deployment/route topology, that machine-verifies no unauthenticated/auth-stripped route reaches the surface; static owner records or author assertions alone are not sufficient. Otherwise 2a remains open and the implementation must reset or regenerate log-id on all paths.
# absent this probe or equivalent owner-suite evidence on a triggered change, probes 2 and 3 remain open gaps even if the curl smoke shows echo/generation behavior

# 3. Live — server-side log-id generation
curl -i -X POST <service-ping-url>
# require the same fresh internal-only classification citation as probe 2
# candidate-only expect: response header includes a server-generated log-id on that proven internal-only surface
# if the change touches exposure, CORS, log-id value path, external/gateway classification, caller identity use, or the classification baseline is missing/stale, run probe 2a and the transport-appropriate egress probe (3b/3c/3d)
# if the surface is browser/CORS-exposed, a raw internal server log-id is not a pass; run the opaque-remap probe and CORS log-id rule instead
```

```
# 3a. Static — external/gateway/browser-exposed log-id remap provenance
# required before any external/gateway or browser-exposed remap probe in 3b/3c/3d can pass; a green live response is not a substitute for token provenance
# require source file/function locator proving the token issuance path uses cryptographic RNG output that flows into the persisted external token, such as Go crypto/rand, Python secrets, or an approved server-side platform CSPRNG; idempotent-mode egress reads may be table reads, but first issuance is still the CSPRNG draw point. Merely importing or naming a CSPRNG API is not enough, and non-CSPRNG sources are open gaps.
# require source file/function locator proving external-to-internal resolution uses table-only lookup and cannot recompute the token from internal LogId plus service-local keys; an unresolvable locator, recompute-capable path, deterministic/token-derived generator, or unverified issuance path is an open gap, not pass
```

```
# 3b. HTTP/JSON external/gateway/browser-exposed log-id remap
# tiering: source/static provenance is 3a; unit/component invariants below require separate committed test evidence with file path/line and command; the curl probe is only the live exposure/remap smoke and cannot satisfy the unit/component seam requirements by itself
curl -i -X POST <service-ping-url> \
  -H "<log-id-header>: my-test-id" \
  -H "<non-allowlisted-base-identity-header>: caller-supplied" \
  -d '{"<base-json-name>":{"<log-id-json-name>":"body-test-id","<caller-json-name>":"caller-supplied","<tags-json-name>":{"<owner-approved-tag>":"allowed-value","non_allowlisted":"caller-supplied"}}}'
# hard precondition: JSON field names come from the generated descriptor's json_name or gateway contract, and a server log/echo/owner probe proves the injected base values were decoded; without this artifact, do not evaluate negative expectations and treat the inconclusive result as an open release gap, not pass
# require a paired internal/server-log lookup for this request; opaque-id format checks are additional evidence, not a substitute
# if the paired lookup is missing or inaccessible, remap is unverified and remains an open gap
# require static gate 3a to pass for the same remap implementation under test
# require one executed unit/component test that exercises the unmocked production token generator and asserts token length/format per owner record; uniqueness/collision safety is proven by the forced-collision test below
# component/live: with no existing remap row for a fresh internal LogId, first external/gateway or browser-exposed egress must issue and persist a CSPRNG-backed opaque token and expose that token, never the internal LogId or an empty/fallback id
# expect: every exposed support log-id is the same owner-approved opaque random token, none equal "my-test-id", "body-test-id", or the paired internal LogId, and the owner remap table resolves it back to that paired internal LogId
# repeat with a second request whose paired internal LogId differs; expect a different opaque support id that resolves to the second internal LogId
# unit/component: resolve the owner mapping mode first (idempotent vs per-request); if unknown, the assertion is inconclusive and remains an open gap. For per-request mode, inject the same fixed internal LogId directly into the remap function twice and expect different unpredictable external tokens. For idempotent mode, prove the same token is returned by table read after a prior independent random-token insert; then delete, hide, or isolate that stored row, re-invoke token issuance for the same internal LogId, and expect a different CSPRNG-issued token. Table-read consistency or delete-then-resolve failure alone is not proof of non-recomputation.
# unit/component: in idempotent mode, require one-external-token-per-internal-LogId via a unique constraint or atomic upsert keyed by internal LogId; run a forced concurrent same-internal-LogId first-egress test and expect only one external token is persisted and every caller receives or resolves to that same token
# unit/component: require no-external-token-reuse-across-distinct-internal-LogIds via a unique constraint or explicit atomic compare-and-set on the external-token column itself, so reverse-resolution cannot be ambiguous. Resolve the production conflict-handling mode first (regenerate vs reject); if unknown, the assertion is inconclusive and remains an open gap. For every mapping mode, prove a concrete duplicate external-token conflict across two different internal LogIds reaches the production uniqueness guard: use a controlled test seam where token issuance returns the pre-seeded colliding value first and then a real CSPRNG value, invoke the production remap creation/insert path with a pre-seeded duplicate external token, or inject the duplicate at the remap persistence/insert function while preserving the production uniqueness guard and 3a CSPRNG provenance evidence. In idempotent mode, this forced duplicate must reach the persistence/insert uniqueness guard; an issuance-only seam is not proof of the external-token constraint. Happy-path concurrency without a forced duplicate is not enough. Assert the branch that production actually takes. On regenerate, persist only a distinct token for the new request, never expose or persist the colliding token for the new request, and reverse-resolve the final token to the new request's paired internal LogId, not the pre-seeded row. On reject, expose no support id and zero egress identity; the internal LogId and colliding token must not appear in headers, metadata, body, logs returned to clients, or request-base echo. In idempotent mode, reject without retry is an open gap and not a pass unless a resolvable platform owner waiver records the no-support-id behavior, owner, scope, future deadline, and a CI-enforceable expiry gate. Diff-resident review evidence for that gate is the committed CI job/config line plus committed test file path/line asserting both pre-deadline pass and post-deadline fail through an injected clock or simulated date. Release pass additionally requires demonstrably blocking enforcement at waiver creation time: paired green required-pipeline run output plus required-pipeline, branch-protection, or merge-blocking status evidence. If that blocking enforcement is missing, stale, advisory-only, or non-blocking, the waiver remains an open release gap. Otherwise prove retry-to-accepted distinct token. In idempotent mode, also prove the final accepted token is stored for the new internal LogId and later returned by table read, not recomputation. For cleanup/expiry, prove expired external tokens remain in a tombstone or exclusion set and are rejected if generated again for a different internal LogId.
# expect on a proven internal propagation channel with positive runtime authenticated-caller evidence and a cited owner allowlist: the owner-approved Tag is preserved internally, and non-allowlisted Tags are absent; without authenticated-caller evidence, caller-supplied Tags are dropped or overwritten even when the key/value is allowlisted
# expect on external/gateway or browser-exposed egress: response body/base fields do not reflect caller-supplied base identity; all base.Response Tags are absent
# expect: response headers are allowlist-only; any non-allowlisted base identity header, caller-supplied identity value, internal base identity value, or substring of Caller/From/IDC/Cluster/Tags/LogId fails
```

```
# 3c. Binary-protobuf gRPC external/gateway/browser-exposed metadata remap
# tiering: source/static provenance is 3a; unit/component invariants below require separate committed test evidence with file path/line and command; the grpcurl probe is only the live exposure/remap smoke and cannot satisfy the unit/component seam requirements by itself
grpcurl \
  -H "<log-id-header>: my-test-id" \
  -H "<non-allowlisted-base-identity-header>: caller-supplied" \
  -d '{"<base-json-name>":{"<log-id-json-name>":"body-test-id","<caller-json-name>":"caller-supplied","<tags-json-name>":{"<owner-approved-tag>":"allowed-value","non_allowlisted":"caller-supplied"}}}' \
  <service-grpc-target> <service>/<method>
# hard precondition: proto-JSON field names come from the generated descriptor's json_name, and a server log/echo/owner probe proves the injected base values were decoded; without this artifact, do not evaluate negative expectations and treat the inconclusive result as an open release gap, not pass
# require a gRPC-aware probe that dumps response metadata and trailers plus a paired internal/server-log lookup for this request
# if the paired lookup is missing or inaccessible, remap is unverified and remains an open gap
# require static gate 3a to pass for the same remap implementation under test
# require one executed unit/component test that exercises the unmocked production token generator and asserts token length/format per owner record; uniqueness/collision safety is proven by the forced-collision test below
# component/live: with no existing remap row for a fresh internal LogId, first external/gateway or browser-exposed egress must issue and persist a CSPRNG-backed opaque token and expose that token, never the internal LogId or an empty/fallback id
# expect: response metadata/trailers are allowlist-only; every exposed support log-id across metadata/trailers and decoded body is the same owner-approved opaque random token, none equal "my-test-id", "body-test-id", or the paired internal LogId, and the owner remap table resolves it back to that paired internal LogId
# repeat with a second request whose paired internal LogId differs; expect a different opaque support id that resolves to the second internal LogId
# unit/component: resolve the owner mapping mode first (idempotent vs per-request); if unknown, the assertion is inconclusive and remains an open gap. For per-request mode, inject the same fixed internal LogId directly into the remap function twice and expect different unpredictable external tokens. For idempotent mode, prove the same token is returned by table read after a prior independent random-token insert; then delete, hide, or isolate that stored row, re-invoke token issuance for the same internal LogId, and expect a different CSPRNG-issued token. Table-read consistency or delete-then-resolve failure alone is not proof of non-recomputation.
# unit/component: in idempotent mode, require one-external-token-per-internal-LogId via a unique constraint or atomic upsert keyed by internal LogId; run a forced concurrent same-internal-LogId first-egress test and expect only one external token is persisted and every caller receives or resolves to that same token
# unit/component: require no-external-token-reuse-across-distinct-internal-LogIds via a unique constraint or explicit atomic compare-and-set on the external-token column itself, so reverse-resolution cannot be ambiguous. Resolve the production conflict-handling mode first (regenerate vs reject); if unknown, the assertion is inconclusive and remains an open gap. For every mapping mode, prove a concrete duplicate external-token conflict across two different internal LogIds reaches the production uniqueness guard: use a controlled test seam where token issuance returns the pre-seeded colliding value first and then a real CSPRNG value, invoke the production remap creation/insert path with a pre-seeded duplicate external token, or inject the duplicate at the remap persistence/insert function while preserving the production uniqueness guard and 3a CSPRNG provenance evidence. In idempotent mode, this forced duplicate must reach the persistence/insert uniqueness guard; an issuance-only seam is not proof of the external-token constraint. Happy-path concurrency without a forced duplicate is not enough. Assert the branch that production actually takes. On regenerate, persist only a distinct token for the new request, never expose or persist the colliding token for the new request, and reverse-resolve the final token to the new request's paired internal LogId, not the pre-seeded row. On reject, expose no support id and zero egress identity; the internal LogId and colliding token must not appear in headers, metadata, body, logs returned to clients, or request-base echo. In idempotent mode, reject without retry is an open gap and not a pass unless a resolvable platform owner waiver records the no-support-id behavior, owner, scope, future deadline, and a CI-enforceable expiry gate. Diff-resident review evidence for that gate is the committed CI job/config line plus committed test file path/line asserting both pre-deadline pass and post-deadline fail through an injected clock or simulated date. Release pass additionally requires demonstrably blocking enforcement at waiver creation time: paired green required-pipeline run output plus required-pipeline, branch-protection, or merge-blocking status evidence. If that blocking enforcement is missing, stale, advisory-only, or non-blocking, the waiver remains an open release gap. Otherwise prove retry-to-accepted distinct token. In idempotent mode, also prove the final accepted token is stored for the new internal LogId and later returned by table read, not recomputation. For cleanup/expiry, prove expired external tokens remain in a tombstone or exclusion set and are rejected if generated again for a different internal LogId.
# expect on a proven internal propagation channel with positive runtime authenticated-caller evidence and a cited owner allowlist: the owner-approved Tag is preserved internally, and non-allowlisted Tags are absent; without authenticated-caller evidence, caller-supplied Tags are dropped or overwritten even when the key/value is allowlisted
# expect on external/gateway or browser-exposed egress: decoded protobuf response body has external-safe base.Response fields; caller-supplied identity and all Tags are not reflected, internal identity fields are zeroed or absent, and any exposed log-id is the owner-approved opaque id, not "my-test-id", "body-test-id", or the paired internal LogId
```

```
# 3d. Metadata-only or non-protobuf external/gateway/browser-exposed transport
# tiering: source/static provenance is 3a; unit/component remap invariants require separate committed test evidence with file path/line and command; the metadata-aware probe is only the live exposure/remap smoke
<metadata-aware-probe> --metadata "<log-id-key>=my-test-id" --metadata "<non-allowlisted-base-identity-key>=caller-supplied" <service-target>
# require a probe that exercises the transport's platform-owner-recorded metadata keys and dumps response metadata/trailers/header channels
# hard precondition: server log/echo/owner probe proves the injected metadata/base values were decoded; without this artifact, do not evaluate negative expectations and treat the inconclusive result as an open release gap, not pass
# require a paired internal/server-log lookup for this request; if missing or inaccessible, remap is unverified and remains an open gap
# require static gate 3a to pass for the same remap implementation under test
# require unit/component remap tests for same-internal-LogId token independence and pre-seeded collision handling as defined in 3b/3c
# expect: same paired-log remap, support-id same-value across channels, allowlist-only, allowlisted-Tag-preserved only for proven internal propagation with runtime authenticated-caller evidence, non-allowlisted-Tag-dropped, and no caller-supplied identity reflection checks as 3b/3c
# absent such a probe, metadata-only egress coverage remains an open gap, not pass
```

```
# 4. Static — error code enum used consistently
grep -c "Code_ServerError\|Code_ServerPanic\|Code_Timeout" <service-code>
# expect: all error returns route through the enum, no raw integer codes

# 5. Trace correlation
# trigger one request → search log search by log-id → all hops visible
# pick a log line → click trace_id → trace view shows all spans linked
```
