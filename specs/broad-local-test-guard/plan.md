# Broad local test guard

## Problem

Agents ran whole test suites locally that CI already runs. `testing-strategy` Local Evidence Selection and the delivery-completion gate both say to run the narrowest check that would fail, so the rule existed. Nothing fired at the point the command was written. A handoff that stated a suite's duration was read as an instruction to run it.

Replaying agent transcripts from one 18-day window across several services found about 122 hours of unselected test commands, measured as the time from call to result or background completion. That figure is an upper bound on waste: it includes lanes a repository requires locally, and background runs can overlap. The largest groups were bare `npm test`, `pytest`, `pnpm test` and Playwright runs, not only lanes named integration or scenario.

## Decision

Three controls, each at a point the next agent reaches in time.

| Control | Fires when | Owner |
| --- | --- | --- |
| `hooks/guard-broad-local-test.sh`, PreToolUse deny | An agent issues a test command that selects nothing, in any repository | this plugin |
| Repository entry: long suites off the local default, `RUN=` to select, `FULL=1` to opt in, CI unaffected | Anyone runs the bare target outside CI | each repository |
| Local Evidence Selection names both controls and the reason prefix | An agent chooses verification | `testing-strategy` |

The hook denies rather than advises, because a PreToolUse advisory reaches the model next to the tool result, after the run. The rule has exceptions, so the deny names them and the agent states one by prefixing `CCL_BROAD_TEST_REASON=user-request|ci-failure|repo-wide|repo-required`. That prefix is the agent's own claim and stays visible in the transcript. The hook is a decision point, not an authority boundary.

## Predicate

A runner in command position (`make`, `npm`/`pnpm`/`yarn`/`bun`, `pytest`, `playwright test`, `node --test`, `go test`), with an entry that names the whole suite: bare `test`, `test:all`/`test:full`, or a name carrying `integration`, `scenario`, `e2e`, `chaos` or `acceptance`. For `go test`, the package pattern `./...` or a slow-lane path.

Anything that selects passes: a test-name flag, a `*RUN=` or `FULL=` variable, a named test file or directory, a read-only flag, `make -n`, or a valid reason prefix. Repository lanes such as `make check` and named subsets such as `test:unit` never match; the repository chose them.

There is no shell parser. Unhandled spellings fall on the quiet side, as `remind-unverified-cli-flag.sh` records for the same reason. A missing `jq` or an internal failure allows the command.

## Rejected

- Advisory only: arrives after the run.
- Per-repository gates alone: the waste is spread over many repositories and stacks, and each would need its own gate before it helped.
- Matching every unselected `npm test`-style lane including named subsets: lane names belong to each repository, and the deny cost would fall on lanes repositories already chose as their local gate.

## Verification

- `bash hooks/test_guard_broad_local_test.sh`: deny, allow, near-miss, exception, read-only, tool-scope and fail-open rows.
- Mutation walk and transcript replay: `evidence/validation.md`.
