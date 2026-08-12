# Config Secrets Runtime

Use this for settings, secrets, dependency clients, and runtime configuration.

## Settings

- Prefer typed settings through Pydantic Settings, Django settings modules with typed accessors, or equivalent schema-backed config.
- Separate local, test, staging, and production configuration without hard-coding environment names into business logic.
- Validate required config at startup before serving traffic. More generally, never let a critical invariant rest on a dependency's incidental or undocumented behavior — assert and own it locally, preferring construction-time fail-fast over request-time fail-open.
- Keep defaults safe for local development, not silently production-like.
- The Settings / Secrets / Dependency Clients rules in this file plus the stateless-process and structured-logs rules in `observability-and-ops.md` and `packaging-runtime-readiness.md` cover the Twelve-Factor App principles MOST relevant to a Python service skill (config in env, backing services as attached resources, build/release/run separation, processes, logs). Do not treat this as a full Twelve-Factor checklist — factors like codebase, port binding, and admin processes are owned elsewhere. Follow the typed-config + env/secret-injection + startup-validation rules here and route deployment / release / port-binding / admin-process factors to `platform-release-engineering` and `packaging-runtime-readiness.md`.

## Secrets

- Secrets must come from environment, secret manager, workload identity, or deployment platform.
- Do not place real secrets in examples, tests, generated clients, notebooks, logs, or pyproject files.
- Redact secrets from error messages and structured logs.

## Dependency Clients

- Define lifecycle: construction, readiness validation, timeout, retry, credentials, close hook, and fake/test substitution.
- Separate startup/admin timeouts from request-path timeouts.
