# HTTP Response Envelope Contract

The cross-stack contract for the JSON business-response shape a backend returns and its clients parse. Owned here alongside the request-side base struct (`rpc-framework-recipe.md`) and the wire-format gate (`protobuf-http-contract-signals.md`) because it is shared across the Go, Python, web, mini-program, and testing skills — each points here and adds only its stack-specific verb (define / implement / consume / assert). Do not restate this policy per stack.

## Canonical envelope

- The canonical JSON business envelope is `code`, `message`, and `data`. `data` is the typed business data model for that operation.
- It is defined in the shared contract source, not invented per handler, route, or client.

## Adoption & migration

- New services and service-level envelope migrations use the canonical `code` / `message` / `data` envelope.
- A new route inside an existing service follows that service's already-shipped envelope until a consumer-migration decision adopts `code` / `message` / `data` for the service.
- An existing surface with a different shipped envelope preserves current behavior until a migration decision exists.

## Surfaces that are not the JSON envelope

Binary protobuf, streaming, file/download, redirect, healthcheck, and externally dictated callback / standard-protocol responses record, implement, and assert their own response contract instead of pretending to use the JSON envelope.

## Anti-patterns (when the canonical JSON envelope applies)

- Do not invent alternate or per-handler / per-route top-level business response shapes.
- Do not duplicate the common envelope fields across clients, or scatter duplicate envelope parsing.
- Do not place business fields outside `data`.
