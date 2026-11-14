## Validity, cost, invocation

| Fixture | Arm | valid | errors | contaminated | mean cost USD | mean wall s | mean turns | invoked typescript-dev | invoked (any) |
|---|---|---|---|---|---|---|---|---|---|
| F44 | before | 10 | 0 | 10 | 0.31 | 76 | 8.2 | 10/10 | typescript-dev |
| F44 | after | 10 | 0 | 0 | 0.37 | 74 | 8.5 | 10/10 | typescript-dev |

Contamination hits: 10
- F44/before/s1: ['{"name": "Skill", "input": {"skill": "ccl-skills:typescript-dev"}}', '{"name": "<result>", "is_error": null, "mentions_typescript_dev": true, "head": "Launching skill: ccl-skills:typescript-dev"}']
- F44/before/s10: ['{"name": "Skill", "input": {"skill": "ccl-skills:typescript-dev"}}', '{"name": "<result>", "is_error": null, "mentions_typescript_dev": true, "head": "Launching skill: ccl-skills:typescript-dev"}']
- F44/before/s2: ['{"name": "Skill", "input": {"skill": "ccl-skills:typescript-dev"}}', '{"name": "<result>", "is_error": null, "mentions_typescript_dev": true, "head": "Launching skill: ccl-skills:typescript-dev"}']
- F44/before/s3: ['{"name": "Skill", "input": {"skill": "ccl-skills:typescript-dev"}}', '{"name": "<result>", "is_error": null, "mentions_typescript_dev": true, "head": "Launching skill: ccl-skills:typescript-dev"}']
- F44/before/s4: ['{"name": "Skill", "input": {"skill": "ccl-skills:typescript-dev"}}', '{"name": "<result>", "is_error": null, "mentions_typescript_dev": true, "head": "Launching skill: ccl-skills:typescript-dev"}']
- F44/before/s5: ['{"name": "Skill", "input": {"skill": "ccl-skills:typescript-dev"}}', '{"name": "<result>", "is_error": null, "mentions_typescript_dev": true, "head": "Launching skill: ccl-skills:typescript-dev"}']
- F44/before/s6: ['{"name": "Skill", "input": {"skill": "ccl-skills:typescript-dev"}}', '{"name": "<result>", "is_error": null, "mentions_typescript_dev": true, "head": "Launching skill: ccl-skills:typescript-dev"}']
- F44/before/s7: ['{"name": "Skill", "input": {"skill": "ccl-skills:typescript-dev"}}', '{"name": "<result>", "is_error": null, "mentions_typescript_dev": true, "head": "Launching skill: ccl-skills:typescript-dev"}']
- F44/before/s8: ['{"name": "Skill", "input": {"skill": "ccl-skills:typescript-dev"}}', '{"name": "<result>", "is_error": null, "mentions_typescript_dev": true, "head": "Launching skill: ccl-skills:typescript-dev"}']
- F44/before/s9: ['{"name": "Skill", "input": {"skill": "ccl-skills:typescript-dev", "args": "pnpm monorepo 5 个 TS 包互相引用：设计 project references/增量类型检查的 tsconfig 结构，并把 TypeScript 从 ', '{"name": "<result>", "is_error": null, "mentions_typescript_dev": true, "head": "Launching skill: ccl-skills:typescript-dev"}']

## Rubric coverage (blinded judge)

| Fixture | before mean | after mean | delta | permutation p | judged before/after | W-flags before | W-flags after |
|---|---|---|---|---|---|---|---|
| F44 | 0.97 | 0.96 | -0.01 | 1.0000 | 10/10 | 0 | 0 |

## Per item (met / partial / missed; W = answers showing the weakness)

| Fixture | Item | before | after |
|---|---|---|---|
| F44 | S1 | 10/0/0 | 10/0/0 |
| F44 | S2 | 10/0/0 | 10/0/0 |
| F44 | S3 | 7/3/0 | 7/3/0 |
| F44 | S4 | 10/0/0 | 9/1/0 |
| F44 | S5 | 10/0/0 | 10/0/0 |
| F44 | W1 | 0 | 0 |
| F44 | W2 | 0 | 0 |
| F44 | W3 | 0 | 0 |

## Judge-reported wrong facts (count of answers with ≥1)

- F44 before: 0/10
- F44 after: 2/10
