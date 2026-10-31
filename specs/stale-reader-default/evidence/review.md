# Review record

All passes used `skills/skill-extraction-workflow/scripts/extraction_review_gate.sh` against `origin/main` at stage `build`. The implementer family was `anthropic`, so the reviewer was Codex. Controller results: `review.json`, `challenge.json`, `delta-review-1.json`.

The branch history was rebuilt once so that the source-register commit comes last. Commit ids below are the ones each pass reviewed. After the rebuild, `c747b2a` is `748037c` and `9224c5d` is `ecbea48`. In each pair the rewritten commit has the same tree minus the two register rows, which were re-added in the last commit. The review and challenge packets therefore included those rows.

## Review pass

- Reviewed commit: `c747b2a`
- Findings: 3 total (0 P0 / 0 P1 / 3 P2)
- R0 evidence: `check-ccl-skills.sh` printed `alias_audit_ok` and `r0_status=private-ok`
- Dispositions:
  - P2 `evidence/behavior-eval.md`: worlds and graders were private, and the eval predated the last narrowing. Fixed: the decisive task's repository, prompt and grader are published in `legacy-model-task.md`, and the candidate arm was replayed on later text.
  - P2 `plan.md`: the required local lanes were not recorded. Fixed: `validation.md`.
  - P2 `refactoring-discipline.md`: an exhaustive enum switch does fail to compile when a member is added. Fixed: the rule says those checks are not guaranteed to reach every reader, and names the switch case. The plan's root-cause row is scoped to the string field it observed.

## Challenge pass

- Reviewed commit: `9224c5d`
- Findings: 3 total (0 P0 / 0 P1 / 3 P2)
- R0 evidence: as above
- Gate-fireability applicability: no — the change adds no gate or hook
- Dispositions:
  - P2 `refactoring-discipline.md` line 36: "report unknown" would override a reader whose contract already defines rejection or a safe fallback, such as a fail-closed allowlist. Fixed in both the canonical rule and the `defect-diagnosis` line.
  - P2 `evidence/legacy-model-task.md`: the grader accepted `Infinity` from capacity and ignored the named consumers and the mapper. Fixed: the grader now requires a finite result that excludes the Auto job, or an explicit unknown, and requires the named consumers and the mapper. A mutant that returns null from the mapper without fixing capacity now fails. Every sample was regraded with no change in counts (base 0/5, candidate 5/5).
  - P2 `refactoring-discipline.md` line 3: the packet held neither the unchanged Impact Analysis section nor the cross-repo field checklist, so the reviewer could not test the scope and compatibility claims. Not changed; checked against source. Impact Analysis lists callers, tests, contracts, persisted data and observability. Applying it to a fix or feature that changes a shared shape or its values asks for an inventory, not refactor-only behavior. The cross-repo checklist in `testing-strategy/references/integration-contract-testing.md` already requires consumer tolerance for "the field's absence/new form" before producer emission. The new rule states the same order inside one repository and does not contradict it.

## Delta pass 1

- Reviewed commit: `c4c7560`; packet: `git diff ecbea48..c4c7560`, with the challenge's safe-fallback finding passed verbatim as an open item
- Findings: 1 total (0 P0 / 0 P1 / 1 P2)
- Dispositions:
  - P2 `source-register.md`: the packet could not show that the rows parse, that the anchors are unique, or the lane results. Fixed: `validation.md` records those commands and results for this commit.

## Post-review delta

Everything after `c4c7560` changes only record files in this directory.
