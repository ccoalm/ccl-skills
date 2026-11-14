# Point sibling skills, docs and the review gate at typescript-dev

## Scope

| Item | Target | Change |
| --- | --- | --- |
| 1 | `skills/testing-strategy/SKILL.md` | Stack pointer list routes TypeScript type checks and type tests to `typescript-dev`, within the entrypoint's byte and word caps |
| 2 | `skills/software-architecture/SKILL.md` | Node.js/TypeScript part loads `typescript-dev` for boundary types and runtime schemas |
| 3 | `skills/code-review/scripts/review_gate.py` | Owner selection by file suffix includes `typescript-dev` for TypeScript files |
| 4 | `skills/test-artifact-management/SKILL.md` | Test-code owner list names `typescript-dev` for type tests |
| 5 | `skills/multi-agent-delegation/SKILL.md` | Surface split keeps the language owner inside the surface slice |
| 6 | `docs/` handbooks, `packages/ccl-skills-npm/README.md` | Stack owner tables list `nodejs-service-dev` and `typescript-dev` |

Unchanged, with reasons:

- `product-rd-workflow/SKILL.md` already names `typescript-dev` in its development routing.
- `product-rd-workflow/references/stage-quality-and-landing.md`: the client line sets rendered evidence per surface; the language layer adds no rendered evidence.
- `code-review/SKILL.md` and references: no stack owner list.
- `go-microservice-dev` and `python-service-dev` backend sibling lists, `product-ui-ux-design` client owner lists, and the source-evidence maps: the language layer is not a backend sibling, a client surface, or a provenance row.

## Item 3: review gate owner selection

Artifact classification: `gate implementation`. Risk tag: `shared-gate` (owner selection decides which self-review owners a review must cover before the gate runs).

### Current behavior

`FILE_TYPE_OWNERS` maps each suffix to one owner. `.ts` and `.tsx` map to `web-react-dev`; `.mts` and `.cts` map to nothing. A derived owner missing from the self-review plan stops the gate with `self_review_incomplete`, and every derived owner is loaded for the reviewer. So a Node.js or library `.ts` change must self-review against `web-react-dev` and is reviewed without `typescript-dev`.

### Decision

A suffix proves the language, not the runtime. The mapping becomes multi-valued:

| Suffix | Owners after | Owners before | Reason |
| --- | --- | --- | --- |
| `.ts`, `.mts`, `.cts` (incl. `.d.ts`) | `typescript-dev` | `web-react-dev` / none | TypeScript on any runtime; a React guess is wrong for Node.js, Deno, libraries and type packages |
| `.tsx` | `typescript-dev`, `web-react-dev` | `web-react-dev` | JSX in TypeScript: both the language and the React owner apply |
| `.js`, `.mjs`, `.cjs`, `.jsx`, `.vue` | `web-react-dev` | `web-react-dev` | Unchanged. JavaScript reaches `typescript-dev` only when the project type-checks it (`checkJs` or `// @ts-check`), which a suffix cannot show; adding it would make every plain JavaScript change self-review against the type layer |
| other mapped suffixes | unchanged | unchanged | — |

Owners still apply only when the registry holds that skill's `SKILL.md`.

Loosened class: a non-JSX `.ts` file in a React project no longer derives `web-react-dev`. Its runtime owner must be declared by the implementer in the self-review plan, which the gate also loads for the reviewer. `.tsx` and `.jsx` keep deriving `web-react-dev`.

### Acceptance (decision table)

| Input paths | Registry | Derived owners |
| --- | --- | --- |
| `src/a.ts` | full | `typescript-dev` only |
| `src/a.mts`, `src/a.cts`, `types/a.d.ts`, `src/A.TS` | full | `typescript-dev` only |
| `src/A.tsx` | full | `typescript-dev`, `web-react-dev` |
| `src/a.js`, `.mjs`, `.cjs`, `.jsx`, `.vue` | full | `web-react-dev` only |
| `src/a.tsx` | without `typescript-dev` | `web-react-dev` only |
| Go + `.ts` + `.tsx` + Dart through the full gate | full | app, Go, `typescript-dev`, `web-react-dev`; a plan missing `typescript-dev` stops with `self_review_incomplete` |

### Tests

`skills/code-review/scripts/test_review_gate.sh`: unit asserts on `derive_owner_selection` for every row above, and the full-gate case for the last row. Written and run RED before the change. The old assertion that `.ts` and `.tsx` derive `web-react-dev` is rewritten to the new table, not deleted.

### Verifiers

`make test-code-review` (CI code-review jobs), `check-ccl-skills.sh`, `make test-repo-gates`, `make test-regressions-fast`.

### Review

Extraction-lane review and challenge over the whole branch; the challenge focuses on the loosened `.ts` class and on owner-selection false positives and negatives.
