# Contributing

Contributions must preserve skill routing, safety boundaries, and deterministic validation. Start with [AGENTS.md](../AGENTS.md); a nearer `AGENTS.md` may add rules for the path you change.

## Prepare an isolated checkout

Do not edit the primary `main` checkout. Create a dedicated branch and worktree:

```bash
git fetch origin
git worktree add ../ccl-skills-my-change -b my-change origin/main
cd ../ccl-skills-my-change
```

Confirm the checkout before editing:

```bash
git branch --show-current
git status --short
```

## Choose the owning workflow

- Change a skill rule, trigger, route, validator, or reusable workflow through `skill-extraction-workflow`.
- Change a product or engineering delivery process through `product-rd-workflow`.
- Diagnose a failing test or defect through `defect-diagnosis` before implementing a fix.
- Finalize reader-facing prose with `tighten-doc` after the substantive owner has settled the content.

Read the owning `SKILL.md` and only the references required for the change.

## Keep shared skills portable

- Do not add credentials, private hostnames, local absolute paths, customer data, or organization-specific examples.
- Keep triggers, routing, hard rules, and stable reference links in `SKILL.md`.
- Put long checklists, examples, and implementation detail in `references/`.
- Treat description, trigger, skip, and redirect edits as routing changes, not wording-only edits.
- Add an `AGENTS.md` to each source directory covered by the repository contract.
- Do not add `version` to `.claude-plugin/plugin.json` or `.codex-plugin/plugin.json`.

## Preserve behavioral evidence

A non-wording shared-skill change needs reviewable evidence. Record the expected behavior, the observed baseline, the changed path, and the verification command in the source register or the artifact required by the owning workflow.

Use one of these terminal states:

- `RED-baseline`: behavior, routing, validation, or acceptance changed and the original failure is reproducible.
- `semantic-control`: a reviewer confirmed that a mechanical refactor preserves behavior.
- `not-applicable: docs-only`: only reader-facing documentation changed; no executable skill, reference, validator, template, hook, or installer behavior changed.

Do not store private provenance in the distributed repository. Keep restricted source details in an access-controlled task artifact.

## Validate the change

Run the minimum repository gates from the root:

```bash
bash skills/product-rd-workflow/scripts/check-agent-contract-coverage.sh --repo . --enforce
bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .
python3 scripts/check-public-sanitization.py .
python3 scripts/check-markdown-links.py .
git diff --check
```

Run the focused tests for every changed script or package. For the unified npm package:

```bash
npm --prefix packages/ccl-skills-npm ci
npm --prefix packages/ccl-skills-npm test
npm --prefix packages/ccl-skills-npm run test:pack
```

Install the optional local pre-push hook for an extra check before pushing:

```bash
git config core.hooksPath .githooks
```

GitHub Actions reruns the repository and package checks. Branch protection and required reviews remain repository-administration settings; the workflow file alone cannot enforce them.

Release maintainers must follow the [npm release runbook](npm-release.md). A code change does not authorize a version bump, tag, registry mutation, or publish.

## Submit a focused change

- Keep unrelated edits out of the branch.
- Explain the user-visible behavior and validation evidence in the pull request.
- Link findings to exact files or commands.
- State skipped checks and unresolved risks explicitly.
- Do not publish npm packages, create releases, or change protected settings as part of an ordinary code change.
