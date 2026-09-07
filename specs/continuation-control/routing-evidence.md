# Code-review routing compatibility evidence

- The code-review routing comparison must preserve the frozen five-case bank, the same catalog except the reviewed description, the same runner and ten replicas per case.

The description adds automatic review after code or executable-test changes while retaining explicit review requests. This comparison measures the existing affected-owner routing cases. It does not measure tool execution after implementation or establish compatibility for the full library.

## Frozen inputs and method

The subset contains every row in `eval/routing-tasks.jsonl` whose `expected_skill`, `acceptable` or `must_not_route_to` names `code-review`: five of 158 rows, copied byte for byte in original order. Utterances, expected outcomes, exclusions and `frozen_at_sha` are unchanged. Four cases expect review; the retrospective case must stay with skill extraction.

- Full bank SHA-256: `1bf0633717c28eb162ce26814a4c94f4530f5b4ec3a464d3ed7172c51f83cf8d`.
- Five-case bank SHA-256: `d13a7256b0f00c1c81882fc38386f3b8b322aa23c18bce6aac989b003b446fef`.
- Catalog source: `1defabb0760ad7d4b072790f61c0207de548803d`. The baseline replaces only the `code-review` description with its bytes from `69bcc3e31556f40e9e10fc4b69837cfc56f6fffe` (`origin/dev` when captured); all other descriptions are identical. The current arm uses the catalog source description unchanged.
- Shared runner: `skills/skill-extraction-workflow/scripts/eval-routing-bank.rb`, SHA-256 `6d1e2f0d13c0965ffe5b41e42a86bfd7e135158cbd1bdfbcbb6f01be9140bee0`.
- Both arms ran on 2026-09-07 with requested model `claude-haiku-4-5`, ten replicas per case and a 30-second per-attempt timeout. Neither uses description truncation or the optional bootstrap layer. The existing classifier invokes Claude with tools disabled.

Run once for each catalog root:

```sh
ruby skills/skill-extraction-workflow/scripts/eval-routing-bank.rb <catalog-root> \
  --bank <frozen-five-case-bank> --replicas 10 --timeout 30 \
  --model claude-haiku-4-5 --json <report.json>
```

## Results

Both processes exited 0. Each arm produced 50 valid observations: 50 PASS, zero FAIL and zero ERROR; each case has all ten required valid observations. All five cases have unanimous top-choice agreement and valid frozen ancestry. No case changed consensus status.

| Case ID | Expected owner | Before valid / PASS / FAIL / ERROR | Current valid / PASS / FAIL / ERROR |
| --- | --- | --- | --- |
| `new-claude-review` | `code-review` | 10 / 10 / 0 / 0 | 10 / 10 / 0 / 0 |
| `route-ordinary-diff-review` | `code-review` | 10 / 10 / 0 / 0 | 10 / 10 / 0 / 0 |
| `route-provider-neutral-diff-review` | `code-review` | 10 / 10 / 0 / 0 | 10 / 10 / 0 / 0 |
| `route-review-to-skill-retro` | `skill-extraction-workflow` | 10 / 10 / 0 / 0 | 10 / 10 / 0 / 0 |
| `var-neg-opencode-review` | `code-review` | 10 / 10 / 0 / 0 | 10 / 10 / 0 / 0 |

The baseline requested clarification in 1/50 observations and the current arm in 0/50; neither had low-confidence observations. This small difference is recorded without claiming an improvement. The reports share the bank hash and replica count; their per-skill description hashes differ only for `code-review`.

| Artifact | Before SHA-256 | Current SHA-256 |
| --- | --- | --- |
| Raw description line, including newline | `b73dfb25bb779b8429a12a2f53636bc44b97649290384c503574c0ddb248e045` | `af5c5e964fce26499953b6fe5e7a910074a538f7a4cb0bf0d05f49cfb7a7a6b8` |
| Raw JSON report | [Before](evidence/routing-before.json): `cac82defd9a5f3b9978ffd6ca41bb28a7fdee6e8f8085614520cfd41dc67f757` | [Current](evidence/routing-after.json): `f67478913f8ffc7ebe2856cd26b39e89593b8f98289fd16f61b00fe30da5150c` |

These are 100 routing observations across the two arms, separate from independent code-review results. The runner may retry timeout or non-JSON responses once and does not report successful retry history, so these totals are not an audited provider-attempt count. The evidence supports compatibility on this affected-owner subset; it does not establish a full 158-case result, universal automatic invocation or a runtime authorization guarantee.
