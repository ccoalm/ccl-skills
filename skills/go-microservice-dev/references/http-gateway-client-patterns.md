# HTTP Gateway And Client Patterns

Use this when implementing HTTP handlers, generated routes, middleware, API docs, or generated HTTP clients.

## Generated Route Files

- Keep generated route registration files marked as generated and do not hand-edit them.
- Use generator-supported insertion points or separate custom registration functions for custom routes.
- Regenerate routes after IDL path, method, handler path, or middleware annotations change.
- If generator output contains placeholder handler bodies, replace behavior in preserved handler files or application services, not in overwritten files.
- Route tests should assert method, path, middleware presence, and auth bypass behavior for changed endpoints.

## Handler Implementation

- Bind and validate request structs at the transport boundary.
- Authenticate and resolve authorization context before domain-side effects.
- Convert path/query/header/body fields into a command/query object instead of passing raw HTTP context into application logic.
- Return responses through one response builder or canonical envelope.
- Map validation failures, auth failures, dependency failures, and domain failures through the canonical error mapping.
- Keep generated documentation comments synchronized with the source contract; do not maintain duplicate route tables by hand.

## Middleware Hooks

- Middleware factory functions should return stable ordered lists and be easy to test.
- Keep no-op middleware hooks explicit when the generator requires them.
- Do not capture per-request mutable state in package-level middleware variables.
- Middleware should add typed context values for trace/log id, auth subject, authorization scope, lane/environment, and request deadline when needed.
- Recovery middleware should convert panics into canonical errors and preserve trace/log id in logs.

## Generated HTTP Client

- Build requests through a typed builder that supports context, path params, query params, headers, body, form fields, files, and request options.
- Escape path parameters and encode repeated query parameters predictably.
- Detect or set content type before serializing body payloads.
- Do not send body payloads for HTTP methods where the client or gateway does not support them.
- Handle gzip or other negotiated compression before unmarshalling.
- Decode successful response bodies into typed responses and error bodies into typed errors when the server provides them.
- Let callers override the response-success policy when HTTP status alone is not enough.
- Return raw response metadata where callers need status, headers, or request diagnostics.

## IDL-First Hertz Layout

When the HTTP gateway uses an IDL-driven generator (Hertz `hz`, gateway-style tools, etc.), the resulting layout has three intentional tiers:

- `<hertz_gen>/router/<domain>/`: generator output binding IDL methods to URL paths and HTTP verbs. Treat as generated code; do not hand-edit. Regenerate when IDL changes.
- `api_methods/`: thin handwritten stub per IDL method. Its job is exactly three things: declare the typed request struct, call `c.BindAndValidate(&req)`, then dispatch to the business handler. Stubs may be initially generated and then frozen with a "do not edit" header; subsequent edits go through the generator only when the IDL changes.
- `handler/<domain>/`: the actual business logic — application service calls, cross-RPC calls, response mapping. Domain code never appears in `api_methods/` and validation logic never appears in `handler/`.

This separation makes IDL evolution cheap (regenerate `router/`, untouched `api_methods/`, business handler unchanged) and keeps each tier reviewable in isolation.

## Double-Layer Middleware Composition

