# Hook compatibility verification

Initial reviewed commit: `d1671afbc7248084bb2001b498e12d14c16a14f0`.

The initial candidate was split into authorization, runtime and package partitions. Each received independent review and adversarial challenge. The union covers all 37 initial changed files; shared startup and helper context appears in the runtime and package packets. Raw controller envelopes are retained beside this record. Their tracked-chain fields describe those invocations; extraction closeout uses the owning review-plus-challenge lane and its delta rule, not a renewed whole-candidate chain.

Delta 1 uses `git diff d1671afbc7248084bb2001b498e12d14c16a14f0` and the original findings as open items. Its single-shot challenge covers the 15 changed paths after those passes. No executable or product-text change followed that delta; only non-executable evidence records were added.

## Finding dispositions

| Occurrence | Disposition and first-hand evidence |
| --- | --- |
| Runtime review and challenge: missing Python bypasses Claude isolation | Fixed. `legacy_paths` retains the original jq/git single-path checks; missing-helper, missing-Python, absolute/relative protected paths and valid worktrees are covered by `hooks/test_host_input.py`. Codex patches still deny when normalization is unavailable. |
| Runtime review and challenge: first advisory hides a later deny | Fixed. `cmd_pretool` examines all patch targets and selects denial first. The synthetic advisory-before-deny case fails against the old early return. |
| Runtime challenge: bounded scan silently appears complete | Fixed. The helper returns an empty, unverified summary and a failure status; optional Stop consumers emit static diagnostics. Partial evidence is not passed off as a complete scan. |
| Package review and challenge: mandatory startup text can exceed the budget | Fixed diagnostic and optional-context handling. `hooks/test_session_start.sh` covers long rendered paths, oversized mandatory text, exact 9600 bytes and near-limit replacement. Mandatory text itself above the limit remains intact with an explicit direct-visibility warning. |
| Package challenge: native packaged helper/policy closure lacks a direct assertion | Fixed coverage. `test/pack.test.mjs` checks helper, Stop script and full policy in both the tarball and release manifest, then executes the extracted startup script from another cwd and resolves its policy link. |
| Package challenge: same-version install overwrites trusted status text | Fixed. `installOrUpdate` preserves the doctor's message. The trusted repeat-install regression failed before the change and passes afterward. |
| Authorization challenge: target-goal consume races lack a killing test | Fixed coverage. Two forced consume-window cases check stop and unknown-scope messages. A goal-only epoch-check mutant passed 472 original assertions and fails the two added assertions; the actual guard passes 474. |
| Runtime/package initial scope-gap findings | Source-refuted by partition coverage. The authorization packet contains both complete authorization scripts and their tests; runtime covers isolation and owner dispatch; package covers native inventory, operations and installation. Each has both lane receipts bound to the initial commit. No individual partition verdict is claimed for omitted files. |
| Runtime challenge: prior handoff also formats later status/stop replies | Source-refuted against the existing session-wide continuation contract in `skills/product-rd-workflow/SKILL.md` and `references/pre-final-continuation-gate.md`. A truthful `none — status only` is valid. The static reason preserves explicit stop, current scope and output format; the host flag limits this to one formatting repair. It supplies no action authority. |
| Delta 1: partial scans should still block on prefix edits | Source-refuted against the optional backstop's existing fail-open contract (`hooks/skill-extraction-gate-stop.sh`, header and failure branch). A skill invocation may occur after the scan limit, so prefix-only evidence cannot establish its absence. The bounded failure is now visible and cannot become a false claim of complete inspection. |
| Delta 1: goal runtime absent from the test-only delta | Source-refuted by the reviewed base above and `auth-review.json` / `auth-challenge.json`. Neither authorization implementation changed after that commit. The delta deliberately contains only the added race assertions. |

## Executed checks

- Initial unified npm lane: build, build-mode checks and all 352 tests passed with test concurrency 2.
- Final affected npm lane: build, build-mode checks and 175 tests passed with concurrency 1 across native inventory, operations, packed artifact, host adapters and OpenCode hooks.
- Final focused source checks: input 13, proposed-next 18, startup 33, authorization prompt 116, authorization guard 474, delegation 35, isolation 20, owner dispatch 133 and source-install status 31 passed.
- Catalog fixture failure was reproduced when its candidate ledger referenced an uncommitted hook absent from its HEAD-only clone. Copying candidate hook files alongside candidate skill contracts preserves the intended fixture; the catalog suite passes.
- Actual Claude Code 2.1.267, current Claude Code 2.1.270 and Codex 0.154.0 each passed four isolated Stop scenarios and six native Stop calls on the final helper. Loopback-only static provider responses prove native payload handling, continuation request and loop prevention; real-model adherence remains unmeasured.
- Full repository lane, final public sanitization, protected-branch CI, three-host lifecycle and publication verification are recorded separately when complete. Earlier failed/in-flight runs are not counted as passing.

Dedicated security review remains pending; these are bounded engineering checks, not a security audit. Installation trust, native execution and model behavior are separate claims. Product installation never automatically trusts hooks.
