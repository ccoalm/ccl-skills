# Modules, Declarations, and Publishing

Use this reference when a change touches module resolution, ESM/CommonJS output, path aliases, `exports`, declaration files, a published package, or monorepo project references.

## Model the module system the code runs under

TypeScript does not resolve modules at run time; it models the resolver that will. The `module` and `moduleResolution` pair must describe that resolver, or the compiler accepts imports that fail in production.

| Emitted code is loaded by | `module` / `moduleResolution` | Consequence |
|---|---|---|
| Node.js directly (apps, scripts, CLIs, servers) | `nodenext` / `nodenext` | ESM vs CJS is decided per file by extension and the nearest `package.json#type`; relative ESM imports need file extensions |
| A bundler that resolves every import (browser apps, most framework apps) | `esnext` or `preserve` / `bundler` | Extensionless relative imports are allowed because the bundler resolves them; do not reuse this config for code Node.js loads |
| A published library | `nodenext` / `nodenext` unless a bundler produces the published output | Consumers' environments are unknown; `nodenext` emits what Node.js and bundlers both accept |
| A bundled library with external dependencies | `bundler` for the bundle, plus a `nodenext` check of the emitted declarations | The compiler cannot model a split between bundled and externalized imports in one compilation |

- `moduleResolution: node`/`node10` is deprecated in TypeScript 6.0; migrate to `nodenext` for Node.js or `bundler` for bundlers.
- `paths` is a compiler-only mapping. Every alias also needs the runtime or bundler mapping (`package.json#imports`, bundler `resolve.alias`, a loader); otherwise it type-checks and fails at run time. Prefer `package.json#imports` (`#internal/*`): Node.js and TypeScript (`node16`, `nodenext`, `bundler`) resolve it natively, and most current bundlers do too — confirm for the project's bundler and test runner. `baseUrl` as a lookup root is deprecated in 6.0; write the prefix into each `paths` entry.
- With `verbatimModuleSyntax`, CommonJS files use `import x = require()` and `export =`, and ESM files use `import`/`export`; the file's format must be intentional.
- When source imports carry `.ts` extensions (needed for type-stripping runtimes), `rewriteRelativeImportExtensions` rewrites them to `.js` on emit. It touches relative import paths only, so aliased imports still need a runtime mapping that resolves the emitted file.

## Declaration files

- Emit declarations with `declaration: true` (plus `declarationMap` when consumers navigate to source). When another tool emits JavaScript, run `tsc --emitDeclarationOnly` for the declarations. Enable `isolatedDeclarations` only when declarations come from a tool that emits them file by file without the type checker, or when the repository adopts that constraint; `tsc` itself infers declarations across the whole program.
- Declarations follow the same module format as the JavaScript they describe: `.d.mts` for `.mjs`, `.d.cts` for `.cjs`, `.d.ts` for `.js` interpreted by the nearest `package.json#type`. A single `.d.ts` shared by an ESM build and a CJS build misdescribes one of them.
- Public types are API. Annotate exported return types, avoid leaking types from private or dev-only dependencies, and put the packages that published types import from in `dependencies` or `peerDependencies`, never only in `devDependencies`.
- Hand-written declarations for an untyped dependency live in one `types/` directory named in `include`, checked with `skipLibCheck: false` because the default skip also hides errors in them; do not scatter `declare module` stubs. Prefer the package's own types or `@types/*` when they exist.

## Package `exports` and types

- In each `exports` condition object, put `types` first. TypeScript follows the Node.js `exports` algorithm, which takes the first matching condition in object order, so a `types` entry after a matching `import`, `require`, or `default` is never reached. For dual packages, nest `types` inside `import` and `require` so each format points to its own declaration file.
- Every entry point listed in `exports` needs a matching declaration. A subpath without types makes consumers fall back to `any` or fail under `nodenext`.
- `typesVersions` exists only for consumers on old compilers; do not add it unless a supported consumer needs it.
- Dual ESM/CJS publishing doubles the surface (two builds, two declaration sets, the dual-package hazard of two module instances). Choose it only when supported consumers need `require`; current Node.js lines can `require` synchronous ESM, so confirm the consumer matrix first.

## Verify the packed artifact

1. Build, then `npm pack` (or the package manager's equivalent) and inspect the tarball file list.
2. Run `@arethetypeswrong/cli` against the tarball (`attw --pack .` or `attw <tarball>`). It reports problems such as declarations resolving to the wrong module format, missing types for an entry point, and false ESM/CJS claims across the `node10`, `node16`, and `bundler` resolution modes.
3. Optionally run `publint` for `package.json` field problems.
4. Install the tarball into a scratch consumer for each promised environment (`nodenext` ESM, `nodenext` CJS when supported, `bundler`) and type-check an import of every entry point. A check run against the source tree instead of the tarball does not prove the published contract.

Release gating and registry publication stay with `platform-release-engineering`.

## Monorepos and project references

- Use project references when packages type-check independently: each package `tsconfig` sets `composite: true` (which implies `declaration` and requires every source file to be matched by `include`/`files`), lists the packages it depends on in `references`, and is built with `tsc -b`, which rebuilds only out-of-date projects.
- A root "solution" `tsconfig` sets `files: []` and references every leaf project, so `tsc -b` at the root checks everything without compiling any file twice.
- Share options through one base config extended by each package; per-package files carry only real differences (environment, `lib`, `types`, paths).
- The dependency direction between packages is an architecture decision owned by `software-architecture`; references must match it, and a reference cycle is a design error, not a configuration problem.
- Workspace packages consumed from source need a decision: build-first through `exports` that point at emitted output, or source-first through a custom export condition (`customConditions`) that the bundler and test runner also honor. Mixing the two produces types that differ between editor, CI, and runtime.
