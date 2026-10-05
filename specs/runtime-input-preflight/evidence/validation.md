# Runtime input preflight validation

Status: original review passed; challenge findings corrected; delta verification pending.

## Behavioral evidence

| Owner | Baseline and control | Limit |
| --- | --- | --- |
| testing-strategy | Initial no-op dispatcher: 7 failed / 3 passed. It emitted omitted/mismatched bindings, unobserved tool routes and validator-refused inputs; its snapshot followed a later mutation. A later control exposed two false/undefined validator results being accepted. Requiring explicit true corrected both. Gated counterpart: 17 passed, including an actual loopback WS JSON frame and cancellation/late-result controls. | Proves the test driver's preflight, not arbitrary prompt semantics |
| llm-inference-integration | Malformed model calls were refused by the owning runtime in observed preparation. The scripted owning-validator negative emits no request; a valid recorded control emits the checked payload. | No deployed provider-payload generation or strict-support claim; no statistical Skill effect measured |
| skill-extraction-workflow | Normal sender without its preflight: the required-attachment negative resolved after dispatch. Connected sender: rejects before record callback and dispatch. | Proves hook placement in that sender, not future host compliance with prose |

The maintained executable belongs to the product test repository. Its standard command:

```bash
npm exec -- vitest run tests/keywords/runtime-turn-preflight.test.ts tests/keywords/benchmark-durable-turn.test.ts tests/keywords/agent-benchmark.test.ts tests/keywords/ws-client-v2-wire.test.ts tests/keywords/ws-client-auth.test.ts --no-file-parallelism --maxWorkers=1
```

Latest observed result: 206 passed across five files. Focused strict type checking passed.
Full lint passed with 43 warnings. Whole-repository type checking failed with the same
40 diagnostics on the candidate and its clean comparison baseline; no new or removed
diagnostic. This does not make the whole-repository type check pass.

A previous implementation passed all 4,001 keyword unit cases in 236 files with a
canonical temporary root. Subsequent adversarial findings required per-attempt tool
evidence and cancellation of pending checks; the current 206-case regression covers
those repairs. Static registration produced a second dispatch after deregistration;
the pending-validator cancellation assertion observed an unsettled sender. Nine
earlier helper mutations and retry-forwarding removal killed their intended controls.
Disabling cancellation kills three current controls; emitting late record/tool
results kills the respective late-result controls. The actual sender also forwards
the signal to its owning recorder; the missing-signal control failed before repair.
Unsupported UI combinations have a poison callback control that kills a removed
refusal. Guarded restoration was verified. One old media-fixture timeout passed
unchanged both in isolation and the full focused rerun; no timeout was increased.

The exact executable candidate's subsequent MR pipeline passed its automatic jobs.
Its full keyword suite reported 236 files, 4,006 passed and one skipped test;
additional CI contract and scoped type checks passed. Manual live/media jobs were
not invoked. This is driver/CI evidence and does not close real-media acceptance.

Independent review must assess whether these behavioral controls support each rule
and preserve the unmeasured Skill-compliance limit. Private source identifiers and
raw live receipts are excluded from the shared packet and this record.

## Repository and review gates

Initial make test rejected entrypoint growth. The correction relocates the existing
cleanup paragraph without changing its obligations; rerun all owed gates after that
change. The spec-reference control initially failed because its new evidence target
was untracked; staging the target restored all 79 tests without changing the checker.
The configured private audit passed on the actual comparison base with process-retro
and project-alias profiles. Public sanitization and all nine heavy-regression suites
passed. Full make test exited 2 at one review-wrapper fixture after repo/fast gates
passed; its isolated full suite then passed, as did the remaining shard and all three
abort-probe legs. The subsequent literal full make test finished with exit 0,
including both review-wrapper shards and all required abort-probe legs. The earlier
failed run remains part of the record. Independent review and challenge are pending.

The original independent review passed; the challenge reported one P1 and two P2.
Their verified corrections are recorded in dispositions.md. A subsequent committed
gate rejected the extraction firing sentence's missing normative-action vocabulary;
the local unpushed checkpoint was corrected to explicit must, preserving its anchor.
The source-register gate evaluates the row's original committed span, so a later
unrelated commit cannot repair that span. Full gates and the owning correction delta
are rerun before shared delivery; no checker or threshold was relaxed.


## Final configured checks and review

The initial gate statement in the plan records its pre-review checkpoint;
this evidence section records the final results.

- Literal standard `make test` exited0 after repository gates, fast regression
  lane, both review shards and all required abort legs. Current full heavy lane
  passed9 suites. No test, threshold or timeout was relaxed.
- Original independent review passed. Original challenge returned three
  findings. Each correction is recorded in the dispositions.
- The required delta review covered the post-review normative corrections and
  original findings, returned passed with no findings, and is preserved in
  `delta-review.json`. The unchanged content was context rather than another
  whole review round.
- Invocation guidance, deterministic sender controls and source-record gates
  are verified. Future host invocation compliance, model semantic accuracy and
  media quality remain unmeasured by this slice.
