# Capability-delta report — candidate vs current

> Judgment-ASSIST, NOT a score. Each row is an LLM-judge reading both answers against the rubric axis (behavior, not keywords). **Confirm every 🔴 HUMAN row by eye** (security/authority/data-loss axes and low-confidence verdicts are always flagged). Raw responses are in this directory; a single sample per arm drives each row — read the `.sN.txt` files for multi-sample nuance.

## 表现变化 (delta counts, judged rows only)
- improved: 4  ·  tie: 0  ·  reduced: 0  ·  **incomplete: 0**
- needs human confirm: F41, F42, F43, F44

## 减少的能力 (candidate does worse / drops)
- A presents dual vs ESM-only as a decision for the user, closer to 'first confirm require is needed'; B assumes dual because the user asked for it
- B gives no staffing or effort estimate, while A estimates about 130–150 person-hours and 4–5 engineers
- B's consumer type-check files are only sketched in comments, and its .cts example contains invalid syntax (`import { foo } = require`), whereas A writes runnable scratch files
- drops A's concrete --traceResolution check that ESM and CJS each resolve to their own .d.ts; B relies on manual F12 jumps in the editor instead
- no tsgo-vs-tsc side-by-side CI parity step like A's non-blocking tsgo job
- the lint guard is narrower: no-restricted-syntax covers only casts on JSON.parse/getItem results, while A's consistent-type-assertions assertionStyle 'never' bans all `as` casts
- toError no longer turns cross-realm error-like objects into Errors by checking their shape, though B notes the limitation

## 新增的能力 (candidate does better / gains)
- B adds a CI check against the main-branch baseline, with CODEOWNERS, so the baseline can only shrink
- B explicitly forbids adding skipLibCheck, expanding exclude or turning off strict in a local tsconfig to hide errors
- B forbids pushing errors onto callers or other files and treats lint bypasses more strictly
- B lists every tsconfig, following extends and references, and requires CI to check source, tests, scripts and Storybook
- B rejects bulk-inserting @ts-expect-error at the end; A plans to bulk-insert ticketed suppressions by script
- B requires the current tsc --noEmit to pass with 0 errors before the baseline is generated
- adds a negative test for an injected role field that expects rejection
- adds negative gate cases so errors planted in src, tests, and scripts must fail tsc -b
- adds type-level tests (.test-d.ts) for Result narrowing, unknown→User being rejected and the catch variable being unknown, plus a step to confirm the type tests actually run
- chooses per boundary: the request-body User schema is .strict() and rejects extra fields like role, while the config schema strips unknown fields and explains why
- explicitly calls a reference cycle a package-boundary design problem
- names the build-first vs customConditions source-direct choice and says not to mix them
- returns the config load result as a discriminated union carrying the problem, so callers can see why it fell back to defaults
- says that public type dependencies must go in dependencies or peerDependencies rather than devDependencies (a rubric item A misses)
- states 7.0 has no compiler API and plans tsc6/6.0-API coexistence per tool, with an upfront inventory of compiler-API tools
- states plainly that checking only the source tree does not prove the published package is correct, and adds npm pack --dry-run to inspect the tarball contents
- tells the user to reuse the repo's existing schema library (valibot/arktype) instead of adding zod
- writes out the changed 6.0 defaults (strict/module/target/types) in the base and flags the types:[] fallout

## Per-fixture

| id | axis | delta | reduced | added | behavior change | flag |
|---|---|---|---|---|---|---|
| F41 | TypeScript library declaration and dual-format publishing | improved | drops A's concrete --traceResolution check that ESM and CJS each resolve to their own .d.ts; B relies on manual F12 jumps in the editor instead; B's consumer type-check files are only sketched in comments, and its .cts example contains invalid syntax (`import { foo } = require`), whereas A writes runnable scratch files; A presents dual vs ESM-only as a decision for the user, closer to 'first confirm require is needed'; B assumes dual because the user asked for it | says that public type dependencies must go in dependencies or peerDependencies rather than devDependencies (a rubric item A misses); states plainly that checking only the source tree does not prove the published package is correct, and adds npm pack --dry-run to inspect the tarball contents | B covers one more rubric item (where public type dependencies belong) and is explicit about validating the tarball, but its check that each format resolves to its own types is weaker and less runnable than A's. | 🔴 HUMAN |
| F42 | TypeScript strictness migration in an existing codebase | improved | B gives no staffing or effort estimate, while A estimates about 130–150 person-hours and 4–5 engineers | B lists every tsconfig, following extends and references, and requires CI to check source, tests, scripts and Storybook; B explicitly forbids adding skipLibCheck, expanding exclude or turning off strict in a local tsconfig to hide errors; B requires the current tsc --noEmit to pass with 0 errors before the baseline is generated; B adds a CI check against the main-branch baseline, with CODEOWNERS, so the baseline can only shrink; B rejects bulk-inserting @ts-expect-error at the end; A plans to bulk-insert ticketed suppressions by script; B forbids pushing errors onto callers or other files and treats lint bypasses more strictly | Both use a baseline that can only shrink. B also makes CI cover every tsconfig and rejects the shortcuts the rubric names (skipLibCheck, narrowing include/exclude, local overrides, bulk suppression), while A ends with a scripted mass insertion of @ts-expect-error. | 🔴 HUMAN |
| F43 | TypeScript runtime boundary for untrusted input | improved | toError no longer turns cross-realm error-like objects into Errors by checking their shape, though B notes the limitation; the lint guard is narrower: no-restricted-syntax covers only casts on JSON.parse/getItem results, while A's consistent-type-assertions assertionStyle 'never' bans all `as` casts | chooses per boundary: the request-body User schema is .strict() and rejects extra fields like role, while the config schema strips unknown fields and explains why; tells the user to reuse the repo's existing schema library (valibot/arktype) instead of adding zod; adds a negative test for an injected role field that expects rejection; adds type-level tests (.test-d.ts) for Result narrowing, unknown→User being rejected and the catch variable being unknown, plus a step to confirm the type tests actually run; returns the config load result as a discriminated union carrying the problem, so callers can see why it fell back to defaults | B rejects unknown fields on the security-relevant request body and strips them on config, and points to the repo's existing schema library; A silently strips extra fields on the user body and assumes zod. | 🔴 HUMAN |
| F44 | TypeScript monorepo project references and compiler upgrade | improved | no tsgo-vs-tsc side-by-side CI parity step like A's non-blocking tsgo job | explicitly calls a reference cycle a package-boundary design problem; names the build-first vs customConditions source-direct choice and says not to mix them; writes out the changed 6.0 defaults (strict/module/target/types) in the base and flags the types:[] fallout; states 7.0 has no compiler API and plans tsc6/6.0-API coexistence per tool, with an upfront inventory of compiler-API tools; adds negative gate cases so errors planted in src, tests, and scripts must fail tsc -b | B covers the same project-references layout but ties it more closely to the rubric: it treats cycles as a design issue, makes an explicit build-first vs source-direct consumption decision, writes out 6.0's changed defaults, and inventories compiler-API tools to plan their coexistence with 7.0, while A covers these points more loosely or only in part. | 🔴 HUMAN |
