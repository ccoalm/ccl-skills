# Compiler Configuration and Checking

Use this reference when a change touches `tsconfig`, the TypeScript version, a strictness flag, the type-check gate, or typed linting.

## Version and toolchain

1. Read the installed compiler (`npx tsc -v`) and every tool that imports the compiler API: typescript-eslint, framework checkers (`vue-tsc` and similar), declaration bundlers, test runners with type checking, editor plugins. Version claims come from the live release notes, not from memory.
2. TypeScript 6.0 changed defaults that a `tsconfig` relying on them inherits silently: `strict` is `true`, `module` defaults to `esnext`, `target` floats to the latest stable ECMAScript year, `noUncheckedSideEffectImports` is `true`, `rootDir` defaults to the `tsconfig` directory, and `types` defaults to `[]`. It also deprecated `baseUrl` as a lookup root and `moduleResolution: node`/`node10`. State these options explicitly rather than depending on whichever default the installed version has.
3. TypeScript 7.0 is the Go-based native compiler. It adopts the 6.0 defaults, turns the 6.0 deprecations into hard errors, and ships without a programmatic API; the TypeScript team publishes `@typescript/typescript6` (a `tsc6` executable plus the 6.0 API) so that tools needing the API can run side by side. Before moving a repository to 7.0: make it compile cleanly on 6.0 with no `ignoreDeprecations`, list every API consumer, and decide per tool whether it stays on the 6.0 API through the alias the TypeScript team documents. Do not mix versions by accident: one `typescript` resolution per workspace unless the split is deliberate and recorded.
4. Upgrade as a migration: compile on the new version, fix or explicitly suppress each new error with a reason, then remove the suppressions in a follow-up. Do not combine a compiler upgrade with unrelated type refactors in one change.

## Baseline options

The options below are the defensible default for new code. In an existing repository, preserve current settings and move toward this baseline through the migration below.

| Option | Why | Notes |
|---|---|---|
| `strict: true` | Enables the whole strict family (`strictNullChecks`, `noImplicitAny`, `strictFunctionTypes`, `useUnknownInCatchVariables`, and others) | Future versions may add checks under `strict`; an upgrade can produce new errors by design |
| `noUncheckedIndexedAccess: true` | Index signatures and array element access return `T \| undefined` | Not part of `strict`; the most common undefined-at-runtime bug it catches is `arr[i]` and `record[key]` |
| `exactOptionalPropertyTypes: true` | Distinguishes "absent" from "present and `undefined`" | Adopt where the codebase can absorb it; libraries that publish types should test with consumers that enable it |
| `noImplicitOverride`, `noFallthroughCasesInSwitch` | Cheap correctness checks | |
| `verbatimModuleSyntax: true` | Import and export syntax is emitted as written; type-only imports must say `import type` | Makes file-format intent explicit; replaces `importsNotUsedAsValues` and `preserveValueImports` |
| `isolatedModules: true` | Every file can be transpiled alone | Required in practice when esbuild, SWC, Babel, or a bundler emits JavaScript |
| `erasableSyntaxOnly: true` | Rejects enums, runtime namespaces, parameter properties, and other syntax with runtime semantics | Use when code runs through a type-stripping runtime such as Node.js, which erases types without transforming syntax; pair with `verbatimModuleSyntax`. Runtimes that fully transpile TypeScript do not need it — confirm in the runtime's documentation |
| `isolatedDeclarations: true` | Exports must carry enough annotation for other tools to emit declarations | Needed only when declarations are produced by a tool that emits them without the type checker; `tsc` does not need it |
| `skipLibCheck: true` | Skips checking every `.d.ts` file, which saves time | It also skips first-party declarations (hand-written `types/` files, declarations committed or generated into the tree) and hides conflicting duplicate type copies. When the repository ships or hand-writes declarations, the gate must also run a check with `skipLibCheck: false` over them (a dedicated `tsconfig` or `tsc --noEmit --skipLibCheck false`), and the packed-consumer check covers published ones. Never use it to hide errors in first-party declarations |
| `types: [...]` | Lists the global type packages each environment may see | With the 6.0 default of `[]`, test globals and `node` types must be named explicitly per `tsconfig` |

`target` and `lib` follow the oldest runtime the emitted code supports, not the developer's machine. `lib` without `dom` keeps browser globals out of server code; give browser, server, worker, and test code separate `tsconfig` files when their globals differ.

## Strictness migration

1. Measure: run the type-check with the target flag on and count errors per directory.
2. Ratchet, do not bulk-suppress. Turn the flag on for a leaf `tsconfig` or a project reference that is already clean, then expand directory by directory. A per-file baseline of known errors is acceptable only when a check fails on any new error and the baseline only shrinks.
3. Fix by narrowing, not by assertion. Replace `x!` and `as T` with a check that proves the type, or change the type so the value cannot be absent.
4. Do not add `// @ts-ignore` in bulk. A temporary suppression uses `// @ts-expect-error <reason>` so it fails once the error is fixed.
5. Finish by removing the scoped override so the whole repository shares one setting.

## The type-check gate

- CI runs the compiler in check mode for every project that owns source, tests, scripts, and configuration files: `tsc --noEmit -p <config>` per `tsconfig`, or `tsc -b` for a solution `tsconfig` with references. A check that covers only `src/` leaves tests and scripts unchecked.
- The gate fails on any error. Warnings and editor diagnostics do not count.
- Type-stripping runtimes, bundlers, and single-file transpilers report success on code that does not type-check. Their success is execution or build evidence only.
- Keep the check deterministic: a committed lockfile, a pinned compiler version, and no dependency on editor state.

## Typed linting

- `typescript-eslint` typed rules need type information: use the `*TypeChecked` presets (`recommendedTypeChecked`, `strictTypeChecked`) with `parserOptions.projectService: true`. They are slower than syntactic rules because they analyze the whole project.
- Rules that catch defects the compiler does not are worth making errors: `no-floating-promises`, `no-misused-promises`, `no-unsafe-*` (assignment, call, member access, return, argument), `only-throw-error`, `switch-exhaustiveness-check`, `restrict-template-expressions`.
- Check the typescript-eslint supported version range before upgrading TypeScript: it supports a stable release some time after it ships, and it needs the compiler API, which TypeScript 7.0 does not provide.
- A rule set that runs at `warn` gates nothing. Rules that matter are `error` in CI. Which rules are mandatory across a portfolio is a conformance-gate decision owned by `testing-strategy` (`testing-strategy/references/fitness-functions.md` §4.1.3); this skill owns the configuration that implements it.

## JavaScript checked with TypeScript

- `checkJs` with JSDoc annotations gives type checking without a build step. Use `// @ts-check` for single files and `allowJs` + `checkJs` for a project.
- The same gate applies: `tsc --noEmit` runs in CI. For a published JavaScript package, emit `.d.ts` files from JSDoc with `declaration` + `emitDeclarationOnly` and verify them like any other published types.
