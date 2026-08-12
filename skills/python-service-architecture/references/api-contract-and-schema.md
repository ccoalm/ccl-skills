# API Contract And Schema

Use this for HTTP API, internal API, generated client, Pydantic, OpenAPI, and protobuf/gRPC architecture.

## Defaults

- Use Pydantic models and OpenAPI as the default contract surface for Python HTTP APIs.
- Keep request, response, persistence, and internal domain models separate when they evolve at different speeds.
- Use protobuf/gRPC only when the integration or platform contract requires it.
- Generated clients are build artifacts; generated migrations are not contract truth.

## Evolution Rules

- Prefer additive evolution: optional fields, new response fields, new endpoints, new enum values, and versioned behavior flags.
- Treat shipped or externally consumed Pydantic/OpenAPI/protobuf/API contracts as compatible-by-default regardless of implementation language. Do not remove, rename, repurpose, make required, or stop accepting existing fields, codes, endpoints, or semantics unless a human explicitly approves a breaking change after reviewing a risk assessment.
- A breaking-change risk assessment must name consumers and generated clients, rollout order, compatibility window, migration or dual-read/dual-write plan, monitoring, rollback path, user/customer impact, and contract/integration/replay evidence for the cutover.
- If launch or consumer status is unknown, assume the contract may be live and design a compatible path first.
- Do not reuse field meanings or silently change validation semantics.
- Make deprecation explicit in schema, docs, and compatibility tests.
- Use typed SDKs or generated clients for cross-service calls when contracts need stability.

## Validation

- Validate at the boundary, then convert to domain objects or use-case inputs.
- Keep public error shape stable even when framework, validation, or dependency exceptions change.
- If schema validation depends on external data, split syntactic validation from business validation.
- Treat schema enums and generated enum clients as boundary representations unless architecture explicitly approves transport-coupled domain code through an ADR or an inline usage-site comment formatted `architecture-approval: transport-coupled finite value <scope> <decision-ref> <reason>` where `<decision-ref>` is a full URL or numeric record id such as `ADR-123`; reviewers must confirm the referenced record exists and approves the specific value/scope before approval. A CI check, grep panel, or required review checklist item MUST exist and pass before any PR introducing `architecture-approval:` comments is merged; absence of that check is itself a blocking finding. The first PR that introduces `architecture-approval:` comments must include the enforcement check in the same PR or reference a prior merged check; "will add later" is not approval.
- For finite values shared by services or clients, define the canonical owner, shared schema/package location, conversion helper owner, unknown/default behavior, and rollout/debt retirement path. If no shared location exists, approve a local fallback and track every temporary duplicate/raw use with `finite-value-debt: <task-ref> <owner> <deadline> <reason>`.

## IDL And Schema Governance (Cross-Stack)

When Python services share IDL surfaces (protobuf for gRPC, OpenAPI/JSON Schema for HTTP, Pydantic models for internal contracts) with Go services or other clients, governance applies symmetrically.

- For multi-service portfolios, prefer dedicated IDL repos (proto, http-thrift, OpenAPI) over inlining schemas in business repos; each IDL repo runs codegen, formatter, and breaking-change checks in CI.
- Inside one IDL set, use a tiered structure — `base` for shared structs and the canonical error/code enum, `api` for gateway-facing contracts, `<domain>` (one bounded context per directory) for per-domain RPC — matching the cross-stack convention. The shared `base` is defined once and imported by every service within that set, never redeclared per service (a deliberate compatibility fork with owner/version/deprecation plan is the documented exception); a service that diverged unintentionally is a recorded known divergence with a migration target, not a silent parallel convention.
- Numeric Code range is reserved at the platform layer (e.g., the platform-specific reserved range) and sub-allocated per tier. Python services raising biz codes must register in the same allocation table as Go services; collisions are caught at allocation, not at runtime.
- Multi-language codegen: each language has its own codegen script (e.g. one shell script per target language), driven from the IDL repo's CI. The language with integration tests is canonical; others inherit the contract and may need their own coverage.
- Breaking-change governance is platform-level: `buf breaking` or equivalent runs in IDL-repo CI; intentional breaks route through an explicit approval path regardless of which language consumes the IDL.

## Response Envelope Strategy (Cross-Stack)

