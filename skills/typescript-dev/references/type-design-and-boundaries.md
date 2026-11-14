# Type Design and Boundaries

Use this reference when designing types, removing `any` or assertions, typing external input, or writing type tests.

## What the type system does and does not guarantee

- TypeScript's type system is structural: two types are compatible when their members are, whatever their names. Nominal distinctions (two kinds of id that are both strings) need an explicit brand.
- It is deliberately unsound: the TypeScript design goals list a sound or provably correct type system as a non-goal, trading correctness for productivity. Known holes include `any`, type assertions, unchecked index access without `noUncheckedIndexedAccess`, method parameter bivariance, and every declaration file that misdescribes its JavaScript. Treat the checker as strong evidence about code you control, not proof.
- Types are erased; no type information exists at run time (also a design non-goal). Anything the program learns from outside must be checked by code that runs.

## `unknown`, `any`, and assertions

- `any` turns checking off in both directions and spreads through inference. In first-party code it needs a reason and the narrowest scope; prefer `unknown`, a generic, or an explicit union.
- `unknown` forces a check before use. Use it for external input, `catch` variables (`useUnknownInCatchVariables`, part of `strict`), and values whose type a caller cannot promise.
- An assertion (`as T`, `<T>x`, `x!`) tells the compiler to trust you. It is acceptable only where the code has just established the fact the compiler cannot see — and then a type guard or assertion function that performs the check is better, because the check and the type stay together.
- `as unknown as T` is a red flag in review: it discards every check.
- `satisfies T` checks that a value conforms to `T` while keeping its narrower inferred type; use it for configuration objects, lookup tables, and literal maps where `: T` would widen keys or values.

## Narrowing and exhaustive handling

- Narrow with `typeof`, `instanceof`, `in`, equality, truthiness (careful with `0` and `""`), discriminant checks, user-defined type guards (`x is T`), and assertion functions (`asserts x is T`).
- Model alternatives as a discriminated union with a literal tag field, not as optional fields plus booleans. Each variant carries only the data valid in that state.
- Handle every variant: end a `switch` over the tag with a `default` that assigns the value to `never` (or calls a helper typed `(x: never) => never`), so adding a variant becomes a compile error at every unhandled site. typescript-eslint `switch-exhaustiveness-check` enforces the same at lint time.
- A user-defined type guard is an unchecked promise: the compiler trusts its return type. Test guards directly, including the negative cases.

## Generics and derived types

- Add a type parameter only when it relates two or more positions (input to output, argument to argument). A type parameter used once is usually a disguised `unknown`.
- Constrain parameters with `extends` to the minimum the body needs; do not constrain to a concrete type when a structural requirement suffices.
- Derive types from one source instead of restating them: `keyof`, `typeof`, indexed access, mapped and conditional types, and template-literal types let a schema, a constant table, or a function signature be the single source. Prefer simple derived types; deeply recursive conditional types slow the checker and produce errors no one can read.
- Brand identifiers that cross a permission, tenant, or cache-key boundary (`type UserId = string & { readonly __brand: 'UserId' }`) and create them only in the parser or constructor that validates them. Do not brand transient values that carry no such meaning.

## Untrusted input: parse once at the boundary

- Practitioners summarize the method as "parse, don't validate": convert input into a precise type at the edge, so the rest of the program receives values whose shape is already proven, instead of scattering checks through business logic. The anti-pattern it replaces — checks spread across processing code, so some invalid input is processed before rejection — is what language-theoretic security research calls shotgun parsing.
- The boundary set is: HTTP and RPC bodies and headers, query parameters, `JSON.parse`, storage reads, message queues, environment and configuration, files, `postMessage` and worker messages, WebSocket frames, third-party SDK callbacks, `localStorage`, and `catch` values.
- Use the repository's runtime schema library when one exists. Libraries implementing the Standard Schema interface can be swapped behind a common type; do not add a second schema library beside an existing one. Derive the static type from the schema (`z.infer` and equivalents) rather than writing the type and the schema separately.
- A parse failure is a typed result or a mapped error at the boundary, never a cast. Decide per boundary whether unknown keys are stripped, rejected, or passed through; for security-relevant input, reject.
- A generated client (OpenAPI, protobuf, GraphQL) types what the server promised, not what arrived. Keep a runtime check where the contract is not enforced end to end, and regenerate in CI so drift fails the build.

## Type tests

- Test exported types when their behavior is part of an API: inference of generic helpers, overload selection, error cases that must not compile.
- Vitest checks `expectTypeOf`/`assertType` assertions in `*.test-d.ts` files through `tsc` (or `vue-tsc`) without executing them, but only when type checking is enabled (`vitest --typecheck` or `typecheck.enabled`); a plain `vitest run` skips those files. Prove the setup once: add a deliberately wrong assertion, confirm the command fails, then remove it. `tsd` and plain `// @ts-expect-error` lines checked by `tsc --noEmit` are lighter alternatives; either way, the `tsconfig` that checks them must include the test files. A `// @ts-expect-error` line is itself a negative test: it fails when the expected error disappears.
- Type tests run inside the type-check gate or as their own CI step; whether they block merge is a `testing-strategy` decision.
