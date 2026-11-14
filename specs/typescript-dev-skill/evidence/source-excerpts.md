# 来源摘录（2026-11-13 抓取）

只摘与版本敏感或容易记错的断言直接相关的短句，原文以链接为准。

| 技能里的断言 | 来源 | 摘录 |
| --- | --- | --- |
| 6.0 起 `strict` 默认开启 | [Announcing TypeScript 6.0](https://devblogs.microsoft.com/typescript/announcing-typescript-6-0/) Simple Default Changes | "`strict` is now `true` by default" |
| 6.0 其他默认值 | 同上 | "`module` defaults to `esnext`"; "The new default `target` is the most recent supported ECMAScript spec version (effectively a floating target)"; "`noUncheckedSideEffectImports` is now `true` by default"; "`libReplacement` is now `false` by default" |
| `rootDir`、`types` 默认值 | [Announcing TypeScript 7.0](https://devblogs.microsoft.com/typescript/announcing-typescript-7-0/) Updates Since 5.x | "`rootDir` now defaults to `./`"; "`types` now defaults to `[]`, and the old behavior can be restored by setting it to `[\"*\"]`" |
| `baseUrl` 查找与 `node10` 废弃 | 6.0 公告 Deprecated 节 | "In TypeScript 6.0, `baseUrl` is deprecated and will no longer be considered a look-up root for module resolution."; "In TypeScript 6.0, `--moduleResolution node` (specifically, `--moduleResolution node10`) is deprecated." |
| 7.0 沿用 6.0 默认值、废弃项变错误 | 7.0 公告 | "TypeScript 7.0 adopts 6.0's new defaults, and provides hard errors in the face of any flags and constructs deprecated in TypeScript 6.0." |
| 7.0 没有 API、并行用 6.0 | 7.0 公告 Running Side-by-Side | "While TypeScript 7.0 is here, it does not ship with an API."; "`@typescript/typescript6`. This package provides an executable named `tsc6` … also re-exports the TypeScript 6.0 API" |
| 6.0 编译干净即 7.0 一致 | 7.0 公告 | "Practically any TypeScript code that compiles cleanly with TypeScript 6.0 (with the `stableTypeOrdering` flag on, and without any `ignoreDeprecations` flag set) should compile identically in TypeScript 7.0." |
| typescript-eslint 对新版本的支持 | [Dependency Versions](https://typescript-eslint.io/users/dependency-versions/) | "We endeavor to support the latest stable TypeScript versions as soon as possible after the release." |
| typed lint 配置 | [Linting with Type Information](https://typescript-eslint.io/getting-started/typed-linting/) | "Add `TypeChecked` to the name of any preset configs"; "`parserOptions.projectService: true` indicates to ask TypeScript's type checking service" |
| `noUncheckedIndexedAccess` 不在 strict 内、加 `undefined` | [TSConfig Reference](https://www.typescriptlang.org/tsconfig/) | `strict` 的 Related 列表不含它；"Turning on `noUncheckedIndexedAccess` will add `undefined` to any un-declared field in the type." |
| `erasableSyntaxOnly` 面向类型剥离并与 `verbatimModuleSyntax` 搭配 | TSConfig Reference | "Node.js supports running TypeScript files directly as of v23.6; however, only TypeScript-specific syntax that does not have runtime semantics are supported"; "Typically, you will want to combine this flag with the `--verbatimModuleSyntax`" |
| `skipLibCheck` 会掩盖重复类型 | TSConfig Reference | "two libraries could define two copies of the same `type` in an inconsistent way" |
| `exports` 解析跟随 Node.js | [Modules — Reference](https://www.typescriptlang.org/docs/handbook/modules/reference.html) | "TypeScript's implementation for resolving a module specifier through `\"exports\"` to a file path follows Node.js exactly." |
| 打包库的解析分裂 | [Choosing Compiler Options](https://www.typescriptlang.org/docs/handbook/modules/guides/choosing-compiler-options.html) | "TypeScript cannot be configured to use two different module resolution settings in the same compilation." |
| `bundler` 不要求扩展名 | TSConfig Reference `moduleResolution` | "unlike the Node.js resolution modes, `bundler` never requires file extensions on relative paths in imports" |
| `composite` 约束 | TSConfig Reference | "All implementation files must be matched by an `include` pattern or listed in the `files` array"; "`declaration` defaults to `true`" |
| solution tsconfig | [Project References](https://www.typescriptlang.org/docs/handbook/project-references.html) | "a “solution” `tsconfig.json` file that simply has `references` to all of your leaf-node projects and sets `files` to an empty array" |
| attw 检查打包产物 | [attw CLI README](https://github.com/arethetypeswrong/arethetypeswrong.github.io/blob/main/packages/cli/README.md) | "The CLI can check an `npm pack`ed tarball"; "pack one in-place by specifying `--pack` and a directory" |
| Vitest 类型测试需要显式开启 | [Testing Types](https://vitest.dev/guide/testing-types) | "To enable typechecking, just add `--typecheck` flag to your Vitest command"; "Vitest doesn't run these files, they are only statically analyzed by the compiler." |
| 健全性与运行时类型信息是非目标 | [TypeScript Design Goals](https://github.com/microsoft/TypeScript/wiki/TypeScript-Design-Goals) | "Apply a sound or \"provably correct\" type system. Instead, strike a balance between correctness and productivity."; "Add or rely on run-time type information in programs" 列为非目标 |
| 结构化类型 | [Type Compatibility](https://www.typescriptlang.org/docs/handbook/type-compatibility.html) | "Type compatibility in TypeScript is based on structural subtyping." |
| shotgun parsing | [Parse, don't validate](https://lexi-lambda.github.io/blog/2019/11/05/parse-don-t-validate/) 引用的 LangSec 定义 | "Shotgun parsing is a programming antipattern whereby parsing and input-validating code is mixed with and spread across processing code" |
