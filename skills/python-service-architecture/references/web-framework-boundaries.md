# Web Framework Boundaries

Use this when choosing or reviewing FastAPI, Flask, Django, Starlette, ASGI, or WSGI boundaries.

## Framework Choice

- Prefer FastAPI for typed HTTP APIs, OpenAPI-first contracts, async-compatible endpoints, dependency injection, and service-style applications.
- Prefer Django when the product needs admin, ORM conventions, forms, templating, user/session features, and a cohesive framework.
- Prefer Flask for small synchronous tools, simple internal UIs, or minimal APIs where explicit wiring is more valuable than framework breadth.
- Use Starlette-level primitives only when the service needs lower-level ASGI control.
- **Consider Litestar (formerly Starlite) as a structured alternative to FastAPI** when the architecture wants framework-owned ORM integration, server-side sessions, caching, plugin system, and OpenTelemetry built in rather than assembled per-project; per Litestar docs the framework does more work at bootstrap (precomputed per-route requirements) so runtime cost is lower, and dependency injection is a dict-based `Provide(...)` model that allows transparent override at app/router/controller/route level. The architecture-level trade-off is: more framework convention vs more ecosystem maturity. Choose Litestar when the team wants framework opinions to outpace ad-hoc choices; stay on FastAPI when ecosystem maturity (third-party integrations, hiring pool, community examples) outweighs the structural delta. **Validate production-adoption risks before committing**: Litestar's plugin / middleware ecosystem is smaller than FastAPI's (which inherits much of Starlette's middleware library); the most common production-critical pieces — observability/OTel exporter (Litestar has first-party support, but the specific exporter version + auth-header forwarding behavior may differ), auth middleware (Litestar plugins exist but parity with FastAPI-specific extensions is per-feature), deployment-runtime quirks (lifespan event ordering, ASGI middleware chaining, custom serializer hooks) — should each be smoke-tested on a real Litestar app before the team commits. Litestar does NOT extend Starlette, so third-party "Starlette middleware" packages may need a Litestar-native equivalent or wrapper. Either choice is a long-term commitment — framework switches mid-product are expensive and rarely worth it. Implementation-level Litestar specifics live in `python-service-dev/references/web-framework-patterns.md`.

## Boundaries

- Keep routers/views thin. They should bind request data, authenticate/authorize, call application services, and map responses/errors.
- Put business decisions and data transactions outside route handlers.
- Use app factories or explicit `create_app()` functions when middleware, clients, settings, and test substitution matter.
- Use framework dependency mechanisms, but do not bury heavy construction, network I/O, or mutable global state inside dependency functions.
- Treat ASGI/WSGI choice as runtime architecture: worker count, event loop, sync adapters, lifespan hooks, and shutdown cleanup all matter.

## Anti-Patterns

- Mixing sync ORM calls inside async endpoints without isolation.
- Starting clients, schedulers, or background loops at import time.
- Returning raw ORM objects or unvalidated dictionaries as public API contracts.
- Letting framework folder conventions define domain ownership without an explicit boundary.
