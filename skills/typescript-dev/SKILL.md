---
name: typescript-dev
description: Use when the TypeScript language or compiler layer is the work in any TypeScript or JSDoc-checked JavaScript project on any runtime — type design (unknown/any, narrowing, discriminated unions, generics, satisfies), tsconfig and strict migration, module resolution and ESM/CJS types, declaration files and library type publishing, project references, type-check and typed-lint gates, type tests, compiler upgrades, typing untrusted input. Triggers include "TypeScript 类型怎么写", "tsconfig 怎么配", "moduleResolution 选哪个", "库的类型声明怎么发", "开 strict 迁移". Compose with the runtime owner (nodejs-service-dev, web-react-dev, app-cross-platform-dev, miniapp-product-dev); failures → defect-diagnosis; test layers → testing-strategy; architecture → software-architecture.
---

# TypeScript Development

- Code/test changes require self-checks; invoke `code-review` automatically before completion.

## Skill Routing

- This skill owns the TypeScript language and compiler layer on every runtime: type design, `tsconfig`, module resolution as the compiler models it, declaration output, type-check and typed-lint gates, type tests, compiler upgrades, and the typed boundary for untrusted input. Plain JavaScript checked through JSDoc and `checkJs` is in scope.
- Load it together with the runtime or framework owner, never instead of one. `nodejs-service-dev` owns Node.js execution (type stripping, loaders, `package.json#type`, event loop, lifecycle); `web-react-dev` owns React components and browser behavior; `app-cross-platform-dev` owns React Native and native apps; `miniapp-product-dev` owns mini-program frameworks and hosts. Bun, Deno, edge, and browser runtimes keep their runtime-specific APIs and permission models outside this skill; confirm them in that runtime's own documentation.
- `testing-strategy` chooses test layers, whether type tests gate CI, and coverage policy. This skill owns the mechanics: the type-check command, type-test files and assertions, and typed-lint configuration. `test-artifact-management` owns testcase traceability; its TypeScript helper must still pass the project's type-check gate.
- An active failure — a type-check that broke, a module that fails to resolve at run time, a declaration a consumer cannot load — enters `defect-diagnosis`; the verified repair returns here.
- Architecture, service boundaries, shared-package ownership, and contract source of truth go to `software-architecture`; new capabilities and multi-stage migrations enter `product-rd-workflow`; release gates and registry publication go to `platform-release-engineering`; the user-facing command contract of a CLI goes to `terminal-cli-dev`.

## Generalization Discipline

- Implement the repository in front of you. Do not carry product nouns, package names, path aliases, or a prior project's `tsconfig` into a reusable rule.
- A rule that depends only on the TypeScript compiler or type system lands here. A rule that depends on one runtime or framework stays in that owner and points here for the type layer. When a sibling skill states a language-layer rule, replace the copy with a pointer rather than keeping two versions.

## Workflow

### 1. Recover the compiler contract

Read the nearest `AGENTS.md`, then `package.json` (`typescript` version, `type`, `exports`, scripts), every `tsconfig*.json` in the `extends` and `references` chains, lint configuration, and the build or bundler that emits JavaScript. Record:

- the installed TypeScript major and whether any tool still needs the compiler API;
- which tool type-checks, which emits JavaScript and which emits declarations — often three different tools;
- the module system per environment and the `module`/`moduleResolution` pair that models it;
- the type-check command CI runs, and whether it covers every `tsconfig` in the repository.

Preserve those choices unless a migration is explicit. Read [compiler-config-and-checking.md](references/compiler-config-and-checking.md) before changing a compiler option, a version, or a gate.

### 2. Model the environment, then the types

- Choose `module`/`moduleResolution` from where the emitted code runs, not from what makes the editor quiet: `nodenext` for code Node.js loads directly and for published libraries, `bundler` (with `module: esnext` or `preserve`) when a bundler resolves every import. One `tsconfig` models one environment; split it when server, browser, worker, and test code see different globals or module rules.
- Read [modules-and-publishing.md](references/modules-and-publishing.md) when the change touches module resolution, ESM/CJS output, path aliases, `exports`, declaration files, a published package, or monorepo project references.
- Static types do not exist at run time. Every value that crosses a trust or process boundary — network, storage, environment, files, `postMessage`, third-party callbacks, `JSON.parse`, `catch` variables — enters as `unknown` and is parsed once at that boundary into a precise type. Read [type-design-and-boundaries.md](references/type-design-and-boundaries.md) when designing types, removing `any` or assertions, or typing external input.

### 3. Implement with the compiler as a checker

- Make illegal states unrepresentable: discriminated unions with exhaustive handling, branded identifiers where swapping two ids would cross a permission or cache boundary, `satisfies` to check a value without widening it.
- Fix the type, not the report. A cast, a non-null `!`, `any`, `// @ts-ignore`, or a loosened flag needs a stated reason and the narrowest scope. Prefer `// @ts-expect-error <reason>`, which fails once the error disappears.
- Keep declaration output stable: annotate exported function return types and public object shapes so a dependency upgrade or an inference change cannot silently change a published type.

### 4. Verify narrow to broad

Run, with repository commands: the type-check for the touched project (`tsc --noEmit` or `tsc -b` with references) → typed lint → type tests, when the repository has them → runtime tests → build → for a published package, a check of the packed artifact. A bundler, transpiler, or type-stripping runtime that ran successfully proves only that the syntax was erasable or transformable; it is never type-check evidence.

## Hard Rules

- A real type-check gate runs in CI and covers every `tsconfig` that owns source, tests, and scripts. Executing TypeScript (type stripping, `tsx`, `ts-node --transpileOnly`, esbuild, SWC, Babel, a bundler) is not type checking.
- Do not weaken `strict`, add `skipLibCheck` to hide a first-party error, or widen `include`/`exclude` to make an error disappear. Turning a check off is a recorded decision with an owner and a removal condition.
- Untrusted data is `unknown` until a runtime parse proves its shape. `as SomeType` on external input is a defect, not a type.
- A published package's types are a public contract: verify them from the packed tarball for every entry point and module format it promises.
- Do not adopt a new compiler major, a native compiler, or a deprecated-option removal by editing versions alone; check every tool that imports the compiler API before switching.

## Output Contract

Report the TypeScript version and toolchain split (check / emit / declarations), compiler options changed and why, type-level behavior preserved or changed, exact commands run with results, skipped checks, and residual risk.

Technical claims and their sources are recorded in [source-map.md](references/source-map.md); ordinary work loads only the reference whose decision surface it reaches.