- Framework-default middleware (recovery, ctx injection, metrics, tenant info, tracing) is registered inside the server-construction wrapper. Business-level middleware (CORS, auth/login, logging, custom ctx) is appended in the service's `main()`.
- Document both layers and the resulting order so reviewers can see which step happens before which. A typical merged order: `CtxInject → Recovery → Metrics → TenantInfo` (framework) then `CORS → UserAuth → Login → RequestLog → CustomCtx` (business).
- Do not let two middleware do the same job in different layers (e.g., two recovery wrappers, two metrics counters) — duplicate metrics inflate counters and double-handling of panic obscures the stack trace.
- Recovery middleware must sanitize the response: return a stable error code (`coderr.ServerPanic` or equivalent) and a generic message; never put the panic value, stack trace, or internal error chain in the response body. The stack trace belongs in the log and the trace, not in the JSON.
- Route-level middleware stubs that exist but have empty bodies are dead code; either implement them or delete them. Empty stubs invite future engineers to assume coverage that does not exist.
- The same risk applies to **scaffold-generated VALIDATION GATES that ship with placeholder content** — distinct from generator-required no-op middleware hooks and extension hooks, which are explicitly allowed empty per the rules above (`http-gateway-architecture.md` Route And Middleware Design "generated middleware hooks should default to no-op", and the "Keep no-op middleware hooks explicit when the generator requires them" rule in the Middleware Hooks section above). A validation gate is identified by **scaffold naming convention** (`check<HandlerName>`, `validate<X>`, `precondition<X>`) — i.e. functions whose name the scaffold uses to signal "this is a validation gate". Defining the gate by call-site position is not enforceable because the lint cannot reliably read intent; the naming convention is the contract between scaffold and reviewer. The scaffold template MUST use the conventional gate name when emitting a validation-gate function — emitting a gate under a non-conventional name (e.g. a generic `hook<X>` that downstream code treats as validation) is itself the bug; fix the scaffold template, not the lint. A gate function body of `// your codes...\nreturn nil` (or any equivalent placeholder comment + bare success return) is a "validation passed" claim that the validation in fact never ran. Required: the build/CI lint fails on a gate-named function whose body lacks an error-returning path. The AST check is "the function has at least one statement that can return a non-nil error (`return ...err...`, `return errdef.X`, `return fmt.Errorf(...)`)" — adding logging, metrics, or a dummy expression without an error path does NOT satisfy the lint. Detection by grep on the placeholder comment is a minimal floor; the AST/error-path check is the real defense.

## API Documentation Generation

- Use the framework's IDL-driven doc generator (Hertz `hz` doc, swag/swaggo, protoc-gen-doc) and expose the docs endpoint only in non-production environments or behind explicit auth.
- Doc generation should run from the same Makefile target as code generation so docs and binding rules never drift.

## Tests

- Test binding for path, query, header, body, form, repeated fields, and enum values when used.
- Test invalid input, missing auth context, canonical error mapping, empty responses, compressed responses, and non-JSON error bodies.
- Test generated clients with a fake Doer/client instead of live network by default.
- Keep generated-code snapshots or clean-generation checks only where generator churn is controlled.
- For IDL-first layouts, include a smoke test that proves a fresh regeneration of `router/` plus untouched `api_methods/` and `handler/` still compiles and routes correctly. This catches the case where the generator changes its emitted shape.
- For recovery middleware, assert that a panic produces a stable error code and a sanitized message, and that the stack trace appears only in the log capture, not in the response body.

## stdlib net/http As Option

- **Go 1.22+ `net/http.ServeMux` got enhanced routing** — pattern syntax now supports method matching (`"GET /users/{id}"`), path wildcards (`{id}`, `{path...}` trailing wildcard), and host matching. Per the net/http docs, route precedence is based on specificity (most-specific pattern wins), and `r.PathValue("id")` reads the matched wildcard. Use stdlib `http.ServeMux` when (a) the service is a small internal tool / admin endpoint / health-probe shim where pulling Hertz/Kitex is over-engineering, (b) the binary needs to be importable as a library and avoid the framework's transitive dependency, (c) the team is writing a sidecar / sidecar-helper / migration utility. For the team's main product services, Hertz remains the default (richer middleware, observability adapters, codegen integration); stdlib ServeMux is an intentional alternative for narrow scope, not a Hertz replacement. **Do NOT mix stdlib `ServeMux` mid-service inside a Hertz application for "just one admin endpoint"**: the stdlib handler runs outside Hertz's middleware chain, so observability (request log, metrics, tracing), auth, rate limiting, panic recovery, and ctx propagation that Hertz attaches to other routes will silently bypass the stdlib-handled endpoint. Either route the admin endpoint through Hertz with its own middleware subset, or use Hertz's v0.10+ `http.Handler` adapter to wrap the stdlib handler so Hertz middleware still applies — never let two HTTP routers serve the same binary's port without an explicit boundary review.
