# Runtime and Project Contract

Use this reference when a Node.js change touches runtime selection, package-manager state, ESM/CommonJS, TypeScript execution, dependencies, or configuration.

## Runtime selection

1. Prefer the repository and deployment contract over a generic recommendation. Reconcile `.nvmrc`, `.node-version`, `package.json#engines`, package-manager metadata, container base image, CI matrix, and production runtime; do not silently choose one when they disagree.
2. For a new production target with no existing contract, select a currently supported Active LTS or Maintenance LTS line from the live [Node.js release page](https://nodejs.org/en/about/previous-releases). Do not hardcode “latest” or infer support from odd/even numbering: the project announced an annual schedule beginning with Node.js 27, and the live [release schedule](https://github.com/nodejs/Release/blob/main/schedule.json) is authoritative when dates drift.
3. Use a Current or Alpha line only for an explicit compatibility/experimentation goal. Record the fallback and do not widen the production support claim from a development smoke test.
4. Test the lowest and highest supported runtime when a library or shared package promises a range. An application normally pins one deployment line and tests the upgrade candidate separately.

## Package-manager and dependency state

- Treat the committed lockfile plus package-manager metadata as the reproducibility contract. Do not switch npm/pnpm/yarn/bun or regenerate a foreign lockfile without an explicit migration.
- Use the manager's frozen install in CI and verification. For npm, `npm ci` requires an existing lockfile, removes an existing `node_modules`, fails when `package.json` and lock state disagree, and does not rewrite either file.
- Keep dependency additions proportional to the contract. Check maintenance, runtime support, transitive size, native build/install scripts, license constraints, and whether a built-in API already meets the need.
- Treat provenance/signatures as origin evidence, not a safety verdict. A vulnerability scan also cannot prove that a dependency is non-malicious or that a vulnerable path is reachable.
- Never accept automatic dependency updates solely because CI is green. Review behavior, changelog/security impact, lockfile delta, and rollback path.

## ESM and CommonJS

- Preserve the established module system. For a new package, set `package.json#type` explicitly and choose extensions/exports that match the actual consumers.
- Do not rely on Node.js syntax detection for ambiguous `.js` files. Explicit intent prevents behavior changes across runtimes and tooling.
- Treat package `exports` as a public compatibility contract. Test every promised import/require path from a packed artifact when publishing a library; service-internal path aliases still need runtime support, not only editor/type-check support.
- Keep dynamic import, top-level await, JSON/native modules, test runner, bundler, and deployment loader behavior in the compatibility matrix when the change uses them.

## TypeScript paths

Choose one explicit path:

| Path | Use when | Required proof |
|---|---|---|
| Compile/transpile before run | The service uses emitted JavaScript, transforms, decorators, path rewriting, or an older runtime | type-check, emitted artifact, source-map/error behavior, production start command |
| Runtime loader/tool | The repository already standardizes on one | loader version/runtime matrix, type-check remains separate, production parity |
| Node.js type stripping | The deployed runtime supports it and source uses erasable syntax only | no unsupported transform syntax, no `tsconfig`-dependent runtime behavior, explicit type-check gate |
| Plain JavaScript | The repository does not require TypeScript | runtime syntax target, lint/check path, public type contract if shipped as a library |

Node.js type stripping ignores `tsconfig.json`, performs no type checking, and does not transform syntax such as enums, runtime namespaces, parameter properties, or import aliases. Do not present it as a drop-in replacement for an existing compiler pipeline.

## Configuration contract

- Parse and validate configuration once during startup; pass typed/validated values inward rather than reading `process.env` throughout the codebase.
- Separate presence, format, range, and cross-field validation. Error messages may name a key but must not echo secret values.
- Define precedence among defaults, env files, environment variables, flags, secret mounts, and remote configuration. A newly available built-in flag is not permission to change repository precedence.
- Keep build-time and runtime configuration distinct. Verify container/orchestrator injection and local development paths separately.

## Contract checkpoint

Before implementation, be able to state:

```text
Runtime: <repo/deploy evidence and supported line>
Package manager: <manager + lockfile>
Modules: <ESM/CJS boundary>
Type path: <execution + type-check>
Public contract changed: <yes/no + exact surface>
Compatibility matrix: <minimum necessary rows>
```
