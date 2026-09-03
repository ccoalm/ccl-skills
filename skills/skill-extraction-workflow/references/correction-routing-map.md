# Correction Routing Map

Use this when a retrospective, review follow-up, or user correction names tests, verifiers, coverage, test order, or real/external evidence that was unavailable, blocked, deferred, skipped, or mock-substituted. It decides which owner(s) the target-output map must name for that correction type; the extraction workflow itself still gets its prevention point per the entrypoint's always-land rule.

The two rules below were relocated verbatim from `SKILL.md`'s `Retrospectives, corrections & auto-triggered learning` Core Rules group (low-frequency detail per the entrypoint's content-placement rule); the entrypoint keeps a one-bullet summary that points here. Wording changes here go through the same shared-skill gates as an entrypoint edit.

## Deferred-evidence over-polishing corrections

- **Deferred-evidence over-polishing corrections** route to `product-rd-workflow`'s `DFE-CONT` rule: when a delivery keeps hardening tests/verifiers after the real/external evidence was unavailable, blocked, unreachable, deferred, skipped, or mock-substituted, or reports such real evidence as complete, the target-output map must name `DFE-CONT` (paraphrases like "why keep fixing tests when the cluster wasn't reachable" count — exact deferred/skipped wording is not required). A bare mention of runtime/external access is not enough: a test-hardening, coverage, or test-order correction with no unavailable/blocked/deferred real-evidence element and no deferral-as-terminal claim defaults to `testing-strategy`; when both a deferral signal and a test-order signal are present, map to both (`DFE-CONT` + `testing-strategy`, the test-case-first rule still mandatory). Validate by confirming the `DFE-CONT` block and its non-completion rule are present in the installed `product-rd-workflow` skill's `SKILL.md` (resolve via routing/skill discovery; inside the ccl-skills repo: `skills/product-rd-workflow/SKILL.md` — the file is not at that relative path on installed hosts), and keep this routing token in sync if that block is renamed.

## Tests-before-test-cases corrections

- If a retrospective correction says tests were run before test cases, or asks why test cases were not written first, the target-output map must include `testing-strategy` and any coordinating workflow such as `product-rd-workflow`. A final answer without a durable test-case-first prevention rule, validation command, and challenge or explicit no-update reason is only `interim`.

## Decision table

| Correction signal present | Owners the target-output map must name |
| --- | --- |
| Deferred / blocked / unreachable / mock-substituted real evidence, then continued test or verifier hardening, or such evidence reported as complete | `product-rd-workflow` (`DFE-CONT`) + this workflow |
| Test-hardening, coverage, or test-order correction with no deferral element and no deferral-as-terminal claim | `testing-strategy` + this workflow |
| Both a deferral signal and a test-order signal | `product-rd-workflow` (`DFE-CONT`) + `testing-strategy` + this workflow (test-case-first still mandatory) |
| Tests were run before test cases / why were test cases not written first | `testing-strategy` + the coordinating workflow (`product-rd-workflow`) + this workflow |
