# Close stdout after env in the closed-stdout test

`code-review-regressions-1` fails on the `ubuntu-26.04` runner image
(`ubuntu-latest` moved from 24.04): "closed stdout cannot strand an
unreported diagnostic child" in `test_opencode_review_retry.sh`. Main's own
code fails the same way, so every pull request is blocked by it.

## Charter

| Field | Decision |
| --- | --- |
| Purpose | Make the closed-stdout case hand the OpenCode review wrapper a stdout that is really closed, on every runner image, and fail loudly when it is not. |
| Scope | The closed-stdout case in `skills/code-review/scripts/test_opencode_review_retry.sh`. The wrapper is unchanged. Pinning the runner image is out of scope. Other suites that close a stream before `env` are checked as siblings. No iterative-program watermark applies. |
| Depth | Generator/tooling change. |
| Result classification | Failure/correction: a required CI lane is red on the current runner image, reproduced on a control branch with main's code. |
| Matching analysis | Diagnosis below; prevention is a launcher that closes the stream after `env`, plus a precondition assertion that the launched process sees it closed. |
| Failure boundary | The wrapper's behaviour and the case's assertion stay as they are; only how the case starts the wrapper changes. |
| Lifecycle impact | Testing (suite) and CI health. No product, implementation, release-process or onboarding change. |
| Evidence plan | CI logs of the failing job on PRs #195, #196 (main control) and the diagnostic runs on #197 and #198; Rust standard library startup code (primary source); a local emulation of that startup behaviour. Produced artifacts: the diagnostic runs' logs, read above. |
| Completion standard | Local RED with the emulated env and GREEN after, a mutation that removes the close, `make test`, review and challenge, the required lane green on the pull request. |

Artifact classification: `test harness`; risk route: `shared-gate`.
Owners: `defect-diagnosis` (cause and regression), `testing-strategy`
(suite), `skill-extraction-workflow` (shared script change).

## Diagnosis

Confirmed on `ubuntu-26.04` (uutils coreutils 0.10.0, `env` at
`/usr/lib/cargo/bin/coreutils/env`), three runs each on #198:

| Launch | fd 1 seen by the wrapper | Diagnostic kept |
| --- | --- | --- |
| `env ... bash wrapper >&-` (the case as written) | `/dev/null` | 3 of 3 |
| `bash wrapper >&-` without `env` | closed | 0 of 3 |

Cause: Rust's standard library reopens a closed standard stream on
`/dev/null` at process start (`sanitize_standard_fds` in
`library/std/src/sys/pal/unix/mod.rs`). uutils `env` is a Rust program, so
the closed stdout reaches the wrapper as an open `/dev/null`; the final write
succeeds, the diagnostic is reported and kept, and the case fails. GNU `env`
on the previous image passed the closed descriptor through.

Rejected hypothesis: an earlier round read the trace as fd 1 being reused by
an open inside the wrapper and changed the wrapper
(`specs/closed-stdout-delivery/plan.md`). That reuse was never observed and
the #198 comparison contradicts it. The change had reached the pull request
branch; this round reverts it and supersedes its register row.

Open observation: one diagnostic run on #197 passed the case. It is not
explained; it does not change the deterministic #198 result.

## Design

`launch_with_closed_stdout` runs `env` with stdout open and closes fd 1 in
the bash that then execs the command, so no program sits between the close
and the exec. A first case launches a probe through the same function and
asserts the probe saw fd 1 closed, so a future launcher or image that
reopens the stream fails that precondition instead of the wrapper case.

Security four questions: no caller-controlled input; the change is test-only.

## Target-output map

| owner | direction | status | changed file or reason |
| --- | --- | --- | --- |
| code-review test suite | executor | updated | `skills/code-review/scripts/test_opencode_review_retry.sh` |
| code-review OpenCode wrapper | upstream | updated | the withdrawn round's change is reverted to the `main` version, which behaves correctly once it receives a closed stdout |
| other suites closing a stream before `env` | sibling | checked | inventory in evidence |
| testing-strategy | coordinator | unchanged | no layer policy change |
| platform-release-engineering | downstream | unchanged | runner image pinning not chosen |

## Acceptance

| ID | Scenario | Expected after | Baseline |
| --- | --- | --- | --- |
| L1 | launcher probe, any env | probe sees fd 1 closed | case started with `/dev/null` under a Rust env |
| L2 | closed-stdout case, Rust-like env | pass | fail |
| L3 | closed-stdout case, plain env | pass | pass |
