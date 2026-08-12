# Protobuf Contract Patterns

Use this when editing `.proto`, generated stubs, Kitex/Hertz/gRPC generation, or handlers bound to generated contracts.

## Edit Workflow

- Edit source `.proto` first, then regenerate outputs.
- Locate include root, target IDL file, generated output root, package mapping, and generator command before changing code.
- Commit source proto and generated output together.
- Do not hand-edit generated `.pb.go`, gateway, or service stub files.
- Prefer `new` only for initial scaffolding and `update` for existing services.
- Keep generator commands repo-relative or configurable through environment variables and Makefile variables.
- Avoid post-generation `mv` or `sed` import rewriting; prefer generator options for package and output mapping. If rewriting is unavoidable, isolate it in a documented script and verify imports.

## Field Rules

- Choose field numbers deliberately; leave gaps for future groups.
- Never reuse field numbers; add `reserved` for removed numbers and names.
- Adding an optional field is compatible only when "field absent" remains an accepted state forever; the moment a service starts to reject requests with the field absent, it is a breaking change for older clients regardless of what the IDL says. New required semantics need a versioned method/message OR a staged compatibility gate (server accepts both for a deprecation window, clients upgrade, then server enforces).
- Use explicit units in field names or comments for timestamps, durations, and sizes.
- Use `int64` for IDs and timestamps when range matters; document JSON/string behavior for HTTP clients if needed.
- Use `optional` only when presence matters; otherwise rely on proto3 defaults and validation.
- Add comments for non-obvious validation: max size, required-by-application, ordering, uniqueness, units, and lifecycle.

## Request/Response Patterns

- Use `MethodRequest` and `MethodResponse` names or one consistent local convention.
- Response should include canonical error/envelope fields or embed a shared response once; do not mix multiple envelope styles in one service.
- Follow the repo's current envelope convention; for new services, define the envelope field name and number intentionally instead of copying a legacy framework convention.
- Data payload should be in typed fields, not JSON strings, unless the API intentionally carries opaque data.
- Batch requests need max item count, idempotency behavior, partial-failure semantics, and per-item result shape.
- List responses need items, pagination cursor/total policy, and stable sort definition.

## Enum Patterns

- First value is unknown/unspecified zero.
- Prefix enum values with enum name or stable short prefix.
- Do not rename generated enum values after clients import them.
- Treat unknown enum values as validation errors at write boundaries and as safe fallback at read boundaries.
- Avoid generic values like `Pending` or `Finished` in shared packages because generated Go names can collide.

## Service And HTTP Mapping

- Keep service methods cohesive; split large services by capability or stability boundary.
- Put HTTP annotations near methods and field binding annotations near fields.
- Path/query/body/header bindings should be explicit and tested.
- Empty request/response messages are acceptable when the method truly has no payload, but keep them named for future evolution.
- Streaming methods require explicit message size, cancellation, backpressure, and retry semantics.

## Generation And Tests

- Keep Kitex, Hertz, gRPC, protoc, and DI generation commands in Makefile targets or scripts.
- Use `protoc --go_opt=paths=source_relative` or an equivalent explicit mapping when generated file layout should mirror source layout.
- Run formatting and compile checks after generation.
- Add contract tests for default values, optional presence, unknown enum handling, field binding, error envelope, pagination, and backward compatibility.
- Add generated-code clean checks in CI when proto inputs change.
- If generator version changes, review generated diff separately from contract changes.

## IDL Repo Organization

- For multi-service portfolios, prefer one or more dedicated IDL repos (proto, thrift, http-thrift each may be its own repo) over inlining IDL into business repos. Each IDL repo carries its own CI to run codegen, format, and pre-commit checks; business repos consume the published generated artifacts.
- When the IDL repo is independent, the standard CI shape is a single docker image (e.g., `idlgen:v1.0.0`) plus a branch-aware `docker run` that rebuilds generated outputs and either commits them back or publishes a module. Tag the image; do not float `:latest` for production codegen.
- Inside one IDL repo, organize sources by three intentional tiers: `base` for shared structs and the canonical error/code enum, `api` for gateway-facing contracts that cross the trust boundary, and `<domain>` (one bounded context per directory, e.g. `<product-line>`, `<platform-layer>`) for internal RPC by business domain. Use the same tiering in the generated output tree.
- Reserve an explicit numeric range for the shared `Code` enum (for example `[0, 11999]`) and document per-tier sub-ranges so downstream services can allocate biz codes without colliding with platform codes.
- Pre-commit hooks in IDL repos at minimum: protoc / thrift compile, formatter (clang-format for proto, thriftfmt for thrift). Add a breaking-change check (`buf breaking`, `kitex check`, or equivalent) when the IDL is consumed by more than one team or has external clients.
- Generated output directories must be excluded from any reformatter the business repo runs; if `reformat.sh` exists, it should carry an explicit skip list (`! -path "./kitex_gen/*" ! -path "./hertz_gen/*"`).

## Multi-Language Codegen

- When the same IDL produces clients for multiple language families (Go, Python, Java, TypeScript), drive each language's codegen from its own dedicated script (one shell script per target language) rather than a single mega-script. Each script lives next to the IDL and is the canonical command — Makefile targets and CI jobs both delegate to it.
- Cross-language codegen scripts that auto-commit and push generated artifacts should: pin tool versions (grpcio-tools, protoc-gen-go-grpc, etc.); use a known build-and-publish flow (poetry / npm publish / go module tag); skip on no-op diffs; emit a clear final status.
- Document which language is the canonical source of behavior expectations when only one language has integration tests against the IDL. Other-language clients inherit the contract but may not catch protocol-level regressions.
