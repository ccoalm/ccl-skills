# Maintainer Source Map

Inspected 2026-11-13. This file records provenance and extraction limits; it is not required reading for ordinary TypeScript work. Short dated excerpts for the version-sensitive claims are frozen in the extraction round's evidence directory.

## Primary TypeScript sources

| Decision surface | Inspected source | Extracted constraint |
|---|---|---|
| compiler options | [TSConfig Reference](https://www.typescriptlang.org/tsconfig/) | `strict` family membership and recommendation; `noUncheckedIndexedAccess` and `exactOptionalPropertyTypes` are separate from `strict`; `verbatimModuleSyntax` (5.0) replaces two older flags; `erasableSyntaxOnly` targets type-stripping runtimes and pairs with `verbatimModuleSyntax`; `isolatedDeclarations` (5.5); `rewriteRelativeImportExtensions` (5.7) rewrites relative paths; `skipLibCheck` trades accuracy for speed and can hide duplicate type copies; `composite` constraints |
| current defaults and deprecations | [Announcing TypeScript 6.0](https://devblogs.microsoft.com/typescript/announcing-typescript-6-0/) | new defaults (`strict`, `module`, `target`, `noUncheckedSideEffectImports`, `libReplacement`, `rootDir`, `types`); `baseUrl` lookup and `moduleResolution: node10` deprecated |
| native compiler | [Announcing TypeScript 7.0](https://devblogs.microsoft.com/typescript/announcing-typescript-7-0/) | 7.0 adopts 6.0 defaults, makes 6.0 deprecations errors, ships without an API; `@typescript/typescript6` provides `tsc6` and the 6.0 API for side-by-side tooling |
| module resolution | [Modules — Theory](https://www.typescriptlang.org/docs/handbook/modules/theory.html), [Choosing Compiler Options](https://www.typescriptlang.org/docs/handbook/modules/guides/choosing-compiler-options.html), [Modules — Reference](https://www.typescriptlang.org/docs/handbook/modules/reference.html) | the compiler models the host's resolver; one `tsconfig` models one environment; `nodenext` for libraries; the bundled-library split cannot be modeled in one compilation; `exports` resolution follows Node.js and always matches `types` and `default` |
| narrowing and unions | [Narrowing](https://www.typescriptlang.org/docs/handbook/2/narrowing.html), [Creating Types from Types](https://www.typescriptlang.org/docs/handbook/2/types-from-types.html) | narrowing forms, discriminated unions, `never` exhaustiveness, derived types |
| `satisfies` | [TypeScript 4.9 release notes](https://www.typescriptlang.org/docs/handbook/release-notes/typescript-4-9.html) | checks conformance while preserving the inferred type |
| declarations and publishing | [Publishing](https://www.typescriptlang.org/docs/handbook/declaration-files/publishing.html) | bundled declarations, dependency placement for published types |
| project references | [Project References](https://www.typescriptlang.org/docs/handbook/project-references.html) | `composite`, `tsc -b`, the solution `tsconfig` with `files: []` |
| JavaScript checking | [JS Projects Utilizing TypeScript](https://www.typescriptlang.org/docs/handbook/intro-to-js-ts.html) | JSDoc + `checkJs` levels of strictness |

## Theory

- [TypeScript Design Goals](https://github.com/microsoft/TypeScript/wiki/TypeScript-Design-Goals): soundness and run-time type information are explicit non-goals. Grounds the rule that static types do not replace runtime checks at boundaries.
- [Type Compatibility](https://www.typescriptlang.org/docs/handbook/type-compatibility.html): structural subtyping. Grounds branding for nominal distinctions.
- [Parse, don't validate](https://lexi-lambda.github.io/blog/2019/11/05/parse-don-t-validate/) and the language-theoretic security definition of shotgun parsing it quotes: parse input once at the boundary into a precise type. The skill uses the method, not an authority claim.

## Ecosystem tools

| Tool | Inspected source | Extracted constraint |
|---|---|---|
| typescript-eslint | [Linting with Type Information](https://typescript-eslint.io/getting-started/typed-linting/), [Dependency Versions](https://typescript-eslint.io/users/dependency-versions/) | `*TypeChecked` presets with `parserOptions.projectService`; slower than syntactic rules; TypeScript support follows stable releases |
| arethetypeswrong | [CLI README](https://github.com/arethetypeswrong/arethetypeswrong.github.io/blob/main/packages/cli/README.md) | checks a packed tarball (`attw --pack .`); profiles across resolution modes |
| Vitest type tests | [Testing Types](https://vitest.dev/guide/testing-types) | `expectTypeOf`/`assertType` in `*.test-d.ts` are statically checked through `tsc`, not executed |
| Standard Schema | [standardschema.dev](https://standardschema.dev/) | a shared interface implemented by several validation libraries |

## Independent practitioner controls

- [The TSConfig Cheat Sheet](https://www.totaltypescript.com/tsconfig-cheat-sheet): a widely used practitioner baseline, consulted to challenge the option table. Options were kept only when the TSConfig Reference supports them.

## Extraction limits

- Version facts reflect the inspected releases. The skill tells the agent to read the live release notes and the installed compiler instead of trusting these dates.
- Framework-specific type setups (React, Vue, Angular, Svelte, Next.js, NestJS) were not generalized; their owners or the framework's own documentation keep them.
- Bun, Deno, and edge-runtime TypeScript handling was not verified against those runtimes; the skill routes runtime-specific behavior to the runtime's documentation.
- The behavior fixtures freeze tasks and rubrics for later paired evaluation; routing results prove owner selection, not the quality of the implementation advice.
