# Web Framework Patterns

Use this for FastAPI, Flask, Django, Starlette, route handlers, app factories, middleware, and dependencies.

## FastAPI

- Use routers for feature boundaries.
- Use Pydantic models for request/response contracts.
- Use dependency functions for request-scoped dependencies, not for hidden heavy construction.
- Use lifespan/startup assembly for shared clients and cleanup.
- Test APIs through framework test clients or `httpx` ASGI clients when appropriate.

## Litestar (FastAPI Alternative)

- **Litestar (formerly Starlite) is the current batteries-included alternative to FastAPI** for typed ASGI services where the project wants more framework-level structure out of the box (built-in ORM integration, server-side sessions, caching, OpenTelemetry, plugin system) without assembling them per-project. Per Litestar benchmarks, performs at the front of the ASGI framework pack (does not extend Starlette — implements its own routing and significant ASGI layer; precomputes route requirements at bootstrap so per-request work is minimized). DI model differs from FastAPI: dependencies declared as `{key: Provide(callable)}` dicts at app/router/controller/route level rather than per-parameter `Depends()`, allowing transparent override at every nesting level. Choose Litestar over FastAPI when: (a) the team wants framework-owned ORM/cache/sessions/OTel rather than choosing each, (b) deeply nested DI override is common, (c) the OpenAPI schema is the dominant contract surface and Litestar's first-class controller pattern fits the team's mental model. Stay on FastAPI when: (a) the team already has FastAPI muscle memory and ecosystem pieces, (b) Pydantic + `Depends()` per-parameter is the team's preferred shape, (c) ecosystem maturity (third-party tutorials, hiring pool, vendor integrations) matters more than the framework-feature delta. Architecture-level framework choice belongs in `python-service-architecture/references/web-framework-boundaries.md`; this file owns the per-feature Litestar implementation details once chosen.
- Treat identity, ownership, actor, tenant, creator, account, and permission fields in headers, query params, bodies, and downstream service calls as client claims until resolved from authenticated context or an authoritative service.
- For write paths, use the resolved authenticated identity as the source of truth. Either overwrite client-supplied owner/creator fields or reject mismatches; never use authenticated identity only as a fallback after trusting a request field.
- When fixing an auth or permission bug, search every ingress and propagation point for the same trust class: headers, body fields, query params, path params, generated client/server schemas, service defaults, and downstream repository inputs.
- When fixing auth or permission behavior, test every input surface that could carry the same spoofing class, and assert downstream services receive the resolved identity or the request is rejected.
- Add fail-closed tests for auth, permission, capability, and profile-resolution errors before side effects.

## Flask

- Prefer app factories for non-trivial apps.
- Keep views thin and push business logic into services.
- Use blueprints for modular routes.
- Avoid process-global mutable state unless it is explicitly initialized and test-substitutable.
- Do not trust request-provided ownership or actor fields for writes; resolve them from authenticated context and pass the resolved identity into services.

## Django

- Follow framework conventions for apps, settings, migrations, and admin when they serve the product.
- Keep domain logic out of views/templates when it needs testing or reuse.
- Use transactions for multi-write workflows.
- Keep user/tenant/owner attribution authoritative from `request.user`, signed session/context, or a trusted service; reject or ignore conflicting request payload fields.