- Architecture decides once whether the portfolio uses HTTP-status-as-semantic or HTTP-200-always-with-JSON-code, and applies the choice consistently across Go and Python services. Mixing the two on the same portfolio breaks gateway error classification and SDK error parsing.
- For HTTP-200-always portfolios, the envelope `{code, message, data}` shape and the code-allocation table are platform contracts. Python services use the same envelope as Go services; SDK generators on either side parse the same shape.

## Contract Tiers, Streaming, And Shape Validation (Cross-Stack)

Mirrors `go-microservice-architecture/references/protobuf-contract-architecture.md` (Streaming And Surface-Shape Validation); keep these cross-stack rules in sync across both files.

- **Distinct contract tiers are distinct shapes — do not force one envelope across all.** Internal RPC (shared base + typed data), the public HTTP JSON envelope (`{code, message, data}`), streaming, and **externally-dictated standard protocols** (a provider-compatible API, a webhook spec, an industry wire format) each carry their own shape. An externally-dictated protocol follows that protocol's wire, mapped from the contract source — not the internal RPC/HTTP envelope. A compatible wire is **not an exemption from internal controls**: authz, tenant isolation, quota, audit, and error-code governance still apply behind it; "just being standard-compatible" must not become a bypass. For a surface with no consumer yet, don't default it to another tier's envelope; define its own contract when a consumer or stability requirement appears.
- **A streamed message (`grpc.aio` streaming, FastAPI `StreamingResponse` / SSE / NDJSON) is a separate shape decision — not automatically the unary envelope.** Define completion and error semantics explicitly: for a fatal terminal error on a transport that can still signal it (gRPC trailers) surface a non-success status, but where the HTTP status is already committed (SSE / NDJSON after a 200) carry the error in-band and ensure observability classifies it as a failure rather than trusting the 200. A stream that already emitted client-visible data or dispatched side effects is not freely retryable; per-domain event payloads are that service's contract, not a universal field set.
- **Make the conventions machine-checkable and multi-service, scaled to repo maturity** — an agent-readable convention spec plus a contract health check that iterates every service (not one hardcoded), validates each unary tier's envelope, and exempts streaming and shared-base definitions. A service it cannot yet validate is a recorded gap with owner and severity, not silently skipped.

## Front-End Consumer Contract

The HTTP / gRPC contract that Python services publish is consumed by front-end clients (React Web, mobile web, mobile-native). The same envelope, header, and timeout decisions appear on the consumer side; architecture documents both sides so they cannot drift independently.

- **Envelope direction**: the server emits the same envelope shape every front-end client parses. Mixing HTTP-200-always with HTTP-status-as-semantic across services forces every front-end caller to special-case per endpoint; the choice is portfolio-level. See the web client skill's cross-stack contract guidance for the consumer-side rules.
- **Trace propagation**: framework middleware reads inbound request-id header when present and otherwise generates one; both the request id and the OTel trace id are surfaced on the response (header or envelope field) so the front end can show them in error UI. Middleware that drops the inbound header silently breaks end-to-end correlation.
- **Auth header contract**: the agreed auth header (e.g. `Authorization` or a platform-specific token header), app-identity header, and any tenant / lane / shadow-traffic headers are validated through one middleware and exposed on the request context using a tiered context-keys convention. Per-route ad hoc header reads are findings.
- **Timeout layering**: outer caller budget is always longer than inner callee budget. For the path `front-end client → Python gateway → downstream RPC/HTTP`, the relationship is `client timeout > gateway timeout (uvicorn / gunicorn worker + framework-level) > downstream RPC/HTTP timeout`. A gateway longer than the client lets the client time out before the gateway can return a structured error; a gateway shorter than the downstream call the gateway itself initiates leaves the inner call running with no caller. Per-endpoint risk tunes the specific values; the ordering is invariant. For long-running work, the gateway holds the request only as far as the streaming/polling contract requires; otherwise the server hands the work to a background worker and returns a task id the front end can poll.
- **Client-signed object-storage upload**: expose a narrow signed-credential endpoint (returns short-lived STS or signed URL + upload target) so front ends write directly to object storage. The main API channel never carries the file body. Token issuance is logged for audit.
- **SDK/codegen for the front end**: when the contract is exposed via OpenAPI / Pydantic schemas, the front-end TS client is generated from the same source the server compiles. Architecture owns the generator command and the publishing cadence so the front-end client never lags the server contract by more than one release.
